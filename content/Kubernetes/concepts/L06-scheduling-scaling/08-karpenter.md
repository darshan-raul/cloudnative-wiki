# Karpenter

*"https://karpenter.sh/"*

Karpenter is a **node provisioner** that watches unschedulable Pods and launches **just-in-time, right-sized nodes** in seconds. It replaces the older Cluster Autoscaler model (node groups + min/max) with a declarative, Pod-driven approach. Karpenter picks the instance type, AZ, capacity type (on-demand vs spot), and operating system based on what the Pod needs, then provisions the node in ~30-60 seconds.

### Table of Contents

1. [What Karpenter Solves](#1-what-karpenter-solves)
2. [Karpenter vs Cluster Autoscaler](#2-karpenter-vs-cluster-autoscaler)
3. [Architecture and Components](#3-architecture-and-components)
4. [NodePool — The Core Resource](#4-nodepool--the-core-resource)
5. [NodeClass — The Cloud-Specific Layer](#5-nodeclass--the-cloud-specific-layer)
6. [Requirements, Limits, and Disruption](#6-requirements-limits-and-disruption)
7. [Consolidation and Bin-Packing](#7-consolidation-and-bin-packing)
8. [Spot, On-Demand, and Capacity Diversification](#8-spot-on-demand-and-capacity-diversification)
9. [Scheduling Integration (Taints, Topology)](#9-scheduling-integration-taints-topology)
10. [Interruption Handling (Spot, Rebalance Recommendations)](#10-interruption-handling-spot-rebalance-recommendations)
11. [Multi-Region and Multi-Cluster](#11-multi-region-and-multi-cluster)
12. [Migration from Cluster Autoscaler](#12-migration-from-cluster-autoscaler)
13. [Operations and Debugging](#13-operations-and-debugging)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)

---

## 1. What Karpenter Solves

Cluster Autoscaler has a model: "I have N node groups, each with min/max sizes and an instance type. When Pods are unschedulable, add a node to one of the groups." This works but has real limits:

* **You have to predefine instance types** in node groups. New instance types aren't auto-discovered.
* **Bin-packing is poor.** CA picks a node group, adds a node of that type, even if a different type would be 30% cheaper.
* **Cold start is 2-3 minutes.** The ASG / cloud provider has to launch, the kubelet has to register, the CNI has to set up networking.
* **Node group proliferation.** Heterogeneous workloads (GPU + CPU + ARM) require many node groups.
* **Consolidation is weak.** CA removes underutilized nodes slowly, conservatively, with PDBs in the way.

Karpenter's model is different:

```
Cluster Autoscaler:                         Karpenter:
                                            
"Add a node to a group"                     "I'll figure out what node to run"
                                            
I have:                                    I see:
- 3 node groups, min=2, max=20 each         - 1 Pending Pod
- each is m5.large                          - Pod wants 1.5 CPU, 2 GB memory
- 30 unschedulable Pods                     - Pod tolerates a taint
                                            
I do:                                      I do:
- pick the cheapest group that fits        - launch the cheapest instance that fits
- add a node                               - launch in 30-60 seconds
- schedule 5-10 Pods on it (limited)       - pack as many Pods as possible
                                            - consolidate when utilization drops
```

**Karpenter is dramatically faster and more efficient.** EKS now recommends it for new clusters.

## 2. Karpenter vs Cluster Autoscaler

| | Karpenter | Cluster Autoscaler |
|---|---|---|
| **Model** | "Launch the right instance" | "Scale node groups" |
| **Cold start** | 30-60s | 2-3 min |
| **Instance selection** | Dynamic, based on Pod requirements | Predefined in node groups |
| **Bin-packing** | Excellent (any instance type) | Limited to node group types |
| **Consolidation** | Built-in, aggressive | Conservative, slow |
| **Spot support** | Native, multi-instance-type | Per-node-group |
| **Multi-AZ** | Automatic | Per-node-group |
| **ARM / GPU / special** | Just works (constraints via requirements) | Separate node groups |
| **Cluster age** | Newer (2021+), rapidly evolving | Mature, well-known |
| **Cloud support** | AWS first; GKE + Azure in progress | All clouds |
| **Heterogeneous workloads** | Single NodePool | Many node groups |

**Recommendation:** new clusters should use Karpenter. Existing clusters on CA can migrate. The two are **mutually exclusive** — don't run both.

## 3. Architecture and Components

Karpenter has two main components, plus cloud-specific providers:

```
┌────────────────────────────────────────────────────────────┐
│  karpenter controller (single Deployment)                  │
│                                                            │
│  - Watches Pods, NodePools, NodeClasses                    │
│  - Decides when to launch / terminate nodes                │
│  - Calls cloud provider (EC2, GCE, etc.) to launch         │
│  - Calls the apiserver to create the Node object           │
└────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────┐
│  karpenter webhook (Deployment, optional)                  │
│  - Validates NodePool and NodeClass on creation            │
│  - Defaults fields                                          │
└────────────────────────────────────────────────────────────┘
        ▲
        │  Watches
        │
┌───────┴────────────────────────────────────────────────────┐
│  Pods (when Pending)                                        │
│  NodePools (CRD, declarative intent)                       │
│  NodeClasses (CRD, cloud-specific config)                  │
└────────────────────────────────────────────────────────────┘
```

Karpenter runs **inside** the cluster as a Deployment. It uses the cluster's apiserver and its own IAM role to launch cloud nodes. **There's no external control plane** — Karpenter is just another k8s workload.

### 3.1 The NodePool

A NodePool declares **how** Karpenter should provision nodes for a class of Pods:

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
      - key: kubernetes.io/arch
        operator: In
        values: [amd64, arm64]
      - key: kubernetes.io/os
        operator: In
        values: [linux]
      - key: karpenter.sh/capacity-type
        operator: In
        values: [on-demand, spot]
      - key: topology.kubernetes.io/zone
        operator: In
        values: [us-east-1a, us-east-1b, us-east-1c]
      - key: karpenter.k8s.aws/instance-family
        operator: In
        values: [m5, m6i, c5, c6i, r5, r6i]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
  limits:
    cpu: "200"
    memory: 800Gi
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
  weight: 100
```

This says: "For Pods matching this NodePool's `template.spec.taints` and labels, launch nodes that are amd64/arm64, linux, on-demand/spot, in those zones, in those instance families, up to 200 cores total. Use the `default` EC2NodeClass for cloud-specific config. Consolidate when underutilized, expire after 30 days."

### 3.2 The NodeClass

A NodeClass is **cloud-specific config** — subnets, security groups, AMI, user data, etc.

```yaml
# AWS example
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2              # Amazon Linux 2; Bottlerocket, Ubuntu also options
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: my-cluster
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: my-cluster
  instanceProfile: KarpenterNodeInstanceProfile
  blockDeviceMappings:
  - deviceName: /dev/xvda
    ebs:
      volumeSize: 100Gi
      volumeType: gp3
      deleteOnTermination: true
```

For other clouds: `GCENodeClass`, `AKSNodeClass`. The cloud-specific provider handles the details.

## 4. NodePool — The Core Resource

### 4.1 Pod selection: how Karpenter picks which NodePool to use

Karpenter matches Pods to NodePools by:

* **`spec.template.spec.taints`** — the Pod must tolerate them.
* **`spec.template.metadata.labels`** — the NodePool can require specific labels on the Pod (via `nodeSelector`).
* **`spec.weight`** — when multiple NodePools match, the higher weight wins.

A common pattern:

```yaml
# NodePool for general workloads
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata: { name: default }
spec:
  weight: 100
  template:
    spec:
      # no taints — any Pod can land here
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: [on-demand, spot]
      - key: karpenter.k8s.aws/instance-family
        operator: In
        values: [m5, m6i, c5, c6i, r5, r6i]
---
# NodePool for GPU workloads (tainted, only GPU Pods tolerate)
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata: { name: gpu }
spec:
  weight: 50
  template:
    spec:
      taints:
      - key: nvidia.com/gpu
        value: present
        effect: NoSchedule
      requirements:
      - key: karpenter.k8s.aws/instance-family
        operator: In
        values: [p3, p4, g4dn, g5]
```

The GPU Pod has a `tolerations: [{ key: nvidia.com/gpu, operator: Exists }]`. Karpenter sees the toleration, matches the Pod to the GPU NodePool, launches a `p3` or `g5` instance.

### 4.2 Requirements — what's allowed

`requirements` constrain **what instance types** Karpenter can launch. Each requirement is a label selector on the eventual Node.

| Well-known label | What it matches |
|---|---|
| `kubernetes.io/arch` | `amd64`, `arm64` |
| `kubernetes.io/os` | `linux`, `windows` |
| `karpenter.sh/capacity-type` | `on-demand`, `spot` |
| `topology.kubernetes.io/zone` | AZ name |
| `topology.kubernetes.io/region` | Region |
| `karpenter.k8s.aws/instance-family` | `m5`, `c5`, `p3`, etc. |
| `karpenter.k8s.aws/instance-size` | `large`, `xlarge`, etc. |
| `karpenter.k8s.aws/instance-cpu` | `4`, `8`, `16`, etc. |
| `karpenter.k8s.aws/instance-memory` | memory in Mi |

A Pod's `nodeSelector` and `nodeAffinity` are also matched against the NodePool's requirements. If a Pod says "I want `instance-family: p3`", Karpenter launches a `p3` for it.

### 4.3 Limits — preventing runaway cost

```yaml
spec:
  limits:
    cpu: "200"
    memory: 800Gi
```

Karpenter won't launch nodes that would exceed these totals. **This is your cost-control safety net.** If a bug or burst tries to launch 1000 nodes, Karpenter caps at 200 cores / 800 GB.

**`limits` is per-NodePool.** You can have multiple NodePools with different limits:

```yaml
# default: up to 200 cores
# gpu: up to 32 cores
# batch: up to 500 cores (sized for batch workloads)
```

### 4.4 Weight — for ambiguous matches

When a Pod matches multiple NodePools, the higher weight wins. Ties are resolved by name (alphabetical).

```yaml
spec:
  weight: 100       # preferred
# vs
spec:
  weight: 50        # fallback
```

Use weight to express preference without forcing a hard selection.

## 5. NodeClass — The Cloud-Specific Layer

The NodeClass encapsulates the cloud-specific config that doesn't change per workload:

* **AMI / image** — the OS image for the node.
* **Subnets** — which subnets to launch in.
* **Security groups** — which SGs to attach.
* **IAM instance profile** — the AWS IAM role for the node.
* **Block device mappings** — EBS volume config (size, type, encryption).
* **User data** — bootstrap script (Karpenter fills in most of it).

```yaml
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: Bottlerocket              # or AL2, Ubuntu
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: my-cluster
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: my-cluster
  instanceProfile: KarpenterNodeInstanceProfile
  blockDeviceMappings:
  - deviceName: /dev/xvda
    ebs:
      volumeSize: 100Gi
      volumeType: gp3
      iops: 3000
      throughput: 125
      encrypted: true
      deleteOnTermination: true
  userData: |
    # extra bootstrap if needed
```

**Tagging the subnets and security groups** with `karpenter.sh/discovery: <cluster-name>` is the standard pattern. Karpenter finds them automatically.

## 6. Requirements, Limits, and Disruption

### 6.1 The full NodePool spec

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels:
        workload-type: general
    spec:
      requirements:
      - key: kubernetes.io/arch
        operator: In
        values: [amd64, arm64]
      - key: karpenter.sh/capacity-type
        operator: In
        values: [on-demand, spot]
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values: [c, m, r]
      - key: karpenter.k8s.aws/instance-generation
        operator: Gt
        values: ["4"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
      taints:
      - key: dedicated
        value: general
        effect: NoSchedule
  limits:
    cpu: "200"
    memory: 800Gi
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
    budgets:
    - nodes: "10%"
    - nodes: "5"
      reasons: [Underutilized]
      schedule: "0 9 * * mon-fri"   # weekday mornings
      duration: 8h
  weight: 100
```

### 6.2 Disruption

Karpenter actively **disrupts** nodes to maintain efficiency. Three mechanisms:

**Consolidation:** when a node is underutilized, Karpenter either:
- **Deletes the node** if its Pods can be rescheduled elsewhere.
- **Replaces the node** with a different, more efficient instance type for the same Pods.

**Expiration:** `expireAfter: 720h` means nodes are terminated and replaced after 30 days. This forces a refresh — useful for security patches, instance type migrations.

**Drift:** when a NodeClass changes (e.g. new AMI), Karpenter replaces nodes with the old config. The replacement is gradual (respects disruption budgets).

### 6.3 Disruption budgets

```yaml
spec:
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
    budgets:
    - nodes: "10%"                # at most 10% of nodes per budget period
    - nodes: "5"
      reasons: [Underutilized]    # only for underutilized, not for other reasons
      schedule: "0 9 * * mon-fri"
      duration: 8h
```

Disruption budgets **rate-limit** Karpenter's termination actions. Without them, a fast-changing workload could trigger waves of node replacements.

The `schedule` and `duration` fields let you say "only do disruptive maintenance during business hours" or "only on weekends".

## 7. Consolidation and Bin-Packing

Karpenter's killer feature. The algorithm:

1. Every few minutes, look at each node's utilization.
2. If a node is underutilized (e.g. < 50% CPU and memory), see if its Pods could fit on fewer / smaller / cheaper nodes.
3. If yes, **replace** the node. The old node is drained (respects PDBs) and terminated. A new node is launched for the Pods.
4. If the Pods are fine where they are, leave them.

The result: cluster capacity tracks demand. You don't pay for empty nodes.

### 7.1 Consolidation policies

| Policy | Behavior |
|---|---|
| `WhenUnderutilized` (default) | Only consolidate when there's clear underutilization |
| `Always` | Aggressively consolidate on every evaluation |

`WhenUnderutilized` is conservative — it doesn't churn. `Always` is aggressive — it tries to remove every node that could be replaced.

### 7.2 Single-node consolidation

A node with one Pod is **not** consolidated — Karpenter won't merge it onto another node. **A node must have 2+ Pods to be a consolidation candidate.** This prevents thrashing on small workloads.

### 7.3 When consolidation is disabled

Set `consolidationPolicy: WhenUnderutilized` but **disable** consolidation entirely with `consolidateAfter: Never` (k8s 1.31+):

```yaml
spec:
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: Never
```

Wait — that disables it. The correct way to disable is:

```yaml
spec:
  disruption:
    consolidationPolicy: WhenUnderutilized
    # or set expireAfter: Never to disable expiration
    expireAfter: Never
```

`consolidationPolicy` must be set; `expireAfter: Never` disables only the time-based expiration.

## 8. Spot, On-Demand, and Capacity Diversification

Karpenter's Spot support is **much better than CA's**:

* **Multi-instance-type** — Karpenter can pick any instance type in a family, not just one. Spot interruptions are absorbed by the diversity.
* **Capacity-optimized** allocation strategy.
* **Interruption handling** — Karpenter is notified of spot interruptions via SQS / EventBridge, and proactively drains the node.

```yaml
spec:
  template:
    spec:
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: [spot]                  # or [on-demand, spot] for mixed
      - key: karpenter.k8s.aws/instance-family
        operator: In
        values: [m5, m5a, m5n, m6i, m6a, m7i, c5, c5a, c6i, c6a, r5, r6i]
```

With 11 instance families, Spot interruption on one family doesn't matter — the others have capacity.

### 8.1 Spot-to-on-demand fallback

Karpenter can **fall back to on-demand** when Spot capacity is unavailable:

```yaml
spec:
  disruption:
    consolidationPolicy: WhenUnderutilized
  template:
    spec:
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: [spot, on-demand]    # try spot first, fall back to on-demand
```

In practice, this means: a Pod that wants 1 core lands on a `m5.large spot` if available, else a `m5.large on-demand`. Karpenter doesn't have a "prefer spot" knob; it picks the cheapest available.

## 9. Scheduling Integration (Taints, Topology)

Karpenter respects **all the k8s scheduling primitives**. A Pod that has:

* `nodeSelector: disktype=ssd` — Karpenter launches a node with that label.
* `nodeAffinity: { zone: [us-east-1a, us-east-1b] }` — Karpenter picks a node in one of those zones.
* `tolerations: [{ key: dedicated, operator: Exists }]` — Karpenter matches the Pod to a NodePool with that taint.
* `topologySpreadConstraints: [{ maxSkew: 1, topologyKey: zone }]` — Karpenter launches nodes in different zones to spread the Pods.

The `topology.kubernetes.io/zone` requirement is a Karpenter `requirements` field. If a Pod wants zone X and the NodePool allows zones X, Y, Z, Karpenter launches in X.

### 9.1 The "Karpenter launched the wrong instance type" case

A Pod's `nodeSelector` or `affinity` rules constrain the node. If they conflict with the NodePool's `requirements`, the Pod is unschedulable.

```yaml
# Pod asks for: instance-family: p3 (GPU)
spec:
  nodeSelector:
    karpenter.k8s.aws/instance-family: p3
# NodePool allows: instance-family: [m5, c5, r5]
# Result: Pod is Pending, no node is launched
```

Karpenter logs the reason. Check with `kubectl describe pod`.

## 10. Interruption Handling (Spot, Rebalance Recommendations)

Karpenter has a **SQS queue** that AWS sends spot interruption events to. When a node is interrupted:

1. Karpenter receives the SQS message (2 minutes before the spot instance is reclaimed).
2. Karpenter cordons the node.
3. Karpenter evicts the Pods (respects terminationGracePeriodSeconds).
4. Karpenter terminates the instance.
5. Karpenter launches a new node for the evicted Pods.

The total time from "interruption notice" to "Pod back on a new node" is **typically 3-5 minutes** (2 min notice + 30s drain + 30-60s new node launch).

This is **much better than** CA, which only learns about spot interruptions when the instance is gone.

### 10.1 The interruption queue

The SQS queue must be configured when installing Karpenter. The Karpenter controller's IAM role has permission to read from it; the cluster's node IAM role has permission to send to it.

```yaml
# karpenter-values.yaml
settings:
  interruptionQueue: my-cluster-karpenter
  clusterName: my-cluster
```

## 11. Multi-Region and Multi-Cluster

Karpenter is **single-cluster**. Multi-cluster setups run one Karpenter per cluster, each with its own IAM role and NodePool / NodeClass.

Cross-cluster is harder. Some patterns:

* **Cluster federation** — KubeFed, but rare in production.
* **Cluster API** — provisions clusters, not individual nodes.
* **Multi-cluster ingress** — Route53, Global Accelerator, etc.
* **Cross-cluster service mesh** — Istio multi-primary, Linkerd multi-cluster.

These are all beyond Karpenter's scope. Karpenter manages nodes within one cluster.

## 12. Migration from Cluster Autoscaler

The standard migration:

1. **Install Karpenter** in the cluster. Don't disable CA yet.
2. **Create a NodePool** that mirrors the existing CA node groups.
3. **Test on non-prod workloads** — let Karpenter handle a few node creations.
4. **Cordon off CA's node groups.** Stop scaling them.
5. **Disable CA.** Delete the CA Deployment.
6. **Let Karpenter consolidate** — it'll replace the old CA-launched nodes with Karpenter-launched ones.

**Don't run both CA and Karpenter at the same time.** They race for the same Pending Pods and create duplicate nodes.

The EKS migration guide has a detailed step-by-step.

## 13. Operations and Debugging

### 13.1 Common commands

```bash
# list NodePools
kubectl get nodepool -A
kubectl get nodepool default -o yaml

# list NodeClasses
kubectl get ec2nodeclass -A   # or gcnodeclass, aksnodeclass
kubectl get ec2nodeclass default -o yaml

# check the controller
kubectl -n kube-system get pods -l app.kubernetes.io/name=karpenter
kubectl -n kube-system logs -l app.kubernetes.io/name=karpenter --tail=100

# check NodeClaims (provisional nodes)
kubectl get nodeclaim -A
# NodeClaim is a Karpenter-managed node, before the Node object is created
```

### 13.2 The "Karpenter didn't launch a node" checklist

```bash
# 1. Is there a Pending Pod that matches a NodePool?
kubectl get pods -A -o wide | grep Pending

# 2. Does the Pod tolerate the NodePool's taints?
kubectl get pod <pod> -o jsonpath='{.spec.tolerations}'
kubectl get nodepool <name> -o jsonpath='{.spec.template.spec.taints}'

# 3. Are the requirements compatible?
kubectl get nodepool <name> -o jsonpath='{.spec.template.spec.requirements}'
kubectl get pod <pod> -o jsonpath='{.spec.nodeSelector}{.spec.affinity}'

# 4. Are the NodePool limits hit?
kubectl describe nodepool <name>
# look at Status.Conditions

# 5. Are the subnets / SGs tagged correctly?
aws ec2 describe-subnets --filters "Name=tag:karpenter.sh/discovery,Values=<cluster>"

# 6. Is the Karpenter IAM role correct?
# check the controller logs
```

### 13.3 The "Karpenter terminated a node I didn't expect" case

Karpenter terminates nodes for:

* **Consolidation** — the node is underutilized.
* **Expiration** — `expireAfter` is reached.
* **Drift** — the NodeClass changed (new AMI, etc.).
* **Interruption** — spot reclaim, health event, etc.
* **Manual** — `kubectl delete node` or via the Karpenter CLI.

Check the NodeClaim's `status.conditions` and the controller logs.

## 14. Gotchas and Common Mistakes

### 14.1 The 25+ common mistakes

1. **Running Karpenter and Cluster Autoscaler at the same time.** They race. Pick one.

2. **NodePool's `requirements` is too restrictive.** A Pod that asks for `instance-family: p3` won't fit in a NodePool that only allows `m5, c5, r5`.

3. **Forgetting to set `expireAfter`.** Without it, nodes run forever. Security patches, AMI updates — none of them apply.

4. **Setting `consolidationPolicy: Always` on a busy workload.** Causes constant node churn, evicting Pods just to put them back.

5. **The interruption queue isn't set up.** Karpenter can't handle spot interruptions gracefully without the SQS queue.

6. **The Karpenter IAM role doesn't have the right permissions.** It needs `ec2:RunInstances`, `ec2:DescribeInstances`, `ec2:TerminateInstances`, `iam:PassRole`, etc.

7. **Subnets aren't tagged with `karpenter.sh/discovery`.** Karpenter can't find them. The controller logs say "no subnets match".

8. **The cluster's VPC CNI limits.** Karpenter can launch nodes faster than the VPC CNI can assign IPs. Watch for `insufficient IP addresses` errors.

9. **A node with one Pod is never consolidated.** A 1-Pod Deployment is "stable" — Karpenter won't try to merge it.

10. **The NodePool's `limits.cpu` includes Pods that are Pending.** A Pod with `requests.cpu: 100` counts against the limit even if no node is running it.

11. **Karpenter doesn't manage `kube-system` Pods (or it does, depending on settings).** The default Karpenter NodePool has taints / labels that don't match `kube-system`. System Pods go to manually-created node groups, not Karpenter.

12. **Spot + `consolidationPolicy: Always` + PDBs = thrashing.** Karpenter wants to drain, PDB blocks it, Spot interrupts, all hell breaks loose.

13. **The `topology.kubernetes.io/zone` requirement doesn't combine with Pod's `topologySpreadConstraints` automatically.** If a Pod wants to spread across 3 zones and the NodePool allows only 1 zone, the Pod won't spread.

14. **Karpenter's launch latency is 30-60s but can spike to 5+ min** during spot capacity crunches. Plan for cold-start time.

15. **Karpenter doesn't respect `nodeSelector` terms added after the NodeClaim is created.** A NodeClaim's `requirements` are snapshotted.

16. **Karpenter v1beta1 vs v1alpha1 API.** Older clusters may have v1alpha1 NodePools / NodeClaims. Migration is required.

17. **The `weight` field is not a priority class.** Two NodePools with the same weight for the same Pod are resolved by name.

18. **Karpenter doesn't add new node labels automatically.** If you want nodes labeled with a custom label, set it in the NodePool's `template.metadata.labels`.

19. **Karpenter doesn't manage kubelet's `--max-pods` or `--system-reserved`.** These come from the AMI / user data. Karpenter's launcher is configured at the cluster level.

20. **A new Karpenter version can change defaults.** Pin your version and read the upgrade notes.

21. **Karpenter doesn't manage EFA devices, GPUs by itself.** The NodeClass / AMI / device plugin handles those. Karpenter just launches the right instance type.

22. **Karpenter terminates nodes one at a time** (respecting disruption budgets). Mass-cordoning all nodes for maintenance doesn't make Karpenter terminate them all at once.

23. **The NodePool's `disruption.budgets` is a rate limit per minute.** A budget of `nodes: "10%"` allows 10% of nodes per minute (or per the schedule's duration, depending on the form).

24. **Karpenter doesn't handle Pods that were scheduled before Karpenter was installed.** They're on existing nodes, Karpenter doesn't know to consolidate them.

25. **Karpenter's status update lags.** `kubectl describe nodepool` may show older state than reality. Wait 30s after a change.

26. **Karpenter doesn't support Windows nodes** in all configurations. Check the version's release notes.

27. **The Karpenter controller runs in a single namespace (usually `kube-system`).** Don't put NodePools elsewhere unless you know the multi-tenancy story.

28. **Karpenter v1 (stable) has different CRD names than v1beta1.** `NodePool` is stable in v1, `NodeClaim` was renamed from `NodeClaim` to `NodePool` in some versions. Check the docs.

29. **Karpenter doesn't add itself to the apiserver's `--enable-admission-plugins`.** The admission plugin is a webhook registered at install time.

30. **Karpenter's metrics are Prometheus-formatted on `:8000` of the controller Pod.** Scrape them with your monitoring stack.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/09-cluster-autoscaler|Cluster Autoscaler]] — the predecessor
* [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling|Scaling]] — L06 overview
* [[Kubernetes/eks/compute/karpenter|Karpenter on EKS]] — EKS-specific install / IAM
* [[Kubernetes/eks/compute/managed-node-groups/cluster-autoscaler|Cluster Autoscaler on EKS]] — EKS-specific install

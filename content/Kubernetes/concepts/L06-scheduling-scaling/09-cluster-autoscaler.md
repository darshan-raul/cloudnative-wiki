# Cluster Autoscaler (CA)

*"https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler"*

The Cluster Autoscaler (CA) **adjusts the size of a cluster's node groups** based on the number of unschedulable Pods and the utilization of existing nodes. It's the **older, more conservative** alternative to Karpenter — predefines node groups, scales each between min and max, and works on every cloud.

### Table of Contents

1. [What CA Solves](#1-what-ca-solves)
2. [CA vs Karpenter](#2-ca-vs-karpenter)
3. [Architecture](#3-architecture)
4. [Node Groups and ASGs](#4-node-groups-and-asgs)
5. [The Scale-Up Logic](#5-the-scale-up-logic)
6. [The Scale-Down Logic](#6-the-scale-down-logic)
7. [Configuration](#7-configuration)
8. [Cloud-Specific Integration](#8-cloud-specific-integration)
9. [Spot, GPU, and Heterogeneous Workloads](#9-spot-gpu-and-heterogeneous-workloads)
10. [Migration to Karpenter](#10-migration-to-karpenter)
11. [Operations and Debugging](#11-operations-and-debugging)
12. [Gotchas and Common Mistakes](#12-gotchas-and-common-mistakes)

---

## 1. What CA Solves

When a Pod can't be scheduled because no node has enough resources, you need **more nodes**. CA watches for this state and adds nodes automatically.

When a node is **underutilized** and its Pods can fit on other nodes, you can **remove it** to save money. CA does this too.

```
Cluster Autoscaler (in cluster)
       │
       │  Watches
       ▼
   Pending Pods (unschedulable)
       │
       │  "I see 5 Pending Pods that don't fit on any current node"
       │  "I see that I can launch an m5.large via the node group"
       │
       │  Calls
       ▼
   Cloud Autoscaling API (ASG, MIG, VMSS)
       │
       │  "Add 1 m5.large to the node group"
       │
       │  New instance launches, joins cluster
       │  Pods get scheduled
```

CA is **mature, well-known, and works on every cloud**. It's not as fast or efficient as Karpenter, but it's the safe default for many setups.

## 2. CA vs Karpenter

See [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter|Karpenter]] for the full comparison. Quick summary:

| | CA | Karpenter |
|---|---|---|
| **Model** | Node groups with min/max | Pod-driven, dynamic instance selection |
| **Cold start** | 2-3 min | 30-60s |
| **Instance diversity** | Per node group | Across the whole NodePool |
| **Consolidation** | Conservative | Aggressive |
| **Cloud support** | All | AWS first; GKE, Azure in progress |
| **Recommendation** | Stable, mature | New clusters, dynamic workloads |

**Pick CA if:**

* You have a stable workload pattern and want predictable node group sizes.
* You're on a cloud where Karpenter isn't ready (e.g. on-prem, some clouds).
* You need mature, well-tested behavior.

**Pick Karpenter if:**

* You have heterogeneous workloads (different instance types needed).
* You want fast scale-up (30s vs 3 min).
* You're on AWS.

## 3. Architecture

CA runs as **a single Deployment** in the cluster (with leader election for HA):

```
┌────────────────────────────────────────────────────────────┐
│  cluster-autoscaler Deployment                            │
│                                                            │
│  - Leader-elected (1 active, 1+ standby)                  │
│  - Watches Pods, Nodes, node group sizes                   │
│  - Decides scale-up / scale-down                           │
│  - Calls cloud APIs (ASG, MIG, VMSS)                       │
└────────────────────────────────────────────────────────────┘
        ▲
        │  Reads cloud config from flags
        │
        ▼
   Cloud provider's autoscaling API
   - AWS: ASG (Auto Scaling Group)
   - GCP: MIG (Managed Instance Group)
   - Azure: VMSS (Virtual Machine Scale Set)
```

CA is a **single binary** (no operator, no CRDs, no webhooks). Config is via flags and a ConfigMap. State is in the apiserver and the cloud.

### 3.1 The CA image

CA is shipped as a container image. The cluster runs it as a Deployment with:

* **ServiceAccount** with permission to read Pods, Nodes, and update node group sizes.
* **IAM role** (cloud) with permission to call the autoscaling API.
* **ConfigMap** (optional) for some tunings.

## 4. Node Groups and ASGs

CA scales **node groups** (cloud concept) up and down. Each node group has a min, max, and the instance type.

### 4.1 AWS: Auto Scaling Group (ASG)

```hcl
resource "aws_autoscaling_group" "workers" {
  name                = "k8s-workers"
  min_size            = 2
  max_size            = 20
  desired_capacity    = 2
  vpc_zone_identifier = [var.subnet_a, var.subnet_b]
  
  launch_template {
    id      = aws_launch_template.workers.id
    version = "$Latest"
  }
  
  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
  # ...
}
```

The tags `k8s.io/cluster-autoscaler/<cluster-name>: owned` tell CA "this ASG is yours to scale."

### 4.2 GCP: Managed Instance Group (MIG)

```hcl
resource "google_container_node_pool" "workers" {
  name       = "workers"
  cluster    = google_container_cluster.primary.name
  node_count = 1
  
  autoscaling {
    min_node_count = 1
    max_node_count = 20
  }
  
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
```

GKE's node pool is the MIG. CA scales it via the GKE API.

### 4.3 Azure: Virtual Machine Scale Set (VMSS)

```hcl
resource "azurerm_kubernetes_cluster_node_pool" "workers" {
  name                  = "workers"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D2s_v5"
  node_count            = 1
  
  auto_scaling_enabled = true
  min_count            = 1
  max_count            = 20
}
```

AKS's node pool is the VMSS. CA scales it.

### 4.4 The min/max pattern

A node group has `min`, `max`, and CA scales between them. The actual size is `desired_capacity` plus CA's adjustments.

```hcl
min_size = 2         # CA will never go below 2
max_size = 20        # CA will never go above 20
desired_capacity = 2 # initial size
```

**Min is a floor** — CA won't scale down below it. **Max is a ceiling** — CA won't scale up above it. **Both are operational levers you set deliberately.**

## 5. The Scale-Up Logic

CA scans for unschedulable Pods every `--scan-interval` (default 10s):

1. **Find unschedulable Pods.** Pods that have been Pending for at least `--max-node-provision-time` (default 15 min, but configurable).
2. **Simulate adding nodes from each node group.** For each group, assume one node is added; see how many Pods would be scheduled.
3. **Pick the best node group** based on the configured `expander`:
   * `least-waste` — minimizes wasted resources (default)
   * `priority` — uses priority list (from a ConfigMap)
   * `random` — random
   * `most-pods` — maximizes Pods scheduled
   * `price` — cheapest first (only on AWS)
   * `cheapest` — also cheapest
4. **Call the cloud API** to add the node.
5. **Wait for the node to join.** The kubelet registers, the CNI sets up networking.
6. **Pods get scheduled.**

The total time from "Pending Pod detected" to "Pod scheduled on a new node" is typically **2-3 minutes** (ASG launch + boot + kubelet registration + CNI setup).

### 5.1 The "Pending for 15 min" gotcha

By default, CA ignores Pods that have been Pending for less than `--max-node-provision-time` (default 15 min). This prevents thrashing on brief load spikes.

For latency-sensitive scaling, lower this:

```yaml
# cluster-autoscaler flags
- --max-node-provision-time=2m
```

Or set on a per-Pod basis with the `cluster-autoscaler.kubernetes.io/pod-scale-up-delay` annotation.

### 5.2 The "bin-packing is poor" issue

CA simulates adding one node of a known type. If your workloads are heterogeneous, you'll end up with:

* A `c5.4xlarge` node for the GPU workload (wasting 30 of 32 cores).
* An `m5.large` node for the small service.
* A separate `r5.2xlarge` node for the memory-hungry service.

Karpenter is better at this — it can pick any instance type for any Pod.

## 6. The Scale-Down Logic

CA scans for underutilized nodes every `--scan-interval`:

1. **Find nodes that are candidates for removal.** A node is a candidate if:
   * It has been running for at least `--scale-down-delay-after-add` (default 10 min).
   * It has been underutilized for at least `--scale-down-unneeded-time` (default 10 min).
   * All its Pods can be rescheduled on other nodes.
2. **Simulate removing the node.** Re-schedule each Pod on remaining nodes (using the scheduler's actual logic).
3. **If all Pods can be rescheduled**, drain and remove the node.

A node is "underutilized" if the sum of its Pods' `requests` is less than 50% of the node's capacity. This threshold is configurable with `--scale-down-utilization-threshold`.

### 6.1 The PDB interaction

CA respects **PodDisruptionBudgets**. If a node's Pods can't be rescheduled without violating a PDB, the node isn't a scale-down candidate.

```yaml
# PDB
spec:
  minAvailable: 2

# Deployment
spec:
  replicas: 2
```

With PDB: minAvailable=2 and replicas=2, CA can't drain the node (would violate the PDB). The node is never scaled down.

**This is a common CA deadlock** — a tight PDB + low replicas = stuck nodes.

### 6.2 The drain process

When CA decides to remove a node:

1. **Cordon** the node (no new Pods).
2. **Evict Pods** one at a time (respects PDBs).
3. **Wait for the Pods to terminate** (respects `terminationGracePeriodSeconds`).
4. **Call the cloud API** to remove the instance.

The total time is `--max-graceful-termination-sec` (default 600s = 10 min). If a Pod doesn't terminate in time, the termination is forced (Pod deleted, but the instance waits for `--max-graceful-termination-sec` total).

## 7. Configuration

CA's configuration is mostly **flags** to the Deployment:

```yaml
spec:
  containers:
  - name: cluster-autoscaler
    image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.30.0
    command:
    - ./cluster-autoscaler
    - --v=4
    - --cloud-provider=aws
    - --cluster-name=my-cluster
    - --region=us-east-1
    - --expander=least-waste
    - --balance-similar-node-groups=true
    - --max-node-provision-time=2m
    - --scale-down-delay-after-add=5m
    - --scale-down-unneeded-time=5m
    - --scale-down-utilization-threshold=0.5
    - --skip-nodes-with-local-storage=false
    - --skip-nodes-with-system-pods=true
```

### 7.1 Key flags

| Flag | Default | What it does |
|---|---|---|
| `--cloud-provider` | (required) | `aws`, `gce`, `azure`, `digitalocean`, etc. |
| `--cluster-name` | (required) | Used to find the right node groups |
| `--expander` | `least-waste` | How to choose which node group to scale up |
| `--max-node-provision-time` | `15m` | Ignore Pods Pending for less time |
| `--scale-down-delay-after-add` | `10m` | Don't scale down nodes younger than this |
| `--scale-down-unneeded-time` | `10m` | Don't scale down until node has been unneeded for this long |
| `--scale-down-utilization-threshold` | `0.5` | Below this fraction of capacity, the node is "unneeded" |
| `--balance-similar-node-groups` | `false` | Try to keep similar node groups balanced |
| `--skip-nodes-with-local-storage` | `false` | Skip nodes with emptyDir / hostPath (Pods can't be rescheduled) |
| `--skip-nodes-with-system-pods` | `true` | Skip nodes with kube-system Pods (don't drain control plane) |

### 7.2 The expander

The `expander` chooses **which node group to scale up** when there are multiple choices:

* `least-waste` (default) — minimizes wasted CPU/memory. **Best for cost.**
* `priority` — uses a ConfigMap with priorities.
* `random` — picks randomly.
* `most-pods` — picks the group that schedules the most Pods.
* `price` (AWS only) — picks the cheapest ASG.
* `cheapest` (AWS only) — also cheapest.

The `priority` expander needs a ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-priority-expander
  namespace: kube-system
data:
  priorities: |-
    10:
      - .*t2\.large.*
    50:
      - .*m5\..*
    90:
      - .*p3\..*        # GPU nodes last
```

Higher priority = scaled up first.

## 8. Cloud-Specific Integration

### 8.1 AWS

```bash
# IAM policy
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups"
      ],
      "Resource": "*"
    }
  ]
}
```

### 8.2 GCP

GKE has built-in CA support. The node pool is the MIG.

### 8.3 Azure

AKS has built-in CA support. The node pool is the VMSS.

## 9. Spot, GPU, and Heterogeneous Workloads

### 9.1 Spot

CA supports Spot via mixed instance policy in the ASG. The ASG has multiple instance types; CA picks the cheapest.

For interruption handling, you need a separate piece (Karpenter is better at this).

### 9.2 GPU

GPU workloads need a separate node group with the right instance type (e.g. `p3.2xlarge`). The Pod has a `nodeSelector` for `instance-type: p3.2xlarge` (or the equivalent), and CA scales that group.

```hcl
resource "aws_autoscaling_group" "gpu" {
  name = "k8s-gpu"
  # ...
  
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy = "lowest-price"
    }
  }
}
```

### 9.3 Heterogeneous workloads

The CA approach:

* One node group per workload type (small / medium / large / GPU / ARM).
* Each with its own min / max.
* Pods use `nodeSelector` or `nodeAffinity` to land on the right group.

This works but creates **node group sprawl**. Karpenter handles this with a single NodePool + requirements.

## 10. Migration to Karpenter

The standard migration:

1. **Install Karpenter** alongside CA. Don't disable CA yet.
2. **Create a NodePool** that mirrors one of the existing ASGs (instance types, AZs, capacity type).
3. **Cordon the existing ASG's nodes** so new Pods don't go there.
4. **Test** — let Karpenter handle new Pods, scale the old ASG down.
5. **Repeat** for other ASGs.
6. **Delete CA** once all ASGs are migrated.
7. **Let Karpenter consolidate** — old nodes get replaced with Karpenter-launched ones.

**Don't run both CA and Karpenter at full scale.** They race for the same Pods.

## 11. Operations and Debugging

### 11.1 Common commands

```bash
# check CA
kubectl -n kube-system get pods -l app=cluster-autoscaler
kubectl -n kube-system logs -l app=cluster-autoscaler --tail=100

# check node group status
kubectl -n kube-system get configmap cluster-autoscaler-status -o yaml
# shows "NodeGroupHealth" sections

# describe a node
kubectl describe node <name>
# look at "Annotations" for cluster-autoscaler.kubernetes.io/* fields
```

### 11.2 The "CA didn't scale up" checklist

```bash
# 1. Are there unschedulable Pods?
kubectl get pods -A | grep Pending

# 2. Is the Pod Pending for > max-node-provision-time?
# default is 15 min
kubectl get pod <pod> -o jsonpath='{.metadata.creationTimestamp}'

# 3. Can the Pod fit on any existing node?
kubectl describe pod <pod>
# look at events for "FailedScheduling"

# 4. Are the node groups' max sizes hit?
# check the cloud's autoscaling console

# 5. Is CA running and leader-elected?
kubectl -n kube-system logs -l app=cluster-autoscaler | grep -i leader

# 6. Are there enough IP addresses in the subnets?
# (for VPC CNI, the most common cause of stuck scale-up)
```

### 11.3 The "CA didn't scale down" checklist

```bash
# 1. Are the nodes too young?
# check --scale-down-delay-after-add (default 10m)

# 2. Are the Pods on the node reschedulable?
kubectl describe node <node>
# look at the Pods list

# 3. Are PDBs blocking?
kubectl get pdb -A
# a tight PDB can prevent scale-down

# 4. Is the node running system Pods?
# CA skips nodes with kube-system Pods (--skip-nodes-with-system-pods=true)
```

## 12. Gotchas and Common Mistakes

### 12.1 The 20+ common mistakes

1. **CA and Karpenter at the same time.** They race. Pick one.

2. **`--max-node-provision-time` is 15 min by default.** Pods Pending for less time are ignored. For latency-sensitive scaling, lower this.

3. **Tight PDBs + low replicas = CA stuck.** A PDB with `minAvailable: 2` and a Deployment with `replicas: 2` blocks scale-down forever.

4. **CA doesn't drain nodes with `hostPath` mounts by default.** Set `--skip-nodes-with-local-storage=false` if you want to drain them.

5. **CA doesn't drain nodes with `kube-system` Pods by default.** Set `--skip-nodes-with-system-pods=false` if you want to.

6. **CA scans every 10s but waits 10 min before scaling down.** A burst of low utilization doesn't trigger scale-down.

7. **CA's scale-down is "conservative".** It only removes nodes that are clearly underutilized, with headroom for the remaining Pods to grow.

8. **Mixed instance policy in the ASG vs single instance type.** Mixed gives more Spot diversification but CA's bin-packing is less predictable.

9. **CA doesn't handle the case where one ASG is in a different region.** All ASGs must be in the same region.

10. **The leader election means only one CA is active.** If the leader dies, a standby takes over after ~30s. No scale events during the transition.

11. **CA's metrics are limited.** It exports Prometheus metrics on `:8085`. Scrape them, but they're not as detailed as Karpenter's.

12. **CA's IAM role needs `autoscaling:SetDesiredCapacity` and `autoscaling:TerminateInstanceInAutoScalingGroup`.** Without these, CA logs "access denied" and does nothing.

13. **The cluster name flag must match the ASG's `k8s.io/cluster-autoscaler/<cluster-name>` tag.** Mismatch = CA ignores the ASG.

14. **CA doesn't manage system node groups (control plane, etcd).** It scales worker node groups only.

15. **A node in an ASG with `desired_capacity: 0` won't be managed by CA.** Set min to 1 or higher.

16. **CA's `--max-graceful-termination-sec` is the upper bound for drain time.** If a Pod has `terminationGracePeriodSeconds: 600`, CA waits up to 600s for the drain.

17. **CA's expander order is fixed per cluster.** You can't have different expanders for different node groups.

18. **CA is per-cluster, not multi-cluster.** Multi-cluster is out of scope.

19. **CA's logs are verbose at `--v=4`.** Use `--v=2` in production for less noise, and bump to 4-6 for debugging.

20. **CA doesn't have a CRD API.** All config is flags. Changing a setting requires a Deployment rollout.

21. **CA's `expander: priority` ConfigMap must be named `cluster-autoscaler-priority-expander` in `kube-system`.** Different name = ignored.

22. **CA doesn't auto-discover new ASGs.** If you add a new ASG, you don't need to restart CA — it picks them up on the next scan. But the tag must be set.

23. **The AWS EKS managed node groups have built-in CA integration.** The node group's min/max is what CA uses.

24. **CA's `--balance-similar-node-groups` distributes scale-up across similar groups.** Without it, one group gets all the scale-up until it hits max.

25. **CA's log format is a bit cryptic.** The lines are usually `scaleUp: group X, node Y, reason Z, ...`. Parse them carefully.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter|Karpenter]] — the modern alternative
* [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling|Scaling]] — L06 overview
* [[Kubernetes/eks/compute/managed-node-groups/cluster-autoscaler|Cluster Autoscaler on EKS]] — EKS-specific install
* [[Kubernetes/eks/compute/karpenter|Karpenter on EKS]] — EKS-specific install

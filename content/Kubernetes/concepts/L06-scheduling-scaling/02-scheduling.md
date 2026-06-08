# Scheduling (Taints, Tolerations, Affinity, Topology)

*"https://kubernetes.io/docs/concepts/scheduling-eviction/"*

The kube-scheduler decides **which node a Pod runs on**. By default, it picks anything with enough resources. When you need to constrain that — keep Pods off certain nodes, group them together, spread them out — you use the scheduling primitives below. The scheduler is a **plugin pipeline** (Filter → Score → Reserve → Permit → Bind) — see [[Kubernetes/concepts/L06-scheduling-scaling/12-scheduler-internals|Scheduler Internals]] for the framework details.

### Table of Contents

1. [The Scheduling Flow](#1-the-scheduling-flow)
2. [The Four Node Selection Primitives](#2-the-four-node-selection-primitives)
3. [nodeSelector (Simple)](#3-nodeselector-simple)
4. [Node Affinity in Depth](#4-node-affinity-in-depth)
5. [Pod Affinity and Anti-Affinity](#5-pod-affinity-and-anti-affinity)
6. [Taints and Tolerations in Depth](#6-taints-and-tolerations-in-depth)
7. [Topology Spread Constraints](#7-topology-spread-constraints)
8. [NodeName and NodeUnschedulable](#8-nodename-and-nodeunschedulable)
9. [Scheduling Profiles](#9-scheduling-profiles)
10. [The "IgnoredDuringExecution" Gotcha](#10-the-ignoredduringexecution-gotcha)
11. [The Scoring Algorithm and Weights](#11-the-scoring-algorithm-and-weights)
12. [The Filter Phase Internals](#12-the-filter-phase-internals)
13. [Common Use Cases](#13-common-use-cases)
14. [Operations and Debugging](#14-operations-and-debugging)
15. [Gotchas and Common Mistakes](#15-gotchas-and-common-mistakes)

---

## 1. The Scheduling Flow

For every Pod with `spec.nodeName` empty, the scheduler:

1. **Pre-filter** — runs pre-filter checks (parse affinity, count matching nodes, etc.). May short-circuit.
2. **Filter** — runs all filter plugins in parallel across nodes. Drops nodes that can't run the Pod.
3. **Pre-score** — preparation for scoring (e.g. compute topology domain counts).
4. **Score** — runs all score plugins. Each returns 0-100 per node.
5. **Normalize score** — combines scores, weighted sum.
6. **Reserve** — marks the chosen node's resources as reserved.
7. **Permit** — waits for external webhook approval (if any).
8. **Pre-bind** — runs pre-bind hooks (e.g. volume binding).
9. **Bind** — sets `spec.nodeName` on the Pod.

If the filter yields 0 nodes, the scheduler tries **preemption** (see [[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption|Priority & Preemption]]). If preemption fails, the Pod stays `Pending`.

The scheduler is **not a daemon**. It runs as a Deployment. Pods are evaluated when the scheduler's queue gets them, not on a timer.

## 2. The Four Node Selection Primitives

| Primitive | Direction | What's selected |
|---|---|---|
| `nodeSelector` | Hard, simple | Nodes matching labels |
| `nodeAffinity` | Hard or soft | Nodes matching labels (richer expressions) |
| `podAffinity` | Hard or soft | Nodes where matching Pods are running |
| `podAntiAffinity` | Hard or soft | Nodes where matching Pods are NOT running |

Plus **taints and tolerations** (repel Pods) and **topology spread constraints** (spread across domains).

The `nodeSelector` and `nodeAffinity` operate on **node labels**. The `podAffinity` and `podAntiAffinity` operate on **other Pods' labels**. Topology spread operates on **node labels and a label selector**.

## 3. nodeSelector (Simple)

```yaml
spec:
  nodeSelector:
    disktype: ssd
```

The Pod only schedules on nodes labeled `disktype=ssd`. Label nodes with:

```bash
kubectl label node <name> disktype=ssd
```

The `nodeSelector` is the simplest primitive. It's hard (no soft version) and supports only `key=value` matches.

### 3.1 Built-in node labels

Every node has well-known labels set by the kubelet / cloud provider:

| Label | Example value | Meaning |
|---|---|---|
| `kubernetes.io/hostname` | `ip-10-0-1-5.ec2.internal` | The node's hostname |
| `kubernetes.io/os` | `linux` / `windows` | The OS |
| `kubernetes.io/arch` | `amd64` / `arm64` | The architecture |
| `topology.kubernetes.io/zone` | `us-east-1a` | The AZ (cloud) |
| `topology.kubernetes.io/region` | `us-east-1` | The region (cloud) |
| `node.kubernetes.io/instance-type` | `m5.large` | The instance type (cloud) |
| `kubernetes.io/role` | `control-plane` / `worker` | Node role (if set) |

You can use any of these in a `nodeSelector`.

## 4. Node Affinity in Depth

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values: ["us-east-1a", "us-east-1b"]
        - matchExpressions:
          - key: kubernetes.io/arch
            operator: In
            values: ["arm64"]
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 80
        preference:
          matchExpressions:
          - key: gpu
            operator: Exists
      - weight: 20
        preference:
          matchExpressions:
          - key: disktype
            operator: In
            values: ["nvme"]
```

### 4.1 Required vs preferred

* **`requiredDuringSchedulingIgnoredDuringExecution`** — hard constraint. The Pod won't schedule if no node matches.
* **`preferredDuringSchedulingIgnoredDuringExecution`** — soft preference. The scheduler scores nodes higher for matching, but doesn't block non-matching.

You can have both. The Pod is scheduled only if required is satisfied, but is preferred to match the soft rules.

### 4.2 The terms semantics

`nodeSelectorTerms` is a **list of OR'd terms**. The Pod matches if **any** term matches.

```yaml
nodeSelectorTerms:
- matchExpressions: [...]     # term 1
- matchExpressions: [...]     # term 2
```

The Pod schedules on a node if term 1 matches OR term 2 matches. **Within a term, all expressions must match** (AND).

```
term 1: zone in [a, b] AND arch in [amd64]
term 2: arch in [arm64]
match: (zone=a AND arch=amd64) OR arch=arm64
```

### 4.3 Operators

| Operator | Matches when |
|---|---|
| `In` | Value is in the list |
| `NotIn` | Value is not in the list |
| `Exists` | Label key exists (any value) |
| `DoesNotExist` | Label key does not exist |
| `Gt` | Label value is greater than (numeric) |
| `Lt` | Label value is less than (numeric) |

`In` and `NotIn` take a list. `Exists` and `DoesNotExist` don't. `Gt` and `Lt` are for numeric labels (e.g. node CPU count, GPU memory).

### 4.4 Weights in preferred

`preferredDuringSchedulingIgnoredDuringExecution` items have a `weight` (1-100). The scheduler **sums** the weights of all matching preferred terms, then normalizes:

```
node scores by preference:
- matches preferred term 1 (weight 80) → +80
- matches preferred term 2 (weight 20) → +20
- matches none → +0

normalized score = (sum of matched weights) / (sum of all weights)
```

A node that matches all preferred terms scores 100. A node that matches half scores 50. The framework combines with other plugins' scores.

## 5. Pod Affinity and Anti-Affinity

### 5.1 Pod affinity

```yaml
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: cache
        topologyKey: kubernetes.io/hostname
        namespaces: ["prod", "staging"]    # optional
```

Schedule the Pod on a node where a Pod with `app=cache` is **already running**.

The `topologyKey` is the node label that defines the "domain". `kubernetes.io/hostname` means "the same node". `topology.kubernetes.io/zone` means "the same zone".

### 5.2 Pod anti-affinity

```yaml
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: web
        topologyKey: kubernetes.io/hostname
```

Schedule the Pod on a node where NO Pod with `app=web` is running. **Spreads replicas of the same Deployment across nodes.**

### 5.3 The performance cost

The scheduler **lists all Pods in the cluster** (or the specified namespaces) and checks the affinity label on each. This is O(n*m) — for every Pod, every node, every existing Pod. The scheduler caches Pod state, but the cache is invalidated frequently.

**At 1000+ nodes and 10,000+ Pods, the scheduler gets slow.** This is why `topologySpreadConstraints` is preferred for "spread evenly" use cases — it's much more efficient.

### 5.4 Soft pod affinity

```yaml
podAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 50
    podAffinityTerm:
      labelSelector:
        matchLabels:
          app: cache
      topologyKey: kubernetes.io/hostname
```

A soft version. The scheduler scores nodes higher if the affinity is satisfied, but doesn't block non-matching.

### 5.5 Namespaces

By default, pod affinity looks at Pods in the **same namespace**. To match across namespaces, list them:

```yaml
namespaces: ["prod", "staging"]
```

Or set `namespaces: []` for cluster-wide (k8s 1.21+).

## 6. Taints and Tolerations in Depth

A taint on a **node** says "repel Pods". A toleration on a **Pod** says "I can tolerate that taint". Pods are scheduled on tainted nodes only if they have a matching toleration.

### 6.1 Taint a node

```bash
kubectl taint nodes node1 special=true:NoSchedule
```

Three effects:

* **`NoSchedule`** — Pods without the toleration won't be scheduled. Existing Pods unaffected.
* **`PreferNoSchedule`** — soft version. The scheduler tries to avoid, but schedules if necessary.
* **`NoExecute`** — Pods without the toleration are **evicted**. Existing Pods are killed.

### 6.2 Tolerate the taint

```yaml
spec:
  tolerations:
  - key: special
    operator: Equal
    value: "true"
    effect: NoSchedule
```

The toleration matches the taint. The Pod is now allowed to be scheduled on the tainted node.

### 6.3 Toleration operators

| Operator | Matches when |
|---|---|
| `Equal` | `key`, `value`, and `effect` all match |
| `Exists` | `key` and `effect` match; `value` is not used |

`Exists` is more permissive — match the key and effect, regardless of value.

```yaml
# matches any taint with key=dedicated and effect=NoSchedule
- key: dedicated
  operator: Exists
  effect: NoSchedule
```

### 6.4 Toleration seconds (NoExecute only)

```yaml
tolerations:
- key: node.kubernetes.io/unreachable
  operator: Exists
  effect: NoExecute
  tolerationSeconds: 300    # tolerate the taint for 5 min before being evicted
```

Used for **node-level taints** that mark a node as NotReady / unreachable. The Pod tolerates for `tolerationSeconds`, then is evicted if the node is still in that state.

This is the standard pattern for giving Pods time to drain to a new node when their current node fails.

### 6.5 The default node taints

The kubelet / cloud-controller adds some taints automatically:

* `node.kubernetes.io/not-ready` — node is NotReady. Removed when ready.
* `node.kubernetes.io/unreachable` — node is unreachable. Removed when reachable.
* `node.kubernetes.io/unschedulable` — node is cordoned. Removed when uncordoned.
* `node.kubernetes.io/memory-pressure` — node is under memory pressure. (Actually, this is a node condition, not a taint — the scheduler considers it for filtering but doesn't add a taint.)
* `node.kubernetes.io/disk-pressure` — same.
* `node.kubernetes.io/pid-pressure` — same.

**The standard `tolerationSeconds: 300` on `not-ready` and `unreachable`** is what gives Pods time to be rescheduled before being killed. Without it, the Pods die as soon as the node goes NotReady.

### 6.6 Control plane taints

Control plane nodes have a taint to keep user Pods off them:

```bash
# added by kubeadm
node-role.kubernetes.io/control-plane:NoSchedule
# or in newer k8s:
node-role.kubernetes.io/control-plane=:NoSchedule
```

System Pods (kube-proxy, CNI, etc.) have a matching toleration. User Pods don't, so they're not scheduled on control plane nodes.

### 6.7 Taint-based dedicated nodes

```bash
# mark a node for GPU workloads
kubectl taint nodes gpu-1 nvidia.com/gpu=present:NoSchedule
```

GPU Pods tolerate:

```yaml
tolerations:
- key: nvidia.com/gpu
  operator: Exists
  effect: NoSchedule
```

Non-GPU Pods (without the toleration) are not scheduled on GPU nodes. **The GPU node is dedicated.**

## 7. Topology Spread Constraints

The modern way to spread Pods across failure domains.

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: web
```

* **`maxSkew: 1`** — at most 1 more Pod in any domain than the average.
* **`topologyKey`** — the node label that defines a domain.
* **`whenUnsatisfiable: DoNotSchedule`** — hard constraint, vs `ScheduleAnyway` (soft).
* **`labelSelector`** — which Pods to count (the Deployment's Pods).

### 7.1 The algorithm

```
For each domain D (defined by topologyKey):
  current = number of Pods matching the selector in D
  if new Pod would land in D:
    new = current + 1
    skew = max(new) - min(new)
  if skew > maxSkew: drop D (DoNotSchedule) or score lower (ScheduleAnyway)
```

### 7.2 Why topology spread is better than pod anti-affinity

`podAntiAffinity` with `topologyKey: kubernetes.io/hostname` does the same thing. But:

* `podAntiAffinity` is O(n) per node (lists all matching Pods).
* `topologySpreadConstraints` is O(1) per node (counts via the scheduler's cache).
* Topology spread has cleaner semantics (`maxSkew` is explicit).

For "spread replicas of a Deployment across nodes", use topology spread. For "I want my Pod near a specific other Pod", use pod affinity.

### 7.3 The `minDomains` parameter

```yaml
topologySpreadConstraints:
- maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    minDomains: 3                # at least 3 zones must have the Pod
    labelSelector: { ... }
```

`minDomains` enforces that the Pods are spread across at least N domains. If only 2 zones have nodes for the Pod, it's unschedulable.

### 7.4 The `nodeAffinityPolicy` and `nodeTaintsPolicy`

```yaml
topologySpreadConstraints:
- maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector: { ... }
    nodeAffinityPolicy: Honor       # ignore nodes that don't match Pod's affinity
    nodeTaintsPolicy: Honor        # ignore tainted nodes
```

* `Honor` (default) — the constraint respects the Pod's other constraints (affinity, taints).
* `Ignore` — the constraint counts Pods on all nodes, including those the Pod wouldn't otherwise land on.

`Honor` is the standard. `Ignore` is for advanced cases.

## 8. NodeName and NodeUnschedulable

### 8.1 nodeName

```yaml
spec:
  nodeName: node-1
```

The Pod is scheduled on `node-1` directly. The scheduler's `NodeName` plugin filters out every other node.

Used by:

* **DaemonSets** (kubelet creates Pods with nodeName set).
* **Custom controllers** that pick the node themselves.
* **Debugging** — force a Pod to a specific node.

**`nodeName` overrides the scheduler.** If `node-1` doesn't have enough resources, the Pod stays Pending. The scheduler doesn't try to fit it elsewhere.

### 8.2 unschedulable nodes

```bash
kubectl cordon node-1
```

Marks the node with `spec.unschedulable: true`. The scheduler's `NodeUnschedulable` plugin drops it. **No new Pods are scheduled on the node.**

Existing Pods are unaffected. To evict them, use `kubectl drain`.

## 9. Scheduling Profiles

A `KubeSchedulerConfiguration` can define multiple profiles:

```yaml
apiVersion: kubescheduler.config.k8s.io/v1beta3
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: default-scheduler
  plugins:
    score:
      enabled:
      - name: NodeResourcesBalancedAllocation
- schedulerName: batch-scheduler
  plugins:
    score:
      enabled:
      - name: NodeResourcesMostAllocated
```

Pods use a profile via `spec.schedulerName`. See [[Kubernetes/concepts/L06-scheduling-scaling/12-scheduler-internals|Scheduler Internals]] for the full picture.

## 10. The "IgnoredDuringExecution" Gotcha

The suffix is everywhere: `requiredDuringSchedulingIgnoredDuringExecution`, `preferredDuringSchedulingIgnoredDuringExecution`. **It means: enforced at scheduling time, ignored afterward.**

Once a Pod is scheduled, the scheduler doesn't re-evaluate:

* Node label changes.
* Pods moving between nodes.
* Taint changes.

**If the cluster state changes after a Pod is scheduled, the Pod is not evicted to satisfy the new state.**

This is a real footgun:

* A Pod scheduled to "us-east-1a" with `zone: [a, b]` affinity stays in `us-east-1a` even if all other Pods in the Deployment move to `us-east-1b`.
* A Pod scheduled to a "ssd" node stays on that node even if you remove the `disktype=ssd` label.

If you want **steady-state enforcement**, use a different mechanism (e.g. an operator that reconciles). Affinity is a scheduling hint, not a steady-state constraint.

## 11. The Scoring Algorithm and Weights

When the scheduler scores a node, it runs all enabled score plugins. Each returns a 0-100 value. The framework combines:

```
final_score(node) = sum(weight_i * score_i(node)) / sum(weight_i) * 100
```

Default plugin weights are 1, but the `NodeResourcesFit` plugin can have weighted resources (e.g. CPU weight 1, memory weight 1, GPU weight 5).

The framework picks the **highest-scoring node**. Ties are broken by random.

### 11.1 `percentageOfNodesToScore`

A key perf tuning. The default is to score **all** nodes that pass the filter. With 1,000 nodes and 1,000 pending Pods, that's 1,000,000 score calls.

```yaml
pluginConfig:
- name: PercentageOfNodesToScore
  args:
    apiVersion: kubescheduler.config.k8s.io/v1beta3
    kind: PercentageOfNodesToScoreArgs
    percentageOfNodesToScore: 50
```

The scheduler picks a random 50% of nodes and scores only those. **The best node is in the 50% with high probability, but the scheduler is 2x faster.** For most clusters, 50% is a good default.

## 12. The Filter Phase Internals

The scheduler's filter phase runs in **parallel across nodes**. The default is 16 goroutines — for a 1,000-node cluster, the filter processes 1,000/16 ≈ 63 batches.

Each filter plugin can return:

* `nil` — node is fine.
* `Unschedulable` — node can't run the Pod (filter it out).
* `UnschedulableAndUnresolvable` — same, plus don't try to preempt on this node.
* `Wait` — wait for the plugin's condition to clear (e.g. PVC binding).

If **any** plugin returns Unschedulable, the node is dropped.

### 12.1 The 16 default filter plugins

| Plugin | What it filters |
|---|---|
| `NodeUnschedulable` | Cordoned nodes |
| `NodeName` | Nodes not matching `spec.nodeName` |
| `NodeAffinity` | Nodes not matching `nodeAffinity` |
| `NodeResourcesFit` | Nodes without enough CPU/memory/extended resources |
| `NodePorts` | Nodes without the requested `hostPort` |
| `NodeVolumeLimits` | Nodes at the per-CSI-driver volume count |
| `TaintToleration` | Nodes with taints the Pod doesn't tolerate |
| `EBSLimits`, `GCEPDLimits`, `AzureDiskLimits`, `CinderLimits` | Per-cloud volume count |
| `MaxCSIVolumeCountPerNode`, `MaxEBSVolumeCountPerNode`, etc. | Max CSI / EBS / GCE PD / Azure Disk / Cinder volume counts |
| `PodTopologySpread` | Nodes violating topology spread (DoNotSchedule) |
| `InterPodAffinity` | Nodes violating pod affinity / anti-affinity (required) |
| `VolumeBinding` | Nodes where the Pod's PVCs can't bind |
| `VolumeRestrictions` | Nodes with restricted volumes (e.g. FUSE) |

Most filters are fast. `InterPodAffinity` is the slow one at scale.

## 13. Common Use Cases

### 13.1 Multi-tenant cluster

```yaml
# Taint team A's nodes
kubectl taint nodes node-1 dedicated=team-a:NoSchedule
# Taint team B's nodes
kubectl taint nodes node-2 dedicated=team-b:NoSchedule
```

Team A's Pods have a toleration for `dedicated=team-a`. Team B's for `dedicated=team-b`. **No accidental cross-team scheduling.**

### 13.2 High availability across zones

```yaml
topologySpreadConstraints:
- maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: web
```

Replicas of `web` are spread evenly across zones. Lose a zone, lose 1/3 of replicas.

### 13.3 Special hardware

```yaml
nodeSelector:
  accelerator: nvidia-tesla-a100
tolerations:
- key: nvidia.com/gpu
  operator: Exists
  effect: NoSchedule
```

Only A100 nodes, with a GPU toleration.

### 13.4 Cache hot by staying on the same node

```yaml
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchLabels:
          app: my-cache
      topologyKey: kubernetes.io/hostname
```

Try to keep the cache's replicas on different nodes. **This is `podAntiAffinity` with `topologyKey: hostname`** — same as spreading.

### 13.5 Dedicated node pool

```bash
# mark the dedicated pool
kubectl taint nodes -l dedicated=general dedicated=general:NoSchedule
```

```yaml
# Pod tolerates the pool
tolerations:
- key: dedicated
  operator: Equal
  value: general
  effect: NoSchedule
```

## 14. Operations and Debugging

### 14.1 Common commands

```bash
# check a Pod's scheduling constraints
kubectl get pod <pod> -o jsonpath='{.spec.nodeName}'
kubectl get pod <pod> -o jsonpath='{.spec.affinity}'
kubectl get pod <pod> -o jsonpath='{.spec.tolerations}'

# check a node's labels
kubectl get node <name> --show-labels
kubectl label nodes <name> <key>=<value>   # add a label
kubectl taint nodes <name> <key>=<value>:<effect>   # add a taint

# see why a Pod is Pending
kubectl describe pod <pod>
# look at "Events" for "FailedScheduling"

# see the scheduler's decisions
kubectl -n kube-system logs -l app=kube-scheduler --tail=100
# verbose: --v=4
```

### 14.2 The "Pod Pending" checklist

```bash
# 1. Is there a node with enough resources?
kubectl describe pod <pod>
# look at "FailedScheduling" event

# 2. Is a taint blocking?
kubectl get nodes -o json | jq '.items[].spec.taints'
kubectl get pod <pod> -o jsonpath='{.spec.tolerations}'

# 3. Is a nodeSelector / affinity wrong?
kubectl get pod <pod> -o yaml | grep -A 5 affinity
kubectl get nodes --show-labels | grep <key>

# 4. Is a topology spread constraint blocking?
kubectl get pod <pod> -o yaml | grep -A 5 topologySpreadConstraints

# 5. Is the scheduler running?
kubectl -n kube-system get pods -l app=kube-scheduler

# 6. Check the scheduler logs for this Pod
kubectl -n kube-system logs -l app=kube-scheduler | grep <pod-name>
```

### 14.3 The "Pod scheduled but in wrong place" case

A Pod is running but in the wrong zone / on the wrong node type. The scheduler put it there.

```bash
# 1. Did the Pod's affinity / nodeSelector match?
kubectl get pod <pod> -o jsonpath='{.spec.nodeSelector}{.spec.affinity}'

# 2. Did the cluster have other choices?
kubectl get nodes -l <key>=<value>    # candidates
# if only one node matched the constraints, that's where it goes

# 3. Is a soft preference being ignored?
# preferredDuringScheduling is a soft preference. If no node matches the
# preferred term, the scheduler picks the best available.
```

## 15. Gotchas and Common Mistakes

### 15.1 The 30+ common mistakes

1. **`IgnoredDuringExecution` is the suffix for a reason.** Affinity is scheduling-time, not steady-state. Don't rely on it for steady-state enforcement.

2. **The scheduler is reactive, not proactive.** It runs when there's something to schedule. There's no constant rebalancing.

3. **A `Pending` Pod with no events is usually a scheduling failure.** `kubectl describe pod` will show why.

4. **Don't over-constrain.** The more affinity rules, the more likely Pods will be `Pending` and nothing gets scheduled. Defaults are sane.

5. **`nodeSelector` and `nodeAffinity` are not mutually exclusive.** A Pod can require both.

6. **Taints are how you protect nodes, not labels.** A node with no taint will accept any Pod. Taint = "no Pods unless they tolerate".

7. **Pod affinity / anti-affinity scale poorly.** With 1000+ nodes and many Pods, the scheduler gets slow. Topology spread constraints are more efficient.

8. **Affinity on hostname is the same as "node anti-affinity with the same Pod".** If you want a Pod to NOT land on the same node as another, use `podAntiAffinity` with `topologyKey: kubernetes.io/hostname`.

9. **The default `tolerationSeconds` for `not-ready` and `unreachable` is 5 minutes.** The Pod tolerates the taint for 5 min, then is evicted. This gives the cluster time to recover the node. If you want longer / shorter, override the default toleration on your Pods.

10. **`PreferNoSchedule` is "try to avoid, but schedule if necessary".** A Pod with `tolerationSeconds` on a `NoExecute` taint is the same as a `PreferNoSchedule` for the same taint.

11. **`NoExecute` taints are dangerous.** A `NoExecute` taint on a node without a matching toleration kills all Pods on the node (after `tolerationSeconds`).

12. **`operator: Exists` is more permissive than `Equal`.** With `Exists`, you don't need to know the value. With `Equal`, you do.

13. **`operator: Gt` and `Lt` are for numeric labels.** Don't use them for strings.

14. **A `nodeSelector` with multiple keys is AND, not OR.** A Pod with `disktype: ssd, gpu: present` needs both labels.

15. **A `matchExpressions` with multiple keys is AND.** A Pod with `zone: In [a, b], arch: In [amd64]` needs both to match.

16. **A `nodeSelectorTerms` list is OR.** A Pod with two terms matches if either term matches.

17. **`preferredDuringSchedulingIgnoredDuringExecution` weights are 1-100.** They don't have to be 100. Smaller weights are valid.

18. **The scheduler's cache is eventually consistent.** A Pod scheduled 100ms ago may not be visible to a new Pod's affinity check.

19. **The scheduler doesn't know about cluster-wide capacity.** It makes per-node decisions.

20. **The scheduler doesn't run on every node.** It's a central Deployment.

21. **A `nodeName` set in the Pod spec overrides everything.** The scheduler filters out every other node. Used by DaemonSets, not by user Pods.

22. **`kubectl cordon` sets `unschedulable: true`.** The scheduler drops the node. Existing Pods are unaffected.

23. **`kubectl drain` cordons + evicts.** Used for node maintenance.

24. **The kubelet's `--register-with-taints`** can set taints on a new node when it joins. Used to keep Pods off nodes until they're ready.

25. **The `node.kubernetes.io/unschedulable` taint is the same as `unschedulable: true`.** `kubectl cordon` adds the taint; `kubectl uncordon` removes it.

26. **The `node.kubernetes.io/memory-pressure` and `disk-pressure` are node conditions, not taints.** They affect the scheduler's filter (nodes under pressure are less preferred) but aren't strict taints.

27. **The scheduler doesn't know about Pod priorities unless you set `priorityClassName`.** All Pods are equal otherwise.

28. **The scheduler doesn't know about PDBs.** PDBs affect eviction, not scheduling.

29. **The scheduler doesn't know about HPA.** HPA changes `replicas`, not node selection. The scheduler just sees "more Pods to schedule".

30. **The scheduler's `Wait` filter result delays scheduling.** A PVC that's not yet bound causes the Pod to be in `Wait` state. The Pod is not Pending, but it's not scheduled either. Wait for the PVC to bind.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption|Priority & Preemption]] — preemption when filter yields 0 nodes
* [[Kubernetes/concepts/L06-scheduling-scaling/12-scheduler-internals|Scheduler Internals]] — the plugin pipeline
* [[Kubernetes/concepts/L06-scheduling-scaling/13-scheduling-gates|Scheduling Gates]] — holding Pods back from scheduling
* [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — what scheduling decisions affect (Service routing)

# Scheduler Internals (Kube-Scheduler, Plugins, Profiles)

*"https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/"*

The kube-scheduler is the **default scheduler** for Kubernetes. It runs as a single Deployment (or HA, with leader election) in `kube-system`, and decides which node every Pod runs on. The scheduling decision is made by a **plugin framework** — a set of "filter" and "score" plugins that the scheduler runs in order. This note covers the internals: how the framework works, the default plugins, and how to customize it.

### Table of Contents

1. [The Scheduler's Job](#1-the-schedulers-job)
2. [The Scheduling Cycle](#2-the-scheduling-cycle)
3. [The Scheduling Framework](#3-the-scheduling-framework)
4. [The Default Plugins in Detail](#4-the-default-plugins-in-detail)
5. [Scheduling Profiles](#5-scheduling-profiles)
6. [Extensibility Points](#6-extensibility-points)
7. [The `NodeResourcesFit` Plugin Deep-Dive](#7-the-noderesourcesfit-plugin-deep-dive)
8. [The `NodeAffinity` and `TaintToleration` Plugins](#8-the-nodeaffinity-and-tainttoleration-plugins)
9. [The `PodTopologySpread` Plugin](#9-the-podtopologyspread-plugin)
10. [The `InterPodAffinity` Plugin](#10-the-interpodaffinity-plugin)
11. [The `VolumeBinding` Plugin](#11-the-volumebinding-plugin)
12. [Custom Plugins and Webhooks](#12-custom-plugins-and-webhooks)
13. [Performance and Scale](#13-performance-and-scale)
14. [Operations and Debugging](#14-operations-and-debugging)
15. [Gotchas and Common Mistakes](#15-gotchas-and-common-mistakes)

---

## 1. The Scheduler's Job

For every unscheduled Pod, the scheduler:

1. **Listens** for Pods with `spec.nodeName` unset.
2. **Filters** out nodes that can't run the Pod.
3. **Scores** the remaining nodes.
4. **Reserves** the chosen node (sets `nominatedNodeName`).
5. **Permits** the bind (or waits for an external webhook).
6. **Binds** the Pod to the node (sets `spec.nodeName`).
7. **Updates** the apiserver.

The scheduler doesn't run the Pod — it just sets the field. The kubelet on the target node picks up the Pod and starts it.

### 1.1 What the scheduler does NOT do

* **Re-schedule Pods.** A scheduled Pod stays on its node unless evicted.
* **Rebalance.** The scheduler doesn't migrate Pods to balance the cluster.
* **Predict future load.** The scheduler makes decisions based on the current state of the cluster.
* **Talk to nodes directly.** It only talks to the apiserver. Nodes register themselves; the scheduler doesn't ping them.

## 2. The Scheduling Cycle

For a single Pod, the scheduling cycle is:

```
Pod is Pending
       │
       ▼
┌──────────────────┐
│ PreFilter        │  Pre-filter checks (e.g. parse affinity)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Filter           │  Run all filter plugins
│ (parallel)       │  Drop nodes that can't run the Pod
└────────┬─────────┘
         │
         ▼ (filtered nodes ≥ 1?)
         │
┌──────────────────┐
│ PreScore         │  Pre-score preparation
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Score            │  Run all score plugins in parallel
│ (parallel)       │  Each returns 0-100
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ NormalizeScore   │  Combine scores, weighted sum
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Reserve          │  Mark the chosen node's resources as reserved
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Permit           │  Wait for webhook approval (optional)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ PreBind          │  Pre-bind hooks (e.g. volume binding)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Bind             │  Set spec.nodeName on the Pod
└────────┬─────────┘
         │
         ▼
Pod is bound to a node
```

If the filter phase yields 0 nodes, the scheduler tries **preemption** (see [[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption|Priority & Preemption]]).

## 3. The Scheduling Framework

The framework is a **plugin pipeline**. Each extension point runs a set of plugins. The default scheduler has many built-in plugins; you can add, remove, or reorder them via `KubeSchedulerConfiguration`.

### 3.1 The extension points

| Extension | What runs | Plugins (defaults) |
|---|---|---|
| `PreEnqueue` | Before the Pod is added to the queue | (none) |
| `Enqueue` | When the Pod is added to the queue | (none) |
| `PreFilter` | Before filtering, can short-circuit | `NodeResourcesFit`, `NodeAffinity`, `PodTopologySpread`, `InterPodAffinity`, `VolumeBinding` |
| `Filter` | Drops nodes that can't run the Pod | `NodeUnschedulable`, `NodeName`, `NodeAffinity`, `NodeResourcesFit`, `NodePorts`, `NodeVolumeLimits`, `TaintToleration`, `EBSLimits`, `GCEPDLimits`, `AzureDiskLimits`, `CinderLimits`, `MaxCSIVolumeCountPerNode`, `MaxEBSVolumeCountPerNode`, `MaxGCEPDVolumeCountPerNode`, `MaxAzureDiskVolumeCountPerNode`, `MaxCinderVolumeCountPerNode`, `PodTopologySpread`, `InterPodAffinity`, `VolumeBinding`, `VolumeRestrictions` |
| `PostFilter` | After filter, if no nodes remain | `DefaultPreemption` |
| `PreScore` | Before scoring | `NodeAffinity`, `PodTopologySpread`, `InterPodAffinity` |
| `Score` | Rank remaining nodes | `NodeResourcesFit`, `NodeAffinity`, `TaintToleration`, `ImageLocality`, `InterPodAffinity`, `NodeResourcesBalancedAllocation`, `NodeResourcesLeastAllocated`, `PodTopologySpread`, `TaintToleration` |
| `NormalizeScore` | Combine scores | (built-in) |
| `Reserve` | Reserve resources on the chosen node | `VolumeBinding` |
| `Permit` | Wait for external approval | (default: always permit) |
| `PreBind` | Before binding | `VolumeBinding` |
| `Bind` | Set the Pod's nodeName | `DefaultBinder` (built-in) |
| `PostBind` | After binding | (default: no-op) |

This is a lot. The key plugins to know are in the next sections.

## 4. The Default Plugins in Detail

### 4.1 `NodeResourcesFit`

**Filter:** drops nodes that don't have enough CPU / memory / extended resources for the Pod's `requests`.

**Score:** ranks nodes by how well their resources fit the Pod. Three scoring strategies:
- `LeastAllocated` (default) — prefers nodes with the most free resources. Spreads load.
- `MostAllocated` — prefers nodes with the least free resources. Packs tight (good for bin-packing).
- `RequestedToCapacityRatio` — uses a custom ratio. Advanced.

The filter is hard; the score is soft. A node that doesn't fit is dropped; a node that fits less well scores lower.

### 4.2 `NodeAffinity`

**Filter:** drops nodes that don't match `requiredDuringSchedulingIgnoredDuringExecution` rules.

**Score:** ranks nodes by how well they match `preferredDuringScheduling...` rules (weight-based).

### 4.3 `TaintToleration`

**Filter:** drops nodes that have taints the Pod doesn't tolerate.

**Score:** ranks nodes by how many PreferNoSchedule taints the Pod tolerates (negative scoring for tolerated taints, but prefers tolerated over not).

### 4.4 `NodeName`

**Filter:** if `spec.nodeName` is set on the Pod, drops every node except that one. (Used by custom controllers that pick the node themselves, like some operators.)

**Disable** this plugin to allow the scheduler to override a `nodeName` set in the Pod (uncommon).

### 4.5 `NodeUnschedulable`

**Filter:** drops nodes that have `spec.unschedulable: true` (cordoned nodes). The default is to drop them.

### 4.6 `NodePorts`

**Filter:** drops nodes that don't have the requested `hostPort` available (only for hostPort Pods).

### 4.7 `NodeVolumeLimits`

**Filter:** drops nodes that have hit their max volume count (per-CSI-driver limits).

### 4.8 `PodTopologySpread`

**Filter:** drops nodes that would violate `topologySpreadConstraints` (when `whenUnsatisfiable: DoNotSchedule`).

**Score:** ranks nodes that satisfy the constraints (when `whenUnsatisfiable: ScheduleAnyway`).

### 4.9 `InterPodAffinity`

**Filter:** drops nodes that would violate `podAffinity` / `podAntiAffinity` (with `requiredDuring...`).

**Score:** ranks nodes by how well they match `preferredDuring...` affinity rules.

### 4.10 `VolumeBinding`

**Filter:** checks that the Pod's PVCs can be bound on the node (storage capacity, zone affinity).

**Reserve / PreBind:** reserves the volume on the chosen node.

### 4.11 `DefaultPreemption`

**PostFilter:** if no nodes pass the filter, try preempting lower-priority Pods on candidate nodes.

### 4.12 `DefaultBinder`

**Bind:** the only plugin that actually sets `spec.nodeName`. It's built-in and can't be replaced (without a custom build).

## 5. Scheduling Profiles

A **profile** is a named configuration of plugins. You can have multiple profiles in the same cluster, and a Pod picks one via `spec.schedulerName`.

```yaml
apiVersion: kubescheduler.config.k8s.io/v1beta3
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: default-scheduler
  plugins:
    score:
      disabled:
      - name: NodeResourcesBalancedAllocation
- schedulerName: system-scheduler
  plugins:
    score:
      enabled:
      - name: NodeResourcesMostAllocated   # pack tight
```

Pods use the profile via `spec.schedulerName`:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: packed }
spec:
  schedulerName: system-scheduler
  # ...
```

The Pod is scheduled by the `system-scheduler` profile, which scores by `NodeResourcesMostAllocated` (pack tight). The default profile (`default-scheduler`) spreads load.

### 5.1 Multiple profiles use case

* **System vs user Pods** — system Pods (kube-proxy, CNI) get a tight-packing profile, user Pods get a spread profile.
* **Batch vs interactive** — batch jobs get a bin-packing profile (pack tight), interactive get a spread profile.
* **Different priority tiers** — high-priority Pods get a profile that tries harder to schedule (e.g. less restrictive filters).

The profiles are **per-scheduler-pod-binding**. Pods with `schedulerName: X` are scheduled by profile X. The default (no `schedulerName`) uses the profile named `default-scheduler`.

## 6. Extensibility Points

The framework has 11 extension points. You can write **custom plugins** (Go, compiled into the scheduler binary) or **out-of-tree** webhooks for some points.

### 6.1 Pre-filter and Filter

Custom filters can drop nodes. The plugin returns `Unschedulable` or `UnschedulableAndUnresolvable` to drop a node.

### 6.2 Score

Custom scores add a 0-100 value to a node. The framework weights and sums all scores.

### 6.3 Reserve, Permit, PreBind, Bind

The most powerful extension points, but also the most complex. Most users don't need them.

### 6.4 The Permit plugin

The `Permit` extension point is special. By default, every Pod is permitted. You can add a `Permit` plugin (or an external scheduler webhook) that says "wait" — the scheduler holds the Pod in a "waiting" state until the permit is granted.

This is used for:
- **Co-scheduling** (a group of Pods must be scheduled together).
- **Quota** (a Pod must wait until a quota is approved).
- **Custom validation** (a Pod must be checked before binding).

```yaml
apiVersion: kubescheduler.config.k8s.io/v1beta3
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: default-scheduler
  plugins:
    permit:
      enabled:
      - name: MyCustomPermitPlugin
```

### 6.5 The scheduler extender (out-of-tree)

For custom logic that doesn't require recompiling the scheduler, you can use a **scheduler extender** — an HTTP webhook the scheduler calls. The extender implements the same interface as built-in plugins.

```yaml
apiVersion: kubescheduler.config.k8s.io/v1beta3
kind: KubeSchedulerConfiguration
extenders:
- urlPrefix: "http://my-extender.default.svc:8080"
  filterVerb: predicate
  prioritizeVerb: prioritizer
  bindingVerb: bind
  weight: 1
  managedResources:
  - name: "example.com/foo"
    ignoredByScheduler: true
```

The scheduler calls the extender's `predicate` (filter) and `prioritizer` (score) endpoints for each Pod. **The scheduler extender is deprecated** in favor of the scheduling framework's plugin API, but it's still supported for back-compat.

## 7. The `NodeResourcesFit` Plugin Deep-Dive

The most-called plugin. It checks the Pod's `requests` against each node's `allocatable`.

```yaml
apiVersion: kubescheduler.config.k8s.io/v1beta3
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: default-scheduler
  pluginConfig:
  - name: NodeResourcesFit
    args:
      apiVersion: kubescheduler.config.k8s.io/v1beta3
      kind: NodeResourcesFitArgs
      scoringStrategy:
        type: LeastAllocated     # default
        resources:
        - name: cpu
          weight: 1
        - name: memory
          weight: 1
        # ignoredResources are not scored (but are still filtered)
        # ignoredResourceGroups are not scored
```

### 7.1 The filter logic

For each node:
1. Sum the node's `allocatable.cpu` (or memory, etc.).
2. Subtract the sum of `requests` of all Pods on the node.
3. Compare to the new Pod's `requests`.
4. If insufficient, drop the node.

The filter is **hard** — a Pod that doesn't fit is dropped.

### 7.2 The score logic

The score is the node's free resources as a fraction:

```
score = free_resources / allocatable_resources
```

For `LeastAllocated` (default), higher = better. The scheduler prefers nodes with the most free resources (spreads load).

For `MostAllocated`, the score is inverted. The scheduler prefers nodes with the least free resources (packs tight).

### 7.3 Extended resources

The `NodeResourcesFit` plugin also handles **extended resources** (GPU, FPGA, etc.):

```yaml
resources:
- name: nvidia.com/gpu
  weight: 5    # weight higher than CPU/memory — GPU fit is critical
```

If a Pod requests 1 GPU and a node has 0, the node is dropped (filter). If a node has 4 GPUs, the score is high.

## 8. The `NodeAffinity` and `TaintToleration` Plugins

See [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|Scheduling]] for the basic syntax. These plugins enforce it.

### 8.1 `NodeAffinity`

`requiredDuringSchedulingIgnoredDuringExecution` rules are enforced in the **Filter** phase. `preferredDuringSchedulingIgnoredDuringExecution` rules are scored.

The "IgnoredDuringExecution" suffix is critical: once a Pod is scheduled, these rules are **not** checked. If you change a node's label, the Pod stays. **Affinity is scheduling-time, not steady-state.**

### 8.2 `TaintToleration`

The `NoSchedule` and `NoExecute` taints are enforced in the Filter phase. `PreferNoSchedule` is scored (negative weight).

`NoExecute` taints are different — they're applied to **existing Pods** (e.g. when a node becomes NotReady). The kubelet evicts Pods that don't tolerate the taint, respecting `tolerationSeconds`.

## 9. The `PodTopologySpread` Plugin

See [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|Scheduling]] for the YAML. The plugin enforces the constraints in the Filter phase and scores in the Score phase.

The `topologyKey` is the label used to group nodes. Common:

* `kubernetes.io/hostname` — each node is its own domain.
* `topology.kubernetes.io/zone` — each zone is a domain.
* `topology.kubernetes.io/region` — each region is a domain.

The `maxSkew: 1` means "the most-loaded domain has at most 1 more Pod than the average". The algorithm:

```
For each domain D:
  current = number of Pods matching the selector in D
  if new Pod would land in D:
    new = current + 1
    skew = max(new, current_max) - min(new, current_min)
  if skew > maxSkew:
    domain D is filtered out (when DoNotSchedule)
    or domain D is scored lower (when ScheduleAnyway)
```

## 10. The `InterPodAffinity` Plugin

`podAffinity` / `podAntiAffinity` rules. The plugin:

1. Lists all Pods in the cluster (cached locally).
2. For each candidate node, counts how many Pods matching the affinity label are on the node.
3. Filters or scores based on the count.

**This is O(n*m)** — for every Pod, every node, every existing Pod. The scheduler caches Pod state, but the cache is invalidated frequently. **At 1000+ nodes and 10,000+ Pods, the scheduler gets slow.** This is why `topologySpreadConstraints` is recommended for "spread evenly" use cases — it's much more efficient.

## 11. The `VolumeBinding` Plugin

Handles PVC binding during scheduling. The plugin:

1. For each PVC referenced by the Pod, check if a matching PV exists.
2. If `WaitForFirstConsumer`, wait for the Pod to be scheduled, then bind.
3. If `Immediate`, bind before scheduling.

This plugin interacts with the **storage provisioner** (CSI driver). For more on this, see [[Kubernetes/concepts/L05-config-storage/06-storageclass|StorageClass]].

## 12. Custom Plugins and Webhooks

### 12.1 Custom plugins (Go)

Write a Go plugin, compile it into the scheduler binary, register it. The plugin implements the relevant extension points.

```go
type MyPlugin struct{}

func (p *MyPlugin) Name() string { return "MyPlugin" }

func (p *MyPlugin) Filter(ctx context.Context, state *framework.CycleState, pod *v1.Pod, node *v1.Node) *framework.Status {
    if podNeedsGPU(state) && !nodeHasGPU(node) {
        return framework.NewStatus(framework.Unschedulable, "no GPU")
    }
    return nil
}
```

Then register it in the scheduler:

```go
cmd := kubescheduler.NewMySchedulerCommand(
    kubescheduler.WithPlugin("MyPlugin", &MyPlugin{}),
)
```

Compile, deploy, restart the scheduler. **The scheduler is a single binary, not a plug-in runtime** — you must compile and deploy.

### 12.2 Scheduler webhooks

For simpler custom logic, use a scheduler webhook. The scheduler calls your HTTP endpoint at specific extension points.

```yaml
apiVersion: kubescheduler.config.k8s.io/v1beta3
kind: KubeSchedulerConfiguration
extenders:
- urlPrefix: "http://my-scheduler-webhook.default.svc:8080"
  filterVerb: predicate
  prioritizeVerb: prioritizer
  weight: 1
```

The webhook implements:

* `POST /predicate` — return whether a node can run the Pod.
* `POST /prioritizer` — return a score for the node.

The scheduler calls these for every node, for every Pod. The webhook becomes a hot path. **Make it fast.**

## 13. Performance and Scale

### 13.1 The scheduler's main bottleneck

The scheduler's main cost is the **filter phase**. For a Pod with many affinity rules or a cluster with many nodes, this can take seconds.

Typical numbers:

* 100 nodes, 1,000 Pods: filter takes ~100ms per Pod.
* 1,000 nodes, 10,000 Pods: filter takes ~1s per Pod.
* 10,000 nodes, 100,000 Pods: filter takes ~10s per Pod. **Problematic.**

The scheduler parallelizes filter and score across nodes (the default is 16 goroutines). With 1,000 nodes, the filter is 1000/16 ≈ 63 batches.

### 13.2 Caching

The scheduler **caches** Pods, Nodes, and other resources. The cache is updated via watch events. **The cache is shared across scheduling decisions** — one Pod's decision uses the same cache as another.

If the cache is stale (e.g. cluster has churn), the scheduler may make suboptimal decisions. The cache is eventually consistent.

### 13.3 Scheduler tuning

```yaml
apiVersion: kubescheduler.config.k8s.io/v1beta3
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: default-scheduler
  percentageOfNodesToScore: 50    # score only 50% of nodes after filter
```

`percentageOfNodesToScore` is a key tuning knob. By default, the scheduler scores **all** nodes that pass the filter. With 1,000 nodes and 1,000 pending Pods, that's 1,000,000 score calls. Setting `percentageOfNodesToScore: 50` makes the scheduler pick a random 50% of nodes and score only those. **The best node is in the 50% with high probability, but the scheduler is 2x faster.**

For most clusters, `percentageOfNodesToScore: 50` is a good balance. For latency-sensitive clusters, lower it. For bin-packing (most-fit), set it higher.

## 14. Operations and Debugging

### 14.1 Common commands

```bash
# check the scheduler
kubectl -n kube-system get pods -l app=kube-scheduler
kubectl -n kube-system logs -l app=kube-scheduler --tail=100

# check the scheduler config
kubectl -n kube-system get configmap kube-scheduler-config -o yaml
# or, for kubeadm:
cat /etc/kubernetes/manifests/kube-scheduler.yaml

# see why a Pod is Pending
kubectl describe pod <pod>
# look at events for "FailedScheduling"

# enable scheduler debug logging
# set --v=4 or higher on the kube-scheduler command line
```

### 14.2 The "Pod is Pending forever" checklist

```bash
# 1. Is the scheduler running?
kubectl -n kube-system get pods -l app=kube-scheduler

# 2. What does the scheduler say about this Pod?
kubectl describe pod <pod>
# look at "Events" - the scheduler records why it didn't schedule

# 3. Are there candidate nodes at all?
kubectl get nodes
# if no nodes, the scheduler has nothing to work with

# 4. Is the cluster out of resources?
kubectl top nodes
kubectl describe node <node> | grep -A 5 "Allocated resources"

# 5. Is a taint / affinity / PDB blocking?
# check the Pod's spec
kubectl get pod <pod> -o yaml

# 6. Is the scheduler profile restrictive?
kubectl -n kube-system get configmap kube-scheduler-config -o yaml
```

### 14.3 Scheduler profiling

The scheduler exposes Prometheus metrics on `:10259` (or `:10251` for older versions):

```bash
kubectl -n kube-system port-forward kube-scheduler-<node> 10259:10259
curl localhost:10259/metrics
```

Key metrics:

* `scheduler_pending_pods` — Pods waiting to be scheduled.
* `scheduler_schedule_attempts_total` — total scheduling attempts.
* `scheduler_scheduling_algorithm_duration_seconds` — time spent in filter + score.
* `scheduler_e2e_scheduling_duration_seconds` — total time from Pod creation to binding.

If `scheduler_e2e_scheduling_duration_seconds` is high, the scheduler is slow. Look at `scheduler_scheduling_algorithm_duration_seconds` to see if it's filter or score.

## 15. Gotchas and Common Mistakes

### 15.1 The 20+ common mistakes

1. **Affinity rules are not steady-state.** Once a Pod is scheduled, the rules are not re-evaluated. If you change node labels, the Pod stays.

2. **Preemption is best-effort.** A high-priority Pod may stay Pending if preemption can't find candidates (PDBs, system Pods, etc.).

3. **The `InterPodAffinity` plugin is slow at scale.** Use `topologySpreadConstraints` for "spread" use cases.

4. **The `NodeAffinity` plugin ignores `IgnoredDuringExecution` changes.** It only checks at scheduling time.

5. **`percentageOfNodesToScore: 100` is a perf footgun.** The default `50` is a good balance.

6. **Custom plugins require recompiling the scheduler.** There's no plug-in runtime (besides webhooks, which are deprecated).

7. **The `Permit` extension can deadlock scheduling.** A `Permit` plugin that never says "approve" is a bug.

8. **The `NodeResourcesFit` plugin uses `requests`, not `limits`.** A Pod's `limits` don't affect scheduling.

9. **The `VolumeBinding` plugin doesn't handle `WaitForFirstConsumer` for unbound PVCs.** The Pod is Pending until the PVC is bound. Make sure the StorageClass has `WaitForFirstConsumer`.

10. **`NodeName` (a hard-coded node in the Pod spec) overrides the scheduler.** The scheduler filters out every node except that one. Used by custom controllers (e.g. `DaemonSet`).

11. **The scheduler doesn't run on every node.** It's a single Deployment (or HA). All decisions go through it.

12. **The scheduler's cache is eventually consistent.** A Pod scheduled 100ms ago may not be visible to a new Pod's affinity check.

13. **The scheduler doesn't know about cluster-wide capacity.** It makes per-node decisions, not global. Two Pods can each fit on different nodes, but together exceed cluster capacity.

14. **The scheduler can preempt across nodes.** A high-priority Pod on node A can preempt Pods on node B if it would fit there.

15. **The scheduler's leader election means only one is active.** If the leader dies, the standby takes over (30s). Pods are queued during the transition.

16. **The scheduler's `--v=4` log is very verbose.** For debugging, bump to `--v=6` (very verbose, slow).

17. **The scheduler's `permit` plugins can hold Pods indefinitely.** Always set a timeout for permit plugins (via the `Permit` plugin itself).

18. **The scheduler extender (out-of-tree) is deprecated.** Migrate to scheduling framework plugins (Go).

19. **The scheduler doesn't enforce Pod priority for already-scheduled Pods.** A new low-priority Pod can't preempt an existing high-priority one.

20. **The scheduler doesn't run the `preemption` algorithm in the cache.** Preemption is a real-time search; it doesn't use the cache.

21. **The scheduler's `NodeResourcesFit` plugin uses `allocatable`, not `capacity`.** The difference is kubelet / system reserved.

22. **The scheduler's `NodeUnschedulable` plugin drops cordoned nodes by default.** To schedule on a cordoned node, you'd have to disable the plugin (or use `kubectl uncordon`).

23. **The scheduler's `NodePorts` plugin is for `hostPort`.** `hostPort` is rarely used; if you have it, the scheduler checks port conflicts.

24. **The scheduler doesn't know about pod resource metrics (CPU, memory usage).** It only uses `requests`. HPA-driven Pods (more replicas) are scheduled based on `requests`, not actual usage.

25. **The scheduler doesn't consider node maintenance windows.** A node scheduled for termination still accepts new Pods unless it's cordoned.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|Scheduling]] — the YAML-level primitives
* [[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption|Priority & Preemption]] — the preemption algorithm
* [[Kubernetes/concepts/L06-scheduling-scaling/13-scheduling-gates|Scheduling Gates]] — holding Pods back from scheduling
* [[Kubernetes/concepts/L05-config-storage/06-storageclass|StorageClass]] — the VolumeBinding plugin's interaction with storage

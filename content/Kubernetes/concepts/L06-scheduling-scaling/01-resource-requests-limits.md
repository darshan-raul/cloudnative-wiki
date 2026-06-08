# Resource Requests and Limits

*"https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/"*

Each container in a Pod can declare how much **CPU and memory** it needs. Two numbers: **requests** (what the container is guaranteed, used by the scheduler) and **limits** (the maximum the container is allowed to use, enforced at runtime). These are the most important numbers you set in k8s — they drive scheduling, HPA, VPA, eviction, and QoS.

### Table of Contents

1. [The Basics — Requests vs Limits](#1-the-basics--requests-vs-limits)
2. [CPU in Detail](#2-cpu-in-detail)
3. [Memory in Detail](#3-memory-in-detail)
4. [Ephemeral Storage](#4-ephemeral-storage)
5. [Huge Pages and Extended Resources](#5-huge-pages-and-extended-resources)
6. [How Requests Drive Scheduling](#6-how-requests-drive-scheduling)
7. [How Limits Are Enforced at Runtime](#7-how-limits-are-enforced-at-runtime)
8. [QoS Classes in Depth](#8-qos-classes-in-depth)
9. [The Init Container Scheduling Footgun](#9-the-init-container-scheduling-footgun)
10. [LimitRange — Defaults and Constraints](#10-limitrange--defaults-and-constraints)
11. [Pod-Level Resources (k8s 1.34+)](#11-pod-level-resources-k8s-134)
12. [The "No Limits" Debate in Depth](#12-the-no-limits-debate-in-depth)
13. [Cgroup v1 vs cgroup v2](#13-cgroup-v1-vs-cgroup-v2)
14. [In-Place Pod Resize (k8s 1.33+)](#14-in-place-pod-resize-k8s-133)
15. [Operations and Debugging](#15-operations-and-debugging)
16. [Gotchas and Common Mistakes](#16-gotchas-and-common-mistakes)

---

## 1. The Basics — Requests vs Limits

```yaml
spec:
  containers:
  - name: app
    image: app:1.0
    resources:
      requests:
        cpu: 100m          # 0.1 CPU guaranteed
        memory: 128Mi      # 128 MiB guaranteed
      limits:
        cpu: 500m          # 0.5 CPU max
        memory: 256Mi      # 256 MiB max
```

* **`requests`** — what the container is **guaranteed** to get. Used by the scheduler for placement. Counts against ResourceQuota. Drives HPA's `Utilization` calculation.
* **`limits`** — the **maximum** the container is allowed to use. Enforced at runtime by the kernel (CFS for CPU, cgroup memory limit for memory). Exceeding a memory limit = OOM-kill. Exceeding a CPU limit = throttled, not killed.

**Requests are the floor; limits are the ceiling.** A container with `requests.cpu: 100m, limits.cpu: 500m` will get 100m guaranteed but can burst up to 500m if the node has spare cycles.

## 2. CPU in Detail

### 2.1 Units

* `1` = 1 CPU = 1 vCPU on a cloud node.
* `1000m` = 1 CPU (the `m` is millicores).
* `500m` = half a CPU.
* `100m` = 1/10th of a CPU.

In fractional cores:
* `0.1` = 100m.
* `0.25` = 250m.
* `0.5` = 500m.

**The decimal and milli forms are equivalent** — `0.5` and `500m` are the same.

### 2.2 CPU is compressible

When a container exceeds its CPU limit, the kernel's **CFS (Completely Fair Scheduler)** throttles the container. The container can still run, just slower. **CPU throttling is not fatal.**

This is different from memory. CPU is a "compressible" resource — the kernel can give the container less of it without killing the process.

### 2.3 CPU in clouds

* 1 AWS vCPU = 1 k8s core = 1000m.
* 1 GCP core = 1 k8s core = 1000m.
* 1 Azure vCPU = 1 k8s core = 1000m.

(Older AWS instance types had a 2:1 vCPU-to-physical-core ratio, but modern types are 1:1.)

### 2.4 Burstable CPU

A container with `requests.cpu: 100m, limits.cpu: 1` is **Burstable**. In practice:

* The scheduler places it based on `requests` (100m).
* The container can use up to `limits` (1 core) if the node has spare cycles.
* If the node is busy, the container is throttled back to 100m.

**CFS quota enforcement** is per-cgroup. The container is assigned a quota of `100m * period` per `period` (default 100ms). If the container uses more than that quota in a period, it's throttled until the next period.

### 2.5 The CPU limit trap

CPU limits can hurt **latency-sensitive apps**. A Java app with `limits.cpu: 500m` may be throttled during GC pauses or bursts, increasing tail latency. The choices:

* **Remove the CPU limit** (only `requests`). The app can use whatever's free. The downside: a misbehaving app can starve neighbors.
* **Set `limits.cpu == requests.cpu`** (Guaranteed). The app gets exactly what it asks for, no throttling. The downside: no bursting.
* **Set a high `limits.cpu`** (e.g. `requests: 100m, limits: 4`). Some burst room, less throttling. The downside: misbehaving apps can spike.

Most production setups use the third option. Some latency-critical apps (search, ML serving) use option 1 or 2.

## 3. Memory in Detail

### 3.1 Units

Memory is in bytes by default. Common suffixes:

* `Ki` = 1024 bytes (kibibyte).
* `Mi` = 1024 Ki = 1,048,576 bytes (mebibyte).
* `Gi` = 1024 Mi (gibibyte).
* `K` = 1000 bytes (kilobyte). Rare in k8s.
* `M` = 1000 KB (megabyte). Rare.

**Use the binary suffixes (`Mi`, `Gi`)** — they're standard in k8s and what most tools expect.

### 3.2 Memory is incompressible

When a container exceeds its memory limit, the **cgroup memory limit** triggers and the kernel **OOM-kills** the container. The container exits with code 137.

Memory is **incompressible** — the kernel can't give the container less memory than it needs. The only options are "give it what it asked for" or "kill it".

### 3.3 Memory accounting subtleties

The cgroup memory limit accounts for **everything** in the cgroup:

* RSS (Resident Set Size) — actual physical memory used.
* Page cache — files the process has read but may not need again.
* Stack, heap, anonymous mappings.
* Kernel memory (network buffers, etc.).
* TCP/UDP socket buffers.

This means a process that **reads a lot of files** can hit its memory limit even if it doesn't think it's using that much memory. The page cache is counted.

For a database that does heavy reads, this is a real issue. You may need to set the memory limit higher than the app's RSS would suggest.

### 3.4 The OOM-kill cascade

A container that's OOM-killed is **restarted by the kubelet** (assuming `restartPolicy: Always`). If the OOM is chronic, the container restarts, OOM-kills again, restarts, OOM-kills again. This is the **CrashLoopBackOff**.

A Pod in CrashLoopBackOff is `Running` (the kubelet considers it running), but the container keeps crashing. **The Pod is alive, but useless.** HPA doesn't scale up a CrashLoopBackOff Pod — it sees the Pod as running.

### 3.5 The JVM-Xmx trap

JVMs allocate a large heap (`-Xmx`) regardless of actual usage. A JVM with `-Xmx=2g` will use 2 GB of cgroup memory (because the heap is reserved), even if the app only uses 200 MB.

If the container's memory limit is 1 GB, the JVM will OOM-kill at startup (the heap reservation alone exceeds the limit).

**Always set the JVM's `-Xmx` to be less than the container's memory limit** (with headroom for non-heap usage, native libs, etc.).

```bash
# in the container command
java -Xmx768m -jar app.jar
# container limit: 1Gi
# 768m heap + ~200m non-heap + ~30m headroom = ~1Gi
```

### 3.6 The Go runtime trap

Go doesn't reserve memory the way JVM does — it uses what it needs. A Go app with `limits.memory: 512Mi` will use 512 MB and OOM if it actually exceeds.

But Go's runtime **doesn't return memory to the OS** by default. The Go runtime holds onto memory even after the heap shrinks (the "GC tuning" problem). A Go app that uses 200 MB at peak will keep that 200 MB reserved.

**For Go apps, `requests.memory` is hard to set right.** Run VPA in `recommend` mode for Go apps.

## 4. Ephemeral Storage

`ephemeral-storage` is the third resource that the kubelet accounts for. It covers:

* **The container's writable layer** (any file the container writes that isn't in a volume).
* **Logs** stored at `/var/log/containers`.
* **`emptyDir` volumes** in the container.

```yaml
resources:
  requests:
    ephemeral-storage: 1Gi
  limits:
    ephemeral-storage: 2Gi
```

### 4.1 When it kicks in

The kubelet monitors ephemeral storage usage. If a container exceeds `limits.ephemeral-storage`, it's **evicted** (similar to OOM-kill). The Pod is rescheduled.

This is most often a problem for:

* **Log-spilling apps** that write huge log files.
* **Apps that write temp files** in the writable layer.
* **Image-extraction** — large container images take up space in the kubelet's storage.

### 4.2 The node's ephemeral storage

The kubelet reserves some ephemeral storage for its own use (image cache, logs, etc.). The node's `allocatable.ephemeral-storage` is what the scheduler sees.

A 100 GB node may have `allocatable.ephemable-storage: 90 GB` (10 GB reserved). The scheduler's bin-packing uses this.

### 4.3 The "node disk full" gotcha

If a node's ephemeral storage fills up, the kubelet starts evicting Pods — even if the Pods have low ephemeral storage usage. The eviction is by **total** usage, not by per-container usage. A Pod that doesn't write much can be evicted because the **node** is full.

This is a common issue with `emptyDir` (logs, caches) and writable layers (large images).

## 5. Huge Pages and Extended Resources

### 5.1 Huge pages

Huge pages are a kernel feature for large memory allocations. k8s supports them as a special resource:

```yaml
resources:
  requests:
    hugepages-2Mi: 1Gi
  limits:
    hugepages-2Mi: 1Gi
```

The container gets 1 GiB of 2 MiB huge pages. Huge pages are **isolated** — they're not pageable, not swappable, and not shared with the kernel's page cache.

Huge pages require the kubelet to be configured with `--hugepages-2Mi=4` (or similar) on nodes that have the pages. The node advertises the huge pages in `allocatable`.

### 5.2 Extended resources

GPU, FPGA, InfiniBand, etc. — opaque resources reported by device plugins. The Pod requests them by name:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
```

See [[Kubernetes/concepts/L06-scheduling-scaling/14-extended-resources|Extended Resources]] for the full treatment.

### 5.3 The integer rule

Extended resources are **integers only**. You can't ask for "0.5 GPUs". Time-slicing changes this (with time-slicing, the device plugin reports multiple "GPU" units, and the Pod asks for an integer count of those units).

## 6. How Requests Drive Scheduling

The scheduler's `NodeResourcesFit` plugin filters nodes by request sum:

```
For each node N:
  used_cpu = sum(requests.cpu for all Pods on N)
  free_cpu = allocatable.cpu - used_cpu
  if Pod's requests.cpu > free_cpu: drop N
```

The same for memory. The filter is hard — a Pod that doesn't fit is dropped.

### 6.1 The bin-packing math

For a 4-CPU node with `allocatable.cpu: 3800m` (200m reserved):

| Pods on the node | requests.cpu | remaining |
|---|---|---|
| (none) | 0m | 3800m |
| Pod A | 500m | 3300m |
| Pod B | 1000m | 2300m |
| Pod C | 2000m | 300m |
| Pod D (requests 500m) | — | won't fit, dropped |

Pod D is dropped from this node. The scheduler moves to the next node.

### 6.2 Overcommitment

The scheduler uses `requests` for placement, not `limits`. A cluster can have `sum(requests)` > `sum(capacity)` if the apps are bursty.

```
Node: 4 cores
Pod A: requests 1, limits 4
Pod B: requests 1, limits 4
Pod C: requests 1, limits 4
Pod D: requests 1, limits 4
Pod E: requests 1, limits 4

sum(requests) = 5, but only 4 cores
sum(limits) = 20, way over

The scheduler places all 5 (each gets 1 core "guaranteed").
At runtime, the kernel throttles any that try to use more than 1.
```

This is **common and intentional**. Apps burst up to their limits, the kernel enforces. CPU usage averages out below `sum(requests)`.

### 6.3 Memory is not overcommitted

Memory is incompressible. The scheduler enforces `sum(requests) <= capacity`. **A node with 16 GB and 16 GB of requests is full — no more Pods can be scheduled.**

If you have 10 GB of requests and 5 GB free, a Pod asking for 6 GB doesn't fit. The scheduler moves to the next node.

## 7. How Limits Are Enforced at Runtime

### 7.1 CPU: CFS throttling

The kernel's CFS (Completely Fair Scheduler) is configured for the container's cgroup:

* `cpu.cfs_quota_us` — the time the container can use per period.
* `cpu.cfs_period_us` — the period (default 100ms).

The container's "CPU usage" is the sum of its threads' CPU time. If it exceeds the quota in a period, it's throttled until the next period.

```
Period = 100ms
Quota = 50ms (for limits.cpu: 500m, requests.cpu: 100m, on a 1-core node)

Container uses 80ms of CPU in the first 100ms period.
→ Container is throttled for the remaining 20ms.
→ New period starts. Container can use 50ms.
```

Throttling is per-period. The container isn't killed; it just runs slower.

### 7.2 The CFS throttling gotcha

CFS throttling can cause **latency spikes** in CPU-bound apps. A Java app doing GC may spike to 200% CPU for 50ms, get throttled, and have its GC pause extended. The user sees the GC pause as latency.

This is why some teams remove CPU limits entirely. The trade-off:

* With limits: predictable resource use, possible throttling.
* Without limits: possible starvation, no throttling.

### 7.3 Memory: cgroup OOM

The cgroup memory limit triggers a **kernel OOM-kill** when exceeded. The container is killed with SIGKILL (exit code 137).

The kernel's OOM-kill is fast and final. The container's process tree is killed; if there are child processes, they're killed too (unless they escaped the cgroup).

### 7.4 The OOM-kill signals

When the cgroup OOM-kills a container, the kubelet sees the exit and restarts it (per `restartPolicy`). The Pod's events show:

```
Last State:     Terminated
Reason:         OOMKilled
Exit Code:      137
```

`kubectl describe pod` shows this in the container's status.

### 7.5 The `node-level OOM`

If a node's total memory usage exceeds the node's capacity, the **node-level OOM** triggers. The kernel picks a process to kill (usually the largest), which may be a kubelet, a system process, or a container.

Node-level OOMs are bad. The node may become unresponsive. The Pods are rescheduled on other nodes.

To avoid node-level OOM: set `requests` accurately. The scheduler places Pods such that `sum(requests) <= node.allocatable`. The actual usage can burst, but the system can usually handle it.

## 8. QoS Classes in Depth

Every Pod has a **QoS class** based on its resource spec. The class affects **eviction order** when a node is under memory pressure.

### 8.1 Guaranteed

* Every container has `requests == limits` for both CPU and memory.
* Both `requests` and `limits` are set (not just one).
* `requests > 0` for both CPU and memory.

Example:

```yaml
containers:
- name: app
  resources:
    requests: { cpu: 100m, memory: 128Mi }
    limits:   { cpu: 100m, memory: 128Mi }
```

**Guaranteed Pods are evicted last** (after Burstable and BestEffort).

### 8.2 Burstable

* At least one container has a request or limit set.
* Not all containers have `requests == limits`.

Examples:

```yaml
# Burstable: has requests but no limits
containers:
- resources:
    requests: { cpu: 100m, memory: 128Mi }
    # no limits
```

```yaml
# Burstable: requests != limits
containers:
- resources:
    requests: { cpu: 100m, memory: 128Mi }
    limits:   { cpu: 500m, memory: 256Mi }
```

**Burstable Pods are evicted second** (after BestEffort, before Guaranteed).

### 8.3 BestEffort

* No container has any request or limit set.

```yaml
containers:
- name: app
  image: app:1.0
  # no resources
```

**BestEffort Pods are evicted first** when the node is under memory pressure.

### 8.4 The eviction logic

When a node runs out of memory:

1. The kernel starts reclaiming page cache.
2. If still under pressure, the kernel OOM-kills cgroups.
3. The kubelet's `oom_watcher` sees the cgroup OOMs.
4. The kubelet evicts Pods in order: BestEffort, Burstable, Guaranteed.
5. Within a class, the Pod that requested the most memory is evicted first.

**Eviction is in a specific order. QoS class is the dominant factor.**

### 8.5 QoS and the scheduler

The scheduler **does not** consider QoS for placement. A Burstable Pod and a Guaranteed Pod are placed the same way (based on `requests`). The QoS class only matters at eviction time.

## 9. The Init Container Scheduling Footgun

Init containers run **before** the main container. The scheduler uses **the highest request of any init container or the main container** for placement.

```yaml
spec:
  initContainers:
  - name: migrate
    image: migrate:1.0
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
  containers:
  - name: app
    image: app:1.0
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
```

This Pod is scheduled as if it needs 500m CPU and 1 GiB memory (the init container's request, which is higher than the main container's).

**The init container only runs once at startup. The Pod's runtime usage is the main container's.** But the scheduler uses the init's request for placement. This is correct behavior — you need the resources to run the init — but it can lead to "wasted" scheduling slots if the init is a one-time heavy task.

### 9.1 The fix

If the init container is one-time heavy, consider:

* Running the migration in a separate Job, not as an init container.
* Using a smaller init container (do the heavy work in a separate step).
* Or: accept the over-allocation. The node is "using" those resources during init, then they're free during runtime.

## 10. LimitRange — Defaults and Constraints

LimitRange is the **namespace-level mechanism** for setting defaults and constraints on Pods and Containers.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
  namespace: prod
spec:
  limits:
  - type: Container
    default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    max:
      cpu: "2"
      memory: 4Gi
    min:
      cpu: 100m
      memory: 128Mi
```

* **`default`** — applied if the Container doesn't set `limits`.
* **`defaultRequest`** — applied if the Container doesn't set `requests`.
* **`max`** — hard cap. Pods that exceed are rejected.
* **`min`** — hard floor. Pods that don't meet are rejected.

See [[Kubernetes/concepts/L05-config-storage/08-resource-quota|ResourceQuota]] for the full treatment.

## 11. Pod-Level Resources (k8s 1.34+)

A newer feature (currently in alpha/beta as of 1.30) lets you set resources at the **Pod** level, not per-container:

```yaml
apiVersion: v1
kind: Pod
spec:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1
      memory: 2Gi
  containers:
  - name: app
    image: app:1.0
```

The Pod-level resources define the **total** across all containers. The per-container resources are still honored, but the Pod's `resources` field is the overall cap.

This is useful for:

* **ResourceQuota constraints** — a quota on `requests.cpu` checks the Pod's total, not the per-container sum.
* **VPA recommendations** — VPA in `Pod` mode recommends at the Pod level, not per-container.
* **Multi-container Pods** — clear, total budgets.

As of 1.30, this is in beta. Adoption is early.

## 12. The "No Limits" Debate in Depth

Some teams run with no CPU limits. The argument:

* **Throttling hurts latency.** A CPU limit causes throttling. For latency-sensitive apps (search, ML serving), the throttling is the bottleneck. Removing the limit removes the throttling.
* **The scheduler is enough.** With `requests` set, the scheduler places Pods such that `sum(requests) <= capacity`. A misbehaving app can still spike, but the average case is fine.
* **CFS is conservative.** The kernel's CFS throttling is per-period, not per-second. A 100ms period with 50% quota means the container is throttled 50ms every 100ms. That's noticeable.

The argument for limits:

* **Predictability.** With limits, you know each container is capped.
* **Multi-tenancy safety.** In a shared cluster, a misbehaving app can't starve neighbors.
* **ResourceQuota safety.** Quotas are about `requests`, not limits. But a runaway container can still OOM-kill a node.

The k8s official position is **set both**. The reality is more nuanced:

* **Latency-critical apps** (search, ML serving) — no CPU limits, just requests. Burstable.
* **General services** — set both. Burstable.
* **Critical services** — set `requests == limits`. Guaranteed.
* **Background / batch** — no limits or high limits. Burstable.

**Tune with VPA** in `recommend` mode to get data-driven values.

## 13. Cgroup v1 vs cgroup v2

k8s supports both cgroup v1 and cgroup v2. The difference matters for resource isolation.

### 13.1 cgroup v1 (legacy)

* Separate cgroup hierarchies for CPU, memory, blkio, etc.
* Resource limits set per-hierarchy.
* More compatible with older kernels.
* Less efficient — the kernel has to coordinate across hierarchies.

### 13.2 cgroup v2 (modern, k8s 1.25+ default)

* Unified hierarchy. All controllers under one tree.
* More efficient — the kernel can coordinate resource pressure.
* **Required for some features** (e.g. PSI — Pressure Stall Information).
* Default on new clusters since 1.25.

### 13.3 The migration

Most modern distros (kubeadm, EKS, GKE) use cgroup v2 by default. If you have an old cluster on cgroup v1, you can:

* Set `--cgroup-driver=cgroupfs` (v1) or `systemd` (v2).
* Migrate by draining nodes, switching the cgroup driver, rejoining.

**The kubelet's cgroup driver must match the container runtime's.** Docker uses `cgroupfs`, containerd uses `systemd` (typically). Mismatches cause Pods to fail.

### 13.4 cgroup v2 and resource isolation

cgroup v2 has better memory isolation — the kernel can throttle or kill a process based on memory pressure more accurately. cgroup v1 has more edge cases where a container can OOM the node.

## 14. In-Place Pod Resize (k8s 1.33+)

A newer feature (alpha in 1.33) lets you **resize a Pod's resources without restarting it**:

```bash
# patch the Pod to change resources
kubectl patch pod <pod> -p '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"500m"}}}]}}'
```

The kubelet updates the cgroup without restarting the container. **The container doesn't see the change** (no SIGTERM, no restart), but the cgroup's CPU/memory quota is updated.

This is useful for:

* **VPA in `Auto` mode** — VPA can resize without a Pod restart.
* **HPA + custom metrics** — the HPA controller can also tune requests (k8s 1.27+ feature).
* **Operational tuning** — change limits without downtime.

As of 1.33, this is in alpha. Check the feature gate (`InPlacePodVerticalScaling`).

## 15. Operations and Debugging

### 15.1 Common commands

```bash
# check a Pod's requests and limits
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].resources}'
kubectl describe pod <pod>

# check QoS class
kubectl get pod <pod> -o jsonpath='{.status.qosClass}'

# check actual usage
kubectl top pod <pod>
# requires metrics-server

# check a node's allocatable
kubectl describe node <node>
# look at "Allocatable" and "Allocated resources"

# check the cgroup on a node
# (on the node)
cat /sys/fs/cgroup/cpu,cpuacct/kubepods/pod<uid>/cpu.cfs_quota_us
cat /sys/fs/cgroup/cpu,cpuacct/kubepods/pod<uid>/cpu.cfs_period_us
```

### 15.2 The "Pod is Pending" — too few resources

```bash
kubectl describe pod <pod>
# look at events: "Insufficient cpu", "Insufficient memory"
# the scheduler is reporting that no node has enough free resources

# fix:
# - reduce the Pod's requests
# - add a node (CA / Karpenter)
# - reduce other Pods' requests
# - check if a node is being held by a "stuck" Pod
```

### 15.3 The "Pod is being OOM-killed" case

```bash
kubectl describe pod <pod>
# look at "Last State" of the container
# Reason: OOMKilled
# Exit Code: 137

# fix:
# - raise the memory limit
# - fix the memory leak
# - lower the JVM heap if it's a Java app
# - check if the cgroup is reporting correctly
```

### 15.4 The "node is under pressure, evicting Pods" case

```bash
kubectl describe node <node>
# look at "Conditions"
# MemoryPressure: True
# DiskPressure: True

# see which Pods are being evicted
kubectl get pods -A --field-selector spec.nodeName=<node>

# fix:
# - raise the node's capacity
# - move Pods to other nodes
# - delete the Pods that are using the most memory (BestEffort first, then Burstable)
```

## 16. Gotchas and Common Mistakes

### 16.1 The 30+ common mistakes

1. **`requests` are what matters for scheduling. `limits` don't affect scheduling** (except for memory, indirectly via QoS and pressure).

2. **CPU limits cause throttling, which can hurt latency-sensitive apps.** A Java app with `cpu: 500m` will get throttled under bursty load. Either raise the limit or set it equal to requests.

3. **Memory limits are dangerous if too low.** A JVM that hits its memory limit will OOM-kill, then restart, then OOM-kill, then restart — a crashloop. Either set limits to what the app actually needs, or use VPA in `recommend` mode.

4. **Setting limits without requests is a misconfig.** You get Burstable QoS but the scheduler has no information about how to place the Pod. The Pod may land on a node that can't actually accommodate its needs.

5. **`100m` is a small amount.** A Node.js app doing real work usually wants 250-1000m. A JVM at startup can easily use 1+ core. Don't go too low just to "fit more Pods per node".

6. **The kubelet reserves system resources** (kernel, kubelet, container runtime). A 4-vCPU node doesn't have 4000m available — it has something like 3800m. Check with `kubectl describe node`.

7. **HPA uses `requests` as the denominator.** If you set `cpu: 100m` requests and the Pod is using 200m, HPA sees "200% of target" and scales. Setting requests correctly is critical for HPA to work.

8. **A Pod that exceeds its memory limit is OOM-killed, the container restarts, the Pod stays.** The Pod is "Running" but the container is crashlooping. This is "the app died" not "the node died" — useful for alerting, but the Pod is still `Running`.

9. **`ephemeral-storage` requests/limits** also exist (k8s 1.10+). For the container's writable layer + logs. Defaulted to node capacity. Set them to avoid filling the node disk.

10. **The `MemoryPressure` condition is not the same as memory exhaustion.** It triggers when the node's memory usage is high. Pods can be evicted in anticipation of OOM, not just at OOM.

11. **JVM apps need `-Xmx` to be less than the memory limit.** With cgroup memory accounting, the heap is reserved, even if not used. A 1 GB heap + 256 MB non-heap = at least 1.25 GB limit.

12. **Go apps don't release memory to the OS** by default. The Go runtime holds onto memory even after the heap shrinks. Set `GOMEMLIMIT` (Go 1.19+) or `GOGC` to control this.

13. **Time-slicing on GPUs is not isolation.** Two Pods on the same time-sliced GPU share the GPU's memory. For ML training, this can cause OOM. Use MIG or separate GPUs.

14. **The `node-level OOM` is rare but devastating.** If a node's total memory usage exceeds its capacity, the kernel kills the largest process. The node may go unresponsive. Avoid by setting `requests` accurately.

15. **The QoS class is determined by the Pod spec, not by usage.** A Pod with no requests is BestEffort, even if it actually uses a lot of memory. The class only matters for eviction, not for resource use.

16. **The `requests.cpu` of the init container is used for placement**, not the main container's. A heavy init container (e.g. database migration) reserves resources for the Pod's whole life.

17. **The `ephemeral-storage` limit includes `emptyDir` volumes** in the container's spec. A 5 GB `emptyDir` limit applies to all `emptyDir` mounts in the container.

18. **The kubelet reserves some memory for itself** (e.g. 1 GB). A 16 GB node may have `allocatable.memory: 15 GB`. Don't assume the full node capacity is available.

19. **HPA's `averageUtilization` is the average across all Pods in the target.** A Deployment with 10 Pods, 5 hot and 5 idle, is 50% utilized on average — HPA doesn't scale.

20. **VPA's recommendation is the 95th percentile of usage.** It doesn't consider the limit. If your usage is bursting to 100% of limit, VPA may not catch it (depending on the percentile window).

21. **The `memory.requests` in a Pod is honored on a node that's under pressure.** A node with `MemoryPressure: True` may evict BestEffort Pods first, then Burstable, then Guaranteed. The order is by `requests.memory`.

22. **The kubelet's cgroup driver and the container runtime's cgroup driver must match.** A mismatch causes Pods to fail to start with cryptic errors.

23. **A LimitRange's `default` is the limit, not the request.** If you set `default: { cpu: 500m }` and the Pod doesn't set `limits.cpu`, it gets 500m as the limit. The `defaultRequest` is the request.

24. **The `requests.cpu` doesn't guarantee the Pod will get that much CPU at any moment.** The scheduler reserves it, but a busy node may not deliver it. CPU is a best-effort resource at the kernel level.

25. **A Pod with `requests.cpu: 0` is a special case.** The scheduler doesn't reserve CPU. The container is Burstable. Useful for low-priority background tasks.

26. **The `cpu.cfs_period_us` is 100ms by default.** A 100ms period with a 50ms quota = the container can use 50ms of CPU per 100ms. Adjustable per cgroup.

27. **Memory QoS** is a cgroup v2 feature (k8s 1.22+). It uses `memory.high` and `memory.max` to throttle the cgroup before OOM-killing. A Burstable Pod in cgroup v2 may be throttled before being killed.

28. **The `Burstable` QoS Pod with high `limits` is not the same as a `Guaranteed` Pod with high requests.** Both have headroom, but Guaranteed is evicted last.

29. **The kubelet's `--enforce-node-allocatable` flag controls whether the kubelet reserves resources from the node's capacity.** Default is to reserve.

30. **ResourceQuota and LimitRange are different.** ResourceQuota is namespace-level aggregate. LimitRange is per-object defaults/constraints. Set both in production.

## See also

* [[Kubernetes/concepts/L05-config-storage/08-resource-quota|ResourceQuota]] — namespace-level aggregates
* [[Kubernetes/concepts/L06-scheduling-scaling/06-restart-policy|Restart Policy]] — what happens when a container OOM-kills
* [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] — uses requests as the baseline
* [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler|VPA]] — tunes requests automatically
* [[Kubernetes/concepts/L06-scheduling-scaling/14-extended-resources|Extended Resources]] — GPU and other opaque resources

---
title: Performance Tuning
tags:
  - Kubernetes
  - Non-Functional
  - Performance
  - Tuning
---

A slow cluster usually isn't slow because of k8s — it's slow because the apps are over-provisioned, under-provisioned, or fighting the scheduler. This note covers the practical levers to make workloads fast.

## The 4 resources

Every container has four resources to tune:

1. **CPU** — request (used for scheduling) and limit (throttling)
2. **Memory** — request (used for scheduling) and limit (OOM kill)
3. **Ephemeral storage** — `/tmp`, container layers, working directory
4. **Network** — implicit, but can be a bottleneck

```
┌────────────────────────────────────────────────────┐
│ Container                                          │
│                                                    │
│  requests:    "guaranteed"    scheduling unit      │
│  limits:      "ceiling"       runtime cap          │
│                                                    │
│  CPU:                                                   │
│    request = scheduler reserves this                                 │
│    limit = throttled to this (or unlimited)              │
│                                                    │
│  Memory:                                                │
│    request = scheduler reserves this                   │
│    limit = OOM kill if exceeded                        │
│                                                    │
└────────────────────────────────────────────────────┘
```

## The QoS classes

Kubernetes assigns pods to one of three QoS classes based on requests and limits. This affects scheduling and eviction behavior.

| QoS class | When assigned | Eviction order |
|-----------|--------------|----------------|
| **Guaranteed** | requests == limits (both CPU and memory) | Last |
| **Burstable** | requests < limits, or only one is set | Middle |
| **BestEffort** | No requests, no limits | First |

**Guaranteed** pods are the most stable but most expensive. They get scheduled onto dedicated resources and are last to be evicted under pressure.

**Burstable** is the default for most production apps. They get scheduled on shared resources and can burst to their limits.

**BestEffort** is rarely used in production — pods can use any available resource, but get killed first.

```yaml
# Guaranteed
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 512Mi

# Burstable
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 1
    memory: 1Gi

# BestEffort
# no resources block
```

**Best practice for production:** requests are mandatory, limits are usually set but higher than requests (Burstable). Guaranteed is for latency-sensitive, predictable workloads.

## CPU: the four configurations

### Configuration 1: No requests, no limits (BestEffort)

```yaml
# Don't do this in production
containers:
- name: web
  image: myorg/web:v1
```

The pod uses whatever's free. Under load, it can use the whole node. Under pressure, it's killed first.

### Configuration 2: Requests, no limits

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  # no limits
```

The pod is scheduled based on 500m CPU. It can use more if available, no upper cap. Common for CPU-bound batch jobs.

### Configuration 3: Requests < limits (Burstable, default)

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1
    memory: 1Gi
```

Scheduled based on 500m, can burst to 1 CPU. Standard for most production apps.

### Configuration 4: Requests == limits (Guaranteed)

```yaml
resources:
  requests:
    cpu: 1
    memory: 1Gi
  limits:
    cpu: 1
    memory: 1Gi
```

No throttling, no OOM risk. Most expensive, most predictable.

## CPU throttling

The Linux kernel's CFS (Completely Fair Scheduler) throttles containers that exceed their CPU limit. Throttling is **silent** — the app just runs slower.

**Symptoms:**

```bash
# high CPU throttling on the container
$ rate(container_cpu_cfs_throttled_seconds_total[5m])
# 0.45   <-- 45% of CPU periods are throttled
```

**Common causes:**

1. **CPU limit too low.** App legitimately needs more.
   ```bash
   $ kubectl top pod web-1
   # CPU: 980m  (limit was 1, app is hitting it)
   ```
   Fix: increase the limit, or set `Burstable: requests < limits`.

2. **Multi-threaded app with one core limit.** A Java app with 16 threads on a 1-CPU pod thrashes.
   Fix: set CPU limit = expected concurrent threads.

3. **GC or other periodic CPU spikes.** The JVM or runtime has periodic CPU bursts.
   Fix: set requests/limits to accommodate bursts.

**CPU limit anti-pattern:** setting CPU limits too aggressively is a common cause of mysterious slowness. Some teams run **without CPU limits** entirely (Burstable with no CPU limit) and let the kernel CFS handle it without explicit throttling.

## Memory: OOMKilled

Memory is different from CPU — there's no throttling, just OOM kill. If a pod exceeds its memory limit, the kernel kills it (OOMKilled).

**Symptoms:**

```bash
$ kubectl describe pod web-1 | tail -10
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

**Common causes:**

1. **Memory limit too low.** App needs more.
2. **Memory leak.** App allocates more over time, never frees.
   ```bash
   # monitor memory over time
   $ watch -n 5 'kubectl top pod web-1'
   # if memory keeps growing, leak
   ```
3. **Spike during startup.** App uses a lot of memory during init, settles down.
   ```bash
   # check if startup memory is high
   $ kubectl top pod web-1 --containers
   # if startup memory > steady-state, request = steady-state, limit = startup
   ```
4. **JVM heap misconfigured.** JVM's `-Xmx` is bigger than the container limit.
   ```bash
   # JVM's max heap is 1/4 of host memory by default
   # if container limit is 1Gi but host is 64Gi, JVM tries to use 16Gi
   ```

**Fix patterns:**

- Set the limit above the steady-state usage, but below the OOM risk
- For JVMs, set `-Xmx` explicitly (e.g., `-Xmx400m` for a 512Mi limit)
- For leaks, fix the leak
- For startup spikes, set limit to startup, request to steady-state

## Memory QoS subtleties

Linux has two memory limits: **cgroup limit** (the k8s memory.limit_in_bytes) and **cgroup request** (memory.low or memory.min). K8s uses different sub-cgroups for different QoS classes:

- **Guaranteed** — memory.min is set (reserved)
- **Burstable** — memory.low is set (best-effort reservation)
- **BestEffort** — no reservation

**What this means:** BestEffort pods are the first to be killed under memory pressure. Burstable pods are second. Guaranteed pods are last.

**For predictable performance:** run critical pods as Guaranteed, or as Burstable with high `requests.memory`.

## Ephemeral storage

The `/tmp`, container layers, and working directory on the node's disk. If a pod fills this, the kubelet evicts it.

**Symptoms:**

```bash
$ kubectl describe pod web-1 | tail
Last State:     Terminated
  Reason:       Error
  Message:      container exceeded its ephemeral storage limit
```

**Common causes:**

1. **Log files in `/tmp` or stdout.** Apps that write verbose logs.
2. **Image layers.** Old images not garbage collected.
3. **Working directory data.** Apps that write to their CWD.

**Fix:**

```yaml
resources:
  requests:
    ephemeral-storage: 1Gi
  limits:
    ephemeral-storage: 2Gi
```

Or set node-level ephemeral storage reservation. Or use a PVC for actual data, ephemeral storage for caches only.

## Network performance

K8s itself doesn't tune the network, but there are k8s-aware patterns:

- **CNI choice matters.** Cilium (eBPF) is generally faster than Flannel (VXLAN). Calico is in between.
- **Service mesh overhead.** Istio's sidecar adds latency (~1-2ms per hop). Linkerd is lighter.
- **Cross-AZ traffic.** Pod in zone A talking to pod in zone B incurs inter-AZ latency (~1-2ms) and **egress cost**. Topology spread to keep traffic in-zone.

```yaml
# topology spread for low-latency
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app: web
```

## JVM-specific tuning

JVMs need explicit tuning for containers. The default behavior is wrong for k8s.

```yaml
env:
- name: JAVA_OPTS
  value: >-
    -XX:+UseContainerSupport
    -XX:MaxRAMPercentage=75.0
    -XX:+ExitOnOutOfMemoryError
    -XX:+HeapDumpOnOutOfMemoryError
    -XX:HeapDumpPath=/tmp/heapdump.hprof
    -Xss512k
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2
    memory: 2Gi
```

- `MaxRAMPercentage=75` — JVM uses 75% of container memory for heap. The other 25% is for non-heap (metaspace, threads, code cache).
- `UseContainerSupport` — JVM respects cgroup limits (default in Java 11+).
- `ExitOnOutOfMemoryError` — exit cleanly on OOM (lets the kubelet restart you).
- `HeapDumpOnOutOfMemoryError` — captures the heap state for postmortem.

## Node-level tuning

The node's kernel and container runtime have settings that affect performance.

### Kernel parameters (sysctl)

```yaml
# pod spec (privileged) or via node-level config
securityContext:
  sysctls:
  - name: net.core.somaxconn
    value: "65535"
  - name: net.ipv4.tcp_max_syn_backlog
    value: "65535"
  - name: vm.swappiness
    value: "1"
```

Or at the node level via kubelet config.

### Container runtime

```toml
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "registry.k8s.io/pause:3.9"
  max_container_log_line_size = 16384
```

### Disk performance

- **Use local NVMe for high-IO workloads** (caching, databases that need fast disk)
- **Network-attached storage (EBS, GCE PD) has latency.** gp3 has 125-1000 IOPS, 125-1000 MB/s. For higher, use io2.
- **Avoid PVCs on busy nodes.** EBS volumes have per-instance limits (28 by default on AWS).

## Application-level performance

Beyond k8s, the application itself is usually the bottleneck.

### Profiling

- **CPU profiling** — `perf`, async-profiler (Java), pprof (Go), py-spy (Python)
- **Memory profiling** — heap dumps, jemalloc stats, valgrind
- **Distributed tracing** — Jaeger, Zipkin, Tempo. Show which span is slow.

### Common app-level issues

1. **Synchronous calls in hot path.** A web request makes 5 database calls, each 100ms. Total 500ms. Cache or batch.
2. **Connection pool starvation.** App has 10 DB connections, 100 concurrent requests, everyone waits.
3. **Lock contention.** Shared lock across all requests. Move to per-key locks, or no locks.
4. **Garbage collection pauses.** JVM can pause for seconds. Tune GC, use G1/ZGC/Shenandoah.
5. **Slow external dependencies.** Calling out to 3rd party APIs that take 1s each.

## The "is it the app or the platform?" test

```bash
# 1. is CPU saturated?
kubectl top pod web-1
# CPU: 1000m (maxed out)

# 2. is memory OK?
kubectl top pod web-1
# MEMORY: 500Mi (plenty of headroom)

# 3. is the node OK?
kubectl describe node node-1 | grep -A 5 "Allocated resources"
# CPU Requests:    30 cores (60% used)
# Memory Requests: 60Gi (50% used)

# 4. is the app slow even when not under load?
# (in staging, with no traffic, hit it directly)
kubectl port-forward pod/web-1 8080:8080
ab -n 1000 -c 10 http://localhost:8080/
# requests per second, latency

# 5. compare with another pod
# (do the same test on a different pod, see if it's specific)
```

## Latency tuning

For latency-sensitive services, every millisecond matters.

**Levers:**

- **CPU pinning** (static CPU manager policy) — pod gets dedicated cores, no scheduling noise
  ```yaml
  # kubelet config
  cpuManagerPolicy: static
  ```
  ```yaml
  # pod
  resources:
    requests:
      cpu: 4
  # pod gets 4 dedicated cores
  ```

- **Pod QoS = Guaranteed** — no throttling, no eviction
- **Topology spread** — keep traffic in-zone
- **Local node for caches** — use `nodeAffinity` to pin cache pods to specific nodes
- **Disable swap** — swap adds latency, and kubelet doesn't support it well

## Throughput tuning

For high-throughput services, parallelism matters more than per-request latency.

**Levers:**

- **HPA scale-out** — more replicas, more concurrent requests
- **Bigger nodes** — fewer cross-node communications
- **Connection pool sizing** — per-pod, sized for expected concurrency
- **Async processing** — push work to queues, process in batches

## Profiling at the k8s layer

### eBPF tools

Modern observability tools use eBPF for deep visibility:

- **Pixie** (`px.dev`) — New Relic's eBPF-based k8s observability
- **Parca** — continuous profiling
- **Cilium's Hubble** — network observability
- **Inspektor Gadget** — k8s debugging toolkit

```bash
# install Pixie
bash -c "$(curl -fsSL https://withpixie.ai/get-pixie.sh)"

# list running processes and their resources
px run px/host

# profile a specific service
px run px/profile -n my-ns --service web
```

### perf for node-level

```bash
ssh node-1
$ perf top
# see what's consuming CPU on the node
```

## Common gotchas

* **`requests.cpu: 0` (or no requests)** means the scheduler can pack pods unlimited onto a node. Under load, the node thrashes.
* **Memory limit too high** doesn't hurt much. Memory limit too low causes OOM. Err on the side of higher.
* **CPU limit too high** doesn't hurt much. CPU limit too low causes throttling. Err on the side of higher.
* **JVMs default to 1/4 host memory for heap.** On a 64Gi node, a 1Gi container limit, the JVM tries 16Gi heap. Set `-Xmx` explicitly.
* **Java 8 needs `-XX:+UseContainerSupport`** to respect cgroup limits. Java 11+ has it on by default.
* **Go programs don't GC-limit well** by default. Set `GOMEMLIMIT` (Go 1.19+).
* **Don't set requests too high "for safety."** Over-provisioning wastes resources.
* **The scheduler only knows requests.** If your app uses 1 CPU but requests 2, the scheduler thinks you need 2x what you do.
* **CPU throttling is silent.** You can be throttled and never see an error.
* **Memory pressure on a node** causes kubelet to evict pods, even BestEffort ones. Guaranteed pods are last to go.
* **`cpuManagerPolicy: static`** is a kubelet setting, not a pod setting. It affects all pods on the node.
* **The HPA and VPA both need requests to work.** Set them.
* **`topology.kubernetes.io/region` and `topology.kubernetes.io/zone`** are the standard labels, but they're populated by the cloud provider. Self-managed clusters may not have them.

## A worked example

App: Java Spring Boot web service, processing payments.

**Problem:** P99 latency 1.5s, occasionally 5s. Spikes correlated with GC.

```bash
$ kubectl logs -l app=payments | grep "GC pause"
[GC (Allocation Failure) 524288K->262144K(524288K), 0.345 secs]
[GC (G1 Evacuation Pause)  1G->512M(1G), 5.123 secs]   <-- 5 second pause
```

5-second GC pause = the entire pod is unresponsive for 5 seconds.

**Diagnosis:**

```bash
# 1. check current resource config
$ kubectl get pod -o jsonpath='{.spec.containers[0].resources}' | jq .
{
  "limits": {
    "memory": "2Gi"
  }
  # no requests, no CPU limit
}

# 2. JVM options
$ kubectl exec payments-1 -- env | grep JAVA
JAVA_OPTS=-Xmx1500m   <-- but cgroup is 2Gi, JVM tries 1.5Gi
```

**Issues:**
- No requests — scheduler can over-pack
- No CPU limit — fine, but no throttling means GC isn't CPU-constrained
- JVM heap = 1.5Gi, but cgroup is 2Gi, no headroom for non-heap

**Fix:**

```yaml
env:
- name: JAVA_OPTS
  value: >-
    -XX:+UseG1GC
    -XX:MaxRAMPercentage=70.0
    -XX:+ExitOnOutOfMemoryError
resources:
  requests:
    cpu: 1
    memory: 1.5Gi     # 1.5Gi: realistic steady-state
  limits:
    cpu: 2
    memory: 2Gi       # 2Gi: allows headroom
```

**Result:** P99 latency drops to 200ms. GC pauses still happen but are <100ms.

## See also

* [[Kubernetes/guides/non-functional/auto-scaling|auto-scaling]] — HPA on resources
* [[Kubernetes/guides/non-functional/cost-optimization|cost-optimization]] — right-sizing is cost
* [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] — OOMKilled diagnostics

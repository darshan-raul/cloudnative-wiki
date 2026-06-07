# Resource Requests and Limits

*"https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/"*

Each container can declare how much **CPU and memory** it needs. Two numbers:

* **`requests`** — what the container is **guaranteed**. Used by the scheduler to find a node with enough capacity.
* **`limits`** — the **maximum** the container is allowed to use. Enforced at runtime.

```yaml
spec:
  containers:
  - name: app
    image: app:1.0
    resources:
      requests:
        cpu: 100m          # 0.1 CPU
        memory: 128Mi
      limits:
        cpu: 500m          # 0.5 CPU
        memory: 256Mi
```

## CPU

* Measured in **millicores** (m) or full cores (`1` = 1 core, `500m` = half a core, `100m` = 1/10th)
* **Compressible** — when the container exceeds its CPU limit, it's throttled, not killed
* 1 AWS vCPU = 1 k8s core = 1000m

## Memory

* Measured in bytes / Ki / Mi / Gi
* **Incompressible** — when the container exceeds its memory limit, it's OOM-killed
* Memory limits also count the page cache — set them carefully, you can OOM-kill a container that "isn't using" that much memory

## How requests are used at scheduling time

The scheduler does a **bin-packing** calculation:

* Total node CPU = `node.status.allocatable.cpu`
* Sum of `requests.cpu` of all Pods already on the node must be ≤ that
* Same for memory

If a Pod's requests can't fit on any node, it stays `Pending`.

## How limits are enforced at runtime

* **CPU limit exceeded** — kernel CFS throttles the container; it can still run, just slower
* **Memory limit exceeded** — the container is OOM-killed (exit code 137)
* **No limit set** — the container can use all the node's resources (subject to the node's capacity). **Bad practice.**

## QoS classes

K8s assigns each Pod a **Quality of Service class** based on its resource spec:

* **Guaranteed** — every container has `requests == limits` for both CPU and memory. Last to be evicted.
* **Burstable** — at least one container has requests or limits set, but not all are equal. Middle priority.
* **BestEffort** — no requests or limits set on any container. **First to be evicted** when the node is under pressure.

```bash
kubectl get pod -o jsonpath='{.items[*].status.qosClass}'
```

QoS class also affects the **eviction order** when a node is under memory pressure. `BestEffort` Pods die first.

## The LimitRange default

A LimitRange in a namespace can **set defaults** for containers that don't specify their own:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
spec:
  limits:
  - type: Container
    default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
```

Useful to prevent "BestEffort by accident" — every Pod in the namespace gets a baseline.

## Gotchas

* **`requests` are what matters for scheduling. `limits` don't affect scheduling** (except for `memory` in some cases via the `MemoryPressure` condition).
* **CPU limits cause throttling, which can hurt latency-sensitive apps.** A Java app with `cpu: 500m` will get throttled under bursty load. Either raise the limit or set it equal to requests.
* **Memory limits are dangerous if too low.** A JVM that hits its memory limit will OOM-kill, then restart, then OOM-kill, then restart — a crashloop. Either set limits to what the app actually needs, or use VPA (see L06 scaling).
* **Setting limits without requests is a misconfig.** You get the QoS class "Burstable" but the scheduler has no information about how to place the Pod.
* **`100m` is a small amount.** A Node.js app doing real work usually wants 250-1000m. A JVM at startup can easily use 1+ core. Don't go too low just to "fit more Pods per node".
* **The kubelet reserves system resources** (kernel, kubelet, container runtime). A 4-vCPU node doesn't have 4000m available — it has something like 3800m. Check with `kubectl describe node`.
* **HPA uses requests as the denominator.** If you set `cpu: 100m` requests and the Pod is using 200m, HPA sees "200% of target" and scales. Setting requests correctly is critical for HPA to work.
* **A Pod that exceeds its memory limit is OOM-killed, the container restarts, the Pod stays.** This is "the app died" not "the node died" — useful for alerting, but the Pod is still `Running`.
* **`ephemeral-storage` requests/limits** also exist (k8s 1.10+) — for the container's writable layer + logs. Defaulted to node capacity. Set them to avoid filling the node disk.

## The "no limits" debate

Some teams run with no CPU limits (only requests) and argue it's the only way to get good latency. Others set `requests == limits` for predictability. The k8s recommendation is to set both. If you're not sure, set both with a sensible value, and tune over time using metrics from your HPA / VPA.

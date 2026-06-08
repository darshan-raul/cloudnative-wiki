# HorizontalPodAutoscaler (HPA)

*"https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/"*

The HorizontalPodAutoscaler (HPA) automatically scales the **number of Pod replicas** in a Deployment, StatefulSet, ReplicaSet, or similar controller, based on observed metrics (CPU, memory, custom, external). It's the **workhorse of k8s autoscaling** — most production clusters have multiple HPAs. HPA is a **control loop** that runs every `--horizontal-pod-autoscaler-sync-period` (default 15s).

### Table of Contents

1. [What HPA Solves](#1-what-hpa-solves)
2. [The HPA Control Loop](#2-the-hpa-control-loop)
3. [Basic Example (CPU)](#3-basic-example-cpu)
4. [The Scaling Formula](#4-the-scaling-formula)
5. [Resource Metrics in Detail](#5-resource-metrics-in-detail)
6. [Container and Pod Metrics](#6-container-and-pod-metrics)
7. [Custom Metrics (v2 API)](#7-custom-metrics-v2-api)
8. [External Metrics](#8-external-metrics)
9. [Behavior Settings in Depth](#9-behavior-settings-in-depth)
10. [Stabilization Windows](#10-stabilization-windows)
11. [Scaling Policies Math](#11-scaling-policies-math)
12. [The HPA Controller and Metrics Pipeline](#12-the-hpa-controller-and-metrics-pipeline)
13. [Min Replicas, Max Replicas, Scale to Zero](#13-min-replicas-max-replicas-scale-to-zero)
14. [HPA on StatefulSets and Other Controllers](#14-hpa-on-statefulsets-and-other-controllers)
15. [HPA + VPA + Karpenter Combinations](#15-hpa--vpa--karpenter-combinations)
16. [Operations and Debugging](#16-operations-and-debugging)
17. [Gotchas and Common Mistakes](#17-gotchas-and-common-mistakes)

---

## 1. What HPA Solves

Replicas in a Deployment are a static number — `spec.replicas: 3`. But the load on the Deployment varies. HPA **changes the replica count in response to a metric**.

```
Static replicas:
   9am: 3 replicas, 80% CPU each
   10am: 3 replicas, 95% CPU each  ← overloaded
   11am: 3 replicas, 30% CPU each  ← wasted

With HPA on CPU (target 60%):
   9am: 3 replicas, 80% CPU each
   10am: HPA scales to 5 replicas, 60% CPU each
   11am: HPA scales to 2 replicas, 60% CPU each
```

HPA's goal is to **keep the metric at the target**, by adding or removing replicas. The metric can be CPU, memory, custom (e.g. queue depth), or external (e.g. Kafka lag via KEDA).

### 1.1 HPA is for replicas, not size

HPA changes **how many** Pods run. It does NOT change **how big** each Pod is. For resizing individual Pods, use [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler|VPA]].

The two are complementary but **don't use both on the same metric** — they fight.

## 2. The HPA Control Loop

```
HPA controller (in cluster, kube-system or custom)
       │
       │  Every --horizontal-pod-autoscaler-sync-period (default 15s):
       │
       ▼
   1. List all HPA objects
   2. For each HPA:
       a. Get the current replica count (from the controller)
       b. Query the metric (Resource / Pod / Object / External)
       c. Compute desiredReplicas
       d. If desiredReplicas != current, update the controller
   3. The controller (Deployment etc.) converges to the new count
```

The HPA controller is in `kube-controller-manager` (built-in) or a separate Deployment (custom). It watches the apiserver for HPA and target objects.

### 2.1 The sync period

`--horizontal-pod-autoscaler-sync-period` controls how often the HPA evaluates. Default 15s. Lower = faster reaction but more API load. Higher = slower reaction.

For latency-sensitive scaling, 5-10s. For most workloads, 15s is fine.

## 3. Basic Example (CPU)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
```

This HPA:

* Targets the `web` Deployment.
* Scales between 2 and 10 Pods.
* Tries to keep average CPU utilization at 60% of `requests.cpu`.

### 3.1 What "Utilization" means

`type: Utilization` means: **metric value / request value**.

For a Pod with `requests.cpu: 200m` using 180m of CPU, utilization is 180 / 200 = 90%. If `target.averageUtilization: 60`, this Pod is over target.

**Without `requests` set, the HPA can't compute utilization** — the metric has no baseline.

## 4. The Scaling Formula

```
desiredReplicas = ceil(currentReplicas * currentMetricValue / targetMetricValue)
```

For the example above:

* `currentReplicas: 3`
* `currentMetricValue: 90%` (average across Pods)
* `targetMetricValue: 60%`

```
desiredReplicas = ceil(3 * 90 / 60) = ceil(4.5) = 5
```

The HPA scales to 5 Pods.

### 4.1 Different metric types

| Metric type | Formula |
|---|---|
| `Utilization` | `currentReplicas * (currentUtilization / targetUtilization)` |
| `AverageValue` | `currentReplicas * (currentAverage / targetAverage)` |
| `Value` | One value per target, scaled directly |
| `AverageUtilization` | Same as `Utilization` (alias in v1) |

For `Utilization`, the metric is a fraction (0-100) of `requests`. For `AverageValue`, the metric is in raw units (e.g. "1k requests per second").

### 4.2 The ceiling

The HPA scales to `min(ceil(formula), maxReplicas)`. If the formula says 100, but `maxReplicas: 20`, the HPA scales to 20. The metric will be at 5x target (e.g. 300% CPU if target was 60%).

**`maxReplicas` is a ceiling, not a guarantee.**

## 5. Resource Metrics in Detail

Resource metrics are **CPU and memory** — the standard k8s resource metrics. They're served by **metrics-server**.

```yaml
metrics:
- type: Resource
  resource:
    name: cpu                    # or "memory"
    target:
      type: Utilization
      averageUtilization: 60
```

### 5.1 CPU target

`target.averageUtilization: 60` — average CPU across all Pods in the target should be 60% of `requests.cpu`.

### 5.2 Memory target

```yaml
metrics:
- type: Resource
  resource:
    name: memory
    target:
      type: AverageValue
      averageValue: 512Mi
```

Memory target is usually `AverageValue` (raw bytes), not `Utilization`. **Memory is harder to reason about as a fraction of requests** because apps are bursty.

### 5.3 The metrics-server requirement

Resource metrics require **metrics-server** to be running. Without it, `kubectl top pods` doesn't work, and HPA can't get CPU / memory data.

```bash
kubectl -n kube-system get pods -l k8s-app=metrics-server
kubectl top pods    # if this fails, metrics-server is broken
```

## 6. Container and Pod Metrics

v2 of the HPA API lets you target **specific containers** (not the whole Pod) and **specific metrics** on those containers.

### 6.1 Container resource metrics

```yaml
metrics:
- type: ContainerResource
  containerResource:
    name: cpu
    container: app              # specific container
    target:
      type: Utilization
      averageUtilization: 60
```

Useful for multi-container Pods where you want to scale based on the main container, not the sidecar.

### 6.2 Pods metrics (custom, per-Pod)

```yaml
metrics:
- type: Pods
  pods:
    metric:
      name: http_requests_per_second
    target:
      type: AverageValue
      averageValue: "1k"
```

This is a **custom metric**, but the source is per-Pod. The HPA reads the metric for each Pod in the Deployment and computes the average.

**Requires a custom metrics adapter** (Prometheus Adapter, KEDA, etc.). See [[Kubernetes/concepts/L06-scheduling-scaling/10-keda|KEDA]] for the event-driven variant.

## 7. Custom Metrics (v2 API)

Custom metrics are **per-Pod or per-Object**, not standard k8s resources. They come from a custom metrics adapter (Prometheus Adapter, KEDA, Datadog adapter, etc.).

### 7.1 Pods metric (per-Pod)

```yaml
metrics:
- type: Pods
  pods:
    metric:
      name: queue_depth
    target:
      type: AverageValue
      averageValue: "10"
```

The adapter serves `queue_depth` per Pod. The HPA reads the metric and computes the average.

### 7.2 Object metric (per-Object)

```yaml
metrics:
- type: Object
  object:
    metric:
      name: queue_depth
    describedObject:
      apiVersion: v1
      kind: Queue           # some custom resource
      name: jobs
    target:
      type: Value
      value: "30"
```

The metric is for a specific k8s Object (not a Pod). Useful for queue depth, custom resources, etc.

## 8. External Metrics

External metrics are **outside the cluster** — Kafka lag, SQS depth, CloudWatch alarms, etc.

```yaml
metrics:
- type: External
  external:
    metric:
      name: kafka_consumer_lag
      selector:
        matchLabels:
          topic: orders
    target:
      type: AverageValue
      averageValue: "100"
```

**External metrics are not associated with a Pod or Object** — they're cluster-wide (or labeled). The HPA reads the metric and scales accordingly.

**KEDA is the de-facto adapter for external metrics.** It implements the external metrics API and provides 60+ scalers. See [[Kubernetes/concepts/L06-scheduling-scaling/10-keda|KEDA]].

## 9. Behavior Settings in Depth

```yaml
spec:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 4
        periodSeconds: 30
      selectPolicy: Max
```

The `behavior` field controls how aggressively HPA scales up vs down. The asymmetry is intentional.

### 9.1 Defaults

Without a `behavior` field:

* **scaleUp**: 0s stabilization, can add 100% or 4 Pods every 30s
* **scaleDown**: 300s stabilization, can remove 100% or 4 Pods every 30s (with the stabilization, scale-down is conservative)

The defaults are sensible. Override them for specific workloads.

### 9.2 Stabilization windows

The stabilization window is the **look-back period** for the HPA's recommendation. The HPA keeps a window of past recommendations and picks the safest one.

For `scaleDown` with a 300s window: the HPA considers recommendations from the last 5 min and picks the one that results in the **fewest** replicas. This prevents flapping — a brief spike in CPU doesn't trigger an immediate scale-down.

For `scaleUp` with a 0s window: the HPA always picks the **highest** recommendation. Scale up immediately.

## 10. Stabilization Windows

The stabilization window is the **look-back period** for the HPA's recommendation. The HPA keeps a window of past recommendations and picks the safest one.

For `scaleDown` with a 300s window: the HPA considers recommendations from the last 5 min and picks the one that results in the **fewest** replicas. This prevents flapping — a brief spike in CPU doesn't trigger an immediate scale-down.

For `scaleUp` with a 0s window: the HPA always picks the **highest** recommendation. Scale up immediately.

### 10.1 The window in action

```
T=0:  3 Pods, 80% CPU. HPA recommends 5.
T=15: 3 Pods, 60% CPU. HPA recommends 3.
T=30: 3 Pods, 90% CPU. HPA recommends 6.
T=45: 3 Pods, 50% CPU. HPA recommends 2.

With scaleDown.stabilizationWindowSeconds: 0:
HPA scales to 6 (highest recommendation in the last 0s = the latest).

With scaleDown.stabilizationWindowSeconds: 60:
HPA picks the LOWEST recommendation in the last 60s = 2.
Stays at 3 (current).

With scaleDown.stabilizationWindowSeconds: 300:
HPA picks the LOWEST recommendation in the last 5 min = 2.
Stays at 3 (current).
```

The window makes HPA **cautious about scaling down**. The 300s default is a sensible default.

## 11. Scaling Policies Math

Policies cap **how fast** HPA can change replicas, in either direction.

### 11.1 The Percent policy

```yaml
policies:
- type: Percent
  value: 50               # at most 50% of current replicas
  periodSeconds: 60       # per 60s
```

A `Percent` policy caps the change as a fraction of the current replicas.

For 3 → 5 with `value: 50, periodSeconds: 60`: at most 50% of 3 = 1.5 → 1 new Pod in 60s. To go to 5 takes 2 minutes.

### 11.2 The Pods policy

```yaml
policies:
- type: Pods
  value: 2                # at most 2 Pods
  periodSeconds: 30       # per 30s
```

An absolute cap. At most 2 new Pods every 30s.

### 11.3 Combining policies

```yaml
policies:
- type: Percent
  value: 100
  periodSeconds: 30
- type: Pods
  value: 4
  periodSeconds: 30
selectPolicy: Max
```

With `selectPolicy: Max`, the HPA picks the more aggressive (the higher value). With `Min`, the more conservative.

In the example: 100% of 3 = 3, vs 4 Pods. Max = 4. So at most 4 new Pods per 30s.

### 11.4 `selectPolicy: Disabled`

If `selectPolicy: Disabled`, the policies are **disabled** for that direction. The HPA scales only on the recommendation (limited by the stabilization window).

This is rarely what you want, but it's a knob.

## 12. The HPA Controller and Metrics Pipeline

The HPA controller is a **separate process** in `kube-controller-manager` (or a separate Deployment in some clusters). It doesn't query metrics directly — it queries the **metrics API** (served by metrics-server or a custom adapter).

```
HPA controller
       │
       │  Query: "what's the current CPU for Pod X?"
       │
       ▼
Metrics API (served by metrics-server or adapter)
       │
       │  Forward to: Prometheus, CloudWatch, Kafka, etc.
       │
       ▼
Adapter (Prometheus Adapter, KEDA, etc.)
       │
       │  Query the actual source
       │
       ▼
Prometheus / CloudWatch / Kafka
```

The HPA controller doesn't know where the metric comes from. It just calls the metrics API.

### 12.1 The API registration

Custom metrics adapters register themselves with the apiserver via `apiservice` objects:

```yaml
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  name: v1beta1.custom.metrics.k8s.io
spec:
  service:
    name: prometheus-adapter
    namespace: monitoring
  group: custom.metrics.k8s.io
  version: v1beta1
```

The adapter serves the `custom.metrics.k8s.io` API. The HPA queries it. **Without the APIService registered, HPA can't get custom metrics.**

## 13. Min Replicas, Max Replicas, Scale to Zero

```yaml
spec:
  minReplicas: 2
  maxReplicas: 10
```

* **`minReplicas`** — the floor. The HPA never scales below this. Default is 1.
* **`maxReplicas`** — the ceiling. The HPA never scales above this.

### 13.1 Scale to zero

`minReplicas: 0` enables **scale to zero**. The HPA can scale the target to 0 replicas when the metric is empty.

```yaml
spec:
  minReplicaCount: 0       # KEDA uses minReplicaCount, not minReplicas
  maxReplicaCount: 10
```

(KEDA's HPA accepts `minReplicaCount`; the standard HPA API uses `minReplicas`.)

### 13.2 Scale to zero gotchas

* **Cold start latency** — scaling from 0 takes 5-30s. Plan for it.
* **Service routing** — a Service with 0 Pods has no Endpoints. The Service is "not ready". Some clients fail.
* **Knative and KEDA** handle this gracefully (built-in scale-to-zero support). Plain HPA doesn't have the same level of polish.

For most production workloads, **don't set `minReplicas: 0`**. The cold start penalty is real. Use it for dev / test or event-driven workloads where KEDA's handling is appropriate.

## 14. HPA on StatefulSets and Other Controllers

HPA works on any controller that implements the **scale subresource** (`/scale`):

* Deployment ✓
* StatefulSet ✓
* ReplicaSet ✓
* ReplicationController ✓
* Custom controllers with the scale subresource

### 14.1 HPA on StatefulSet

```yaml
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: db
```

HPA changes `spec.replicas` on the StatefulSet. The StatefulSet controller handles the rest (creating / deleting Pods in order, preserving PVCs).

**Scaling a StatefulSet down** removes the **highest-numbered** Pod. The PVCs are retained (with `Retain` reclaim policy). To clean up, delete the PVCs manually.

**Scaling a StatefulSet up** is similar to Deployment: creates the new Pod with the next ordinal.

### 14.2 HPA on custom controllers

Custom controllers must implement the `scale` subresource. The HPA calls `/scale` to get the current replica count and updates `spec.replicas` (or whatever the controller watches).

## 15. HPA + VPA + Karpenter Combinations

### 15.1 HPA + Karpenter

The standard combination. HPA scales Pods; Karpenter adds nodes when Pods can't be scheduled.

```
HPA:  scales Pods (3 → 10)
Karpenter:  sees 7 unschedulable Pods, launches a node
HPA:  sees 10 Pods at 60% CPU each
```

### 15.2 HPA + VPA — on different metrics

```yaml
# HPA: scale on CPU
metrics:
- type: Resource
  resource: { name: cpu, target: { type: Utilization, averageUtilization: 60 } }

# VPA: tune memory
controlledResources: [memory]
```

HPA scales Pods based on CPU. VPA tunes memory requests. **No conflict.**

### 15.3 HPA + Cluster Autoscaler (or Karpenter)

```
HPA:  scales Pods (3 → 10)
CA:   sees 7 unschedulable Pods, adds a node
HPA:  sees 10 Pods at 60% CPU each
```

Same as HPA + Karpenter. CA or Karpenter is the cluster-level autoscaler.

### 15.4 What doesn't work

* **HPA + VPA on the same metric** — fight. The HPA controller emits an error event.
* **HPA scaling on a metric VPA controls** — see above.
* **HPA on `replicas: 0` Deployment** — HPA has no Pods to query, can't compute.

## 16. Operations and Debugging

### 16.1 Common commands

```bash
# list HPAs
kubectl get hpa -A
# shows NAME, REFERENCE, TARGETS, MINPODS, MAXPODS, REPLICAS, AGE

# describe
kubectl describe hpa <name>
# shows metrics, current values, recent scaling events

# check the controller
kubectl -n kube-system get pods -l app=kube-controller-manager
kubectl -n kube-system logs -l app=kube-controller-manager | grep -i hpa

# check the metrics-server
kubectl -n kube-system get pods -l k8s-app=metrics-server
kubectl top pods
```

### 16.2 The "HPA not scaling" checklist

```bash
# 1. Are the metrics available?
kubectl top pods
# if this fails, metrics-server is broken

# 2. Does the Deployment have requests?
kubectl get pod <pod> -o jsonpath='{.spec.containers[0].resources}'
# HPA needs requests to compute Utilization

# 3. Is the HPA reading the right metric?
kubectl describe hpa <name>
# look at "TARGETS" - shows the current vs target value

# 4. Is minReplicas >= current replicas?
kubectl get hpa <name> -o jsonpath='{.spec.minReplicas}'

# 5. Is the HPA in error state?
kubectl describe hpa <name>
# look at "Conditions" - any errors?

# 6. Is the HPA controller running?
kubectl -n kube-system logs -l app=kube-controller-manager | grep -i "hpa"
```

### 16.3 The "HPA scaling too aggressively" case

```bash
# check the behavior
kubectl get hpa <name> -o yaml
# look at spec.behavior

# fix:
# - increase scaleDown.stabilizationWindowSeconds
# - add a Percent policy with a small value
# - set a more conservative target
```

### 16.4 The "HPA scaling to max but Pods are OOMing" case

HPA is scaling up because CPU is high, but the new Pods OOM. The metric is misleading.

```bash
# 1. Check if memory is the actual problem
kubectl top pods
# look at memory usage

# 2. Add memory requests (or use VPA)
kubectl edit deployment <name>

# 3. Or, change HPA to scale on memory instead
# if memory is the real bottleneck
```

## 17. Gotchas and Common Mistakes

### 17.1 The 30+ common mistakes

1. **HPA uses `requests`, not actual usage, as the baseline for CPU utilization %.** If `requests.cpu: 100m` and the Pod uses 70m, you're at 70% — HPA may scale up. Set requests thoughtfully.

2. **No requests = no HPA on resource metrics.** The HPA can't compute utilization if there's no request to compare against. Set requests.

3. **HPA needs metrics-server (or a custom metrics adapter) to be running.** Check with `kubectl top pods` — if that doesn't work, HPA can't see anything.

4. **HPA does not work on `replicas: 0`.** Set `minReplicas: 1` at minimum.

5. **Scaling can be slow** if your readiness probe takes time to pass. HPA adds a Pod, but the Pod is not "ready" until the probe passes, and the Service doesn't route to it until then.

6. **Custom metrics require the metric to be on a "metric server" HPA can query.** Out-of-the-box k8s has no custom metrics.

7. **HPA will not scale below `minReplicas`.** If you set `minReplicas: 0`, you get scale-to-zero (k8s 1.16+).

8. **The HPA controller is rate-limited.** It will not scale a Deployment from 1 to 1000 in one cycle — there's a 4-Pod-per-30s default.

9. **HPA respects PodDisruptionBudgets** during scale-down, but the inverse is not true — PDB doesn't know about HPA scale-down events. Set `minReplicas` such that PDB + minReplicas makes sense.

10. **HPA doesn't know about pending scheduling.** If HPA scales to 10 replicas but only 2 nodes can fit, you'll have 8 Pending Pods. That's where CA / Karpenter kicks in.

11. **HPA's recompute is every 15s, but Pod start is slower.** Don't expect instant scaling. Image pull + container start + readiness probe = 10-30s typical.

12. **HPA respects scale-down policies that are conservative by default.** `scaleDown.stabilizationWindowSeconds: 300` means HPA waits 5 min before scaling down. Tune for your workload.

13. **Custom metrics HPA needs the metric to be present and accessible.** If Prometheus is down, HPA can't scale. Have a fallback (HPA on CPU as a backup).

14. **CA's scale-down is conservative** (10 min unused by default). It also respects PDB. Don't expect nodes to disappear the moment they're empty.

15. **CA + Karpenter is "either/or"**, not "both". Pick one. EKS now recommends Karpenter for new clusters.

16. **VPA in `Auto` mode restarts Pods.** For stateful workloads, this can cause data loss if the app doesn't drain properly. Use `Initial` or `Off` for stateful.

17. **VPA + HPA on the same metric = fight.** Use HPA on one metric, VPA on another, or HPA only, or VPA only.

18. **`maxReplicas` is a ceiling, not a guarantee.** If a metric says you need 100, but `maxReplicas: 20`, you get 20. The Pods will be at 5x the target utilization.

19. **Scaling a StatefulSet is different.** Each replica has a stable identity. Scaling down removes the highest-numbered Pod. The PVCs are not deleted (they're `Retain` by default). To clean up, delete the PVCs manually.

20. **HPA on `Utilization` with a target of 100% means the average is 100% of `requests`.** This is "use all the CPU you have". You usually want 60-80% for headroom.

21. **HPA on memory with `Utilization` is unusual.** Memory is bursty; a `Utilization` target of 80% doesn't capture the burst pattern. Use `AverageValue` for memory.

22. **HPA's metrics are eventually consistent.** The HPA reads metrics that are 10-30s old. The "current" value is not real-time.

23. **The HPA controller is in `kube-controller-manager`** by default. Some clusters run it separately. Check the cluster's setup.

24. **A custom controller must implement the `scale` subresource** for HPA to work on it. Without it, HPA can't update the controller's replica count.

25. **HPA + VPA both touching the same Deployment is a fight.** Pick one. Or scope them to different metrics.

26. **HPA on a `DaemonSet` doesn't make sense.** DS Pods are per-node, not per-load. The DS controller ignores the HPA's `replicas` setting.

27. **HPA + PDB deadlock:** PDB says minAvailable: N. HPA wants to scale below N. PDB blocks. The HPA controller retries, fails, and the Pod count stays at N+.

28. **HPA can scale to 0 if `minReplicas: 0`.** The Deployment's `replicas` field goes to 0. The Deployment controller deletes all Pods. **This is reversible** — a metric spike brings them back.

29. **HPA doesn't restart Pods that fail to be Ready.** The HPA updates `replicas`, and the controller creates new Pods. The new Pods need to pass readiness before the Service routes traffic.

30. **HPA's `behavior` field is per-HPA, not cluster-wide.** Set it per workload. Don't make it overly aggressive — bursty scaling can stress other components.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource Requests & Limits]] — what HPA computes against
* [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler|VPA]] — the vertical counterpart
* [[Kubernetes/concepts/L06-scheduling-scaling/10-keda|KEDA]] — the event-driven variant
* [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PDB]] — how PDBs interact with HPA scale-down
* [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling|Scaling]] — the L06 overview

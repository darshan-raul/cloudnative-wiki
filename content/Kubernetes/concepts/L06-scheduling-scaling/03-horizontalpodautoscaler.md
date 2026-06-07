# HorizontalPodAutoscaler (HPA)

*"https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/"*

The HPA automatically scales the **number of Pod replicas** in a Deployment, StatefulSet, ReplicaSet, or similar controller, based on observed metrics (CPU, memory, custom).

## How it works

HPA is a control loop:

1. Queries metrics (every `--horizontal-pod-autoscaler-sync-period`, default 15s)
2. Computes `desiredReplicas = ceil(currentReplicas * currentMetricValue / targetMetricValue)`
3. Updates the controller's `replicas` field
4. The controller (Deployment etc.) converges to the new count via its own rolling update

## Basic example (CPU)

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

* Scale between 2 and 10 Pods
* Target 60% of `cpu` **requests** (not limits, not actual usage)
* If a Pod has `requests.cpu: 200m` and is using 180m, that's 90% — HPA will scale up

## Custom metrics (the v2 API)

```yaml
spec:
  metrics:
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "1k"
  - type: Object
    object:
      metric:
        name: queue_depth
      describedObject:
        apiVersion: v1
        kind: Queue
        name: jobs
      target:
        type: Value
        value: "30"
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

You need the corresponding metrics adapter installed (Prometheus Adapter, KEDA, etc.). HPA itself doesn't know how to collect custom metrics.

## Behavior settings

```yaml
spec:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300      # wait 5 min before scaling down
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60                  # at most 10% per minute
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30                  # can double every 30s
      - type: Pods
        value: 4
        periodSeconds: 30
      selectPolicy: Max                    # pick the more aggressive
```

Defaults:

* **scaleUp**: 0s stabilization, can add 100% or 4 Pods every 30s
* **scaleDown**: 300s stabilization, can remove 100% or 4 Pods every 30s (but with the stabilization, scale-down is conservative)

The asymmetry is intentional — scaling down too fast kills in-flight work; scaling up too slowly lets traffic pile up.

## HPA vs VPA vs Cluster Autoscaler

| | HPA | VPA | CA |
|---|---|---|---|
| What it scales | Replicas (Pods) | Pod resource requests/limits | Nodes |
| Driven by | CPU/memory/custom | Historical usage | Pending Pods |
| Restarts Pods | Yes (during scale up) | Yes (every change) | No |
| Best for | Stateless HTTP services | Stateful, single-replica | Capacity |

You can combine HPA + CA (HPA scales Pods, CA adds nodes when Pods can't be scheduled). HPA + VPA on the same metric doesn't make sense — pick one. **VPA is in beta and rarely used in production.**

## Gotchas

* **HPA uses `requests`, not actual usage, as the baseline for CPU utilization %.** If `requests.cpu: 100m` and the Pod uses 70m, you're at 70% — HPA may scale up. Set requests thoughtfully.
* **No requests = no HPA on resource metrics.** The HPA can't compute utilization if there's no request to compare against. Set requests.
* **HPA needs metrics-server (or a custom metrics adapter) to be running.** Check with `kubectl top pods` — if that doesn't work, HPA can't see anything.
* **HPA does not work on `replicas: 0`.** Set `minReplicas: 1` at minimum.
* **Scaling can be slow** if your readiness probe takes time to pass. HPA adds a Pod, but the Pod is not "ready" until the probe passes, and the Service doesn't route to it until then.
* **Custom metrics require the metric to be on a "metric server" HPA can query.** Out-of-the-box k8s has no custom metrics.
* **HPA will not scale below `minReplicas`.** If you set `minReplicas: 0`, you get scale-to-zero (k8s 1.16+ via `--enable-vertical-pod-autoscaling=false` is not required, but the Deployment must support scale-to-zero, which Deployment does by default).
* **The HPA controller is rate-limited.** It will not scale a Deployment from 1 to 1000 in one cycle — there's a 4-Pod-per-30s default.
* **HPA respects PodDisruptionBudgets** during scale-down, but the inverse is not true — PDB doesn't know about HPA scale-down events. Set `minReplicas` such that PDB + minReplicas makes sense.

# Metrics Sources

*"https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/"*

A reference for **where metrics come from** in a Kubernetes cluster. The k8s metrics stack is layered; knowing the layers helps you figure out what's missing when a metric is silent.

## The layers

```
┌────────────────────────────────────────────┐
│  Application                               │  ← your app exposes /metrics
├────────────────────────────────────────────┤
│  Container / cAdvisor                      │  ← per-container resource use
├────────────────────────────────────────────┤
│  kubelet                                  │  ← aggregates, exposes via API
├────────────────────────────────────────────┤
│  metrics-server (or kube-state-metrics)    │  ← serves to k8s API
├────────────────────────────────────────────┤
│  Prometheus / Datadog / CloudWatch / etc.  │  ← long-term storage, dashboards
└────────────────────────────────────────────┘
```

## 1. cAdvisor (per-container)

Built into the **kubelet**. Collects CPU, memory, network, and filesystem usage for every container on the node. No setup.

* **Exposed at** `https://<node>:10250/metrics/cadvisor` (kubelet's `/metrics/cadvisor` endpoint)
* **Auth**: kubelet's serving cert, requires `nodes/metrics` RBAC
* **Granularity**: per-container, per-pod
* **Retention**: in-memory, lost on kubelet restart

You don't usually query cAdvisor directly — it's the source that `metrics-server` aggregates from.

## 2. kubelet (node-level)

The kubelet exposes its own metrics on the same port:

* `https://<node>:10250/metrics` — kubelet's view: restarts, operation latency, Pod lifecycle stats
* Includes `kubelet_running_pods`, `kubelet_pleg_relist_interval_seconds`, etc.

Useful for diagnosing the kubelet itself (not the Pods on it).

## 3. metrics-server (cluster-wide aggregates)

`metrics-server` is the official k8s project that aggregates cAdvisor data and exposes it via the **Metrics API** (not the main API):

* `kubectl top nodes` and `kubectl top pods` query this
* HPA queries this for resource-based scaling
* Endpoint: `apis/metrics.k8s.io/v1beta1` (or `/v1`)

```bash
# is it installed?
kubectl get deployment metrics-server -n kube-system

# is it serving data?
kubectl get --raw='/apis/metrics.k8s.io/v1beta1/pods' | jq .
```

If `kubectl top` returns "Metrics API not available", metrics-server isn't running or is unhealthy.

**Important:** metrics-server is **in-memory**. It restarts → it forgets. It's meant for autoscaling (HPA, VPA, CA), not for dashboards or alerting.

## 4. kube-state-metrics (object state)

`kube-state-metrics` watches the k8s API and produces metrics about **object state** — not resource usage.

Examples:

* `kube_pod_status_phase` — Pod phase counts
* `kube_deployment_status_replicas` — Deployment replica counts
* `kube_node_status_condition` — Node Ready / NotReady
* `kube_pod_container_status_restarts_total` — restart counts
* `kube_pod_container_resource_limits` — what's been requested

It's the source of truth for "how many Pods are pending", "is the Deployment healthy", etc. **Every monitoring stack needs this.**

## 5. Node exporter / runtime metrics

* **node-exporter** (Prometheus) — host-level metrics: CPU, memory, disk, network, kernel stats
* **kube-proxy metrics** — `http://<kube-proxy>:10249/metrics` (or via the kubelet's port)
* **Container runtime metrics** — containerd / CRI-O expose their own

These are per-node, not per-Pod. They tell you about the host.

## 6. Application metrics

The app itself exposes `/metrics` (usually Prometheus format) on a port. This is the only way to know **business-level** signals (requests/sec, error rate, queue depth).

**Best practice:** apps expose metrics on a separate port that's only accessible on localhost (use `NetworkPolicy` to enforce).

## Putting it together — the typical stack

```
              ┌──────────────┐
              │ Prometheus   │  ← scrapes everything, stores
              │  / Thanos    │     long-term
              │  / Mimir     │
              └──────┬───────┘
                     │ PromQL
        ┌────────────┼────────────┐
        ▼            ▼            ▼
    Grafana     AlertManager   (HPA, etc.)
    dashboards   → PagerDuty
                     ▲
                     │ alerts
                     │
        ┌────────────┴────────────────────┐
        │                                 │
   kubelet /10250/metrics            application /metrics
        ▲                                 ▲
        │                                 │
   cAdvisor (per-container)         app code
        ▲
        │
   metrics-server (aggregates, HPA)
        ▲
        │
   kube-state-metrics (object state)
```

The full path for, say, "average Pod memory usage":

1. App's container uses memory
2. cAdvisor on the node measures it
3. metrics-server queries cAdvisor across all nodes
4. metrics-server exposes it via the Metrics API
5. Prometheus scrapes metrics-server (or queries the API directly)
6. Grafana queries Prometheus
7. AlertManager queries Prometheus for alerts
8. HPA queries the Metrics API directly

## Gotchas

* **`kubectl top` works only if metrics-server is installed and healthy.** Without it, the command errors out.
* **metrics-server is not a long-term metrics store.** It forgets. Don't try to use it for dashboards.
* **kube-state-metrics is its own thing.** It comes with the Prometheus community; you install it separately. It's not a side-effect of metrics-server.
* **The Metrics API is separate from the main API.** It's at `apis/metrics.k8s.io/...`, not at `api/v1/...`. RBAC for it is separate.
* **kubelet's `/metrics` endpoint is unauthenticated by default on some clusters** (the kubelet's `readOnlyPort` 10255 is HTTP). It should be off in production — use the secured port 10250 with cert auth.
* **Application metrics are your responsibility.** k8s has no idea what your service is doing. If your app doesn't expose `/metrics`, you can't graph it.
* **Custom metrics for HPA require an adapter** (Prometheus Adapter, KEDA, etc.). HPA itself doesn't know how to query Prometheus.

## Where to go for the deployment side

* [[Kubernetes/guides/prometheus|Prometheus on k8s]] (in Guides) — full stack setup
* `metrics-server` deployment — usually via the `metrics-server` Helm chart or k8s add-on
* `kube-state-metrics` — usually via Helm or kube-prometheus-stack

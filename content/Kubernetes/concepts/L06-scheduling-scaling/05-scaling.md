# Scaling (L06 Overview)

*"https://kubernetes.io/docs/concepts/cluster-administration/autoscaling/"*

A high-level overview of the **scaling family** in Kubernetes — HPA, VPA, CA, and how they fit together. The deeper notes are linked below.

## The three scaling dimensions

When load on a Deployment changes, you can scale in three orthogonal ways:

| Dimension | What scales | Mechanism | Affects existing Pods |
|---|---|---|---|
| **Horizontal** | Number of replicas (Pods) | Add / remove Pods | No (new Pods have new IPs) |
| **Vertical** | CPU / memory per Pod | Resize requests/limits | Yes (Pods restart) |
| **Cluster** | Number of nodes | Add / remove nodes | N/A |

The three autoscalers:

* **HPA** — Horizontal Pod Autoscaler
* **VPA** — Vertical Pod Autoscaler
* **CA** — Cluster Autoscaler (or Karpenter, which is a newer alternative)

## Horizontal Pod Autoscaler (HPA)

The HPA watches a metric and changes the number of replicas in a controller (Deployment, StatefulSet, ReplicaSet, etc.) to drive the metric to a target.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: web }
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
```

The HPA controller:

1. Queries the metric every `--horizontal-pod-autoscaler-sync-period` (default 15s)
2. Computes `desiredReplicas = ceil(currentReplicas * currentMetricValue / targetMetricValue)`
3. Updates the controller's `replicas` field
4. The controller does the rest (rolls out new Pods, etc.)

**Target metrics can be:**

* **Resource** (CPU, memory) — uses metrics-server
* **Pod** (custom per-pod metrics) — needs a metrics adapter
* **Object** (custom per-object metrics, e.g. queue depth) — needs a metrics adapter
* **External** (anything else) — needs a metrics adapter

→ [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] — the full deep dive

## Vertical Pod Autoscaler (VPA)

The VPA watches historical resource usage and **recommends or sets** the right `requests.cpu` / `requests.memory` for a Pod. It addresses the "you have no idea what to set" problem.

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata: { name: web }
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  updatePolicy:
    updateMode: Auto     # or "Off" (just recommend) or "Initial" (only at creation)
  resourcePolicy:
    containerPolicies:
    - containerName: '*'
      maxAllowed: { cpu: "2", memory: 4Gi }
      minAllowed: { cpu: 50m, memory: 64Mi }
```

**VPA modes:**

* **`Off`** — collect metrics, write recommendations to the VPA object's `status`. Don't change Pods.
* **`Initial`** — set the right size at Pod creation. Don't resize live Pods.
* **`Auto`** — set at creation AND resize live Pods (restarts them).

**VPA restarts Pods** when it resizes them. Not suitable for stateful workloads with no graceful restart.

**VPA + HPA on the same metric doesn't work** — they fight each other. Pick one. The most common pattern: HPA on CPU for stateless services, VPA on memory for stateful services.

**VPA is in beta.** It's been "beta" since k8s 1.9. It works but has rough edges, especially with PodDisruptionBudgets and sidecar containers.

## Cluster Autoscaler (CA)

The Cluster Autoscaler watches for Pods that **can't be scheduled** (e.g. `Pending` because of insufficient resources) and **adds nodes** to the cluster. When nodes are underutilized, it removes them.

```bash
# on a managed cluster, CA runs as a Deployment
kubectl get deployment cluster-autoscaler -n kube-system

# on a self-managed cluster, it's deployed via the cluster-autoscaler chart
# https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler
```

CA is **cloud-aware** — it calls the cloud provider's API to add/remove nodes. EKS, GKE, AKS each have their own integration. The "node group" concept (managed node group on EKS, MIG on GKE, VMSS on AKS) is what CA scales.

**CA's logic:**

1. Every 10s, scan for unschedulable Pods
2. If any, simulate adding a node of each type; pick the type that gets the most Pods scheduled
3. Call the cloud API to add that node group / node template
4. Once the new node joins, the scheduler places the Pods
5. For scale-down: every 10s, find nodes whose utilization is below a threshold; cordon + drain + terminate

**Caveats:**

* CA is conservative about removing nodes (drains take time, PDBs can block)
* CA doesn't handle heterogeneous nodes (GPU vs CPU) well — use node taints and tolerations
* CA is being replaced by **Karpenter** in many clusters (EKS especially)

## Karpenter (the modern alternative to CA)

Karpenter is a node provisioner that:

* Watches unschedulable Pods directly
* Picks the **right instance type** (any available on AWS) based on the Pod's requirements
* Launches the node in ~30 seconds (vs ~3 minutes for CA)
* Consolidates nodes (replaces underutilized ones with fewer, larger ones)

Karpenter is **much more dynamic** than CA. It's a different model: instead of "I have 3 node groups, scale each between min and max", Karpenter says "I'll figure out what instances to run based on the Pods you need to schedule".

→ [[Kubernetes/eks/compute/karpenter|Karpenter]] — the EKS-specific deep dive

## The combination

A typical production setup uses all three:

```
                ┌─────────────────────────────────────────┐
                │              CLUSTER                     │
                │                                          │
                │   ┌─────────┐                            │
                │   │   CA /  │  ← adds nodes when HPA    │
                │   │Karpenter│    asks for more replicas  │
                │   └────┬────┘                            │
                │        │                                 │
                │   nodes │                                 │
                │        ▼                                 │
                │   ┌─────────┐    ┌─────────┐             │
                │   │ kubelet │    │ kubelet │  ...        │
                │   └────┬────┘    └────┬────┘             │
                │        │             │                  │
                │   ┌────▼─────┐  ┌────▼─────┐             │
                │   │ Pod x N  │  │ Pod x N  │  ...        │
                │   │ (HPA     │  │          │             │
                │   │  decides │  │          │             │
                │   │  N)      │  │          │             │
                │   └──────────┘  └──────────┘             │
                │                                          │
                └─────────────────────────────────────────┘

HPA:  changes N based on metric (CPU, custom, ...)
VPA:  changes requests/limits based on history (off by default in production)
CA / Karpenter: changes node count based on unschedulable Pods
```

## HPA vs VPA — when to use which

| | HPA | VPA |
|---|---|---|
| Use when | Stateless, can scale horizontally | Stateful, can't easily add replicas |
| Scales | Number of Pods | Resource requests/limits per Pod |
| Restart needed? | No (new Pods) | Yes (VPA resizes by recreating) |
| Works with PDB? | Yes | Not always |
| Production-ready? | Yes | Beta, use with care |
| Common metric | CPU, custom | Historical usage |

**Don't use both HPA and VPA on the same resource metric** — they'll fight. A common pattern:

* HPA on CPU for the stateless tier
* VPA on memory for the stateful tier (DB Pods, where adding replicas is hard)
* Neither for batch / Job workloads (just right-size manually)

## HPA on custom metrics

The default HPA can only use CPU / memory. For queue depth, request rate, business metrics, etc., you need a **custom metrics adapter**:

* **Prometheus Adapter** — exposes Prometheus queries as k8s custom metrics
* **KEDA** — external scaler for any source (Kafka lag, RabbitMQ queue, SQS, etc.)
* **CloudWatch Adapter** (EKS) — uses CloudWatch metrics

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: web }
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  metrics:
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "1k"
```

The HPA controller asks the metrics adapter: "what's the current value of `http_requests_per_second` for Pods of this Deployment?". The adapter queries Prometheus. The HPA scales accordingly.

## Scaling to zero

HPA can scale to zero replicas with `minReplicas: 0`. The Deployment must support scale-to-zero (it does, by default — `kubectl scale deploy web --replicas=0` works).

Scaling to zero is useful for:

* Dev / test environments
* Cost optimization (idle services)
* Event-driven workloads (scale up on first request, down when idle)

Caveats:

* **Cold start latency.** When traffic arrives, the Pod needs to start. Add 5-30s for image pull, container start, readiness probe.
* **Some Service meshes and ingress controllers** don't handle scale-to-zero gracefully. Test it.
* **Knative** and **KEDA** have first-class scale-to-zero with HTTP-driven scaling. Plain HPA doesn't.

## Manual scaling

You can always scale manually:

```bash
kubectl scale deployment web --replicas=10
```

This sets `spec.replicas` to 10. The Deployment controller will add 5 Pods to reach 10. HPA's next sync will see the new state and either let it be (if the metric is below target) or change it.

To disable HPA temporarily, set `spec.minReplicas` and `spec.maxReplicas` to the current value. Or `kubectl delete hpa web`.

## PodDisruptionBudget vs autoscaling

A PodDisruptionBudget **limits voluntary disruption** (drain, autoscaler scale-down). It doesn't stop scaling up; it just makes scale-down gentler.

A common pattern:

```yaml
# HPA: 2-20 replicas, target 60% CPU
# PDB: minAvailable: 1
```

If HPA decides to scale down from 2 to 1, the PDB is violated (minAvailable=1 means at least 1 must be available; if you're scaling down, you have 0 for a moment). The eviction API retries with backoff. Eventually, the autoscaler gives up and leaves 2 Pods.

**Always have a PDB** if you have HPA scale-down enabled. Without it, all Pods could be terminated simultaneously.

## Gotchas

* **HPA on CPU is the most common, but CPU isn't always the right metric.** For an I/O-bound service, CPU might stay low even when the service is overwhelmed. Use a custom metric (request latency, queue depth) for these cases.
* **HPA needs `requests` to compute utilization.** A Pod with no `requests` can't be HPA'd on CPU. Set requests.
* **HPA doesn't know about scheduling.** If HPA scales to 10 replicas but only 2 nodes can fit, you'll have 8 Pending Pods. That's where CA / Karpenter kicks in.
* **HPA's recompute is every 15s, but Pod start is slower.** Don't expect instant scaling. Image pull + container start + readiness probe = 10-30s typical.
* **HPA respects scale-down policies that are conservative by default.** `scaleDown.stabilizationWindowSeconds: 300` (5 min) means HPA waits 5 min before scaling down. Tune for your workload.
* **Custom metrics HPA needs the metric to be present and accessible.** If Prometheus is down, HPA can't scale. Have a fallback (HPA on CPU as a backup).
* **CA's scale-down is conservative** (10 min unused by default). It also respects PDB. Don't expect nodes to disappear the moment they're empty.
* **CA + Karpenter is "either/or"**, not "both". Pick one. EKS now recommends Karpenter for new clusters.
* **VPA in `Auto` mode restarts Pods.** For stateful workloads, this can cause data loss if the app doesn't drain properly. Use `Initial` or `Off` for stateful.
* **VPA + HPA on the same metric = fight.** Use HPA on one metric, VPA on another, or HPA only, or VPA only.
* **`maxReplicas` is a ceiling, not a guarantee.** If a metric says you need 100, but `maxReplicas: 20`, you get 20. The Pods will be at 5x the target utilization.
* **Scaling a StatefulSet is different.** Each replica has a stable identity. Scaling down removes the highest-numbered Pod. The PVCs are not deleted (they're `Retain` by default). To clean up, delete the PVCs manually.

## When to use what

| Scenario | Scaling choice |
|---|---|
| Stateless HTTP service | HPA on CPU + CA / Karpenter |
| Stateless HTTP service with custom load metric | HPA on custom metric (Prometheus) + CA / Karpenter |
| Stateful service, hard to add replicas (DB) | VPA on memory, manual replica count |
| Stateful service, can add replicas (Kafka, Cassandra) | HPA on CPU + careful state management |
| Batch / Job workloads | None — right-size the Job spec |
| Dev / test environments | HPA min=0, scale to zero on idle |
| Event-driven (Kafka, SQS) | KEDA on the queue metric |
| Multi-cluster | Each cluster's autoscaler; cross-cluster is harder |

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource Requests & Limits]] — what HPA / VPA compute against
* [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] — full deep dive
* [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudget]] — interaction with scale-down
* [[Kubernetes/eks/compute/karpenter|Karpenter]] — the modern alternative to CA
* [[Kubernetes/guides/auto-scaling|Auto-scaling guide]] — practical patterns

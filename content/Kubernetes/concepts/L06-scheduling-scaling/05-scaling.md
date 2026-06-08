# Scaling — The L06 Overview

A high-level overview of the **scaling family** in Kubernetes — HPA, VPA, Cluster Autoscaler, Karpenter, and KEDA. This is the hub: the deeper notes are linked below. If you're looking for the "which autoscaler do I use" decision, this is the place to start.

## The three scaling dimensions

When load on a Deployment changes, you can scale in three orthogonal ways:

| Dimension | What scales | Mechanism | Affects existing Pods? |
|---|---|---|---|
| **Horizontal** | Number of replicas (Pods) | Add / remove Pods | No (new Pods have new IPs) |
| **Vertical** | CPU / memory per Pod | Resize requests/limits | Yes (Pods restart) |
| **Cluster** | Number of nodes | Add / remove nodes | N/A |

The four autoscalers:

* **HPA** — Horizontal Pod Autoscaler
* **VPA** — Vertical Pod Autoscaler
* **CA** — Cluster Autoscaler (or **Karpenter**, the modern alternative)
* **KEDA** — Kubernetes Event-Driven Autoscaling (drives HPA, the only one that natively scales to zero from external sources)

## The one-table comparison

| | HPA | VPA | CA | Karpenter | KEDA |
|---|---|---|---|---|---|
| **What it scales** | Replicas (Pods) | Pod resource requests/limits | Nodes (ASG / MIG / VMSS) | Nodes (dynamic instance types) | Drives HPA — scales replicas from external sources |
| **Driven by** | CPU / memory / custom / external | Historical usage | Pending Pods | Pending Pods | Kafka lag, queue depth, SQS, cron, Prometheus, 60+ others |
| **Restarts Pods** | No (new Pods) | Yes (in `Auto` mode) | No | No | No (drives HPA) |
| **Best for** | Stateless HTTP services | Stateful, single-replica | Stable, predictable workloads | Heterogeneous, fast-scaling | Event-driven, queue-based |
| **Production-ready?** | Yes | Beta (since k8s 1.9) | Yes | Yes (v1 GA) | Yes |
| **Scales to zero?** | With `minReplicas: 0` | No | No | No | Yes (built-in) |
| **Common pairing** | CA / Karpenter | HPA on a different metric | HPA | HPA | HPA (it IS HPA's metrics source) |

→ [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] — the workhorse
→ [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler|VPA]] — the right-sizing complement
→ [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter|Karpenter]] — the modern alternative to CA
→ [[Kubernetes/concepts/L06-scheduling-scaling/09-cluster-autoscaler|Cluster Autoscaler]] — the older node provisioner
→ [[Kubernetes/concepts/L06-scheduling-scaling/10-keda|KEDA]] — event-driven scaling

## How they combine

A typical production setup uses three of the four:

```
                ┌────────────────────────────────────────────────┐
                │                CLUSTER                          │
                │                                                 │
                │  ┌──────────────────────────────────────────┐   │
                │  │  Karpenter / Cluster Autoscaler         │   │
                │  │  Watches for Pending Pods, adds nodes   │   │
                │  └──────────────────────────────────────────┘   │
                │                       │ adds nodes               │
                │  ┌─────────┐  ┌─────────┐  ┌─────────┐         │
                │  │ kubelet │  │ kubelet │  │ kubelet │  ...     │
                │  └────┬────┘  └────┬────┘  └────┬────┘         │
                │       │            │            │              │
                │  ┌────▼────┐  ┌────▼────┐  ┌────▼────┐         │
                │  │ Pod x N │  │ Pod x N │  │ Pod x N │  ...     │
                │  │ (HPA    │  │ (HPA    │  │         │         │
                │  │  decides│  │         │  │         │         │
                │  │  N)     │  │         │  │         │         │
                │  └─────────┘  └─────────┘  └─────────┘         │
                │                                                 │
                │  VPA tunes requests (right-sizing)              │
                │  KEDA drives HPA from external sources          │
                │  PDB protects availability during drains        │
                └────────────────────────────────────────────────┘
```

### The standard pattern

* **HPA on CPU** for stateless services (HTTP APIs, workers).
* **VPA in `recommend` mode** for right-sizing (you apply the recommendations manually).
* **Karpenter** for node provisioning (replace CA on new clusters).
* **KEDA** for event-driven workloads (Kafka, SQS, RabbitMQ).
* **PDB** for availability during voluntary disruption.

### What NOT to do

* **HPA + VPA on the same metric.** They fight. Use one on CPU, the other on memory.
* **CA + Karpenter at the same time.** They race for the same Pending Pods.
* **HPA + manual `kubectl scale`.** Manual changes are overridden by HPA in seconds.
* **Tight PDBs with low replicas.** `minAvailable: 2` on a Deployment with 2 replicas is a deadlock.

## When to use what (decision tree)

```
Stateless HTTP service, scale on CPU?
├── Yes → HPA on CPU + Karpenter
└── No, custom metric → HPA on custom + Karpenter
        (custom metric needs Prometheus Adapter or similar)

Stateless HTTP service, scale on event (Kafka, SQS, RabbitMQ)?
└── KEDA on the queue metric + Karpenter

Stateful service, hard to add replicas (single DB)?
├── VPA in Auto mode on memory + manual replica count
└── OR: VPA in Off mode, apply recommendations manually

Stateful service, can add replicas (Cassandra, Kafka)?
└── HPA on CPU + careful state management (PDB matters here)

Batch / Job workloads?
└── Right-size the Job spec; no autoscaler

Dev / test environments?
└── KEDA on cron + scale to zero on idle

Multi-cluster?
└── Each cluster's autoscaler; cross-cluster is harder
```

## The "production checklist" for autoscaling

* **Set resource requests** on every container. HPA needs them.
* **Pick one autoscaler per metric.** Don't have HPA and VPA both touching CPU.
* **Use a PDB** for any service with > 1 replica. Without it, drains are dangerous.
* **Have a fallback for custom metrics.** If Prometheus is down, HPA on custom can't scale. Add HPA on CPU as a backup.
* **Monitor the autoscaler itself.** Each autoscaler exposes Prometheus metrics — scrape them.
* **Test scale-up and scale-down in non-prod.** A scale-up to 1000 Pods in 30s may break the apiserver, the CNI, the load balancer, etc. Tune the rate limits.
* **Document the autoscalers.** The next operator will need to know which metric drives which Deployment.

## Where to go next

* [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] — the full deep dive
* [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler|VPA]] — the vertical counterpart
* [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter|Karpenter]] — node provisioning
* [[Kubernetes/concepts/L06-scheduling-scaling/09-cluster-autoscaler|Cluster Autoscaler]] — the older node provisioner
* [[Kubernetes/concepts/L06-scheduling-scaling/10-keda|KEDA]] — event-driven scaling
* [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PDB]] — availability during disruption
* [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource Requests & Limits]] — the foundation

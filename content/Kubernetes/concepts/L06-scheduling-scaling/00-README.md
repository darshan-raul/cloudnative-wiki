---
title: "L06 — Scheduling & Scaling"
tags: [kubernetes, k8s, scheduling, hpa, vpa, autoscaling]
date: 2026-06-06
description: Kubernetes scheduling and scaling — taints/tolerations, affinity, HPA, VPA, restart policies
---

# L06 — Scheduling & Scaling

Once pods exist, two questions: **where** should this pod run, and **how many** should I have? This level covers scheduling decisions and the autoscaling family.

## What you'll understand after this level

- The **kube-scheduler** flow: filter → score → bind
- **Taints and tolerations** — keeping pods off (or onto) specific nodes
- **Node affinity / pod anti-affinity** — schedule based on labels
- **Topology spread constraints** — spread replicas across zones/nodes
- **Resource requests vs limits** — what each does, QoS classes, the dangers of misconfiguration
- **HPA** (horizontal, scale replicas), **VPA** (vertical, resize requests), **Cluster Autoscaler** (add nodes) — what each does and doesn't
- **PodDisruptionBudgets** — keep services available during voluntary disruption
- **Restart policies** — `Always`, `OnFailure`, `Never` and when each applies

## Notes in this level

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling\|Scheduling]] | ✅ | Taints, tolerations, node/pod affinity, anti-affinity, topology spread |
| [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|Resource Requests & Limits]] | ✅ | requests vs limits, CPU/memory semantics, QoS classes, the limit debate |
| [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler\|HPA]] | ✅ | The autoscaling control loop, custom metrics, behavior settings, HPA vs VPA vs CA |
| [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget\|PodDisruptionBudget]] | ✅ | minAvailable/maxUnavailable, the eviction API, drain interaction |
| [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling\|Scaling]] | 🟡 | A high-level overview — superseded by the HPA note in depth |
| [[Kubernetes/concepts/L06-scheduling-scaling/06-restart-policy\|Restart Policy]] | ✅ | When kubelet restarts containers, when it doesn't |

## Suggested reading order

1. [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource Requests & Limits]] — the foundation; everything else assumes you have this
2. [[Kubernetes/concepts/L06-scheduling-scaling/06-restart-policy|Restart Policy]] — short, foundational
3. [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|Scheduling]] — read this before you deploy anything with constraints
4. [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] — when load changes
5. [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudget]] — before you start draining nodes
6. [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling|Scaling]] — high-level overview, useful as a quick-reference index

## Where to go next

→ [[Kubernetes/concepts/L07-security|L07 — Security]]: with workloads running, decide who can do what to them.

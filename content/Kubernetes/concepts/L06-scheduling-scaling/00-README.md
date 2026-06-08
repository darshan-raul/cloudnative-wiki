---
title: "L06 — Scheduling & Scaling"
tags: [kubernetes, k8s, scheduling, hpa, vpa, autoscaling, karpenter, keda, priority, preemption]
date: 2026-06-08
description: Kubernetes scheduling and scaling — taints/tolerations, affinity, HPA, VPA, Karpenter, KEDA, priority, preemption, the scheduler internals
---

# L06 — Scheduling & Scaling

Once pods exist, two questions: **where** should this pod run, and **how many** should I have? L06 covers both — the **scheduling primitives** (where Pods land) and the **scaling family** (how many Pods run, how much they get).

## What you'll understand after this level

- The **kube-scheduler** flow: PreFilter → Filter → PreScore → Score → Reserve → Permit → PreBind → Bind
- **Taints and tolerations** — keeping pods off (or onto) specific nodes
- **Node affinity / pod anti-affinity** — schedule based on labels
- **Topology spread constraints** — spread replicas across zones/nodes
- **PriorityClass and preemption** — the only signal the scheduler uses to evict a lower-priority Pod
- **Scheduling gates** — hold a Pod back from scheduling until an external signal
- **Resource requests vs limits** — what each does, QoS classes, cgroups, the limits debate
- **HPA** (horizontal scale replicas), **VPA** (vertical resize requests), **Cluster Autoscaler + Karpenter** (add nodes), **KEDA** (event-driven) — what each does and how they fit
- **PodDisruptionBudgets** — keep services available during voluntary disruption
- **Restart policies** — `Always`, `OnFailure`, `Never` and when each applies
- **Extended resources** — GPUs, FPGAs, and the device plugin model

## Notes in this level

### Scheduling primitives

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling\|Scheduling]] | ✅ | Taints, tolerations, node/pod affinity, anti-affinity, topology spread, all the operator semantics |
| [[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption\|Priority & Preemption]] | ✅ | PriorityClass, preemption algorithm, system classes, the PD deadlocks, QoS vs priority |
| [[Kubernetes/concepts/L06-scheduling-scaling/12-scheduler-internals\|Scheduler Internals]] | ✅ | The plugin pipeline, every default plugin, profiles, framework extensions, perf tuning |
| [[Kubernetes/concepts/L06-scheduling-scaling/13-scheduling-gates\|Scheduling Gates]] | ✅ | Pod scheduling readiness, holding Pods back, the StatefulSet join pattern |
| [[Kubernetes/concepts/L06-scheduling-scaling/14-extended-resources\|Extended Resources]] | ✅ | GPUs, device plugins, time-slicing, MIG, DRA, ResourceClaim, the integer rule |

### Resources and constraints

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|Resource Requests & Limits]] | ✅ | CPU/memory/ephemeral-storage, CFS throttling, OOM-kill, QoS classes, cgroup v2, the limits debate |
| [[Kubernetes/concepts/L06-scheduling-scaling/06-restart-policy\|Restart Policy]] | ✅ | Always / OnFailure / Never, the backoff algorithm, CrashLoopBackOff, exit codes, Job/CronJob behavior |

### Scaling family

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling\|Scaling — overview]] | ✅ | The L06 hub: HPA / VPA / Karpenter / CA / KEDA at a glance, how they combine |
| [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler\|HPA]] | ✅ | The autoscaling control loop, custom / external metrics, behavior settings, scaling math, the HPA controller |
| [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler\|VPA]] | ✅ | VPA modes (Off / Initial / Auto), the recommender, VPA + HPA coexistence, the OOM pattern |
| [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter\|Karpenter]] | ✅ | NodePools, EC2NodeClass, consolidation, spot, the modern alternative to Cluster Autoscaler |
| [[Kubernetes/concepts/L06-scheduling-scaling/09-cluster-autoscaler\|Cluster Autoscaler]] | ✅ | ASG / MIG / VMSS, scale-up and scale-down logic, the CA vs Karpenter decision |
| [[Kubernetes/concepts/L06-scheduling-scaling/10-keda\|KEDA]] | ✅ | Event-driven autoscaling, 60+ scalers, scale to zero, the external metrics API |
| [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget\|PodDisruptionBudget]] | ✅ | minAvailable / maxUnavailable, the eviction API, the HPA + PDB deadlock, unhealthyPodEvictionPolicy |

## Suggested reading order

### Scheduling path

1. [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource Requests & Limits]] — the foundation; everything else assumes you have this
2. [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|Scheduling]] — the YAML-level primitives (taints, affinity, topology)
3. [[Kubernetes/concepts/L06-scheduling-scaling/06-restart-policy|Restart Policy]] — short, foundational
4. [[Kubernetes/concepts/L06-scheduling-scaling/12-scheduler-internals|Scheduler Internals]] — the framework that enforces the above
5. [[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption|Priority & Preemption]] — when scheduling fails, what happens
6. [[Kubernetes/concepts/L06-scheduling-scaling/13-scheduling-gates|Scheduling Gates]] — advanced: hold a Pod back from scheduling
7. [[Kubernetes/concepts/L06-scheduling-scaling/14-extended-resources|Extended Resources]] — GPUs and the device plugin model

### Scaling path

1. [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling|Scaling — overview]] — at-a-glance comparison of all the scaling primitives
2. [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] — the workhorse
3. [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler|VPA]] — the right-sizing complement
4. [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PDB]] — read before you start draining nodes
5. [[Kubernetes/concepts/L06-scheduling-scaling/09-cluster-autoscaler|Cluster Autoscaler]] — the older node provisioner
6. [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter|Karpenter]] — the modern alternative
7. [[Kubernetes/concepts/L06-scheduling-scaling/10-keda|KEDA]] — event-driven, the right answer for queue-based workloads

## Where to go next

→ [[Kubernetes/concepts/L07-security|L07 — Security]]: with workloads scheduled and scaled, decide who can do what to them.

---
title: "L03 — Workloads"
tags: [kubernetes, k8s, workloads, pods, deployments, statefulsets]
date: 2026-06-06
description: Kubernetes workloads — Pods, Deployments, StatefulSets, DaemonSets, Jobs, CronJobs
---

# L03 — Workloads

Workloads are the **kinds of things you put in a cluster**. Each kind is a controller pattern with a specific reconciliation strategy. Master the layered model — Pod is the unit, everything else manages Pods.

## What you'll understand after this level

- A **Pod** is a unit of scheduling (1+ containers, shared network, shared volumes) — not a unit of deployment
- The **layered controllers**: Deployment → ReplicaSet → Pod
- When to use **Deployment** (stateless), **StatefulSet** (stable identity, ordered), **DaemonSet** (one per node), **Job/CronJob** (run-to-completion)
- The **static pod** pattern (kubelet-managed, bypasses the API)
- How **probes** (liveness / readiness / startup) keep traffic healthy
- **Init containers** for setup and gating
- **Multi-container patterns** — sidecar, ambassador, adapter

## Notes in this level

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L03-workloads/01-pods\|Pods]] | ✅ | The unit of scheduling, lifecycle phases, container probes, lifecycle hooks |
| [[Kubernetes/concepts/L03-workloads/02-replicaset\|ReplicaSet]] | ✅ | The lower-level controller a Deployment uses |
| [[Kubernetes/concepts/L03-workloads/03-deployments\|Deployments]] | 🟡 | Deployment → ReplicaSet → Pod layering, rollout strategies, rollbacks |
| [[Kubernetes/concepts/L03-workloads/04-statefulsets\|StatefulSets]] | 🟡 | Stable network IDs, ordered scaling, persistent storage per replica |
| [[Kubernetes/concepts/L03-workloads/05-daemonset\|DaemonSet]] | ✅ | One Pod per (selected) node — node agents, CNI, log shippers |
| [[Kubernetes/concepts/L03-workloads/06-job\|Job]] | ✅ | Run-to-completion batch workloads, completion modes, backoffLimit |
| [[Kubernetes/concepts/L03-workloads/07-cronjob\|CronJob]] | ✅ | Time-scheduled Jobs, concurrency policies, common gotchas |
| [[Kubernetes/concepts/L03-workloads/08-init-containers\|Init Containers]] | ✅ | Setup, gating, and migration before the main container starts |
| [[Kubernetes/concepts/L03-workloads/09-multi-container-pods\|Multi-Container Pods]] | ✅ | Sidecar / ambassador / adapter patterns, when to use each |
| [[Kubernetes/concepts/L03-workloads/10-probes\|Probes]] | ✅ | Liveness / readiness / startup — what each is for, common anti-patterns |
| [[Kubernetes/concepts/L03-workloads/11-static-pods\|Static Pods]] | ⚪ | Pods managed by kubelet directly (used by the control plane itself) |

## Suggested reading order

1. [[Kubernetes/concepts/L03-workloads/01-pods|Pods]] — what a Pod actually is, before any controller
2. [[Kubernetes/concepts/L03-workloads/10-probes|Probes]] — short, foundational, will keep coming up
3. [[Kubernetes/concepts/L03-workloads/03-deployments|Deployments]] — the default for any stateless service
4. [[Kubernetes/concepts/L03-workloads/02-replicaset|ReplicaSet]] — what a Deployment manages under the hood
5. [[Kubernetes/concepts/L03-workloads/04-statefulsets|StatefulSets]] — when stable identity matters (databases, queues)
6. [[Kubernetes/concepts/L03-workloads/09-multi-container-pods|Multi-Container Pods]] + [[Kubernetes/concepts/L03-workloads/08-init-containers|Init Containers]] — patterns for the Pod manifest
7. [[Kubernetes/concepts/L03-workloads/05-daemonset|DaemonSet]] — when you need one per node
8. [[Kubernetes/concepts/L03-workloads/06-job|Job]] → [[Kubernetes/concepts/L03-workloads/07-cronjob|CronJob]] — batch + scheduled workloads
9. [[Kubernetes/concepts/L03-workloads/11-static-pods|Static Pods]] — niche but illuminating (this is how control-plane components run)

## Where to go next

→ [[Kubernetes/concepts/L04-services-networking|L04 — Services & Networking]]: once you have Pods running, you need a way to reach them.

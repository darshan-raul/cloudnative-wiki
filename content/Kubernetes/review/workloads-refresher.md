---
title: "5-Minute Refresher: Workloads & Pod Lifecycle"
tags: [kubernetes, review, workloads, pods, deployments, rollout]
date: 2026-09-06
description: Rapid review of workload controller ownership, rolling updates, pod lifecycle conditions, and zero-downtime graceful termination.
aliases:
  - Kubernetes/review/workloads-refresher
---

# 5-Minute Refresher: Workloads & Pod Lifecycle

A rapid architectural review of workload ownership, rolling updates, and the graceful termination lifecycle.

```mermaid
graph TD
    DEP["Deployment (Declarative Rollout Strategy)"] -->|spec.replicas| RS["ReplicaSet (Exact Count Reconciliation)"]
    RS -->|spec.template| POD["Pod (Atomic Scheduling Unit)"]
    POD --> C1["Main App Container"]
    POD --> C2["Sidecar Container (restartPolicy: Always)"]

    classDef obj fill:#f9f9f9,stroke:#284b63,stroke-width:2px;
    class DEP,RS,POD obj;
```

---

## The RollingUpdate Handoff

When a Deployment is patched with a new container image or environment variable, the controller orchestrates a seamless handoff between two ReplicaSets:

```mermaid
sequenceDiagram
    autonumber
    participant D as Deployment Controller
    participant RS1 as Old ReplicaSet (v1)
    participant RS2 as New ReplicaSet (v2)
    participant EP as EndpointSlice Controller

    Note over D: Update triggered with maxSurge: 1, maxUnavailable: 0
    D->>RS2: Scale to 1 replica (Desired: 1, Total Pods = 3)
    RS2-->>EP: New Pod becomes Ready (passes readiness probe)
    EP-->>EP: Add New Pod IP to Service endpoints
    D->>RS1: Scale down to 1 replica (terminates 1 old pod)
    EP-->>EP: Remove Old Pod IP from endpoints
    D->>RS2: Scale to 2 replicas
    RS2-->>EP: Second New Pod becomes Ready
    D->>RS1: Scale down to 0 replicas (preserved in history for rollback)
```

---

## Graceful Termination & Zero-Downtime Rule

When a Pod is terminated, Kubernetes executes two independent operations **in parallel**:

```
Timeline:
T0: Pod marked Terminating in apiserver
    ├── Thread A: EndpointSlice controller removes Pod IP from Service routing (takes 1–5s to propagate)
    └── Thread B: Kubelet executes preStop hook → sends SIGTERM → waits terminationGracePeriodSeconds → sends SIGKILL
```

> [!IMPORTANT]
> If your application does not have a `preStop` hook with a brief delay (e.g. `sleep 5`), the application process might exit immediately upon receiving `SIGTERM` before kube-proxy and ingress proxies have completed updating their routing tables. This causes client requests to be sent to a dead socket, resulting in `502 Bad Gateway` drops.

### Recommended `preStop` Configuration:
```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 10 && app -s quit"]
```

---

## Modern Workload Features (v1.37 Baseline)

1. **Native Sidecars (GA in v1.29+):** Define long-running auxiliary sidecars inside `spec.initContainers` with `restartPolicy: Always`. They start before the main container and remain running until all other containers terminate.
2. **In-Place Pod Resize (GA in v1.37):** Change container CPU and memory requests/limits in-place without triggering pod recreation or disruption.

---

## Diagnostic Commands

```bash
# Rollout status and revision history
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>

# Instant rollback to previous version
kubectl rollout undo deployment/<name>

# Check granular pod readiness conditions
kubectl get pod <pod-name> -o jsonpath='{range .status.conditions[*]}{.type}{"="}{.status}{"\n"}{end}'
```

---

## Next Refresher

Proceed to **[[Kubernetes/review/networking-refresher|Networking, Services & Gateway API Refresher]]**.

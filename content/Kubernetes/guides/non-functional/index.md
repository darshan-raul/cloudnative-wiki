---
title: Non-Functional Requirements & Cluster Operations
tags: [kubernetes, guides, non-functional, operations, production, nfr]
date: 2026-09-06
description: Practical operating guides for non-functional requirements — scalability, resilience, security baseline, cost, and upgrades.
---

# Non-Functional Requirements & Production Readiness

Operational excellence guides addressing cluster architecture, reliability, governance, and capacity planning.

## Pillar Directory

### 1. Reliability & Availability
- [[Kubernetes/guides/non-functional/high-availability|High Availability]]: Control plane topologies, etcd quorum, multi-AZ nodes, and Pod Disruption Budgets (PDBs).
- [[Kubernetes/guides/non-functional/disaster-recovery|Disaster Recovery]]: RTO/RPO targets, multi-region failover, and cluster rebuild workflows.
- [[Kubernetes/guides/non-functional/backup-restore|Backup & Restore]]: Velero backups, etcd snapshots, volume snapshots, and verification drills.
- [[Kubernetes/guides/non-functional/chaos-engineering|Chaos Engineering]]: Validating cluster resilience using Chaos Mesh and LitmusChaos.

### 2. Scalability & Performance
- [[Kubernetes/guides/non-functional/auto-scaling|Autoscaling Strategy]]: Combining HPA (scale-to-zero), VPA, KEDA, and node provisioners (Karpenter / Cluster Autoscaler).
- [[Kubernetes/guides/non-functional/performance-tuning|Performance Tuning]]: Kernel limits, cgroup v2, kubelet parameters, and runtime configurations.
- [[Kubernetes/guides/non-functional/cost-optimization|Cost Optimization]]: Workload rightsizing, Spot instance management, and bin-packing.

### 3. Security & Governance
- [[Kubernetes/guides/non-functional/security-baseline|Security Baseline]]: Pod Security Standards, NetworkPolicy default-deny, and policy engines (Kyverno / OPA Gatekeeper).
- [[Kubernetes/guides/non-functional/multi-tenancy|Multi-Tenancy]]: Namespace boundaries, vCluster, quota enforcement, and network isolation.
- [[Kubernetes/guides/non-functional/oidc-integration|OIDC Authentication]]: Connecting enterprise IdPs (Okta, Keycloak, Dex) to the Kubernetes API server.

### 4. Lifecycle & Upgrades
- [[Kubernetes/guides/non-functional/upgrade-strategy|Upgrade Strategy]]: Zero-downtime control-plane and worker-node upgrades for self-managed and cloud clusters.
- [[Kubernetes/guides/non-functional/deprecations|API Deprecations]]: Detecting removed APIs, version gates, and migration schedules.

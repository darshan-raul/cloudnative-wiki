---
title: Kubernetes
tags: [kubernetes, k8s, container-orchestration, cloud-native, platform-engineering]
date: 2026-09-06
description: Comprehensive Kubernetes curriculum and deep-reference system — from container orchestration primitives to production operations and controller internals.
---

# Kubernetes ☸️

> [!NOTE] Current Baseline: Kubernetes 1.37 ("Garhwal", Released August 2026)
> This curriculum reflects the modern Kubernetes baseline:
> - **Gateway API** as the primary ingress standard following the community retirement of `ingress-nginx` in March 2026.
> - **nftables** as the primary `kube-proxy` direction alongside IPVS deprecation.
> - **EndpointSlices**, **cgroup v2**, **`metrics.k8s.io` GA**, and **DRA Extended Resources GA**.

---

## Choose Your Path

| Reader Intent | Where to Start | What You Will Get |
| :--- | :--- | :--- |
| **I am new to Kubernetes** | [[Kubernetes/concepts/L00-start-here/00-start-here\|00 — Start Here]] | Hands-on local cluster setup with `kind` and first workload deployment. |
| **I want a structured conceptual learning path** | [[Kubernetes/concepts/00-hub\|Concepts Hub (L00–L09)]] | 10-level sequential curriculum from primitives to controller internals. |
| **I need to fix a cluster or workload outage** | [[Kubernetes/guides/README#troubleshooting\|Troubleshooting Playbooks]] | Symptom-first diagnosis (`CrashLoopBackOff`, `Pod Pending`, DNS, PVC issues). |
| **I am hardening or preparing for production** | [[Kubernetes/concepts/L07-security/00-README\|L07 — Security]] & [[Kubernetes/guides/non-functional/security-baseline\|Security Baseline]] | Layered threat model, Pod Security Standards, NetworkPolicies, and admission control. |
| **I am running on AWS (EKS)** | [[Kubernetes/eks/README\|EKS Implementation Track]] | VPC CNI, IRSA, EKS Pod Identity, Karpenter, and EKS Auto Mode. |
| **I want tool & delivery walkthroughs** | [[Kubernetes/guides/README\|Guides Index]] | Helm, Kustomize, Argo CD, kubectl workflows, and k9s. |

---

## Curriculum Roadmap

```mermaid
flowchart TD
    L00["00 — Start Here\n(Mental Model, kind Cluster, First Workload)"] --> L01["01 — Architecture\n(Control Plane, Worker Nodes, Reconciliation)"]
    L01 --> L02["02 — Objects & API\n(Manifests, State, Labels, Downward API)"]
    L02 --> L03["03 — Workloads\n(Pods, Deployments, StatefulSets, Jobs)"]
    L03 --> L04["04 — Services & Networking\n(ClusterIP, DNS, Gateway API, CNI)"]
    L04 --> L05["05 — Config & Storage\n(ConfigMaps, Secrets, PVs, PVCs, CSI)"]
    L05 --> L06["06 — Scheduling & Scaling\n(Requests/Limits, Affinity, HPA, PDBs)"]
    L06 --> L07["07 — Security\n(RBAC, ServiceAccounts, PSS, NetworkPolicy)"]
    L07 --> L08["08 — Operations\n(Observability, Node Drains, Upgrades, Triage)"]
    L08 --> L09["09 — Advanced & Internals\n(CRDs, Operators, Finalizers, etcd, GC)"]

    subgraph DeepDives ["Practical Guides & Tracks"]
        G_Trouble["Troubleshooting Guides"]
        G_Delivery["GitOps & Helm Delivery"]
        G_EKS["EKS Implementation Track"]
    end

    L04 -.-> G_Delivery
    L07 -.-> G_EKS
    L08 -.-> G_Trouble

    style L00 fill:#e1f5fe,stroke:#0288d1,stroke-width:2px
    style L03 fill:#e8f5e9,stroke:#388e3c,stroke-width:2px
    style L04 fill:#fff3e0,stroke:#f57c00,stroke-width:2px
    style L07 fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    style L09 fill:#ede7f6,stroke:#512da8,stroke-width:2px
```

---

## Core Sections

### 1. Conceptual Curriculum (`concepts/`)
Sequential, provider-neutral fundamentals building a single mental model:
- [[Kubernetes/concepts/00-hub|00 — Concepts Hub]]: Roadmap and reading order.
- [[Kubernetes/concepts/L00-start-here/00-start-here|L00 — Start Here]]: Prerequisites, local cluster setup, and first deployment.
- [[Kubernetes/concepts/L01-architecture/00-README|L01 — Architecture]]: Control plane components, kubelet, and reconciliation loops.
- [[Kubernetes/concepts/L02-objects/00-README|L02 — Objects & API]]: Declarative API model, `spec` vs `status`, and schema validation.
- [[Kubernetes/concepts/L03-workloads/00-README|L03 — Workloads]]: Controller hierarchy from Pods to Deployments, StatefulSets, and Jobs.
- [[Kubernetes/concepts/L04-services-networking/00-README|L04 — Services & Networking]]: Service VIPs, EndpointSlices, CoreDNS, and Gateway API.
- [[Kubernetes/concepts/L05-config-storage/00-README|L05 — Config & Storage]]: ConfigMaps, Secrets, dynamic PersistentVolumes, and CSI.
- [[Kubernetes/concepts/L06-scheduling-scaling/00-README|L06 — Scheduling & Scaling]]: Resource QoS, placement constraints, HPA, and capacity management.
- [[Kubernetes/concepts/L07-security/00-README|L07 — Security]]: Identity, least-privilege RBAC, Pod Security Standards, and policy engines.
- [[Kubernetes/concepts/L08-operations/00-README|L08 — Operations]]: Systematic failure triage, observability hooks, node lifecycle, and day-2 ops.
- [[Kubernetes/concepts/L09-advanced/00-README|L09 — Advanced & Internals]]: CRDs, reconciliation loops, custom controllers, finalizers, and etcd.

### 2. Practical Guides (`guides/`)
- [[Kubernetes/guides/README|Guides Hub]]: Real-world implementation guides.
- **Troubleshooting:** [[Kubernetes/guides/troubleshooting/crashloop-backoff|CrashLoopBackOff]], [[Kubernetes/guides/troubleshooting/pod-pending|Pod Pending]], [[Kubernetes/guides/troubleshooting/service-unreachable|Service Unreachable]], [[Kubernetes/guides/troubleshooting/dns-resolution|DNS Resolution]], [[Kubernetes/guides/troubleshooting/pvc-stuck|PVC Stuck]], [[Kubernetes/guides/troubleshooting/node-not-ready|Node NotReady]].
- **Delivery & GitOps:** [[Kubernetes/guides/delivery/gitops/basics|GitOps Concepts]], [[Kubernetes/guides/delivery/gitops/argo-cd/README|Argo CD]], [[Kubernetes/guides/delivery/templating-patching/helm/README|Helm Series]], [[Kubernetes/guides/delivery/templating-patching/kustomize|Kustomize]].
- **Networking & Ingress:** [[Kubernetes/guides/networking/envoy-gateway|Envoy Gateway (Gateway API)]], [[Kubernetes/guides/networking/comparison|Service Mesh Comparison]], [[Kubernetes/guides/networking/istio|Istio]], [[Kubernetes/guides/networking/linkerd|Linkerd]].
- **Production Operations:** [[Kubernetes/guides/non-functional/high-availability|High Availability]], [[Kubernetes/guides/non-functional/auto-scaling|Autoscaling Strategy]], [[Kubernetes/guides/non-functional/security-baseline|Security Baseline]], [[Kubernetes/guides/non-functional/backup-restore|Backup & Restore]].

### 3. Provider Tracks
- [[Kubernetes/eks/README|AWS EKS Implementation Track]]: Cloud-specific implementations for IAM, VPC networking, storage classes, Karpenter node provisioning, and observability.

---

## Related Knowledge Bases

- [[Linux/virtualization/container-runtimes|Container Runtimes (CRI, containerd, runc)]]: The engine executing container processes.
- [[Linux]]: OS primitives powering containers (namespaces, cgroups v2, seccomp).
- [[Observability]]: Metrics, distributed tracing, and Prometheus/Grafana architecture.
- [[AWS]]: Cloud infrastructure, IAM, and VPC networking foundation.
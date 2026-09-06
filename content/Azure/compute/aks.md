---
title: Azure Kubernetes Service (AKS) Architecture Hub
description: Enterprise architecture hub for Azure Kubernetes Service (AKS) — Managed control planes, AKS Automatic, Azure CNI Overlay, Cilium eBPF, Application Gateway for Containers, Workload Identity, GPU AI infrastructure, and multi-cluster Fleets.
tags:
  - azure
  - compute
  - kubernetes
  - aks
  - containers
  - hub
---

# Azure Kubernetes Service (AKS) Architecture Hub ☸️☁️

**Azure Kubernetes Service (AKS)** is Microsoft's hyperscale managed Kubernetes platform. AKS abstracts control plane provisioning, automated patching, `etcd` multi-zone clustering, and high-availability operations while integrating deeply with **Azure Virtual Networks (VNet)**, **Microsoft Entra ID**, **Azure Monitor**, and the **Azure AI Supercomputing** infrastructure.

This hub serves as the master engineering directory for enterprise AKS architecture. Explore the dedicated deep-dive modules below for production configurations, CLI reference commands, performance quotas, cost models, and battle-tested gotchas.

---

## Architectural Master Index

```
                                AZURE KUBERNETES SERVICE (AKS)
                                              │
    ┌──────────────────┬──────────────────┬───┴──────────────┬──────────────────┬──────────────────┐
    │                  │                  │                  │                  │                  │
    ▼                  ▼                  ▼                  ▼                  ▼                  ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│CONTROL PLANE │ │  NETWORKING  │ │   COMPUTE    │ │   STORAGE    │ │   SECURITY   │ │  OPERATIONS  │
│& AUTOMATION  │ │  & TRAFFIC   │ │& ACCELERATORS│ │ CSI DRIVERS  │ │ & GOVERNANCE │ │  & FINOPS    │
├──────────────┤ ├──────────────┤ ├──────────────┤ ├──────────────┤ ├──────────────┤ ├──────────────┤
│• Automatic   │ │• Azure CNI   │ │• Hetero Pools│ │• Azure Disks │ │• Workload ID │ │• Observability
│• Tiers & SLA │ │• Cilium eBPF │ │• Autoscaling │ │• Azure Files │ │• Key Vault   │ │• Backup & DR │
│• Upgrades    │ │• Gateway API │ │• GPU / AI    │ │• Azure Blob  │ │• Azure Policy│ │• Runbook     │
│• Maintenance │ │• App Gateway │ │• Kueue Batch │ │• Elastic SAN │ │• Kata/SEV-SNP│ │• FinOps & RI │
└──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘
```

---

### 1. Control Plane, Automation & Upgrades
* **[[Azure/compute/aks/automatic-deep-dive|AKS Automatic Deep Dive]]** — Fully managed Kubernetes, Karpenter-powered Node Auto-Provisioning (NAP), automated weekly OS patch rollouts, SLA mechanics, and compute class economics.
* **[[Azure/compute/aks/cluster-tiers-sla|Cluster Tiers, High Availability Control Plane & Private Clusters]]** — Free vs Standard (99.95% SLA) vs Premium (LTS), API Server VNet Integration, Private Link clusters, and `etcd` Raft quorum across Availability Zones.
* **[[Azure/compute/aks/upgrades-maintenance|Upgrades, Maintenance Windows & Safe Rollout Strategies]]** — Node image auto-upgrades (`NodeImage`), Kubernetes auto-upgrades, planned maintenance windows, surge upgrade tuning (`maxSurge`), PDB deadlocks, and blue-green cluster rollouts.

### 2. Networking, Datapath & Traffic Routing
* **[[Azure/compute/aks/networking-cni|AKS Networking Deep Dive: Azure CNI, CNI Overlay & Pod Subnets]]** — Kubenet vs Azure CNI (Node Subnet) vs Azure CNI Overlay vs Dynamic Pod IP Allocation (Pod Subnet), IPAM allocation mechanics, packet routing, and subnet sizing.
* **[[Azure/compute/aks/cilium-ebpf|Azure CNI Powered by Cilium: eBPF Datapath, WireGuard & Hubble]]** — eBPF kernel datapath, `kube-proxy` iptables replacement, transparent WireGuard node-to-node encryption, Layer 7 CiliumNetworkPolicies, and Hubble deep observability.
* **[[Azure/compute/aks/ingress-appgw-gateway|AKS Ingress, Application Gateway for Containers & Gateway API]]** — AGIC vs Application Routing Add-on vs Application Gateway for Containers (AGfC), Gateway API controller (`HTTPRoute`), WAF v2 inspection, and Key Vault TLS termination.

### 3. Compute, Heterogeneous Pools & AI/ML Acceleration
* **[[Azure/compute/aks/node-pools-heterogeneous|Heterogeneous Node Pools: System vs User, Ephemeral OS & Azure Linux]]** — System vs User pools, Ephemeral OS disks on local NVMe/Cache, Azure Linux 3 vs Ubuntu, custom Kubelet/sysctl configurations, and Spot VM pool architectures.
* **[[Azure/compute/aks/autoscaling-keda|Autoscaling Architecture: Cluster Autoscaler, KEDA & Virtual Nodes]]** — Cluster Autoscaler (CA) tuning, Node Auto-Provisioning (NAP / Karpenter), HPA v2 with custom metrics, KEDA event-driven queue scalers, and Azure Virtual Nodes (ACI bursts).
* **[[Azure/compute/aks/gpu-orchestration-ai|GPU Orchestration for AI/ML: NVIDIA H100/A100, InfiniBand & KubeRay]]** — NVIDIA NC/ND-series VMs (H100, H200, A100), automated GPU driver extensions, Quantum-2 3.2 Tbps InfiniBand GPUDirect RDMA, KubeRay operator, and vLLM model serving.
* **[[Azure/compute/aks/batch-workloads|Batch Workloads, Job Orchestration & Kueue Scheduling]]** — IndexedJob API, Kueue multi-tenant queueing, fair-share scheduling, Spot instance preemption checkpointing, and gang scheduling.

### 4. Stateful Storage & CSI Drivers
* **[[Azure/compute/aks/storage-csi-disks|Azure Managed Disks, Premium SSD v2 & Elastic SAN CSI]]** — Azure Disk CSI driver (v2), Premium SSD v2, Ultra Disk, Azure Elastic SAN, online volume expansion, volume snapshots, and RWO failover tuning.
* **[[Azure/compute/aks/storage-csi-files-blob|Shared Storage CSI: Azure Files (NFS/SMB) & Azure Blob Storage]]** — Multi-pod ReadWriteMany (RWX) storage, Azure Files CSI driver (NFS v4.1 vs SMB), Azure Blob Storage CSI driver (BlobFuse2 vs NFS v3), POSIX compatibility, and high-throughput AI streaming.

### 5. Security, Identity, Governance & Isolation
* **[[Azure/compute/aks/security-workload-identity|Security Architecture & Microsoft Entra Workload Identity]]** — Keyless authentication, OIDC federated credentials, eliminating deprecated `aad-pod-identity`, Azure RBAC for Kubernetes Authorization, and PIM just-in-time access.
* **[[Azure/compute/aks/security-key-vault-csi|Secrets Management: Azure Key Vault Provider for Secrets Store CSI]]** — Azure Key Vault CSI driver add-on, in-memory `tmpfs` mounts, auto-syncing to Kubernetes Secret objects, secret auto-rotation, and FIPS 140-2 Level 3 HSM security.
* **[[Azure/compute/aks/governance-azure-policy|Governance: Azure Policy for Kubernetes & OPA Gatekeeper Guardrails]]** — Azure Policy add-on, Open Policy Agent (OPA) Gatekeeper, CIS Kubernetes benchmarks, custom Rego constraint templates, and audit vs deny enforcement modes.
* **[[Azure/compute/aks/multi-tenancy-isolation|Multi-Tenancy, Hard Isolation & Confidential Containers]]** — Soft vs Hard multi-tenancy, Pod Security Standards (PSS), Azure Linux Kata Containers (Hyper-V micro-VM isolation), and AMD SEV-SNP Confidential Containers.

### 6. Observability, DR, FinOps & Multi-Cluster Management
* **[[Azure/compute/aks/observability-monitoring|Observability: Container Insights, Managed Prometheus & ContainerLogV2]]** — Azure Monitor Container Insights, Azure Managed Prometheus, Azure Managed Grafana, ContainerLogV2 cost optimization, and KQL performance troubleshooting.
* **[[Azure/compute/aks/backup-disaster-recovery|Backup, Disaster Recovery & Cross-Region Business Continuity]]** — Azure Backup for AKS (managed Velero extension), BackupVault, VolumeSnapshot replication, cross-region disaster recovery, and multi-region active-active routing via Azure Front Door.
* **[[Azure/compute/aks/troubleshooting-runbook|SRE Troubleshooting & Incident Runbook]]** — Exit code taxonomy, Node NotReady triage, OOMKilled remediation, CNI IP exhaustion, Azure Disk attachment deadlocks, and `az aks` diagnostic tooling.
* **[[Azure/compute/aks/cost-optimization-finops|FinOps, Cost Allocation & Cloud Spend Optimization]]** — Microsoft Cost Management AKS Cost Allocation (namespace/pod splitting), Azure Savings Plans, Spot node pools, VPA rightsizing, and pause pod overprovisioning.
* **[[Azure/compute/aks/fleet-manager-multicluster|Azure Kubernetes Fleet Manager: Multi-Cluster Governance & MCS]]** — Azure Kubernetes Fleet Manager, staged rolling update runs, ClusterResourcePlacement, Multi-Cluster Services (MCS), and global Anycast load balancing.

---

## Quick Reference Architecture Cheat Sheet

| Requirement | Recommended Technology Pattern | Architecture Rationale |
| :--- | :--- | :--- |
| **New Production Cluster** | **Azure CNI Overlay + Cilium eBPF** | Zero VNet IP exhaustion, $O(1)$ routing, WireGuard encryption, and L7 Hubble metrics. |
| **Managed Set-and-Forget** | **AKS Automatic (`--sku automatic`)** | Auto-managed nodes via Karpenter, Azure Linux 3, automated weekly patching. |
| **Layer 7 Traffic Routing** | **Application Gateway for Containers (AGfC)**| Official Kubernetes Gateway API controller with sub-second xDS endpoint updates. |
| **Pod Cloud Credentials** | **Microsoft Entra Workload Identity** | Eliminates static credentials; leverages OIDC federation with short-lived tokens. |
| **Secret Management** | **Azure Key Vault Secrets Store CSI Driver** | Mounts secrets into in-memory `tmpfs` without persisting plain text in `etcd`. |
| **High-Performance DBs** | **Premium SSD v2 (`WaitForFirstConsumer`)**| Sub-millisecond latency; independently scales IOPS (up to 80,000) and throughput. |
| **Shared Multi-Pod State**| **Azure Files Premium NFS v4.1 (`nconnect=4`)**| Full Linux POSIX file locking; multiplexes parallel TCP connections for 10 GB/s. |
| **Multi-Cluster Federation**| **Azure Kubernetes Fleet Manager (Fleet Hub)** | Staged rolling updates across clusters and cross-cluster service discovery (MCS). |

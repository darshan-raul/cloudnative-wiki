---
title: Azure Compute Architecture Hub
description: Master architectural guide to Microsoft Azure compute services — Virtual Machines, VMSS, App Service, Azure Container Apps (ACA), Azure Kubernetes Service (AKS), and Azure Functions.
tags:
  - azure
  - compute
  - aks
  - containers
  - serverless
  - vm
date: 2026-10-15
---

# Azure Compute Architecture Hub 🖥️⚡

Microsoft Azure provides a comprehensive compute continuum spanning raw infrastructure-as-a-service (IaaS) virtual machines, managed serverless application runtimes, elastic container platforms, and hyperscale GPU clusters for artificial intelligence.

---

## Architectural Decision Framework

Selecting the optimal Azure compute platform requires balancing infrastructure control, operational overhead, cold-start latency, and scaling dynamics:

```
                                  Compute Requirement
                                           │
            ┌──────────────────────────────┴──────────────────────────────┐
            ▼                                                             ▼
    Containers / Cloud-Native                                   Legacy / Full OS / Monolith
            │                                                             │
    ┌───────┴───────┐                                             ┌───────┴───────┐
    ▼               ▼                                             ▼               ▼
Event-Driven   Microservices /                              Standard App    Scale & Elastic
Small Units     Full Kubernetes                             Single VM       Fault Domains
    │               │                                             │               │
    ▼               ▼                                             ▼               ▼
[[Azure/compute/functions|Azure Functions]]      ┌──────┴──────┐          [[Azure/compute/vm|Azure VM]]  [[Azure/compute/vm|VMSS]]
                            │             │
                    Low Complexity  Full Control
                            │             │
                            ▼             ▼
          [[Azure/compute/container-apps/README|Azure Container Apps]]  [[Azure/compute/aks|Azure Kubernetes Service (AKS)]]
```

### Compute Platform Comparison Matrix

| Service                                                                 | Abstraction Level                          | Scaling Mechanism                                | Networking & Isolation                                         | Primary Workload Fit                                                                 |
| :---------------------------------------------------------------------- | :----------------------------------------- | :----------------------------------------------- | :------------------------------------------------------------- | :----------------------------------------------------------------------------------- |
| **[[Azure/compute/vm\|Virtual Machines (VM) & VMSS]]**                  | Full IaaS (Linux/Windows OS)               | Horizontal Autoscale (VMSS metrics/schedule)     | Direct VNet NIC, Availability Zones, Proximity Placement       | Legacy monolithic apps, stateful clustering, custom kernel drivers, HPC.             |
| **[[Azure/compute/app-service/README\|Azure App Service]]**             | PaaS (Web & API Hosting)                   | Scale across App Service Plan instances          | Regional VNet integration, Private Endpoints, Deployment Slots | Web apps, REST APIs, enterprise web tiers needing zero-downtime blue/green slots.    |
| **[[Azure/compute/container-apps/README\|Azure Container Apps (ACA)]]** | Serverless Containers (Managed Envoy/KEDA) | Event-driven KEDA scalers (Scale to Zero)        | Managed VNet environment, internal service discovery, Dapr     | Microservices, background queue workers, event-driven containerized APIs.            |
| **[[Azure/compute/aks\|Azure Kubernetes Service (AKS)]]**               | Managed Kubernetes Engine                  | Cluster Autoscaler, Karpenter (NAP), HPA, KEDA   | Azure CNI, CNI Overlay, Cilium eBPF, Pod Subnets               | Complex multi-tier microservices, distributed stateful systems, high-density fleets. |
| **[[Azure/compute/functions\|Azure Functions]]**                        | Serverless FaaS (Event-driven)             | Scale Controller, Flex Consumption (up to 1,000) | Regional VNet integration, Private Endpoints                   | Webhooks, stream consumers, asynchronous ETL, event-driven reactive micro-tasks.     |

---

## Service Catalog

### 1. IaaS & Virtual Machines

- [[Azure/compute/vm|Virtual Machines & Scale Sets (VMSS)]] — VM series taxonomy (B, D, E, F, M, N), Flexible VMSS orchestration, Availability Zones vs Fault Domains, and Proximity Placement Groups.
- [[Azure/compute/vm/spot-vms|Azure Spot VMs & Scheduled Events]] — Surplus capacity at up to 90% discount, 30-second eviction handling via Scheduled Events API, and fault-tolerant batch architectures.

### 2. PaaS & Serverless Application Platforms

- [[Azure/compute/app-service/README|Azure App Service & Deployment Slots]] — Dedicated App Service Plans, zero-downtime deployment slots with traffic routing, custom domain TLS, and regional VNet integration.
- [[Azure/compute/container-apps/README|Azure Container Apps (ACA), KEDA & Dapr]] — Serverless containerized microservices built on AKS/Envoy, event-driven KEDA autoscaling, Dapr microservice sidecars, and scale-to-zero semantics.
- [[Azure/compute/functions|Azure Functions & Serverless Computing]] — Event-driven FaaS, Flex Consumption, Isolated Worker Model, Durable Functions stateful orchestrations, and cold-start optimization.

### 3. Managed Kubernetes (AKS Ecosystem)

- [[Azure/compute/aks|AKS Master Architecture Hub]] — Complete engineering guide indexing 22 specialized AKS deep dives:
  - [[Azure/compute/aks/automatic-deep-dive|AKS Automatic]] — Fully managed Kubernetes, Karpenter-powered Node Auto-Provisioning (NAP), automated weekly maintenance.
  - [[Azure/compute/aks/cluster-tiers-sla|Cluster Tiers & SLA]] — Free vs Standard (99.95% SLA) vs Premium (LTS), Private Link clusters, API Server VNet Integration.
  - [[Azure/compute/aks/networking-cni|Networking & CNI Overlay]] — Kubenet vs Azure CNI vs Azure CNI Overlay vs Dynamic Pod IP Allocation.
  - [[Azure/compute/aks/cilium-ebpf|Azure CNI Powered by Cilium]] — eBPF kernel datapath, kube-proxy replacement, WireGuard encryption, Hubble observability.
  - [[Azure/compute/aks/ingress-appgw-gateway|Ingress & Gateway API]] — Application Gateway for Containers (AGfC), Gateway API (`HTTPRoute`), and WAF v2.
  - [[Azure/compute/aks/node-pools-heterogeneous|Heterogeneous Node Pools]] — System vs User pools, Ephemeral OS disks on NVMe/Cache, Azure Linux 3, and Spot pools.
  - [[Azure/compute/aks/autoscaling-keda|Autoscaling Architecture]] — Cluster Autoscaler (CA), Node Auto-Provisioning (Karpenter), HPA v2, KEDA, and Virtual Nodes.
  - [[Azure/compute/aks/gpu-orchestration-ai|GPU AI/ML Infrastructure]] — NVIDIA H100/H200 (NDv5), Quantum-2 3.2 Tbps InfiniBand RDMA, KubeRay, and vLLM serving.
  - [[Azure/compute/aks/storage-csi-disks|Storage CSI (Disks)]] — Azure Managed Disks, Premium SSD v2, Ultra Disk, and Azure Elastic SAN.
  - [[Azure/compute/aks/storage-csi-files-blob|Shared Storage CSI (Files & Blob)]] — Multi-pod RWX, Azure Files NFS v4.1, and Azure Blob Storage BlobFuse2.
  - [[Azure/compute/aks/security-workload-identity|Entra Workload Identity]] — Keyless authentication, OIDC federated credentials, and Azure RBAC for Kubernetes.
  - [[Azure/compute/aks/security-key-vault-csi|Key Vault Secrets Store CSI]] — In-memory tmpfs mounts, secret auto-rotation, and FIPS 140-2 Level 3 HSM.
  - [[Azure/compute/aks/governance-azure-policy|Azure Policy & Gatekeeper]] — OPA Gatekeeper admission guardrails, CIS benchmarks, and custom Rego constraints.
  - [[Azure/compute/aks/multi-tenancy-isolation|Multi-Tenancy & Confidential Containers]] — PSS, Azure Linux Kata Containers (Hyper-V micro-VMs), and AMD SEV-SNP.
  - [[Azure/compute/aks/observability-monitoring|Observability & Monitoring]] — Azure Monitor Container Insights, Managed Prometheus, Grafana, and ContainerLogV2.
  - [[Azure/compute/aks/backup-disaster-recovery|Backup & Disaster Recovery]] — Azure Backup for AKS (managed Velero), BackupVault, and multi-region Active-Active Front Door.
  - [[Azure/compute/aks/troubleshooting-runbook|SRE Troubleshooting Runbook]] — Exit code taxonomy (137 OOMKilled), Node NotReady triage, and CNI IP exhaustion.
  - [[Azure/compute/aks/cost-optimization-finops|FinOps & Cost Allocation]] — Microsoft Cost Management AKS Cost Allocation, Savings Plans, and pause pod overprovisioning.
  - [[Azure/compute/aks/fleet-manager-multicluster|Azure Kubernetes Fleet Manager]] — Staged rolling update runs across clusters and Multi-Cluster Services (MCS).

---

## Multi-Cloud Equivalents

| Capability                | Microsoft Azure                                                     | Amazon Web Services (AWS)          | Google Cloud Platform (GCP)           |
| :------------------------ | :------------------------------------------------------------------ | :--------------------------------- | :------------------------------------ |
| **Virtual Machines**      | [[Azure/compute/vm\|Azure Virtual Machines]]                        | Amazon EC2                         | Compute Engine                        |
| **Scale Sets**            | [[Azure/compute/vm\|Virtual Machine Scale Sets (VMSS)]]             | EC2 Auto Scaling Groups (ASG)      | Managed Instance Groups (MIG)         |
| **Web PaaS**              | [[Azure/compute/app-service/README\|Azure App Service]]             | AWS Elastic Beanstalk / App Runner | App Engine                            |
| **Serverless Containers** | [[Azure/compute/container-apps/README\|Azure Container Apps (ACA)]] | AWS App Runner / ECS Fargate       | Cloud Run                             |
| **Managed Kubernetes**    | [[Azure/compute/aks\|Azure Kubernetes Service (AKS)]]               | Amazon EKS                         | Google Kubernetes Engine (GKE)        |
| **Serverless Functions**  | [[Azure/compute/functions\|Azure Functions]]                        | AWS Lambda                         | Cloud Functions / Cloud Run functions |

---
title: Azure Kubernetes Service (AKS)
description: AKS architecture — Azure CNI vs Kubenet vs CNI Overlay, Cilium eBPF dataplane, System vs User node pools, Ephemeral OS disks, and Workload Identity.
tags:
  - azure
  - compute
  - kubernetes
  - aks
  - containers
---

# Azure Kubernetes Service (AKS) ☸️

Azure Kubernetes Service (AKS) is Microsoft's managed Kubernetes platform. AKS handles the complexity of control plane provisioning, automated patching, etcd clustering, and multi-zone resilience while providing deep native integration with **Azure Virtual Networks (Azure CNI)**, **Microsoft Entra ID**, and **Azure Monitor**.

---

## Architecture & Mental Model

### Network Plugin Comparison: Azure CNI vs. CNI Overlay vs. Kubenet

Choosing the networking model is the most critical Day-0 architectural decision when provisioning an AKS cluster:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   1. Azure CNI (Node-Assigned)                         │
│ Every Pod consumes a real, routable IP from your corporate VNet Subnet.│
│ Pro: Direct VNet routability. Con: Severe Subnet IP Exhaustion!        │
├────────────────────────────────────────────────────────────────────────┤
│                   2. Azure CNI Overlay (Modern Default)                │
│ Nodes get VNet IPs; Pods get private overlay IPs (e.g. 192.168.0.0/16).│
│ Pro: Zero VNet IP exhaustion + wire-speed routing + scales to 1,000s   │
├────────────────────────────────────────────────────────────────────────┤
│                   3. Azure CNI Powered by Cilium                       │
│ Uses Linux kernel eBPF bytecode for routing, replacing kube-proxy      │
│ iptables. Built-in Cilium Network Policies and L7 Hubble observability.│
└────────────────────────────────────────────────────────────────────────┘
```

---

## Networking Decision Matrix

| Dimension | Kubenet | Traditional Azure CNI | Azure CNI Overlay (Recommended) |
| :--- | :--- | :--- | :--- |
| **Pod IP Source** | Virtual overlay CIDR | **VNet Subnet IP Pool** | Independent private overlay CIDR |
| **VNet IP Consumption** | Only Node VMs consume VNet IPs | **Nodes + All Pods** consume VNet IPs | **Only Node VMs** consume VNet IPs |
| **Subnet Size Requirement** | Small (`/24` or `/23`) | **Massive (`/20` or `/19`)** | Small (`/24` or `/23`) |
| **Pod Reachability from VNet** | Requires NAT (not directly reachable) | Directly reachable via VNet IP | Reachable through Kubernetes Services |
| **Max Scale** | Limited to 400 nodes | Subnet IP bound | **5,000 nodes** |

---

## Core Concepts

### 1. System Node Pools vs. User Node Pools

Production AKS architectures isolate control components from application code:
* **System Node Pool:** Dedicated exclusively to running critical Kubernetes pods (`CoreDNS`, `metrics-server`, `konnectivity-agent`). Automatically tainted with `CriticalAddonsOnly=true:NoSchedule`.
* **User Node Pools:** Dedicated to customer applications and microservices. Can be sized with specialized VM series (e.g., GPU compute, high-memory, Spot instances).

### 2. Ephemeral OS Disks

Traditional AKS nodes host their root operating system on remote Azure Managed Disks (Persistent Storage).
* **Ephemeral OS Disks (Production Standard):**
  * The node OS disk is placed directly on the physical host VM's local NVMe or SSD cache.
  * Delivers near-zero disk latency, faster read/write speeds, and dramatically faster node provisioning and re-imaging times during auto-scaling events.
  * Incurs **zero storage disk cost**.

### 3. Cluster Tiers & Uptime SLA

* **Free Tier:** Free cluster management. No financial SLA on the Kubernetes control plane. Suitable for development and testing.
* **Standard Tier ($0.10 / hour):** Includes a financially backed **99.95% control plane uptime SLA** for clusters using Availability Zones (99.9% without AZs).
* **Premium Tier:** Adds long-term support (LTS) for older Kubernetes versions and automated enterprise guardrails.

---

## Production `az` CLI Commands

### 1. Provisioning a Production Multi-Zone AKS Cluster with CNI Overlay & Cilium

```bash
# Create AKS cluster in custom VNet with CNI Overlay and Cilium
az aks create \
  --resource-group prod-aks-rg \
  --name prod-core-aks \
  --location eastus \
  --tier standard \
  --node-count 3 \
  --zones 1 2 3 \
  --vnet-subnet-id "/subscriptions/sub-123/resourceGroups/prod-net-rg/providers/Microsoft.Network/virtualNetworks/prod-vnet/subnets/snet-aks-nodes" \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --network-dataplane cilium \
  --pod-cidr 192.168.0.0/16 \
  --service-cidr 10.240.0.0/16 \
  --dns-service-ip 10.240.0.10 \
  --enable-managed-identity \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --enable-cluster-autoscaler \
  --min-count 3 \
  --max-count 10 \
  --node-osdisk-type Ephemeral \
  --node-osdisk-size 64 \
  --node-vm-size Standard_D4ds_v5
```

### 2. Adding a User Node Pool with Spot VMs for Batch Workloads

```bash
az aks nodepool add \
  --resource-group prod-aks-rg \
  --cluster-name prod-core-aks \
  --name spotpool \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --node-vm-size Standard_D8s_v5 \
  --enable-cluster-autoscaler \
  --min-count 0 \
  --max-count 20 \
  --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max nodes per cluster** | 5,000 nodes | Using Azure CNI Overlay |
| **Max node pools per cluster** | 100 node pools | Supports diverse VM types |
| **Default max pods per node** | 110 pods (Azure CNI) | Configurable up to 250 pods/node |
| **Control plane SLA (Standard Tier)** | 99.95% availability | Requires multi-zone node pools |
| **Ephemeral OS disk minimum VM size** | Standard_D4ds_v5 or higher | Must have sufficient local cache size |

---

## References

* **Homepage:** https://azure.microsoft.com/en-us/products/kubernetes-service
* **AKS Documentation:** https://learn.microsoft.com/en-us/azure/aks/
* **Azure CNI Overlay Guide:** https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay
* **Azure CNI Powered by Cilium:** https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium
* **Pricing:** https://azure.microsoft.com/en-us/pricing/details/kubernetes-service/

---

## Pricing Examples

### Scenario 1: Production Multi-Zone AKS Cluster (Standard Tier)
* Control Plane: Standard Tier Uptime SLA ($0.10 / hr × 730 hrs = **$73.00 / month**).
* Worker Nodes: 6 instances of `Standard_D4ds_v5` (4 vCPU, 16 GB RAM) across 3 zones.
* Compute: 6 × ~$140.00 / month = **$840.00 / month**.
* OS Storage: **$0.00** (Using local Ephemeral OS disks).
* Egress and Azure Load Balancer: ~$50.00.
* **Total Monthly Cost:** $73 + $840 + $50 = **~$963.00 / month**.

### Scenario 2: Batch Analytics on AKS Spot Node Pool
* 20 instances of `Standard_D8s_v5` (8 vCPU, 32 GB RAM) processing batch queues for 4 hours every night (120 hours / month).
* Standard On-Demand cost: 20 × $0.384 / hr × 120 hrs = $921.60.
* Spot discount (~80% savings): 20 × $0.0768 / hr × 120 hrs = **$184.32 / month**.
* **Monthly Savings:** **$737.28** per month.

---

## Nuggets & Gotchas

1. **The Traditional Azure CNI Subnet Exhaustion Trap:** In traditional Azure CNI, every pod requires an IP address allocated directly from your VNet subnet. If you deploy a 50-node cluster with default `max-pods=110`, Azure immediately reserves **5,500 private IP addresses** from your corporate subnet upon cluster creation! If the subnet does not have 5,500 free IPs, deployment fails. **Always choose Azure CNI Overlay for new clusters.**
2. **Never Run Application Workloads on the System Node Pool:** The System Node Pool runs cluster-critical pods like `coredns` and `konnectivity-agent`. If customer microservices experience memory leaks or CPU starvation on the system nodes, core DNS resolution fails and the entire cluster enters a degraded state. Always maintain separate User Node Pools for applications.
3. **Control Plane Upgrades and `maxSurge` Disruption:** During AKS version upgrades, Azure uses a rolling node replacement strategy governed by `maxSurge` (default: 1 extra node). If you have Pod Disruption Budgets (`PDBs`) requiring 100% of pods available (`minAvailable: 100%`), AKS cannot evict pods from upgrading nodes, causing cluster upgrades to stall and time out after 1 hour.
4. **Service CIDR and Pod CIDR Can Never Overlap:** The `--service-cidr` (ClusterIP range) and `--pod-cidr` must not overlap with each other, with the host VNet subnet, with any peered VNet, or with on-premises networks. If you specify an overlapping CIDR, routing loops will cause pods to fail reaching external APIs.
5. **Ephemeral OS Disks Require Specific VM Sizes:** To enable Ephemeral OS disks, the selected VM size must have a local temporary cache larger than the OS disk size (typically >= 64 GB). Selecting small instances like `Standard_B2s` will cause ephemeral disk provisioning to fail with `EphemeralDiskNotSupportedForVmSize`.

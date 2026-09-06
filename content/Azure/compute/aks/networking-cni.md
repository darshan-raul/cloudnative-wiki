---
title: AKS Networking Deep Dive — Azure CNI, CNI Overlay, and Dynamic Pod IP Allocation
description: Exhaustive engineering guide to AKS network plugins — Kubenet vs Azure CNI (Node Subnet) vs Azure CNI Overlay vs Dynamic Pod IP Allocation (Pod Subnet), IPAM allocation mechanics, packet routing, and subnet sizing.
tags:
  - azure
  - aks
  - networking
  - cni
  - cni-overlay
  - ipam
  - routing
---

# AKS Networking Deep Dive — Azure CNI, CNI Overlay, and Dynamic Pod IP Allocation 🌐🔌

Networking architecture is the most critical and irreversible Day-0 design choice when provisioning an Azure Kubernetes Service (AKS) cluster. Selecting the wrong network plugin can lead to **premature corporate VNet IP exhaustion**, routing deadlocks, or artificial scale ceilings. Modern AKS offers three primary networking paradigms: **Traditional Azure CNI (Node Subnet)**, **Azure CNI with Dynamic Pod IP Allocation (Pod Subnet)**, and **Azure CNI Overlay (Modern Production Standard)**.

---

## 1. Network Topology Comparison & Packet Flow

The fundamental distinction between AKS network plugins lies in whether Pod IP addresses are allocated directly from the customer's corporate Azure VNet or from an isolated, private overlay address space.

```
═════════════════════════════════════════════════════════════════════════════════
1. TRADITIONAL AZURE CNI (Node Subnet Allocation)
Workload: Pods consume real, routable IPs from the Node VNet Subnet (10.100.0.0/20)
Result: Massive IP exhaustion. A 50-node cluster consumes 5,500 VNet IPs upfront!

  Node VM: 10.100.0.4 ──────► Pod 1: 10.100.0.5  (Consumes corporate VNet IP)
                      ──────► Pod 2: 10.100.0.6  (Consumes corporate VNet IP)
═════════════════════════════════════════════════════════════════════════════════
2. AZURE CNI WITH POD SUBNET (Dynamic Pod IP Allocation)
Workload: Nodes live in Node Subnet; Pods live in a separate dedicated Pod Subnet.
Benefit: Isolates pod IP consumption; avoids wasting node subnet IPs.

  Node Subnet (10.100.0.0/24) ──► Node VM: 10.100.0.4
  Pod Subnet  (10.200.0.0/18) ──► Pod 1: 10.200.0.12 (Direct VNet routing)
═════════════════════════════════════════════════════════════════════════════════
3. AZURE CNI OVERLAY (Modern Production Default)
Workload: Nodes get VNet IPs; Pods receive private, non-routable Overlay IPs.
Traffic between nodes is encapsulated via Geneve/VXLAN tunnels.
Benefit: ZERO corporate VNet IP exhaustion. Scales to 5,000 nodes on a /24 subnet!

  Node VNet: 10.100.0.4 ────► Pod 1: 192.168.1.15 (Private Overlay CIDR)
  Node VNet: 10.100.0.5 ────► Pod 2: 192.168.2.20 (Private Overlay CIDR)
═════════════════════════════════════════════════════════════════════════════════
```

---

## 2. Comprehensive Network Plugin Comparison Matrix

| Architectural Parameter | Kubenet | Traditional Azure CNI | Azure CNI (Pod Subnet) | Azure CNI Overlay (Recommended) |
| :--- | :--- | :--- | :--- | :--- |
| **Pod IP Source** | User-defined overlay CIDR | **Host Node Subnet** | Dedicated Pod Subnet | **Independent Overlay CIDR** |
| **VNet IP Consumption** | Nodes only (e.g., 50 IPs) | **Nodes + All Pods** (e.g., 5,550 IPs)| **Nodes + Pods** (Dual subnets) | **Nodes only** (e.g., 50 IPs) |
| **Corporate Subnet Sizing**| `/24` (251 usable IPs) | **`/19` or `/18` (8,000+ IPs)** | Node `/24`, Pod `/18` | **`/24` (251 usable IPs)** |
| **Pod-to-Pod Cross-Node** | Linux Bridge + UDR routes | Native VNet wire-speed | Native VNet wire-speed | **Encapsulated Geneve/VXLAN** |
| **Pod Reachable from VNet**| No (requires NAT / Ingress)| **Yes (Directly routable)** | **Yes (Directly routable)** | No (Requires Service / Ingress)|
| **Max Cluster Scale** | 400 nodes (UDR limit) | Subnet IP bound | Subnet IP bound | **5,000 nodes** |
| **Dual-Stack IPv6** | No | Yes | No | **Yes (GA)** |
| **Cilium eBPF Support** | No | No | Yes | **Yes (Native)** |

---

## 3. Engineering Mechanics: Inside the Linux Datapath

### Azure CNI Overlay Datapath
When Pod A on Node 1 (`192.168.1.15`) communicates with Pod B on Node 2 (`192.168.2.20`):
1. **Local Egress:** Pod A pushes packets into its network namespace virtual ethernet interface (`eth0`).
2. **Host Routing:** The host kernel inspects the destination IP (`192.168.2.20`). The Linux routing table matches the route installed by Azure CNI:
   ```bash
   192.168.2.0/24 via 10.100.0.5 dev azure0
   ```
3. **Encapsulation:** The host kernel wraps the inner IP packet into an outer Geneve or VXLAN packet where:
   - Source IP = `10.100.0.4` (Node 1 VNet IP)
   - Destination IP = `10.100.0.5` (Node 2 VNet IP)
4. **Wire Transit:** The Azure physical software-defined network (SDN) routes the outer packet at line speed across Azure datacenters. Azure switches see only the Node VNet IPs, completely ignoring the internal pod overlay CIDR.
5. **Decapsulation:** Node 2 receives the packet, strips the outer Geneve header, and delivers the raw frame to Pod B's `eth0`.

---

## 4. Production Deployment & CLI Operations (`az` CLI)

### 1. Provision Multi-Zone Cluster with Azure CNI Overlay and Cilium eBPF

```bash
# Provision Azure CNI Overlay cluster with Cilium dataplane
az aks create \
    --resource-group rg-prod-network \
    --name aks-overlay-prod \
    --location eastus \
    --tier standard \
    --zones 1 2 3 \
    --node-count 6 \
    --node-vm-size Standard_D4ds_v5 \
    --node-osdisk-type Ephemeral \
    --vnet-subnet-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod-network/providers/Microsoft.Network/virtualNetworks/vnet-eastus/subnets/snet-aks-nodes" \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --network-dataplane cilium \
    --pod-cidr 192.168.0.0/16 \
    --service-cidr 10.240.0.0/16 \
    --dns-service-ip 10.240.0.10 \
    --max-pods 110 \
    --enable-managed-identity
```

### 2. Provision Cluster with Dynamic Pod IP Allocation (Pod Subnet)

Use this pattern when enterprise security firewalls mandate that every pod must have a routable, non-NATted corporate VNet IP for inspection:

```bash
# Provision cluster with separate subnets for Nodes and Pods
az aks create \
    --resource-group rg-prod-network \
    --name aks-podsubnet-prod \
    --location eastus \
    --node-count 3 \
    --node-vm-size Standard_D4ds_v5 \
    --vnet-subnet-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod-network/providers/Microsoft.Network/virtualNetworks/vnet-eastus/subnets/snet-nodes" \
    --pod-subnet-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod-network/providers/Microsoft.Network/virtualNetworks/vnet-eastus/subnets/snet-pods" \
    --network-plugin azure \
    --service-cidr 10.240.0.0/16 \
    --dns-service-ip 10.240.0.10 \
    --max-pods 110 \
    --enable-managed-identity
```

### 3. Verify Node Routing & Pod CIDR Allocations

```bash
# Connect to AKS cluster
az aks get-credentials --resource-group rg-prod-network --name aks-overlay-prod

# Inspect per-node allocated pod CIDRs (/24 assigned to each node)
kubectl get nodes -o custom-columns=NAME:.metadata.name,POD_CIDR:.spec.podCIDR,INTERNAL_IP:.status.addresses[0].address
```

---

## 5. Quotas, Performance & Configuration Limits

| Dimension / Metric | Hard Limit | Production Impact |
| :--- | :--- | :--- |
| **Max Nodes (Overlay)** | **5,000 nodes** | Single cluster capacity without VNet IP exhaustion |
| **Max Nodes (Kubenet)** | **400 nodes** | Azure Route Table (UDR) limit of 400 routes |
| **Default Max Pods per Node**| **110 pods** (Azure CNI) / **30** (Kubenet)| Configurable between 10 and 250 pods/node |
| **Pod Subnet CIDR Sizing** | Minimum `/24` per node pool | Must contain sufficient IPs for `nodeCount × maxPods` |
| **Encapsulation Overhead** | **~50 bytes** (Geneve/VXLAN header)| AKS automatically configures MTU to **1450** |
| **Overlay IP Space** | Private non-overlapping CIDR | e.g., `192.168.0.0/16` or `100.64.0.0/10` (CGNAT) |

---

## 6. Official References

- [Azure CNI Overlay Documentation](https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay)
- [Azure CNI with Dynamic Pod IP Allocation (Pod Subnet)](https://learn.microsoft.com/en-us/azure/aks/configure-azure-cni)
- [Compare Network Models in AKS](https://learn.microsoft.com/en-us/azure/aks/concepts-network)
- [Azure Kubernetes Service Limits](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#azure-kubernetes-service-limits)

---

## 7. Realistic Pricing Scenarios

### Scenario A: Corporate Multi-Tenant Cluster (100 Nodes, 4,000 Pods)

- **Network Architecture:** Azure CNI Overlay.
- **IP Resource Savings:**
  - Traditional Azure CNI requires: $100 \text{ nodes} + (100 \times 110 \text{ pods}) = \mathbf{11,100 \text{ VNet IPs}}$ (a `/18` corporate CIDR block, costing significant enterprise planning).
  - Azure CNI Overlay requires: $100 \text{ nodes} + 5 \text{ Azure reserved} = \mathbf{105 \text{ VNet IPs}}$ (comfortably fits in a standard `/24` subnet).
- **Monthly Network Infrastructure Cost:**
  - Standard Azure Internal Load Balancer: Free.
  - Azure Standard Public Load Balancer (Outbound SNAT): ~$18.00 / month.
  - Cross-Availability Zone Network Egress: 50 TB/mo × $0.01/GB = **$500.00 / month**.
- **Total Network Infrastructure Cost:** **$518.00 / month**

### Scenario B: Regulatory Regime with Pod Subnet and Azure Firewall

- **Network Architecture:** Azure CNI with Pod Subnet routed through centralized Azure Firewall Premium.
- **Resource Footprint:**
  - 20 nodes with 500 pods.
  - All pod egress inspected at Layer 7 by Azure Firewall.
- **Monthly Cost Breakdown:**
  - Azure Firewall Premium Base: $1.75/hr × 730 hrs = **$1,277.50**
  - Data Processing Fee: 10 TB × $0.016/GB = **$160.00**
  - Azure Load Balancer: ~$18.00
- **Total Network Cost:** **$1,455.50 / month**

---

## 8. Battle-Tested Nuggets & Production Gotchas

1. **The Traditional Azure CNI Upfront Allocation Trap:** In traditional Azure CNI, IP addresses are reserved **upfront** per node based on `--max-pods` (default: 30 or 110), regardless of how many pods are actually running! A 20-node cluster with `max-pods=110` consumes 2,200 private IP addresses immediately upon startup. If your subnet runs out of IPs during autoscaling, new nodes fail to join the cluster with `FailedToAllocateIPAddress`. **Always use Azure CNI Overlay for new architectures.**
2. **Geneve MTU Mismatch & Silent Packet Drops:** Azure CNI Overlay encapsulates pod packets in Geneve headers, reducing effective MTU by 50 bytes (standard Ethernet MTU is 1500; Overlay MTU is 1450). If an application inside a pod attempts to send frames with the `Don't Fragment` (DF) bit set at 1500 bytes (e.g., certain legacy NFS clients or raw UDP video streamers), packets are silently dropped without an ICMP `Fragmentation Needed` response reaching the container. Ensure applications respect MTU 1450.
3. **Pod CIDR Overlap with On-Premises Networks:** Even though the `--pod-cidr` in Azure CNI Overlay is not routable directly outside the cluster, **it must never overlap with any on-premises CIDR, peered VNet, or Azure service CIDR** that pods need to reach. If your `--pod-cidr` is `10.0.0.0/16` and your on-premises datacenter database lives on `10.0.50.10`, the host Linux kernel will assume the target database is an internal pod and drop the packet locally!
4. **Cannot Switch Network Plugins Post-Creation:** AKS does **not support converting an existing cluster from Kubenet or Traditional Azure CNI to Azure CNI Overlay in place**. Changing the network plugin requires provisioning a fresh AKS cluster and migrating workloads via DNS cutover.
5. **Kubenet 400-Node Scale Ceiling:** Kubenet creates an Azure Route Table (UDR) in the node resource group and injects one route per node. Because Azure Route Tables have a hard platform limit of **400 user-defined routes per table**, Kubenet clusters can never scale past 400 nodes.

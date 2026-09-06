---
title: Azure Virtual Network (VNet) & Hybrid Routing
description: Azure VNet architecture — regional VNets, 5 reserved subnet IPs, VNet Peering with Gateway Transit, User Defined Routes (UDRs), NAT Gateway, and Private Endpoints.
tags:
  - azure
  - networking
  - vnet
  - hybrid
  - security
---

# Azure Virtual Network (VNet) & Hybrid Routing 🌐

An Azure Virtual Network (VNet) is the fundamental building block for private networks in Microsoft Azure. A VNet is **regionally scoped** (bound to a single Azure region), while its subnets naturally span across all three availability zones within that region.

Azure VNets isolate compute workloads, enable cross-subscription peering over Microsoft's global fiber backbone, and connect seamlessly to on-premises datacenters via ExpressRoute or VPN gateways.

---

## Architecture & Mental Model

### Hub-and-Spoke Topology with Gateway Transit

```
┌────────────────────────────────────────────────────────────────────────┐
│                      Hub VNet (Region: East US)                        │
│                                                                        │
│   ┌───────────────────────────┐      ┌──────────────────────────────┐  │
│   │ GatewaySubnet (/27)       │      │ AzureFirewallSubnet (/26)    │  │
│   │ ExpressRoute / VPN Gateway│◄────►│ Azure Firewall NVA           │  │
│   │ (allow-gateway-transit)   │      │ (Central Egress / Inspection)│  │
│   └─────────────▲─────────────┘      └──────────────▲───────────────┘  │
└─────────────────┼───────────────────────────────────┼──────────────────┘
                  │ VNet Peering                      │ VNet Peering
                  │ (use-remote-gateways)             │ (UDR NextHop: Firewall)
        ┌─────────┴───────────────┐         ┌─────────┴───────────────┐
        ▼                         ▼         ▼                         ▼
┌─────────────────────────┐             ┌─────────────────────────┐
│ Spoke VNet A (App Tier) │             │ Spoke VNet B (Data Tier)│
│ Subnet: 10.1.0.0/24     │             │ Subnet: 10.2.0.0/24     │
│ (AKS / Virtual Machines)│             │ (Private Endpoints)     │
└─────────────────────────┘             └─────────────────────────┘
```

* **Non-Transitive Peering:** Spoke VNet A cannot communicate directly with Spoke VNet B across standard VNet peering. Traffic must route through the Hub's central Network Virtual Appliance (NVA / Azure Firewall) via **User Defined Routes (UDRs)**.

---

## Core Concepts

### 1. The 5 Reserved IP Addresses per Subnet

In every Azure subnet, Microsoft permanently reserves **5 IP addresses**. A `/24` subnet (256 theoretical addresses) yields only **251 usable IP addresses**:

* `x.x.x.0`: Network address.
* `x.x.x.1`: Default gateway assigned to the subnet router.
* `x.x.x.2`, `x.x.x.3`: Azure DNS mapping addresses (used by Azure to resolve internal DNS and Azure PaaS endpoints).
* `x.x.x.255`: Network broadcast address (Azure virtual networks do not broadcast, but the address is reserved).

### 2. VNet Peering & Gateway Transit

VNet Peering connects two VNets directly over Microsoft's private network backbone with sub-millisecond latency:
* **Regional Peering:** Between VNets within the same Azure region.
* **Global VNet Peering:** Between VNets in different Azure regions across continents.
* **Gateway Transit:** Allows spoke VNets to share a single, costly ExpressRoute or VPN Gateway located in the hub VNet:
  * Hub sets: `--allow-gateway-transit`
  * Spoke sets: `--use-remote-gateways`

### 3. Route Tables & User Defined Routes (UDRs)

Azure automatically provisions **System Routes** that route traffic between subnets within the same VNet, between peered VNets, and out to the internet. **User Defined Routes (UDRs)** override these system defaults:

| Next Hop Type | Purpose | Production Use Case |
| :--- | :--- | :--- |
| **VirtualAppliance** | Routes traffic to a private IP (e.g. Azure Firewall, Palo Alto, Fortinet) | Force all internet-bound traffic through central firewall |
| **VirtualNetworkGateway** | Routes traffic to an on-premises VPN or ExpressRoute | Hybrid connectivity |
| **None** | Blackholes matching packets | Drop unwanted traffic between environments |
| **Internet** | Routes traffic directly to Azure internet edge | Bypass firewall for whitelisted SaaS traffic |

### 4. Service Endpoints vs. Private Endpoints (Private Link)

| Dimension | Service Endpoints | Private Endpoints (Azure Private Link) |
| :--- | :--- | :--- |
| **IP Addressing** | PaaS resource retains its **public IP**; traffic routed internally | PaaS resource receives a **private RFC 1918 IP** from your local subnet |
| **Network Reachability** | Accessible only from the configured VNet/subnet | Accessible across peered VNets, VPN, and ExpressRoute |
| **Data Exfiltration** | Broad access to the service (e.g., all Azure Storage accounts) | **Zero exfiltration**: Restricted strictly to the specific single resource instance |
| **Production Recommendation** | Legacy architectures; low complexity | **Modern Enterprise Standard**: Completely disables PaaS public endpoints |

---

## Production `az` CLI Commands

### 1. Provisioning a Custom VNet and Subnets

```bash
# 1. Create Virtual Network
az network vnet create \
  --resource-group prod-net-rg \
  --name prod-vnet-eastus \
  --address-prefixes 10.10.0.0/16 \
  --location eastus

# 2. Create Application Subnet
az network vnet subnet create \
  --resource-group prod-net-rg \
  --vnet-name prod-vnet-eastus \
  --name snet-workloads \
  --address-prefixes 10.10.1.0/24 \
  --private-endpoint-network-policies Enabled

# 3. Create Private Endpoints Subnet
az network vnet subnet create \
  --resource-group prod-net-rg \
  --vnet-name prod-vnet-eastus \
  --name snet-private-endpoints \
  --address-prefixes 10.10.2.0/24
```

### 2. Creating an Azure NAT Gateway for Outbound Egress

```bash
# 1. Create a Public IP for the NAT Gateway
az network public-ip create \
  --resource-group prod-net-rg \
  --name pip-natgw-eastus \
  --sku Standard \
  --zone 1 2 3

# 2. Create the NAT Gateway resource
az network nat gateway create \
  --resource-group prod-net-rg \
  --name natgw-eastus \
  --public-ip-addresses pip-natgw-eastus \
  --idle-timeout-in-minutes 10

# 3. Associate NAT Gateway with application subnet
az network vnet subnet update \
  --resource-group prod-net-rg \
  --vnet-name prod-vnet-eastus \
  --name snet-workloads \
  --nat-gateway natgw-eastus
```

### 3. Deploying a Route Table with Forced Tunneling (UDR)

```bash
# 1. Create Route Table
az network route-table create \
  --resource-group prod-net-rg \
  --name rt-spoke-to-firewall \
  --location eastus

# 2. Add Default Route forcing all 0.0.0.0/0 traffic to Hub Azure Firewall IP
az network route-table route create \
  --resource-group prod-net-rg \
  --route-table-name rt-spoke-to-firewall \
  --name default-egress-to-fw \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address 10.0.1.4

# 3. Attach Route Table to workload subnet
az network vnet subnet update \
  --resource-group prod-net-rg \
  --vnet-name prod-vnet-eastus \
  --name snet-workloads \
  --route-table rt-spoke-to-firewall
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Virtual Networks per subscription** | 1,000 per region | Can be increased via support ticket |
| **Subnets per Virtual Network** | 3,000 subnets | Ample capacity for micro-segmentation |
| **VNet Peerings per VNet** | 500 peerings | Use Virtual WAN or Hub-and-Spoke to scale beyond |
| **Routes per Route Table** | 400 user-defined routes | Aggregate CIDRs to avoid route exhaustion |
| **NAT Gateway assigned IPs** | Up to 16 public IPs | Delivers over 1,000,000 concurrent SNAT ports |

---

## References

* **Homepage:** https://azure.microsoft.com/en-us/products/virtual-network
* **VNet Documentation:** https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview
* **VNet Peering Overview:** https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview
* **Azure Private Link:** https://learn.microsoft.com/en-us/azure/private-link/private-link-overview
* **Pricing:** https://azure.microsoft.com/en-us/pricing/details/virtual-network/

---

## Pricing Examples

### Scenario 1: Enterprise Hub-and-Spoke VNet Peering
* Hub VNet in East US peered to 10 Spoke VNets within the same region.
* Monthly inter-VNet data transfer across peering: 20 TB ingress + 20 TB egress.
* Intra-region peering rate: $0.01 / GB in both directions ($0.02 / GB total).
* Data transfer cost: 20,480 GB × $0.02 = **$409.60 / month**.
* Virtual Network and Subnets: **$0.00** (Free).

### Scenario 2: Azure NAT Gateway for Outbound Internet Egress
* 1 NAT Gateway deployed to handle outbound egress for 5 subnets in East US.
* Hourly rate: ~$0.045 / hour × 730 hours = ~$32.85.
* Data processed: 10 TB / month at $0.045 / GB = $450.00.
* Public IP address: Standard static IP = $3.65 / month.
* **Total Monthly NAT Cost:** ~$32.85 + $450.00 + $3.65 = **~$486.50 / month**.

---

## Nuggets & Gotchas

1. **The 5-IP Subnet Carveout Breaks `/29` Subnets:** Because Azure reserves the first 4 and last 1 IP address in every subnet, creating a tiny `/29` subnet (8 theoretical IPs) leaves you with **only 3 usable IP addresses**. If you attempt to deploy a 2-node cluster or an Azure PaaS service that requires 4 IPs, deployment will fail instantly. Never create subnets smaller than `/28` in Azure.
2. **Default Outbound Access Retirement:** Historically, any VM in Azure without a public IP or NAT gateway was granted an ephemeral default outbound IP to reach the internet. Azure has officially **deprecated Default Outbound Access**. All new VMs requiring outbound internet access must have an explicit NAT Gateway, Azure Firewall, or User Defined Route.
3. **Private Endpoint DNS Resolution Pitfalls:** When deploying a Private Endpoint for an Azure Storage Account (`privatelink.blob.core.windows.net`), your VNet must be linked to the Azure Private DNS Zone. If the VNet link is missing, applications will resolve the storage account to its public IP address instead of its private endpoint, failing with a firewall or network timeout error.
4. **VNet Peering Overlapping CIDRs Cannot Be Fixed Online:** If VNet A (`10.0.0.0/16`) and VNet B have even a single overlapping IP range, Azure will refuse to establish VNet Peering with an `AddressSpaceOverlaps` error. You cannot shrink or alter an existing VNet address space while subnets are active; fixing this requires tearing down resources and recreating subnets.
5. **GatewaySubnet Must Be Named Exactly `GatewaySubnet`:** To deploy a Virtual Network Gateway (VPN or ExpressRoute), Azure strictly mandates that the hosting subnet be named `GatewaySubnet` (case-sensitive). Furthermore, never associate an NSG or Route Table with `GatewaySubnet`, as this disrupts gateway control plane communication with Microsoft controllers.

---
title: Azure Virtual WAN (vWAN) Architecture & Global Transit Routing
description: Exhaustive engineering guide to Azure Virtual WAN — Hub-and-Spoke vs vWAN transit architecture, Virtual Hub routing tables, Secured Virtual Hubs, ExpressRoute, Site-to-Site VPN, and global any-to-any networking.
tags:
  - azure
  - networking
  - virtual-wan
  - vwan
  - hybrid-cloud
---

# Azure Virtual WAN (vWAN) Architecture & Global Transit Routing 🌐🛤️

**Azure Virtual WAN (vWAN)** is a Microsoft-managed global transit networking service that brings together networking, security, and routing functionalities into a single unified operational interface. Unlike traditional customer-managed Hub-and-Spoke architectures that require complex User Defined Route (UDR) management, NVA clusters, and manual VNet peering meshes, Azure Virtual WAN provides **automated any-to-any branch connectivity**, **transitive routing between VNets**, and **Secured Virtual Hubs** integrated with Azure Firewall across Microsoft's global fiber backbone.

---

## 1. Architecture: Traditional Hub-and-Spoke vs Virtual WAN

In traditional Azure networking, VNet peering is **non-transitive**: Spoke A cannot talk to Spoke B through Hub VNet unless you configure an NVA/Firewall and manage complex UDR route tables on every spoke subnet.

```
                    TRADITIONAL HUB-AND-SPOKE (Manual & Non-Transitive)
            ┌──────────────┐                       ┌──────────────┐
            │ Spoke VNet A │◄───[Peering 1]───────►│ Hub VNet NVA │
            └──────────────┘                       └──────┬───────┘
                                                          │ [Peering 2]
            ┌──────────────┐                              │
            │ Spoke VNet B │◄─────────────────────────────┘
            └──────────────┘
            * Requires manual UDRs on all subnets for Spoke-to-Spoke transit.
            * Scaling NVA capacity requires third-party load balancer tuning.

═════════════════════════════════════════════════════════════════════════════════

                    AZURE VIRTUAL WAN (Managed Global Any-to-Any Mesh)
       ┌──────────────────────┐                         ┌──────────────────────┐
       │     SPOKE VNET A     │                         │     SPOKE VNET B     │
       │  (VNet Connection)   │                         │  (VNet Connection)   │
       └──────────┬───────────┘                         └──────────┬───────────┘
                  │                                                │
                  ▼                                                ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                  AZURE SECURED VIRTUAL HUB (us-east)                   │
       │                                                                        │
       │  ┌──────────────────────────────────────────────────────────────────┐  │
       │  │               VIRTUAL HUB ROUTER & ROUTE TABLES                  │  │
       │  │  - Dynamic BGP route propagation across all spokes & branches    │  │
       │  │  - Default Route Table & Custom Isolated Route Tables            │  │
       │  └──────────────────────────────────┬───────────────────────────────┘  │
       │                                     │                                  │
       │  ┌──────────────────────────────────┼───────────────────────────────┐  │
       │  │      SECURED VIRTUAL HUB         │   GATEWAYS (Scale Units)      │  │
       │  │  ┌────────────────────────────┐  │  ┌─────────────────────────┐  │  │
       │  │  │   Azure Firewall Policy    │  │  │ ExpressRoute Gateway    │  │  │
       │  │  │ (L3-L7 Inspection / IDPS)  │  │  │ (Up to 20 Gbps)         │  │  │
       │  │  └────────────────────────────┘  │  ├─────────────────────────┤  │  │
       │  │                                  │  │ Site-to-Site VPN (20G)  │  │  │
       │  │                                  │  ├─────────────────────────┤  │  │
       │  │                                  │  │ Point-to-Site User VPN  │  │  │
       │  └──────────────────────────────────┘  └─────────────────────────┘  │  │
       └───────────────────────────────────┬────────────────────────────────────┘
                                           │ Global High-Speed Microsoft Fiber
                                           ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                 AZURE VIRTUAL HUB (europe-west)                        │
       │      (Cross-Region Inter-Hub Transit with Sub-Millisecond Jitter)      │
       └────────────────────────────────────────────────────────────────────────┘
```

### Core Architectural Constructs

1. **Virtual WAN Resource:** The top-level global orchestrator representing the entire global corporate network overlay across all Azure regions.
2. **Virtual Hub:** A Microsoft-managed resource deployed into a specific region containing the core routing engine. The hub internally manages dynamic BGP peering, routing tables, and gateways.
3. **Hub Gateways (Scale Units):** Gateways inside the hub (VPN, ExpressRoute, Point-to-Site) are provisioned via **Scale Units** (e.g., 1 Scale Unit = 500 Mbps; 20 Scale Units = 10 Gbps) without deploying or managing individual VM instances.
4. **Secured Virtual Hub:** A Virtual Hub that includes an integrated, zero-touch **Azure Firewall**. When configured as a Secured Hub, routing intent policies automatically steer all Internet-bound and private branch-to-spoke traffic through the firewall without requiring manual UDRs.
5. **Virtual Hub Route Tables:** Support advanced routing scenarios:
   - **Associations:** Defines which route table a VNet connection listens to for next-hop routing.
   - **Propagations:** Defines which route tables learn the VNet's address space. Enables isolation (e.g., Prod VNets cannot route to Dev VNets).

---

## 2. Deep Core Routing Mechanics

### Route Table Associations & Propagations Matrix

To create network micro-segmentation without deploying firewalls between every spoke, Virtual WAN uses Route Tables:

| Spoke Type | Associated Route Table | Propagates To | Routing Behavior |
| :--- | :--- | :--- | :--- |
| **Production Spoke** | `RT_Production` | `RT_Production`, `Default` | Can reach all Prod spokes and Hub Gateways; cannot reach Dev |
| **Development Spoke** | `RT_Development` | `RT_Development`, `Default` | Can reach Dev spokes; isolated from Prod spokes |
| **Shared Services Spoke** | `Default` | `Default`, `RT_Production`, `RT_Dev` | Reachable by both Production and Development spokes |
| **Hybrid On-Premises** | `Default` | `Default`, `RT_Production` | Routes to corporate datacenter via ExpressRoute |

### Routing Intent & Routing Policies

Historically, forcing all traffic through a firewall required writing explicit `0.0.0.0/0` and private CIDR UDRs. Virtual WAN introduced **Routing Intent**:
- **Internet Traffic Policy:** Configures the Virtual Hub to automatically inject a `0.0.0.0/0` default route pointing to Azure Firewall across all connected Spoke VNets and Branches.
- **Private Traffic Policy:** Automatically steers all RFC 1918 private inter-spoke and branch-to-spoke traffic through Azure Firewall.

---

## 3. Production Deployment & Management CLI (`az`)

### 1. Create a Standard Virtual WAN Resource

```bash
az group create --name rg-vwan-global-prod --location eastus

# Deploy Standard Virtual WAN (Standard tier enables any-to-any and hub-to-hub transit)
az network vwan create \
    --resource-group rg-vwan-global-prod \
    --name vwan-enterprise-core \
    --location eastus \
    --type Standard
```

### 2. Deploy Regional Virtual Hub with Address Prefix

The Virtual Hub requires its own dedicated `/24` or `/23` address block (used for internal gateways, routing engines, and firewalls).

```bash
az network vhub create \
    --resource-group rg-vwan-global-prod \
    --name vhub-eastus-01 \
    --vwan vwan-enterprise-core \
    --location eastus \
    --address-prefix 10.10.0.0/23 \
    --sku Standard
```

### 3. Provision High-Capacity Site-to-Site VPN Gateway

```bash
# Provision VPN Gateway with 2 Scale Units (1 Gbps redundant throughput)
az network vpn-gateway create \
    --resource-group rg-vwan-global-prod \
    --name vpngw-hub-eastus \
    --vhub vhub-eastus-01 \
    --location eastus \
    --scale-unit 2
```

### 4. Connect Spoke VNets to the Virtual Hub

```bash
# Connect Production Spoke VNet to the Virtual Hub
az network vhub connection create \
    --resource-group rg-vwan-global-prod \
    --name conn-to-spoke-prod \
    --vhub-name vhub-eastus-01 \
    --remote-vnet "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod-eastus" \
    --associated-route-table "defaultRouteTable" \
    --propagated-route-tables "defaultRouteTable"
```

### 5. Convert to Secured Virtual Hub with Azure Firewall

```bash
# Deploy Azure Firewall directly inside the Virtual Hub
az network firewall create \
    --resource-group rg-vwan-global-prod \
    --name afw-vhub-eastus \
    --vhub-name vhub-eastus-01 \
    --sku AZFW_Hub \
    --tier Standard \
    --firewall-policy fwp-enterprise-prod

# Apply Routing Intent to steer all traffic through the Firewall automatically
az network vhub routing-intent create \
    --resource-group rg-vwan-global-prod \
    --vhub-name vhub-eastus-01 \
    --name HubRoutingIntent \
    --routing-policies \
        name=InternetTraffic dests=Internet next-hop="/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-vwan-global-prod/providers/Microsoft.Network/azureFirewalls/afw-vhub-eastus" \
        name=PrivateTraffic dests=PrivateTraffic next-hop="/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-vwan-global-prod/providers/Microsoft.Network/azureFirewalls/afw-vhub-eastus"
```

---

## 4. Quotas, Performance, and Configuration Limits

| Dimension / Resource | Default Limit | Maximum / High-Scale Consideration |
| :--- | :--- | :--- |
| **Virtual Hubs per vWAN** | 60 Hubs | Multi-hub mesh across global regions |
| **Spoke VNets per Hub** | 500 VNet connections | Connects hundreds of enterprise spoke VNets |
| **Hub-to-Hub Transit** | Automatic full-mesh | Microsoft global fiber backbone routing |
| **VPN Gateway Scale Units** | 1 to 40 Scale Units | 500 Mbps to 20 Gbps active-active throughput |
| **ExpressRoute Scale Units**| 1 to 20 Scale Units | 1 Gbps to 20 Gbps active-active throughput |
| **Hub Address Prefix** | `/24` minimum | Recommend `/23` to support Azure Firewall + Gateways |
| **BGP Dynamic Routes** | Up to 10,000 routes | Learned from ExpressRoute & SD-WAN partners |

---

## 5. Official References & Documentation

- [Azure Virtual WAN Overview & Architecture](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about)
- [How to Configure Virtual Hub Routing](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-virtual-hub-routing)
- [Virtual WAN Routing Intent & Policies](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-routing-policies)
- [Secured Virtual Hub with Azure Firewall](https://learn.microsoft.com/en-us/azure/firewall-manager/secure-cloud-network)
- [Azure Virtual WAN Pricing Details](https://azure.microsoft.com/en-us/pricing/details/virtual-wan/)

---

## 6. Realistic Pricing Scenarios

Azure Virtual WAN pricing includes:
1. **Virtual Hub Base Fee:** $0.25 per Virtual Hub per hour (~$182.50/month).
2. **VNet Connection Fee:** $0.05 per connection per hour (~$36.50/month per connected VNet).
3. **Gateway Scale Units:** E.g., VPN Gateway at $0.361 per Scale Unit per hour (~$263.53/month per unit).
4. **Data Processing:**
   - Hub-to-Hub inter-region peering: standard inter-region data transfer ($0.02 - $0.05/GB).
   - VNet-to-Hub routing: $0.02 per GB processed.

### Scenario A: Multi-Region Global Enterprise Transit (2 Hubs, 20 Spokes)

- **Topology:**
  - 2 Virtual Hubs (`East US` and `West Europe`).
  - 10 Spoke VNets connected per hub (20 VNet connections total).
  - 1 S2S VPN Gateway (2 Scale Units) in each hub for branch offices.
  - Data Processing: 10,000 GB (10 TB) routed through the hubs.
- **Monthly Cost Calculation:**
  - Hub Deployment: 2 hubs × $0.25/hr × 730 hrs = **$365.00**
  - VNet Connections: 20 connections × $0.05/hr × 730 hrs = **$730.00**
  - VPN Gateways: 4 Scale Units total × $0.361/hr × 730 hrs = **$1,054.12**
  - Data Processing: 10,000 GB × $0.02/GB = **$200.00**
- **Total Monthly Cost:** **$2,349.12 / month**

### Scenario B: Single Regional Secured Hub (1 Hub, 15 Spokes + Azure Firewall)

- **Topology:**
  - 1 Secured Virtual Hub (`East US`).
  - 15 Spoke VNet connections.
  - 1 ExpressRoute Gateway (1 Scale Unit = 1 Gbps = $0.42/hr).
  - 1 Azure Firewall Standard in Hub ($1.25/hr + $0.016/GB).
  - Data Processed: 5,000 GB.
- **Monthly Cost Calculation:**
  - Virtual Hub: $0.25 × 730 = **$182.50**
  - VNet Connections: 15 × $0.05 × 730 = **$547.50**
  - ExpressRoute Gateway: $0.42 × 730 = **$306.60**
  - Azure Firewall Base: $1.25 × 730 = **$912.50**
  - Firewall Data Fee: 5,000 GB × $0.016 = **$80.00**
  - Hub Routing Data Fee: 5,000 GB × $0.02 = **$100.00**
- **Total Monthly Cost:** **$2,129.10 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **VNet Connection Hourly Charges Add Up Quickly:** In traditional Hub-and-Spoke networks, VNet Peering has no hourly connection fee (only $0.01/GB data transfer). In Virtual WAN, **every single VNet connected to a hub incurs a flat fee of $0.05 per hour ($36.50/month)**. If you have 100 small micro-service or developer VNets connected to a hub, you will pay $3,650/month just in connection idle fees before transferring a single byte. Consolidate subnets into fewer, well-architected spoke VNets.
2. **Virtual Hub Address Prefix Overlap is Fatal:** When creating a Virtual Hub, you must assign it an address prefix (e.g., `10.10.0.0/23`). This prefix is used internally by Azure for the router instances and gateways. If this CIDR overlaps with *any* existing on-premises network, SD-WAN branch, or spoke VNet, Virtual WAN routing breaks catastrophically. The hub prefix **cannot be edited or modified after creation**; you must delete and recreate the entire hub and all gateways to fix an IP conflict.
3. **Routing Intent Replaces All Spoke UDRs Automatically:** Before Virtual WAN Routing Intent existed, engineers had to write and maintain dozens of UDRs on spoke subnets to steer traffic through the firewall. When you enable Routing Intent on a Secured Hub, Azure **programmatically overrides and injects default routes into the effective routing tables of all attached VNets**. If you had custom UDRs sending specific traffic directly to another NVA, Routing Intent will take precedence, which can unintentionally black-hole legacy appliance traffic.
4. **Hub-to-Hub Transit Requires "Standard" SKU:** Azure offers a "Basic" Virtual WAN SKU and a "Standard" SKU. Basic only supports Site-to-Site VPN and does not support VNet-to-VNet transit, ExpressRoute, or Hub-to-Hub inter-region transit. If you create a Basic vWAN, you cannot convert it in-place to Standard without deleting and rebuilding your hub topology. Always create **Standard Virtual WAN** from day one.
5. **ExpressRoute Gateway Scale Units Cannot Be Set to Zero:** Once you deploy an ExpressRoute or VPN Gateway inside a Virtual Hub, you cannot scale it down to 0 units to pause billing during a testing hiatus. The gateway will bill for at least 1 Scale Unit ($263 - $306/month) 24/7. To stop charges in development environments, you must delete the gateway resource completely.
6. **BGP AS Number Collisions with On-Premises:** Azure Virtual Hub uses Autonomous System Number (ASN) `65515` by default. If your corporate on-premises datacenter router or an existing ExpressRoute circuit is already configured with ASN `65515`, BGP route peering will fail immediately due to AS-Path loop prevention rules. Verify and customize your BGP ASN settings before establishing hybrid connections.

---
title: Azure Virtual Network (VNet) & Hybrid Routing
description: Comprehensive engineering guide to Azure Virtual Networks (VNets) — single-VNet fundamentals, multi-zone subnets, 5 reserved IPs, default routing, NICs, delegated subnets, VNet Peering, Gateway Transit, UDRs, and NAT Gateway.
tags:
  - azure
  - networking
  - vnet
  - hybrid
  - routing
  - security
date: 2026-10-16
---

# Azure Virtual Network (VNet) & Hybrid Routing 🌐

An **Azure Virtual Network (VNet)** is the foundational private network boundary in Microsoft Azure. Built on Microsoft's **Andromeda** software-defined networking (SDN) substrate, a VNet provides isolated compute environments, internal IP routing, private connectivity to Azure PaaS services, and hybrid integration with on-premises datacenters over ExpressRoute or VPN tunnels.

Understanding Azure networking requires starting with the **anatomy and behavior of a single VNet** before progressing to multi-VNet peering and enterprise hub-and-spoke transit topologies.

---

## 1. Single-VNet Fundamentals & Mental Models

### VNet Scope & Multi-Zone Subnet Anatomy

A VNet is strictly **regionally scoped** (bound to a single Azure region such as `eastus` or `westeurope`). However, unlike AWS (where each subnet is bound to a single Availability Zone), **Azure subnets naturally span all Availability Zones within the region**.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        Azure Virtual Network (VNet: 10.10.0.0/16)                      │
│                                Region: East US                                         │
│                                                                                        │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ Subnet: snet-workloads (10.10.1.0/24) — Spans All Availability Zones           │   │
│   │                                                                                │   │
│   │   ┌──────────────────────┐  ┌──────────────────────┐  ┌─────────────────────┐  │   │
│   │   │ Availability Zone 1  │  │ Availability Zone 2  │  │ Availability Zone 3 │  │   │
│   │   │ VM-App-01            │  │ VM-App-02            │  │ VM-App-03           │  │   │
│   │   │ IP: 10.10.1.10       │  │ IP: 10.10.1.11       │  │ IP: 10.10.1.12      │  │   │
│   │   │ vNIC (SR-IOV Accel)  │  │ vNIC (SR-IOV Accel)  │  │ vNIC (SR-IOV Accel) │  │   │
│   │   └──────────────────────┘  └──────────────────────┘  └─────────────────────┘  │   │
│   └───────────────────────────────────────▲────────────────────────────────────────┘   │
│                                           │                                            │
│                      Default Intra-VNet System Route: "VirtualNetwork"                 │
│                 (Subnets communicate directly with zero routers or gateways)           │
│                                           │                                            │
│   ┌───────────────────────────────────────▼────────────────────────────────────────┐   │
│   │ Subnet: snet-data (10.10.2.0/24) — Spans All Availability Zones                │   │
│   │                                                                                │   │
│   │   ┌─────────────────────────────────────┐  ┌────────────────────────────────┐  │   │
│   │   │ VM-DB-Primary (Zone 1)              │  │ Private Endpoint (Zone 2)      │  │   │
│   │   │ IP: 10.10.2.15                      │  │ Azure SQL / Cosmos DB          │  │   │
│   │   │                                     │  │ IP: 10.10.2.50                 │  │   │
│   │   └─────────────────────────────────────┘  └────────────────────────────────┘  │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────┬────────────────────────────────────────────┘
                                            │ Outbound Egress via Attached NAT Gateway
                                            ▼
                               [ Azure NAT Gateway (Static PIP) ] ──► Internet
```

### Architectural Comparison: Azure VNet vs. AWS VPC vs. GCP VPC

| Networking Attribute        | Azure VNet                                                 | AWS VPC                                                 | GCP VPC                                                            |
| :-------------------------- | :--------------------------------------------------------- | :------------------------------------------------------ | :----------------------------------------------------------------- |
| **Network Scope**           | **Regional** (bound to 1 region)                           | **Regional** (bound to 1 region)                        | **Global** (spans all regions worldwide)                           |
| **Subnet Scope**            | **Regional / Multi-Zone** (spans all AZs)                  | **Zonal** (strictly locked to 1 AZ)                     | **Regional** (spans all zones in region)                           |
| **Intra-Network Routing**   | **Automatic Mesh**: All subnets communicate out-of-the-box | **Local Route**: All subnets communicate via VPC router | **Default Routes**: All subnets communicate globally via Andromeda |
| **Reserved IPs per Subnet** | **5 IPs** (.0, .1, .2, .3, .255)                           | **5 IPs** (.0, .1, .2, .3, .255)                        | **4 IPs** (.0, .1, .2, .255)                                       |
| **Cross-Zone Subnet VMs**   | Supported natively in same CIDR                            | Requires separate subnets per AZ                        | Supported natively in same CIDR                                    |
| **Internet Ingress**        | Public IP directly on vNIC or Load Balancer                | Public IP on ENI + Internet Gateway route               | External IP on instance + Default Internet Route                   |

---

## 2. Core Building Blocks of a Single VNet

### 1. Address Spaces & CIDR Allocation

A VNet requires at least one IPv4 address block defined using Classless Inter-Domain Routing (CIDR) notation.

- **Supported Address Ranges:** Standard private RFC 1918 ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) or any publicly routable IP prefix used privately.
- **Multiple Address Spaces:** A single VNet can have multiple non-contiguous address spaces added or expanded dynamically without downtime, provided the new ranges do not overlap with peered VNets or on-premises networks.
- **Prefix Size Range:** Minimum subnet size is `/29` (8 addresses), maximum is `/8` (16,777,216 addresses).

### 2. The 5 Reserved IP Addresses per Subnet

In every Azure subnet, Microsoft permanently reserves **5 IP addresses**. Therefore, a `/24` subnet (256 theoretical addresses) provides exactly **251 usable IP addresses**:

| Reserved IP Address | Designated Role & Behavioral Function                                                                               |
| :------------------ | :------------------------------------------------------------------------------------------------------------------ |
| `x.x.x.0`           | **Network Address:** RFC boundary identifier for the subnet prefix.                                                 |
| `x.x.x.1`           | **Default Gateway:** Assigned to the Azure virtual router for the subnet. All outbound packets target this gateway. |
| `x.x.x.2`           | **Azure DNS Mapping 1:** Reserved by Azure to route queries to the Azure wire server DNS (`168.63.129.16`).         |
| `x.x.x.3`           | **Azure DNS Mapping 2:** Secondary Azure DNS mapping address for high-availability DNS relay.                       |
| `x.x.x.255`         | **Network Broadcast Address:** Reserved for protocol compliance (Azure VNets do not support Layer 2 broadcasts).    |

> [!WARNING]
> Because 5 IPs are consumed unconditionally, creating a `/29` subnet leaves **only 3 usable IP addresses**. Deploying high-availability infrastructure or PaaS services requiring minimum IP allocations will fail. **Adopt `/27` or `/28` as the standard minimum for production subnets.**

### 3. Virtual Network Interfaces (vNICs) & IP Configurations

Virtual machines connect to a VNet subnet through virtual Network Interface Cards (**vNICs**):

- **Private IP Allocation:**
  - **Dynamic (Default):** Assigned by Azure DHCP at VM startup. Remains consistent through VM reboots, but may change if the VM is stopped/deallocated unless made static.
  - **Static:** Permanently reserved from the subnet CIDR. The IP remains bound to the vNIC even across deallocations.
- **Accelerated Networking (SR-IOV):**
  - Uses Single Root I/O Virtualization (SR-IOV) to bypass the host hypervisor CPU virtual switch, offloading packet processing directly to the physical FPGA SmartNIC.
  - Reduces latency from ~100µs to **<15µs** and eliminates host CPU jitter. Mandatory for production workloads, database nodes, and AKS user pools.
- **Secondary IP Configurations:** A single vNIC can hold multiple private and public IP addresses (common for multi-SSL web servers or container runtimes).

### 4. Special Dedicated & Delegated Subnets

Azure requires specific, reserved subnet names and dedicated delegations for managed infrastructure and PaaS integration:

| Special Subnet Name / Delegation    | Minimum Sizing            | Mandatory Rules & Restrictions                                                                                                                                                                                                      |
| :---------------------------------- | :------------------------ | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`GatewaySubnet`**                 | `/27` (`/26` recommended) | Exact case-sensitive name. Hosts Virtual Network Gateways (VPN & ExpressRoute). **Never attach NSGs or Route Tables (UDRs) directly to this subnet.**                                                                               |
| **`AzureFirewallSubnet`**           | `/26`                     | Dedicated to Azure Firewall data planes. Must not host any workloads, VMs, or other endpoints.                                                                                                                                      |
| **`AzureFirewallManagementSubnet`** | `/26`                     | Required for Azure Firewall forced-tunneling scenarios to separate management plane traffic from inspected customer traffic.                                                                                                        |
| **`AzureBastionSubnet`**            | `/26`                     | Dedicated to Azure Bastion host instances. Requires standard ports open to `GatewayManager` service tag.                                                                                                                            |
| **`RouteServerSubnet`**             | `/27`                     | Hosts Azure Route Server instances for dynamic BGP peering with SD-WAN NVAs.                                                                                                                                                        |
| **Delegated Subnets**               | Sized per service         | Subnets delegated to specific resource providers (e.g., `Microsoft.Web/serverFarms` for App Service, `Microsoft.App/environments` for ACA, `Microsoft.Sql/managedInstances`). Only the delegated service can provision NICs inside. |

---

## 3. Traffic Routing: System Routes vs. User Defined Routes (UDRs)

### System Routes (Azure Default Routing Table)

Every subnet automatically receives default system routes managed by Azure. You cannot delete system routes, but you can override them using **User Defined Routes (UDRs)**:

| System Destination Prefix                     | Default Next Hop | Description                                                                                                                                 |
| :-------------------------------------------- | :--------------- | :------------------------------------------------------------------------------------------------------------------------------------------ |
| **VNet Address Prefix** (e.g. `10.10.0.0/16`) | `VirtualNetwork` | Direct, wire-speed routing between all subnets in the VNet and across established VNet peerings.                                            |
| **`0.0.0.0/0`**                               | `Internet`       | Direct egress to the public internet edge. _(Note: Default outbound access is deprecated; modern VMs require NAT Gateway or explicit PIP)._ |
| **RFC 1918 / 6598 Prefixes**                  | `None`           | Traffic to unallocated private CIDRs (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `100.64.0.0/10`) is blackholed by default.           |

### User Defined Routes (UDRs) & Route Selection Order

A **Route Table** containing custom UDRs can be associated with one or more subnets to override system routes (e.g., forcing all outbound traffic through an NVA or firewall):

```
                   Azure Routing Evaluation Precedence
                                    │
           ┌────────────────────────▼────────────────────────┐
           │ 1. Longest Prefix Match (LPM) Rule               │
           │    Most specific CIDR mask wins (e.g. /24 > /16)│
           └────────────────────────┬────────────────────────┘
                                    │ If prefix lengths match
           ┌────────────────────────▼────────────────────────┐
           │ 2. Route Origin Priority:                       │
           │    User Defined Route (UDR)                     │
           │       ▼                                         │
           │    BGP / ExpressRoute Route (VirtualNetworkGw)   │
           │       ▼                                         │
           │    System Route (Default Azure Routing)         │
           └─────────────────────────────────────────────────┘
```

#### Available Next Hop Types in UDRs

- **`VirtualAppliance`:** Directs traffic to a private IP of a firewall or NVA (e.g., Azure Firewall at `10.0.1.4`).
- **`VirtualNetworkGateway`:** Forwards traffic across an ExpressRoute circuit or S2S VPN tunnel.
- **`Internet`:** Forces traffic out through the Azure internet gateway (useful to bypass an NVA for specific public endpoints).
- **`None`:** Blackholes and silently drops matching packets (useful for isolation between security zones).
- **`VnetLocal`:** Overrides an active cross-subnet or peering route to keep traffic confined within the local VNet.

---

## 4. Multi-VNet & Hybrid Enterprise Topologies

Once single-VNet concepts are mastered, enterprise architectures scale across subscriptions and regions using **VNet Peering** and **Hub-and-Spoke Topologies**.

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

### VNet Peering Rules & Gateway Transit Mechanics

1. **Non-Transitive Peering:** Peering is strictly non-transitive. If Spoke A is peered to Hub, and Spoke B is peered to Hub, **Spoke A cannot communicate directly with Spoke B**. Inter-spoke traffic must be routed through the Hub's Azure Firewall or NVA using a UDR (`0.0.0.0/0` or `10.0.0.0/8` next hop `VirtualAppliance`).
2. **Gateway Transit:** Allows spoke VNets to share a single, high-cost ExpressRoute or VPN Gateway located in the Hub VNet:
   - Hub peering configuration: `--allow-gateway-transit true`
   - Spoke peering configuration: `--use-remote-gateways true`
3. **No Downtime Peering Creation:** VNets can be peered while VMs are actively transmitting traffic without packet loss or interface resets.
4. **Global VNet Peering:** Peers VNets across different physical Azure regions over Microsoft's encrypted dark fiber backbone with wire-speed performance.

### Service Endpoints vs. Private Endpoints (Private Link)

| Architectural Dimension  | Service Endpoints                                                                                | Private Endpoints (Azure Private Link)                                                |
| :----------------------- | :----------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------ |
| **IP Addressing**        | PaaS resource retains its **public IP**; traffic is optimized internally over Microsoft backbone | PaaS resource receives a **private RFC 1918 IP** directly inside your workload subnet |
| **Network Reachability** | Accessible only from the configured local VNet/subnet                                            | Accessible across peered VNets, VPN, and ExpressRoute circuits                        |
| **Data Exfiltration**    | Broad access to the service (e.g., access to all Azure Storage accounts unless filtered)         | **Zero exfiltration**: Restricted strictly to that single resource instance ID        |
| **Enterprise Status**    | Legacy pattern; low complexity                                                                   | **Enterprise Standard**: Allows completely disabling public network access on PaaS    |

---

## 5. Production `az` CLI Workflows

### 1. Provisioning a Production VNet with Multi-Zone Subnets

```bash
# 1. Create Resource Group
az group create --name rg-network-core-prod --location eastus

# 2. Create Virtual Network with primary CIDR block
az network vnet create \
  --resource-group rg-network-core-prod \
  --name vnet-workloads-eastus \
  --address-prefixes 10.20.0.0/16 \
  --location eastus

# 3. Create General Workload Subnet (Multi-Zone)
az network vnet subnet create \
  --resource-group rg-network-core-prod \
  --vnet-name vnet-workloads-eastus \
  --name snet-apps \
  --address-prefixes 10.20.1.0/24 \
  --private-endpoint-network-policies Enabled

# 4. Create Private Link Endpoints Subnet
az network vnet subnet create \
  --resource-group rg-network-core-prod \
  --vnet-name vnet-workloads-eastus \
  --name snet-private-endpoints \
  --address-prefixes 10.20.2.0/24
```

### 2. Deploying Azure NAT Gateway for Deterministic Egress

```bash
# 1. Provision a Standard Zone-Redundant Public IP
az network public-ip create \
  --resource-group rg-network-core-prod \
  --name pip-natgw-eastus \
  --sku Standard \
  --zone 1 2 3

# 2. Create the NAT Gateway resource
az network nat gateway create \
  --resource-group rg-network-core-prod \
  --name natgw-workloads-eastus \
  --location eastus \
  --public-ip-addresses pip-natgw-eastus \
  --idle-timeout-in-minutes 10

# 3. Attach NAT Gateway to the application subnet
az network vnet subnet update \
  --resource-group rg-network-core-prod \
  --vnet-name vnet-workloads-eastus \
  --name snet-apps \
  --nat-gateway natgw-workloads-eastus
```

### 3. Establishing Bidirectional VNet Peering with Gateway Transit

```bash
# 1. Spoke-to-Hub Peering (Requesting to use Hub's Gateway)
az network vnet peering create \
  --name peer-spoke-to-hub \
  --resource-group rg-network-core-prod \
  --vnet-name vnet-workloads-eastus \
  --remote-vnet "/subscriptions/<SUB_ID>/resourceGroups/rg-hub-prod/providers/Microsoft.Network/virtualNetworks/vnet-hub-eastus" \
  --allow-vnet-access \
  --use-remote-gateways

# 2. Hub-to-Spoke Peering (Authorizing Gateway Transit)
az network vnet peering create \
  --name peer-hub-to-spoke \
  --resource-group rg-hub-prod \
  --vnet-name vnet-hub-eastus \
  --remote-vnet "/subscriptions/<SUB_ID>/resourceGroups/rg-network-core-prod/providers/Microsoft.Network/virtualNetworks/vnet-workloads-eastus" \
  --allow-vnet-access \
  --allow-gateway-transit
```

### 4. Deploying a Route Table (UDR) for Forced Egress Inspection

```bash
# 1. Create custom Route Table
az network route-table create \
  --resource-group rg-network-core-prod \
  --name rt-workloads-to-firewall \
  --location eastus \
  --disable-bgp-route-propagation false

# 2. Add Default Route forcing all internet egress (0.0.0.0/0) to Central Firewall NVA
az network route-table route create \
  --resource-group rg-network-core-prod \
  --route-table-name rt-workloads-to-firewall \
  --name udr-default-to-hub-firewall \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address 10.0.1.4

# 3. Associate Route Table with Workload Subnet
az network vnet subnet update \
  --resource-group rg-network-core-prod \
  --vnet-name vnet-workloads-eastus \
  --name snet-apps \
  --route-table rt-workloads-to-firewall
```

---

## 6. Quotas & Limits

| Parameter                             | Limit            | Architectural Guidance                                                                    |
| :------------------------------------ | :--------------- | :---------------------------------------------------------------------------------------- |
| **Virtual Networks per Subscription** | 1,000 per region | Adjustable via support ticket                                                             |
| **Address Spaces per VNet**           | 50 CIDR blocks   | Keep contiguous whenever possible                                                         |
| **Subnets per Virtual Network**       | 3,000 subnets    | Ample capacity for multi-tenant isolation                                                 |
| **VNet Peerings per VNet**            | 500 peerings     | Use [[Azure/networking/virtual-wan/README\|Azure Virtual WAN]] to scale beyond 500 spokes |
| **Routes per Route Table (UDR)**      | 400 routes       | Summarize CIDRs to avoid route exhaustion                                                 |
| **Route Tables per Subscription**     | 2,048            | Shared across multiple subnets                                                            |
| **NAT Gateway Public IPs**            | Up to 16 IPs     | Delivers over 1,000,000 concurrent SNAT connections                                       |
| **Accelerated Networking Bandwidth**  | Up to 100 Gbps   | Dependent on underlying VM instance size (e.g. Edv5, NDv5)                                |

---

## 7. Pricing Examples

### Scenario 1: Regional Hub-and-Spoke VNet Peering

- **Topology:** 1 Central Hub VNet in East US peered to 12 Spoke VNets within the same region.
- **Traffic Volume:** 30 TB ingress + 30 TB egress data transferred across peerings per month.
- **Pricing Rates:** Intra-region VNet peering data transfer is billed at **$0.01 / GB in each direction** ($0.02 / GB total round-trip).
- **Calculation:**
  - 30,720 GB × $0.02 / GB = **$614.40 / month**.
  - Virtual Network, Subnets, and Route Tables: **$0.00** (Free).

### Scenario 2: Azure NAT Gateway for Outbound Internet Egress

- **Topology:** 1 NAT Gateway assigned to 4 subnets in East US with 1 static Standard Public IP.
- **Usage Metrics:** 730 active gateway hours, 15 TB outbound internet egress processed per month.
- **Pricing Rates:**
  - Gateway instance: ~$0.045 / hour × 730 hours = **~$32.85 / month**.
  - Data processing fee: 15,360 GB × $0.045 / GB = **$691.20 / month**.
  - Static Standard Public IP: **$3.65 / month**.
- **Total Cost:** $32.85 + $691.20 + $3.65 = **$727.70 / month**.

---

## 8. Battle-Tested Nuggets & Gotchas

1. **The 5-IP Subnet Carveout Breaks `/29` Subnets:** Because Azure unconditionally reserves the first 4 (`.0`, `.1`, `.2`, `.3`) and the last 1 (`.255`) IP address in every subnet, creating a `/29` subnet (8 total addresses) yields **only 3 usable IP addresses**. Deploying an AKS node pool or an Azure Application Gateway requires a minimum of 8 to 30 usable addresses and will reject a `/29` immediately. Standardize on `/27` or `/28` minimum.
2. **Default Outbound Access Has Been Retired:** In older Azure configurations, VMs created without a public IP or NAT gateway were assigned an ephemeral, hidden outbound SNAT IP by Azure. Azure has deprecated Default Outbound Access across all new subscriptions. All workloads requiring outbound egress must be explicitly provisioned with a NAT Gateway, Azure Firewall, or User Defined Route.
3. **Subnets Span Zones, But Storage/Disks Do Not:** An Azure subnet spans all three availability zones seamlessly. However, virtual machines, local OS disks, and zonal public IPs are **strictly zonal**. When architecting high-availability across Zone 1 and Zone 2 within the same subnet, ensure your Load Balancers use Zone-Redundant Standard SKUs to bridge traffic across zones.
4. **VNet Peering Overlapping CIDRs Cannot Be Resolved Online:** If VNet A (`10.10.0.0/16`) and VNet B have even a single overlapping IP range (e.g., `10.10.5.0/24`), Azure will reject VNet Peering with an `AddressSpaceOverlaps` error. You cannot shrink or alter an address space while subnets are active; resolving an overlap requires tearing down active resources.
5. **GatewaySubnet & AzureFirewallSubnet Strict Naming:** Azure strictly enforces reserved names: `GatewaySubnet`, `AzureFirewallSubnet`, and `AzureBastionSubnet` are **case-sensitive**. Never associate an NSG or custom Route Table directly to `GatewaySubnet`, as this disrupts the gateway's internal control plane communication with Microsoft controllers.
6. **Accelerated Networking Requires VM Deallocation to Toggle:** Accelerated Networking (SR-IOV) cannot be enabled or disabled while a VM is running. The VM must be put into the `Stopped (deallocated)` state via `az vm deallocate` before modifying the NIC setting.
7. **Private Endpoint DNS Split-Brain Resolution:** Deploying a Private Endpoint (`privatelink.blob.core.windows.net`) assigns an internal RFC 1918 IP, but clients will continue connecting to the public IP unless the VNet is explicitly linked to the Azure Private DNS Zone. Always link Private DNS Zones to all hub and spoke VNets during provisioning.

---

## Across the Wiki

- [[Azure/networking/README|Azure Networking Hub]] — Master architectural directory for Azure networking
- [[Azure/networking/nsg|Network Security Groups (NSGs) & ASGs]] — Stateful L3/L4 subnet and interface filtering
- [[Azure/networking/load-balancing|Azure Load Balancing, App Gateway & Front Door]] — Layer 4 vs Layer 7 load balancing
- [[Azure/networking/firewall/README|Azure Firewall & IDPS]] — Centralized hub inspection and TLS decryption
- [[Azure/networking/virtual-wan/README|Azure Virtual WAN (vWAN)]] — Microsoft-managed global transit architecture
- [[Azure/networking/private-link/README|Azure Private Link & Private Endpoints]] — Secure private PaaS connectivity
- [[Azure/networking/bastion-nat|Azure Bastion & NAT Gateway]] — Zero-public-IP access and SNAT egress
- [[AWS/networking/vpc/README|Amazon VPC]] — Virtual private clouds in AWS
- [[GCP/networking/vpc|GCP Virtual Private Cloud (VPC)]] — Global VPCs and subnets in GCP
- [[Architecture/solution-architecture-concepts/networking/README|Cloud-Native Networking Guide]] — Multi-cloud networking patterns

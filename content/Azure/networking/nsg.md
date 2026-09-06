---
title: Azure Network Security Groups (NSGs) & ASGs
description: Azure NSG & ASG architecture — rule priority evaluation, default rules, Service Tags, Application Security Groups, and dual-layer subnet vs NIC filtering.
tags:
  - azure
  - networking
  - nsg
  - asg
  - security
  - firewall
---

# Azure Network Security Groups (NSGs) & ASGs 🛡️🧱

Network Security Groups (NSGs) provide stateful Layer 3 and Layer 4 packet filtering for virtual machines, subnets, and container network interfaces in Azure. 

To prevent IP churn from breaking security configurations, Azure provides **Application Security Groups (ASGs)**, allowing administrators to group VMs logically into tiers (e.g., `ASG-Web`, `ASG-DB`) and write firewall policies based on application identity rather than ephemeral IP addresses.

---

## Architecture & Mental Model

### Dual-Layer Evaluation: Subnet NSG vs. NIC NSG

Traffic entering or leaving an Azure VM can pass through two distinct NSG boundaries:

```
                        INCOMING PACKET (INGRESS)
                                   │
                                   ▼
                   ┌──────────────────────────────┐
                   │       Subnet-Level NSG       │
                   │ (Evaluated First for Ingress)│
                   └──────────────┬───────────────┘
                                  │ MATCH: ALLOW
                                  ▼
                   ┌──────────────────────────────┐
                   │         NIC-Level NSG        │
                   │ (Evaluated Second for Ingress│
                   └──────────────┬───────────────┘
                                  │ MATCH: ALLOW
                                  ▼
                         Target Virtual Machine
                                  │
                                  ▼
                        OUTGOING PACKET (EGRESS)
                                  │
                                  ▼
                   ┌──────────────────────────────┐
                   │         NIC-Level NSG        │
                   │  (Evaluated First for Egress)│
                   └──────────────┬───────────────┘
                                  │ MATCH: ALLOW
                                  ▼
                   ┌──────────────────────────────┐
                   │       Subnet-Level NSG       │
                   │ (Evaluated Second for Egress)│
                   └──────────────┬───────────────┘
                                  │ MATCH: ALLOW
                                  ▼
                           Destination Network
```

* **The Double-Allow Requirement:** For an inbound packet to reach a VM, **both** the Subnet NSG and the NIC NSG must permit the traffic. If either NSG denies the packet, it is immediately dropped.

---

## Core Concepts

### 1. Rule Priority & Evaluation Order

* Rules are processed in strict priority order from **100 to 4096** (lowest numeric value evaluated first).
* The **first matching rule** terminates evaluation; subsequent rules are ignored.

### 2. Immutable Default Ingress & Egress Rules

Every NSG contains default system rules with priority >= 65000 that cannot be deleted, only overridden by lower priority custom rules:

#### Default Ingress Rules

| Priority | Name | Source | Destination | Port | Action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **65000** | `AllowVnetInBound` | `VirtualNetwork` | `VirtualNetwork` | Any | **ALLOW** (Permits all intra-VNet and peered VNet traffic) |
| **65001** | `AllowAzureLoadBalancerInBound` | `AzureLoadBalancer` | Any | Any | **ALLOW** (Permits health check probes) |
| **65500** | `DenyAllInBound` | Any | Any | Any | **DENY** (Implicit zero-trust block) |

#### Default Egress Rules

| Priority | Name | Source | Destination | Port | Action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **65000** | `AllowVnetOutBound` | `VirtualNetwork` | `VirtualNetwork` | Any | **ALLOW** |
| **65001** | `AllowInternetOutBound` | Any | `Internet` | Any | **ALLOW** (Permits unrestricted internet outbound by default!) |
| **65500** | `DenyAllOutBound` | Any | Any | Any | **DENY** |

### 3. Application Security Groups (ASGs)

ASGs enable micro-segmentation without managing static IP lists:

```
┌────────────────────────────────────────────────────────┐
│                        Subnet                          │
│                                                        │
│  ┌─────────────────────────┐ ┌──────────────────────┐  │
│  │ VM 1: Web Frontend      │ │ VM 2: Web Frontend   │  │
│  │ (Member of: ASG-Web)    │ │ (Member of: ASG-Web) │  │
│  └────────────┬────────────┘ └──────────┬───────────┘  │
│               │                         │              │
│               └────────────┬────────────┘              │
│                            │ Ingress: Port 5432        │
│                            │ Source: ASG-Web           │
│                            │ Destination: ASG-Database │
│                            ▼                           │
│              ┌───────────────────────────┐             │
│              │ VM 3: PostgreSQL Database │             │
│              │ (Member of: ASG-Database) │             │
│              └───────────────────────────┘             │
└────────────────────────────────────────────────────────┘
```

* When new web VMs are added via auto-scaling, they are simply tagged with `ASG-Web` and automatically inherit the database firewall rules without updating NSG CIDRs!

### 4. Service Tags

Service Tags represent pre-defined IP address groups maintained dynamically by Microsoft:
* `VirtualNetwork`: Includes the local VNet, all peered VNets, and connected on-prem gateways.
* `AzureLoadBalancer`: Azure's infrastructure health probe IP (`168.63.129.16`).
* `Internet`: Any IP address outside the VirtualNetwork range.
* `Storage.EastUS`, `Sql.EastUS`: Azure PaaS service IP ranges within a specific region.

---

## Production `az` CLI Commands

### 1. Creating an NSG with Hardened Micro-segmentation

```bash
# 1. Create the NSG
az network nsg create \
  --resource-group prod-net-rg \
  --name nsg-backend-tier \
  --location eastus

# 2. Create an Application Security Group (ASG)
az network asg create \
  --resource-group prod-net-rg \
  --name asg-api-servers \
  --location eastus

az network asg create \
  --resource-group prod-net-rg \
  --name asg-db-servers \
  --location eastus

# 3. Allow API tier to access DB tier on PostgreSQL port 5432
az network nsg rule create \
  --resource-group prod-net-rg \
  --nsg-name nsg-backend-tier \
  --name allow-api-to-db \
  --priority 200 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-asgs asg-api-servers \
  --destination-asgs asg-db-servers \
  --destination-port-ranges 5432

# 4. Explicitly block all inbound traffic from other subnets (Zero-Trust)
az network nsg rule create \
  --resource-group prod-net-rg \
  --nsg-name nsg-backend-tier \
  --name deny-all-vnet-inbound \
  --priority 4000 \
  --direction Inbound \
  --access Deny \
  --protocol '*' \
  --source-address-prefixes VirtualNetwork \
  --destination-address-prefixes '*' \
  --destination-port-ranges '*'
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **NSGs per subscription** | 5,000 per region | Standard subscription limit |
| **Security rules per NSG** | 1,000 rules | Use ASGs and augmented rules to minimize rule counts |
| **ASGs per subscription** | 3,000 ASGs | Supports large enterprise architectures |
| **ASGs per NIC** | Up to 20 ASGs | Can tag a VM with multiple functional roles |
| **Augmented rule IPs** | Up to 4,000 IP prefixes per rule | Specify comma-separated CIDR blocks in a single rule |

---

## References

* **Homepage:** https://azure.microsoft.com/en-us/products/virtual-network
* **NSG Documentation:** https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview
* **ASG Overview:** https://learn.microsoft.com/en-us/azure/virtual-network/application-security-groups
* **Service Tags Reference:** https://learn.microsoft.com/en-us/azure/virtual-network/service-tags-overview
* **Pricing:** Free (NSGs and ASGs incur zero charges)

---

## Pricing Examples

### Scenario 1: Standard Enterprise Micro-segmentation
* 50 NSGs and 100 ASGs governing 500 VMs across 15 subnets in East US.
* **Monthly NSG & ASG Cost:** **$0.00 / month** (Azure provides stateful NSG and ASG filtering completely free of charge).

### Scenario 2: Security Auditing with NSG Flow Logs & Traffic Analytics
* NSG Flow Logs enabled on all 50 NSGs to capture network telemetry for SIEM ingestion.
* Log storage in Azure Storage Account (100 GB / month): ~$2.00.
* Traffic Analytics log processing (100 GB ingested via Log Analytics @ $2.30/GB): ~$230.00.
* **Total Network Observability Cost:** **~$232.00 / month**.

---

## Nuggets & Gotchas

1. **`AllowVnetInBound` Grants Full Cross-Subnet Access by Default:** The default rule `65000 AllowVnetInBound` permits **any VM in any subnet to connect to any port on any other VM within the VNet and all peered VNets**. Unless you explicitly create an override rule (e.g. priority 4000) denying `VirtualNetwork` traffic, your database tier is fully reachable from your untrusted DMZ subnets!
2. **Blocking `AzureLoadBalancer` Kills Health Probes:** If you create a rule blocking all incoming traffic and inadvertently block source `AzureLoadBalancer` (`168.63.129.16`), health probes from Azure Load Balancer and Application Gateway will fail immediately. The load balancer will mark all backend VMs dead and return 503 errors to users.
3. **ASGs Require All VMs to Be in the Same VNet:** Application Security Groups **cannot span across multiple VNets**. If your web frontend resides in VNet-Spoke-1 and your database resides in VNet-Spoke-2 across VNet peering, you cannot use an ASG as the source or destination across the peering boundary; you must fall back to explicit subnet CIDRs.
4. **Stateful Connection Tracking & Asymmetric Routing Drops:** Azure NSGs are strictly stateful: if inbound traffic is permitted on port 443, the outbound return traffic is automatically allowed regardless of egress rules. However, if traffic enters via a public IP on NIC 1 and the operating system's routing table attempts to send return packets out via an NVA or VPN on NIC 2, Azure drops the connection due to asymmetric routing.
5. **Subnet vs. NIC NSG Administrative Confusion:** Best practice in modern Azure architecture is to **attach NSGs exclusively at the Subnet level** and avoid NIC-level NSGs entirely. Managing rules across both layers leads to severe operational troubleshooting confusion where an allowed rule on the subnet is secretly dropped by an forgotten NIC rule.

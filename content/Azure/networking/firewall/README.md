---
title: Azure Firewall Architecture, TLS Inspection, and IDPS
description: Exhaustive engineering guide to Azure Firewall — Standard vs Premium vs Basic, stateful Layer 3-7 inspection, TLS inspection, signature-based IDPS, FQDN filtering, and Virtual WAN Secured Hub integration.
tags:
  - azure
  - networking
  - firewall
  - security
  - idps
---

# Azure Firewall Architecture, TLS Inspection, and IDPS 🛡️🔥

**Azure Firewall** is a cloud-native, intelligent, stateful network security service providing automated Layer 3 through Layer 7 traffic inspection. Designed with built-in high availability and unrestricted cloud scalability, Azure Firewall eliminates the administrative burden of deploying, clustering, and patching third-party virtual network appliances (NVAs). In its **Premium** tier, it provides deep packet inspection (**TLS Inspection**), signature-based **Intrusion Detection and Prevention Systems (IDPS)**, URL filtering, and web categories to secure enterprise networks against modern cyber threats.

---

## 1. Architecture & Hub-and-Spoke Topology

Azure Firewall deploys inside a dedicated, non-routable subnet named `AzureFirewallSubnet` (minimum `/26` prefix) within a centralized Hub Virtual Network or a Virtual WAN Secured Hub.

```
                   SPOKE VNET 1 (App Tier)         SPOKE VNET 2 (Data Tier)
                   ┌─────────────────────┐         ┌─────────────────────┐
                   │ Subnet 10.1.1.0/24  │         │ Subnet 10.2.1.0/24  │
                   │ UDR: 0.0.0.0/0 ─┐   │         │ UDR: 0.0.0.0/0 ─┐   │
                   └─────────────────┼───┘         └─────────────────┼───┘
                                     │                               │
                                     ▼                               ▼
       ══════════════════════════════╪═══════════════════════════════╪═════════
       HUB VNET (Transit Backbone)   │                               │
                                     ▼                               ▼
       ┌──────────────────────────────────────────────────────────────────────┐
       │                   AZURE FIREWALL SUBNET (10.0.1.0/26)                │
       │                                                                      │
       │  ┌────────────────────────────────────────────────────────────────┐  │
       │  │             AZURE FIREWALL PREMIUM ENGINE                      │  │
       │  │                                                                │  │
       │  │  1. Threat Intelligence Filtering (Malicious IPs/Domains)      │  │
       │  │  2. TLS Inspection Engine (Decryption & Re-encryption)         │  │
       │  │  3. Signature-Based IDPS (67,000+ Exploit Signatures)          │  │
       │  │  4. Layer 7 Application Rules (FQDNs & URL Paths)              │  │
       │  │  5. Layer 4 Network Rules (IP, Port, Protocol)                 │  │
       │  │  6. DNAT Rules (Inbound Port Translation)                      │  │
       │  └────────────────────────────────┬───────────────────────────────┘  │
       └───────────────────────────────────┼──────────────────────────────────┘
                                           │
                    ┌──────────────────────┴──────────────────────┐
                    │                                             │
                    ▼ Clean Egress                                ▼ Clean Hybrid
       ┌────────────────────────┐                   ┌────────────────────────┐
       │     PUBLIC INTERNET    │                   │ ON-PREMISES DATACENTER │
       │  (Via Public IP Pool)  │                   │ (ExpressRoute / S2S)   │
       └────────────────────────┘                   └────────────────────────┘
```

### Core Architecture Constructs

1. **Firewall Policy:** An Azure Resource Manager object that centralizes rule collection groups, threat intelligence modes, TLS inspection certificates, and IDPS settings. Policies can be hierarchical: a parent policy defines corporate-wide mandatory deny rules, while child policies inherit and append project-specific application rules.
2. **Rule Processing Logic:** Incoming packets are processed in strict priority order:
   - **DNAT Rules:** Evaluated first to map incoming public IP/ports to private backend IPs.
   - **Network Rules (L3/L4):** Evaluated second. Matches source IP, destination IP, port, and protocol.
   - **Application Rules (L7):** Evaluated third for HTTP/HTTPS/MSSQL traffic. Performs FQDN, URL path, and HTTP header inspection.
3. **Autoscaling Fleet:** Azure Firewall is not a single VM. It is an elastomeric cluster of Compute nodes behind an Azure Software-Defined Network load balancer that automatically scales out from 2 up to 100 VM instances as throughput and connection counts increase.

---

## 2. SKU Comparison: Basic vs Standard vs Premium

| Feature / Capability | Basic Tier | Standard Tier | Premium Tier |
| :--- | :--- | :--- | :--- |
| **Target Workload** | Small/Medium Business (< 250 Mbps) | Enterprise L3-L7 Spoke Routing | High-Security / Banking / PCI-DSS |
| **Max Throughput** | 250 Mbps | Up to 30 Gbps | Up to 100 Gbps |
| **L3-L7 Filtering** | Yes (FQDNs only) | Yes (FQDNs only) | Yes (FQDNs + Full URLs) |
| **Threat Intelligence** | Alert only | Alert and Deny | Alert and Deny |
| **TLS Inspection** | No | No | **Yes (Outbound & East-West)** |
| **IDPS** | No | No | **Yes (67,000+ signatures)** |
| **Web Categories** | No | Yes (FQDNs) | **Yes (Full URLs)** |
| **Availability SLA** | 99.95% (Single AZ) | 99.99% (Multi-AZ) | 99.99% (Multi-AZ) |

---

## 3. Production Deployment & Management CLI (`az`)

### 1. Create Dedicated Subnet & Public IP Pool

Azure Firewall requires the exact subnet name `AzureFirewallSubnet`.

```bash
az group create --name rg-network-hub-prod --location eastus

# Create Hub VNet
az network vnet create \
    --resource-group rg-network-hub-prod \
    --name vnet-hub-prod \
    --address-prefixes 10.0.0.0/16 \
    --subnet-name AzureFirewallSubnet \
    --subnet-prefixes 10.0.1.0/26

# Allocate 2 static Public IPs for outbound SNAT capacity
az network public-ip create \
    --resource-group rg-network-hub-prod \
    --name pip-fw-prod-01 \
    --sku Standard \
    --allocation-method Static

az network public-ip create \
    --resource-group rg-network-hub-prod \
    --name pip-fw-prod-02 \
    --sku Standard \
    --allocation-method Static
```

### 2. Deploy Azure Firewall Policy with Premium IDPS & Threat Intel

```bash
# Create Firewall Policy
az network firewall policy create \
    --resource-group rg-network-hub-prod \
    --name fwp-enterprise-prod \
    --sku Premium \
    --threat-intel-mode Deny

# Configure IDPS mode to Alert and Deny
az network firewall policy update \
    --resource-group rg-network-hub-prod \
    --name fwp-enterprise-prod \
    --set intrusionDetection.mode="Deny"
```

### 3. Deploy Azure Firewall Premium Instance

```bash
az network firewall create \
    --resource-group rg-network-hub-prod \
    --name afw-core-hub-prod \
    --vnet-name vnet-hub-prod \
    --firewall-policy fwp-enterprise-prod \
    --public-ip-address pip-fw-prod-01 \
    --sku AZFW_VNet \
    --tier Premium \
    --zones 1 2 3

# Add second public IP for SNAT scale
az network firewall ip-config create \
    --firewall-name afw-core-hub-prod \
    --name ip-config-02 \
    --public-ip-address pip-fw-prod-02 \
    --resource-group rg-network-hub-prod
```

### 4. Create Production Network & Application Rule Collection Groups

```bash
# Add Network Rule Collection Group (Priority 1000)
az network firewall policy rule-collection-group create \
    --resource-group rg-network-hub-prod \
    --policy-name fwp-enterprise-prod \
    --name rcg-core-network \
    --priority 1000

# Add Network Rule: Allow Spoke to On-Premises DNS & NTP
az network firewall policy rule-collection-group collection add-filter-collection \
    --resource-group rg-network-hub-prod \
    --policy-name fwp-enterprise-prod \
    --rule-collection-group-name rcg-core-network \
    --name coll-internal-services \
    --collection-priority 1100 \
    --action Allow \
    --rule-name Allow-DNS \
    --rule-type NetworkRule \
    --source-addresses "10.1.0.0/16" "10.2.0.0/16" \
    --destination-addresses "10.0.0.10" "10.0.0.11" \
    --destination-ports 53 \
    --ip-protocols UDP TCP

# Add Application Rule: Allow Outbound GitHub & Linux Package Repositories
az network firewall policy rule-collection-group collection add-filter-collection \
    --resource-group rg-network-hub-prod \
    --policy-name fwp-enterprise-prod \
    --rule-collection-group-name rcg-core-network \
    --name coll-outbound-web \
    --collection-priority 1200 \
    --action Allow \
    --rule-name Allow-DevOps \
    --rule-type ApplicationRule \
    --source-addresses "10.1.0.0/16" \
    --target-fqdns "github.com" "*.github.com" "archive.ubuntu.com" "*.docker.io" \
    --protocols Http=80 Https=443
```

### 5. Enforce Spoke Egress via User Defined Route (UDR)

```bash
# Obtain private IP of the firewall
FW_PRIVATE_IP=$(az network firewall show \
    --resource-group rg-network-hub-prod \
    --name afw-core-hub-prod \
    --query "ipConfigurations[0].privateIpAddress" -o tsv)

# Create Route Table directing 0.0.0.0/0 to the Firewall
az network route-table create \
    --resource-group rg-network-hub-prod \
    --name rt-spoke-to-firewall

az network route-table route create \
    --resource-group rg-network-hub-prod \
    --route-table-name rt-spoke-to-firewall \
    --name default-to-firewall \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address "${FW_PRIVATE_IP}"
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Standard Quota / Limit | Operational Guidance |
| :--- | :--- | :--- |
| **Max Throughput** | Up to 100 Gbps (Premium) | Auto-scales in 1 Gbps / 500 Mbps steps |
| **Subnet Size Required** | `/26` minimum (64 IPs) | Cannot be resized after firewall deployment |
| **Max Public IPs for SNAT** | 250 public IP addresses | Each IP provides 64,960 SNAT ports |
| **Rule Collection Groups** | 60 per policy | Order priorities in increments of 100 |
| **Max Rules per Policy** | 10,000 rules | Consolidate IP ranges with IP Groups |
| **TLS Inspection CA Key** | Azure Key Vault managed | Requires Enterprise Intermediate CA cert |
| **SLA Guarantee** | **99.99%** with 3 Availability Zones | Spans 3 physical zones within the region |

---

## 5. Official References & Documentation

- [Azure Firewall Architecture Overview](https://learn.microsoft.com/en-us/azure/firewall/overview)
- [Azure Firewall Premium Features (TLS & IDPS)](https://learn.microsoft.com/en-us/azure/firewall/premium-features)
- [Azure Firewall Policy Rule Processing Logic](https://learn.microsoft.com/en-us/azure/firewall/rule-processing)
- [Virtual WAN Secured Hub Integration](https://learn.microsoft.com/en-us/azure/virtual-wan/secure-firewall)
- [Azure Firewall Pricing Matrix](https://azure.microsoft.com/en-us/pricing/details/azure-firewall/)

---

## 6. Realistic Pricing Scenarios

Azure Firewall pricing is based on:
1. **Base Deployment Fee:**
   - Standard: ~$1.25 per hour (~$912.50/month).
   - Premium: ~$1.75 per hour (~$1,277.50/month).
2. **Data Processed:**
   - Standard: $0.016 per GB processed.
   - Premium: $0.016 per GB processed.
3. **Public IP Addresses:** Standard Public IP rate ($0.005/hr each).

### Scenario A: Enterprise Hub-and-Spoke Deployment (Standard Firewall)

- **Architecture:**
  - 1 Azure Firewall Standard deployed in multi-zone Hub VNet.
  - 10 Spoke VNets routing all cross-spoke and internet-bound traffic through the firewall.
  - Data Volume Processed: 5,000 GB (5 TB) per month.
  - Public IPs: 2 Standard Public IPs for outbound SNAT.
- **Monthly Cost Calculation:**
  - Firewall Base: $1.25/hr × 730 hrs = **$912.50**
  - Data Processing: 5,000 GB × $0.016/GB = **$80.00**
  - Public IPs: 2 IPs × $0.005/hr × 730 hrs = **$7.30**
- **Total Monthly Cost:** **$999.80 / month**

### Scenario B: Highly Regulated Financial Workload (Premium Firewall + Deep Packet Inspection)

- **Architecture:**
  - 1 Azure Firewall Premium deployed across 3 Availability Zones.
  - Full TLS Inspection & IDPS enabled for all outbound banking APIs and payment gateways.
  - Data Volume Processed: 25,000 GB (25 TB) per month.
  - Public IPs: 5 Standard Public IPs.
- **Monthly Cost Calculation:**
  - Firewall Base (Premium): $1.75/hr × 730 hrs = **$1,277.50**
  - Data Processing: 25,000 GB × $0.016/GB = **$400.00**
  - Public IPs: 5 IPs × $0.005/hr × 730 hrs = **$18.25**
- **Total Monthly Cost:** **$1,695.75 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Subnet Size `/26` Minimum Trap:** Azure documentation previously permitted `/25` or `/26` subnets. If you deploy Azure Firewall into a `/27` or smaller subnet, the deployment will fail immediately. Furthermore, as the firewall scales out to 50+ underlying instances under heavy traffic, it consumes internal IP addresses from `AzureFirewallSubnet`. You **cannot resize the subnet after deployment** without completely deleting the firewall, dropping production routing for 30+ minutes. Always allocate at least a `/26` prefix.
2. **SNAT Port Exhaustion on Outbound Connections:** When spoke VMs connect to external web services or third-party APIs via Azure Firewall, the firewall masks their source IP using its public IP address (SNAT). Each public IP provides 64,960 SNAT ports. If your spoke microservices open thousands of concurrent outbound short-lived TCP connections, the firewall runs out of SNAT ports, resulting in random 30-second TCP timeouts. Always attach a pool of at least 3 to 5 Public IPs to your production firewall.
3. **Application Rules Convert Network Traffic to HTTP Proxies:** When you define an Application Rule with target FQDNs (e.g., `*.github.com`), Azure Firewall routes that traffic through an internal transparent Envoy proxy. If an application attempts to speak a non-HTTP protocol (e.g., SSH on port 22, Git SSH, custom binary TCP) targeting a domain name, the connection **will be terminated immediately with a protocol error**. Non-HTTP traffic must always be routed through **Network Rules**, never Application Rules.
4. **Asymmetric Routing Disasters with ExpressRoute/VPN:** If a spoke VM receives incoming traffic from an on-premises datacenter via ExpressRoute, but the spoke subnet has a UDR sending `0.0.0.0/0` to Azure Firewall, the return packets will route to the firewall instead of back through the ExpressRoute Gateway. Because Azure Firewall is stateful and never saw the initial SYN packet, it will drop the return packet immediately as invalid state. To prevent this, add a specific route in the UDR for your on-premises CIDR block pointing directly to `VirtualNetworkGateway`.
5. **TLS Inspection Requires Intermediate CA Chain Installation:** To use TLS Inspection on Azure Firewall Premium, you must import a CA certificate into Azure Key Vault and grant the firewall managed identity access to it. If the client machines (VMs, container pods) in your spoke VNets do not have the Root CA of that intermediate certificate installed in their local OS trust stores (`/etc/ssl/certs/` or Windows Certificate Store), every single HTTPS call made by `curl`, Python `requests`, or Java will fail with `SSL_CERTIFICATE_VERIFY_FAILED`.
6. **Use IP Groups to Prevent Rule Compilation Delays:** If your firewall policy contains thousands of individual IP addresses entered directly into rule lines, Azure Firewall Policy updates take 10 to 20 minutes to compile and distribute across instances. Group your CIDR blocks into **Azure IP Groups** (`az network ip-group`). Updating an IP Group updates all linked rules in seconds without recompiling the entire policy.

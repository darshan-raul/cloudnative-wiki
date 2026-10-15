---
title: Azure Networking Architecture Hub
description: Master architectural guide to Microsoft Azure networking — Virtual Networks (VNet), NSGs, Load Balancing, Azure Firewall, Virtual WAN, Private Link, DNS, ExpressRoute, and Bastion.
tags:
  - azure
  - networking
  - vnet
  - hybrid-networking
  - firewall
  - security
date: 2026-10-15
---

# Azure Networking Architecture Hub 🌐🧱

Microsoft Azure's software-defined networking (SDN) platform provides a global, enterprise-grade substrate for cloud-native applications, hybrid multi-cloud transit, perimeter security, and zero-trust private communications.

---

## Architectural Decision Framework

```
                               Network Architecture Need
                                           │
            ┌──────────────────────────────┼──────────────────────────────┐
            ▼                              ▼                              ▼
    Core Foundation & Routing     Security & Isolation          Global Transit & Ingress
            │                              │                              │
    ┌───────┴───────┐              ┌───────┴───────┐              ┌───────┴───────┐
    ▼               ▼              ▼               ▼              ▼               ▼
[[Azure/networking/vnet|Azure VNet]]   [[Azure/networking/expressroute-vpn|ExpressRoute/VPN]] [[Azure/networking/nsg|NSG & ASG]]   [[Azure/networking/firewall/README|Azure Firewall]] [[Azure/networking/load-balancing|Load Balancing]] [[Azure/networking/virtual-wan/README|Virtual WAN]]
- Regional CIDR - Dedicated L3 - L3/L4 Rules   - L7 Threat IDPS - App Gateway    - Global Hub
- Subnet Rules  - BGP Transit  - Stateful      - TLS Inspection - Front Door     - Any-to-Any
```

### Core Networking Capabilities Matrix

| Capability                | Azure Solution                                                   | AWS Equivalent                | GCP Equivalent                | Key Cloud Native Differentiator                                                            |
| :------------------------ | :--------------------------------------------------------------- | :---------------------------- | :---------------------------- | :----------------------------------------------------------------------------------------- |
| **Virtual Network Scope** | [[Azure/networking/vnet\|Regional VNet]]                         | Regional VPC                  | Global VPC                    | Azure isolates VNets by region; GCP VPCs span all global regions natively.                 |
| **Micro-Segmentation**    | [[Azure/networking/nsg\|NSGs & ASGs]]                            | Security Groups               | VPC Firewall Rules / Tags     | Azure NSGs are stateful at both Subnet and NIC levels, with Application Security Groups.   |
| **Layer 4 & 7 Balancing** | [[Azure/networking/load-balancing\|Load Balancer & App Gateway]] | NLB & ALB                     | Cloud Load Balancing          | App Gateway v2 integrates native OWASP ModSecurity WAF and URL path rewriting.             |
| **Global Edge Anycast**   | [[Azure/networking/load-balancing\|Azure Front Door]]            | CloudFront + Route 53         | Cloud CDN + Global HTTPS LB   | Anycast edge termination with integrated WAF, caching, and SSL offloading.                 |
| **Private PaaS Ingress**  | [[Azure/networking/private-link/README\|Azure Private Link]]     | AWS PrivateLink               | Private Service Connect (PSC) | Eliminates public IPs from PaaS services; routes securely over Azure backbone.             |
| **Secured Hub & Mesh**    | [[Azure/networking/virtual-wan/README\|Azure Virtual WAN]]       | AWS Cloud WAN / Transit GW    | Network Connectivity Center   | Fully managed Microsoft-managed transit hub with automated routing and firewall injection. |
| **Enterprise Hybrid**     | [[Azure/networking/expressroute-vpn\|ExpressRoute & VPN]]        | Direct Connect & Site-to-Site | Cloud Interconnect & VPN      | ExpressRoute FastPath allows hypervisor-level data-path bypass directly to VM NICs.        |
| **Zero-Public-IP Access** | [[Azure/networking/bastion-nat\|Azure Bastion]]                  | EC2 Instance Connect Endpoint | Identity-Aware Proxy (IAP)    | Web browser and CLI-based RDP/SSH jump host without exposing public VM IPs.                |
| **Outbound SNAT Egress**  | [[Azure/networking/bastion-nat\|Azure NAT Gateway]]              | AWS NAT Gateway               | Cloud NAT                     | Provides 64,512 SNAT ports per IP, completely eliminating outbound socket starvation.      |

---

## Service Catalog

### 1. Foundation & Micro-Segmentation

- [[Azure/networking/vnet|Virtual Network (VNet) & Hybrid Routing]] — Regional VNet architecture, the 5 reserved subnet IP addresses, VNet Peering with Gateway Transit, User Defined Routes (UDRs), and system routes.
- [[Azure/networking/nsg|Network Security Groups (NSGs) & Application Security Groups (ASGs)]] — Rule priority evaluation (100–4096), default rules, Service Tags, ASG workload grouping, and dual-layer subnet vs NIC filtering.

### 2. Traffic Management & Load Balancing

- [[Azure/networking/load-balancing|Azure Load Balancing, Application Gateway & Front Door]] — Layer 4 Azure Load Balancer, Layer 7 Application Gateway WAF v2, Azure Front Door Anycast edge CDN, and Private Link integration.
- [[Azure/networking/dns-traffic-manager|Azure DNS & Traffic Manager Architecture]] — Public Anycast DNS, Private DNS Zones, Azure DNS Private Resolver for hybrid resolution, and Traffic Manager's 6 DNS routing methods.

### 3. Perimeter Defense & Zero Trust

- [[Azure/networking/firewall/README|Azure Firewall & IDPS]] — Standard vs Premium tiers, TLS inspection, 67,000+ signature intrusion detection, FQDN filtering, and Virtual WAN Secured Hub integration.
- [[Azure/networking/private-link/README|Azure Private Link, Private Endpoints & DNS]] — Securing Azure PaaS behind private IP addresses, Private DNS Zone integration, eliminating public access, and exfiltration defense.
- [[Azure/networking/bastion-nat|Azure Bastion & NAT Gateway Architecture]] — Fully managed zero-public-IP RDP/SSH jump hosts (Developer vs Standard SKU) and outbound SNAT port exhaustion mitigation.

### 4. Global Transit & Hybrid Interconnect

- [[Azure/networking/virtual-wan/README|Azure Virtual WAN (vWAN)]] — Global transit networking, Secured Virtual Hubs, any-to-any VNet transit, automated branch connectivity, and NVA integration.
- [[Azure/networking/expressroute-vpn|Azure ExpressRoute & VPN Gateway Hybrid Architecture]] — Private and Microsoft Peering, FastPath wire-speed bypass, Active-Active BGP routing (ASN 65515), and S2S VPN disaster recovery coexistence.

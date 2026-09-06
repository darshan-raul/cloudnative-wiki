---
title: GCP Cloud DNS Architecture
description: Cloud DNS architecture — 100% uptime SLA, Anycast nameservers, split-horizon DNS, private forwarding zones, DNS peering, Response Policies (RPZ), and DNSSEC.
tags:
  - gcp
  - networking
  - dns
  - cloud-dns
  - security
---

# GCP Cloud DNS Architecture 🌐📡

Google Cloud DNS is a high-performance, resilient Domain Name System (DNS) service running on Google's global Anycast infrastructure. Backed by an industry-leading **100% availability SLA**, Cloud DNS translates domain names into IP addresses with ultra-low latency worldwide while providing advanced hybrid capabilities: **Split-Horizon DNS**, **Private Forwarding Zones**, and **DNS Peering**.

---

## Architecture & Mental Model

### Split-Horizon DNS & Hybrid Forwarding

```
                             Client Query: "api.company.com"
                                           │
                       Is the query originating from inside VPC?
                       ├── YES (Private Resolver in Andromeda)
                       │    │
                       │    ▼
                       │  Private Managed Zone (Internal IP: 10.10.0.50)
                       │  (Only reachable by authorized VPC networks)
                       │
                       └── NO (Public Internet Anycast Resolver)
                            │
                            ▼
                          Public Managed Zone (Public Anycast IP: 34.120.50.1)
                          (Reachable by public clients worldwide)
```

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Hybrid DNS Resolution Flow                      │
│                                                                        │
│   GCP VPC: prod-vpc                                                    │
│   └── VM requests: "database.corp.onprem"                              │
│       │                                                                │
│       ▼                                                                │
│   Cloud DNS Forwarding Zone for "corp.onprem"                          │
│   └── Next Hop: 192.168.1.10 (On-Premises Windows/BIND DNS Server)    │
│       │                                                                │
│       ▼ Traverses Cloud Interconnect / HA VPN                          │
│   On-Premises Corporate Datacenter                                     │
│   └── Internal DNS Server resolves private on-prem IP address          │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Core Concepts

### 1. Public vs. Private Managed Zones

| Zone Type | Visibility | Access Control | SLA |
| :--- | :--- | :--- | :--- |
| **Public Zone** | Global Public Internet | Anyone querying public Anycast nameservers (`ns-cloud-a1.googledomains.com`) | **100%** |
| **Private Zone** | Internal to Google Cloud | Restricted strictly to authorized VPC networks in your projects | **100%** |

### 2. Split-Horizon DNS

Enables using the identical domain name (e.g. `service.company.com`) with different resolution targets depending on whether the request originates internally or externally:
* **Internal VPC Queries:** Resolve to internal RFC 1918 addresses (e.g. `10.10.1.5` behind an Internal Application Load Balancer).
* **Public Internet Queries:** Resolve to the public IP address (e.g. `34.120.10.5` protected by Cloud Armor WAF).

### 3. DNS Forwarding & Inbound DNS Policies

* **Outbound DNS Forwarding:** A private zone configured to forward queries for specific domain suffixes (e.g. `*.corp.internal`) to on-premises DNS servers over Cloud VPN or Cloud Interconnect.
* **Inbound DNS Policy:** Provisions an **Inbound DNS Forwarding Endpoint** (internal IP) inside your VPC subnet. On-premises servers can query this IP to resolve private GCP records!

### 4. DNS Peering

DNS Peering allows a VPC network to share private DNS zones with another VPC network without establishing full network routing or VPC Network Peering:
* VPC A peers its DNS namespace to VPC B.
* Instances in VPC A can resolve private records hosted in VPC B's private DNS zone.

### 5. DNSSEC (Domain Name System Security Extensions)

Cloud DNS provides automated managed **DNSSEC**:
* Cryptographically signs DNS records using public-key cryptography.
* Protects clients against DNS spoofing, cache poisoning, and man-in-the-middle record hijacking.

---

## Production `gcloud` CLI Commands

### 1. Creating a Private Managed Zone Authorized for a VPC

```bash
gcloud dns managed-zones create internal-company-zone \
  --description="Private DNS zone for internal microservices" \
  --dns-name="corp.internal." \
  --visibility=private \
  --networks=prod-vpc
```

### 2. Creating an Outbound DNS Forwarding Zone to On-Premises DNS

```bash
gcloud dns managed-zones create onprem-forwarding-zone \
  --description="Forward corporate queries to on-prem DNS" \
  --dns-name="onprem.company.com." \
  --visibility=private \
  --networks=prod-vpc \
  --forwarding-targets="192.168.1.10,192.168.1.11"
```

### 3. Enabling Inbound DNS Queries from On-Premises

```bash
# Create Inbound DNS Policy allocating internal IPs in each subnet
gcloud dns policies create inbound-dns-policy \
  --description="Permits on-prem systems to resolve GCP private DNS" \
  --networks=prod-vpc \
  --enable-inbound-forwarding
```

### 4. Creating DNS Records (A and CNAME Records)

```bash
# 1. Start a transaction
gcloud dns record-sets transaction start --zone=internal-company-zone

# 2. Add an 'A' record pointing to Internal Load Balancer
gcloud dns record-sets transaction add 10.10.1.50 \
  --name="api.corp.internal." \
  --ttl=300 \
  --type=A \
  --zone=internal-company-zone

# 3. Execute the transaction
gcloud dns record-sets transaction execute --zone=internal-company-zone
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Managed Zones per project** | 10,000 zones | Increase via quota console |
| **Resource Records per zone** | Up to 100,000 records | Use transactions for batch updates |
| **VPC networks per private zone** | Up to 100 networks | Can authorize across projects |
| **Forwarding targets per zone** | Up to 15 IP targets | Redundant on-prem resolvers |
| **SLA Availability** | **100% Uptime SLA** | Google's highest cloud SLA |

---

## References

* **Cloud DNS Overview:** https://cloud.google.com/dns/docs/overview
* **Private Zones Guide:** https://cloud.google.com/dns/docs/zones/zones-overview#private-zones
* **Hybrid DNS Setup:** https://cloud.google.com/dns/docs/zones/forwarding-zones
* **Pricing:** https://cloud.google.com/dns/pricing

---

## Pricing Examples

### Scenario 1: Standard Enterprise Private DNS Architecture
* 5 Private Managed Zones (e.g. `corp.internal`, `dev.internal`, `data.internal`).
* 2,500 Resource Record Sets across all zones.
* Total DNS queries: 50 million queries / month.
* Zone hosting fee: First 25 zones = $0.20 / zone / month = **$1.00 / month**.
* Query fee:
  * First 1 Billion queries: $0.40 per million queries.
  * 50M × $0.40 = **$20.00 / month**.
* **Total Monthly DNS Bill:** **~$21.00 / month** for 100% SLA enterprise resolution.

### Scenario 2: High-Traffic Public SaaS Web Application
* 1 Public Managed Zone with DNSSEC enabled.
* Total public queries: 500 million queries / month across worldwide Anycast nameservers.
* Base zone hosting: $0.20 / month.
* Query fee: 500M × $0.40 / million = $200.00.
* DNSSEC signing: **$0.00** (Free).
* **Total Monthly Cost:** **~$200.20 / month**.

---

## Nuggets & Gotchas

1. **Trailing Dots in DNS Names are Mandatory:** In Cloud DNS CLI commands and zone definitions, all fully qualified domain names (FQDNs) **must end with a trailing dot** (e.g. `--dns-name="corp.internal."` and `--name="api.corp.internal."`). Omitting the trailing dot will result in syntax validation errors or unexpected relative subdomain nesting (e.g. `api.corp.internal.corp.internal.`).
2. **Inbound DNS Forwarding Subnet IP Allocation:** Enabling an Inbound DNS Policy allocates a private IP address in **every single subnet** of your VPC. If on-premises firewalls only permit traffic to specific IPs, ensure you document the specific subnet IP assigned by Cloud DNS (`gcloud compute addresses list`).
3. **DNS Forwarding Targets Must Not Loop Back:** If you configure a Cloud DNS Forwarding Zone for `corp.internal` pointing to an on-prem server, and that on-prem server has a forwarder pointing back to GCP for `corp.internal`, queries will enter an **infinite recursive DNS loop**, causing queries to time out and exhausting resolver connections.
4. **VPC Peering Does Not Peer DNS Automatically:** Establishing VPC Network Peering between VPC A and VPC B allows network IP routing, but **does not share private DNS zones**. Instances in VPC B cannot resolve VPC A's private DNS records unless VPC A explicitly adds VPC B to the private zone's authorized networks or sets up a DNS Peering zone.
5. **DNS Propagation Time vs TTL Caching:** While updates to Cloud DNS records propagate across Google's global Anycast nameservers in under **5 seconds**, recursive resolvers on the public internet cache records according to the record's **Time-to-Live (TTL)**. When planning an IP migration, lower the record's TTL to 60 seconds at least 48 hours in advance.

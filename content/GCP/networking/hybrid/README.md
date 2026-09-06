---
title: GCP Cloud Interconnect & HA VPN
description: GCP Hybrid Connectivity architecture — Cloud HA VPN (99.99% SLA), Dedicated vs Partner Interconnect, BGP routing with Cloud Router, and 99.99% enterprise topologies.
tags:
  - gcp
  - networking
  - hybrid
  - vpn
  - interconnect
  - bgp
---

# GCP Cloud Interconnect & HA VPN 🌐🔌

Google Cloud Hybrid Connectivity links on-premises corporate datacenters, branch offices, and colocation facilities to your Google Cloud VPC networks. Depending on bandwidth, latency, and SLA requirements, Google provides two enterprise-grade solutions: **Cloud HA VPN** (IPSec VPN over the public internet with a 99.99% SLA) and **Cloud Interconnect** (direct physical fiber cross-connects delivering 10 Gbps to 100 Gbps circuits with up to a 99.99% SLA).

---

## Architecture & Mental Model

### High Availability Topologies (99.99% SLA Architectures)

#### 1. Cloud HA VPN Topology (Active-Active Dual Tunnels)

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Google Cloud Region (us-central1)               │
│                                                                        │
│   Cloud Router (ASN: 16550, Global BGP Routing)                        │
│   Cloud HA VPN Gateway (2 Fixed Public Anycast IPs: IP-A and IP-B)     │
└──────────────┬──────────────────────────────────────────┬──────────────┘
               │ Tunnel 0 (IPSec + BGP)                   │ Tunnel 1 (IPSec + BGP)
               │ (Active)                                 │ (Active)
               ▼ Traverses Public Internet                ▼ Traverses Public Internet
┌──────────────┴──────────────────────────────────────────┴──────────────┐
│                    On-Premises Enterprise Datacenter                   │
│                                                                        │
│   Dual Customer Gateway Devices (or single multi-interface router)     │
│   BGP ASN: 65001 (Advertising On-Prem CIDRs: 192.168.0.0/16)          │
└────────────────────────────────────────────────────────────────────────┘
```

#### 2. Cloud Interconnect 99.99% Dual-Metro Architecture

For mission-critical production workloads, Google mandates a **4-circuit, dual-metropolitan topology** to qualify for the 99.99% availability SLA:

```
                  ┌────────────────────────────────────────┐
                  │          Google Cloud Global VPC       │
                  │   Cloud Router A        Cloud Router B │
                  └─────────┬────────────────────┬─────────┘
                            │                    │
             ┌──────────────┴──────┐      ┌──────┴─────────────┐
             ▼                     ▼      ▼                    ▼
     ┌──────────────┐     ┌──────────────┐┌──────────────┐┌──────────────┐
     │ VLAN Attach.1│     │ VLAN Attach.2││ VLAN Attach.3││ VLAN Attach.4│
     └──────┬───────┘     └──────┬───────┘└──────┬───────┘└──────┬───────┘
            │                    │               │               │
     ┌──────┴──────┐      ┌──────┴───────┐┌──────┴──────┐ ┌──────┴───────┐
     │ Colocation  │      │ Colocation   ││ Colocation  │ │ Colocation   │
     │ Facility 1  │      │ Facility 1   ││ Facility 2  │ │ Facility 2   │
     │ Metro: CHI  │      │ Metro: CHI   ││ Metro: DAL  │ │ Metro: DAL   │
     └──────┬──────┘      └──────┬───────┘└──────┬──────┘ └──────┬───────┘
            │                    │               │               │
            └───────────── Direct Physical Fiber ────────────────┘
                                 │
                                 ▼
                     On-Premises Core Routers
```

---

## Comparison: HA VPN vs. Dedicated vs. Partner Interconnect

| Feature | Cloud HA VPN | Partner Interconnect | Dedicated Interconnect |
| :--- | :--- | :--- | :--- |
| **Physical Medium** | Public Internet (IPSec encrypted) | Service Provider network (Equinix, Megaport, AT&T) | **Direct physical fiber cross-connect** to Google Colocation |
| **Circuit Bandwidth**| Up to **3 Gbps per tunnel** (scale with multiple tunnels) | **50 Mbps to 100 Gbps** per VLAN attachment | **10 Gbps or 100 Gbps** per physical port |
| **Setup Time** | **Minutes** via CLI / Console | Days to weeks | Weeks to months (cross-connect provisioning) |
| **Routing Protocol**| Dynamic BGP exclusively | Dynamic BGP exclusively | Dynamic BGP exclusively |
| **Maximum SLA** | **99.99%** | **99.99%** (dual-metro) or 99.9% | **99.99%** (dual-metro) or 99.9% |
| **Encryption** | Built-in AES-GCM IPSec encryption | Unencrypted by default (add Cloud Interconnect MACsec) | Unencrypted by default (add Cloud Interconnect MACsec) |

---

## Core Concepts

### 1. Cloud Router & BGP Route Exchange

All hybrid connectivity in GCP terminates logically on a **Cloud Router**:
* **eBGP Sessions:** Exchanging routes dynamically between Google Cloud and on-premises routers.
* **Autonomous System Numbers (ASNs):** Google Cloud uses private ASN `16550` by default (or user-configurable RFC 6996 private ASNs: `64512–65534`).
* **Multi-Exit Discriminator (MED):** Used by on-premises routers to configure active/passive failover paths by assigning route preferences.

### 2. VPC Dynamic Routing: Regional vs. Global

* **Regional Dynamic Routing (Default):** Cloud Router only advertises and learns routes for subnets within its **own region** (e.g. `us-central1`).
* **Global Dynamic Routing:** Cloud Router advertises and learns routes for **all subnets across the entire global VPC worldwide**. An on-prem datacenter connected to Chicago can route directly to VMs in Frankfurt or Tokyo over Google's private backbone!

### 3. Cloud Interconnect MACsec Encryption

By default, physical fiber interconnects transmit unencrypted Ethernet frames. For zero-trust compliance (HIPAA, PCI-DSS):
* **MACsec (IEEE 802.1AE):** Provides hardware-level wire-speed encryption between customer routers and Google edge switches on 100 Gbps Dedicated Interconnect circuits.

---

## Production `gcloud` CLI Commands

### 1. Provisioning a Cloud HA VPN Gateway with Dual Tunnels

```bash
# 1. Create a Cloud Router in the VPC
gcloud compute routers create prod-vpn-router \
  --network=prod-vpc \
  --region=us-central1 \
  --asn=65001

# 2. Create the Cloud HA VPN Gateway (Allocates two Google external Anycast IPs)
gcloud compute vpn-gateways create prod-ha-vpn-gw \
  --network=prod-vpc \
  --region=us-central1

# 3. Create External VPN Gateway representing on-prem routers
gcloud compute external-vpn-gateways create onprem-peer-gw \
  --interfaces 0=203.0.113.50,1=203.0.113.51

# 4. Create Tunnel 0
gcloud compute vpn-tunnels create vpn-tunnel-0 \
  --peer-external-gateway=onprem-peer-gw \
  --peer-external-gateway-interface=0 \
  --region=us-central1 \
  --ike-version=2 \
  --shared-secret="MySuperSecretPresharedKey123!" \
  --router=prod-vpn-router \
  --vpn-gateway=prod-ha-vpn-gw \
  --interface=0

# 5. Create Tunnel 1 (Mandatory for 99.99% SLA)
gcloud compute vpn-tunnels create vpn-tunnel-1 \
  --peer-external-gateway=onprem-peer-gw \
  --peer-external-gateway-interface=1 \
  --region=us-central1 \
  --ike-version=2 \
  --shared-secret="MySuperSecretPresharedKey123!" \
  --router=prod-vpn-router \
  --vpn-gateway=prod-ha-vpn-gw \
  --interface=1
```

### 2. Configuring BGP Interfaces and Peers on Cloud Router

```bash
# 1. Add BGP Interface for Tunnel 0
gcloud compute routers add-interface prod-vpn-router \
  --interface-name=if-tunnel-0 \
  --ip-address=169.254.0.1 \
  --mask-length=30 \
  --vpn-tunnel=vpn-tunnel-0 \
  --region=us-central1

# 2. Add BGP Peer for Tunnel 0
gcloud compute routers add-bgp-peer prod-vpn-router \
  --peer-name=bgp-peer-0 \
  --interface=if-tunnel-0 \
  --peer-ip-address=169.254.0.2 \
  --peer-asn=65002 \
  --region=us-central1
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **HA VPN Throughput** | Up to 3 Gbps per tunnel (ingress + egress) | Max 250,000 packets/sec per tunnel |
| **Max Tunnels per HA VPN Gateway** | Up to 128 tunnels | Scales across multiple peers/regions |
| **Dedicated Interconnect Port Speeds**| 10 Gbps or 100 Gbps | Up to 8 circuits in a Link Aggregation Group (LAG) |
| **BGP Dynamic Learned Routes** | 100 routes (default) | Can be increased to 1,000 via quota request |
| **SLA Guarantee** | **99.99% Uptime** | Strictly requires dual-tunnel or dual-metro setup |

---

## References

* **Cloud HA VPN Documentation:** https://cloud.google.com/network-connectivity/docs/vpn/concepts/overview
* **Cloud Interconnect Overview:** https://cloud.google.com/network-connectivity/docs/interconnect/concepts/overview
* **99.99% SLA Topology Guide:** https://cloud.google.com/network-connectivity/docs/interconnect/tutorials/dedicated-creating-9999-pipeline
* **Cloud Router BGP Configuration:** https://cloud.google.com/network-connectivity/docs/router/concepts/overview
* **Pricing:** https://cloud.google.com/network-connectivity/pricing

---

## Pricing Examples

### Scenario 1: Cloud HA VPN for Enterprise Branch Office
* 1 HA VPN Gateway in `us-central1` with 2 active tunnels connected to corporate headquarters.
* Gateway fee: 1 gateway × $0.05 / hour × 730 hrs = **$36.50 / month**.
* Tunnel fees: 2 tunnels × $0.05 / hour × 730 hrs = **$73.00 / month**.
* Outbound egress over VPN: 2 TB / month ($0.08 / GB = $160.00).
* **Total Monthly Cost:** $36.50 + $73.00 + $160.00 = **~$269.50 / month** (Guaranteed 99.99% SLA).

### Scenario 2: High-Bandwidth Dedicated Interconnect (10 Gbps)
* 2 × 10 Gbps Dedicated Interconnect physical cross-connects (for 99.9% high availability in one colocation facility).
* Port fee: 2 ports × $1,700.00 / port / month = **$3,400.00 / month**.
* 2 VLAN Attachments: 2 × $72.00 / month = **$144.00 / month**.
* Outbound egress data processed (50 TB): Discounted Interconnect egress rate ($0.02 / GB = **$1,000.00**).
* **Total Monthly Bill:** **~$4,544.00 / month** (Delivers dedicated line rate with sub-millisecond latency).

---

## Nuggets & Gotchas

1. **The 99.99% SLA Requires Two Independent Metropolitan Areas:** To qualify for Google's 99.99% Cloud Interconnect SLA, your circuits cannot reside in the same physical city or facility. You **must** provision two circuits in Metropolitan Area A (e.g. Chicago) and two circuits in Metropolitan Area B (e.g. Dallas). Deploying all 4 circuits in the same building qualifies for only a 99.9% SLA.
2. **Static Routes Are Prohibited on Cloud HA VPN:** Cloud HA VPN **strictly requires dynamic BGP routing via Cloud Router**. You cannot configure static routes (`0.0.0.0/0 via tunnel-ip`) on HA VPN gateways; any attempt to do so will fail validation. Your on-premise firewall or router must support BGP (RFC 4271).
3. **BGP Learned Route Quota Overflow Drops Connectivity:** By default, Cloud Router accepts a maximum of **100 learned routes** from on-premises BGP peers. If an on-premises network engineer accidentally redistributes an internal BGP table containing 101 routes, Cloud Router will drop the BGP session entirely! Always filter on-premises route advertisements to aggregate supernets before advertising to GCP.
4. **MTU Mismatches Cause Silent Packet Drops:** Cloud HA VPN supports an MTU of up to **1440 bytes** (or 1460 bytes in custom configurations). If on-premises client machines transmit standard 1500-byte packets without TCP Path MTU Discovery (`pmtud`) or MSS clamping enabled, large packets will be dropped silently without error, causing HTTPS handshakes to hang indefinitely.
5. **VPC Dynamic Routing Mode Pitfall:** If your VPC network uses **Regional Dynamic Routing**, a VM in `europe-west1` cannot communicate over a Cloud Interconnect established in `us-central1`. To enable global reachability from any cloud region across a single interconnect, you must update the VPC network setting to **Global Dynamic Routing** (`--bgp-routing-mode=global`).

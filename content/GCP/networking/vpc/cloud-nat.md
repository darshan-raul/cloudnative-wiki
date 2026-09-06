---
title: GCP Cloud NAT Deep Dive & SNAT Port Allocation
description: Cloud NAT architecture — software-defined distributed NAT, Cloud Router integration, dynamic port allocation, SNAT port exhaustion prevention, and outbound logging.
tags:
  - gcp
  - networking
  - cloud-nat
  - vpc
  - security
  - snat
---

# GCP Cloud NAT Deep Dive & SNAT Port Allocation 🌐🔄

Google Cloud NAT provides high-performance, software-defined Source Network Address Translation (SNAT) for Compute Engine VMs and GKE nodes that do not have external public IP addresses. 

Unlike AWS NAT Gateway (which deploys dedicated virtual appliances in a single availability zone with a 45 Gbps per-gateway bandwidth ceiling), GCP Cloud NAT is **fully distributed and software-defined**: it runs directly in the Andromeda hypervisor network, introducing **zero hop latency, zero bandwidth bottlenecks, and zero single points of failure**.

---

## Architecture & Mental Model

### Distributed Andromeda Hypervisor NAT Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        Regional VPC Subnet (us-central1)                               │
│                                                                                        │
│   Private VM 1 (10.10.0.5)      Private VM 2 (10.10.0.6)      GKE Node (10.10.0.7)     │
│   (No Public IP)                (No Public IP)                (No Public IP)           │
└──────────────┬─────────────────────────────┬─────────────────────────────┬─────────────┘
               │                             │                             │
               ▼                             ▼                             ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        Google Andromeda SDN Hypervisor Fabric                          │
│   (Performs local kernel packet rewrite: RFC 1918 Private IP ──► External NAT IP)       │
│                                                                                        │
│   Managed by: Cloud Router (Controls BGP and routing tables; no data path traffic)     │
│   Allocated External Static IPs: 34.120.10.5, 34.120.10.6                              │
└──────────────────────────────────────────┬─────────────────────────────────────────────┘
                                           │
                                           ▼ Outbound Internet Traffic
                                  [Public Internet API]
```

* **No Proxy Bottleneck:** Outbound packets travel directly from the VM's host hypervisor to the internet gateway. Packets never funnel through an intermediate NAT proxy instance or gateway appliance.

---

## Core Concepts

### 1. SNAT Mechanics & Port Allocation

When a private VM initiates a connection to an external IP address (e.g. `api.github.com:443`), Cloud NAT maps the VM's internal `(Private IP, Ephemeral Port)` tuple to an `(External NAT IP, Allocated Port)` tuple.

#### The 5-Tuple Connection Key:
`{Source IP, Source Port, Destination IP, Destination Port, Protocol}`

### 2. Static vs. Dynamic Port Allocation

| Port Allocation Mode | Mechanics | Tradeoffs |
| :--- | :--- | :--- |
| **Static Port Allocation (Default)** | Allocates a fixed number of ports per VM (default: **64 ports**) | **Risk of Port Exhaustion:** A VM making >64 simultaneous connections to the same destination IP will fail |
| **Dynamic Port Allocation (Recommended)** | Automatically adjusts port allocation between `--min-ports-per-vm` (e.g. 64) and `--max-ports-per-vm` (e.g. 1,024) based on demand | **Optimal Efficiency:** Prevents port starvation while conserving external IPv4 addresses |

### 3. SNAT Port Exhaustion (The Silent Outage)

If a high-concurrency microservice on a private VM attempts to open 100 simultaneous HTTP connections to an external third-party payment gateway (`203.0.113.10:443`), and the VM is allocated only 64 ports:
* Connections 1 through 64 succeed.
* Connections 65 through 100 **fail immediately** or hang with connection timeouts.
* Cloud NAT drops the packets due to **SNAT Port Exhaustion**, emitting a `DROPPED` metric in Cloud Monitoring.

### 4. Cloud Router Relationship

A Cloud NAT gateway is logically associated with an existing **Cloud Router** in the region:
* The Cloud Router acts as the control plane configuration manager.
* **Important:** Data plane packets do **not** traverse the Cloud Router! The router merely programs the hypervisor NAT tables.

---

## Production `gcloud` CLI Commands

### 1. Provisioning a Cloud NAT with Dynamic Port Allocation & Multiple Public IPs

```bash
# 1. Create a Cloud Router in the target region
gcloud compute routers create prod-nat-router \
  --network=prod-vpc \
  --region=us-central1

# 2. Reserve two static external IP addresses for predictable outbound whitelisting
gcloud compute addresses create nat-ip-01 nat-ip-02 \
  --region=us-central1

# 3. Create the Cloud NAT gateway with dynamic port allocation
gcloud compute routers nats create prod-nat-gateway \
  --router=prod-nat-router \
  --region=us-central1 \
  --nat-external-ip-pool=nat-ip-01,nat-ip-02 \
  --nat-all-subnet-ip-ranges \
  --enable-dynamic-port-allocation \
  --min-ports-per-vm=64 \
  --max-ports-per-vm=1024 \
  --enable-endpoint-independent-mapping=FALSE \
  --enable-logging \
  --log-filter=ERRORS_ONLY
```

* `--enable-endpoint-independent-mapping=FALSE`: Conserves NAT ports by reusing allocated ports across different destination IP endpoints.

### 2. Monitoring SNAT Port Exhaustion and Dropped Packets

```bash
# Query Cloud Monitoring for dropped connections due to port exhaustion:
gcloud monitoring metrics list \
  --filter="metric.type = \"compute.googleapis.com/nat/dropped_sent_packets_count\""
```

---

## Quotas & Limits

| Parameter | Default Limit | Production Notes |
| :--- | :--- | :--- |
| **Max external IPs per NAT gateway** | Up to 50 public IPs | Delivers over 3,200,000 concurrent ports |
| **Default ports per VM** | 64 ports | Increase or enable Dynamic Port Allocation |
| **TCP Established Connection Timeout** | 1,200 seconds (20 mins) | Reclaims idle TCP ports |
| **TCP Transitory Connection Timeout** | 30 seconds | Handshake / Reset cleanup |
| **UDP Connection Timeout** | 30 seconds | Configurable down to 10s |

---

## References

* **Cloud NAT Overview:** https://cloud.google.com/nat/docs/overview
* **Port Allocation Mechanics:** https://cloud.google.com/nat/docs/ports-and-addresses
* **Troubleshooting SNAT Exhaustion:** https://cloud.google.com/nat/docs/troubleshooting
* **Pricing:** https://cloud.google.com/nat/pricing

---

## Pricing Examples

### Scenario 1: Standard Kubernetes Cluster Outbound Egress
* 1 Cloud NAT Gateway running in `us-central1` managing 30 private GKE nodes.
* 2 Allocated Static External IP addresses.
* Fixed Gateway fee: 1 gateway × $0.045 / hour × 730 hrs = **$32.85 / month**.
* Outbound egress data processed: 5 TB / month ($0.045 / GB = **$225.00 / month**).
* Static external IPs: Free while in use by Cloud NAT.
* **Total Monthly Cloud NAT Cost:** $32.85 + $225.00 = **~$257.85 / month**.

### Scenario 2: High-Volume Data Scraping / Ingestion Service
* High-volume private compute fleet processing 50 TB of external egress data per month.
* Fixed Gateway fee: $32.85 / month.
* Data processed: 50 TB (51,200 GB) × $0.045 / GB = **$2,304.00 / month**.
* **Total Monthly Cost:** **~$2,336.85 / month** (Tip: Placing workloads in the same region as the destination reduces external data transfer charges).

---

## Nuggets & Gotchas

1. **The 64-Port Default SNAT Exhaustion Outage:** The default setting of 64 ports per VM is dangerously low for microservices that call external APIs. If an application makes 65 concurrent HTTP requests to a SaaS endpoint, the 65th connection will fail. Always enable **Dynamic Port Allocation** or set `--min-ports-per-vm=128` or `256` for container nodes.
2. **Cloud NAT Never Accepts Inbound Connections:** Cloud NAT is strictly a Source NAT (SNAT) service for outbound internet requests. It **cannot** function as a Destination NAT (DNAT) or port forwarder to route incoming public internet requests to a private VM. For inbound traffic, you must deploy a Google Cloud Load Balancer.
3. **Endpoint-Independent Mapping Multiplies Port Consumption:** Setting `--enable-endpoint-independent-mapping=TRUE` (Full Cone NAT) forces Cloud NAT to use the exact same external port for a VM regardless of the destination IP. This exhausts allocated ports dramatically faster. Leave this disabled (`FALSE`) unless specifically required for peer-to-peer VoIP or WebRTC protocols.
4. **Cloud NAT Requires Subnets in the Same Region:** A Cloud NAT gateway in `us-central1` can only translate traffic for subnets located in `us-central1`. It **cannot** provide NAT translation for instances residing in `us-east1` or `europe-west1`. You must create a dedicated Cloud NAT gateway in every region where private instances reside.
5. **Port Allocation Reductions Are Not Dynamic:** If a VM's traffic surges and Dynamic Port Allocation scales its allocated ports from 64 to 512, Cloud NAT **will not immediately shrink the allocation back to 64** when traffic subsides. Port allocations are maintained to prevent connection thrashing, gradually reconciling over time.

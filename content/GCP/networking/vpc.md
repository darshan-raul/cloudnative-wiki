---
title: GCP Virtual Private Cloud (VPC) & Networking
description: GCP VPC architecture — global VPC vs regional subnets, primary and secondary ranges, Shared VPC, Cloud NAT, and hierarchical firewall policies.
tags:
  - gcp
  - networking
  - vpc
  - security
---

# GCP Virtual Private Cloud (VPC) & Networking 🌐

Google Cloud VPC provides software-defined networking across Google's private global fiber backbone. Unlike AWS (where a VPC is bound to a single region and subnets to single availability zones), a GCP VPC is **globally scoped**: a single VPC spans all Google Cloud regions worldwide, while subnets are **regionally scoped** (spanning all zones within that region).

---

## Architecture & Mental Model

### Global VPC Topology

```
                  ┌────────────────────────────────────────────────────────┐
                  │                    GCP Global VPC                      │
                  │             (Single Global Routing Domain)             │
                  └────────────┬──────────────────────────────┬────────────┘
                               │                              │
             ┌─────────────────┴────────────┐   ┌─────────────┴────────────────┐
             ▼                              ▼   ▼                              ▼
    ┌─────────────────┐            ┌─────────────────┐        ┌─────────────────┐
    │ Subnet: us-east1│            │Subnet: us-cent1 │        │Subnet: europe-w1│
    │  10.10.0.0/20   │            │  10.20.0.0/20   │        │  10.30.0.0/20   │
    └────────┬────────┘            └────────┬────────┘        └────────┬────────┘
             │                              │                          │
      ┌──────┴──────┐                ┌──────┴──────┐            ┌──────┴──────┐
      ▼             ▼                ▼             ▼            ▼             ▼
   Zone a        Zone b           Zone a        Zone b       Zone a        Zone b
  (VM-1)        (VM-2)           (VM-3)        (VM-4)        (VM-5)        (VM-6)
      │                                                                   ▲
      └──────────────── Google Global Private Fiber Backbone ─────────────┘
                (Zero VPN/Peering required; internal IP routing)
```

* **Zero Peering Across Regions:** A VM in `us-central1-a` (`10.20.0.5`) communicates directly with a VM in `europe-west1-b` (`10.30.0.12`) over internal IP addresses without VPN tunnels, NAT gateways, or peering configurations.

---

## Core Concepts

### 1. Auto Mode vs. Custom Mode VPC

| Feature | Auto Mode VPC | Custom Mode VPC |
| :--- | :--- | :--- |
| **Creation** | Default on project creation | Manually created or via IaC |
| **Subnets** | Automatically creates a `/20` subnet in *every* GCP region | Subnets created explicitly only where needed |
| **CIDR Ranges** | Fixed, non-configurable (`10.128.0.0/9` allocated across regions) | Fully custom RFC 1918 ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) |
| **Enterprise Feasibility** | **Unusable:** Overlaps with corporate on-prem or multi-cloud CIDRs | **Standard:** Mandatory for enterprise, Shared VPC, and peering |

### 2. Primary vs. Secondary Subnet Ranges (Alias IPs)

In GCP, a subnet can have one **Primary IP Range** and multiple **Secondary IP Ranges**:
* **Primary IP Range:** Assigns internal IPv4 addresses to VM network interfaces (NICs) and GKE node VMs.
* **Secondary IP Ranges:** Used heavily by **VPC-native GKE clusters**:
  * Pod Secondary Range: Allocates a dedicated IP directly to every Kubernetes Pod.
  * Service Secondary Range: Allocates ClusterIPs for Kubernetes Services.

### 3. Shared VPC (Multi-Project Centralized Networking)

Shared VPC allows an organization to separate network administration from application development:

```
┌────────────────────────────────────────────────────────┐
│             Host Project (Managed by NetOps)           │
│  Owns: VPC, Subnets, Cloud NAT, Interconnect, Routes   │
└────────────┬──────────────────────────────┬────────────┘
             │ Subnet IAM Delegation        │ Subnet IAM Delegation
             ▼                              ▼
┌─────────────────────────┐    ┌─────────────────────────┐
│ Service Project A (Dev) │    │ Service Project B (Prod)│
│ Deploys: GCE, GKE Pods  │    │ Deploys: Cloud SQL, GKE │
└─────────────────────────┘    └─────────────────────────┘
```

* **Host Project:** Centralizes network definitions, firewall rules, and hybrid connectivity (Cloud Interconnect / Cloud VPN).
* **Service Projects:** Attached to the Host Project. Developers deploy workloads into designated host subnets using IAM permissions (`roles/compute.networkUser`).

### 4. Cloud Router & Cloud NAT

Compute Engine instances and GKE nodes without public external IPs cannot access the internet directly. 
* **Cloud NAT:** A distributed, software-defined managed NAT service. It does **not** rely on proxy VMs or bottlenecks.
* Cloud NAT is managed by **Cloud Router** in the region to handle egress traffic for all instances in that region's subnets.

### 5. Firewalls: Traditional vs. Hierarchical

GCP firewalls operate at the virtual network interface level (distributed stateful inspection):

* **Project VPC Firewall Rules:** Applied per VPC. Uses **Network Tags** or **Service Accounts** to target specific VMs.
* **Hierarchical Firewall Policies:** Applied at the Organization or Folder level. 
  * Evaluated **before** project-level VPC rules.
  * Enables security teams to enforce immutable global rules (e.g., "Deny SSH port 22 from internet across all projects").

```
Incoming Packet
      │
      ▼
Hierarchical Org Policy Firewall Rules (Evaluated First: Priority 0 - 65535)
      ├── MATCH (Deny / Allow) ──► Apply Action & Terminate
      └── GOTO_NEXT
            │
            ▼
Hierarchical Folder Policy Firewall Rules
            │
            ▼
Project VPC Firewall Rules (Evaluated Last: Priority 0 - 65535)
```

---

## Production `gcloud` CLI Commands

### 1. Provisioning a Production Custom VPC & Subnets

```bash
# 1. Create a custom-mode VPC (no auto-generated subnets)
gcloud compute networks create prod-vpc \
  --subnet-mode=custom \
  --bgp-routing-mode=global

# 2. Create a regional subnet with primary (nodes) and secondary (GKE pods/services) ranges
gcloud compute networks subnets create prod-us-central1 \
  --network=prod-vpc \
  --region=us-central1 \
  --range=10.100.0.0/20 \
  --secondary-range=gke-pods=10.101.0.0/16,gke-services=10.102.0.0/20 \
  --enable-private-ip-google-access
```

### 2. Configuring Cloud NAT for Private Egress

```bash
# 1. Create a Cloud Router in the region
gcloud compute routers create prod-nat-router \
  --network=prod-vpc \
  --region=us-central1

# 2. Add a Cloud NAT gateway to the router
gcloud compute routers nats create prod-nat-gw \
  --router=prod-nat-router \
  --region=us-central1 \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges \
  --enable-logging
```

### 3. Creating Stateful Firewall Rules

```bash
# Allow internal mesh communication between subnets
gcloud compute firewall-rules create allow-internal-mesh \
  --network=prod-vpc \
  --priority=1000 \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=all \
  --source-ranges=10.0.0.0/8

# Allow health checks from Google Cloud Load Balancer probe ranges
gcloud compute firewall-rules create allow-gcp-health-checks \
  --network=prod-vpc \
  --priority=1000 \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:80,tcp:443,tcp:8080 \
  --source-ranges=35.191.0.0/16,130.211.0.0/22 \
  --target-tags=web-backend
```

---

## Quotas & Limits

| Metric / Limit | Default Limit | Production Notes |
| :--- | :--- | :--- |
| **VPC networks per project** | 15 | Can be increased via quota request |
| **Subnets per VPC** | Unlimited (up to IP limits) | Subnets must not have overlapping CIDRs |
| **Secondary IP ranges per subnet** | 30 ranges | Plan GKE clusters carefully |
| **Internal IP addresses per VPC** | 150,000 | Encompasses VMs, GKE pods, internal LBs |
| **Firewall rules per VPC** | 500 rules | Use tags and Service Accounts to minimize rules |
| **Shared VPC Service Projects per Host** | 1,000 | Supports massive multi-tenant architectures |

---

## References

* **Homepage:** https://cloud.google.com/vpc
* **Documentation:** https://cloud.google.com/vpc/docs
* **Shared VPC Guide:** https://cloud.google.com/vpc/docs/shared-vpc
* **Cloud NAT Docs:** https://cloud.google.com/nat/docs
* **Pricing:** https://cloud.google.com/vpc/pricing

---

## Pricing Examples

### Scenario 1: Inter-Region Microservices Data Transfer
* 20 VMs communicating across regions (`us-central1` to `europe-west1`) over Google's global fiber backbone.
* Total cross-region internal egress: 15 TB / month.
* Inter-region egress rate: ~$0.02 / GB ($20 / TB).
* **Cross-Region Egress Cost:** 15 × $20 = **$300 / month** (Notice: AWS charges ~$0.02/GB cross-region as well; inter-zone within same region is $0.01/GB).

### Scenario 2: Cloud NAT for High-Throughput Cluster
* GKE cluster with 100 private nodes pulling container images and calling external SaaS APIs.
* NAT Gateway hourly rate: ~$0.045 / hour / gateway = ~$32.40 / month.
* Data processed via NAT: 10 TB / month at $0.045 / GB = $450.
* **Total Cloud NAT Cost:** ~$32.40 + $450 = **~$482.40 / month**.

---

## Nuggets & Gotchas

1. **Delete the Default Auto Mode VPC Immediately:** Default projects come with an "auto-mode" default VPC where a subnet is auto-provisioned in every GCP region. This consumes internal IP space and creates severe routing conflicts if you connect on-prem or other clouds via VPN. Always delete the `default` VPC and use custom mode.
2. **Google Cloud Health Check Probes Are External IPs:** Google Cloud Load Balancer health check probes originate from Google-owned IP blocks (`35.191.0.0/16` and `130.211.0.0/22`). If you fail to add an explicit firewall rule allowing ingress from these CIDRs to your backend VM/container ports, health checks will fail and the load balancer will mark all instances unhealthy.
3. **Private Google Access Is Required for Non-Public VMs:** If a VM has no external public IP address, it cannot access Google APIs (like `storage.googleapis.com` or `container.googleapis.com`) even though Google owns both the network and the APIs. You **must** enable `Private Google Access` on the subnet, which routes `*.googleapis.com` traffic internally through Google's frontends.
4. **VPC Peering Is NOT Transitive:** Just like AWS, VPC Network Peering in GCP is non-transitive. If VPC A peers with VPC B, and VPC B peers with VPC C, VPC A cannot communicate with VPC C through B. To achieve hub-and-spoke or multi-VPC mesh at scale, use **Network Connectivity Center** or **Private Service Connect**.
5. **GKE Secondary Range IP Exhaustion is Irreversible:** When creating a GKE cluster with VPC-native networking, Pod and Service secondary CIDRs are permanently bound to the cluster. If you undersize the secondary Pod CIDR (e.g., choosing a `/24` allowing only 256 Pod IPs), you **cannot** resize it in place; you will be forced to recreate the entire GKE cluster to expand Pod capacity.
6. **Cloud NAT Port Exhaustion (SNAT Depletion):** By default, Cloud NAT allocates 64 ports per VM. If high-concurrency microservices make thousands of simultaneous outbound connections to the same destination endpoint, connections will fail with `connection reset` or timeouts due to port exhaustion. Configure dynamic port allocation or increase `--min-ports-per-vm`.

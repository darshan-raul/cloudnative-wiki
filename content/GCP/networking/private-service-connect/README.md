---
title: GCP Private Service Connect (PSC)
description: Private Service Connect architecture — private consumption of Google APIs and multi-tenant SaaS services, Service Attachments, PSC Endpoints, and eliminating VPC peering IP overlap.
tags:
  - gcp
  - networking
  - private-service-connect
  - psc
  - security
  - saas
---

# GCP Private Service Connect (PSC) 🔌🔒

Google Cloud Private Service Connect (PSC) allows consumers to access managed services (such as Google APIs, third-party SaaS platforms like Snowflake/MongoDB Atlas, or internal microservices in other projects) privately from their own VPC network. 

By leveraging software-defined proxy translation, PSC solves the two greatest pain points of VPC Network Peering: **it completely eliminates RFC 1918 IP address overlap conflicts** and **preserves strict administrative isolation** between producer and consumer networks.

---

## Architecture & Mental Model

### Producer-Consumer Service Publishing via PSC

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Consumer Project VPC (CIDR: 10.0.0.0/16)             │
│                                                                        │
│   Compute Engine VM / GKE Pod (10.0.1.5)                               │
│   └── Connects to local private IP: 10.0.2.50                          │
│       (PSC Endpoint / Forwarding Rule in Consumer Subnet)              │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Unidirectional Encapsulated Tunnel
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   Producer Project VPC (CIDR: 10.0.0.0/16 - SAME CIDR!)│
│                                                                        │
│   PSC Service Attachment                                               │
│   ├── Associated with NAT Subnet (Purpose: PRIVATE_SERVICE_CONNECT)    │
│   │   (Translates consumer packets to 100.64.0.0/24 NAT IPs)           │
│   │                                                                    │
│   ▼                                                                    │
│   Internal Application / Network Load Balancer                        │
│   └── Routes to Backend Microservices / Database Fleet                 │
└────────────────────────────────────────────────────────────────────────┘
```

* **Zero IP Overlap Conflicts:** Both the consumer and producer VPCs can use the exact same CIDR block (`10.0.0.0/16`). Because PSC terminates traffic on a private endpoint and translates it through a dedicated NAT subnet, no IP routing collision can ever occur!

---

## Core Concepts

### 1. Private Service Connect vs. VPC Network Peering

| Dimension | VPC Network Peering | Private Service Connect (PSC) |
| :--- | :--- | :--- |
| **IP Address Constraints** | **Strictly Forbidden to Overlap:** Both VPC CIDRs must be mutually exclusive | **Overlapping CIDRs Fully Supported:** No coordination needed |
| **Routing Domain** | Merges routing domains; both networks see all routes | **Strict Isolation:** Consumer only sees a single private IP address |
| **Transitive Routing** | Non-transitive | **Fully Accessible:** Reachable from peered VNets, on-prem VPN, and Interconnect |
| **Data Exfiltration Risk**| High (entire remote VPC is routable) | **Zero Exfiltration:** Traffic cannot flow backward from producer to consumer |
| **SaaS Publishing** | Impossible to peer with hundreds of customers | **Ideal for Multi-Tenant SaaS:** Scale to thousands of consumers |

### 2. PSC Endpoints vs. PSC Backends

* **PSC Endpoint (Forwarding Rule):**
  * Allocates a dedicated private IP from the consumer's local subnet.
  * Workloads query this IP directly or via internal DNS.
  * Best for internal database access, private Google APIs (`storage.p.googleapis.com`), and SaaS consumption.
* **PSC Backend:**
  * Uses a PSC Network Endpoint Group (NEG) as a backend for a Google Cloud Load Balancer.
  * Allows you to place Cloud Armor WAF, Cloud CDN, and custom URL routing maps directly in front of cross-project or multi-tenant services.

### 3. The Producer NAT Subnet

When publishing a service via PSC, the producer must create a specialized subnet:
* **Subnet Purpose:** `PRIVATE_SERVICE_CONNECT`
* All consumer packets arriving at the producer's internal load balancer have their source IP translated (SNAT) to an IP from this NAT subnet.
* Enables the producer's firewalls and backend servers to accept traffic without knowing the consumer's internal IP ranges.

---

## Production `gcloud` CLI Commands

### 1. Producer: Publishing a Service via Service Attachment

```bash
# 1. Create the dedicated PSC NAT Subnet
gcloud compute networks subnets create psc-nat-subnet \
  --network=producer-vpc \
  --region=us-central1 \
  --range=10.100.0.0/24 \
  --purpose=PRIVATE_SERVICE_CONNECT

# 2. Create the Service Attachment pointing to an existing Internal Load Balancer
gcloud compute service-attachments create payment-service-attachment \
  --region=us-central1 \
  --producer-forwarding-rule=internal-payment-lb-fe \
  --connection-preference=ACCEPT_AUTOMATIC \
  --nat-subnets=psc-nat-subnet \
  --enable-proxy-protocol=FALSE
```

### 2. Consumer: Connecting to the Published Service via PSC Endpoint

```bash
# 1. Reserve an internal IP in the consumer subnet
gcloud compute addresses create psc-payment-ip \
  --region=us-central1 \
  --subnet=consumer-subnet \
  --addresses=10.0.2.50

# 2. Create the Forwarding Rule (PSC Endpoint) pointing to the producer's Service Attachment
gcloud compute forwarding-rules create psc-payment-endpoint \
  --region=us-central1 \
  --network=consumer-vpc \
  --address=psc-payment-ip \
  --target-service-attachment=projects/producer-proj/regions/us-central1/serviceAttachments/payment-service-attachment
```

### 3. Consumer: Accessing Google APIs Privately via PSC

```bash
# Reserve an IP and create a PSC forwarding rule for all Google APIs (BigQuery, GCS, Secret Manager)
gcloud compute addresses create psc-google-apis-ip \
  --region=us-central1 \
  --subnet=consumer-subnet \
  --addresses=10.0.2.100

gcloud compute forwarding-rules create psc-google-apis \
  --region=us-central1 \
  --network=consumer-vpc \
  --address=psc-google-apis-ip \
  --target-google-apis-bundle=all-apis
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **PSC Endpoints per VPC** | Up to 50 endpoints | Can request quota increases |
| **Service Attachments per project** | Up to 50 attachments | For publishing enterprise SaaS |
| **Max connections per Service Attachment**| 1,000 connections | Accept automatically or via project whitelist |
| **NAT Subnet sizing** | Recommended minimum `/24` | 1 NAT IP supports thousands of connections |

---

## References

* **Private Service Connect Overview:** https://cloud.google.com/vpc/docs/private-service-connect
* **Publishing Services Guide:** https://cloud.google.com/vpc/docs/configure-private-service-connect-services
* **Accessing Google APIs via PSC:** https://cloud.google.com/vpc/docs/configure-private-service-connect-apis
* **Pricing:** https://cloud.google.com/vpc/pricing#private-service-connect

---

## Pricing Examples

### Scenario 1: Private Google APIs Access via PSC Endpoint
* 1 PSC Endpoint connecting an entire private VPC to Google APIs (Cloud Storage, BigQuery, Pub/Sub).
* Fixed endpoint hourly rate: $0.01 / hour × 730 hrs = **$7.30 / month**.
* Data processed: 10 TB / month ($0.01 / GB = **$100.00 / month**).
* **Total Monthly Cost:** **~$107.30 / month** (Guarantees zero internet exposure for sensitive data queries).

### Scenario 2: Multi-Tenant Enterprise Microservice Publishing
* Central payments team publishing their API to 20 internal consumer projects via Service Attachment.
* Service Attachment hosting: **$0.00** (Free for producers).
* Consumer endpoint fee: 20 endpoints × $7.30 / month = **$146.00 / month** (Billed to individual consumer projects).
* Data transfer processed: Negligible ($0.01/GB).
* **Total Monthly Bill:** **~$146.00 / month** across all 20 consumer business units.

---

## Nuggets & Gotchas

1. **NAT Subnet Exhaustion (Connection Failures):** The producer's PSC NAT subnet translates incoming consumer connections. Each NAT IP in the subnet can maintain up to **64,000 concurrent TCP connections** to a single backend VM. If you size the NAT subnet as a tiny `/29` (leaving only 3 usable IPs) and millions of consumer connections arrive, the NAT subnet runs out of ports, causing new consumer connections to be dropped immediately. Size producer NAT subnets as at least `/24`.
2. **Client IP Loss Without PROXY Protocol v2:** Because PSC performs Source NAT, the producer's backend servers will see the source IP as an internal IP from the producer's NAT subnet (`100.64.0.x`), **obscuring the consumer's real IP address**. If your application requires the real client IP for audit logging or geo-fencing, you **must enable PROXY Protocol v2** (`--enable-proxy-protocol=TRUE`) on the Service Attachment and configure your backend Nginx/Envoy to parse the PROXY header.
3. **Consumer Firewall Rules Must Target the PSC Endpoint IP:** Inside the consumer VPC, instances must have an egress firewall rule that explicitly allows traffic to the internal IP reserved for the PSC endpoint (`10.0.2.50`). If your VPC has a default-deny egress rule and you forget to allow the PSC endpoint IP, consumer connections will time out locally.
4. **Producer Ingress Firewall Must Permit the NAT Subnet:** On the producer side, backend VMs and internal load balancers must have an ingress firewall rule permitting traffic from the **PSC NAT Subnet CIDR** (`10.100.0.0/24`). If this firewall rule is missing, health checks may pass on the load balancer, but all consumer traffic will be dropped at the backend VM virtual NIC.
5. **PSC Replaces Private Google Access:** While legacy `Private Google Access` routes API calls to the shared default virtual IPs (`199.36.153.8/30`), it cannot be extended across VPN or Cloud Interconnect to on-prem datacenters without complex DNS hacks. **Private Service Connect for Google APIs** allocates a real RFC 1918 IP inside your subnet, making it instantly reachable from on-premise servers over VPN and Interconnect with standard DNS forwarding!

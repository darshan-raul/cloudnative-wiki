---
title: GCP Cloud Load Balancing & Cloud Armor
description: GCP Cloud Load Balancing — Global Anycast IPs, Envoy-based ALBs, Maglev NLBs, Network Endpoint Groups (NEGs), Cloud Armor WAF, and Private Service Connect.
tags:
  - gcp
  - networking
  - load-balancing
  - cloud-armor
  - security
---

# GCP Cloud Load Balancing & Cloud Armor ⚖️🛡️

Google Cloud Load Balancing is built on Google's globally distributed software-defined networking infrastructure (**Google Front Ends (GFE)**, **Maglev**, and **Envoy**). 

The defining characteristic of GCP's Global External Load Balancer is its **Single Anycast IP architecture**: a single static IP address is advertised from hundreds of Google Edge Points of Presence (PoPs) worldwide. User traffic enters Google's private network at the closest geographical edge and travels entirely across Google's high-speed private fiber backbone to backend instances or containers.

---

## Architecture & Mental Model

### Global Anycast Routing vs DNS Load Balancing

```
      Client in Tokyo                     Client in London
      IP: 203.0.113.10                    IP: 198.51.100.25
             │                                    │
             ▼                                    ▼
┌──────────────────────────┐            ┌──────────────────────────┐
│  Google Edge PoP Tokyo   │            │  Google Edge PoP London  │
│ Anycast IP: 34.120.50.1  │            │ Anycast IP: 34.120.50.1  │
│   (TLS Termination)      │            │   (TLS Termination)      │
│  Cloud Armor DDoS / WAF  │            │  Cloud Armor DDoS / WAF  │
└────────────┬─────────────┘            └─────────────┬────────────┘
             │                                        │
             └─────────────── Google Private ─────────┘
                             Fiber Backbone
                                   │
                    ┌──────────────┴──────────────┐
                    ▼                             ▼
       ┌─────────────────────────┐   ┌─────────────────────────┐
       │   GCP Region: us-west1  │   │  GCP Region: europe-w1  │
       │   GKE Cluster (Zonal NEG│   │  GKE Cluster (Zonal NEG │
       │    Pod Container IP)    │   │    Pod Container IP)    │
       └─────────────────────────┘   └─────────────────────────┘
```

* **Zero DNS Switching Delay:** If `us-west1` experiences an outage, edge GFEs immediately route traffic over the private backbone to `europe-west1` without waiting for client DNS TTLs to expire.
* **Instant DDoS Absorption:** DDoS attacks are absorbed across Google's global multi-terabit edge before packets ever reach your VPC.

---

## Load Balancer Decision Matrix

| Load Balancer Type | Layer | Scope | Architecture Base | Common Use Cases |
| :--- | :--- | :--- | :--- | :--- |
| **Global External Application LB** | Layer 7 (HTTP/S) | Global | Google Front End (GFE) + Envoy | Multi-region web apps, APIs, CDN, Cloud Armor, SSL offload |
| **Regional External Application LB** | Layer 7 (HTTP/S) | Regional | Envoy in Proxy-only Subnet | Strict data sovereignty/compliance requiring traffic within one region |
| **Internal Application LB** | Layer 7 (HTTP/S) | Regional | Envoy in Proxy-only Subnet | Microservices communication within VPC, internal dashboards |
| **External Network LB** | Layer 4 (TCP/UDP) | Global / Regional | Maglev (kernel packet routing) | High-performance gaming, VoIP, non-HTTP wire-speed routing |
| **Internal Network LB** | Layer 4 (TCP/UDP) | Regional | Andromeda SDN (Direct Server Return) | Database tiers, internal TCP services, zero-hop performance |

---

## Core Concepts

### 1. Network Endpoint Groups (NEGs)

Traditional load balancers target VMs (Compute Engine instances). In modern containerized and serverless environments, GCP uses **Network Endpoint Groups (NEGs)**:

* **Zonal NEGs (Container-Native Load Balancing):**
  * Directly routes traffic from the GFE/Envoy to individual **GKE Pod IP addresses**.
  * Eliminates the double-hop latency of Kubernetes `kube-proxy` and NodePort!
* **Serverless NEGs:**
  * Routes traffic from a Global HTTP(S) Load Balancer directly to **Cloud Run**, **Cloud Functions**, or **App Engine**.
  * Allows you to put custom domains, Cloud CDN, and Cloud Armor WAF in front of serverless workloads.
* **Internet NEGs:**
  * Routes traffic to public endpoints outside Google Cloud (on-premises or 3rd-party clouds).
* **Private Service Connect (PSC) NEGs:**
  * Targets managed services in other VPCs or Google-managed tenant projects via internal endpoints.

### 2. Cloud Armor (DDoS & WAF)

Cloud Armor provides enterprise-grade Web Application Firewall (WAF) and DDoS defense integrated natively at the edge of the Global External Application Load Balancer:

* **Preconfigured WAF Rules:** Defends against OWASP Top 10 vulnerabilities (SQLi, XSS, RFI, LFI, RCE, scanner detection).
* **Adaptive Protection:** Uses machine learning models to detect anomalous traffic patterns and generates actionable mitigation rules automatically during layer 7 attacks.
* **Rate Limiting:** Enforces client-based request rate caps per IP, subnet, or custom HTTP header/cookie.
* **Geo-fencing:** Restricts or permits requests based on client country codes.

### 3. Private Service Connect (PSC)

Private Service Connect enables private, secure consumption of services across independent VPC networks (e.g. multi-tenant SaaS, internal platform teams, or managed Google APIs like BigQuery/Cloud SQL) without VPC Network Peering:
* Prevents RFC 1918 CIDR IP overlap issues.
* Consumer connects via a standard internal IP address in their local subnet.

---

## Production `gcloud` CLI Commands

### 1. Deploying a Cloud Armor Security Policy with WAF Rules

```bash
# 1. Create the Cloud Armor policy
gcloud compute security-policies create prod-waf-policy \
  --description="Production WAF policy with OWASP rules and rate limiting"

# 2. Add SQL Injection (SQLi) protection rule (OWASP ModSecurity Core Rule Set)
gcloud compute security-policies rules create 1000 \
  --security-policy=prod-waf-policy \
  --expression="evaluatePreconfiguredExpr('sqli-v33-stable')" \
  --action=deny-403 \
  --description="Block SQL injection attacks"

# 3. Add Rate Limiting rule (Max 100 requests per minute per client IP)
gcloud compute security-policies rules create 2000 \
  --security-policy=prod-waf-policy \
  --expression="true" \
  --action=rate-based-ban \
  --rate-limit-threshold-count=100 \
  --rate-limit-threshold-interval-sec=60 \
  --ban-duration-sec=300 \
  --conform-action=allow \
  --exceed-action=deny-429 \
  --enforce-on-key=IP

# 4. Attach policy to backend service
gcloud compute backend-services update prod-web-backend \
  --security-policy=prod-waf-policy \
  --global
```

### 2. Creating a Serverless NEG for Cloud Run

```bash
# 1. Create the serverless NEG pointing to Cloud Run service
gcloud compute network-endpoint-groups create cloudrun-neg \
  --region=us-central1 \
  --network-endpoint-type=serverless \
  --cloud-run-service=order-service

# 2. Add NEG to a global backend service
gcloud compute backend-services create cloudrun-backend-service \
  --global \
  --load-balancing-scheme=EXTERNAL_MANAGED

gcloud compute backend-services add-backend cloudrun-backend-service \
  --global \
  --network-endpoint-group=cloudrun-neg \
  --network-endpoint-group-region=us-central1
```

---

## Quotas & Limits

| Parameter | Default Limit | Production Notes |
| :--- | :--- | :--- |
| **Global Anycast IPv4 addresses** | 1 per forwarding rule | Included with load balancer |
| **Cloud Armor rules per policy** | 200 rules | Higher limits available for Enterprise tier |
| **Rate limit keys tracked** | Up to 100,000 unique IPs | Dynamic tracking in memory |
| **Backend services per project** | 75 | Can be increased via quota request |
| **Proxy-only subnet size** | Minimum `/26` recommended | Required for Regional/Internal Application LBs |

---

## References

* **Homepage:** https://cloud.google.com/load-balancing
* **Documentation:** https://cloud.google.com/load-balancing/docs
* **Cloud Armor Docs:** https://cloud.google.com/armor/docs
* **Container-Native Load Balancing:** https://cloud.google.com/kubernetes-engine/docs/how-to/container-native-load-balancing
* **Pricing:** https://cloud.google.com/load-balancing/pricing

---

## Pricing Examples

### Scenario 1: Global External ALB for Microservices API
* 1 Global External Application Load Balancer with 5 forwarding rules and SSL termination.
* Traffic volume: 150 million HTTP requests / month (approx. 5 TB ingress + egress).
* Base LB hourly rate: 5 forwarding rules = ~$0.025 / hour for first rule + $0.010 for each additional = ~$0.065 / hr (~$46.80 / month).
* Data processing charges: 5 TB × $0.008 / GB = $40.
* **Monthly LB Cost:** ~$46.80 + $40 = **~$86.80 / month**.

### Scenario 2: Cloud Armor Enterprise vs Standard WAF
* **Standard Tier:**
  * 1 Security Policy ($5 / month).
  * 3 Rules ($1 / rule / month = $3).
  * 10 million evaluated requests ($0.75 per million = $7.50).
  * Standard Total: **~$15.50 / month**.
* **Enterprise Tier:**
  * Flat subscription ($3,000 / month) including unlimited rules, Adaptive Protection ML, and DDoS response team billing protection against volumetric attacks.

---

## Nuggets & Gotchas

1. **Proxy-Only Subnet Requirement for Regional & Internal ALBs:** Global External ALBs run directly on Google Front Ends (GFEs). However, **Regional External** and **Internal Application LBs** run on dedicated managed Envoy proxies inside your VPC. You **must** create a subnet with purpose `REGIONAL_MANAGED_PROXY` (recommended size `/26`). If this subnet is missing or runs out of IPs, your LB cannot scale or deploy.
2. **Backend Timeouts vs Client Timeouts:** The default backend service timeout on a Global Application LB is **30 seconds**. If your backend takes 30.1 seconds to respond (e.g. an AI inference API or long reporting query), the LB will immediately terminate the connection with an `HTTP 502 Bad Gateway`. Increase `--timeout` on the backend service to match your application requirements.
3. **Firewall Rules Must Target GFE IP Ranges:** For Global ALBs, traffic arrives at your backend VMs/Pods from Google's GFE probe proxies (`130.211.0.0/22` and `35.191.0.0/16`), **not** from the client's public IP address. The original client IP is preserved in the `X-Forwarded-For` header. Ensure your ingress firewall permits Google's proxy ranges.
4. **Cloud Armor Rule Evaluation Priority:** Rules in Cloud Armor are evaluated strictly in ascending order by **Priority number** (lower numbers evaluate first). The first rule that matches an incoming request terminates evaluation. Always leave numeric gaps between rules (e.g., 1000, 1100, 1200) so you can insert emergency mitigation rules during an active incident.
5. **Session Affinity Breaches with Auto-Scaling:** Enabling `GENERATED_COOKIE` or `CLIENT_IP` session affinity on a backend service does not guarantee sticky sessions if instances auto-scale or fail health checks. Maglev and Envoy will redistribute traffic across surviving endpoints, breaking local in-memory session states. Always store persistent sessions in an external cache like Memorystore (Redis).

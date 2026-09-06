---
title: GKE Advanced Network Security — Datapath V2 eBPF, FQDN Policies, and Egress NAT
description: Exhaustive engineering guide to GKE advanced network security — GKE Datapath V2 (Cilium eBPF), Layer 7 FQDN network policies, dedicated egress NAT per namespace, Cloud Armor integration, and Private Service Connect publishing.
tags:
  - gcp
  - gke
  - networking
  - security
  - ebpf
  - cilium
---

# GKE Advanced Network Security — Datapath V2 eBPF, FQDN Policies, and Egress NAT 🛡️⚡

Network security in Google Kubernetes Engine has evolved from rudimentary Layer 3/4 IP-based firewalling into an intelligent, kernel-native security enforcement architecture. Powered by **GKE Datapath V2** (Google Cloud's managed distribution of open-source **Cilium eBPF**), GKE replaces the legacy `iptables` and `kube-proxy` networking stacks with kernel-level packet inspection. This unlocks enterprise-grade security capabilities including **Layer 7 FQDN-based egress filtering**, **namespace-level dedicated egress NAT gateways**, and zero-trust micro-segmentation.

---

## 1. Architecture: iptables vs GKE Datapath V2 (eBPF)

In traditional Kubernetes networking, every Service and NetworkPolicy rule generated hundreds of thousands of `iptables` kernel chains, leading to $O(N)$ sequential packet traversal overhead and CPU starvation during cluster scaling.

```
                  TRADITIONAL KUBERNETES (iptables / kube-proxy)
       Packet In ──► iptables (Sequential Chains: 50,000 rules) ──► O(N) Delay
                     - Linear rule evaluation burns CPU
                     - NetworkPolicy and Service routing fight for chain priority
                     - iptables locks during rule syncs cause connection drops

═════════════════════════════════════════════════════════════════════════════════

                  GKE DATAPATH V2 (Cilium eBPF Kernel Architecture)
                                    POD NETWORK (VPC)
                                           │
                                           ▼ (tc / cgroup / sock_ops)
       ┌────────────────────────────────────────────────────────────────────────┐
       │                   LINUX KERNEL EXTENDED BPF ENGINE                     │
       │                                                                        │
       │  ┌──────────────────────────────────────────────────────────────────┐  │
       │  │               eBPF BPF_MAP HASH TABLE LOOKUPS (O(1))             │  │
       │  │  - Constant-time packet routing bypassing kube-proxy             │  │
       │  │  - Zero iptables synchronization locks                            │  │
       │  └──────────────────────────────────┬───────────────────────────────┘  │
       │                                     │ Verified Packet Flow             │
       │  ┌──────────────────────────────────▼───────────────────────────────┐  │
       │  │                 KERNEL ENFORCEMENT LAYERS                        │  │
       │  │  1. Ingress & Egress NetworkPolicy (L3 / L4)                     │  │
       │  │  2. FQDN NetworkPolicy (L7 DNS Snooping & Egress Whitelisting)  │  │
       │  │  3. Pod-to-Pod mTLS Encryption (Optional Cilium IPSec / WireGuard)│  │
       │  └──────────────────────────────────┬───────────────────────────────┘  │
       └─────────────────────────────────────┼──────────────────────────────────┘
                                             │
             ┌───────────────────────────────┴───────────────────────────────┐
             │                                                               │
             ▼ Intended Internal Egress                                      ▼ Regulated External Egress
  ┌─────────────────────────────────────┐                         ┌─────────────────────────────────────┐
  │ Internal Microservices / Databases  │                         │ GKE CLOUD EGRESS NAT GATEWAY        │
  │ (Direct Private IP - VPC Native)    │                         │ (Static Deterministic Public IP     │
  └─────────────────────────────────────┘                         │  dedicated to exact namespace)      │
                                                                  └─────────────────────────────────────┘
```

### Core Architecture Constructs

1. **Datapath V2 (Cilium eBPF):** Programs byte-code directly into kernel socket hooks (`sock_ops`) and traffic control (`tc`) classifiers. Packet decisions (routing, SNAT, policy checks) occur in **$O(1)$ constant time**, supporting thousands of services and network policies without CPU degradation.
2. **FQDN Network Policies:** Traditional Kubernetes `NetworkPolicy` can only filter by CIDR blocks (e.g., `192.0.2.0/24`). Datapath V2 intercepts Pod DNS queries in the kernel, builds a local mapping between hostnames and resolved IPs, and allows or denies egress based on domain names (e.g., allow `*.stripe.com` and deny everything else).
3. **GKE Egress NAT Policies:** Allows assigning a **dedicated static public IP address** to all outbound traffic originating from specific pods or namespaces, satisfying third-party banking and partner IP-whitelisting requirements without running self-managed NAT proxies.

---

## 2. Layer 7 FQDN Network Policies & DNS Snooping

When an application pod attempts to contact an external service:
1. The pod issues a DNS lookup: `curl https://api.stripe.com`.
2. The Datapath V2 eBPF hook intercepts the DNS response from CoreDNS, dynamically extracting the returned IPv4/IPv6 addresses.
3. eBPF immediately updates the kernel BPF table whitelist for that specific pod.
4. When the pod initiates the HTTPS TCP connection to that IP, the kernel validates that the destination IP was legally returned by an authorized FQDN query and permits the packet. If the pod tries to bypass DNS and connect to an arbitrary IP, the packet is immediately dropped at the socket layer.

---

## 3. Production Deployment & CLI Operations (`gcloud` & `kubectl`)

### 1. Provision GKE Cluster with Datapath V2 Enabled

```bash
gcloud container clusters create prod-secure-cluster \
    --region=us-central1 \
    --enable-ip-alias \
    --enable-dataplane-v2 \
    --network=production-vpc \
    --subnetwork=gke-nodes-subnet \
    --cluster-secondary-range-name=gke-pods \
    --services-secondary-range-name=gke-services \
    --enable-network-policy \
    --project=core-infrastructure-prod
```
*(Note: `--enable-dataplane-v2` automatically enables Cilium eBPF and replaces `kube-proxy`).*

### 2. Deploy Zero-Trust Default-Deny NetworkPolicy

Isolate the `payment` namespace so all pods deny inbound and outbound traffic by default:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: payment
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### 3. Deploy FQDN Egress Policy (Allow Stripe & Internal DNS Only)

Allow the payment processor pod to talk *only* to internal CoreDNS and external Stripe payment APIs:

```yaml
apiVersion: networking.gke.io/v1
kind: NetworkPolicy
metadata:
  name: allow-stripe-fqdn-egress
  namespace: payment
spec:
  podSelector:
    matchLabels:
      app: payment-worker
  policyTypes:
  - Egress
  egress:
  # 1. Allow UDP 53 to In-Cluster CoreDNS
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
  # 2. Allow Layer 7 Egress to Stripe API via FQDN
  - to:
    - fqdn: "api.stripe.com"
    - fqdn: "*.stripe.com"
    ports:
    - protocol: TCP
      port: 443
```

Apply policy:

```bash
kubectl apply -f allow-stripe-fqdn-egress.yaml
```

### 4. Deploy Dedicated Egress NAT Gateway for Financial Workloads

Third-party banking APIs often require whitelisting a single static IP address. Configure GKE Egress NAT:

```bash
# Reserve a static external IP for the payment namespace
gcloud compute addresses create payment-egress-static-ip \
    --region=us-central1 \
    --project=core-infrastructure-prod
```

Create `egress-nat-policy.yaml`:

```yaml
apiVersion: networking.gke.io/v1
kind: EgressNATPolicy
metadata:
  name: payment-static-egress
spec:
  nodeSelector: {}
  podSelector:
    matchLabels:
      app: payment-worker
  destinations:
  - cidr: "198.51.100.0/24" # Partner Bank API CIDR
  egressGateway:
    staticIP: "34.120.55.90" # Reserved IP from above
```

Apply Egress NAT:

```bash
kubectl apply -f egress-nat-policy.yaml
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Standard Limit / Quota | Engineering Guidance |
| :--- | :--- | :--- |
| **Max Network Policies per Cluster**| 1,000+ policies | $O(1)$ eBPF hash lookup maintains performance |
| **FQDN Rules per Policy** | 50 FQDNs per rule | Use wildcards (`*.service.com`) to consolidate |
| **FQDN Cache TTL** | Respects DNS TTL | Minimum 30 seconds enforced by eBPF map |
| **Datapath V2 Memory Footprint**| ~200 MiB per node | Low memory footprint compared to iptables chains |
| **Egress NAT IP Limit** | Up to 10 static IPs per pool | Distribute across high-volume partner destinations |

---

## 5. Official References & Documentation

- [GKE Datapath V2 Overview](https://cloud.google.com/kubernetes-engine/docs/concepts/about-dataplane-v2)
- [Using FQDN Network Policies on GKE](https://cloud.google.com/kubernetes-engine/docs/how-to/fqdn-network-policies)
- [GKE Egress NAT Policy Architecture](https://cloud.google.com/kubernetes-engine/docs/how-to/egress-nat-policy)
- [Kubernetes Network Policies Specification](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Cilium eBPF Open Source Project](https://cilium.io/)

---

## 6. Realistic Pricing Scenarios

Pricing components:
1. **GKE Datapath V2:** Included with GKE ($0.00 platform fee).
2. **FQDN Network Policies:** Included ($0.00).
3. **Egress NAT Static IP:** Standard Google Cloud external IP fee ($0.005/hour while in use = ~$3.65/month) + standard egress internet bandwidth ($0.08 - $0.12/GB).

### Scenario A: Regulated Fintech Payment Microservice

- **Security Requirements:**
  - Zero-trust namespace isolation (default deny).
  - Outbound calls strictly restricted to 3 payment vendors (Stripe, PayPal, Adyen) via FQDN rules.
  - Dedicated Egress NAT Gateway IP whitelisted by partner banks.
  - Outbound data transfer: 2,000 GB/month.
- **Monthly Cost Calculation:**
  - Datapath V2 & FQDN Engine: **$0.00**
  - Reserved Static IP Address: $0.005/hr × 730 hrs = **$3.65**
  - Internet Egress Bandwidth (2,000 GB): 2,000 GB × $0.08/GB = **$160.00**
- **Total Monthly Cost:** **$163.65 / month**

### Scenario B: Massive E-Commerce Storefront (Migrating from iptables to eBPF)

- **Cluster Profile:**
  - 100 worker nodes, 800 services, 3,000 pods.
  - In legacy iptables mode: Nodes consumed 1.5 vCPUs each just syncing iptables chains ($1.5 \times 100 = 150 \text{ wasted vCPUs}$).
- **Financial Return of Datapath V2:**
  - Switching to Datapath V2 eliminated 150 vCPUs of kernel synchronization overhead.
  - Monthly Savings: 150 vCPUs × $0.0316/vCPU-hr × 730 hrs = **$3,460.20 / month saved** in node compute.

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **DNS Lookup Failure Drops FQDN Egress Packets:** FQDN network policies rely entirely on the pod performing a DNS lookup *before* connecting. If an application pod caches DNS responses in memory indefinitely (e.g., a long-lived Java application with `networkaddress.cache.ttl = -1`), the eBPF kernel DNS cache may expire the IP while the application continues to use it. Subsequent TCP packets from the application will be **immediately dropped by the kernel with connection timeouts**. Always set JVM DNS caching TTL to 60 seconds (`networkaddress.cache.ttl=60`).
2. **Default Deny Breaks In-Cluster DNS Resolution:** When you apply a `default-deny` egress network policy, it blocks **all** outbound traffic, including traffic to the Kubernetes DNS service (`kube-dns`). Pods immediately fail to resolve internal service hostnames (`order-service.default.svc.cluster.local`). You **must explicitly whitelist egress on UDP/TCP port 53** targeting the `kube-system` namespace in your network policies.
3. **Datapath V2 Cannot Be Disabled After Cluster Creation:** The choice between Datapath V1 (iptables) and Datapath V2 (Cilium eBPF) is an immutable cluster configuration. You **cannot enable or disable Datapath V2 on an existing GKE cluster**. To adopt Datapath V2, you must create a new cluster and migrate workloads.
4. **Hardcoded IP Addresses Bypass FQDN Policies:** If a developer attempts to call a third-party API using a hardcoded raw IP address (e.g., `curl https://198.51.100.5`) instead of a domain name, the packet does not trigger a DNS lookup and is immediately blocked by FQDN network policies. Enforce code quality rules preventing hardcoded IP endpoints.
5. **Egress NAT Policy Routing Contention with Cloud NAT:** If a subnet already has Google Cloud NAT enabled, GKE Egress NAT Policies take precedence for the specific pods matching the `podSelector`. However, if the destination CIDR in the `EgressNATPolicy` does not cover all traffic, non-matching traffic falls back to Cloud NAT. Ensure your firewall rules and destination CIDR masks are clearly documented to prevent confusion over which public IP was used.
6. **NetworkPolicy Logging Verification:** To debug dropped packets in Datapath V2, do not install third-party network dump tools. Enable native Datapath V2 logging:
```bash
gcloud container clusters update prod-secure-cluster \
    --enable-dataplane-v2-metrics \
    --project=core-infrastructure-prod
```
Dropped packets are immediately queryable in Google Cloud Logging with filter: `logName:"projects/.../logs/dataplane-v2"` and `jsonPayload.disposition="DROPPED"`.

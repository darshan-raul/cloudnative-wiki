---
title: Azure Load Balancing, Application Gateway & Front Door
description: Azure Load Balancing architecture — Azure Load Balancer (L4), Application Gateway (L7 with WAF v2), Azure Front Door (Global Anycast), and Private Link.
tags:
  - azure
  - networking
  - load-balancer
  - application-gateway
  - front-door
  - waf
---

# Azure Load Balancing, Application Gateway & Front Door ⚖️🛡️

Azure provides a tiered suite of load-balancing services designed for different network layers and geographic scopes. Choosing the correct service depends on whether traffic is Layer 4 (TCP/UDP) or Layer 7 (HTTP/HTTPS), and whether the workload is regional or globally distributed.

---

## Architecture & Mental Model

### The Azure Load Balancing Decision Tree

```
                          Incoming Traffic
                                 │
                 Is it HTTP/HTTPS (Layer 7)?
                 ├── NO (TCP / UDP / Wire-speed Layer 4)
                 │    │
                 │    └── Is it Internal or Public?
                 │         └── Azure Load Balancer (Standard SKU)
                 │             (Kernel hash routing, sub-millisecond)
                 │
                 └── YES (Layer 7: SSL Offload, URL Routing, WAF)
                      │
                      └── Is the architecture Global or Regional?
                           ├── GLOBAL (Multi-region Anycast + CDN)
                           │    └── Azure Front Door (Standard / Premium)
                           │        (Edge Anycast IP, WAF, TLS at edge)
                           │
                           └── REGIONAL (Within single VNet / Region)
                                └── Azure Application Gateway (WAF v2)
                                    (Dedicated proxy subnet, cookie affinity)
```

---

## Service Comparison Matrix

| Dimension | Azure Load Balancer | Azure Application Gateway | Azure Front Door |
| :--- | :--- | :--- | :--- |
| **OSI Layer** | Layer 4 (TCP / UDP) | Layer 7 (HTTP / HTTPS / WebSockets) | Layer 7 (HTTP / HTTPS / WebSockets) |
| **Scope** | Regional | Regional | **Global** (Anycast Edge PoPs) |
| **Routing Logic** | 5-tuple hash (IPs, ports, protocol) | URL path, host header, cookie affinity | Latency-based Anycast, priority/weighted |
| **SSL / TLS** | Passthrough only (no decryption) | **SSL Termination & End-to-End TLS** | **Edge SSL Termination** |
| **WAF Protection** | None (use NSGs) | **WAF v2** (OWASP 3.2, bot protection) | **Global WAF** + DDoS protection |
| **VNet Placement** | Resides in any standard subnet | **Requires dedicated subnet** | Edge service (outside VNet; uses Private Link) |

---

## Core Concepts

### 1. Azure Load Balancer (Standard SKU)

Azure Load Balancer operates at Layer 4:
* **High Performance:** Routes packets at wire speed with zero software proxy overhead.
* **Zone-Redundant:** Standard SKU automatically distributes traffic across all three availability zones.
* **Floating IP (Direct Server Return):** Reuses the frontend IP on backend VMs, essential for SQL Server Always On Availability Group listeners.

### 2. Azure Application Gateway (WAF v2)

Application Gateway is a dedicated reverse-proxy deployment based on Azure-managed VMs:
* **Dedicated Subnet Requirement:** Must be provisioned inside a subnet dedicated exclusively to Application Gateway (recommended minimum `/24`).
* **WAF v2 Engine:** Evaluates OWASP Core Rule Set (CRS 3.2) rules against SQLi, XSS, and command injection before traffic hits backend pools.
* **Autoscaling:** Scales from 2 to 125 instances automatically based on capacity units (compute, persistent connections, throughput).

### 3. Azure Front Door

Microsoft's enterprise cloud CDN and global web load balancer:
* **Anycast Architecture:** User connections terminate at the nearest Microsoft Point of Presence (PoP) across 190+ locations globally.
* **Split TCP:** Accelerates connection handshakes by terminating TCP sessions at the edge and utilizing Microsoft's private global fiber backbone to reach origin servers.
* **Private Link Origin:** Can connect directly to private AKS clusters and internal load balancers without exposing them to the public internet.

---

## Production `az` CLI Commands

### 1. Deploying a Production Standard Load Balancer with Health Probe

```bash
# 1. Create a Zone-Redundant Public IP
az network public-ip create \
  --resource-group prod-net-rg \
  --name pip-alb-frontend \
  --sku Standard \
  --tier Regional \
  --zone 1 2 3

# 2. Create the Standard Load Balancer
az network lb create \
  --resource-group prod-net-rg \
  --name alb-internal-services \
  --sku Standard \
  --frontend-ip-name fe-public-ip \
  --public-ip-address pip-alb-frontend \
  --backend-pool-name be-vm-pool

# 3. Create an HTTP Health Probe
az network lb probe create \
  --resource-group prod-net-rg \
  --lb-name alb-internal-services \
  --name probe-http-8080 \
  --protocol Http \
  --port 8080 \
  --path "/healthz" \
  --interval 5 \
  --threshold 2

# 4. Create the Load Balancing Rule
az network lb rule create \
  --resource-group prod-net-rg \
  --lb-name alb-internal-services \
  --name rule-http-traffic \
  --protocol Tcp \
  --frontend-port 80 \
  --backend-port 8080 \
  --frontend-ip-name fe-public-ip \
  --backend-pool-name be-vm-pool \
  --probe-name probe-http-8080
```

### 2. Deploying Application Gateway with WAF v2

```bash
# Create Application Gateway in its dedicated subnet
az network application-gateway create \
  --resource-group prod-net-rg \
  --name appgw-prod-waf \
  --location eastus \
  --sku WAF_v2 \
  --capacity 2 \
  --vnet-name prod-vnet-eastus \
  --subnet snet-appgw \
  --public-ip-address pip-appgw \
  --frontend-port 443 \
  --priority 100 \
  --http-settings-port 8080 \
  --http-settings-protocol Http
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Application Gateway instances** | Up to 125 instances | Autoscales dynamically via capacity units |
| **Dedicated AppGateway Subnet** | Minimum `/26` (recomm. `/24`)| Cannot host any other VM or resource |
| **Load Balancer backend VMs** | Up to 1,000 backend VMs | Across a single virtual network |
| **Front Door routing rules** | 500 rules per profile | Path-based and host-based routing |

---

## References

* **Azure Load Balancer Documentation:** https://learn.microsoft.com/en-us/azure/load-balancer/load-balancer-overview
* **Application Gateway Documentation:** https://learn.microsoft.com/en-us/azure/application-gateway/overview
* **Azure Front Door Overview:** https://learn.microsoft.com/en-us/azure/frontdoor/front-door-overview
* **Pricing:** https://azure.microsoft.com/en-us/pricing/details/load-balancer/

---

## Pricing Examples

### Scenario 1: Standard Azure Load Balancer (Internal Tier)
* 1 Standard Internal Load Balancer with 3 load balancing rules and 20 backend VMs.
* Base hourly rate: First 5 rules = $0.025 / hour × 730 hours = **$18.25 / month**.
* Data processed: 10 TB / month ($0.005 / GB = $50.00).
* **Total Monthly Cost:** $18.25 + $50.00 = **~$68.25 / month**.

### Scenario 2: Application Gateway WAF v2 (High-Traffic Web API)
* 1 Application Gateway WAF v2 running in East US.
* Fixed hourly charge: ~$0.443 / hour × 730 hours = $323.39 / month.
* Capacity Units (CU) consumed: Average 5 CUs continuously (for TLS offload, WAF inspection, and 20 Mbps throughput):
  * 5 CUs × $0.0144 / CU-hour × 730 hours = ~$52.56.
* **Total Monthly AppGateway Cost:** $323.39 + $52.56 = **~$375.95 / month**.

---

## Nuggets & Gotchas

1. **The Application Gateway Subnet Lockout:** Azure Application Gateway **requires a completely dedicated subnet**. You cannot place virtual machines, Bastion hosts, or other load balancers into this subnet. If the subnet is sized too small (e.g. `/28`), the Application Gateway will fail to autoscale during traffic spikes because it runs out of internal IP addresses for scale-out proxy instances.
2. **Basic SKU vs. Standard SKU Incompatibility:** Basic SKU Load Balancers and Standard SKU Load Balancers cannot be mixed within the same backend pool or availability set. Furthermore, Basic SKU is officially retired in modern Azure regions; always use **Standard SKU**.
3. **Health Probe IP `168.63.129.16` Must Never Be Blocked:** Azure uses the magic virtual IP `168.63.129.16` to communicate health probes, DHCP renewals, and DNS queries to your VMs. If an aggressive NSG rule drops inbound traffic from this IP, Azure Load Balancer will mark every VM in your backend pool dead.
4. **App Gateway 502 Bad Gateway on Host Mismatches:** When Application Gateway routes HTTPS traffic to backend VMs or App Services, it expects the backend TLS certificate to match the hostname requested by the client. If your backend listens on a custom internal domain or IP without `--pick-host-name-from-backend-address`, Application Gateway will reject the backend TLS handshake and return an instant `HTTP 502 Bad Gateway`.
5. **Direct Server Return (Floating IP) Requires Guest OS Loopback Config:** Enabling Floating IP on Azure Load Balancer preserves the frontend IP in the packet destination header. If you do not configure a dummy loopback adapter with that IP inside the Windows or Linux guest OS, the OS network stack will drop the packet because the destination IP does not match its primary NIC IP.

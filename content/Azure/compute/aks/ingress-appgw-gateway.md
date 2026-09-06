---
title: AKS Ingress, Application Gateway for Containers, and Gateway API Architecture
description: Exhaustive engineering guide to Layer 7 ingress traffic on AKS — AGIC vs Application Routing Add-on vs Application Gateway for Containers (AGfC), Gateway API controller, HTTPRoute canary splitting, WAF v2, and Key Vault TLS termination.
tags:
  - azure
  - aks
  - ingress
  - gateway-api
  - application-gateway
  - nginx
  - waf
---

# AKS Ingress, Application Gateway for Containers, and Gateway API Architecture 🚦🌐

Managing external and internal Layer 7 HTTP/HTTPS traffic entering an Azure Kubernetes Service (AKS) cluster requires balancing performance, security, and cloud-native standards. While legacy architectures relied on the **Application Gateway Ingress Controller (AGIC)** or self-hosted NGINX pods, Microsoft has evolved its ingress portfolio into two distinct modern paradigms: the **Application Routing Add-on (Managed NGINX)** for lightweight developer ingress, and **Azure Application Gateway for Containers (AGfC)**—Microsoft's flagship implementation of the open Kubernetes **Gateway API** standard.

---

## 1. Architecture: Application Gateway for Containers (AGfC) & Gateway API

Unlike legacy Application Gateway v2 (which required minutes to reconfigure backends whenever pods scaled), **Application Gateway for Containers (AGfC)** is a cloud-native proxy that receives near-instantaneous (< 1 second) updates directly from the Kubernetes control plane.

```
                           INTERNET / CORPORATE WAN CLIENTS
                                          │
                                          ▼ Public / Private Frontend IP
       ┌────────────────────────────────────────────────────────────────────────┐
       │             APPLICATION GATEWAY FOR CONTAINERS (ALB PROXY)             │
       │             - Envoy-based disaggregated data plane                     │
       │             - Near-instantaneous backend updates (< 1s)                │
       │             - Layer 7 WAF v2 Inspection + TLS Termination              │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ Sub-millisecond Private VNet Transit
                                          ▼ Delegated Subnet
       ┌────────────────────────────────────────────────────────────────────────┐
       │                    AKS CLUSTER (Azure CNI Overlay)                     │
       │                                                                        │
       │  ┌──────────────────────────────────────────────────────────┐          │
       │  │ AGfC ALB CONTROLLER (Managed Pod in kube-system)         │          │
       │  │ - Watches `Gateway` and `HTTPRoute` CRD resources        │          │
       │  │ - Streams endpoint updates to Envoy control plane via xDS│          │
       │  └───────────────────────────┬──────────────────────────────┘          │
       │                              │ Dynamic Routing                         │
       │              ┌───────────────┴───────────────┐                         │
       │              ▼ (90% Traffic)                 ▼ (10% Canary)            │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ Service: `order-v1`    │         │ Service: `order-v2`    │         │
       │  │ - Pod 1: 192.168.1.10  │         │ - Pod 3: 192.168.2.14  │         │
       │  │ - Pod 2: 192.168.1.11  │         │ - Pod 4: 192.168.2.15  │         │
       │  └────────────────────────┘         └────────────────────────┘         │
       └────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Decision Matrix: Ingress Options on AKS

| Dimension | Application Gateway Ingress Controller (AGIC) | Application Routing Add-on | Application Gateway for Containers (AGfC) |
| :--- | :--- | :--- | :--- |
| **API Specification** | Kubernetes `networking.k8s.io/v1` Ingress | Kubernetes `networking.k8s.io/v1` Ingress | **Kubernetes Gateway API (`gateway.networking.k8s.io/v1`)** |
| **Data Plane Engine** | Azure Application Gateway v2 VM instances | In-cluster managed NGINX pods | **Managed Envoy-based Disaggregated Proxy** |
| **Reconfiguration Latency**| **15 to 90 seconds** (ARM API call bottleneck) | Near instant (< 1 second) | **Sub-second (< 1 second via xDS streaming)** |
| **WAF Protection** | Azure WAF v2 on App Gateway | Requires custom ModSecurity | **Native Azure WAF v2 integration** |
| **Canary Traffic Splitting**| Requires complex annotations | Annotations-based | **Declarative weight in `HTTPRoute`** |
| **Cost Model** | Hourly App Gateway fee + Capacity Units | In-cluster VM resource consumption | **Fixed base fee + Capacity Units (NCUs)** |

---

## 3. Production Deployment & CLI Operations (`az` CLI & `kubectl`)

### 1. Enable Application Gateway for Containers (AGfC) on AKS

```bash
# Register required resource providers
az provider register --namespace Microsoft.ServiceNetworking

# Create dedicated delegated subnet for Application Gateway for Containers
az network vnet subnet create \
    --resource-group rg-prod-network \
    --vnet-name vnet-eastus-prod \
    --name snet-agfc-alb \
    --address-prefixes 10.100.20.0/24 \
    --delegations "Microsoft.ServiceNetworking/trafficControllers"

# Enable the AGfC extension on the target AKS cluster
az aks appgateway-for-containers enable \
    --resource-group rg-prod-aks \
    --cluster-name aks-core-prod \
    --delegated-subnet-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod-network/providers/Microsoft.Network/virtualNetworks/vnet-eastus-prod/subnets/snet-agfc-alb"
```

### 2. Deploy Gateway and Managed TLS via Gateway API

Create `gateway-definition.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: external-public-gateway
  namespace: production
spec:
  gatewayClassName: azure-alb-external
  listeners:
  - name: https-listener
    port: 443
    protocol: HTTPS
    allowedRoutes:
      namespaces:
        from: All
    tls:
      mode: Terminate
      certificateRefs:
      - group: ""
        kind: Secret
        name: wildcard-corp-tls-secret
```

### 3. Deploy Advanced Canary Routing with HTTPRoute

Deploy an `HTTPRoute` that performs a **90/10 weighted canary split** and routes `/api/v2/orders` to the new microservice version:

Create `canary-httproute.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: orders-traffic-route
  namespace: production
spec:
  parentRefs:
  - name: external-public-gateway
  hostnames:
  - "orders.contoso.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api/orders
    backendRefs:
    # Stable Production Version (90% weight)
    - name: orders-service-v1
      port: 80
      weight: 90
    # Canary Candidate Version (10% weight)
    - name: orders-service-v2
      port: 80
      weight: 10
```

Apply manifests:

```bash
kubectl apply -f gateway-definition.yaml
kubectl apply -f canary-httproute.yaml
```

---

## 4. Quotas, Performance & Configuration Limits

| Limit / Metric | Hard Limit / SLA | Production Impact |
| :--- | :--- | :--- |
| **Reconfiguration Speed** | **< 1 second** | Solves the legacy AGIC pod scaling delay completely |
| **Max Gateways per ALB** | **Up to 100 Gateways** | Multi-tenant platform consolidation |
| **Max Rules per HTTPRoute**| **1,000 rules** | High-density path, header, and query parameter routing |
| **Max Concurrent TCP Conns**| **1,000,000+ connections**| Scales dynamically via Envoy data plane |
| **TLS Certificate Source** | Kubernetes Secrets / Key Vault| Automated rotation via Azure Key Vault CSI Provider |

---

## 5. Official References

- [Application Gateway for Containers (AGfC) Overview](https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/overview)
- [Gateway API Implementation on Azure](https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/gateway-api-support)
- [Application Routing Add-on for AKS](https://learn.microsoft.com/en-us/azure/aks/app-routing)
- [Application Gateway for Containers Pricing](https://azure.microsoft.com/en-us/pricing/details/application-gateway-for-containers/)

---

## 6. Realistic Pricing Scenarios

Application Gateway for Containers uses a consumption-based pricing model based on **Gateway Base Hours** and **Normalized Capacity Units (NCUs)** (which account for connections, active throughput, and rule evaluations).

### Scenario A: Enterprise E-Commerce Gateway (High Traffic, WAF Enabled)

- **Traffic Profile:**
  - 1 Active AGfC Gateway deployed across 3 Availability Zones.
  - Average throughput: 150 Mbps (~20 NCUs during peak).
  - WAF v2 inspection enabled.
- **Monthly Cost Breakdown:**
  - Gateway Base Fee: ~$0.025/hr × 730 hrs = **$18.25**
  - NCU Consumption: 20 NCUs × $0.008/NCU-hr × 730 hrs = **$116.80**
  - WAF Security Surcharge: ~$0.015/hr × 730 hrs = **$10.95**
  - Ingress Data Egress Bandwidth (10 TB): ~$150.00
- **Total Ingress Cost:** **$296.00 / month** *(Compared to $450+/mo on legacy Application Gateway v2).*

### Scenario B: Lightweight B2B Portal (Application Routing Add-on)

- **Traffic Profile:**
  - Uses the managed **Application Routing Add-on (NGINX)** running directly on existing AKS nodes.
  - Low to medium internal traffic.
- **Monthly Cost Breakdown:**
  - Azure Application Routing Add-on Fee: **$0.00 (Completely Free)**.
  - Compute Overhead: ~0.5 vCPU and 1 GiB RAM across worker nodes (absorbed by existing node pool).
  - Azure Standard Public Load Balancer: ~$18.00 / month.
- **Total Ingress Cost:** **$18.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Legacy AGIC Scale Freeze:** On legacy Application Gateway v2 with AGIC, every time a Kubernetes Deployment scales out from 10 to 50 pods, AGIC calls the Azure Resource Manager (ARM) API to update the backend pool. ARM takes **30 to 60 seconds** to reconfigure the gateway, during which traffic cannot reach the newly spun-up pods. If pod scaling is rapid, ARM throttles the AGIC controller with `429 Too Many Requests`. **Always migrate to Application Gateway for Containers (AGfC) to eliminate ARM API bottlenecks.**
2. **Dedicated Delegated Subnet Requirement:** The subnet allocated to Application Gateway for Containers must be **100% dedicated and delegated exclusively to `Microsoft.ServiceNetworking/trafficControllers`**. You cannot place AKS worker VMs, Private Endpoints, or any other virtual machines in this subnet. Attempting to deploy AGfC into an existing shared subnet will cause deployment failure with `SubnetAlreadyInUse`.
3. **HTTPRoute Hostname Wildcard Matching Precedence:** When defining multiple `HTTPRoute` resources, exact hostnames (`app.contoso.com`) always take precedence over wildcard hostnames (`*.contoso.com`). If a developer accidentally creates an exact match route targeting a dead service, all traffic is blackholed, bypassing the wildcard fallback route.
4. **Automated TLS Certificate Sync Lag:** When syncing TLS certificates from Azure Key Vault into the Gateway via Secret sync, rotation is not instantaneous. If a certificate is rotated in Key Vault, the secret provider polls every few minutes. Ensure certificates are rotated at least 7 days before expiration to prevent transient SSL handshake rejections.
5. **BackendTLSPolicy for Strict End-to-End Encryption:** If your pods handle sensitive banking data, terminating TLS at the Gateway and sending unencrypted plaintext over the internal VNet violates PCI-DSS. With Gateway API, use **`BackendTLSPolicy`** to re-encrypt traffic from the AGfC proxy to the backend pod, validating the pod's internal TLS certificate authority.

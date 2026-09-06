---
title: GKE Gateway API Architecture, HTTPRoute, and Cloud Armor Integration
description: Exhaustive engineering guide to the Kubernetes Gateway API on GKE — GatewayClasses (gke-l7-global-external-managed, gke-l7-rilb), HTTPRoute routing rules, GCP frontend policies, HealthCheckPolicy, and Cloud Armor WAF integration.
tags:
  - gcp
  - gke
  - gateway-api
  - networking
  - ingress
---

# GKE Gateway API Architecture, HTTPRoute, and Cloud Armor Integration 🚪🌐

The **Kubernetes Gateway API** is the open-standard, next-generation evolution of Kubernetes networking, replacing the legacy `Ingress` specification. On Google Kubernetes Engine, the Gateway API is implemented via the **GKE Gateway Controller**, a native control plane that provisions and configures Google Cloud's planetary-scale external and internal Application Load Balancers. By cleanly separating the roles of **Infrastructure Provider**, **Cluster Operator**, and **Application Developer**, the Gateway API enables expressive Layer 7 traffic routing, canary traffic splitting, cross-namespace routing, and direct integration with **Cloud Armor WAF**.

---

## 1. Architecture & Role-Oriented Persona Model

Unlike traditional `Ingress` where routing, TLS, timeouts, and health checks were jammed into fragile, vendor-specific annotations on a single YAML object, the Gateway API establishes a structured, role-separated resource hierarchy:

```
                            ROLE-ORIENTED PERSONA MODEL
    ┌───────────────────────────┬───────────────────────────┬───────────────────────────┐
    │ INFRASTRUCTURE PROVIDER   │ CLUSTER OPERATOR          │ APPLICATION DEVELOPER     │
    │ (Google Cloud Platform)   │ (Platform / SRE Team)     │ (Microservice Teams)      │
    │                           │                           │                           │
    │  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────┐  │
    │  │    GATEWAYCLASS     │  │  │       GATEWAY       │  │  │      HTTPROUTE      │  │
    │  │ - gke-l7-global-ext │  │  │ - IP reservation    │  │  │ - Path & header     │  │
    │  │ - gke-l7-rilb       │  │  │ - TLS certificates  │  │  │   routing rules     │  │
    │  │ - gke-l7-gxlb       │  │  │ - Listeners (80/443)│  │  │ - Traffic splitting │  │
    │  └─────────────────────┘  │  └──────────┬──────────┘  │  └──────────┬──────────┘  │
    └───────────────────────────┴─────────────┼─────────────┴─────────────┼─────────────┘
                                              │ Bound via Listeners       │ Attached via
                                              ▼                           ▼ ParentRefs
    ┌───────────────────────────────────────────────────────────────────────────────────┐
    │                      GOOGLE CLOUD EXTERNAL APPLICATION LOAD BALANCER              │
    │  - Anycast Global IPv4 VIP (Edge PoP Termination)                                │
    │  - Cloud Armor Security Policies (DDoS & WAF Rules)                               │
    │  - Direct routing to Pods via Zonal Network Endpoint Groups (Zonal NEGs)          │
    └───────────────────────────────────────────────────────────────────────────────────┘
```

### Core Architecture Constructs

1. **GatewayClass:** A cluster-scoped template provided by GCP defining the underlying load balancer type.
   - `gke-l7-global-external-managed`: Global external Application Load Balancer with Anycast VIP, Cloud Armor, and Cloud CDN support.
   - `gke-l7-rilb`: Regional internal Application Load Balancer for private VPC-only east-west traffic.
   - `gke-l7-gxlb`: Classic external HTTP(S) Load Balancer.
2. **Gateway:** Managed by platform SREs. Binds to a GatewayClass, reserves the external IP address, and configures TLS certificates and listener ports (e.g., HTTPS 443).
3. **HTTPRoute:** Managed by microservice developers. Defines URL routing rules (`/api/v1/orders`), header rewrites, redirects, and canary weight distributions.
4. **Zonal Network Endpoint Groups (NEGs):** The GKE Gateway controller automatically bypasses `kube-proxy` and routes traffic directly from the Google Cloud Envoy proxy to the individual Pod IP and container port.

---

## 2. GKE Gateway Policy Attachments

To configure Google-specific load balancing parameters without non-standard annotations, GKE introduces **Direct Policy Attachments**:
- **GCPBackendPolicy:** Configures Cloud Armor WAF security policies, Cloud CDN caching, connection draining timeouts, and session affinity on backend services.
- **HealthCheckPolicy:** Customizes HTTP health check request paths, probing intervals, and healthy/unhealthy thresholds directly at the Google load balancer.
- **GCPFrontendPolicy:** Binds SSL policies (TLS 1.3 enforcement) and HTTPS redirects at the frontend listener level.

---

## 3. Production Deployment & CLI Operations (`gcloud` & `kubectl`)

### 1. Enable Gateway API Controller on GKE Cluster

```bash
# Enable Gateway API controller
gcloud container clusters update prod-regional-cluster \
    --region=us-central1 \
    --gateway-api=standard \
    --project=core-infrastructure-prod

# Verify that GatewayClasses are available
kubectl get gatewayclass
```

### 2. Reserve Global Anycast IP and Deploy the Gateway

```bash
# Reserve global static external IP
gcloud compute addresses create gke-gateway-global-ip \
    --global \
    --project=core-infrastructure-prod
```

Create `production-gateway.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: prod-external-gateway
  namespace: networking-infra
spec:
  gatewayClassName: gke-l7-global-external-managed
  addresses:
  - type: NamedAddress
    value: gke-gateway-global-ip
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
      - name: enterprise-wildcard-cert
        group: ""
        kind: Secret
    allowedRoutes:
      namespaces:
        from: All # Allows HTTPRoutes from any microservice namespace to attach
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
```

Apply Gateway:

```bash
kubectl apply -f production-gateway.yaml
```

### 3. Deploy Multi-Service HTTPRoute with Canary Traffic Splitting

Create `storefront-route.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: storefront-route
  namespace: storefront
spec:
  parentRefs:
  - name: prod-external-gateway
    namespace: networking-infra
    sectionName: https
  hostnames:
  - "shop.cloudnative-wiki.internal"
  rules:
  # Rule 1: Route API calls to Order Service with Canary Splitting (90% Stable / 10% Canary)
  - matches:
    - path:
        type: PathPrefix
        value: /api/orders
    backendRefs:
    - name: order-service-stable
      port: 8080
      weight: 90
    - name: order-service-canary
      port: 8080
      weight: 10
  # Rule 2: Route Static Assets to Catalog UI
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: catalog-frontend
      port: 80
```

Apply HTTPRoute:

```bash
kubectl apply -f storefront-route.yaml
```

### 4. Attach Cloud Armor WAF Policy via GCPBackendPolicy

Protect the `order-service-stable` Kubernetes Service with Cloud Armor WAF rules:

```yaml
apiVersion: networking.gke.io/v1
kind: GCPBackendPolicy
metadata:
  name: order-service-security-policy
  namespace: storefront
spec:
  default:
    securityPolicy: enterprise-cloud-armor-waf
    timeoutSec: 30
    connectionDraining:
      drainingTimeoutSec: 60
  targetRef:
    group: ""
    kind: Service
    name: order-service-stable
```

Apply Policy:

```bash
kubectl apply -f order-service-security-policy.yaml
```

---

## 4. Quotas, Performance, and Configuration Limits

| Dimension / Resource | Limit / Quota | Engineering Guidance |
| :--- | :--- | :--- |
| **Max HTTPRoutes per Gateway** | 100 routes | Consolidate microservice routes per host |
| **Backend NEGs per Service** | 1 Zonal NEG per zone | Direct container-native Pod IP routing |
| **DNS / SSL Certificates** | Up to 15 certs per listener | Use Google Managed Certificates or cert-manager |
| **Canary Weight Resolution**| 1 to 10,000 integer range | Enables precise fraction-of-a-percent canaries |
| **Provisioning Latency** | 2 to 5 minutes | Time for GCP Load Balancer VIP propagation |
| **Cloud Armor Support** | Global External Managed | Requires `gke-l7-global-external-managed` |

---

## 5. Official References & Documentation

- [GKE Gateway API Overview](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api)
- [GKE Gateway API Deployment Guide](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)
- [Kubernetes Gateway API Official Specification](https://gateway-api.sigs.k8s.io/)
- [GCPBackendPolicy and HealthCheckPolicy Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/gateway-api-policies)
- [Migrating from Ingress to Gateway API](https://cloud.google.com/kubernetes-engine/docs/how-to/migrate-ingress-gateway-api)

---

## 6. Realistic Pricing Scenarios

Pricing components:
1. **GKE Gateway Controller:** $0 platform surcharge (included in GKE management fee).
2. **Google Cloud Application Load Balancer:**
   - Base forwarding rule: ~$0.025 per hour (~$18.25/month).
   - Data processed: $0.008 per GB.
3. **Cloud Armor:** $0.75 per policy per month + $0.75 per million HTTP requests.

### Scenario A: Enterprise Public Storefront with Cloud Armor WAF

- **Traffic Profile:**
  - 1 Global External Gateway handling 50 million HTTPS requests per month.
  - Ingress/Egress data processed: 4,000 GB (4 TB).
  - 1 Cloud Armor WAF Security Policy attached.
- **Monthly Cost Calculation:**
  - Load Balancer Forwarding Rule: $0.025/hr × 730 hrs = **$18.25**
  - LB Data Processing: 4,000 GB × $0.008/GB = **$32.00**
  - Cloud Armor Base: **$0.75**
  - Cloud Armor Requests (50M): 50 × $0.75 = **$37.50**
- **Total Monthly Cost:** **$88.50 / month**

### Scenario B: High-Throughput Media Streaming API (300 TB/Month)

- **Traffic Profile:**
  - Gateway API routing large API responses (300,000 GB = 300 TB data transfer).
  - 10 million requests/month.
- **Monthly Cost Calculation:**
  - Load Balancer Base: $18.25
  - LB Data Processing: 300,000 GB × $0.008/GB = **$2,400.00**
  - Cloud Armor: $0.75 + (10 × $0.75) = **$8.25**
- **Total Monthly Cost:** **$2,426.50 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Ingress to Gateway API NEG Prerequisite:** The GKE Gateway API **requires** VPC-native clusters and container-native load balancing via Zonal Network Endpoint Groups (NEGs). If your GKE cluster is routes-based (legacy non-VPC-native) or your Kubernetes Service lacks the `cloud.google.com/neg: '{"ingress": true}'` annotation, the Gateway controller cannot register Pod endpoints to the GCP load balancer, leaving the load balancer backend service in `HEALTH_CHECKING` state indefinitely.
2. **Cross-Namespace Route Attachment Permissions:** In standard Ingress, an Ingress object could only route to Services within its own namespace. In Gateway API, HTTPRoutes in `namespace: order` can bind to a Gateway in `namespace: infra`. However, the Gateway **must explicitly authorize cross-namespace attachments** via `spec.listeners[].allowedRoutes.namespaces.from: All` (or `Selector`). If omitted, the Gateway defaults to `Same` namespace, silently rejecting all microservice HTTPRoutes.
3. **Backend Service Health Check Paths Differ from Container Probes:** GKE Gateway API does **not** automatically copy the `livenessProbe` or `readinessProbe` path from your pod specification into the Google Cloud Load Balancer health check. By default, Google Cloud checks `GET /` on the container port. If your application returns HTTP 404 or 401 on `/`, the GCP load balancer marks all Pod NEGs as unhealthy and returns `HTTP 502 Server Error`. Always deploy a `HealthCheckPolicy` specifying the exact health endpoint (e.g., `/healthz`).
4. **Cloud Armor Policy Changes Take 60 Seconds to Propagate:** When you attach or update a `GCPBackendPolicy` binding a Cloud Armor security rule, the Google Cloud control plane compiles the Envoy rules across all global edge points of presence. This propagation takes between **30 to 90 seconds**. Do not assume a newly applied WAF block rule is actively filtering traffic the instant `kubectl apply` completes.
5. **Gateway Deletion Orphaned Global Static IP:** If you delete a Gateway object, GKE tears down the forwarding rules, URL maps, and target proxies. However, if you specified a pre-created named external IP (`NamedAddress`), the IP address is **not deleted from your GCP project**. Unattached reserved external IP addresses accrue idle charges ($0.01/hr) until assigned or deleted.
6. **HTTP to HTTPS Redirects Require Dual Listeners:** To enforce HTTPS redirection, you must configure *both* an HTTP (Port 80) and an HTTPS (Port 443) listener on the Gateway, and attach an HTTPRoute to the port 80 listener with a `RequestRedirect` filter:
```yaml
rules:
- filters:
  - type: RequestRedirect
    requestRedirect:
      scheme: https
      statusCode: 301
```
Omitting the port 80 listener causes client HTTP requests to time out rather than redirecting.

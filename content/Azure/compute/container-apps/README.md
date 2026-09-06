---
title: Azure Container Apps (ACA), KEDA, and Dapr Microservices
description: Exhaustive engineering guide to Azure Container Apps — serverless container architecture, Envoy proxy ingress, KEDA event-driven autoscaling, Dapr sidecar integration, revision management, and virtual network integration.
tags:
  - azure
  - compute
  - container-apps
  - keda
  - dapr
  - serverless
---

# Azure Container Apps (ACA), KEDA, and Dapr Microservices 🚀📦

**Azure Container Apps (ACA)** is a fully managed, serverless container runtime built on top of Azure Kubernetes Service (AKS), Envoy proxy, and KEDA (Kubernetes Event-driven Autoscaling). It enables developers to deploy microservices, background event workers, and API endpoints packaged as OCI containers without managing Kubernetes control planes, Helm charts, ingress controllers, or node pools. ACA natively integrates with the **Distributed Application Runtime (Dapr)** for state management, pub/sub messaging, and service-to-service invocation.

---

## 1. Architecture & Core Subsystems

Under the hood, Azure Container Apps abstracts an entire Kubernetes and service mesh topology inside an isolated boundary called a **Container Apps Environment**.

```
                        CLIENT TRAFFIC / PUBLIC INTERNET
                                       │
                                       ▼
       ┌────────────────────────────────────────────────────────────────┐
       │                   AZURE MANAGED ENVOY PROXY                    │
       │  - TLS termination & automatic Let's Encrypt certificates      │
       │  - Path-based routing, split-traffic canary deployments        │
       │  - Internal vs External ingress boundaries                     │
       └───────────────────────────────┬────────────────────────────────┘
                                       │
       ════════════════════════════════╪═════════════════════════════════
       CONTAINER APPS ENVIRONMENT (Dedicated Subnet / Delegated VNet)   │
                                       ▼
       ┌────────────────────────────────────────────────────────────────┐
       │                   CONTAINER APP REVISION (POD)                 │
       │                                                                │
       │  ┌────────────────────────┐        ┌────────────────────────┐  │
       │  │ User Application       │        │ Dapr Sidecar (daprd)   │  │
       │  │ Container              │◄──────►│ (gRPC / HTTP 3500)     │  │
       │  │ (Node, Go, Python, .NET│        │ - State, PubSub, Lock  │  │
       │  └────────────────────────┘        └───────────┬────────────┘  │
       └────────────────────────────────────────────────┼───────────────┘
                                                        │
                    ┌───────────────────────────────────┴───────────────┐
                    │                                                   │
                    ▼                                                   ▼
       ┌────────────────────────┐                         ┌────────────────────────┐
       │     KEDA AUTOSCALER    │                         │   DAPR COMPONENT SINK  │
       │  - HTTP Request Rate   │                         │  - Azure Service Bus   │
       │  - Service Bus Queue   │                         │  - Azure Cosmos DB     │
       │  - Scale 0 ◄► N Pods   │                         │  - Redis Cache         │
       └────────────────────────┘                         └────────────────────────┘
```

### Core Architecture Constructs

1. **Container Apps Environment:** The shared networking and logging boundary. Multiple container apps within the same environment deploy into the same virtual network, share an Azure Log Analytics workspace, and can communicate securely over private mTLS without leaving the virtual network.
2. **Revisions:** Immutable snapshots of a container app's configuration (container image tag, environment variables, resource allocations). Revisions enable zero-downtime blue-green deployments, canary testing, and instant rollback.
3. **KEDA Autoscaling Engine:** ACA embeds KEDA directly into the control plane. Workloads can autoscale based on HTTP concurrent requests, CPU/memory thresholds, or 30+ external event scalers (e.g., Azure Service Bus queue length, Kafka lag, RabbitMQ queue depth). Crucially, ACA can **scale down to zero** instances when idle to eliminate compute costs.
4. **Dapr (Distributed Application Runtime):** Can be enabled with a single CLI flag or YAML declaration. ACA automatically injects a `daprd` sidecar container alongside the application container. The app talks to `localhost:3500` via HTTP/gRPC, and Dapr abstracts backend infrastructure (e.g., swapping Redis for Cosmos DB without changing application code).

---

## 2. Ingress & Traffic Splitting Mechanics

ACA provides native Layer 7 routing via managed Envoy proxies:
- **Ingress Modes:**
  - `External`: Publicly routable endpoint with automatic TLS certificate provisioning.
  - `Internal`: Accessible only within the ACA environment or from within the peered Azure Virtual Network.
- **Traffic Splitting (Canary & Blue-Green):**
  Traffic can be distributed across active revisions by percentage:

```yaml
properties:
  configuration:
    ingress:
      traffic:
        - revisionName: order-service--v1
          weight: 80
        - revisionName: order-service--v2
          weight: 20
```

---

## 3. Production Deployment & CLI Operations (`az`)

### 1. Create a Dedicated Subnet for ACA Environment

Azure Container Apps requires a dedicated delegated subnet with at least a `/23` CIDR block for infrastructure consumption.

```bash
# Create dedicated resource group
az group create --name rg-containerapps-prod --location eastus

# Create VNet and delegated subnet for ACA
az network vnet create \
    --resource-group rg-containerapps-prod \
    --name vnet-aca-prod \
    --address-prefixes 10.100.0.0/16 \
    --subnet-name snet-aca-infrastructure \
    --subnet-prefixes 10.100.0.0/23

SUBNET_ID=$(az network vnet subnet show \
    --resource-group rg-containerapps-prod \
    --vnet-name vnet-aca-prod \
    --name snet-aca-infrastructure \
    --query id --output tsv)
```

### 2. Deploy Azure Container Apps Environment

```bash
# Create Log Analytics Workspace
az monitor log-analytics workspace create \
    --resource-group rg-containerapps-prod \
    --workspace-name law-aca-prod

LOG_KEY=$(az monitor log-analytics workspace get-shared-keys \
    --resource-group rg-containerapps-prod \
    --workspace-name law-aca-prod \
    --query primarySharedKey --output tsv)

LOG_ID=$(az monitor log-analytics workspace show \
    --resource-group rg-containerapps-prod \
    --workspace-name law-aca-prod \
    --query customerId --output tsv)

# Deploy ACA Environment in VNet
az containerapp env create \
    --name cae-production-eastus \
    --resource-group rg-containerapps-prod \
    --location eastus \
    --infrastructure-subnet-resource-id "${SUBNET_ID}" \
    --logs-workspace-id "${LOG_ID}" \
    --logs-workspace-key "${LOG_KEY}"
```

### 3. Deploy Production Microservice with KEDA & Dapr

Deploy an event-driven order processing worker scaling on Azure Service Bus queue depth:

```bash
az containerapp create \
    --name order-processor \
    --resource-group rg-containerapps-prod \
    --environment cae-production-eastus \
    --image mcr.microsoft.com/k8se/quickstart:latest \
    --cpu 0.5 \
    --memory 1.0Gi \
    --min-replicas 0 \
    --max-replicas 15 \
    --enable-dapr \
    --dapr-app-id order-processor \
    --dapr-app-port 8080 \
    --ingress internal \
    --target-port 8080 \
    --scale-rule-name service-bus-scale \
    --scale-rule-type azure-servicebus \
    --scale-rule-metadata \
        queueName=orders \
        messageCount=10 \
    --scale-rule-auth \
        connection=service-bus-connection \
    --secrets \
        service-bus-connection="Endpoint=sb://sb-prod.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=secret"
```

### 4. Configure Traffic Splitting for Zero-Downtime Rollouts

```bash
# Set traffic weights between current and canary revision
az containerapp ingress traffic set \
    --name order-processor \
    --resource-group rg-containerapps-prod \
    --revision-weight \
        order-processor--v1=80 \
        order-processor--v2=20
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Consumption Plan Limit | Dedicated Workload Profile |
| :--- | :--- | :--- |
| **Max Cores per App** | 4.0 vCPU | Up to 32 vCPU per replica |
| **Max Memory per App**| 8.0 GiB | Up to 256 GiB per replica |
| **Min Replicas** | 0 (Scale to zero) | 0 to any arbitrary number |
| **Max Replicas per App** | 30 replicas | Up to 300 replicas |
| **Subnet Size Required**| `/23` minimum (512 IPs) | `/23` minimum |
| **Concurrent Active Revisions** | 100 per app | 100 per app |
| **Startup Probe Timeout** | 240 seconds | 240 seconds |
| **Storage Mounts** | Azure Files (SMB / NFS) | Azure Files, ephemeral local storage |

---

## 5. Official References & Documentation

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [KEDA Autoscaling in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Dapr Integration Guide for Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview)
- [VNet Injection & Architecture](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Azure Container Apps Pricing Matrix](https://azure.microsoft.com/en-us/pricing/details/container-apps/)

---

## 6. Realistic Pricing Scenarios

Azure Container Apps Consumption pricing is charged per second:
1. **vCPU Usage:** $0.000024 per vCPU-second.
2. **Memory Usage:** $0.000003 per GiB-second.
3. **HTTP Requests:** $0.40 per million requests (first 2 million requests/month are free).
4. **Free Tier:** 180,000 vCPU-seconds and 360,000 GiB-seconds free every month.

### Scenario A: Event-Driven Queue Consumer (Bursty Worker Scaling to Zero)

- **Workload:**
  - Microservice processes orders from Service Bus. Runs an average of 4 hours per day (120 hours/month).
  - Scaled to **0 replicas** for the remaining 20 hours/day ($0 cost).
  - While active: Scales dynamically between 1 and 5 replicas (average: 3 replicas).
  - Size per replica: 0.5 vCPU, 1.0 GiB RAM.
- **Monthly Cost Calculation:**
  - Active Compute: 3 replicas × 0.5 vCPU = 1.5 vCPUs.
  - Active Memory: 3 replicas × 1.0 GiB = 3.0 GiB.
  - Active Seconds: 120 hours × 3,600 seconds = 432,000 seconds.
  - vCPU-seconds: $1.5 \times 432{,}000 = 648{,}000$. Deduct free tier (180,000) = 468,000 billable.
  - Memory GiB-seconds: $3.0 \times 432{,}000 = 1{,}296{,}000$. Deduct free tier (360,000) = 936,000 billable.
  - vCPU Cost: $468{,}000 \times \$0.000024 = \mathbf{\$11.23}$
  - RAM Cost: $936{,}000 \times \$0.000003 = \mathbf{\$2.81}$
- **Total Monthly Cost:** **$14.04 / month**

### Scenario B: High-Throughput Public API (Always-On Baseline + Auto-Burst)

- **Workload:**
  - Minimum 2 replicas running 24/7 (1.0 vCPU, 2.0 GiB each).
  - Spikes to 10 replicas for 4 hours daily during peak business traffic.
  - Handles 20 million HTTP requests per month.
- **Monthly Cost Calculation:**
  - Baseline Replicas (2 × 730 hrs): $2 \times 730 \times 3{,}600 = 5{,}256{,}000 \text{ replica-seconds}$.
  - Peak Burst Replicas (8 extra replicas × 120 hrs): $8 \times 120 \times 3{,}600 = 3{,}456{,}000 \text{ replica-seconds}$.
  - Total Replica Seconds: $8{,}712{,}000 \text{ seconds}$.
  - vCPU Cost (1.0 vCPU/rep): $(8{,}712{,}000 - 180{,}000) \times \$0.000024 = \mathbf{\$204.77}$
  - RAM Cost (2.0 GiB/rep): $((8{,}712{,}000 \times 2) - 360{,}000) \times \$0.000003 = \mathbf{\$51.19}$
  - Request Fees: $(20\text{M} - 2\text{M}) \times \$0.40/\text{M} = \mathbf{\$7.20}$
- **Total Monthly Cost:** **$263.16 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Subnet Delegation `/23` Size Requirement:** When provisioning an ACA Environment with VNet injection, Azure strictly requires a delegated subnet with at least a `/23` prefix (512 IP addresses). If you attempt to use a standard `/24` or `/25` subnet, environment creation fails immediately with `SubnetSizeTooSmall`. The infrastructure reserves hundreds of IPs internally for control-plane ingress Envoy controllers, node scaling buffers, and internal DNS resolution.
2. **Cold Starts When Scaling from Zero:** Scaling an application from 0 to 1 replica takes between **4 to 12 seconds** depending on container image size and container registry network latency. For latency-sensitive user-facing public APIs, never set `--min-replicas 0`; keep `--min-replicas 1` or `2` active at all times. Reserve scale-to-zero for asynchronous background queue processors.
3. **Environment Variable Changes Create New Revisions Silently:** In Azure Container Apps, any update to an environment variable, image tag, secret reference, or resource request creates a brand new **Revision**. If you have configured static traffic percentages across revisions, the new revision might receive 0% of traffic by default until you update your traffic routing rules. Set revision mode to `Single` if you intend each deployment to immediately supersede the previous version.
4. **Log Analytics Workspace Log Ingestion Volume Shock:** By default, Envoy access logs, system events, and container console output (`stdout`/`stderr`) are streamed into the linked Log Analytics workspace under the `ContainerAppConsoleLogs_CL` and `ContainerAppSystemLogs_CL` tables. High-volume logging can easily rack up hundreds of gigabytes in Log Analytics ingestion fees ($2.30/GB). Ensure application logging levels are set to `WARN` or `ERROR` in production.
5. **Dapr Actor State Management Bottlenecks:** When leveraging Dapr actors inside ACA, state persistence relies on external components (e.g., Azure Cosmos DB or Azure Cache for Redis). Ensure the connection pool and request timeout of your Dapr state store component match the max replica concurrency of your container apps, or Dapr sidecars will throw `HTTP 500 Dapr Actor Placement Service Timeout` errors under sudden burst traffic.
6. **Managed Identity Token Caching Inside Containers:** ACA injects the Azure Managed Identity endpoint inside the container via `IDENTITY_ENDPOINT` and `IDENTITY_HEADER` environment variables. Microservices should use the Azure Identity SDK (`DefaultAzureCredential`) to request OAuth2 access tokens. Always cache tokens until their expiration (`expires_in`); requesting a fresh token over HTTP on every incoming request will trigger platform throttling from Entra ID (`AADSTS50196: Client loop detected`).

---
title: AKS Autoscaling Architecture — Cluster Autoscaler, KEDA, and Virtual Nodes
description: Exhaustive engineering guide to multi-dimensional autoscaling on AKS — Cluster Autoscaler (CA) tuning, Node Auto-Provisioning (NAP/Karpenter), HPA v2 with Azure Monitor external metrics, KEDA event-driven queue scalers, and Azure Virtual Nodes (ACI bursts).
tags:
  - azure
  - aks
  - autoscaling
  - keda
  - hpa
  - karpenter
  - aci
---

# AKS Autoscaling Architecture — Cluster Autoscaler, KEDA, and Virtual Nodes 📈⚡

Modern cloud architectures experience volatile, bursty, and unpredictable traffic patterns. Scaling an Azure Kubernetes Service (AKS) cluster efficiently requires coordinating **three distinct autoscaling layers**:
1. **Pod Horizontal Scaling (HPA v2):** Adjusts pod replicas based on CPU, memory, or custom HTTP request metrics.
2. **Event-Driven Scaling (KEDA):** Drives pod counts to zero or hundreds based on external messaging queues (Azure Service Bus, Event Hubs, Kafka).
3. **Infrastructure Scaling:** Expands underlying VM capacity via the **Cluster Autoscaler (CA)**, **Node Auto-Provisioning (Karpenter for Azure)**, or serverless container bursts via **Azure Virtual Nodes (ACI)**.

---

## 1. Architecture: The Multi-Layer Autoscaling Loop

```
       EXTERNAL EVENT SOURCES (Azure Service Bus / Event Hubs / Kafka)
                                  │
                                  ▼ Ingests 50,000 Messages/sec
       ┌────────────────────────────────────────────────────────────────────────┐
       │                KEDA (KUBERNETES EVENT-DRIVEN AUTOSCALING)              │
       │                - Polls Service Bus queue length every 15 seconds       │
       │                - Exposes `ExternalMetric` to Kubernetes HPA v2         │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ Scales Deployment Replicas
                                          ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │             HORIZONTAL POD AUTOSCALER (HPA v2): Scales 5 -> 100 Pods   │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ 80 Pods Enter "Pending" (Insufficient CPU)
                                          ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                   INFRASTRUCTURE PROVISIONING LAYER                    │
       │                                                                        │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ Cluster Autoscaler(VMSS│   OR    │ Node Auto-Provisioning │         │
       │  │ - Expands Node Pool    │         │ (Karpenter on Azure)   │         │
       │  │ - Provisions D8ds_v5   │         │ - JIT VM shape packing │         │
       │  │ - 60-90s spin-up       │         │ - 40s rapid bootstrap  │         │
       │  └───────────┬────────────┘         └───────────┬────────────┘         │
       │              │ VM Ready                         │ VM Ready             │
       │              ▼                                  ▼                      │
       │  ┌──────────────────────────────────────────────────────────┐          │
       │  │     ALTERNATIVE: AZURE VIRTUAL NODES (SERVERLESS ACI)    │          │
       │  │     - Bypasses VM spin-up entirely                       │          │
       │  │     - Pods burst directly into Azure Container Instances │          │
       │  │     - Sub-10 second execution with per-second billing    │          │
       │  └──────────────────────────────────────────────────────────┘          │
       └────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Infrastructure Scaler Comparison: CA vs. NAP (Karpenter) vs. Virtual Nodes

| Dimension | Cluster Autoscaler (CA) | Node Auto-Provisioning (Karpenter) | Azure Virtual Nodes (ACI) |
| :--- | :--- | :--- | :--- |
| **Target Mechanism** | Pre-configured VMSS pools | JIT Arbitrary VM creation | Serverless Container Instances |
| **Cold Start Latency**| **60 to 90 seconds** | **~40 seconds** | **< 10 seconds** |
| **Instance Flexibility**| Fixed to pool's VM size (e.g. D4s)| Any Azure VM size matching pod requests| CPU/Memory allocated per container |
| **Bin-Packing Efficiency**| Moderate (Can strand CPU/RAM) | **Optimal (Consolidates on the fly)**| Perfect (Pay strictly for pod size) |
| **Max Pods per Node** | Fixed per VMSS node pool | Dynamically tailored per instance | Unlimited (Serverless) |
| **Stateful Disks (PVC)**| Supported (Azure Disk / Files)| Supported | Azure Files only (No Azure Disk) |

---

## 3. Production Configuration & CLI Operations (`az` CLI & `kubectl`)

### 1. Fine-Tune Cluster Autoscaler on AKS

Optimize Cluster Autoscaler parameters to eliminate scale-down delays while preventing thrashing:

```bash
# Update Cluster Autoscaler profile with aggressive scale-up and optimized scale-down
az aks update \
    --resource-group rg-prod-aks \
    --name aks-core-prod \
    --cluster-autoscaler-profile \
        scan-interval=10s \
        scale-down-delay-after-add=5m \
        scale-down-unneeded-time=5m \
        scale-down-utilization-threshold=0.6 \
        max-empty-bulk-delete=10 \
        expander=least-waste
```

### 2. Enable KEDA Add-on on AKS

```bash
# Enable native managed KEDA extension on the cluster
az aks update \
    --resource-group rg-prod-aks \
    --name aks-core-prod \
    --enable-keda
```

### 3. Deploy Event-Driven Autoscaling with KEDA (Azure Service Bus)

Scale the `order-worker` deployment dynamically based on the queue depth of Azure Service Bus:

Create `order-worker-keda-scaler.yaml`:

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: azure-servicebus-auth
  namespace: production
spec:
  podIdentity:
    provider: azure-workload
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: order-processor-scaler
  namespace: production
spec:
  scaleTargetRef:
    name: order-processor
  minReplicaCount: 0   # Scales to ZERO when queue is empty!
  maxReplicaCount: 50  # Scales up to 50 pods during flash sales
  cooldownPeriod: 300
  pollingInterval: 15
  triggers:
  - type: azure-servicebus
    metadata:
      queueName: incoming-orders
      namespace: sb-ecommerce-prod
      messageCount: "10" # Target 1 pod for every 10 messages in queue
    authenticationRef:
      name: azure-servicebus-auth
```

Apply KEDA manifests:

```bash
kubectl apply -f order-worker-keda-scaler.yaml
```

### 4. Deploy HPA v2 with Multiple Metrics

Create `api-hpa-v2.yaml` scaling based on both CPU utilization and concurrent active requests:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-service-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-service
  minReplicas: 3
  maxReplicas: 30
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
```

Apply HPA:

```bash
kubectl apply -f api-hpa-v2.yaml
```

---

## 4. Quotas, Performance & Configuration Limits

| Parameter | Platform Limit | Production Context |
| :--- | :--- | :--- |
| **Max Nodes per VMSS Pool** | **1,000 nodes** | Single node pool ceiling |
| **Max ScaledObject per Cluster**| **1,000 ScaledObjects** | KEDA controller polling scale limit |
| **ACI Virtual Node Scale** | Up to **500 concurrent pods**| Limited by regional ACI subscription vCPU quotas |
| **KEDA Polling Interval** | Default: **30 seconds** | Minimum safe interval is `10s` to avoid Azure API throttling |
| **Cluster Autoscaler Expanders**| `random`, `most-pods`, `least-waste`, `priority` | `least-waste` minimizes unallocated VM slack capacity |

---

## 5. Official References

- [Cluster Autoscaler in AKS](https://learn.microsoft.com/en-us/azure/aks/cluster-autoscaler)
- [Node Auto-Provisioning (Karpenter on AKS)](https://learn.microsoft.com/en-us/azure/aks/node-autoprovisioning)
- [KEDA Add-on for Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/aks/keda-about)
- [Azure Virtual Nodes with AKS](https://learn.microsoft.com/en-us/azure/aks/virtual-nodes)

---

## 6. Realistic Pricing Scenarios

### Scenario A: Asynchronous Processing Pipeline with KEDA Scale-to-Zero

- **Workload Profile:**
  - Order batch ingestion running 3 hours daily.
  - Pods scale from **0 to 40 pods** when messages arrive.
  - Node pool uses `Standard_D8ds_v5` instances ($0.384/hr each).
- **Monthly Cost Breakdown:**
  - Idle Hours (21 hrs/day × 30 days = 630 hrs): **$0.00 compute spend** (Worker node pool scales to 0 nodes).
  - Active Processing Hours (3 hrs/day × 30 days = 90 hrs): 5 nodes × $0.384/hr × 90 hrs = **$172.80**
  - Control Plane Fee: **$73.00**
- **Total Monthly Spend:** **$245.80 / month** *(Delivering over $1,200/mo in savings compared to keeping 5 nodes running 24/7).*

### Scenario B: Flash Sale Burst via Azure Virtual Nodes (ACI)

- **Workload Profile:**
  - Sudden Black Friday flash sale spikes pod demand from 10 pods to 100 pods for exactly 30 minutes.
  - VMSS autoscaling would take 90 seconds to add nodes; Virtual Nodes spin up pods in Azure Container Instances (ACI) instantly.
- **Monthly Cost Breakdown:**
  - 90 ACI pods requesting 1 vCPU and 2 GiB RAM running for 0.5 hours:
    - vCPU cost: 90 × $0.0405/hr × 0.5 hrs = **$1.82**
    - Memory cost: 180 GiB × $0.0044/hr × 0.5 hrs = **$0.40**
- **Total Burst Infrastructure Spend:** **$2.22 for the entire flash event**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Scale-Down Thrashing Trap (`scale-down-unneeded-time`):** If `scale-down-unneeded-time` is left at the default (10 minutes) and traffic spikes every 15 minutes, the Cluster Autoscaler will add nodes, wait 10 minutes, terminate nodes, and then immediately be forced to add nodes again. This **autoscaler thrashing** causes constant pod evictions and container restart churn. Set `scale-down-unneeded-time: 15m` or `20m` in environments with recurring cyclical traffic.
2. **KEDA Scale-to-Zero Service Port Probing Outages:** When KEDA scales a Deployment to zero replicas, any Kubernetes `Service` fronting that deployment loses all endpoints. If internal services or health checks attempt to make HTTP calls to that service, connections fail with `502 Bad Gateway` or `Connection Refused` rather than waiting for KEDA to scale up pods. Use KEDA's HTTP Add-on for HTTP scale-to-zero workloads, or ensure upstream callers handle retries with exponential backoff.
3. **Pods Blocked by Local Storage Blocking Cluster Autoscaler Scale-Down:** By default, the Cluster Autoscaler will **refuse to terminate a node** if any pod on that node uses an `emptyDir` local volume, unless that pod declares the annotation `"cluster-autoscaler.kubernetes.io/safe-to-evict": "true"`. If developers omit this annotation on caching pods, nodes will remain active at 5% utilization, wasting thousands of dollars monthly.
4. **Virtual Nodes Cannot Mount Azure Managed Disks:** Azure Virtual Nodes execute pods inside Azure Container Instances (ACI). ACI does **not support attaching Azure Managed Disks (ReadWriteOnce block storage)**. If a pod requires persistent storage, it must mount an Azure Files share (SMB/NFS) or Azure Blob Storage.
5. **Autoscaler Deadlocks Caused by Zone Unbalance:** When Cluster Autoscaler is deployed across Availability Zones 1, 2, and 3, it attempts to maintain balanced node counts. If Azure temporarily runs out of VM capacity in Zone 1 (Azure Compute allocation failure), the autoscaler may stall scaling across all zones, leaving pods in a permanent `Pending` state. Enable `--balance-similar-node-groups` or migrate to Node Auto-Provisioning (Karpenter).

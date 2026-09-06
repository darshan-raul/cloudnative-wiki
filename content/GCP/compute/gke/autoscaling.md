---
title: GKE Autoscaling Architecture — Cluster Autoscaler, NAP, HPA v2, and VPA
description: Exhaustive engineering guide to GKE autoscaling tiers — Cluster Autoscaler (CA), Node Auto-Provisioning (NAP), Horizontal Pod Autoscaler (HPA v2 with custom & external metrics), Vertical Pod Autoscaler (VPA), and multidimensional autoscaling.
tags:
  - gcp
  - gke
  - autoscaling
  - hpa
  - vpa
  - cluster-autoscaler
---

# GKE Autoscaling Architecture — Cluster Autoscaler, NAP, HPA v2, and VPA 📈⚡

Autoscaling in Google Kubernetes Engine operates as a multi-tiered, coordinated feedback loop. It spans from the application container layer—dynamically adding pod replicas via the **Horizontal Pod Autoscaler (HPA v2)** or adjusting CPU/memory boundaries via the **Vertical Pod Autoscaler (VPA)**—down to the underlying infrastructure layer via the **Cluster Autoscaler (CA)** and **Node Auto-Provisioning (NAP)**. Mastering the interplay between pod-level and node-level autoscalers is critical to achieving sub-minute scaling responsiveness without thrashing or runaway cloud expenditures.

---

## 1. Multi-Tiered Autoscaling Architecture

GKE decouples workload autoscaling (pods) from infrastructure autoscaling (nodes).

```
                         INCOMING TRAFFIC / WORKLOAD LOAD
                                        │
                                        ▼
    ┌────────────────────────────────────────────────────────────────────────┐
    │                      TIER 1: POD-LEVEL AUTOSCALING                     │
    │                                                                        │
    │  ┌──────────────────────────────────┐ ┌─────────────────────────────┐  │
    │  │ HORIZONTAL POD AUTOSCALER (HPA)  │ │ VERTICAL POD AUTOSCALER(VPA)│  │
    │  │ - Evaluates CPU/RAM utilization  │ │ - Recommends CPU/RAM bounds │  │
    │  │ - Evaluates Custom / Ext Metrics │ │ - Updates pod spec in-place │  │
    │  │ - Scale: 5 Pods ──► 50 Pods      │ │ - Auto-restarts on OOM      │  │
    │  └──────────────────┬───────────────┘ └──────────────┬──────────────┘  │
    └─────────────────────┼────────────────────────────────┼─────────────────┘
                          │ Pending Pods (Unschedulable)   │
                          ▼                                ▼
    ┌────────────────────────────────────────────────────────────────────────┐
    │                     TIER 2: NODE-LEVEL INFRASTRUCTURE                  │
    │                                                                        │
    │  ┌──────────────────────────────────┐ ┌─────────────────────────────┐  │
    │  │ CLUSTER AUTOSCALER (CA)          │ │ NODE AUTO-PROVISIONING (NAP)│  │
    │  │ - Expands EXISTING node pools    │ │ - Creates NEW node pools    │  │
    │  │ - Min/Max node bounds per pool   │ │ - Chooses optimal VM shapes │  │
    │  │ - Scales down underutilized nodes│ │ - Provisions GPUs/TPUs      │  │
    │  └──────────────────┬───────────────┘ └──────────────┬──────────────┘  │
    └─────────────────────┼────────────────────────────────┼─────────────────┘
                          │ GCE Compute API Calls          │
                          ▼                                ▼
    ┌────────────────────────────────────────────────────────────────────────┐
    │                  DYNAMIC COMPUTE ENGINE WORKER FLEET                   │
    │   [Node 1: E2-Std-4]   [Node 2: E2-Std-4]   [Node 3: C3-Highmem-8]     │
    └────────────────────────────────────────────────────────────────────────┘
```

### Core Mechanics & Coordination

1. **The Scale-Up Handshake:**
   - Traffic spikes $\rightarrow$ HPA increases Deployment replica count from 5 to 50.
   - 30 pods schedule onto existing nodes with available capacity.
   - Remaining 20 pods cannot fit $\rightarrow$ Kubernetes scheduler flags pods as `Unschedulable` (`Pending`).
   - Cluster Autoscaler (CA) intercepts the `Pending` pods, simulates placement, calculates the exact number of nodes required, and calls the Google Compute Engine API to expand the Managed Instance Group (MIG).
2. **The Scale-Down Quarantine:**
   - Traffic subsides $\rightarrow$ HPA scales down pods from 50 to 5.
   - CA monitors node utilization. If a node's total requested CPU and memory drop below **50%** for more than 10 minutes (configurable via autoscaling profile), CA cordons the node, evicts remaining pods, and deletes the VM instance.

---

## 2. Pod Autoscaling: HPA v2 vs VPA

### HPA v2 (Horizontal Pod Autoscaler)

HPA scales the *number* of pod replicas horizontally based on metrics:
- **Resource Metrics:** Target average CPU or Memory utilization (e.g., scale when average CPU $> 75\%$).
- **Custom Metrics (GMP / Prometheus):** Scale on application-level metrics, such as HTTP requests per second (`http_requests_per_second > 500`) or active TCP sockets.
- **External Metrics (Stackdriver / Cloud Monitoring):** Scale on external Google Cloud events, such as Cloud Pub/Sub unacknowledged message depth (`subscription/num_undelivered_messages > 1000`).

### VPA (Vertical Pod Autoscaler)

VPA adjusts the *CPU and memory requests/limits* of a single container:
- **Modes:**
  - `Off`: Only provides recommendations without modifying pods.
  - `Initial`: Applies recommendations only when pods are first created.
  - `Auto` / `Recreate`: Evicts and recreates running pods with right-sized resource requests.
- **CRITICAL RULE:** **Never run HPA and VPA simultaneously on the same metric (e.g., CPU or Memory).** They will enter a devastating feedback loop where VPA increases memory while HPA deletes pods, destabilizing the service.

---

## 3. Node-Level Autoscaling: Cluster Autoscaler vs Node Auto-Provisioning (NAP)

| Dimension | Cluster Autoscaler (CA) | Node Auto-Provisioning (NAP) |
| :--- | :--- | :--- |
| **Operational Paradigm** | Expands/contracts **pre-existing** node pools | Automatically **creates & destroys** node pools |
| **Machine Shape Selection**| Fixed to the machine types defined in pools | Dynamically picks best machine shape (C3, N2, E2, GPU) |
| **Autoscaling Boundaries**| Bound by per-pool `--min-nodes` / `--max-nodes` | Bound by global cluster resource limits (Total CPU/RAM) |
| **Heterogeneous Workloads**| Requires manual node pool setup for GPUs/Spot | Automatically creates Spot or GPU pools on demand |
| **Best Used For** | Predictable enterprise architectures | Diverse batch, AI/ML, and variable-shape workloads |

---

## 4. Production Deployment & CLI Operations (`gcloud` & `kubectl`)

### 1. Enable Cluster Autoscaler with Optimize-Utilization Profile

```bash
# Set autoscaling profile to optimize-utilization (aggressive downscaling)
gcloud container clusters update prod-regional-cluster \
    --region=us-central1 \
    --autoscaling-profile=optimize-utilization \
    --project=core-infrastructure-prod

# Update worker node pool with min 1 and max 15 nodes per zone
gcloud container node-pools update prod-worker-pool \
    --cluster=prod-regional-cluster \
    --region=us-central1 \
    --enable-autoscaling \
    --min-nodes=1 \
    --max-nodes=15 \
    --total-min-nodes=3 \
    --total-max-nodes=45 \
    --project=core-infrastructure-prod
```

### 2. Enable Node Auto-Provisioning (NAP) with Global Limits

```bash
gcloud container clusters update prod-regional-cluster \
    --region=us-central1 \
    --enable-autoprovisioning \
    --max-cpu=200 \
    --max-memory=800 \
    --autoprovisioning-scopes=https://www.googleapis.com/auth/cloud-platform \
    --autoprovisioning-service-account=gke-node-sa@core-infrastructure-prod.iam.gserviceaccount.com \
    --project=core-infrastructure-prod
```

### 3. Deploy Production HPA v2 with Scaling Behavior & Pub/Sub Metric

Create `order-processor-hpa.yaml`:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: order-processor-hpa
  namespace: e-commerce
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: order-processor
  minReplicas: 3
  maxReplicas: 50
  metrics:
  # Metric 1: CPU Utilization Threshold
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 75
  # Metric 2: Cloud Pub/Sub Undelivered Messages (External Metric)
  - type: External
    external:
      metric:
        name: pubsub.googleapis.com|subscription|num_undelivered_messages
        selector:
          matchLabels:
            resource.labels.subscription_id: "order-events-sub"
      target:
        type: AverageValue
        averageValue: 50
  # Advanced Scaling Behavior (Anti-Flapping stabilization)
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
      - type: Pods
        value: 10
        periodSeconds: 15
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
      selectPolicy: Min
```

Apply HPA:

```bash
kubectl apply -f order-processor-hpa.yaml
```

### 4. Deploy Vertical Pod Autoscaler in Recommendation Mode

Create `order-processor-vpa.yaml`:

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: order-processor-vpa
  namespace: e-commerce
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: order-processor
  updatePolicy:
    updateMode: "Off" # Safely generate recommendations without evicting pods
  resourcePolicy:
    containerPolicies:
    - containerName: "processor"
      minAllowed:
        cpu: "100m"
        memory: "256Mi"
      maxAllowed:
        cpu: "4"
        memory: "8Gi"
```

Apply and inspect recommendations:

```bash
kubectl apply -f order-processor-vpa.yaml
kubectl get vpa order-processor-vpa -n e-commerce -o yaml
```

---

## 5. Quotas, Performance, and Configuration Limits

| Dimension / Parameter | Default Setting | Maximum / Scalability Boundary |
| :--- | :--- | :--- |
| **CA Scale-Up Latency** | ~60 to 90 seconds | Time for GCE VM provision + Kubelet bootstrap |
| **CA Scale-Down Delay** | 10 minutes unneeded | 0 to 20 minutes via `--scale-down-unneeded-time` |
| **Max Node Pools per Cluster**| 100 node pools | NAP creates pools dynamically within this quota |
| **HPA Evaluation Cadence** | Every 15 seconds | Managed by `--horizontal-pod-autoscaler-sync-period` |
| **HPA Metrics per Target** | 4 metrics | Evaluates all metrics and scales to highest target |
| **Scale-Down Stabilization** | 300 seconds (5m) | Prevents rapid flapping on bursty traffic |

---

## 6. Official References & Documentation

- [GKE Cluster Autoscaler Overview](https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-autoscaler)
- [Node Auto-Provisioning (NAP) Architecture](https://cloud.google.com/kubernetes-engine/docs/how-to/node-auto-provisioning)
- [Kubernetes Horizontal Pod Autoscaler v2](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Vertical Pod Autoscaler (VPA) in GKE](https://cloud.google.com/kubernetes-engine/docs/concepts/verticalpodautoscaler)
- [Autoscaling Profiles: Balanced vs Optimize-Utilization](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-autoscaler#autoscaling_profiles)

---

## 7. Realistic Pricing Scenarios

Autoscaling optimization directly impacts cloud spend:
1. **Cluster Autoscaler:** Incurs $0 extra platform fee. Bills strictly for the underlying Compute Engine instances provisioned during scale-up.
2. **Node Auto-Provisioning:** $0 platform fee.
3. **Overprovisioning / Ballooning Pods:** Deliberate idle compute reserved to eliminate scale-up latency.

### Scenario A: Un-Autoscaled Static Cluster vs Autoscaled Fleet

- **Static Fleet (Peak-Sized):**
  - Statically provisioned for peak load (50 nodes running `n2-standard-4` 24/7).
  - Cost: 50 nodes × $0.194/hr × 730 hrs = **$7,081.00 / month**.
- **Autoscaled Fleet (CA + HPA Enabled):**
  - Baseline (Night / Off-Peak: 16 hrs/day): 10 nodes ($0.194 × 10 × 480 hrs = $931.20).
  - Peak Traffic (Daytime: 8 hrs/day): Scales to 40 nodes ($0.194 × 40 × 240 hrs = $1,862.40).
  - Net Compute Cost: $931.20 + $1,862.40 = **$2,793.60 / month**.
- **Net Monthly Savings:** **$4,287.40 / month** (~60% reduction).

### Scenario B: Overprovisioning (Ballooning) Capacity for Sub-Second Scaling

- **Workload Requirement:** High-velocity flash sales requiring 100 new pods in < 5 seconds without waiting 90 seconds for GCE VM boot.
- **Architecture:**
  - Cluster Autoscaler running with 3 `n2-standard-4` nodes held by low-priority Pause Pods (`PriorityClass: -1`).
  - Pause Pod Cost: 3 nodes × $0.194/hr × 730 hrs = **$424.86 / month**.
- **Return on Investment:** Production pods evict the pause pods in **< 400 milliseconds**, absorbing the flash spike instantly with zero dropped user carts while CA provisions replacement buffer nodes asynchronously in the background.

---

## 8. Battle-Tested Nuggets & Production Gotchas

1. **The HPA / VPA Circular Conflict Disaster:** If you attach an HPA configured to scale on CPU utilization and a VPA configured in `Auto` mode on the exact same Deployment, they will destabilize each other. When CPU load spikes, HPA adds replicas, which lowers average per-pod CPU utilization. Concurrently, VPA observes high CPU and increases pod resource requests, evicting pods to resize them. This circular fight leads to pod flapping, service degradation, and catastrophic outages. **Use VPA in `Off` (Recommendation) mode when HPA is active.**
2. **Un-Evictable Pods Block Cluster Scale-Down:** Cluster Autoscaler will **never delete a node** if any of the following conditions exist on that node:
   - A pod has local storage (`emptyDir` or `hostPath`) and lacks the annotation `"cluster-autoscaler.kubernetes.io/safe-to-evict": "true"`.
   - A pod lacks a `PodDisruptionBudget` or its PDB has `minAvailable = replicas`.
   - A pod is running in the `kube-system` namespace without a specialized PDB.
   If one non-evictable pod is stuck on a 64-core node, that entire node remains running at 1% utilization forever. Always annotate batch pods with `safe-to-evict: "true"`.
3. **Autoscaling Profile `optimize-utilization` Can Cause Pod Eviction Churn:** The default autoscaling profile is `balanced`. If you switch to `optimize-utilization`, CA aggressively packs pods onto fewer nodes and terminates underutilized nodes after only a few minutes of low traffic. In bursty environments, this causes continuous eviction churn where nodes are repeatedly deleted and recreated every 15 minutes. Use `optimize-utilization` for batch/dev clusters; keep `balanced` for production web APIs.
4. **HPA Scale-Down Flapping (Stabilization Window):** By default in Kubernetes, HPA waits 5 minutes (`stabilizationWindowSeconds: 300`) before executing a scale-down. If a developer overrides this to 0 seconds, a brief 30-second lull in incoming web traffic causes HPA to immediately delete 80% of your pods. When traffic spikes 10 seconds later, remaining pods are overwhelmed and crash. Always enforce a scale-down stabilization window of at least 300 seconds.
5. **GCE Zone Quota Exhaustion Halts Cluster Autoscaler:** When HPA triggers pending pods, CA attempts to provision VMs in the cluster's node zones. If your GCP project exhausts its regional `CPUS_ALL_REGIONS` or zonal `N2_CPUS` compute quota, GCE rejects the VM creation request. Pods remain in `Pending` indefinitely, and `kubectl describe pod` outputs `FailedScaleUp: Pod group couldn't be scheduled on any node pool`. Always set up GCP quota alerting before scaling up production limits.
6. **NAP Creates Unexpected High-Cost Shapes if Unconstrained:** When Node Auto-Provisioning (NAP) is enabled without specifying explicit allowed machine families, NAP can choose expensive memory-optimized (M2) or accelerator shapes if a single developer submits a pod requesting large amounts of memory without a node selector. Always restrict NAP using `--autoprovisioning-locations` and set strict maximum resource bounds (`--max-cpu` and `--max-memory`).

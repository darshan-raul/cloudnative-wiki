---
title: Auto-Scaling
tags:
  - Kubernetes
  - Non-Functional
  - Scaling
  - HPA
  - VPA
  - Karpenter
---

Four layers of scaling work in concert: **HPA** scales pods, **VPA** rightsizes pod resources, **Cluster Autoscaler / Karpenter** scales nodes, **KEDA** scales based on event sources. Used together, they form an elastic system. Misused, they fight each other.

## The four scalers

| Scaler | Scales | Trigger | Status |
|--------|--------|---------|--------|
| **HPA** (HorizontalPodAutoscaler) | Pod replicas | CPU, memory, custom metrics | GA |
| **VPA** (VerticalPodAutoscaler) | Pod resources (requests/limits) | Historical usage | Beta |
| **Cluster Autoscaler (CA)** | Nodes | Pending pods (unschedulable) | GA |
| **Karpenter** | Nodes | Pending pods (direct provisioning) | GA |
| **KEDA** | Pod replicas (via HPA) | External event sources (Kafka, SQS, cron, etc.) | GA |

```
                          ┌─────────────────┐
                          │   Application   │
                          │   traffic       │
                          └────────┬────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
        ▼                          ▼                          ▼
   ┌─────────┐              ┌─────────────┐            ┌─────────────┐
   │   HPA   │              │  Cluster    │            │    KEDA    │
   │  more   │              │  Autoscaler │            │  scale on  │
   │  pods   │              │  / Karpenter│            │  events    │
   └────┬────┘              └──────┬──────┘            └──────┬──────┘
        │                         │                          │
        │      Pending pods      │      Schedulable         │
        │ ◄──────────────────────┤      capacity            │
        │                         │      changes             │
        ▼                         ▼                          ▼
   ┌─────────────────────────────────────────────────────────────┐
   │                          Cluster                            │
   │                                                             │
   │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
   │   │  Pod    │  │  Pod    │  │  Pod    │  │  Pod    │        │
   │   └─────────┘  └─────────┘  └─────────┘  └─────────┘        │
   │                                                             │
   │   ┌────────────┐           ┌────────────┐                   │
   │   │   Node 1   │           │   Node 2   │                   │
   │   └────────────┘           └────────────┘                   │
   └─────────────────────────────────────────────────────────────┘
```

VPA is the orthogonal one: it doesn't change pod count, it changes the resources requested/limited on each pod.

## HPA — Horizontal Pod Autoscaler

HPA scales the **number of pod replicas** in a Deployment, StatefulSet, ReplicaSet, or ReplicationController. It uses the Metrics API to get resource usage, then computes the desired replica count.

### The algorithm

```
desiredReplicas = ceil(currentReplicas * currentMetricValue / desiredMetricValue)
```

With `targetMetricValue: 70` (target 70% CPU), `currentReplicas: 4`, `currentMetricValue: 90` (90% CPU):

```
desiredReplicas = ceil(4 * 90 / 70) = ceil(5.14) = 6
```

Cap at `maxReplicas`. Floor at `minReplicas`.

### Basic HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300   # wait 5min before scaling down
    scaleUp:
      stabilizationWindowSeconds: 0     # scale up immediately
      policies:
      - type: Percent
        value: 100                        # can double
        periodSeconds: 60
```

### What HPA needs

1. **metrics-server** (for CPU/memory) — most clusters have this.
2. **Pod resource requests** — HPA computes utilization as `usage / request`. If requests are missing, the math doesn't work.
3. **Custom metrics adapter** (for non-CPU/memory) — Prometheus Adapter, KEDA, etc.

```bash
# verify HPA can read metrics
kubectl get hpa web-hpa
# NAME      REFERENCE          TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
# web-hpa   Deployment/web     45%/70%   2         20        4          1h

# if "TARGETS" is "<unknown>/70%", metrics-server isn't working
```

### Common HPA mistakes

1. **No resource requests set on pods.** HPA needs `requests.cpu` to compute utilization.
2. **CPU-only scaling for a memory-bound app.** Profile your app; scale on the right metric.
3. **Aggressive scale-up + slow scale-down = flapping.** Set `stabilizationWindowSeconds` to dampen.
4. **HPA + VPA on CPU/memory = conflict.** Don't run both on the same metric.
5. **Scaling a StatefulSet with persistent volumes.** Each replica might need its own PV. HPA works but PV allocation needs to scale with it.

### HPA on custom / external metrics

The Metrics API is extensible. Common adapters:

- **Prometheus Adapter** — query Prometheus, expose as Metrics API
  ```yaml
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "100"
  ```

- **KEDA** — see below

- **Cloud-specific** — AWS CloudWatch, GCP Stackdriver (via adapters)

Setup is non-trivial: deploy the adapter, configure the APIService, register the metrics. The win is scaling on **business metrics** (queue depth, RPS, error rate) instead of just CPU.

## VPA — Vertical Pod Autoscaler

VPA **rightsizes** the resources (requests/limits) on each pod. It watches historical usage and recommends or applies better values.

### Three modes

- **`off`** — recommendations only, no action
- **`initial`** — set requests on pod creation, never update
- **`auto`** — evict pods and recreate with updated requests (DISRUPTIVE)

### Basic VPA

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: web-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  updatePolicy:
    updateMode: "Auto"      # or "Off" for recommendations only
  resourcePolicy:
    containerPolicies:
    - containerName: web
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 2
        memory: 4Gi
```

### When to use VPA

- **Stateless workloads** with predictable resource patterns
- **Right-sizing new deployments** — start with `Off`, look at recommendations, set manually
- **Memory leaks** — VPA won't help with a leak, but it will tell you the leak's growth rate
- **Cost reduction** — many clusters have over-provisioned pods; VPA finds the right size

### When NOT to use VPA

- **HPA is using CPU/memory** — conflict. VPA and HPA on the same metric will fight.
- **Stateful workloads with PVCs** — VPA evicts pods to apply new requests; this disrupts the workload.
- **Latency-sensitive services** — eviction causes a brief capacity dip.
- **Workloads with sidecars** — VPA can misjudge if it doesn't account for sidecar resources.

### VPA + HPA: the right combination

Use them on **different metrics**:

```yaml
# HPA on CPU
metrics:
- type: Resource
  resource:
    name: cpu
    target: { type: Utilization, averageUtilization: 70 }

# VPA on memory
# (VPA is in "Auto" mode for memory only)
```

Or use VPA in **`Off` mode** (recommendations) and HPA on a custom metric (RPS, queue depth, etc.).

## Cluster Autoscaler (CA)

CA watches for **unschedulable pods** and adds nodes. When nodes are underutilized, it removes them.

### How it works

```
pending pod
    ↓
CA sees it
    ↓
CA finds the best node group (based on pod requirements)
    ↓
CA asks the cloud to add nodes (via ASG, MIG, etc.)
    ↓
new nodes come up
    ↓
kube-proxy, CNI, kubelet bootstrap
    ↓
pending pod schedules
```

### When to use CA

- **Cloud-managed clusters** (EKS, GKE, AKE) — CA is built-in or trivial to enable
- **Stable, predictable workloads** — CA is conservative; takes minutes to scale up
- **Cost-conscious** — CA removes underutilized nodes after 10+ minutes

### CA config

```yaml
# EKS — already integrated
# Just create node groups with min/max/desired

# Standalone CA deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - name: cluster-autoscaler
        image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.29.0
        command:
        - ./cluster-autoscaler
        - --v=4
        - --cloud-provider=aws
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/<cluster-name>
        - --balance-similar-node-groups
        - --expander=least-waste
        - --scale-down-delay-after-add=10m
        - --scale-down-unneeded-time=10m
```

### CA gotchas

1. **Scale-up takes 3-5 minutes** (cloud LB provisioning, image pull, kubelet bootstrap). Don't expect instant.
2. **Scale-down is conservative** — 10 minutes of underutilization by default. Adjust for your workload.
3. **Node groups must be tagged** correctly for auto-discovery.
4. **Bin-packing is greedy** — CA adds nodes that fit the largest pending pod, may not be optimal.
5. **Spot instances + CA** — possible, but spot reclamation causes pod rescheduling.

## Karpenter

Karpenter is the **modern replacement for Cluster Autoscaler**. Instead of working through node groups, Karpenter directly provisions nodes that match pending pod requirements.

### How it works

```
pending pod
    ↓
Karpenter sees it (via direct apiserver watch)
    ↓
Karpenter picks the best instance type for the pod's requirements
    ↓
Karpenter calls the cloud API to provision a node
    ↓
node boots, kubelet joins, pod schedules
```

### Karpenter advantages over CA

- **Faster** — 30-60s to scale up, vs 3-5min for CA
- **Right-sized** — Karpenter picks the instance type, not the node group
- **Spot-friendly** — Karpenter has built-in spot, on-demand, and capacity-optimized strategies
- **Consolidation** — Karpenter actively rebalances workloads to fewer, better-fit nodes
- **Simpler** — no node groups, no ASG configs

### Karpenter NodePool

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
      - key: kubernetes.io/arch
        operator: In
        values: ["amd64"]
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot", "on-demand"]
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values: ["c", "m", "r"]
      - key: karpenter.k8s.aws/instance-generation
        operator: Gt
        values: ["4"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
  limits:
    cpu: "1000"
    memory: 4000Gi
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
```

### When to use Karpenter

- **New clusters** — start with Karpenter, skip CA entirely
- **Spot-heavy workloads** — Karpenter's spot handling is much better than CA's
- **Mixed instance types** — Karpenter picks the best fit; no need to pre-define node groups
- **Cost optimization** — Karpenter's consolidation actively reduces nodes
- **Large scale (1000+ nodes)** — Karpenter scales better than CA

### Karpenter gotchas

1. **Karpenter doesn't replace all of CA** — for some cloud features, you still need node groups.
2. **Consolidation can be aggressive** — pods get evicted to bin-pack. Use PodDisruptionBudgets.
3. **Instance type requirements** must be specified carefully. Too narrow = no nodes found. Too broad = expensive nodes.
4. **Node expiration** — `expireAfter` evicts pods after N hours. Plan for stateful workloads.

## KEDA — Kubernetes Event-Driven Autoscaling

KEDA extends HPA to scale based on **event sources** beyond CPU/memory.

### What KEDA can scale on

- **Message queues** — Kafka, RabbitMQ, SQS, Azure Service Bus, GCP Pub/Sub
- **Databases** — PostgreSQL, MongoDB, Redis (query lag, queue depth)
- **Cron** — schedule-based scaling
- **Metrics** — Prometheus, Datadog, CloudWatch
- **HTTP** — request rate
- **Webhooks** — custom event sources

### Example: Kafka lag-based scaling

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kafka-consumer-scaler
spec:
  scaleTargetRef:
    name: kafka-consumer
  minReplicaCount: 1
  maxReplicaCount: 50
  triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka:9092
      consumerGroup: my-consumer-group
      topic: orders
      lagThreshold: "100"     # scale up if any partition lag > 100
```

KEDA watches the Kafka consumer group lag, scales the Deployment to keep lag under 100.

### When to use KEDA

- **Async workloads** — workers consuming from queues
- **Batch processing** — scale to N workers when N records are pending
- **Bursty traffic from external sources** — webhooks, events
- **Replacing custom code** — instead of writing your own scaler

### KEDA gotchas

1. **KEDA is a separate operator.** Adds operational overhead.
2. **Scaling to zero** is supported, but cold-start time matters.
3. **Stateful workloads** — KEDA scale-to-zero kills the workload. Make sure state is external.
4. **Some scalers need credentials** — Kafka SASL, AWS IAM, etc.

## Putting it together

The right combination for most production clusters:

```
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  KEDA (event-driven scaling for async workers)                 │
│    └─> scales kafka-consumer, cron workers, webhook handlers   │
│                                                                │
│  HPA (CPU/memory/custom metrics for stateless services)        │
│    └─> scales web, api based on CPU or RPS                     │
│                                                                │
│  VPA (recommendation mode for rightsizing)                     │
│    └─> outputs recommendations; humans set values              │
│                                                                │
│  Karpenter (cluster scale)                                      │
│    └─> adds/removes nodes based on pending pods                │
│                                                                │
│  PodDisruptionBudgets (safety net)                              │
│    └─> prevents scaling from killing too many pods at once     │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Anti-patterns to avoid

- **HPA + VPA on the same metric** — they'll fight. Use one or the other, or VPA in `Off` mode.
- **CA + Karpenter** — never both. Pick one.
- **No PodDisruptionBudgets** — Karpenter's consolidation can evict all your pods at once.
- **Aggressive scale-up + slow scale-down** — flapping. Set stabilization windows.
- **Scaling on CPU only for memory-bound apps** — scale on memory, or RPS, or queue depth.
- **Setting requests too low** — HPA computes utilization as `usage / request`. If request is too low, you always look at 100% utilization.

## The decision tree

```
Q: What's the workload pattern?
│
├── Steady load, scales predictably     → HPA (CPU/memory)
│
├── Bursty load, event-driven           → KEDA (queue, cron, etc.)
│
├── Latency-sensitive, can scale out    → HPA (RPS, custom metric)
│
├── Right-sizing new workload           → VPA (Off mode, then manual)
│
└── Need to add/remove nodes            → Karpenter (modern) or CA (legacy)
```

## PodDisruptionBudgets — the safety net

PDB is **required** when you have any autoscaling or disruption happening. It tells Kubernetes: "during voluntary disruption, keep at least N pods running."

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 2          # always keep 2 pods
  # or
  maxUnavailable: 1        # never have more than 1 down
  selector:
    matchLabels:
      app: web
```

**This is critical for Karpenter consolidation.** Without PDB, Karpenter can evict all your pods simultaneously, causing a brief outage.

## Metrics to monitor

- **`kube_horizontalpodautoscaler_status_current_replicas`** — HPA's current target
- **`kube_horizontalpodautoscaler_status_desired_replicas`** — what HPA wants
- **`cluster_autoscaler_nodes_total`** / Karpenter equivalent — node count
- **Pod scheduling latency** — how long pending pods wait
- **Scale-up/down events** — alert if HPA is flapping

## Common gotchas

* **HPA needs `metrics-server`.** Without it, HPA shows `<unknown>/70%` and doesn't scale.
* **HPA can only scale on metrics it can read.** CPU/memory is built-in. RPS, queue depth, etc. need adapters.
* **HPA won't scale to zero** by default. Use KEDA for that.
* **VPA + HPA conflict on the same metric.** Don't run both on CPU/memory.
* **Karpenter's consolidation is aggressive.** Always set PDBs.
* **Cluster Autoscaler takes minutes to scale up.** Plan for it. Karpenter is faster.
* **Spot instances + stateful workloads** is risky. Use StatefulSets carefully with spot.
* **Resource requests are the foundation.** Without them, HPA is useless, VPA is guessing, and the scheduler doesn't know what to do.
* **`minReplicas: 0` requires a custom metrics adapter** that supports scaling to zero (KEDA, KNative, etc.). Default HPA cannot scale to zero.
* **HPA and PDB don't always play nicely.** If HPA scales down to minReplicas and PDB says `minAvailable: minReplicas`, the system can deadlock during voluntary disruption. Set PDB conservatively.
* **Karpenter doesn't manage existing node groups** — only the nodes it provisions. Mixed clusters are fine but be aware.

## A worked example

Cluster: 100 RPS average, 1000 RPS peak. Stateless web service.

```yaml
# HPA: scale on CPU
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 5
  maxReplicas: 50
  metrics:
  - type: Resource
    resource:
      name: cpu
      target: { type: Utilization, averageUtilization: 70 }
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
    scaleDown:
      stabilizationWindowSeconds: 300
```

```yaml
# Deployment: requests match HPA's math
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 5
  template:
    spec:
      containers:
      - name: web
        image: myorg/web:v1
        resources:
          requests:
            cpu: 500m    # each pod wants half a core
            memory: 512Mi
          limits:
            cpu: 1
            memory: 1Gi
```

```yaml
# Karpenter NodePool: add nodes when pods don't fit
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot", "on-demand"]
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values: ["c", "m"]
      nodeClassRef:
        name: default
  limits:
    cpu: "200"
    memory: 800Gi
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
```

```yaml
# PDB: keep at least 3 pods during disruption
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 3
  selector:
    matchLabels:
      app: web
```

Together: at low load, 5 pods on 2 nodes. At 1000 RPS, HPA scales to ~30 pods, Karpenter adds 4-6 nodes. Karpenter's consolidation moves pods to fewer, larger nodes during low-load periods. PDB prevents Karpenter from killing all the pods at once.

## See also

* [[Kubernetes/guides/non-functional/cost-optimization|cost-optimization]] — autoscaling + right-sizing = cost
* [[Kubernetes/guides/non-functional/high-availability|high-availability]] — PDBs, multi-AZ
* [[Kubernetes/guides/non-functional/performance-tuning|performance-tuning]] — resource requests and limits
* [[Kubernetes/concepts/L06-scheduling-scaling|L06-scheduling-scaling]] — the concept layer

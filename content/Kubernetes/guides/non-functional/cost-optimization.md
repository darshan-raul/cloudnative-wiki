---
title: Cost Optimization
tags:
  - Kubernetes
  - Non-Functional
  - Cost
  - FinOps
---

K8s clusters are easy to over-spend on. The default behavior is to provision conservatively (lots of headroom, big nodes, no spot), and bills grow linearly with the number of services. The good news: a few well-placed levers can cut your bill 50-70% without changing the workload.

## Where the money goes

```
Typical k8s cluster cost breakdown:
┌──────────────────────────────────────────────────────────┐
│                                                          │
│  60-80%   Compute (EC2/EKS nodes, GKE nodes, AKS VMs)    │
│  10-20%   Control plane (EKS, GKE, AKS)                  │
│   5-15%   Storage (EBS, persistent disks, object storage)│
│   2-5%    Egress (cross-AZ, cross-region, internet)      │
│   1-5%    Load balancers (NLB, ALB)                      │
│   <1%     Other (API calls, CloudWatch, etc.)            │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

The bulk of the bill is **compute**. Storage is a distant second. Egress can sneak up on you if you have a lot of cross-AZ traffic.

## The cost optimization levers

In order of impact, easiest first:

### 1. Right-size pod requests (5-30% savings)

Most clusters have over-provisioned pods. Common patterns:
- 1GB memory request for a pod that uses 80Mi
- 1 CPU request for a pod that uses 50m
- Memory requests copied from the limit, not the actual need

**How to find:** deploy VPA in `Off` mode, look at recommendations.

```bash
kubectl get vpa -A
# NAME      REFERENCE         MODE   CPU    MEM    PROVIDED
# web-vpa   Deployment/web    Off    80m    180Mi  1       1Gi
# HPA says "use 80m CPU, 180Mi memory"
# but you set requests to 1 CPU, 1Gi
# that's 12x overprovisioned on CPU, 5x on memory
```

**Fix:** update the Deployment's `resources.requests` to match actual usage.

```yaml
resources:
  requests:
    cpu: 100m       # was 1
    memory: 256Mi   # was 1Gi
  limits:
    cpu: 500m       # was 2
    memory: 512Mi   # was 2Gi
```

**Why it matters:** the scheduler uses requests to bin-pack pods onto nodes. If requests are too high, fewer pods fit per node, you need more nodes, more cost.

### 2. Use spot / preemptible instances (60-90% on those nodes)

Spot instances are 60-90% cheaper than on-demand. The catch: they can be reclaimed with 30s-2min notice.

**Where spot works:**
- Stateless services that can be rescheduled quickly
- Batch jobs (with checkpointing)
- Dev/staging environments
- Worker nodes behind a service mesh (rescheduling is fast)

**Where spot doesn't work:**
- Stateful workloads with PVCs (re-attaching a volume takes minutes)
- Latency-sensitive services that can't tolerate brief capacity loss
- Gossip-based systems (Consul, etcd — except as a quorum with on-demand)

**Karpenter + spot** is the modern approach:

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: spot
spec:
  template:
    spec:
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot"]
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values: ["c", "m", "r"]
      nodeClassRef:
        name: default
  limits:
    cpu: "500"
  disruption:
    consolidationPolicy: WhenUnderutilized
    # spot nodes can be reclaimed; Karpenter handles the disruption
```

For mixed workloads, run critical pods on on-demand nodes, best-effort on spot. Use nodeSelectors, taints/tolerations, or topology spread.

### 3. Right-size cluster nodes (10-30%)

Many clusters use a single instance type (e.g., all `m5.large`). That bin-packs poorly — a pod needing 1.5GB memory won't fit, even if the node has 1GB CPU free.

**Karpenter** solves this by **right-sizing nodes per pod**:

```
Pod asks for 1 CPU, 1Gi memory
    ↓
Karpenter picks the smallest instance that fits
    ↓
c6g.large (2 CPU, 4Gi) — 1 pod, 50% utilized
```

vs. CA / node groups:

```
All nodes are m5.large (2 CPU, 8Gi)
    ↓
Pod asks for 1 CPU, 1Gi
    ↓
Lands on m5.large, 50% utilized
    ↓
If 10 pods land here, you're at 100% memory — needs another node
    ↓
But if pods are smaller, the node is wasted
```

**Instance family selection matters.** Some instances are more cost-effective for certain workloads:
- **Compute-optimized (c5, c6i, c7g)** — CPU-bound, batch, video
- **Memory-optimized (r5, r6i, x2)** — caches, in-memory DBs
- **General (m5, m6i)** — web servers, APIs
- **ARM (Graviton — c7g, m7g, r7g)** — 20-40% cheaper per core, requires ARM-compatible images

### 4. Scale down off-hours (20-50% for non-prod)

Dev/staging clusters don't need to run 24/7.

**Pattern: scale to zero at night**

```bash
# in CI / a CronJob
# scale all Deployments to 0 at 7pm
kubectl scale deploy --all -n dev --replicas=0
# scale back up at 8am
kubectl scale deploy --all -n dev --replicas=1
```

**Pattern: scale down cluster nodes** (Karpenter can do this automatically)

```yaml
disruption:
  consolidationPolicy: WhenUnderutilized
  expireAfter: 24h
```

**Pattern: separate dev and prod clusters.** Scale dev aggressively, leave prod stable.

### 5. Use committed-use / savings plans (20-40% on steady state)

AWS Compute Savings Plans, GCP Committed Use Discounts, Azure Reserved Instances. 1-year or 3-year commitments for 20-40% off on-demand prices.

**Strategy:** commit to your **steady-state** baseline. Use spot for burst.

```bash
# EKS example
# Baseline: 20 m5.large always running = $3,200/mo at on-demand
# 1-year Compute Savings Plan: $2,100/mo (35% off)
# Burst: 50 c5.xlarge spot for peak = $1,200/mo (vs $4,000 on-demand)
```

### 6. Use cluster autoscaler / Karpenter aggressively (10-20%)

If your cluster doesn't scale to zero or scale down aggressively, you're paying for idle capacity.

**Karpenter's `consolidationPolicy: WhenUnderutilized`** continuously rebalances pods to fewer, better-fit nodes. This is one of Karpenter's biggest cost wins vs CA.

### 7. Storage cost (5-20%)

Persistent disks are billed by size and type. Optimization:

- **Don't over-provision PVCs.** Many teams ask for 100Gi when they need 10Gi.
- **Use the right storage class.** gp3 is cheaper than io1. Standard disks are cheaper than SSD.
- **Lifecycle old data.** Move backups to S3 (or equivalent), not EBS.
- **Use snapshots, not cloned volumes.** Snapshots are incremental and cheap.

```yaml
# bad: io2 with 1000 IOPS
storageClassName: io2
resources:
  requests:
    storage: 1Ti

# good: gp3 for most workloads
storageClassName: gp3
resources:
  requests:
    storage: 100Gi
```

### 8. Egress cost (varies wildly)

Cloud egress is the silent killer. Each cloud's pricing differs:

| Cloud | Egress cost |
|-------|-------------|
| **AWS** | $0.09/GB to internet, $0.01/GB cross-AZ, free in-region |
| **GCP** | $0.12/GB to internet, $0.01-0.08/GB cross-region |
| **Azure** | $0.087/GB to internet, $0.01/GB cross-AZ |

**Common egress bombs:**

1. **Cross-AZ traffic.** A pod in zone A talking to a Service that routes to a pod in zone B. Multiply by RPS, you can spend thousands.
   ```bash
   # check cross-AZ traffic
   # (AWS: VPC Flow Logs; GCP: VPC Flow Logs; or your CNI's metrics)
   # if high, fix with topology-aware routing or affinity
   ```
   Fix: pod topology spread constraints, or use a service mesh with locality-aware load balancing.

2. **Cross-region replication.** S3 cross-region replication, RDS cross-region replicas, etc. — billed by data transferred.
   Fix: aggressive lifecycle policies, only replicate what you need.

3. **Internet egress from nodes.** Pods talking to external APIs (github.com, registry.npmjs.org, etc.).
   Fix: NAT gateway is cheaper than per-pod NAT, but still expensive. Use VPC endpoints for AWS services (free).

### 9. NetworkPolicy for unused namespaces (1-5%)

Namespaces that aren't actively used still get default policies and possibly DNS traffic. If a dev namespace is left running, pods there can still consume resources.

**Pattern: TTL on dev namespaces**

```yaml
# using kubedb or a custom controller
apiVersion: dev.example.com/v1
kind: DevNamespace
metadata:
  name: alice-experiment
spec:
  ttl: 7d  # auto-delete after 7 days
```

### 10. Image optimization (5-10%)

Smaller images = faster pulls, less storage on nodes.

```dockerfile
# 1.2 GB
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3 python3-pip
COPY . .
RUN pip install -r requirements.txt
CMD ["python3", "server.py"]

# 80 MB
FROM python:3.12-slim
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python3", "server.py"]

# 30 MB
FROM python:3.12-alpine
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python3", "server.py"]

# 20 MB with multi-stage
FROM python:3.12-alpine AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt
COPY . .

FROM python:3.12-alpine
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY . .
ENV PATH=/root/.local/bin:$PATH
CMD ["python3", "server.py"]
```

## The 80/20 — what to do first

For a typical cluster, the biggest wins are:

1. **Right-size pod requests** (VPA in `Off` mode) — easy, 5-30% savings
2. **Spot instances for non-prod and stateless workloads** — 60-90% on those nodes
3. **Karpenter for node right-sizing** — 10-30% on compute
4. **Committed-use / savings plans for steady state** — 20-40% on the committed portion
5. **Scale down dev/staging off-hours** — 20-50% on those clusters

Together: **50-70% reduction** is realistic.

## Tools

### Kubecost (commercial, free tier)

The standard cost-monitoring tool for k8s. Shows:
- Per-namespace, per-Deployment, per-Label cost
- Right-sizing recommendations
- Spot vs on-demand breakdown
- Slack/Teams alerts on cost anomalies

```yaml
# install
helm install kubecost cost-analyzer \
  --repo https://kubecost.github.io/cost-analyzer \
  --namespace kubecost --create-namespace
```

Web UI at `localhost:9090` (port-forward).

### OpenCost (CNCF, open source)

CNCF version of kubecost. Less polished, but free and open.

```yaml
# install
kubectl apply -f https://opencost.github.io/opencost-install.yaml
```

Prometheus + Grafana integration.

### Cloud-native tools

- **AWS Cost Explorer** — per-resource, per-tag cost
- **GCP Billing Reports** — BigQuery export for analysis
- **Azure Cost Management** — per-subscription, per-resource group

Pair these with k8s labels: tag every namespace, Deployment, and Service with `team`, `project`, `environment`. Then bills roll up by label.

### Spot instance management

- **AWS Spot Instance Advisor** — interruption rates per instance type
- **Spotinst / Spot.io** (now AWS Spot) — managed spot orchestration
- **Karpenter** — built-in spot handling, no extra tool

## Cost-aware cluster design

### The "right-sized cluster" pattern

```yaml
# baseline: 3 on-demand c6g.xlarge (steady state)
# burst: spot c6g.2xlarge, c6g.4xlarge, etc. (Karpenter-managed)
# all on ARM (Graviton) for 30% cost savings
```

### The "fleet of small clusters" pattern

Instead of one big shared cluster, run many small clusters:
- Per-environment: dev, staging, prod
- Per-region: us-east-1, eu-west-1
- Per-team: team-a-cluster, team-b-cluster

**Pros:** scale down to zero (dev), isolated blast radius, different node types per cluster.
**Cons:** operational overhead, control plane cost per cluster ($73/mo each on EKS).

**Rule of thumb:** if the cluster runs 24/7 and serves production, one big cluster. If dev/staging, split it.

### The "shared services" pattern

For multi-cluster setups, run shared services (logging, monitoring, ingress) in a dedicated cluster.

- **Control plane cluster** — Argo CD, Vault, monitoring, logging
- **Workload clusters** — your actual apps

Workload clusters can scale up/down without affecting the control plane.

## Cost anomaly detection

Set up alerts for unexpected spikes:

```yaml
# Prometheus alert
- alert: CostAnomaly
  expr: |
    sum(kube_pod_container_resource_requests{resource="cpu"}) 
    > 1.5 * avg_over_time(sum(kube_pod_container_resource_requests{resource="cpu"})[7d])
  for: 1h
  annotations:
    summary: "Cluster CPU requests 50% above 7-day average"
```

Kubecost has built-in anomaly detection. Cloud-native tools (AWS Cost Anomaly Detection, GCP) catch billing anomalies at the account level.

## Capacity planning

For predictable workloads, model the cost:

```
Workload X needs:
  - 10 replicas
  - 500m CPU each = 5 cores total
  - 1Gi memory each = 10Gi total
  - always-on (no scaling down)
  - latency-sensitive (no spot)

Cost calculation:
  - On-demand: 3 c6g.xlarge (4 CPU, 8Gi each) = 12 cores, 24Gi for 10 pods
    = $0.076/hour * 3 * 730 = $166/mo
  - 1-year savings plan: $110/mo
  - 3-year savings plan: $85/mo
```

## The "showback" vs "chargeback" question

**Showback:** tell teams what they're spending. They get visibility, but no bill.

**Chargeback:** actually bill teams. Drives accountability but creates politics.

**For most companies:** showback first, chargeback later. Showback is a soft control; chargeback is a hard one. Once teams see their spend, they self-optimize.

```bash
# kubecost — per-namespace cost
kubectl get ns -o custom-columns=NAME:.metadata.name
# or via the kubecost UI:
# http://kubecost.monitoring:9090/allocation
```

## Cost as a first-class SLO

Treat cost like any other SLO:

```yaml
# Prometheus alerting rule
- alert: NamespaceCostAnomaly
  expr: |
    kubecost_namespace_cost
    > 1.5 * avg_over_time(kubecost_namespace_cost[7d])
  for: 1h
  annotations:
    summary: "Namespace {{ $labels.namespace }} spending 50% over 7-day average"
    runbook: "https://wiki.example.com/runbooks/cost-anomaly"
```

Tie cost anomalies to your SLO/SLA. The team that owns the namespace owns the bill.

## The reserved vs on-demand vs spot decision tree

```
Q: Is the workload stateful with PVCs?
│
├── Yes  →  on-demand (or savings plan)
│          Spot risk = PVC re-attachment = data loss
│
└── No
    │
    Q: Is it latency-sensitive, <100ms p99?
    │
    ├── Yes  →  on-demand (predictable performance)
    │          Spot interruption = brief latency spike
    │
    └── No
        │
        Q: Can it tolerate 30s-2min interruption?
        │
        ├── Yes  →  spot (60-90% savings)
        │          Karpenter handles interruption
        │
        └── No   →  on-demand (or savings plan)
```

## Cost optimization for specific workload types

### Databases

- **Right-size the instance type.** Memory-optimized instances (r5, r7g) for in-memory DBs.
- **Use Aurora / Cloud SQL / managed Postgres** rather than self-managed.
- **Tune the database itself.** Slow queries waste CPU. Indexes, query plans.
- **Connection pooling.** PgBouncer, RDS Proxy. Avoids per-pod DB connection overhead.
- **Read replicas for read-heavy workloads.** Cheaper than scaling the primary.

### Web servers

- **ARM/Graviton** for 30% savings (compatible workloads).
- **Right-size requests** (most common savings lever).
- **CDN for static content.** CloudFront, Cloudflare. Reduces egress and origin load.
- **Caching layer** (Redis, Memcached) for hot data.

### Workers / batch

- **Spot by default** — workers are the spot-friendly workload.
- **Pre-emptible VMs** (GCP) or **Spot VMs** (Azure) for short jobs.
- **Cluster autoscaler / Karpenter** with mixed instance types.
- **Run during off-hours** if possible (scale to 0 at night).

### ML/AI workloads

- **Spot for training** (interruptions OK, can resume from checkpoint).
- **On-demand for inference** (latency-sensitive).
- **GPU sharing** (MIG, time-slicing) for cost efficiency.

## Common cost pitfalls

1. **Multi-AZ when you don't need it.** Multi-AZ adds 2x the data transfer cost for some setups.
2. **Cross-region replication for everything.** Replicate only what you need to recover.
3. **Over-provisioned storage.** Most teams ask for 100Gi when they need 10Gi.
4. **Snapshot sprawl.** Snapshots pile up; lifecycle policies are essential.
5. **NAT gateway data processing.** $0.045/GB processed by NAT. Use VPC endpoints for AWS services (free).
6. **Container image pull costs.** With most clouds, pull is free, but egress from a registry to other regions isn't.
7. **Logging everything at high verbosity.** Ingest costs add up.
8. **Untagged resources.** Cost allocation breaks. Tag everything.
9. **Long-lived dev clusters.** Scale down or destroy.
10. **Egress to internet for AI/ML data.** Move data with Snowball or DataSync.

## The "show me the money" report

A monthly cost report should answer:

- **What did we spend?** Total, by team, by environment, by service.
- **What changed?** vs last month, with explanations.
- **What's the trend?** Forecast for next quarter.
- **What's the saving opportunity?** Items flagged by right-sizing, idle resources.
- **Who owns the spend?** Per-team accountability.

```bash
# kubecost has a built-in report
# /allocation?window=month&aggregation=namespace,team

# raw cost data
kubectl get ns -o json | jq '.items[].metadata.labels.team' | sort -u

# aws cost explorer
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=LINKED_ACCOUNT
```

A good cost report drives action. A bad one is just a number no one looks at.

## Multi-tenant cost allocation

Tag everything:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
  labels:
    team: team-a
    cost-center: engineering
    project: web-app
    environment: production
```

```yaml
# kubecost
apiVersion: kubecost.com/v1alpha1
kind: AllocationTags
metadata:
  name: default
spec:
  tags:
  - team
  - cost-center
  - project
  - environment
```

Now your bill rolls up by team / project / environment.

## The "cheap" gotchas

1. **Spot savings evaporate if your HPA can't reschedule fast.** If pods take 2 minutes to reschedule and your spot gets reclaimed every 5 minutes, you're constantly restarting.
2. **Right-sizing too aggressively** leads to OOMKills and CPU throttling. Profile before shrinking.
3. **Committed-use discounts lock you in.** If you commit for 3 years and your workload shrinks, you still pay.
4. **Karpenter consolidation is disruptive.** Always set PodDisruptionBudgets.
5. **Dev clusters scaled to zero** still cost something. Cluster itself (control plane), persistent disks, etc.
6. **Egress is hard to predict.** One misconfigured service can balloon your bill overnight.
7. **Storage costs don't shrink with auto-scaling.** PVCs persist even when pods are gone.

## A worked example

Cluster: 50 nodes, mostly `m5.2xlarge` (8 CPU, 32Gi). 200 namespaces, mixed dev/staging/prod.

**Bills:**
- Compute: 50 * 8 * $0.192/hour = $5,600/mo
- Storage: 30 PVCs at 100Gi gp3 = $360/mo
- Egress: 2TB cross-AZ at $0.01/GB = $20/mo
- LB: 5 NLB = $90/mo
- **Total: $6,070/mo**

**Optimization:**

1. **Right-size pods.** 30% of pods are over-provisioned by 2x. New node count: 35.
2. **Move dev to spot.** 20 of 35 nodes are dev/staging, can be spot. New dev cost: $560/mo (down from $2,240).
3. **Karpenter for node right-sizing.** Average node utilization goes from 30% to 65%. New node count: 25.
4. **1-year Compute Savings Plan** for steady-state prod (10 nodes). New prod compute: $1,440/mo.
5. **Drop idle namespaces.** 5 namespaces with 0 Deployments still have over-provisioned limit ranges. Drop.

**New bills:**
- Compute (prod): $1,440/mo
- Compute (dev, spot): $560/mo
- Storage: $360/mo
- LB: $90/mo
- **Total: $2,450/mo**

**Savings: 60%.**

## See also

* [[Kubernetes/guides/non-functional/auto-scaling|auto-scaling]] — HPA, VPA, Karpenter, KEDA
* [[Kubernetes/guides/non-functional/performance-tuning|performance-tuning]] — right-sizing
* [[Kubernetes/guides/non-functional/high-availability|high-availability]] — cost vs reliability tradeoffs
* [[Kubernetes/guides/non-functional/backup-restore|backup-restore]] — storage costs

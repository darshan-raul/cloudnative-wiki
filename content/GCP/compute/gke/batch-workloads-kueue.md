---
title: GKE Batch Workloads & Kueue Job Orchestration Architecture
description: Exhaustive engineering guide to running large-scale batch processing on GKE — Kubernetes Job & IndexedJob APIs, Kueue multi-tenant queuing, fair-share scheduling, preemption handling, and Spot VM fault tolerance.
tags:
  - gcp
  - gke
  - batch
  - kueue
  - jobs
  - scheduling
---

# GKE Batch Workloads & Kueue Job Orchestration Architecture ⏱️📦

While Kubernetes was originally architected for long-running stateless microservices, enterprise environments increasingly utilize GKE as a unified compute fabric for **large-scale batch processing**: genomic sequencing, financial risk modeling, rendering pipelines, and parallel data transformations. Orchestrating millions of run-to-completion batch tasks requires specialized primitives: the **Kubernetes Job and IndexedJob APIs**, **GKE Pod-per-Core Autoscaling**, and **Kueue**—the Cloud Native Computing Foundation (CNCF) job queueing controller that enforces multi-tenant quotas, priority preemption, and fair-share resource allocation.

---

## 1. Architecture: The Batch Scheduling Pipeline

Unlike microservices where pods remain running indefinitely behind a Service, batch jobs run to completion and exit with status `Completed` (Exit Code 0).

```
                  BATCH SUBMISSIONS (Data Scientists, Airflow, CI/CD)
                                         │
                                         ▼ (Job / IndexedJob / RayJob)
       ┌────────────────────────────────────────────────────────────────────────┐
       │                   KUEUE QUEUEING CONTROLLER (ADMISSION)                │
       │                                                                        │
       │  ┌──────────────────────────────────────────────────────────────────┐  │
       │  │               MULTI-TENANT LOCAL QUEUES                          │  │
       │  │  Queue 1: Team Risk (Priority 100) | Queue 2: Team ML (Prio 50)  │  │
       │  └──────────────────────────────────┬───────────────────────────────┘  │
       │                                     │ Fair-Share Quota Allocation      │
       │  ┌──────────────────────────────────▼───────────────────────────────┐  │
       │  │                    CLUSTER QUEUE & COHORT POOL                   │  │
       │  │  - Enforces Nominal Quota (Max 500 vCPUs per team)               │  │
       │  │  - Borrowing: Borrows unused quota from peer cohorts             │  │
       │  │  - Gang Scheduling: Suspends jobs until 100% capacity available │  │
       │  └──────────────────────────────────┬───────────────────────────────┘  │
       └─────────────────────────────────────┼──────────────────────────────────┘
                                             │ Unsuspends Admitted Workload
                                             ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                     GKE KUBERNETES CONTROL PLANE                       │
       │                                                                        │
       │   - Schedules Job pods onto matching worker nodes                      │
       │   - Cluster Autoscaler (CA) spins up Spot GCE instances on demand      │
       └─────────────────────────────────────┬──────────────────────────────────┘
                                             │
       ══════════════════════════════════════╪═══════════════════════════════════
       HETEROGENEOUS WORKER FLEET (Spot VMs / Preemptible Capacity)             │
                                             ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │            INDEXED JOB WORKERS (Parallel Sharded Processing)           │
       │                                                                        │
       │   Pod Index 0: Shard 0/100 ──► Checkpoint to Cloud Storage ──► Exit 0  │
       │   Pod Index 1: Shard 1/100 ──► Checkpoint to Cloud Storage ──► Exit 0  │
       │   Pod Index N: Shard N/100 ──► Checkpoint to Cloud Storage ──► Exit 0  │
       └────────────────────────────────────────────────────────────────────────┘
```

### Core Architecture Constructs

1. **Kubernetes Indexed Job API:** Spawns a parallel array of pods where each pod receives a unique, deterministic environment variable `JOB_COMPLETION_INDEX` (e.g., `0`, `1`, ..., `N-1`). Each worker processes its assigned slice of data (e.g., shard ID in GCS or partition range in BigQuery) without requiring an external message queue broker.
2. **Kueue Resource Cohorts:** Allows multiple teams (e.g., Team Analytics and Team Risk) to define separate `LocalQueues` that share a common `Cohort`. If Team Analytics is idle, Team Risk can borrow up to 100% of the cluster's idle capacity. When Team Analytics submits jobs, Kueue preempts the borrowed workloads to reclaim quota.
3. **Pod-Level Exit Code Mechanics:** Supports Kubernetes `podFailurePolicy`. You can configure the Job controller to retry transient network timeouts (Exit Code 1) up to 5 times, but immediately fail the entire Job without retrying if a container exits with an irrecoverable configuration error (e.g., Exit Code 42).

---

## 2. Advanced Job Lifecycle: Pod Failure Policies & Backoff

```yaml
# Pod Failure Policy example inside Job spec
spec:
  backoffLimit: 6
  podFailurePolicy:
    rules:
    # 1. Ignore preemption from Spot VM shutdowns (Do not count toward backoffLimit)
    - action: Ignore
      onPodConditions:
      - type: DisruptionTarget
    # 2. Count application exceptions toward retry backoff limit
    - action: Count
      onExitCodes:
        containerName: worker
        operator: In
        values: [1, 2]
    # 3. Fail immediately on fatal database schema mismatch (Do not waste compute retrying)
    - action: FailJob
      onExitCodes:
        containerName: worker
        operator: In
        values: [99]
```

---

## 3. Production Deployment & CLI Operations (`gcloud` & `kubectl`)

### 1. Provision a High-Density Spot Node Pool for Batch Jobs

```bash
gcloud container node-pools create batch-spot-pool \
    --cluster=prod-regional-cluster \
    --region=us-central1 \
    --machine-type=c3-standard-8 \
    --spot \
    --num-nodes=0 \
    --enable-autoscaling \
    --min-nodes=0 \
    --max-nodes=50 \
    --node-taints="workload=batch:NoSchedule" \
    --node-labels="cloud.google.com/gke-spot=true" \
    --project=core-infrastructure-prod
```

### 2. Install and Initialize Kueue Controller

```bash
# Install Kueue manifests into the cluster
kubectl apply -f https://github.com/kubernetes-sigs/kueue/releases/download/v0.7.1/manifests.yaml

# Verify Kueue controller manager is running
kubectl get pods -n kueue-system
```

### 3. Configure Kueue ResourceFlavor and ClusterQueue

Create `batch-kueue-setup.yaml`:

```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: spot-c3-flavor
spec:
  nodeLabels:
    cloud.google.com/gke-spot: "true"
  nodeTaints:
  - key: "workload"
    value: "batch"
    effect: "NoSchedule"
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: enterprise-batch-cq
spec:
  namespaceSelector: {}
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: spot-c3-flavor
      resources:
      - name: "cpu"
        nominalQuota: 200 # Up to 200 Spot vCPUs
      - name: "memory"
        nominalQuota: 800Gi
  preemption:
    reclaimWithinCohort: Any
    withinClusterQueue: LowerPriority
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: risk-modeling-queue
  namespace: batch-analytics
spec:
  clusterQueue: enterprise-batch-cq
```

Apply Kueue configuration:

```bash
kubectl apply -f batch-kueue-setup.yaml
```

### 4. Deploy High-Scale Parallel IndexedJob Managed by Kueue

Create `parallel-risk-job.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: portfolio-risk-analysis-2026
  namespace: batch-analytics
  labels:
    kueue.x-k8s.io/queue-name: risk-modeling-queue # Binds Job to Kueue Queue
spec:
  parallelism: 20
  completions: 100 # 100 total parallel tasks (runs in 5 waves of 20)
  completionMode: Indexed # Injects JOB_COMPLETION_INDEX
  suspend: true # Suspended by default until Kueue admits it
  template:
    metadata:
      labels:
        app: risk-worker
    spec:
      tolerations:
      - key: "workload"
        operator: "Equal"
        value: "batch"
        effect: "NoSchedule"
      restartPolicy: OnFailure
      terminationGracePeriodSeconds: 25
      containers:
      - name: worker
        image: us-central1-docker.pkg.dev/core-infrastructure-prod/batch/risk-engine:v1.4
        command:
        - "sh"
        - "-c"
        - "python3 analyze_shard.py --shard-id=${JOB_COMPLETION_INDEX} --output=gs://batch-results-prod/shard_${JOB_COMPLETION_INDEX}.parquet"
        resources:
          requests:
            cpu: "2"
            memory: "8Gi"
```

Apply Job:

```bash
kubectl apply -f parallel-risk-job.yaml

# Inspect Kueue admission and queue depth
kubectl get workloads -n batch-analytics
kubectl get jobs -n batch-analytics
```

---

## 4. Quotas, Performance, and Configuration Limits

| Dimension / Parameter | Standard Boundary | Scalability Guidance |
| :--- | :--- | :--- |
| **Max Completions per Job** | 100,000 tasks | Use IndexedJob for high-volume tasks |
| **Kueue Admission Latency** | Sub-second (< 500ms) | Evaluates quotas in-memory |
| **Cluster Autoscaler Scale-Out**| 0 to 50 nodes in ~2-3 mins | Leverages GCE parallel VM creation |
| **Spot Preemption Grace Period**| 25-30 seconds | Checkpoint state to GCS before exit |
| **Job History Retention** | `failedJobsHistoryLimit` | Clean up completed pods to reduce etcd bloat |

---

## 5. Official References & Documentation

- [GKE Batch Workloads Overview](https://cloud.google.com/kubernetes-engine/docs/concepts/batch)
- [Kubernetes Indexed Jobs Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/job/#indexed-job)
- [Kueue CNCF Project Documentation](https://kueue.sigs.k8s.io/)
- [Pod Failure Policy Specification](https://kubernetes.io/docs/concepts/workloads/controllers/job/#pod-failure-policy)
- [Running Large Scale Batch on GKE](https://cloud.google.com/blog/products/containers-kubernetes/best-practices-for-running-batch-jobs-on-gke)

---

## 6. Realistic Pricing Scenarios

Batch pricing relies heavily on **Compute Engine Spot VMs**:
- **C3 Standard Spot VM (8 vCPU / 32 GiB):** ~$0.075 per hour (~75% discount off on-demand).

### Scenario A: Nightly Financial Monte Carlo Simulation (10,000 Tasks)

- **Workload Profile:**
  - 100 parallel worker pods running continuously for 3 hours every night (90 hours/month).
  - Each pod requests 2 vCPUs and 8 GiB RAM.
  - Total compute required: $100 \times 2 = 200 \text{ vCPUs}$ (25 `c3-standard-8` Spot VMs).
- **Monthly Cost Calculation:**
  - 25 Spot VMs × $0.075/hr × 90 hrs = **$168.75**
  - Boot Disks (25 × 100 GB PD during active hours): Negligible (~$1.50)
  - GCS result uploads (500 GB): 500 GB × $0.020/GB = **$10.00**
- **Total Monthly Cost:** **$180.25 / month**
*(Running this identical simulation on on-demand VMs would cost ~$720/month; Spot + Kueue saves **$540/month**).*

### Scenario B: Massive Genomic Sequencing Pipeline (500-Node Burst)

- **Workload Profile:**
  - Ad-hoc genomic pipeline submitted twice a month.
  - Spikes cluster autoscaler from 0 to 100 `c3-standard-16` Spot VMs (1,600 vCPUs, 6,400 GiB RAM).
  - Runs for 8 hours per run (16 hours total/month).
  - Hourly rate for 100 Spot VMs: $100 \times \$0.150/\text{hr} = \$15.00/\text{hr}$.
- **Monthly Cost Calculation:**
  - Spot Compute: $15.00/hr × 16 hrs = **$240.00**
  - GCS FUSE dataset streaming (20 TB): **$400.00**
- **Total Monthly Cost:** **$640.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Completed Pod etcd Bloat Disaster:** When a Kubernetes Job completes 10,000 tasks, each completed pod's metadata remains stored in the Kubernetes master `etcd` database. If your batch pipelines execute hundreds of jobs daily without automatic cleanup, etcd reaches its maximum 8 GB storage limit, crashing the GKE control plane. Always set `ttlSecondsAfterFinished: 300` in your Job spec to automatically purge completed and failed pods from etcd after 5 minutes.
2. **Spot VM Preemption Counts Against `backoffLimit` Without Pod Failure Policy:** By default, if a Spot VM is preempted by Google Cloud, the running pod is killed with `DisruptionTarget`. Kubernetes interprets this as a container failure and increments the Job's `backoffLimit`. If 6 Spot nodes are preempted during a 10-hour training run, Kubernetes **marks the entire Job as FAILED**, abandoning all work. You **must configure a `podFailurePolicy` with `action: Ignore` for `type: DisruptionTarget`**.
3. **Kueue Admission Requires `suspend: true`:** When submitting a Job intended to be governed by Kueue, you **must set `spec.suspend: true`** in the Job manifest. If `suspend: true` is omitted, the standard Kubernetes scheduler will immediately attempt to schedule the pods onto the cluster, completely bypassing Kueue's quota, queueing, and gang scheduling logic.
4. **Indexed Jobs Require Atomic State Checkpoints:** When using `completionMode: Indexed`, if a worker pod processing index 42 crashes 90% of the way through its task, Kubernetes restarts a new pod with the same index 42. If the application did not write state atomically (e.g., uploading partially written corrupt parquet files to GCS), the retried worker will produce duplicate or corrupt data. Always write to a temporary file (`shard_42.tmp`) and atomically rename it (`shard_42.parquet`) upon successful completion.
5. **Scale-to-Zero Node Pool Scheduling Deadlocks:** If your batch node pool autoscales to 0 nodes (`--min-nodes=0`), and you submit a Job requesting specialized taints or resource requests, the Cluster Autoscaler must simulate node provisioning. If the Job specification contains conflicting node selectors or impossible CPU requests (e.g., requesting 34 vCPUs on a 32-vCPU machine), the autoscaler will ignore the pods, and the Job will sit in `Pending` forever without triggering autoscaling.
6. **Kueue Cohort Borrowing Starvation:** If Team A and Team B belong to the same Cohort, and Team A submits 10,000 short 10-second batch tasks, Kueue will allow Team A to borrow Team B's idle quota. If Team B subsequently submits a high-priority Job, Kueue must wait for Team A's running tasks to finish or actively preempt them. Configure `preemption.withinClusterQueue: LowerPriority` and assign explicit priority classes to ensure mission-critical jobs preempt borrowed capacity immediately.

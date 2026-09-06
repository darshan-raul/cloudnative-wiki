---
title: AKS Batch Workloads, Job Orchestration, and Kueue Fair-Share Scheduling
description: Exhaustive engineering guide to large-scale batch computing on AKS — IndexedJob API, Kueue multi-tenant queueing, fair-share scheduling, Spot instance preemption checkpointing, and gang scheduling.
tags:
  - azure
  - aks
  - batch
  - kueue
  - jobs
  - spot-vms
  - ai-ml
---

# AKS Batch Workloads, Job Orchestration, and Kueue Fair-Share Scheduling 📊⏳

While Kubernetes was historically optimized for long-running stateless microservices, enterprise organizations increasingly execute massive **run-to-completion batch computations (genomics sequencing, Monte Carlo financial simulations, nightly data pipelines, and AI model evaluation runs)** on Azure Kubernetes Service (AKS). Standard Kubernetes lacks queuing and fair-share arbitration primitives, causing large batch jobs to starve smaller jobs or exhaust cluster capacity. By orchestrating batch workloads using the **Kubernetes IndexedJob API** and **Kueue (Kubernetes-native Queue Manager)** on **Spot VM node pools**, organizations achieve maximum compute efficiency and cost reduction.

---

## 1. Architecture: Multi-Tenant Batch Queueing with Kueue

Standard Kubernetes schedules pods immediately upon creation; if cluster resources are exhausted, pods pile up in a chaotic `Pending` state. **Kueue** intercepts Job submissions, queues them based on organizational priorities, enforces team-level quotas, and coordinates with the Azure Cluster Autoscaler to provision capacity only when an entire job can run (**All-or-Nothing Gang Scheduling**).

```
       DATA SCIENCE / DATA ENGINEERING USERS & CI/CD PIPELINES
            │                                             │
            ▼ Team A Job Submission                       ▼ Team B Job Submission
       ┌────────────────────────┐                    ┌────────────────────────┐
       │ LocalQueue: `team-risk`│                    │ LocalQueue: `team-nlp` │
       └───────────┬────────────┘                    └───────────┬────────────┘
                   │                                             │
                   └──────────────────────┬──────────────────────┘
                                          │
                                          ▼ Evaluates Quotas & Priorities
       ┌────────────────────────────────────────────────────────────────────────┐
       │                KUEUE CLUSTER QUEUE: `enterprise-batch-cq`              │
       │                                                                        │
       │  - Total Shared Quota: 500 vCPUs / 16 NVIDIA A100 GPUs                 │
       │  - Fair-Share Borrowing: Unused quota shared dynamically               │
       │  - Preemption Policy: Low-priority jobs preempted by critical SLAs     │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ Admits Job (All-or-Nothing)
                                          ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │             KUBERNETES CONTROL PLANE: SCHEDULES 100 PODS               │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ Dynamic Autoscaling Trigger
                                          ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │             SPOT USER NODE POOL (Standard_D16ds_v5 - 80% Off)          │
       │  - Automatic checkpointing to Azure Blob Storage upon preemption       │
       │  - Scales from 0 to 50 nodes during jobs; scales to 0 when idle        │
       └────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Core Batch Engineering Constructs

### 1. The Kubernetes IndexedJob API
For parallel embarrassingly parallel batch computations (e.g., processing 1,000 video chunks or 500 shard files), standard Jobs assign identical environment variables to all pods. The modern **`IndexedJob`** assigns an immutable, unique sequential index (`0` to `N-1`) via the environment variable `JOB_COMPLETION_INDEX` to each pod:
- Pod 0 processes `chunk-000.mp4`
- Pod 1 processes `chunk-001.mp4`
- Pod $N-1$ processes `chunk-(N-1).mp4`
- If Pod 42 fails due to a Spot VM preemption, Kubernetes restarts **only Pod 42**, preserving the completed execution of the remaining 499 pods.

### 2. Kueue: Gang Scheduling vs. Deadlocks
In multi-node distributed AI training or MPI jobs:
- If Job A requests 8 GPUs and Job B requests 8 GPUs on a cluster with only 8 GPUs total, native Kubernetes might schedule 4 pods of Job A and 4 pods of Job B. Neither job can proceed, resulting in a **hardware deadlock**.
- Kueue prevents this by enforcing **All-or-Nothing gang scheduling**: a job is held in the queue until all 8 GPUs are simultaneously available.

---

## 3. Production Deployment & CLI Operations (`kubectl`)

### 1. Install Kueue on AKS

```bash
# Install latest Kueue controller on AKS
kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/v0.6.2/manifests.yaml

# Verify Kueue controller is operational
kubectl wait --for=condition=Available deployment/kueue-controller-manager -n kueue-system --timeout=60s
```

### 2. Configure ClusterQueue and LocalQueue

Create `kueue-configuration.yaml`:

```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: default-spot-flavor
spec:
  nodeLabels:
    workload: batch
    tier: spot
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: batch-cluster-queue
spec:
  namespaceSelector: {} # Monitors all namespaces
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-spot-flavor
      resources:
      - name: "cpu"
        nominalQuota: "200"
        borrowingLimit: "100"
      - name: "memory"
        nominalQuota: "800Gi"
        borrowingLimit: "400Gi"
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: analytics-queue
  namespace: batch-jobs
spec:
  clusterQueue: batch-cluster-queue
```

Apply queue configuration:

```bash
kubectl apply -f kueue-configuration.yaml
```

### 3. Deploy High-Throughput Parallel IndexedJob

Create `parallel-indexed-job.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: genomics-variant-caller
  namespace: batch-jobs
  labels:
    kueue.x-k8s.io/queue-name: analytics-queue # Enroutes job to Kueue!
spec:
  completions: 50
  parallelism: 10 # Runs 10 concurrent worker pods at a time
  completionMode: Indexed
  backoffLimit: 3
  template:
    metadata:
      labels:
        workload: batch
        tier: spot
    spec:
      restartPolicy: OnFailure
      tolerations:
      - key: "kubernetes.azure.com/scalesetpriority"
        operator: "Equal"
        value: "spot"
        effect: "NoSchedule"
      containers:
      - name: variant-caller
        image: mcr.microsoft.com/oss/azure/azure-cli:latest
        command: ["/bin/bash", "-c"]
        args:
        - |
          echo "Processing shard index: ${JOB_COMPLETION_INDEX}"
          # Pull chunk from Azure Blob Storage using the pod index
          az storage blob download \
            --account-name genstorageprod \
            --container-name raw-reads \
            --name "chromosome_${JOB_COMPLETION_INDEX}.bam" \
            --file "chromosome.bam" \
            --auth-mode login
          # Execute processing
          sleep 60
          echo "Completed shard ${JOB_COMPLETION_INDEX} successfully."
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
```

Apply Job:

```bash
kubectl apply -f parallel-indexed-job.yaml
```

---

## 4. Quotas, Performance & Configuration Limits

| Parameter | Limit / Specification | Production Context |
| :--- | :--- | :--- |
| **Max Completions (Job API)** | **100,000 Completions** | Scale limit for single IndexedJob manifest |
| **Max Parallelism** | **10,000 Pods** | Bounded by cluster IPAM and node quotas |
| **Job History Limits** | Default: 3 successful, 1 failed | Prune old jobs to prevent API server etcd bloat |
| **Kueue Admission Latency** | **< 100 milliseconds** | Evaluates queue depth in real time |
| **Spot Eviction Grace Window** | **30 Seconds** | Flush progress to Azure Blob Storage before SIGKILL |

---

## 5. Official References

- [Kubernetes Indexed Job API Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/job/#indexed-job)
- [Kueue: Kubernetes-native Queue Manager](https://kueue.sigs.k8s.io/)
- [Use Spot Node Pools in AKS](https://learn.microsoft.com/en-us/azure/aks/spot-node-pool)
- [Azure Scheduled Events for Spot VM Termination](https://learn.microsoft.com/en-us/azure/virtual-machines/windows/scheduled-events)

---

## 6. Realistic Pricing Scenarios

### Scenario A: Nightly Genomics Processing Pipeline (1,000 Shards on Spot)

- **Job Profile:**
  - 1,000 sequential task shards processed using IndexedJob with `parallelism: 50`.
  - Node pool uses 7x `Standard_D16ds_v5` instances (16 vCPU, 64 GiB RAM each) on Spot.
  - Total job runtime: 3 hours every night (90 hours / month).
- **Cost Calculation:**
  - Standard On-Demand Rate: 7 nodes × $0.768/hr × 90 hrs = **$483.84**
  - Spot Discount (~80% Savings): 7 nodes × $0.1536/hr × 90 hrs = **$96.77**
  - Azure Blob Storage Egress/Ingress (Internal VNet): **$0.00**
- **Total Monthly Processing Cost:** **$96.77 / month** *(Delivering over $380/month in net savings).*

### Scenario B: Multi-Department Financial Simulation (Kueue Fair-Share)

- **Cluster Profile:**
  - 20x `Standard_D8ds_v5` instances reserved for risk analysis.
  - Risk Team and Quant Team share the cluster with nominal quotas of 80 vCPUs each.
  - When Quant Team is idle, Risk Team borrows their quota automatically.
- **Monthly Cost Breakdown:**
  - Compute Nodes (20 nodes): 20 × $0.384/hr × 730 hrs = **$5,606.40**
  - Standard Control Plane: **$73.00**
- **Hardware Efficiency Gain:** By borrowing idle quotas via Kueue, cluster hardware utilization increases from **42% to 91%**, eliminating the need for a secondary $5,600/month cluster.

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The `backoffLimit` Restart Loop on Non-Idempotent Jobs:** By default, if a pod in a Kubernetes Job fails, the Job controller retries until `backoffLimit` (default: 6) is exhausted. If a batch task is non-idempotent (e.g., it writes a database transaction before crashing on file export), retrying the failed pod will create **duplicate database records**. Always make batch operations idempotent or set `spec.backoffLimit: 0`.
2. **etcd Out-of-Memory Crashes from Unpruned Finished Jobs:** Finished Jobs and their completed Pod objects remain in the Kubernetes API server until deleted. If a cron pipeline creates 20,000 completed jobs a month without setting `ttlSecondsAfterFinished: 86400` (or `successfulJobsHistoryLimit`), etcd will exhaust its 8 GiB storage quota, **freezing the entire AKS cluster**.
3. **Spot Eviction Checkpointing Race Condition:** When Azure reclaims a Spot node, it delivers an eviction signal 30 seconds before termination. If a batch pod processes a massive 5 GB memory dataset and attempts to serialize and upload it to Azure Blob Storage during the 30-second window, network saturation will prevent the upload from completing before the hard `SIGKILL` arrives. Architect batch tasks to write lightweight incremental checkpoints every 5 minutes.
4. **Kueue Job Admission Webhook Latency:** Kueue uses a validating and mutating admission webhook to intercept Job submissions. If the `kueue-controller-manager` deployment crashes or runs out of CPU, all future `kubectl apply -f job.yaml` and Helm batch deployments will hang and time out with `Internal error occurred: failed calling webhook`. Monitor Kueue pod health with Azure Monitor.
5. **IndexedJob Image Pull Thrashing:** When an IndexedJob with `parallelism: 100` is admitted simultaneously, 100 pods are scheduled across newly provisioned nodes at the exact same second. If the container image is 5 GB, 100 nodes will concurrently pull the image from Azure Container Registry (ACR), **saturating the registry rate limits (`429 Throttling`)**. Pre-bake batch images into custom VM images or leverage Azure Container Registry Artifact Cache.

---
title: GKE GPU & TPU Orchestration — AI/ML Accelerators, Ray on GKE, and Kueue
description: Exhaustive engineering guide to AI/ML accelerator orchestration on GKE — NVIDIA GPUs (L4, A100, H100), Cloud TPU v5e/v5p slicing, Dynamic Resource Allocation (DRA), Kueue queue management, Ray on GKE, and GPUDirect RDMA.
tags:
  - gcp
  - gke
  - ai-ml
  - gpu
  - tpu
  - ray
  - llm
---

# GKE GPU & TPU Orchestration — AI/ML Accelerators, Ray on GKE, and Kueue 🤖⚡

Google Kubernetes Engine is the premier hyperscale container runtime for modern artificial intelligence, generative models, and large-scale distributed training. Supporting the entire spectrum of machine learning acceleration—from cost-effective **NVIDIA L4** inference GPUs and **NVIDIA H100 80GB SXM5** clusters with **GPUDirect RDMA** to Google's proprietary **Cloud TPU v5e / v5p multi-slice architectures**—GKE provides deep orchestration primitives. By combining Kubernetes with **Kueue** (fair-share job queueing) and **Ray on GKE (KubeRay)**, organizations can train, fine-tune, and serve frontier LLMs with maximum hardware utilization.

---

## 1. Accelerator Architecture: NVIDIA GPU vs Cloud TPU

GKE abstracts two fundamentally distinct accelerator architectures into a unified Kubernetes scheduling plane:

```
                  NVIDIA GPU ACCELERATOR CLUSTER (A3 / H100)
    ┌────────────────────────────────────────────────────────────────────────┐
    │ HOST COMPUTE NODE (a3-highgpu-8g: 208 vCPUs / 1872 GiB RAM)            │
    │                                                                        │
    │  ┌──────────────────────┐  NVLink 4  ┌──────────────────────┐          │
    │  │ 8x NVIDIA H100 GPUs  │◄──────────►│ High-Speed Intra-Host│          │
    │  │ (80GB HBM3 each)     │  (900 GB/s)│ All-Reduce Sync      │          │
    │  └──────────┬───────────┘            └──────────────────────┘          │
    │             │ GPUDirect RDMA                                           │
    │             ▼                                                          │
    │  ┌──────────────────────────────────────────────────────────┐          │
    │  │ 4x 200 Gbps Host Interconnect (3.2 Tbps Cross-Node Mesh) │          │
    │  └──────────────────────────────────────────────────────────┘          │
    └────────────────────────────────────────────────────────────────────────┘

═════════════════════════════════════════════════════════════════════════════════

                  GOOGLE CLOUD TPU ARCHITECTURE (v5e / v5p Slices)
    ┌────────────────────────────────────────────────────────────────────────┐
    │ OPTICAL CIRCUIT SWITCH (OCS) RECONFIGURABLE TORUS INTERCONNECT         │
    │                                                                        │
    │  ┌────────────────────────┐         ┌────────────────────────┐         │
    │  │ TPU Node (Chip 0)      │  ICI    │ TPU Node (Chip 1)      │         │
    │  │ 16-32 GB HBM2e         │◄───────►│ 16-32 GB HBM2e         │         │
    │  │ Matrix Multiply Units  │ (Torus) │ Matrix Multiply Units  │         │
    │  └────────────────────────┘         └────────────────────────┘         │
    │                                                                        │
    │  - Multi-Host Slices: 16 to 8,960 chips interconnected via dedicated   │
    │    Inter-Chip Interconnect (ICI) cables, completely bypassing standard │
    │    TCP/IP datacenter networking.                                       │
    └────────────────────────────────────────────────────────────────────────┘
```

### Accelerator Taxonomy & Machine Families

| Dimension | NVIDIA L4 (G2) | NVIDIA H100 (A3 Mega) | NVIDIA H200 (A3 Ultra) | Cloud TPU v5e / v5p | Cloud TPU v6e (Trillium) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Primary Use Case** | LLM Inference & Vision | Massive Frontier Training | Ultra-Memory LLM Training | Foundation Training & Serving | Next-Gen Foundation Training |
| **VRAM / HBM** | 24 GB GDDR6 | 80 GB HBM3 | 141 GB HBM3e | 16/32 GB (v5e), 95 GB (v5p) | 32 GB HBM (4.7x v5e perf) |
| **Interconnect** | PCIe Gen4 | NVLink 4 (900 GB/s) | NVLink 4 (900 GB/s) | ICI (Torus 3D mesh) | ICI (up to 256 chips/pod) |
| **Cross-Node Fabric**| Standard TCP/IP | GPUDirect RDMA (3.2 Tbps)| GPUDirect RDMA (6.4 Tbps)| Optical Circuit Switch (OCS) | Optical Circuit Switch (OCS) |
| **Next-Gen Counterpart**| — | — | NVIDIA Blackwell B200 (A4)| — | Scalable AI Hypercomputer |
| **Best Framework** | PyTorch, vLLM, TensorRT | Megatron-LM, NeMo, PyTorch| DeepSpeed, Megatron, vLLM | JAX, PyTorch/XLA, MaxText | JAX, PyTorch/XLA, MaxText |

---

## 2. Distributed AI Frameworks: Kueue, DWS, and Ray on GKE

### Dynamic Workload Scheduler (DWS)
Accelerator capacity for frontier AI/ML nodes (A3 Ultra, TPU pods) is in extreme global demand. Rather than suffering immediate pod scheduling rejections (`Insufficient nvidia.com/gpu`), GKE integrates **Dynamic Workload Scheduler (DWS)**:
- **Flex-Start Mode:** Allows queueing batch workloads with specified execution durations. GKE holds the job and provisions GPUs as soon as contiguous hardware capacity opens up in the region.
- **Calendar Mode:** Enables reserving dedicated GPU/TPU node pools ahead of time for deterministic training runs.

### Kueue: Multi-Tenant Batch Job Queueing
Standard Kubernetes schedules pods immediately or fails them if capacity is unavailable. In multi-team AI clusters:
- **Kueue** acts as a Kubernetes-native job queue manager.
- It pools available GPU/TPU capacity, enforces team-level quotas, and holds jobs in a `Queue` until all required accelerators are simultaneously available (**All-or-Nothing gang scheduling**), preventing deadlocks where Job A holds 4 GPUs and Job B holds 4 GPUs while both require 8 GPUs to train.

### Ray on GKE (KubeRay)
- **Ray** is the leading open-source framework for scaling Python and AI workloads (vLLM, Ray Train, Ray Data).
- The **KubeRay Operator** manages Ray clusters on GKE, dynamically orchestrating a Ray Head pod and autoscaling Ray Worker pods across heterogeneous GPU node pools.

---

## 3. Production Deployment & CLI Operations (`gcloud` & `kubectl`)

### 1. Provision a Multi-Host Cloud TPU v5e Node Pool

Deploy a 16-chip TPU slice (`v5litepod-16`) on a regional GKE cluster:

```bash
gcloud container node-pools create tpu-v5e-pool \
    --cluster=prod-regional-cluster \
    --region=us-central1 \
    --node-locations=us-central1-a \
    --machine-type=ct5lp-hightpu-4t \
    --tpu-topology=2x4 \
    --num-nodes=4 \
    --project=core-infrastructure-prod
```
*(Note: Cloud TPU slices are multi-host; all nodes in a slice must reside in the exact same physical zone).*

### 2. Deploy NVIDIA GPU Node Pool with GPUDirect RDMA (A3 Series)

```bash
gcloud container node-pools create a3-megagpu-pool \
    --cluster=prod-regional-cluster \
    --region=us-central1 \
    --node-locations=us-central1-a \
    --machine-type=a3-highgpu-8g \
    --accelerator=type=nvidia-h100-80gb-sxm5,count=8,gpu-driver-version=default \
    --enable-fast-socket \
    --num-nodes=2 \
    --node-taints="nvidia.com/gpu=present:NoSchedule" \
    --project=core-infrastructure-prod
```

### 3. Deploy KubeRay Operator on GKE

```bash
# Install KubeRay Operator via Helm
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

helm install kuberay-operator kuberay/kuberay-operator \
    --namespace kuberay-system \
    --create-namespace
```

### 4. Deploy a RayCluster with Distributed L4 GPU Workers

Create `ray-cluster-gpu.yaml`:

```yaml
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: ray-llm-serving
  namespace: ai-workloads
spec:
  rayVersion: '2.30.0'
  headGroupSpec:
    rayStartParams:
      dashboard-host: '0.0.0.0'
    template:
      spec:
        containers:
        - name: ray-head
          image: rayproject/ray-ml:2.30.0-py310-gpu
          resources:
            requests:
              cpu: "4"
              memory: "16Gi"
  workerGroupSpecs:
  - groupName: gpu-inference-workers
    replicas: 4
    minReplicas: 1
    maxReplicas: 10
    rayStartParams: {}
    template:
      spec:
        tolerations:
        - key: "nvidia.com/gpu"
          operator: "Equal"
          value: "present"
          effect: "NoSchedule"
        containers:
        - name: ray-worker
          image: rayproject/ray-ml:2.30.0-py310-gpu
          resources:
            limits:
              nvidia.com/gpu: "1"
              cpu: "8"
              memory: "32Gi"
            requests:
              nvidia.com/gpu: "1"
              cpu: "8"
              memory: "32Gi"
```

Apply RayCluster:

```bash
kubectl apply -f ray-cluster-gpu.yaml

# Verify Ray pods and GPU allocation
kubectl get pods -n ai-workloads -l ray.io/cluster=ray-llm-serving
```

### 5. Configure Kueue LocalQueue & ClusterQueue for Gang Scheduling

Create `kueue-config.yaml`:

```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: gpu-cluster-queue
spec:
  namespaceSelector: {} # Cluster-wide
  resourceGroups:
  - coveredResources: ["nvidia.com/gpu", "cpu", "memory"]
    flavors:
    - name: "h100-flavor"
      resources:
      - name: "nvidia.com/gpu"
        nominalQuota: 16 # 16 physical GPUs total quota
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: team-nlp-queue
  namespace: ai-workloads
spec:
  clusterQueue: gpu-cluster-queue
```

Apply Kueue configuration:

```bash
kubectl apply -f kueue-config.yaml
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Limit / Constraint | Engineering Guidance |
| :--- | :--- | :--- |
| **GPU Interconnect Speed** | 900 GB/s NVLink 4 | Enables ultra-fast tensor-parallel All-Reduce |
| **TPU ICI Latency** | Sub-microsecond | Direct optical connection bypassing TCP |
| **Max GPUs per Node** | 8 GPUs (A3 / A2) | 640 GB total VRAM on a single physical host |
| **Max Pods per TPU Slice** | 1 Pod per TPU VM host | Multi-host TPU jobs must use `Job` or `IndexedJob` |
| **GPUDirect RDMA** | Requires Fast Socket & VPC | Eliminates CPU copying during distributed training |

---

## 5. Official References & Documentation

- [GPUs on GKE Architecture Guide](https://cloud.google.com/kubernetes-engine/docs/concepts/gpus)
- [Cloud TPUs on GKE Architecture Guide](https://cloud.google.com/kubernetes-engine/docs/concepts/tpus)
- [KubeRay on GKE Documentation](https://cloud.google.com/kubernetes-engine/docs/add-on/ray-on-gke/concepts/overview)
- [Kueue Kubernetes Gang Scheduling](https://kueue.sigs.k8s.io/)
- [Google Cloud Machine Learning Pricing](https://cloud.google.com/compute/gpus-pricing)

---

## 6. Realistic Pricing Scenarios

Accelerator pricing is the largest component of AI cloud infrastructure bills:
- **NVIDIA L4 (24 GB):** ~$0.56 per GPU-hour.
- **NVIDIA A100 80GB SXM4:** ~$3.93 per GPU-hour.
- **NVIDIA H100 80GB SXM5:** ~$9.88 per GPU-hour.
- **Cloud TPU v5e:** ~$1.20 per chip-hour.

### Scenario A: High-Concurrency LLM Inference Serving (vLLM on NVIDIA L4)

- **Architecture:**
  - 8 nodes of `g2-standard-8` (each equipped with 1x NVIDIA L4 24GB GPU).
  - Serving open-source Llama-3-8B model with vLLM tensor optimizations.
  - Compute: 8 nodes × $0.842/hr ($0.56 GPU + $0.282 host VM) = $6.736/hr.
  - Running 24/7 across the month.
- **Monthly Cost Calculation:**
  - Host VM + L4 GPUs: $6.736/hr × 730 hrs = **$4,917.28**
  - Attached Balanced Disks (8 × 200 GB): 1,600 GB × $0.10 = **$160.00**
- **Total Monthly Cost:** **$5,077.28 / month**

### Scenario B: Distributed Foundation Model Fine-Tuning (Cloud TPU v5e 16-Chip Slice)

- **Architecture:**
  - 1 TPU v5e `v5litepod-16` slice (16 chips total = 4 host VMs of 4 chips each).
  - Running a 2-week continuous distributed fine-tuning job (336 hours).
  - Hourly rate: 16 chips × $1.20/chip-hr = $19.20/hr.
- **Monthly Cost Calculation:**
  - TPU Slice Compute: $19.20/hr × 336 hrs = **$6,451.20**
  - GCS FUSE dataset streaming (5 TB in-region): **$100.00**
- **Total Monthly Cost:** **$6,551.20 / month**
*(An identical 16-accelerator training run on A100 GPUs would cost ~$21,000.00, yielding a **69% cost reduction** using TPU v5e).*

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Distributed All-Reduce Deadlock (Gang Scheduling Requirement):** When running distributed data-parallel training (such as PyTorch DDP or DeepSpeed) across 16 GPUs, **every single worker process must initialize and connect simultaneously**. If your cluster only has 12 GPUs available, Kubernetes standard scheduling places 12 pods, while 4 pods remain `Pending`. The 12 running pods wait at the PyTorch `torch.distributed.init_process_group` barrier until the default 30-minute TCP timeout expires, crashing the job and burning thousands of dollars in idle GPU capacity. **Always use Kueue to enforce All-or-Nothing gang scheduling.**
2. **NVIDIA Driver Version Mismatch on Custom Images:** When adding a GPU node pool using Container-Optimized OS (COS), GKE automatically manages the NVIDIA kernel module. However, if you specify an Ubuntu image type without enabling automated driver installation, the host will boot without `/dev/nvidia0`. The Kubelet will register 0 allocatable GPUs, and GPU pods will be rejected with `0/10 nodes available: Insufficient nvidia.com/gpu`. Always set `--accelerator=...,gpu-driver-version=default`.
3. **Multi-Host TPU Slices Must Be Scheduled Together:** Unlike GPUs where individual cards can be scheduled independently across arbitrary nodes, a Cloud TPU v5e pod slice (e.g., `2x4` or `4x4`) is a **monolithic physical torus array**. You cannot deploy a single pod requesting 1 chip on a 16-chip multi-host node pool. Multi-host TPU jobs must use a Kubernetes `Job` or `IndexedJob` with `parallelism` equal to the number of host VMs in the TPU slice.
4. **Out-of-Memory (CUDA OOM) Kills Containers Without Warning:** When a neural network batch size exceeds GPU VRAM, NVIDIA CUDA triggers a fatal `CUDA out of memory` exception inside the Python process. Because this is an application exception and not an OS-level cgroup violation, Kubernetes does **not** report `OOMKilled` (Exit Code 137)—it reports standard application failure `Error (Exit Code 1)`. SREs frequently misdiagnose CUDA VRAM exhaustion as code bugs; always inspect container `stdout` for `torch.cuda.OutOfMemoryError`.
5. **Fast Socket Requirement for Multi-Node H100 Training:** When training across multiple A3 (H100) nodes, GKE includes a specialized network kernel plugin called **Fast Socket**. Fast Socket bypasses the Linux TCP stack to allow multi-stream communication directly over GPUDirect RDMA. If you build custom training container images that overwrite the base system dynamic linker (`LD_LIBRARY_PATH`), you can accidentally break Fast Socket libraries, causing cross-node gradient synchronization throughput to drop from 3.2 Tbps to standard 50 Gbps TCP rates.
6. **Spot GPU Preemption Cascades:** Running distributed training on Spot GPUs can reduce compute costs by 70%. However, if **one single Spot node in an 8-node training cluster is preempted**, the entire PyTorch DDP rank ring collapses, terminating the entire training run. When running training on Spot GPUs, you **must** configure frequent checkpointing (e.g., saving model weights to GCS via GCS FUSE every 15 minutes) and implement automated checkpoint recovery in code.

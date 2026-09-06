---
title: AKS GPU Orchestration for AI/ML — NVIDIA H100/A100, InfiniBand RDMA, and KubeRay
description: Exhaustive engineering guide to AI/ML accelerator infrastructure on AKS — NVIDIA NC/ND-series VMs (H100, H200, A100), automated GPU driver extensions, Quantum-2 3.2 Tbps InfiniBand GPUDirect RDMA, KubeRay operator, and vLLM model serving.
tags:
  - azure
  - aks
  - ai-ml
  - gpu
  - nvidia
  - infiniband
  - ray
  - llm
---

# AKS GPU Orchestration for AI/ML — NVIDIA H100/A100, InfiniBand RDMA, and KubeRay 🤖⚡

Azure Kubernetes Service is the flagship infrastructure foundation powering OpenAI, Microsoft Copilot, and enterprise frontier AI. Orchestrating machine learning workloads on AKS spans two distinct operational tiers: **low-cost inference clusters** utilizing **NVIDIA L4 / T4 (NCas_v3 / NCads_v4)**, and **massive distributed LLM foundation training supercomputers** utilizing **NVIDIA H100 / H200 (NDv5-series)** backed by **3.2 Tbps Quantum-2 InfiniBand GPUDirect RDMA**. Managing these accelerators requires deep Kubernetes integration with the **NVIDIA GPU Operator**, **KubeRay**, and modern LLM serving runtimes (e.g., **vLLM**).

---

## 1. Architecture: Azure AI Supercomputing Node (NDv5 / H100)

```
       ┌────────────────────────────────────────────────────────────────────────┐
       │ HOST COMPUTE NODE (Standard_ND96isr_H100_v5: 96 vCPUs / 1900 GiB RAM)  │
       │                                                                        │
       │  ┌──────────────────────┐  NVLink 4  ┌──────────────────────┐          │
       │  │ 8x NVIDIA H100 GPUs  │◄──────────►│ High-Speed Intra-Host│          │
       │  │ (80GB HBM3 each)     │  (900 GB/s)│ All-Reduce Sync      │          │
       │  └──────────┬───────────┘            └──────────────────────┘          │
       │             │ GPUDirect RDMA                                           │
       │             ▼                                                          │
       │  ┌──────────────────────────────────────────────────────────┐          │
       │  │ 8x 400 Gbps NVIDIA ConnectX-7 NICs (3.2 Tbps InfiniBand) │          │
       │  └──────────────────────────┬───────────────────────────────┘          │
       └─────────────────────────────┼──────────────────────────────────────────┘
                                     │ InfiniBand Quantum-2 Non-Blocking Fabric
                                     ▼ (Sub-microsecond latency)
       ┌────────────────────────────────────────────────────────────────────────┐
       │               AZURE INFINIBAND FABRIC (PEER GPU WORKERS)               │
       │  (Enables multi-node distributed training across thousands of GPUs)   │
       └────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Azure GPU Machine Series Taxonomy

| VM Family | GPU Accelerator | VRAM / GPU | Interconnect | Cross-Node Fabric | Primary AI Workload |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **NCas_T4_v3** | 1–4x NVIDIA T4 | 16 GB GDDR6 | PCIe Gen3 | Standard Ethernet | Classical Vision & Embedding Inference |
| **NC_A100_v4** | 1–2x NVIDIA A100 | 40 GB or 80 GB | PCIe Gen4 | Standard Ethernet | Mid-Scale Fine-Tuning & Serving |
| **NDv4_A100** | 8x NVIDIA A100 SXM4| 80 GB HBM2e | NVLink 3 (600 GB/s) | 8x 200 Gbps HDR InfiniBand | Distributed Pre-Training (Megatron) |
| **NDv5_H100** | 8x NVIDIA H100 SXM5| 80 GB HBM3 | NVLink 4 (900 GB/s) | **8x 400 Gbps NDR InfiniBand** | **Frontier LLM Training (GPT-4 class)**|
| **NDv5_H200** | 8x NVIDIA H200 SXM5| **141 GB HBM3e** | NVLink 4 (900 GB/s) | **8x 400 Gbps NDR InfiniBand** | **Ultra-Long-Context Frontier LLMs** |

---

## 3. GPU Driver Strategy: Managed AKS Extension vs. NVIDIA GPU Operator

AKS offers two methods to install NVIDIA kernel drivers and CUDA runtimes:

1. **AKS Automated GPU Driver Extension (`--enable-gpu-driver`):**
   - Microsoft automatically builds, packages, and injects validated NVIDIA proprietary drivers directly into the node image during VMSS creation.
   - Recommended for standard production setups: eliminates Helm operator overhead and guarantees compatibility with the host kernel.
2. **NVIDIA GPU Operator:**
   - Deploys as an in-cluster Helm chart managing the containerized NVIDIA driver, `k8s-device-plugin`, DCGM metrics exporter, and GPU feature discovery.
   - Required for specialized configurations (e.g., MIG partitioning, custom vGPU licensing).

---

## 4. Production Deployment & CLI Operations (`az` CLI & `kubectl`)

### 1. Provision a Dedicated GPU Node Pool with Automated Driver Extension

```bash
# Add a multi-GPU user node pool running NC_A100_v4 with automated driver installation
az aks nodepool add \
    --resource-group rg-prod-ai \
    --cluster-name aks-ai-cluster \
    --name a100pool \
    --node-vm-size Standard_NC24ads_A100_v4 \
    --os-sku Ubuntu \
    --node-count 2 \
    --enable-gpu-driver \
    --node-taints "sku=gpu:NoSchedule" \
    --labels accelerator=nvidia-a100 workload=llm-serving \
    --node-osdisk-type Ephemeral \
    --node-osdisk-size 100
```

### 2. Verify GPU Device Allocation on Nodes

```bash
# Verify NVIDIA GPU device plugin has registered resources with the API server
kubectl describe nodes -l accelerator=nvidia-a100 | grep -A 6 "Allocatable:"
# Expected Output: nvidia.com/gpu: 1
```

### 3. Deploy Production vLLM LLM Inference Server with GPU Acceleration

Deploy a production LLM serving container (e.g., Mistral-7B or Llama-3-8B) with **vLLM** for continuous batching and PagedAttention:

Create `vllm-mistral-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-mistral-serving
  namespace: ai-serving
spec:
  replicas: 2
  selector:
    matchLabels:
      app: vllm-mistral
  template:
    metadata:
      labels:
        app: vllm-mistral
    spec:
      tolerations:
      - key: "sku"
        operator: "Equal"
        value: "gpu"
        effect: "NoSchedule"
      nodeSelector:
        accelerator: nvidia-a100
      containers:
      - name: vllm-engine
        image: vllm/vllm-openai:v0.4.0
        args:
        - "--model"
        - "mistralai/Mistral-7B-Instruct-v0.2"
        - "--tensor-parallel-size"
        - "1"
        - "--gpu-memory-utilization"
        - "0.90"
        - "--max-model-len"
        - "8192"
        resources:
          limits:
            nvidia.com/gpu: "1"
            memory: "32Gi"
            cpu: "8"
          requests:
            nvidia.com/gpu: "1"
            memory: "16Gi"
            cpu: "4"
        ports:
        - containerPort: 8000
          name: http
        volumeMounts:
        - name: model-cache
          mountPath: /root/.cache/huggingface
      volumes:
      - name: model-cache
        emptyDir:
          medium: Memory
```

Apply deployment:

```bash
kubectl apply -f vllm-mistral-deployment.yaml
```

---

## 5. Quotas, Performance & Configuration Limits

| Dimension | Limit / Metric | Production Constraint |
| :--- | :--- | :--- |
| **InfiniBand Network Bandwidth**| **3.2 Tbps (NDv5)** | 8x 400 Gbps ConnectX-7 adapters operating concurrently |
| **Max GPUs per Node** | **8x H100 / H200** | Full NVLink 4 mesh with 900 GB/s bidirectional throughput |
| **Regional GPU Quota** | Subscription Bound | Request N-series vCPU quota increases via Azure Support |
| **InfiniBand Driver (OFED)** | Mandatory MLNX_OFED | Automatically configured on Ubuntu HPC node images |
| **Multi-Instance GPU (MIG)** | Up to 7 instances per A100 | Slices 80 GB A100 into 7x 10 GB independent vGPUs |

---

## 6. Official References

- [Use GPUs on AKS (Automated Driver Extension)](https://learn.microsoft.com/en-us/azure/aks/gpu-cluster)
- [Azure ND H100 v5 Machine Architecture](https://learn.microsoft.com/en-us/azure/virtual-machines/nd-h100-v5-series)
- [KubeRay on Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/aks/ray-operator)
- [Azure Virtual Machines Pricing (N-Series GPUs)](https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/#n-series)

---

## 7. Realistic Pricing Scenarios

### Scenario A: Enterprise LLM Serving Cluster (2x A100 GPUs 24/7)

- **Compute Profile:**
  - 2x `Standard_NC24ads_A100_v4` nodes (1x 80GB A100 GPU each, ~$3.67/hr per node).
  - Continuous hosting of internal enterprise copilot / RAG pipelines.
- **Monthly Cost Breakdown:**
  - GPU Compute Nodes: 2 × $3.67/hr × 730 hrs = **$5,358.20**
  - Ephemeral OS Disks: **$0.00**
  - Control Plane Fee: **$73.00**
  - Azure Key Vault & Container Registry: ~$25.00
- **Total Monthly Spend:** **$5,456.20 / month** *(Eligible for 1-yr Savings Plan discount to ~$3,800/mo).*

### Scenario B: Multi-Node Frontier Fine-Tuning Run (Spot NDv5 H100 Cluster)

- **Compute Profile:**
  - 4x `Standard_ND96isr_H100_v5` instances (32 total NVIDIA H100 GPUs).
  - Distributed 48-hour fine-tuning job running over the weekend using InfiniBand.
  - Standard Pay-As-You-Go rate: ~$40.00/hr per instance.
- **Run Cost Breakdown:**
  - GPU Compute (48 hours): 4 nodes × $40.00/hr × 48 hrs = **$7,680.00**
  - High-Performance Blob Storage (Model Checkpoints): ~$50.00
- **Total Job Spend:** **$7,730.00 for the full distributed training run**

---

## 8. Battle-Tested Nuggets & Production Gotchas

1. **The Regional GPU Quota Silent Failure:** By default, new Azure enterprise subscriptions have a **quota of 0 vCPUs for the NC-family and ND-family**. Attempting to add a GPU node pool via the `az aks nodepool add` CLI will succeed in sending the request to ARM, but the deployment will fail 10 minutes later with `QuotaExceeded: The quota for N-family vCPUs in region eastus is 0`. You must proactively submit an Azure Support quota increase request weeks before procurement.
2. **PyTorch NCCL InfiniBand vs Ethernet Hangs:** In multi-node distributed training runs across NDv5 clusters, if the NVIDIA Collective Communications Library (`NCCL`) is misconfigured, worker pods will fail to detect the InfiniBand Mellanox interfaces (`ib0`, `ib1`) and fall back to standard Azure VNet Ethernet (`eth0`). Cross-node All-Reduce operations will experience an **80x throughput drop**, causing distributed training to hang or time out. Always verify that pods inject environment variables `NCCL_IB_DISABLE=0` and `NCCL_NET_GDR_LEVEL=5`.
3. **MIG Slicing Taints Prevent Standard Pod Scheduling:** If you partition an A100 GPU into Multi-Instance GPU (MIG) slices (e.g., `1g.10gb`), the Kubernetes node labels mutate to expose `nvidia.com/mig-1g.10gb` instead of `nvidia.com/gpu`. Any deployment requesting standard `nvidia.com/gpu` will remain in a permanent `Pending` state. Update workload manifests to request the exact MIG slice resource identifier.
4. **Host Caching Prohibited on GPU VM Disks:** Similar to high-performance database disks, attaching Azure Managed Disks to N-series GPU worker nodes requires setting host caching to `None`. Attempting to mount data disks with `ReadWrite` caching enabled can cause I/O lockups when CUDA kernels execute direct DMA memory transfers.
5. **GPU Driver Kernel Mismatch during Ubuntu Auto-Patches:** If you run the unmanaged node OS upgrade channel (`--node-os-upgrade-channel Unmanaged`), the underlying Ubuntu VM will run `unattended-upgrades`, updating the Linux kernel from `5.15.0-88` to `5.15.0-91`. If the NVIDIA kernel module was built against the older kernel headers, **the GPU driver crashes upon reboot**, leaving `nvidia.com/gpu: 0` allocatable. **Always use `--node-os-upgrade-channel NodeImage` to ensure the entire VHD (kernel + NVIDIA driver) is upgraded as a pre-tested atomic unit.**

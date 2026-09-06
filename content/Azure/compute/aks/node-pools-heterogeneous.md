---
title: AKS Heterogeneous Node Pools — System vs User, Ephemeral OS Disks, and Azure Linux
description: Exhaustive engineering guide to AKS worker nodes — System vs User pools, Ephemeral OS disks on NVMe/Cache, Azure Linux 3 vs Ubuntu, custom Kubelet/sysctl configurations, and Spot VM pool architectures.
tags:
  - azure
  - aks
  - compute
  - node-pools
  - ephemeral-os
  - azure-linux
  - spot-vms
  - vmss
---

# AKS Heterogeneous Node Pools — System vs User, Ephemeral OS Disks, and Azure Linux 🖥️⚡

In production Kubernetes environments, a single homogeneous worker node pool cannot efficiently satisfy the disparate computing, storage, and isolation demands of modern cloud architectures. Running microservices, in-memory databases, batch ML jobs, and cluster system daemons on the same node configuration leads to **resource starvation, noisy-neighbor contention, and bloated cloud bills**. AKS solves this through **Heterogeneous Node Pools**, allowing platform teams to combine **System Node Pools**, **User Node Pools**, **Ephemeral OS Disks**, **Azure Linux 3**, and **Spot VM Scale Sets** into a cohesive cluster.

---

## 1. Architecture: Heterogeneous Node Pool Topology

```
                                AKS PRODUCTION CLUSTER
                                          │
       ┌──────────────────────────────────┼──────────────────────────────────┐
       │                                  │                                  │
       ▼                                  ▼                                  ▼
┌─────────────────────────────┐ ┌─────────────────────────────┐ ┌─────────────────────────────┐
│   SYSTEM NODE POOL (3 AZs)  │ │   USER NODE POOL (General)  │ │   SPOT BATCH POOL (Scale-0) │
│   - Purpose: Cluster Daemons│ │   - Purpose: Microservices  │ │   - Purpose: Async Jobs     │
│   - VM: Standard_D4ds_v5    │ │   - VM: Standard_D8ds_v5    │ │   - VM: Standard_D16ds_v5   │
│   - OS: Azure Linux 3       │ │   - OS: Azure Linux 3       │ │   - Priority: Spot (80% Off)│
│   - Disk: Ephemeral (NVMe)  │ │   - Disk: Ephemeral (Cache) │ │   - Eviction: Delete        │
│   - Taint:                  │ │   - Taint: None             │ │   - Taint:                  │
│     CriticalAddonsOnly=true │ │                             │ │     spot=true:NoSchedule    │
└──────────────┬──────────────┘ └──────────────┬──────────────┘ └──────────────┬──────────────┘
               │                               │                               │
               ▼ Runs Core System Pods         ▼ Runs Customer Microservices   ▼ Runs Batch Compute
       ┌────────────────────────┐      ┌────────────────────────┐      ┌────────────────────────┐
       │ - CoreDNS              │      │ - Order Service        │      │ - Video Transcoding    │
       │ - konnectivity-agent   │      │ - Payment API          │      │ - Financial Risk Sim   │
       │ - metrics-server       │      │ - User Profile Cache   │      │ - Model Training Run   │
       │ - azure-cni-overlay    │      │ - Kafka Producer Pods  │      │ - Data Pipeline ETL    │
       └────────────────────────┘      └────────────────────────┘      └────────────────────────┘
```

---

## 2. Core Architectural Components

### 1. System Node Pools vs. User Node Pools
- **System Node Pool:**
  - Dedicated strictly to running cluster-critical control pods (`CoreDNS`, `konnectivity-agent`, `metrics-server`).
  - Microsoft enforces a minimum of 1 node (3 nodes across 3 AZs strongly recommended in production).
  - Automatically tainted with `CriticalAddonsOnly=true:NoSchedule` to prevent developer applications from monopolizing resources and destabilizing DNS resolution.
- **User Node Pools:**
  - Dedicated to customer business applications, APIs, databases, and batch pipelines.
  - Can be scaled to zero when idle (`min-count: 0`).
  - Support arbitrary VM families (Compute-optimized F-series, Memory-optimized E-series, GPU-accelerated NC-series).

### 2. Ephemeral OS Disks: NVMe vs. VM Cache
Traditional AKS nodes boot from a remote Azure Managed Disk (Persistent OS Disk), incurring network IOPS bottlenecks, 5–10 minute re-imaging delays, and monthly disk storage fees.
- **Ephemeral OS Disks:**
  - The node's operating system is written directly to the host VM's local physical NVMe or SSD cache.
  - **Performance:** Line-speed disk I/O with near-zero latency, enabling nodes to re-image and autoscale in **under 45 seconds**.
  - **Cost:** **100% Free** (incurs $0 in storage disk costs).
  - **Placement Types:**
    - `CacheDisk`: Placed in the VM's unmanaged OS cache space (standard on D-series and E-series).
    - `NvmeDisk`: Placed on high-speed physical NVMe drives (available on modern L-series and v5 NVMe shapes).

### 3. Operating System: Azure Linux 3 vs. Ubuntu
- **Ubuntu 22.04:** Broad ecosystem compatibility, standard general-purpose distribution.
- **Azure Linux 3 (formerly CBL-Mariner):**
  - Microsoft's enterprise-grade, security-hardened Linux distribution engineered specifically for AKS container hosts.
  - **Minimal Attack Surface:** Stripped of unnecessary packages, legacy utilities, and background daemons.
  - **Faster Boot Times:** Smaller image size accelerates autoscaling node spin-up by up to 25%.
  - **Rapid CVE Patching:** Direct kernel patches authored and verified by Microsoft OS engineers.

---

## 3. Production Deployment & CLI Operations (`az` CLI)

### 1. Add an Optimized User Node Pool with Ephemeral OS Disks & Azure Linux

```bash
# Add multi-zone User Node Pool running Azure Linux 3 and Ephemeral OS Disks
az aks nodepool add \
    --resource-group rg-prod-aks \
    --cluster-name aks-core-prod \
    --name userpool01 \
    --mode User \
    --os-sku AzureLinux \
    --node-vm-size Standard_D8ds_v5 \
    --node-osdisk-type Ephemeral \
    --node-osdisk-size 100 \
    --zones 1 2 3 \
    --enable-cluster-autoscaler \
    --min-count 3 \
    --max-count 30 \
    --max-pods 110
```

### 2. Add a Cost-Optimized Spot Node Pool for Batch Workloads

```bash
# Add Spot VM pool scaling to zero with automated taints and Delete eviction
az aks nodepool add \
    --resource-group rg-prod-aks \
    --cluster-name aks-core-prod \
    --name spotbatch \
    --mode User \
    --priority Spot \
    --eviction-policy Delete \
    --spot-max-price -1 \
    --os-sku AzureLinux \
    --node-vm-size Standard_D16ds_v5 \
    --node-osdisk-type Ephemeral \
    --enable-cluster-autoscaler \
    --min-count 0 \
    --max-count 20 \
    --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule" \
    --labels workload=batch-compute tier=spot
```

### 3. Apply Custom Kubelet & Linux Sysctl Configuration

Fine-tune kernel networking and memory swapping for high-throughput in-memory caching:

```bash
# Create custom node config JSON
cat <<EOF > custom-node-config.json
{
  "sysctls": {
    "netCoreSomaxconn": 16384,
    "netIpv4TcpTwReuse": true,
    "vmMaxMapCount": 262144
  },
  "kubeletConfig": {
    "cpuManagerPolicy": "static",
    "imageGcHighThresholdVirtual": 80,
    "imageGcLowThresholdVirtual": 70
  }
}
EOF

# Add specialized high-performance node pool applying sysctl settings
az aks nodepool add \
    --resource-group rg-prod-aks \
    --cluster-name aks-core-prod \
    --name cachepool \
    --node-vm-size Standard_E8ds_v5 \
    --node-osdisk-type Ephemeral \
    --kubelet-config custom-node-config.json \
    --linux-os-config custom-node-config.json \
    --min-count 3 \
    --max-count 6
```

---

## 4. Quotas, Performance & Configuration Limits

| Architectural Parameter | Platform Limit | Production Rule |
| :--- | :--- | :--- |
| **Max Node Pools per Cluster**| **100 Node Pools** | Segregate by workload type (General, In-Memory, GPU, Spot)|
| **Min System Node Pool Size**| **1 Node** | Minimum 3 nodes across 3 AZs required for production HA |
| **Ephemeral OS Min VM Size** | **Standard_D4ds_v5** | VM cache must exceed requested OS disk size (e.g., ≥ 64 GB) |
| **Spot Node Eviction Notice** | **30 Seconds** | Azure Scheduled Events API alerts host prior to reclamation |
| **Max Pods per Node Pool** | **250 Pods** | Configurable via `--max-pods` flag |

---

## 5. Official References

- [Manage System and User Node Pools in AKS](https://learn.microsoft.com/en-us/azure/aks/use-system-pools)
- [Ephemeral OS Disks for AKS Nodes](https://learn.microsoft.com/en-us/azure/aks/cluster-configuration#ephemeral-os)
- [Use Azure Linux Container Host for AKS](https://learn.microsoft.com/en-us/azure/aks/use-azure-linux)
- [Custom Node Configuration (Sysctl & Kubelet)](https://learn.microsoft.com/en-us/azure/aks/custom-node-configuration)

---

## 6. Realistic Pricing Scenarios

### Scenario A: Enterprise Workload with Ephemeral OS Disks

- **Configuration:** 30 nodes using `Standard_D8ds_v5` (8 vCPU, 32 GiB RAM).
- **Storage Cost Comparison:**
  - *Option 1 (Traditional Managed OS Disks):* 30 nodes × 128 GiB Premium SSD (P10 disk @ $19.71/mo) = **$591.30 / month in storage waste**.
  - *Option 2 (Ephemeral OS Disks on Local Cache):* **$0.00 storage cost**.
- **Monthly Compute Spend:**
  - Compute Nodes: 30 × $0.384/hr × 730 hrs = **$8,409.60**
  - OS Disks: **$0.00**
  - Control Plane Fee: **$73.00**
- **Total Monthly Spend:** **$8,482.60 / month** *(Directly saving $7,000+ annually on disk fees alone).*

### Scenario B: Nightly Batch Processing on Spot Pools (Scale to Zero)

- **Configuration:**
  - Baseline: System Node Pool (3x `Standard_D4ds_v5` @ $0.192/hr = $420.48/mo).
  - Batch Pool: 20x `Standard_D16ds_v5` (16 vCPU, 64 GiB RAM) running 4 hours nightly on Spot (~$0.1536/hr, 80% discount).
- **Monthly Compute Spend:**
  - System Pool (24/7): 3 × $0.192/hr × 730 hrs = **$420.48**
  - Spot Batch Nodes (120 hrs/mo): 20 × $0.1536/hr × 120 hrs = **$368.64**
  - Standard Control Plane: **$73.00**
- **Total Monthly Spend:** **$862.12 / month** *(Compared to $1,900+ on full-price On-Demand).*

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The System Node Pool Taint Erasure Bug:** When adding a new system node pool or altering an existing one via the Azure Portal or ARM templates, engineers occasionally omit `--node-taints CriticalAddonsOnly=true:NoSchedule`. Without this taint, the Kubernetes scheduler treats system nodes as general compute, flooding them with heavy application pods. When an application leaks memory, `CoreDNS` is evicted, causing **total cluster DNS outage**. Always verify taints with `kubectl describe nodes -l kubernetes.azure.com/mode=system`.
2. **Ephemeral OS Disk Provisioning Failures on Resized VMs:** If an existing node pool is resized to a different VM SKU with a smaller temporary disk cache than the configured `--node-osdisk-size`, Azure rejects the operation with `OperationNotAllowed: Ephemeral disk size exceeds VM cache size`. Always check Azure VM specs to verify `MaxResourceVolumeMB` or `CachedDiskBytes` before configuring OS disk size.
3. **Spot Eviction Handling with Azure Scheduled Events:** When Azure needs Spot capacity back, it provides only a **30-second warning** via the Azure Instance Metadata Service (IMDS). Standard Kubernetes drain operations take longer than 30 seconds. Deploy the **Azure Node Termination Handler (or AKS Spot Node Drainer)** to intercept IMDS preemption events, issue immediate `cordon`, and send `SIGTERM` signals before Azure violently powers off the VM.
4. **Arm64 Architecture Node Pool Scheduling Conflicts:** Deploying Ampere Altra Arm-based VM shapes (e.g., `Standard_D8ps_v5`) provides extraordinary price-performance. However, if microservices are built solely for `linux/amd64`, pods scheduled onto Arm nodes will fail with `CrashLoopBackOff (exec format error)`. Ensure your CI/CD builds multi-arch container images (`docker buildx`) and declare `nodeSelector: kubernetes.io/arch: arm64` explicitly.
5. **System Node Pool Cannot Be Deleted While Active:** An AKS cluster must always possess at least one operational System Node Pool. Attempting to run `az aks nodepool delete --name systempool` will fail with an error. To migrate system pods to a new VM shape, you must create a *second* System Node Pool (`--mode System`), wait for all core add-ons to migrate, and only then delete the original pool.

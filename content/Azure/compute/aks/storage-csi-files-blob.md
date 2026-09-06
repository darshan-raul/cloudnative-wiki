---
title: AKS Shared Storage CSI — Azure Files (NFS/SMB) and Azure Blob CSI Architecture
description: Exhaustive engineering guide to multi-pod ReadWriteMany (RWX) storage on AKS — Azure Files CSI driver (NFS v4.1 vs SMB), Azure Blob Storage CSI driver (BlobFuse2 vs NFS v3), POSIX compatibility, and high-throughput AI streaming.
tags:
  - azure
  - aks
  - storage
  - csi
  - azure-files
  - azure-blob
  - rwx
  - nfs
---

# AKS Shared Storage CSI — Azure Files (NFS/SMB) and Azure Blob CSI Architecture 📂⚡

While block storage (Azure Disks) excels at single-node high-performance databases, enterprise architectures frequently require **ReadWriteMany (RWX)** storage volumes where hundreds of pods across multiple worker nodes concurrently read and write to the same shared directory. Common workloads include **web content management (WordPress/Drupal), shared report generation, ML model artifact sharing, and distributed AI training pipelines**. AKS solves this through two native storage plugins: the **Azure Files CSI Driver (NFS v4.1 & SMB)** and the **Azure Blob Storage CSI Driver (BlobFuse2 & NFS v3)**.

---

## 1. Architecture: The Shared Multi-Pod Storage Plane

```
       APPLICATION REPLICAS SPREAD ACROSS 3 AVAILABILITY ZONES
       ┌────────────────────────┐  ┌────────────────────────┐  ┌────────────────────────┐
       │ Pod 1 (Node in Zone 1) │  │ Pod 2 (Node in Zone 2) │  │ Pod 3 (Node in Zone 3) │
       └───────────┬────────────┘  └───────────┬────────────┘  └───────────┬────────────┘
                   │ Concurrent RWX Mount      │ Concurrent RWX Mount      │ Concurrent RWX Mount
                   ▼                           ▼                           ▼
       ┌────────────────────────────────────────────────────────────────────────────────┐
       │                PERSISTENT VOLUME CLAIM (PVC): AccessMode: ReadWriteMany        │
       └───────────────────────────────────────┬────────────────────────────────────────┘
                                               │
               ┌───────────────────────────────┴───────────────────────────────┐
               ▼ Option A: Low Latency / File Locks                            ▼ Option B: Massive Scale / AI
       ┌──────────────────────────────────────────────┐ ┌──────────────────────────────────────────────┐
       │            AZURE FILES CSI DRIVER            │ │            AZURE BLOB CSI DRIVER             │
       │                                              │ │                                              │
       │  - Protocol: NFS v4.1 or SMB 3.0             │ │  - Protocol: BlobFuse2 (FUSE) or NFS v3      │
       │  - Full POSIX file locking & permissions     │ │  - Direct object storage streaming           │
       │  - Premium Tier: 100,000 IOPS / 10 GB/s      │ │  - Petabyte scale at lowest cost/GB          │
       │  - Best for: Web CMS, legacy enterprise apps │ │  - Best for: AI/ML training dataset streaming│
       └──────────────────────┬───────────────────────┘ └──────────────────────┬───────────────────────┘
                              │ Wire-Speed VNet Transit                        │ Wire-Speed VNet Transit
                              ▼                                                ▼
       ┌──────────────────────────────────────────────┐ ┌──────────────────────────────────────────────┐
       │          AZURE STORAGE ACCOUNT (NFS)         │ │          AZURE DATA LAKE STORAGE GEN2        │
       └──────────────────────────────────────────────┘ └──────────────────────────────────────────────┘
```

---

## 2. Storage Comparison: Azure Files vs. Azure Blob Storage

| Feature / Metric | Azure Files (NFS v4.1) | Azure Files (SMB 3.0) | Azure Blob (BlobFuse2) | Azure Blob (NFS v3) |
| :--- | :--- | :--- | :--- | :--- |
| **Kubernetes AccessMode**| **ReadWriteMany (RWX)** | **ReadWriteMany (RWX)** | **ReadWriteMany (RWX)** | **ReadWriteMany (RWX)** |
| **POSIX Compatibility** | **Full POSIX** (chown/chmod) | Windows ACLs / Linux GID | Near-POSIX (Emulated via FUSE)| Partial POSIX |
| **File Locking Support** | **Native fcntl / flock** | Native SMB oplocks | Limited / Weak locks | Weak locks |
| **Max Capacity per Share**| **100 TiB** | **100 TiB** | **Petabytes (Unlimited)** | **Petabytes (Unlimited)** |
| **Max IOPS per Share** | **Up to 100,000 IOPS** | **Up to 100,000 IOPS** | High (Multi-part parallel) | High (Multi-part parallel) |
| **Authentication Mode** | Private VNet IP / Private Link| Storage Account Access Key | Managed Identity / Workload ID | Private VNet IP / Private Link|
| **Cost Profile** | Moderate ($0.16/GiB Premium) | Moderate ($0.16/GiB Premium)| **Ultra-Low ($0.018/GiB Hot)** | **Ultra-Low ($0.018/GiB Hot)** |

---

## 3. Production Deployment & CLI Operations (`az` CLI & `kubectl`)

### 1. Enable Azure Files and Azure Blob CSI Drivers on AKS

Modern AKS clusters enable both CSI drivers by default. To verify or activate them:

```bash
# Verify CSI storage drivers on existing cluster
az aks update \
    --resource-group rg-prod-storage \
    --name aks-core-prod \
    --enable-blob-driver \
    --enable-disk-driver \
    --enable-file-driver
```

### 2. Deploy Azure Files NFS v4.1 StorageClass (Full Linux POSIX)

Create `storageclass-azurefile-nfs.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azurefile-premium-nfs
provisioner: file.csi.azure.com
mountOptions:
  - nconnect=4 # Multiplex up to 4 TCP connections for 4x throughput!
  - noresvport
  - actimeo=30
parameters:
  protocol: nfs
  skuName: Premium_LRS # NFS requires Premium tier
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: Immediate
```

### 3. Deploy Azure Blob CSI StorageClass with BlobFuse2 Caching for AI/ML

Create `storageclass-blobfuse2.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: blobfuse2-ai-datasets
provisioner: blob.csi.azure.com
mountOptions:
  - -o allow_other
  - --file-cache-timeout-in-seconds=120
  - --use-adls=true
parameters:
  skuName: Standard_LRS
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: Immediate
```

### 4. Deploy Multi-Pod Web Application with Shared RWX Volume

Create `shared-web-deployment.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-content-pvc
  namespace: web
spec:
  accessModes:
  - ReadWriteMany
  storageClassName: azurefile-premium-nfs
  resources:
    requests:
      storage: 500Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
  namespace: web
spec:
  replicas: 5 # 5 concurrent pods mounting the identical NFS directory
  selector:
    matchLabels:
      app: web-frontend
  template:
    metadata:
      labels:
        app: web-frontend
    spec:
      containers:
      - name: nginx
        image: mcr.microsoft.com/oss/nginx/nginx:1.25.3
        volumeMounts:
        - name: shared-storage
          mountPath: /usr/share/nginx/html/assets
      volumes:
      - name: shared-storage
        persistentVolumeClaim:
          claimName: shared-content-pvc
```

Apply manifests:

```bash
kubectl apply -f storageclass-azurefile-nfs.yaml
kubectl apply -f storageclass-blobfuse2.yaml
kubectl apply -f shared-web-deployment.yaml
```

---

## 4. Quotas, Performance & Configuration Limits

| Dimension | Metric / Hard Limit | Production Impact |
| :--- | :--- | :--- |
| **Azure Files Share Max Size** | **100 TiB (102,400 GiB)** | Provisioned capacity on Premium tier |
| **Max Open Files per Share** | **1,000,000 handles** | High-concurrency web servers |
| **Max Throughput (NFS Share)** | **10,340 MB/s (10 GB/s)** | Achieved using `nconnect=4` mount flag |
| **Max Single File Size (Blob)** | **190.7 TiB** | Block blob maximum size for LLM weights |
| **Blob CSI Mount Protocol** | **BlobFuse2 (FUSE daemon)** | Operates inside container user space |

---

## 5. Official References

- [Azure Files CSI Driver on AKS](https://learn.microsoft.com/en-us/azure/aks/azure-files-csi)
- [Use Azure Blob Storage CSI Driver on AKS](https://learn.microsoft.com/en-us/azure/aks/azure-blob-csi)
- [NFS v4.1 Performance Tuning in Azure Files](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-how-to-mount-nfs-share)
- [Azure Files Pricing](https://azure.microsoft.com/en-us/pricing/details/storage/files/)

---

## 6. Realistic Pricing Scenarios

### Scenario A: High-Concurrency Enterprise Web Cluster (500 GiB Premium NFS)

- **Storage Profile:**
  - 500 GiB provisioned on Azure Files Premium NFS (`azurefile-premium-nfs`).
  - Mounted concurrently by 10 frontend web pods across 3 zones.
- **Monthly Cost Breakdown:**
  - Provisioned Storage (500 GiB): 500 × $0.16/GiB = **$80.00**
  - Included Baseline IOPS: 400 + (1 × 500) = 900 IOPS (Free).
  - Included Baseline Throughput: 100 MB/s + (0.1 × 500) = 150 MB/s (Free).
  - Data Transactions: **$0.00** (Included in Premium provisioned model).
- **Total Monthly Storage Cost:** **$80.00 / month**

### Scenario B: Massive Computer Vision Training Dataset (50 TiB Blob Storage)

- **Storage Profile:**
  - 50 TiB (51,200 GiB) of training images stored in Azure Data Lake Storage Gen2 (Standard Hot).
  - Mounted via Azure Blob CSI with BlobFuse2 on 8x GPU nodes.
- **Monthly Cost Breakdown:**
  - Blob Storage Capacity (50 TiB): 51,200 GiB × $0.018/GiB = **$921.60**
  - Read Operations (5,000,000 reads): 50 × $0.004 per 10,000 = **$2.00**
  - VNet Data Transfer (Within same Azure region): **$0.00**
- **Total Monthly Storage Cost:** **$923.60 / month** *(Compared to $8,192/mo if stored on Premium Files).*

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The SMB Port 445 Blocking Outage:** Azure Files using SMB 3.0 communicates over TCP port 445. If your AKS worker nodes live in a secured corporate VNet where Network Security Groups (NSGs) or corporate firewalls block outbound port 445 to the internet, SMB mounts will hang indefinitely with `Connection timed out`. **For Linux clusters, always use NFS v4.1 over private VNet endpoints to eliminate port 445 dependencies.**
2. **NFS v4.1 Root Squashing and File Permissions:** By default, Azure Files NFS shares enforce root squashing (mapping UID `0` to `nobody`). If a container running as root (`UID 0`) attempts to create directories or initialize a database, the mount will fail with `Permission denied`. You must explicitly configure UID/GID parameters in the container's `securityContext` or mount with `actimeo=30`.
3. **BlobFuse2 Memory Bloat on Large Parallel Writes:** When pods write massive multi-gigabyte files to a Blob CSI volume, BlobFuse2 buffers data chunks in the container's local memory or temporary local disk before flushing them as block blobs to Azure. If container memory limits are tightly constrained (e.g., 2 GiB), the pod will be abruptly killed with **`OOMKilled (Exit Code 137)`**. Configure `--file-cache-timeout-in-seconds` and allocate adequate memory requests.
4. **NFS Multiplexing with `nconnect=4`:** Default Linux NFS mount parameters establish only a single TCP connection between a worker node and the Azure Storage account, capping throughput at ~1.5 Gbps. Adding the mount option `nconnect=4` to your StorageClass instructs the Linux kernel to open **4 parallel TCP connections**, quadrupling single-node network throughput to over 6 Gbps.
5. **Storage Account Name 24-Character Limit Collision:** When Azure Files or Blob CSI dynamically provisions a dedicated Storage Account on demand, it derives the name by hashing the cluster and PVC metadata. Storage Account names must be globally unique across all of Azure and strictly **under 24 alphanumeric characters**. If an AKS cluster name is exceptionally long, automated name generation can truncate awkwardly or fail. Use pre-provisioned Storage Accounts for critical enterprise state.

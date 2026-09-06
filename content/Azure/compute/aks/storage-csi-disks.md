---
title: AKS Storage CSI Architecture — Azure Managed Disks, Premium SSD v2, and Elastic SAN
description: Exhaustive engineering guide to stateful block storage on AKS — Azure Disk CSI driver (v2), Premium SSD v2, Ultra Disk, Azure Elastic SAN, online volume expansion, volume snapshots, and RWO failover tuning.
tags:
  - azure
  - aks
  - storage
  - csi
  - disks
  - stateful
  - elastic-san
---

# AKS Storage CSI Architecture — Azure Managed Disks, Premium SSD v2, and Elastic SAN 💽📦

Running mission-critical stateful workloads (PostgreSQL, Cassandra, Kafka, Elasticsearch, Redis) on Azure Kubernetes Service (AKS) requires predictable IOPS, sub-millisecond latency, and rapid failover recovery. AKS provides this block storage foundation via the **Azure Disk Container Storage Interface (CSI) Driver (v2)**. By bridging the Kubernetes `PersistentVolumeClaim` (PVC) API with Azure Managed Disks, platform teams can dynamically provision **Premium SSD**, configurable **Premium SSD v2**, ultra-low-latency **Ultra Disk**, and multi-terabyte **Azure Elastic SAN** volumes.

---

## 1. Architecture: The Azure Disk CSI Storage Pipeline

```
                        STATEFULSET POD (e.g., PostgreSQL Primary)
                                          │
                                          ▼ Mounts `/var/lib/postgresql/data`
       ┌────────────────────────────────────────────────────────────────────────┐
       │             PERSISTENT VOLUME CLAIM (PVC): 500 GiB                     │
       │             StorageClass: `managed-csi-premium-v2`                     │
       │             VolumeMode: Filesystem (ext4/xfs)                          │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ Dynamic Volume Binding
                                          ▼ (WaitForFirstConsumer)
       ┌────────────────────────────────────────────────────────────────────────┐
       │                      AZURE DISK CSI DRIVER SUBSYSTEM                   │
       │                                                                        │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ csi-azuredisk-plugin   │         │ csi-snapshot-controller│         │
       │  │ (Calls ARM Compute API)│         │ (Azure Disk Snapshots) │         │
       │  └───────────┬────────────┘         └───────────┬────────────┘         │
       │              │ Issues AttachDisk                │ Creates Snapshots    │
       │              ▼                                  ▼                      │
       │  ┌──────────────────────────────────────────────────────────┐          │
       │  │ csi-resizer: Triggers Online Zero-Downtime Expansion     │          │
       │  └───────────────────────────┬──────────────────────────────┘          │
       └──────────────────────────────┼─────────────────────────────────────────┘
                                      │ Attaches LUN to Azure VM Host
                                      ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                    AZURE MANAGED DISK SUBSTRATE                        │
       │                                                                        │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ Premium SSD v2         │         │ Azure Elastic SAN      │         │
       │  │ - Up to 80,000 IOPS    │         │ - iSCSI Managed Fabric │         │
       │  │ - Sub-millisecond P99  │         │ - Shared Pool IOPS     │         │
       │  │ - Independent IOPS/GB  │         │ - Millions of IOPS     │         │
       │  └────────────────────────┘         └────────────────────────┘         │
       └────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Disk Tier Comparison Matrix for AKS Workloads

| Dimension | Standard SSD (`StandardSSD_LRS`) | Premium SSD (`Premium_LRS`) | Premium SSD v2 (`PremiumV2_LRS`) | Ultra Disk (`UltraSSD_LRS`) |
| :--- | :--- | :--- | :--- | :--- |
| **Max Disk IOPS** | 6,000 IOPS | 20,000 IOPS | **80,000 IOPS** | **400,000 IOPS** |
| **Max Throughput** | 750 MB/s | 900 MB/s | **1,200 MB/s** | **10,000 MB/s** |
| **IOPS Decoupling**| Tied to disk size | Tied to disk size (P-tier)| **Independently configurable**| **Independently configurable**|
| **Latency Profile**| 5–10 milliseconds | Sub-5 milliseconds | **Sub-millisecond P99** | **Sub-millisecond P99** |
| **Failover Detach Latency**| ~45–60 seconds | ~30–45 seconds | ~30–45 seconds | ~30–45 seconds |
| **Best Workload** | Dev/Test databases | Production general state | **High-performance DBs (Postgres/Kafka)**| Low-latency In-Memory Cache |

---

## 3. Production Configuration & CLI Operations (`az` CLI & `kubectl`)

### 1. Define a Production StorageClass with Premium SSD v2 and Fast Failover

Create `storageclass-premium-v2.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-csi-premium-v2
provisioner: disk.csi.azure.com
parameters:
  skuName: PremiumV2_LRS
  cachingMode: None
  # Independently provision IOPS and Throughput regardless of disk size
  iopsReadWrite: "10000"
  mbpsReadWrite: "250"
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer # MANDATORY for Multi-Zone clusters!
```

Apply StorageClass:

```bash
kubectl apply -f storageclass-premium-v2.yaml
```

### 2. Deploy StatefulSet with Dynamic Volume Expansion & VolumeSnapshots

Create `postgres-statefulset.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql-db
  namespace: database
spec:
  serviceName: "postgresql-headless"
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: mcr.microsoft.com/oss/postgresql/postgresql:16
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: data-volume
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data-volume
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: managed-csi-premium-v2
      resources:
        requests:
          storage: 200Gi
```

Apply StatefulSet:

```bash
kubectl apply -f postgres-statefulset.yaml
```

### 3. Perform Online Zero-Downtime Volume Expansion

When PostgreSQL disk usage reaches 85%, expand the PVC directly via `kubectl patch` without terminating the database pod:

```bash
# Expand volume from 200Gi to 500Gi online
kubectl -n database patch pvc data-volume-postgresql-db-0 \
    --type merge \
    -p '{"spec":{"resources":{"requests":{"storage":"500Gi"}}}}'

# Verify expansion status in real time
kubectl -n database describe pvc data-volume-postgresql-db-0
```

---

## 4. Quotas, Performance & Configuration Limits

| Parameter / Feature | Platform Limit | Production Impact |
| :--- | :--- | :--- |
| **Max Disks per Node** | **Up to 64 Disks** | Strictly bounded by the underlying Azure VM size |
| **Max Disk Volume Size** | **32 TiB (32,767 GiB)** | Maximum size per individual PVC |
| **Online Expansion** | **Supported (Ext4/XFS)**| Does not require pod restart or cordoning |
| **Volume Shrinking** | **Strictly Prohibited** | Kubernetes and Azure Disks cannot be shrunk |
| **Volume Binding Mode** | `WaitForFirstConsumer` | Prevents provisioning disk in Zone 1 for pod in Zone 2 |

---

## 5. Official References

- [Azure Disk CSI Driver on AKS](https://learn.microsoft.com/en-us/azure/aks/azure-disk-csi)
- [Use Premium SSD v2 with AKS](https://learn.microsoft.com/en-us/azure/aks/premium-ssd-v2)
- [Azure Elastic SAN Integration with AKS](https://learn.microsoft.com/en-us/azure/aks/elastic-san)
- [Azure Managed Disks Pricing](https://azure.microsoft.com/en-us/pricing/details/managed-disks/)

---

## 6. Realistic Pricing Scenarios

### Scenario A: High-Throughput PostgreSQL Database (Premium SSD v2)

- **Storage Profile:**
  - 1x 1,000 GiB volume on `PremiumV2_LRS`.
  - Configured with 10,000 IOPS and 250 MB/s throughput.
- **Monthly Cost Breakdown:**
  - Base Capacity Cost (1,000 GiB): 1,000 × $0.0805/GiB = **$80.50**
  - Configured IOPS Cost (10,000 IOPS - first 3,000 free): 7,000 IOPS × $0.0051 = **$35.70**
  - Configured Throughput (250 MB/s - first 125 free): 125 MB/s × $0.057 = **$7.13**
- **Total Monthly Disk Cost:** **$123.33 / month** *(Compared to $380+/mo on older Premium SSD P40 tier).*

### Scenario B: Multi-Broker Kafka Cluster (3 Brokers, 3x 500 GiB Disks)

- **Storage Profile:**
  - 3 Kafka brokers running across 3 Availability Zones.
  - 3x 500 GiB Premium SSD (`managed-csi-premium`, P20 disk @ $73.22/mo each).
- **Monthly Cost Breakdown:**
  - Storage Disks: 3 × $73.22 = **$219.66**
  - Incremental Volume Snapshots (Daily 50 GiB deltas): 150 GiB × $0.05/GiB = **$7.50**
- **Total Monthly Disk Spend:** **$227.16 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Multi-Zone Disk Attachment Mismatch (`Immediate` Binding):** If a StorageClass uses `volumeBindingMode: Immediate`, Azure creates the Managed Disk immediately upon PVC creation in whatever zone the CSI driver defaults to (e.g., Zone 1). If the Kubernetes scheduler later places the pod in Zone 2 (due to CPU capacity), the pod enters a perpetual `CrashLoopBackOff` with `FailedAttachVolume: disk zone 1 does not match node zone 2`. **Always set `volumeBindingMode: WaitForFirstConsumer`.**
2. **StatefulSet Failover Detach Delays (The 6-Minute Timeout):** When an AKS node crashes or enters `NodeNotReady`, Azure's underlying storage fabric does not immediately detach the attached Azure Disk to prevent data corruption. The `csi-attacher` controller will wait up to **6 minutes** before issuing a force detach. To accelerate failover for high-availability databases, tune `pod-eviction-timeout` and deploy an automated node fencing controller.
3. **VM Max Data Disk Limit Exhaustion:** Every Azure VM shape has a hard hardware ceiling on how many data disks can be attached simultaneously (e.g., `Standard_D4ds_v5` supports a maximum of 8 data disks). If you schedule 10 stateful pods (each requesting a PVC) onto a single D4ds_v5 node, 2 pods will remain stuck in `Pending` with `VolumeAttachLimitReached`. Ensure stateful pods have anti-affinity rules to distribute them evenly across nodes.
4. **Volume Expansion Must Never Shrink:** Kubernetes supports expanding PersistentVolumeClaims online by editing `.spec.resources.requests.storage`. However, **Azure Managed Disks do not support shrinking**. If an engineer accidentally edits a PVC from 500Gi to 5000Gi, the 5 TB disk is provisioned and billed immediately, and there is no way to revert the size without backing up the database and creating a new volume.
5. **CachingMode Conflicts on Premium SSD v2:** Standard Premium SSDs support `cachingMode: ReadOnly` or `ReadWrite` (host VM cache). However, **Premium SSD v2 and Ultra Disks strictly prohibit host caching (`cachingMode: None`)**. Specifying any caching parameter other than `None` in the StorageClass will cause PVC provisioning to fail with `InvalidParameter: Host caching is not supported for disk type`.

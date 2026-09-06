---
title: GCP Persistent Disk & Hyperdisk
description: GCP Block Storage architecture — pd-balanced vs pd-ssd vs Hyperdisk, regional synchronous replication, dynamic volume expansion, and GKE CSI driver integration.
tags:
  - gcp
  - storage
  - persistent-disk
  - hyperdisk
  - kubernetes
---

# GCP Persistent Disk & Hyperdisk 💽⚡

Google Cloud provides network-attached block storage decoupled from virtual machine instances. Data on Persistent Disk (PD) and Hyperdisk persists independently of the VM lifecycle, automatically providing built-in encryption at rest and seamless live snapshots.

---

## Architecture & Mental Model

### Storage Types & Performance Tiers

```
┌────────────────────────────────────────────────────────────────────────┐
│                     Google Cloud Block Storage                         │
├─────────────────┬─────────────────┬──────────────────┬─────────────────┤
│   pd-standard   │   pd-balanced   │      pd-ssd      │    Hyperdisk    │
│      (HDD)      │   (Default SSD) │  (High-Perf SSD) │   (Next-Gen)    │
├─────────────────┼─────────────────┼──────────────────┼─────────────────┤
│ Max IOPS:       │ Max IOPS:       │ Max IOPS:        │ Max IOPS:       │
│ ~7,500          │ ~80,000         │ ~100,000         │ Up to 500,000   │
├─────────────────┼─────────────────┼──────────────────┼─────────────────┤
│ Best For:       │ Best For:       │ Best For:        │ Best For:       │
│ Large sequential│ Standard OS     │ High-throughput  │ Extreme DBs,    │
│ backups, batch  │ boot, micro-    │ OLTP databases,  │ LLM weight      │
│ log processing  │ services, Redis │ Kafka brokers    │ loading (ML)    │
└─────────────────┴─────────────────┴──────────────────┴─────────────────┘
```

* **Network-Attached Architecture:** Disks are not physical drives plugged into the host motherboard; they are distributed block devices communicated over Google's ultra-low-latency datacenter fabric.

---

## Core Concepts

### 1. Zonal vs. Regional Persistent Disk

* **Zonal Persistent Disk:** Replicated across multiple physical drives within a **single availability zone** for 99.999% component durability.
* **Regional Persistent Disk (Active-Standby Storage Replication):**
  * Data is synchronously mirrored across **two zones** within the same region.
  * In the event of a total datacenter zone outage, the disk can be immediately force-attached to a VM in the secondary zone with **zero data loss (RPO = 0)**.
  * Essential for stateful workloads (like PostgreSQL, MySQL, and single-replica Kafka) requiring high availability without application-level replication.

### 2. Next-Gen Hyperdisk Families

Traditional PD ties IOPS and throughput directly to provisioned disk capacity (larger disks = more IOPS). **Hyperdisk decouples performance from capacity**:
* **Hyperdisk Balanced:** Independently tune capacity, IOPS, and throughput for cost optimization.
* **Hyperdisk Extreme:** Up to 500,000 IOPS for mission-critical SAP HANA and Oracle databases.
* **Hyperdisk ML:** Delivers up to **1,200,000 IOPS** and **130 GB/s throughput** designed specifically for instant AI model weight loading onto NVIDIA GPUs.

### 3. Dynamic Online Volume Resizing

* Disk capacity can be increased in real time **without unmounting the disk, rebooting the VM, or restarting containers**:
  * Expand disk size via API/CLI: `gcloud compute disks resize`.
  * Expand guest filesystem on the fly using `resize2fs` (ext4) or `xfs_growfs` (XFS).

---

## Production `gcloud` CLI Commands

### 1. Provisioning a Regional Persistent Disk for Stateful High Availability

```bash
gcloud compute disks create prod-db-data-disk \
  --region=us-central1 \
  --replica-zones=us-central1-a,us-central1-b \
  --size=200GB \
  --type=pd-ssd
```

### 2. Dynamically Resizing an Attached Disk Online

```bash
# 1. Expand the GCP block device from 200GB to 500GB
gcloud compute disks resize prod-db-data-disk \
  --region=us-central1 \
  --size=500GB

# 2. Inside the VM guest OS, expand the filesystem live without unmounting:
# For ext4:
sudo resize2fs /dev/disk/by-id/google-prod-db-data-disk

# For XFS:
sudo xfs_growfs -d /mnt/disks/data
```

### 3. Kubernetes PVC with Regional PD via CSI Driver

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: regional-pd-ssd
provisioner: pd.csi.storage.gke.io
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: pd-ssd
  replication-type: regional-pd
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data-pvc
  namespace: database
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: regional-pd-ssd
  resources:
    requests:
      storage: 250Gi
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max disk size (PD)** | 64 TB per individual disk | Minimum 10 GB |
| **Max attached disks per VM** | 128 disks | Or 257 TB total attached capacity |
| **Regional PD replica zones** | Exactly 2 zones | Cannot replicate across 3 zones |
| **Snapshots per disk** | Up to 1,000 snapshots | Incremental differential storage |

---

## References

* **Homepage:** https://cloud.google.com/persistent-disk
* **Documentation:** https://cloud.google.com/compute/docs/disks
* **Hyperdisk Overview:** https://cloud.google.com/compute/docs/disks/hyperdisk-overview
* **GKE Persistent Volumes:** https://cloud.google.com/kubernetes-engine/docs/concepts/persistent-volumes
* **Pricing:** https://cloud.google.com/compute/disks-image-pricing

---

## Pricing Examples

### Scenario 1: Standard Application Fleet Storage
* 20 web and API VMs, each attached to a 50 GB `pd-balanced` boot disk.
* Total provisioned storage: 1,000 GB (1 TB).
* Monthly rate: 1,000 GB × $0.10 / GB = **$100.00 / month**.

### Scenario 2: High-Availability Database with Regional SSD
* Production transactional database requiring synchronous cross-zone durability.
* 1 TB Regional `pd-ssd` disk (`replica-zones=us-central1-a,us-central1-b`).
* Regional disks duplicate raw storage across both zones:
  * Regional `pd-ssd` rate: $0.34 / GB / month.
  * 1,024 GB × $0.34 = **$348.16 / month**.
* Daily snapshots (100 GB change rate retained for 30 days): ~$26.00.
* **Total Monthly Cost:** **~$374.16 / month**.

---

## Nuggets & Gotchas

1. **IOPS and Throughput Scale With VM Size, Not Just Disk Size:** Even if you provision an ultra-fast `pd-ssd` capable of 100,000 IOPS, a small VM instance (e.g. `e2-standard-2`) has strict hypervisor network bandwidth caps that limit disk throughput to ~2,000 IOPS! Maximum disk performance requires a machine type with at least 16–32 vCPUs.
2. **Disks Cannot Be Downsized:** Just like Cloud SQL, you can expand a Persistent Disk instantly, but **you can never shrink a disk**. If you accidentally create a 10 TB disk instead of 1 TB, you cannot downsize it; you must create a new 1 TB disk, rsync the data over, and delete the original.
3. **Regional PD Failover Requires `ReadWriteOnce` Force-Detachment:** When a zone fails and Kubernetes attempts to reschedule a stateful pod to the surviving zone, the underlying Regional PD may still be locked by the dead node. GKE's CSI driver supports automated volume attachment detachment, but can take ~2–3 minutes to break the stale attachment lock.
4. **Local SSDs Are Ephemeral (Loss on Stop):** Google also offers **Local SSDs** (NVMe physically connected to the host) boasting millions of IOPS and microsecond latencies. However, Local SSD data is **wiped clean if the VM is stopped**. Only use Local SSDs for ephemeral scratch space, swap disks, or distributed databases with application-level multi-node quorum (Cassandra, Elasticsearch).
5. **Snapshot Consistency Requires Filesystem Sync:** Taking a snapshot of an active disk while a database is writing heavy uncommitted transactions can result in crash-inconsistent filesystems. Always flush the filesystem buffer (`sync` or `fsfreeze -f`) prior to initiating snapshots of bare-metal databases.

---
title: GKE Storage Architecture — Compute Persistent Disk CSI, Hyperdisk, and Volume Snapshots
description: Exhaustive engineering guide to stateful storage on GKE — Google Cloud Compute Persistent Disk CSI Driver, Hyperdisk Extreme and ML dynamic provisioning, online volume expansion, volume snapshots, and regional replication.
tags:
  - gcp
  - gke
  - storage
  - csi
  - hyperdisk
  - stateful
---

# GKE Storage Architecture — Compute Persistent Disk CSI, Hyperdisk, and Volume Snapshots 💽📦

Running stateful enterprise workloads (PostgreSQL, Kafka, Cassandra, Elasticsearch) on Google Kubernetes Engine requires robust, performant block storage integration. GKE provides this via the **Google Compute Engine Persistent Disk Container Storage Interface (CSI) Driver**. Decoupled from the Kubernetes core codebase, the CSI driver enables dynamic provisioning of standard Persistent Disks, ultra-low-latency **Hyperdisk (Extreme, Throughput, and Balanced)**, **online zero-downtime volume expansion**, and point-in-time **Kubernetes VolumeSnapshots**.

---

## 1. Architecture & The CSI Storage Pipeline

The GKE Compute Persistent Disk CSI Driver translates standard Kubernetes `PersistentVolumeClaim` (PVC) declarations into Google Compute Engine storage infrastructure.

```
                         KUBERNETES APPLICATION POD (StatefulSet)
                                            │
                                            ▼ Mounts `/var/lib/data`
       ┌────────────────────────────────────────────────────────────────────────┐
       │                PERSISTENT VOLUME CLAIM (PVC): 500 GiB                  │
       │                StorageClass: `hyperdisk-balanced-sc`                   │
       └───────────────────────────────────┬────────────────────────────────────┘
                                           │ Dynamic Volume Binding
                                           ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                  GKE GCE PERSISTENT DISK CSI DRIVER                    │
       │                                                                        │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ csi-provisioner        │         │ csi-attacher           │         │
       │  │ (Calls GCE Disks API)  │         │ (Calls AttachDisk API) │         │
       │  └───────────┬────────────┘         └───────────┬────────────┘         │
       │  ┌───────────▼────────────┐         ┌───────────▼────────────┐         │
       │  │ csi-snapshotter        │         │ csi-resizer            │         │
       │  │ (VolumeSnapshot API)   │         │ (Online Expansion)     │         │
       │  └────────────────────────┘         └────────────────────────┘         │
       └───────────────────────────────────┬────────────────────────────────────┘
                                           │
       ════════════════════════════════════╪═════════════════════════════════════
       GOOGLE CLUSTER STORAGE INFRASTRUCTURE (Disaggregated Fiber Network)      │
                                           ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                    COMPUTE ENGINE DISK SUBSTRATE                       │
       │                                                                        │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ Zonal Hyperdisk        │         │ Regional PD Mirror     │         │
       │  │ Up to 500,000 IOPS     │         │ Synchronous RPO=0      │         │
       │  │ Sub-millisecond P99    │         │ Multi-Zone Replication │         │
       │  └────────────────────────┘         └────────────────────────┘         │
       └───────────────────────────────────┬────────────────────────────────────┘
                                           │ Continuous Deltas
                                           ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                 GOOGLE CLOUD STORAGE BACKUP SNAPSHOTS                  │
       │               (Global Durable VolumeSnapshot Recovery)                 │
       └────────────────────────────────────────────────────────────────────────┘
```

### Dynamic Provisioning Stages

1. **Volume Creation:** When a PVC is created, `csi-provisioner` intercepts the claim, inspects the `StorageClass`, and provisions an underlying GCE disk with designated IOPS, throughput, and encryption keys (CMEK).
2. **Volume Attachment:** When the pod is scheduled to a specific node, `csi-attacher` invokes the GCE `compute.instances.attachDisk` API to attach the physical block device (e.g., `/dev/sdb`) to the GCE VM.
3. **Volume Mounting:** The local CSI node daemon formats the disk (`ext4` or `xfs`) if empty and bind-mounts it into the container's designated directory path.

---

## 2. StorageClass Taxonomy: Standard vs Balanced vs Hyperdisk

GKE supports diverse block storage tiers tailored for specific I/O profiles:

| Storage Tier | GCE Disk Type | Max IOPS / Volume | Max Throughput | Recommended Workload |
| :--- | :--- | :--- | :--- | :--- |
| **Standard Persistent Disk** | `pd-standard` (HDD) | Up to 7,500 | 1,200 MB/s | Cold logs, bulk backup targets |
| **Balanced Persistent Disk** | `pd-balanced` (SSD) | Up to 80,000 | 1,200 MB/s | General microservices, web apps |
| **SSD Persistent Disk** | `pd-ssd` (SSD) | Up to 100,000 | 1,200 MB/s | Standard OLTP databases |
| **Hyperdisk Balanced** | `hyperdisk-balanced` | Up to 500,000 | 3,000 MB/s | High-performance enterprise DBs |
| **Hyperdisk Extreme** | `hyperdisk-extreme` | Up to 500,000 | 5,000 MB/s | Mission-critical SAP HANA, Oracle |
| **Regional Persistent Disk** | `pd-ssd` (Regional) | Up to 100,000 | 1,200 MB/s | Synchronous zero-data-loss failover |

---

## 3. Production Deployment & CLI Operations (`gcloud` & `kubectl`)

### 1. Enable the GCE Persistent Disk CSI Driver on GKE

The CSI driver is enabled by default on modern GKE clusters. Verify driver status:

```bash
# Verify CSI driver pods are healthy across all nodes
kubectl get pods -n kube-system -l app=gcp-compute-persistent-disk-csi-driver
```

### 2. Create StorageClass with Hyperdisk Balanced and CMEK

Create `hyperdisk-storageclass.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hyperdisk-balanced-encrypted
provisioner: pd.csi.storage.gke.io
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: hyperdisk-balanced
  provisioned-iops-on-create: "10000"
  provisioned-throughput-on-create: "500MiB"
  kms-key: projects/secops-kms-prod/locations/us-central1/keyRings/gke-storage-ring/cryptoKeys/pvc-key
```

Apply StorageClass:

```bash
kubectl apply -f hyperdisk-storageclass.yaml
```
*(Note: `volumeBindingMode: WaitForFirstConsumer` is mandatory; it prevents GKE from provisioning a disk in Zone A when the pod might later be scheduled in Zone B).*

### 3. Deploy StatefulSet with PersistentVolumeClaim

Create `postgres-statefulset.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  namespace: database
spec:
  serviceName: postgres-service
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: pgdata
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: pgdata
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: hyperdisk-balanced-encrypted
      resources:
        requests:
          storage: 250Gi
```

Apply StatefulSet:

```bash
kubectl apply -f postgres-statefulset.yaml
```

### 4. Execute Zero-Downtime Online Volume Expansion

GKE supports expanding Persistent Volumes on-the-fly without taking pods offline:

```bash
# Expand PVC from 250Gi to 500Gi directly
kubectl patch pvc pgdata-postgres-db-0 -n database \
    --patch '{"spec":{"resources":{"requests":{"storage":"500Gi"}}}}'

# Verify underlying GCE disk expansion and file system resize
kubectl get pvc pgdata-postgres-db-0 -n database -w
```
*(The GKE CSI driver calls GCE APIs to resize the block volume, and then dynamically resizes the `ext4/xfs` filesystem inside the running container without unmounting).*

### 5. Create Point-in-Time Kubernetes VolumeSnapshot

Create `postgres-snapshot.yaml`:

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-db-backup-01
  namespace: database
spec:
  volumeSnapshotClassName: gke-pd-snapshot-class
  source:
    persistentVolumeClaimName: pgdata-postgres-db-0
```

Apply snapshot:

```bash
kubectl apply -f postgres-snapshot.yaml

# Verify snapshot creation status
kubectl get volumesnapshot postgres-db-backup-01 -n database
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Standard Limit | Engineering Guidance |
| :--- | :--- | :--- |
| **Max Disks per GCE VM** | 128 disks per node | Depends on machine shape (e.g., N2 supports 128) |
| **Max Storage per VM** | 257 TiB total attached | Total attached disk storage across all pods on 1 node |
| **Volume Resizing** | Expansion only | Volumes cannot be shrunk; allocate conservatively |
| **Regional PD Zones** | Exactly 2 zones | Synchronous replication with zero data loss |
| **VolumeSnapshot Retention**| Backed by GCS | Persists independently of PVC lifecycle |
| **Access Modes** | `ReadWriteOnce` (RWO) | For `ReadWriteMany` (RWX), use Filestore or GCS FUSE |

---

## 5. Official References & Documentation

- [GKE Persistent Disk CSI Driver Overview](https://cloud.google.com/kubernetes-engine/docs/concepts/persistent-volumes)
- [Provisioning Hyperdisk on GKE](https://cloud.google.com/kubernetes-engine/docs/how-to/hyperdisk)
- [Expanding Persistent Volumes Online](https://cloud.google.com/kubernetes-engine/docs/how-to/expand-persistent-volumes)
- [VolumeSnapshots on GKE](https://cloud.google.com/kubernetes-engine/docs/how-to/volume-snapshots)
- [Regional Persistent Disks for High Availability](https://cloud.google.com/kubernetes-engine/docs/concepts/regional-pd)

---

## 6. Realistic Pricing Scenarios

Pricing components:
1. **Standard SSD (`pd-ssd`):** $0.17 per GB-month.
2. **Balanced PD (`pd-balanced`):** $0.10 per GB-month.
3. **Hyperdisk Balanced:** $0.08 per GB-month + $0.005 per provisioned IOPS + $0.04 per provisioned MB/s.
4. **Regional PD:** Doubles storage price (synchronous cross-zone replication).
5. **VolumeSnapshots:** $0.026 per GB-month (differential delta stored in GCS).

### Scenario A: Production PostgreSQL Cluster (Regional PD for RPO=0 Failover)

- **Architecture:**
  - 3 StatefulSet PostgreSQL pods across 3 zones.
  - Each pod attaches a 500 GiB **Regional SSD Persistent Disk** (synchronously mirrored across 2 zones).
  - Total Storage: 1,500 GiB Regional SSD.
  - Daily incremental volume snapshots (average accumulated snapshot delta: 1,000 GB).
- **Monthly Cost Calculation:**
  - Regional SSD Storage: 1,500 GB × $0.34/GB = **$510.00**
  - VolumeSnapshot Storage (1,000 GB): 1,000 GB × $0.026/GB = **$26.00**
- **Total Monthly Cost:** **$536.00 / month**

### Scenario B: High-Throughput Distributed Analytics (Hyperdisk Balanced)

- **Architecture:**
  - 5 ClickHouse analytics pods.
  - Each pod attaches 1,000 GiB Hyperdisk Balanced provisioned for **20,000 IOPS** and **400 MB/s throughput**.
  - Total Capacity: 5,000 GiB disk, 100,000 IOPS, 2,000 MB/s.
- **Monthly Cost Calculation:**
  - Capacity: 5,000 GB × $0.08/GB = **$400.00**
  - Provisioned IOPS: 100,000 IOPS × $0.005 = **$500.00**
  - Provisioned Throughput: 2,000 MB/s × $0.04 = **$80.00**
- **Total Monthly Cost:** **$980.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **`WaitForFirstConsumer` is Non-Negotiable:** If you create a StorageClass with `volumeBindingMode: Immediate`, Kubernetes provisions the GCE Persistent Disk immediately upon PVC creation in an arbitrary availability zone (e.g., `us-central1-c`). If your pod has node affinity or resource constraints that force it to schedule in `us-central1-a`, the pod will fail to start permanently with `FailedScheduling: 0/10 nodes available: 10 node(s) had volume node affinity conflict`. Always set `volumeBindingMode: WaitForFirstConsumer`.
2. **Volume Expansion Does Not Support Downsizing:** Just like in raw GCE, Kubernetes Persistent Volumes **can only be expanded; they can never be shrunk**. If an engineer accidentally edits a PVC to request `5000Gi` instead of `500Gi`, the CSI driver expands the volume to 5 TiB immediately. You will be billed for 5 TiB every month until you manually create a new PVC, copy the data with `rsync`, and delete the old volume.
3. **Regional PD Failover Disk Locking Delay:** Regional Persistent Disks allow a pod to fail over to another zone with zero data loss. However, when the original node in Zone A crashes, GCE takes between **60 and 120 seconds** to detect node death and release the block storage lock. During this period, the pod in Zone B will output `AttachVolume.Attach failed: Volume is already exclusively attached to node-zone-a`. Design application health checks to allow a 2-minute failover buffer.
4. **Local SSDs Are NOT Persistent Volumes:** Do not confuse GCE Persistent Disks with Local NVMe SSDs. Local SSDs cannot be managed via the standard GCE PD CSI driver; they are ephemeral. If you need local SSD performance managed as a PV, deploy the open-source **Kubernetes Local Storage Operator (LSO)** or use GKE's native ephemeral storage local SSD feature.
5. **StatefulSet VolumeClaimTemplates Retain Disks on Deletion:** When you scale down a StatefulSet from 5 replicas to 3, or delete the StatefulSet entirely, **Kubernetes intentionally DOES NOT delete the underlying PVCs or GCE Persistent Disks**. This safety mechanism prevents catastrophic data loss, but orphaned disks continue to accrue full storage billing. Implement automated clean-up pipelines to purge orphaned PVCs.
6. **Hyperdisk Requires Compatible Machine Series:** Hyperdisk Balanced and Extreme cannot be attached to legacy N1 or E2 machine series. They **strictly require third-generation or newer compute instances (C3, C3D, N4, G2, A3)**. If your node pool runs `n2-standard-4` and you attempt to mount a Hyperdisk PVC, the pod will fail to schedule with `FailedAttachVolume: Hyperdisk is not supported on machine type n2-standard-4`.

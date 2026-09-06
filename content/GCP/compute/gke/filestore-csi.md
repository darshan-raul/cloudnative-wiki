---
title: GKE Filestore CSI Driver — Managed NFS and ReadWriteMany (RWX) Architecture
description: Exhaustive engineering guide to Google Cloud Filestore CSI Driver on GKE — Enterprise managed NFS v3/v4.1, dynamic ReadWriteMany (RWX) volume provisioning, Enterprise multi-share instances, automated volume snapshots, and stateful multi-pod architectures.
tags:
  - gcp
  - gke
  - storage
  - filestore
  - nfs
  - rwx
---

# GKE Filestore CSI Driver — Managed NFS and ReadWriteMany (RWX) Architecture 📁⚡

While block storage (Persistent Disk / Hyperdisk) provides high-performance I/O for single-instance workloads, standard disks only support `ReadWriteOnce` (RWO)—they cannot be mounted concurrently by multiple pods across different nodes. The **Google Cloud Filestore CSI Driver** for GKE bridges this gap by delivering fully managed, high-performance **NFS (Network File System v3 and v4.1)** volumes with native **ReadWriteMany (RWX)** semantics. It powers enterprise CMS platforms (WordPress, Drupal), shared CI/CD build caches, distributed machine learning scratch spaces, and legacy stateful applications requiring POSIX file sharing.

---

## 1. Architecture & The Filestore CSI Pipeline

The Filestore CSI driver decouples the Kubernetes PVC lifecycle from manual NFS server and export configuration.

```
                  KUBERNETES APPLICATION PODS (Across Multiple Nodes & Zones)
       ┌────────────────────────┐         ┌────────────────────────┐
       │ Pod 1 (Node A / Zone 1)│         │ Pod 2 (Node B / Zone 2)│
       │ Mount: `/shared/assets`│         │ Mount: `/shared/assets`│
       └───────────┬────────────┘         └───────────┬────────────┘
                   │                                  │
                   └─────────────────┬────────────────┘
                                     │ ReadWriteMany (RWX) NFS Mounts
                                     ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                 PERSISTENT VOLUME CLAIM (PVC): 1 TiB                   │
       │                 StorageClass: `filestore-enterprise-multishare`        │
       └───────────────────────────────────┬────────────────────────────────────┘
                                           │ Dynamic Provisioning
                                           ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                    GKE FILESTORE CSI CONTROLLER                        │
       │                                                                        │
       │  ┌──────────────────────────────────────────────────────────────────┐  │
       │  │               MULTI-SHARE INSTANCE PACKER                        │  │
       │  │  - Packs multiple small PVCs (e.g., 100 GiB) into a single       │  │
       │  │    high-throughput enterprise Filestore cluster (1 TiB minimum)  │  │
       │  │  - Eliminates paying for standalone NFS VMs per microservice     │  │
       │  └──────────────────────────────────┬───────────────────────────────┘  │
       └─────────────────────────────────────┼──────────────────────────────────┘
                                             │ Filestore API Calls
       ══════════════════════════════════════╪═══════════════════════════════════
       GOOGLE CLUSTER NETWORK (VPC Subnet / RFC 1918 Private IP)               │
                                             ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                 GOOGLE MANAGED FILESTORE CLUSTER                       │
       │                                                                        │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ NFS v3 / v4.1 Engine   │         │ Multi-Zone Replication │         │
       │  │ 100,000+ IOPS          │         │ 99.99% Availability SLA│         │
       │  │ Multi-GB/s Throughput  │         │ Non-disruptive snapshot│         │
       │  └────────────────────────┘         └────────────────────────┘         │
       └────────────────────────────────────────────────────────────────────────┘
```

### Core Architecture Constructs

1. **ReadWriteMany (RWX) Semantics:** Any number of pods spread across hundreds of GKE nodes can simultaneously mount the same directory, issue file locks, write files, and see real-time updates across nodes.
2. **Filestore Multi-Shares (Enterprise):** Standard Filestore instances historically required a minimum 1 TiB allocation per instance ($660+/month). The GKE Filestore CSI Driver introduces **Multi-Shares**: a single 1 TiB Enterprise Filestore instance can be subdivided dynamically into dozens of smaller Kubernetes PVCs (e.g., 50 GiB each), dramatically lowering per-workload costs.
3. **Automated VolumeSnapshots:** Supports the Kubernetes `VolumeSnapshot` API, creating instantaneous, non-disruptive file system snapshots stored durably in Google Cloud Storage.

---

## 2. Filestore Tier Matrix & Sizing Boundaries

| Filestore Tier | Minimum Size | Max Throughput | Availability SLA | Supported Features |
| :--- | :--- | :--- | :--- | :--- |
| **Basic HDD** | 1 TiB | Up to 100 MB/s | 99.9% (Single Zone) | Backup targets, cold file shares |
| **Basic SSD** | 2.5 TiB | Up to 1,200 MB/s | 99.9% (Single Zone) | General web hosting, CMS, CI/CD |
| **Zonal (High Scale)**| 10 TiB | Up to 26,000 MB/s | 99.9% (Single Zone) | High-performance AI/ML, EDA, genomics |
| **Enterprise** | **1 TiB** | Up to 1,200 MB/s | **99.99% (Multi-Zone)**| **Multi-share GKE packing, snapshots** |

---

## 3. Production Deployment & CLI Operations (`gcloud` & `kubectl`)

### 1. Enable Filestore CSI Driver on GKE Cluster

```bash
gcloud container clusters update prod-regional-cluster \
    --region=us-central1 \
    --update-addons=GcpFilestoreCsiDriver=ENABLED \
    --project=core-infrastructure-prod
```

### 2. Deploy Multi-Share Enterprise StorageClass

Create `filestore-multishare-sc.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: filestore-multishare
provisioner: filestore.csi.storage.gke.io
volumeBindingMode: Immediate
allowVolumeExpansion: true
parameters:
  tier: enterprise
  network: production-vpc
  # Enables packing multiple PVCs into a single shared Filestore instance
  multishare: "true"
  instance-encryption-kms-key: projects/secops-kms-prod/locations/us-central1/keyRings/gke-storage-ring/cryptoKeys/filestore-key
```

Apply StorageClass:

```bash
kubectl apply -f filestore-multishare-sc.yaml
```

### 3. Deploy ReadWriteMany (RWX) PersistentVolumeClaim

Create `shared-assets-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-web-assets-pvc
  namespace: web-apps
spec:
  accessModes:
  - ReadWriteMany # RWX access mode
  storageClassName: filestore-multishare
  resources:
    requests:
      storage: 100Gi
```

Apply PVC:

```bash
kubectl apply -f shared-assets-pvc.yaml
```

### 4. Deploy Multi-Replica Web Service Sharing the NFS Volume

Create `cms-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: enterprise-cms
  namespace: web-apps
spec:
  replicas: 10
  selector:
    matchLabels:
      app: cms
  template:
    metadata:
      labels:
        app: cms
    spec:
      containers:
      - name: nginx-php
        image: wordpress:6-php8.2-apache
        ports:
        - containerPort: 80
        volumeMounts:
        - name: shared-uploads
          mountPath: /var/www/html/wp-content/uploads
      volumes:
      - name: shared-uploads
        persistentVolumeClaim:
          claimName: shared-web-assets-pvc
```

Apply Deployment:

```bash
kubectl apply -f cms-deployment.yaml

# Verify all 10 pods across multiple nodes mounted the same volume
kubectl get pods -n web-apps -o wide
```

### 5. Create Point-in-Time Filestore VolumeSnapshot

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: shared-assets-snapshot-nightly
  namespace: web-apps
spec:
  volumeSnapshotClassName: gke-filestore-snapshot-class
  source:
    persistentVolumeClaimName: shared-web-assets-pvc
```

Apply snapshot:

```bash
kubectl apply -f filestore-snapshot.yaml
```

---

## 4. Quotas, Performance, and Configuration Limits

| Dimension / Parameter | Limit / Boundary | Engineering Guidance |
| :--- | :--- | :--- |
| **Max Multi-Shares per Instance**| Up to 80 shares per instance | Allows 80 microservices per 1 TiB Filestore cluster |
| **Minimum Provisioned Share** | 10 GiB per PVC | Fine-grained allocation |
| **NFS Protocol Versions** | NFS v3 and NFS v4.1 | NFS v3 recommended for raw speed |
| **Max Concurrent TCP Sockets** | Up to 10,000 clients | Connects thousands of pods simultaneously |
| **Multi-Zone High Availability** | 99.99% SLA (Enterprise) | Synchronous mirroring across 2 zones in region |
| **Private IP Requirement** | Requires reserved `/26` range | Allocated from VPC Service Networking |

---

## 5. Official References & Documentation

- [GKE Filestore CSI Driver Overview](https://cloud.google.com/kubernetes-engine/docs/concepts/filestore-csi-driver)
- [How to Access Filestore Instances using CSI](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/filestore-csi-driver)
- [Filestore Multi-Shares for GKE Optimization](https://cloud.google.com/filestore/docs/multishares)
- [Filestore Enterprise Multi-Zone High Availability](https://cloud.google.com/filestore/docs/enterprise-multizone)
- [Google Cloud Filestore Pricing](https://cloud.google.com/filestore/pricing)

---

## 6. Realistic Pricing Scenarios

Pricing components:
1. **Filestore Enterprise Tier:** $0.66 per GiB-month (Includes synchronous multi-zone replication and 99.99% SLA).
2. **Filestore Basic HDD:** $0.067 per GiB-month.
3. **Filestore Basic SSD:** $0.17 per GiB-month.
4. **Filestore Snapshot Storage:** $0.026 per GB-month (differential backup stored in GCS).

### Scenario A: Enterprise Multi-Tenant CMS (Multi-Share Optimization)

- **Architecture:**
  - 10 distinct web applications requiring RWX shared storage (e.g., 50 GiB each = 500 GiB total requested).
  - Provisioned via a single **1 TiB Enterprise Multi-Share Filestore instance** ($0.66/GiB).
  - All 10 microservice PVCs carve out storage from this shared 1 TiB pool.
- **Monthly Cost Calculation:**
  - 1 TiB Enterprise Instance (1,024 GiB): $1{,}024 \times \$0.66/\text{GiB} = \mathbf{\$675.84 / month}$.
  - Cost per microservice ($675.84 / 10$): **$67.58 / month per service**.
*(Without multi-share, deploying 10 individual 1 TiB enterprise instances would cost $6,758.40/month—a **90% cost reduction**).*

### Scenario B: Shared CI/CD Build Cache (Basic SSD Tier)

- **Architecture:**
  - 2.5 TiB Basic SSD Filestore instance mounted across 30 Jenkins / GitLab CI worker pods for caching Go, Node, and Maven dependencies.
  - Generates 500 MB/s sustained sequential read/write throughput.
- **Monthly Cost Calculation:**
  - Basic SSD (2.5 TiB = 2,560 GiB): $2{,}560 \times \$0.17/\text{GiB} = \mathbf{\$435.20 / month}$.
- **Total Monthly Cost:** **$435.20 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **NFS File Locking and Deadlocks in Multi-Pod Writes:** When hundreds of containers mount the exact same NFS share and concurrently attempt to update the same SQLite database, search index, or log file, NFS file locking mechanisms (`NLM` in NFS v3 or stateful leases in NFS v4) can enter deadlock states. NFS was designed for shared static assets, media uploads, and decoupled documents—**never use Filestore as the backing storage for an embedded transactional relational database (like SQLite or embedded BerkeleyDB)**.
2. **Service Networking Private IP Exhaustion:** Filestore instances connect to your GKE cluster via VPC Service Peering (`servicenetworking.googleapis.com`). Each Filestore cluster consumes an internal `/26` IP block (64 IP addresses). If your organization reserved a narrow `/24` range for Service Networking and attempts to provision 5 distinct Filestore instances, creation will fail with `IP_SPACE_EXHAUSTED`. Use **Multi-Shares** to consolidate shares into a single `/26` reservation.
3. **Root Squashing UID/GID Permissions Trap:** By default, NFS exports frequently enforce `root_squash`, mapping container root (`UID 0`) to `nobody:nogroup` (`UID 65534`). If your container image executes as `root` and attempts to `chown` or create folders, it will throw `Permission denied`. Configure the `StorageClass` with `nfs-export-options` explicitly defining `squash: no_root_squash` or enforce non-root security contexts (`runAsUser: 10001`) across your pods.
4. **The 1 TiB Minimum Billing Boundary:** You can declare a Kubernetes PVC requesting `10Gi` of Filestore storage. However, if your StorageClass specifies `tier: enterprise` without `multishare: "true"`, the Filestore API will provision a full 1 TiB physical instance behind the scenes, and **you will be billed for 1,024 GiB ($675.84/month)** for a 10 GiB PVC. Always set `multishare: "true"` when allocating small RWX volumes.
5. **NFS Client Caching Attribute Latency (`acregmin` / `acregmax`):** When Pod A writes a file to the Filestore share, Pod B on a different node might not see the new file for 3 to 30 seconds due to Linux NFS client attribute caching (`actimeo`). If your application architecture relies on Pod A writing a file and immediately signaling Pod B via Pub/Sub to read it, Pod B will throw `FileNotFoundException`. Fix this by tuning mount options in the StorageClass: `mountOptions: ["acregmin=0", "acregmax=0"]` (at the cost of slightly higher metadata I/O).
6. **Cross-Zone Network Egress with Basic Tier:** Filestore Basic tiers are strictly zonal (deployed in a single availability zone, e.g., `us-central1-a`). If worker pods in `us-central1-b` and `us-central1-c` mount that Basic volume, every gigabyte of read/write traffic crosses zone boundaries, incurring GCP cross-zone egress charges ($0.01/GB) and adding 1-2ms network latency. For multi-zone regional GKE clusters, always use **Filestore Enterprise**, which replicates synchronously across multiple zones and optimizes local-zone reads.

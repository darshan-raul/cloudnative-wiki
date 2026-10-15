---
title: Azure Blob Storage & Data Lake Storage Gen2
description: Exhaustive engineering guide to Azure Blob Storage and ADLS Gen2 — Storage Account resource models, 3-tier hierarchy, Block vs Append vs Page blobs, redundancy tiers, access tiers, Archive rehydration, and User Delegation SAS.
tags:
  - azure
  - storage
  - blob
  - adls
  - object-storage
  - big-data
date: 2026-10-16
---

# Azure Blob Storage & Data Lake Storage Gen2 🪣📊

**Azure Blob Storage** is Microsoft's massively scalable object storage engine designed for unstructured data, distributed analytics lakes, container registries, enterprise backups, and media streaming. When enabled with a **Hierarchical Namespace (HNS)**, Blob Storage becomes **Azure Data Lake Storage Gen2 (ADLS Gen2)**, delivering atomic directory operations and POSIX-compliant access control lists for big data engines (Databricks, Fabric, Synapse, Apache Spark).

Unlike cloud storage providers where "buckets" exist as standalone top-level resources, Azure Blob Storage operates within a **multi-tiered resource envelope** governed by the **Azure Storage Account**.

---

## 1. Single-Service Fundamentals & Mental Models

### The Storage Account Resource Envelope & 3-Tier Hierarchy

In Azure, blobs cannot exist independently. All data is scoped within a three-level containment hierarchy:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│               STORAGE ACCOUNT: stproddatalake01 (Global Unique Name)                   │
│               Endpoint: https://stproddatalake01.blob.core.windows.net                 │
│                                                                                        │
│  - Regional Placement (e.g., East US)                                                  │
│  - Performance Tier (Standard GPv2 vs. Premium BlockBlob)                             │
│  - Redundancy Policy (LRS, ZRS, GRS, GZRS)                                             │
│  - Firewall, VNet Service Endpoints & Private Link Boundary                            │
│  - Microsoft Entra ID Authentication & Shared Key Authority                            │
│                                                                                        │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ CONTAINER: telemetry-raw (Analogous to an AWS S3 Bucket)                       │   │
│   │ - Public Access Level: Private (No anonymous access)                           │   │
│   │ - Immutability Policies (WORM) & Legal Holds                                   │   │
│   │ - Container-level RBAC (Storage Blob Data Contributor)                         │   │
│   │                                                                                │   │
│   │   ┌────────────────────────────────────────────────────────────────────────┐   │   │
│   │   │ BLOBS (Individual Objects & Analytical Data Streams)                   │   │   │
│   │   │                                                                        │   │   │
│   │   │  • Block Blob:  logs/2026-10/app.parquet (Hot Tier, 4.2 GB)            │   │   │
│   │   │  • Append Blob: audit/stream.log (Continuous Real-time Appends)        │   │   │
│   │   │  • Page Blob:   disks/legacy-boot.vhd (512-byte aligned random I/O)    │   │   │
│   │   └────────────────────────────────────────────────────────────────────────┘   │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### The 3 Core Blob Types

| Blob Type       | Internal Data Structure & Composition                                                                                                                                  | Maximum Size                        | Ideal Production Use Cases                                                                            |
| :-------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :---------------------------------- | :---------------------------------------------------------------------------------------------------- |
| **Block Blob**  | Composed of discrete, individually committed blocks (up to 50,000 blocks × 4,000 MiB). Supports parallel block uploads and block-level updates.                        | **~190.7 TiB**                      | Standard files, documents, images, video streaming, Parquet datasets, and backups.                    |
| **Append Blob** | Composed of committed blocks optimized strictly for append operations. Existing blocks cannot be modified or deleted; new data is written only to the end of the blob. | **195 GiB** (50,000 blocks × 4 MiB) | Continuous real-time logging, audit trails, and crash dump collectors.                                |
| **Page Blob**   | Collection of 512-byte pages indexed for random read and write operations.                                                                                             | **8 TiB**                           | Backing storage for unmanaged legacy VM VHD disks and database transactional log write-ahead buffers. |

### Storage Account Kinds & Performance Tiers

- **General Purpose v2 (GPv2):** The standard account kind for 95% of workloads. Supports all access tiers (Hot, Cool, Cold, Archive) and all storage services (Blob, File, Queue, Table).
- **Premium BlockBlobStorage:** High-performance SSD storage providing consistent, single-digit millisecond latency and high transaction rates. Ideal for AI/ML model training datasets, genomic pipelines, and telemetry ingestion.
- **Premium FileStorage:** Dedicated SSD storage for high-IOPS SMB and NFS file shares.
- **Premium PageBlobStorage:** Dedicated SSD storage for random read/write page blobs.

---

## 2. Storage Redundancy Hierarchy

Azure Storage automatically replicates all data to maintain high availability and durability against hardware failures, rack faults, and regional disasters:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Data Redundancy Tiers                           │
├─────────────────┬─────────────────┬──────────────────┬─────────────────┤
│ LRS             │ ZRS             │ GRS              │ GZRS            │
│ (Locally        │ (Zone-          │ (Geo-            │ (Geo-Zone-      │
│  Redundant)     │  Redundant)     │  Redundant)      │  Redundant)     │
├─────────────────┼─────────────────┼──────────────────┼─────────────────┤
│ 3 copies in a   │ 3 copies across │ 3 copies in LRS  │ 3 copies across │
│ single data-    │ 3 separate zones│ primary + async  │ 3 AZs primary + │
│ center          │ in 1 region     │ replicate to     │ replicate to    │
│                 │                 │ paired region    │ paired region   │
├─────────────────┼─────────────────┼──────────────────┼─────────────────┤
│ 11 Nines        │ 12 Nines        │ 16 Nines         │ 16 Nines        │
│ (99.999999999%) │ Durability      │ Durability       │ Durability      │
└─────────────────┴─────────────────┴──────────────────┴─────────────────┘
```

- **Read-Access Geo-Redundant Storage (RA-GRS / RA-GZRS):** Exposes a secondary read-only DNS endpoint (`<account>-secondary.blob.core.windows.net`) in the paired geographic region, allowing read operations to continue uninterrupted even during a catastrophic primary region outage.

---

## 3. Access Tiers & Archive Rehydration

Azure Blob Storage provides four distinct storage tiers to align financial cost with data access frequency:

| Access Tier | Optimal Access Pattern                                       | Minimum Storage Duration | First-Byte Retrieval Latency |
| :---------- | :----------------------------------------------------------- | :----------------------- | :--------------------------- |
| **Hot**     | Active daily reads and writes; high throughput               | None                     | Milliseconds (Online)        |
| **Cool**    | Infrequently accessed (>= 30 days)                           | 30 days                  | Milliseconds (Online)        |
| **Cold**    | Rarely accessed (>= 90 days)                                 | 90 days                  | Milliseconds (Online)        |
| **Archive** | Historical compliance and regulatory retention (>= 180 days) | 180 days                 | **Hours (Offline)**          |

### The Archive Rehydration Process

Blobs in the Archive tier are offline and cannot be read, downloaded, or copied directly. To read an archived blob, you must **rehydrate** it back to Hot or Cool:

- **Standard Priority Rehydration:** Processes requests in FIFO order; typically completes in **up to 15 hours**.
- **High Priority Rehydration:** Bypasses the queue to rehydrate blobs (< 10 GB) in **under 1 hour** at a higher transaction rate.

---

## 4. ADLS Gen2 Hierarchical Namespace (HNS)

In standard flat object storage (like AWS S3 or standard Azure Blob), "directories" do not exist; they are artificial virtual prefixes parsed from the object key name (e.g. `telemetry/2026/10/dataset.csv`).

```
Flat Object Store (Standard Blob / S3)       Hierarchical Namespace (ADLS Gen2)
           Virtual String Prefix                            Real Filesystem Inode
       telemetry/2026/10/file.csv                       ┌───── telemetry (Directory)
                                                        │       │
Rename 'telemetry' to 'archived':                       │       └─ 2026 (Directory)
• Must copy 1,000,000 files individually                │           │
• Must delete 1,000,000 old files                       │           └─ file.csv
• 2,000,000 API calls & hours of runtime                Rename 'telemetry' to 'archived':
                                                        • 1 Atomic metadata pointer update (<10ms)
```

- **ADLS Gen2 Advantage:** Enables atomic folder renames, POSIX access control lists (ACLs) per folder/file, and native Hadoop/Spark driver optimization (`abfss://`).

---

## 5. Security Architecture: Entra ID RBAC vs. SAS

### User Delegation SAS vs. Master Account Keys

```
                                  Client Request
                                        │
           ┌────────────────────────────┴────────────────────────────┐
           ▼                                                         ▼
[ Insecure: Shared Master Keys ]                     [ Production Standard: Entra ID RBAC ]
- Signed using Key1 or Key2                         - Signed using temporary OAuth2 token
- Full root admin access over entire account         - Scoped to exact container or blob
- Cannot be revoked without breaking all apps       - Revoking identity immediately kills access
```

- **Disable Shared Key Access:** Secure production storage accounts by setting `--allow-shared-key-access false`. This forces all client SDKs, pipelines, and applications to authenticate via **Microsoft Entra ID (Azure RBAC)** or **User Delegation SAS**.

---

## 6. Production `az` CLI Workflows

### 1. Creating a Hardened ADLS Gen2 Storage Account with Zone Redundancy

```bash
# 1. Create Resource Group
az group create --name rg-storage-prod --location eastus

# 2. Provision Hardened Storage Account (Disabling Shared Keys and Enforcing TLS 1.2)
az storage account create \
  --resource-group rg-storage-prod \
  --name stproddatalake01 \
  --location eastus \
  --sku Standard_ZRS \
  --kind StorageV2 \
  --hierarchical-namespace true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --allow-shared-key-access false \
  --default-action Deny
```

### 2. Creating a Container and Uploading Blobs with Entra ID Authentication

```bash
# 1. Create private container using logged-in Entra ID identity (--auth-mode login)
az storage container create \
  --account-name stproddatalake01 \
  --name raw-telemetry \
  --auth-mode login

# 2. Upload dataset as Block Blob with Hot access tier
az storage blob upload \
  --account-name stproddatalake01 \
  --container-name raw-telemetry \
  --name "metrics/2026-10-16/data.parquet" \
  --file ./data.parquet \
  --tier Hot \
  --auth-mode login
```

### 3. Configuring Automated Lifecycle Management (Auto-Tiering Rules)

```json
{
  "rules": [
    {
      "enabled": true,
      "name": "auto-tier-to-archive-and-expire",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["raw-telemetry/"]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": { "daysAfterModificationGreaterThan": 30 },
            "tierToCold": { "daysAfterModificationGreaterThan": 90 },
            "tierToArchive": { "daysAfterModificationGreaterThan": 180 },
            "delete": { "daysAfterModificationGreaterThan": 2555 }
          }
        }
      }
    }
  ]
}
```

```bash
az storage account management-policy create \
  --resource-group rg-storage-prod \
  --account-name stproddatalake01 \
  --policy @lifecycle-policy.json
```

---

## 7. Quotas & Limits

| Parameter                             | Limit                     | Production Notes                                  |
| :------------------------------------ | :------------------------ | :------------------------------------------------ |
| **Max Capacity per Storage Account**  | 5 PiB (5,120 TB)          | Increase via Azure support ticket                 |
| **Max Individual Block Blob Size**    | 190.7 TiB                 | 50,000 blocks × 4,000 MiB block size              |
| **Max Append Blob Size**              | 195 GiB                   | 50,000 blocks × 4 MiB block size                  |
| **Max Ingress Request Rate**          | Up to 20,000 req/sec      | Scaled automatically across partitions            |
| **Max Egress Bandwidth**              | Up to 50 Gbps per account | Request limit expansion for high-throughput lakes |
| **Storage Accounts per Subscription** | 250 per region            | Consolidate containers into shared accounts       |

---

## 8. Pricing Examples

### Scenario 1: Big Data Analytics Lake with ADLS Gen2

- **Storage Volume:** 100 TB of analytical data in `Hot` tier with Zone-Redundant Storage (`Standard_ZRS`).
- **Storage Cost:** 102,400 GB × $0.023 / GB = **$2,355.20 / month**.
- **Transactions:** 20 million read operations ($0.005 / 10,000) = **$10.00 / month**.
- **Total Monthly Lake Cost:** **~$2,365.20 / month**.

### Scenario 2: Regulatory Archive with Lifecycle Rules

- **Storage Volume:** 250 TB of compliance audit logs transitioned to `Archive` tier with Locally Redundant Storage (`Standard_LRS`).
- **Storage Cost:** 256,000 GB × $0.00099 / GB = **$253.44 / month**.
- **Occasional Audit Retrieval:** 2 TB rehydrated once per year ($0.022 / GB = $44.00).
- **Total Baseline Monthly Storage:** **~$253.44 / month** for 250 TB of preserved data.

---

## 9. Battle-Tested Nuggets & Gotchas

1. **Archive Tier Blobs Cannot Be Read Directly:** Issuing a standard HTTP `GET` or download request against an archived blob will fail immediately with `409 Conflict: BlobArchived`. Applications must initiate an asynchronous rehydration request (`az storage blob set-tier --tier Hot`) and poll until the blob transitions to an online tier before reading bytes.
2. **Early Deletion Penalties on Cold and Archive Tiers:** Cool has a 30-day, Cold has a 90-day, and Archive has a **180-day minimum storage commitment**. Deleting or overwriting a 10 TB blob in Archive after 10 days incurs an early deletion fee for the remaining 170 days of storage!
3. **Hierarchical Namespace (HNS) Cannot Be Enabled After Creation:** You cannot turn an existing standard Blob Storage account into an ADLS Gen2 Hierarchical Namespace account in place. If big data engines require atomic folder renames, you must provision a new HNS-enabled storage account and migrate data over AzCopy.
4. **Primary Key Storage Account Compromise:** The master Access Keys (`key1` and `key2`) have unrestricted root administrative ownership over the entire storage account, completely bypassing all Azure RBAC policies. Always disable key-based access (`--allow-shared-key-access false`) and enforce Microsoft Entra ID authentication.
5. **Soft Delete vs. Retention Locks:** Azure Blob Soft Delete protects against accidental file deletions. However, if an administrator or compromised credential deletes the **entire Storage Account resource**, all blobs inside it are wiped instantly. Enable an Azure Resource Lock (`CanNotDelete`) on the storage account resource itself.
6. **Container Names Must Be Lowercase:** Unlike AWS S3 where bucket names have mixed restrictions, Azure container names must be strictly lowercase alphanumeric strings between 3 and 63 characters. Supplying uppercase characters results in immediate client-side validation failures.

---

## Across the Wiki

- [[Azure/storage/README|Azure Storage Hub]] — Master directory for Azure storage architectures
- [[Azure/storage/files-netapp|Azure Files & Azure NetApp Files]] — Enterprise SMB and NFS shared filesystems
- [[Azure/storage/disks-elastic-san|Azure Managed Disks & Elastic SAN]] — High-performance block storage
- [[AWS/storage/s3/README|Amazon S3]] — Object storage in AWS
- [[GCP/storage/gcs|Google Cloud Storage (GCS)]] — Object storage in Google Cloud
- [[Kubernetes/eks/storage/mountpoint-s3|Mountpoint for Amazon S3 CSI Driver]] — Object storage CSI integration in Kubernetes
- [[GCP/compute/gke/cloud-storage-fuse|GKE Cloud Storage FUSE CSI Driver]] — AI/ML object storage filesystem integration

---
title: Azure Blob Storage & Data Lake Storage Gen2
description: Azure Blob Storage architecture — redundancy tiers (LRS/ZRS/GRS), access tiers, Archive rehydration, ADLS Gen2 Hierarchical Namespace, and User Delegation SAS.
tags:
  - azure
  - storage
  - blob
  - adls
  - object-storage
---

# Azure Blob Storage & Data Lake Storage Gen2 🪣📊

Azure Blob Storage is Microsoft's massively scalable object storage service for unstructured data, logs, backups, and media assets. When enabled with a **Hierarchical Namespace (HNS)**, Blob Storage becomes **Azure Data Lake Storage Gen2 (ADLS Gen2)**, delivering atomic directory operations and POSIX-compliant access control lists for big data analytics (Databricks, Synapse, Apache Spark).

---

## Architecture & Mental Model

### Storage Redundancy Hierarchy

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
│ 11 Nines (99.999999999%) Durability│ 12 Nines Durability│ 16 Nines Durability│ 16 Nines Durability│
└─────────────────┴─────────────────┴──────────────────┴─────────────────┘
```

---

## Core Concepts

### 1. Access Tiers & Archive Rehydration

| Access Tier | Optimal Access Pattern | Min Storage Duration | First-Byte Latency |
| :--- | :--- | :--- | :--- |
| **Hot** | Active daily reads and writes | None | Milliseconds (Online) |
| **Cool** | Infrequently accessed (>= 30 days) | 30 days | Milliseconds (Online) |
| **Cold** | Rarely accessed (>= 90 days) | 90 days | Milliseconds (Online) |
| **Archive** | Historical compliance (>= 180 days) | 180 days | **Hours (Offline)** |

* **The Archive Rehydration Process:** Blobs in the Archive tier are offline. To read an archived blob, you must **rehydrate** it back to Hot or Cool:
  * **Standard Priority:** Rehydration completes in **up to 15 hours**.
  * **High Priority:** Rehydrates small blobs (< 10 GB) in **under 1 hour** at higher cost.

### 2. ADLS Gen2 Hierarchical Namespace (HNS)

In standard object storage (like AWS S3 or standard Azure Blob), "folders" do not exist; they are merely prefixes in the object key string (e.g. `folder/subfolder/file.csv`).
* **The Rename Problem:** In standard object storage, renaming a folder containing 1,000,000 files requires **1,000,000 individual copy operations followed by 1,000,000 delete operations**, taking hours and costing thousands of API transactions.
* **ADLS Gen2 Solution:** The Hierarchical Namespace creates real filesystem directory nodes. Renaming a directory is an **atomic metadata operation** that completes in **milliseconds**, regardless of how many petabytes of data reside inside the folder.

### 3. User Delegation SAS vs. Account Key SAS

Shared Access Signatures (SAS) generate temporary, signed URLs for client uploads and downloads:
* **Account Key SAS (Insecure):** Signed using the master Storage Account Access Key. If compromised, an attacker can generate unlimited SAS tokens with full permissions.
* **User Delegation SAS (Enterprise Best Practice):**
  * Signed using temporary **Microsoft Entra ID credentials**.
  * Revoking the user or service account in Entra ID immediately invalidates all active delegated SAS tokens!

---

## Production `az` CLI Commands

### 1. Creating a Storage Account with ADLS Gen2 and Zone Redundancy

```bash
az storage account create \
  --resource-group prod-data-rg \
  --name stproddatalake01 \
  --location eastus \
  --sku Standard_ZRS \
  --kind StorageV2 \
  --hierarchical-namespace true \
  --enable-large-file-share \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false
```

### 2. Configuring Blob Lifecycle Management (Auto-Tiering)

```json
{
  "rules": [
    {
      "enabled": true,
      "name": "tier-to-archive-and-delete",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": {"daysAfterModificationGreaterThan": 30},
            "tierToCold": {"daysAfterModificationGreaterThan": 90},
            "tierToArchive": {"daysAfterModificationGreaterThan": 180},
            "delete": {"daysAfterModificationGreaterThan": 2555}
          }
        }
      }
    }
  ]
}
```

```bash
az storage account management-policy create \
  --resource-group prod-data-rg \
  --account-name stproddatalake01 \
  --policy @lifecycle-policy.json
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max storage capacity per account** | 5 PiB (5,120 TB) | Increase via support request |
| **Max individual block blob size** | 190.7 TiB | Via 50,000 blocks × 4,000 MiB |
| **Max ingress request rate** | Up to 20,000 requests/sec | Scales automatically |
| **Storage accounts per subscription** | 250 accounts per region | Group containers into shared accounts |

---

## References

* **Homepage:** https://azure.microsoft.com/en-us/products/storage/blobs
* **Blob Storage Documentation:** https://learn.microsoft.com/en-us/azure/storage/blobs/
* **ADLS Gen2 Overview:** https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction
* **Pricing:** https://azure.microsoft.com/en-us/pricing/details/storage/blobs/

---

## Pricing Examples

### Scenario 1: Big Data Analytics Lake with ADLS Gen2
* 100 TB of active analytical data stored in `Hot` tier with Zone-Redundant Storage (`Standard_ZRS`).
* Storage cost: 100 TB (102,400 GB) × $0.023 / GB = **$2,355.20 / month**.
* Read transactions (10 million read operations @ $0.005 / 10,000): $5.00.
* **Total Monthly Data Lake Cost:** **~$2,360.20 / month**.

### Scenario 2: Regulatory Archive with Lifecycle Rules
* 250 TB of compliance audit logs transitioned to `Archive` tier with Locally Redundant Storage (`Standard_LRS`).
* Storage cost: 250 TB (256,000 GB) × $0.00099 / GB = **$253.44 / month**.
* Retrieval cost (when audited): 1 TB rehydrated ($0.022 / GB = $22.00).
* **Total Baseline Monthly Storage:** **~$253.44 / month** for 250 TB of preserved data.

---

## Nuggets & Gotchas

1. **Archive Tier Blobs Cannot Be Read Directly:** Attempting to issue a standard HTTP `GET` or download request against an archived blob will fail immediately with `409 Conflict: BlobArchived`. The application must initiate an asynchronous rehydration request and poll until the blob transitions back to Cool or Hot before reading bytes.
2. **Early Deletion Penalties on Cold Tiers:** Cool has a 30-day, Cold has a 90-day, and Archive has a **180-day minimum storage commitment**. Deleting or overwriting a 10 TB blob in Archive after 10 days incurs an early deletion fee for the remaining 170 days of storage!
3. **Hierarchical Namespace (HNS) Cannot Be Enabled After Creation:** You cannot turn an existing standard Blob Storage account into an ADLS Gen2 Hierarchical Namespace account in place. If your data team later needs Databricks or atomic directory renames, you must create a new HNS-enabled storage account and migrate all data over AzCopy.
4. **Primary Key Storage Account Compromise:** The two master Access Keys (`key1` and `key2`) have unrestricted root administrative ownership over the entire storage account, completely bypassing all Azure RBAC policies. Always disable key-based access (`--allow-shared-key-access false`) and enforce Microsoft Entra ID authentication.
5. **Soft Delete vs. Retention Lock:** Azure Blob Soft Delete protects against accidental file deletions. However, if an attacker deletes the **entire Storage Account resource**, all blobs inside it are wiped instantly. Enable an Azure Resource Lock (`CanNotDelete`) on the storage account resource itself.

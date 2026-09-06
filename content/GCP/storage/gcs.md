---
title: Google Cloud Storage (GCS)
description: GCS architecture — storage classes, instant-retrieval archive, Object Lifecycle Management (OLM), Bucket Lock WORM compliance, Soft Delete, and Uniform Bucket-Level Access.
tags:
  - gcp
  - storage
  - gcs
  - object-storage
  - security
---

# Google Cloud Storage (GCS) 🪣

Google Cloud Storage is an exabyte-scale object storage service offering high durability (99.999999999% / 11 9s), strong global consistency, and a unified API across all storage classes. 

GCS differs fundamentally from AWS S3 in its cold storage tier: **GCS Archive storage offers sub-second (millisecond) retrieval latency**, completely eliminating the multi-hour restore jobs and expedite fees required by AWS S3 Glacier.

---

## Architecture & Mental Model

### Storage Classes & Retrieval Spectrum

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Google Cloud Storage                            │
├─────────────────┬─────────────────┬──────────────────┬─────────────────┤
│    Standard     │    Nearline     │     Coldline     │     Archive     │
├─────────────────┼─────────────────┼──────────────────┼─────────────────┤
│ Active hot data,│ Access < 1/mo   │ Access < 1/qtr   │ Access < 1/yr   │
│ websites, apps  │ Backups, reports│ Long-term backup │ Compliance logs │
├─────────────────┴─────────────────┴──────────────────┴─────────────────┤
│ First-Byte Latency: MILLISECONDS ACROSS ALL FOUR CLASSES               │
├─────────────────┬─────────────────┬──────────────────┬─────────────────┤
│ Min Retention:  │ Min Retention:  │ Min Retention:   │ Min Retention:  │
│     None        │     30 Days     │     90 Days      │    365 Days     │
└─────────────────┴─────────────────┴──────────────────┴─────────────────┘
```

* **No Retrieval Waiting:** When querying an object in `Archive` class, the application makes a standard `GET` request and receives bytes immediately, avoiding the complex asynchronous restore workflows of other clouds.

---

## Core Concepts

### 1. Bucket Location Types

* **Region:** Stored across multiple zones in a single geographical region (e.g. `us-central1`). Lowest latency and lowest storage cost.
* **Dual-Region:** Replicated across two specific regions (e.g., `nam4` = `us-central1` + `us-east1`).
  * **Turbo Replication:** Guarantees 100% of newly written data replicated across regions within **15 minutes** (backed by an SLA).
* **Multi-Region:** Geo-redundant storage across a continent (e.g., `us`, `eu`, `asia`). Delivers high availability (99.95%) for public content and global data lakes.

### 2. Uniform Bucket-Level Access (UBLA)

* **Legacy Object ACLs (Anti-Pattern):** Each individual object can carry its own Access Control List, leading to security blind spots where a single file is inadvertently exposed publicly.
* **Uniform Bucket-Level Access (Production Standard):** Disables all object-level ACLs. Access is governed exclusively by IAM policies bound at the bucket, folder, or organization level.

### 3. Soft Delete & Object Versioning

* **Object Versioning:** Retains previous revisions of an object when overwritten or deleted.
* **Soft Delete (Enabled by default on new buckets):** Retains deleted objects for a configurable retention window (default 7 days, up to 90 days). If a compromised service account or ransomware deletes files, they can be restored without data loss.

### 4. Retention Policies & Bucket Lock (WORM Compliance)

* **Retention Policy:** Enforces Write-Once-Read-Many (WORM) storage. Objects cannot be deleted or overwritten until their age exceeds the retention period.
* **Bucket Lock:** Permanently locks the retention policy. Once locked, **even Google Cloud Support and Project Owners cannot shorten the retention period or delete the bucket** until every object expires. Used for strict regulatory compliance (SEC Rule 17a-4, FINRA).

---

## Production `gcloud` CLI Commands

### 1. Provisioning a Hardened Production Bucket

```bash
# Create bucket with custom region, UBLA, Soft Delete, and Public Access Prevention
gcloud storage buckets create gs://prod-company-artifacts \
  --location=us-central1 \
  --default-storage-class=STANDARD \
  --uniform-bucket-level-access \
  --public-access-prevention \
  --soft-delete-duration=14d
```

### 2. Configuring Object Lifecycle Management (OLM)

```json
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30, "matchesStorageClass": ["STANDARD"]}
    },
    {
      "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
      "condition": {"age": 90, "matchesStorageClass": ["NEARLINE"]}
    },
    {
      "action": {"type": "SetStorageClass", "storageClass": "ARCHIVE"},
      "condition": {"age": 365, "matchesStorageClass": ["COLDLINE"]}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"age": 2555}
    }
  ]
}
```

```bash
# Apply lifecycle policy to bucket
gcloud storage buckets update gs://prod-company-artifacts \
  --lifecycle-file=lifecycle.json
```

### 3. Generating a Secure Signed URL for Direct Uploads

```bash
# Generate a temporary 15-minute upload URL using service account credentials
gcloud storage sign-url gs://prod-company-artifacts/uploads/incoming.dat \
  --duration=15m \
  --http-verb=PUT \
  --impersonate-service-account=uploader@my-prod-project.iam.gserviceaccount.com
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max object size** | 5 TiB per individual object | Upload via parallel composite uploads for objects > 100 MiB |
| **Max bucket count** | Unlimited per project | Organise by access boundary, not per user |
| **Write rate limit** | 1,000 writes/sec initial | Scales automatically up to tens of thousands of writes/sec |
| **Read rate limit** | 5,000 reads/sec initial | Scales automatically as traffic ramps smoothly |
| **Soft Delete duration** | 7 to 90 days | Configurable; charged at standard storage rates |

---

## References

* **Homepage:** https://cloud.google.com/storage
* **Documentation:** https://cloud.google.com/storage/docs
* **Storage Classes Guide:** https://cloud.google.com/storage/docs/storage-classes
* **Bucket Lock Overview:** https://cloud.google.com/storage/docs/bucket-lock
* **Pricing:** https://cloud.google.com/storage/pricing

---

## Pricing Examples

### Scenario 1: Media Streaming Application (High Egress & Hot Storage)
* 50 TB of video assets stored in `Standard` storage (`us-central1`).
* Monthly read egress to internet: 100 TB.
* Storage cost: 50 TB (51,200 GB) × $0.020 / GB = $1,024.00.
* Internet Egress: 100 TB × ~$0.08 / GB = $8,000.00.
* Operations (Class A write/list + Class B read): ~$25.00.
* **Total Monthly Bill:** **~$9,049.00 / month** (Tip: Cloud CDN in front of GCS slashes egress costs by ~60%).

### Scenario 2: Regulatory Long-Term Audit Archive
* 200 TB of compliance audit logs stored in `Archive` class.
* Retention: 7 years. Retrieval rate: Less than 1 TB read per year.
* Storage cost: 200 TB (204,800 GB) × $0.0012 / GB = **$245.76 / month**.
* Retrieval cost (when tested): 1 TB × $0.05 / GB = $50.00 (charged only on access).
* **Total Baseline Monthly Cost:** **~$245.76 / month** for 200 TB of millisecond-accessible data.

---

## Nuggets & Gotchas

1. **Early Deletion Penalties on Cold Classes:** Nearline has a 30-day, Coldline a 90-day, and Archive a **365-day minimum storage commitment**. If an automated script creates a 10 TB object in Archive storage and deletes it after 5 days, Google will bill you for the remaining **360 days of storage immediately**. Never use Archive storage for temporary or scratch files.
2. **Sequential Naming Hotspots:** In high-throughput write workloads (>5,000 writes/sec), naming objects sequentially (e.g. `log-2026-09-01-0001.json`, `log-2026-09-01-0002.json`) routes all writes to the same internal storage partition server. To achieve linear scaling, prepend a hash prefix to object names or use randomized UUIDs.
3. **Bucket Lock Is 100% Irreversible:** Once a retention policy is locked via `gcloud storage buckets update gs://bucket --lock-retention-policy`, it is impossible to undo. If a developer sets a retention period of 100 years by mistake, Google Cloud engineers **cannot** delete the bucket. Test retention policies thoroughly before locking.
4. **Soft Delete Storage Costs:** Soft Delete keeps deleted objects in a restorable state for 7 to 90 days. During this window, you continue to pay the object's base storage rate. If you delete 50 TB of data to cut costs, your bill will not decrease until the Soft Delete retention period elapses.
5. **Turbo Replication SLA Conditions:** Turbo Replication (15-minute inter-region RPO) is only available on **Dual-Region buckets** and requires an extra fee (~$0.02/GB written). It is not available on Multi-Region buckets (`us`, `eu`).

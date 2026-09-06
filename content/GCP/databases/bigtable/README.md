---
title: Google Cloud Bigtable
description: Cloud Bigtable architecture — petabyte-scale wide-column NoSQL, LSM-trees, tablet sharding, row key design, and HBase API compatibility.
tags:
  - gcp
  - databases
  - bigtable
  - nosql
  - big-data
---

# Google Cloud Bigtable 🗄️⚡

Google Cloud Bigtable is an enterprise-grade, sparsely populated, persistent, multidimensional sorted map that scales to petabytes of data across thousands of nodes. As the foundational storage engine that powers Google Search, Google Maps, YouTube, and Gmail, Bigtable provides **sub-10ms latency for random reads and writes** at massive scale.

---

## Architecture & Mental Model

### Disaggregated Compute & Storage (LSM-Tree on Colossus)

Unlike Apache Cassandra or MongoDB (where compute and disk storage are bound to the same physical host), Bigtable decouples compute from storage entirely:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Bigtable Cluster Compute                        │
│                        (Borg Worker Nodes)                             │
│                                                                        │
│   Node 1                   Node 2                   Node 3             │
│   Manages Tablets:         Manages Tablets:         Manages Tablets:   │
│   [aaa - ezz]              [faa - mzz]              [naa - zzz]        │
│   ├── MemTable (RAM)       ├── MemTable (RAM)       ├── MemTable (RAM) │
│   └── Write-Ahead Log      └── Write-Ahead Log      └── Write-Ahead Log│
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Jupiter Network Fabric (100 Gbps+)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     Colossus Distributed File System                   │
│                                                                        │
│   Stores Immutable SSTables & Commit Logs replicated across disks      │
│   • Tablet 1 SSTables: [aaa-czz] [daa-ezz]                             │
│   • Tablet 2 SSTables: [faa-izz] [jaa-mzz]                             │
│   • Tablet 3 SSTables: [naa-rzz] [saa-zzz]                             │
└────────────────────────────────────────────────────────────────────────┘
```

* **Instant Node Rebalancing:** Because data files (SSTables) reside on Colossus rather than local disks, adding or removing Bigtable compute nodes takes **seconds**: nodes simply reassign pointers to metadata tables without copying gigabytes of data over the network!

---

## Core Concepts

### 1. The Bigtable Data Model

Bigtable is formally structured as:
`(row:string, column_family:string, column_qualifier:string, timestamp:int64) ──► cell_value:string`

```
Row Key: "device_100#2026-09-06"
┌────────────────────────────────────────────────────────────────────────┐
│ Column Family: metrics                                                 │
├────────────────────┬───────────────────────────────────────────────────┤
│ Column Qualifier   │ Timestamped Cell Values (LIFO Order)              │
├────────────────────┼───────────────────────────────────────────────────┤
│ cpu_utilization    │ t=1725624000: "78.4%", t=1725623940: "72.1%"      │
├────────────────────┼───────────────────────────────────────────────────┤
│ memory_used_bytes  │ t=1725624000: "16777216", t=1725623940: "15982100"│
└────────────────────┴───────────────────────────────────────────────────┘
```

* **Single Index Only:** Bigtable is indexed **strictly by the Row Key**. There are no secondary indexes, foreign keys, or joins. All query filtering must either be encoded into the row key or executed via column filters.

### 2. Row Key Design (The Anti-Hotspotting Mandate)

Because Bigtable shards data into **Tablets** ordered lexicographically by row key, sequential keys route all traffic to a single tablet server, causing severe CPU hotspotting:

| Row Key Strategy | Pattern Example | Evaluation |
| :--- | :--- | :--- |
| **Sequential Timestamps (Anti-Pattern)** | `2026-09-06T12:00:01#dev1` | **FATAL:** All current writes hit the last tablet in the cluster; 99% of nodes remain idle |
| **Hashed Prefix (Scattered Writes)** | `md5(dev1)[0:4]#dev1#2026-09-06` | **Excellent for Writes:** Evenly distributes writes across all nodes |
| **Reversed Timestamps (Time-Series)** | `dev1#${MAX_INT - timestamp}` | **Excellent for Range Scans:** Latest sensor metrics are stored first |
| **Field Salting** | `salt_01#dev1#2026-09-06` | Balances writes across a fixed number of partitions |

### 3. Garbage Collection Policies

Bigtable retains multiple versions of each cell differentiated by timestamp. Without a Garbage Collection (GC) policy, data grows indefinitely:
* **Age-based:** Retain cells for up to 30 days (`max-age=30d`).
* **Version-based:** Retain only the latest 3 versions (`max-versions=3`).
* **Union/Intersection:** Retain data matching combinations of age and version.

---

## Production `gcloud` CLI & `cbt` Commands

### 1. Provisioning an Autoscaling Bigtable Production Instance

```bash
gcloud bigtable instances create prod-telemetry-db \
  --display-name="Production IoT Telemetry" \
  --cluster-config=id=cluster-us-central1,zone=us-central1-a,autoscaling-min-nodes=3,autoscaling-max-nodes=15,autoscaling-cpu-target=70 \
  --cluster-storage-type=SSD
```

### 2. Creating Tables & Column Families with Garbage Collection via `cbt`

```bash
# 1. Configure cbt CLI context
echo "project = my-prod-project" > ~/.cbtrc
echo "instance = prod-telemetry-db" >> ~/.cbtrc

# 2. Create the table
cbt createtable sensor_metrics

# 3. Create a Column Family with a 30-day Garbage Collection policy
cbt createfamily sensor_metrics raw_data "maxage=30d"

# 4. Insert a sample metric cell
cbt set sensor_metrics "sensor#1002#reversed_ts" raw_data:temperature="23.5"
```

### 3. Scanning a Specific Row Key Prefix

```bash
# Efficiently scan all rows for sensor 1002
cbt read sensor_metrics prefix="sensor#1002"
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max data per SSD node** | 5 TB per node | Bigtable forces node scale-out if storage exceeds 5 TB/node |
| **Max data per HDD node** | 16 TB per node | HDD only recommended for cold batch archives |
| **Max cell size** | 100 MB (recomm. < 10 MB) | Store large files in GCS |
| **Max row size** | 256 MB (recomm. < 100 MB) | Avoid unbounded row growth |
| **Throughput per SSD node** | ~10,000 QPS reads / ~10,000 QPS writes | Benchmark based on 1 KB rows with non-hotspotting keys |

---

## References

* **Bigtable Architecture Paper:** https://research.google/pubs/pub27898/
* **Row Key Design Best Practices:** https://cloud.google.com/bigtable/docs/schema-design
* **Garbage Collection Guide:** https://cloud.google.com/bigtable/docs/garbage-collection
* **Pricing:** https://cloud.google.com/bigtable/pricing

---

## Pricing Examples

### Scenario 1: Real-Time IoT Telemetry Ingestion (Autoscale SSD)
* Production Bigtable SSD cluster with 3 baseline nodes in `us-central1`.
* Ingests 50,000 sensor writes / sec continuously.
* Autoscaling range: 3 to 9 nodes. Average usage: 4 nodes sustained.
* Compute cost: 4 nodes × $0.65 / node-hour × 730 hrs = **$1,898.00 / month**.
* SSD Storage: 6 TB SSD = 6,144 GB × $0.17 / GB = **$1,044.48 / month**.
* **Total Monthly Bill:** **~$2,942.48 / month** (Serving 130 billion writes/month with sub-5ms write latency).

### Scenario 2: Historical Batch Log Archive (HDD)
* Cold historical security log archive storing 100 TB of data with HDD storage.
* 3 baseline nodes to manage tablets.
* Compute cost: 3 nodes × $0.65 / node-hour × 730 hrs = **$1,423.50 / month**.
* HDD Storage: 100 TB (102,400 GB) × $0.025 / GB = **$2,560.00 / month**.
* **Total Monthly Cost:** **~$3,983.50 / month**.

---

## Nuggets & Gotchas

1. **The Sequential Key Write Bottleneck:** Inserting rows with keys like `2026-09-06-0001`, `2026-09-06-0002` will bottleneck the entire cluster to a **single node**. Because all sequential keys belong to the same tablet, only 1 CPU core in the cluster processes writes, yielding ~10,000 QPS regardless of whether you have 3 nodes or 100 nodes provisioned! Always salt or hash the prefix.
2. **HDD Storage Performance Cliff:** Bigtable offers an HDD storage tier that is 85% cheaper than SSD. However, HDD performance is severely degraded: sequential reads are acceptable, but **random read latency jumps from 6ms to over 250ms**. Never use HDD for interactive customer APIs or real-time gaming services.
3. **The 5 TB Per Node Storage Floor:** Bigtable mandates a minimum of 1 node per 5 TB of SSD storage. If your dataset reaches 21 TB, the cluster will automatically scale to and enforce a minimum of **5 nodes ($2,372/month)**, even if your application CPU utilization is hovering near 1%!
4. **Garbage Collection Is Asynchronous:** Deleting data via a Garbage Collection policy (e.g. `maxage=7d`) does not immediately reclaim disk space or delete data instantly. Expired cells are masked from query results immediately, but physical storage blocks are only purged during background **Major Compactions**.
5. **No Atomic Multi-Row Transactions:** Bigtable supports atomicity **strictly within a single row** (`CheckAndMutateRow`, `ReadModifyWriteRow`). It is mathematically impossible to execute an atomic transaction that spans across two different rows. For multi-row ACID transactions, use **Google Cloud Spanner**.

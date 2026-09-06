---
title: Google Cloud Spanner
description: Cloud Spanner architecture — TrueTime API, external consistency (serializability), horizontal scaling, interleaved tables, and multi-region 5-nines availability.
tags:
  - gcp
  - databases
  - spanner
  - distributed-systems
  - sql
---

# Google Cloud Spanner 🌐⚡

Google Cloud Spanner is the world's first globally distributed, horizontally scalable relational database that provides **full ACID transactions, SQL querying, and external consistency (strict serializability)** without sacrificing high availability. 

Spanner delivers an industry-leading **99.999% (five nines) availability SLA** for multi-region configurations, representing no more than 5 minutes and 15 seconds of downtime per year.

---

## Architecture & Mental Model

### The TrueTime API & Distributed Transactions

Traditional distributed databases struggle with the CAP theorem because distributed clocks drift. Spanner solves global ordering using Google's proprietary **TrueTime API**:

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │                        TrueTime Architecture                          │
 │                                                                        │
 │   GPS Receivers (Antennas)       Atomic Clocks (Rubidium Standards)    │
 │           ┌────────┐                         ┌────────┐                │
 │           │  GPS   │                         │ Atomic │                │
 │           └────┬───┘                         └───┬────┘                │
 │                ▼                                 ▼                     │
 │          ┌─────────────────────────────────────────────┐               │
 │          │         TrueTime Master Daemons             │               │
 │          │ Returns time as interval: [t.earliest, t.latest]            │
 │          │ Guaranteed clock uncertainty: ε ≤ 7 ms      │               │
 │          └──────────────────────┬──────────────────────┘               │
 └─────────────────────────────────┼──────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Commit Wait Algorithm:                                                  │
│ A transaction chooses commit timestamp s = t.latest.                    │
│ The transaction WAITS until TrueTime guarantees that the absolute time │
│ has passed s (wait duration: 2ε).                                       │
│ Result: Causal ordering across all continents without cross-globe locks!│
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Core Concepts

### 1. Compute Capacity: Processing Units (PUs) vs. Nodes

Spanner separates compute from storage:
* **Storage:** Managed automatically on Google's Colossus distributed filesystem, replicating data across zones/regions via Paxos consensus groups.
* **Compute Capacity:** Allocated in **Processing Units (PUs)**:
  * `100 PUs` = 0.1 of a traditional Spanner node (ideal for development and smaller services).
  * `1,000 PUs` = 1 full Spanner Node.
  * Autoscaling dynamically scales PUs based on CPU utilization and storage thresholds.

### 2. Multi-Region vs. Regional Configurations

| Configuration | Topology | Quorum / Leader | SLA |
| :--- | :--- | :--- | :--- |
| **Regional** | 3 read-write replicas across 3 zones in one region | Local Paxos quorum | **99.99%** (4 nines) |
| **Multi-Region** | 5+ replicas across multiple regions (e.g., `nam-eur-asia1`) | Witness and read-only replicas across continents | **99.999%** (5 nines) |

### 3. Schema Design: Interleaved Tables

In traditional relational databases, joining related tables across nodes involves costly network shuffles. Spanner solves this with **Interleaved Tables**:

```sql
-- Root table: Users
CREATE TABLE Users (
  UserId STRING(36) NOT NULL,
  Name STRING(100),
) PRIMARY KEY (UserId);

-- Child table: Orders physically co-located on disk with parent User row
CREATE TABLE Orders (
  UserId STRING(36) NOT NULL,
  OrderId STRING(36) NOT NULL,
  OrderTotal NUMERIC,
) PRIMARY KEY (UserId, OrderId),
  INTERLEAVE IN PARENT Users ON DELETE CASCADE;
```

* **Physical Co-location:** All orders belonging to `UserId = '123'` are stored on the **exact same physical storage server** as the parent user record, turning distributed joins into lightning-fast local memory lookups.

---

## Production `gcloud` CLI Commands

### 1. Creating a Spanner Instance with Granular Processing Units (PUs)

```bash
gcloud spanner instances create prod-spanner-db \
  --config=regional-us-central1 \
  --description="Production Core Banking Spanner" \
  --processing-units=400 \
  --edition=ENTERPRISE
```

### 2. Provisioning a Database with PostgreSQL Dialect

```bash
gcloud spanner databases create orders-db \
  --instance=prod-spanner-db \
  --database-dialect=POSTGRESQL
```

### 3. Configuring Instance Autoscaling

```bash
gcloud spanner instances update prod-spanner-db \
  --autoscaling-min-processing-units=200 \
  --autoscaling-max-processing-units=2000 \
  --autoscaling-high-priority-cpu-target=65 \
  --autoscaling-storage-target=75
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max storage per 1000 PUs (1 Node)** | 4 TB | Spanner forces compute scale-out if storage exceeds 4 TB/node |
| **Max mutations per commit** | 80,000 mutations | Batch large inserts into chunks |
| **Max transaction commit size** | 100 MB | Keep OLTP transactions compact |
| **Read throughput per 1000 PUs** | ~10,000 QPS (reads) | Benchmarked on 1 KB rows |
| **Write throughput per 1000 PUs** | ~2,000 QPS (writes) | Requires un-hotspotted primary keys |

---

## References

* **Homepage:** https://cloud.google.com/spanner
* **Documentation:** https://cloud.google.com/spanner/docs
* **Spanner TrueTime Paper:** https://research.google/pubs/pub39966/
* **Schema Design Best Practices:** https://cloud.google.com/spanner/docs/schema-and-data-model
* **Pricing:** https://cloud.google.com/spanner/pricing

---

## Pricing Examples

### Scenario 1: Entry-Level Production Database (Regional)
* Instance provisioned with 300 Processing Units (0.3 nodes) in `us-central1`.
* Storage footprint: 500 GB.
* Compute cost: 300 PUs = 0.3 nodes × $0.90 / hour × 730 hours = **$197.10 / month**.
* Storage cost: 500 GB × $0.30 / GB = **$150.00 / month**.
* Backups: 500 GB retained = $50.00 / month.
* **Total Monthly Cost:** **~$397.10 / month** for a resilient, auto-sharding relational DB.

### Scenario 2: Global Enterprise Financial Fabric (Multi-Region)
* Multi-region instance configuration (`nam3` - Iowa, South Carolina, Northern Virginia).
* 3 full nodes (3,000 PUs) running continuously for high-throughput global transactional ledger.
* Compute cost: 3 nodes × $4.50 / hour (multi-region rate) × 730 hours = **$9,855.00 / month**.
* Storage: 5 TB multi-region storage = 5,120 GB × $0.45 / GB = **$2,304.00 / month**.
* **Total Monthly Bill:** **~$12,159.00 / month** (Guarantees zero data loss and 5-nines 99.999% multi-region uptime).

---

## Nuggets & Gotchas

1. **The Monotonically Increasing Key Disaster (Hotspotting):** Using sequential IDs (`AUTO_INCREMENT`, sequential integers, or timestamps `2026-09-06T12:00:00Z`) as the first column of a primary key will **destroy Spanner's performance**. Because Spanner shards data by key ranges, all consecutive writes route to a single Paxos server, bottlenecking the entire cluster to 1 node's throughput. **Always use UUIDv4 or bit-reversed sequential hashes for primary keys.**
2. **The 4 TB Storage Quota Forces Compute Scaling:** Spanner enforces a strict rule: a single node (1,000 PUs) can manage at most 4 TB of storage. If your database reaches 8.1 TB, Spanner will mandate a minimum of 3 nodes (3,000 PUs) even if your CPU utilization is 2%! Your monthly compute bill will jump automatically to maintain storage sharding integrity.
3. **80,000 Mutations Limit per Commit:** A single transaction cannot exceed 80,000 mutations. Note that a "mutation" is **not** a single row: inserting 1 row into a table with 5 secondary indexes counts as 6 mutations! If you attempt to bulk-insert 15,000 rows in a single transaction, the commit will crash with `FAILED_PRECONDITION: The transaction contains too many mutations`.
4. **Stale Reads for High-Throughput Analytics:** If your query does not require real-time read-your-writes consistency, use **Stale Reads** (`read_timestamp` set to 15 seconds in the past). Stale reads bypass Paxos leader leases entirely and execute on local replicas without locking or impacting active write transactions.
5. **Schema Changes Run Asynchronous Background Jobs:** Running `ALTER TABLE` in Spanner does not lock tables or block reads/writes. However, adding a secondary index to an existing 100-million-row table triggers a massive background backfill process across all storage splits that can take several hours to complete.

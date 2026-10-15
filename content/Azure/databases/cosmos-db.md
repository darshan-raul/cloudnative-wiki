---
title: Azure Cosmos DB
description: Exhaustive engineering guide to Azure Cosmos DB — resource hierarchy, multi-model APIs, Request Units (RUs), 5 consistency levels, partition key strategy, and autoscale throughput.
tags:
  - azure
  - databases
  - cosmos-db
  - nosql
  - distributed-systems
  - multi-model
date: 2026-10-16
---

# Azure Cosmos DB 🪐⚡

**Azure Cosmos DB** is Microsoft's globally distributed, multi-model NoSQL and relational database service. Designed for mission-critical cloud applications requiring single-digit millisecond latency at any scale, Cosmos DB features automatic multi-region data replication, turnkey global active-active writes, and a financially backed **99.999% availability SLA**.

Under the hood, Cosmos DB separates its distributed storage engine from multiple wire-protocol APIs, normalizing all operations into a unified throughput currency: **Request Units (RUs)**.

---

## 1. Single-Service Fundamentals & Mental Models

### The 4-Tier Resource Hierarchy

Cosmos DB organizes data into a strict four-level containment model:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│               COSMOS DB ACCOUNT: cosmos-prod-global (Global Entity)                    │
│               Endpoint: https://cosmos-prod-global.documents.azure.com:443/           │
│                                                                                        │
│  - API Model (NoSQL, MongoDB, Cassandra, Gremlin, Table, PostgreSQL)                   │
│  - Multi-Region Replication Topology (e.g., East US [Write], West US [Write])         │
│  - Default Consistency Level (Session, Strong, Bounded Staleness, etc.)               │
│  - Network Security: Firewall, VNet Service Endpoints, Private Link Endpoint          │
│  - Total Account Storage & Aggregate Throughput Caps                                   │
│                                                                                        │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ DATABASE: store-db (Logical Management Scope)                                  │   │
│   │ - Optional: Shared Database Throughput Pool (e.g. 10,000 RU/s shared)          │   │
│   │ - User & Permission Management Scope                                           │   │
│   │                                                                                │   │
│   │   ┌────────────────────────────────────────────────────────────────────────┐   │   │
│   │   │ CONTAINER / COLLECTION: orders (Scalability & Partition Boundary)       │   │   │
│   │   │ - Dedicated Throughput (e.g. Autoscale 4,000–40,000 RU/s)              │   │   │
│   │   │ - Mandatory Partition Key Definition (e.g. /customerId)                │   │   │
│   │   │ - Automatic & Custom Indexing Policies (Included/Excluded Paths)       │   │   │
│   │   │ - Time to Live (TTL) Configuration (Auto-expiring documents)           │   │   │
│   │   │ - Unique Key Constraints & Change Feed Output                          │   │   │
│   │   │                                                                        │   │   │
│   │   │   ┌────────────────────────────────────────────────────────────────┐   │   │   │
│   │   │   │ ITEMS / DOCUMENTS (JSON Document / Row / Vertex)               │   │   │   │
│   │   │   │ { "id": "ord-9481", "customerId": "c-100", "total": 129.50 }   │   │   │   │
│   │   │   └────────────────────────────────────────────────────────────────┘   │   │   │
│   │   └────────────────────────────────────────────────────────────────────────┘   │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### Multi-Model APIs & Wire Protocol Abstraction

Cosmos DB's core storage engine is the **Atom-Record-Sequence (ARS)** engine. Multiple database personalities are projected onto this engine via protocol parsers:

| API Flavor                 | Data Model               | Native Query Protocol                   | Ideal Use Case                                                                               |
| :------------------------- | :----------------------- | :-------------------------------------- | :------------------------------------------------------------------------------------------- |
| **NoSQL API (Core / SQL)** | JSON Documents           | SQL syntax (`SELECT * FROM c WHERE...`) | **Default choice for 90% of new cloud-native apps**; supports deepest Cosmos DB feature set. |
| **MongoDB API**            | BSON Documents           | MongoDB wire protocol (v4.0 / v4.2)     | Lift-and-shift of existing MongoDB apps without driver or query code changes.                |
| **Apache Cassandra API**   | Wide-column Tabular      | Cassandra Query Language (CQL v4)       | Migrating on-prem Apache Cassandra clusters while eliminating node patching.                 |
| **Table API**              | Key-Value Entities       | Azure Table Storage SDKs                | Seamless migration from legacy Azure Storage Tables to high-performance dedicated RUs.       |
| **Apache Gremlin API**     | Graph (Vertices & Edges) | Apache TinkerPop / Gremlin              | Social graphs, recommendation engines, fraud networks, and relationship traversal.           |
| **PostgreSQL API**         | Distributed Relational   | Native PostgreSQL + Citus extension     | Distributed SQL requiring ACID transactions, joins, and foreign keys across worker nodes.    |

> [!NOTE]
> The API flavor is locked **at account creation time** and cannot be changed. Choose the NoSQL API unless migrating legacy code from MongoDB, Cassandra, or Gremlin.

### Throughput Provisioning Scope: Container vs. Database

1. **Dedicated Container Throughput:** Provisioned directly on a single container (e.g. 5,000 RU/s). Guarantees that this specific container always has full throughput reserved, isolated from other tables.
2. **Shared Database Throughput (Elastic Pool):** Provisioned at the database level (e.g. 10,000 RU/s) and shared dynamically across all containers in that database. Ideal when you have 10+ collections with variable, unpredictable traffic patterns where dedicating fixed RUs to each container would be cost-prohibitive.

---

## 2. Request Units (RUs): The Currency of Throughput

Cosmos DB normalizes CPU, memory, and disk IOPS across database operations into a single deterministic currency: **Request Units per second (RU/s)**:

- **1 RU Baseline Benchmark:** The exact compute and I/O cost required to perform a **point read** of a **1 KB item** by its `id` and partition key.
- **Write Cost:** Writing a 1 KB item costs **~5–7 RUs** due to indexing and cross-replica quorum synchronization.
- **Query Cost:** Complex queries involving filters, cross-partition scans, aggregations, or regex matching consume RUs proportional to data processed and index utilization.

### Throughput Modes: Serverless vs. Provisioned vs. Autoscale

| Throughput Mode          | Financial Billing Model                            | Scaling Characteristics                                                             | Best Production Fit                                                                         |
| :----------------------- | :------------------------------------------------- | :---------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------ |
| **Serverless**           | Strictly pay-per-request ($0.25 per 1M RUs)        | Scales automatically from **0 to 5,000 RU/s**; no hourly base charge.               | Dev/test, low traffic, and bursty microservices (< 5,000 RU/s).                             |
| **Standard Provisioned** | Fixed hourly fee per 100 RU/s ($0.008 / 100 RU/hr) | Static allocation; manual CLI/API adjustment.                                       | Predictable 24/7 background ingestion engines with steady state load.                       |
| **Autoscale (Default)**  | Hourly fee per 100 RU/s max ($0.012 / 100 RU/hr)   | **Instantly scales between 10% and 100% of max RU/s** (e.g., 4,000 to 40,000 RU/s). | **Enterprise production standard**: Unpredictable consumer web traffic and seasonal surges. |

---

## 3. The 5 Consistency Levels Spectrum

Traditional databases force an architectural compromise between Strong (ACID) and Eventual (BASE) consistency. Cosmos DB provides five mathematically defined consistency levels:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Cosmos DB Consistency Spectrum                  │
│                                                                        │
│ Strong ──► Bounded Staleness ──► Session ──► Consistent Prefix ──► Eventual
│                                  (Default)                             │
├────────────────────────────────┬───────────────────────────────────────┤
│ High Consistency / Higher Cost │ Low Consistency / Maximum Throughput  │
│ Strict linearizability; reads  │ Reads may lag behind writes; lowest   │
│ guaranteed latest commit       │ RU cost; lowest latency               │
└────────────────────────────────┴───────────────────────────────────────┘
```

1. **Strong:** Strict linearizability. Reads are guaranteed to see the latest committed write. Requires regional synchronous quorum; **cannot be used on multi-region write accounts**.
2. **Bounded Staleness:** Reads lag behind writes by at most $K$ versions (e.g. 100,000 updates) or $T$ time intervals (e.g. 5 seconds). The highest consistency level supported for multi-region accounts.
3. **Session (Default):** Guarantees **read-your-own-writes** and monotonic reads within a single client session. Ideal for 90% of web and mobile applications.
4. **Consistent Prefix:** Guarantees readers never see out-of-order writes (e.g., if updates occur as $A \to B \to C$, a client never observes $C$ before $B$).
5. **Eventual:** Out-of-order, best-effort reads. Delivers the lowest latency and lowest RU query consumption.

---

## 4. Partition Key Strategy: Logical vs. Physical Partitions

Cosmos DB scales horizontally by distributing documents across **Physical Partitions** managed entirely by the Azure fabric:

```
                            Partition Key Distribution
                                        │
             ┌──────────────────────────┴──────────────────────────┐
             ▼                                                     ▼
[ Physical Partition 1 (Max 50 GB / 10k RU) ] [ Physical Partition 2 (Max 50 GB / 10k RU) ]
  ├── Logical Partition: customerId = "c-100"   ├── Logical Partition: customerId = "c-300"
  └── Logical Partition: customerId = "c-200"   └── Logical Partition: customerId = "c-400"
```

- **Logical Partitions:** Formed by documents sharing the exact same partition key value. **A single logical partition cannot exceed 20 GB of storage.**
- **Physical Partitions:** Transparent Azure compute/storage nodes holding up to **50 GB of storage** and capped at **10,000 RU/s maximum**.
- **RU Distribution Rule:** Provisioned RU/s is **divided evenly** across all physical partitions. If an account has 5 physical partitions and 10,000 RU/s provisioned, each physical partition receives exactly **2,000 RU/s**.

---

## 5. Production `az` CLI Workflows

### 1. Provisioning a Multi-Region Cosmos DB Account with Autoscale

```bash
# 1. Create Resource Group
az group create --name rg-data-prod --location eastus

# 2. Provision Multi-Region Cosmos DB Account with Multi-Region Writes Enabled
az cosmosdb create \
  --resource-group rg-data-prod \
  --name cosmos-ecommerce-prod \
  --default-consistency-level Session \
  --locations regionName=eastus failoverPriority=0 isZoneRedundant=true \
  --locations regionName=westeurope failoverPriority=1 isZoneRedundant=true \
  --enable-multiple-write-locations true \
  --enable-free-tier false

# 3. Create SQL Database with Shared Throughput
az cosmosdb sql database create \
  --resource-group rg-data-prod \
  --account-name cosmos-ecommerce-prod \
  --name orders-db

# 4. Create Container with Autoscale Throughput (Max 10,000 RU/s) and Partition Key
az cosmosdb sql container create \
  --resource-group rg-data-prod \
  --account-name cosmos-ecommerce-prod \
  --database-name orders-db \
  --name orders \
  --partition-key-path "/customerId" \
  --max-throughput 10000 \
  --ttl 2592000
```

---

## 6. Quotas & Limits

| Parameter                                 | Limit                         | Architectural Guidance                                                  |
| :---------------------------------------- | :---------------------------- | :---------------------------------------------------------------------- |
| **Max Logical Partition Size**            | 20 GB per partition key       | Use high-cardinality keys to prevent partition overflow                 |
| **Max Throughput per Physical Partition** | 10,000 RU/s                   | Avoid hot partition bottlenecks                                         |
| **Max Document / Item Size**              | 2 MB per JSON document        | Offload large blobs/images to Azure Blob Storage                        |
| **Max Containers per Account**            | Unlimited (soft limit per DB) | Consolidate schemas into shared containers using a `type` discriminator |
| **Multi-Region Availability SLA**         | 99.999%                       | Requires multi-region writes or automatic failover                      |

---

## 7. Pricing Examples

### Scenario 1: Intermittent Microservice with Serverless Tier

- **Usage:** 50 million reads (1 KB each = 50M RUs) + 10 million writes (1 KB each = ~5 RUs each = 50M RUs) per month.
- **Total RUs:** 100 million RUs / month.
- **Serverless Rate:** $0.25 per 1 million RUs = **$25.00 / month**.
- **Storage:** 20 GB @ $0.25 / GB = **$5.00 / month**.
- **Total Cost:** **$30.00 / month**.

### Scenario 2: Global Active-Active E-Commerce Platform (Autoscale)

- **Configuration:** Multi-region writes across 2 regions (`East US` and `West Europe`).
- **Autoscale Throughput:** Max 20,000 RU/s per region (scales down to 2,000 RU/s off-peak; average 6,000 RU/s).
- **Compute Billing:**
  - 60 units of 100 RU/s × $0.012 / hr × 730 hrs = ~$525.60 per region.
  - Across 2 active write regions: 2 × $525.60 = **$1,051.20 / month**.
- **Storage Billing:** 100 GB replicated across 2 regions = 200 GB @ $0.25 / GB = **$50.00 / month**.
- **Total Monthly Investment:** **~$1,101.20 / month** for sub-10ms writes worldwide with 99.999% SLA.

---

## 8. Battle-Tested Nuggets & Gotchas

1. **The "Hot Partition" 429 Throttle Trap:** Choosing a low-cardinality partition key (e.g. `country` or `orderStatus`) forces all writes for `"US"` or `"PENDING"` onto the **same physical partition**. Regardless of provisioning 50,000 RU/s, that single partition is hard-capped at **10,000 RU/s**, triggering immediate `HTTP 429: Request rate too large`. Always choose high-cardinality keys with even write distribution (e.g. `userId` or `uuid`).
2. **Cross-Partition Queries Multiply RU Burn:** When a query filters on the partition key (`WHERE c.customerId = '123'`), Cosmos DB routes directly to one partition. Omitting the partition key (`SELECT * FROM c WHERE c.status = 'active'`) executes a **fan-out cross-partition query** against every physical partition in parallel, multiplying RU consumption exponentially.
3. **Multi-Region Writes Duplicates RU Billing:** Enabling multi-region writes replicates provisioned throughput across every regional replica. Provisioning 10,000 RU/s on an account with 3 regions bills for **30,000 RU/s**.
4. **The 20 GB Logical Partition Limit Is Immutable:** A single logical partition key value cannot exceed 20 GB. If an enterprise tenant accumulates 20 GB under one key, subsequent inserts are rejected. For high-volume entities, construct **synthetic partition keys** (e.g. `customerId_YYYY-MM`).
5. **Session Consistency Requires Passing Session Tokens:** Under Session consistency, client SDK requests must supply the `x-ms-session-token` header. If a multi-tier web application uses a stateless load balancer that drops the session cookie across requests, end users may observe out-of-order reads.

---

## Across the Wiki

- [[Azure/databases/README|Azure Databases Hub]] — Master architectural directory for Azure databases
- [[Azure/databases/azure-sql|Azure SQL Database & Managed Instance]] — Enterprise relational SQL workloads
- [[Azure/databases/postgres-flexible/README|Azure Database for PostgreSQL Flexible Server]] — Open-source relational database
- [[AWS/databases/dynamodb/README|Amazon DynamoDB]] — Distributed NoSQL database in AWS
- [[GCP/databases/firestore/README|Google Cloud Firestore]] — Serverless document NoSQL in GCP

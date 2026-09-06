---
title: Azure Cosmos DB
description: Azure Cosmos DB architecture — Request Units (RUs), multi-region active-active writes, 5 consistency levels, partition key design, and Autoscale throughput.
tags:
  - azure
  - databases
  - cosmos-db
  - nosql
  - distributed-systems
---

# Azure Cosmos DB 🪐⚡

Azure Cosmos DB is Microsoft's globally distributed, multi-model NoSQL database service. Cosmos DB provides single-digit millisecond response times at any scale, automatic global distribution, and a financially backed **99.999% availability SLA** for multi-region multi-master deployments.

---

## Architecture & Mental Model

### The 5 Consistency Levels Spectrum

Unlike traditional databases that force a binary choice between Strong and Eventual consistency, Cosmos DB provides five mathematically defined consistency levels:

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

1. **Strong:** Strict linearizability. All reads guaranteed to see the latest committed write. Requires regional quorum; not supported for multi-region write accounts.
2. **Bounded Staleness:** Reads lag behind writes by at most $K$ versions or $T$ time intervals (e.g. 5 seconds or 100,000 updates).
3. **Session (Default):** Guarantees **read-your-own-writes** within a single client session. The most popular choice for web and mobile apps.
4. **Consistent Prefix:** Guarantees reads never see out-of-order updates (e.g. if writes are $A \to B \to C$, client never sees $C$ before $B$).
5. **Eventual:** Out-of-order, best-effort reads. Highest throughput and lowest RU cost.

---

## Core Concepts

### 1. Request Units (RUs): The Currency of Throughput

Cosmos DB normalizes all database operations (reads, writes, queries, stored procedures) into **Request Units per second (RU/s)**:
* **Baseline Benchmark:** **1 RU** corresponds to the compute and I/O required to read a **1 KB item** by its `id` and partition key.
* Writing a 1 KB item typically costs **~5–7 RUs** due to indexing and replication.

### 2. Throughput Modes: Autoscale vs. Provisioned vs. Serverless

| Throughput Mode | Mechanics | Best For |
| :--- | :--- | :--- |
| **Serverless** | Pay strictly per RU consumed ($0.25 per million RUs); scales to 0 | Dev/test, low traffic, intermittent burst apps (< 5,000 RU/s) |
| **Standard Provisioned** | Pre-allocated hourly capacity (e.g. fixed 10,000 RU/s) | Predictable, sustained 24/7 background workloads |
| **Autoscale (Default)** | Set max RU/s (e.g. 10,000); instantly scales between **10% and 100%** (1,000 to 10,000 RU/s) | Production apps with unpredictable traffic surges |

### 3. Partition Key Strategy: Logical vs. Physical Partitions

* **Logical Partitions:** Defined by the value of your chosen partition key (e.g. `tenantId = "cust-100"`). Max size: **20 GB per logical partition**.
* **Physical Partitions:** Managed internally by Azure. Each physical partition holds up to **50 GB of storage** and can deliver a maximum of **10,000 RU/s**.
* **Provisioned Throughput Distribution:** Throughput is distributed **evenly** across all physical partitions!
  * If you have 5 physical partitions and provision 10,000 RU/s, each partition gets **2,000 RU/s**.

---

## Production `az` CLI Commands

### 1. Provisioning a Multi-Region Cosmos DB Account with Autoscale

```bash
# 1. Create the Cosmos DB account across two regions (East US + West US)
az cosmosdb create \
  --resource-group prod-data-rg \
  --name cosmos-global-core \
  --default-consistency-level Session \
  --locations regionName=eastus failoverPriority=0 isZoneRedundant=true \
  --locations regionName=westus failoverPriority=1 isZoneRedundant=false \
  --enable-multiple-write-locations true

# 2. Create the Database
az cosmosdb sql database create \
  --resource-group prod-data-rg \
  --account-name cosmos-global-core \
  --name core-db

# 3. Create a Container with Autoscale Throughput (Max 10,000 RU/s) and Partition Key
az cosmosdb sql container create \
  --resource-group prod-data-rg \
  --account-name cosmos-global-core \
  --database-name core-db \
  --name orders \
  --partition-key-path "/customerId" \
  --max-throughput 10000
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max logical partition size** | 20 GB per partition key value | Crucial: Choose high-cardinality keys |
| **Max throughput per physical partition** | 10,000 RU/s | Partition hot spotting causes 429 errors |
| **Item size limit** | 2 MB per document | Compress or store attachments in Blob Storage |
| **Multi-region write SLA** | 99.999% availability | Guaranteed < 10ms read/write latency |

---

## References

* **Homepage:** https://azure.microsoft.com/en-us/products/cosmos-db
* **Cosmos DB Documentation:** https://learn.microsoft.com/en-us/azure/cosmos-db/
* **Request Units Overview:** https://learn.microsoft.com/en-us/azure/cosmos-db/request-units
* **Consistency Levels Deep Dive:** https://learn.microsoft.com/en-us/azure/cosmos-db/consistency-levels
* **Pricing:** https://azure.microsoft.com/en-us/pricing/details/cosmos-db/

---

## Pricing Examples

### Scenario 1: Intermittent Microservice with Serverless Tier
* Service processes 50 million reads and 10 million writes / month.
* Reads (1 KB each = 1 RU): 50,000,000 RUs.
* Writes (1 KB each = ~5 RUs): 50,000,000 RUs.
* Total consumed RUs: 100 million RUs / month.
* Serverless rate: $0.25 per 1 million RUs = **$25.00 / month**.
* Storage (20 GB @ $0.25 / GB): $5.00 / month.
* **Total Monthly Bill:** **$30.00 / month**.

### Scenario 2: Global Active-Active E-Commerce Platform (Autoscale)
* Multi-region write account in 2 regions (`East US` and `West Europe`).
* Autoscale max set to 20,000 RU/s per region (scales down to 2,000 RU/s during off-peak).
* Average consumption: 6,000 RU/s per region across the month.
* Autoscale RU rate: $0.012 per 100 RU/s per hour.
* Compute cost per region: 60 units of 100 RU/s × $0.012 × 730 hrs = ~$525.60.
* Multi-region total (2 regions): 2 × $525.60 = **$1,051.20 / month**.
* Storage (100 GB replicated = 200 GB @ $0.25 = $50.00).
* **Total Monthly Cost:** **~$1,101.20 / month** (Delivers sub-10ms writes worldwide with 5-nines SLA).

---

## Nuggets & Gotchas

1. **The "Hot Partition" 429 Throttle Trap:** If you choose a low-cardinality partition key (e.g. `country` or `orderStatus`), all writes for `"US"` or `"COMPLETED"` hit the **same physical partition**. Even if your container has 50,000 RU/s provisioned, that single physical partition is hard-capped at **10,000 RU/s**. Your application will immediately be throttled with `HTTP 429: Request rate too large`. Always choose high-cardinality keys with even write distribution (e.g. `userId` or `uuid`).
2. **Cross-Partition Queries Burn Massive RUs:** When a query includes the partition key (`WHERE customerId = '123'`), Cosmos DB routes the query to a single partition. If you omit the partition key (`SELECT * FROM c WHERE c.status = 'active'`), Cosmos DB must execute a **fan-out cross-partition query** querying every single physical partition in parallel, multiplying RU consumption by the number of partitions!
3. **Multi-Region Writes Double Throughput Billing:** Enabling multi-region writes duplicates your provisioned RU/s across every region in the account. If you provision 10,000 RU/s on an account with 3 regions, you are billed for **30,000 RU/s**.
4. **The 20 GB Logical Partition Limit Is Immutable:** A single logical partition key value cannot exceed 20 GB of storage. If an enterprise customer's partition exceeds 20 GB, inserts for that customer key will be rejected with an error. For massive entities, construct **synthetic partition keys** (e.g. `customerId_YYYY-MM`).
5. **Session Consistency Requires Forwarding Session Tokens:** To guarantee read-your-own-writes under Session consistency, client requests must pass the `x-ms-session-token` header back to Cosmos DB. If a multi-tier web application uses a stateless load balancer and does not preserve the session token cookie across requests, the client may experience out-of-order reads.

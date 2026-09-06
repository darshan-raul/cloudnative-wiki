---
title: Google BigQuery
description: BigQuery architecture — Dremel execution engine, Capacitor columnar storage, slot allocations, partitioned/clustered tables, and on-demand vs edition pricing.
tags:
  - gcp
  - databases
  - bigquery
  - analytics
  - data-warehouse
---

# Google BigQuery 📊⚡

Google BigQuery is a serverless, highly scalable, cost-effective enterprise data warehouse designed for business agility. BigQuery separates compute from storage entirely, allowing each layer to scale independently on Google's global infrastructure without provisioning clusters, tuning indexing, or managing vacuum operations.

---

## Architecture & Mental Model

### The Four Pillars of BigQuery

BigQuery's ability to scan petabytes of data in seconds relies on four foundational Google technologies:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        BigQuery Internal Stack                         │
├────────────────────────────────────────────────────────────────────────┤
│ 1. Dremel: Distributed Execution Engine                                │
│    Transforms SQL into a massive execution tree across thousands of    │
│    parallel worker nodes ("Slots").                                    │
├────────────────────────────────────────────────────────────────────────┤
│ 2. Jupiter Network: Petabit Datacenter Fabric                          │
│    Connects Dremel compute workers to Colossus storage at 100 Gbps+    │
│    per server with petabits of bisection bandwidth.                    │
├────────────────────────────────────────────────────────────────────────┤
│ 3. Colossus: Distributed File System                                   │
│    Provides exabyte-scale durability, replication, and encryption.     │
├────────────────────────────────────────────────────────────────────────┤
│ 4. Capacitor: Columnar Storage Format                                  │
│    Optimizes column layout, dictionary compression, and run-length     │
│    encoding directly on storage blocks.                                │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Core Concepts

### 1. Partitioning vs. Clustering

Optimizing query speed and reducing cost in BigQuery relies on limiting the number of bytes scanned from disk:

```
Unoptimized Table: 10 TB scanned ($62.50 query)
┌──────────────────────────────────────────────────────────┐
│ All Records (2020 - 2026) in a single massive table      │
└──────────────────────────────────────────────────────────┘

Partitioned by Date: 500 GB scanned ($3.12 query)
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  2026-09-01  │ │  2026-09-02  │ │  2026-09-03  │ │  2026-09-04  │
└──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘

Clustered by customer_id within Partition: 15 GB scanned ($0.09 query)
┌────────────────────────────────────────────────────────┐
│ Sorted & grouped blocks: [cust_100-200] [cust_201-300] │
└────────────────────────────────────────────────────────┘
```

* **Partitioning:** Segregates data into physical date, timestamp, or integer-range blocks (up to 4,000 partitions per table).
* **Clustering:** Automatically sorts data based on the contents of up to four specified columns (e.g., `customer_id`, `country`). BigQuery skips unneeded blocks during query execution.

### 2. Pricing Models: On-Demand vs. Editions (Capacity)

| Dimension | On-Demand (Per-Query) | BigQuery Editions (Slots) |
| :--- | :--- | :--- |
| **Billing Basis** | Billed on **bytes scanned** by queries ($6.25 per TB) | Billed per **Slot-Hour** (CPU/RAM compute workers) |
| **Concurrency** | Shared pool of up to 2,000 burst slots | Dedicated or autoscaling slots allocated to reservations |
| **Predictability** | High variability (one runaway query can scan 20 TB) | Predictable, capped monthly infrastructure spend |
| **Best For** | Ad-hoc analytics, small datasets, variable dev teams | Enterprise ETL, continuous streaming ingestion, BI dashboards |

### 3. BigQuery ML (Machine Learning via SQL)

Allows data analysts to train and evaluate ML models directly inside BigQuery using standard SQL syntax without exporting data to Python or external training pipelines:

```sql
-- Train a customer churn prediction model directly on warehouse data
CREATE OR REPLACE MODEL `prod_analytics.churn_model`
OPTIONS(model_type='LOGISTIC_REG', input_label_cols=['has_churned']) AS
SELECT
  account_age_days,
  total_spend,
  support_tickets_count,
  has_churned
FROM `prod_analytics.user_metrics`
WHERE partition_date >= '2026-01-01';
```

---

## Production `gcloud` CLI & SQL Commands

### 1. Creating a Partitioned & Clustered Table

```sql
CREATE TABLE `my-prod-project.analytics.orders`
(
  order_id STRING NOT NULL,
  customer_id STRING NOT NULL,
  order_timestamp TIMESTAMP NOT NULL,
  order_total NUMERIC,
  shipping_country STRING
)
PARTITION BY DATE(order_timestamp)
CLUSTER BY customer_id, shipping_country
OPTIONS(
  partition_expiration_days = 730,
  require_partition_filter = TRUE
);
```

* `--require_partition_filter = TRUE`: **Critical guardrail** that prevents developers from accidentally running `SELECT *` without a `WHERE date >= ...` filter.

### 2. Running a Dry-Run to Predict Query Cost Before Execution

```bash
# Calculate exact bytes to be scanned without executing or paying for the query
bq query \
  --use_legacy_sql=false \
  --dry_run \
  "SELECT customer_id, SUM(order_total) FROM \`my-prod-project.analytics.orders\` WHERE DATE(order_timestamp) = '2026-09-01' GROUP BY customer_id;"
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max partitions per table** | 4,000 partitions | E.g. ~10 years of daily partitions |
| **Max columns per table** | 10,000 columns | Supports wide schema designs |
| **Max query execution time** | 6 hours | Queries exceeding 6 hrs are aborted |
| **Concurrent on-demand queries** | 300 concurrent queries | Queued automatically if limit exceeded |
| **Free Tier Allowance** | 1 TB query scans + 10 GB storage | Free every month per billing account |

---

## References

* **Homepage:** https://cloud.google.com/bigquery
* **Documentation:** https://cloud.google.com/bigquery/docs
* **Partitioning & Clustering Guide:** https://cloud.google.com/bigquery/docs/partitioned-tables
* **BigQuery Editions (Slots):** https://cloud.google.com/bigquery/docs/editions-intro
* **Pricing:** https://cloud.google.com/bigquery/pricing

---

## Pricing Examples

### Scenario 1: Optimized On-Demand Analytics Team
* 20 Data Analysts executing ad-hoc reporting queries.
* Total unoptimized potential scan: 250 TB / month.
* With partition pruning and clustering, actual scanned bytes reduced by 90% to 25 TB.
* Query Cost: 25 TB × $6.25 / TB = **$156.25 / month**.
* Active Storage: 5 TB active × $0.02 / GB = $102.40 / month.
* Long-Term Storage (untouched for 90 days): 15 TB × $0.01 / GB = $153.60 / month.
* **Total Monthly Cost:** **~$412.25 / month**.

### Scenario 2: Enterprise BigQuery Edition (Autoscaling Slots)
* Large enterprise running mission-critical real-time BI dashboards with continuous Looker queries.
* **Enterprise Edition Reservation:** 100 baseline slots with autoscaling up to 300 slots during peak hours.
* Average usage: 150 slot-hours continuously throughout the month (109,500 slot-hours).
* Enterprise slot-hour rate: ~$0.06 / slot-hour.
* Compute cost: 109,500 × $0.06 = **$6,570.00 / month**.
* Storage (50 TB): ~$1,000.00.
* **Total Monthly Bill:** **~$7,570.00 / month** (Eliminates all per-query byte charges; unlimited ad-hoc scans).

---

## Nuggets & Gotchas

1. **`SELECT *` Is the Number One Source of Cloud Bill Shock:** Because BigQuery charges $6.25 per TB based on the **columns referenced** in the query (due to Capacitor's columnar format), executing `SELECT * FROM massive_table` scans every single column across all partitions. If the table is 20 TB, that single test query costs **$125.00**! Always specify explicit column names and enforce `require_partition_filter`.
2. **Long-Term Storage Automatic 50% Discount:** If a table or partition remains unmodified for **90 consecutive days**, BigQuery automatically drops its storage price by **50%** (from $0.020/GB to $0.010/GB) with zero degradation in read performance. However, performing an `UPDATE` or appending a row to a 3-year-old partition resets the 90-day timer back to day zero!
3. **Partition Limits and Granularity:** BigQuery caps tables at 4,000 partitions. If you partition by hour instead of day, you will exhaust your partition ceiling in under 166 days (`4000 / 24`). Use hourly partitioning only for high-throughput, short-retention ingestion buffers.
4. **Streaming Ingestion Buffer Latency:** Data inserted via the Storage Write API or legacy streaming buffer is immediately available for querying in real time. However, data in the streaming buffer is held in temporary memory before being compacted into Capacitor files on Colossus; during this 90-minute window, `UPDATE` and `DELETE` operations on those specific streaming rows will fail with `UPDATE or DELETE statement over table would affect rows in the streaming buffer`.
5. **Clustering Column Order Matters:** When clustering by multiple columns (e.g. `CLUSTER BY department, employee_id`), column order determines filter efficiency. Queries filtering on `department` will efficiently prune blocks, but queries filtering *only* on `employee_id` without specifying `department` will see significantly less clustering optimization.

---
title: Amazon Redshift
description: Amazon Redshift — petabyte-scale data warehouse. RA3 nodes, spectrum, concurrency scaling, distribution styles, sort keys, WLM, and ML integration.
tags:
  - aws
  - databases
  - analytics
  - redshift
  - data-warehouse
---

# Amazon Redshift

Redshift is a petabyte-scale data warehouse based on PostgreSQL. It uses columnar storage, massive parallel processing (MPP), and compression to deliver fast analytical queries on large datasets. Designed for OLAP (analytics, BI, reporting), not OLTP.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Client (SQL client, BI tool)                           │
│    └─► Leader Node (SQL coordination, metadata)          │
│            │                                            │
│            ▼                                            │
│  ┌─────────────────────────────────────────────────┐  │
│  │  Compute Layer (2-128 compute nodes)             │  │
│  │                                                  │  │
│  │  Node 1         Node 2         Node 3             │  │
│  │  ┌────────┐    ┌────────┐    ┌────────┐         │  │
│  │  │ Slice  │    │ Slice  │    │ Slice  │         │  │
│  │  │ (CPU)  │    │ (CPU)  │    │ (CPU)  │         │  │
│  │  └────────┘    └────────┘    └────────┘         │  │
│  │                                                  │  │
│  │  Local disk (columnar storage per slice)         │  │
│  └─────────────────────────────────────────────────┘  │
│            │                                            │
│            ▼                                            │
│  ┌─────────────────────────────────────────────────┐  │
│  │  Redshift Managed Storage (RMS)                  │  │
│  │  (S3-backed, auto-scales)                        │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Node Types

### RA3 (Current Generation)

RA3 nodes use managed storage — separate compute from storage:

| Node | vCPU | S3 Storage | Managed Storage Cost |
|------|------|-----------|---------------------|
| ra3.xlplus | 4 | Local NVMe | $0.024/GB/month |
| ra3.4xlarge | 12 | Local NVMe | $0.024/GB/month |
| ra3.16xlarge | 48 | Local NVMe | $0.024/GB/month |

Use RA3 when you need to scale storage independently from compute.

### Dense Storage (DS2) — Previous Gen

HDD-based, for very large cold data:
- ds2.xlarge (4 vCPU, 2TB HDD)
- ds2.8xlarge (36 vCPU, 16TB HDD)

### Dense Compute (DC2) — Previous Gen

SSD-based, for high-performance:
- dc1.large (4 vCPU, 0.16TB SSD)
- dc2.8xlarge (32 vCPU, 1TB SSD)

## Creating a Cluster

```bash
aws redshift create-cluster \
  --cluster-identifier my-redshift \
  --node-type ra3.4xlarge \
  --number-of-nodes 3 \
  --master-username admin \
  --master-user-password SecretPassword \
  --cluster-subnet-group-name my-subnet-group \
  --vpc-security-group-ids sg-xxxxx \
  --enhanced-vpc-routing \
  --automated-snapshot-retention-period 7
```

## Distribution Styles

How data is distributed across nodes:

### KEY

```sql
CREATE TABLE orders (
  order_id INT,
  customer_id INT,
  amount NUMERIC
)
DISTKEY(customer_id);  -- Same customer goes to same slice
```

Use when: large table joined frequently with dimension table on a key.

### ALL

```sql
CREATE TABLE customers (
  id INT,
  name VARCHAR
)
DISTSTYLE ALL;  -- Full copy on every node
```

Use when: small dimension tables (< 10M rows).

### EVEN

```sql
CREATE TABLE events (
  id INT,
  event_type VARCHAR
)
DISTSTYLE EVEN;  -- Round-robin distribution
```

Default. Use when: no clear distribution key, or table is huge with no obvious join key.

## Sort Keys

Order of data within each slice (like an index):

```sql
CREATE TABLE sales (
  id INT,
  sale_date DATE,
  amount NUMERIC
)
SORTKEY(sale_date);  -- Orders by date
```

Types:
- **Compound** — standard, first column used most
- **Interleaved** — equal weight to all columns (higher maintenance overhead)

Use when: queries filter or sort by the same column frequently.

## Loading Data

### COPY (from S3)

```sql
COPY orders
FROM 's3://my-bucket/data/orders/'
CREDENTIALS 'aws_iam_role=arn:aws:iam::123456789012:role/redshift-role'
DELIMITER ','
GZIP
IGNOREHEADER 1
REMOVEQUOTES
BLANKSASNULL
DATEFORMAT 'YYYY-MM-DD';
```

### UNLOAD (to S3)

```sql
UNLOAD ('SELECT * FROM sales WHERE sale_date >= '2024-01-01'')
TO 's3://my-bucket/reports/sales_2024'
CREDENTIALS 'aws_iam_role=arn:aws:iam::123456789012:role/redshift-role'
FORMAT AS PARQUET
PARTITION BY (sale_date);
```

### From DynamoDB

```sql
CREATE EXTERNAL TABLE dynamo_orders (
  order_id INT,
  customer_id INT
)
STORAGE ('location' = 's3://my-bucket/dynamo/')
FORMAT AS JSON 'auto';

-- Then INSERT INTO ... SELECT * FROM dynamo_orders;
```

## Spectrum (Redshift Spectrum)

Query data directly in S3 without loading:

```sql
-- Create external table (points to S3)
CREATE EXTERNAL TABLE spectrum_orders (
  order_id INT,
  customer_id INT,
  amount NUMERIC
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3://my-bucket/spectrum/orders/';

-- Query it
SELECT * FROM spectrum_orders WHERE amount > 100;
```

Spectrum uses Athena under the hood. You pay for data scanned ($5/TB).

## WLM (Workload Management)

Priority-based query queuing:

```sql
-- Set WLM configuration
ALTER DATABASE mydb SET wlm_json_configuration = '[
  {"queue_name": "admin", "priority": "highest", "slots": 4},
  {"queue_name": "analytics", "priority": "normal", "slots": 10},
  {"queue_name": "light", "priority": "low", "slots": 20}
]';
```

Modern Redshift uses Service Class Level WLM (auto-WLM):

```sql
ALTER DATABASE mydb SET wlm_json_configuration = '{
  "auto_wlm": true
}';
```

## Concurrency Scaling

Automatically adds capacity for concurrent queries:

```sql
-- Enable per-cluster (always on)
ALTER CLUSTER my-redshift SET enable_concurrency_scaling = ON;
```

Concurrency scaling kicks in when the main queue has > 5 queries. Each cluster supports 10-50 concurrent queries (depending on cluster size).

## Maintaining Tables

### VACUUM

Reclaims space and re-sorts after DELETE:

```sql
VACUUM (DELETE ONLY) my_table;        -- Reclaim deleted rows
VACUUM (SORT ONLY) my_table;         -- Re-sort without reclaim
VACUUM my_table;                       -- Full vacuum (default)
```

With `VACUUM DELETE ONLY`, rows marked for deletion are removed. With `SORT ONLY`, rows are re-sorted but deleted rows remain until `VACUUM`.

### ANALYZE

Update statistics for query planner:

```sql
ANALYZE;
ANALYZE my_table;
ANALYZE my_table (column1, column2);  -- Specific columns
```

## Monitoring

```bash
# Key metrics
# STL_QUERY — query execution history
# STV_BLOCKLIST — table block distribution
# SVL_QUERY_SUMMARY — query runtime breakdown

# Check query performance
SELECT query, label, elapsed, rows FROM STL_QUERY ORDER BY starttime DESC LIMIT 10;

# Check table size
SELECT "schema", "table", rows, size FROM SVV_TABLE_INFO ORDER BY size DESC;
```

## Resize

```bash
# Classic resize (downtime)
aws redshift resize-cluster \
  --cluster-identifier my-redshift \
  --cluster-type multi-node \
  --node-type ra3.4xlarge \
  --number-of-nodes 6

# Elastic resize (minimal downtime)
aws redshift resize-cluster \
  --cluster-identifier my-redshift \
  --classic
```

## Pricing

| Component | Cost |
|-----------|------|
| ra3.xlplus | $0.288/hr |
| ra3.4xlarge | $1.728/hr |
| Spectrum | $5.00/TB scanned |
| Backup | $0.023/GB/month |
| Data transfer | $0.02-0.09/GB |

## Limits

| Resource | Limit |
|----------|-------|
| Max nodes | 128 |
| Max table size | 16 PB (with RA3) |
| Max databases per cluster | 10 |
| Max schemas per database | 100 |
| Max tables per database | 98,304 |
| Max views per database | 100 |
| Max concurrent queries | 50 (with concurrency scaling) |

## References

- **Homepage:** https://aws.amazon.com/redshift/
- **Documentation:** https://docs.aws.amazon.com/redshift/
- **Pricing:** https://aws.amazon.com/redshift/pricing/

## Pricing Examples

**Scenario 1:** A 3-node ra3.4xlarge cluster running 24/7. On-Demand: 3 × $1.728/hr × 24 × 30 = $3,727/month. With Reserved (1 year, no upfront): $1.036/hr effective = $2,237/month. Storage 50TB × $0.024/GB = $1,200/month. Total: ~$3,437/month.

**Scenario 2:** A BI dashboard querying S3 data via Spectrum. 100GB scanned/month. Spectrum: 100GB × $5/TB = $0.50/month. Compare to loading into Redshift: 100GB storage × $0.024/GB = $2.40/month. For infrequent queries on large S3 datasets, Spectrum is cheaper and doesn't require data movement.

## Nuggets & Gotchas

- **Redshift is NOT a replacement for RDS — it's for analytics, not OLTP:** Redshift has 100GB+ minimum storage per node and is optimized for full table scans. Don't use it for single-row lookups, high-frequency writes, or anything requiring sub-second latency on small datasets.
- **Distribution key选择的不好会导致数据倾斜 (skew):** If one node has 10x more data than others, that node becomes a bottleneck. Check distribution with `SELECT * FROM SVV_DISKUSAGE;` or `SELECT slice, col, num_values FROM STL_DIST;`.
- **Sort keys are NOT the same as indexes — they determine physical order on disk:** A sort key on `date` means all data is physically ordered by date. Queries filtering on date will scan less data. But inserting with incorrect order requires `VACUUM` to re-sort.
- **Redshift Spectrum has a 10-query concurrency limit per cluster — if you run 11 queries simultaneously, the 11th waits:** For high-concurrency workloads, use Redshift provisioned concurrency or Athena instead.
- **The `CONVERT_TO_CHAR` and `DECIMAL` type handling differs from PostgreSQL — test your queries:** Redshift is based on PostgreSQL 8.0.2 (heavily modified), not current PostgreSQL. Functions like `NOW()` return different types. Always test in dev before running in production.
---
title: Amazon Redshift
description: Amazon Redshift — data warehouse architecture, cluster configuration, RA3 nodes, spectrum, distribution keys, sort keys, WLM, and performance tuning
tags:
  - aws
  - analytics
  - redshift
---

# Amazon Redshift

Redshift is AWS's petabyte-scale data warehouse. It uses columnar storage and massively parallel processing (MPP) to run complex analytical queries against structured data. It's designed for BI, reporting, and analytics workloads that scan billions of rows.

## Architecture

### Cluster

A Redshift cluster is a set of compute nodes. All nodes communicate over a high-speed internal network. The leader node receives queries, distributes work to compute nodes, and aggregates results.

```
Client (JDBC/ODBC)
    ↓
Leader Node (query planning, result aggregation)
    ↓
Compute Nodes (data storage, query execution)
  ├── Node 1 (2 slices on DC2, or multiple slices on RA3)
  ├── Node 2
  └── Node 3
```

### Node Types

**RA3 (latest):**
- Separate compute from storage
- Managed storage in S3 (Redshift-managed storage)
- Scale compute independently of storage
- Recommended for all new workloads
- 16 vCPU per node, 128GB RAM per node

**Dense Compute (DC2):**
- Fixed local NVMe SSD storage
- High compute density for performance-critical workloads
- Not recommended for new workloads (RA3 is better)

**Dense Storage (DS2):**
- Large HDD storage for data-heavy workloads
- Older, replaced by RA3

### Spectrum

Redshift Spectrum extends queries to data in S3 without loading it into Redshift. You create external tables in Redshift that point to S3, and Spectrum queries them using separate Spectrum nodes.

```
Redshift Cluster
  ├── Internal tables (local SSD)
  └── External tables (S3 via Spectrum)
        ↓
    Spectrum Nodes (separate, managed by AWS)
```

**When to use Spectrum:**
- Data too large to fit in Redshift cluster
- Infrequently accessed cold data that stays in S3
- Data that needs to be accessible from both Redshift and other tools (Athena, EMR)

**When to avoid Spectrum:**
- Frequently accessed data — Spectrum has per-byte scanning cost and higher latency than local tables
- Complex joins across many large external tables — network shuffle is expensive

## Table Design

### Distribution Keys (DISTKEY)

Every table has a distribution style that determines how data is distributed across compute nodes.

```sql
CREATE TABLE sales (
  sale_id BIGINT,
  product_id INT,
  customer_id INT,
  sale_date DATE,
  amount DECIMAL(10,2)
)
DISTKEY(customer_id);  -- All records with same customer_id go to same node
```

**Distribution styles:**
- **KEY:** Rows with the same key value go to the same node. Use for join-heavy tables where you frequently join on the same column.
- **ALL:** Full copy of the table on every node. Use for small dimension tables (< 10MB) that are joined frequently.
- **EVEN:** Round-robin distribution. Default, use when you don't know the access pattern.

**Choosing a DISTKEY:**
- For large fact tables, use the column most frequently used in JOINs
- For date-partitioned data, date columns often make good DISTKEYs
- Avoid high-cardinality keys (unique IDs) as DISTKEY — causes data skew

### Sort Keys

Sort keys determine the physical order of data within each node. Similar to an index but built into the storage layer.

```sql
CREATE TABLE sales (
  sale_id BIGINT,
  product_id INT,
  customer_id INT,
  sale_date DATE,
  amount DECIMAL(10,2)
)
SORTKEY(sale_date, customer_id);  -- Data sorted by date first, then customer
```

**When to use:**
- Columns frequently used in range filters (`WHERE sale_date > '2024-01-01'`)
- Columns used in ORDER BY clauses
- Columns used in GROUP BY with range queries

**Compound vs Interleaved Sort Keys:**
- **Compound (default):** Sort key columns are used in order. First column is most important. Fast for queries filtering on the leading column.
- **Interleaved:** All sort key columns weighted equally. Good when queries filter on various combinations of sort columns. Higher maintenance overhead (VACUUM REINDEX needed).

### Compression Encodings

Redshift stores data column-by-column with compression encodings. Proper encoding dramatically reduces storage and improves query speed.

```sql
CREATE TABLE sales (
  sale_id BIGINT ENCODE ZSTD,
  product_id INT ENCODE DELTA,
  customer_id INT ENCODE DELTA32K,
  sale_date DATE ENCODE DELTA,
  amount DECIMAL(10,2) ENCODE ZSTD
);
```

**Common encodings:**
- **ZSTD:** Best overall compression for most data types
- **DELTA:** Good for sequential data (timestamps, IDs)
- **LZO:** Good for text data with many distinct values
- **RUNLENGTH:** Good for low-cardinality columns (status codes, categories)

**ANALYZE COMPRESSION** automatically determines optimal encodings for existing tables.

## Workload Management (WLM)

WLM controls how queries are prioritized and how many slots (concurrency) each queue has.

```sql
-- Configure WLM via parameter group
wlm_json_configuration = [
  {
    "queue_name": "etl_queue",
    "priority": "HIGH",
    "slots": 4,
    "percent_of_group_to_use": 40,
    "memory_percent_to_use": 80
  },
  {
    "queue_name": "reporting_queue",
    "priority": "NORMAL",
    "slots": 4,
    "percent_of_group_to_use": 60,
    "memory_percent_to_use": 80
  }
]
```

**Concurrency scaling:** When a queue is saturated, Redshift automatically spins up additional query processing capacity. Concurrency scaling adds capacity within seconds and is charged per second.

**Short Query Acceleration (SQA):** Short-running queries (under 10 seconds) are automatically moved to a dedicated high-priority queue ahead of longer queries.

## Vacuum and Analyze

Redshift doesn't auto-vacuum. Tables need periodic maintenance.

```sql
-- Vacuum to re-sort data and reclaim space after deletes/updates
VACUUM DELETE ONLY sales;

-- Vacuum sort only (faster, only re-sorts without reclaiming space)
VACUUM SORT ONLY sales;

-- Reclaim space after major delete
VACUUM;

-- Analyze to update statistics for query planner
ANALYZE;

-- Analyze with compression encoding
ANALYZE COMPRESSION sales;
```

**When to vacuum:**
- After a large DELETE or UPDATE that leaves many dead rows
- When sort key columns have changed significantly
- When query performance degrades over time

**Automatic table maintenance:** Enable `autovacuum` via parameter group, but it still requires periodic manual vacuum for large maintenance operations.

## Views for Common Patterns

### Late-Binding Views

```sql
CREATE LATE BINDING VIEW sales_summary AS
SELECT 
  DATE_TRUNC('month', sale_date) AS month,
  product_id,
  COUNT(*) AS transaction_count,
  SUM(amount) AS total_revenue
FROM sales
GROUP BY DATE_TRUNC('month', sale_date), product_id;
```

Late-binding views don't check the underlying table schema at creation time. Useful for querying raw tables through transformation layers that might change.

### Materialized Views

```sql
CREATE MATERIALIZED VIEW monthly_sales AS
SELECT 
  DATE_TRUNC('month', sale_date) AS month,
  customer_id,
  SUM(amount) AS total_spend
FROM sales
GROUP BY DATE_TRUNC('month', sale_date), customer_id;

-- Refresh on schedule or on-demand
REFRESH MATERIALIZED VIEW monthly_sales;
```

Materialized views pre-compute expensive aggregations and store results. Queries against materialized views are fast because they don't scan the base fact table. Refreshes can be incremental (where supported) or full.

## Data Sharing

Redshift supports data sharing between clusters without data movement:

```sql
-- Producer cluster: create datashare
CREATE DATASHARE salesshare;
ALTER DATASHARE salesshare ADD SCHEMA sales;
GRANT USAGE ON DATASHARE salesshare TO ACCOUNT '123456789012';

-- Consumer cluster: create database from datashare
CREATE DATABASE consumer_db FROM DATASHARE salesshare OF ACCOUNT '123456789012';
```

**Use cases:**
- Share data with partner accounts without copying
- Separate clusters for different teams (dev vs prod) but share a single source of truth
- Data mesh architectures where each domain owns its data

## Security

- **IAM authentication:** Connect to Redshift using IAM credentials (temporary tokens via SAML/OIDC)
- **VPC mode:** Cluster lives in a VPC, accessible only via private IP
- **Encryption:** AES-256 at rest (AWS-managed or KMS CMK), SSL in transit
- **Column-level security:** Redshift supports column-level access control via IAM
- **Row-level security:** Use views with WHERE clauses filtered by current_user

## Performance Tuning Checklist

```
□ Distribution key chosen for large fact tables (JOIN column)
□ Sort key on frequently filtered columns (range filters, ORDER BY)
□ Compression encodings applied (ZSTD for most columns)
□ WLM configured for workload separation (ETL vs reporting)
□ Tables analyzed after large loads (ANALYZE)
□ Vacuum run after large deletes (VACUUM)
□ Concurrent queries within WLM limits (concurrency scaling enabled)
□ QUEUE_METRICS CloudWatch monitored (query wait time in queue)
□ STL_QUERY and SVL_QUERY used for query profiling
```

## References

- **Homepage:** https://aws.amazon.com/redshift/
- **Documentation:** https://docs.aws.amazon.com/redshift/latest/dg/
- **Pricing:** https://aws.amazon.com/redshift/pricing/

## Pricing Examples

**Scenario 1:** A data warehouse with 3 dc2.large nodes (6TB storage, 6 compute nodes). Leader node included. Monthly cost: 6 nodes × $0.25/hr × 720hr = $1,080/month. Using RA3 nodes (ra3.xlplus, 16TBeach): 3 nodes × $0.67/hr × 720hr = $1,447/month. RA3 costs more but scales storage and compute independently. For 100TB data on dc2: you'd need 17 dc2 nodes at $2,550/month vs 3 RA3 nodes at $1,447/month.

**Scenario 2:** A SaaS analytics platform with 3 tenants running separate Redshift workloads. Using 3 separate Redshift clusters (dc2.large × 2 nodes each): 3 × $0.50 × 720 = $1,080/month total. vs a single cluster with separate namespaces: $0.50 × 720 = $360/month. Namespace isolation is cheaper but less secure for multi-tenant compliance requirements.

## Nuggets & Gotchas

- **Redshift Spectrum queries scan data in S3 and are expensive:** A Spectrum query that scans 100TB of data costs $0.50 per TB scanned ($50 per query). Always filter aggressively and use partition columns to minimize data scanned.
- **RA3 nodes decouple storage from compute but you pay for both:** Even if you're not running queries, you pay for RA3 storage. If you have a 100TB data warehouse but only query it occasionally, RA3 might cost more than dc2 with frequent pauses.
- **Dense compute nodes (dc2.8xlarge) have local NVMe storage for temp data:** If your queries use a lot of intermediate sort/join spill, dc2.8xlarge is faster (local SSD) than ds2.xlarge (EBS). The NVMe-based dc2 nodes are better for heavy analytics.
- **Pause and resume has a warm-up time:** Resuming a paused cluster takes 5-10 minutes for the cluster to become available. It's not suitable for always-on workloads. Consider RA3 with minimal compute for always-on but lightly queried data.
- **WLM concurrency limits are per-cluster, not per-database:** If you have multiple databases in one cluster sharing WLM slots, a runaway query in one database consumes slots from all databases. Use separate clusters for workloads that need strict isolation.
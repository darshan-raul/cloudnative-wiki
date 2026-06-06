---
title: Athena
description: Amazon Athena — SQL queries directly on S3 data, schema-on-read, partitions, compression formats, workgroups, and performance optimization
tags:
  - aws
  - analytics
  - athena
---

# Athena

Athena is an interactive query service that lets you run SQL directly against data in S3 — no ETL, no infrastructure, no clusters. You define a schema (table definitions that describe your data in S3), and Athena queries the data in place using Presto.

## Core Concepts

### Schema-on-Read

Athena doesn't load data or transform it at ingestion time. When you query a table, Athena reads the data in S3 and applies the schema you defined. This means:

- **No data loading step** — query S3 data immediately after defining the schema
- **Data stays in S3** — Athena is a query engine, not a storage system
- **Can query any data format** — CSV, JSON, Parquet, ORC, Avro, etc.

### How It Works

```sql
SELECT user_id, action, COUNT(*) as cnt
FROM weblogs
WHERE year = '2024' AND month = '06'
  AND action = 'purchase'
GROUP BY user_id, action;
```

Behind the scenes:
1. Athena parses the query, determines which partitions are needed (`year=2024, month=06`)
2. Athena uses the AWS Glue Data Catalog to find the schema and partition metadata
3. Athena reads only the relevant S3 objects (partition pruning)
4. Presto executes the query across distributed workers
5. Results are returned to the client

### Cost Model

Athena charges per query based on data scanned:
- **$5 per TB of data scanned** for SELECT queries
- **No charge** for DDL (CREATE TABLE, ALTER TABLE, etc.)
- **No charge** for CTAS (CREATE TABLE AS SELECT) — data written to S3 is charged at S3 rates

**Compression and columnar formats dramatically reduce cost:**
- CSV (uncompressed): 100% of data scanned
- GZIP compressed: ~20-40% reduction in data scanned
- Parquet: 10-20% of data scanned (only required columns read)
- Partition pruning: only relevant partitions scanned

## Table Definitions

### Create Table (CSV)

```sql
CREATE EXTERNAL TABLE weblogs (
  user_id string,
  timestamp string,
  action string,
  page_url string,
  ip_address string
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3://my-data-bucket/weblogs/'
TBLPROPERTIES ('skip.header.line.count'='1');
```

### Create Table (Parquet)

```sql
CREATE EXTERNAL TABLE events_parquet (
  user_id string,
  event_time timestamp,
  action string,
  properties map<string, string>
)
STORED AS PARQUET
LOCATION 's3://my-data-bucket/events/'
TBLPROPERTIES ('parquet.compression'='SNAPPY');
```

### Create Table (JSON)

```sql
CREATE EXTERNAL TABLE events_json (
  user_id string,
  event_time string,
  action string,
  properties struct<key:string, value:string>
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.JsonSerDe'
LOCATION 's3://my-data-bucket/events-json/';
```

## Partitioning

Partitions are the most important performance optimization in Athena. A partition is a subset of your data keyed by a column value (typically date/time components).

### Partitioned Table

```sql
CREATE EXTERNAL TABLE weblogs_partitioned (
  user_id string,
  timestamp string,
  action string,
  page_url string
)
PARTITIONED BY (year string, month string, day string)
STORED AS PARQUET
LOCATION 's3://my-data-bucket/weblogs/';
```

### Partition Layout in S3

```
s3://my-data-bucket/weblogs/
  year=2024/
    month=06/
      day=01/
        file.parquet
        file.parquet
      day=02/
        file.parquet
    month=07/
      day=01/
        ...
```

### Add Partitions

```sql
-- Single partition
ALTER TABLE weblogs_partitioned ADD
PARTITION (year='2024', month='06', day='01')
LOCATION 's3://my-data-bucket/weblogs/year=2024/month=06/day=01';

-- Multiple partitions (MSCK REPAIR for auto-discovery)
MSCK REPAIR TABLE weblogs_partitioned;
```

**Athena reads partition metadata from the Glue Data Catalog.** The partition key columns are not stored in the data — they're derived from the S3 key path. When you query with `WHERE year = '2024'`, Athena reads only `year=2024/` prefixes.

### Partition Pruning

Without partitions: Athena scans all data in the table → expensive
With partitions: Athena reads only matching partitions → cheap

**Query performance tip:** Always filter on partition columns first. Athena will prune partitions before reading any data.

## Data Formats

### Columnar Formats (Parquet, ORC)

Best for analytical queries that read many rows but few columns:
- **Parquet:** Most widely supported, excellent for Athena
- **ORC:** Slightly better performance for Hive/Presto workloads, good for Athena

Columnar formats store data column-by-column rather than row-by-row. For queries like `SELECT AVG(price) FROM transactions`, only the `price` column is read.

### Compression

| Format | Compression | Athena Support | Use When |
|--------|-------------|----------------|----------|
| Parquet | Snappy (default), GZIP, Zstd | Native | Analytical queries, best perf |
| ORC | Zstd (default), Snappy | Native | Hive workloads |
| JSON | GZIP | Native | Human-readable logs |
| CSV | GZIP | Native | Simple structured data |

### When to Use Each

- **Parquet with Snappy:** Most analytical workloads, best balance of compression and query speed
- **GZIP compressed text:** Legacy data, simple ETL, maximum compatibility
- **Uncompressed text:** Never — always compress

## Workgroups

Workgroups let you isolate queries, set per-workgroup limits, and track costs per group.

```sql
-- Run query in specific workgroup
SELECT * FROM my_table; -- runs in default workgroup

-- Via JDBC/ODBC connection string
-- jdbc:awsathena://...;Workgroup=engineering
```

**Workgroup features:**
- Per-workgroup query result expiration
- Per-workgroup data scanned limit (blocks queries that would scan too much)
- Per-workgroup CloudWatch logging
- Per-workgroup cost tracking via tags

**Use cases:**
- `engineering` workgroup: higher limits, full logging
- `dev` workgroup: lower limits, cost tracking
- `adhoc` workgroup: query size limits to prevent runaway queries

## Federated Queries

Athena supports federated queries — query data in non-S3 sources using Athena Data Connectors (Lambda-based connectors).

```sql
-- Query CloudWatch Logs via federated connector
SELECT * FROM cloudwatch_logs.scan_logs(
    log_group => '/aws/lambda/my-function',
    start_time => '2024-06-01',
    end_time => '2024-06-02'
);
```

Available connectors:
- CloudWatch Logs
- DynamoDB
- Redis (ElastiCache)
- JDBC-compliant databases (MySQL, PostgreSQL, etc.)
- DocumentDB
- Timestream

## Performance Optimization

### 1. Use Columnar Formats

Parquet/ORC instead of CSV/JSON:
```
CSV: 100GB scanned @ $5/TB = $0.50/query
Parquet (10% compression): 10GB scanned @ $5/TB = $0.05/query
```

### 2. Partition Aggressively

Partition by the most common filter columns. For time-series data: `year/month/day` or `year/month/day/hour`.

### 3. Optimize Column Order in Parquet

Parquet stores columns in order. Put the most frequently queried columns first within each row group. If you always query `user_id` and `timestamp` but rarely `properties`, put them first.

### 4. Use Bucketing

```sql
CREATE TABLE users_bucketed (
  user_id string,
  name string,
  email string
)
WITH (format='PARQUET', partitioned_by=ARRAY['year'],
      bucketed_by=ARRAY['user_id'], bucket_count=50)
AS SELECT * FROM source_table;
```

Bucketing groups data by the bucketed column within each partition. If you frequently query `WHERE user_id = '123'`, bucketing ensures all records for that user are in the same file.

### 5. Avoid SELECT *

Always specify the columns you need. `SELECT *` reads all columns, even unused ones.

### 6. Use Approximate Aggregates for Large Data

```sql
-- HyperLogLog for distinct counts on billions of rows
SELECT APPROX_DISTINCT(user_id) FROM huge_table;

-- Percentile approximation
SELECT APPROX_PERCENTILE(latency_ms, 0.95) FROM logs;
```

These are orders of magnitude faster than exact counts and accurate within ~2%.

## Glue Integration

Athena uses the AWS Glue Data Catalog as its metastore. Tables created in Glue are available in Athena automatically.

**Glue Crawlers** can automatically discover schema by scanning S3:
```python
import boto3

glue = boto3.client('glue')

glue.create_crawler(
    Name='weblogs-crawler',
    Role='arn:aws:iam::123456789:role/GlueCrawlerRole',
    DatabaseName='production',
    Targets={
        'S3Targets': [{
            'Path': 's3://my-data-bucket/weblogs/',
            'Exclusions': ['**/*.tmp']
        }]
    },
    Schedule='cron(0 1 * * ? *)',
    SchemaChangePolicy={
        'DeleteBehavior': 'LOG'
    }
)
```

Crawlers infer schema from file content and create tables in the Glue Data Catalog. You can then query them in Athena.

## Limits

- Maximum query string length: 256KB
- Maximum query result row size: 100MB
- Maximum number of partitions per table: 20,000 (soft limit)
- Query timeout: 30 minutes (default)
- DDL timeout: 10 minutes
- Concurrent queries: 20 per workgroup (default)

## References

- **Homepage:** https://aws.amazon.com/athena/
- **Documentation:** https://docs.aws.amazon.com/athena/latest/ug/
- **Pricing:** https://aws.amazon.com/athena/pricing/

## Pricing Examples

**Scenario 1:** A data lake with 10TB of Parquet data, queried by 5 analysts 20 times/day each. Each query scans ~500MB (column projection). Monthly data scanned: 5 analysts × 20 queries × 30 days × 500MB = 1.5TB =1.5TB × $5/TB = $7.50/month. Plus S3 GETs: ~$0.40/1,000 queries = $6/month. Total: ~$13.50/month. vs Redshift: minimum $0.25/hour = $180/month for a small cluster.

**Scenario 2:** A security team running50 Athena queries/day on CloudTrail logs (500GB). Each query scans 10GB (partitioned by date). Monthly: 50 × 30 × 10GB = 15TB scanned = 15TB × $5/GB = $75/month. Adding a Glacier Deep Archive source (50GB queried monthly, $0.002/GB for direct Select): $0.10/month. Total: ~$75/month vs ingesting CloudTrail into Elasticsearch (~$400/month).

## Nuggets & Gotchas

- **Athena charges per TB of data scanned:** Queries that scan large amounts of data are expensive. Use columnar formats (Parquet, ORC), partition by date, and use column projection to minimize data scanned.
- **Uncompressed text/CSV scans full files:** If your CSV files are 1GB each, a query touching 10 files scans 10GB and costs $0.05. Converting to Parquet (10:1 compression) reduces cost to $0.005 per query.
- **Workgroups enforce query limits and billing controls:** You can set per-workgroup data usage limits (e.g., 100MB/query max) and query timeout (30 minutes). Use workgroups to isolate BI tools from ad-hoc analyst queries.
- **Athena uses Hive Metastore under the hood:** Tables created in Athena are accessible to Glue crawlers, EMR, Redshift Spectrum. The catalog is shared. A table created by an Athena query is visible to all services.
- ** Federated queries (Data Catalog Connectors) cost extra:** Using Athena to query RDS, DynamoDB, or on-prem data via federation connectors incurs additional charges per query. Check the specific connector pricing before building federated architectures.
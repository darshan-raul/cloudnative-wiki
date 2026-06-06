---
title: AWS Analytics
description: AWS analytics services — Kinesis for streaming data, Athena for SQL queries, Redshift for data warehousing, Glue for ETL, OpenSearch for search/analytics, EMR for big data processing, and Lake Formation for data lake governance
tags:
  - aws
  - analytics
---

# AWS Analytics

Analytics on AWS spans a spectrum from real-time streaming to batch warehousing to ad-hoc SQL queries. Each service solves a different problem — understanding where each fits is key to building a cost-effective data architecture.

## Service Map

```
Real-time Streaming
├── Kinesis Data Streams     — real-time ingestion, shard-based
├── Kinesis Data Firehose    — near-real-time delivery to storage
└── Kinesis Data Analytics   — SQL-based stream processing

Ad-hoc Query
├── Athena                   — SQL queries directly on S3 data
└── OpenSearch               — search and log analytics

Data Warehouse
└── Redshift                 — petabyte-scale, columnar, SQL

ETL / Data Processing
├── Glue                     — managed ETL, crawlers, data catalog
└── EMR                      — managed Hadoop/Spark clusters

Data Lake
└── Lake Formation          — unified data lake governance
```

## Real-time vs Batch Decision

| Workload | Service |
|----------|---------|
| Ingest millions of events/sec, process in real-time | Kinesis Data Streams + Kinesis Data Analytics |
| Deliver data to S3/Redshift/Druid with minimal processing | Kinesis Data Firehose |
| Ad-hoc SQL on log files or data lake | Athena |
| Dashboarding and BI on structured data | Redshift |
| ETL between databases and data lakes | Glue |
| Large-scale distributed processing (Spark, Hadoop) | EMR |
| Full-text search on large datasets | OpenSearch |

## Data Flow Patterns

### Lambda Architecture (classic)
```
Real-time layer: Kinesis → Kinesis Data Analytics (SQL) → DynamoDB/ES
Batch layer: S3 → Glue → Redshift
Serving layer: Merge real-time + batch results for queries
```

### Kappa Architecture (simplified)
```
Kinesis → Kinesis Data Analytics (continuous SQL) → serving layer
S3 as the immutable log (no separate batch layer)
```

### Modern Data Stack
```
Ingestion: DMS, Firehose, Kafka Connect
Storage: S3 (raw) + S3 (processed)
Catalog: Glue Data Catalog
Processing: Glue ETL, Athena, Redshift Spectrum
Visualization: QuickSight, Tableau, Grafana
```
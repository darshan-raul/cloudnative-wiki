---
title: AWS Databases
description: AWS database services — RDS (relational), Aurora (MySQL/PostgreSQL compatible), DynamoDB (NoSQL), ElastiCache (in-memory), Redshift (data warehouse), DocumentDB, Neptune, QLDB, and Timestream.
tags:
  - aws
  - databases
---

# AWS Databases

AWS offers managed databases across all major categories: relational (RDS, Aurora), NoSQL (DynamoDB), in-memory (ElastiCache), data warehouse (Redshift), document (DocumentDB), graph (Neptune), ledger (QLDB), and time-series (Timestream).

## Service Map

| Service | Type | Engine | Use Case |
|---------|------|--------|----------|
| [[rds/README|RDS]] | Relational | MySQL, PostgreSQL, MariaDB, Oracle, SQL Server | General OLTP, web apps |
| [[aurora/README|Aurora]] | Relational (MySQL/PG compatible) | Aurora MySQL, Aurora PostgreSQL | High-scale, HA, serverless |
| [[dynamodb/README|DynamoDB]] | NoSQL (key-value, document) | DynamoDB | High-scale, low-latency |
| [[elasticache/README|ElastiCache]] | In-memory | Redis, Memcached | Caching, sessions, pub/sub |
| [[redshift/README|Redshift]] | Data warehouse | Redshift (PostgreSQL-based) | Analytics, BI |
| [[documentdb/README|DocumentDB]] | Document | MongoDB compatible | Semi-structured data |
| [[neptune/README|Neptune]] | Graph | Gremlin, SPARQL, openCypher | Social, fraud, knowledge graphs |
| [[qldb/README|QLDB]] | Ledger | Amazon Quantum Ledger Database | Audit trail, immutable |
| [[timestream/README|Timestream]] | Time-series | Timestream | IoT, metrics, events |

## Database Selection Decision Tree

```
What type of data?
  │
  ├── Structured relational (ACID transactions)?
  │     │
  │     ├── Need high availability + auto-scaling + serverless?
  │     │     YES → Aurora (MySQL or PostgreSQL)
  │     │     NO ↓
  │     │
  │     ├── Need managed Oracle/SQL Server?
  │     │     YES → RDS (Oracle, SQL Server)
  │     │     NO → RDS (MySQL, PostgreSQL, MariaDB)
  │     │
  │     └── Need petabyte-scale data warehouse?
  │           YES → Redshift
  │           NO ↓
  │
  ├── Semi-structured (JSON documents)?
  │     YES → DocumentDB (MongoDB compatible)
  │     NO ↓
  │
  ├── Graph (relationships, social, fraud)?
  │     YES → Neptune (Gremlin or SPARQL)
  │     NO ↓
  │
  ├── Key-value (high-scale, low-latency)?
  │     YES → DynamoDB
  │     NO ↓
  │
  ├── In-memory (caching, sessions)?
  │     YES → ElastiCache (Redis or Memcached)
  │     NO ↓
  │
  ├── Immutable audit log (financial, compliance)?
  │     YES → QLDB
  │     NO ↓
  │
  └── Time-series (IoT, metrics)?
        YES → Timestream
        NO → Consider what you're actually storing
```

## Architecture Patterns

### Read Replicas

```
Writer (Primary)
  │
  └──► Read Replica 1 (async, read-only)
  └──► Read Replica 2 (async, read-only)
  └──► Read Replica 3 (async, read-only)
```

### Multi-AZ (HA)

```
AZ-1: Primary DB
  │
  └──► AZ-2: Standby (sync replication)
  └──► AZ-3: Read Replica 1
```

### Cache Layer

```
Application
  │
  ▼
ElastiCache (Redis/Memcached)
  │ Cache miss
  ▼
RDS / DynamoDB
```

### Aurora Serverless

```
Application
  │
  ▼
Aurora Serverless (auto-scales ACU)
  │
  └── Data API (HTTPS, no persistent connections)
```

## Shared Concepts

### Encryption at Rest

All AWS managed databases support encryption at rest using KMS:
- AWS managed keys (free)
- Customer managed keys (CMK) — you pay for KMS

### Automated Backups

| Database | Default Retention | Max Retention |
|----------|------------------|---------------|
| RDS MySQL/PG | 1 day | 35 days |
| Aurora | 1 day (continuous) | 35 days |
| DynamoDB | Incremental forever | Infinite (PITR) |
| ElastiCache Redis | 1 day (RDB) | 35 days |
| Redshift | 1 day | 35 days |

### Maintenance Windows

All databases have a weekly maintenance window (30 minutes):
- Engine version upgrades
- OS patches
- Instance class changes

Set `maintenance-window` to off-peak hours.

## References

- **Homepage:** https://aws.amazon.com/products/databases/
- **Documentation:** https://docs.aws.amazon.com/databases/
- **Pricing:** https://aws.amazon.com/products/databases/pricing/

## Nuggets & Gotchas

- **RDS and Aurora are NOT multi-region by default — you must create read replicas in another region for DR:** A Multi-AZ deployment keeps a standby in the same region only. For true DR across regions, use cross-region read replicas or Aurora Global Database.
- **DynamoDB has no schema — you can store anything, but you should enforce a schema at the application layer:** DynamoDB will happily store `{"name": "x"}` in one item and `{"count": 42}` in another. Your application must handle schema variations.
- **ElastiCache Redis has two modes — Cluster Mode Disabled (single shard, up to 5 replicas) and Cluster Mode Enabled (up to 90 shards):** Cluster Mode Enabled allows horizontal scaling but requires Redis cluster clients. Most use cases work fine with Cluster Mode Disabled.
- **Redshift is not meant for OLTP — it's a columnar MPP database for analytics, not transactions:** If you need sub-second queries on millions of rows with high write throughput, use RDS or DynamoDB. Redshift is for complex analytical queries on large datasets (BI, reporting).
- **QLDB is immutable but not encrypted at rest by default with customer managed keys — it's always encrypted with AWS managed keys:** For financial compliance, verify your encryption requirements match QLDB's default behavior. Use customer managed keys if you need extra control.
---
title: Amazon Aurora
description: Amazon Aurora — MySQL and PostgreSQL compatible relational database with distributed storage. 6-way replication, auto-scaling, serverless, global database, backtrack, and ml integration.
tags:
  - aws
  - databases
  - aurora
---

# Amazon Aurora

Aurora is MySQL and PostgreSQL compatible with a distributed, self-healing storage layer that replicates data across 6 storage nodes in 3 AZs. It delivers up to 5x throughput of standard MySQL and 3x throughput of standard PostgreSQL at 1/10th the cost of commercial databases.

## How Aurora Works

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Aurora Cluster                                              │
│                                                              │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐       │
│  │   Writer    │◄──│  Reader 1   │   │  Reader 2   │       │
│  │  (primary)  │   │ (async rep) │   │ (async rep) │       │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘       │
│         │                 │                 │               │
│         ▼                 ▼                 ▼               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Aurora Distributed Storage Layer             │  │
│  │                                                        │  │
│  │   AZ-1          AZ-2          AZ-3                     │  │
│  │  ┌──────┐    ┌──────┐    ┌──────┐                    │  │
│  │  │ Node 1│    │ Node 2│    │ Node 3│                   │  │
│  │  └──────┘    └──────┘    └──────┘                    │  │
│  │  ┌──────┐    ┌──────┐    ┌──────┐                    │  │
│  │  │ Node 4│    │ Node 5│    │ Node 6│                   │  │
│  │  └──────┘    └──────┘    └──────┘                    │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

Data is written to 6 of 6 nodes (quorum: 4 of 6). Data is read from 4 of 6 nodes.

## Aurora MySQL vs Aurora PostgreSQL

| | Aurora MySQL | Aurora PostgreSQL |
|--|--|--|
| MySQL compatible | 5.7, 8.0 | N/A |
| PostgreSQL compatible | N/A | 13, 14, 15, 16 |
| Parallel query | Yes | No |
| Backtrack | Yes | No |
| Serverless v2 | Yes | Yes |
| Global Database | Yes | Yes |
| ML integrations | Yes | Yes |

## Endpoints

Aurora has multiple endpoints for different use cases:

| Endpoint | Use | Points To |
|----------|-----|----------|
| Cluster endpoint | Primary writes | Writer DB instance |
| Reader endpoint | Read-only queries | All reader instances (load-balanced) |
| Custom endpoint | Specific instance(s) | Named instances |
| Instance endpoint | Specific instance | Single instance |

```bash
# Get all endpoints
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].{ClusterEndpoint:Endpoint,ReaderEndpoint:ReaderEndpoint}'
```

## Creating an Aurora Cluster

```bash
# Create Aurora cluster (serverless v2)
aws rds create-db-cluster \
  --db-cluster-identifier my-aurora-cluster \
  --engine aurora-postgresql \
  --engine-version 15.3 \
  --serverless-v2-scaling-configuration '{
    "MinCapacity": 1,
    "MaxCapacity": 16
  }' \
  --master-username postgres \
  --master-user-password SecretPassword \
  --vpc-security-group-ids sg-xxxxx \
  --db-subnet-group my-subnet-group \
  --backup-retention-period 1

# Add reader
aws rds create-db-instance \
  --db-instance-identifier my-aurora-reader \
  --db-cluster-identifier my-aurora-cluster \
  --db-instance-class db.serverless \
  --engine aurora-postgresql
```

## Aurora Serverless v2

Aurora Serverless v2 scales ACU (Aurora Capacity Units) automatically:

```bash
# Create serverless v2 cluster
aws rds create-db-cluster \
  --db-cluster-identifier my-aurora-serverless \
  --engine aurora-postgresql \
  --serverless-v2-scaling-configuration '{
    "MinCapacity": 0.5,
    "MaxCapacity": 32
  }' \
  --master-username postgres \
  --master-user-password SecretPassword

# Scale manually
aws rds modify-db-cluster \
  --db-cluster-identifier my-aurora-serverless \
  --serverless-v2-scaling-configuration '{
    "MinCapacity": 1,
    "MaxCapacity": 64
  }'
```

### ACU Pricing

| | Aurora Serverless v2 |
|--|--|
| Per ACU-hour | $0.12/hr |
| Storage | $0.10/GB/month |
| I/O | $0.20 per million requests |

## Global Database (Cross-Region)

Aurora Global Database replicates to secondary regions with < 1 second lag:

```bash
# Create global database
aws rds create-global-cluster \
  --global-cluster-identifier my-global-cluster \
  --engine aurora-postgresql \
  --engine-version 15.3

# Add secondary region cluster
aws rds create-db-cluster \
  --db-cluster-identifier my-aurora-secondary \
  --global-cluster-identifier my-global-cluster \
  --engine aurora-postgresql \
  --db-subnet-group-name my-subnet-group
```

Use case: Primary in us-east-1, secondary in eu-west-1. Failover: promote secondary to primary in < 1 second.

## Backtrack (Aurora MySQL only)

Rewind the database to a specific point in time (up to 72 hours):

```bash
# Backtrack to 1 hour ago
aws rds backtrack-db-cluster \
  --db-cluster-identifier my-aurora-mysql \
  --backtrack-to 2024-01-15T09:00:00Z
```

This is instant (unlike restore from backup). Useful for "oops, I deleted the wrong table."

## High Availability

### Multi-Master

All instances can write (MySQL only):

```bash
aws rds create-db-cluster \
  --db-cluster-identifier my-aurora-multimaster \
  --engine aurora-mysql \
  --engine-version 8.0 \
  --serverless-v2-scaling-configuration '...'
```

### Fault Tolerance

- 6 storage nodes across 3 AZs
- Quorum: 4 of 6 writes must succeed
- Automatic failover to reader: < 30 seconds
- No data loss on single-AZ failure

## Performance

| Metric | Aurora MySQL | Aurora PostgreSQL | Standard MySQL |
|--------|-------------|------------------|----------------|
| Throughput | 5x MySQL | 3x PostgreSQL | Baseline |
| Max connections | 160,000 | 65,535 | 151 (default) |
| Max storage | 128 TB | 128 TB | 64 TB |

## Monitoring

```bash
# Aurora metrics
aws cloudwatch list-metrics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity
```

Key Aurora-specific metrics:
- `ServerlessDatabaseCapacity` — current ACU usage
- `AuroraVolumeBytesChanged` — data written to storage
- `RollbackSegmentInflation` — undo header inflation
- `FreeLocalStorage` — temp storage available

## Limits

| Resource | Limit |
|----------|-------|
| Max storage | 128 TB |
| Max instances per cluster | 1 writer + 15 readers |
| Max connections | 160,000 (Aurora MySQL), 65,535 (Aurora PG) |
| Backtrack window | 72 hours (MySQL only) |
| Global database regions | 5 secondary regions |

## References

- **Homepage:** https://aws.amazon.com/rds/aurora/
- **Documentation:** https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/
- **Pricing:** https://aws.amazon.com/rds/aurora/pricing/

## Pricing Examples

**Scenario 1:** An Aurora PostgreSQL serverless v2 cluster (1-16 ACU) running an API with variable load. Average: 2 ACU, 16hr/day. 2 ACU × $0.12 × 16hr × 30 days = $115.20/month. Storage 500GB × $0.10 = $50/month. Total: ~$165/month. Compare to RDS db.r6g.large Multi-AZ (2 × $0.252 = $0.504/hr × 24 × 30 = $362/month). Aurora is 54% cheaper for variable workloads.

**Scenario 2:** A high-traffic e-commerce site needing consistent 8 ACU. 8 ACU × $0.12/hr × 24 × 30 = $691.20/month. Reserved ACU (1 year): 8 ACU × $0.075/hr = $0.60/hr × 24 × 30 = $432/month. Storage 2TB × $0.10 = $200/month. Total: ~$632/month. Compare to RDS db.r6g.2xlarge × 2 Multi-AZ: 2 × $0.504/hr × 24 × 30 = $725/month.

## Nuggets & Gotchas

- **Aurora Serverless v2 has a cold start delay (~30 seconds) when scaling from 0 ACU:** If you scale to 0 during quiet periods, the first request after idle has a 30-second delay. Use `MinCapacity: 0.5` to keep some capacity warm.
- **Aurora MySQL backtrack requires the InnoDB tablespace to be at least 128MB:** If your tables are small, you may get a "tablespace too small" error. You can increase it with `innodb_undo_tablespaces`.
- **Aurora Global Database allows one secondary region to have a writable instance (promoted primary):** In a global database, only one region is writable at a time. If you need to write in multiple regions simultaneously, use Aurora Multi-Master (MySQL only) instead.
- **Aurora's reader endpoint load-balances at the connection level, not the query level:** Each new connection goes to a different reader. For true query-level load balancing, use a connection pooler (like PgBouncer for PostgreSQL or ProxySQL for MySQL).
- **Aurora PostgreSQL's `shared_buffers` parameter should be set to 75% of Aurora's buffer cache, not the instance's memory:** Aurora's storage layer is separate from PostgreSQL's `shared_buffers`. The default `shared_buffers` (128MB) is fine for most Aurora workloads — don't blindly set it to 75% of instance memory.
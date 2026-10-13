---
title: "AWS Databases"
description: "Choose from access patterns, transactions, query language, latency and recovery needs, not a service-logo checklist."
tags:
  - aws/databases
date: 2026-10-12
---

# AWS Databases

Choose from access patterns, transactions, query language, latency and recovery needs, not a service-logo checklist. Start with [[AWS/architecture/data-store-selection|data-store selection]], [[AWS/security/iam/README|IAM]] and [[AWS/networking/README|networking]]. Then read [[AWS/reliability/backup-and-recovery|backup and recovery]] before handling durable production data.

## Learning path and service map

| Lesson                                            | Main decision                                                                                                                    |
| ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| [[AWS/databases/rds/README\|RDS]]                 | Managed relational engines including PostgreSQL, MySQL, MariaDB, Oracle, SQL Server and Db2; engine-specific features/licensing. |
| [[AWS/databases/aurora/README\|Aurora]]           | MySQL/PostgreSQL-compatible clustered relational storage, replicas and Serverless v2.                                            |
| [[AWS/databases/dynamodb/README\|DynamoDB]]       | Key/value and document access patterns designed around partition/sort keys.                                                      |
| [[AWS/databases/elasticache/README\|ElastiCache]] | Valkey, Redis OSS or Memcached caching; do not confuse a cache with authoritative data.                                          |
| [[AWS/databases/documentdb/README\|DocumentDB]]   | MongoDB-compatible APIs with a distinct compatibility/support matrix.                                                            |
| [[AWS/databases/neptune/README\|Neptune]]         | Connected data, RDF/property graphs and graph-specific queries/analytics.                                                        |
| [[AWS/analytics/redshift/README\|Redshift]]       | Columnar analytical warehouse; not a low-latency transactional replacement.                                                      |
| [[AWS/databases/timestream/README\|Timestream]]   | Separate LiveAnalytics eligibility from InfluxDB deployment/API choices.                                                         |
| [[AWS/databases/qldb/README\|QLDB history]]       | Ended support July 31, 2025; not a new-workload recommendation.                                                                  |

## Architecture distinctions

A read replica scales supported read workloads but is not necessarily a synchronous HA standby. Classic RDS Multi-AZ DB instances and Multi-AZ DB clusters expose different standby/read behavior. Aurora separates clustered storage, writer and readers. Multi-Region replication requires explicit topology and does not automatically eliminate data-loss/failover concerns.

Caching introduces TTL/invalidation and stale-read behavior. Before adding DAX or ElastiCache, identify the source of truth and define what the application does during a cache outage. Query-heavy relationship traversal suggests Neptune; large aggregates/BI favor Redshift rather than an operational database.

## Recovery and security

Encryption at rest, TLS in transit, network isolation, IAM/database credentials and authorization are different controls. Parameter/option groups and maintenance windows must match the engine and supported configuration. The automated backup window is separate from a maintenance window.

DynamoDB PITR provides a configurable one-to-thirty-five-day recovery window, not infinite retention. On-demand backups/long-term retention are separate. Across services, copy/restore limitations, KMS permissions and recovery time matter more than a successful backup status.

## Selection exercise

Given an order-processing system and BI dashboard, document transactional requirements, access patterns, consistency, item/query sizes and RPO/RTO. Compare two eligible databases and identify one reason the rejected option fails. In a sandbox, verify least-privilege reads/writes, demonstrate an unauthorized denial and restore a small test dataset into an isolated target. Remove disposable databases, replicas, caches and retained backup artifacts according to policy.

Estimate compute/capacity, storage, I/O, backup, transfer, licenses and replication from one Region's current rates. Quotas and engine versions should be discovered from owning documentation, not an unsourced universal table.

## Selection decision tree and shared operating concepts

```text
Need transactional relational queries?
  → RDS/Aurora, validating engine compatibility
Known key/item access patterns at scale?
  → DynamoDB, modelling keys/indexes first
Document API compatibility required?
  → DocumentDB, checking exact operator/driver support
Relationship traversal is central?
  → Neptune and explicit graph model
Large aggregates/BI?
  → Redshift/Athena rather than OLTP-by-default
Cache acceleration?
  → ElastiCache/DAX with a defined authoritative store
Time-series workload?
  → eligible Timestream product or another justified store
```

This is a starting point, not a one-question algorithm. An application can use a relational source of truth, cache and warehouse simultaneously, each with distinct consistency/recovery guarantees.

| Concept            | What it does                             | What it does not establish                        |
| ------------------ | ---------------------------------------- | ------------------------------------------------- |
| Read replica       | Supported read scaling/replication       | Guaranteed synchronous HA or zero-loss promotion  |
| HA standby         | Supported availability/failover topology | An independently retained backup                  |
| Cache              | Faster eligible accesses                 | Authoritative durability or universal consistency |
| PITR/snapshot      | Supported recovery points                | Complete application/network/identity restoration |
| Encryption at rest | Protects storage under key policy        | Network authorization, TLS or backup availability |
| Maintenance window | Governs supported maintenance timing     | Same schedule as automated backups                |

Benchmark the actual query/item model and failure paths. A database's supported API name is not proof that every upstream feature/version behaves identically. Record engine versions, restore/key dependencies and application reconnect behavior with the architecture decision.

## References

- [AWS database selection guide](https://docs.aws.amazon.com/decision-guides/latest/databases-on-aws-how-to-choose/databases-on-aws-how-to-choose.html)
- [DynamoDB backup and recovery](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Backup-and-Restore.html)
- [AWS service availability changes](https://aws.amazon.com/about-aws/whats-new/2025/05/aws-service-changes/)

---
title: "Database selection and operations"
description: "Choose a data store from access, consistency, recovery and operating requirements, then validate it with a failure/restore exercise."
tags:
  - cloud/aws/architecture
date: 2026-10-12
---

# Database selection and operations

Start with [[AWS/databases/README|the database map]]. Do not select a store solely because it is managed or because its catalog description says “scalable.”

## Requirements before products

Specify access patterns, transaction boundaries, consistency, data model, item/row size, peak traffic, latency, retention and recovery objectives. Include licensing, migration effort and operator skills.

| Requirement                   | Candidate direction | Evidence to obtain                                                        |
| ----------------------------- | ------------------- | ------------------------------------------------------------------------- |
| Relational transactions/joins | RDS/Aurora          | Engine compatibility, indexes, HA mode, failover/client behavior          |
| Key-based scale               | DynamoDB            | Keys/hot partitions, item-size units, transactions, global-table behavior |
| Cache/ephemeral acceleration  | ElastiCache/DAX     | Integration, consistency/invalidation, miss/load behavior                 |
| Document workload             | DocumentDB          | Supported operators/versions, compatibility, topology                     |
| Graph relationships           | Neptune             | Graph model/query language, algorithms and application requirements       |
| Analytical scans              | Redshift/Athena     | Data layout, workload isolation, bytes/compute and freshness              |

A cache is not the system of record by default. A classic RDS Multi-AZ standby is not a read-scaling replica; Multi-AZ clusters have a different topology. Avoid treating all replication as synchronous or all failover as a fixed number of seconds.

## Comparative exercise

For an order workload requiring atomic order/inventory updates and reporting, choose a transactional store and a separate analytics path. Explain why copying a query workload into a key-value store can require redesign rather than a drop-in migration.

Test one representative transaction, one peak-load query and one recovery scenario. Define acceptable latency/error/data-loss bounds before measuring.

## Restore and failover drill

Use only an isolated sandbox database with disposable data. Record known keys/rows and checksums, capture a supported recovery point, restore into a separate target and verify data plus roles/network/client configuration.

For failover, induce only an approved sandbox transition; observe connection retries, endpoint changes, replication lag and committed data. Measure detection-to-validated-application time, not just the control-plane status.

Cleanup dedicated restored instances/clusters, storage, snapshots, endpoints and telemetry after confirming retention. Stopping compute may leave storage billing.

## References

- [Database selection guidance](https://docs.aws.amazon.com/decision-guides/latest/databases-on-aws-how-to-choose/databases-on-aws-how-to-choose.html).
- [RDS Multi-AZ modes](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html).
- [DynamoDB design best practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html).
- Next: [[AWS/reliability/backup-and-recovery|recovery plan]] and [[AWS/cost-management/README|cost model]].

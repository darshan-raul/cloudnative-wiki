---
title: "Amazon DocumentDB"
description: "DocumentDB is a managed document database with MongoDB-compatible APIs, not a promise of complete MongoDB feature equivalence."
tags:
  - aws/databases
date: 2026-10-12
---

# Amazon DocumentDB

DocumentDB is a managed document database with MongoDB-compatible APIs, not a promise of complete MongoDB feature equivalence. Check engine/version-specific operator, driver and administrative support before migration. Prerequisites: [[AWS/databases/README|database selection]], [[AWS/networking/README|networking]] and [[AWS/reliability/backup-and-recovery|recovery]].

## Architecture and compatibility

Instance-based clusters have one primary plus optional replicas, backed by six storage copies across three AZs. They do not have three writable primaries. Elastic Clusters are a distinct sharded deployment model; a classic cluster cannot be sharded by inventing an enableSharding parameter.

Use the cluster endpoint for supported primary access and configure driver replica-set/read preference behavior according to the guide. Validate indexes, transactions, aggregation behavior, connection pooling and failover against your selected engine, not just a successful connection. $lookup is supported with documented constraints; categorical unsupported claims are incorrect. Unsupported operators need application redesign, not an assumed alternative operator.

## Provisioning and operations

CreateDBCluster provisions cluster metadata/storage, while CreateDBInstance creates compute separately. replication-group-id and num-cache-verticies are not DocumentDB cluster flags. Use private network paths, restrictive security groups, TLS and secure credential retrieval; avoid passwords embedded in URIs committed to notes or source code.

Stop/start is supported for eligible clusters but retains storage/other charges and has restrictions/automatic restart behavior. Snapshot/PITR recovery is distinct from replicas. Monitor database load, memory, connections, I/O and replication lag with the documented metrics for the chosen model.

## Migration/restore exercise

Prerequisites: an isolated, budgeted test cluster, compatible client, IAM/TLS/network prerequisites and a representative dataset without sensitive production content. Restore or import a few documents and indexes; test each application query/operator and compare output with the source database.

Demonstrate a denied unauthorized connection and a controlled primary failover; record driver reconnect behavior and lag rather than claiming uninterrupted writes. Restore a snapshot to a separate sandbox target and verify counts, representative values and index definitions—counts alone are insufficient migration evidence. Remove disposable instances, clusters and reviewed snapshots.

## Cost and limits

Estimate compute, storage, I/O or I/O-optimized mode where applicable, backups and network costs. Elastic and instance-based models have different dimensions/quotas. Discover supported engine versions and account/Region limits from current owning pages instead of maintaining a guessed numeric table. Compare total application compatibility/remediation cost, not only database instance price.

## Document schema and aggregation

```json
{
  "user_id": "user123",
  "name": { "first": "Alice", "last": "Smith" },
  "orders": [
    { "order_id": "order-001", "total": 99.99 },
    { "order_id": "order-002", "total": 149.99 }
  ]
}
```

Collections group documents; absence of a mandatory relational schema does not remove validation/versioning requirements. Embedding bounded related data versus referencing separate collections changes read patterns, update atomicity and document growth.

The following Mongo-style shell examples assume an authorized supported engine and disposable collections. Verify actual feature/operator support by engine/version before migration.

```javascript
db.users.insertOne({ user_id: "sandbox-123", name: "Alice" });
db.users.findOne({ user_id: "sandbox-123" });
db.users.createIndex({ user_id: 1 }, { unique: true });
db.orders.createIndex({ customer_id: 1, created_at: -1 });
db.orders.aggregate([
  { $unwind: "$items" },
  { $group: { _id: "$customer_id", total_spent: { $sum: "$items.price" } } },
  { $sort: { total_spent: -1 } },
  { $limit: 10 },
]);
```

This aggregation sums the specified item price field; if quantities/discounts exist, include them in the business definition. An identical row count is not proof of financial reconciliation.

## Connection, transactions and change streams

Retrieve the real cluster endpoint and follow the current DocumentDB TLS/client guide with a trusted CA and hostname verification. Avoid passwords in connection strings/shell history; current client parameters replace deprecated ssl_ca_certs examples. Configure supported replica-set/read preference behavior, connection pooling and retry semantics deliberately.

Transactions depend on the engine/model's supported behavior and limits; test rollback and retry errors with your actual driver. Do not copy a multi-database application transaction without checking support. Change streams require supported configuration and retention, plus resumable consumers that tolerate retries and expired progress. A listener callback logging full documents can expose sensitive content.

## Instance-based versus Elastic Clusters

Instance-based creation separates cluster from compute, with one writer and replicas. Elastic Clusters provide a distinct shard-based model and compatibility/administration constraints; classic enableSharding is not an RDS parameter. Keep separate tests for $lookup, index/aggregation behavior, transactions, change streams and operators used by the application.

## Recovery and monitoring

Create a snapshot/PITR restore into an isolated target, reconnect through verified TLS and compare documents, indexes and representative queries. Stop/start is eligible-model-specific and retains costs; deleting/recreating is not the only workaround for idle usage.

Watch CPU/memory, connections, I/O and replica lag; workload query plans/index effectiveness matter as much as instance size. Separate compute, storage, I/O mode, backups and transfer when pricing. Protect backups and test KMS/network/credentials during restore rather than only recording snapshot status.

## References

- [DocumentDB architecture](https://docs.aws.amazon.com/documentdb/latest/developerguide/how-it-works.html)
- [Supported APIs and operators](https://docs.aws.amazon.com/documentdb/latest/developerguide/mongo-apis.html)
- [Cluster creation CLI contract](https://docs.aws.amazon.com/cli/latest/reference/docdb/create-db-cluster.html)
- [Stopping and starting clusters](https://docs.aws.amazon.com/documentdb/latest/developerguide/db-cluster-start-stop.html)
- [DocumentDB pricing](https://aws.amazon.com/documentdb/pricing/)

## Across the wiki

- [[Azure/databases/cosmos-db|Azure Cosmos DB]] — NoSQL databases (Azure)
- [[GCP/databases/firestore/README|Google Cloud Firestore]] — NoSQL databases (GCP)
- [[Architecture/solution-architecture-concepts/data-architecture/databases/mongodb/README|MongoDB]] — NoSQL databases (Architecture)
- [[GCP/databases/bigtable/README|Google Cloud Bigtable]] — NoSQL databases (GCP)

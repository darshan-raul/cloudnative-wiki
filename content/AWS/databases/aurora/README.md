---
title: "Amazon Aurora"
description: "Aurora is MySQL/PostgreSQL-compatible relational database infrastructure with storage separated from compute instances."
tags:
  - aws/databases
date: 2026-10-12
---

# Amazon Aurora

Aurora is MySQL/PostgreSQL-compatible relational database infrastructure with storage separated from compute instances. Prerequisites: [[AWS/databases/rds/README|RDS]], [[AWS/networking/README|networking]] and [[AWS/reliability/backup-and-recovery|recovery planning]].

## Cluster, instances and endpoints

Traditional Aurora storage maintains six copies across three AZs, with three-copy read quorum and four-copy write quorum. The cluster has a writer plus optional readers; the first instance created becomes writer even if its identifier contains reader. Cluster creation and instance creation are separate operations.

Use the writer/cluster endpoint for writes, reader endpoint for supported load-distributed reads and instance endpoints when deliberately targeting a node. Promotion tiers, connections and DNS influence failover. Replication lag is not a failover-time guarantee. Use supported single-writer/read-replica architecture rather than an invented Multi-Master creation flag.

## Serverless v2 and global databases

Serverless v2 scales supported compute capacity within configured bounds. Zero-ACU auto-pause/resume is supported for selected engine versions; 0.5 ACU is not a universal cost floor. Auto-pause introduces resume latency and depends on supported configuration/connections. Provisioned instances and Serverless v2 may coexist where documented.

Global Database provides cross-Region replication with explicit switchover/failover workflows. Current constraints allow up to ten secondary Regions, with the combined count of primary readers plus secondary clusters not exceeding fifteen; check engine/version/Region support. Treat lag, write routing and regional failure recovery explicitly.

## Backtrack and tuning

Aurora MySQL Backtrack moves a cluster backward within a configured window up to 72 hours, subject to version/Region and feature restrictions. It must be enabled at creation/restoration. It is not a replacement for backups or cross-Region recovery, and there is no documented tiny-tablespace/undo-setting shortcut that fixes every backtrack failure.

Aurora PostgreSQL still uses an instance buffer cache; shared_buffers defaults are memory-derived, typically around 75% of available memory, not a universal 128 MB. Tune using measured workload behavior rather than assuming distributed storage eliminates caching.

## Recovery exercise and costs

Create a budgeted sandbox cluster with one writer and one reader, using secure credentials/private networking. Verify writer roles through DBClusterMembers.IsClusterWriter in DescribeDBClusters rather than instance names. Insert a labelled row, read through appropriate endpoints and perform a controlled failover; record reconnect behavior. Restore to a separate cluster and verify checksums/data, then remove sandbox readers, writer, cluster and retained snapshots according to policy.

```bash
aws rds describe-db-clusters --db-cluster-identifier example-aurora
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=example-aurora
```

These are read-only CLI v2 examples requiring real identifiers. Cost includes instance/ACU-hours, storage, applicable I/O, backups and global transfer/replication. There is no standalone Reserved ACU product; Database Savings Plans are a distinct eligible-usage hourly commitment, not a fabricated reserved-ACU tariff.

## Distributed architecture and engine comparison

```text
Writer instance       Reader instance(s)
        └───────┬───────────────┘
                ▼
        Shared cluster storage
      AZ A       AZ B       AZ C
      copy 1     copy 3     copy 5
      copy 2     copy 4     copy 6
```

Compute instances access the cluster storage; readers are not three unrelated storage primaries. The write quorum is four copies, read quorum three. Storage redundancy, reader availability, client reconnect and regional disaster recovery are different parts of resilience.

| Choice                 | What carries over                                  | What still needs validation                                                          |
| ---------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Aurora MySQL           | Supported MySQL-compatible protocols/features      | Exact engine version, extensions/features, backtrack constraints and query behavior. |
| Aurora PostgreSQL      | Supported PostgreSQL-compatible protocols/features | Extension support, parameter groups, logical replication and application tests.      |
| Provisioned instance   | Selected fixed instance class                      | Instance sizing, maintenance and cost.                                               |
| Serverless v2 instance | Supported workload with scaling bounds             | Engine/version eligibility, scaling latency and pause/resume behavior.               |

Compatibility is not an assurance that every feature from an arbitrary upstream version exists. Pin a supported engine family/version and test representative migrations, extensions and SQL before cutover.

## Endpoints and connection behavior

| Endpoint       | Routing purpose                      | Caveat                                                                               |
| -------------- | ------------------------------------ | ------------------------------------------------------------------------------------ |
| Writer/cluster | Current writer                       | Failover changes routing; clients must reconnect and honor DNS.                      |
| Reader         | Connections across available readers | Connection balancing is not per-query balancing; absent readers can change behavior. |
| Instance       | One specified instance               | Does not track a different promoted writer automatically.                            |
| Custom         | Selected supported instances         | Membership/configuration is an explicit operating responsibility.                    |

A connection pool can keep reading one node long after other readers are added. Test read-only enforcement and transaction routing at the client; the endpoint name is not an application authorization policy.

## Correct cluster → writer → reader walkthrough

Prerequisites: an eligible supported Aurora PostgreSQL configuration, isolated DB subnet group/security group, authorized deployment role, KMS/Secrets permissions and budget. The example uses managed master credentials instead of a plaintext password in shell history. Check available engine versions first; do not pin an obsolete version from an old note.

```bash
aws rds describe-db-engine-versions --engine aurora-postgresql \
  --query 'DBEngineVersions[].EngineVersion'

# Select a version only after verifying Serverless v2 support in this Region.
read -r -p "Verified supported Aurora PostgreSQL version: " AURORA_LAB_ENGINE_VERSION
: "${AURORA_LAB_ENGINE_VERSION:?Select a verified supported version first}"

aws rds create-db-cluster \
  --db-cluster-identifier sandbox-aurora \
  --engine aurora-postgresql \
  --engine-version "$AURORA_LAB_ENGINE_VERSION" \
  --engine-mode provisioned \
  --master-username sandboxadmin \
  --manage-master-user-password \
  --db-subnet-group-name sandbox-db-subnets \
  --vpc-security-group-ids sg-0123456789abcdef0 \
  --serverless-v2-scaling-configuration MinCapacity=1,MaxCapacity=8 \
  --backup-retention-period 1

aws rds create-db-instance \
  --db-instance-identifier sandbox-aurora-writer \
  --db-cluster-identifier sandbox-aurora \
  --db-instance-class db.serverless \
  --engine aurora-postgresql

aws rds wait db-instance-available \
  --db-instance-identifier sandbox-aurora-writer

aws rds create-db-instance \
  --db-instance-identifier sandbox-aurora-reader \
  --db-cluster-identifier sandbox-aurora \
  --db-instance-class db.serverless \
  --engine aurora-postgresql

aws rds wait db-instance-available \
  --db-instance-identifier sandbox-aurora-reader
aws rds describe-db-clusters --db-cluster-identifier sandbox-aurora \
  --query 'DBClusters[0].DBClusterMembers[].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}'
```

These are creation examples, not actions run during this review. The first created instance is the writer; labels do not assign roles. Wait for actual available state and inspect IsClusterWriter before connecting. Use managed secret retrieval through an authorized path, a verified TLS client and the actual endpoint.

Insert a synthetic table, read from the appropriate endpoint and initiate a controlled failover only in the sandbox. Measure reconnect time/errors, promoted role and committed data. Clean up instances before deleting the cluster; deliberately decide whether to retain a final snapshot, and inspect managed secret/backups afterward.

## Global Database and backtrack operating sequence

For Global Database, check engine/version/Region support, create the global topology and attach eligible secondary clusters through the documented workflow. Route reads/writes explicitly. During planned switchover, verify replication readiness; during disaster failover, assess lag and data-loss risk. Re-establish topology and application endpoints after the event. A secondary cluster is not an automatic second writer.

Backtrack is a cluster-wide Aurora MySQL feature enabled at creation/restoration with a configured window. It rewinds supported cluster state, so coordinate application writes and downstream systems before using it. It does not undo external messages/cache changes or replace off-cluster backups. Check current restrictions rather than recommending a fictional Multi-Master or tiny undo-tablespace remedy.

## Monitoring and worked capacity-cost scenario

Inspect CPU, DatabaseConnections, freeable memory, BufferCacheHitRatio, AuroraReplicaLag, storage/I/O and failover events appropriate to the instance/cluster. Compare slow-query/database-load evidence with latency before changing shared_buffers or adding replicas. Database Insights and enhanced telemetry have their own mode/cost choices.

For an illustrative Serverless v2 scenario, two instances averaging 2 ACUs for 100 hours each consume 2 × 2 × 100 = 400 ACU-hours. Multiply by the chosen Region/engine rate once; then add storage, applicable I/O, backups, transfer and monitoring. If the reader runs fewer hours or capacity varies, integrate each instance's actual usage rather than applying the writer's average to every instance. Database Savings Plans can affect eligible usage at their commitment rates, but are not “Reserved ACUs.”

Zero-ACU pause can improve an eligible idle workload's cost, with resume latency and restrictions. A production latency target may justify a nonzero minimum; measure rather than assume both cost and response-time benefits.

## References

- [Aurora storage and reliability](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Concepts.Aurora.html)
- [Serverless v2 auto-pause](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2-auto-pause.html)
- [Global Database limits](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)
- [Backtrack requirements](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraMySQL.Managing.Backtrack.html)
- [Aurora pricing](https://aws.amazon.com/rds/aurora/pricing/)
- [CreateDBCluster contract](https://docs.aws.amazon.com/cli/latest/reference/rds/create-db-cluster.html)
- [CreateDBInstance contract](https://docs.aws.amazon.com/cli/latest/reference/rds/create-db-instance.html)

## Across the wiki

- [[Azure/databases/azure-sql|Azure SQL Database & Managed Instance]] — relational databases (Azure)
- [[GCP/databases/cloud-sql|GCP Cloud SQL]] — relational databases (GCP)
- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/README|PostgreSQL]] — relational databases (Architecture)
- [[Azure/databases/postgres-flexible/README|Azure Database for PostgreSQL Flexible Server Architecture & Operations]] — relational databases (Azure)

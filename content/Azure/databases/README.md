---
title: Azure Databases Architecture Hub
description: Master architectural guide to Microsoft Azure database services — Azure SQL Database, Managed Instance, Cosmos DB, PostgreSQL Flexible Server, MySQL Flexible Server, and Azure Cache for Redis.
tags:
  - azure
  - databases
  - sql
  - cosmos-db
  - postgresql
  - mysql
  - redis
date: 2026-10-15
---

# Azure Databases Architecture Hub 🗄️⚡

Microsoft Azure provides a comprehensive database ecosystem spanning fully managed relational database management systems (RDBMS), globally distributed multi-model NoSQL, hyperscale storage engines, and enterprise in-memory caches.

---

## Architectural Decision Matrix

```
                                  Database Workload
                                          │
            ┌─────────────────────────────┼─────────────────────────────┐
            ▼                             ▼                             ▼
    Relational (OLTP / SQL)       Distributed NoSQL / Global      In-Memory Caching
            │                             │                             │
    ┌───────┴───────┐              [[Azure/databases/cosmos-db|Azure Cosmos DB]]          [[Azure/databases/redis/README|Azure Cache for Redis]]
    ▼               ▼              - Multi-Region Multi-Master   - Sub-ms Key-Value
Proprietary    Open Source         - 5 Consistency Levels        - Enterprise Clustering
    │               │              - NoSQL, Mongo, Cassandra     - Active-Active CRDT
    ▼               ▼
[[Azure/databases/azure-sql|Azure SQL / MI]]   ┌───────┴───────┐
- Hyperscale    ▼               ▼
- Serverless   [[Azure/databases/postgres-flexible/README|PostgreSQL Flex]]   [[Azure/databases/mysql-flexible|MySQL Flex]]
- T-SQL        - PgBouncer     - Zone-Redundant
               - Citus Scale   - Autoscale IOPS
```

### Database Capabilities Matrix

| Service                                                                      | Engine & Paradigm                              | Scalability Model                                        | Consistency & High Availability                                        | Primary Use Case                                                                    |
| :--------------------------------------------------------------------------- | :--------------------------------------------- | :------------------------------------------------------- | :--------------------------------------------------------------------- | :---------------------------------------------------------------------------------- |
| **[[Azure/databases/azure-sql\|Azure SQL Database & Managed Instance]]**     | Microsoft SQL Server (T-SQL)                   | Vertical vCore + Hyperscale (100 TB distributed storage) | 99.995% SLA, Auto-Failover Groups, Serverless auto-pause               | Enterprise business logic, legacy SQL Server migration, complex stored procedures.  |
| **[[Azure/databases/cosmos-db\|Azure Cosmos DB]]**                           | Multi-Model NoSQL (Document, Key-Value, Graph) | Horizontal sharding across partition keys, Autoscale RUs | Active-active multi-region writes, 5 mathematical consistency levels   | Global web apps, IoT telemetry, real-time personalization, gaming leaderboards.     |
| **[[Azure/databases/postgres-flexible/README\|PostgreSQL Flexible Server]]** | Native PostgreSQL 14–16                        | Up to 64 vCPUs / 32 TiB, built-in PgBouncer              | Zone-redundant standby with automated failover (< 60–120s)             | Modern cloud-native microservices, JSONB document querying, geospatial (PostGIS).   |
| **[[Azure/databases/mysql-flexible\|MySQL Flexible Server]]**                | Community MySQL 8.0                            | Up to 64 vCPUs / 32 TiB, storage autogrow                | Zone-redundant synchronous log replication                             | Open-source web platforms, e-commerce stores, LAMP/LEMP application stacks.         |
| **[[Azure/databases/redis/README\|Azure Cache for Redis]]**                  | Redis 6.x/7.x & Redis Enterprise               | Sharded clustering up to 2 TB RAM                        | In-memory replication, AOF/RDB persistence, active-active multi-region | Session stores, sub-millisecond query caching, distributed locking, pub/sub queues. |

---

## Service Catalog

- [[Azure/databases/azure-sql|Azure SQL Database & Managed Instance]] — Single Database vs Elastic Pools vs Managed Instance, vCore vs DTU models, Serverless auto-pause, Hyperscale multi-tier architecture, and Auto-Failover Groups.
- [[Azure/databases/cosmos-db|Azure Cosmos DB]] — Request Units (RUs), 5 well-defined consistency levels (Strong, Bounded Staleness, Session, Consistent Prefix, Eventual), partition key design, and multi-region active-active writes.
- [[Azure/databases/postgres-flexible/README|Azure Database for PostgreSQL Flexible Server]] — Zone-redundant HA failover, integrated PgBouncer connection pooling, storage autogrow, and customized maintenance windows.
- [[Azure/databases/mysql-flexible|Azure Database for MySQL Flexible Server Architecture]] — Zone-redundant high availability, pre-provisioned vs Autoscale IOPS, read replicas, and server parameter tuning.
- [[Azure/databases/redis/README|Azure Cache for Redis Architecture & Enterprise Tiers]] — Basic vs Standard vs Premium (clustering, persistence) vs Enterprise (Redis modules, Active-Active geo-replication using CRDTs).

---

## Multi-Cloud Equivalents

| Capability                     | Microsoft Azure                                                          | Amazon Web Services (AWS)          | Google Cloud Platform (GCP)        |
| :----------------------------- | :----------------------------------------------------------------------- | :--------------------------------- | :--------------------------------- |
| **Enterprise Relational**      | [[Azure/databases/azure-sql\|Azure SQL Database]]                        | Amazon Aurora / RDS SQL Server     | Cloud SQL / AlloyDB                |
| **Managed PostgreSQL**         | [[Azure/databases/postgres-flexible/README\|PostgreSQL Flexible Server]] | Amazon RDS for PostgreSQL / Aurora | Cloud SQL for PostgreSQL / AlloyDB |
| **Managed MySQL**              | [[Azure/databases/mysql-flexible\|MySQL Flexible Server]]                | Amazon RDS for MySQL / Aurora      | Cloud SQL for MySQL                |
| **Globally Distributed NoSQL** | [[Azure/databases/cosmos-db\|Azure Cosmos DB]]                           | Amazon DynamoDB                    | Cloud Spanner / Cloud Bigtable     |
| **Managed Redis Cache**        | [[Azure/databases/redis/README\|Azure Cache for Redis]]                  | Amazon ElastiCache / MemoryDB      | Memorystore for Redis              |

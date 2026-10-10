---
title: Databases
tags: [architecture, databases, data, postgres, redis, mongodb]
date: 2026-10-10
description: A guide to choosing and understanding databases — the main families and what each is good at, the trade-offs behind them, a default-first selection method, and an index of the database notes in this wiki.
---

# Databases

Choosing a database is choosing which problems you want to be easy. Every engine optimises for some access patterns and consistency guarantees at the expense of others. This page maps the territory and indexes the detailed notes.

## Start with a default

For a new application whose requirements are not yet clear, **start with PostgreSQL**. It is relational, transactional, mature, and stretches surprisingly far: JSON documents, full-text search, geospatial data, time series and vector search all work in one engine. You can run it anywhere.

Move to something specialised when you can name the specific limit you have hit — not in anticipation of scale you do not have. Operating two data stores well is more than twice the work of operating one.

## The families

| Family              | Data model                         | Good at                                                | Weak at                                         | Examples                                      |
| :------------------ | :--------------------------------- | :----------------------------------------------------- | :---------------------------------------------- | :-------------------------------------------- |
| **Relational**      | Tables, rows, joins, SQL           | Transactions, integrity, ad hoc queries                | Horizontal write scaling                        | PostgreSQL, MySQL, SQL Server                 |
| **Distributed SQL** | Relational, sharded and replicated | SQL with horizontal scale and multi-region consistency | Latency per transaction, cost, complexity       | Spanner, CockroachDB, YugabyteDB, Aurora DSQL |
| **Key-value**       | Key → opaque value                 | Very fast lookups by key, simple scaling               | Queries by anything other than the key          | Redis, DynamoDB, etcd                         |
| **Document**        | JSON-like documents                | Flexible schemas, aggregates read and written whole    | Joins, multi-document invariants                | MongoDB, Firestore, DocumentDB                |
| **Wide-column**     | Rows with sparse, dynamic columns  | Huge write volumes, known query patterns               | Ad hoc queries; data must be modelled per query | Cassandra, Bigtable, ScyllaDB                 |
| **Columnar / OLAP** | Data stored by column              | Aggregations over billions of rows                     | Single-row lookups and updates                  | ClickHouse, BigQuery, Redshift, Snowflake     |
| **Search**          | Inverted indexes                   | Full-text search, relevance, faceting                  | Being the system of record                      | OpenSearch, Elasticsearch                     |
| **Time series**     | Timestamped measurements           | Append-heavy ingest, downsampling, retention           | General-purpose queries                         | Prometheus, InfluxDB, TimescaleDB             |
| **Graph**           | Nodes and edges                    | Traversing relationships many hops deep                | Bulk analytics, simple CRUD                     | Neo4j, Neptune                                |
| **Vector**          | High-dimensional embeddings        | Similarity search                                      | Everything else                                 | pgvector, Pinecone, Qdrant, Milvus            |
| **Log / stream**    | An append-only, replayable log     | Decoupling producers and consumers, event history      | Random access and queries                       | Kafka, Kinesis, Pulsar                        |

## The trade-offs underneath

**OLTP or OLAP.** Transactional workloads read and write a few rows at a time and need low latency. Analytical workloads scan millions of rows and aggregate. Row stores serve the first, column stores the second — see [[Architecture/solution-architecture-concepts/data-architecture/databases/columnar-databases|columnar databases]]. Running heavy analytics on the transactional database is a classic cause of outages; replicate to an analytical store instead, for example with [[Architecture/solution-architecture-concepts/migration-patterns/change-data-capture|change data capture]].

**Consistency.** A single-node relational database gives ACID [[Architecture/solution-architecture-concepts/data-architecture/databases/transactions|transactions]]. Once data is replicated across machines, the [[Architecture/solution-architecture-concepts/api-design/cap-theorem|CAP theorem]] applies: during a network partition a system either refuses some requests or serves possibly stale data. Know which your database does, and what its _default_ settings actually guarantee.

**Scaling.** Scale up first; it is simple and modern machines are very large. Then add read replicas for read-heavy workloads. Sharding — splitting data across independent nodes — is the last resort, because it pushes complexity into the application: cross-shard queries, transactions and rebalancing. Background in [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/scalability|scalability]] and [[Architecture/solution-architecture-concepts/data-architecture/hashing|hashing]].

**Schema.** "Schemaless" databases still have a schema; it just lives in application code instead of the database. Enforcing it in the database catches bad data at write time; enforcing it in code makes changes faster and failures later.

## A selection method

1. **Write down the access patterns**: the ten most important reads and writes, with expected rates and sizes.
2. **State the consistency needs** per pattern. Money and inventory need transactions; a view counter does not.
3. **Estimate volume and growth** honestly — [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/capacity-planning|capacity planning]].
4. **Check whether the default handles it.** It usually does.
5. **Consider operations**: who runs it, backs it up, upgrades it and is paged for it. Prefer a managed service unless there is a reason not to.
6. **Plan the exit**: how would data be migrated out? See [[Architecture/solution-architecture-concepts/migration-patterns/data-migration|data migration]].

Common combinations that work well: PostgreSQL as the system of record, [[Architecture/solution-architecture-concepts/data-architecture/databases/redis|Redis]] for caching and ephemeral state, [[Architecture/solution-architecture-concepts/event-driven-architecture/kafka/README|Kafka]] to move data between systems, and a columnar store for analytics.

## Notes in this section

**Relational fundamentals**

- [[Architecture/solution-architecture-concepts/data-architecture/databases/normalization|Normalization]] — normal forms, and when to denormalise
- [[Architecture/solution-architecture-concepts/data-architecture/databases/indexing|Indexing]] — how indexes work and how to design them
- [[Architecture/solution-architecture-concepts/data-architecture/databases/transactions|Transactions]] — ACID and isolation levels
- [[Architecture/solution-architecture-concepts/data-architecture/databases/foreign-keys-and-constraints|Foreign keys and constraints]]
- [[Architecture/solution-architecture-concepts/data-architecture/databases/referential-actions|Referential actions]] — `CASCADE`, `SET NULL`, `RESTRICT`
- [[Architecture/solution-architecture-concepts/data-architecture/databases/views|Views]] and materialised views
- [[Architecture/solution-architecture-concepts/data-architecture/databases/opm-or-not-to-orm|To ORM or not]]

**Engines**

- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/README|PostgreSQL]] — architecture, MVCC, vacuum, indexes, connections
- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/replication-and-ha|PostgreSQL replication and high availability]]
- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/psql|psql]] — A cheat sheet for psql, the PostgreSQL command-line client: connecting, meta-commands, output formatting and scripting.
- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/foreign-data-wrapper|Foreign data wrappers]]
- [[Architecture/solution-architecture-concepts/data-architecture/databases/redis|Redis]] — data structures, persistence, caching patterns
- [[Architecture/solution-architecture-concepts/data-architecture/databases/mongodb/README|MongoDB]] and [[Architecture/solution-architecture-concepts/data-architecture/bson|BSON]]
- [[Architecture/solution-architecture-concepts/data-architecture/databases/columnar-databases|Columnar databases]]

**Around the database**

- [[Architecture/solution-architecture-concepts/caching|Caching]]
- [[Architecture/solution-architecture-concepts/event-driven-architecture/README|Event-driven architecture]]
- [[Architecture/solution-architecture-concepts/migration-patterns/expand-contract|Expand and contract]] — changing a schema without downtime
- [[AI/vector-databases|Vector databases]]

## Managed services

| Provider | Relational                                                                 | Key-value / cache                                                                              | Document / wide-column / other                                                                                                          |
| :------- | :------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------- |
| AWS      | [[AWS/databases/rds/README\|RDS]], [[AWS/databases/aurora/README\|Aurora]] | [[AWS/databases/dynamodb/README\|DynamoDB]], [[AWS/databases/elasticache/README\|ElastiCache]] | [[AWS/databases/documentdb/README\|DocumentDB]], [[AWS/databases/neptune/README\|Neptune]], [[AWS/databases/redshift/README\|Redshift]] |
| Azure    | [[Azure/databases/azure-sql\|Azure SQL]]                                   | Azure Cache for Redis                                                                          | [[Azure/databases/cosmos-db\|Cosmos DB]]                                                                                                |
| GCP      | [[GCP/databases/cloud-sql\|Cloud SQL]], [[GCP/databases/spanner\|Spanner]] | Memorystore                                                                                    | [[GCP/databases/bigquery\|BigQuery]], Firestore, Bigtable                                                                               |

Running databases on Kubernetes is possible with operators and persistent volumes — see [[Kubernetes/concepts/L03-workloads/04-statefulsets|StatefulSets]] and [[Kubernetes/eks/storage/ebs-csi|EBS on EKS]] — but a managed service is the better default unless you have the operational depth.

## Further reading

- [Stored Procedures (video)](https://www.youtube.com/watch?v=AYUnaErhdS8)
- [Database Schema Design (video)](https://www.youtube.com/watch?v=U2_MBLS04aQ)

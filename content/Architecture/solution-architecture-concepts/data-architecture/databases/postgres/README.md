---
title: PostgreSQL
tags: [architecture, databases, postgres, sql, mvcc]
date: 2026-10-10
description: How PostgreSQL works inside and what that means in production — the process model, memory, the write-ahead log, MVCC and vacuum, index types, reading query plans, connection pooling, locks and the settings worth changing.
---

# PostgreSQL

PostgreSQL is an open-source relational database with full ACID transactions, a rich type system and an extension mechanism that lets it act as a document store, a search engine, a time-series database or a vector database. It is the sensible default for most applications — see [[Architecture/solution-architecture-concepts/data-architecture/databases/README|choosing a database]].

Most production problems with PostgreSQL trace back to four internals: its process-per-connection model, the write-ahead log, MVCC, and vacuum. Understanding those four explains nearly everything else.

## Architecture

```
clients ──► postmaster ──fork──► backend process (one per connection)
                                      │
            ┌─────────────────────────┼──────────────────────────────┐
            │ shared memory           │                              │
            │  shared_buffers (page cache)   WAL buffers   lock table│
            └─────────────────────────┼──────────────────────────────┘
                                      │
 background processes: checkpointer · background writer · WAL writer ·
                       autovacuum launcher/workers · WAL senders · archiver
                                      │
                       data files (8 kB pages)      WAL segments (pg_wal/)
```

- **One OS process per connection.** Each backend uses several megabytes and competes for CPU. Thousands of connections are expensive in a way they are not for threaded databases — hence connection pooling, below.
- **`shared_buffers`** is PostgreSQL's own page cache. It also relies on the operating system's page cache, which is why it is normally set to about a quarter of RAM rather than most of it.
- **Data is stored in 8 kB pages** in files per table and index.

## The write-ahead log

Every change is first written to the **WAL**, a sequential log, and flushed to disk at commit. The data files are updated later, lazily.

- **Durability**: after a crash, PostgreSQL replays the WAL from the last checkpoint and loses nothing that was committed.
- **Performance**: a commit needs one sequential write instead of many random ones.
- **Replication and backup** are built on shipping the same log — see [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/replication-and-ha|replication and high availability]].

A **checkpoint** writes all dirty pages to the data files so that older WAL can be recycled. Checkpoints that are too frequent cause I/O spikes; raise `max_wal_size` so they are driven by `checkpoint_timeout` rather than by WAL volume.

## MVCC: readers never block writers

PostgreSQL implements isolation with multi-version concurrency control. An `UPDATE` does not overwrite a row. It writes a **new version** (tuple) and marks the old one as expired. Each tuple records the transaction that created it (`xmin`) and the one that deleted it (`xmax`), and every transaction sees only the versions that were committed when its snapshot was taken.

Consequences:

- Reads never wait for writes, and writes never wait for reads.
- An `UPDATE` is physically an insert plus a delete. Every index on the table gets a new entry too, unless the update qualifies as a _HOT_ update (no indexed column changed and there is free space on the page).
- Old versions — **dead tuples** — accumulate until something removes them.

Isolation levels and their anomalies are covered in [[Architecture/solution-architecture-concepts/data-architecture/databases/transactions|transactions]]. The default level is Read Committed.

## Vacuum

**Vacuum** removes dead tuples so their space can be reused, and **autovacuum** runs it automatically. It does three jobs:

1. Reclaims space from dead tuples (for reuse within the table; it does not usually shrink the file).
2. Updates the planner's statistics (`ANALYZE`).
3. **Freezes** old transaction IDs to prevent wraparound.

Two failure modes are worth knowing by name:

| Problem                       | Cause                                                                          | Symptom                                                      |
| :---------------------------- | :----------------------------------------------------------------------------- | :----------------------------------------------------------- |
| **Bloat**                     | Autovacuum cannot keep up, or is blocked from removing dead tuples             | Tables and indexes several times their real size; slow scans |
| **Transaction ID wraparound** | IDs are 32-bit; rows must be frozen before about two billion transactions pass | Warnings, then the database refuses writes to protect itself |

The most common cause of both is **a long-running transaction**. Vacuum cannot remove any tuple that some open transaction might still need, so one forgotten `BEGIN` in a session — or an abandoned replication slot — holds back cleanup for the whole database.

```sql
-- Oldest open transactions
SELECT pid, state, xact_start, now() - xact_start AS age, left(query, 60)
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start
LIMIT 5;

-- Tables with the most dead tuples
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 10;
```

Set `idle_in_transaction_session_timeout`, and make autovacuum more aggressive on large, busy tables by lowering `autovacuum_vacuum_scale_factor` per table.

## Indexes

| Type                          | Use for                                                                                              |
| :---------------------------- | :--------------------------------------------------------------------------------------------------- |
| **B-tree**                    | The default: equality, ranges, sorting                                                               |
| **GIN**                       | Values containing many keys: `jsonb`, arrays, full-text search                                       |
| **GiST**                      | Geometric and range types, nearest-neighbour, exclusion constraints                                  |
| **BRIN**                      | Very large tables whose physical order follows the column, e.g. append-only timestamps               |
| **Hash**                      | Equality only; rarely better than B-tree                                                             |
| **HNSW / IVFFlat** (pgvector) | Approximate nearest-neighbour search over embeddings — see [[AI/vector-databases\|vector databases]] |

Useful variations: **multicolumn** indexes (column order matters — equality columns first), **partial** indexes (`WHERE status = 'pending'`), **expression** indexes (`lower(email)`), and **covering** indexes (`INCLUDE (…)`) that enable index-only scans.

Every index slows down writes and consumes memory. Build indexes with `CREATE INDEX CONCURRENTLY` in production so the table is not locked, and drop the ones `pg_stat_user_indexes` shows are never scanned. Design principles are in [[Architecture/solution-architecture-concepts/data-architecture/databases/indexing|indexing]].

## Reading a query plan

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE customer_id = 42 AND created_at > now() - interval '7 days';
```

| Look at                               | It tells you                                                            |
| :------------------------------------ | :---------------------------------------------------------------------- |
| `Seq Scan` on a large table           | No usable index, or the planner expects most rows to match              |
| Estimated `rows` versus actual `rows` | A large mismatch means stale or insufficient statistics — run `ANALYZE` |
| `Buffers: shared read`                | Pages fetched from disk rather than cache                               |
| `Rows Removed by Filter`              | Work wasted after the index — a better index could filter earlier       |
| `Sort Method: external merge  Disk`   | `work_mem` too small for this sort                                      |
| Nested loop with a large outer side   | Often a bad row estimate                                                |

Enable the `pg_stat_statements` extension. It records execution counts and total time per query shape, and sorting it by total time shows where the database actually spends its effort — usually a query nobody suspected, run very often.

## Connections and pooling

Because each connection is a process, a database handling a few hundred active connections well can be brought down by a few thousand idle ones. Application-side pools help within one instance, but with many application replicas — or serverless functions — the total still explodes.

Put a **pooler** in between: PgBouncer, Pgcat, or a managed proxy such as RDS Proxy.

| Pool mode       | A server connection is held for | Trade-off                                                                              |
| :-------------- | :------------------------------ | :------------------------------------------------------------------------------------- |
| Session         | The whole client session        | Fully compatible; little multiplexing                                                  |
| **Transaction** | One transaction                 | High multiplexing; session state (`SET`, advisory locks, `LISTEN`) does not carry over |
| Statement       | One statement                   | No multi-statement transactions                                                        |

Transaction mode is the usual choice. Keep `max_connections` modest and let the pooler queue.

## Locks

Readers and writers do not block each other, but **schema changes** can block everything. Most `ALTER TABLE` forms take an `ACCESS EXCLUSIVE` lock. The lock itself may be brief; the danger is the **lock queue**: if the `ALTER` has to wait behind one long-running query, every later query on that table queues behind the `ALTER`, and the application stalls.

- Always run migrations with `SET lock_timeout = '5s'` and retry.
- Add columns without a volatile default; add `NOT NULL` and foreign keys as `NOT VALID` first, then `VALIDATE` separately.
- Use the [[Architecture/solution-architecture-concepts/migration-patterns/expand-contract|expand and contract]] pattern so old and new code both work during the change.

## Settings worth changing

| Setting                               | Guideline                                                                             |
| :------------------------------------ | :------------------------------------------------------------------------------------ |
| `shared_buffers`                      | About 25% of RAM                                                                      |
| `effective_cache_size`                | About 50–75% of RAM (a planner hint, not an allocation)                               |
| `work_mem`                            | Per sort or hash, per query node — small globally, raised per session for big queries |
| `maintenance_work_mem`                | Larger, to speed up vacuum and index builds                                           |
| `max_wal_size`                        | Large enough that checkpoints are time-driven                                         |
| `random_page_cost`                    | About 1.1 on SSDs (the default assumes spinning disks)                                |
| `idle_in_transaction_session_timeout` | A minute or so                                                                        |
| `statement_timeout`                   | Set per role for application users                                                    |
| `log_min_duration_statement`          | Log slow queries                                                                      |

Storage behaviour underneath is covered in [[Linux/storage/storage-performance-tuning|storage performance tuning]] and [[Linux/storage/filesystems|filesystems]].

## Extensions worth knowing

`pg_stat_statements` (query statistics), `pgvector` (embeddings), PostGIS (geospatial), `pg_trgm` (fuzzy text matching), TimescaleDB (time series), `pg_partman` (partition management), and [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/foreign-data-wrapper|foreign data wrappers]] to query other systems.

## Related

- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/psql|psql]]
- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/replication-and-ha|Replication and high availability]]
- [[Architecture/solution-architecture-concepts/data-architecture/databases/normalization|Normalization]] and [[Architecture/solution-architecture-concepts/data-architecture/databases/foreign-keys-and-constraints|constraints]]
- [[AWS/databases/rds/README|Amazon RDS]], [[AWS/databases/aurora/README|Aurora]], [[GCP/databases/cloud-sql|Cloud SQL]]
- [[AWS/cost-management/rds-cost-optimization|RDS cost optimization]]
- [PostgreSQL documentation](https://www.postgresql.org/docs/current/)

## Across the wiki

- [[Azure/databases/azure-sql|Azure SQL Database & Managed Instance]] — relational databases (Azure)
- [[AI/inner-workings/embeddings|Embeddings]] — embeddings and search (AI)
- [[AWS/analytics/opensearch/README|Amazon OpenSearch]] — embeddings and search (AWS)

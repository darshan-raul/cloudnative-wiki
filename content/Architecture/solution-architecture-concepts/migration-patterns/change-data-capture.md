---
title: Change Data Capture (CDC)
---

# Change Data Capture (CDC)

CDC is a pattern for watching a database for changes and streaming those changes to downstream systems in real-time — without polling, without batch jobs, without touching the source tables after the initial setup.

## The Core Idea

Traditional migration: "give me everything and I'll figure out what's different."
CDC: "tell me when something changes."

```
Traditional polling:
  App → "anything new?" → DB → "here's everything" → App filters for changes
  Problem: hits DB every few seconds even when nothing changed

CDC:
  DB → "something changed" → CDC → "here's what changed" → downstream
  Problem: none — you only process actual changes
```

## How It Works

CDC tools sit between the primary database and the outside world, reading the database's transaction log and publishing change events.

### Log-Based CDC (Preferred)

Databases write every change to a transaction log (WAL in Postgres, binlog in MySQL). CDC reads this log — it never touches the actual data tables.

```
User executes: UPDATE users SET phone = '555-0100' WHERE id = 42

DB writes to WAL:
  operation: UPDATE
  table: users
  before: {id: 42, phone: NULL}
  after:  {id: 42, phone: '555-0100'}
  timestamp: 1709294021

CDC reads WAL → transforms → publishes event → downstream
```

This is the gold standard. Zero performance overhead on source tables.

### Trigger-Based CDC (Fallback)

For databases without accessible transaction logs, CDC adds triggers to every table that write change records to a shadow table, then reads the shadow table.

```
Users table trigger:
  ON UPDATE → INSERT INTO _users_changes (id, before, after, ts) VALUES (...)
```

Trade-off: adds write overhead to every table, and triggers can be disabled or missed in edge cases.

## The CDC Event Shape

Every change event has the same structure regardless of the database:

```json
// INSERT into users
{
  "op": "c",                          // create
  "table": "users",
  "ts_ms": 1709294021000,
  "after": { "id": 42, "name": "Darshan", "email": "d@example.com" }
}

// UPDATE users SET phone = '555-0100' WHERE id = 42
{
  "op": "u",                          // update
  "table": "users",
  "ts_ms": 1709294021000,
  "before": { "id": 42, "phone": null },
  "after":  { "id": 42, "phone": "555-0100" }
}

// DELETE FROM users WHERE id = 42
{
  "op": "d",                          // delete
  "table": "users",
  "ts_ms": 1709294021000,
  "before": { "id": 42, "name": "Darshan", "email": "d@example.com" }
}
```

`op` values: `c` (create), `u` (update), `d` (delete), `r` (read/snapshot).

## Tooling

| Tool | Database | Delivery | Notes |
|---|---|---|---|
| **Debezium** | Postgres, MySQL, MongoDB, SQL Server, Oracle | Kafka, Webhook | Open source, Apache license |
| **AWS DMS** | 20+ sources | S3, Kafka, Redshift, etc. | Managed, no-code setup |
| **Oracle GoldenGate** | Oracle, SQL Server, etc. | Proprietary | Enterprise, expensive |
| **Fivetran** | 100+ connectors | Data warehouse | SaaS, pricing per row |
| **Maxwell** | MySQL binlog | Kafka | Lightweight, open source |

### Debezium Example

```java
DebeziumEngine engine = DebeziumEngine.create(ChangeEvent.createUsingWebSocket())
    .using(new PostgresConnectorConfig.ScrollPositionDao(source ->
        new OffsetQuery().execute(source)
    ))
    .notifier(notification -> {
        notification.forEach(change -> {
            String table   = change.getHeader("table");
            String op      = change.getHeader("operation");
            Struct payload = change.getPayload();

            // route to downstream system
            if ("users".equals(table)) {
                routeUserChange(op, payload);
            }
        });
    })
    .using(config -> {
        config.set("database.hostname", "postgres-primary");
        config.set("database.port", "5432");
        config.set("database.dbname", "mydb");
        config.set("plugin.name", "pgoutput");  // Postgres WAL plugin
        config.set("table.include.list", "orders,users,products");
    });
```

## Common Architectures

### Zero-Downtime Database Migration

CDC is the bridge between "we need all historical data" and "we can't afford downtime":

```
Phase 1: Bulk snapshot
  Legacy DB → DMS/Debezium → New DB
  (all existing data copied in batches)

Phase 2: CDC sync (runs during and after snapshot)
  Legacy DB → CDC → Kafka → Consumer → New DB

Phase 3: Catch-up
  After snapshot completes, replay CDC backlog
  Monitor lag until< 1 second

Phase 4: Cutover
  Reads → New DB
  Writes → New DB (Legacy DB becomes read-only backup)
```

### Audit Trail / Event Sourcing

```
Any DB write → CDC → Kafka → Audit consumer
                              → Search index (Elasticsearch)
                              → Cache invalidation (Redis)
                              → Notification service
                              → Compliance log (S3)
```

### Multi-System Synchronization

```
Orders DB (Postgres) → CDC → Kafka → Consumer 1 → Analytics DB (ClickHouse)
                                          → Consumer 2 → Search (Elasticsearch)
                                          → Consumer 3 → Cache (Redis)
```

## Delivery Guarantees

CDC guarantees **at-least-once** delivery — every change is sent, but network issues can cause duplicates.

Downstream consumers must be **idempotent**:

```python
# Idempotent upsert: re-running produces the same result
def process_user_event(event):
    if event['op'] == 'c' or event['op'] == 'u':
        upsert_user(event['after']) # INSERT ... ON CONFLICT UPDATE
    elif event['op'] == 'd':
        delete_user(event['before']['id'])

# Running this twice = same final state (safe for CDC retries)
```

**Exactly-once** requires distributed transactions or a dedicated coordination layer (Kafka transactions, outbox pattern), which adds significant complexity.

## The Hard Parts

### Schema Evolution

The database adds a column. CDC has to handle old events (pre-column) and new events (with column) simultaneously.

```
Before: {id, name}
After:  {id, name, phone}

CDC event from before schema change:
  after: {id: 42, name: "Darshan"} # no phone field

CDC event from after schema change:
  after: {id: 42, name: "Darshan", phone: "555-0100"}
```

Consumer must tolerate missing fields (optional, not required).

### WAL Retention

Postgres recycles WAL segments if CDC falls behind. If your CDC connector stops for more than `wal_keep_size` window, you lose the log history and must re-snapshot.

```
wal_keep_size = 1GB     # ~30 minutes of WAL for busy DB
wal_keep_size = 10GB   # ~5 hours of WAL
```

Set this before deploying CDC, not after you've fallen behind.

### Transaction Grouping

Multiple writes in a single transaction should be grouped together. Without this, you can get partial transaction events:

```
BEGIN;
  UPDATE accounts SET balance = balance - 100 WHERE user_id = 1;
  UPDATE accounts SET balance = balance + 100 WHERE user_id = 2;
COMMIT;
```

CDC must emit these two changes as one atomic unit. Debezium groups by `transaction_id` from the WAL.

### Initial Snapshot

Large tables (billions of rows) take hours to snapshot. During this time, CDC continues capturing changes. When the snapshot finishes, those accumulated changes are replayed.

```
Total migration time = snapshot_duration + catch-up_duration
```

Estimate: snapshot at 10,000 rows/second for a 100M row table = 2.7 hours, then catch-up on top.

## CDC vs. Other Patterns

| Pattern | Approach | Latency | Data Scope |
|---|---|---|---|
| **CDC** | Event-driven (log) | Seconds | Changes only |
| **Polling** | Query-based (batch) | Minutes to hours | Full table or incremental column |
| **Dual-write** | Application-level | Synchronous | Every write explicitly sent |
| **Trigger-to-table** | DB triggers | Near-real-time | Changes only |

CDC sits between polling (slow, batch) and dual-write (fast but application-level耦合). Log-based CDC is the best of all worlds — real-time, no application code changes, no performance hit — but requires database support for transaction log access.

## Related

- [[data-migration|Data Migration]] — using CDC in zero-downtime migration workflows
- [[strangler-fig|Strangler Fig]] — CDC as the sync mechanism for legacy replacement
- [[event-driven-architecture/README|Event-Driven Architecture]] — CDC feeds into event streams
- [[expand-contract|Expand-Contract]] — schema evolution when CDC is involved

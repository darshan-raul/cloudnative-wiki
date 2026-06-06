---
title: Data Migration Patterns
---

# Data Migration Patterns

Data migration is the process of moving data from one system, format, or storage to another. For a solution architect, data migration is never just a "move data" problem — it's about maintaining data integrity, minimizing downtime, and handling the case where migration fails halfway through.

## The Four Migration Types

### 1. Storage Migration
Moving data from one storage system to another (e.g., from on-prem NFS to cloud S3).

### 2. Database Migration
Changing the database engine, schema, or structure (e.g., from MySQL to PostgreSQL, from monolith DB to microservice DBs).

### 3. Platform Migration
Moving from one platform to another (e.g., from EC2 to Lambda, from on-prem to cloud).

### 4. Application Migration
Moving from one application to another (e.g., from legacy ERP to SaaS ERP, from custom CMS to managed CMS).

All four types share common patterns and risks.

## The Migration Risk Matrix

Every data migration has two risks:

| Risk | What happens | Mitigation |
|---|---|---|
| **Data loss** | Some data doesn't make it to the new system | Verification, checksums, reconciliation |
| **Downtime** | System is unavailable during migration | Zero-downtime patterns (see below) |
| **Corruption** | Data arrives but is wrong (wrong format, truncated) | Schema validation, sampling |
| **Rollback need** | Migration fails and you need to go back | Keep old system running, test first |

## Zero-Downtime Migration Strategy

### Phase 1: Prepare (Before Any Migration)

```
1. Profile the data
   - Row count, data size, growth rate
   - Identify large objects (blobs, JSON fields)
   - Identify problematic data (NULLs, duplicates, encoding issues)

2. Choose migration window
   - Low-traffic period (night, weekend)
   - Communicate to users/customers

3. Test on a subset
   - Migrate 1% of data first
   - Verify correctness, measure time
   - Extrapolate to full migration time
```

### Phase 2: Dual-Write (Before Cutover)

Write to both old and new systems simultaneously:

```
Application:
  write(record) → old_db
 → new_db  (async or sync)

Both systems stay in sync until cutover
```

> **Risk:** Dual-write adds latency to every write operation. If async, there's a window of potential inconsistency.

### Phase 3: Backfill Historical Data

For new systems that need historical data:

```python
# Backfill pattern: batched, resumable, logged
def backfill(batch_size=1000, resume_token=None):
    last_id = resume_token or0
    while True:
        batch = old_db.fetch(
            "SELECT * FROM records WHERE id > %s ORDER BY id LIMIT %s",
            (last_id, batch_size)
        )
        if not batch:
            break

        # Transform to new schema
        transformed = [transform_record(r) for r in batch]

        # Write to new DB
        new_db.bulk_insert(transformed)

        # Log progress (resumable)
        last_id = batch[-1]['id']
        checkpoint.save(last_id)

        time.sleep(0.1)  # Throttle to reduce load on source DB
```

For large datasets (billions of rows), backfill takes days or weeks. Design for resumability — if the job fails at80%, it must resume from where it left off, not start over.

### Phase 4: Reconcile

Verify that new system has all the data it should:

```sql
-- Reconciliation query
SELECT
 COUNT(*) as total,
  COUNT(DISTINCT id) as unique_ids,
  COUNT(*) - COUNT(DISTINCT id) as duplicates,
  COUNT(CASE WHEN migrated_at IS NULL THEN 1 END) as missing
FROM new_db.records;

-- Find records in old but not in new
SELECT id FROM old_db.records
EXCEPT
SELECT id FROM new_db.records;
-- Should return0 rows
```

### Phase 5: Cutover

Switch reads (and optionally writes) from old to new:

```
Before cutover:
  Reads → Old DB
  Writes → Old DB → CDC (see [[change-data-capture|CDC]]) → New DB (async)

After cutover:
  Reads → New DB
  Writes → New DB
```

## Database-Specific Migration Patterns

### PostgreSQL Migration

```sql
-- Large table: add column without table lock
-- Bad: ALTER TABLE users ADD COLUMN phone VARCHAR(20); -- locks table
-- Good:
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
COMMENT ON COLUMN users.phone IS 'migrated from legacy system2024-03-15';

-- Backfill without locking (UPDATE in batches)
UPDATE users SET phone = email_lookup.phone
FROM email_lookup
WHERE users.email = email_lookup.email
  AND users.phone IS NULL
  AND users.id BETWEEN 1 AND 10000;  -- batch

-- Partition large tables for performance
CREATE TABLE orders (
    id BIGSERIAL,
    created_at TIMESTAMP,
    ...
) PARTITION BY RANGE (created_at);

CREATE TABLE orders_2024_01 PARTITION OF orders
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

### MongoDB Migration

```javascript
// Backfill with aggregation pipeline (server-side)
db.orders.aggregate([
  { $match: { phone: { $exists: false } } },
  { $limit: 10000 },
  { $lookup: { from: "email_lookup", localField: "email", foreignField: "email", as: "lookup" } },
  { $unwind: "$lookup" },
  { $merge: { into: "orders", whenMatched: "merge" } }
])
```

### MySQL to PostgreSQL Migration

Tools: AWS DMS, Debezium, custom ETL

Key differences to handle:
- Auto-increment (MySQL) vs SERIAL (Postgres)
- VARCHAR(255) vs VARCHAR(n) — Postgres requires length
- ENUM types — different syntax
- Date functions — different syntax

## Data Validation Patterns

### Checksum Reconciliation

```python
import hashlib

def record_checksum(record: dict) -> str:
    # Hash of all field values (deterministic, order-independent)
    fields = sorted(record.keys())
    data = ''.join(str(record[f]) for f in fields)
    return hashlib.sha256(data.encode()).hexdigest()

# After migration:
old_counts = old_db.execute("SELECT COUNT(*), SUM(checksum) FROM records")
new_counts = new_db.execute("SELECT COUNT(*), SUM(checksum) FROM records")

assert old_counts['count'] == new_counts['count'], "Row count mismatch"
assert old_counts['checksum'] == new_counts['checksum'], "Data mismatch"
```

### Sampling Validation

For very large datasets, validate a statistical sample instead of all records:

```python
import random

def sample_validate(old_db, new_db, sample_size=1000, tolerance=0.001):
    total = old_db.execute("SELECT COUNT(*) FROM records").fetchone()['count']
    sample = old_db.fetch(
        f"SELECT * FROM records ORDER BY RANDOM() LIMIT {sample_size}"
    )

    mismatches = 0
    for record in sample:
        new_record = new_db.fetch(
            "SELECT * FROM records WHERE id = %s", (record['id'],)
        )
        if not new_record:
            mismatches += 1
        elif record != new_record:
            mismatches += 1

    error_rate = mismatches / sample_size
    assert error_rate < tolerance, f"Error rate {error_rate} exceeds tolerance {tolerance}"
```

## Handling Migration Failures

### Checkpoint/Resume Pattern

```python
class MigrationJob:
    def __init__(self, job_name):
        self.checkpoint_key = f"migration:{job_name}:last_id"
        self.last_id = checkpoint.get(self.checkpoint_key) or 0

    def run(self):
        while True:
            batch = fetch_batch(starting_after=self.last_id)
            if not batch:
                break

            migrate(batch)
            self.last_id = batch[-1]['id']
            checkpoint.save(self.last_id)  # Resume point saved

            if self.last_id % 100000 == 0:
                log(f"Migrated {self.last_id} records...")

# If job crashes, restart picks up from last checkpoint
```

### The Rollback Plan

Before any migration:

```
1. Old system is backed up (full snapshot)
2. Old system kept running (read-only if needed)
3. Migration job is idempotent (re-running doesn't duplicate data)
4. Cutover has a defined rollback procedure
```

Idempotent migration = safe to re-run. Use UPSERT (INSERT ... ON CONFLICT UPDATE) rather than raw INSERT.

## Common Data Migration Mistakes

- **Not profiling data first** — discovering 50GB of JSON blobs mid-migration
- **No checkpointing** — job fails at 80%, must restart from 0
- **Ignoring indexes** — data migrates, queries are slow without indexes
- **Foreign key constraints** — migrating parent and child tables out of order
- **Timezone handling** — UTC vs local time mismatches
- **Encoding issues** — Latin-1 vs UTF-8 causing character corruption
- **No testing on production-scale data** — works on100 rows, fails on 10M rows
- **Forgetting about growth** — new system sized for today, not tomorrow

## Related

- [[expand-contract|Expand-Contract Pattern]] — schema evolution
- [[strangler-fig|Strangler Fig Pattern]] — legacy system replacement
- [[blue-green-deployments|Blue-Green Deployments]] — deployment with data changes
- [[databases/README|Databases]] — specific database patterns

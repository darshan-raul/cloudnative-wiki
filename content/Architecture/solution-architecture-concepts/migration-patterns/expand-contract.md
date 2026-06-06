---
title: Expand-Contract Pattern
---

# Expand-Contract Pattern

The expand-contract pattern (also called parallel change or never break the contract) is a technique for safely evolving a shared API or database schema without downtime. The key principle: **a consumer of your API or schema should never experience an error due to a change you made**.

The name describes the two phases:
- **Expand** — add new capability (new column, new field, new endpoint) that doesn't break existing consumers
- **Contract** — remove old capability after all consumers have migrated away

## The Core Problem

```
Before change:
  Client (old) → Server: expects {id, name}
 Server ←: returns {id, name} ✓

After naive change (breaking):
  Client (old) → Server: expects {id, name}
                 Server ←: returns {id, name, phone} ← but old client doesn't understand phone
                 → Old client ignores phone (safe, but...)
```

But the real problem is the reverse:

```
After naive change (breaking the other way):
  Client (old) → Server: sends {id, name}
 Server ←: now REQUIRES phone field
                 → Old client sends no phone → 400 Bad Request ✗
```

## The Three-Phase Migration

### Phase 1: Expand (Add Only)

Add the new thing without breaking the old thing. Both old and new code must work simultaneously.

**API example:**

```bash
# Old API response
{
  "id": "123",
  "name": "Darshan"
}

# New API response (expand)
{
  "id": "123",
  "name": "Darshan",
  "email": "darshan@example.com"   # NEW field, nullable
}
```

The old client ignores the new field. The new client can use it. Both work.

**Database example:**

```sql
-- Add new column as nullable (no data, no NOT NULL constraint)
ALTER TABLE users ADD COLUMN phone VARCHAR(20);

-- v1 code: ignores phone column, works fine
-- v2 code: writes phone, reads phone (NULL if not set yet)
```

**Key rules during expand:**
- New fields are always nullable or optional
- New endpoints are additive (never break existing endpoints)
- Never require new fields in requests
- Keep old behavior as default

### Phase 2: Migrate (Backfill)

Populate the new structure with data from the old structure. This is a data migration, not a code change.

**API:** Notify consumers to start using the new field. This is a communication/coordination step.

**Database:**

```sql
-- Backfill: populate phone for users who have it elsewhere
UPDATE users
SET phone = email_lookup.phone
FROM email_lookup
WHERE users.email = email_lookup.email
  AND users.phone IS NULL;

-- Verify backfill is complete
SELECT COUNT(*) FROM users WHERE phone IS NULL AND email IS NOT NULL;
-- Should return 0 before proceeding
```

For large tables, backfill in batches to avoid locking:

```sql
-- Backfill in batches of 1000
DO $$
DECLARE
  batch_size INT := 1000;
  offset_val INT := 0;
  rows_updated INT;
BEGIN
  LOOP
    UPDATE users
    SET phone = 'pending'
    WHERE id IN (
      SELECT id FROM users
      WHERE phone IS NULL AND email IS NOT NULL
      LIMIT batch_size
    );

    GET DIAGNOSTICS rows_updated = ROW_COUNT;
    EXIT WHEN rows_updated = 0;

    PERFORM pg_sleep(0.1);  -- Throttle to reduce load
 END LOOP;
END $$;
```

### Phase 3: Contract (Remove Old)

After all consumers have migrated to the new thing, remove the old thing.

**API:** Remove the old field from responses. Remove the old endpoint.

**Database:**

```sql
-- Only after all code that uses the old column is gone
ALTER TABLE users DROP COLUMN old_field;
```

> **Critical:** You cannot contract until you're certain no code reads the old thing. This requires coordination with consumers (internal teams, API clients, mobile apps).

## Common API Migration Examples

### Adding a Required Field

```
Never: just add the field and require it
Always: add as optional → backfill → make required
```

### Renaming a Field

```
Never: rename field directly (breaks old clients)
Always: add new field → dual-write → migrate consumers → remove old field
```

```bash
# Phase 1: Add new field, keep old
{
  "id": "123",
  "name": "Darshan",           # old field
  "displayName": "Darshan"     # new field (duplicated)
}

# Phase 2: Dual-write (code update)
if (request.name) {
  record.name = request.name;
  record.displayName = request.name;  # sync
}

# Phase 3: Consumers migrated, remove old
{
  "id": "123",
  "displayName": "Darshan"    # old field removed
}
```

### Splitting One Table into Two

```
Phase 1: Add new table, add foreign key to old table
Phase 2: Backfill foreign keys
Phase 3: Migrate data, enforce constraints
Phase 4: Remove denormalized fields from old table
```

## Database Schema Migration Sequence

For schema changes that affect both the database and the application code:

```
1. Add new column as nullable (expand)
2. Deploy application code that writes to new column (but doesn't require it)
3. Backfill existing rows
4. Deploy code that reads from new column (prefers it)
5. Deploy code that REQUIRES new column (contract begins)
6. Drop old column (contract complete)
```

This requires **multiple deployment cycles**. Each cycle must be independently deployable and safe.

## Rules for Expand-Contract

1. **Never remove something in the same release that adds its replacement**
 - Spread changes across multiple deployments
   - Each deployment must be independently safe

2. **Never require new fields in requests**
   - New request fields = optional
   - Old clients sending old format must still work

3. **Never remove fields from responses without warning**
   - Add new fields first
   - Keep old fields until all consumers migrate
   - Communicate migration timelines

4. **Backfill must be complete before contracting**
   - Query for NULLs in new column: must return 0
   - Check dependent systems: all consumers migrated?

5. **Use feature flags to gate new behavior**
   - Deploy new code paths without activating them
   - Flip flag when ready, not at deploy time

## Expand-Contract vs Feature Flags

| Scenario | Pattern | Notes |
|---|---|---|
| Database schema evolution | Expand-contract | Requires multi-deployment cycle |
| API field addition | Expand-contract | Old clients ignore new field |
| Behavior change (pricing logic) | Feature flag | Gate without schema change |
| New service replacing old | Strangler fig | Incremental routing |

## Expand-Contract for Microservices

In a microservice architecture, expand-contract applies at service boundaries:

```
Service A → Service B (calls /v1/users endpoint)

Phase 1: Service B adds /v2/users alongside /v1/users
Phase 2: Service A migrates to /v2/users
Phase 3: Service B deprecates /v1/users
```

Deprecation notices and sunset headers help consumers plan migrations:

```bash
# Deprecation header
curl -I https://api.example.com/v1/users
HTTP/1.1 200 OK
Deprecation: true
Sunset: Sat, 01 Mar 2025 00:00:00 GMT
Link: <https://api.example.com/v2/users>; rel="successor-version"
```

## Common Mistakes

- **Too many changes in one release** — mixing expand and contract in the same deployment
- **Not monitoring backfill progress** — backfill running for days without visibility
- **Forgetting to contract** — old fields left in schema indefinitely ("zombie columns")
- **Not communicating timelines** — consumers surprised by deprecation
- **Breaking the expand rule** — making new fields required before consumers migrate

## Related

- [[blue-green-deployments|Blue-Green Deployments]] — deployment strategy that pairs well
- [[strangler-fig|Strangler Fig Pattern]] — incremental migration for legacy replacement
- [[data-migration|Data Migration Patterns]] — bulk data movement

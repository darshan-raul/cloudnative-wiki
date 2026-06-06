---
title: Strangler Fig Pattern
---

# Strangler Fig Pattern

The strangler fig pattern is a migration strategy for replacing a legacy system incrementally — routing pieces of functionality to the new system while the old system still runs, until the old system is eventually "strangled" and decommissioned. The name comes from a fig tree that grows around an existing tree, eventually replacing it.

## When to Use It

The strangler fig is the right pattern when:
- **Replacing a monolithic legacy system** — too risky to rewrite in one pass
- **No big-bang rewrite acceptable** — business can't tolerate downtime or migration risk
- **The legacy system is a black box** — no documentation, no tests, unknown behavior
- **You need to migrate data** — historical data must be preserved and accessible

## The Core Idea

```
Legacy System (monolith) = Old behavior you need to replace
New System (microservices) = New behavior you're building

Strategy: Route one piece at a time to new system until legacy is gone
```

## How It Works

### Step 1: Proxy In Front

Place a proxy (reverse proxy, API gateway) in front of both the legacy and new systems. All traffic starts going to the legacy system.

```
User → Proxy → Legacy System (100% traffic)
                New System (0% traffic)
```

### Step 2: Route One Feature to New System

Pick a small, independent feature. Build it in the new system. Route only that feature's traffic to the new system.

```
User → Proxy
 ↓ Feature /users → New System
         ↓ All other → Legacy System
```

### Step 3: Repeat Until Legacy is Strangled

Each iteration:
1. Identify another piece of functionality
2. Build it in the new system
3. Route that traffic to new system
4. Remove that functionality from legacy system

```
Iteration1: /users → new
Iteration 2: /orders → new
Iteration 3: /inventory → new
...
Legacy system gets smaller and smaller until it can be decommissioned
```

## Implementation: The Proxy Layer

The proxy is the traffic director. Two main approaches:

### 1. URL-Path Based Routing

```nginx
# Nginx: route /api/v2/* to new system, everything else to legacy
location /api/v2/ {
    proxy_pass http://new-system:8080;
    proxy_set_header Host $host;
}

location / {
    proxy_pass http://legacy-system:8080;
}
```

### 2. Header-Based Routing (Feature Flags)

```nginx
# Route based on header value (for A/B testing, gradual migration)
location / {
    if ($http_x_migration_flag = "new-system") {
        proxy_pass http://new-system:8080;
 }
    proxy_pass http://legacy-system:8080;
}
```

### 3. Percentage-Based Routing (Canary)

```yaml
# Kubernetes with Istio: gradual traffic shift
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: api
spec:
  hosts:
  - api.example.com
  http:
  - route:
    - destination:
        host: legacy-system
        weight: 95
    - destination:
        host: new-system
        weight: 5
```

## Data Migration with Strangler Fig

Historical data must be migrated from the legacy system to the new system. This is one of the hardest parts.

### Pattern: Dual-Write with Shadow Read

```
Phase 1: Write to legacy, read from legacy
Phase 2: Write to legacy AND new system (dual-write)
Phase 3: Read from new system, write to legacy (shadow read)
Phase 4: Write to new system, read from new system
```

**Phase 2 (dual-write)** is the riskiest — if the two systems get out of sync, you have data inconsistency.

### Pattern: Event Sourcing from Legacy

If the legacy system emits events (database changes, message queue), capture those events to feed the new system:

```
Legacy DB → CDC (Change Data Capture) → Message Queue → New System
```

Tools: Debezium, AWS DMS, custom triggers.

### Pattern: Copy-then-Sync

```
1. Bulk copy historical data to new system (batch job, overnight)
2. Enable real-time sync (CDC or dual-write)
3. Cut over reads to new system
4. Decommission legacy storage
```

## Identifying Features to Migrate First

Choose migration candidates based on:

1. **Low risk** — functionality that's well-understood, low business criticality
2. **Low coupling** — doesn't depend heavily on other parts of the monolith
3. **Clear boundaries** — clear API surface, minimal shared state
4. **High value** — frequently changed, bottleneck for team velocity

Avoid migrating the data layer first — migrate application logic, then handle data as a separate concern.

## The Anti-Corruption Layer

The new system shouldn't inherit the legacy system's data model. An **anti-corruption layer** translates between the legacy model and the clean new model:

```
Legacy System (messy schema) → Anti-Corruption Layer → New System (clean schema)
                              (transforms/translates)
```

```python
# Anti-corruption layer example
class LegacyUserMapper:
    def to_new_format(self, legacy_user: dict) -> NewUser:
        return NewUser(
            id=legacy_user['user_id'],           # different field name
            name=legacy_user['full_name'],       # different field name
            email=legacy_user['contact_email'],  # different field name
            created_at=parse_date(legacy_user['creation_dt'])  # different format
        )
```

This layer is temporary — once migration is complete, the anti-corruption layer is removed.

## Measuring Progress

Track migration progress by traffic volume, not just feature count:

```
Migration Progress = (Traffic to new system) / (Total traffic)
 ↓
 0% = fully legacy
                 100% = fully migrated
```

A system with 50 features migrated but 90% of traffic still hitting legacy is not done.

## Common Strangler Fig Mistakes

- **Migrating the wrong features first** — picking high-risk or highly-coupled features
- **No anti-corruption layer** — inheriting legacy data model mess into new system
- **Keeping legacy system running too long** — operational overhead of maintaining two systems
- **Data migration last** — treating data migration as an afterthought instead of a first-class concern
- **No rollback plan** — no way to route back to legacy if new system has issues
- **Legacy features that aren't strangled** — zombie features left in legacy forever because they're "too small to bother"

## Strangler Fig vs Other Patterns

| Pattern | When to use |
|---|---|
| **Strangler fig** | Replacing a legacy monolith incrementally |
| **Blue-green** | Deploying a new version of the same system |
| **Expand-contract** | Evolving a shared API or schema |
| **Big-bang rewrite** | Legacy is small enough to replace in one release (rare) |

## Related

- [[blue-green-deployments|Blue-Green Deployments]] — deployment strategy
- [[expand-contract|Expand-Contract Pattern]] — API/schema evolution
- [[data-migration|Data Migration Patterns]] — bulk data movement
- [[event-driven-architecture/README|Event-Driven Architecture]] — CDC and event sourcing

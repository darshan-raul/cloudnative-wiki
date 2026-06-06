---
title: Scalability
---

# Scalability

Scalability is the ability of a system to handle increased load by adding resources. The key question isn't "how fast is it now" but "how does performance change as load increases" — and "what does it cost to double capacity."

## Vertical vs Horizontal Scaling

### Vertical Scaling (Scale Up)

Add more power to the existing machine: more CPU, RAM, disk IOPS.

```
Before: 4 cores, 16GB RAM, 10K IOPS  →  handles1,000 RPS
After:  64 cores, 256GB RAM, 100K IOPS → handles ~10,000 RPS
```

**Pros:** No code changes, shared memory (no distributed state complexity), lower latency.
**Cons:** Hardware ceiling, single point of failure, maintenance requires downtime.

### Horizontal Scaling (Scale Out)

Add more machines to the pool.

```
Before: 2 app servers → handles 1,000 RPS
After:  20 app servers → handles10,000 RPS
```

**Pros:** Near-unlimited scale, fault tolerance (lose one node, pool absorbs it).
**Cons:** Requires stateless design, session affinity considerations, distributed state management.

### The Architecture Decision

| Factor | Go Vertical | Go Horizontal |
|---|---|---|
| Team size | Small team | Large team with platform/SRE |
| Growth curve | Predictable, slow | Unpredictable or fast |
| Complexity tolerance | Low | High |
| Failure tolerance | Single node OK | Need resilience |
| Latency sensitivity | Very high (shared memory) | Moderate (stateless is fast enough) |
| Data layer | Single-writer DB | Sharded or distributed DB |

Most architectures start vertical, then shift to horizontal when they hit hardware limits or need fault tolerance. A hybrid approach (vertical for data layer, horizontal for app layer) is common.

## The Scalability Formula

For any system, identify the **bottleneck** — the component that hits its limit first:

```
Capacity = min(
    CPU_capacity / CPU_per_request,
    Memory_capacity / Memory_per_request,
    Network_capacity / Network_per_request,
    Disk_IOPS_capacity / Disk_IOPS_per_request,
    DB_connections_capacity / DB_connections_per_request
)
```

The **smallest** ratio is your actual capacity. Optimizing the wrong ratio wastes money.

## Stateless Architecture

Horizontal scaling requires stateless application servers. Every request must contain all information needed to process it — no server-local session state.

```
# Stateless: session data lives in external store
GET /api/users/123/session
  → Redis lookup (session store) → return user data
  → Any app server can handle this request

# Stateful: session data lives on the server
GET /api/users/123/session
  → Local memory lookup → return user data
  → Only server-123 can handle this request (sticky session)
```

**Rule:** If you need state, push it to an external store (Redis, Memcached, DB). App servers are cattle, not pets.

## Database Scalability Patterns

The database is almost always the scalability bottleneck. Solutions:

### Read Replicas

```
Primary (writes) → Replica 1 (reads) → Replica 2 (reads) → ...
```

Route read queries to replicas, writes to primary. Works for read-heavy workloads (90/10 read/write is common). Replication lag means replica reads may be slightly stale — acceptable for most use cases, not for financial transactions.

### Sharding

Split data across multiple database instances by shard key:

```
User ID % 4 == 0 → Shard 0
User ID % 4 == 1 → Shard 1
User ID % 4 == 2 → Shard 2
User ID % 4 == 3 → Shard 3
```

**Shard key selection is critical.** A bad shard key creates hot spots (one shard gets all writes for a power user). Common shard keys: user ID, geographic region, time-based (with caution).

### CQRS (Command Query Responsibility Segregation)

Separate read and write models. Write to a optimized write store, project to a optimized read store:

```
Write path: API → Write DB (normalized, write-optimized)
Read path:  API → Read DB (denormalized, read-optimized)

Event: UserUpdated
  → Projection writes to read store
  → Report table updated asynchronously
```

High complexity, high payoff for write-heavy workloads with complex read patterns.

## Caching for Scale

Caching reduces database load by serving repeated reads from memory:

```
Request → Cache hit? → return cached
 ↓ miss
                 DB query → cache result → return
```

**Cache hit rate** is the most important metric:

```
Hit rate = (cache hits) / (cache hits + cache misses)
```

- 90% hit rate → 10x reduction in DB load
- 99% hit rate → 100x reduction in DB load

Each additional 9 in hit rate is harder to achieve than the last. Diminishing returns kick in fast.

## Auto-Scaling

Dynamically add/remove capacity based on demand:

```yaml
# Kubernetes HPA example
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 3
  maxReplicas: 100
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

**Scaling thresholds** must account for:
- **Cold start time** — new instances take 30-120 seconds to be ready
- **Cooldown period** — prevent thrashing (scale up, then immediately scale down)
- **Predictable spikes** — auto-scale reacts, scheduled scale pre-empts (daily traffic patterns, product launches)

## Scaling Laws

**Universal Scalability Law (USL)** — as you add nodes, throughput increases, but not linearly. There's overhead from coordination (locks, network messages, data partitioning). Eventually, adding nodes actually decreases throughput.

```
理想: Throughput ∝ N_nodes (linear)
现实: Throughput = N_nodes / (1 + α(N_nodes-1) + β(N_nodes-1)(N_nodes-2))
                                    ↑    ↑
 contention coordination
```

**Key insight:** Amdahl's law says the fraction of the system that can't be parallelized caps your maximum speedup. If10% of your code is serial, maximum speedup is 10x regardless of how many nodes you add.

## When to Scale

Metrics that signal you need to scale:

- **CPU utilization > 70-80% sustained** — headroom for spikes disappears
- **P99 latency increasing** — system is approaching its limit
- **Queue depth growing** — message queue backing up means producers outpace consumers
- **Error rate > 0.1%** — system is in overload, dropping requests

**Don't wait for failures.** Scale when utilization crosses60-70%, not when it hits 100%.

## Common Scalability Mistakes

- **Premature sharding** — adds massive complexity before you need it
- **Ignoring the bottleneck** — scaling the wrong component (more app servers when DB is the bottleneck)
- **No connection pooling** — DB connections are finite and slow to establish
- **Synchronous cache invalidation** — invalidation on every write adds latency
- **No caching strategy** — every request hits the database
- **Shard key hotspot** — time-based shard keys cause hot shards during peak periods

## Related

- [[performance|Performance]] — latency and throughput fundamentals
- [[back-of-the-envelope-calculations|Back-of-the-Envelope Calculations]] — quick capacity estimates
- [[performance-testing|Performance Testing]] — load testing methodology
- [[caching|Caching]] — cache patterns and hit rates

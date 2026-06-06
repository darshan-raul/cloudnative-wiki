---
title: Performance
---

# Performance

Performance is the measure of how fast a system responds to requests and how much work it can accomplish within a given timeframe. For a solution architect, performance isn't a single number — it's a set of measurable targets across latency, throughput, and resource efficiency.

## Core Metrics

### Latency

**Latency** is the time between a request being sent and the response being received. Key percentiles:

| Percentile | What it means | Common target |
|---|---|---|
| p50 (median) | Half of requests are faster | < 100ms for APIs |
| p95 | 5% of requests are slower | < 200ms for web |
| p99 | 1% of requests are slowest | < 500ms for non-real-time |
| p99.9 | 0.1% — your worst users | < 1s for any sync call |

> **ELI5:** p99 means "if 1000 requests come in, the 10 slowest ones should still be under your limit." That's the customer you don't want to lose.

Always measure latency from the **client's perspective**, not the server. Network transit, CDN, and load balancers add invisible time.

### Throughput

**Throughput** is how many requests the system can handle per unit time.

- **Requests per second (RPS)** — for stateless HTTP services
- **Transactions per second (TPS)** — for payment/financial systems
- **Events per second (EPS)** — for event-driven systems

Throughput is bounded by your slowest component. A database that maxes out at 5,000 queries/second caps your API layer regardless of how many app servers you add.

### Resource Efficiency

How much work you extract from each unit of infrastructure:

- **CPU utilization** — cycles spent doing useful work vs idle/wait
- **Memory efficiency** — working set vs RSS, GC pressure
- **IOPS** — disk operations per second (often the hidden bottleneck in databases)
- **Network bandwidth** — saturation at high fan-out architectures

## Designing for Performance

### The Latency Stack

Every request touches multiple layers. Sum them to get total latency:

```
Total Latency = Network Latency
 + Load Balancer overhead
              + TLS handshake (if new connection)
              + Application logic
              + Database queries (N queries × avg query time)
              + Serialization/deserialization
              + Response network transit
```

Reducing any single layer improves the whole. Common wins: connection pooling (removes TLS overhead), read replicas (removes write bottleneck), caching (removes DB round-trips).

### Horizontal vs Vertical Scaling

**Vertical scaling** (bigger machine) — simpler, no architectural changes, hits hardware limits fast, single point of failure.

**Horizontal scaling** (more machines) — scales linearly, requires stateless design, adds complexity at the load-balancing layer.

| Approach | Pros | Cons |
|---|---|---|
| Vertical | Simple, low latency (shared memory) | Hardware ceiling, single failure point |
| Horizontal | Near-unlimited scale, fault tolerance | Stateless requirement, session affinity issues |
| Hybrid | Best of both | Complex — big machines in the data path |

### Caching as a Performance Multiplier

Caching is the single highest-leverage performance move in architecture. Layers:

1. **CDN / Edge** — static assets, API responses with long TTLs
2. **Reverse proxy** (Nginx, Varnish) — response caching for expensive queries
3. **Application cache** (Redis, Memcached) — session data, computed results
4. **Database query cache** — MySQL query cache, Postgres shared buffers
5. **OS page cache** — kernel-level file caching (often overlooked)

**Cache invalidation** is the hard problem. Strategies:
- **TTL-based** — simple, eventual consistency, risk of stale reads
- **Event-driven invalidation** — pub/sub invalidation on write (complex, immediate)
- **Write-through** — update cache on every write (consistency, write latency cost)
- **Write-behind** — update cache async after write (fast writes, risk of loss)

### Database Performance Patterns

**N+1 queries** — the silent killer. One query to get a list, then one query per item. At1,000 items, that's 1,001 database round-trips.

```sql
-- N+1 problem
SELECT * FROM orders;                    -- 1 query
-- then for each order:
SELECT * FROM order_items WHERE order_id = ?;  -- 1000 queries

-- Fixed: JOIN
SELECT o.*, i.* FROM orders o
JOIN order_items i ON o.id = i.order_id;  -- 1 query
```

**Connection pooling** — opening a DB connection is expensive (~5-20ms). Pool10-50 connections and share across requests. PgBouncer for Postgres, HikariCP for Java.

**Read replicas** — route read queries to replicas, writes to primary. Linear scale for read-heavy workloads (90/10 read/write ratio is common).

**Sharding** — horizontal partition of data across nodes. Choose the shard key carefully — a bad key causes hot spots (one shard takes all traffic).

## Performance Testing

See [[performance-testing|Performance Testing]] for load testing types (load, stress, spike, soak) and tooling.

## SLOs and Performance

Performance targets become **Service Level Objectives (SLOs)**:

```
Target: p99 latency < 200ms for /api/checkout
Current: p99 = 180ms @ 500 RPS
Action: Alert when p99 > 150ms (headroom before breach)
```

Performance budgets are per-endpoint. `/api/checkout` might need p99 < 200ms while `/api/search` tolerates p99 < 2s.

## Common Anti-Patterns

- **Premature optimization** — profiling first, optimizing second. Don't guess.
- **Ignoring p99** — median looks great, p99 is where users rage-quit.
- **No connection pooling** — every request opens a new DB connection.
- **Synchronous everything** — fire-and-forget for non-critical operations.
- **Missing timeouts** — a slow dependency cascades into a full outage.

## Related

- [[availability|Availability]] — uptime guarantees
- [[scalability|Scalability]] — handling growing load
- [[performance-testing|Performance Testing]] — load testing methodology
- [[caching|Caching]] — cache patterns and invalidation
- [[back-of-the-envelope-calculations|Back-of-the-Envelope Calculations]] — quick capacity estimates

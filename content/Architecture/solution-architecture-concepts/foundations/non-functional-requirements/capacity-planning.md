---
title: Capacity Planning
---

# Capacity Planning

Capacity planning answers: "Do we have enough resources to handle the expected load — now, and in the future?" It's the bridge between business growth projections and infrastructure investment.

## The Core Formula

For any resource, capacity is determined by:

```
Capacity = (Resource Amount) / (Resource Consumption per Unit of Work)
```

**Example:**
```
Fargate task: 1 vCPU, 2GB RAM
Avg request:50ms CPU, 128MB RAM working set
Max concurrent requests (CPU): 1000ms / 50ms = 20 concurrent per task
Max concurrent requests (Memory): 2048MB / 128MB = 16 concurrent per task

Bottleneck: Memory → 16 concurrent requests per task
If target: 1,000 concurrent users → need ceil(1000/16) = 63 tasks
```

The **bottleneck** is the resource that runs out first. Optimize the bottleneck, not everything.

## Resource Dimensions

### Compute (CPU)

- **Utilization target:** 60-70% sustained (headroom for spikes)
- **Scaling trigger:** > 70% sustained for 5+ minutes
- **Measurement:** CPU steal (for cloud VMs), CPU credits (for burstable instances)

### Memory

- **Working set** — memory actively used (not total RSS)
- **OOM events** — system kills process when memory exhausted
- **GC pressure** — in managed languages (Java, Go), GC pauses increase with memory utilization

### Storage

- **IOPS vs throughput** — IOPS (random ops) vs throughput (sequential MB/s)
- **Disk queues** — requests waiting for disk (indicator of saturation)
- **SSD vs HDD** — SSD for random IOPS workloads, HDD for high-throughput sequential

### Network

- **Bandwidth** —饱和 at high fan-out (many services calling many others)
- **Connections** — TCP connection limits (especially for connection-pooled protocols)
- **DNS query rate** — often overlooked (many services resolve on every request)

### Database Connections

Often the hidden bottleneck:

```
App servers: 50 instances × 100 connections each = 5,000 connections
DB max connections: 1,000
→ Gap: 4,000 connections short at peak
```

**Solution:** Connection pooling (PgBouncer, HikariCP) to multiplex many app connections onto fewer DB connections.

## Forecasting

### Linear Extrapolation

For predictable growth:

```
Current:10,000 RPS,30% CPU
Growth: 20% per quarter
Next quarter: 12,000 RPS
At 12,000 RPS, 30% CPU → CPU at 36% (still OK)
At 20,000 RPS, 30% CPU → CPU at 60% (need to scale)
So: scale before next quarter
```

### Growth Curves

Not all growth is linear. Distinguish:

- **Linear** — steady growth, predictable capacity needs
- **Step function** — product launches, marketing campaigns cause sudden jumps
- **Exponential** — viral growth, network effects (hardest to plan for)
- **Seasonal** — daily peaks, monthly billing cycles, holiday spikes

### Capacity Planning Process

```
1. Current state assessment
   → Measure actual resource consumption per component
   → Identify current bottlenecks

2. Growth projection
   → Business forecast (user growth, transaction growth)
   → Historical growth rate
   → Planned product changes (new features = new load patterns)

3. Headroom calculation
   → Current capacity × 1.3 (30% headroom minimum)
   → Factor in known upcoming events (product launch, peak season)

4. Gap analysis
   → Required capacity - Current capacity = Gap
   → Time to gap = timeline for procurement/deployment

5. Procurement and deployment
   → Lead time for new resources
   → Provision and test before you need them
```

## Back-of-the-Envelope Calculations

Quick estimates for common scenarios:

### API Server Capacity

```
Target: 10,000 RPS
Avg response time: 100ms
Concurrent requests at steady state: 10,000 × 0.1 = 1,000 concurrent
Each server handles: 500 concurrent (CPU-bound, not I/O bound)
Servers needed: ceil(1000/500) = 2 (use 4 for HA + headroom)
```

### Database Capacity

```
Target: 5,000 writes/sec, 50,000 reads/sec
Write-heavy (Postgres):
  - Each write uses ~1ms CPU time
  - 8-core DB → ~8,000 writes/sec max (per instance)
  - Need:1 writer (can parallelize reads with replicas)

Read replicas:
  - Each replica handles ~2,000 reads/sec
  - Need: ceil(50,000/2,000) = 25 read replicas
  - Replication lag: ~100ms (acceptable for non-financial)
```

### Cache Capacity

```
Working set: 10 million items
Avg item size: 2KB
Total working set: 20GB
Redis: 25GB allocated (some overhead, fragmentation)
Need: at least 25GB memory for working set
```

## Cost Modeling

Every capacity decision has a cost dimension:

### Cost Per User

```
Monthly infra cost: $50,000
Active users: 100,000
Cost per user per month: $0.50
Cost per user per year: $6.00
LTV: $500 → cost is 1.2% of LTV (healthy)
```

### Cost Scaling Patterns

| Scaling approach | Cost curve | Notes |
|---|---|---|
| Vertical (bigger instance) | Step function | Pay for idle capacity |
| Horizontal (more small instances) | Linear | Pay for what you use |
| Serverless (Lambda, Cloud Run) | Pay-per-use | Good for variable load |
| Reserved instances |30-60% savings | Commitment required |

### Right-Sizing

Most cloud workloads are over-provisioned by 2-4x. Regularly review:

- **Actual CPU utilization** — if averaging 20%, you're paying for 80% idle
- **Right-sizing recommendations** — AWS Compute Optimizer, Azure Advisor
- **Scaling down** — reduce instance sizes as load is characterized

## Capacity and Performance Interaction

Capacity planning and performance are linked:

- **More capacity → lower latency** (less queuing)
- **Better performance → more capacity** (same hardware serves more)
- **Performance optimization → defer capacity purchase** (cheaper than scaling)

The order of preference:
1. **Optimize first** — faster code, better caching, lower latency
2. **Scale horizontally** — add more machines
3. **Scale vertically** — bigger machines (last resort)

## Monitoring for Capacity

Key signals that predict capacity exhaustion:

| Signal | Threshold | Action |
|---|---|---|
| CPU > 70% sustained | Warning | Plan scale-up |
| CPU > 85% | Critical | Scale immediately |
| Memory > 80% | Warning | Investigate memory leak |
| Disk queue > 10 | Warning | IO bottleneck |
| DB connections > 80% max | Warning | Connection pool or scale |
| P99 latency increasing | Any increase | Capacity constrained |
| Queue depth growing | Warning | Consumer lag |

## Common Capacity Planning Mistakes

- **No growth buffer** — capacity plan for today, not tomorrow
- **Ignoring the data layer** — scale app servers, forget the DB is the bottleneck
- **No connection pooling** — finite DB connections, not scaled with app servers
- **Not measuring utilization** — decisions based on gut, not data
- **Over-provisioning "to be safe"** — wasted cost
- **Under-provisioning "to save money"** — performance crises, emergency scaling
- **No cost monitoring** — don't discover over-provisioning in the bill

## Related

- [[back-of-the-envelope-calculations|Back-of-the-Envelope Calculations]] — quick estimates
- [[scalability|Scalability]] — scaling patterns
- [[performance|Performance]] — latency and throughput
- [[reliability|Reliability]] — capacity for resilience

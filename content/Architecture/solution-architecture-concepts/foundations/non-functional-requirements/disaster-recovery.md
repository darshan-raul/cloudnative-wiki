---
title: Disaster Recovery
---

# Disaster Recovery

Disaster recovery (DR) is the ability to restore full service after a major failure that takes out one or more critical components. Unlike standard reliability (single component failure), DR addresses catastrophic failures — entire regions, data corruption, ransomware, natural disasters.

## RPO and RTO

Two numbers define your DR posture:

- **RPO (Recovery Point Objective)** — maximum acceptable data loss measured in time. "RPO = 1 hour" means you must lose no more than 1 hour of data.
- **RTO (Recovery Time Objective)** — maximum acceptable downtime. "RTO = 4 hours" means you must restore service within 4 hours.

```
RPO = how much data can we afford to lose?
RTO = how long can we afford to be down?
```

These are business decisions, not technical ones. Finance cares about RPO (transactions), Operations cares about RTO (service restoration).

| Criticality | RPO | RTO | Example |
|---|---|---|---|
| Mission-critical | 0 (synchronous replication) | < 15 min | Financial trading, emergency services |
| Business-critical | < 1 hour | < 4 hours | E-commerce checkout, ERP |
| Business-operational | < 24 hours | < 24 hours | Internal tools, reporting |
| Low-critical | < 1 week | < 1 week | Analytics, data pipelines |

## DR Strategies

### Strategy 1: Backup and Restore

Periodically back up data, restore from backup after disaster.

```
Nightly backup → restore takes hours → RTO = hours to days
Weekly backup → restore takes days → RTO = days
```

**Pros:** Simple, low cost, works for any data store.
**Cons:** High RPO (all data since last backup is lost), high RTO (restore takes time).

**When to use:** RTO > 24 hours acceptable, data not frequently changed, budget constrained.

### Strategy 2: Pilot Light

A minimal version of your infrastructure is always running in the secondary region. Core data is replicated, but app servers are off until needed.

```
Primary: Full infrastructure (all services running)
Secondary: Pilot light (DB replica, minimal compute, storage)

Disaster:
1. Scale up secondary app servers (minutes)
  2. Update DNS to secondary (DNS TTL must be low)
  3. Restore from replicated data (already there)
  RTO: 15 minutes to 2 hours
```

**Pros:** Lower cost than full hot standby, reasonable RTO.
**Cons:** Secondary isn't production-tested until disaster strikes, data replication lag.

**When to use:** RTO in hours acceptable, budget constraints, regional disaster scenario.

### Strategy 3: Warm Standby

Secondary region has scaled-down but functional infrastructure. Data is synchronously or near-synchronously replicated.

```
Primary: Full infrastructure
Secondary: Warm standby (10-20% capacity, scaled down)

Disaster:
  1. Scale up secondary to full capacity (auto-scale, 5-15 minutes)
  2. DNS failover (1-5 minutes with low TTL)
  RTO: 15-60 minutes
```

**Pros:** Faster failover than pilot light, regularly tested (at reduced scale).
**Cons:** Higher cost (standby always running), still a gap between normal and DR capacity.

**When to use:** RTO in minutes to hours, some budget for standby infrastructure.

### Strategy 4: Multi-Region Active-Active

Two or more regions serve traffic simultaneously. If one region fails, the other absorbs all traffic.

```
Region A (50% traffic) ←→ Data (synchronous replication) ←→ Region B (50% traffic)
Region C (geo-distributed reads) ←→ Data (async replication)
```

**Pros:** Near-zero RTO for regional failure, no "disaster mode" activation needed.
**Cons:** Maximum complexity, maximum cost, cross-region writes are slow (latency penalty).

**When to use:** RTO < 15 minutes, revenue-critical systems, global user base with latency requirements.

## Data Replication Patterns

### Synchronous Replication

Write confirmed only when both primary and replica acknowledge.

```
Client → Primary → Replica (ack) → Client (write confirmed)
```

- **RPO = 0** for replica failure (no data loss)
- **Latency penalty** = one-way network latency to replica
- **Availability penalty** — write blocked if replica is down

### Asynchronous Replication

Write confirmed on primary, replicated to replica in background.

```
Client → Primary (ack immediately) → Replica (async, background)
```

- **Latency penalty** = minimal (only primary ack required)
- **RPO > 0** — some data loss if primary fails before replication
- **Replica can lag** — network issues cause replication backlog

### Change Data Capture (CDC)

Capture database changes as events and stream to secondary:

```
Primary DB → CDC (Debezium, AWS DMS) → Message Queue → Secondary DB
```

- **Near-real-time** — typically seconds of lag
- **Schema evolution handling** — complex but powerful
- **Works across heterogeneous stores** — migrate from MySQL to Postgres

## DR Topology

### Same-Region, Different AZs

Cheapest multi-AZ setup. Protects against single AZ failure, not against region-level disasters.

```
us-east-1a (primary) ←→ us-east-1b (secondary AZ)
  ↑ RDS Multi-AZ (synchronous)
```

### Cross-Region

Protects against regional disasters. Choose regions with geographic separation:

```
us-east-1 (primary) ←→ eu-west-1 (secondary)
us-west-2 (primary) ←→ ap-southeast-1 (secondary)
```

**Considerations:**
- Data residency laws (data can't leave certain jurisdictions)
- Cross-region latency (all writes have added latency)
- Cost differences between regions

## Failover Procedures

DR is only as good as the failover procedure. Document and test it.

### DNS Failover

```
Normal: api.example.com → ALIAS → CloudFront → LB → us-east-1
Disaster: Change ALIAS → us-west-2
```

**Requirements:**
- Low TTL on DNS records (60 seconds or less)
- Health checks before failover (don't fail over to a also-failing region)
- Automated DNS update (Route53 health check + failover routing)

### Database Failover

```
Primary (us-east-1) → Replica (us-west-2)
Disaster:
  1. Promote replica to primary ( RDS promote-read-replica)
  2. Update connection strings (or use a proxy/endpoint)
  3. Verify data integrity
  4. DNS failover to new primary
```

### Application Failover

```
Disaster:
  1. Verify secondary region is healthy (health checks)
  2. Scale secondary app tier to full capacity
  3. Update DNS / load balancer
  4. Clear cached state (Redis in secondary region)
  5. Verify end-to-end functionality
```

## Testing DR

A DR plan that hasn't been tested is not a DR plan.

### Types of DR Testing

| Test Type | What it exercises | Frequency |
|---|---|---|
| **Tabletop exercise** | Walk through procedure, identify gaps | Quarterly |
| **Partial failover** | Fail over one component, verify recovery | Monthly |
| **Full failover** | Complete DR drill, measure actual RTO | Annually |
| **Chaos injection** | Deliberately destroy components, verify recovery | Monthly |

### Measuring Actual RTO

Run a real failover and measure:

```
t_discovery = time failure is detected
t_notification = time on-call is paged
t_diagnosis = time to understand root cause
t_decision = time to decide on DR action
t_execution = time to execute DR procedure
t_verification = time to verify service restored

RTO = t_discovery + t_notification + t_diagnosis + t_decision + t_execution + t_verification
```

Most companies discover their RTO is 2-10x their planned RTO when they first test.

## Common DR Mistakes

- **DR plan not documented** — procedure lives in one engineer's head
- **DNS TTL too high** — failover takes hours because records cached everywhere
- **No regular DR testing** — plan is untested until disaster strikes
- **Replication lag not monitored** — replica is days behind and nobody noticed
- **Secrets not replicated** — credentials needed for failover aren't in secondary region
- **Data in the wrong region** — compliance data residency violated during failover
- **Single vendor dependency** — cloud provider outage takes out both primary and DR

## Related

- [[availability|Availability]] — uptime architecture
- [[reliability|Reliability]] — fault tolerance patterns
- [[back-of-the-envelope-calculations|Back-of-the-Envelope Calculations]] — capacity for DR infra

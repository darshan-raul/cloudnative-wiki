---
title: Availability
---

# Availability

Availability is the percentage of time a system is operational and accessible. For a solution architect, availability is not just a percentage — it's a contractual commitment backed by architectural decisions.

## The Nineys

Availability is expressed as a percentage of uptime per year:

| Availability | Downtime/year | Downtime/month | Downtime/week |
|---|---|---|---|
| 99% ("two nines") | 3.65 days | 7.31 hours | 1.69 hours |
| 99.9% ("three nines") | 8.76 hours | 43.83 min | 10.08 min |
| 99.99% ("four nines") | 52.60 min | 4.38 min | 1.01 min |
| 99.999% ("five nines") | 5.26 min | 26.30 sec | 6.05 sec |

> **ELI5:** Each "nine" costs roughly 90% of the downtime of the previous level. Going from 99% to 99.9% saves you 3 days of downtime per year. Going from 99.9% to 99.99% saves you 8 hours. The cost to achieve the last nine is usually10x the cost of the first.

## What Availability Numbers Mean in Practice

**99.9% (3 nines)** — standard for consumer web apps. Planned maintenance windows acceptable. Brief outages are tolerable.

**99.99% (4 nines)** — enterprise SaaS, B2B products. Requires automated failover, not manual intervention. Downtime is a contract breach.

**99.999% (5 nines)** — telecom, financial trading, emergency services. ~5 minutes downtime/year. Requires active-active architecture with automatic failover and pre-calibrated runbooks.

## The Components of Availability

Availability is multiplicative across the entire call chain:

```
Total Availability = A_service1 × A_service2 × A_database × A_load_balancer × ...
```

If your API (99.9%) calls a database (99.99%) which calls a cache (99.9%):

```
Total = 0.999 × 0.9999 × 0.999 = 0.9979 ≈ 99.79%
```

Every component in the critical path drags down the total. This is why **reducing dependencies** improves availability more than hardening any single component.

## Architectural Patterns for Availability

### Redundancy

Run multiple copies of every component. If one fails, traffic routes to survivors.

- **Active-active** — all nodes serve traffic simultaneously. Failover is instant (DNS flip or load balancer weight change). Requires distributed state (sessions, DB).
- **Active-passive** — standby node(s) take over on failure. Simpler state management, but failover takes seconds to minutes (health check interval + routing propagation).

### Health Checks and Failover

Load balancers need health checks to know when to remove a failed node:

```nginx
# Nginx upstream health check
upstream backend {
    server10.0.1.1:8080;
    server 10.0.1.2:8080;
}

# Kubernetes readiness probe
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```

Health checks should verify **actual functionality**, not just process aliveness. A process can be up but deadlocked — the health endpoint catches this.

### Circuit Breakers

Prevent cascading failures by stopping requests to a failing dependency:

```
Normal → dependency responds< 100ms
 ↓
Failure rate exceeds50% in 10 seconds
     ↓
Circuit OPENS → requests fail fast (no round-trip to dead dependency)
     ↓
After 30 seconds → HALF-OPEN → allow test requests through
     ↓
Still failing → OPEN again
     ↓
Recovering → CLOSED (normal operation resumes)
```

Pattern: [[resilience|Resilience]] has more detail on circuit breakers.

### Graceful Degradation

When full functionality isn't possible, provide partial functionality:

- **Feature flags** — disable expensive features (recommendations, analytics) under load
- **Fallback responses** — serve cached/stale data when the database is unavailable
- **Read-only mode** — allow reads but block writes during partial outages

### Rate Limiting and Backpressure

Protect the system from overload. See [[rate-limiting|Rate Limiting]] for implementation.

## Planned vs Unplanned Downtime

**Unplanned** — failures (hardware, software, network). Mitigated by redundancy, monitoring, and incident response.

**Planned** — deployments, maintenance. Mitigated by:
- Rolling deployments (zero-downtime updates)
- Blue-green deployments (instant rollback capability)
- Feature flags (disable features without redeploying)

> **Key insight:** 80% of downtime is planned (deployments). Reducing planned downtime often matters more than hardening against unplanned failures.

## SLOs vs SLAs

- **SLO (Service Level Objective)** — internal target you aim for. "We target 99.95% uptime."
- **SLA (Service Level Agreement)** — contractual commitment to customers. Usually slightly lower than your SLO (gives buffer before breach).

SLOs should be tighter than SLAs. If your SLA is 99.9%, set your SLO at 99.95% — the gap absorbs unexpected issues before they become SLA breaches.

## Observability for Availability

Availability problems are detected through:

- **Synthetic monitoring** — periodic scripted checks from outside your network (catches network-path failures)
- **Real user monitoring (RUM)** — actual user request performance (catches client-side issues)
- **Uptime checks** — HTTP checks from multiple geographic regions (PagerDuty, Better Uptime)
- **Error rate spikes** — sudden increase in 5xx responses is the fastest availability signal

## Common Availability Killers

- **Single points of failure** — one database, one load balancer, one availability zone
- **Synchronous full-stack restarts** — app server restart cascades to database overload
- **Missing timeouts** — one slow dependency takes down the entire system
- **No health checks** — load balancer keeps routing to dead instances
- **Hard-coded IPs or hostnames** — can't failover when IPs change
- **No rollback plan** — failed deployment requires manual intervention (hours of downtime)

## Related

- [[reliability-vs-availability|Reliability vs Availability]] — the distinction
- [[resilience|Resilience]] — patterns for handling failures
- [[load-balancing|Load Balancing]] — traffic distribution
- [[disaster-recovery|Disaster Recovery]] — recovering from major outages

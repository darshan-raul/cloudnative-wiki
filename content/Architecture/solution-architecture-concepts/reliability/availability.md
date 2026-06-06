---
title: Availability
tags: [architecture, reliability, sla]
date: 2025-05-24
description: Designing for high availability — SLA, SLO, and failure budgets
---

# Availability

Availability is the **proportion of time a system is operational and accessible**. It's the first reliability metric stakeholders care about.

---

## Key Terms

| Term | Meaning | Example |
|------|---------|---------|
| **SLA** (Service Level Agreement) | Contractual commitment to customers | "99.9% uptime, or we pay credits" |
| **SLO** (Service Level Objective) | Internal target you aim for | "Target 99.95% uptime" |
| **SLI** (Service Level Indicator) | What you actually measure | Real p99 latency, real error rate |
| **Error Budget** | Allowable downtime per period | 4.38 min/month at 99.9% |

---

## Availability Tiers

| Target | Downtime/Year | Downtime/Month | Downtime/Week |
|--------|--------------|----------------|---------------|
| 90% | 36.5 days |3 days | 16.8 hours |
| 99% | 3.65 days | 7.3 hours | 1.7 hours |
| 99.9% | 8.76 hours | 43.8 min | 10.1 min |
| 99.95% | 4.38 hours | 21.9 min | 5.0 min |
| 99.99% | 52.6 min | 4.4 min | 1.0 min |
| 99.999% | 5.26 min | 26.3 sec | 6.1 sec |

**Rule:** Each9 costs ~10x in complexity and infrastructure cost.

---

## Measuring Availability

### SLI Patterns

```python
# Availability = successful requests / total requests
availability = successful_requests / total_requests * 100

# For a system with SLO of 99.9%:
# Allowable error budget: 0.1% of requests per window
# If you handle 1M req/day, error budget = 1000 failed req/day
```

### Common SLIs

| Service Type | Good SLI | Bad SLI |
|-------------|---------|---------|
| User-facing API | Request success rate | — |
| Read-heavy data | Cache hit ratio | — |
| Write-heavy data | Commit success rate | — |
| Background jobs | Job completion rate | — |
| Data pipeline | Records processed / expected | — |

---

## Error Budgets

The **error budget** is the allowable amount of unreliability before you freeze features and focus on stability.

```
SLO: 99.9% (43.8 min/month downtime budget)
Actual: 99.95% (21.9 min/month downtime) ← budget healthy, ship features

Actual: 99.85% (65.7 min/month downtime) ← budget burning, halt feature work
```

### Budget Policy

```yaml
# Alert when error budget is burning fast
error_budget_remaining < 50%:
  severity: warning
  action: investigate reliability incidents

error_budget_remaining < 10%:
  severity: critical
  action: feature freeze, all hands on reliability
```

---

## Designing for Availability

### Redundancy Patterns

```
Single component:      Redundant:
┌──────────┐           ┌────┐  ┌────┐
│ DB    │           │ DB │  │ DB │ ← primary + replica
└──────────┘           └────┘  └────┘
   ↓ failure ↓ replica handles failover

Multi-AZ deployment:
┌──────────┐  ┌──────────┐  ┌──────────┐
│  AZ-1   │  │  AZ-2   │  │  AZ-3   │
│ ┌────┐ │  │  ┌────┐ │  │  ┌────┐ │
│  │app │ │  │  │app │ │  │  │app │ │
│  └────┘ │  │  └────┘ │  │  └────┘ │
│  ┌────┐ │  │  ┌────┐ │  │ ┌────┐ │
│  │ DB │ │  │  │ DB │ │  │  │ DB │ │
│  └────┘ │  │  └────┘ │  │  └────┘ │
└──────────┘  └──────────┘  └──────────┘
 ↑ AZ failure = handled by other AZs
```

### High Availability Checklist

```
□ Active-active across2+ AZs (not active-passive)
□ Database with同步 replication (or equivalent)
□ Load balancer health checks with automatic removal
□ Graceful degradation (circuit breakers)
□ Health endpoints for orchestration (k8s readiness/liveness)
□ Regular chaos testing (game days)
□ Runbook for every failure scenario
□ Observability: SLO dashboard + error budget alerts
```

---

## Common Causes of Downtime

| Cause | Mitigation |
|-------|-----------|
| Database overload | Read replicas, connection pooling, query limits |
| Cascading failures | Circuit breakers, bulkheads, rate limiting |
| Deployment failures | Blue-green, canary, rollback automation |
| Dependency outage | Graceful degradation, fallback behavior |
| Traffic spikes | Auto-scaling, rate limiting, CDN |
| Configuration errors | Config-as-code, staged rollout, validation |
| Resource exhaustion | Auto-scaling, resource limits (K8s) |

---

## Source

- [Google SRE — SLI/SLO/SLA](https://sre.google/sre-book/table-of-contents/)
- [Alex Xu — System Design Vol. 1](https://www.bytebytego.com/)

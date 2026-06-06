---
title: Reliability
tags: [reliability, resilience, availability, sre]
date: 2025-05-24
description: Patterns for building fault-tolerant, highly available distributed systems
---

# Reliability

Reliability = the ability of a system to keep working correctly over time, even when components fail. The foundation of SRE.

---

## What's Here

- [[availability]] — SLA, SLO, error budgets, availability tiers
- [[resilience]] — Circuit breakers, retries with backoff, bulkheads, graceful degradation
- [[load-balancing]] — LB algorithms, health checks, L4 vs L7
- [[idempotency]] — Designing APIs that are safe to retry
- [[memory-leaks]] — Detection, prevention, and impact on reliability

---

## Quick Reference

```
Failure Mode Analysis:
  Every component WILL fail.
  Question: what is the blast radius?

Reliability Patterns (in order of impact):
  1. Redundancy — N+1 instances, multi-AZ
  2. Health checks — detect failures fast
  3. Circuit breakers — stop cascading failures
  4. Graceful degradation — serve what you can
  5. Idempotency — make retries safe
6. Observability — you can't fix what you can't see
```

---

## Key Metrics

| Metric | Meaning |
|--------|---------|
| Error Budget | Allowable downtime per period (SLO target vs actual) |
| MTTR | Mean Time To Recovery — how fast you recover |
| MTTF | Mean Time To Failure — how long until first failure |
| Availability | Uptime / (Uptime + Downtime) as a percentage |

---

## Related

- [[../performance/caching]] — Caching impacts reliability (cache failures cascade)
- [[../security/shift-left]] — Security testing improves reliability
- [[../foundations/non-functional-requirements/scaling]] — Scaling for reliability

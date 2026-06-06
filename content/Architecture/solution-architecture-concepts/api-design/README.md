---
title: API Design
tags: [api-design, system-design, architecture]
date: 2025-05-24
description: API design principles, distributed systems theory, and architectural constraints
---

# API Design

API design is where solution architecture meets implementation. This section covers the **constraints and trade-offs** that define distributed system behavior.

---

## What's Here

### Distributed Systems Theory
- [[cap-theorem]] — Consistency vs Availability vs Partition tolerance
- [[concurrency]] — Concurrency models, locks, actors, async patterns
- [[stateful-vs-stateless]] — How state affects scalability and reliability

### API Design Patterns
- [[12-factor-app]] — Heroku's methodology for cloud-native SaaS
- [[cheatsheets]] — Quick reference: latency numbers, CAP, HTTP status codes, caching patterns
- [[idempotency]] — Designing for safe retries (covered in [[../reliability/idempotency]])

---

## Key Trade-offs

```
CAP Theorem:
 CP systems: block on partition (Zookeeper, etcd)
  AP systems: serve stale on partition (Cassandra, DynamoDB)

PACELC:
  When there's no partition: do you prefer low latency or strong consistency?
```

---

## Quick Reference

| Topic | Key Question |
|-------|--------------|
| [[cap-theorem]] | Can I have both consistency and availability during a network partition? |
| [[concurrency]] | What concurrency model fits my team's skills and language? |
| [[stateful-vs-stateless]] | Should my service hold state or delegate to a backing store? |
| [[12-factor-app]] | Does my app follow cloud-native principles? |

---

## Related

- [[../foundations/thinking-like-an-architect]] — The mental model for making these trade-offs
- [[../reliability/resilience]] — Implementing reliable APIs in practice
- [[../protocols/README]] — Network protocols underlying API communication

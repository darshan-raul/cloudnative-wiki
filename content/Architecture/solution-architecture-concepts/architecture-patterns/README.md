---
title: Architecture Patterns
tags: [architecture, patterns, design-patterns]
date: 2025-05-24
description: Reusable architectural patterns for building distributed systems
---

# Architecture Patterns

Proven structural solutions to recurring architectural problems. Patterns are not implementations — they're **descriptions of proven approaches** with trade-off analysis.

---

## What's Here

---

## Common Patterns Quick Reference

| Pattern             | What It Solves                                      | Example                                    |
| ------------------- | --------------------------------------------------- | ------------------------------------------ |
| **Strangler Fig**   | Incremental migration from legacy                   | Route traffic to new system piece by piece |
| **Sidecar**         | Attach utilities to services without modifying them | Logging sidecar, metrics exporter          |
| **Circuit Breaker** | Prevent cascading failures                          | Hystrix, Envoy circuit breaker             |
| **CQRS**            | Separate read and write models                      | Event-sourced systems                      |
| **Event Sourcing**  | Store state changes as events                       | Audit trails, temporal queries             |
| **Saga**            | Distributed transactions without2PC                 | Choreography vs orchestration              |
| **Bulkhead**        | Isolate failures                                    | Separate thread pools per dependency       |
| **Leader Election** | Single-writer coordination                          | etcd, Zookeeper                            |
| **Write-Ahead Log** | Durability before acknowledgment                    | Kafka, PostgreSQL WAL                      |

---

## When to Use Patterns

Patterns are **starting points**, not finished designs. Every pattern introduces trade-offs:

```
Strangler Fig:
  ✅ Incremental migration, low risk
  ✅ Old and new systems coexist
  ❌ Dual-running complexity
  ❌ Temporary twice the infrastructure cost
```

---

## Related

- [[../foundations/thinking-like-an-architect]] — How to evaluate pattern trade-offs
- [[../reliability/resilience]] — Implementation of resilience patterns
- [[Architecture/solution-architecture-concepts/system-design/README|System Design Primer]] — System design interview patterns

## Further reading

- [Architecture Patterns (video)](https://www.youtube.com/watch?v=nH4qjmP2KEE)

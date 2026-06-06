---
title: Architecture Basics
tags: [architecture, fundamentals, system-design]
date: 2025-05-24
description: Foundational concepts for understanding system architecture
---

# Architecture Basics

Fundamental concepts every solution architect needs to internalize.

---

## Core Principles

### 1. Design for the Expected Load

Know your numbers before you design:

```
Users: 10,000 DAU → 1,000 concurrent
Peak concurrent:     5x baseline → 5,000 concurrent
Requests/sec peak:   ~50-100/sec at typical usage
Data volume:         Start small, design for10x year 1
```

### 2. Everything Fails

```
Components that WILL fail:
  - Hard disks (MTBF: ~50,000 hours = ~5 years)
  - Network links (human error, cable cut, BGP misconfig)
  - Cloud availability zones (AZs fail independently)
  - Dependencies (they will be slow or unavailable)
  - Your code (bugs exist)

Design accordingly:
  - No single points of failure
  - Graceful degradation
  - Automatic recovery
```

### 3. The Fallacies of Distributed Computing

These assumptions will bite you:

```
1. The network is reliable
2. Latency is zero
3. Bandwidth is infinite
4. The network is secure
5. Topology doesn't change
6. There is one administrator
7. Transport cost is zero
8. The network is homogeneous
```

---

## Scalability Patterns

### Vertical vs Horizontal

```
Vertical (scale up): Horizontal (scale out):
┌────────────────┐           ┌────┐  ┌────┐  ┌────┐
│ Bigger machine │ │app │  │app │  │app │
│ CPU/RAM/disk   │           └────┘  └────┘  └────┘
└────────────────┘           Load Balancer
         ↑ limits exist ↑ add more machines
```

**Horizontal is preferred** for production systems — no single big machine to fail.

### Read vs Write Scaling

| Pattern | When to Use | How |
|---------|------------|-----|
| Read replicas | Read-heavy (80/20 read/write) | 1 primary + N replicas |
| Write sharding | Write-heavy | Partition by key |
| CQRS | Complex read/write profiles | Separate models for read and write |
| Event sourcing | Audit trail, temporal queries | Append-only event log |

---

## Consistency Patterns

### ACID vs BASE

| Property | ACID (Traditional DB) | BASE (NoSQL) |
|----------|---------------------|--------------|
| Atomicity | All or nothing | All or nothing |
| Consistency | Invariant enforcement | Eventually consistent |
| Isolation | Serialized transactions | Concurrent, no isolation |
| Durability | Committed = durable | Committed = eventually durable |

**Rule:** Most systems need ACID for financial transactions. BASE is fine for social feeds, activity logs, etc.

### CAP Theorem (Quick Refresher)

```
         ┌─────────────┐
         │   CAP │
         └──────┬──────┘
   Consistency ◄───┴──► Availability
                (pick1 in partition)

CP: blocks on network partition (Zookeeper, etcd)
AP: returns stale data on partition (Cassandra, DynamoDB)
```

---

## The Building Blocks

```
┌─────────────────────────────────────────────────────────┐
│ Clients │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│                    Load Balancer                        │
│             (health check, round robin) │
└─────────────────┬─────────────────────┬───────────────┘
                  │                     │
 ┌────────▼────────┐   ┌────────▼────────┐
         │  App Server 1   │   │  App Server 2   │
         └────────┬────────┘   └────────┬────────┘
                  │                     │
    ┌─────────────┼─────────────────────┘
    │             │
┌───▼───┐   ┌─────▼─────┐
│ Cache │ │ Database │
│(Redis)│   │(primary + │
└───────┘   │ replicas) │
 └───────────┘
```

---

## Common Architectural Patterns

| Pattern | What It Solves | Examples |
|---------|---------------|----------|
| **Layered** | Code organization | Traditional monoliths |
| **Event-driven** | Decoupling, async processing | Kafka, SNS |
| **Microservices** | Team autonomy, independent deploy | Kubernetes services |
| **CQRS** | Read/write separation | Event-sourced systems |
| **Hexagonal** | Testability, replaceable components | Ports and adapters |
| **Strangler Fig** | Incremental migration | Legacy → new system |

---

## Source

- [ByteByteGo — System Design for Beginners](https://medium.com/@shivambhadani_/system-design-for-beginners-everything-you-need-in-one-article-c74eb702540b)
- [Peter Deutsch — Fallacies of Distributed Computing](https://en.wikipedia.org/wiki/Fallacies_of_distributed_computing)

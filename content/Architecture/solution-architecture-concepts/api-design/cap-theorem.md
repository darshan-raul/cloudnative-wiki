---
title: CAP Theorem
tags: [architecture, distributed-systems, databases]
date: 2025-05-24
description: Consistency, Availability, Partition tolerance — pick one
---

# CAP Theorem

In a distributed system, you can only guarantee **two of three** properties simultaneously.

```
         ┌─────────────┐
         │   CAP │
         └──────┬──────┘
 Consistency ◄───┴──► Availability
                (pick1)

   You MUST choose between C and A when a network partition occurs.
```

**Key constraint:** Network partitions WILL happen in any real distributed system. You can't avoid them. So in practice, you're choosing between:
- **CP** — consistent but unavailable during partition
- **AP** — available but returns stale data during partition

---

## The Three Properties

### Consistency
Every read receives the **most recent write** or an error.

```
Write: x =5 ────────────────────────────────▶ Node A (x=5)
        │                                       │
        │ replicate │
        ▼ ▼
      Node B (x=5)                           Node C (x=5)

Read from any node → always returns x=5
```

### Availability
Every request receives a **response** — but it might not be the most recent data.

```
Node A is partitioned from B and C
        │
        │ A can't replicate to B/C
        ▼
  A continues serving reads (potentially stale)
  B/C continue serving reads (potentially stale)
  System never returns an error
```

### Partition Tolerance
The system continues operating when **network partitions** occur.

```
  Node A          Node B
  ┌────┐    X ┌────┐
  │    │  ────  │ │  ← network partition
  └────┘        └────┘
  A can't talk to B
 What does the system do?
```

---

## CAP in Practice

| System | Type | How It Behaves |
|--------|------|---------------|
| **Zookeeper** | CP | Quorum required for writes — unavailable if can't reach majority |
| **etcd** | CP | Same as Zookeeper |
| **MongoDB** (standalone) | CP | Primary must be reachable for writes |
| **Cassandra** | AP | Any node can serve reads/writes — eventual consistency |
| **DynamoDB** | AP | Tunable consistency (strong/eventual) |
| **CouchDB** | AP | Eventual consistency |
| **PostgreSQL** (primary) | CP | Writes must reach primary + replica |
| **RabbitMQ** | CP | Mirror queue requires quorum |

---

## PACELC

CAP doesn't cover **latency**. PACELC extends it:

```
If there is a partition (P):
 → Choose between Consistency (C) and Availability (A)
Else (no partition, E):
  → Choose between Consistency (C) and Latency (L)
```

| System | PACELC |
|--------|--------|
| Cassandra | PA/EL — Available under partition, low latency |
| DynamoDB (strong consistency) | PC/EC — Consistent, higher latency |
| CosmosDB | PA/EC — Configurable per operation |
| HBase | PC/EC |
| Kafka | PC/EC — Durability over low latency |

---

## Choosing CP vs AP

### Choose CP When:
- **Financial transactions** — correctness > availability (double-entry bookkeeping)
- **Inventory systems** — overselling is catastrophic
- **Distributed locks** — stale locks cause data corruption

### Choose AP When:
- **Social feeds** — stale data is fine, downtime is not
- **Analytics dashboards** — approximate data is acceptable
- **CDN edge caches** — serving stale content better than no content
- **Event logging** — eventual consistency is fine

---

## Common Misconceptions

| Misconception | Reality |
|--------------|---------|
| "We can have all three" | Only in systems with no network partitions (not a distributed system) |
| "CAP means2 of 3 always" | You always have partitions in distributed systems. The choice is C vs A. |
| "CA systems exist" | A CA system = no partitions = not distributed. Not a real-world claim. |
| "Eventual consistency = AP" | Not always. Some CP systems use eventual consistency for reads. |

---

## Quick Reference

```
The CAP Choice:

 Network Partition happens
 │
         ▼
┌────────┴────────┐
│                 │
▼ ▼
CP AP
(stall)         (serve stale)
 │
 ▼
"Block until I can guarantee consistency"
    vs
"Keep serving, warn the client data may be stale"
```

---

## Source

- [Eric Brewer — CAP Theorem (original)](https://people.eecs.berkeley.edu/~brewer/cs262b-2004.pdf)
- [DBMS Musings — CAP and PACELC](https://www.dbms2.com/2010/04/23/cap-and-pacelc/)

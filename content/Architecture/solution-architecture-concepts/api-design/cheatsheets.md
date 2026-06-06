---
title: System Design Cheatsheets
tags: [system-design, cheatsheet, reference]
date: 2025-05-24
description: Quick-reference cheatsheets for system design concepts
---

# System Design Cheatsheets

Quick-reference sheets for architecture and system design work. Bookmark this page.

---

## CAP Theorem

```
         ┌───────────────┐
         │  CAP Theorem  │
         └───────┬───────┘
     Consistency ◄──────► Availability
              (pick1)
```

| System Type | Guarantees |
|-------------|-----------|
| CA (theoretical) | Consistent + Available — cannot exist in distributed systems |
| CP | Consistent + Partition-tolerant — blocks on partition |
| AP | Available + Partition-tolerant — returns stale data |

**Practical rule:** Network partitions WILL happen. Choose CP or AP per use case:
- **CP:** Zookeeper, etcd, HBase, MongoDB
- **AP:** Cassandra, DynamoDB, CouchDB

---

## Latency Numbers (Must-Know)

| Operation | Latency |
|-----------|---------|
| L1 cache reference | 0.5 ns |
| L2 cache reference | 7 ns |
| Memory access | 100 ns |
| Read1 MB from memory | 250 µs |
| Read 1 MB from SSD | 1 ms |
| Round trip within same DC | 0.5 ms |
| Read 1 MB from disk | 20 ms |
| Send packet: SF → NYC | 40 ms |

**Rule:** Latency is6 orders of magnitude from L1 cache to cross-DC round trip. Design accordingly.

---

## HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | OK |
| 201 | Created |
| 204 | No Content |
| 301 | Moved Permanently |
| 302 | Found (redirect) |
| 400 | Bad Request |
| 401 | Unauthorized |
| 403 | Forbidden |
| 404 | Not Found |
| 409 | Conflict |
| 429 | Too Many Requests |
| 500 | Internal Server Error |
| 502 | Bad Gateway |
| 503 | Service Unavailable |
| 504 | Gateway Timeout |

---

## SQL vs NoSQL

| Dimension | SQL (RDBMS) | NoSQL |
|-----------|-------------|-------|
| Data model | Relational | Key-value, Document, Column, Graph |
| Schema | Fixed (DML migration) | Schema-less (flexible) |
| Transactions | ACID | Eventually consistent |
| Scaling | Vertical | Horizontal |
| Joins | Yes | No (denormalize) |
| Examples | PostgreSQL, MySQL | DynamoDB, MongoDB, Cassandra |

---

## Load Balancing Algorithms

| Algorithm | How | Best For |
|-----------|-----|----------|
| Round Robin | Cycle through list | Homogeneous backends |
| Weighted RR | Assign weights | Different capacity nodes |
| Least Connections | Fewest active connections | Variable request duration |
| IP Hash | Hash client IP → backend | Session affinity (legacy) |
| Random | Random selection | Simple, stateless |

---

## Caching Patterns

| Pattern | Description | Use When |
|---------|-------------|----------|
| Cache-Aside | App manages read/write | Read-heavy, single app |
| Write-Through | Write to cache + DB simultaneously | Read-heavy, need consistency |
| Write-Behind | Write to cache, async DB flush | Write-heavy, can tolerate loss |
| Refresh-Ahead | Proactively refresh expiring entries | Predictable hot data |

---

## Data Replication Models

| Model | Writes | Reads | Consistency |
|-------|--------|-------|-------------|
| Single-leader | → primary | ← any replica | Eventual (async) |
| Multi-leader | → any primary | ← any primary | Eventual |
| Leaderless | → quorum (W+R>N) | ← quorum | Tunable (strong/eventual) |

---

## Message Queue Patterns

| Pattern | Description | Example |
|---------|-------------|---------|
| Point-to-Point | One consumer per message | SQS, RabbitMQ queue |
| Pub/Sub | Fan-out to multiple consumers | SNS, Kafka (consumer groups) |
| Dead Letter Queue | Failed messages for retry/review | SQS DLQ, RabbitMQ x-delayed-message |

---

## Security Checklist

```
□ TLS everywhere (in-transit encryption)
□ mTLS for service-to-service
□ Secrets in vault (not env vars in code)
□ RBAC (least privilege)
□ Input validation + sanitization
□ Rate limiting (DoS protection)
□ Audit logging (who did what, when)
□ Encryption at rest (AES-256)
```

---

## Source

- [ByteByteGo System Design 101](https://github.com/ByteByteGoHq/system-design-101)
- [Jeff Dean's latency numbers](https://people.eecs.berkeley.edu/~rcs/research-interactive.html)

---
title: Data Architecture
tags: [data, databases, architecture]
date: 2025-05-24
description: Data modeling, database selection, and data flow architecture
---

# Data Architecture

Data architecture covers **how data is stored, accessed, and flows** through a system. Database choice is one of the highest-impact architectural decisions.

---

## What's Here

### Data Formats
- [[bson]] — Binary JSON, MongoDB's data format
- [[base64-encoding]] — Encoding binary data as ASCII text
- [[hashing]] — Hash functions for integrity, lookup, and cryptography
- [[cdn]] — Content delivery networks and caching strategies

### Databases
- [[databases/README]] — Database selection guide
- [[databases/postgres/README]] — PostgreSQL deep dive
- [[databases/mongodb/README]] — MongoDB deep dive
- [[databases/normalization]] — Normal forms and when to denormalize
- [[databases/indexing]] — Index design for query performance
- [[databases/database-schema-design]] — Schema design principles
- [[databases/foreign-keys-and-constraints]] — Referential integrity
- [[databases/opm-or-not-to-orm]] — ORM trade-offs

---

## Database Selection

| Use Case | Database Type | Examples |
|----------|-------------|----------|
| Financial transactions | Relational (ACID) | PostgreSQL, MySQL |
| Flexible schema | Document | MongoDB, CouchDB |
| High-volume time series | Time-series | InfluxDB, TimescaleDB |
| Key-value cache | In-memory | Redis, Memcached |
| Graph relationships | Graph | Neo4j |
| Search | Search engine | Elasticsearch, OpenSearch |
| Wide-column | Column-family | Cassandra, DynamoDB |

---

## Quick Links

| Topic | Key Question |
|-------|--------------|
| [[databases/normalization]] | Should I normalize or denormalize my schema? |
| [[databases/indexing]] | How do I design indexes for performance? |
| [[databases/opm-or-not-to-orm]] | Should I use an ORM or raw SQL? |
| [[cdn]] | When should I use a CDN? |
| [[hashing]] | What hashing algorithm for what purpose? |

---

## Related

- [[../performance/caching]] — Caching layer in front of databases
- [[../reliability/availability]] — Database availability patterns
- [[../event-driven-architecture/README]] — Async data pipelines

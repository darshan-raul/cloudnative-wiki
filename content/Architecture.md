---
title: Architecture
tags: [architecture, system-design, software-engineering, protocols]
date: 2025-05-24
description: Software architecture, system design, engineering concepts, protocols, and programming languages
---

# Architecture 🏛️

Software architecture, system design, and engineering concepts.

## Sections

### System Design

- [[Architecture/solution-architecture-concepts/system-design/README|System Design]]
- [[Architecture/solution-architecture-concepts/performance/README|Performance]]

### Software Concepts

- [[Architecture/solution-architecture-concepts/software-engineering-concepts/README|Software Engineering]]
- [[Architecture/programming-concepts/README|Programming Concepts]]

### Protocols

- [[Architecture/solution-architecture-concepts/protocols/README|Protocols]] - HTTP, gRPC, WebSocket

### Languages

- [[Architecture/languages/golang/README|Go]]
- [[Architecture/languages/python/README|Python]]

### Authentication

- [[Architecture/solution-architecture-concepts/authentication/README|Identity & Auth Curriculum]] — 6-stage, 26-module deep dive: OIDC, JWT, OAuth 2.x, SAML 2.0, SSO, federation, security, Keycloak capstone
  - [[Architecture/solution-architecture-concepts/authentication/stage0/README|Stage 0]] — Crypto, encoding, HTTP/TLS primitives
  - [[Architecture/solution-architecture-concepts/authentication/stage1/README|Stage 1]] — JWT deep dive + JOSE family
  - [[Architecture/solution-architecture-concepts/authentication/stage2/README|Stage 2]] — OAuth 2.0 (flows, PKCE, DPoP, 2.1)
  - [[Architecture/solution-architecture-concepts/authentication/stage3/README|Stage 3]] — OpenID Connect
  - [[Architecture/solution-architecture-concepts/authentication/stage4/README|Stage 4]] — Federation, SSO, SAML 2.0, B2B
  - [[Architecture/solution-architecture-concepts/authentication/stage5/README|Stage 5]] — Security, attacks, hardening
  - [[Architecture/solution-architecture-concepts/authentication/stage6/README|Stage 6]] — HA, performance, frontier standards
  - [[Architecture/solution-architecture-concepts/authentication/capstone/README|Capstone]] — Keycloak reference lab + tabletop

### Observability & Telemetry

- [[Observability/opentelemetry/index|OpenTelemetry (OTel)]] — Tracing, Metrics, Logs, Collector, Semantic Conventions, and Context Propagation

### Architecture Foundations

- [[Architecture/solution-architecture-concepts/foundations/solutions-architecture|Solutions Architecture]] - Solution architect role, NFRs, tradeoffs
- [[Architecture/solution-architecture-concepts/foundations/thinking-like-an-architect|Thinking Like an Architect]]
- [[Architecture/solution-architecture-concepts/foundations/software-planning|Software Planning]] - ADRs, RFCs, SLOs
- [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/README|Non-Functional Requirements]]

### Reliability

- [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/availability|Availability]] - SLA, SLO, error budgets
- [[Architecture/solution-architecture-concepts/reliability/resilience|Resilience]] - Circuit breakers, retries, graceful degradation
- [[Architecture/solution-architecture-concepts/reliability/load-balancing|Load Balancing]]
- [[Architecture/solution-architecture-concepts/reliability/idempotency|Idempotency]]

### Performance

- [[Architecture/solution-architecture-concepts/caching|Caching]] - Cache patterns, Redis
- [[Architecture/solution-architecture-concepts/performance/rate-limiting|Rate Limiting]]
- [[Architecture/solution-architecture-concepts/percentile|Percentiles]] - p50, p95, p99
- [[Architecture/solution-architecture-concepts/performance-testing|Performance Testing]]

### Security

- [[Architecture/solution-architecture-concepts/security/security|Security Architecture]] - CIA triad, zero-trust
- [[Architecture/solution-architecture-concepts/security/shift-left|Shift Left]] - DevSecOps
- [[Architecture/solution-architecture-concepts/security/totp|TOTP]]

### API Design

- [[Architecture/solution-architecture-concepts/api-design/cheatsheets|System Design Cheatsheets]]
- [[Architecture/solution-architecture-concepts/api-design/cap-theorem|CAP Theorem]]
- [[Architecture/solution-architecture-concepts/api-design/concurrency|Concurrency]]
- [[Architecture/solution-architecture-concepts/api-design/stateful-vs-stateless|Stateful vs Stateless]]
- [[Architecture/solution-architecture-concepts/api-design/12-factor-app|12-Factor App]]

### Data Architecture

- [[Architecture/solution-architecture-concepts/data-architecture/databases/README|Databases]] - Choosing a database, families and trade-offs
- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/README|PostgreSQL]] - MVCC, vacuum, indexes, connection pooling
- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/replication-and-ha|PostgreSQL replication and HA]] - Failover, backups, point-in-time recovery
- [[Architecture/solution-architecture-concepts/data-architecture/databases/redis|Redis]] - Data structures, persistence, caching patterns
- [[Architecture/solution-architecture-concepts/event-driven-architecture/README|Event-driven architecture]] - Events, outbox, sagas, idempotency
- [[Architecture/solution-architecture-concepts/event-driven-architecture/kafka/README|Apache Kafka]] - Partitions, replication, consumer groups, delivery semantics
- [[Architecture/solution-architecture-concepts/data-architecture/hashing|Hashing]]
- [[Architecture/solution-architecture-concepts/data-architecture/cdn|CDN]]

### Architecture Patterns

- [[Architecture/solution-architecture-concepts/architecture-patterns/README|Architecture Patterns]]

### Migration Patterns

- [[Architecture/solution-architecture-concepts/migration-patterns/README|Migration Patterns]] - Blue-green, expand-contract, strangler fig, data migration

### Cryptography

- [[Architecture/solution-architecture-concepts/cryptography/README|Cryptography]] - PKI, TLS, signing

### Developer Tooling

- [[Architecture/languages/README|Languages]] — Language-specific notes. The emphasis is on the parts of each language that matter for building and operating backend services.
- [[Architecture/solution-architecture-concepts/data-architecture/README|Data Architecture]] — Data modeling, database selection, and data flow architecture
- [[Architecture/solution-architecture-concepts/reliability/README|Reliability]] — Patterns for building fault-tolerant, highly available distributed systems
- [[Architecture/solution-architecture-concepts/security/README|Security]] — Security architecture patterns, zero-trust, and secure-by-design principles

## More in this section

- [[Architecture/solution-architecture-concepts/basics|Architecture Basics]] — Foundational concepts for understanding system architecture

## Related

- [[Kubernetes/concepts/L04-services-networking/00-README|Kubernetes Networking & Protocols]]
- [[Architecture/solution-architecture-concepts/data-architecture/databases/README|Data Architecture & Databases]]
- [[Kubernetes]] - Cloud-native architecture

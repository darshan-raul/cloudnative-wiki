---
title: Architecture Foundations
tags: [architecture, foundations, solution-architecture]
date: 2025-05-24
description: Core mindset, principles, and practices for solution architects
---

# Architecture Foundations

This section covers the **mental models, processes, and frameworks** that define how a solution architect thinks and works.

---

## What's Here

### Solution Architecture
- [[solutions-architecture]] — What a solution architect does, NFRs, trade-off analysis
- [[thinking-like-an-architect]] — Mental models, the scale of the role, red flags
- [[software-planning]] — ADRs, RFCs, SLOs, architecture reviews

### Non-Functional Requirements
- [[non-functional-requirements/README]] — NFR taxonomy and how to define them
- [[non-functional-requirements/performance|Performance]] — Latency, throughput, caching, database optimization
- [[non-functional-requirements/availability|Availability]] — The nines, redundancy, health checks, SLOs vs SLAs
- [[non-functional-requirements/scalability|Scalability]] — Vertical vs horizontal, stateless design, sharding, auto-scaling
- [[non-functional-requirements/reliability|Reliability]] — Failure modes, circuit breakers, MTTR, bulkheads
- [[non-functional-requirements/security|Security]] — CIA triad, defense in depth, threat modeling, encryption
- [[non-functional-requirements/maintainability|Maintainability]] — Modifiability, technical debt, CI/CD quality gates
- [[non-functional-requirements/disaster-recovery|Disaster Recovery]] — RPO/RTO, backup/restore, failover strategies
- [[non-functional-requirements/capacity-planning|Capacity Planning]] — Resource forecasting, cost modeling, right-sizing
- [[non-functional-requirements/back-of-the-envelope-calculations]] — Quick capacity estimates
- [[non-functional-requirements/reliability-vs-availability]] — The distinction that matters

### Migration Patterns
- [[migration-patterns/README]] — Strategies for safe system and data migration
- [[migration-patterns/blue-green-deployments|Blue-Green Deployments]] — Zero-downtime deployment with instant rollback
- [[migration-patterns/expand-contract|Expand-Contract]] — Safe API and schema evolution without breaking consumers
- [[migration-patterns/strangler-fig|Strangler Fig]] — Incremental legacy system replacement
- [[migration-patterns/data-migration|Data Migration]] — Bulk data movement with zero downtime

### Design Principles
- [[high-cohesion-loose-coupling]] — Object-oriented design principles applied to system architecture

---

## Start Here

If you're new to solution architecture:

1. [[thinking-like-an-architect]] — understand the mindset shift from engineer to architect
2. [[solutions-architecture]] — understand the role and its responsibilities
3. [[non-functional-requirements/README]] — learn to define what "good enough" means

Then pick your topic based on the problem you're solving.

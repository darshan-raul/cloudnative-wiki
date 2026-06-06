---
title: Migration Patterns
---

# Migration Patterns

Migration patterns are strategies for safely transitioning systems, data, and infrastructure without service interruption. Every migration carries risk — these patterns reduce that risk by breaking large, dangerous changes into small, reversible steps.

## When to Use Each Pattern

| Pattern | Use When |
|---|---|
| [[blue-green-deployments|Blue-Green Deployments]] | Deploying a new version of a system with instant rollback capability |
| [[expand-contract|Expand-Contract]] | Evolving a shared API or database schema without breaking consumers |
| [[strangler-fig|Strangler Fig]] | Replacing a legacy monolith incrementally without big-bang rewrite |
| [[data-migration|Data Migration]] | Moving or transforming large datasets between systems |
| [[change-data-capture|Change Data Capture]] | Streaming database changes to downstream systems in real-time |

## The Core Principle

**Never do in one step what you can do in two.**

The biggest migration failures come from trying to change too much at once. Every pattern here breaks a scary change into phases:
1. Add new thing (expand) — old and new work simultaneously
2. Migrate — data, consumers, traffic gradually move to new thing
3. Remove old thing (contract) — cleanup after migration is confirmed

## Migration Readiness Checklist

Before any migration:

- [ ] **Backup exists** — point-in-time backup of current state
- [ ] **Rollback plan documented** — step-by-step procedure to go back
- [ ] **Monitoring in place** — dashboards for error rates, latency, traffic
- [ ] **Communication sent** — stakeholders aware of migration window
- [ ] **Stakeholders identified** — who needs to sign off on cutover
- [ ] **Tested on subset** — validated on 1% of traffic/data before full migration
- [ ] **Cutover window defined** — start time, expected duration, go/no-go criteria

## Common Migration Risks

| Risk | Mitigation |
|---|---|
| Data loss | Checksum reconciliation, UPSERT (not INSERT) |
| Downtime | Zero-downtime patterns (blue-green, dual-write) |
| Data corruption | Schema validation, sampling checks |
| Rollback complexity | Idempotent operations, keep old system running |
| Consumer breakage | Expand-contract, deprecation timelines |
| Performance regression | Load test with production-scale data |

## Related Sections

- [[foundations/non-functional-requirements/README|Non-Functional Requirements]] — NFRs that apply to migrations (availability, RPO/RTO)
- [[reliability|Reliability]] — fault tolerance during migration
- [[databases/README|Databases]] — database-specific migration patterns

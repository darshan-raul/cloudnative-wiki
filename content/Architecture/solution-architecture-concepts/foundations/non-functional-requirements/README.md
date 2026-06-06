---
title: Non-Functional Requirements
---

# Non-Functional Requirements

Non-functional requirements (NFRs) define the quality attributes of a system — the characteristics that determine how well the system works, not what it does. While functional requirements answer "what does the system do," NFRs answer "how well does it do it."

NFRs are constraints that apply across all features. They're defined early, measured objectively, and are typically contractually committed (SLA) or architecturally enforced.

## The NFR Stack

Each NFR is a dimension. Trade-offs between them are where architecture lives:

```
Performance ←→ Cost
Availability ←→ Complexity
Security ←→ Usability
Scalability ←→ Maintainability
```

Improving one often costs another. A solution architect's job is finding the right balance for the business context.

## NFR Deep-Dives

Each NFR is covered in depth in its own file:

| NFR | File | What it covers |
|---|---|---|
| [[performance|Performance]] | Latency, throughput, resource efficiency, caching, database performance patterns |
| [[availability|Availability]] | The nines, redundancy, health checks, circuit breakers, SLOs vs SLAs |
| [[scalability|Scalability]] | Vertical vs horizontal, stateless architecture, sharding, auto-scaling |
| [[reliability|Reliability]] | Failure modes, fault tolerance patterns, MTTR, MTBF, observability |
| [[security|Security]] | CIA triad, defense in depth, threat modeling, encryption, compliance |
| [[maintainability|Maintainability]] | Modifiability, testability, operability, technical debt, CI/CD quality gates |
| [[disaster-recovery|Disaster Recovery]] | RPO/RTO, backup/restore, pilot light, warm standby, active-active, failover testing |
| [[capacity-planning|Capacity Planning]] | Resource dimensions, forecasting, cost modeling, right-sizing, monitoring |

## Cross-NFR Concerns

### Performance + Scalability
High performance at low scale doesn't guarantee performance at high scale. Test at production-scale load.

### Availability + Disaster Recovery
Availability targets regional failures. DR targets catastrophic failures. They require different architectural responses.

### Security + Usability
Every security control adds friction. The art is adding the minimum friction for the maximum protection.

### Maintainability + Reliability
A system you can't modify reliably is a system that degrades over time. Technical debt is a reliability risk.

## NFR Requirements Process

```
1. Define NFRs early (before architecture is finalized)
   → Talk to stakeholders, legal, security, finance

2. Make them measurable
   → "Fast" = p99 < 200ms
   → "Secure" = no CVEs > 7.0 in dependencies
   → "Available" = 99.95% uptime

3. Validate against cost
   → Each NFR has a cost to achieve
   → Budget constraint may require prioritizing

4. Enforce in architecture
   → NFRs drive structural decisions, not just testing

5. Monitor in production
   → NFRs unmeasured in prod are NFRs not achieved
```

## Key Metrics Quick Reference

| NFR | Common Metric | Target Range |
|---|---|---|
| Performance | p99 latency |< 200ms for APIs, < 2s for web |
| Availability | Uptime % | 99.9% (consumer), 99.99% (enterprise) |
| Scalability | Concurrent users | Design for 10x current |
| Reliability | MTTR |< 1 hour for critical,< 4 hours for standard |
| Security | Vulnerability age | Critical CVEs patched< 24h |
| Disaster Recovery | RTO | < 4 hours (business), < 15 min (mission-critical) |
| Capacity | Resource utilization | 60-70% sustained |

## Related

- [[back-of-the-envelope-calculations|Back-of-the-Envelope Calculations]] — quick NFR estimates
- [[performance-testing|Performance Testing]] — validating performance targets
- [[foundations/README|Foundations]] — foundational solution architecture concepts

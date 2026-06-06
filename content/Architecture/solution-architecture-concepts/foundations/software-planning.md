---
title: Software Planning
tags: [planning, adr, rfcs, architecture]
date: 2025-05-24
description: Planning artifacts and processes for solution architecture
---

# Software Planning

Architecture decisions live and die by documentation. Without a paper trail, the team forgets *why* something was built a certain way — and repeats the same mistakes.

---

## Core Artifacts

### 1. Architecture Decision Records (ADRs)

A short document capturing a **significant architectural decision**: the context, the decision, and its consequences.

```markdown
# ADR-042: Use Kafka for async inter-service events

## Status: Accepted
## Date: 2025-05-24
## Deciders: jane@corp.com, bob@corp.com

## Context
Orders service needs to notify fulfillment, billing, and analytics
without coupling. Sync HTTP calls create circular dependency risk.

## Decision
Apache Kafka with consumer groups per downstream service.
Topic: `orders.events`

## Consequences
+ Decoupled: producers don't know consumers
+ Replay: new services can consume from beginning
+ High throughput: handles 50k events/sec
- Operational complexity: need Kafka cluster / MSK
- Learning curve: offset management, consumer groups
- Latency: async, not real-time
```

**Store ADRs in version control** (`docs/adr/`) — keeps them in sync with code.

### 2. RFCs (Request for Comments)

For **controversial or high-impact decisions** — propose, gather feedback, then decide.

```
RFC-001: Switch from REST to gRPC for internal services
├── Author: jane@corp.com
├── Created: 2025-05-20
├── Status: Review
├── Review Deadline: 2025-05-27
└── Reactions: +8 👍 -2 👎  5 💬
```

### 3. RFC Process

```
1. Author writes RFC (problem, proposed solution, alternatives)
2. Share with stakeholders (async or meeting)
3. Collect feedback (5 business days)
4. Author revises or withdraws
5. Decider approves / rejects / defers
6. ADR created from final decision
```

###4. SLO Documents

Define **Service Level Objectives** during design — before launch.

```yaml
# slo.yaml
api-gateway:
  availability:
    target: 99.95%
    window: 30d
    alert_threshold: 99.9%
  latency:
    target: p99 < 500ms
    window: 30d
    alert_threshold: p99 > 800ms
  error_rate:
    target: < 0.1%
    window: 30d
    alert_threshold: > 0.5%
```

---

## Planning Meeting Formats

### 1. Architecture Review (1-2h, infrequent)

```
Agenda:
1. Present proposed architecture (author, 20min)
2. Clarifying questions (all, 15min)
3. Alternatives discussion (all, 30min)
4. Risks and concerns (all, 20min)
5. Decision (decider, 15min)
6. Action items (all, 10min)
```

### 2. Design Studio (2-4h, when starting something new)

Collaborative whiteboarding session for greenfield problems.

```
Format:
1. Problem framing (15min)
2. Individual sketching (30min)
3. Gallery walk (15min)
4. Group discussion (60min)
5. Vote on top 2-3 approaches (10min)
6. Consolidate into next steps (15min)
```

### 3. Retrospective (1h, per sprint/iteration)

```
Format (4Ls):
- Liked: what worked well
- Learned: new insights
- Lacked: what was missing
- Longed for: what we wish we had
```

---

## Roadmap Planning

### Now / Next / Later Framework

| Horizon | Timeframe | Output |
|---------|-----------|--------|
| **Now** | This quarter | Sprint backlog |
| **Next** | Next quarter | Roadmap (themes, not features) |
| **Later** | 6-12 months | Strategic initiatives |

### OKRs for Architecture

```yaml
# Example
Objective: Improve platform reliability
Key Results:
  - KR1: Reduce P50 incident detection time from 15min to 2min
  - KR2: Achieve 99.95% API availability (from 99.7%)
  - KR3: 80% of services instrumented with SLO dashboards
```

---

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| No ADRs | Same debates every year | Mandate ADR for any cross-team decision |
| ADRs written after the fact | They become rationalization, not documentation | Write ADR before decision is final |
| Giant spec documents | Nobody reads them | Keep ADRs under 1 page |
| Planning without constraints | Architects design fantasies | Start with budget, timeline, team size |
| No rollback plan | Changes are one-way | Always document rollback procedure |

---

## Tools

| Artifact | Tool |
|----------|------|
| ADRs | Markdown in `docs/adr/`, or use [adr-tools](https://github.com/npryce/adr-tools) |
| RFCs | GitHub PRs, Notion, or HackMD |
| SLOs | Prometheus, Datadog, or Grafana |
| Roadmap | Linear, Notion, or Aha! |
| Diagrams | Excalidraw, draw.io, Mermaid |

---

## Source

- [Michael Nygard — Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
- [Staff Engineer — Writing ADRs](https://staffeng.com/guides/technical-decisions)

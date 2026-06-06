---
title: Thinking Like an Architect
tags: [architecture, mindset, career]
date: 2025-05-24
description: The mental models and habits that distinguish architects from individual contributors
---

# Thinking Like an Architect

Software engineers solve **known problems** with known tools. Architects solve **ambiguous problems** where the right answer depends on constraints nobody fully understands yet.

---

## Core Mental Models

### 1. Trade-offs, Not Best Practices

Every architectural decision is a **trade-off**. There is no "correct" answer independent of context.

```
"We will use microservices"
 ↓
"But you need:"
    ✓ Distributed tracing
    ✓ Service mesh
    ✓ Independent deploy pipelines
    ✓ Team autonomy
    ✓ Contract testing
    ✓ Observability per service
    ✓ Database per service (or shared with coordination cost)
```

**The architect's question:** *What are we trading away, and is that acceptable given our constraints?*

### 2. The Whole System, Not Just Your Part

Engineers optimize their component. Architects optimize the **system**.

```
Engineer sees:      Architect sees:
┌─────────┐         ┌────────────────────────────────┐
│ API    │         │  API ──▶ Auth ──▶ DB ──▶ Cache │
│  Layer  │         │    │         │        │        │
└─────────┘         │    ▼ ▼        ▼        │
                    │  Rate RBAC     ACID    TTL │
                    │  Limit eviction│ │
                    └────────────────────────────────┘
```

Ask: *What happens when this component is slow, unavailable, or overloaded?*

### 3. Prefer Reversibility Over Correctness

```
Irreversible decision:     Reversible decision:
┌──────────────┐ ┌──────────────┐
│Monolith │           │ Service A ──▶ Service B │
│              │           │    │ │    │
│──────▶ │           │ ◀──────────────┘    │
│(can't go back without rewrite)│(can extract or merge)
└──────────────┘           └──────────────┘
```

**Rule:** When uncertain, choose the **more reversible** path. Prefer:
- Strangler fig over big bang rewrite
- Feature flags over code branches
- Side-by-side new system over in-place replacement

### 4. Last Responsible Moment

Don't decide early what you can decide late — but don't be late either.

```
Too early:  "We need to pick the database before we know the query patterns"
Just right: "We've profiled the workload, DB choice is now obvious"
Too late:   "We're in prod with 10M rows, migrating is expensive"
```

**The last responsible moment** is when:
1. You have enough information to make a good decision
2. Delaying further would cost more than deciding now

### 5. SLO-Driven Development

Design to a **defined reliability target**, not "as high as possible."

```yaml
# SLO: API gateway availability
target: 99.9% # 43min downtime/month
budget: 8.76h/year

# Error budget policy:
# - Within budget: ship features
# - Budget burning fast: focus on reliability
# - Budget exhausted: feature freeze, focus on stability
```

---

## Habits

### Ask "Compared to What?"

Every architectural choice needs a **baseline**.

```
"We should use event sourcing"
  └── Compared to what? CRUD with audit log?
 What problem does event sourcing solve that our current approach doesn't?
```

### Draw the Failure Mode

For every component, ask: *How does this fail, and what is the blast radius?*

```
┌─────────────┐
│  Load       │
│  Balancer   │
└──────┬──────┘
 │
   ┌───┴───┐
   ▼       ▼
┌────┐ ┌────┐
│ Web│ │ Web│
│ 1 │ │  2 │
└────┘ └────┘
   │       │
   ▼       ▼
┌─────────────┐
│    DB       │  ← single point of failure
└─────────────┘

Failure: DB goes down → both web servers return 500
Fix: Primary-replica with read replica for reads
```

### Write the ADR Before Deciding

The act of writing forces clarity. If you can't write a clear ADR, you don't understand the decision well enough.

### Say "It Depends" Without Apologizing

Architecture is context-dependent. The same answer to the same question changes based on:
- Team size and experience
- Traffic patterns
- Regulatory environment
- Timeline and budget
- Organisational tolerance for risk

---

## The Architect's Scale

```
Senior Engineer Staff Engineer          Architect
─────────────────       ──────────────────       ──────────────────
Optimizes my code   →   Optimizes team →   Optimizes system
Owns my service     →   Owns multiple      →   Owns cross-team
                       services design principles

"What should I          "How do we build         "What should we
 build?"                this efficiently?"        not build?"
```

---

## Red Flags in Architecture Review

| Red Flag | What It Signals |
|----------|-----------------|
| "We'll figure it out later" | No data for a high-impact decision |
| "It's just like X but simpler" | Underestimated complexity |
| "We'll add caching later" | Performance not considered in design |
| "Nobody will need that scale" | No load testing assumptions |
| "The cloud handles it" | Vendor lock-in, cost blindness |
| No rollback plan | Irreversibility risk |
| Single point of failure | Unaddressed reliability risk |

---

## Source

- [ThoughtWorks — Architecture Skills](https://www.thoughtworks.com/insights/articles/what-does-an-architect-actually-do)
- [Staff Engineer — Architecture](https://staffeng.com/guides/architecture)
- [SeanGOedecke — Good System Design](https://www.seangoedecke.com/good-system-design/)

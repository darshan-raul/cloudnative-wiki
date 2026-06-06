---
title: Maintainability
---

# Maintainability

Maintainability is the measure of how easily a system can be modified to fix bugs, add features, or improve performance. A highly maintainable system has low friction between "we decided to change something" and "change is deployed."

## The Three Dimensions

### Modifiability

How easy is it to make changes without breaking existing functionality?

**Architectural practices that improve modifiability:**

- **Loose coupling** — services can change independently. See [[high-cohesion-loose-coupling|High Cohesion, Loose Coupling]].
- **Interface stability** — public APIs don't break clients when internal implementation changes
- **Feature flags** — deploy code without activating it; toggle features without redeploying
- **Plugin architecture** — extend system behavior without modifying core code

### Testability

How easy is it to verify that the system works correctly?

A system is testable when:
- It has clear inputs and outputs (black box)
- Internal state is observable (can inspect intermediate results)
- Dependencies are injectable (can mock/swap external services)
- Side effects are controllable (can reset state between tests)

**Testability anti-patterns:**
- Hard-coded date/time (can't test time-dependent logic)
- Static global state (tests pollute each other)
- Uninjectable dependencies (can't mock the database)
- Side effects without boundaries (sending emails, writing files mid-test)

### Operability

How easy is it to keep the system running correctly in production?

- **Observability** — logs, metrics, traces that make production issues diagnosable
- **Runbooks** — documented procedures for known failure modes
- **Alerting with signal** — alerts that fire on actual problems, not noise
- **Graceful degradation** — partial functionality during partial failures

## Codebase Health Metrics

These are the signals that predict maintainability:

### Cyclomatic Complexity

Measures decision complexity per function. High complexity = hard to test, hard to reason about.

```python
# Low complexity (1) — easy to test
def get_discount(user):
    if user.is_premium:
        return 0.2
    return 0.0

# High complexity (7) — hard to test all paths
def get_discount(user, order, today, promo_code, loyalty_tier, hour):
    if user.is_premium and (hour < 18 or loyalty_tier > 2):
        ...
```

Target: keep function complexity below 10. Above 20 = immediate refactor.

### Coupling Metrics

- **Afferent coupling (ca)** — number of other components that depend on this component (incoming dependencies)
- **Efferent coupling (ce)** — number of other components this component depends on (outgoing dependencies)

High afferent coupling = "this is a critical shared component, changing it breaks many things."

### Code Coverage

Percentage of code executed by tests. Target:80% coverage on business logic.

> **Important:**100% coverage doesn't mean well-tested. Coverage measures execution, not assertion quality. A test that calls every line but checks nothing is worthless.

### Churn

Files that change frequently alongside each other indicate coupling that isn't expressed in the code structure. High churn = hidden coupling.

## Technical Debt

The implied cost of future rework caused by choosing a quick solution now over a better approach that takes longer.

### Tracking Technical Debt

```markdown
// TODO (tech-debt): Replace custom auth with OAuth2 library
// Created: 2024-01-15
// Issue: SECURITY-204
// Priority: High
// Estimated refactor: 3 days
```

Track technical debt explicitly:
- **Issue tracker** — tag debt items, prioritize alongside features
- **SonarQube / CodeClimate** — automated debt detection
- **Architecture Decision Records (ADRs)** — record why a suboptimal choice was made and what would make it right

### Paying Down Debt

Two strategies:
1. **Boy scout rule** — leave code cleaner than you found it (5 min refactor per change)
2. ** dedicated debt sprints** — time-boxed periods to specifically address debt

Neither works without explicit tracking. Untracked debt accumulates invisibly until it becomes the reason you can't ship.

## Maintainability Requirements in Contracts

When defining vendor or procurement requirements:

| Requirement | What to specify |
|---|---|
| **Code quality gates** | Linting passes, complexity thresholds, no hard-coded secrets |
| **Test coverage** | Minimum 80% on new code, 70% on existing |
| **Documentation** | README per service, API docs, runbook per critical path |
| **Dependency management** | No transitive dependencies with known CVEs >7.0 |
| **Change process** | Review required for production changes, rollback plan |
| **On-call coverage** | Engineer availability for production incidents |

## Deployment Pipeline for Maintainability

A well-designed CI/CD pipeline enforces maintainability:

```yaml
# Quality gates in CI
stages:
  - lint:          # Code style, static analysis
  - test:          # Unit tests, coverage gate
  - security:      # SAST, dependency scan, secret scan
  - integration:   # Integration tests
  - staging:       # Smoke tests in staging
  - production:    # Canary deployment, automated rollback
```

Each gate must pass before proceeding. A failing gate blocks deployment.

## Common Maintainability Failures

- **Monolithic shared state** — one team's change breaks another team's feature
- **No feature flags** — every deploy is a feature release, no independent rollout
- **Missing observability** — production issues require guesswork to diagnose
- **Undocumented dependencies** — unclear what services depend on each other
- **Technical debt without tracking** — debt accumulates silently until it blocks progress
- **No rollback capability** — a bad deploy requires manual remediation
- **Tight coupling to external systems** — API changes from vendors require immediate code changes

## Related

- [[high-cohesion-loose-coupling|High Cohesion, Loose Coupling]] — coupling principles
- [[shift-left|Shift Left]] — quality gates earlier in the pipeline
- [[software-planning|Software Planning]] — scoping and prioritization

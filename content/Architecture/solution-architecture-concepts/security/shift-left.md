---
title: Shift Left
tags: [devops, security, quality, ci-cd]
date: 2025-05-24
description: Moving activities earlier in the development lifecycle to reduce cost and risk
---

# Shift Left

**Shift left** = move activities **earlier** in the delivery lifecycle (design → develop → test → staging → prod) so issues are caught cheaper and faster.

```
Traditional:
 Design ──▶ Develop ──▶ Test ──▶ Staging ──▶ Prod
                              ▲
                         Bugs found here (expensive)

Shift Left:
  Design ──▶ Develop ──▶ Test ──▶ Staging ──▶ Prod
           ▲        ▲
 Bugs found here (cheap to fix)
```

**Cost of fixing a bug by phase:**
```
Design ──────────────────────────── 1x
Code ───────────────────────────10x
Test ─────────────────────────── 100x
Staging ─────────────────────────── 1000x
Prod    ─────────────────────────── 10000x
```

---

## What Gets Shifted Left

### Security — DevSecOps

| Without Shift Left | With Shift Left |
|-------------------|-----------------|
| Pen test in staging | SAST/DAST in CI |
| Security review before release | Threat modeling in design phase |
| Manual security audit | Automated CVE scanning |
| Secrets in prod | Vault + secret scanning in PR |

```yaml
# GitHub Actions — SAST in CI
- name: Run Semgrep
  uses: returntocorp/semgrep-action@v1
  with:
    config: >
      p/owasp-top-ten
      p/nodejs
```

### Testing — TDD / E2E Earlier

| Without Shift Left | With Shift Left |
|-------------------|-----------------|
| E2E tests only in staging | Unit + integration in dev |
| Manual QA gate | Automated QA in PR |
| Performance test at release | Load testing in CI |
| Accessibility ignored | a11y checks in CI |

### Observability — Design-Time

| Without Shift Left | With Shift Left |
|-------------------|-----------------|
| Logs added after bugs | Structured logging in design |
| Dashboards built post-launch | SLOs defined in design phase |
| Alerting is reactive | Proactive alerts from SLO definitions |

---

## Implementation Patterns

### 1. Pre-commit Hooks

```bash
#!/bin/bash
# .git/hooks/pre-commit
semgrep --config p/security-experimental .
pytest tests/unit --fail-fast
```

### 2. PR Gates

```
PR opened
 ├── lint + format check
  ├── unit tests (coverage gate)
  ├── security scan (SAST)
  ├── dependency scan (CVE check)
  ├── secret scan (nocreds)
  └── preview environment deploy
       └── e2e tests against preview
            └── approval gate
```

### 3. Architecture Decision Records (ADRs)

ADRs shift **design decisions** left — record the why, not just the what.

```markdown
# ADR-001: Use PostgreSQL instead of MongoDB

## Status: Accepted
## Date: 2025-05-24

## Context
Need a relational store for order items with ACID transactions.

## Decision
PostgreSQL 16 with psycopg3.

## Consequences
- ✅ ACID compliance for order processing
- ✅ Schema enforcement reduces bugs
- ❌ Need migration strategy for schema changes
```

---

## Shift Left in Your Stack

Given your setup (Wazuh SIEM, AWS org, n8n), shift-left for security means:

```
Design ──▶ IaC Scan ──▶ Container Scan ──▶ Wazuh FIM ──▶ SIEM
         (checkov)    (trivy)           (in-prod)     (alerting)
```

| Phase | Tool | What It Catches |
|-------|------|-----------------|
| IaC (Terraform) | checkov | OpenSecurity S3, IAM misconfigs |
| Container build | trivy | CVE in base images |
| K8s deploy | kyverno | Policy violations before apply |
| Runtime | Wazuh FIM | File integrity changes |
| Runtime | GuardDuty | AWS API anomaly detection |

---

## Common Pitfalls

| Pitfall | Why It's a Problem | Fix |
|---------|-------------------|-----|
| Shift everything left | Slows down dev, team ignores gates | Shift high-value, high-signal items only |
| No owner for security in design | Security is an afterthought | Add security review to design checklist |
| Gates without action | Scan runs, nobody cares | Make gates blocking for critical issues |
| No feedback loop | Same bugs keep slipping through | Track bug origin → fix the gate |

---

## Quick Reference

**Shift Left = catch issues early = cheaper to fix**

| Activity | Traditional Phase | Shifted Phase |
|----------|-----------------|---------------|
| Security review | Pre-release | Design |
| SAST | Staging | CI (PR) |
| Load testing | Pre-release | CI |
| Accessibility | Staging | CI |
| Chaos engineering | Prod | Staging |
| SLO definition | Post-launch | Design |

---

## Source

- [freeCodeCamp — What is Shift Left](https://www.freecodecamp.org/news/what-is-shift-left-in-software/)
- [OWASP DevSecOps Guideline](https://owasp.org/www-project-devsecops-guideline/)

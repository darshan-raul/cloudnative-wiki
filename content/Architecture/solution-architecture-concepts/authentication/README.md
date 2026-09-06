---
title: Identity & Authentication — OIDC, JWT, OAuth, SAML
tags: [authentication, identity, oidc, oauth, jwt, saml, sso, federation, curriculum]
date: 2026-06-13
description: Complete curriculum from crypto primitives to production-grade identity fabrics — OAuth 2.x, OIDC, JWT, SAML 2.0, SSO, federation, security attacks, and a Keycloak reference lab capstone
---

# Identity & Authentication 🔐

A **6-stage, 26-submodule curriculum** that takes you from "what is a token?" to designing zero-trust, multi-tenant, cross-cloud identity fabrics. Built for DevOps/SRE/Security engineers who have to *ship* identity, not just consume it.

## Curriculum Map

| Stage | Focus | Modules | Status |
|-------|-------|---------|--------|
| [[stage0/README\|Stage 0]] | Primitives — crypto, encoding, HTTP/TLS alphabet | 3 | ⬜ |
| [[stage1/README\|Stage 1]] | JWT — the token, end to end | 5 | ⬜ |
| [[stage2/README\|Stage 2]] | OAuth 2.0 — the authorization framework | 6 | ⬜ |
| [[stage3/README\|Stage 3]] | OIDC — identity layer on top of OAuth | 5 | ⬜ |
| [[stage4/README\|Stage 4]] | Federation, SSO, SAML 2.0, B2B | 6 | ⬜ |
| [[stage5/README\|Stage 5]] | Security, attacks, hardening, SIEM | 4 | ⬜ |
| [[stage6/README\|Stage 6]] | Production, scale, frontier (DPoP, PAR, FAPI) | 4 | ⬜ |
| [[capstone/README\|Capstone]] | Keycloak reference lab + incident tabletop | 2 | ⬜ |

**Total: 26 submodules + 2 capstone deliverables.**

## How to Use This Curriculum

1. **Linear path** — start at stage 0, do all modules in order, finish with the capstone. Designed so each module assumes the prior stages are done.
2. **Reference path** — jump straight to the stage you need (e.g. an engineer debugging JWT validation goes to [[stage1/03-jwt-validation|Stage 1.3]]).
3. **Code-first** — every module has working Python/Go snippets you can run, plus a `DevOps analogy` section tying it to infrastructure you already know.

## Audience

- DevOps/SRE engineers building or operating auth services
- Security engineers designing zero-trust architectures
- Platform engineers integrating OIDC into internal platforms
- Backend engineers who own the auth code and need to understand *why*, not just *how*

## Prerequisites

- Comfort with HTTP, JSON, basic Linux/CLI
- Basic Python (all code examples are Python or Go)
- No prior auth experience required — Stage 0 builds the alphabet

## Conventions

- Every module has the same skeleton: **Concept → How it works → Code → DevOps analogy → Attacks/pitfalls → Exercises**
- Wikilinks use the form `[[stageN/MM-slug|Display Name]]`
- YAML frontmatter on every file (title, tags, date, description)
- Code blocks are language-tagged and runnable

## Quick Links

- New here? Start with [[stage0/01-crypto-primitives|Stage 0.1 — Cryptographic Building Blocks]]
- Know JWT, need OAuth? Jump to [[stage2/README|Stage 2]]
- Auditing an existing system? Go to [[stage5/01-top-12-attacks|Stage 5.1 — The Top 12 Attacks]]
- Want to build it end-to-end? The [[capstone/01-keycloak-lab|Keycloak capstone]] walks a full local lab

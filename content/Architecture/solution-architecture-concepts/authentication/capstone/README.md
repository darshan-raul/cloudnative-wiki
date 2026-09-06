---
title: "Capstone — Keycloak Reference Lab & Incident Tabletop"
tags: [authentication, capstone, keycloak, lab, incident-response, tabletop]
date: 2026-06-13
description: Build a full local Keycloak lab exercising OIDC, OAuth2, SSO, SAML, SCIM, and JWKS rotation — then run an identity incident tabletop
---

# Capstone — Putting It All Together

> **Goal:** Two deliverables. **(1)** A complete, reproducible local lab that exercises OIDC, OAuth 2.0, SSO across multiple apps, SAML bridging, and JWKS rotation. **(2)** An incident tabletop you can run with your team to validate your runbook before a real incident hits.

**Prerequisites:** Stages 0-6 complete (or the specific stages each capstone module references).

## Modules

| # | Module | What it builds | Exit criterion |
|---|--------|----------------|----------------|
| [[01-keycloak-lab\|C.1 Keycloak Reference Lab]] | A full Docker Compose stack: Keycloak + 3 client apps (SPA, mobile-API, CLI), OIDC code+PKCE, OAuth2 client_credentials, SAML SP bridge, group/role mapping, JWKS rotation drill | You can run `./up.sh` and demonstrate end-to-end auth across all 3 apps with one Keycloak login |
| [[02-incident-tabletop\|C.2 Identity Incident Tabletop]] | 3 scenarios: token leak, signing key compromise, full IdP outage | You have a tested runbook for each, with SIEM rules wired in |

## What the Keycloak Lab Demonstrates

```
                  ┌──────────────┐
                  │   Keycloak   │
                  │   (IdP)      │
                  └──────┬───────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   ┌────▼────┐      ┌────▼────┐     ┌────▼────┐
   │  App A  │      │  App B  │     │  App C  │
   │ (SPA)   │      │ (API)   │     │ (CLI)   │
   │ OIDC    │      │ OIDC    │     │ OAuth2  │
   │ +PKCE   │      │ +PKCE   │     │ client_ │
   │         │      │         │     │ creds   │
   └─────────┘      └─────────┘     └─────────┘

SSO: log into App A → App B and C recognize you automatically
SAML bridge: legacy SAML SP connects to Keycloak via SAML → OIDC bridge
JWKS rotation: scheduled drill that verifies zero-downtime key rotation
SCIM: create user in Keycloak → propagates to all 3 apps
SIEM hooks: Keycloak events → JSON log → Wazuh → Slack
```

## Connections

This capstone uses:
- [[../stage0/README|Stage 0]] — TLS for the lab, HMAC + RSA for JWT verification
- [[../stage1/README|Stage 1]] — JWT inspection, JWKS rotation drill
- [[../stage2/README|Stage 2]] — OAuth 2.0 auth code + PKCE, client_credentials
- [[../stage3/README|Stage 3]] — OIDC discovery, claims, logout
- [[../stage4/README|Stage 4]] — SAML SP bridge, SCIM
- [[../stage5/README|Stage 5]] — Attack scenarios, audit logging
- [[../stage6/README|Stage 6]] — HA, performance, zero-trust patterns

## Status

- [ ] [[01-keycloak-lab|C.1 Keycloak Reference Lab]]
- [ ] [[02-incident-tabletop|C.2 Identity Incident Tabletop]]

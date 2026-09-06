---
title: "Stage 3 — OpenID Connect (OIDC)"
tags: [authentication, stage-3, oidc, openid, sso, identity]
date: 2026-06-13
description: OIDC fundamentals, flows, claims, discovery, dynamic registration, session management, logout
---

# Stage 3 — OpenID Connect (OIDC)

> **Goal:** OIDC is the identity layer OAuth deliberately isn't. By the end of this stage you can integrate any OIDC IdP, design a claims pipeline, and operate a logout flow that doesn't strand users.

**Prerequisites:** [[../stage2/README|Stage 2]] complete (OAuth 2.0).

## Modules

| # | Module | Why it matters | Exit criterion |
|---|--------|----------------|----------------|
| [[01-oidc-fundamentals\|3.1 OIDC Fundamentals]] | ID token, UserInfo, what OIDC adds on top of OAuth | You can explain the difference in one sentence |
| [[02-oidc-flows\|3.2 OIDC Flows]] | Auth Code + PKCE (canonical), Hybrid, legacy Implicit | You can pick the right flow for SPA vs native vs web |
| [[03-claims-and-sub\|3.3 Claims & sub Discipline]] | Standard claims, custom claims, why `sub` must be opaque | Your multi-tenant systems survive a re-architecture |
| [[04-discovery-registration\|3.4 Discovery & Dynamic Registration]] | `/.well-known/openid-configuration`, JWKS_URI, registration | You can onboard a new IdP by hitting two URLs |
| [[05-session-logout\|3.5 Session Management & Logout]] | Front-channel, back-channel, RP-initiated, sid vs id_token | Your users log out everywhere, not just on the SP they clicked |

## Connections

→ **Next:** [[../stage4/README|Stage 4 — Federation, SSO, SAML, B2B]] extends OIDC to multi-app, multi-org, multi-vendor scenarios.

## Quick Reference

```
OIDC = OAuth 2.0 + identity layer
  - ID Token (JWT, signed by AS, contains user identity)
  - UserInfo endpoint (optional, for richer claims)
  - Standard claims (sub, name, email, etc.)
  - Discovery (/.well-known/openid-configuration)
  - Session management (sid, logout endpoints)

Mandatory vs optional:
  MANDATORY  → iss, sub, aud, exp, iat
  RECOMMENDED → nonce (binds ID token to request)
  OPTIONAL    → name, email, picture, custom claims

ID token is for the CLIENT, not the resource server.
Access token is for the RESOURCE SERVER.
Don't mix them up.
```

## Status

- [ ] [[01-oidc-fundamentals|3.1 OIDC Fundamentals]]
- [ ] [[02-oidc-flows|3.2 OIDC Flows]]
- [ ] [[03-claims-and-sub|3.3 Claims & sub Discipline]]
- [ ] [[04-discovery-registration|3.4 Discovery & Dynamic Registration]]
- [ ] [[05-session-logout|3.5 Session Management & Logout]]

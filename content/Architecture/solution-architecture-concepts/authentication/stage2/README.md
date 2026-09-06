---
title: "Stage 2 — OAuth 2.0"
tags: [authentication, stage-2, oauth, oauth2, pkce, dpop, authorization]
date: 2026-06-13
description: The OAuth 2.0 framework — flows, PKCE, token lifecycles, introspection, revocation, and OAuth 2.1
---

# Stage 2 — OAuth 2.0

> **Goal:** You understand what OAuth actually is (an *authorization* framework, not authentication), can pick the right grant for any scenario, and can design a token lifecycle that doesn't leak, doesn't replay, and survives key compromise.

**Prerequisites:** [[../stage1/README|Stage 1]] complete (JWT, signatures, JWK).

## Modules

| # | Module | Why it matters | Exit criterion |
|---|--------|----------------|----------------|
| [[01-oauth-fundamentals\|2.1 OAuth 2.0 Fundamentals]] | RFC 6749 motivation, actors, scopes, why it's NOT auth | You never say "OAuth is for login" again |
| [[02-auth-code-pkce\|2.2 Authorization Code + PKCE]] | The workhorse flow, PKCE for public + confidential clients | You can implement it from scratch and explain every redirect |
| [[03-other-grants\|2.3 Client Credentials, ROPC, Implicit]] | M2M, legacy, why implicit is dead | You can pick the right grant for a CI job, a CLI, an SPA, a backend |
| [[04-token-lifecycles\|2.4 Token Lifecycles]] | Access tokens, refresh tokens, DPoP, sender-constrained | You can design a refresh rotation scheme with reuse detection |
| [[05-introspection-revocation\|2.5 Introspection & Revocation]] | RFC 7662, RFC 7009, opaque vs self-contained | You can choose between JWT and opaque tokens for any use case |
| [[06-oauth-2-1\|2.6 OAuth 2.1]] | The cleanup: implicit gone, PKCE mandatory | You can map any 2.0 spec onto 2.1 and back |

## Connections

→ **Next:** [[../stage3/README|Stage 3 — OIDC]] adds the *identity* layer (ID token, UserInfo) on top of OAuth's *authorization* layer.

## Quick Reference

```
OAuth 2.0 actors:
  Resource Owner (RO)     = the user
  Resource Server (RS)    = the API that holds the data
  Authorization Server (AS) = issues tokens
  Client                  = the app requesting access

Grants (pick one):
  authorization_code + PKCE    → humans, SPAs, mobile (DEFAULT)
  client_credentials           → machine-to-machine
  device_code                  → input-constrained devices (TVs, CLI)
  refresh_token                → extend a session

NEVER USE (deprecated):
  implicit                     → replaced by auth_code + PKCE
  password (ROPC)              → replaced by auth_code + PKCE

Token forms:
  Self-contained (JWT) → fast verify, hard to revoke
  Opaque + introspect  → slow, real-time revocable
```

## Status

- [ ] [[01-oauth-fundamentals|2.1 OAuth 2.0 Fundamentals]]
- [ ] [[02-auth-code-pkce|2.2 Authorization Code + PKCE]]
- [ ] [[03-other-grants|2.3 Client Credentials, ROPC, Implicit]]
- [ ] [[04-token-lifecycles|2.4 Token Lifecycles]]
- [ ] [[05-introspection-revocation|2.5 Introspection & Revocation]]
- [ ] [[06-oauth-2-1|2.6 OAuth 2.1]]

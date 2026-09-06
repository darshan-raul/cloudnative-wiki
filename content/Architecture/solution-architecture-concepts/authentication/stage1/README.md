---
title: "Stage 1 — JWT Deep Dive"
author: darshan
tags: [authentication, stage-1, jwt, jose, jws, jwe, jwk, jwks]
date: 2026-06-13
description: JWT anatomy, algorithms, validation, lifecycle, and the JOSE family — JWS, JWE, JWK, JWKS
---

# Stage 1 — JWT Deep Dive

> **Goal:** You can read any JWT, write one by hand, validate one correctly, choose the right algorithm, and operate a JWKS rotation without breaking production.

**Prerequisites:** [[../stage0/README|Stage 0]] complete (crypto, encoding, TLS).

## Modules

| # | Module | Why it matters | Exit criterion |
|---|--------|----------------|----------------|
| [[01-jwt-anatomy\|1.1 JWT Anatomy]] | Header.Payload.Signature, registered claims, JOSE header fields | You can decode any JWT and explain every field |
| [[02-algorithms\|1.2 JWT Algorithms]] | HS256/384/512, RS256, ES256, EdDSA, PS256 | You can pick the right algorithm for a use case and justify it |
| [[03-validation\|1.3 JWT Validation]] | The 7 checks, in the right order, every time | You never ship a validator that accepts `alg=none` or a wrong-audience token |
| [[04-lifecycle\|1.4 JWT Lifecycle]] | Issuance, rotation, revocation, replay protection | You can design a short-lived + refresh + JTI-denylist system |
| [[05-jose-family\|1.5 JWS/JWE/JWK/JWKS]] | Compact vs JSON serialization, JWE encryption, JWK public key format, JWKS rotation | You can operate JWKS rotation without a 3am outage |

## Connections

→ **Next:** [[../stage2/README|Stage 2 — OAuth 2.0]] uses JWT access tokens in almost every modern deployment, and what you learned about JWKS here becomes the discovery mechanism for OAuth/OIDC.

## Quick Reference

```
JWT = JWS (signed) | JWE (encrypted + signed)
     Header.Payload.Signature (compact form)

Header   → alg, typ, kid, cty, x5t, crit
Payload  → registered (iss, sub, aud, exp, nbf, iat, jti) + custom claims
Signature → cryptographically binds header + payload

Validation order (MUST):
  1. Algorithm allowlist (NEVER trust the header alg)
  2. Signature (with the right key, resolved via kid)
  3. iss claim
  4. aud claim
  5. exp + nbf
  6. sub (if you need it)
  7. jti (if you maintain a denylist)
```

## Status

- [ ] [[01-jwt-anatomy|1.1 JWT Anatomy]]
- [ ] [[02-algorithms|1.2 JWT Algorithms]]
- [ ] [[03-validation|1.3 JWT Validation]]
- [ ] [[04-lifecycle|1.4 JWT Lifecycle]]
- [ ] [[05-jose-family|1.5 JWS/JWE/JWK/JWKS]]

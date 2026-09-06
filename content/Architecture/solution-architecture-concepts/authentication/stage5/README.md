---
title: "Stage 5 — Security, Attacks, Hardening"
tags: [authentication, stage-5, security, attacks, hardening, audit, siem, threat-model]
date: 2026-06-13
description: The top 12 OAuth/OIDC/JWT attacks, token storage, cryptographic hardening, audit logging, SIEM detection rules
---

# Stage 5 — Security, Attacks, Hardening

> **Goal:** Know the threat model before the attacker shows you. Every auth system ships with the same dozen vulnerabilities — learn to recognize, prevent, and detect each one.

**Prerequisites:** [[../stage2/README|Stage 2]] + [[../stage3/README|Stage 3]] complete.

## Modules

| # | Module | Why it matters | Exit criterion |
|---|--------|----------------|----------------|
| [[01-top-12-attacks\|5.1 The Top 12 OAuth/OIDC/JWT Attacks]] | Confused deputy, CSRF, alg confusion, PKCE downgrade, IDOR, token leakage, mix-up, JWT stripping, open redirect, scope escalation, stolen refresh, session fixation | You can audit an auth system and produce a prioritized fix list |
| [[02-token-storage\|5.2 Token Storage & Side-channel Leaks]] | localStorage vs memory vs cookie, HttpOnly + SameSite, devtools, server logs, referer leakage | You pick the right storage for SPA, native, server-side |
| [[03-crypto-hardening\|5.3 Cryptographic Hardening & Key Rotation]] | JWKS rotation, RS256 → EdDSA migration, key compromise playbook | You can rotate signing keys without a 3am outage |
| [[04-audit-logging-siem\|5.4 Audit, Logging, SIEM Detection]] | Auth event taxonomy, what SOC 2 + ISO 27001 demand, Wazuh/Splunk rules | You can ship an auth audit pipeline that survives a SOC 2 audit |

## Connections

→ **Next:** [[../stage6/README|Stage 6 — Production, Scale, Frontier]] — hardening one server is one thing; hardening a multi-region, multi-tenant identity fabric is another.

## Quick Reference

```
The Top 12 attacks (memorize these):
  1. Confused deputy       → user attacks tenant they have access to
  2. CSRF on /callback     → missing state parameter
  3. Token leakage         → localStorage, logs, referer headers
  4. Alg confusion         → AS accepts alg=none or wrong key
  5. PKCE downgrade        → client omits code_challenge
  6. IDOR via sub          → tenant A can read tenant B
  7. Mix-up attack         → confused which IdP issued what
  8. JWT stripping         → RS256 → HS256 with public key as secret
  9. Open redirect         → unvalidated redirect_uri
 10. Scope escalation      → user gets scopes they shouldn't
 11. Stolen refresh token  → no rotation, no reuse detection
 12. Session fixation      → attacker sets session ID pre-login

Token storage rule of thumb:
  Server-rendered web  → HttpOnly + Secure + SameSite=Strict cookie
  SPA                  → access in memory, refresh in HttpOnly cookie
  Native (iOS/Android) → OS keychain (Keychain / Keystore)
  NEVER                → localStorage, sessionStorage, unencrypted cookies
```

## Status

- [ ] [[01-top-12-attacks|5.1 The Top 12 Attacks]]
- [ ] [[02-token-storage|5.2 Token Storage & Side-channel Leaks]]
- [ ] [[03-crypto-hardening|5.3 Cryptographic Hardening & Key Rotation]]
- [ ] [[04-audit-logging-siem|5.4 Audit, Logging, SIEM Detection]]

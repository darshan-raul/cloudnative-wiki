---
title: "Stage 0 — Primitives: Crypto, Encoding, HTTP/TLS"
author: darshan
tags: [authentication, stage-0, primitives, cryptography, tls, http]
date: 2026-06-13
description: The alphabet before the language — symmetric/asymmetric crypto, encoding vs encryption, signing, TLS, cookies, CORS
---

# Stage 0 — Primitives

> **Goal:** Before you can read a JWT spec or wire up an OIDC flow, you need the alphabet. This stage covers the crypto, encoding, and HTTP/TLS foundations that every auth concept in Stages 1-6 assumes you already know.

**Prerequisites:** basic Linux CLI, comfortable reading JSON, no auth experience required.

## Why this stage exists

The most common reason engineers ship broken auth isn't malice or stupidity — it's a missing mental model for **what a signature actually is**, **what "Base64URL" really does**, or **why a cookie with `SameSite=Lax` behaves differently from `Strict`**. Stage 0 closes those gaps with the minimum viable depth.

## Modules

| # | Module | Why it matters | Exit criterion |
|---|--------|----------------|----------------|
| [[01-crypto-primitives\|0.1 Crypto Building Blocks]] | Symmetric vs asymmetric, hashing, HMAC, RSA, ECDSA, EdDSA | You can explain why `alg=none` is fatal and pick the right algorithm for a use case |
| [[02-encoding-signing-verification\|0.2 Encoding, Signing, Verification]] | Base64URL vs Base64, JSON canonicalization, signature malleability | You can hand-craft and verify a signature without a library |
| [[03-http-tls-foundations\|0.3 HTTP & TLS Foundations]] | TLS 1.2 vs 1.3, mTLS, cookies, Authorization header, CORS preflight, SameSite | You can read a network trace and explain every auth-relevant header |

## Connections

→ **Next:** [[../stage1/README\|Stage 1 — JWT Deep Dive]] builds directly on Stage 0.3 (HMAC, signatures) and Stage 0.2 (Base64URL encoding).

## Quick Reference

```
Symmetric  → one key, both sides keep it secret     (HMAC, AES)
Asymmetric → public key signs/encrypts, private     (RSA, ECDSA, EdDSA)
Hashing    → one-way, no key                         (SHA-256, SHA-3)
Encoding   → NOT encryption, just representation    (Base64, Base64URL)
Signing    → hash + key, proves authenticity         (HMAC, RSA-PSS, EdDSA)
TLS        → encryption + auth at transport layer    (1.2 vs 1.3, mTLS for service-to-service)
```

## Status

- [ ] [[01-crypto-primitives|0.1 Crypto Building Blocks]]
- [ ] [[02-encoding-signing-verification|0.2 Encoding, Signing, Verification]]
- [ ] [[03-http-tls-foundations|0.3 HTTP & TLS Foundations]]

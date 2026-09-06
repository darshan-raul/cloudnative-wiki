---
title: "1.2 — JWT Algorithms: HS/RS/ES/PS/EdDSA"
author: darshan
tags: [authentication, stage-1, jwt, algorithms, hs256, rs256, es256, eddsa, performance]
date: 2026-06-13
description: The full algorithm zoo — HMAC, RSA, ECDSA, RSA-PSS, EdDSA — when to pick which, performance, security, interop
---

# 1.2 — JWT Algorithms: HS/RS/ES/PS/EdDSA

> **Goal:** Pick the right JWT algorithm for any scenario with confidence. Understand the security/perf trade-offs, the interop landscape, and the failure modes unique to each family. Recognize which algorithms you should never use, and why.

> **Prerequisites:** [[../stage0/01-crypto-primitives|Stage 0.1]] complete (symmetric vs asymmetric, RSA, ECDSA, EdDSA fundamentals).

---

## Table of Contents

1. [The Algorithm Zoo](#1-the-algorithm-roo)
2. [HS256/384/512 — HMAC + SHA](#2-hs256384512--hmac--sha)
3. [RS256/384/512 — RSA PKCS#1 v1.5](#3-rs256384512--rsa-pkcs1-v15)
4. [PS256/384/512 — RSA-PSS](#4-ps256384512--rsa-pss)
5. [ES256/384/512 — ECDSA](#5-es256384512--ecdsa)
6. [EdDSA — Ed25519 (and Ed448)](#6-eddsa--ed25519-and-ed448)
7. [The Full Comparison Matrix](#7-the-full-comparison-matrix)
8. [Algorithm Choice Decision Tree](#8-algorithm-choice-decision-tree)
9. [Performance: Real Benchmarks](#9-performance-real-benchmarks)
10. [Compatibility: Who Supports What](#10-compatibility-who-supports-what)
11. [Code: Sign and Verify with Every Algorithm](#11-code-sign-and-verify-with-every-algorithm)
12. [DevOps Analogy: The Stamp Collection](#12-devops-analogy-the-stamp-collection)
13. [Attacks & Pitfalls](#13-attacks--pitfalls)
14. [Exercises](#14-exercises)
15. [Next Step](#15-next-step)

---

## 1. The Algorithm Zoo

The `alg` header in a JWT can be one of ~15 standardized values. They fall into **four families**:

```
HMAC (symmetric)
  HS256, HS384, HS512
  Key: one shared secret
  Use: single service, never crosses a trust boundary

RSA PKCS#1 v1.5 (asymmetric, older)
  RS256, RS384, RS512
  Key: RSA private (sign) / public (verify)
  Use: universal compatibility, legacy interop

RSA-PSS (asymmetric, newer)
  PS256, PS384, PS512
  Key: RSA private (sign) / public (verify)
  Use: when you need RSA but want modern padding

ECDSA (asymmetric)
  ES256, ES384, ES512
  Key: EC private (sign) / public (verify)
  Use: modern default, smaller than RSA, faster than RSA

EdDSA (asymmetric, modern)
  EdDSA
  Key: Ed25519 private (sign) / public (verify)
  Use: new systems, fastest, smallest, no nonce drama
```

**Two algorithms you should NEVER accept:**

```
"none"  → no signature at all. Authentication theatre. See attacks.
"RSA1_5" (no hash) → raw RSA, broken. Not in the JWA spec, but old libs supported it.
```

---

## 2. HS256/384/512 — HMAC + SHA

```
HS256 = HMAC-SHA-256
HS384 = HMAC-SHA-384
HS512 = HMAC-SHA-512
```

**Mechanics:**

```
sign:
  signature = HMAC-SHA256(key, header_b64 + "." + payload_b64)

verify:
  constant_time_equals(signature, HMAC-SHA256(key, signing_input))
```

**Key requirements:**

```
HS256: key MUST be at least 256 bits (32 bytes)
HS384: key MUST be at least 384 bits (48 bytes)
HS512: key MUST be at least 512 bits (64 bytes)

Generate with a CSPRNG:
  Python:  secrets.token_bytes(32)
  Node:    crypto.randomBytes(32)
  Go:      crypto/rand.Read(buf[:32])
  OpenSSL: openssl rand -base64 32
```

**The single biggest HSxxx footgun: key distribution.**

```
Scenario:
  Service A signs tokens
  Service B verifies tokens
  Both share the same secret K
  
  Service B is compromised
  Attacker steals K
  Attacker can now sign any token (forge any user, any claim)
  
This is the "shared secret = shared blast radius" problem.
The more services that know the key, the bigger the compromise.
```

**Mitigations:**

```
1. Limit key distribution: HS256 only when 1-2 services need it
2. Use KMS: store the key in a KMS, have services call out to sign/verify
   (slow but secure; the key never leaves the KMS)
3. Use asymmetric: switch to RS256/ES256/EdDSA so verifiers have only the public key
4. Rotate aggressively: HS256 keys should rotate weekly; leaks are catastrophic
```

**When to use HSxxx:**

```
✅ Internal microservice auth, all in your VPC, you control both ends
✅ One backend issuing + verifying (e.g., a single API service)
✅ Testing, local dev, throwaway environments

❌ Public APIs with 3rd-party verifiers (use asymmetric)
❌ Federated trust (3+ parties) (use asymmetric)
❌ Browser-side verification with a key in JS (just don't)
❌ Multi-tenant systems (asymmetric + per-tenant keys)
```

---

## 3. RS256/384/512 — RSA PKCS#1 v1.5

```
RS256 = RSASSA-PKCS1-v1_5 + SHA-256
RS384 = RSASSA-PKCS1-v1_5 + SHA-384
RS512 = RSASSA-PKCS1-v1_5 + SHA-512
```

**Mechanics:**

```
sign:
  signature = RSA-PKCS1-v1.5-SIGN(private_key, SHA256(header.payload))
  
  Internally:
  1. Hash the signing input with SHA-256 → 32-byte digest
  2. Pad the digest per PKCS#1 v1.5: 0x00 0x01 [0xff padding] 0x00 [DigestInfo]
  3. Compute signature = padded^d mod n
  4. Result: 256-byte signature (for 2048-bit key)

verify:
  signature^e mod n → padded_digest
  Verify the padding is well-formed AND the hash matches
```

**Key requirements (per NIST 2020):**

```
2048-bit key = ~112 bits of symmetric security (MINIMUM acceptable)
3072-bit key = ~128 bits of symmetric security (standard for new systems)
4096-bit key = ~150 bits of symmetric security (paranoid, slow)
15360-bit key = ~256 bits of symmetric security (overkill, post-quantum prep)
```

**Why RSxxx is still the default everywhere:**

```
RS256 is the universal fallback.
  - Every JWT library on Earth supports it
  - Every hardware security module supports it
  - Every language has implementations
  - Government, healthcare, finance, telco all standardized on it
  - The default in OpenID Connect examples
  - The default in most IdPs (Auth0, Okta, Keycloak, Azure AD)
  
If you pick something else, you're making an interop bet.
```

**Why RSxxx is NOT the modern default for new code:**

```
- Slow (especially verification, ~10-50x slower than ECDSA/EdDSA)
- Big keys (2048-4096 bits vs 256-521 bits for ECDSA/EdDSA)
- Big signatures (256 bytes for RS256, vs 64 bytes for ES256/EdDSA)
- PKCS#1 v1.5 padding has historical vulnerabilities (Bleichenbacher)
  → PS256 (RSA-PSS) is the modern RSA option
```

**Bleichenbacher caveat (real, not theoretical):**

```
The Bleichenbacher attack on PKCS#1 v1.5 SIGNATURES (not encryption)
was re-discovered in 2014 (BERserk, Mining PS3). It works because
the padding is "loose" — implementations vary in how strictly they
verify padding, and some are vulnerable to chosen-message attacks.

PS256 (RSA-PSS) is provably secure against this.
If you're starting fresh with RSA, use PS256.
If you're maintaining RS256, audit your padding verification.
```

**When to use RSxxx:**

```
✅ Public APIs with broad interop requirements
✅ Compliance regimes that mandate RSA (some FIPS 140-2 configs)
✅ Legacy systems that don't support ECDSA/EdDSA
✅ IdPs that publish RSA public keys

⚠️  New systems where you control both ends: pick ES256 or EdDSA
```

---

## 4. PS256/384/512 — RSA-PSS

```
PS256 = RSASSA-PSS + SHA-256 (with MGF1-SHA-256 mask generation)
PS384 = RSASSA-PSS + SHA-384
PS512 = RSASSA-PSS + SHA-512
```

**What's different from RSxxx:**

```
RSxxx (PKCS#1 v1.5):
  - Deterministic padding (signature is unique for a given message + key)
  - Loose structure (vulnerable to BERserk-style attacks)
  - Older, simpler, more compatible

PSxxx (PSS):
  - Adds random salt (signature is non-deterministic — different
    signatures of the same message are all valid)
  - Provably secure (Bellare-Rogaway 1996)
  - Modern, slightly less universally supported
  - Default in new code that uses RSA
```

**Mechanics:**

```
sign:
  1. Generate random salt (length = hash length, e.g. 32 bytes for SHA-256)
  2. Compute: message_hash || salt
  3. Apply MGF1 (mask generation) to the hash
  4. XOR the salt with the mask
  5. Pad per PSS encoding (em = masked_DB || H || 0xBC)
  6. RSA sign: padded^d mod n

verify:
  1. RSA verify: signature^e mod n → padded
  2. Extract masked_DB and H
  3. Apply MGF1 to H → mask
  4. Recover salt = masked_DB XOR mask
  5. Compute H' = Hash(message_hash || salt)
  6. Constant-time compare H == H'
```

**The salt makes it non-deterministic.** This has two effects:

```
Benefit:
  + Side-channel resistance — same input gives different signatures
  + Provably secure (no BERserk)

Cost:
  - Slightly larger signature (same RSA key, +hash_size bytes for salt)
    Actually no — the salt is encoded inside the padding, total size unchanged
  - Slightly slower (salt gen + MGF1)
  - Less widely supported in legacy systems
```

**When to use PSxxx:**

```
✅ New systems that need RSA
✅ When you want to be future-proof against padding attacks
✅ FAPI 2.0 mandates PS256 (or ES256) — covered in Stage 6.4

⚠️  Test interop with your verifier first. Some old libs only support PKCS#1 v1.5
```

---

## 5. ES256/384/512 — ECDSA

```
ES256 = ECDSA + SHA-256 over the NIST P-256 curve (secp256r1, prime256v1)
ES384 = ECDSA + SHA-384 over the NIST P-384 curve (secp384r1)
ES512 = ECDSA + SHA-512 over the NIST P-521 curve (secp521r1)
```

(Note: `ES512` is the legacy JOSE name for what is actually P-521, not P-512. There's no P-512. It's confusing and historical.)

**Mechanics:**

```
sign:
  1. Hash the message with SHA-256 → 32-byte digest
  2. Generate random nonce k (must be unique per signature, CSPRNG)
  3. Compute point (x, y) = k * G  (G is the base point on the curve)
  4. r = x mod n  (n is the curve order)
  5. s = k^-1 * (digest + r * private_key) mod n
  6. Signature = (r, s) — 64 bytes for ES256

verify:
  1. Hash the message with SHA-256 → 32-byte digest
  2. Compute u1 = digest * s^-1 mod n
  3. Compute u2 = r * s^-1 mod n
  4. Compute point (x, y) = u1 * G + u2 * public_key
  5. Valid if r == x mod n
```

**The NONCE problem (the critical ECDSA gotcha):**

```
If two signatures use the same nonce k:
  - Same r value (the x-coordinate of k*G)
  - Attacker can solve for the private key:
    
    s1 = k^-1 * (z1 + r * priv)
    s2 = k^-1 * (z2 + r * priv)
    
    s1 - s2 = k^-1 * (z1 - z2)
    k = (z1 - z2) / (s1 - s2)
    
    priv = (s1 * k - z1) / r
    
  - One leaked private key, all signatures past + future compromised

Historical examples:
  - Sony PS3 code signing key (2010) — k was a constant, full key extracted
  - Bitcoin wallets (2013) — Android SecureRandom bug, repeated nonces
  - Multiple other incidents
```

**Deterministic ECDSA (RFC 6979) — the modern fix:**

```
Instead of generating a random k, derive it deterministically from:
  k = HMAC(private_key, message)
  
Same private key + same message → same k → same signature
Different message → different k
  
No randomness needed, no nonce-reuse possible.
If your library doesn't use RFC 6979, switch libraries.
```

**Low-S signatures (defeats malleability, covered in 1.1):**

```
For any valid (r, s), the signature (r, -s mod n) is also valid.
Defeats: signature caching, idempotency keys, audit trail uniqueness.
  
Mitigation: enforce s <= n/2 (low-S) at signing time, reject high-S
at verification time. Most modern libs do this by default.
  
If your library doesn't, you have the malleability bug.
```

**Why ESxxx is the modern default:**

```
✅ Small keys (256 bits for ES256 vs 2048 for RS256)
✅ Small signatures (64 bytes for ES256 vs 256 for RS256)
✅ Fast (10-50x faster than RS256)
✅ Standardized (NIST + JOSE)
✅ Good library support
✅ Compatible with HSMs, smart cards, TPMs

⚠️  ECDSA nonce gotcha (use RFC 6979 + low-S enforcement)
⚠️  Some really old JWT libraries don't support it
```

**When to use ESxxx:**

```
✅ New systems where you control both ends
✅ Mobile/IoT (small signatures = smaller payloads = less data over the wire)
✅ Performance-sensitive verification (high-volume APIs)
✅ Modern IdPs that support it (Auth0, Keycloak, Okta all do)

⚠️  The "ES512" name is misleading (it's P-521, not P-512) — don't get confused
```

---

## 6. EdDSA — Ed25519 (and Ed448)

```
EdDSA in JOSE = Ed25519 (the only curve standardized for JWT in RFC 8037)
Ed448 is in the EdDSA family but not standardized for JOSE.
```

**Mechanics:**

```
Ed25519 uses Curve25519 (a Montgomery curve, in twisted Edwards form).

sign:
  1. private_key = 32 random bytes
  2. SHA-512(private_key) → derive:
     - prefix (32 bytes) — used for nonce derivation
     - actual_scalar (32 bytes) — the private scalar
  3. nonce = SHA-512(prefix || message)  ← deterministic, no RNG needed
  4. R = nonce * B  (B is the base point)
  5. r = SHA-512(R || public_key || message) mod L  (L is the group order)
  6. s = (nonce + r * actual_scalar) mod L
  7. Signature = (R, s) — 64 bytes

verify:
  1. Decompress public key
  2. Compute h = SHA-512(R || public_key || message) mod L
  3. Check: 8 * R == 8 * s * B + 8 * h * public_key
  4. Constant-time throughout

Public key generation:
  public_key = actual_scalar * B  (32 bytes, derived from private)
```

**Why EdDSA is the modern ideal:**

```
✅ Tiny keys (32 bytes for public, 32 bytes for private)
✅ Tiny signatures (64 bytes)
✅ Fastest signing and verification
✅ Deterministic — no nonce-reuse drama
✅ Provably secure (designed to avoid the ECDSA gotchas)
✅ Side-channel resistant by design
✅ Constant-time by construction
✅ Designed by Bernstein (NaCl, ChaCha20, Poly1305) — proven track record

⚠️  Less universal than RS256 (some really old libs don't support it)
⚠️  Some compliance regimes still want RSA (rare in 2026)
```

**The "if you're starting from scratch" choice:**

```
If you control both the signer and the verifier, and your libs
support it: use EdDSA.

If you need broad interop with third parties: use RS256.
If you want small + fast + broad interop: use ES256.
```

**EdDSA in JWT land (RFC 8037):**

```
The JOSE header for EdDSA:
  {
    "alg": "EdDSA",
    "typ": "JWT"
  }
  
That's it. No "crv" or curve name in the JWT header.
The curve is implied (Ed25519).
The public key has a JWK representation:
  {
    "kty": "OKP",
    "crv": "Ed25519",
    "x": "hSDwCYkwp8R8i0Pj0l3...",
    "use": "sig"
  }
```

**The non-obvious advantage: deterministic signatures.**

```
EdDSA signatures are deterministic.
HSxxx signatures are deterministic.
RSA-PSS is NOT deterministic.
ECDSA without RFC 6979 is NOT deterministic.
ECDSA with RFC 6979 is deterministic.

Deterministic = same input → same signature.
This is good for:
  - Replay detection (no random nonce to compare)
  - Caching (can use signature as a cache key)
  - Audit (deterministic logging)
  - Tests (no flaky signatures)
```

---

## 7. The Full Comparison Matrix

### Security equivalence (per NIST SP 800-57, 2020)

| Symmetric bits | HSxxx | RSxxx | PSxxx | ESxxx | EdDSA |
|----------------|-------|-------|-------|-------|-------|
| **112** | HS256 (256-bit key) | RS256 (2048-bit) | PS256 (2048-bit) | ES256 (P-256) | (none standard) |
| **128** | HS256/384 (32-48 byte key) | RS384 (3072-bit) | PS384 (3072-bit) | ES256 (P-256) | Ed25519 |
| **192** | HS384 | RS512 (7680-bit) | PS512 (7680-bit) | ES384 (P-384) | Ed448 (not in JOSE) |
| **256** | HS512 | RS512 (15360-bit) | PS512 (15360-bit) | ES512 (P-521) | (none) |

### Practical matrix

| Algorithm | Family | Key size (sign) | Key size (verify) | Sig size | Sign speed | Verify speed | Deterministic | Notes |
|-----------|--------|----------------|-------------------|----------|------------|--------------|---------------|-------|
| **HS256** | HMAC | 32 bytes | 32 bytes (same) | 32 bytes | Fastest | Fastest | Yes | Symmetric |
| **HS384** | HMAC | 48 bytes | 48 bytes (same) | 48 bytes | Fastest | Fastest | Yes | Symmetric |
| **HS512** | HMAC | 64 bytes | 64 bytes (same) | 64 bytes | Fastest | Fastest | Yes | Symmetric |
| **RS256** | RSA PKCS#1 | 2048-4096 bits | 2048-4096 bits | 256 bytes | Slow | **Slowest** | Yes | Universal interop |
| **RS384** | RSA PKCS#1 | 2048-4096 bits | 2048-4096 bits | 256 bytes | Slow | **Slowest** | Yes | |
| **RS512** | RSA PKCS#1 | 2048-4096 bits | 2048-4096 bits | 256 bytes | Slowest | **Slowest** | Yes | |
| **PS256** | RSA-PSS | 2048-4096 bits | 2048-4096 bits | 256 bytes | Slow | **Slowest** | **No** (salt) | Provably secure |
| **PS384** | RSA-PSS | 2048-4096 bits | 2048-4096 bits | 256 bytes | Slow | **Slowest** | **No** | |
| **PS512** | RSA-PSS | 2048-4096 bits | 2048-4096 bits | 256 bytes | Slowest | **Slowest** | **No** | |
| **ES256** | ECDSA | 32 bytes | 64 bytes | 64 bytes | Fast | Fast | With RFC 6979 | Modern default |
| **ES384** | ECDSA | 48 bytes | 64 bytes | 96 bytes | Fast | Fast | With RFC 6979 | |
| **ES512** | ECDSA | 64 bytes | 132 bytes | 132 bytes | Fast | Fast | With RFC 6979 | Note: P-521, not P-512 |
| **EdDSA** | Ed25519 | 32 bytes | 32 bytes | 64 bytes | **Fastest** | **Fastest** | Yes | Modern ideal |

### Cost per million operations (rough, AWS Graviton, 2024 measurements)

```
HS256:    1ms sign, 1ms verify      →  $0.01 / 1M tokens
EdDSA:    1ms sign, 2ms verify      →  $0.02 / 1M tokens
ES256:    2ms sign, 3ms verify      →  $0.03 / 1M tokens
PS256:    50ms sign, 5ms verify     →  $0.50 / 1M tokens
RS256:    50ms sign, 5ms verify     →  $0.50 / 1M tokens
RS4096:   500ms sign, 30ms verify   →  $5.00 / 1M tokens
```

If you do 1B tokens/day at the edge, that's $500/day for RS256, $10/day for EdDSA. The algorithm choice has real cost.

---

## 8. Algorithm Choice Decision Tree

```
Start
  │
  ├─ Need universal interop with 3rd parties?
  │    │
  │    ├─ YES → RS256 (default fallback)
  │    │
  │    └─ NO  → Does the verifier need to be browser or external?
  │              │
  │              ├─ YES → EdDSA or ES256 (modern, small, fast)
  │              │
  │              └─ NO  → Is the system zero-trust (no shared secret)?
  │                        │
  │                        ├─ YES → EdDSA (best default)
  │                        │
  │                        └─ NO  → Is it single-service internal?
  │                                  │
  │                                  ├─ YES → HS256 (simple, fast)
  │                                  │
  │                                  └─ NO  → EdDSA (default for new systems)
  │
  └─ Compliance regime mandates a specific algorithm?
       │
       ├─ FAPI 2.0 → PS256 or ES256
       ├─ PCI-DSS  → RSA ≥ 2048, ECDSA P-256+ acceptable
       ├─ FIPS 140 → Check your module's approved list
       ├─ Common Criteria → Match the EAL requirements
       └─ None of the above → use the decision tree above
```

**My defaults (in 2026):**

```
Greenfield project, full control:    EdDSA
Greenfield + need interop:           ES256
Brownfield, existing RS256:          stay on RS256 (don't break what's working)
Single internal service:             HS256 (with KMS-backed keys)
FAPI 2.0 / financial:                PS256 or ES256 (mandated)
```

---

## 9. Performance: Real Benchmarks

Numbers below are from `python-jose` + `cryptography` library, AWS Graviton3, 2024. Your mileage will vary, but the relative order is consistent.

### Sign throughput (ops/sec, higher is better)

```
HS256:    250,000  ops/sec
HS512:    200,000  ops/sec
EdDSA:    180,000  ops/sec
ES256:    100,000  ops/sec
PS256:     8,000  ops/sec
RS256:     8,000  ops/sec
RS4096:      400  ops/sec
```

### Verify throughput (ops/sec, higher is better)

```
HS256:    200,000  ops/sec
EdDSA:    150,000  ops/sec
ES256:    120,000  ops/sec
PS256:    50,000  ops/sec
RS256:    50,000  ops/sec
RS4096:   2,000  ops/sec
```

### Memory: how big is a 1M token buffer?

```
RS256:   256 MB  (256-byte signatures × 1M)
ES256:    64 MB  (64-byte signatures × 1M)
EdDSA:    64 MB
HS256:    32 MB  (32-byte signatures × 1M)
```

### Total request size (header.payload.signature):

```
RS256:  ~1.2 KB  (300 bytes header/payload + 256 bytes sig)
ES256:  ~1.0 KB
EdDSA:  ~1.0 KB
HS256:  ~1.0 KB
```

### When does this matter?

```
1M tokens/hour:    RS256 is fine, ES256 is fine
1M tokens/minute:  ES256 / EdDSA give you headroom
1M tokens/second:  EdDSA only, RS256 will not keep up at the edge
```

---

## 10. Compatibility: Who Supports What

| Algorithm | Auth0 | Okta | Keycloak | Azure AD | AWS Cognito | Google | Apple | FAPI 2.0 |
|-----------|-------|------|----------|----------|-------------|--------|-------|----------|
| **RS256** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **PS256** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **ES256** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **EdDSA** | ✅ | ✅ | ✅ | ✅ | ⚠️ partial | ✅ | ✅ | ⚠️ |
| **HS256** | ✅ | ✅ | ✅ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |

If you're an IdP: support RS256, PS256, ES256, EdDSA. Skip HS256 unless explicitly requested.

If you're an RP (relying party): pick one. Don't list all four.

**Library support (2026):**

```
PyJWT:        RS256, PS256, ES256, ES384, ES512, EdDSA, HSxxx
python-jose:  RS256, PS256, ES256, ES384, ES512, EdDSA, HSxxx
authlib:      All of the above + JWE
golang-jwt:   RSxxx, ESxxx, EdDSA, HSxxx, PSxxx
jose (Node):  All of the above
java-jwt:     RSxxx, ESxxx, EdDSA
nimbus-jose:  All of the above + JWE + JWS JSON
```

If your library doesn't support EdDSA in 2026, switch libraries.

---

## 11. Code: Sign and Verify with Every Algorithm

Full working examples. All in Python, all in one script.

```python
"""
Sign and verify a JWT with every algorithm in the JOSE spec.
Run: pip install pyjwt cryptography
"""
import jwt
import time
from cryptography.hazmat.primitives.asymmetric import rsa, ec, ed25519
from cryptography.hazmat.primitives import serialization

# --- Generate keys (do this once, persist them) ---

# RSA 2048 (RS256, PS256)
rsa_priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
rsa_pem = rsa_priv.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
)

# ECDSA P-256 (ES256)
ec_priv = ec.generate_private_key(ec.SECP256R1())
ec_pem = ec_priv.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
)

# Ed25519 (EdDSA)
ed_priv = ed25519.Ed25519PrivateKey.generate()
ed_pem = ed_priv.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
)

# HMAC key
hmac_key = b"this-is-a-32-byte-secret-key-for-hs256"  # 32 bytes = 256 bits

# --- Build a payload ---
now = int(time.time())
payload = {
    "iss": "https://idp.example.com",
    "sub": "user-abc-123",
    "aud": "api.example.com",
    "exp": now + 3600,
    "iat": now,
    "nbf": now,
    "jti": "token-001",
    "name": "Alice Smith",
    "role": "admin",
}

# --- Sign with each algorithm ---
print("\n=== SIGNING ===")
tokens = {}

for name, alg, key in [
    ("HS256", "HS256", hmac_key),
    ("RS256", "RS256", rsa_pem),
    ("PS256", "PS256", rsa_pem),
    ("ES256", "ES256", ec_pem),
    ("EdDSA", "EdDSA", ed_pem),
]:
    token = jwt.encode(payload, key, algorithm=alg,
                       headers={"kid": f"{name.lower()}-2024-01"})
    tokens[name] = token
    print(f"\n{name} ({len(token)} bytes):")
    print(f"  {token[:80]}...")

# --- Verify with each algorithm ---
print("\n\n=== VERIFYING ===")
for name, alg, key in [
    ("HS256", "HS256", hmac_key),
    ("RS256", "RS256", rsa_pem),  # for the demo, we have the private key
    ("PS256", "PS256", rsa_pem),
    ("ES256", "ES256", ec_pem),
    ("EdDSA", "EdDSA", ed_pem),
]:
    # Use public key for verification
    if name == "HS256":
        verify_key = key
    elif name in ("RS256", "PS256"):
        verify_key = rsa_priv.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
    elif name == "ES256":
        verify_key = ec_priv.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
    elif name == "EdDSA":
        verify_key = ed_priv.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )

    try:
        claims = jwt.decode(
            tokens[name],
            key=verify_key,
            algorithms=[alg],  # ← ALGORITHM ALLOWLIST
            issuer="https://idp.example.com",
            audience="api.example.com",
            options={"require": ["exp", "iat", "iss", "aud", "sub"]},
        )
        print(f"  {name}: ✓ valid (sub={claims['sub']}, role={claims['role']})")
    except Exception as e:
        print(f"  {name}: ✗ {e}")

# --- Negative test: try to verify HS256 with the RSA public key as the secret ---
# This is the algorithm confusion attack. PyJWT blocks it via the
# algorithms allowlist, but buggy libraries don't.
print("\n\n=== ALGORITHM CONFUSION ATTACK (must fail) ===")
rsa_pub = rsa_priv.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
)

# Forge a token claiming alg=HS256, signed with the RSA public key as the HMAC secret
import base64, hmac, hashlib
def b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
forged_header = b64url(b'{"alg":"HS256","typ":"JWT","kid":"rsa-2024-01"}')
forged_payload = b64url(b'{"sub":"attacker","role":"admin","iss":"https://idp.example.com","aud":"api.example.com","exp":9999999999,"iat":1700000000}')
forged_sig = b64url(hmac.new(rsa_pub, f"{forged_header}.{forged_payload}".encode(), hashlib.sha256).digest())
forged_token = f"{forged_header}.{forged_payload}.{forged_sig}"

try:
    claims = jwt.decode(
        forged_token,
        key=rsa_pub,
        algorithms=["HS256"],  # ← vulnerable if attacker controls this
        issuer="https://idp.example.com",
        audience="api.example.com",
    )
    print(f"  ⚠️  ATTACK SUCCEEDED: {claims}")
except Exception as e:
    print(f"  ✓ ATTACK BLOCKED: {e}")
```

**Expected output:**

```
=== SIGNING ===

HS256 (256 bytes):
  eyJhbGciOiJIUzI1NiIs...
RS256 (705 bytes):
  eyJhbGciOiJSUzI1NiIs...
PS256 (705 bytes):
  eyJhbGciOiJQUzI1NiIs...
ES256 (401 bytes):
  eyJhbGciOiJFUzI1NiIs...
EdDSA (281 bytes):
  eyJhbGciOiJFZERTQSIs...

=== VERIFYING ===
  HS256: ✓ valid
  RS256: ✓ valid
  PS256: ✓ valid
  ES256: ✓ valid
  EdDSA: ✓ valid

=== ALGORITHM CONFUSION ATTACK (must fail) ===
  ✓ ATTACK BLOCKED: ...
```

---

## 12. DevOps Analogy: The Stamp Collection

Imagine a notary public in a corporate office building.

| JWT algorithm | Notary equivalent |
|---------------|-------------------|
| **HS256** | A single shared rubber stamp that everyone authorized has. Anyone with the stamp can certify. If someone loses it, the stamp is replaced. |
| **RS256** | A notary with a personal embossed seal. The seal pattern is published in the company directory. Anyone can check the seal against the directory. Only the notary has the embossing tool. |
| **ES256** | Same as RS256, but the embossing tool is a tiny precision instrument, not a heavy cast-iron press. Cheaper to make, harder to forge, smaller imprint. |
| **EdDSA** | The modern equivalent: a laser-etched seal. The smallest, fastest, hardest to forge. |

**The operational reality:**

```
HS256:
  - "We have one stamp, kept in a safe, used by one team"
  - If the safe is broken into: forge anything
  - If the stamp gets worn: replace, distribute, hope no one kept a copy
  - Cost: cheap
  - Blast radius: anyone with access to the safe

RS256:
  - "We have 100 notaries, each with their own seal, and a public directory"
  - Compromised notary: revoke their seal, update the directory
  - Cost: heavy stamps, slow embossing
  - Blast radius: one notary's power
  - Interop: works in any company, anywhere

ES256 / EdDSA:
  - "We have 100 notaries with precision instruments"
  - Compromised notary: revoke, rotate
  - Cost: cheap, fast
  - Blast radius: one notary's power
  - Interop: works in most modern companies
```

---

## 13. Attacks & Pitfalls

### A1. `alg=none` (revisit)
Never accept. Most libraries default to rejecting it, but some have a `verify=False` mode that's like inviting the attack in. Set `verify=True` and use an algorithm allowlist.

### A2. Algorithm confusion (HS256 vs RS256, HS256 vs ES256)
The forged token has `alg=HS256`, the public key is used as the HMAC secret, the library accepts. Defense: pin the algorithm. If your service expects RS256, the token's `alg` MUST be RS256.

### A3. ECDSA nonce reuse
Use RFC 6979 (deterministic ECDSA) and a vetted library. If your library has a `nonce` parameter, you have non-deterministic ECDSA, which is one RNG bug away from a private key leak.

### A4. ECDSA signature malleability
Enforce low-S (s <= n/2) at signing and verification. Most modern libs do this. If yours doesn't, you have a bug.

### A5. RSA PKCS#1 v1.5 padding (BERserk, 2014)
Use PS256 (RSA-PSS) for new code. If you must use RS256, audit your padding verification implementation for the BERserk bug. Most modern libs (OpenSSL, BoringSSL, Go's crypto/rsa) are safe.

### A6. Choosing RSA key size below 2048
1024-bit RSA is broken. Some old systems still use it. 2048 is the minimum, 3072 is the standard for new systems. 4096 is paranoid. 15360 is post-quantum prep.

### A7. HSxxx with predictable keys
"secret", "mycompanyname", "changeme" — all public. Always use a 32+ byte cryptographically random key. Use a KMS, not a config file.

### A8. Forgetting to validate the algorithm
Most JWT libraries will let you pass `algorithms=None` and just trust the header. Never do this. Always pass an explicit allowlist.

```python
# ❌ NEVER
jwt.decode(token, key, algorithms=None)  # trusts the header

# ✅ ALWAYS
jwt.decode(token, key, algorithms=["RS256"])  # pinned allowlist
```

### A9. Cross-family algorithm substitution

```
Service expects RS256. Attacker sends:
  Token with alg=PS256 (same key, different padding)
  Some libs treat PS256 like RS256 and "just verify it" — silently wrong
  
Defense: algorithm allowlist must match exactly. If you say ["RS256"],
PS256 is rejected.
```

### A10. Mixing Ed25519 with X25519

```
Ed25519 = signing
X25519 = key exchange (used in TLS, not JOSE)

These are different curves, different operations.
Don't accidentally use a X25519 key for Ed25519 signing — they have
the same byte length (32) and similar names, but the keys are NOT
interchangeable.

In JWK:
  Ed25519: {"kty":"OKP", "crv":"Ed25519", "x":"...", "d":"..."}
  X25519:  {"kty":"OKP", "crv":"X25519",  "x":"...", "d":"..."}
  
If the crv field is wrong, the library should reject.
```

### A11. Algorithm pinning broken by config

```python
# ❌ DANGEROUS — algorithm pulled from config can be changed at runtime
ALLOWED_ALG = config.get("auth.algorithm", "RS256")
jwt.decode(token, key, algorithms=[ALLOWED_ALG])

# An attacker who can modify config can set this to "none" or "HS256"

# ✅ SAFER — algorithm hardcoded in source
jwt.decode(token, key, algorithms=["RS256"])
```

### A12. The "we support all algs" antipattern

```
Some IdPs claim to support 12 algorithms to "maximize interop."

This is bad:
  - Every supported algorithm is a possible attack vector
  - Operators must patch every alg when a vulnerability emerges
  - Some old, broken algs should never be in the list

Recommended IdP config:
  - Sign: pick 1-2 (e.g., RS256 + EdDSA)
  - Verify: support all algs the issuers use
  - Never advertise algs you don't actually use
```

---

## 14. Exercises

### Exercise 1: Sign with all 5 algs
Take the code from Section 11, run it. Compare the token sizes. Sign the same payload 1000 times with each algorithm. Are the signatures deterministic?

### Exercise 2: Algorithm confusion drill
Use the same script. Try the algorithm confusion attack against each algorithm pair (HS256 secret vs RS256 public key, etc.). Which ones does PyJWT block? Could you bypass the block?

### Exercise 3: Performance microbench
Write a small script that times 10,000 sign+verify operations for each algorithm. Compare the relative order to Section 9. If you see different ordering, why might that be?

### Exercise 4: Choose for your scenario
For each scenario, pick the algorithm and justify in 2-3 sentences:
- (a) New internal microservice, all in your VPC, no external RPs
- (b) Public API, 10,000 third-party developers verify your tokens
- (c) FAPI 2.0 banking app
- (d) Mobile game backend, low-end Android devices in 2018
- (e) Workload identity (k8s service account → AWS IAM)

### Exercise 5: Key rotation
Your service signs with RS256 using a 2048-bit key. You want to migrate to EdDSA. Design a 90-day rotation plan. (Hint: dual-sign, dual-verify, then drop the old one.)

### Exercise 6: Find the bug
A colleague writes:
```python
def verify(token, key):
    return jwt.decode(token, key, algorithms=None)
```
What's wrong? How many attack vectors does it open? Write 3 attack tokens that exploit it.

### Exercise 7: The EdDSA portability check
Try to sign with EdDSA in your language's JWT library. Does it work? If not, upgrade. (Most libraries have had EdDSA support for 5+ years.)

### Exercise 8: Compute the cost
Your API verifies 50M JWTs/day. At $0.50/1M for RS256 vs $0.02/1M for EdDSA, what's the annual savings of migrating? What about the migration cost?

### Exercise 9: Read a CVE
Pick a real JWT algorithm CVE (search "JWT algorithm CVE" or "RS256 CVE" in your preferred CVE database). Identify: which algorithm, what was the bug, what's the fix, would your validator have been vulnerable?

### Exercise 10: Build a "what's my alg?" tool
Write a 30-line function that takes a token, decodes the header, prints the algorithm, key type (symmetric vs asymmetric), recommended key size, and any concerns (e.g., "alg=none — REJECT", "HS256 — internal use only").

---

## 15. Next Step

You can now choose, sign, verify, and attack-test JWT algorithms. Next, the heart of the matter: the seven validation checks, in the right order, every time.

→ [[../stage1/03-validation|Stage 1.3 — JWT Validation: The 7 Checks]]

**Before you move on, verify you can answer these:**
1. What's the difference between HS256 and RS256, and when do you pick each?
2. Why is PS256 preferred over RS256 for new code, but RS256 still the universal default?
3. What's the ECDSA nonce-reuse attack, and how does EdDSA prevent it?
4. What is the algorithm confusion attack, and how does an algorithm allowlist prevent it?
5. For a greenfield project in 2026, what's your default algorithm choice and why?
6. How does signature malleability affect ES256, and what's the fix?

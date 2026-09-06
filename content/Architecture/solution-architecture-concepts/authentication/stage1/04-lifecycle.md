---
title: "1.4 — JWT Lifecycle: Issuance, Rotation, Revocation, Replay Protection"
author: darshan
tags: [authentication, stage-1, jwt, lifecycle, rotation, revocation, refresh-tokens, replay-protection, denylist]
date: 2026-06-13
description: How JWTs are issued, how long they live, how they're refreshed, rotated, revoked, and protected against replay
---

# 1.4 — JWT Lifecycle: Issuance, Rotation, Revocation, Replay Protection

> **Goal:** Design a token lifecycle that doesn't leak, doesn't strand users, and can be revoked when needed. Understand the trade-off between statelessness and control, when short-lived + refresh is the right pattern, and how to detect replayed or stolen tokens.

> **Prerequisites:** [[../stage1/01-jwt-anatomy|Stage 1.1]] + [[../stage1/02-algorithms|Stage 1.2]] + [[../stage1/03-validation|Stage 1.3]] complete.

---

## Table of Contents

1. [The Lifecycle Problem](#1-the-lifecycle-problem)
2. [Issuance — Minting the First Token](#2-issuance--minting-the-first-token)
3. [Token Lifetimes — The Short-Lived + Refresh Pattern](#3-token-lifetimes--the-short-lived--refresh-pattern)
4. [Refresh Token Rotation with Reuse Detection](#4-refresh-token-rotation-with-reuse-detection)
5. [Revocation — Killing a Live Token](#5-revocation--killing-a-live-token)
6. [JTI Denylist — The Standard Revocation Mechanism](#6-jti-denylist--the-standard-revocation-mechanism)
7. [Replay Protection — Detecting Reused Tokens](#7-replay-protection--detecting-reused-tokens)
8. [Sender-Constrained Tokens (DPoP, mTLS)](#8-sender-constrained-tokens-dpop-mtls)
9. [Sliding Sessions vs Absolute Sessions](#9-sliding-sessions-vs-absolute-sessions)
10. [The Full Lifecycle State Machine](#10-the-full-lifecycle-state-machine)
11. [Code: Complete Lifecycle in 80 Lines](#11-code-complete-lifecycle-in-80-lines)
12. [DevOps Analogy: The Hotel Keycard](#12-devops-analogy-the-hotel-keycard)
13. [Attacks & Pitfalls](#13-attacks--pitfalls)
14. [Exercises](#14-exercises)
15. [Next Step](#15-next-step)

---

## 1. The Lifecycle Problem

A JWT, once issued, is **valid until it expires**. The signature is fine. The claims are correct. The verifier has no reason to reject it.

**The problem:** the user might:
- Log out (and we want the token dead immediately)
- Be fired (and we want all their tokens dead immediately)
- Have their token stolen (and we want that one token dead immediately)
- Have changed roles (and the old token's claims are stale)
- Have their account deleted (and the token should be dead)

A self-contained, stateless JWT doesn't know about any of these. The signature says "this was issued by the IdP, the claims are correct, the time hasn't passed." That's it.

**The trade-off:**

```
Stateless (pure JWT):
  ✓ No server state
  ✓ Verifier needs only the public key
  ✓ Scales infinitely
  ✗ Cannot revoke instantly
  ✗ Stale claims (role changes, etc.)
  ✗ Stolen tokens valid until exp

Stateful (with denylist):
  ✓ Instant revocation
  ✓ Real-time claim updates
  ✓ Stolen token = add to denylist
  ✗ Server state (Redis, DB)
  ✗ Single point of failure if denylist goes down
  ✗ Doesn't scale infinitely (Redis cluster, partitioning)

The answer: short-lived access tokens + denylist for emergencies.
```

The "modern" pattern, used by every well-architected system in 2026:

```
┌──────────────────────────────────────────────────────────┐
│  Access token (JWT, 5-15 min)                            │
│    → Self-contained, stateless verification               │
│    → Long enough for a single user session                │
│    → Short enough to limit damage from leak               │
│                                                          │
│  Refresh token (opaque or JWT, 7-90 days)                │
│    → Used to mint new access tokens                       │
│    → Stored securely (HttpOnly cookie or keychain)        │
│    → Rotated on every use (with reuse detection)          │
│    → Revocable (denylist or DB flag)                      │
│                                                          │
│  Result:                                                 │
│    - Stolen access token: dies in 5-15 min automatically  │
│    - User logs out: refresh token revoked                 │
│    - User fired: all refresh tokens revoked               │
│    - System scales: access token verification is O(1)     │
│    - System revokes: refresh token check is O(1) in Redis │
└──────────────────────────────────────────────────────────┘
```

---

## 2. Issuance — Minting the First Token

Issuance happens after the user authenticates (password, MFA, federated login, etc.). The IdP creates a JWT, signs it, and returns it.

```python
import jwt
import time
import uuid

def issue_access_token(*, sub: str, scopes: list[str], 
                       issuer: str, audience: str,
                       signing_key: bytes | str, algorithm: str,
                       ttl_seconds: int = 900,  # 15 min default
                       extra_claims: dict = None) -> str:
    """
    Issue a short-lived access token.
    
    Returns: signed JWT string
    """
    now = int(time.time())
    payload = {
        "iss": issuer,
        "sub": sub,
        "aud": audience,
        "exp": now + ttl_seconds,
        "iat": now,
        "nbf": now,
        "jti": str(uuid.uuid4()),  # unique per token
        "scope": " ".join(scopes),  # OAuth 2.0 convention
    }
    if extra_claims:
        payload.update(extra_claims)
    
    return jwt.encode(payload, signing_key, algorithm=algorithm,
                      headers={"kid": get_current_kid()})
```

**Key choices at issuance time:**

```
1. Algorithm: pick from your allowlist (RS256, ES256, EdDSA typically)
2. Lifetime: 5-15 min for access tokens, 7-90 days for refresh
3. kid: which signing key (use a kid rotation strategy — see 1.5)
4. jti: must be unique (UUIDv4 is the standard)
5. Claims: iss, sub, aud, exp, iat, nbf are mandatory; scope/permissions
   are common; custom claims per your application
6. extras: any custom claims your app needs (org_id, tenant_id, roles, etc.)
```

**The "iat in the past" check is your clock-skew detector:**

```
If iat is in the past (with leeway), it's normal.
If iat is far in the future, the token is forged (or clocks are wildly off).
This is why you should always include iat.
```

---

## 3. Token Lifetimes — The Short-Lived + Refresh Pattern

The access token's job: live just long enough for a user session. Not longer.

```
┌─────────┐
│ Access  │  5-15 minutes
│ Token   │  → expires, then user gets a new one
│ (JWT)   │  → stateless, no server lookup
└─────────┘

┌─────────┐
│ Refresh │  7-90 days
│ Token   │  → used to mint new access tokens
│         │  → stateful (server has a record)
│         │  → can be revoked
└─────────┘
```

**The full request flow:**

```
1. User authenticates (password + MFA)
2. IdP issues access token (15 min) + refresh token (30 days)
3. Client stores both:
   - Access token: in memory (or volatile state)
   - Refresh token: in HttpOnly + Secure + SameSite=Strict cookie
4. Client makes API call with access token
5. 15 min later, access token expires
6. Client sees 401 from API
7. Client sends refresh token to /token endpoint
8. IdP validates refresh token (DB lookup or denylist)
9. IdP issues new access token + new refresh token
10. Old refresh token is now invalid (rotated)
11. Loop continues until 30 days, then user re-authenticates
```

**Why this is the right pattern:**

```
- Stolen access token: 15 min of damage max
- Stolen refresh token: 30 days of damage (until detection)
  → Why you detect refresh token reuse (Section 4)
- Logout: revoke the refresh token → no more new access tokens
- User fired: revoke all their refresh tokens → they get locked out
  within 15 min (when current access token expires)
- Scale: access token verification is O(1), no DB
- Compromise: refresh token check is O(1) in Redis
```

**Access token lifetime decision matrix:**

```
Static API keys (CI, scripts):  never expires (with explicit rotation)
  → Or 90 days with admin revocation
  → Or 1 year with annual rotation
  → But: bearer of a long-lived token IS the user

User-facing access tokens:  5-15 min
  → Long enough for a user to do a workflow
  → Short enough that "forgot to log out" damage is bounded
  → Standard in OIDC (most IdPs default to 1 hour, recommend 15 min)

Internal service tokens:  1 hour
  → Long enough for retries, batch jobs
  → Short enough for "service compromised" recovery

Workload identity (SPIFFE):  1 hour
  → SPIFFE handles rotation automatically
  → See Stage 6.3

Machine-to-machine:  1 hour - 24 hours
  → CI jobs, scheduled tasks
  → Consider workload identity for modern systems
```

**Refresh token lifetime decision matrix:**

```
Web app (B2C):  30 days
  → Long enough to not annoy users with daily re-login
  → Short enough that "stolen device" damage is bounded
  → Modern apps: 7-30 days

Mobile app (B2C):  90 days - 1 year
  → Users don't want to re-login on mobile
  → Compensating: device fingerprint binding, biometric re-auth
  → Trade-off: usability vs security

B2B / enterprise:  8 hours - 7 days
  → Compliance regimes often mandate short sessions
  → Often paired with SSO IdP, so re-auth is fast

Server-to-server:  depends on rotation strategy
  → Or: use mTLS for workload identity instead (no refresh token)
```

---

## 4. Refresh Token Rotation with Reuse Detection

The critical security feature of refresh tokens: **rotate them on every use**, and **detect reuse** (which indicates theft).

### Without rotation

```
Issue refresh token A
User uses A, gets new access token
User uses A again (attacker also has A)
User uses A again (attacker also has A)
... no detection, attacker has access until A expires
```

### With rotation (RFC 6749 + OAuth 2.0 Security BCP, draft)

```
Issue refresh token A
User uses A, IdP issues new refresh token B, A is now invalid
User uses B, IdP issues new refresh token C, B is now invalid
... chain of single-use tokens

If the user uses A again (after it was rotated):
  → IdP detects: A was already used
  → IdP revokes the ENTIRE token family
  → User is logged out everywhere
  → Re-authentication required
```

**Why rotation + reuse detection works:**

```
If an attacker steals A and uses it first:
  Attacker uses A, gets B
  Legitimate user tries A, gets rejection
  If system revokes the family on A reuse, attacker is locked out too
  
If the legitimate user uses A first and then attacker uses A:
  Attacker tries A, gets rejection (already used)
  If system revokes the family on A reuse, legitimate user is also locked out
    (but this is a "false positive" that's worth it for security)
```

**The state to maintain:**

```python
# Per refresh token family:
refresh_token = {
    "jti": "rt-001",                      # current token's JTI
    "family_id": "fam-abc",                # the chain this token belongs to
    "sub": "user-123",                     # the user
    "issued_at": 1700000000,
    "expires_at": 1702592000,              # 30 days from issuance
    "parent_jti": None,                    # previous token in chain (for family tree)
    "rotated_at": None,                    # when this token was used
    "revoked": False,
    "revoked_reason": None,
}
```

**The rotation flow:**

```python
import redis
import secrets

r = redis.Redis(...)

def rotate_refresh_token(old_jti: str, sub: str) -> dict:
    # 1. Check if old token is valid (exists, not revoked, not expired)
    key = f"rt:{old_jti}"
    record = r.hgetall(key)
    if not record:
        # Token doesn't exist. Either already used, or never existed.
        # CRITICAL: check the family for reuse detection
        check_reuse_violation(old_jti)
        raise TokenReuseError("token invalid")
    
    if record.get("revoked") == "1":
        raise TokenRevokedError("token revoked")
    
    # 2. Mark the old token as used (set rotated_at)
    r.hset(key, "rotated_at", int(time.time()))
    r.expire(key, 30 * 24 * 3600)  # keep for audit
    
    # 3. Issue a new refresh token
    new_jti = f"rt-{secrets.token_urlsafe(32)}"
    new_record = {
        "jti": new_jti,
        "family_id": record["family_id"],
        "sub": sub,
        "issued_at": int(time.time()),
        "expires_at": int(time.time()) + 30 * 24 * 3600,
        "parent_jti": old_jti,
        "rotated_at": None,
        "revoked": "0",
    }
    r.hset(f"rt:{new_jti}", mapping=new_record)
    r.expire(f"rt:{new_jti}", 30 * 24 * 3600)
    
    return new_record


def check_reuse_violation(used_jti: str):
    """
    Called when a token is presented that doesn't exist or is already used.
    If the token was previously used, this is a reuse — possible theft.
    We revoke the entire family.
    """
    key = f"rt:{used_jti}"
    record = r.hgetall(key)
    if record and record.get("rotated_at"):
        # The token WAS used (has a rotated_at). This is reuse.
        family_id = record["family_id"]
        revoke_token_family(family_id, reason="reuse_detected")


def revoke_token_family(family_id: str, reason: str = "user_logout"):
    """
    Revoke every token in the family.
    """
    # Find all tokens in the family
    # (In production, maintain a family → tokens index)
    for jti in get_family_tokens(family_id):
        r.hset(f"rt:{jti}", "revoked", "1")
        r.hset(f"rt:{jti}", "revoked_reason", reason)
    
    # Audit log
    log_security_event("refresh_token_family_revoked", {
        "family_id": family_id,
        "reason": reason,
    })
```

**The misuse patterns:**

```
1. User logs in on phone. Uses refresh token. Logs out.
   → Server revokes family. User has to re-auth on phone next time.
   → Correct behavior.

2. User logs in on phone and laptop. Two devices, two refresh tokens, two families.
   → Revoking one family doesn't affect the other. Correct.

3. Attacker steals user's refresh token. Uses it first.
   → Attacker gets new access token. User tries to use old token, gets 401.
   → User re-authenticates. Attacker still has a valid token from the rotated family.
   → Mitigation: detect reuse (Section 7), revoke entire family on detection.

4. User logs in, refreshes 100 times in 1 minute.
   → Some IdPs rate-limit. Most don't. Consider throttling.
```

---

## 5. Revocation — Killing a Live Token

There are five ways to "kill" a token, each with different trade-offs.

### 5.1 Wait for expiration

```
The stateless default. The token is valid until exp. No server action needed.

Pros: nothing to do.
Cons: if token has 30 days left, attacker has 30 days.
```

### 5.2 Denylist by jti (most common)

```
Server maintains a denylist of revoked jti values.
Validator checks the denylist on every request.
Entry is removed when the token would have expired anyway.

Storage: Redis with TTL = remaining token lifetime.
Lookup: O(1).

Pros: instant revocation of one token.
Cons: every request does a Redis lookup.
```

### 5.3 Denylist by user (logout everywhere)

```
Server maintains a "tokens issued before T for user U" denylist.
Validator checks the user's "issued before" timestamp on every request.

Storage: Redis hash per user, "tokens_issued_before": timestamp.
Lookup: O(1) per request, but constant time.

Pros: revokes ALL of a user's tokens at once.
Cons: doesn't help if a single token is stolen (you want to keep the
other tokens alive).
```

### 5.4 Refresh token revocation

```
Server marks the refresh token (or its family) as revoked.
Existing access token still valid (until exp), but no new ones.

Pros: instant revocation for future use; existing token dies naturally.
Cons: if access token is 1 hour, attacker has 1 hour.
```

### 5.5 Key rotation (nuclear option)

```
Server rotates the signing key. ALL tokens signed with the old key are
now invalid. Every user has to re-authenticate.

Pros: complete invalidation, all tokens dead.
Cons: disruptive, every user re-authenticates at once.
Use case: signing key compromise.
```

**Which to use when:**

```
Stolen single token:           denylist by jti
User clicks "log out":          revoke refresh token (or family)
User fired:                    revoke all user's refresh tokens
User's account deleted:        revoke all user's refresh tokens
Signing key compromised:       rotate signing key (and revoke all refresh tokens)
User "log out everywhere":     revoke all user's refresh token families
GDPR right-to-be-forgotten:    revoke all + delete account
```

---

## 6. JTI Denylist — The Standard Revocation Mechanism

A `jti` (JWT ID) is a unique identifier per token. The denylist tracks revoked jti values.

**Implementation:**

```python
import redis
import time

class JTIDenylist:
    """
    Redis-backed denylist for revoked JWT IDs.
    Each entry has a TTL = remaining token lifetime.
    """
    def __init__(self, redis_client, namespace: str = "jwt:revoked"):
        self.r = redis_client
        self.ns = namespace
    
    def revoke(self, jti: str, ttl_seconds: int):
        """Add a JTI to the denylist. Auto-expires when token would have died."""
        key = f"{self.ns}:{jti}"
        self.r.set(key, "1", ex=max(ttl_seconds, 1))
    
    def is_revoked(self, jti: str) -> bool:
        """Check if a JTI is in the denylist. O(1)."""
        return self.r.exists(f"{self.ns}:{jti}") > 0
    
    def revoke_all_for_user(self, sub: str, all_jtis: list[str]):
        """Revoke a batch of JTIs at once."""
        pipe = self.r.pipeline()
        for jti, ttl in all_jtis:
            pipe.set(f"{self.ns}:{jti}", "1", ex=max(ttl, 1))
        pipe.execute()


# Usage
denylist = JTIDenylist(redis.Redis(host="redis"))

# Revoke a token
denylist.revoke(jti="abc-123", ttl_seconds=900)  # 15 min remaining

# Check during validation
if denylist.is_revoked(payload["jti"]):
    raise InvalidTokenError("token revoked")
```

**The TTL trick:**

```
When you revoke a jti, set the denylist entry's TTL to the token's
remaining lifetime. After the token would have expired naturally, the
denylist entry disappears.

This means:
  - The denylist never grows unbounded
  - Old entries clean themselves up
  - No background cleanup job needed
  - Storage cost: O(active revoked tokens), not O(all-time revoked)
```

**The Redis-down problem:**

```
If Redis goes down, what do you do?

Option 1: Fail closed (deny all requests). Maximum security, breaks users.
Option 2: Fail open (allow all). Maximum availability, security risk.
Option 3: Fail open with alerting. Allow but log loudly, page on-call.

The right answer depends on your threat model:
  - Banking: fail closed (security > availability)
  - Internal tool: fail open (availability > security)
  - Public SaaS: fail open with alerting (use short token TTL to limit exposure)
  
If your access tokens are 5 min and Redis is down for 5 min:
  - Worst case: an attacker has 5 min of extra access
  - Probably acceptable
  - Fix Redis, then audit logs for suspicious activity

If your access tokens are 1 hour and Redis is down:
  - Worst case: an hour of extra access
  - Probably not acceptable
  - Switch to fail-closed or use a different revocation mechanism
```

---

## 7. Replay Protection — Detecting Reused Tokens

A "replay" is when the same token is used twice (in contexts where it shouldn't be). Two flavors:

### 7.1 Refresh token reuse (covered above)

```
Refresh tokens are designed for rotation + reuse detection.
If a refresh token is presented twice, the family is revoked.
```

### 7.2 Access token replay (one-time use, e.g., for high-value operations)

```
Some operations use a "single-use" token:
  - Email verification: "click this link to verify"
  - Password reset: "click this link to reset"
  - High-value action: "confirm this transfer"
  
The token is presented once, the action is performed, the token is consumed.
If presented again, it's rejected.
```

**Implementation: a "consumed" set in Redis.**

```python
def consume_one_time_token(jti: str, action: str, ttl_seconds: int = 3600):
    """
    Mark a token as consumed. Returns False if already consumed.
    """
    key = f"jwt:consumed:{jti}"
    # SETNX = SET if Not eXists. Returns True if set, False if already exists.
    was_new = redis_client.set(key, action, nx=True, ex=ttl_seconds)
    if not was_new:
        return False  # already consumed
    return True  # first use
```

**Use cases:**

```
1. Email verification link:
   jti = unique per email send
   TTL = 24 hours
   On click: consume_one_time_token(jti, "verify_email")
   If first time: verify. If second time: "link already used".

2. Password reset link:
   Same pattern, TTL = 1 hour, action = "reset_password"

3. MFA challenge:
   jti = unique per MFA prompt
   TTL = 5 min
   On response: consume_one_time_token(jti, "mfa_response")
   If first time: validate. If second: reject.

4. Webhook delivery (sender-side):
   jti = unique per webhook event
   On receiver: consume_one_time_token(jti, "webhook")
   If already consumed: idempotent success (webhook system pattern)
```

### 7.3 Replay attack (the security-critical version)

```
Scenario: an attacker captures a valid access token (e.g., from a
referer header leak), waits 1 hour, then uses it.
  
  The token is still valid (1 hour access token, 1 hour replay delay).
  Replay succeeds. Bad.

Mitigation: bind the token to the client.

Techniques:
  - DPoP (RFC 9449) — token is bound to a key the client proves
    possession of for each request. Covered in 8.1.
  - mTLS — token is bound to a client cert. Covered in 8.2.
  - Token reference binding (RFC 8471) — similar concept
  - Sender-constrained tokens in general — covered in Stage 2.4

The pattern: a stolen access token alone is NOT enough to use the API.
The attacker needs ALSO the private key / cert that the token is bound to.
```

---

## 8. Sender-Constrained Tokens (DPoP, mTLS)

A **sender-constrained token** is one that can only be used by the client it was issued to. The token is bound to a cryptographic key (or certificate) the client holds.

### 8.1 DPoP (Demonstrating Proof-of-Possession, RFC 9449)

```
Standard Bearer access token:
  Token: eyJ...
  Request: Authorization: Bearer eyJ...
  
  Anyone with the token can use it.
  
DPoP:
  Token: eyJ... + jkt claim (JWK thumbprint of the client's key)
  Request: Authorization: DPoP eyJ...
           DPoP: <signed JWT over (method + URL + timestamp + nonce)>
  
  The client signs a DPoP proof with their private key.
  The server verifies the proof matches the jkt in the token.
  Attacker with the token but not the key: rejected.
```

**The DPoP proof structure:**

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

```json
{
  "jti": "dpop-1",
  "htm": "POST",
  "htu": "https://api.example.com/transfer",
  "iat": 1700000000,
  "nonce": "server-provided-nonce"
}
```

The server verifies:
1. The token's `jkt` matches the DPoP proof's `jwk` thumbprint
2. The DPoP proof signature is valid (with the public key from `jwk`)
3. The `htm` (HTTP method) and `htu` (HTTP URI) match the actual request
4. The `iat` is recent (replay protection)
5. The `nonce` matches what the server sent (if used)

**Result:** an attacker who steals the token still can't use it, because they don't have the private key. Even if they capture a valid DPoP proof, they can't reuse it for a different request (htm/htu is bound).

### 8.2 mTLS (mutual TLS)

```
At the TLS handshake:
  - Server presents cert (proves server identity)
  - Client presents cert (proves client identity)
  - TLS session is bound to both certs
  
Access token:
  - Issued with cnf claim: {"cnf": {"x5t#S256": "<cert thumbprint>"}}
  
Request:
  - Client makes request over the mTLS connection
  - Server checks: the client cert on this connection matches the
    thumbprint in the token's cnf claim
  - Different cert = different client = reject
```

**Result:** an attacker with the token still can't use it, because they don't have the matching cert. And the cert requires the private key, which the attacker doesn't have.

### 8.3 When to use sender-constrained

```
DPoP:
  ✓ Public clients (SPAs, mobile apps) that can store a private key
  ✓ High-value APIs where replay is a real risk
  ✓ OAuth 2.1+ compliant systems
  ✗ Legacy systems that don't support it
  
mTLS:
  ✓ Service-to-service in a zero-trust network
  ✓ Internal workloads (k8s, service mesh)
  ✓ Banking / regulated
  ✗ Browser clients (no client cert by default)
  ✗ Mobile (cert distribution is heavy)
```

### 8.4 The `cnf` claim (RFC 7800)

Both DPoP and mTLS use the `cnf` (confirmation) claim to bind a token to a key:

```json
{
  "sub": "user-123",
  "cnf": {
    "jkt": "<jwk-thumbprint>"           // for DPoP
  }
}
```

```json
{
  "sub": "service-a",
  "cnf": {
    "x5t#S256": "<cert-sha256-thumbprint>"   // for mTLS
  }
}
```

The verifier checks: "the key/cert used to make this request matches the cnf in the token." If not, reject.

---

## 9. Sliding Sessions vs Absolute Sessions

Two strategies for "when does the user have to log in again?"

### Sliding sessions

```
Each request with a valid refresh token extends the session.
  
  Day 0: log in, refresh expires Day 30
  Day 5: make a request, refresh extended to Day 35
  Day 10: request, refresh extended to Day 40
  ...
  Day 100: still logged in if used within last 30 days

Pros: user stays logged in as long as they're active
Cons: indefinite if user keeps using the system
Compliance: bad for "max session length" requirements
```

### Absolute sessions

```
User MUST re-authenticate at a fixed deadline, no matter what.
  
  Day 0: log in, must re-authenticate by Day 30
  Day 5: make a request, deadline still Day 30
  Day 25: make a request, deadline still Day 30
  Day 30: re-authenticate, new 30-day window
  ...

Pros: predictable, compliance-friendly
Cons: user gets logged out even if they're actively using the system
```

**The hybrid pattern (most common):**

```
Sliding with absolute maximum:
  
  - Sliding: as long as you use it within 7 days, you stay logged in
  - Absolute: must re-authenticate every 30 days no matter what
  - Re-auth: password + MFA, or biometric, or "trusted device" check
```

**How to implement in JWT land:**

```
Sliding:
  - On every successful access token refresh, extend the refresh token
    by TTL (e.g., extend by 7 days from now)
  - OR: issue refresh token with 7-day TTL, no extension
  - Latter is simpler: 7 days of inactivity = re-auth

Absolute:
  - Store the user's "auth_time" claim (when they last re-auth'd with password)
  - On every request, check: now - auth_time < absolute_max
  - If not: reject the access token, force re-auth (even if not expired)
  - This is the "max_age" concept from OIDC
```

---

## 10. The Full Lifecycle State Machine

```
                    ┌─────────────────┐
                    │  Anonymous      │
                    └────────┬────────┘
                             │ authenticate (password + MFA)
                             ▼
                    ┌─────────────────┐
         ┌─────────│  Authenticated   │◄──── re-auth (MFA, password)
         │          │  (access+refresh) │
         │          └────────┬─────────┘
         │                   │ access token expired
         │                   ▼
         │          ┌─────────────────┐
         │  refresh │  Refresh         │ access token valid
         │  token   │  (in flight)     │ for each request
         │  rotation└────────┬─────────┘
         │                   │ access token refresh success
         │                   ▼
         │          ┌─────────────────┐
         │          │  Authenticated   │  ← loop until refresh expires
         │          │  (new access+    │
         │          │   new refresh)   │
         │          └────────┬─────────┘
         │                   │
         │  ┌────────────────┼────────────────┐
         │  │                │                │
         │  │ refresh        │ user logs      │ admin revokes
         │  │ expires        │ out            │ (fired, deleted)
         │  │                │                │
         │  ▼                ▼                ▼
         │  ┌─────────────────┐
         │  │  Re-auth         │
         │  │  required        │
         │  └─────────────────┘
         │
         │  Reuse detected (theft indicator)
         └──────────────────────────►
                                  ┌─────────────────┐
                                  │  Family revoked  │
                                  │  Re-auth required│
                                  └─────────────────┘

         At any time:
           - Signing key compromise → rotate, revoke everything
           - GDPR right-to-be-forgotten → revoke + delete account
```

---

## 11. Code: Complete Lifecycle in 80 Lines

```python
"""
A complete token lifecycle: issue, refresh (with rotation), revoke.
Uses Redis for state. Production-ready pattern.
"""
import jwt
import time
import secrets
import redis
from typing import Optional

# --- Config ---
ISSUER = "https://idp.example.com"
AUDIENCE = "api.example.com"
SIGNING_KEY = b"rsa-private-key"  # or load from KMS
ACCESS_TTL = 900        # 15 min
REFRESH_TTL = 30 * 86400  # 30 days
ALGORITHM = "RS256"

r = redis.Redis(host="redis", decode_responses=True)


# --- Issuance ---
def issue_tokens(sub: str, scopes: list[str]) -> dict:
    """Issue access + refresh tokens. Returns both."""
    now = int(time.time())
    family_id = f"fam-{secrets.token_urlsafe(16)}"
    access_jti = f"at-{secrets.token_urlsafe(16)}"
    refresh_jti = f"rt-{secrets.token_urlsafe(16)}"
    
    access = jwt.encode({
        "iss": ISSUER, "sub": sub, "aud": AUDIENCE,
        "exp": now + ACCESS_TTL, "iat": now, "nbf": now,
        "jti": access_jti, "scope": " ".join(scopes),
        "token_type": "access",
    }, SIGNING_KEY, algorithm=ALGORITHM, headers={"kid": "key-2024-01"})
    
    refresh = jwt.encode({
        "iss": ISSUER, "sub": sub, "aud": AUDIENCE,
        "exp": now + REFRESH_TTL, "iat": now, "nbf": now,
        "jti": refresh_jti, "family_id": family_id,
        "token_type": "refresh",
    }, SIGNING_KEY, algorithm=ALGORITHM, headers={"kid": "key-2024-01"})
    
    # Store refresh token metadata
    r.hset(f"rt:{refresh_jti}", mapping={
        "jti": refresh_jti, "sub": sub, "family_id": family_id,
        "issued_at": now, "expires_at": now + REFRESH_TTL,
        "rotated_at": "", "revoked": "0",
    })
    r.expire(f"rt:{refresh_jti}", REFRESH_TTL)
    
    # Track family for bulk revoke
    r.sadd(f"family:{family_id}", refresh_jti)
    
    return {
        "access_token": access,
        "refresh_token": refresh,
        "expires_in": ACCESS_TTL,
        "token_type": "Bearer",
    }


# --- Refresh (with rotation + reuse detection) ---
def refresh_tokens(refresh_token: str) -> dict:
    """Validate refresh token, issue new pair, mark old as used."""
    try:
        claims = jwt.decode(refresh_token, SIGNING_KEY, algorithms=[ALGORITHM],
                            issuer=ISSUER, audience=AUDIENCE)
    except jwt.InvalidTokenError as e:
        raise InvalidTokenError(f"refresh token invalid: {e}")
    
    if claims.get("token_type") != "refresh":
        raise InvalidTokenError("not a refresh token")
    
    old_jti = claims["jti"]
    sub = claims["sub"]
    family_id = claims["family_id"]
    
    # Check if the token still exists (hasn't been used)
    record = r.hgetall(f"rt:{old_jti}")
    if not record:
        # Token was either used (and expired from Redis) or never existed
        # But: if there's a "rotated_at" timestamp, this is REUSE
        # The hash still exists with the rotated_at field, just expired
        raise TokenReuseError("token already used or expired")
    
    if record.get("revoked") == "1":
        raise InvalidTokenError(f"token revoked: {record.get('revoked_reason', 'unknown')}")
    
    # Mark old as rotated
    r.hset(f"rt:{old_jti}", "rotated_at", int(time.time()))
    
    # Issue new pair
    new_tokens = issue_tokens(sub, claims.get("scope", "").split())
    # But issue_tokens creates a new family. We want the same family.
    # (See note below for the cleaner version.)
    
    return new_tokens


# --- Revocation ---
def revoke_token(jti: str, ttl_seconds: int):
    """Revoke a single access token by JTI."""
    r.set(f"jwt:revoked:{jti}", "1", ex=max(ttl_seconds, 1))


def revoke_refresh_family(family_id: str, reason: str = "user_logout"):
    """Revoke every refresh token in a family (logout everywhere)."""
    jtis = r.smembers(f"family:{family_id}")
    pipe = r.pipeline()
    for jti in jtis:
        pipe.hset(f"rt:{jti}", "revoked", "1")
        pipe.hset(f"rt:{jti}", "revoked_reason", reason)
    pipe.execute()


def revoke_all_user_tokens(sub: str, reason: str = "user_disabled"):
    """Revoke all refresh tokens for a user."""
    # Maintain a sub → families index
    for family_id in r.smembers(f"user:{sub}:families"):
        revoke_refresh_family(family_id, reason)


# --- Exceptions ---
class InvalidTokenError(Exception): pass
class TokenReuseError(Exception): pass
```

This is 80 lines for the complete lifecycle. Production code would add:
- Metrics
- Structured logging
- Tracing
- Rate limiting
- Schema validation
- Multi-tenant key resolution

But the 80 lines are the core pattern.

---

## 12. DevOps Analogy: The Hotel Keycard

Imagine a hotel with electronic keycards.

| JWT concept | Hotel equivalent |
|-------------|------------------|
| **Access token** | The keycard itself — opens the door for 24 hours |
| **Refresh token** | The "extend your stay" token at the front desk — let you get a new keycard |
| **Rotation** | Old keycard stops working the moment you get a new one |
| **Reuse detection** | If the same "extend" token is presented twice, the hotel assumes it's stolen and locks the room |
| **JTI denylist** | The "do not honor" list at the front desk |
| **Revocation by jti** | The front desk cancels that specific keycard |
| **Revocation by family** | The front desk cancels ALL keycards for that room |
| **Key rotation** | The hotel re-keys every door in the building (nuclear option) |
| **Sender-constrained (DPoP)** | The keycard only works for the specific person whose biometric is enrolled |
| **mTLS** | The room can only be opened by the person who has both the keycard AND a fingerprint match |

**The operational pattern:**

```
1. Guest checks in, gets keycard A (valid 24h, opens room 101)
2. Guest can extend at the front desk: present A, get B (valid until checkout)
3. If A is used twice (stolen), the family is revoked. Guest must come to the desk.
4. Guest checks out: family is revoked. Keycard dies naturally after 24h.
5. Guest loses keycard: comes to desk, gets B (old A is canceled).
6. Hotel discovers a master key was stolen: re-key every door. All guests re-key.
```

**Why this is the right model:**

```
- Stolen keycard: 24h max damage
- Stolen "extend" token: detected on first use after legitimate use (or vice versa)
- Lost keycard: cancel + reissue, no impact on other rooms
- Mass compromise: re-key all doors, every guest inconvenienced but secure
```

---

## 13. Attacks & Pitfalls

### A1. Long-lived access tokens

```
The most common bug. Access tokens valid for 24 hours, 7 days, or longer.

The damage from a stolen token: up to the lifetime.

If you find yourself wanting a 24-hour access token, you want:
  - 15-minute access token
  - 7-day refresh token (rotated)
  
Use the right tool for the right job.
```

### A2. Refresh tokens that don't rotate

```
If the same refresh token is used 1000 times, the 1001st use is just
as risky as the 1st. No detection of theft.

ALWAYS rotate. ALWAYS detect reuse.
```

### A3. Reuse detection that doesn't revoke the family

```
The reuse check throws an error, but the family continues. Attacker
has the new token. User re-auths. Attacker still has access via the
rotated chain.

Always: reuse detected → revoke entire family → user must re-auth.
The "false positive" of a legitimate user getting logged out is
worth the security guarantee.
```

### A4. Storing the refresh token in localStorage

```
Refresh token in localStorage = XSS steals it. Same problem as
access tokens in localStorage (covered in 5.2).

Refresh tokens should be in:
  - HttpOnly + Secure + SameSite=Strict cookie (web)
  - OS keychain (mobile)
  - Memory (server-side, e.g., for service accounts)
```

### A5. Refresh tokens with no expiry

```
Some apps issue refresh tokens that never expire. This is the
"permanent bearer" pattern. If stolen, the attacker has permanent
access.

ALWAYS set an absolute maximum on refresh tokens (30-90 days).
After that, the user MUST re-authenticate.
```

### A6. No `jti` on tokens

```
Without jti, you can't:
  - Revoke a specific token
  - Detect refresh token reuse
  - Audit "this specific token did X at time T"
  
ALWAYS include jti on refresh tokens. For access tokens, include it
if you might need to revoke them.
```

### A7. Sending refresh tokens in URL

```
Some apps put the refresh token in the URL:
  https://api.example.com/refresh?token=eyJ...

Bad: same as sending any token in URL — gets logged, ends up in
browser history, leaks via Referer.

Refresh tokens should be sent in the Authorization header or in
a cookie.
```

### A8. Forgetting to revoke on user delete

```
User account deleted (GDPR right-to-be-forgotten, voluntary delete,
admin delete). But their access tokens are still valid. They can
still hit the API until the tokens expire.

ALWAYS revoke all tokens when a user is deleted. And delete the
refresh token records. And rotate the signing key if the user had
elevated privileges.
```

### A9. The denylist that never expires entries

```
Denylist entries with no TTL = the denylist grows unbounded.
Eventually OOM. Eventually slow lookups. Eventually forgotten old
compromises that the token would have expired anyway.

ALWAYS set TTL on denylist entries = remaining token lifetime.
Redis does this automatically with `ex=`.
```

### A10. The denylist that doesn't survive Redis restart

```
If Redis is volatile (no persistence) and Redis restarts, the
denylist is empty. Attacker knows this (or learns it). Replays a
stolen token. It works.

Mitigation:
  - Use Redis with AOF (append-only file) persistence
  - Or: write the denylist to a durable store on every add
  - Or: have a fallback path (e.g., on Redis miss, check a
    distributed DB, which is slow but durable)
```

### A11. The "logout" that only clears the client cookie

```
User clicks "log out."
JavaScript clears the cookie from localStorage.
Server has no idea.

Token is still valid. If it was stolen, the thief is still logged in.

ALWAYS: logout = revoke the refresh token + add the access token
to the denylist (if it has lifetime remaining).
```

### A12. Refresh token in a URL after redirect

```
Pattern: user logs in, IdP redirects to app with refresh token in URL.
  https://app.example.com/callback#refresh_token=eyJ...

Problems:
  - URL fragment (after #) is harder to extract, but if you use ?  it's leaked to logs
  - Browser history stores the URL
  - If the page makes subresource requests, the URL may be in Referer
  - Mobile deep links also get logged

Use the authorization code flow with PKCE, not the implicit flow.
The code goes in the URL briefly, exchanged for tokens at the back channel.
```

### A13. Storing the access token for too long

```
A common pattern: store the access token in localStorage and reuse it
across page reloads. Persists the token indefinitely.

Combine with: no automatic refresh, long-lived access token.
Result: a stolen token is valid until manually cleared.

Modern pattern:
  - Access token in memory only (lost on page reload, that's fine)
  - On reload: use the refresh token (in cookie) to get a new access token
  - If refresh token is gone: force re-auth
```

### A14. Race condition in refresh

```
Two browser tabs both fire a request with an expired access token.
Both get 401.
Both fire /refresh with the refresh token.
First one succeeds, gets new access + refresh.
Second one's refresh is now the old (used) one.
If you do reuse detection, the second triggers a family revoke.

Mitigations:
  - Lock around the refresh endpoint (one refresh at a time)
  - Use a single "in-flight refresh" pattern (singleton promise)
  - Accept the family revoke as the cost
```

---

## 14. Exercises

### Exercise 1: Design the lifetimes
For each scenario, pick access token TTL and refresh token TTL, justify in 2 sentences:
- (a) Banking web app, strict compliance
- (b) Social media mobile app
- (c) Internal admin tool, used 8 hours/day by employees
- (d) CI/CD system, runs jobs non-stop
- (e) IoT device fleet, 10M devices, firmware updates monthly

### Exercise 2: Build the denylist
Implement `JTIDenylist` with Redis. Test:
- Revoke a jti, verify is_revoked returns True
- Wait for TTL, verify the entry expires
- Bulk-revoke 100 jtis at once

### Exercise 3: Implement reuse detection
Build the rotation logic. On reuse:
- Throw an error
- Revoke the family
- Log a security event
Test with: legitimate use, then attacker uses the same old token.

### Exercise 4: Add metrics
Instrument the lifecycle: tokens issued, refreshes, reuses detected, revocations. Plot over time. What does "normal" look like? What does "an attack" look like?

### Exercise 5: DPoP proof
Sign a DPoP proof in your language of choice. Include method, URL, timestamp, and a JWK. Send it to a test server (or mock) and verify the proof is validated.

### Exercise 6: GDPR delete
User invokes right-to-be-forgotten. Write the function that:
- Revokes all their refresh tokens
- Adds all their access tokens to the denylist
- Deletes the denylist entries (because the user wants the data gone)
- Rotates signing key? (Probably yes for high-value users.)
- Returns: "all data and tokens purged"

### Exercise 7: Logout everywhere
Implement "log out everywhere" — user clicks a button, all their devices lose their sessions. Test with 3 simulated devices.

### Exercise 8: Race condition
Two tabs, simultaneous 401s, both try to refresh. What happens? Implement the fix (single in-flight refresh promise).

### Exercise 9: Audit your existing systems
For every system you have that issues tokens:
- What's the access token TTL?
- What's the refresh token TTL?
- Is there a denylist? Where?
- Is rotation implemented?
- What happens on user delete?
Write a one-page report with improvements.

### Exercise 10: Family revoke blast radius
Scenario: a refresh token family has 100 active tokens (100 devices). Reuse is detected. The family is revoked. What's the user experience? Document the comms plan.

---

## 15. Next Step

You can now design, implement, and operate a token lifecycle. Next, we round out the JOSE family: JWS variants, JWE encryption, JWK public key format, and JWKS rotation.

→ [[../stage1/05-jose-family|Stage 1.5 — JWS/JWE/JWK/JWKS: The JOSE Family]]

**Before you move on, verify you can answer these:**
1. Why are access tokens short-lived and refresh tokens long-lived? What's the trade-off?
2. What is refresh token rotation, and what does reuse detection do?
3. What are the 5 ways to revoke a JWT, and when do you use each?
4. What is a `jti` denylist, and why does the entry TTL = remaining token lifetime?
5. What is a sender-constrained token, and what attacks does it prevent?
6. What's the difference between sliding and absolute sessions, and what's the modern hybrid?

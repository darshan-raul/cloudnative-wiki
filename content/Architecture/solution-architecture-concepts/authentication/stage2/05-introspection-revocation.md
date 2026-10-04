---
title: "2.5 — Token Introspection (RFC 7662) & Revocation (RFC 7009)"
author: darshan
tags:
  [
    authentication,
    stage-2,
    oauth,
    oauth2,
    introspection,
    revocation,
    rfc7662,
    rfc7009,
    tokens,
  ]
date: 2026-06-13
description: Deep dive into RFC 7662 Token Introspection and RFC 7009 Token Revocation — self-contained JWTs vs opaque reference tokens, real-time revocation semantics, cascading invalidation, and caching trade-offs
---

# 2.5 — Token Introspection (RFC 7662) & Revocation (RFC 7009)

> **Goal:** Master the trade-offs between self-contained tokens (JWT) and reference tokens (opaque), implement RFC 7662 introspection and RFC 7009 revocation, and build real-time revocation systems that scale without collapsing the authorization server.

> **Prerequisites:** [[01-oauth-fundamentals|Stage 2.1]] through [[04-token-lifecycles|Stage 2.4]]. You must understand access and refresh token mechanics.

---

## Table of Contents

1. [The Architectural Dilemma: Self-Contained vs Reference Tokens](#1-the-architectural-dilemma-self-contained-vs-reference-tokens)
2. [OAuth 2.0 Token Introspection (RFC 7662)](#2-oauth-20-token-introspection-rfc-7662)
3. [Introspection Request & Response Specification](#3-introspection-request--response-specification)
4. [Securing the Introspection Endpoint](#4-securing-the-introspection-endpoint)
5. [OAuth 2.0 Token Revocation (RFC 7009)](#5-oauth-20-token-revocation-rfc-7009)
6. [Cascading Revocation Architecture](#6-cascading-revocation-architecture)
7. [High-Performance Token Verification & Revocation Patterns](#7-high-performance-token-verification--revocation-patterns)
8. [Production Implementation: FastAPI & Python](#8-production-implementation-fastapi--python)
9. [Common Attacks & Failure Modes](#9-common-attacks--failure-modes)
10. [Exercises & Verification](#10-exercises--verification)
11. [Next Step](#11-next-step)

---

## 1. The Architectural Dilemma: Self-Contained vs Reference Tokens

In modern distributed systems, token design boils down to a fundamental architectural trade-off: **Network Latency vs Instant Revocability**.

```
Self-Contained (JWT):
  Client ─── Token (Signed JWT) ───> Resource Server (RS)
                                            │
                                            ▼
                                  Local Crypto Verification
                                  (0ms external I/O, fast)
  Trade-off: Cannot instantly revoke without centralized state.

Reference Token (Opaque):
  Client ─── Token (Random String) ─> Resource Server (RS)
                                            │
                                            ▼
                                    POST /introspect
                                            │
                                            ▼
                                  Authorization Server (AS)
                                  (Network round-trip per call)
  Trade-off: Instantly revocable, but puts heavy read traffic on AS.
```

### Comparative Breakdown

| Dimension              | Self-Contained Token (JWT)                    | Reference / Opaque Token                              | Hybrid Pattern (JWT + Revocation Bloom Filter)   |
| :--------------------- | :-------------------------------------------- | :---------------------------------------------------- | :----------------------------------------------- |
| **Payload Format**     | Base64URL-encoded JSON with signature         | High-entropy random string (e.g., 256-bit UUID / hex) | Short-lived signed JWT (`exp <= 5m`)             |
| **Verification Cost**  | CPU bound (RSA/ECDSA/EdDSA signature check)   | I/O bound (HTTP POST to AS or Redis query)            | CPU bound + fast in-memory blacklist lookup      |
| **Revocation Latency** | Eventual consistency (must wait until `exp`)  | Immediate (sub-millisecond at AS database)            | Instant for critical events, bounded by `exp`    |
| **Payload Leakage**    | Client & proxies can read claims (unless JWE) | Zero internal metadata exposed to client              | Claims exposed to client, sensitive data omitted |
| **AS Load**            | AS only touched during token issuance/refresh | AS (or shared cache) queried on every API call        | AS touched only during refresh                   |

---

## 2. OAuth 2.0 Token Introspection (RFC 7662)

RFC 7662 defines a standard protocol for resource servers to query the authorization server about the current active state and metadata of an incoming token.

### Core Motivation

1. **Opaque Tokens:** The resource server cannot parse an opaque string; it must ask the issuer who owns it and what scopes it holds.
2. **Contextual Metadata:** The AS can provide dynamic context (e.g., risk score, client IP restrictions, organizational tier).
3. **Revocation Check:** Even if the token is formatted as a JWT, the RS can use introspection to confirm the token has not been revoked prior to expiration.

---

## 3. Introspection Request & Response Specification

### The Request

The introspection endpoint is hosted on the Authorization Server (e.g., `https://auth.example.com/oauth/v2/introspect`).

```http
POST /oauth/v2/introspect HTTP/1.1
Host: auth.example.com
Authorization: Basic cnMtYXBpLWdhdGV3YXk6c2VjcmV0LXBhc3N3b3Jk
Content-Type: application/x-www-form-urlencoded

token=2YotnFZFEjr1zCsicMWpAA&token_type_hint=access_token
```

- `token` _(Required)_: The token string to inspect.
- `token_type_hint` _(Optional)_: `access_token` or `refresh_token`. Optimizes lookup in storage.

### The Response: Active Token

If the token is valid, unexpired, and not revoked:

```http
HTTP/1.1 200 OK
Content-Type: application/json;charset=UTF-8

{
  "active": true,
  "scope": "read:documents write:documents",
  "client_id": "billing-spa-client",
  "username": "darshan@example.com",
  "token_type": "Bearer",
  "exp": 1781350400,
  "iat": 1781346800,
  "nbf": 1781346800,
  "sub": "usr_99882211a",
  "aud": "https://api.example.com/v1/",
  "iss": "https://auth.example.com/",
  "jti": "b0f74136-1e64-4e31-893d-82dcf3519b78"
}
```

### The Response: Inactive Token

If the token is expired, revoked, invalid, or was issued to a different security boundary:

```http
HTTP/1.1 200 OK
Content-Type: application/json;charset=UTF-8

{
  "active": false
}
```

> [!IMPORTANT]
> RFC 7662 mandates that if the token is invalid, revoked, or expired, the AS **MUST** return HTTP 200 with `{"active": false}`. It must **never** return HTTP 404 or 401 for an invalid token to prevent oracle attacks and client enumeration.

---

## 4. Securing the Introspection Endpoint

The introspection endpoint exposes sensitive user and token metadata. It must be heavily protected:

1. **Mandatory RS Authentication:** Only authorized Resource Servers may call `/introspect`. Common methods:
   - HTTP Basic Auth (`client_id` + `client_secret` of the RS)
   - Mutual TLS (mTLS) with client certificate thumbprint validation
   - RS Private Key JWT (`client_assertion`)
2. **Audience Restriction:** An RS must only be permitted to introspect tokens where `aud` matches its own identifier. If Resource Server A inspects a token issued exclusively for Resource Server B, the AS must respond with `{"active": false}`.
3. **Rate Limiting & DoS Mitigation:** Introspection endpoints are vulnerable to DoS from rogue services or high inbound API volume.

---

## 5. OAuth 2.0 Token Revocation (RFC 7009)

RFC 7009 standardizes token invalidation. When a user logs out, closes a session, or uninstalls a client application, the client requests revocation.

### Revocation Flow

```http
POST /oauth/v2/revoke HTTP/1.1
Host: auth.example.com
Authorization: Basic Y2xpZW50LWlkOmNsaWVudC1zZWNyZXQ=
Content-Type: application/x-www-form-urlencoded

token=rF12vX5KxNqP9z0A&token_type_hint=refresh_token
```

### Revocation Rules Under RFC 7009

1. **HTTP Status 200 on Non-Existent Tokens:** If the token does not exist or was already revoked, the server **MUST** return HTTP 200 OK. Revocation is an idempotent operation.
2. **Unsupported Token Type:** If the AS cannot revoke the given type, it returns HTTP 400 with `unsupported_token_type`.
3. **Client Ownership:** The AS must verify that the client requesting revocation is the client to which the token was originally issued, preventing denial-of-service against legitimate user sessions.

---

## 6. Cascading Revocation Architecture

When a token is revoked, how does revocation propagate through dependent artifacts?

```mermaid
flowchart TD
    User([User clicks Logout]) --> Client[Client App]
    Client -->|POST /revoke refresh_token| AS[Authorization Server]

    subgraph Authorization Server
        AS --> RevokeRT[1. Mark Refresh Token as Revoked]
        RevokeRT --> CascadeAT[2. Invalidate all Access Tokens in Session]
        CascadeAT --> PublishEvent[3. Publish Revocation Event to Redis Pub/Sub]
    end

    PublishEvent --> RS1[API Gateway / RS1 Cache]
    PublishEvent --> RS2[Resource Server 2]

    RS1 --> InvalCache1[Evict Token from Local Cache]
    RS2 --> InvalCache2[Evict Token from Local Cache]
```

### Cascading Rules

- **Revoking a Refresh Token:** MUST immediately invalidate all active access tokens issued from that refresh token or session grant.
- **Revoking an Access Token:** Does NOT automatically invalidate the parent refresh token (allows a client to discard a single compromised or temporary bearer token while keeping the long-lived refresh grant intact).

---

## 7. High-Performance Token Verification & Revocation Patterns

Directly querying the AS on every single HTTP request destroys throughput and creates a single point of failure. Below are the three enterprise patterns used in production.

### Pattern A: Short-Lived JWT + Centralized Revocation Denylist (Redis)

- **Token:** JWT with 5-minute lifespan (`exp = now + 300s`).
- **Verification:** RS verifies signature and `exp` locally.
- **Revocation Check:** RS does an asynchronous, sub-millisecond check against Redis:
  ```bash
  # Check if token ID (jti) or user ID (sub) is blacklisted
  EXISTS "blacklist:jti:<jti>"
  GET "user:revoked_before:<sub_id>"
  ```
- If timestamp of token issuance `iat` < `user:revoked_before`, reject with HTTP 401.

### Pattern B: Introspection Caching with TTL

When using opaque tokens with RFC 7662:

1. RS queries `/introspect` on first token sight.
2. RS caches the response in local memory (LRU cache) or local Redis for `min(token.ttl, 60s)`.
3. If an emergency revocation occurs, the AS broadcasts an invalidation message over Kafka or Redis Pub/Sub to all RS nodes.

---

## 8. Production Implementation: FastAPI & Python

Here is a production-grade implementation of an RFC 7662-compliant introspection handler and an RS validation middleware.

### Authorization Server Introspection Handler

```python
from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter, Depends, Form, HTTPException, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials
import redis.asyncio as redis

router = APIRouter(prefix="/oauth/v2")
security = HTTPBasic()
r = redis.Redis(host="localhost", port=6379, decode_responses=True)

# Authorized Resource Server registry
AUTHORIZED_RESOURCE_SERVERS = {
    "rs-gateway": "super-secure-rs-password-889"
}

async def authenticate_resource_server(credentials: HTTPBasicCredentials = Depends(security)) -> str:
    expected_secret = AUTHORIZED_RESOURCE_SERVERS.get(credentials.username)
    if not expected_secret or expected_secret != credentials.password:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            headers={"WWW-Authenticate": "Basic"},
            detail="Invalid resource server credentials",
        )
    return credentials.username

@router.post("/introspect")
async def introspect_token(
    token: str = Form(...),
    token_type_hint: Optional[str] = Form(None),
    rs_id: str = Depends(authenticate_resource_server),
):
    # Lookup token record in store (Redis / Database)
    token_data = await r.hgetall(f"token:{token}")

    if not token_data:
        return {"active": False}

    # Check revocation status
    if token_data.get("revoked", "false") == "true":
        return {"active": False}

    # Check expiration
    exp = int(token_data.get("exp", 0))
    now = int(datetime.now(timezone.utc).timestamp())
    if now >= exp:
        return {"active": False}

    # Audience verification: RS can only inspect tokens for itself
    aud = token_data.get("aud", "")
    if rs_id not in aud.split():
        return {"active": False}

    return {
        "active": True,
        "scope": token_data.get("scope", ""),
        "client_id": token_data.get("client_id", ""),
        "sub": token_data.get("sub", ""),
        "exp": exp,
        "iat": int(token_data.get("iat", 0)),
        "token_type": "Bearer",
        "jti": token_data.get("jti", "")
    }
```

---

## 9. Common Attacks & Failure Modes

1. **Introspection Denial of Service:** An attacker sends 50,000 req/sec with random garbage tokens to your API gateway. If the gateway calls `/introspect` for every garbage token, the AS crashes.  
   _Mitigation:_ Use short-lived self-contained JWTs for external edge APIs, or rate-limit unauthenticated callers at the edge before introspection.
2. **Oracle & Information Leakage:** Returning HTTP 404 or specific error messages on `/introspect` allows attackers to probe whether a token exists.  
   _Mitigation:_ Always return HTTP 200 with `{"active": false}`.
3. **Audience Cross-Pollination:** Resource Server A inspects a token issued for high-security Resource Server B, extracting admin scopes and replaying calls.  
   _Mitigation:_ Strict audience validation inside the introspection handler.

---

## 10. Exercises & Verification

1. **Implement RFC 7009:** Add the `/oauth/v2/revoke` endpoint to the FastAPI example. Ensure that revoking an unknown token returns HTTP 200.
2. **Simulate Cascading Logout:** Write a script where revoking a `refresh_token` instantly blacklists all active `access_token` JTIs sharing the same session ID.
3. **Measure Latency:** Benchmark API Gateway throughput when introspecting synchronously over HTTP vs validating a signed JWT locally.

---

## 11. Next Step

Now that token introspection and revocation mechanics are clear, we examine how the industry learned from 12 years of OAuth 2.0 deployment mistakes and consolidated best practices into **OAuth 2.1**.

→ [[06-oauth-2-1|Stage 2.6 — OAuth 2.1: The Definitive Consolidation]]

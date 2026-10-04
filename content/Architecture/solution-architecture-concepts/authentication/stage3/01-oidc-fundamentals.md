---
title: "3.1 — OpenID Connect (OIDC) Fundamentals"
author: darshan
tags: [authentication, stage-3, oidc, openid, identity, jwt, id-token, tokens]
date: 2026-06-13
description: The identity layer on top of OAuth 2.0 — why OAuth is not authentication, ID tokens vs access tokens, the Relying Party and OpenID Provider model, and UserInfo endpoint architecture
---

# 3.1 — OpenID Connect (OIDC) Fundamentals

> **Goal:** Understand why using plain OAuth 2.0 for user authentication is dangerous (the "pseudo-authentication" trap), how OpenID Connect (OIDC) introduces an identity layer on top of OAuth 2.0, and how the ID Token differs from an Access Token.

> **Prerequisites:** [[../stage1/01-jwt-anatomy|Stage 1]] (JWT anatomy and validation) and [[../stage2/README|Stage 2]] (OAuth 2.0 fundamentals).

---

## Table of Contents

1. [The Pseudo-Authentication Vulnerability](#1-the-pseudo-authentication-vulnerability)
2. [What OIDC Adds to OAuth 2.0](#2-what-oidc-adds-to-oauth-20)
3. [The Three Tokens Compared](#3-the-three-tokens-compared)
4. [The OIDC Actors](#4-the-oidc-actors)
5. [Anatomy of an ID Token](#5-anatomy-of-an-id-token)
6. [The UserInfo Endpoint](#6-the-userinfo-endpoint)
7. [Step-by-Step ID Token Verification](#7-step-by-step-id-token-verification)
8. [Common Misconceptions & Gotchas](#8-common-misconceptions--gotchas)
9. [Exercises & Verification](#9-exercises--verification)
10. [Next Step](#10-next-step)

---

## 1. The Pseudo-Authentication Vulnerability

For years, developers tried to turn OAuth 2.0 into an authentication protocol by doing this:

1. Client sends user to Google to authorize access with scope `profile`.
2. Client receives an `access_token`.
3. Client calls `https://www.googleapis.com/oauth2/v1/userinfo` with the access token.
4. Google returns `{"id": "12345", "name": "Alice"}`.
5. Client says: _"Great! The user is Alice. Let's log Alice in!"_

### Why this is a catastrophic security vulnerability:

```mermaid
sequenceDiagram
    autonumber
    actor Attacker as Attacker
    participant RogueApp as Attacker's Malicious App
    participant Google as Identity Provider (OAuth AS)
    participant VictimApp as Target Service (e.g. Bank/Wiki)

    Attacker->>RogueApp: Log into Rogue App with Google
    RogueApp->>Google: OAuth 2.0 Flow
    Google-->>RogueApp: Returns valid Access Token (issued for Rogue App)
    Note over RogueApp,VictimApp: The Access Token is legitimate and valid for Google, but was issued to RogueApp!
    Attacker->>VictimApp: POST /login/oauth (Injects the Rogue App Access Token)
    VictimApp->>Google: GET /userinfo (Bearer <Attacker Token>)
    Google-->>VictimApp: Returns {"id": "attacker_id", "email": "victim@work.com"}
    Note over VictimApp: If VictimApp doesn't check audience, it logs the attacker in as victim!
```

**The fundamental flaws in OAuth-as-Authentication:**

1. **No Audience Binding:** An access token does not tell the client _who_ the token was issued to. A rogue app can trick another app into accepting an access token issued for the rogue app.
2. **No Context:** An access token does not tell the client _when_ or _how_ the user authenticated (password, MFA, biometric, or SSO session reuse).
3. **No Guarantee of Identity:** OAuth 2.0 is an authorization framework designed for resource delegation, not identity assertion.

---

## 2. What OIDC Adds to OAuth 2.0

**OpenID Connect 1.0 (OIDC)** is an identity layer built directly on top of the OAuth 2.0 framework. It standardizes:

- **The ID Token:** A signed JSON Web Token (JWT) issued directly to the client application asserting the user's identity.
- **The `openid` Scope:** Requesting `scope=openid` tells the Authorization Server to act as an OpenID Provider (OP) and issue an ID token alongside or instead of an access token.
- **Standardized Claims:** Universal user profile attributes (`sub`, `email`, `email_verified`, `name`, `locale`).
- **Discovery Document:** `/.well-known/openid-configuration` for automated endpoint and key discovery.
- **UserInfo Endpoint:** Standardized REST endpoint to fetch user profile attributes.

```
┌────────────────────────────────────────────────────────┐
│               OpenID Connect 1.0 (OIDC)                │
│  - ID Token (JWT)    - UserInfo Endpoint               │
│  - Standard Claims   - Discovery & Dynamic Registration│
├────────────────────────────────────────────────────────┤
│                      OAuth 2.0                         │
│  - Grants (Auth Code + PKCE, Client Credentials)       │
│  - Access Tokens & Refresh Tokens                      │
│  - Scopes & Resource Servers                           │
└────────────────────────────────────────────────────────┘
```

---

## 3. The Three Tokens Compared

In an OIDC transaction, up to three tokens can be issued:

| Attribute                     | ID Token                                      | Access Token                                  | Refresh Token                                      |
| :---------------------------- | :-------------------------------------------- | :-------------------------------------------- | :------------------------------------------------- |
| **Intended Audience (`aud`)** | **The Client Application** (Relying Party)    | **The Resource Server (API)**                 | **The Authorization Server**                       |
| **Primary Purpose**           | Prove the user authenticated and who they are | Authorize API calls on behalf of the user     | Obtain fresh access/ID tokens without user re-auth |
| **Format**                    | **Always a signed JWT**                       | Opaque string or JWT                          | Opaque string or signed JWT                        |
| **Should Client Inspect?**    | **YES** (Client decodes and validates claims) | **NO** (Client treats it as an opaque bearer) | **NO** (Client simply stores and presents it)      |
| **Typical Lifespan**          | Short to medium (5 min to 1 hour)             | Short (5 min to 15 min)                       | Long (days, weeks, or rolling)                     |
| **Transport**                 | Frontend callback / token response            | `Authorization: Bearer <token>` header to API | POST body to `/token` endpoint                     |

> [!CAUTION]
> **Golden Rule of OIDC:** Never send an ID Token to your backend API Gateway as an authorization token. The API Gateway is NOT the intended audience (`aud`) of an ID Token. Send the **Access Token** to APIs, and use the **ID Token** in the client UI.

---

## 4. The OIDC Actors

OIDC maps traditional OAuth 2.0 actors to identity-specific terminology:

```mermaid
graph LR
    User[End-User] <--> RP[Relying Party - RP<br/>Client Application]
    RP <--> OP[OpenID Provider - OP<br/>Identity Provider / IdP]
    RP --> RS[Resource Server - RS<br/>Protected API]

    style RP fill:#3b82f6,stroke:#1d4ed8,color:#fff
    style OP fill:#10b981,stroke:#047857,color:#fff
    style RS fill:#8b5cf6,stroke:#6d28d9,color:#fff
```

1. **End-User:** The human being being authenticated.
2. **Relying Party (RP):** The client application (SPA, mobile app, web app) that relies on the OpenID Provider for authentication assertions.
3. **OpenID Provider (OP):** The OAuth 2.0 Authorization Server capable of authenticating the End-User and issuing ID Tokens (e.g., Keycloak, Okta, Google Identity, Auth0).
4. **Resource Server (RS):** The API that requires an access token issued by the OP.

---

## 5. Anatomy of an ID Token

An ID Token is a standard signed JWT (RFC 7519) consisting of three base64url-encoded parts:

```
eyJhbGciOiJSUzI1NiIsImtpZCI6IjIwMjYtMDYtay0xIn0.
eyJpc3MiOiiaHR0cHM6Ly9hdXRoLmV4YW1wbGUuY29tLyIsInN1YiI6InVzcl84ODg3NzYiLCJhdWQiOiJteS13aWtpLWFwcCIsImV4cCI6MTc4MTM1MDQwMCwiaWF0IjoxNzgxMzQ2ODAwLCJub25jZSI6ImY3YTIwODQxOWIiLCJlbWFpbCI6ImRhcnNoYW5AZXhhbXBsZS5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZX0.
SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c...
```

### Decoded Header

```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "2026-06-k-1"
}
```

### Decoded Payload (Claims)

```json
{
  "iss": "https://auth.example.com/",
  "sub": "usr_888776",
  "aud": "my-wiki-app",
  "exp": 1781350400,
  "iat": 1781346800,
  "auth_time": 1781346790,
  "nonce": "f7a208419b",
  "name": "Darshan K",
  "email": "darshan@example.com",
  "email_verified": true
}
```

### Mandatory Claims in Every ID Token:

- `iss` _(Issuer Identifier)_: Exact URL of the OpenID Provider.
- `sub` _(Subject Identifier)_: Unique, persistent, and unchangeable identifier for the End-User.
- `aud` _(Audience)_: Must contain the `client_id` of the Relying Party.
- `exp` _(Expiration Time)_: Unix timestamp after which the token must be rejected.
- `iat` _(Issued At)_: Unix timestamp when the token was created.

---

## 6. The UserInfo Endpoint

While core claims (`sub`, `iss`, `aud`) are packaged into the ID Token, large or frequently changing profile data (such as address, phone number, picture, or organizational department) can bloat token size.

The **UserInfo Endpoint** is a protected resource on the OP that returns claims about the authenticated user when presented with a valid Access Token.

### Request:

```http
GET /protocol/openid-connect/userinfo HTTP/1.1
Host: auth.example.com
Authorization: Bearer 2YotnFZFEjr1zCsicMWpAA
```

### Response:

```json
{
  "sub": "usr_888776",
  "name": "Darshan K",
  "given_name": "Darshan",
  "family_name": "K",
  "preferred_username": "darshan",
  "email": "darshan@example.com",
  "email_verified": true,
  "zoneinfo": "Asia/Kolkata",
  "updated_at": 1781300000
}
```

---

## 7. Step-by-Step ID Token Verification

A Relying Party MUST validate the ID Token before trusting any user claims:

```mermaid
flowchart TD
    Start[Receive ID Token] --> Step1{1. Is JWT valid structure?}
    Step1 -- No --> Reject[Reject Token / Auth Failure]
    Step1 -- Yes --> Step2{2. Retrieve public key matching 'kid' from JWKS}
    Step2 -- Missing/Mismatch --> Reject
    Step2 -- Found --> Step3{3. Verify cryptographic signature}
    Step3 -- Invalid --> Reject
    Step3 -- Valid --> Step4{4. Does 'iss' match expected OP issuer?}
    Step4 -- No --> Reject
    Step4 -- Yes --> Step5{5. Does 'aud' contain my client_id?}
    Step5 -- No --> Reject
    Step5 -- Yes --> Step6{6. Is current time < 'exp'?}
    Step6 -- No --> Reject
    Step6 -- Yes --> Step7{7. If sent, does 'nonce' match session nonce?}
    Step7 -- No --> Reject
    Step7 -- Yes --> Accept[Accept User Identity & Establish Session]
```

### Critical Python Validation Example

```python
import jwt
from jwt import PyJWKClient

JWKS_URL = "https://auth.example.com/.well-known/jwks.json"
EXPECTED_ISSUER = "https://auth.example.com/"
CLIENT_ID = "my-wiki-app"

jwks_client = PyJWKClient(JWKS_URL)

def verify_id_token(id_token: str, expected_nonce: str) -> dict:
    signing_key = jwks_client.get_signing_key_from_jwt(id_token)

    claims = jwt.decode(
        id_token,
        signing_key.key,
        algorithms=["RS256", "ES256", "EdDSA"],
        audience=CLIENT_ID,
        issuer=EXPECTED_ISSUER,
        options={
            "require": ["exp", "iss", "aud", "sub", "iat"],
            "verify_exp": True,
            "verify_aud": True,
            "verify_iss": True,
        }
    )

    # Nonce verification to stop replay attacks
    token_nonce = claims.get("nonce")
    if not token_nonce or token_nonce != expected_nonce:
        raise ValueError("Invalid or mismatched nonce parameter")

    return claims
```

---

## 8. Common Misconceptions & Gotchas

1. **"The ID Token can be sent to APIs":** If your microservices accept ID Tokens, Service B can take the ID token it received and replay it against Service C, spoofing the user without authorization checks. APIs must accept Access Tokens intended for their specific `aud`.
2. **"Email is the primary key":** Users change their email addresses, companies reassign corporate emails, and domains expire. Never use `email` as the user's primary key in your database. Use `sub` (or `iss` + `sub`).
3. **"Skip signature check if received over HTTPS":** Even if the token was received directly over a TLS connection from the token endpoint, signature validation is mandatory to protect against internal proxy compromises and token tampering.

---

## 9. Exercises & Verification

1. **Inspect an ID Token:** Use `jwt.io` or the CLI to decode an ID token from Google or Keycloak. Identify `iss`, `sub`, `aud`, and `nonce`.
2. **Verify Audience Mismatch:** Modify the `CLIENT_ID` in the verification script to `another-client` and confirm that validation fails with `InvalidAudienceError`.
3. **Trace the UserInfo Call:** In your browser network inspector, observe an OIDC login flow. Note when `/token` is called vs when `/userinfo` is invoked.

---

## 10. Next Step

Now that the core principles and tokens of OIDC are understood, we examine the execution mechanics: the flows (Auth Code + PKCE, Hybrid, and the deprecated Implicit Flow) and response modes.

→ [[02-oidc-flows|Stage 3.2 — OIDC Flows: Authorization Code, Hybrid, and Implicit]]

---
title: "3.4 — Discovery & Dynamic Client Registration"
author: darshan
tags:
  [
    authentication,
    stage-3,
    oidc,
    discovery,
    well-known,
    dynamic-registration,
    rfc7591,
  ]
date: 2026-06-13
description: The self-describing identity fabric — OpenID Provider Configuration Discovery (/.well-known/openid-configuration), JWKS discovery, Dynamic Client Registration (RFC 7591), and Software Statements
---

# 3.4 — Discovery & Dynamic Client Registration

> **Goal:** Build applications that can onboard new Identity Providers dynamically without manual configuration or code deployments, and understand how clients register themselves automatically using RFC 7591.

> **Prerequisites:** [[01-oidc-fundamentals|Stage 3.1]] and [[03-claims-and-sub|Stage 3.3]].

---

## Table of Contents

1. [The Magic of Self-Describing Identity: OpenID Discovery](#1-the-magic-of-self-describing-identity-openid-discovery)
2. [The Discovery Document (`/.well-known/openid-configuration`)](#2-the-discovery-document-well-knownopenid-configuration)
3. [Strict Security Rules for Discovery Parsing](#3-strict-security-rules-for-discovery-parsing)
4. [JWKS URI Discovery & Key Caching Pipeline](#4-jwks-uri-discovery--key-caching-pipeline)
5. [Dynamic Client Registration (RFC 7591)](#5-dynamic-client-registration-rfc-7591)
6. [Software Statements: Cryptographic Trust for Registration](#6-software-statements-cryptographic-trust-for-registration)
7. [Client Metadata & Lifecycle Management](#7-client-metadata--lifecycle-management)
8. [Code: Complete Automated IdP Bootstrap in Python](#8-code-complete-automated-idp-bootstrap-in-python)
9. [Exercises & Verification](#9-exercises--verification)
10. [Next Step](#10-next-step)

---

## 1. The Magic of Self-Describing Identity: OpenID Discovery

Before OpenID Connect, integrating an enterprise SSO provider required tedious manual configuration: an administrator copied the authorization URL, token URL, logout URL, public certs, and supported algorithms into configuration files or database tables. When the IdP rotated certs or changed a hostname, services broke silently.

**OpenID Discovery** solves this by establishing a standardized well-known metadata URL:

$$\text{Discovery URL} = \text{Issuer URL} + \text{/.well-known/openid-configuration}$$

Given only the base URL of an IdP (e.g. `https://accounts.google.com` or `https://auth.company.com/realms/prod`), an application can fetch the entire protocol schema, cryptographic endpoints, and supported features in a single HTTP request.

---

## 2. The Discovery Document (`/.well-known/openid-configuration`)

### Sample OpenID Provider Metadata Response:

```json
{
  "issuer": "https://auth.company.com/realms/prod",
  "authorization_endpoint": "https://auth.company.com/realms/prod/protocol/openid-connect/auth",
  "token_endpoint": "https://auth.company.com/realms/prod/protocol/openid-connect/token",
  "userinfo_endpoint": "https://auth.company.com/realms/prod/protocol/openid-connect/userinfo",
  "end_session_endpoint": "https://auth.company.com/realms/prod/protocol/openid-connect/logout",
  "jwks_uri": "https://auth.company.com/realms/prod/protocol/openid-connect/certs",
  "registration_endpoint": "https://auth.company.com/realms/prod/clients-registrations/openid-connect",
  "scopes_supported": ["openid", "profile", "email", "offline_access", "roles"],
  "response_types_supported": [
    "code",
    "none",
    "id_token",
    "token",
    "id_token token",
    "code id_token"
  ],
  "response_modes_supported": ["query", "fragment", "form_post"],
  "grant_types_supported": [
    "authorization_code",
    "refresh_token",
    "client_credentials"
  ],
  "id_token_signing_alg_values_supported": ["RS256", "ES256", "EdDSA"],
  "token_endpoint_auth_methods_supported": [
    "client_secret_basic",
    "client_secret_post",
    "private_key_jwt"
  ],
  "code_challenge_methods_supported": ["S256"]
}
```

### Key Fields Breakdown:

- `issuer` _(Mandatory)_: The exact URL identifying the OpenID Provider.
- `jwks_uri` _(Mandatory)_: URL where the client can retrieve the OP's JSON Web Key Set (JWKS) to verify signatures.
- `authorization_endpoint` _(Mandatory)_: Where user interactive login begins.
- `token_endpoint` _(Mandatory)_: Where authorization codes and refresh tokens are exchanged.
- `code_challenge_methods_supported`: Must include `S256` for OAuth 2.1 compliance.
- `token_endpoint_auth_methods_supported`: Tells the client how it can authenticate (e.g. `private_key_jwt` for mutual cryptographic proof).

---

## 3. Strict Security Rules for Discovery Parsing

Attackers frequently attempt **Server-Side Request Forgery (SSRF)** and **Issuer Spoofing** via metadata discovery. You must enforce these rules:

1. **Exact Issuer Match Rule:** The `issuer` value inside the JSON document **MUST match exactly** the base URL used to construct the discovery request.
   - If you queried `https://auth.example.com/.well-known/openid-configuration`, and the JSON returns `"issuer": "https://evil.com/"`, **abort immediately**.
2. **HTTPS Enforcement:** The discovery URL, `jwks_uri`, and all token endpoints **MUST** use the `https://` scheme (except `localhost` strictly in development).
3. **No Dynamic Open Redirects:** Never allow unauthenticated users to provide an arbitrary discovery URL that your server blindly fetches (prevents internal network port scanning and cloud metadata SSRF).

---

## 4. JWKS URI Discovery & Key Caching Pipeline

The `jwks_uri` points to the public keys used to sign ID tokens. Key retrieval must be performant and resilient:

```mermaid
flowchart TD
    Req[Incoming ID Token with 'kid'] --> Cache{Key in In-Memory Cache?}
    Cache -- Yes --> Verify[Verify Signature]
    Cache -- No --> Throttle{Fetched JWKS in last 60s?}
    Throttle -- Yes (Rate-limited) --> Fail[Reject Token / Do not overload IdP]
    Throttle -- No --> Fetch[HTTP GET to jwks_uri]
    Fetch --> UpdateCache[Update In-Memory Cache with TTL]
    UpdateCache --> Verify
```

- **Cache TTL:** Cache JWKS for at least 1 to 24 hours.
- **Cache-Busting on Unknown `kid`:** If an incoming token has a `kid` not in your cache (indicating a key rotation occurred), fetch the latest JWKS, but rate-limit refetches to at most once per 60 seconds to avoid DoS attacks using spoofed `kid` values.

---

## 5. Dynamic Client Registration (RFC 7591)

In large-scale environments (such as mobile app fleets, IoT devices, or open banking ecosystems), registering every client manually is impossible.

**RFC 7591 Dynamic Client Registration** allows a client to register itself with the Authorization Server programmatically.

### Registration Request:

```http
POST /clients-registrations/openid-connect HTTP/1.1
Host: auth.company.com
Authorization: Bearer INITIAL_ACCESS_TOKEN_XYZ
Content-Type: application/json

{
  "client_name": "Mobile Banking Client 2.0",
  "redirect_uris": [
    "com.bank.app:/oauth2redirect"
  ],
  "grant_types": ["authorization_code", "refresh_token"],
  "response_types": ["code"],
  "token_endpoint_auth_method": "none",
  "application_type": "native"
}
```

### Registration Response:

```http
HTTP/1.1 201 Created
Content-Type: application/json

{
  "client_id": "client_98a72b0c",
  "client_id_issued_at": 1781346800,
  "client_name": "Mobile Banking Client 2.0",
  "redirect_uris": ["com.bank.app:/oauth2redirect"],
  "grant_types": ["authorization_code", "refresh_token"],
  "registration_client_uri": "https://auth.company.com/clients/client_98a72b0c",
  "registration_access_token": "reg_token_9918231"
}
```

---

## 6. Software Statements: Cryptographic Trust for Registration

If anyone can call `/register`, an attacker could spam the AS with millions of dummy clients.

To prevent this, the AS can require a **Software Statement** (RFC 7591 Section 2.3) — a digitally signed JWT issued by a central authority certifying that this client software is authorized:

```json
{
  "software_statement": "eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiJodHRwczovL2FwcHN0b3JlLmNvbSIsImFwcF9pZCI6ImNvbS5iYW5rLmFwcCIsInZlcnNpb24iOiIyLjAifQ..."
}
```

The AS validates the software statement's signature before creating the `client_id`.

---

## 7. Client Metadata & Lifecycle Management

Dynamic clients receive a `registration_client_uri` and a `registration_access_token`. This allows the client to update its configuration or de-register itself:

- **Update Client (`PUT /clients/{client_id}`):** Add a new redirect URI or rotate public keys.
- **Delete Client (`DELETE /clients/{client_id}`):** De-register upon app uninstallation.

---

## 8. Code: Complete Automated IdP Bootstrap in Python

```python
import httpx
from urllib.parse import urljoin

class OIDCProviderClient:
    def __init__(self, issuer_url: str):
        self.issuer_url = issuer_url.rstrip("/")
        self.config = {}
        self.jwks = {}

    async def discover(self):
        well_known_url = f"{self.issuer_url}/.well-known/openid-configuration"
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(well_known_url)
            resp.raise_for_status()
            data = resp.json()

            # Security Rule 1: Issuer Match
            if data.get("issuer") != self.issuer_url:
                raise ValueError(
                    f"Discovery issuer mismatch! Expected {self.issuer_url}, got {data.get('issuer')}"
                )

            # Security Rule 2: HTTPS enforcement
            jwks_uri = data.get("jwks_uri")
            if not jwks_uri or not jwks_uri.startswith("https://"):
                raise ValueError("JWKS URI must use HTTPS")

            self.config = data

            # Fetch Initial JWKS
            jwks_resp = await client.get(jwks_uri)
            jwks_resp.raise_for_status()
            self.jwks = jwks_resp.json()

    @property
    def authorization_endpoint(self) -> str:
        return self.config["authorization_endpoint"]

    @property
    def token_endpoint(self) -> str:
        return self.config["token_endpoint"]

    @property
    def jwks_uri(self) -> str:
        return self.config["jwks_uri"]
```

---

## 9. Exercises & Verification

1. **Inspect Live OpenID Providers:** Run `curl -s https://accounts.google.com/.well-known/openid-configuration | jq .` and examine the supported signing algorithms and claims.
2. **Issuer Mismatch Trap:** Write a test that intercepts the discovery response, modifies `"issuer"`, and verifies that your client refuses to initialize.
3. **Register Dynamic Client:** If you have Keycloak running locally, enable client registration and register a new client using `curl`.

---

## 10. Next Step

With discovery and dynamic registration in place, we tackle one of the most operationally challenging areas of identity: coordinating logout and session termination across distributed systems.

→ [[05-session-logout|Stage 3.5 — Session Management & Logout: Front-Channel, Back-Channel, and RP-Initiated]]

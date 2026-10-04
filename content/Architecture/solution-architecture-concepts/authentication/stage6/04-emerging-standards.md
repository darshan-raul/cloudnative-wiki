---
title: "6.4 — Emerging Standards: DPoP, PAR, RAR, FAPI 2.0, and OID4VCI"
author: darshan
tags:
  [
    authentication,
    stage-6,
    standards,
    dpop,
    par,
    rar,
    fapi,
    oid4vci,
    passkeys,
    webauthn,
  ]
date: 2026-06-13
description: The next 5 years of identity engineering — DPoP (RFC 9449), Pushed Authorization Requests (RFC 9126), Rich Authorization Requests (RFC 9396), FAPI 2.0, and OpenID for Verifiable Credentials
---

# 6.4 — Emerging Standards: DPoP, PAR, RAR, FAPI 2.0, and OID4VCI

> **Goal:** Anticipate and adopt the next wave of identity specifications. Understand how DPoP replaces Bearer tokens, how PAR and RAR eliminate URL parameter tampering and coarse scopes, and how FAPI 2.0 and Verifiable Credentials (OID4VCI) shape modern enterprise and banking identity.

> **Prerequisites:** Stages 1 through 5 complete.

---

## Table of Contents

1. [The Frontiers of Identity Standards](#1-the-frontiers-of-identity-standards)
2. [DPoP: Demonstrating Proof-of-Possession (RFC 9449)](#2-dpop-demonstrating-proof-of-possession-rfc-9449)
3. [PAR: Pushed Authorization Requests (RFC 9126)](#3-par-pushed-authorization-requests-rfc-9126)
4. [RAR: Rich Authorization Requests (RFC 9396)](#4-rar-rich-authorization-requests-rfc-9396)
5. [FAPI 2.0: The Financial-Grade API Profile](#5-fapi-20-the-financial-grade-api-profile)
6. [OID4VCI & OID4VP: Decentralized Identity & Digital Wallets](#6-oid4vci--oid4vp-decentralized-identity--digital-wallets)
7. [Passkeys & WebAuthn: The Passwordless End-State](#7-passkeys--webauthn-the-passwordless-end-state)
8. [The 2026-2030 Architecture Roadmap](#8-the-2026-2030-architecture-roadmap)
9. [Exercises & Verification](#9-exercises--verification)
10. [Next Step](#10-next-step)

---

## 1. The Frontiers of Identity Standards

The core specifications of OAuth 2.0 (RFC 6749) and OpenID Connect 1.0 were finalized over a decade ago. While battle-tested, modern high-security domains (banking, healthcare, government, and zero-trust edge environments) demand cryptographic guarantees that legacy OAuth cannot provide:

```
Legacy Limitations:                    Modern Emerging Standard:
- Bearer tokens stolen & replayed  ──> DPoP (RFC 9449) Sender-Constraining
- Long query strings in browser    ──> PAR (RFC 9126) Pushed Auth Requests
- Coarse strings ("scope=write")   ──> RAR (RFC 9396) Rich Authorization Requests
- Ambiguous security profiles      ──> FAPI 2.0 Security Profile
- Centralized user tracking        ──> OID4VCI / OID4VP Verifiable Credentials
```

---

## 2. DPoP: Demonstrating Proof-of-Possession (RFC 9449)

In standard OAuth, access tokens are **Bearer tokens**: whoever holds the token string can use it, even if they stole it.

**DPoP (RFC 9449)** binds the access token to an asymmetric cryptographic key pair held in the client's memory or browser WebCrypto sandbox:

```mermaid
sequenceDiagram
    autonumber
    actor Client as Client App
    participant AS as Authorization Server
    participant RS as Resource Server (API)

    Note over Client: Generates local ECDSA key pair (P-256)<br/>Creates DPoP proof JWT signed by private key
    Client->>AS: POST /token + DPoP: <Proof JWT>
    Note over AS: Binds token to client's public key (jkt claim)
    AS-->>Client: 200 OK { access_token, token_type: "DPoP" }

    Note over Client: Generates new DPoP proof for target API call:<br/>htm=GET, htu=https://api.com/v1/data
    Client->>RS: GET /v1/data<br/>Authorization: DPoP <access_token><br/>DPoP: <Proof JWT>
    Note over RS: Verifies token thumbprint matches DPoP proof public key!<br/>Verifies HTTP method & URI match request!
    RS-->>Client: 200 OK Protected Data
```

If an attacker intercepts or steals the `access_token` string, **it is completely useless** because the attacker does not possess the client's private key required to generate the per-request DPoP proof!

---

## 3. PAR: Pushed Authorization Requests (RFC 9126)

In standard OAuth, initiating a login involves redirecting the browser with a massive query string:

```
GET /authorize?response_type=code&client_id=123&redirect_uri=...&scope=...&code_challenge=...&state=...
```

### The Problems with Query Strings:

- Browsers and proxies truncate URLs longer than 2,048 characters.
- Query parameters leak into browser history, web server logs, and HTTP Referer headers.
- Attackers can tamper with query parameters in transit.

### The PAR Solution:

The client pushes the authorization parameters directly to the AS via a secure back-channel HTTP POST before redirecting:

```http
POST /as/par HTTP/1.1
Host: auth.example.com
Authorization: Basic Y2xpZW50X2lkOmNsaWVudF9zZWNyZXQ=
Content-Type: application/x-www-form-urlencoded

response_type=code&redirect_uri=https%3A%2F%2Fapp.com%2Fcb&scope=openid+profile&code_challenge=xyz...
```

The AS validates parameters immediately, stores them in memory, and returns a short-lived URI:

```json
{
  "request_uri": "urn:ietf:params:oauth:request_uri:6b04f7c1-8899",
  "expires_in": 90
}
```

The client then redirects the browser with only the reference:

```http
GET /authorize?client_id=123&request_uri=urn:ietf:params:oauth:request_uri:6b04f7c1-8899 HTTP/1.1
```

---

## 4. RAR: Rich Authorization Requests (RFC 9396)

OAuth scopes are flat strings (e.g. `scope=read:accounts`). But what if a banking app needs authorization to transfer exactly **$4,500.00 USD to IBAN DE89370400440532013000**?

**Rich Authorization Requests (RAR - RFC 9396)** standardizes complex, structured JSON authorization requests via the `authorization_details` parameter:

```json
{
  "authorization_details": [
    {
      "type": "payment_initiation",
      "instructed_amount": {
        "currency": "EUR",
        "amount": "1250.00"
      },
      "creditor_account": {
        "iban": "DE89370400440532013000"
      },
      "remittance_information": "Invoice #88392"
    }
  ]
}
```

The Authorization Server presents this exact transaction detail to the user during consent, and binds the authorized payment details directly to the issued access token.

---

## 5. FAPI 2.0: The Financial-Grade API Profile

The **OpenID Foundation FAPI 2.0 Security Profile** is the international benchmark for high-risk, regulated industries (Open Banking UK, Open Insurance Brazil, US Consumer Financial Protection Bureau, Healthcare).

### FAPI 2.0 Non-Negotiable Mandates:

- **Mandatory PKCE:** `code_challenge_method=S256` for all clients.
- **Mandatory PAR:** Direct query string authorization is forbidden.
- **Sender-Constrained Tokens:** Bearer tokens are prohibited; clients **MUST** use either **mTLS (RFC 8705)** or **DPoP (RFC 9449)**.
- **Cryptographic Algorithms:** RS256 is deprecated in favor of **ES256, EdDSA, or PS256**.
- **No Implicit Grants:** All tokens must be delivered via back-channel code exchange.

---

## 6. OID4VCI & OID4VP: Decentralized Identity & Digital Wallets

The identity paradigm is shifting from centralized Identity Providers towards **Decentralized Verifiable Credentials (VCs)** stored in user-controlled digital identity wallets (e.g., Apple Wallet, EU Digital Identity Wallet):

- **OID4VCI (OpenID for Verifiable Credential Issuance):** Protocol enabling an Issuer (e.g. a University or Government DMV) to issue a cryptographically signed digital diploma or driver's license to a user's wallet app using standard OAuth flows.
- **OID4VP (OpenID for Verifiable Presentations):** Protocol enabling a Verifier (e.g. an Airport or Bank) to request proof of age or employment from the user's wallet without contacting the original government issuer, preserving privacy and eliminating cross-site tracking.

---

## 7. Passkeys & WebAuthn: The Passwordless End-State

Shared secrets (passwords) are the root cause of 80% of data breaches. **Passkeys (FIDO2 / WebAuthn)** replace passwords with public-key cryptography:

- The user authenticates using on-device biometrics (Touch ID, Face ID, Windows Hello).
- The device generates an asymmetric key pair and registers the public key with the Relying Party.
- Authentication uses a cryptographic challenge-response signed by the device's hardware Secure Enclave.
- **Phishing-Proof:** The browser cryptographically binds the challenge to the exact origin domain (`https://cloudnative.wiki`), making credential phishing impossible.

---

## 8. The 2026-2030 Architecture Roadmap

```
Phase 1 (Current Baseline):
  - OAuth 2.1 + OIDC + PKCE S256
  - HttpOnly SameSite=Strict Cookies / BFF
  - SPIFFE/SPIRE for Workload Identity

Phase 2 (Immediate Modernization):
  - Replace Bearer tokens with DPoP (RFC 9449)
  - Adopt PAR (RFC 9126) for all authorization endpoints
  - Enforce Passkeys/WebAuthn for all interactive user logins

Phase 3 (Frontier Compliance):
  - FAPI 2.0 Security Profile compliance
  - Support OID4VP digital wallet presentations
```

---

## 9. Exercises & Verification

1. **Inspect DPoP Proof:** Write a script using the `jose` library that generates a DPoP proof JWT with `htm="POST"` and `htu="https://auth.company.com/token"`. Verify that modifying the URI string breaks the proof.
2. **Execute PAR Call:** Use `curl` to POST authorization parameters to a Keycloak or Ory Hydra instance supporting PAR. Observe the returned `request_uri`.
3. **Audit FAPI 2.0 Readiness:** Run through your production identity stack against the FAPI 2.0 Security Profile checklist. Identify any remaining Bearer tokens or non-PAR flows.

---

## 10. Next Step

We have completed the entire theoretical and architectural curriculum (Stages 0 through 6). Now, it is time to build and verify everything in our **Capstone: Keycloak Reference Lab & Identity Incident Tabletop**.

→ [[../capstone/01-keycloak-lab|Capstone C.1 — Keycloak Reference Lab: Multi-Client, SSO, and JWKS Rotation]]

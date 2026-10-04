---
title: "3.3 — Claims & sub Discipline: Designing Resilient Identity Schemas"
author: darshan
tags: [authentication, stage-3, oidc, claims, sub, identity, multi-tenant, ppid]
date: 2026-06-13
description: The discipline of identity claims — standard OIDC claims, custom attributes, why the sub claim must be immutable and opaque, public vs pairwise identifiers (PPID), and multi-tenant schema design
---

# 3.3 — Claims & sub Discipline: Designing Resilient Identity Schemas

> **Goal:** Design user schemas and token claims that survive corporate mergers, email address changes, multi-tenant migrations, and strict privacy regulations. Learn why the `sub` claim is the single most critical field in your entire identity architecture.

> **Prerequisites:** [[01-oidc-fundamentals|Stage 3.1]] and [[02-oidc-flows|Stage 3.2]].

---

## Table of Contents

1. [The Cardinal Rule of the `sub` Claim](#1-the-cardinal-rule-of-the-sub-claim)
2. [Why `email` as a Primary Key Destroys Architectures](#2-why-email-as-a-primary-key-destroys-architectures)
3. [Standard OIDC Claims Taxonomy](#3-standard-oidc-claims-taxonomy)
4. [Public vs Pairwise Subject Identifiers (PPID)](#4-public-vs-pairwise-subject-identifiers-ppid)
5. [Custom Claims & Proper Namespacing](#5-custom-claims--proper-namespacing)
6. [Multi-Tenant Claims Architecture](#6-multi-tenant-claims-architecture)
7. [Token Size vs Claims Richness: The Thin Token Pattern](#7-token-size-vs-claims-richness-the-thin-token-pattern)
8. [Code: Defensive Claim Extraction & Mapping](#8-code-defensive-claim-extraction--mapping)
9. [Exercises & Verification](#9-exercises--verification)
10. [Next Step](#10-next-step)

---

## 1. The Cardinal Rule of the `sub` Claim

The **Subject Identifier (`sub`)** is the claim that uniquely identifies the human or machine principal who authenticated.

According to the OpenID Connect Core specification (Section 2):

> **`sub` (Subject Identifier):** A locally unique and never-reassigned identifier within the Issuer for the End-User, which is intended to be consumed by the Client. It MUST NOT exceed 255 ASCII characters. It is case-sensitive.

### The Four Invariants of a Production `sub`:

1. **Immutable:** Once assigned to a user, it can **never** change. If the user changes their legal name, email, phone number, gender, or username, `sub` remains unchanged.
2. **Never Reassigned:** If a user account is deleted, that exact `sub` string must **never** be recycled or assigned to a new user.
3. **Opaque:** A `sub` should contain zero semantic meaning (no embedded names, email fragments, or predictable sequences). Use a UUIDv4, UUIDv7, ULID, or cryptographically random 128-bit hex string.
4. **Scoped to Issuer:** Identity uniqueness is universally expressed as the tuple: `(iss, sub)`.

```
Good sub:
  "sub": "018f2d5e-4c8e-7320-b452-9b2f671c504a"
  "sub": "usr_99a8f27b1c4e"

Terrible sub:
  "sub": "alice@gmail.com"           <-- Mutable, leak of PII
  "sub": "john_doe"                  <-- Name change causes drift
  "sub": "1002"                      <-- Predictable IDOR vulnerability
```

---

## 2. Why `email` as a Primary Key Destroys Architectures

Almost every catastrophic identity migration in software engineering stems from treating `email` as the immutable primary key in a database.

```mermaid
graph TD
    User([User Alice Smith]) --> OldEmail[alice@startup.io]
    OldEmail --> AppDB[(Application Database<br/>PK = email)]

    Acquisition[Company Acquired by Megacorp] --> NewEmail[alice.smith@megacorp.com]
    NewEmail -.-> Conflict[Cannot update PK across 50 microservice databases!]

    DomainExpire[startup.io domain expires] --> Attacker[Attacker buys startup.io]
    Attacker --> Hijack[Registers alice@startup.io<br/>Takes over account via email reset!]

    style Conflict fill:#ef4444,stroke:#b91c1c,color:#fff
    style Hijack fill:#ef4444,stroke:#b91c1c,color:#fff
```

### The 5 Failure Modes of Email-as-Primary-Key:

1. **Legal & Name Changes:** People get married, divorced, or transition, changing their names and emails.
2. **Corporate Mergers & Rebranding:** Company domains change (`@google.com` vs `@alphabet.com`).
3. **Domain Expiration & Recycling:** When companies abandon old domains, attackers purchase them and claim all inbound email, taking over any system keyed by email.
4. **`email_verified` Neglect:** An OIDC token containing `"email": "ceo@victim.com"` is meaningless unless `"email_verified": true` is also checked! An attacker can create an unverified account on public IdPs with the victim's email.
5. **Aliasing & Plus Addressing:** `alice@gmail.com` and `alice+spam@gmail.com` are the same mailbox, but naive systems treat them as two different identities.

---

## 3. Standard OIDC Claims Taxonomy

OpenID Connect standardizes user profile claims so applications do not invent disparate schemas:

| Claim Name           | Type    | Description                                  | Privacy / Compliance Note            |
| :------------------- | :------ | :------------------------------------------- | :----------------------------------- |
| `sub`                | string  | Unique subject identifier                    | Mandatory in ID Token.               |
| `name`               | string  | Full display name (e.g. "Darshan K")         | PII. Subject to GDPR / CCPA.         |
| `given_name`         | string  | Given name / first name                      | PII.                                 |
| `family_name`        | string  | Surname / last name                          | PII.                                 |
| `preferred_username` | string  | Shorthand username (e.g. "darshan")          | Mutable.                             |
| `email`              | string  | Email address                                | Must check `email_verified`.         |
| `email_verified`     | boolean | True if identity provider verified ownership | **CRITICAL security check**.         |
| `picture`            | string  | URL pointing to user profile photo           | Potential SSRF / mixed-content risk. |
| `locale`             | string  | RFC 5646 language tag (e.g., `en-US`)        | Useful for UI localization.          |
| `updated_at`         | integer | Unix timestamp of profile last modification  | Cache invalidation trigger.          |

---

## 4. Public vs Pairwise Subject Identifiers (PPID)

In a standard OIDC setup, the OpenID Provider returns the same `sub` to every Relying Party. This is called a **Public Subject Identifier**.

### The Privacy Problem with Public `sub`:

If App A (a healthcare portal) and App B (an advertising tracker) both use Google as their OP, and both receive `sub = "usr_12345"`, they can correlate user activity across completely unrelated domains without the user's consent.

### Pairwise Pseudonymous Identifiers (PPID):

With pairwise identifiers, the OP calculates a mathematically distinct `sub` for each client (or client sector):

$$\text{sub}_{\text{client}} = \text{HMAC-SHA256}(\text{Sector Identifier} \parallel \text{Internal User ID}, \text{Master Secret})$$

```
Internal User ID: 994812

Client A (health.org)  receives sub: "4f7a9b1c-8821"
Client B (fitness.io)  receives sub: "e3d810aa-5519"
Client C (tracker.net) receives sub: "88ba7721-0012"
```

- Client A and Client B cannot correlate their databases to track the user.
- Apple's "Sign in with Apple" uses Pairwise Identifiers by default ("Hide My Email").

---

## 5. Custom Claims & Proper Namespacing

When your application requires domain-specific claims (such as subscription tiers, feature flags, or organizational roles), you must avoid collisions with existing or future OIDC standards.

### The RFC 7519 / OIDC Namespacing Rule:

Custom claims that are not defined in the IANA JSON Web Token Claims Registry **MUST** be namespaced using a collision-resistant URI or reverse-domain naming.

```json
{
  "iss": "https://auth.example.com/",
  "sub": "usr_998822",
  "aud": "cloud-wiki-client",

  // BAD: May collide with future OIDC RFCs
  "role": "admin",
  "org_id": "org_456",

  // GOOD: Namespaced via reverse-domain or HTTPS URI
  "https://cloudnative.wiki/claims/roles": ["editor", "billing_admin"],
  "https://cloudnative.wiki/claims/tenant_id": "tenant_enterprise_771",
  "https://cloudnative.wiki/claims/tier": "enterprise"
}
```

---

## 6. Multi-Tenant Claims Architecture

In multi-tenant B2B architectures, an employee may belong to multiple organizations or workspaces with different roles in each.

### Recommended Multi-Tenant Token Schema:

```json
{
  "iss": "https://auth.enterprise.com/",
  "sub": "usr_018f2d5e",
  "aud": "api-gateway",
  "https://myapp.com/current_tenant": {
    "id": "tenant_acme_corp",
    "name": "Acme Corporation",
    "roles": ["workspace_admin", "billing_contact"]
  },
  "https://myapp.com/available_tenants": [
    { "id": "tenant_acme_corp", "name": "Acme Corporation" },
    { "id": "tenant_beta_labs", "name": "Beta Labs" }
  ]
}
```

When switching tenants, the client requests a refreshed access token scoped to the selected target tenant ID.

---

## 7. Token Size vs Claims Richness: The Thin Token Pattern

Developers often fall into the trap of shoving large permission matrices, user groups, and settings into JWTs.

### The Problem:

- HTTP headers have strict size limits (nginx defaults to 8KB; AWS ALB defaults to 16KB).
- Exceeding header limits results in cryptic HTTP 431 (_Request Header Fields Too Large_) or HTTP 502 errors.
- Every API call incurs bandwidth overhead transmitting bloated tokens.

### The Solution: The "Thin Token" Pattern

- **Token Payload:** Keep it under 1KB. Include only `sub`, `tenant_id`, `scope`, and essential coarse-grained role tags (`role: ["admin"]`).
- **Detailed Permissions:** Fetch fine-grained permissions (e.g., individual button-level capabilities) inside the microservice or API Gateway using local in-memory caching or an Authorization Engine like Open Policy Agent (OPA) / Cerbos.

---

## 8. Code: Defensive Claim Extraction & Mapping

```python
from dataclasses import dataclass
from typing import List, Optional

@dataclass(frozen=True)
class AppUserIdentity:
    issuer: str
    subject_id: str
    email: Optional[str]
    is_email_verified: bool
    roles: List[str]
    tenant_id: str

def parse_and_validate_claims(claims: dict) -> AppUserIdentity:
    # 1. Enforce Mandatory Invariants
    iss = claims.get("iss")
    sub = claims.get("sub")
    if not iss or not sub:
        raise ValueError("Token missing mandatory 'iss' or 'sub' claim")

    # 2. Defensive Email Extraction
    email = claims.get("email")
    email_verified = claims.get("email_verified", False)

    # If email is present but not verified, treat as untrusted for account binding!
    trusted_email = email if (email and email_verified is True) else None

    # 3. Extract Namespaced Custom Claims
    ns = "https://cloudnative.wiki/claims/"
    roles = claims.get(f"{ns}roles", [])
    tenant_id = claims.get(f"{ns}tenant_id", "default")

    return AppUserIdentity(
        issuer=iss,
        subject_id=sub,
        email=trusted_email,
        is_email_verified=bool(email_verified),
        roles=roles,
        tenant_id=tenant_id
    )
```

---

## 9. Exercises & Verification

1. **Verify Email Verification Check:** Write a unit test that feeds a JWT with `"email": "admin@target.com"` and `"email_verified": false`. Ensure your system refuses to bind or grant administrative access.
2. **Calculate Pairwise Identifier:** Implement the HMAC-SHA256 calculation for pairwise identifiers given a sector identifier URI and confirm that different client domains produce uncorrelated hashes.
3. **Token Size Audit:** Measure the byte length of your application's JWT. Verify that the Authorization header does not exceed 2048 bytes.

---

## 10. Next Step

Now that claims and subject discipline are locked down, we examine how clients and servers discover endpoints and negotiate cryptographic keys automatically via **OpenID Discovery and Dynamic Client Registration**.

→ [[04-discovery-registration|Stage 3.4 — Discovery & Dynamic Client Registration]]

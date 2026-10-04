---
title: "4.3 — SCIM 2.0: Automated User Provisioning & Deprovisioning"
author: darshan
tags:
  [
    authentication,
    stage-4,
    scim,
    scim2,
    provisioning,
    deprovisioning,
    rfc7643,
    rfc7644,
    enterprise,
  ]
date: 2026-06-13
description: The System for Cross-domain Identity Management (SCIM 2.0) — RFC 7643 and RFC 7644, automated CRUD for /Users and /Groups, PATCH operations, and real-time deprovisioning
---

# 4.3 — SCIM 2.0: Automated User Provisioning & Deprovisioning

> **Goal:** Master SCIM 2.0 (RFC 7643 / RFC 7644), understand how enterprise IT directories automatically synchronize user and group lifecycles into your SaaS application, and implement a secure SCIM server that eliminates orphaned accounts through immediate deprovisioning.

> **Prerequisites:** [[01-sso-patterns|Stage 4.1]] (SSO and the JIT deprovisioning blindspot).

---

## Table of Contents

1. [The Provisioning Problem in Enterprise IT](#1-the-provisioning-problem-in-enterprise-it)
2. [What is SCIM 2.0?](#2-what-is-scim-20)
3. [The Core SCIM Endpoints](#3-the-core-scim-endpoints)
4. [The SCIM User Schema (`/Users`)](#4-the-scim-user-schema-users)
5. [The SCIM Group Schema (`/Groups`)](#5-the-scim-group-schema-groups)
6. [The Power of `PATCH`: Partial Updates & Suspensions](#6-the-power-of-patch-partial-updates--suspensions)
7. [The Offboarding Security Workflow (`active: false`)](#7-the-offboarding-security-workflow-active-false)
8. [Production SCIM Server Implementation (FastAPI)](#8-production-scim-server-implementation-fastapi)
9. [Common SCIM Pitfalls & Compliance Traps](#9-common-scim-pitfalls--compliance-traps)
10. [Exercises & Verification](#10-exercises--verification)
11. [Next Step](#11-next-step)

---

## 1. The Provisioning Problem in Enterprise IT

When an enterprise hires 200 employees a month, IT cannot manually create accounts across 50 internal and external tools. Conversely, when an employee leaves, IT must guarantee that access across **every single downstream system is terminated within minutes** to satisfy SOC 2, ISO 27001, and HIPAA compliance.

SSO handles _authentication_, but it does not proactively push changes when users are added, promoted, or terminated.

**Enter SCIM 2.0 (System for Cross-domain Identity Management).**

```
┌────────────────────────────────────────────────────────┐
│   Enterprise Identity Provider (SCIM Client)           │
│   (Okta, Microsoft Entra ID, PingFederate, JumpCloud)  │
└───────────────────────────┬────────────────────────────┘
                            │ RESTful HTTP Requests
                            │ (POST /Users, PATCH /Users, DELETE /Users)
┌───────────────────────────▼────────────────────────────┐
│      Your SaaS Application (SCIM Service Provider)     │
│   Creates, updates, and suspends accounts in real time │
└────────────────────────────────────────────────────────┘
```

---

## 2. What is SCIM 2.0?

Standardized by the IETF in RFC 7643 (Core Schema) and RFC 7644 (Protocol), SCIM 2.0 is an opinionated, RESTful JSON API designed specifically for managing identity resources.

### Core Standards:

- Content-Type: `application/scim+json`
- Uniform schemas for Users and Groups
- Standardized query filters, pagination, and attribute sorting
- High-efficiency partial modifications via HTTP `PATCH`

---

## 3. The Core SCIM Endpoints

A compliant SCIM Service Provider must implement:

| Endpoint                         | HTTP Methods                    | Description                                                                |
| :------------------------------- | :------------------------------ | :------------------------------------------------------------------------- |
| `/scim/v2/Users`                 | `GET`, `POST`                   | Query user directory, create new user accounts                             |
| `/scim/v2/Users/{id}`            | `GET`, `PUT`, `PATCH`, `DELETE` | Retrieve, overwrite, modify, or delete a user                              |
| `/scim/v2/Groups`                | `GET`, `POST`                   | List and create user groups / teams                                        |
| `/scim/v2/Groups/{id}`           | `GET`, `PUT`, `PATCH`, `DELETE` | Manage group membership                                                    |
| `/scim/v2/ServiceProviderConfig` | `GET`                           | Discovery endpoint reporting supported SCIM features (PATCH, bulk, filter) |
| `/scim/v2/Schemas`               | `GET`                           | Describes schema definitions supported by the service provider             |

---

## 4. The SCIM User Schema (`/Users`)

### Example: Creating a User (`POST /scim/v2/Users`)

```json
{
  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
  "userName": "darshan@company.com",
  "name": {
    "givenName": "Darshan",
    "familyName": "K",
    "formatted": "Darshan K"
  },
  "emails": [
    {
      "value": "darshan@company.com",
      "type": "work",
      "primary": true
    }
  ],
  "active": true,
  "externalId": "okta_usr_99881122",
  "title": "Principal Architect",
  "department": "Platform Engineering"
}
```

### Key Attributes:

- `userName` _(Required)_: Unique identifier used by the user to log in.
- `externalId` _(Recommended)_: The unique ID of the user in the enterprise IdP. Essential for mapping during identity migrations.
- `active` _(Required)_: Boolean flag controlling account enabled/disabled status.

---

## 5. The SCIM Group Schema (`/Groups`)

Groups represent organizational teams, departments, or role assignments:

```json
{
  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:Group"],
  "displayName": "Platform-Engineering",
  "members": [
    {
      "value": "usr_018f2d5e",
      "display": "Darshan K"
    }
  ]
}
```

When an employee changes departments in Workday, Okta sends a `PATCH` request to `/scim/v2/Groups/{id}` to automatically adjust their application permissions.

---

## 6. The Power of `PATCH`: Partial Updates & Suspensions

Instead of overwriting an entire user record with `PUT`, IdPs send granular `PATCH` operations:

```http
PATCH /scim/v2/Users/usr_018f2d5e HTTP/1.1
Host: api.saas.com
Authorization: Bearer scim_secret_token_889
Content-Type: application/scim+json

{
  "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
  "Operations": [
    {
      "op": "replace",
      "path": "title",
      "value": "VP of Architecture"
    },
    {
      "op": "replace",
      "path": "active",
      "value": false
    }
  ]
}
```

---

## 7. The Offboarding Security Workflow (`active: false`)

When an employee is terminated, corporate directories rarely delete the user immediately; instead, they set `"active": false`.

```mermaid
flowchart TD
    HR[HR enters termination in Workday] --> IdP[Okta / Entra marks user Suspended]
    IdP -->|PATCH /scim/v2/Users/{id} active=false| SCIM[Your SCIM Service Provider]

    subgraph SaaS Application Actions
        SCIM --> Step1[1. Mark user record: is_active = False]
        Step1 --> Step2[2. Immediately Revoke all active Access & Refresh Tokens]
        Step2 --> Step3[3. Invalidate local Redis application sessions]
        Step3 --> Step4[4. Deactivate all Personal Access Tokens & API Keys]
        Step4 --> Step5[5. Disconnect active WebSockets & SSO sessions]
    end
```

> [!CAUTION]
> If your SCIM handler updates `is_active = False` in PostgreSQL but forgets to revoke active access tokens in Redis, the terminated employee can continue accessing your APIs until the token expires!

---

## 8. Production SCIM Server Implementation (FastAPI)

```python
from fastapi import APIRouter, Header, HTTPException, status, Query
from pydantic import BaseModel, Field
from typing import List, Optional

router = APIRouter(prefix="/scim/v2")
SCIM_BEARER_TOKEN = "enterprise-tenant-secret-bearer-token"

def verify_scim_auth(authorization: str = Header(...)):
    if not authorization.startswith("Bearer ") or authorization[7:] != SCIM_BEARER_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized SCIM request"
        )

@router.get("/ServiceProviderConfig")
async def get_service_provider_config():
    return {
        "schemas": ["urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig"],
        "patch": {"supported": True},
        "bulk": {"supported": False, "maxOperations": 0, "maxPayloadSize": 0},
        "filter": {"supported": True, "maxResults": 100},
        "changePassword": {"supported": False},
        "sort": {"supported": False},
        "etag": {"supported": False},
        "authenticationSchemes": [
            {
                "name": "OAuth Bearer Token",
                "description": "Authentication using Bearer Token",
                "type": "oauthbearertoken"
            }
        ]
    }

@router.patch("/Users/{user_id}")
async def patch_scim_user(user_id: str, patch_doc: dict, auth: None = Depends(verify_scim_auth)):
    operations = patch_doc.get("Operations", [])
    for op in operations:
        action = op.get("op", "").lower()
        path = op.get("path")
        value = op.get("value")

        if action == "replace" and path == "active":
            is_active = bool(value)
            if not is_active:
                # Security Hook: Invalidate user immediately!
                await terminate_all_user_sessions(user_id)
                await revoke_all_user_tokens(user_id)

    return {"schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"], "id": user_id, "active": False}
```

---

## 9. Common SCIM Pitfalls & Compliance Traps

1. **Failure to Implement Filtering:** IdPs query `GET /scim/v2/Users?filter=userName eq "alice@example.com"` before creating a user. If your SCIM endpoint returns HTTP 501 or ignores the query filter, user provisioning breaks.
2. **Missing `startIndex` (1-Indexed):** SCIM pagination is 1-indexed (`startIndex=1`), unlike standard APIs which are 0-indexed. Returning 0 items when `startIndex=1` confuses Okta.
3. **Hard Deletes vs Soft Deletes:** Enterprise customers expect auditability. Never hard-delete records on `DELETE /Users/{id}`. Perform a soft-delete and preserve audit logs.

---

## 10. Exercises & Verification

1. **Inspect SCIM Discovery:** Run `curl -H "Accept: application/scim+json" http://localhost:8000/scim/v2/ServiceProviderConfig` and verify all required keys exist.
2. **Test User Suspension:** Issue a `PATCH` request setting `active: false`. Verify that the targeted user's active session cookie is immediately rejected on subsequent requests.
3. **Pagination Test:** Create 10 dummy SCIM users and execute query requests using `startIndex=1&count=5` and `startIndex=6&count=5`. Confirm no duplicate users are returned.

---

## 11. Next Step

Now that user provisioning and enterprise SSO are clear, we examine how to architect applications that serve millions of consumer accounts alongside thousands of corporate enterprise tenants without code branching.

→ [[04-multi-tenant-b2b-b2c|Stage 4.4 — Multi-Tenant Identity Architecture: B2B vs B2C Patterns]]

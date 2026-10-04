---
title: "Capstone C.1 — Keycloak Reference Lab: Multi-Client, SSO, and JWKS Rotation"
author: darshan
tags:
  [
    authentication,
    capstone,
    keycloak,
    docker,
    oidc,
    oauth2,
    pkce,
    sso,
    saml,
    jwks,
  ]
date: 2026-06-13
description: The complete reproducible Keycloak reference lab — Docker Compose stack, OIDC Code+PKCE SPA, bearer API, client credentials CLI, SAML bridge, and live JWKS rotation drill
---

# Capstone C.1 — Keycloak Reference Lab: Multi-Client, SSO, and JWKS Rotation

> **Goal:** Deploy a fully functional, production-modeled Keycloak environment locally via Docker Compose, configure three distinct client types (SPA, API, and CLI), exercise Single Sign-On, and execute an automated zero-downtime JWKS key rotation drill.

> **Prerequisites:** Stages 0 through 6 complete.

---

## Table of Contents

1. [Lab Architecture Overview](#1-lab-architecture-overview)
2. [Docker Compose Stack: Keycloak + PostgreSQL](#2-docker-compose-stack-keycloak--postgresql)
3. [Automated Realm Provisioning (`realm-export.json`)](#3-automated-realm-provisioning-realm-exportjson)
4. [Client Configuration Breakdown](#4-client-configuration-breakdown)
5. [The Three Exercises](#5-the-three-exercises)
6. [JWKS Rotation Drill Execution](#6-jwks-rotation-drill-execution)
7. [Automated Test & Verification Suite](#7-automated-test--verification-suite)
8. [Tear Down & Cleanup](#8-tear-down--cleanup)
9. [Next Step](#9-next-step)

---

## 1. Lab Architecture Overview

This reference lab exercises the entire authentication stack across four distinct components:

```
                          ┌───────────────────────────┐
                          │   Keycloak Identity Hub   │
                          │   (Port 8080 / PostgreSQL)│
                          └─────────────┬─────────────┘
                                        │
        ┌───────────────────────────────┼───────────────────────────────┐
        │                               │                               │
 ┌──────▼──────┐                 ┌──────▼──────┐                 ┌──────▼──────┐
 │ Client 1    │                 │ Client 2    │                 │ Client 3    │
 │ Web SPA     │                 │ Resource API│                 │ CLI Daemon  │
 │ (OIDC+PKCE) │                 │ (Bearer RS) │                 │ (ClientCred)│
 └─────────────┘                 └─────────────┘                 └─────────────┘
```

---

## 2. Docker Compose Stack: Keycloak + PostgreSQL

Create a file named `docker-compose.yml`:

```yaml
version: "3.8"

services:
  postgres:
    image: postgres:16-alpine
    container_name: keycloak-db
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: keycloak_secret_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U keycloak"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - auth-net

  keycloak:
    image: quay.io/keycloak/keycloak:24.0.5
    container_name: keycloak-server
    command: start-dev --import-realm
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: keycloak_secret_password
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin_secure_password
      KC_HEALTH_ENABLED: "true"
      KC_METRICS_ENABLED: "true"
    ports:
      - "8080:8080"
    volumes:
      - ./realm-export.json:/opt/keycloak/data/import/realm-export.json:ro
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - auth-net

volumes:
  postgres_data:

networks:
  auth-net:
    driver: bridge
```

---

## 3. Automated Realm Provisioning (`realm-export.json`)

To auto-import our configured realm upon container startup, create `realm-export.json`:

```json
{
  "realm": "enterprise-lab",
  "enabled": true,
  "displayName": "Enterprise Identity Lab",
  "accessTokenLifespan": 300,
  "ssoSessionIdleTimeout": 1800,
  "ssoSessionMaxLifespan": 36000,
  "roles": {
    "realm": [
      { "name": "admin", "description": "Administrator Role" },
      { "name": "engineer", "description": "Engineering Staff" },
      { "name": "viewer", "description": "Read-only Access" }
    ]
  },
  "users": [
    {
      "username": "darshan",
      "enabled": true,
      "email": "darshan@example.com",
      "firstName": "Darshan",
      "lastName": "K",
      "credentials": [
        {
          "type": "password",
          "value": "LabUserPassword2026!",
          "temporary": false
        }
      ],
      "realmRoles": ["admin", "engineer"]
    }
  ],
  "clients": [
    {
      "clientId": "portal-spa",
      "name": "Enterprise Web Portal SPA",
      "enabled": true,
      "publicClient": true,
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": true,
      "redirectUris": ["http://localhost:3000/*", "http://127.0.0.1:3000/*"],
      "webOrigins": ["http://localhost:3000", "+"],
      "attributes": {
        "pkce.code.challenge.method": "S256"
      }
    },
    {
      "clientId": "inventory-api",
      "name": "Backend Inventory Resource Server",
      "enabled": true,
      "bearerOnly": true
    },
    {
      "clientId": "cli-automation",
      "name": "CI/CD Automation CLI",
      "enabled": true,
      "publicClient": false,
      "serviceAccountsEnabled": true,
      "secret": "cli_client_secret_778899",
      "standardFlowEnabled": false,
      "directAccessGrantsEnabled": false
    }
  ]
}
```

---

## 4. Client Configuration Breakdown

1. **`portal-spa` (Public Client):**
   - Uses `publicClient: true` (no client secret stored in the browser).
   - Enforces PKCE with `pkce.code.challenge.method: S256`.
   - Restricts callbacks strictly to `http://localhost:3000/*`.
2. **`inventory-api` (Resource Server):**
   - Configured as `bearerOnly: true`. It never initiates user login; it only validates incoming bearer tokens against the Keycloak realm JWKS.
3. **`cli-automation` (Machine-to-Machine):**
   - Configured with `serviceAccountsEnabled: true`. Exercises OAuth 2.0 `client_credentials` grant with a confidential secret.

---

## 5. The Three Exercises

### Exercise 1: M2M Token Issuance (Client Credentials)

```bash
curl -s -X POST "http://localhost:8080/realms/enterprise-lab/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=cli-automation" \
  -d "client_secret=cli_client_secret_778899" | jq .
```

Verify that Keycloak issues an access token with `typ: Bearer` and `sub: service-account-cli-automation`.

### Exercise 2: Authorization Code Flow with PKCE

1. Generate a high-entropy string `code_verifier`.
2. Calculate `code_challenge = base64url(sha256(code_verifier))`.
3. Open the authorization URL in your browser:
   ```
   http://localhost:8080/realms/enterprise-lab/protocol/openid-connect/auth?
     response_type=code
     &client_id=portal-spa
     &redirect_uri=http://localhost:3000/callback
     &scope=openid profile email
     &code_challenge=<YOUR_CODE_CHALLENGE>
     &code_challenge_method=S256
   ```
4. Authenticate as `darshan` / `LabUserPassword2026!`.
5. Capture the authorization code from the redirect URL and exchange it via POST:
   ```bash
   curl -s -X POST "http://localhost:8080/realms/enterprise-lab/protocol/openid-connect/token" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "grant_type=authorization_code" \
     -d "client_id=portal-spa" \
     -d "redirect_uri=http://localhost:3000/callback" \
     -d "code=<AUTH_CODE>" \
     -d "code_verifier=<YOUR_CODE_VERIFIER>" | jq .
   ```

---

## 6. JWKS Rotation Drill Execution

Run a zero-downtime key rotation drill inside Keycloak:

```bash
# 1. Fetch current active keys
curl -s http://localhost:8080/realms/enterprise-lab/protocol/openid-connect/certs | jq '.keys[].kid'

# 2. Add new RSA-OAEP/RS256 active key via Keycloak Admin CLI
docker exec -it keycloak-server /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin --password admin_secure_password

# Add a higher priority key provider (priority 100 > default 10)
docker exec -it keycloak-server /opt/keycloak/bin/kcadm.sh create components -r enterprise-lab \
  -s name=rsa-new-active -s providerId=rsa-generated -s providerType=org.keycloak.keys.KeyProvider \
  -s 'config.priority=["150"]' -s 'config.keySize=["2048"]' -s 'config.algorithm=["RS256"]'

# 3. Verify JWKS now advertises BOTH old and new public keys
curl -s http://localhost:8080/realms/enterprise-lab/protocol/openid-connect/certs | jq '.keys[].kid'
```

Downstream services continue to verify tokens signed by the old key while new tokens are signed using the newly promoted key.

---

## 7. Automated Test & Verification Suite

Create `verify_lab.py`:

```python
import httpx
import jwt
from jwt import PyJWKClient

REALM_URL = "http://localhost:8080/realms/enterprise-lab"
JWKS_URL = f"{REALM_URL}/protocol/openid-connect/certs"

def verify_lab():
    # 1. Verify Discovery
    resp = httpx.get(f"{REALM_URL}/.well-known/openid-configuration")
    assert resp.status_code == 200, "Discovery failed"
    disc = resp.json()
    assert disc["issuer"] == REALM_URL, "Issuer mismatch"

    # 2. Obtain Token via Client Credentials
    token_resp = httpx.post(
        disc["token_endpoint"],
        data={
            "grant_type": "client_credentials",
            "client_id": "cli-automation",
            "client_secret": "cli_client_secret_778899"
        }
    )
    assert token_resp.status_code == 200, "Token exchange failed"
    access_token = token_resp.json()["access_token"]

    # 3. Cryptographically Verify Token
    jwks_client = PyJWKClient(JWKS_URL)
    signing_key = jwks_client.get_signing_key_from_jwt(access_token)
    claims = jwt.decode(
        access_token,
        signing_key.key,
        algorithms=["RS256"],
        audience="account",
        issuer=REALM_URL
    )
    print("Verification Successful! Token Claims:", claims["sub"])

if __name__ == "__main__":
    verify_lab()
```

---

## 8. Tear Down & Cleanup

```bash
docker-compose down -v
```

---

## 9. Next Step

With your working reference lab verified, you are ready for the final capstone exercise: simulating production incidents, threat containment, and disaster response.

→ [[02-incident-tabletop|Capstone C.2 — Identity Incident Tabletop: 3 Realistic Scenarios]]

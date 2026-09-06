---
title: "2.3 — Client Credentials, ROPC, Implicit (and Why to Avoid)"
author: darshan
tags: [authentication, stage-2, oauth, client-credentials, ropc, implicit, device-code, m2m]
date: 2026-06-13
description: The other OAuth grants — when client_credentials is right, why ROPC and implicit are deprecated, and when to reach for device_code
---

# 2.3 — Client Credentials, ROPC, Implicit (and Why to Avoid)

> **Goal:** Pick the right grant for any non-auth-code scenario. Know why ROPC and implicit are dead, when client_credentials is the perfect choice, and when device_code is the only way.

> **Prerequisites:** [[../stage2/01-oauth-fundamentals|2.1]] + [[../stage2/02-auth-code-pkce|2.2]] complete.

---

## Table of Contents

1. [The Grant Decision Tree](#1-the-grant-decision-tree)
2. [Client Credentials — Machine Identity](#2-client-credentials--machine-identity)
3. [Resource Owner Password Credentials (ROPC) — Deprecated](#3-resource-owner-password-credentials-ropc--deprecated)
4. [Implicit Grant — Removed in OAuth 2.1](#4-implicit-grant--removed-in-oauth-21)
5. [Device Code — Input-Constrained Devices](#5-device-code--input-constrained-devices)
6. [Refresh Token — Extension Grant](#6-refresh-token--extension-grant)
7. [JWT Bearer (RFC 7523) — Token Exchange](#7-jwt-bearer-rfc-7523--token-exchange)
8. [The Modern Default: Authorization Code + PKCE](#8-the-modern-default-authorization-code--pkce)
9. [Code: Client Credentials in 20 Lines](#9-code-client-credentials-in-20-lines)
10. [DevOps Analogy: The Different Visitor Passes](#10-devops-analogy-the-different-visitor-passes)
11. [Attacks & Pitfalls](#11-attacks--pitfalls)
12. [Exercises](#12-exercises)
13. [Next Step](#13-next-step)

---

## 1. The Grant Decision Tree

```
Is there a human user involved?
│
├── NO → machine-to-machine
│        │
│        └── Use client_credentials
│            (with mTLS or private_key_jwt for high-value)
│
└── YES → human user
         │
         ├── Does the user have a full browser?
         │    │
         │    ├── YES (web app, mobile app with browser) → authorization_code + PKCE
         │    │
         │    └── NO (smart TV, CLI, IoT) → device_code
         │
         └── Is this a legacy app that must have the password?
              │
              ├── NO → authorization_code + PKCE (you always have a choice)
              │
              └── YES, really truly legacy
                   └── ROPC (and migrate ASAP — it's deprecated)
```

**In one sentence per grant:**

| Grant | Use when | Avoid when |
|-------|----------|------------|
| `authorization_code` (+PKCE) | Human user with browser or browser-capable device | (default — use unless you have a reason not to) |
| `client_credentials` | Machine-to-machine, no human | Any user-facing flow |
| `device_code` | User on a separate device (TV, CLI, IoT) | User has a browser on the same device |
| `refresh_token` | Extending the auth code or device code flow | (extension grant — used with another) |
| `password` (ROPC) | **NEVER** | (deprecated, removed in 2.1) |
| `implicit` | **NEVER** | (deprecated, removed in 2.1) |
| `jwt-bearer` (RFC 7523) | Token exchange — converting one token to another | (advanced — covered at the end) |

---

## 2. Client Credentials — Machine Identity

**The grant for: no human in the loop.** A backend service, a CI job, a script, an internal API call.

**The actors:**

```
RO  = nobody (no user)
C   = the service (e.g., billing-svc)
AS  = the IdP (issues the token)
RS  = the API the service wants to call
```

**The flow (2 steps, server-to-server):**

```
1. The service authenticates itself to the IdP
   POST /token
   grant_type=client_credentials
   &client_id=billing-svc
   &client_secret=...    (or private_key_jwt, or mTLS)
   &scope=read:invoices write:invoices

2. IdP returns an access token
   {
     "access_token": "...",
     "token_type": "Bearer",
     "expires_in": 3600,
     "scope": "read:invoices write:invoices"
   }
```

**That's it. No user. No browser. No redirect.**

### When to use

```
✓ Backend service calling another backend service
✓ CI/CD job calling your deployment API
✓ Cron job calling your reporting API
✓ Scheduled task calling your data API
✓ Server-to-server federation
```

### When NOT to use

```
✗ Anything with a user (use auth code + PKCE)
✗ Browser-based apps (the secret would be exposed)
✗ Mobile apps (the secret would be extractable)
```

### Authentication methods

**For client_credentials, the service must authenticate to the IdP.** Options:

```
client_secret_basic    HTTP Basic auth with the secret (most common)
client_secret_post     Secret in the form body (legacy, avoid)
private_key_jwt        Client signs a JWT with its private key
                       (more secure, no shared secret)
mTLS                   Client presents a certificate
                       (most secure, no shared secret at all)
```

**For high-value services (cross-org, banking, financial), use private_key_jwt or mTLS.** No shared secret = no secret to leak.

### Code: client_credentials with private_key_jwt

```python
import jwt
import time
import uuid
import requests

PRIVATE_KEY = open("service-private.pem", "rb").read()
CLIENT_ID = "billing-svc"
TOKEN_ENDPOINT = "https://idp.example.com/token"
SCOPES = "read:invoices write:invoices"

def get_service_token() -> str:
    # Build a client assertion JWT
    now = int(time.time())
    assertion = jwt.encode({
        "iss": CLIENT_ID,                    # who is signing
        "sub": CLIENT_ID,                    # who is signing (same)
        "aud": TOKEN_ENDPOINT,               # for whom (the IdP)
        "exp": now + 60,                     # short-lived (60 sec)
        "iat": now,
        "jti": str(uuid.uuid4()),
    }, PRIVATE_KEY, algorithm="RS256",
       headers={"kid": "service-2024-01"})
    
    response = requests.post(
        TOKEN_ENDPOINT,
        data={
            "grant_type": "client_credentials",
            "client_id": CLIENT_ID,
            "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            "client_assertion": assertion,
            "scope": SCOPES,
        },
        timeout=10,
    )
    response.raise_for_status()
    return response.json()["access_token"]

# Use the token
token = get_service_token()
resp = requests.get("https://api.example.com/invoices",
                    headers={"Authorization": f"Bearer {token}"})
```

**Why private_key_jwt is better than client_secret:**

```
client_secret:  "Here's the password" — both sides have it. If either leaks, game over.
private_key_jwt: "Here's a signed proof" — only the client has the private key.
                  The IdP has the public key. Can't forge the proof without the key.
                  No shared secret to leak.
```

### The scope question

```
For client_credentials, scopes are usually fine-grained API permissions:
  read:invoices      → can read invoices
  write:invoices     → can write invoices
  admin:everything   → can do anything (avoid)
  
The "sub" claim in the token is the CLIENT ID, not a user.
If you need to know "which user triggered this service call," you need
to pass that through a different mechanism (e.g., a separate header).
```

### Caching tokens

```
Don't request a new token for every API call. The IdP is rate-limited
and tokens are short-lived but reusable.

Pattern:
  token = get_service_token()  # once
  ... many API calls with this token ...
  # when the token expires (or you get a 401), get a new one
```

---

## 3. Resource Owner Password Credentials (ROPC) — Deprecated

**The grant that the OAuth spec was created to replace.** Don't use it.

**The flow (the anti-pattern):**

```
1. The client app asks the user for their username and password
2. The client app sends these to the IdP:
   POST /token
   grant_type=password
   &username=alice
   &password=alice's-password
   &client_id=myapp
3. IdP returns a token
```

**Why this is wrong:**

```
The client app now has the user's actual password.
  - The app can do anything with the account
  - If the app is compromised, the user's password is compromised
  - The app can log in as the user at any time
  - Revoking access = changing the password
  - No MFA possible (the app has the password, MFA would be bypassed)
  - The user can't tell which app did what
  
This is the same anti-pattern OAuth was designed to replace.
If you're tempted to use ROPC, you missed the entire point of OAuth.
```

**The only "valid" use:**

```
Migrating a legacy app that already had the user's password (e.g., a
custom-built auth system you're replacing). Use ROPC briefly to issue
tokens, then force the user to do a real auth code + PKCE flow.
Then remove the ROPC path.
```

**OAuth 2.1 removes ROPC entirely.** If your code uses it, plan a migration.

### Why you should never use ROPC

```
1. The user types their password into a third-party app.
   (Even if it's your own app, it's still the anti-pattern.)
2. The app can impersonate the user forever (until they change the password).
3. MFA doesn't work (the password is enough).
4. No fine-grained scopes (the app gets the user's full account).
5. No user consent screen (the user has no idea what they're granting).
6. The whole point of OAuth is "no password sharing." ROPC shares the password.
```

### The migration path

```
If you have ROPC today:
  1. Identify all the apps using it
  2. For each: figure out what flows are available
     - Web app → auth code + PKCE
     - Mobile app → auth code + PKCE
     - CLI → device code or auth code + PKCE
     - Internal service → client_credentials
  3. Build the new flow in the app
  4. Force the user to re-auth (one time, via the new flow)
  5. Disable ROPC
  6. Audit logs for old ROPC usage
```

---

## 4. Implicit Grant — Removed in OAuth 2.1

**The flow that was "good enough" in 2012.** Don't use it.

**The flow (the original SPA pattern):**

```
1. Redirect user to IdP
2. IdP redirects back to the SPA with the token in the URL fragment:
   https://app.example.com/callback#access_token=...&token_type=Bearer&expires_in=3600
3. The SPA's JavaScript extracts the token from the URL fragment
```

**Why this is wrong:**

```
1. Token in the URL → leaked via:
   - Browser history
   - Server logs (if the server sees the URL)
   - Referer header to third-party resources
   - Browser extensions
2. No client authentication → anyone can pretend to be the client
3. No refresh tokens (had to redirect again to get a new token)
4. No PKCE (added later as mitigation, but the damage was done)
```

**Timeline:**

```
2012:  OAuth 2.0 RFC. Implicit is the recommended flow for SPAs.
2014:  Industry realizes the problems.
2017:  OAuth WK recommends PKCE even for confidential clients.
2018:  "OAuth 2.0 for Browser-Based Apps" draft (now RFC 8252) says
       "use auth code + PKCE, not implicit."
2019:  Auth0, Okta, Google, others start deprecating implicit.
2022:  Most IdPs no longer offer implicit for new clients.
2024:  OAuth 2.1 removes implicit entirely.
2026:  If you see implicit, it's a legacy system.
```

**The replacement: auth code + PKCE for SPAs.**

The SPA does the auth code flow, with PKCE, exactly like a server-side app would. The only difference: the SPA doesn't have a client_secret (it's public). The PKCE code_verifier is the proof.

**The BFF (Backend-For-Frontend) pattern** for sensitive SPAs:

```
SPA → its own backend → IdP
  (SPA never directly handles the token)
  
  The SPA's backend does the auth code flow.
  The backend stores the tokens (server-side, safe).
  The SPA gets a session cookie from its backend.
  
This eliminates token-in-browser entirely.
```

---

## 5. Device Code — Input-Constrained Devices

**The grant for: a device that can't display a login form.** Smart TVs, CLIs, IoT devices, anything where the user has to authenticate on a SEPARATE device.

**The flow (5 steps):**

```
1. The device requests a device code
   POST /device/code
   client_id=tv-app
   scope=watch_history

2. IdP returns:
   {
     "device_code": "abc123",
     "user_code": "WXYZ-PQRS",     ← user types this on their phone
     "verification_uri": "https://idp.example.com/device",
     "verification_uri_complete": "https://idp.example.com/device?user_code=WXYZ-PQRS",
     "expires_in": 1800,            ← 30 min to enter the code
     "interval": 5                   ← poll every 5 seconds
   }

3. The device displays:
   "Go to https://idp.example.com/device on your phone
    and enter the code: WXYZ-PQRS"

4. The device polls the token endpoint:
   POST /token
   grant_type=urn:ietf:params:oauth:grant-type:device_code
   &device_code=abc123
   &client_id=tv-app
   
   Response (while waiting):
   {
     "error": "authorization_pending"     ← user hasn't entered the code yet
   }
   
   Response (when user enters the code and approves):
   {
     "access_token": "...",
     "refresh_token": "...",
     "expires_in": 3600
   }
   
   Response (if user denies or code expires):
   {
     "error": "access_denied"  or  "expired_token"
   }

5. The user, on their phone:
   a. Opens https://idp.example.com/device
   b. Logs in (with MFA)
   c. Enters the code WXYZ-PQRS
   d. Approves the scopes
   e. The device's next poll succeeds
```

**Visualized:**

```
   Smart TV                          IdP                     User's Phone
      │                               │                            │
      │ 1. /device/code               │                            │
      ├──────────────────────────────►│                            │
      │                               │                            │
      │ 2. device_code, user_code     │                            │
      │◄──────────────────────────────┤                            │
      │                               │                            │
      │ "Enter WXYZ-PQRS at            │                            │
      │  https://idp.example.com/      │                            │
      │  device on your phone"         │                            │
      │                               │                            │
      │ 3. Poll /token                │                            │
      ├──────────────────────────────►│                            │
      │                               │                            │
      │ {error: "authorization_pending"}                            │
      │◄──────────────────────────────┤                            │
      │                               │  4. Open URL, log in,     │
      │                               │  enter code, approve      │
      │                               │◄───────────────────────────┤
      │                               │                            │
      │ 5. Poll /token                │                            │
      ├──────────────────────────────►│                            │
      │                               │                            │
      │ {access_token: "..."}         │                            │
      │◄──────────────────────────────┤                            │
      │                               │                            │
      │ ✓ Logged in! Use the token    │                            │
```

**Code: device flow in 30 lines**

```python
import requests
import time

CLIENT_ID = "tv-app"
DEVICE_ENDPOINT = "https://idp.example.com/device/code"
TOKEN_ENDPOINT = "https://idp.example.com/token"
SCOPES = "watch_history"

def device_flow_login():
    # Step 1: request a device code
    resp = requests.post(DEVICE_ENDPOINT, data={
        "client_id": CLIENT_ID,
        "scope": SCOPES,
    })
    resp.raise_for_status()
    device = resp.json()
    
    # Step 2: show the user the code and URL
    print(f"\nGo to: {device['verification_uri']}")
    print(f"Enter code: {device['user_code']}\n")
    
    # Step 3: poll the token endpoint
    device_code = device["device_code"]
    interval = device.get("interval", 5)
    expires_at = time.time() + device["expires_in"]
    
    while time.time() < expires_at:
        time.sleep(interval)
        
        resp = requests.post(TOKEN_ENDPOINT, data={
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "device_code": device_code,
            "client_id": CLIENT_ID,
        })
        
        if resp.status_code == 200:
            return resp.json()  # access_token, refresh_token, etc.
        
        err = resp.json().get("error")
        if err == "authorization_pending":
            continue  # user hasn't entered the code yet
        elif err == "slow_down":
            interval += 5  # back off
        elif err == "expired_token":
            raise Exception("device code expired, please restart")
        elif err == "access_denied":
            raise Exception("user denied the request")
        else:
            raise Exception(f"device flow error: {err}")
    
    raise Exception("device flow timed out")

tokens = device_flow_login()
print(f"Logged in! Access token: {tokens['access_token'][:20]}...")
```

**When to use device_code:**

```
✓ Smart TVs (no keyboard, user has phone)
✓ CLI tools (user has to log in via browser anyway)
✓ IoT devices (limited UI)
✓ Desktop apps that want a "log in on your phone" flow
✓ Anything where the user can't type a password on the device
```

**When NOT to use device_code:**

```
✗ The device has a browser (use auth code + PKCE)
✗ The device is purely server-side (use client_credentials)
✗ The user expects to type their password on the device (use auth code)
```

---

## 6. Refresh Token — Extension Grant

This isn't a standalone grant. It's the way to extend the others. Already covered in [[02-auth-code-pkce#9-the-refresh-token-flow|2.2 Section 9]] and [[../stage1/04-lifecycle|1.4]]. Quick recap:

```
The access_token expires (after 5-15 min).
The client uses the refresh_token to get a new access_token:
  POST /token
  grant_type=refresh_token
  &refresh_token=... 
  &client_id=...
  &client_secret=... (if confidential)
  
IdP returns:
  { access_token: ..., refresh_token: ... (new, rotated) }
  
Old refresh_token is now invalid.
```

**Refresh tokens are issued for:**
- `authorization_code` (covered in 2.2)
- `device_code` (same pattern)
- Sometimes `client_credentials` (less common)

**Not issued for:**
- `password` (deprecated)
- `implicit` (no secret to bind to)

---

## 7. JWT Bearer (RFC 7523) — Token Exchange

**The grant for: exchanging one token for another.** Useful in federation, delegation, and "act as" scenarios.

**The pattern:**

```
Service A has a JWT for user Alice.
Service A wants to call Service B as Alice, but Service B trusts
a different IdP.
Service A uses token exchange to get a new JWT from B's IdP.
```

**The flow:**

```
1. Service A POSTs to B's IdP token endpoint:
   POST /token
   grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer
   &assertion=EYJ...   (the JWT from A's IdP)
   &scope=read:reports
   &audience=https://api-b.example.com

2. B's IdP validates the assertion (signature, claims)
   If B's IdP trusts A's IdP (via federation):
     B's IdP issues a new JWT for Alice, scoped to B

3. Service A uses the new token to call Service B
```

**Real-world uses:**

```
1. Cross-cloud: k8s service account in AWS → AWS IAM token (via OIDC federation)
2. Cross-org: vendor's IdP issues a token → your IdP accepts it → your token
3. "Act as": admin acts on behalf of a user
4. Impersonation: a service acts as the user for audit clarity
5. Token exchange: refresh token → access token for a different audience
```

**RFC 8693 (Token Exchange)** is the more comprehensive version. RFC 7523 is the simpler "exchange a JWT for a token" pattern.

**This is advanced.** If you're just doing user auth or service-to-service in one org, you don't need this. But for cross-cloud, multi-org, or "act as" patterns, it's the right tool.

---

## 8. The Modern Default: Authorization Code + PKCE

**If you're starting new in 2026 and you have any doubt, use auth code + PKCE.** This is the default. Every other grant is for a specific exception.

```
✓ Web app (server-rendered, SPA, BFF)
✓ Mobile app (iOS, Android)
✓ Native desktop app
✓ CLI (with auth code + PKCE, browser-based login)
✓ Anything with a human user
```

**Reach for the other grants only when you have a specific reason:**

```
client_credentials → no user, just a service
device_code       → no usable browser, user logs in elsewhere
refresh_token     → extend an existing flow
jwt-bearer        → token exchange, cross-org
```

---

## 9. Code: Client Credentials in 20 Lines

```python
"""
Client credentials grant: machine-to-machine authentication.
The service authenticates to the IdP with its own credentials,
gets a token, uses the token to call an API.
"""
import time
import threading
import requests

CLIENT_ID = "billing-svc"
CLIENT_SECRET = "s3cr3t"
TOKEN_ENDPOINT = "https://idp.example.com/token"
API_BASE = "https://api.example.com"
SCOPES = "read:invoices write:invoices"

class ServiceTokenCache:
    """Cache the service token until it's about to expire."""
    
    def __init__(self):
        self._token = None
        self._expires_at = 0
        self._lock = threading.Lock()
    
    def get(self) -> str:
        with self._lock:
            now = time.time()
            if self._token and now < self._expires_at - 60:  # refresh 60s early
                return self._token
            
            # Get a new token
            resp = requests.post(TOKEN_ENDPOINT, data={
                "grant_type": "client_credentials",
                "client_id": CLIENT_ID,
                "client_secret": CLIENT_SECRET,
                "scope": SCOPES,
            }, timeout=10)
            resp.raise_for_status()
            data = resp.json()
            
            self._token = data["access_token"]
            self._expires_at = now + data["expires_in"]
            return self._token

# Usage
tokens = ServiceTokenCache()

def call_api(path: str, method: str = "GET", **kwargs) -> dict:
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = f"Bearer {tokens.get()}"
    return requests.request(method, f"{API_BASE}{path}",
                            headers=headers, timeout=10, **kwargs).json()

# Use it
invoices = call_api("/invoices")
print(f"Got {len(invoices)} invoices")
```

The token cache is important: don't request a new token on every API call.

---

## 10. DevOps Analogy: The Different Visitor Passes

A corporate office has different visitor passes for different needs.

```
┌──────────────────────────────────────────────────────────────────┐
│  Visitor Type              │  Pass Type      │  OAuth Grant     │
├──────────────────────────────────────────────────────────────────┤
│  Guest visiting 1 person   │  Day pass       │  authorization_  │
│  (logged at front desk,    │  (escort req'd) │  code + PKCE     │
│  name + photo + visit time)│                 │                  │
│                            │                 │                  │
│  Cleaning crew             │  Building pass  │  client_         │
│  (no host, but authorized  │  (no escort,    │  credentials     │
│  to be in the building)    │  but no office  │  (the crew has   │
│                            │  access)        │  a "service      │
│                            │                 │  account")       │
│                            │                 │                  │
│  Contractor fixing a       │  Work order     │  device_code     │
│  smart HVAC system         │  pass (no UI on │  (the technician │
│  (can't enter password on  │  the device)    │  uses a phone to │
│  the HVAC touchscreen)     │                 │  authorize)      │
│                            │                 │                  │
│  Vendor with an old legacy │  "Password"     │  ROPC            │
│  badge that requires the   │  pass (vendor   │  (deprecated,    │
│  password to be entered    │  literally has  │  don't use)      │
│  directly — pre-2010)      │  the password)  │                  │
│                            │                 │                  │
│  Old app that just needs   │  Implicit pass  │  implicit        │
│  a token fast, in the URL  │  (token printed │  (deprecated,    │
│                            │  on the badge)  │  don't use)      │
└──────────────────────────────────────────────────────────────────┘
```

**The authorization code + PKCE flow is the day pass** — you go to the front desk (IdP), they verify your identity, they print a pass, you go to your destination. Standard, secure, well-understood.

**The client credentials flow is the building pass** — the cleaning crew has a pass, doesn't need a host, but can't go anywhere restricted. Just lets them do their job.

**The device code flow is the work order pass** — the HVAC technician can't enter their password on the touchscreen, so they call the front desk from their phone, get a code, enter it, and the system authorizes them remotely.

---

## 11. Attacks & Pitfalls

### A1. Using ROPC "just for testing"

```
"I've got a demo tomorrow, the IdP isn't set up yet, let me just
 use ROPC to test the flow."

NO. Use client_credentials (if no user needed) or auth code + PKCE
(if user needed). ROPC in "test" code ends up in production.

If the IdP isn't set up: spin up a local IdP (Keycloak in Docker)
or use a hosted free tier (Auth0 dev keys, Okta dev org).
```

### A2. The implicit grant in legacy code

```
Code: response_type=token
Token: in the URL fragment
Result: leaked via browser history, logs, Referer

Migrate to auth code + PKCE. The migration is:
  1. Add /authorize redirect (with PKCE) to your SPA
  2. Add /callback handler (parses ?code, exchanges for tokens)
  3. Test thoroughly
  4. Remove the implicit response_type=token path
  5. Rotate any tokens that were issued via implicit (force re-auth)
```

### A3. client_secret in a mobile app

```
Mobile app: hardcoded client_secret in the binary.
Anyone with the APK/IPA: has the secret.

Fix:
  1. Remove the client_secret from the app
  2. Configure the IdP to allow this client as "public" (no secret)
  3. Use PKCE for client authentication
  4. Optional: use private_key_jwt (signed JWT, no shared secret)
```

### A4. client_credentials with too-broad scopes

```
Service A gets a token with scope=admin:everything.
Service A only needs to read invoices.
Service A is compromised. Attacker has admin:everything.

Fix: minimum scopes per service. "Read invoices" should be a
different token than "deploy code."
```

### A5. Token caching forever

```
"Cache the service token. It works."

But: tokens expire. Forever-cached token = expired token = API calls fail.
Worse: token is good, but you can't revoke it (it's still in the cache).

Fix: cache with TTL (per the expires_in claim). Refresh before expiry.
Force refresh on 401.
```

### A6. Device code polling too aggressively

```
Device polls every 100ms. IdP rate-limits. IdP returns slow_down.
Device ignores slow_down. IdP blocks the client. Device is now
permanently broken.

Fix: respect the `interval` value from the IdP. Back off on
slow_down (typically +5 seconds). Don't poll faster than the IdP says.
```

### A7. Device code displayed insecurely

```
TV app shows the user_code on screen.
The code is visible to anyone in the room.
The user goes to their phone, enters the code, approves.
But anyone who saw the code could approve it instead.

Fix: device codes are short-lived (30 min) and the user
has to authenticate to enter them. The exposure window is small.
But: don't display the code in a public area (e.g., a kiosk).
```

### A8. JWT bearer with no validation

```
Service A sends a JWT to Service B's IdP.
Service B's IdP accepts the JWT without verifying the signature.

Result: anyone can forge a JWT and get a token from B's IdP.

Fix: validate the JWT (signature, iss, aud, exp). Use a library.
Pin the expected algorithms. Require iss/aud.
```

### A9. ROPC still in production "for compatibility"

```
"We've got 3 internal apps using ROPC. We can't migrate them this quarter."

OK, but:
  1. Document them
  2. Set a deadline for migration
  3. Disable new ROPC clients
  4. Audit ROPC usage monthly
  5. Force a password reset when the user has to re-auth
  6. Plan the migration
  7. MIGRATE THE DAMN THINGS
```

### A10. Refresh tokens for client_credentials

```
Some apps request a refresh_token from a client_credentials grant.
This is unusual. client_credentials is for short-lived service identity.
If your service needs long-lived tokens, either:
  - Use a short-lived access_token + re-auth (e.g., via a
    pre-shared key or workload identity like SPIFFE)
  - Get a new token from client_credentials periodically
    (the standard pattern)
  
Most IdPs don't issue refresh tokens for client_credentials.
If yours does, be careful — it's a long-lived credential.
```

### A11. The "OAuth 2.0 supports every flow" IdP mistake

```
IdP config: all grants enabled, all client types, all response types.
"This way, any client can use us."

Every enabled grant is an attack surface. Enable only what you need:
  - First-party web app: auth code + PKCE
  - Mobile app: auth code + PKCE
  - Internal service: client_credentials
  - Smart TV app: device_code
  
Less is more.
```

### A12. Authorization code for SPA without a backend

```
The SPA does the auth code flow, gets the code in the URL,
exchanges it for tokens... but where? The SPA can't keep a
client_secret. And the token exchange usually needs server-side code.

Options:
  1. PKCE without a secret (works, but token is in the browser)
  2. BFF pattern: SPA → its own backend → IdP
     The backend stores the tokens. The SPA has a session cookie.
     This is the modern best practice for sensitive SPAs.
  3. Use a "token handler" service (a tiny backend just for OAuth)
```

---

## 12. Exercises

### Exercise 1: Grant decision
For each scenario, pick the right grant and justify in 2 sentences:
- (a) Your CI system deploys to your production API
- (b) A smart TV app lets the user log in with their phone
- (c) Your SaaS web app lets users log in with Google
- (d) A backend service calls another backend service
- (e) Your CLI tool needs to call your API
- (f) Two cloud providers need to exchange identity (AWS → GCP)
- (g) A legacy desktop app from 2012 that asks for a password

### Exercise 2: Build client_credentials
Take the code from Section 9. Test it against a real IdP (Keycloak in Docker is free). Verify the token works against a real API. Add metrics: how many tokens issued, average lifetime, etc.

### Exercise 3: Build device flow
Take the code from Section 5. Test it: your laptop is the "TV", your phone visits the URL and enters the code. Verify the polling works, the slow_down handling works, the timeout works.

### Exercise 4: Find the implicit grant
Search your codebase (or any open-source project) for `response_type=token`. For each hit, write a 1-paragraph migration plan to auth code + PKCE.

### Exercise 5: Find the ROPC
Search your codebase (or any open-source project) for `grant_type=password` in HTTP requests. For each hit, design a migration to client_credentials or auth code + PKCE.

### Exercise 6: client_secret_in_app detection
Find a mobile app. Unpack the APK (using apktool or similar). Search the resources/code for a `client_secret`. If you find one, that's a security issue — the secret is extractable. Document your findings.

### Exercise 7: Token caching with TTL
Build a `ServiceTokenCache` class that:
- Returns a cached token if valid
- Refreshes the token if expired
- Handles 401s by force-refreshing
- Thread-safe (multiple goroutines/threads share the cache)
Test with concurrent access.

### Exercise 8: Device code security review
For the device flow code, identify 3 security issues that could occur:
- (a) The device displays the user_code to a public screen
- (b) The device polls faster than the IdP's interval
- (c) The device code is exposed in the device's logs
For each, propose a fix.

### Exercise 9: JWT bearer exercise
Set up two IdPs (A and B). Configure A to federate with B. Service at A gets a JWT for user Alice. Service A uses RFC 7523 to exchange it for a B-issued JWT. Service A calls B's API as Alice. Document the config and the flow.

### Exercise 10: Grant audit
For your production system (if you have one):
- Which grants are enabled at your IdP?
- Which clients use which grants?
- Are there any ROPC clients still in production?
- Are there any implicit grants still in production?
- Document the migration plan for anything deprecated.

---

## 13. Next Step

You can now pick the right OAuth grant for any scenario. Next, we cover the token lifecycles in depth — access tokens, refresh tokens, rotation, and the sender-constrained variants (DPoP, mTLS).

→ [[../stage2/04-token-lifecycles|Stage 2.4 — Token Lifecycles: Access, Refresh, DPoP]]

**Before you move on, verify you can answer these:**
1. When do you use client_credentials, and how is it different from auth code + PKCE?
2. Why is ROPC deprecated, and what's the migration path?
3. Why is the implicit grant deprecated, and what replaced it for SPAs?
4. When is the device code flow the right choice?
5. What is JWT bearer (RFC 7523), and when would you use it?
6. If a colleague says "we use OAuth for our SPA login," what's the more precise answer?

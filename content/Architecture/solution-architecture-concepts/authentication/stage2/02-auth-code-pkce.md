---
title: "2.2 — Authorization Code + PKCE: The Workhorse"
author: darshan
tags: [authentication, stage-2, oauth, authorization-code, pkce, rfc7636, csrf, state-parameter]
date: 2026-06-13
description: The OAuth 2.0 workhorse — authorization code grant, state parameter, PKCE for public + confidential clients, and the security threats each one defeats
---

# 2.2 — Authorization Code + PKCE: The Workhorse

> **Goal:** Implement the authorization code grant from scratch (in 80 lines) and explain every redirect, every parameter, and every security check. Know what PKCE is, why it was originally for mobile/SPA, and why it's now mandatory for ALL clients.

> **Prerequisites:** [[../stage2/01-oauth-fundamentals|Stage 2.1]] + Stage 1 complete.

---

## Table of Contents

1. [Why This Flow Dominates](#1-why-this-flow-dominates)
2. [The Flow: 7 Steps in Detail](#2-the-flow-7-steps-in-detail)
3. [The `state` Parameter: CSRF Defense](#3-the-state-parameter-csrf-defense)
4. [PKCE: The Defense Against Code Interception](#4-pkce-the-defense-against-code-interception)
5. [PKCE Mechanics: code_verifier, code_challenge, S256](#5-pkce-mechanics-code_verifier-code_challenge-s256)
6. [PKCE for Confidential Clients (Yes, Even Server Apps)](#6-pkce-for-confidential-clients-yes-even-server-apps)
7. [The Token Endpoint: Server-to-Server](#7-the-token-endpoint-server-to-server)
8. [What the Token Response Looks Like](#8-what-the-token-response-looks-like)
9. [The Refresh Token Flow](#9-the-refresh-token-flow)
10. [Error Responses](#10-error-responses)
11. [Code: A Working Implementation](#11-code-a-working-implementation)
12. [DevOps Analogy: The Coat Check](#12-devops-analogy-the-coat-check)
13. [Attacks & Pitfalls](#13-attacks--pitfalls)
14. [Exercises](#14-exercises)
15. [Next Step](#15-next-step)

---

## 1. Why This Flow Dominates

Five OAuth 2.0 grant types exist. One rules them all.

```
authorization_code         ← 90%+ of OAuth in production
client_credentials         ← machine-to-machine
device_code                ← input-constrained devices (TVs, CLI)
refresh_token              ← extension of another grant
(removed in 2.1)
implicit                   ← was used by SPAs in 2014-2020
password (ROPC)            ← was used by first-party apps in 2012-2018
```

**Why the auth code grant wins:**

```
✓ Works for any client type (web, mobile, native, server-side)
✓ The token is delivered server-to-server, never in the URL
✓ PKCE defends against code interception
✓ Refresh tokens for long sessions, no password sharing
✓ Compatible with FAPI 2.0, OAuth 2.1, every modern spec
✓ Industry standard, every IdP supports it
```

**Why the other grants lose:**

```
implicit:      token in URL fragment, vulnerable to leakage
password:      user's password goes to the client app
client_creds:  no user — only for machine identity
device_code:   UX is clunky (user has to type a code on a phone)
```

**If you're starting new in 2026 and you have a user involved, use authorization code + PKCE.** Don't think. Don't debate. Use it.

---

## 2. The Flow: 7 Steps in Detail

**The cast, again:**

```
RO  = the user (logged in at the IdP, e.g., Google)
C   = the client app (e.g., a Node.js server)
AS  = the authorization server (e.g., Google's OAuth)
RS  = the resource server (e.g., Google's API)
```

**The flow, in detail:**

### Step 1: User initiates

```
The user is at the client app and clicks "Sign in with IdP" or
"Connect my account."

Client decides to start the OAuth flow.
```

### Step 2: Client generates state + PKCE values, redirects

```
The client generates:
  - state = random nonce (32+ bytes, base64url)
  - code_verifier = random string (43-128 chars, base64url-safe)
  - code_challenge = base64url(sha256(code_verifier))
  - code_challenge_method = "S256"

The client stores state and code_verifier in the user's session
(must survive the redirect round trip).

The client redirects the user's browser to the AS's authorization endpoint:
  HTTP 302 Found
  Location: https://idp.example.com/authorize
    ?response_type=code
    &client_id=CLIENT_ID
    &redirect_uri=https://app.example.com/callback
    &scope=openid+profile+email+https://api.example.com/read
    &state=STATE_VALUE
    &code_challenge=CODE_CHALLENGE_VALUE
    &code_challenge_method=S256
```

**What each parameter means:**

| Parameter | Required | Meaning |
|-----------|----------|---------|
| `response_type=code` | Yes | "I want the authorization code flow" |
| `client_id` | Yes | The IdP's identifier for this app |
| `redirect_uri` | Yes | Where the IdP sends the user back. MUST be pre-registered. |
| `scope` | Yes | What the client wants. Space-separated. |
| `state` | Recommended (effectively required) | CSRF defense. Client-generated nonce. |
| `code_challenge` | PKCE required (per OAuth 2.1) | Hashed secret, ties the request to the token exchange |
| `code_challenge_method` | Required if code_challenge present | Almost always `S256` (SHA-256) |

### Step 3: User authenticates at the IdP

```
The IdP checks if the user has an active session. If not, prompts
for credentials (username + password, MFA, passkey, etc.).

This step is entirely up to the IdP. OAuth 2.0 doesn't specify
how authentication works — that's the IdP's job.
```

### Step 4: User grants (or denies) the requested scopes

```
The IdP shows a consent screen:
  "App X wants to:
   ✓ Read your email
   ✓ Read your calendar
   
   [Allow]  [Deny]"

If the user clicks Deny, the IdP redirects back with an error.
If Allow, the IdP generates a short-lived authorization code.
```

### Step 5: IdP redirects back to the client

```
HTTP 302 Found
Location: https://app.example.com/callback
  ?code=AUTHORIZATION_CODE
  &state=STATE_VALUE   ← the SAME value the client sent
  
The authorization code is:
  - Short-lived (typically 30 seconds to 10 minutes)
  - Single-use (consumed at the token endpoint)
  - Bound to the client_id, redirect_uri, code_challenge
  - Tied to the user who granted permission
```

### Step 6: Client exchanges code for tokens (server-to-server)

```
The client's BACKEND (not the browser) POSTs to the IdP's token endpoint:

POST https://idp.example.com/token
Content-Type: application/x-www-form-urlencoded
Authorization: Basic <base64(client_id:client_secret)>  ← for confidential clients

grant_type=authorization_code
&code=AUTHORIZATION_CODE
&redirect_uri=https://app.example.com/callback   ← SAME as in step 2
&client_id=CLIENT_ID
&code_verifier=CODE_VERIFIER_VALUE               ← the ORIGINAL value, not the hash
```

**For public clients (no secret):**

```
POST https://idp.example.com/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code=AUTHORIZATION_CODE
&redirect_uri=https://app.example.com/callback
&client_id=CLIENT_ID
&code_verifier=CODE_VERIFIER_VALUE
```

No `Authorization: Basic` header. The code_verifier proves client identity (PKCE is the auth mechanism for public clients).

### Step 7: IdP returns tokens

```
HTTP 200 OK
Content-Type: application/json

{
  "access_token": "ya29.a0AfH6SMB...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "1//09GxvXH...",
  "scope": "openid profile email https://api.example.com/read",
  "id_token": "eyJhbGciOiJSUzI1NiIs..."   ← only present if openid scope was requested
}
```

The client now has:
- **access_token** — for API calls
- **refresh_token** — for getting new access tokens
- **id_token** (if OIDC) — for user identity

**The complete sequence diagram:**

```
     User              Client App            IdP (AS)              API (RS)
      │                     │                    │                     │
      │ 1. Click login      │                    │                     │
      ├────────────────────►│                    │                     │
      │                     │ 2. Generate state+PKCE                   │
      │                     │ 3. Redirect to /authorize                │
      │◄────────────────────┤                    │                     │
      │                                              │                 │
      │ 4. User authenticates, grants permission     │                 │
      ├─────────────────────────────────────────────►│                 │
      │                                              │                 │
      │ 5. Redirect back to /callback?code=...&state=...              │
      │◄─────────────────────────────────────────────┤                 │
      │                     │                    │                     │
      │ 6. Browser follows redirect                │                     │
      ├────────────────────►│                    │                     │
      │                     │ 7. POST /token (code + verifier)         │
      │                     ├───────────────────►│                     │
      │                     │                    │                     │
      │                     │ 8. {access_token, refresh_token, id_token}│
      │                     │◄───────────────────┤                     │
      │                     │                                            │
      │ 9. App uses access_token                                            │
      │                     ├──────────────────────────────────────────►│
      │                     │                                            │
      │                     │ 10. {user data}                            │
      │                     │◄───────────────────────────────────────────┤
```

---

## 3. The `state` Parameter: CSRF Defense

**The threat:** an attacker tricks the user into completing an OAuth flow with the attacker's account.

```
Attack without state (CSRF on the callback):
  1. Alice is logged into IdP
  2. Attacker starts an OAuth flow, gets an auth code bound to attacker's account
  3. Attacker tricks Alice's browser into visiting:
     https://app.example.com/callback?code=ATTACKER_CODE
  4. Alice's app receives the code, exchanges it for a token bound to ATTACKER
  5. Alice's app now thinks Alice is logged in... as Attacker
  6. Alice adds her data to what is now Attacker's account
  7. Attacker reads Alice's data through their own account
```

**The defense (state):**

```
Client (before redirect):
  state = base64url(random_bytes(32))   ← unique per request
  store state in user's session

Client (on callback):
  expected_state = session.get("oauth_state")
  received_state = request.args.get("state")
  if not hmac.compare_digest(expected_state, received_state):
      raise InvalidStateError
  
  if state matches:
      session.pop("oauth_state")
      proceed with token exchange
  
  if state doesn't match:
      abort. probably a CSRF attempt.
```

**Why it works:**

```
Attacker needs to predict the state value the client will use.
State is 32+ random bytes. Unpredictable.
Attacker can't complete the attack without knowing the state.
```

**Modern libraries do this for you. But verify they do.**

### Code: the state handling

```python
import secrets
import hmac

def generate_state() -> str:
    return secrets.token_urlsafe(32)

def verify_state(received: str, expected: str) -> bool:
    return hmac.compare_digest(received, expected)
```

### What if I skip state?

```
You become vulnerable to OAuth CSRF. An attacker can log you in
to their account, see your data get added to it, and effectively
hijack your session.

This is not theoretical. It's been used in real attacks.
```

---

## 4. PKCE: The Defense Against Code Interception

**The threat:** an attacker steals the authorization code from the redirect.

**When can this happen?**

```
1. Mobile app with a custom URL scheme (e.g., myapp://callback)
   - Another app on the device can register the same scheme
   - Or a malicious app intercepts the redirect
   
2. Native app using a loopback redirect
   - Localhost listener on the device
   - Other apps on the device can listen on the same port
   
3. Single-page app with a wildcard redirect
   - The redirect_uri is too permissive
   - Attacker can register a similar URI

4. Network MITM
   - If the redirect happens over HTTP (it shouldn't, but bugs happen)
   
5. Log injection
   - If the callback URL ends up in server logs
   - Attacker reads the logs, extracts the code
```

**The defense (PKCE):**

```
Before redirecting, the client:
  1. Generates code_verifier (random string, 43-128 chars)
  2. Computes code_challenge = base64url(sha256(code_verifier))
  3. Sends code_challenge to the IdP (in the auth request)
  4. Stores code_verifier in the session

When exchanging the code for tokens, the client:
  5. Sends code_verifier to the IdP (in the token request)
  6. IdP computes sha256(code_verifier) and compares to code_challenge
  7. If they match, the IdP knows the request came from the same client
  8. If they don't match, the code is rejected
```

**Result:** an attacker who steals the code (without the verifier) can't exchange it for tokens.

### Why this works

```
Attacker scenario: steals the code from the redirect.

Attacker tries to exchange it:
  POST /token
    code=STOLEN_CODE
    code_verifier=?  ← attacker doesn't know this
    
IdP:
  received verifier: (empty or wrong)
  stored challenge: hash(some_real_verifier)
  hash(received) != stored challenge
  REJECT.

The code is useless without the verifier.
```

**The code_verifier is 43-128 characters of base64url-safe random data.** That's 256+ bits of entropy. Unguessable.

### Why this is better than just a client_secret

```
Client secret: known to the client. If the client is malicious or
               compromised, the secret is exposed. Can't tell the
               difference between "real client" and "attacker who
               got the secret."

PKCE: bound to ONE specific auth flow. Even if the attacker gets
      a PKCE code_challenge from one request, they can't reuse it
      for a different request. Each request has its own verifier.
      No "secret" in the traditional sense — it's a per-request
      proof.
```

---

## 5. PKCE Mechanics: code_verifier, code_challenge, S256

### The verifier

```python
import secrets

# 43-128 characters from the unreserved set
# [A-Z] [a-z] [0-9] - . _ ~
code_verifier = secrets.token_urlsafe(64)
print(code_verifier)
# 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'
# (43 characters, ~256 bits of entropy)
```

**Length requirements (RFC 7636):**

```
Minimum length: 43 characters
Maximum length: 128 characters
Allowed chars:  [A-Z] [a-z] [0-9] - . _ ~
Recommended:    64 random bytes → base64url = 86 chars (well within limits)
```

### The challenge

```python
import hashlib
import base64

def make_code_challenge(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode()

code_challenge = make_code_challenge(code_verifier)
print(code_challenge)
# 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'
```

### The challenge method

```
S256 (recommended):    code_challenge = base64url(sha256(code_verifier))
                       Strong. Use this. The default for OAuth 2.1.
                       
plain (don't use):     code_challenge = code_verifier
                       Legacy. The verifier IS the challenge.
                       Some old servers still support it.
                       Vulnerable to verifier leakage in logs.
                       NEVER use if you control the client.
```

### The math

```
You have:
  code_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  
You compute:
  sha256(code_verifier) = 0x7c1d3... (32 bytes)
  
You base64url-encode (no padding):
  base64url(0x7c1d3...) = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  
You send the challenge to the IdP at auth time.
You send the verifier to the IdP at token time.
The IdP hashes the verifier and checks it matches the challenge.
```

### Why S256 is the only safe choice

```
The verifier is the secret. If you use "plain", the verifier is
also the challenge, which means the challenge (sent in the
auth URL) IS the verifier. Anyone who sees the auth URL has
the verifier.

If the auth URL ends up in:
  - Browser history
  - Server logs at the IdP
  - Browser Referer header
  - Network capture
... the attacker has the verifier. The PKCE is broken.

S256: the challenge is the HASH of the verifier. The verifier
is never sent in the auth URL. The attacker has the hash.
Hashes are one-way — can't recover the verifier from the hash.
```

---

## 6. PKCE for Confidential Clients (Yes, Even Server Apps)

OAuth 2.1 says: PKCE is REQUIRED for ALL clients using the authorization code grant. Not just public clients.

**Why?**

```
For confidential clients (server-side apps with a client_secret):
  - The client_secret authenticates the client
  - PKCE additionally binds the auth request to the token exchange
  - If the client_secret leaks, PKCE still defends against code interception

For public clients (SPAs, mobile apps):
  - No client_secret
  - PKCE IS the client authentication
  - The client proves "I started this flow" via the verifier

Either way: PKCE always provides defense-in-depth.
```

**The "PKCE is for mobile" misconception:**

```
In 2015, PKCE was introduced as RFC 7636. It was recommended for
public clients (mobile, native) because they can't keep secrets.

Around 2019-2022, the OAuth working group realized:
  1. PKCE is also good for confidential clients
  2. The cost is low (32 bytes of randomness + a SHA-256)
  3. The benefit is high (defense against code interception)
  4. Implementing it once for all clients is simpler than
     maintaining two paths

OAuth 2.1: PKCE is REQUIRED for the authorization code grant.
No exceptions. Even for confidential clients with a client_secret.
```

**Implementation for a confidential client:**

```python
# Step 2: Auth request
auth_url = (
    f"https://idp.example.com/authorize"
    f"?response_type=code"
    f"&client_id={CLIENT_ID}"
    f"&redirect_uri={REDIRECT_URI}"
    f"&scope={SCOPES}"
    f"&state={state}"
    f"&code_challenge={code_challenge}"         ← PKCE
    f"&code_challenge_method=S256"
)

# Step 6: Token request
token_request = {
    "grant_type": "authorization_code",
    "code": code,
    "redirect_uri": REDIRECT_URI,
    "client_id": CLIENT_ID,
    "client_secret": CLIENT_SECRET,             ← confidential client
    "code_verifier": code_verifier,             ← PKCE
}
```

You have BOTH client_secret AND PKCE. Defense in depth.

---

## 7. The Token Endpoint: Server-to-Server

The token endpoint is the only place tokens are issued (and the only place the client_secret is used). It's a server-to-server POST — never from the browser.

### Request

```http
POST /token HTTP/1.1
Host: idp.example.com
Content-Type: application/x-www-form-urlencoded
Authorization: Basic <base64(client_id:client_secret)>

grant_type=authorization_code
&code=AUTHORIZATION_CODE
&redirect_uri=https%3A%2F%2Fapp.example.com%2Fcallback
&code_verifier=CODE_VERIFIER_VALUE
```

**For public clients (no Authorization header):**

```http
POST /token HTTP/1.1
Host: idp.example.com
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code=AUTHORIZATION_CODE
&redirect_uri=https%3A%2F%2Fapp.example.com%2Fcallback
&client_id=CLIENT_ID
&code_verifier=CODE_VERIFIER_VALUE
```

### Authentication methods at the token endpoint

```
1. client_secret_basic (most common for confidential clients)
   - HTTP Basic auth: Authorization: Basic base64(client_id:client_secret)
   
2. client_secret_post (sometimes required by old IdPs)
   - In the form body: client_id=...&client_secret=...
   
3. client_secret_jwt (signed JWT, more secure)
   - Client signs a JWT with the secret as the key
   - Sends the JWT as client_assertion
   
4. private_key_jwt (signed with the client's RSA/ECDSA private key)
   - Most secure. No shared secret. Client has a key pair.
   - Used in FAPI 2.0, B2B scenarios.
   
5. none (public clients)
   - No client authentication. PKCE is the auth.
```

**For confidential clients, prefer (1) or (4).** (2) puts the secret in the request body, which is more likely to end up in logs. (3) is fine but obscure.

### Code: the token request

```python
import requests
import base64

def exchange_code_for_token(code: str, code_verifier: str,
                            redirect_uri: str,
                            client_id: str, client_secret: str,
                            token_endpoint: str) -> dict:
    """
    Exchange an authorization code for tokens.
    Returns: { access_token, refresh_token, id_token, expires_in, ... }
    """
    # For confidential clients: HTTP Basic auth
    auth = (client_id, client_secret)
    
    response = requests.post(
        token_endpoint,
        data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect_uri,
            "code_verifier": code_verifier,
        },
        auth=auth,
        timeout=10,
    )
    
    if response.status_code != 200:
        # Try to extract error
        try:
            err = response.json()
            raise TokenExchangeError(
                f"token endpoint error: {err.get('error')}",
                err.get("error_description", ""),
            )
        except ValueError:
            raise TokenExchangeError(
                f"token endpoint HTTP {response.status_code}: {response.text}"
            )
    
    return response.json()
```

---

## 8. What the Token Response Looks Like

### Success (HTTP 200)

```json
{
  "access_token": "ya29.a0AfH6SMBx-...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "1//09GxvXHXv...",
  "scope": "openid profile email https://api.example.com/read",
  "id_token": "eyJhbGciOiJSUzI1NiIs..."   // only if openid scope requested
}
```

**Field meanings:**

| Field | Required? | Meaning |
|-------|-----------|---------|
| `access_token` | Yes | The token to use at the API |
| `token_type` | Yes | Almost always "Bearer" |
| `expires_in` | Recommended | Seconds until access_token expires |
| `refresh_token` | Optional | For getting a new access_token. Some flows don't issue. |
| `scope` | Recommended | The scopes actually granted (may be a subset of requested) |
| `id_token` | OIDC only | The user's identity (covered in Stage 3) |

### Variations

```
- Some IdPs return the access_token in a JWT format (with alg, kid, etc.)
  You can decode it, but you don't have to.
  
- Some IdPs return opaque tokens (random strings)
  You can't decode them. You use introspection (2.5) to validate.
  
- Some IdPs use a "scope" claim (space-separated string)
  Some use a "scp" claim (array of strings)
  This is normal. Both are common.
```

### The expires_in trap

```
If the IdP returns expires_in=3600:
  - The access_token expires 3600 SECONDS from now
  - Some clients compute absolute exp: now() + 3600
  - But the server's clock might be different
  - In practice: refresh slightly EARLY (e.g., 5 min before exp)
  - To handle clock skew: refresh at expires_in - 60 seconds
```

---

## 9. The Refresh Token Flow

The client has an access_token. It expires. Now what?

```
Client: "I need a new access token. Here's my refresh token."
  
POST /token HTTP/1.1
Host: idp.example.com
Content-Type: application/x-www-form-urlencoded
Authorization: Basic <base64(client_id:client_secret)>

grant_type=refresh_token
&refresh_token=REFRESH_TOKEN_VALUE
&scope=openid+profile+email  ← optional, request a subset
```

**Response (success):**

```json
{
  "access_token": "ya29.a0AfH6SMBx-...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "1//09GxvXHXv..."   ← NEW one (rotation)
}
```

**Important details:**

```
1. The IdP may issue a NEW refresh_token. The old one is now invalid.
   This is "refresh token rotation" — best practice.
   
2. The scope parameter is OPTIONAL. If present, it must be a subset
   of the originally granted scopes. The IdP may reject if you ask
   for more than originally granted.
   
3. Some IdPs return the same refresh_token (no rotation). Less secure.
   Always prefer rotation.
   
4. The new access_token may have a different expires_in than the
   original. Some IdPs shorten the lifetime with each refresh.
```

**Reuse detection (covered in detail in 1.4):**

```
If the old refresh_token is presented again (after rotation):
  → The IdP revokes the entire token family
  → User is logged out everywhere
  → Re-auth required
  
This is the "refresh token theft detection" pattern.
```

### Code: refresh

```python
def refresh_access_token(refresh_token: str, client_id: str,
                          client_secret: str, token_endpoint: str) -> dict:
    response = requests.post(
        token_endpoint,
        data={
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        },
        auth=(client_id, client_secret),
        timeout=10,
    )
    response.raise_for_status()
    return response.json()
```

---

## 10. Error Responses

### The IdP redirects back with an error

```
HTTP 302 Found
Location: https://app.example.com/callback
  ?error=access_denied
  &error_description=The+user+denied+the+request
  &state=STATE_VALUE
```

**Common error codes (RFC 6749 Section 4.1.2.1):**

| Error | Meaning | When |
|-------|---------|------|
| `invalid_request` | Malformed request | Missing required parameter, invalid value, etc. |
| `invalid_client` | Client auth failed | Bad client_id/client_secret, unregistered client |
| `invalid_grant` | The grant is invalid | Code expired, code already used, PKCE failed, etc. |
| `unauthorized_client` | Client not authorized for this grant | e.g., trying to use auth code when only client_creds is allowed |
| `unsupported_grant_type` | Grant type not supported | e.g., device code on an IdP that doesn't support it |
| `invalid_scope` | Requested scope is invalid/unknown | Typo in scope name |
| `access_denied` | User denied consent | User clicked "Deny" on the consent screen |
| `server_error` | IdP internal error | Something broke on the IdP side |
| `temporarily_unavailable` | IdP overloaded | Try again later |

### The token endpoint returns an error (HTTP 400 or 401)

```json
{
  "error": "invalid_grant",
  "error_description": "Authorization code expired"
}
```

### Error handling in the client

```python
def handle_callback(request):
    # Check for error first
    if "error" in request.args:
        error = request.args["error"]
        description = request.args.get("error_description", "")
        # Don't auto-retry on access_denied
        if error == "access_denied":
            return redirect("/login?msg=user_denied_consent")
        if error == "invalid_request":
            return redirect("/login?msg=bad_request")
        # ... handle other errors
        log.warning(f"OAuth error: {error} - {description}")
        return redirect("/login?msg=auth_failed")
    
    code = request.args.get("code")
    state = request.args.get("state")
    
    # Verify state
    if not verify_state(state, session.pop("oauth_state")):
        log.warning("State mismatch — possible CSRF")
        return redirect("/login?msg=state_mismatch")
    
    # Exchange code for tokens
    try:
        tokens = exchange_code_for_token(...)
    except TokenExchangeError as e:
        log.error(f"Token exchange failed: {e}")
        return redirect("/login?msg=token_exchange_failed")
    
    # Store tokens
    session["access_token"] = tokens["access_token"]
    session["refresh_token"] = tokens.get("refresh_token")
    # ... etc
```

---

## 11. Code: A Working Implementation

A minimal but complete authorization code + PKCE flow in 80 lines.

```python
"""
Minimal OAuth 2.0 authorization code + PKCE flow.
For a real app, use a library (authlib, oauthlib, etc.).
This is the educational version.
"""
import secrets
import hashlib
import base64
import requests
import hmac
from flask import Flask, request, redirect, session, jsonify

app = Flask(__name__)
app.secret_key = secrets.token_bytes(32)

# --- Configuration ---
CLIENT_ID = "your-client-id"
CLIENT_SECRET = "your-client-secret"  # confidential client
REDIRECT_URI = "http://localhost:5000/callback"
AUTH_ENDPOINT = "https://idp.example.com/authorize"
TOKEN_ENDPOINT = "https://idp.example.com/token"
SCOPES = "openid profile email"

# --- PKCE helpers ---
def generate_code_verifier() -> str:
    return secrets.token_urlsafe(64)  # 86 chars

def derive_code_challenge(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode()

def generate_state() -> str:
    return secrets.token_urlsafe(32)

# --- Step 1: Initiate the flow ---
@app.route("/login")
def login():
    # Generate PKCE pair
    code_verifier = generate_code_verifier()
    code_challenge = derive_code_challenge(code_verifier)
    state = generate_state()
    
    # Store in session (must survive the redirect round trip)
    session["code_verifier"] = code_verifier
    session["oauth_state"] = state
    
    # Build authorization URL
    auth_url = (
        f"{AUTH_ENDPOINT}"
        f"?response_type=code"
        f"&client_id={CLIENT_ID}"
        f"&redirect_uri={REDIRECT_URI}"
        f"&scope={SCOPES}"
        f"&state={state}"
        f"&code_challenge={code_challenge}"
        f"&code_challenge_method=S256"
    )
    return redirect(auth_url)

# --- Step 2: Handle the callback ---
@app.route("/callback")
def callback():
    # Check for error
    if "error" in request.args:
        return jsonify({
            "error": request.args["error"],
            "description": request.args.get("error_description", "")
        }), 400
    
    code = request.args.get("code")
    state = request.args.get("state")
    
    # Verify state (CSRF defense)
    expected_state = session.pop("oauth_state", None)
    if not state or not hmac.compare_digest(state, expected_state or ""):
        return jsonify({"error": "state_mismatch"}), 400
    
    # Exchange code for tokens (server-to-server)
    code_verifier = session.pop("code_verifier")
    try:
        resp = requests.post(
            TOKEN_ENDPOINT,
            data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": REDIRECT_URI,
                "code_verifier": code_verifier,
            },
            auth=(CLIENT_ID, CLIENT_SECRET),
            timeout=10,
        )
        resp.raise_for_status()
        tokens = resp.json()
    except requests.RequestException as e:
        return jsonify({"error": "token_exchange_failed", "detail": str(e)}), 500
    
    # Store tokens (in real app, securely — encrypted, HttpOnly cookie, etc.)
    session["access_token"] = tokens["access_token"]
    session["refresh_token"] = tokens.get("refresh_token")
    
    return redirect("/me")

# --- Step 3: Use the access token ---
@app.route("/me")
def me():
    access_token = session.get("access_token")
    if not access_token:
        return redirect("/login")
    
    # Call the resource server
    resp = requests.get(
        "https://api.example.com/me",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=10,
    )
    return jsonify(resp.json())

# --- Step 4: Refresh the access token ---
@app.route("/refresh")
def refresh():
    refresh_token = session.get("refresh_token")
    if not refresh_token:
        return jsonify({"error": "no_refresh_token"}), 400
    
    try:
        resp = requests.post(
            TOKEN_ENDPOINT,
            data={
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
            },
            auth=(CLIENT_ID, CLIENT_SECRET),
            timeout=10,
        )
        resp.raise_for_status()
        tokens = resp.json()
    except requests.RequestException as e:
        return jsonify({"error": "refresh_failed", "detail": str(e)}), 500
    
    session["access_token"] = tokens["access_token"]
    if "refresh_token" in tokens:
        session["refresh_token"] = tokens["refresh_token"]  # rotated
    
    return jsonify({"status": "refreshed"})

if __name__ == "__main__":
    app.run(debug=True, port=5000)
```

That's the entire flow in 80 lines. A real library does it better (handles errors, retries, JWKS, validation, etc.) but these 80 lines are the core.

---

## 12. DevOps Analogy: The Coat Check

Imagine an opera. You arrive in a fur coat. You check it at the coat check.

```
You (RO)        = the opera-goer with the coat
Coat check (AS) = the coat check counter
Theater (C)     = the venue giving you the check ticket
Fur coat (RS)   = your actual coat (the resource you own)

Without OAuth (the bad old way):
  1. You give the coat to the theater, hoping they hold it for you
  2. The theater has your coat, can do anything with it
  3. To get it back, you have to identify yourself and ask
  
With OAuth:
  1. The coat check gives you a numbered ticket (the access token)
  2. The ticket has your coat number on it, plus the time you'll
     pick it up (the scope and lifetime)
  3. The coat check can verify the ticket at any time
  4. If you lose the ticket, you can call the coat check, prove who
     you are, and have the ticket canceled (revocation)
  5. The theater never touches your coat directly
```

**Where PKCE fits:**

```
The ticket has a special mark on it that only the coat check knows
about (the code_challenge). When you present the ticket, you also
have to say a secret phrase (the code_verifier) that matches the
mark. If someone steals the ticket, they don't know the phrase —
the ticket is useless.

Without PKCE: stolen ticket = thief gets your coat
With PKCE: stolen ticket = thief has the ticket but can't prove
           they have the secret phrase = no coat
```

**Where the state parameter fits:**

```
The ticket has a number. But the number was generated when YOU
arrived. The coat check remembers: "this number was issued for
this person at this time." If the thief tries to use a ticket
they got from somewhere else, the number doesn't match the arrival
record. Rejected.
```

---

## 13. Attacks & Pitfalls

### A1. Missing `state` (CSRF on the callback)

```
Threat: covered in Section 3. Without state, an attacker can
log a victim into the attacker's account, then harvest data
the victim adds.

Fix: always generate a random state, store it, verify on callback.
Most libraries do this. Verify yours.
```

### A2. Missing PKCE (code interception)

```
Threat: covered in Section 4. An attacker intercepts the auth
code in the redirect and exchanges it for tokens.

Fix: always use PKCE. Even for confidential clients. Always S256.
```

### A3. Open redirect via `redirect_uri` mismatch

```
The client app passes redirect_uri=... in the auth request.
The IdP must validate this against the pre-registered list.
EXACT match. Not prefix. Not pattern.

Common bug: the IdP uses prefix matching
  Allowed: https://app.example.com/*
  Request: https://app.example.com.evil.com/callback
  Match: yes (prefix)
  Result: open redirect, phishing opportunity.

Fix: exact string match. No wildcards. No prefixes.
```

### A4. Storing the `code_verifier` insecurely

```
The code_verifier is sensitive. If the attacker has it AND the
code, they can exchange the code for tokens.

Where to store:
  ✓ Server-side session (cookie + server state)
  ✓ Encrypted local storage (less ideal, but OK if encrypted)
  ✗ localStorage (XSS-stealable)
  ✗ URL (logged everywhere)
  ✗ Client-side sessionStorage (lost on tab close — bad for the flow)
```

### A5. Token endpoint hitting a wrong URL

```
The IdP has multiple environments: dev, staging, prod.
If the client is configured for staging but the user logged into
prod (or vice versa), the token exchange fails.

Mitigation:
  - Use the same environment for auth + token endpoints
  - Validate the iss claim in the response (Stage 3 covers this for OIDC)
  - Use distinct client_ids per environment
```

### A6. Refresh token without rotation

```
Threat: refresh token is stolen. Attacker can keep using it
because it's not invalidated on use.

Fix: rotate refresh tokens (covered in 1.4). Reuse detection.
The IdP issues a new refresh_token on every refresh. The old one
is now invalid. Reuse → revoke the family.
```

### A7. Using `code` parameter in production URLs

```
The auth code in the URL (?code=ABC123) is a one-time use credential.
If the user reloads the page, hits back, or shares the URL, the
code is exposed.

Mitigation:
  - Code expires fast (30 sec to 10 min)
  - Code is single-use
  - Don't log the URL with the code
  - Don't share the URL
  - Bind to the client_id and redirect_uri
```

### A8. Mismatched `redirect_uri` between auth and token requests

```
Auth request: redirect_uri=https://app.example.com/callback
Token request: redirect_uri=https://APP.example.com/CALLBACK  ← case differs

The IdP checks: do these match? No. Reject.

Common bugs:
  - Trailing slash: /callback vs /callback/
  - HTTP vs HTTPS
  - Path case sensitivity
  - Query parameters
  
Fix: use a constant in your code. Compare exactly. Don't recompute.
```

### A9. Not validating the `iss` in the response

```
If the IdP supports multiple environments (dev, staging, prod) and
your client gets a token from the wrong one, you've got a problem.

The token response doesn't have a JWT, so no iss claim. For opaque
tokens, the only defense is to validate the token endpoint URL.
For JWT access tokens, check the iss claim. (RFC 9068.)
```

### A10. Implicit grant in legacy code

```
Old code: response_type=token
The token comes back in the URL fragment. The whole grant is
deprecated. Migrate to authorization code + PKCE.

If you find this in your codebase:
  1. Mark it as deprecated
  2. Migrate to authorization code + PKCE
  3. Test in staging
  4. Roll out
  5. Remove the implicit code path
```

### A11. The "secret in mobile app" footgun

```
Mobile app developers sometimes embed the client_secret in the
mobile app's code. Then the secret is extractable by anyone with
the APK or IPA.

This is the "confidential client" pattern — but mobile apps can't
keep secrets. They're public clients.

Fix: don't use client_secret in mobile. Use PKCE only. Configure
the IdP to allow this client as "public" (no secret).
```

### A12. Scope downgrade attack

```
The client requests scope=read.
The IdP issues a token with scope=read.
The client (in a bug or compromise) uses the token for write.
The RS checks scope: token has "read", request needs "write", reject.

But: what if the client requests scope=read and the IdP
mistrustingly grants scope=admin? Or what if the client manipulates
the token? Or what if the RS doesn't check scopes?

This isn't really an attack vector if scopes are checked. But:
  - The IdP should not grant MORE than requested
  - The RS should check the scope on every request
  - Auditing scope grants catches weird patterns
```

---

## 14. Exercises

### Exercise 1: Trace a real flow
Take a "Sign in with Google" or "Sign in with GitHub" on a real site. Trace every redirect, every parameter, every cookie. Document the flow with screenshots.

### Exercise 2: The state without state
Take the code from Section 11. Remove the state check. Try to CSRF yourself (start a flow, get the code, send it to a different browser session). Verify the attack works.

### Exercise 3: PKCE without S256
Modify the code to use `code_challenge_method=plain` (challenge = verifier). Identify the attack. Then restore S256.

### Exercise 4: Build the verifier
Hand-write the PKCE generation in 10 lines. Match the output of `secrets.token_urlsafe(64)` and `base64.urlsafe_b64encode(sha256(...).digest()).rstrip(b'=')`.

### Exercise 5: The redirect_uri footgun
Configure an IdP with `https://app.example.com/callback` as the allowed URI. Then try to auth with `https://app.example.com/callback/`, `https://app.example.com/callback?foo=bar`, `https://APP.example.com/callback`. Document which work and which don't.

### Exercise 6: Token exchange with curl
Use curl to do a complete auth code flow manually (no library). Generate PKCE values, build the URL, do the redirect (use --data-urlencode and the IdP's test endpoint), exchange the code, get the token. Save as a shell script.

### Exercise 7: The client_secret_in_app footgun
Find a mobile app that uses OAuth. Check if it has a client_secret. If yes, that secret is in the app's binary. Anyone with the binary has the secret. Document the de-anonymization risk.

### Exercise 8: Token response variations
Hit 5 different IdPs (Google, GitHub, Auth0, Okta, Keycloak). Compare their token responses. What fields differ? What about expires_in values?

### Exercise 9: Refresh token rotation
Take the Section 11 code, add refresh logic. Test: refresh once, get new tokens. Try to use the old refresh token — should fail (rotation). Try to use the OLD access token — should still work until exp.

### Exercise 10: PKCE on confidential client
Configure your IdP to require PKCE for a confidential client. Verify: with PKCE works, without PKCE fails. Document the response when PKCE is missing.

---

## 15. Next Step

You can now implement the authorization code grant from scratch, with state and PKCE. Next, we cover the other grants — and why most of them shouldn't be used.

→ [[../stage2/03-other-grants|Stage 2.3 — Client Credentials, ROPC, Implicit (and Why to Avoid)]]

**Before you move on, verify you can answer these:**
1. What are the 7 steps of the authorization code flow?
2. What does the `state` parameter defend against, and how?
3. What does PKCE defend against, and why is S256 the only safe choice?
4. Why does OAuth 2.1 require PKCE for confidential clients too?
5. What's the difference between the code and the token, and why is the code short-lived?
6. What error do you get if you try to use the same code twice? Why?

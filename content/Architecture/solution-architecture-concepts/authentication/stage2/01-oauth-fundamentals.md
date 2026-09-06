---
title: "2.1 — OAuth 2.0 Fundamentals: What It Is, What It Isn't"
author: darshan
tags: [authentication, stage-2, oauth, oauth2, authorization, framework, rfc6749]
date: 2026-06-13
description: The single most misunderstood thing in modern auth — what OAuth 2.0 actually is, who the actors are, and why "Login with Google" is OAuth, not auth
---

# 2.1 — OAuth 2.0 Fundamentals: What It Is, What It Isn't

> **Goal:** Understand OAuth 2.0 deeply enough to explain it to a non-technical stakeholder, pick the right flow for any scenario, and stop saying "OAuth is for login" (it's not — that's OIDC, which we cover in Stage 3).

> **Prerequisites:** [[../stage1/01-jwt-anatomy|Stage 1.1]] + [[../stage1/03-validation|Stage 1.3]] complete. You should know what a JWT is and how to validate one.

---

## Table of Contents

1. [The Most Misunderstood Acronym in Software](#1-the-most-misunderstood-acronym-in-software)
2. [What OAuth Actually Solves](#2-what-oauth-actually-solves)
3. [The Four Actors](#3-the-four-actors)
4. [The Two Key Concepts: Scopes and Tokens](#4-the-two-key-concepts-scopes-and-tokens)
5. [The Authorization Code Grant — 30,000 ft View](#5-the-authorization-code-grant--30000-ft-view)
6. [Why OAuth Is NOT Authentication](#6-why-oauth-is-not-authentication)
7. [The OAuth Token Types: Bearer, PoP, mTLS](#7-the-oauth-token-types-bearer-pop-mtls)
8. [RFC 6749 vs RFC 6749bis vs OAuth 2.1](#8-rfc-6749-vs-rfc-6749bis-vs-oauth-21)
9. [The Evolution: From Web 1.0 to OAuth 2.1](#9-the-evolution-from-web-10-to-oauth-21)
10. [When to Use OAuth (and When NOT To)](#10-when-to-use-oauth-and-when-not-to)
11. [DevOps Analogy: The Valet Key](#11-devops-analogy-the-valet-key)
12. [Attacks & Pitfalls](#12-attacks--pitfalls)
13. [Exercises](#13-exercises)
14. [Next Step](#14-next-step)

---

## 1. The Most Misunderstood Acronym in Software

If you've ever said any of these, you're not alone — and you're not wrong for the reasons you think:

- "We use OAuth for login"
- "OAuth gives us SSO"
- "OAuth is the modern replacement for SAML"
- "Our users authenticate with OAuth"
- "We use OAuth tokens as session cookies"

**Every one of these is technically wrong, but they're commonly used because OAuth 2.0 + OIDC together cover all these use cases.** The thing most people call "OAuth login" is actually **OIDC on top of OAuth 2.0**. OAuth alone is **not** an authentication protocol.

```
OAuth 2.0  = authorization framework ("what can this client do?")
OIDC       = identity layer on top of OAuth ("who is this user?")
SAML 2.0   = a different identity layer (XML, older, enterprise-heavy)

"You use OAuth for login" = you use OIDC, which is built on OAuth 2.0.
"You use OAuth for SSO"   = you use OIDC, with multiple clients sharing one IdP.
```

**The single sentence to internalize:**

> **OAuth 2.0 lets a client application act on behalf of a user (or on its own) to access resources, WITHOUT the user giving the client their password.**

The user gives the client a **token** instead of a password. The token is scoped (limited in what it can do), revocable (can be killed), and short-lived (expires fast). The user's actual credentials (password) never leave the IdP.

---

## 2. What OAuth Actually Solves

### The pre-OAuth problem (the "password anti-pattern")

Imagine three applications: Gmail, Google Calendar, Google Photos. All Google. All in the same trust domain.

Before OAuth, the only way for a third-party app to access your Google data was:

```
1. App asks: "give me your Google password"
2. User types their Google password into the app
3. App stores the password (or uses it to log in as the user)
4. App does whatever it wants with full account access
5. To revoke: change your password (everywhere)
```

**Problems:**

```
- App has the user's actual password
- App has unrestricted access to the account
- Revoking the app means changing the password
- The user can only have one password per service
- The app has access to things it doesn't need
- There's no audit trail of what the app did
- If the app is compromised, the user's password is compromised
```

### The OAuth solution

```
1. App says: "I want to read your calendar"
2. App redirects user to Google (the IdP)
3. Google says: "This app wants calendar access. Allow?"
4. User says: "Yes, calendar only, for the next hour"
5. Google gives the app a TOKEN — not a password
6. Token is SCOPED (calendar only) and TIME-LIMITED (1 hour)
7. App uses the token to read the calendar
8. To revoke: user goes to Google → "remove this app"
9. Token is dead. Password was never shared.
```

**The improvements:**

```
- App never sees the password
- App gets only what it asked for
- User can revoke without changing password
- Tokens expire automatically
- Google can audit what the app did
- If the app is compromised, the attacker gets the token, not the password
- The user can use the same Google login across many apps
```

This pattern — **delegate access via tokens, not credentials** — is the entire point of OAuth.

---

## 3. The Four Actors

RFC 6749 names them precisely. Memorize these four.

```
┌──────────────┐
│  Resource    │  The user. Owns the data. The "human" at the keyboard.
│  Owner (RO)  │  Grants permission.
└──────┬───────┘
       │ (allows)
       ▼
┌──────────────┐
│  Client      │  The app that wants to access the data. Web app, mobile
│  (C)         │  app, CLI, server-side app, etc.
└──────┬───────┘
       │ (asks for token)
       ▼
┌──────────────┐
│  Authoriza-  │  The IdP / token issuer. Authenticates the user,
│  tion Server │  issues tokens, enforces scopes.
│  (AS)        │
└──────┬───────┘
       │ (returns token)
       ▼
┌──────────────┐
│  Resource    │  The API that holds the data. Accepts tokens.
│  Server (RS) │  Validates tokens, serves data.
└──────────────┘
```

**Aliases you'll see in the wild:**

| RFC 6749 name | Common aliases |
|---------------|----------------|
| Resource Owner | User, end user, subject, principal |
| Client | App, application, Relying Party (in OIDC), Service Provider (in SAML) |
| Authorization Server | IdP (Identity Provider), OP (OIDC Provider), STS (Security Token Service) |
| Resource Server | API, backend, resource host, target service |

**Concrete example: a fitness app reading your Fitbit data**

```
Resource Owner  =  you (the user with the Fitbit)
Client          =  the fitness app (e.g., Strava)
Authorization Server =  Fitbit's OAuth server (api.fitbit.com)
Resource Server =  Fitbit's API (api.fitbit.com/oauth2/...)

Flow:
  Strava: "I want to read your Fitbit activity"
  Fitbit (AS): "Allow Strava to read your activity for 1 hour?"
  You: "Yes"
  Fitbit: gives Strava a token
  Strava: uses token to call Fitbit API
  Fitbit API: "Token valid? Yes? Here are the activities."
```

**The trust boundaries:**

```
Strava and Fitbit trust each other via the OAuth protocol.
Strava has NO direct relationship with you, the user.
Fitbit has no idea what Strava is going to do with the data.
The user explicitly granted the access, via Fitbit's consent screen.
```

---

## 4. The Two Key Concepts: Scopes and Tokens

### Scopes

A **scope** is a permission the resource owner grants. It's a string that the AS uses to limit what the token can do.

**Examples:**

```
"openid"           → OIDC: request an ID token (Stage 3)
"profile"          → OIDC: read the user's profile (name, picture)
"email"            → OIDC: read the user's email
"read:calendar"    → custom: read calendar events
"write:calendar"   → custom: write calendar events
"https://api.example.com/users.read"
                   → namespaced: read users in api.example.com
"https://www.googleapis.com/auth/drive.readonly"
                   → Google: read-only Drive access
```

**Scope rules of thumb:**

```
1. The client REQUESTS scopes (in the authorization request)
2. The user (RO) APPROVES the requested scopes (or a subset)
3. The AS issues a token with the APPROVED scopes
4. The RS checks the token's scopes before serving the request
5. Scopes are STRINGS, not objects. Format is up to the AS.
6. Scopes are SPACE-SEPARATED in the token (the "scope" claim)
```

**The "least privilege" principle applied to scopes:**

```
❌  Client requests: ["openid", "profile", "email",
                       "read:calendar", "write:calendar",
                       "delete:calendar", "admin"]
    User approves: all of them
    App does: read the calendar once
    
    Over-privileged. App got write + delete + admin for a read-only task.
    
✅  Client requests: ["read:calendar"]
    User approves: just read
    App does: read the calendar
    
    Minimum necessary. User can verify the request matches the use.
```

### Tokens

OAuth 2.0 doesn't mandate a specific token format. RFC 6749 is silent on this. In practice:

**Option A: Opaque access token (a random string)**

```
eyJhbGciOiJIUzI1NiJ9...   ← not this, this is a JWT
```

Actually:

```
2YotnFZFEjr1zCsicMWpAA   ← 22 base64url chars = ~128 random bits
```

A random string the RS doesn't understand directly. The RS has to call the AS's **introspection endpoint** (RFC 7662) to validate it.

```
RS: "Is this token valid? What scopes does it have?"
AS: "Yes, valid, scopes=read:calendar, sub=alice, exp=... "
```

**Option B: Self-contained JWT**

```
eyJhbGciOiJSUzI1NiIs...   ← the JWT we know
```

The RS validates it directly with the public key. No round-trip to the AS.

**Trade-offs (covered in detail in [[05-introspection-revocation|2.5]]):**

| | Opaque | JWT |
|--|--------|-----|
| Format | Random string | Signed JSON |
| Validation | Call AS introspection | Verify signature locally |
| Speed | Network round-trip per request | Local, O(microseconds) |
| Revocation | Instant (AS says "revoked") | Hard (token valid until exp) |
| Storage | AS must remember each token | Stateless |
| Use when | High-security, low-volume | High-volume, latency-sensitive |

### The token itself: Bearer, MAC, PoP

OAuth 2.0 has three token types per RFC 6750 (Bearer) and emerging RFC 9449 (DPoP):

```
Bearer token:   "anyone who bears (holds) this token is authorized"
                (the default, what most people mean by "OAuth token")
                Authorization: Bearer eyJ...

PoP token:      "this token is bound to a key, prove you have the key"
                (DPoP, RFC 9449 — sender-constrained)
                Authorization: PoP eyJ... + DPoP proof

mTLS token:     "this token is bound to a client cert"
                (RFC 8705 — sender-constrained via mTLS)
                Authorization: Bearer eyJ... over mTLS connection
```

We'll cover the sender-constrained variants (DPoP, mTLS) in detail in [[04-token-lifecycles|2.4]]. For now, "Bearer" is the default.

---

## 5. The Authorization Code Grant — 30,000 ft View

The most-used OAuth flow. The workhorse. 90% of OAuth in production uses this.

**The cast:**

```
RO  = you (logged in at your IdP, e.g., Google)
C   = the app that wants to access your data (e.g., Strava)
AS  = Google's OAuth server
RS  = Google's API (Calendar API)
```

**The flow in 7 steps:**

```
1. User clicks "Connect with Google" in Strava
2. Strava redirects the browser to Google's authorization endpoint
   https://accounts.google.com/o/oauth2/v2/auth?
     client_id=strava_app_id
     &redirect_uri=https://strava.com/oauth/callback
     &response_type=code
     &scope=openid+email+profile+https://www.googleapis.com/auth/calendar.readonly
     &state=random_nonce_strava_generated
     &code_challenge=base64url(sha256(code_verifier))  ← PKCE
     &code_challenge_method=S256
3. User logs in to Google (if not already), sees the consent screen
4. User clicks "Allow"
5. Google redirects the browser back to Strava
   https://strava.com/oauth/callback?
     code=short-lived-authorization-code
     &state=same_nonce_strava_generated  ← Strava checks this
6. Strava (server-to-server) POSTs to Google's token endpoint
   POST https://oauth2.googleapis.com/token
     code=<the code>
     &client_id=strava_app_id
     &client_secret=strava_app_secret
     &redirect_uri=https://strava.com/oauth/callback
     &code_verifier=the_random_value_strava_generated  ← PKCE
7. Google returns:
   {
     "access_token": "ya29....",
     "refresh_token": "1//09...",
     "expires_in": 3600,
     "token_type": "Bearer",
     "scope": "...",
     "id_token": "eyJ..."  ← OIDC: this is the auth part
   }
```

**After this:**

```
- Strava uses access_token in Authorization: Bearer *** to call the Calendar API
- When it expires, Strava uses refresh_token to get a new access_token
- The user stays logged in at Google; the access_token is just for Strava
- The user can revoke Strava's access in Google's "Connected Apps" settings
```

**The two key security elements:**

```
1. state parameter (prevents CSRF on the callback)
2. PKCE (prevents authorization code interception)
```

Both are covered in detail in [[02-auth-code-pkce|2.2]].

---

## 6. Why OAuth Is NOT Authentication

This is the part most tutorials get wrong. OAuth 2.0 by itself tells you NOTHING about the user.

**The distinction:**

```
Authorization: "what can this client do?"
               "this client can read my calendar for the next hour"

Authentication: "who is this user?"
                "this user is alice@company.com with MFA enabled"
```

**OAuth 2.0 does NOT provide authentication.** RFC 6749 says so explicitly:

> "OAuth 2.0 is a delegation protocol, good for thought only insofar as it
> provides no definition of the mechanism by which the user is authenticated."

The OAuth access token authorizes the client to act. It doesn't prove who the user is, what their role is, or what attributes they have.

**What an access token alone can NOT tell your app:**

```
- The user's name
- The user's email
- Whether the user is human or a service
- Whether the user authenticated with MFA
- When the user last authenticated
- The user's roles or permissions
- Whether this is the same user as last time
```

**The OAuth access token is FOR the resource server.** It says "this client is allowed to access this resource." It does NOT say "this user is Alice."

**The solution: OIDC.**

```
OIDC = OAuth 2.0 + ID token
The ID token is a JWT signed by the AS, containing USER identity:
  - sub: stable user ID
  - name, email, picture: user profile
  - auth_time, amr, acr: when and how they authenticated
  - iss, aud, exp, iat: standard claims
  
OIDC is covered in detail in Stage 3. For now, the mental model:
  - OAuth 2.0 = authorization (for the API)
  - OIDC = authentication (for your app)
  - Together: you can do "Login with Google" AND "Google can call your API"
```

**The marketing lie:**

```
"Sign in with Google"  →  technically, this is OIDC
                           with OAuth 2.0 as the transport
                           
                          The "Sign in" is OIDC (ID token proves identity)
                          The "with Google" is OAuth (Google's AS issues tokens)
```

**Practical test:**

```
Your app: "Is this user logged in?"
  - Look at the ID token (OIDC). It has the user's identity.
  - Don't look at the access token (OAuth). It doesn't have the user's identity.
  
Your API: "Is this request authorized?"
  - Look at the access token (OAuth). It has the scopes.
  - Don't look at the ID token (OIDC). It doesn't have the API's permissions.
```

---

## 7. The OAuth Token Types: Bearer, PoP, mTLS

### Bearer (RFC 6750)

The default. "Whoever has the token, is the user."

```
GET /api/users/me HTTP/1.1
Authorization: Bearer ya29.a0AfH6SM...
```

**The problem:** if the token is stolen, the thief IS the user. (This is why we hash tokens at rest, use TLS, and short-lived tokens — covered in 2.4.)

### PoP / DPoP (RFC 9449, 2023)

A "proof-of-possession" token. Bound to a key the client holds.

```
GET /api/users/me HTTP/1.1
Authorization: DPoP eyJhbG...     ← the access token
DPoP: eyJhbG...                  ← a JWT signed with the client's key
```

The DPoP proof is a JWT that contains:
- The HTTP method
- The URL
- A timestamp (iat)
- A nonce (if required by the server)
- A JWK (the client's public key)

The server verifies: the client's key matches the `jkt` (JWK thumbprint) in the access token, AND the proof is recent, AND the method+URL match.

**Result:** a stolen token alone is useless. The thief also needs the private key.

### mTLS (RFC 8705)

The token is bound to a client certificate. The TLS connection itself proves the client holds the cert.

```
TLS handshake:
  Server presents cert (proves server identity)
  Client presents cert (proves client identity)
  Session is bound to both

Request:
  GET /api/users/me HTTP/1.1   (over the mTLS connection)
  Authorization: Bearer eyJhbG...
```

The token's `cnf` claim contains the cert's thumbprint:

```json
{
  "sub": "service-a",
  "cnf": {
    "x5t#S256": "thumbprint-of-client-cert"
  }
}
```

**Result:** stolen token alone is useless. The thief also needs the cert and its private key.

### When to use which

```
Bearer:    default, most compatible, simplest
PoP/DPoP:  modern SPAs and mobile apps that can store a key
mTLS:      service-to-service, zero-trust networks, banking
```

Full deep-dive in [[04-token-lifecycles|2.4]].

---

## 8. RFC 6749 vs RFC 6749bis vs OAuth 2.1

OAuth 2.0 has been "in progress" for years. Here's the current state of the specs.

```
RFC 6749          (2012)   The original. THE spec for OAuth 2.0.
                            "OAuth 2.0 Authorization Framework"
                            
draft-ietf-oauth-v2-1  (2024+)  The cleanup. Removes the deprecated bits,
                            pins the modern best practices. NOT an RFC yet.
                            When it lands, it'll be "OAuth 2.1".
                            
RFC 6749bis        (drafts)  The intermediate drafts that fed into 2.1.
                            Most of the "best current practice" guidance
                            came from this work.
```

**What 2.1 changes vs 2.0:**

| OAuth 2.0 | OAuth 2.1 |
|-----------|-----------|
| Implicit grant (deprecated) | Implicit grant REMOVED |
| Resource Owner Password Credentials (ROPC) | ROPC REMOVED |
| PKCE "RECOMMENDED" | PKCE REQUIRED for authorization code |
| Exact redirect URI matching "RECOMMENDED" | EXACT matching REQUIRED |
| Multiple response types in one request | Restricted |
| Public clients | Public clients OK with PKCE |
| Bearer tokens | Bearer, DPoP, mTLS all first-class |

**If you're starting new in 2026, follow OAuth 2.1.** Most IdPs already do. RFC 6749 is for understanding the historical baggage; 2.1 is for the modern reality.

---

## 9. The Evolution: From Web 1.0 to OAuth 2.1

```
2006:  Twitter OAuth 1.0a (custom, not RFC)
2010:  Facebook Login (custom, OAuth 1.0a-like)
2012:  RFC 6749 — OAuth 2.0 (the framework)
2012:  RFC 6750 — Bearer tokens
2014:  OpenID Connect 1.0 (OIDC, identity layer on OAuth)
2015:  RFC 7636 — PKCE (protects public clients)
2015:  RFC 7662 — Token introspection (opaque tokens)
2018:  RFC 8252 — OAuth for native apps (PKCE for mobile)
2020:  RFC 8628 — Device authorization grant (smart TVs, CLIs)
2020:  RFC 8705 — mTLS client auth + sender-constrained tokens
2021:  RFC 9068 — JWT profile for access tokens
2022:  OAuth 2.0 Security BCP (best current practice, became 2.1)
2023:  RFC 9449 — DPoP (sender-constrained tokens)
2024:  RFC 9861 — Per-passphrase tokens
2024:  OAuth 2.1 drafts (the cleanup)
2026:  OAuth 2.1 RFC expected
```

**The 14-year journey has been mostly about removing bad practices and adding protections for public clients.**

---

## 10. When to Use OAuth (and When NOT To)

### USE OAuth when

```
✓ You want users to grant third-party apps LIMITED access to their data
✓ You're a SaaS that wants "Connect with Google/Dropbox/Slack"
✓ You're building an API that multiple clients will consume
✓ You have multiple services that need to act on behalf of a user
✓ You need scoped, revocable, time-limited access
✓ You want to avoid users typing passwords into third-party apps
```

### DON'T use OAuth when

```
✗ You just need authentication (use OIDC, or plain sessions, or magic links)
✗ You have one client and one server, internal to your org
  (use mTLS, or a shared signing key, or SPIFFE)
✗ You have legacy systems that can't do the redirect dance
  (use SAML, or a simple token issued by a custom endpoint)
✗ You're using OAuth as a session mechanism without understanding the trade-offs
  (you're going to leak tokens and have a bad time)
```

### The matrix

| Scenario | Use |
|----------|-----|
| "Login with Google" | OIDC (OAuth 2.0 + ID token) |
| "Connect Strava to your Fitbit" | OAuth 2.0 authorization code + PKCE |
| "Server-to-server internal API" | OAuth 2.0 client credentials |
| "Mobile app talks to your API" | OAuth 2.0 authorization code + PKCE |
| "Web SPA talks to your API" | OAuth 2.0 authorization code + PKCE |
| "CLI tool talks to your API" | OAuth 2.0 device code or authorization code + PKCE |
| "Internal microservice identity" | mTLS / SPIFFE, not OAuth |
| "Banking-grade API" | FAPI 2.0 (OAuth 2.1 + additional constraints) |
| "Single-page app, no backend" | OAuth 2.0 authorization code + PKCE + back-end-for-front-end |
| "Smart TV / IoT with no browser" | OAuth 2.0 device code |
| "Server-rendered app with first-party users" | Probably just sessions, or OIDC |

---

## 11. DevOps Analogy: The Valet Key

A valet key for a car is a real-world analogy that perfectly captures OAuth.

```
Full key:    Opens everything. Start the car, open the trunk, glove box, all doors.
             Only the owner has it.

Valet key:   Starts the car, drives it. CAN'T open the trunk or glove box.
             Given to the parking attendant, who only needs to drive the car.
             
OAuth token: A "valet key" for a digital resource.
             Gives the client LIMITED access to do SOMETHING with the user's data.
             Can't do anything else.
             Can be revoked (the user takes the valet key back).
             Expires (the valet only has it for the duration of parking).
```

**The model:**

```
User (Resource Owner) = the car owner
Client (Strava, etc.) = the valet parking attendant
Authorization Server = the car manufacturer (issued the original key)
Resource Server (API) = the car itself
Token = the valet key

Properties of the valet key:
  ✓ Limited (can't open trunk)
  ✓ Time-limited (parking is 1 hour)
  ✓ Revocable (owner can disable the valet key in the app)
  ✓ Doesn't compromise the original (the owner's full key still works)
  ✓ Auditable (the car's app shows when the valet drove it)
```

**Why this works better than giving the valet your full key:**

```
1. The full key is never shared
2. The valet can only do what the valet key allows
3. The valet key expires automatically
4. Revocation is one tap in the app
5. The owner gets an audit trail
```

**When the analogy breaks:**

```
Car valet keys are physical. You can only have so many copies.
OAuth tokens are digital. An attacker can copy infinitely.
That's why the time-limit and revocation are critical.
```

---

## 12. Attacks & Pitfalls

### A1. "OAuth is for login" (the conceptual bug)

```
Bug: building "Login with Google" using only OAuth 2.0, no OIDC.

What you have: an access token. Anyone with it can call the API.
What you don't have: identity. No "user is alice@company.com."

What goes wrong: you use the access token as a session token. The user
"logs in" to your app. But the access token has no user identity — it
has scopes. You treat the token as a session, but you can't tell WHO
is logged in.

Fix: add OIDC. Request the "openid" scope. Get the ID token back.
The ID token has the user's identity. Use THAT for session.
The access token has the API's permissions. Use THAT for API calls.
```

### A2. The implicit grant (the deprecated flow)

```
In 2012-2018, SPAs used the implicit grant:
  1. Redirect to IdP
  2. IdP returns the token in the URL fragment (#access_token=...)
  3. JS extracts the token from the URL
  
Problems:
  - Token in URL → leaked via browser history, logs, Referer
  - No client authentication → anyone can pretend to be the client
  - Tokens had long lifetimes (no refresh, so the user could stay logged in)
  - Industry moved on: use authorization code + PKCE for SPAs now
  
OAuth 2.1 REMOVES implicit. Don't use it.
```

### A3. The Resource Owner Password Credentials (ROPC) grant

```
ROPC = "give me the user's username and password, I'll exchange it
        for a token at the AS"

Use case: legacy apps that couldn't do the redirect dance.
Problems:
  - User's password goes to the client app
  - Client app can do anything with the password
  - No way to do MFA in the flow
  - Same anti-pattern OAuth was designed to fix
  
OAuth 2.1 REMOVES ROPC. If you see ROPC in 2026, it's a code smell.
The only legitimate modern use: migration from a legacy system
that already had the password. And even then, do the migration
quickly and use auth code + PKCE going forward.
```

### A4. Scope creep (the silent over-permission)

```
App requests: ["read:profile", "write:profile", "read:calendar", 
               "write:calendar", "admin:everything"]
AS grants:    all of them (because user clicked "Allow")
App uses:     read:profile, occasionally

Result: app has 5x the permissions it needs. If compromised,
attacker has write:calendar and admin:everything.

Fix: request only the scopes you need. Audit your scopes regularly.
Most modern apps request the minimum and re-request on demand.
```

### A5. Refresh tokens with infinite lifetime

```
Client gets a refresh token. Never expires. Attacker steals it.
Attacker has access for... forever.

Fix: short refresh token TTL (7-90 days). Rotate on every use.
Detect reuse. Revoke on user logout.
```

### A6. The "OAuth isn't authentication" mistake leads to confused-deputy

```
Multi-tenant SaaS. App trusts the IdP. Receives an access token.

App does: db.query("SELECT * FROM data WHERE tenant_id = ?", ???)

What does it use for tenant_id?
- The access token's sub? (no, that's the user, not the tenant)
- The access token's aud? (no, that's the API, not the tenant)
- A custom claim that doesn't exist in pure OAuth?

This is a confused-deputy attack waiting to happen. Without OIDC's
ID token (which has user identity claims), the app doesn't know
which tenant the user belongs to.

Fix: use OIDC. Get the ID token. Use the claims (custom if needed)
for tenant routing.
```

### A7. Token in the URL

```
Implicit flow: token came back in the URL fragment.
Some apps still do this: ?access_token=... or #access_token=...

Problems:
- Browser history
- Server logs
- Referer header to third-party resources
- Email forwarding (if the URL was emailed)
- Screen sharing / screenshots

Fix: use authorization code + PKCE. Token goes back-channel
(server-to-server from AS to client), never in the URL.
```

### A8. The state parameter bypass

```
The state parameter in the auth code flow prevents CSRF on the callback.
Some apps: don't use it. Or: use it but don't verify it.

Attack:
  1. Attacker starts an auth flow with their account
  2. Attacker gets an auth code bound to attacker's account
  3. Attacker tricks victim's browser into completing the callback
  4. Victim's app now thinks victim is logged in as attacker
  5. Victim adds their data to attacker's account
  6. Attacker reads victim's data via attacker's account
  
Fix: generate a random state, store it in the session, verify it on
callback. Mismatch → reject.
```

### A9. Open redirect via redirect_uri

```
Auth request: redirect_uri=https://app.example.com/callback
AS checks: starts with "https://app.example.com"? Yes. Allow.

But: the attacker registered redirect_uri=https://app.example.com.evil.com
AS: matches the prefix. Allows.

Fix: EXACT match of redirect_uri. No wildcards. No prefix matching.
The list of allowed redirect URIs is hardcoded per client.
```

### A10. The "we support every grant" antipattern

```
IdP config: authorization_code, implicit, password, client_credentials,
            refresh_token, urn:ietf:params:oauth:grant-type:device_code,
            urn:ietf:params:oauth:grant-type:jwt-bearer
            
This is the "we support every grant" antipattern. It looks flexible.
It's a security disaster.

For each client, configure only the grants it needs:
  - Web app: authorization_code + refresh_token
  - Mobile app: authorization_code + PKCE + refresh_token
  - Server-to-server: client_credentials
  - CLI: device_code or authorization_code + PKCE
  
Less is more. Every grant you enable is an attack surface.
```

### A11. Bearer token in a connection string

```
Database: "postgresql://user:***@db"
That's a credential. OK.
But: "postgresql://user:oauth_bearer_token@db"
Is the bearer token sent in the connection URL? In some libs, yes.
Logs the token. URL-encoded the token. Various disasters.
```

### A12. Long-lived Bearer tokens

```
A Bearer token that's valid for 24 hours, 7 days, 30 days, or "until
I revoke" is a password. Anyone who steals it IS the user for that
whole window.

Best practice: access tokens 5-15 min, refresh tokens 7-30 days
with rotation.
```

---

## 13. Exercises

### Exercise 1: Name the four actors
For each real-world scenario, identify the four OAuth actors (RO, Client, AS, RS):
- (a) "Connect Strava to Fitbit"
- (b) "Sign in to a web app with Google"
- (c) "GitHub Actions deploying to AWS"
- (d) "Your CI system calling your internal API"

### Exercise 2: Find the OAuth misuse
A colleague says: "We're using OAuth for our app's session. The access token IS the session cookie. It works great." Identify the (at least) 3 problems with this.

### Exercise 3: Scope audit
Take a real app you use that does "Login with X" (Google, Apple, GitHub, etc.). What scopes does it request? Does it request more than it needs? Could you design it with minimum scopes?

### Exercise 4: Trace a flow
Take a real "Login with Google" you can do right now. In DevTools network tab, trace:
- The redirect to Google's auth endpoint
- The consent screen
- The callback to the app
- The token exchange (server-side)
- The API call with the access token

### Exercise 5: The valet key
Explain OAuth 2.0 to a non-technical friend using ONLY the valet key analogy. No jargon. Time yourself: under 3 minutes.

### Exercise 6: Build a tiny authorization server
Use a library (e.g., `oauthlib` for Python, `oauth2-server` for Node). Issue a token, validate it. Don't use OIDC yet — just OAuth. Then add OIDC (request "openid" scope, return id_token).

### Exercise 7: Identify the implicit grant
Search your codebase (or any open-source project) for `response_type=token` in URLs. This was the implicit grant. If you find it, write a 1-paragraph proposal for migrating to authorization code + PKCE.

### Exercise 8: RFC reading
Read RFC 6749 Section 1 (Introduction) and Section 1.7 (What OAuth 2.0 Is Not). Compare to what you thought OAuth was. What surprised you?

### Exercise 9: The 5-second test
If I give you the name of an app, can you say whether it uses OAuth, OIDC, or both? Test on 10 apps: Slack, Notion, GitHub, AWS Console, your bank, your ISP's portal, Spotify, a SaaS you pay for, a SaaS you don't pay for, an open-source dashboard.

### Exercise 10: A confused-deputy in 100 lines
Build a tiny multi-tenant app that uses ONLY OAuth (no OIDC). Demonstrate the confused-deputy: a user from tenant A can access tenant B's data. Then add OIDC with a custom "tenant_id" claim, and show the fix.

---

## 14. Next Step

You now understand what OAuth actually is, who the actors are, and why "OAuth for login" is wrong (use OIDC, which we cover in Stage 3). Next, we go deep on the workhorse flow: Authorization Code + PKCE.

→ [[../stage2/02-auth-code-pkce|Stage 2.2 — Authorization Code + PKCE: The Workhorse]]

**Before you move on, verify you can answer these:**
1. What are the four OAuth actors? Give an example with real products.
2. What is a scope, and why does the principle of least privilege apply to it?
3. Why is OAuth 2.0 NOT an authentication protocol? What do you add to make it one?
4. What's the difference between a Bearer token and a DPoP/mTLS-bound token?
5. Why is the implicit grant deprecated, and what replaced it?
6. Why is ROPC deprecated, and what does the deprecation tell you about password anti-patterns?

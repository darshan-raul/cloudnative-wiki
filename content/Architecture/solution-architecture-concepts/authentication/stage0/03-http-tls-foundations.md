---
title: "0.3 — HTTP & TLS Foundations Every Auth Engineer Must Know"
author: darshan
tags: [authentication, stage-0, http, tls, mtls, cookies, cors, samesite, preflight]
date: 2026-06-13
description: TLS 1.2 vs 1.3, mTLS, cookies vs Authorization header, CORS preflight, SameSite — the transport-layer alphabet for auth
---

# 0.3 — HTTP & TLS Foundations Every Auth Engineer Must Know

> **Goal:** Auth doesn't happen in a vacuum. Tokens travel over HTTP, sessions travel in cookies, and TLS is the transport that (usually) keeps them private. This module covers the transport-layer alphabet: TLS 1.2 vs 1.3, mTLS for service-to-service, the differences between cookies and the `Authorization` header, CORS preflight, and the `SameSite` cookie attribute that breaks half the auth integrations in the wild.

> **Prerequisites:** [[01-crypto-primitives|Stage 0.1]] + [[02-encoding-signing-verification|Stage 0.2]] complete.

---

## Table of Contents

1. [The Transport Layer's Job in Auth](#1-the-transport-layers-job-in-auth)
2. [TLS 1.2 vs 1.3 — What's Actually Different](#2-tls-12-vs-13--whats-actually-different)
3. [mTLS — Mutual Authentication for Services](#3-mtls--mutual-authentication-for-services)
4. [Cookies: Attributes, Flags, Footguns](#4-cookies-attributes-flags-footguns)
5. [The `Authorization` Header: Bearer, Basic, and Friends](#5-the-authorization-header-bearer-basic-and-friends)
6. [CORS and the Preflight Request](#6-cors-and-the-preflight-request)
7. [CSRF: The Cookie-Auth Attack](#7-csrf-the-cookie-auth-attack)
8. [Session vs Token: The Two Models](#8-session-vs-token-the-two-models)
9. [DevOps Analogy: The Building's Front Desk](#9-devops-analogy-the-buildings-front-desk)
10. [Attacks & Pitfalls](#10-attacks--pitfalls)
11. [Exercises](#11-exercises)
12. [Next Step](#12-next-step)

---

## 1. The Transport Layer's Job in Auth

Three jobs, three layers:

| Layer | Job | Examples |
|-------|-----|----------|
| **TLS** (transport) | Encrypt the wire. Server proves its identity. Optionally client proves its. | TLS 1.3, mTLS |
| **HTTP** (application protocol) | Move requests around. Carry auth headers/cookies. | HTTP/1.1, HTTP/2, HTTP/3 |
| **Auth protocol** (application logic) | Issue, validate, refresh, revoke. | OAuth, OIDC, SAML |

**The cardinal rule:** if you skip TLS, none of the rest matters. A signed JWT in plaintext HTTP is a signed JWT that anyone on the network can read AND copy AND replay.

```
The mental model:

  ┌──────────────────────────────────────────────────────────┐
  │  App: "Here's a signed JWT, you can trust it came from   │
  │        the IdP and wasn't tampered with"                  │
  │                                                          │
  │  HTTP: "I'll carry that JWT in my Authorization header   │
  │         (or in a cookie) from the browser to the server" │
  │                                                          │
  │  TLS:  "I'll encrypt the HTTP request so nobody in       │
  │         between can read the JWT or modify it"           │
  └──────────────────────────────────────────────────────────┘

  Skip TLS → all three layers are useless.
  Skip auth protocol → TLS gives you privacy, not identity.
  Skip app layer → you're just doing TLS, no auth.
```

**Modern baseline (2026):** TLS 1.3 everywhere. TLS 1.2 still supported for legacy. TLS 1.0 and 1.1 are gone (RFC 8996, deprecated 2018, removed from major browsers by 2020). SSLv3 is a museum piece.

```
What you'll see in production:
  - TLS 1.3              ← green
  - TLS 1.2 with ECDHE   ← green (ECDHE = forward secret, no RSA key exchange)
  - TLS 1.2 with RSA key exchange ← yellow (no forward secrecy, avoid)
  - TLS 1.1 / 1.0        ← red (compliance violation, browsers reject)
  - SSLv3                ← red (POODLE attack, broken since 2014)
```

---

## 2. TLS 1.2 vs 1.3 — What's Actually Different

### TLS 1.2 (RFC 5246, 2008)

```
Client                                 Server
  │──── ClientHello ────────────────────►│   (cipher suites, key share)
  │                                      │
  │◄── ServerHello ──────────────────────│   (chosen cipher suite)
  │◄── Certificate ──────────────────────│   (server's X.509 cert chain)
  │◄── ServerKeyExchange ────────────────│   (optional, e.g. DHE params)
  │◄── ServerHelloDone ──────────────────│
  │                                      │
  │──── ClientKeyExchange ──────────────►│   (e.g. encrypted pre-master secret)
  │──── ChangeCipherSpec ────────────────►│
  │──── Finished ───────────────────────►│
  │                                      │
  │◄── ChangeCipherSpec ─────────────────│
  │◄── Finished ─────────────────────────│
  │                                      │
  │════ encrypted application data ══════│
```

**Two round-trips** before the first byte of application data. A lot of cipher suite negotiation. Lots of moving parts. Lots of historical bugs (Heartbleed, POODLE, ROBOT, Sweet32 — all in 1.2-era code).

### TLS 1.3 (RFC 8446, 2018)

```
Client                                 Server
  │──── ClientHello + key share ─────────►│   (cipher suites + KEY SHARE)
  │                                      │
  │◄── ServerHello ──────────────────────│
  │◄── EncryptedExtensions ──────────────│
  │◄── Certificate ──────────────────────│   (encrypted!)
  │◄── CertificateVerify ────────────────│
  │◄── Finished ─────────────────────────│
  │                                      │
  │════ encrypted application data ══════│  ← only 1 round trip!
```

**One round-trip** (or zero, with the `0-RTT` mode). Mandatory forward secrecy (no more RSA key exchange — only ECDHE/DHE). All handshake messages after `ServerHello` are encrypted. Removed a pile of legacy cipher suites that were attack-prone.

**The cipher suite list went from ~30 options to 5:**

```
TLS 1.2 had:                          TLS 1.3 has:
  TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256    TLS_AES_128_GCM_SHA256
  TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384    TLS_AES_256_GCM_SHA384
  TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256  TLS_CHACHA20_POLY1305_SHA256
  TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384  TLS_AES_128_CCM_SHA256
  ... and 26 more                        ... and that's it
```

The naming in 1.3 is also much shorter — it only specifies the symmetric cipher and hash. The key exchange (always ECDHE) and authentication (negotiated in extensions) are implied.

### What TLS gives you

| Property | What it means | How |
|----------|---------------|-----|
| **Confidentiality** | Nobody can read the traffic | Symmetric encryption (AES-GCM, ChaCha20-Poly1305) |
| **Integrity** | Nobody can modify the traffic in flight | Authenticated encryption (AEAD) |
| **Server authentication** | Client knows it's talking to the real server | X.509 certificate chain to a trusted CA |
| **(Optional) Client authentication** | Server knows who's calling | Client certificate (mTLS) |

**What TLS does NOT give you:**
- Identity of the *user* (only the *server*, and optionally the *client* as a system)
- Session management (you build that on top)
- Authorization (TLS doesn't know what the user can do)

```
TLS authenticates CONNECTIONS, not USERS.
OIDC authenticates USERS, not CONNECTIONS.
You need both.
```

### Cipher suite quick reference

```
Recommended (TLS 1.3):
  TLS_AES_256_GCM_SHA384       AES-256, GCM mode, SHA-384 PRF
  TLS_AES_128_GCM_SHA256       AES-128, GCM mode, SHA-256 PRF  (default for most)
  TLS_CHACHA20_POLY1305_SHA256 ChaCha20-Poly1305, SHA-256 PRF (mobile/ARM-friendly)

Recommended (TLS 1.2):
  TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384  ECDHE + ECDSA cert
  TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384    ECDHE + RSA cert
  TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305    ECDHE + ECDSA + ChaCha20

Avoid:
  TLS_RSA_WITH_*                ← no forward secrecy, gone in TLS 1.3
  TLS_*_WITH_3DES_*             ← 3DES broken
  TLS_*_WITH_NULL_*             ← no encryption, only useful for debugging
  TLS_*_WITH_RC4_*              ← RC4 broken
  TLS_*_WITH_MD5                ← MD5 broken
```

### Test your TLS configuration

```bash
# Quick test (no install needed)
openssl s_client -connect example.com:443 -tls1_3
openssl s_client -connect example.com:443 -tls1_2

# Comprehensive test
testssl.sh example.com    # or https://www.ssllabs.com/ssltest/
```

A grading rubric for TLS configs:

```
A+  TLS 1.3, TLS 1.2 with ECDHE only, HSTS, HPKP (deprecated), CAA records, OCSP stapling
A   TLS 1.3, TLS 1.2 with ECDHE, HSTS
B   TLS 1.2 with some weak ciphers, no TLS 1.3
C   TLS 1.0/1.1 still supported
F   SSLv3, expired cert, self-signed in prod
```

---

## 3. mTLS — Mutual Authentication for Services

**Normal TLS:** only the server proves its identity. The client is anonymous (or authenticated by other means — password, token, etc.).

**mTLS:** both sides prove their identity with X.509 certificates. The server presents a cert signed by a trusted CA. The client also presents a cert signed by a trusted CA.

```
Normal TLS:
  Client → "Hi, I'm whoever"
  Server → "I'm api.example.com (cert proves it)"
  Connection: encrypted. Server identified. Client not identified by TLS.

mTLS:
  Client → "Hi, I'm service-A (my cert proves it)"
  Server → "I'm api.example.com (my cert proves it)"
  Connection: encrypted. Both identified. Both verified against trusted CAs.
```

**When to use mTLS:**

```
Use mTLS when:
  - Service-to-service in a zero-trust network (no VPN, no perimeter)
  - You need cryptographically strong workload identity
  - You can't rely on network ACLs (multi-cloud, sidecar proxies, mesh)
  - Compliance regime requires it (PCI-DSS for some segments)

Don't use mTLS when:
  - Client is a browser (browsers don't have client certs by default)
  - You need to revoke identity in seconds (cert revocation is slow)
  - You have thousands of clients (cert issuance/distribution is heavy)
  
For browser-facing services, mTLS is too heavy.
For workload-to-workload in a mesh, mTLS is the default.
```

**The cert lifecycle pain:**

```
Day 0:  generate CA
Day 1:  issue cert to service-A, signed by CA
Day 2:  issue cert to service-B, signed by CA
...
Day 365: cert expires. Service-A stops being able to authenticate.
         Alert fires. On-call engineer rotates.
         Repeat 100x for 100 services.

The reason SPIFFE/SPIRE exists (Stage 6.3) is to automate this
without humans in the loop.
```

**Modern mesh implementations (Istio, Linkerd, Consul Connect) do mTLS automatically.** The sidecar proxy handles cert issuance, rotation, and verification. Your app code just sees "incoming connection from service-A" — the cert mechanics are invisible.

```yaml
# Istio PeerAuthentication: enforce mTLS in a namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT  # reject any plaintext or non-mTLS connection
```

**mTLS vs OIDC for service identity:**

```
mTLS:
  ✅ Strong cryptographic identity (cert)
  ✅ Works at L4 (no app-layer changes needed if mesh handles it)
  ❌ Cert lifecycle is heavy
  ❌ Doesn't carry user identity (only workload identity)
  ❌ Browser-hostile
  
OIDC/JWT:
  ✅ Works for browsers, mobile, APIs, CLI
  ✅ Carries user identity + claims
  ✅ Easy to revoke (deny-list the JTI, rotate the key)
  ❌ More app-layer code

Use mTLS for WORKLOAD identity. Use OIDC for USER identity.
In a real system, you usually have both.
```

---

## 4. Cookies: Attributes, Flags, Footguns

A **cookie** is a small piece of data the server asks the browser to store and resend on future requests. It's the original session mechanism (before JWTs, before OAuth).

### Set-Cookie header

```http
HTTP/1.1 200 OK
Set-Cookie: session=abc123; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=3600
```

The browser stores `session=abc123` and resends it on requests matching the path (and other criteria).

### The flags you MUST get right

| Flag | Effect | Why it matters |
|------|--------|----------------|
| **`Secure`** | Only sent over HTTPS | Without this, the cookie goes over plaintext HTTP. Trivially sniffable on a coffee-shop WiFi. |
| **`HttpOnly`** | JavaScript can't read it (`document.cookie` excludes it) | Without this, any XSS bug in your app gives the attacker the session cookie. |
| **`SameSite=Strict`** | Never sent on cross-site requests | Without this, you're vulnerable to CSRF (see Section 7). |
| **`SameSite=Lax`** | Sent on top-level cross-site GETs only | Compromise — most cross-site flows still work, CSRF on POSTs is blocked. |
| **`SameSite=None`** | Always sent on cross-site requests | Required for some third-party cookies, must also have `Secure` (browsers reject `None` without `Secure`). |
| **`Path=/`** | Cookie sent for any path on this domain | The default if you don't set it. Be specific if you have multiple apps on one domain. |
| **`Domain=.example.com`** | Sent to any subdomain | Be careful — `Domain=.example.com` leaks the cookie to `evil.example.com` if that subdomain is compromised. |
| **`Max-Age=3600`** | Expires in 1 hour | Or `Expires=Wed, 21 Oct 2026 07:28:00 GMT`. Use one, not both. |
| **`__Host-` prefix** | Browser enforces: must have `Secure`, no `Domain`, `Path=/` | A free hardening layer. Use `__Host-sessionid=...` if you can. |
| **`__Secure-` prefix** | Browser enforces: must have `Secure` | Weaker than `__Host-` (doesn't enforce path or absence of domain). |

### The `__Host-` prefix trick

```http
# All these are valid:
Set-Cookie: session=abc; Secure; Path=/                    # OK
Set-Cookie: __Secure-session=abc; Secure; Path=/           # browser enforces Secure
Set-Cookie: __Host-session=abc; Secure; Path=/             # browser enforces Secure + Path=/ + no Domain
```

**Use `__Host-` for session cookies.** The browser will refuse to set the cookie if any of the security conditions aren't met. If a misconfigured server tries to set `__Host-session=abc; Domain=.example.com`, the browser silently drops it.

### Cookie scope = blast radius

```
A cookie set with Domain=.example.com is sent to:
  ✓ example.com
  ✓ api.example.com
  ✓ admin.example.com
  ✓ staging.example.com
  ✗ example.com.attacker.com          ← different TLD, OK
  ✗ attacker.com                      ← different domain entirely

A cookie set without Domain is sent to:
  ✓ the exact host that set it
  ✗ other subdomains
  
If you set Domain=.example.com and one of your subdomains is compromised,
the attacker reads the cookie and replays it on api.example.com.
DON'T set Domain unless you absolutely need cross-subdomain auth.
```

### Cookie size limit

```
4KB total per cookie, ~50 cookies per domain.

JWT in a cookie? 3-part JWT is typically 800-2000 bytes.
You can fit 1-2 of them per cookie, max.

If your JWT is 3KB, it's too big for a cookie. Put it in localStorage
or in-memory (with the tradeoffs covered in Stage 5.2).
```

### SameSite decision tree

```
Does your auth flow ever cross origins? (e.g. login on idp.example.com,
  callback to app.example.com)
  │
  ├─ No, everything is same-origin → SameSite=Strict (most secure)
  │
  └─ Yes, cross-origin callback happens
       │
       ├─ Top-level navigation only (typical OIDC redirect) → SameSite=Lax
       │  (this is the default in modern browsers anyway)
       │
       └─ iframe / cross-origin XHR / fetch with credentials
            → SameSite=None; Secure (required for Chrome/Firefox/Safari)
```

---

## 5. The `Authorization` Header: Bearer, Basic, and Friends

The `Authorization` header carries credentials in a single request — no cookie, no persistence on the client side (well, persistence in your JS code).

### Common schemes

| Scheme | Format | Used for |
|--------|--------|----------|
| **`Bearer`** | `Authorization: Bearer eyJhbGci...` | OAuth 2.0 access tokens, OIDC ID tokens, JWTs |
| **`Basic`** | `Authorization: Basic dXNlcjpwYXNz` (base64 of `user:pass`) | Legacy HTTP Basic auth (still common in admin UIs, internal tools) |
| **`Digest`** | `Authorization: Digest username="...", realm="...", ...` | Legacy, more secure than Basic, mostly replaced by Bearer |
| **Mutual** | (client cert, not in header) | mTLS |
| **API Key** | `Authorization: ApiKey abc123` or `X-Api-Key: abc123` | Vendor-specific (Stripe, AWS, etc.) |
| **`HOBA`** | (not widely deployed) | HTTP Origin-Bound Authentication (RFC 7486) |

### Bearer token mechanics

```http
GET /api/users/me HTTP/1.1
Host: api.example.com
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

**The "Bearer" name is literal:** whoever bears (holds) this token is authenticated as the user. There's no proof of possession beyond holding the string. This is why you protect the token as if it were a password.

**If the token is stolen, the thief IS the user** (until the token expires or is revoked).

### Why we use Bearer instead of cookies for APIs

```
Cookie:
  ✓ Auto-attached by browser
  ✓ HttpOnly + Secure + SameSite = strong protection
  ✗ Browser-only (curl, mobile apps, server-to-server need a different way)
  ✗ CSRF concerns
  ✗ Domain/path scoping quirks

Bearer token:
  ✓ Works in any HTTP client (browser, mobile, server, CLI)
  ✓ No CSRF (no automatic attachment)
  ✓ Standardized in OAuth 2.0
  ✗ You have to attach it yourself (Authorization: Bearer ...)
  ✗ Storage is your problem (localStorage vs memory vs cookie)
  ✗ If stolen, no defense (unlike HttpOnly cookie)
```

**Modern best practice: hybrid**

```
Web SPA:
  - Access token (JWT, short-lived, ~5min): in memory
  - Refresh token (opaque, long-lived): in HttpOnly + Secure + SameSite=Strict cookie
  - When access token expires, use refresh token (sent automatically as cookie) to get a new one

Server-to-server:
  - Bearer token in Authorization header
  
Mobile:
  - Access + refresh tokens in OS keychain (Keychain on iOS, Keystore on Android)
```

This pattern is covered in detail in [[../stage5/02-token-storage|Stage 5.2 — Token Storage]].

### Basic auth — quick coverage

```http
GET /admin HTTP/1.1
Authorization: Basic dXNlcjpwYXNz
# dXNlcjpwYXNz is base64("user:pass")
```

**The problem:** base64 is encoding, not encryption. The username and password are recoverable by anyone who sees the header. With TLS this is fine (the wire is encrypted), but you should still:
- Use it only over TLS
- Use it only for service-to-service or admin tools, never for end users
- Prefer Bearer (OAuth) for anything user-facing
- If you must store credentials, store them hashed, not base64

---

## 6. CORS and the Preflight Request

**CORS (Cross-Origin Resource Sharing)** is a browser mechanism that lets a server say which origins can make JS-initiated requests to it. It exists because of the **Same-Origin Policy**: by default, a page on `app.example.com` can't make XHR/fetch requests to `api.example.com`.

### The flow

```
Page: https://app.example.com
JS:   fetch('https://api.example.com/users/me')
      │
      │   Browser checks: are app.example.com and api.example.com the same origin?
      │   No. Different subdomain.
      │   Browser will make a CORS request.
      │
      ├─ Simple request (GET/HEAD/POST with safe headers):
      │  Browser sends the request directly.
      │  Server must respond with Access-Control-Allow-Origin.
      │
      └─ Non-simple request (custom header, JSON body, etc.):
         Browser sends OPTIONS first ("preflight").
         Server must respond to OPTIONS with CORS headers.
         Browser then sends the real request.
```

### Preflight example

```http
# Browser sends this OPTIONS first
OPTIONS /api/users/me HTTP/1.1
Host: api.example.com
Origin: https://app.example.com
Access-Control-Request-Method: GET
Access-Control-Request-Headers: authorization
```

```http
# Server must respond
HTTP/1.1 204 No Content
Access-Control-Allow-Origin: https://app.example.com
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: authorization, content-type
Access-Control-Allow-Credentials: true
Access-Control-Max-Age: 600
```

```http
# Browser then sends the real request
GET /api/users/me HTTP/1.1
Host: api.example.com
Origin: https://app.example.com
Authorization: Bearer eyJ...
```

### CORS headers cheat sheet

| Header | Sent by | Meaning |
|--------|---------|---------|
| `Origin` | Browser (always) | Where the request is coming from |
| `Access-Control-Request-Method` | Browser (preflight) | Method the real request will use |
| `Access-Control-Request-Headers` | Browser (preflight) | Custom headers the real request will use |
| `Access-Control-Allow-Origin` | Server | Allowed origins. `*` (wildcard) or specific origin. |
| `Access-Control-Allow-Methods` | Server (preflight) | Allowed methods |
| `Access-Control-Allow-Headers` | Server (preflight) | Allowed request headers |
| `Access-Control-Allow-Credentials` | Server | `true` to allow cookies/auth headers |
| `Access-Control-Max-Age` | Server (preflight) | How long the browser can cache the preflight response (seconds) |
| `Access-Control-Expose-Headers` | Server | Which response headers the browser can read |

### The CORS gotchas

```
❌  Access-Control-Allow-Origin: *
    Access-Control-Allow-Credentials: true
    
    Browsers REJECT this. You can't have wildcard origin with credentials.
    Either use a specific origin, or don't allow credentials.
    
❌  Access-Control-Allow-Origin: https://app.example.com
    Access-Control-Allow-Origin: https://other.example.com
    
    Browsers REJECT duplicate headers. Pick one origin per request.
    
❌  Building the origin dynamically from the request:
    Access-Control-Allow-Origin: <whatever the request's Origin header was>
    
    This is a "reflected origin" attack. If the server reflects ANY
    Origin header back, attacker sites can make credentialed requests
    to your API.
    
✅  Static list of allowed origins, per environment:
    dev:      http://localhost:3000
    staging:  https://staging.example.com
    prod:     https://app.example.com
```

**CORS is not a security boundary — it's a browser-side request gate.** A non-browser client (curl, Postman, an attacker's server) can make any request they want, ignoring CORS. CORS only protects browser users from malicious JavaScript on third-party sites. Your actual auth is the token validation — CORS is just there to keep browsers from being annoying.

```
The chain of defense:

  CORS                       → stops browser JS from making cross-origin requests
  Bearer token validation    → stops anyone without a valid token
  Token scopes/permissions   → stops valid tokens from doing things they shouldn't
  Server-side input validation → stops malformed requests
  
If your security depends on CORS, you have no security.
If your security depends on token validation alone, you're fine.
CORS is UX, not security.
```

---

## 7. CSRF: The Cookie-Auth Attack

**CSRF (Cross-Site Request Forgery)** is the canonical attack against cookie-based auth. It works because cookies are *automatically* attached by the browser to requests matching their origin/path — and the browser doesn't know whether the request was initiated by you or by JavaScript on a malicious site.

### The attack

```
User is logged into bank.com. Cookie: session=abc123 (Secure, HttpOnly, no SameSite).

User visits evil.com.

evil.com has:
  <form action="https://bank.com/transfer" method="POST">
    <input type="hidden" name="to" value="attacker">
    <input type="hidden" name="amount" value="10000">
  </form>
  <script>document.forms[0].submit()</script>

When the form submits:
  - Browser navigates to https://bank.com/transfer
  - Same origin (bank.com) → cookie is sent
  - bank.com receives the POST with the user's valid session cookie
  - Money moves.
```

**The vulnerability:** the cookie is sent automatically. The browser doesn't know the request was initiated by `evil.com` — the form submission is a top-level navigation, the request *looks* normal.

### The defenses

**1. SameSite cookies (the modern primary defense)**

```
SameSite=Strict:
  Cookie is NEVER sent on cross-site requests.
  Form POST from evil.com → no cookie → bank.com rejects (401/403).
  Side effect: if the user clicks a link from email to your site, the
  session cookie isn't sent on that initial cross-site navigation.
  For OIDC redirects, this can be a problem (see below).

SameSite=Lax:
  Cookie IS sent on top-level cross-site GETs (links, redirects).
  Cookie is NOT sent on cross-site POSTs, XHR, iframes, etc.
  This is the browser default since Chrome 80, Firefox 69, Safari 13.1.
  
  For OIDC auth code flow:
    - User on idp.example.com clicks "Allow" → redirects to app.example.com/callback
    - Top-level navigation = GET
    - SameSite=Lax sends the cookie on the redirect
    - Works. ✓

SameSite=None; Secure:
  Cookie is sent on all cross-site requests.
  Required for some embedded/iframe flows.
  Disables CSRF protection. Don't use unless you have a specific need.
```

**2. CSRF tokens (the traditional defense, still in use)**

```http
GET /transfer HTTP/1.1
→ Server generates random CSRF token, sets in form + in user's session

POST /transfer HTTP/1.1
Cookie: session=abc123
X-CSRF-Token: xyz789
→ Server checks: X-CSRF-Token in request matches the one stored in session
→ If no match, reject.
```

The attacker's form on `evil.com` doesn't know the CSRF token (it's per-session, not in any cookie the attacker can read), so the forged request fails.

**3. Double-submit cookie pattern**

```
Server sets a non-HttpOnly cookie: csrf=xyz789
Server also embeds the same value in a hidden form field or returns it via an API.
Client sends BOTH:
  - Cookie: session=abc123; csrf=xyz789
  - Header: X-CSRF-Token: xyz789
Server checks: cookie value == header value
```

Attacker on `evil.com` can trigger a form submit that sends the cookie (auto), but can't read the cookie value (HttpOnly on the session, but the CSRF cookie is intentionally non-HttpOnly so JS can read it) and can't set a matching header.

**4. Origin/Referer checking**

```python
# Server-side: check that Origin or Referer matches expected
if request.headers.get("Origin") not in {"https://app.example.com"}:
    return 403
```

The browser always sends `Origin` on POSTs (and most modern browsers send `Referer` too, though it's being deprecated for privacy). Attacker JS can't fake `Origin` on a cross-origin request.

**5. Custom request header (Bearer, not cookies)**

```
If you use Authorization: Bearer <token> instead of cookies:
  - No automatic attachment
  - The browser won't add the Authorization header to a cross-origin request
    unless the JS explicitly does so
  - The malicious form on evil.com can't include an Authorization header
  - CSRF doesn't work
```

**This is why "use Bearer tokens, not cookies" is the modern CSRF defense for SPAs.** You still need a place to put the refresh token, and that's where the HttpOnly cookie comes in — and that cookie is SameSite=Strict, so it can't be triggered cross-site.

```
Modern auth architecture (CSRF-free):

  SPA at app.example.com
    │
    ├─ Login: redirect to idp.example.com, OAuth code flow
    ├─ Receive access token (JWT) in URL fragment or via postMessage
    ├─ Store access token in MEMORY (not localStorage)
    ├─ Refresh token in HttpOnly + Secure + SameSite=Strict cookie
    │   (the cookie can only be sent on first-party requests)
    │
    └─ API calls:
        fetch('https://api.example.com/users/me', {
          headers: { 'Authorization': 'Bearer ' + accessToken }
        })
        
        No CSRF token needed.
        No SameSite=None needed.
        The access token is sent explicitly by JS, not auto-attached by the browser.
```

### When you DO need CSRF tokens

```
  - Server-rendered apps (PHP, Rails, Django, etc.) with cookie-based sessions
  - Old SPAs that store the JWT in a cookie instead of in memory
  - Anything where the auth credential is auto-attached by the browser
  - POST endpoints that accept form-encoded data with cookies
```

---

## 8. Session vs Token: The Two Models

Two fundamentally different ways to track "who is this user?" across HTTP requests.

### Session model (stateful, server-side)

```
User logs in
  → Server creates a session record: {session_id: "abc123", user_id: 1, expires: ...}
  → Server stores it (memory, Redis, DB)
  → Server sets a cookie: session=abc123

Subsequent request
  → Browser sends Cookie: session=abc123
  → Server looks up "abc123" in the session store
  → Server finds the user, proceeds

Logout
  → Server deletes the session record
  → Server clears the cookie
  → Next request with the old cookie: server says "I don't know you"
  → (Even if the cookie is stolen, it's now invalid)
```

**Characteristics:**
- ✅ Server has full control — can revoke instantly
- ✅ Cookie is opaque — no info leak
- ✅ Simple mental model
- ❌ Server must store state (Redis, DB)
- ❌ Hard to scale (need shared session store)
- ❌ Doesn't work well for cross-domain (third-party cookies dying)
- ❌ Doesn't work for native mobile apps

### Token model (stateless, client-side)

```
User logs in
  → Server validates credentials
  → Server creates a JWT: {sub: "user-1", exp: ..., role: "admin"}
  → Server signs the JWT and returns it
  → Client stores it (in memory, localStorage, or cookie)

Subsequent request
  → Client sends Authorization: Bearer <JWT>
  → Server verifies the signature
  → Server checks claims (exp, iss, aud, ...)
  → Server uses the claims (no DB lookup)
  → Server proceeds

Logout
  → Client deletes the token from memory
  → Server doesn't know (token is still valid until exp)
  → For instant revocation, need a denylist (jti) or short-lived tokens
```

**Characteristics:**
- ✅ Stateless — server doesn't need to store anything
- ✅ Works across domains naturally
- ✅ Works for mobile / native / CLI
- ✅ Self-contained — claims are in the token
- ❌ Can't revoke instantly (token valid until exp)
- ❌ Compromise means "game over" until exp (or denylist)
- ❌ If stored in localStorage, XSS = game over
- ❌ Larger request payload

### When to use which

```
Use SESSIONS when:
  - Single-domain web app
  - Server-rendered (PHP, Rails, Django, etc.)
  - You need instant revocation
  - Compliance requires server-side audit of active sessions

Use TOKENS (JWT) when:
  - SPA, mobile, or API
  - Multi-domain / cross-origin
  - You need stateless verification (every microservice can verify without DB)
  - Workload identity (SPIFFE does this for non-human identities)

Use BOTH (hybrid):
  - Web app with cookie session for the browser
  - JWT for API-to-service calls
  - Best of both worlds
```

**The trend in 2026:** hybrid. Access token in memory, refresh token in HttpOnly + Secure + SameSite=Strict cookie. Effectively a session for the long-lived credential, a token for the short-lived one.

---

## 9. DevOps Analogy: The Building's Front Desk

Imagine a corporate office building.

| Concept | Office equivalent |
|---------|-------------------|
| **TLS** | The encrypted radio between the front desk and the visitor's car. Eavesdroppers hear static. |
| **Server cert** | The front desk's employee ID badge. Verified against the company's HR records (CA chain). |
| **Client cert (mTLS)** | The visitor's ID badge. Also verified against the company directory. |
| **Cookie** | A visitor sticker the front desk gives you. You flash it on subsequent visits — they recognize the sticker, not you. |
| **`HttpOnly` cookie** | A sticker that the visitor can't physically take off and show anyone else. Stays on your lapel. |
| **`Secure` cookie** | A sticker that only works in the main lobby (HTTPS). Useless if you walk into the parking lot (HTTP). |
| **`SameSite=Strict` cookie** | A sticker that only works if you entered through the front door of THIS building. Doesn't work if you came from a connecting skybridge from another building. |
| **`Authorization: Bearer` header** | A security code you speak aloud. Anyone within earshot who knows the code is you. |
| **CORS** | The building policy: "if a request comes from a person standing in the parking lot of building B, you must check the visitor's invite before letting them in." |
| **CSRF** | Attacker tricks you into walking from building B to building A and submitting a form on your behalf. The sticker goes with you automatically. |
| **Session** | A paper log at the front desk: "visitor ID, name, signed in at, signed out at." |
| **Token (JWT)** | A tamper-evident badge you print yourself at check-in. Has your name + expiry. Front desk verifies the badge, not the log. |
| **OIDC** | A single sign-on system: one central check-in desk (the IdP) that issues badges accepted by all the other buildings (SPs). |

**The TL;DR for sysadmins:**
- **TLS** is the encrypted radio. Use it. Always.
- **Cookies** are stickers. Use `HttpOnly` + `Secure` + `SameSite=Strict` (or `Lax` if you need cross-site GETs to work).
- **`Authorization: Bearer`** is a spoken code. Use it for APIs. Use `localStorage` for the access token only if you accept the XSS trade-off (covered in Stage 5.2).
- **CORS** is a courtesy. It's not security. Your real security is the token validation.
- **CSRF** is the reason you put `SameSite` on cookies, or use Bearer headers instead.
- **mTLS** is the encrypted radio where both sides have ID badges. Use it for service-to-service.

---

## 10. Attacks & Pitfalls

### A1. Cookies without `Secure` over mixed HTTP/HTTPS

```
Dev:    http://localhost:3000   (HTTP, no Secure)
Staging: https://staging.example.com  (HTTPS)
Prod:   https://app.example.com  (HTTPS)

If you set the cookie with Secure in dev, it won't be set.
So you "just disable Secure in dev" — and forget to re-enable in prod.

Result: cookie is sent over plaintext HTTP. Stealable on any WiFi.
```

**Fix:** use environment-specific config that fails closed. No `Secure` in dev = warning + log. `Secure` in prod = mandatory.

### A2. Cookies with `Domain=.example.com` (subdomain leak)

```
Set-Cookie: session=abc; Domain=.example.com; Secure; HttpOnly

If attacker compromises:
  - blog.example.com (WordPress, 3-year-old plugin)
  - staging.example.com (developer left a key)
  - any old subdomain nobody remembered
  
They get the session cookie sent to api.example.com.
```

**Fix:** set the cookie to the exact host. Don't set `Domain` unless you have a specific cross-subdomain auth requirement (and even then, use `__Host-` prefix to enforce it).

### A3. CORS reflecting `Origin`

```python
# ❌ CATASTROPHICALLY WRONG
def cors_headers(request):
    origin = request.headers.get("Origin")
    return {
        "Access-Control-Allow-Origin": origin,  # ← reflects whatever
        "Access-Control-Allow-Credentials": "true"
    }

# Attacker site evil.com makes credentialed request to api.example.com
# Browser sends Origin: https://evil.com
# Server reflects: Access-Control-Allow-Origin: https://evil.com
# Browser allows the response (CORS check passes)
# Attacker reads the response (with the user's session)
```

**Fix:** static list of allowed origins. Reflected origins + credentials = universal CSRF.

### A4. Wildcard CORS + credentials

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true

Browser says: no.
The spec says: if Allow-Credentials is true, Allow-Origin MUST be a specific origin.
Browsers enforce this.
```

### A5. Missing preflight caching

```http
# Server responds to preflight without Max-Age
Access-Control-Allow-Origin: https://app.example.com
Access-Control-Allow-Methods: GET, POST
# (no Access-Control-Max-Age)

# Browser re-preflights EVERY request. Slow.
```

```http
# Better
Access-Control-Allow-Max-Age: 600
# Browser caches preflight for 10 minutes.
```

Be careful: a long `Max-Age` means changes to your CORS policy don't take effect immediately. 5-15 minutes is a reasonable balance.

### A6. TLS with expired certs

```
Browsers: hard error, no bypass in production
CLI tools: usually bypassable with -k, --insecure
Backend: depends — some libraries bypass by default, some don't

Configure: cert auto-renewal via Let's Encrypt or cert-manager.
Alert: when cert is < 30 days from expiry.
Test: external monitoring (not just from inside the network).
```

### A7. TLS with weak ciphers

```
Old server config:
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers HIGH:!aNULL:!MD5;
  
"HIGH" includes a lot of bad stuff. Use Mozilla's intermediate profile:
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
```

Or just use a maintained config: [[https://ssl-config.mozilla.org|Mozilla SSL Config Generator]].

### A8. JWT in a cookie (cross-site + no SameSite)

```
App: app.example.com
JWT in cookie, no SameSite set
Browser default in 2026 is SameSite=Lax (since Chrome 80)
So the cookie is sent on top-level GETs only

But: if you explicitly set SameSite=None (for an iframe flow), and forget Secure,
browsers reject the cookie.

Or: if the JWT is in localStorage (not a cookie), and you have an XSS,
the attacker exfiltrates the JWT via fetch to their server.
```

**This is why the modern architecture (access token in memory, refresh token in HttpOnly + Secure + SameSite=Strict cookie) matters.**

### A9. `Authorization: Bearer` logged by middleboxes

```
Reverse proxy (nginx) access log:
  $request = "GET /api/users/me HTTP/1.1"
  
If you log $request, the JWT is in your logs.
Logs go to: ELK, S3, CloudWatch, anywhere.
Anyone with log access has every user's token.

Fix: log only the request line, not the headers. Or strip Authorization before logging.
```

```nginx
# nginx: don't log Authorization
log_format main '$remote_addr - $remote_user [$time_local] '
                '"$request" $status $body_bytes_sent '
                '"$http_referer" "$http_user_agent"';
# Note: no $http_authorization. Don't add it.
```

### A10. HSTS not set

```
HSTS (HTTP Strict Transport Security):
  Strict-Transport-Security: max-age=31536000; includeSubDomains; preload

If you don't set HSTS:
  1. User types http://example.com
  2. Browser sends plaintext request
  3. Attacker MITM (on a coffee shop WiFi) intercepts, serves their content
  4. Downgrade attack succeeds

If you set HSTS:
  1. User types http://example.com
  2. Browser remembers "I should always use HTTPS for this domain"
  3. Browser sends HTTPS request directly (no plaintext round trip)
  4. MITM can't downgrade
```

**HSTS preload:** submit your domain to the Chrome HSTS preload list. The browser ships with the list, so even first-visit gets HTTPS.

---

## 11. Exercises

### Exercise 1: Inspect your browser's cookies
Open DevTools → Application → Cookies. For each cookie on a site you're logged into, check: Secure? HttpOnly? SameSite? Domain? Path? Expiry? Are they all correct? What would break if you set SameSite=Strict on the session cookie?

### Exercise 2: Decode a real request
```bash
curl -v https://httpbin.org/headers
```
Look at the request and response headers. What's the TLS version? Cipher suite? HSTS? CORS headers?

### Exercise 3: Trigger a CORS preflight
```bash
# Simple request — no preflight
curl -v https://api.example.com/users

# Non-simple — preflight required (because of Authorization header)
curl -v -X GET https://api.example.com/users \
     -H "Authorization: Bearer abc" \
     -H "Origin: https://app.example.com"
```
Compare the OPTIONS preflight to the actual GET.

### Exercise 4: Test your TLS config
```bash
# Quick check
openssl s_client -connect yourdomain.com:443 -tls1_3 </dev/null 2>&1 | grep -E "Protocol|Cipher"

# Comprehensive (no install)
# Use https://www.ssllabs.com/ssltest/ (online)
# Or install testssl.sh: https://github.com/drwetter/testssl.sh
```

### Exercise 5: Build a cookie-based session (Node.js, 20 lines)
```javascript
const express = require('express');
const cookieParser = require('cookie-parser');
const crypto = require('crypto');
const app = express();
app.use(cookieParser());

const sessions = new Map();

app.post('/login', (req, res) => {
  const sessionId = crypto.randomBytes(32).toString('hex');
  sessions.set(sessionId, { user: 'alice', created: Date.now() });
  res.cookie('session', sessionId, {
    httpOnly: true,
    secure: true,         // HTTPS only
    sameSite: 'strict',   // no cross-site
    maxAge: 3600000,      // 1 hour
  });
  res.send('logged in');
});

app.get('/me', (req, res) => {
  const session = sessions.get(req.cookies.session);
  if (!session) return res.status(401).send('unauthorized');
  res.json(session);
});

app.listen(3000);
```
Run it, hit `/login`, hit `/me`, examine the `Set-Cookie` header. Try accessing `/me` from a different origin (with `Origin: https://evil.com`) — does `SameSite=Strict` block it? (SameSite only affects browsers, not curl, but you get the idea.)

### Exercise 6: Read a CVSS 9.0 TLS CVE
Find a recent TLS-related CVE. Was it protocol-level (TLS 1.0/1.1), implementation-level (OpenSSL, BoringSSL), or configuration-level (weak cipher suite)? What was the fix? What's the modern equivalent?

### Exercise 7: Audit your own auth flow
Pick a web app you've built. Draw the request flow: where does the user authenticate? Where does the token live? How does it get to the API? Is TLS enforced? Are cookies configured correctly? Is CORS configured with a static allowlist? If you find issues, you have a 5-item backlog.

---

## 12. Next Step

You now have the cryptographic alphabet (Stage 0.1), the encoding/signing mechanics (Stage 0.2), and the transport-layer alphabet (Stage 0.3). With these, you're ready to read and understand JWT, OAuth, and OIDC at a deep level.

→ [[../stage1/01-jwt-anatomy|Stage 1.1 — JWT Anatomy: Header.Payload.Signature]]

**Before you move on, verify you can answer these:**
1. What's the difference between TLS 1.2 and TLS 1.3 in one sentence?
2. What does mTLS add on top of normal TLS, and when do you use it?
3. What are the three flags you should always set on a session cookie, and what do they do?
4. What does the CORS preflight do, and when is it sent?
5. What's the difference between session and token auth, and what's the modern hybrid approach?
6. Why is `Access-Control-Allow-Origin: *` incompatible with credentials?

---
title: Security
tags: [security, zero-trust, devsecops]
date: 2025-05-24
description: Security architecture patterns, zero-trust, and secure-by-design principles
---

# Security

Security is not a feature you add at the end — it's a **structural property** of the architecture. Design it in from the start.

---

## What's Here

- [[security]] — CIA triad, zero-trust, common security patterns
- [[shift-left]] — Moving security earlier in the delivery lifecycle
- [[totp]] — How TOTP (Google Authenticator-style) works under the hood

---

## CIA Triad

| Property | What It Means | Example Control |
|----------|---------------|-----------------|
| **Confidentiality** | Only authorized access | Encryption at rest, RBAC |
| **Integrity** | Data not tampered with | Digital signatures, checksums |
| **Availability** | System stays up | DDoS protection, redundancy |

---

## Zero Trust Principles

**Never trust, always verify.**

```
Traditional:                       Zero Trust:
"inside the network" = trusted    "identity is the perimeter"
"outside" = untrusted             every request is untrusted by default
```

1. **Identity is the perimeter** — not IP or network location
2. **Least privilege** — minimum access required, always
3. **Microsegmentation** — divide network into small zones
4. **Inspect all traffic** — no "internal" traffic bypass

---

## Quick Links

| Topic | When to Read |
|-------|-------------|
| [[totp]] | Understanding how2FA / TOTP works |
| [[shift-left]] | Integrating security into CI/CD |
| [[security]] | Deep dive on patterns and checklist |

---

## Related

- [[../foundations/software-planning]] — ADRs for security decisions
- [[../authentication/README]] — Auth patterns (OAuth2, OIDC, SAML)
- [[../cryptography/README]] — PKI, TLS, signing

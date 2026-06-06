---
title: Cryptography
tags: [cryptography, tls, pki, security]
date: 2025-05-24
description: PKI, TLS, certificate management, and signing
---

# Cryptography

Practical cryptography for solution architects — **not** deep math, but the patterns and tooling you need to design secure systems.

---

## What's Here

- [[pki]] — Public Key Infrastructure, certificate authorities, certificate chains
- [[keystore]] — Managing keys and certificates ( keystore, truststore, HSM)
- [[signing-and-verifying]] — Digital signatures, message integrity, code signing

---

## Quick Reference

### TLS Termination

```
Client ──[TLS]──▶ Load Balancer ──[mTLS]──▶ Service A
                   (terminates TLS)      (service verifies client cert)
```

### Certificate Types

| Type | What It Is | Example |
|------|-----------|---------|
| Root CA | Self-signed, trusted by everyone | DigiCert Root |
| Intermediate CA | Signed by root, signs leaf certs | Let's Encrypt R3 |
| Leaf certificate | End-entity cert, used by services | `api.example.com` |
| Wildcard | Covers all subdomains | `*.example.com` |

### Key Exchange

| Algorithm | Use | Notes |
|-----------|-----|-------|
| RSA | Key exchange + signatures | Legacy, being phased out |
| ECDH | Key exchange (P-256, P-384) | Modern, fast |
| EdDSA | Signatures (Ed25519, Ed448) | Modern, recommended |

---

## Related

- [[../security/security]] — Security architecture context
- [[../authentication/README]] — Auth patterns built on cryptography
- [[../networking/tcpip]] — The transport layer TLS runs on

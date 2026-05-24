---
title: Network Security
tags: [network, security, tls, vpn, zero-trust]
date: 2025-05-24
description: Network security - TLS/mTLS, zero trust, VPN, firewall, and network segmentation
---

# Network Security

Network security — TLS/mTLS, zero trust architecture, VPN, firewall, and network segmentation.

## Key Concepts

### Zero Trust Principles

1. **Never trust, always verify** — Every request is authenticated
2. **Least privilege access** — Just-in-time access, just-enough permissions
3. **Assume breach** — Limit blast radius, segment everything
4. **Verify explicitly** — Pull context from identity, device, location

### TLS/mTLS

```bash
# Generate self-signed cert for testing
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes

# mTLS - client and server certificates
openssl req -newkey rsa:4096 -keyout client-key.pem -out client.csr
openssl x509 -req -in client.csr -CA ca.pem -CAkey ca-key.pem -out client-cert.pem
```

## Related

- [[Security/endpoint-security/README|Endpoint Security]] — Host-based network protection
- [[Architecture/solution-architecture-concepts/authentication/README|Auth]] — Identity-based access
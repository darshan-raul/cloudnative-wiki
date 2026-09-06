---
title: "Stage 6 — Production, Scale, Frontier"
tags: [authentication, stage-6, ha, performance, zero-trust, spiiffe, dpop, par, fapi, oid4vci]
date: 2026-06-13
description: HA identity, edge auth performance, zero-trust with SPIFFE, emerging standards — DPoP, PAR, RAR, FAPI 2.0, OID4VCI
---

# Stage 6 — Production, Scale, Frontier

> **Goal:** Ship identity that doesn't go down, doesn't leak, and is ready for the next 5 years of standards.

**Prerequisites:** [[../stage5/README|Stage 5]] complete.

## Modules

| # | Module | Why it matters | Exit criterion |
|---|--------|----------------|----------------|
| [[01-ha-identity\|6.1 HA Identity: Multi-Region, DR]] | Active/active IdP, JWKS replication, regional failover, RTO/RPO for auth | Your auth survives a region loss without user-visible impact |
| [[02-performance-edge\|6.2 Performance: Caching, Edge Auth]] | Token caching, JWKS caching, OPA at the edge, cost per million auth | Your p99 token verification is < 5ms and your IdP isn't the bottleneck |
| [[03-zero-trust-spiiffe\|6.3 Zero-Trust & Workload Identity]] | BeyondCorp, SPIFFE/SPIRE, OIDC federation (k8s → AWS, GitHub Actions → GCP) | Your workloads have cryptographic identity, not just network ACLs |
| [[04-emerging-standards\|6.4 Emerging Standards]] | DPoP, PAR, RAR, FAPI 2.0, OID4VCI, OID4VP | You know what's coming and can plan a migration |

## Connections

→ **Capstone:** [[../capstone/README|Capstone]] — the Keycloak reference lab ties Stages 0-6 into one buildable system.

## Quick Reference

```
HA identity:
  - Active/active IdP (Keycloak, Okta) → regional failover via DNS
  - Replicated JWKS → every region serves its own keys
  - DR runbook → tested quarterly, not annually
  - RTO for auth = 0 minutes (regional) / 1 hour (full DR)
  - RPO for auth = 0 (sessions, tokens are stateless)

Edge auth:
  - Verify JWT at CDN edge (Cloudflare Workers, Lambda@Edge)
  - Cache JWKS in CDN KV (TTL = key rotation interval)
  - OPA/Rego for fine-grained policy at the edge
  - Cost = 1 IdP call per JWKS rotation, not per request

Zero-trust workload identity:
  - SPIFFE = Secure Production Identity Framework For Everyone
  - SPIRE = the runtime that issues SPIFFE IDs
  - OIDC federation = k8s service account → AWS IAM, GCP SA, Azure MI
  - No more static credentials in CI/CD

Emerging (2024-2026):
  DPoP (RFC 9449)   → sender-constrained access tokens
  PAR (RFC 9126)    → Pushed Authorization Requests
  RAR (RFC 9396)    → Rich Authorization Requests
  FAPI 2.0          → Financial-grade API profile
  OID4VCI           → OpenID for Verifiable Credentials Issuance
  OID4VP            → OpenID for Verifiable Presentations
```

## Status

- [ ] [[01-ha-identity|6.1 HA Identity: Multi-Region, DR]]
- [ ] [[02-performance-edge|6.2 Performance: Caching, Edge Auth]]
- [ ] [[03-zero-trust-spiffe|6.3 Zero-Trust & Workload Identity]]
- [ ] [[04-emerging-standards|6.4 Emerging Standards]]

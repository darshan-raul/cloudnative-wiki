---
title: "Stage 4 — Federation, SSO, SAML 2.0, B2B"
tags: [authentication, stage-4, sso, federation, saml, scim, b2b, b2c, multi-tenant]
date: 2026-06-13
description: SSO patterns, SAML 2.0 deep dive, SCIM provisioning, multi-tenant identity, vendor comparison, B2B federation
---

# Stage 4 — Federation, SSO, SAML 2.0, B2B

> **Goal:** Make multiple apps feel like one product — securely — and bridge to legacy SAML IdPs, partner federations, and B2B customer orgs without painting yourself into a corner.

**Prerequisites:** [[../stage3/README|Stage 3]] complete (OIDC).

## Modules

| # | Module | Why it matters | Exit criterion |
|---|--------|----------------|----------------|
| [[01-sso-patterns\|4.1 SSO Patterns]] | SP-initiated, IdP-initiated, JIT provisioning | You can defend an SSO architecture to a CISO and a CFO |
| [[02-saml-deep-dive\|4.2 SAML 2.0 Deep Dive]] | Assertions, AuthnRequest, Response, metadata, signing, encryption, OIDC interop | You can integrate a legacy SAML IdP and bridge to OIDC |
| [[03-scim-provisioning\|4.3 SCIM 2.0]] | `/Users`, `/Groups`, JIT vs SCIM, deprovisioning | A contractor's last-day access is gone within minutes, not weeks |
| [[04-multi-tenant-b2b-b2c\|4.4 Multi-Tenant: B2B vs B2C]] | Org claims, tenant isolation, IdP-of-IdPs | Your customers can bring their own IdP without code changes |
| [[05-idp-vendor-comparison\|4.5 IdP Vendor Comparison]] | Cognito, Entra External ID, Auth0, Okta, Keycloak, WorkOS | You can pick the right vendor (or self-host Keycloak) for the job |
| [[06-b2b-federation\|4.6 B2B Federation & Trust Frameworks]] | Trust frameworks, entity statements, expiring federations | You can onboard a partner org in hours, not weeks |

## Connections

→ **Next:** [[../stage5/README|Stage 5 — Security, Attacks, Hardening]] — knowing the SSO architecture is half the battle; knowing the attack surface is the other half.

## Quick Reference

```
SSO patterns:
  SP-initiated (recommended) → user hits app, app redirects to IdP
  IdP-initiated (legacy)     → user starts at IdP portal, IdP pushes assertion
  Just-in-time provisioning  → user created on first login (use SCIM instead)

SAML 2.0 (legacy but alive):
  - XML-based assertions (signed + optionally encrypted)
  - AuthnRequest / Response / LogoutRequest / LogoutResponse
  - Metadata exchange for trust setup
  - Still dominates enterprise, government, healthcare
  - Bridge to OIDC via Keycloak, Okta, Auth0

SCIM 2.0 (provisioning):
  - REST API for user/group lifecycle
  - Use SCIM, not JIT, for any org with > 5 users
  - Deprovisioning is the security-critical path

B2B vs B2C:
  B2C → your users, your IdP, simple claims
  B2B → customer's IdP, per-tenant config, JIT or SCIM
  Workload → SPIFFE/SPIRE, not OIDC (see Stage 6.3)
```

## Status

- [ ] [[01-sso-patterns|4.1 SSO Patterns]]
- [ ] [[02-saml-deep-dive|4.2 SAML 2.0 Deep Dive]]
- [ ] [[03-scim-provisioning|4.3 SCIM 2.0]]
- [ ] [[04-multi-tenant-b2b-b2c|4.4 Multi-Tenant: B2B vs B2C]]
- [ ] [[05-idp-vendor-comparison|4.5 IdP Vendor Comparison]]
- [ ] [[06-b2b-federation|4.6 B2B Federation & Trust Frameworks]]

---
title: "4.5 — IdP Vendor Comparison: Cognito, Entra, Auth0, Okta, Keycloak, and WorkOS"
author: darshan
tags:
  [
    authentication,
    stage-4,
    idp,
    cognito,
    auth0,
    okta,
    keycloak,
    workos,
    entra,
    comparison,
  ]
date: 2026-06-13
description: Architectural and economic comparison of identity platforms — AWS Cognito, Microsoft Entra External ID, Auth0/Okta, Keycloak, and WorkOS across protocol support, B2B multi-tenancy, and TCO
---

# 4.5 — IdP Vendor Comparison: Cognito, Entra, Auth0, Okta, Keycloak, and WorkOS

> **Goal:** Evaluate the leading Identity Provider platforms with technical rigor and financial awareness. Avoid multi-million-dollar vendor lock-in traps, understand the "SSO Tax," and choose the optimal identity foundation for your architecture.

> **Prerequisites:** [[01-sso-patterns|Stage 4.1]] through [[04-multi-tenant-b2b-b2c|Stage 4.4]].

---

## Table of Contents

1. [The Identity Buy-vs-Build Calculus](#1-the-identity-buy-vs-build-calculus)
2. [The "Enterprise SSO Tax" Phenomenon](#2-the-enterprise-sso-tax-phenomenon)
3. [The Contenders: Architectural Profiles](#3-the-contenders-architectural-profiles)
4. [In-Depth Platform Evaluations](#4-in-depth-platform-evaluations)
5. [The Comprehensive Comparison Matrix](#5-the-comprehensive-comparison-matrix)
6. [Total Cost of Ownership (TCO) & Pricing Curves](#6-total-cost-of-ownership-tco--pricing-curves)
7. [Decision Framework: Selecting Your Identity Engine](#7-decision-framework-selecting-your-identity-engine)
8. [Exercises & Verification](#8-exercises--verification)
9. [Next Step](#9-next-step)

---

## 1. The Identity Buy-vs-Build Calculus

Building production authentication from scratch is universally recognized as an anti-pattern. Between password hashing, MFA, WebAuthn, OAuth 2.1 compliance, SAML XML parsing, SCIM synchronization, and audit logging, identity engineering consumes quarters of engineering time and exposes systems to critical CVEs.

However, **buying the wrong identity provider is equally dangerous**. Migration costs between IdPs are catastrophic because passwords cannot be exported in plain text and customer IT teams must reconfigure production SSO metadata.

---

## 2. The "Enterprise SSO Tax" Phenomenon

Many commercial SaaS vendors charge a 200% to 500% price premium just to unlock SAML/OIDC SSO for enterprise plans (documented by [sso.tax](https://sso.tax/)).

Similarly, IdP vendors often lock B2B multi-tenancy, custom domains, and SCIM behind exorbitant enterprise tiers. When evaluating vendors, **always analyze pricing at 1,000, 50,000, and 500,000 Monthly Active Users (MAU)**, including enterprise SAML connection fees.

---

## 3. The Contenders: Architectural Profiles

```
┌────────────────────────────────────────────────────────┐
│ Cloud Managed (General) │ Cloud Managed (B2B Focused)  │
│  - AWS Cognito          │  - WorkOS / BoxyHQ           │
│  - Microsoft Entra ID   │                              │
├─────────────────────────┼──────────────────────────────┤
│ Commercial Enterprise   │ Open Source / Self-Hosted    │
│  - Auth0 / Okta         │  - Keycloak                  │
│                         │  - Ory (Kratos/Hydra)        │
└────────────────────────────────────────────────────────┘
```

---

## 4. In-Depth Platform Evaluations

### 1. AWS Cognito

- **Strengths:** Native integration with AWS API Gateway, ALB, and IAM Roles. Very generous free tier (50,000 MAU free for Cognito User Pools). Extremely low cost per MAU at high scale.
- **Weaknesses:** Clunky UI, rigid customization capabilities, primitive SAML attribute mapping, difficult multi-region active-active setups.
- **Best Fit:** Serverless and microservice workloads built strictly inside AWS where cost efficiency outweighs developer ergonomics.

### 2. Auth0 (by Okta)

- **Strengths:** Industry benchmark for developer experience. Superb documentation, drop-in SDKs, rich extensibility via Auth0 Actions (JavaScript serverless functions running inside the auth pipeline).
- **Weaknesses:** Severe pricing cliff. As MAU scales or enterprise SAML connections grow, monthly bills escalate rapidly. Vendor lock-in on custom rules.
- **Best Fit:** Fast-moving venture-backed startups and enterprises prioritizing rapid time-to-market over operational infrastructure costs.

### 3. Microsoft Entra External ID (formerly Azure AD B2C)

- **Strengths:** Seamless enterprise integration for organizations heavily invested in Microsoft 365 and Azure. Enterprise-grade compliance (FedRAMP High, HIPAA).
- **Weaknesses:** Complex XML-based custom trust frameworks (Identity Experience Framework) are notoriously difficult to debug and maintain.
- **Best Fit:** Large enterprise environments standardized on Microsoft cloud infrastructure.

### 4. Keycloak (Open Source / Red Hat)

- **Strengths:** Fully open source (Apache 2.0). Complete feature set: OIDC, OAuth 2.0, SAML 2.0, Kerberos, SCIM integration, multi-realm tenancy, user federation (LDAP/AD). Zero licensing fees. Can be self-hosted in any cloud or on-prem Kubernetes cluster.
- **Weaknesses:** You own the infrastructure, database clustering (Infinispan), backups, zero-downtime upgrades, and security patching.
- **Best Fit:** Enterprises with strict data residency mandates (GDPR, air-gapped environments) and platform engineering teams capable of running HA stateful services.

### 5. WorkOS

- **Strengths:** Purpose-built for B2B SaaS. Implements an abstraction layer over SSO (SAML/OIDC), Directory Sync (SCIM), Audit Logs, and Multi-factor auth. Connects to your existing auth system via standard OIDC.
- **Weaknesses:** Not a standalone user directory (relies on your auth system for core user tables). Flat fee per active enterprise SSO connection.
- **Best Fit:** B2B SaaS applications that already have username/password or social auth, but need to unlock Fortune 500 enterprise SSO and SCIM overnight.

---

## 5. The Comprehensive Comparison Matrix

| Capability                | AWS Cognito         | Auth0 (Okta)         | Entra External ID     | Keycloak                 | WorkOS                |
| :------------------------ | :------------------ | :------------------- | :-------------------- | :----------------------- | :-------------------- |
| **Hosting Model**         | Fully Managed (AWS) | Fully Managed (SaaS) | Fully Managed (Azure) | **Self-Hosted (K8s/VM)** | Fully Managed (SaaS)  |
| **OIDC / OAuth 2.0**      | Yes                 | Yes                  | Yes                   | Yes                      | Yes                   |
| **SAML 2.0 IdP / SP**     | SP only             | Both                 | Both                  | **Both**                 | SP Broker only        |
| **SCIM 2.0 Server**       | No                  | Enterprise Tier      | Yes                   | Via Extensions           | **Native Out-of-Box** |
| **Multi-Tenancy**         | Multi-Pool          | Organizations        | Multi-Tenant          | **Multi-Realm**          | Org-First Model       |
| **Custom Pipeline Hooks** | Lambda Triggers     | Auth0 Actions (Node) | Custom XML Policies   | **Java SPI / Scripting** | Webhooks              |
| **Data Sovereignty**      | AWS Regions         | Cloud Regions        | Azure Regions         | **Anywhere / On-Prem**   | US/EU Cloud           |
| **Free Tier**             | 50,000 MAU          | 7,500 MAU            | 50,000 MAU            | **Unlimited (FOSS)**     | Dev Environment       |

---

## 6. Total Cost of Ownership (TCO) & Pricing Curves

```
Monthly Cost ($)
  ^
  │                                 / Auth0 (Enterprise SAML + High MAU)
  │                                /
  │                              /
  │                            /
  │              ────────────/───── Keycloak TCO (Fixed K8s Node/DB Cost)
  │            /
  │          /
  │        /
  │  ────/───────────────────────── AWS Cognito (High free tier, low marginal)
  └─────────────────────────────────────> MAU Volume
```

- **Under 10,000 MAU:** Managed SaaS (Auth0, Cognito) is cheaper than running Keycloak when accounting for engineer salaries.
- **Over 500,000 MAU or 200+ Enterprise SAML Connections:** Self-hosted Keycloak or AWS Cognito saves hundreds of thousands of dollars annually in vendor licensing.

---

## 7. Decision Framework: Selecting Your Identity Engine

```
Do you have strict data residency, air-gapped, or zero-license cost requirements?
  ├── YES ───────────────────────────> KEYCLOAK (Self-Hosted on K8s)
  └── NO
        Do you need rapid enterprise B2B features (SAML + SCIM for enterprise deals)?
          ├── YES, on top of existing auth ─> WORKOS / BOXYHQ
          ├── YES, as all-in-one auth ───────> AUTH0 (with B2B Organizations)
          └── NO (Consumer / Developer focused)
                ├── Heavy AWS infrastructure ─> AWS COGNITO
                └── Heavy Azure ecosystem ────> MICROSOFT ENTRA EXTERNAL ID
```

---

## 8. Exercises & Verification

1. **Calculate Pricing Cliff:** Visit the pricing calculator of Auth0 and Cognito. Calculate the monthly cost of 100,000 B2C MAUs vs 2,000 B2B users across 20 SAML enterprise connections.
2. **Review Keycloak Helm Chart:** Inspect the official `keycloak` Helm chart on ArtifactHub. Note the database prerequisites (PostgreSQL) and clustering requirements (JGroups / Infinispan).
3. **Audit Vendor Lock-in Risk:** Check whether your prospective IdP allows exporting password hashes (e.g. bcrypt/argon2) to enable future migration.

---

## 9. Next Step

Beyond standard single-org federation, cross-organizational trust is evolving into decentralized federations and verified identity networks. We examine **B2B Federation & Trust Frameworks** next.

→ [[06-b2b-federation|Stage 4.6 — B2B Federation & Trust Frameworks: OpenID Federation 1.0]]

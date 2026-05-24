---
title: GCP Security
tags: [security, gcp, google-cloud, scc, chronicle, workload-identity]
date: 2025-05-24
description: GCP security - Security Command Center, Chronicle, Workload Identity Federation, and GCP-native security tooling
---

# GCP Security 🟠🔐

Google Cloud Platform security services and configuration.

## Core Services

| Service | Purpose |
|---------|---------|
| **Security Command Center (SCC)** | GCP's CSPM — centralized security monitoring |
| **Chronicle** | Google's SIEM + threat intel platform |
| **Workload Identity Federation** | OIDC/SAML-based access to GCP without keys |
| **Cloud Armor** | DDoS protection and WAF |
| **Binary Authorization** | Verify container images before deployment |

## Security Command Center (SCC)

GCP's cloud-native CSPM. Activate at organization or project level.

```bash
# Enable SCC
gcloud services enable securitycenter.googleapis.com

# List findings
gcloud scc findings list --organization=<org-id> --severity=HIGH
```

### tiers

- **SCC Standard** — Free, basic findings
- **SCC Premium** — Advanced threat detection, Threat Intelligence

## Chronicle

GCP's SIEM — designed for long-term log storage and threat hunting.

```bash
# Ingest logs via Chronicle ingestion
gcloud logging write syslog --severity=ERROR
```

## Workload Identity Federation

Avoid service account keys — federate identity from AWS/Azure/K8s:

```bash
# AWS to GCP
gcloud iam workload-identity-pools create aws-pool \
  --organization=<org>

gcloud iam workload-identity-pools add-iam-policy-binding aws-pool \
  --member="principal://arn:aws:sts::123456789:assumed-role/MyRole"
```

## Related

- [[Security/cloud-security/README|Cloud Security Hub]]
- [[GCP/identity|GCP IAM]]
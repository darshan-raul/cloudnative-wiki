---
title: Application Security
tags: [application, security, auth, secrets, sca]
date: 2025-05-24
description: Application security - authentication, secrets management, dependency scanning, and supply chain security
---

# Application Security

Security for applications — authentication, secrets management, dependency scanning, and supply chain security.

## Sections

- **Authentication** — [[Architecture/solution-architecture-concepts/authentication/README|OAuth2/OIDC/JWT]]
- **Secrets Management** — HashiCorp Vault, AWS Secrets Manager, Kubernetes secrets
- **Dependency Scanning** — Trivy, Snyk, Grype, Dependabot
- **Supply Chain Security** — [[Resources/guides/security/supply-chain-security|SBOM, Sigstore, SLSA]]

## Key Concepts

### Secrets Management

```bash
# HashiCorp Vault - dynamic secrets
vault kv get secret/myapp/database

# AWS Secrets Manager
aws secretsmanager get-secret-value --secret-id myapp/db

# Kubernetes secrets (base64 encoded - not encryption)
kubectl get secret mysecret -o yaml
```

### Dependency Scanning

```bash
# Trivy - scan container image
trivy image myapp:latest

# Grype - scan SBOM
grype sbom:myapp.spdx -o json

# Snyk - scan code
snyk test --all-projects
```

## Related

- [[Security/devsecops/README|DevSecOps]] — Shift-left security
- [[Security/incident-response/README|Incident Response]] — AppSec incident response
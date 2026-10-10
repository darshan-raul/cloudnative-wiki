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
- **Supply Chain Security** — [[DevOps/devsecops/README|SBOM, Sigstore, SLSA]]

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

## Across the wiki

- [[Architecture/solution-architecture-concepts/authentication/stage6/03-zero-trust-spiffe|6.3 — Zero-Trust & Workload Identity: SPIFFE/SPIRE and Multi-Cloud Federation]] — zero trust (Architecture)
- [[Architecture/solution-architecture-concepts/security/security|Security Architecture]] — zero trust (Architecture)
- [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/security|Security]] — zero trust (Architecture)
- [[Architecture/solution-architecture-concepts/security/README|Security]] — zero trust (Architecture)
- [[AI/agents|AI Agents]] — LLM applications (AI)
- [[Architecture/solution-architecture-concepts/protocols/server-sent-events|Server-Sent Events (SSE) Architecture & LLM Streaming]] — LLM applications (Architecture)
- [[AI/langgraph/README|LangGraph]] — LLM applications (AI)
- [[AI/langchain/README|LangChain]] — LLM applications (AI)

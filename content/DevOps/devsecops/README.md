---
title: DevSecOps
tags: [devops, security, devsecops, ci-cd]
date: 2025-05-24
description: Shift-left security practices, securing CI/CD pipelines, and integrating security into the development lifecycle
---

# DevSecOps 🔒

DevSecOps embeds security into the CI/CD pipeline rather than treating it as a post-deployment concern.

## Core Principles

- **Shift left** — Catch vulnerabilities early in the development cycle
- **Automation** — Security checks run automatically on every commit/PR
- **Defense in depth** — Multiple layers of security at each stage

## Pipeline Security Layers

```
Code → SAST → Dependency Scan → Container Scan → Deploy → Runtime Protection
```

### 1. SAST (Static Application Security Testing)
Scan source code for vulnerabilities before build. Tools: Semgrep, SonarQube, Bandit (Python), Gosec (Go).

### 2. Dependency Scanning
Detect vulnerable dependencies (CVEs) in packages/ libraries. Tools: Trivy, Snyk, Dependabot, Grype.

### 3. Container Image Scanning
Scan base images and built artifacts. Reject builds with critical CVEs. Tools: Trivy, Grype, Clair.

### 4. Secrets Detection
Prevent credentials from entering the repository. Tools: Gitleaks, Talisman, git-secrets.

### 5. Policy Enforcement (OPA)
Enforce organizational policies at deploy time using OPA Gatekeeper or Kyverno.

## Supply Chain Security

- **SBOM** — Software Bill of Materials for dependency visibility
- **Sigstore** — Sign and verify container images / artifacts
- **SLSA** — Supply chain Levels for Software Artifacts

## Your Stack

- Trivy for container image scanning (CI/CD)
- Wazuh for runtime security on Kubernetes
- Vault for secrets management
- n8n for security workflow automation

## Related

- [[Security/devsecops/README|Security DevSecOps Hub]]
- [[DevOps/ci-cd/README|CI/CD]]
- [[Security/siem/wazuh/README|Wazuh]]
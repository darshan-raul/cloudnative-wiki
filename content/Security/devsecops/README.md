---
title: DevSecOps
tags: [devsecops, shift-left, security, ci-cd]
date: 2025-05-24
description: DevSecOps - shift-left security, CI/CD security scanning, container security, and secure pipeline design
---

# DevSecOps

Shift-left security principles — integrating security into CI/CD pipelines, container security, and secure software development.

## Core Principles

1. **Shift left** — Security checks as early as possible in pipeline
2. **Automate security** — No manual security review bottlenecks
3. **Fail fast** — Block builds on critical vulnerabilities
4. **Everything as code** — Security policies in code (OPA, Sentinel, etc.)

## Sections

- [[DevOps/devsecops/stage2-build/11-cicd-pipeline-hardening|Pipeline Security]] — Securing CI/CD pipelines, GitHub Actions hardening, secrets management
- [[Linux/security/container-security|Container Security]] — Image scanning, distroless, rootless, capabilities

## Pipeline Security Checks

| Stage       | Check                        | Tools                     |
| ----------- | ---------------------------- | ------------------------- |
| **Commit**  | Pre-commit hook secrets scan | gitleaks, detect-secrets  |
| **Build**   | SAST, dependency scan        | SonarQube, Snyk, Trivy    |
| **Test**    | DAST, fuzzing                | OWASP ZAP, AFL            |
| **Deploy**  | Image scan, IaC scan         | Trivy, Checkov, Terrascan |
| **Runtime** | RASP, runtime monitoring     | Falco, AppArmor           |

## Key Tools

- **Trivy** — Container and IaC vulnerability scanner
- **Checkov** — Terraform/K8s policy scanning
- **Snyk** — Dependency and container scanning
- **Gitleaks** — Secrets detection in code
- **OPA Gatekeeper** — Kubernetes policy enforcement

## Related

- [[DevOps/devsecops/README|Supply Chain Security]] — SBOM, Sigstore, SLSA
- [[Security/incident-response/README|Incident Response]] — CI/CD security incidents

## Across the wiki

- [[DevOps/devsecops/stage2-build/09-container-image-scanning|M09: Container Image Scanning & Hardening]] — software supply chain (DevOps)
- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image Hardening]] — software supply chain (Kubernetes)
- [[Containers/registries|Container Registries]] — software supply chain (Containers)
- [[AWS/security/inspector/README|AWS Inspector]] — software supply chain (AWS)

---
title: DevSecOps
tags: [devops, security, devsecops, ci-cd]
date: 2025-05-24
description: 20-module DevSecOps curriculum — shift-left, shift-right, and the pipeline in between. From culture and threat modeling to runtime detection and the capstone end-to-end pipeline.
---

# DevSecOps 🔒

DevSecOps embeds security into the CI/CD pipeline rather than treating it as a post-deployment concern. This curriculum takes you from culture (Stage 0) through the scanners (Stage 1), build hardening (Stage 2), deploy gates (Stage 3), and runtime detection (Stage 4). 20 modules, ~400 lines each.

## Curriculum Map

```
Stage 0 — Foundations       Stage 1 — Code           Stage 2 — Build
(M01–M04)                   (M05–M08)                 (M09–M11)
                            ┌──────────┐              ┌──────────┐
   M01 Mindset              │ M05 SAST │              │ M09 Cnt  │
   M02 Threat Modeling      │ M06 Secr │              │ M10 IaC  │
   M03 Secure SDLC          │ M07 SCA  │              │ M11 CI   │
   M04 Security Reqs        │ M08 SBOM │              └──────────┘
                            └──────────┘
                                                      Stage 3 — Deploy
Stage 4 — Runtime                                     (M12–M15)
(M16–M20)                                              ┌──────────┐
   ┌──────────┐                                        │ M12 OIDC │
   │ M16 SecM │                                        │ M13 Sign │
   │ M17 Det  │                                        │ M14 SLSA │
   │ M18 Comp │                                        │ M15 PaC  │
   │ M19 IR   │                                        └──────────┘
   │ M20 CPS  │
   └──────────┘
```

## Modules

### Stage 0 — Foundations

  - [[DevOps/devsecops/stage0-foundations/01-devsecops-mindset|M01: DevSecOps Mindset & Principles]]
  - [[DevOps/devsecops/stage0-foundations/02-threat-modeling|M02: Threat Modeling for DevSecOps]]
  - [[DevOps/devsecops/stage0-foundations/03-secure-sdlc|M03: Secure SDLC]]
  - [[DevOps/devsecops/stage0-foundations/04-security-requirements|M04: Security Requirements & Acceptance Criteria]]

### Stage 1 — Code

  - [[DevOps/devsecops/stage1-code/05-static-analysis-sast|M05: Static Analysis (SAST)]]
  - [[DevOps/devsecops/stage1-code/06-secrets-detection|M06: Secrets Detection & Prevention]]
  - [[DevOps/devsecops/stage1-code/07-sca-dependency-scanning|M07: SCA & Dependency Scanning]]
  - [[DevOps/devsecops/stage1-code/08-sbom-generation|M08: SBOM Generation & Consumption]]

### Stage 2 — Build

  - [[DevOps/devsecops/stage2-build/09-container-image-scanning|M09: Container Image Scanning & Hardening]]
  - [[DevOps/devsecops/stage2-build/10-iac-security|M10: Infrastructure-as-Code Security]]
  - [[DevOps/devsecops/stage2-build/11-cicd-pipeline-hardening|M11: CI/CD Pipeline Hardening]]

### Stage 3 — Deploy

  - [[DevOps/devsecops/stage3-deploy/12-pipeline-identity-oidc|M12: Pipeline Identity & OIDC]]
  - [[DevOps/devsecops/stage3-deploy/13-artifact-signing|M13: Artifact Signing]]
  - [[DevOps/devsecops/stage3-deploy/14-supply-chain-attestations|M14: Supply Chain Attestations & SLSA]]
  - [[DevOps/devsecops/stage3-deploy/15-policy-as-code|M15: Policy-as-Code]]

### Stage 4 — Runtime

  - [[DevOps/devsecops/stage4-runtime/16-secret-management|M16: Runtime Secret Management]]
  - [[DevOps/devsecops/stage4-runtime/17-runtime-detection|M17: Runtime Detection & Response]]
  - [[DevOps/devsecops/stage4-runtime/18-compliance-evidence|M18: Compliance Evidence & Audit Trail]]
  - [[DevOps/devsecops/stage4-runtime/19-incident-response-in-ci|M19: Incident Response in CI]]
  - [[DevOps/devsecops/stage4-runtime/20-capstone-end-to-end-pipeline|M20: Capstone — End-to-End Secure Pipeline]]

## Stages

  - [[DevOps/devsecops/stage0-foundations/README|Stage 0 — Foundations]]
  - [[DevOps/devsecops/stage1-code/README|Stage 1 — Code]]
  - [[DevOps/devsecops/stage2-build/README|Stage 2 — Build]]
  - [[DevOps/devsecops/stage3-deploy/README|Stage 3 — Deploy]]
  - [[DevOps/devsecops/stage4-runtime/README|Stage 4 — Runtime]]

## Core Principles

  - **Shift left** — Catch vulnerabilities early in the development cycle
  - **Shift right** — Catch what got through at runtime
  - **Automation** — Security checks run automatically on every commit/PR
  - **Defense in depth** — Multiple layers of security at each stage
  - **Continuous improvement** — Every incident makes the pipeline stronger

## Pipeline Security Layers

```
Code → SAST → Dependency Scan → Container Scan → Deploy → Runtime Detection
```

### 1. SAST (Static Application Security Testing)
Scan source code for vulnerabilities before build. Tools: Semgrep, SonarQube, CodeQL.

### 2. Secrets Detection
Prevent credentials from entering the repository. Tools: Gitleaks, Trufflehog.

### 3. Dependency Scanning (SCA)
Detect vulnerable dependencies (CVEs) in packages/libraries. Tools: Trivy, Snyk, Dependabot.

### 4. Container Image Scanning
Scan base images and built artifacts. Reject builds with critical CVEs. Tools: Trivy, Grype, Clair.

### 5. IaC Scanning
Catch misconfigurations in Terraform, CloudFormation, K8s manifests. Tools: Checkov, tfsec, Trivy IaC.

### 6. Policy-as-Code
Enforce organizational policies at deploy time. Tools: OPA, Kyverno, CEL.

### 7. Runtime Detection
Detect anomalous behavior in running workloads. Tools: Falco, Tetragon, Wazuh.

## Supply Chain Security

  - **SBOM** — Software Bill of Materials for dependency visibility
  - **Sigstore** — Sign and verify container images / artifacts
  - **SLSA** — Supply chain Levels for Software Artifacts
  - **VEX** — Vulnerability Exploitability eXchange

## Recommended Order

If you only have time for some modules, do these in order:

  1. M01 — culture and principles
  2. M02 — threat modeling in 30 minutes
  3. M06 — secrets prevention (the 4-minute window)
  4. M07 — SCA / dependency scanning
  5. M09 — container image hardening
  6. M11 — pipeline hardening
  7. M12 — OIDC federation
  8. M13 — artifact signing
  9. M15 — policy-as-code at admission
  10. M17 — runtime detection
  11. M20 — capstone

The other modules fill the gaps. The capstone is the integration.

## Your Stack in This Wiki

| Component | Where it lives in this wiki |
| --------- | --------------------------- |
| Trivy (container/SCA) | [[DevOps/devsecops/stage1-code/07-sca-dependency-scanning|M07]], [[DevOps/devsecops/stage2-build/09-container-image-scanning|M09]] |
| Gitleaks (secrets) | [[DevOps/devsecops/stage1-code/06-secrets-detection|M06]] |
| Semgrep (SAST) | [[DevOps/devsecops/stage1-code/05-static-analysis-sast|M05]] |
| Checkov / tfsec (IaC) | [[DevOps/devsecops/stage2-build/10-iac-security|M10]] |
| Sigstore / cosign | [[DevOps/devsecops/stage3-deploy/13-artifact-signing|M13]] |
| OPA / Kyverno | [[DevOps/devsecops/stage3-deploy/15-policy-as-code|M15]] |
| Wazuh (SIEM) | [[Security/siem/wazuh/README]] |
| Falco (runtime) | [[DevOps/devsecops/stage4-runtime/17-runtime-detection|M17]] |

## Related

  - [[DevOps]] — top-level DevOps hub
  - [[DevOps/devsecops/stage0-foundations/README|Stage 0 README]]
  - [[DevOps/devsecops/stage1-code/README|Stage 1 README]]
  - [[DevOps/devsecops/stage2-build/README|Stage 2 README]]
  - [[DevOps/devsecops/stage3-deploy/README|Stage 3 README]]
  - [[DevOps/devsecops/stage4-runtime/README|Stage 4 README]]
  - [[Security/devsecops/README|Security DevSecOps Hub]]
  - [[Architecture/solution-architecture-concepts/security/shift-left|Shift-Left Notes]]

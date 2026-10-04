---
title: DevOps
tags: [devops, ci-cd, github-actions, platform-engineering, sre, gitops]
date: 2026-09-06
description: "DevOps, CI/CD, GitHub Actions, DevSecOps, Platform Engineering, GitOps, and SRE practices."
---

# DevOps 🚀

Continuous Integration, Continuous Delivery, Platform Engineering, DevSecOps, and Reliability.

---

## 1. CI/CD & Delivery Engineering

- **[[DevOps/ci-cd/README|CI/CD Master Architecture]]** — Build once, deploy everywhere; artifact immutability and promotion
- **[[DevOps/ci-cd/github-actions|GitHub Actions Deep Dive]]** — Keyless cloud OIDC federation, reusable workflows, and caching
- **[[DevOps/ci-cd/git|Git Strategy & Production Workflows]]** — Trunk-Based Development, conventional commits, and rebase discipline
- **[[Kubernetes/guides/delivery/gitops/argo-cd/README|GitOps with Argo CD]]** — Declarative continuous delivery on Kubernetes

---

## 2. DevSecOps (Shift-Left to Shift-Right)

A comprehensive 20-module end-to-end security pipeline curriculum:

- **[[DevOps/devsecops/README|DevSecOps Curriculum Overview]]**
  - **[[DevOps/devsecops/stage0-foundations/README|Stage 0 — Foundations & Threat Modeling]]** (Culture, secure SDLC, threat modeling)
  - **[[DevOps/devsecops/stage1-code/README|Stage 1 — Code Security]]** (SAST, Secrets detection, SCA, SBOM generation)
  - **[[DevOps/devsecops/stage2-build/README|Stage 2 — Build & Image Hardening]]** (Container scanning, IaC security, pipeline hardening)
  - **[[DevOps/devsecops/stage3-deploy/README|Stage 3 — Deploy & Attestations]]** (OIDC pipeline identity, Cosign signing, SLSA, Policy-as-Code)
  - **[[DevOps/devsecops/stage4-runtime/README|Stage 4 — Runtime & Incident Response]]** (Secret management, runtime detection, capstone pipeline)

---

## 3. Platform Engineering & Self-Service

- **[[DevOps/platform-engineering/README|Platform Engineering & Internal Developer Platforms (IDP)]]** — Developer portals, Golden Paths, Backstage, and Crossplane control planes
- **[[Resources/guides/platform-engineering/crossplane|Crossplane Architecture]]** — Composable infrastructure control planes
- **[[Resources/guides/opentofu|OpenTofu Guide]]** — Open-source declarative infrastructure orchestration

---

## Related Knowledge Bases

- ☸️ **[[Kubernetes]]** — Container orchestration runtime
- ☁️ **[[AWS]]** — AWS cloud deployment targets (ECS, EKS, Lambda)
- 🐧 **[[Linux]]** — Runner configuration, kernel cgroups, and shell automation
- 🔐 **[[Security]]** — Cloud and container security architecture
- 📊 **[[Observability]]** — Telemetry, Prometheus, and SLO/SLI tracking

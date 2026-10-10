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
- **[[DevOps/ci-cd/pipeline-design|Pipeline Design]]** — Stage order, build once and promote, test strategy, speed, pipeline security
- **[[DevOps/ci-cd/deployment-strategies|Deployment Strategies]]** — Rolling, blue-green, canary, shadow and feature flags; rollback and data compatibility
- **[[DevOps/ci-cd/release-and-versioning|Release and Versioning]]** — SemVer, immutable artifacts, promotion, changelogs, dependency updates
- **[[DevOps/ci-cd/dora-metrics|DORA Metrics]]** — Measuring delivery performance without gaming it
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
- **[[DevOps/platform-engineering/internal-developer-platforms|Internal Developer Platforms]]** — Capabilities, platform as a product, the thinnest viable platform, metrics
- **[[DevOps/platform-engineering/golden-paths|Golden Paths]]** — Paved roads, guardrails over gates, keeping services current
- **[[DevOps/platform-engineering/backstage|Backstage]]** — Catalog, templates, TechDocs and the real cost of running a portal
- **[[DevOps/platform-engineering/crossplane|Crossplane for Platform APIs]]** — Designing self-service infrastructure APIs
- **[[DevOps/platform-engineering/platform-vs-devops-vs-sre|Platform Engineering vs DevOps vs SRE]]** — How the three relate

---

## 4. Infrastructure as Code

- **[[DevOps/infrastructure-as-code/README|Infrastructure as Code]]** — Declarative versus imperative, provisioning versus configuration, choosing tools
- **[[DevOps/infrastructure-as-code/terraform|Terraform]]** — The plan and apply loop, HCL, modules, lifecycle controls, refactoring safely
- **[[DevOps/infrastructure-as-code/terraform-state-and-collaboration|Terraform State and Collaboration]]** — Backends, locking, splitting state, team workflows, drift
- **[[DevOps/infrastructure-as-code/opentofu|OpenTofu]]** — The open-source fork
- **[[DevOps/infrastructure-as-code/ansible|Ansible]]** — Agentless configuration management
- **[[DevOps/infrastructure-as-code/packer|Packer]]** — Machine images and immutable infrastructure

---

## 5. Site Reliability Engineering

- **[[DevOps/sre/README|SRE Overview]]** — Reliability as a target, toil, and how SRE relates to DevOps
- **[[DevOps/sre/slos-and-error-budgets|SLOs and Error Budgets]]** — Choosing SLIs, setting targets, burn rate, error budget policy
- **[[DevOps/sre/on-call|On-Call]]** — Rotation design, what should page, runbooks, preventing burnout
- **[[DevOps/sre/incident-management|Incident Management and Postmortems]]** — Roles, mitigation first, blameless reviews

---

## Related Knowledge Bases

- ☸️ **[[Kubernetes]]** — Container orchestration runtime
- ☁️ **[[AWS]]** — AWS cloud deployment targets (ECS, EKS, Lambda)
- 🐧 **[[Linux]]** — Runner configuration, kernel cgroups, and shell automation
- 🔐 **[[Security]]** — Cloud and container security architecture
- 📊 **[[Observability]]** — Telemetry, Prometheus, and SLO/SLI tracking
- 📦 **[[Containers]]** — Images, registries and Dockerfile practice

---
title: "Stage 0 — Foundations"
tags: [devsecops, stage0, foundations, hub]
date: 2026-06-16
description: Stage 0 of the 20-module DevSecOps curriculum — culture, threat modeling, SDLC phases, and security requirements. The mental models before the tooling.
---

# Stage 0 — Foundations

Four modules that build the conceptual scaffolding for everything in stages 1–5. The tooling in later stages is mechanical; the judgment in this stage is what makes it useful.

## Modules

  - [[DevOps/devsecops/stage0-foundations/01-devsecops-mindset|M01: DevSecOps Mindset & Principles]]
  - [[DevOps/devsecops/stage0-foundations/02-threat-modeling|M02: Threat Modeling for DevSecOps]]
  - [[DevOps/devsecops/stage0-foundations/03-secure-sdlc|M03: Secure SDLC]]
  - [[DevOps/devsecops/stage0-foundations/04-security-requirements|M04: Security Requirements & Acceptance Criteria]]

## What You Should Be Able to Do After Stage 0

  - Explain DevSecOps in terms a CFO will accept
  - Run a 4-question threat model in 30 minutes during grooming
  - Identify the maturity tier of your team's pipeline and the next-tier controls to add
  - Write security acceptance criteria (SEC- prefix) on any story that touches a trust boundary
  - Distinguish threat, vulnerability, risk, and control without thinking about it

## Stage 0 vs. Stage 1+

  - Stage 0 is read-mostly. Few scanners, more judgment.
  - Stage 1 introduces the actual tools: SAST, secrets, SCA, SBOM.
  - Stage 2 covers the build side: container, IaC, image hardening.
  - Stage 3 covers deploy: OIDC, signing, policy-as-code, gating.
  - Stage 4 covers runtime: detection, response, compliance, capstone.

If you only have time to do four modules of this curriculum, do these four. Everything else builds on them.

## Related

  - [[DevOps/devsecops/README|DevSecOps Hub]]
  - [[DevOps/devsecops/stage1-code/README|Stage 1 — Code]]
  - [[DevOps/devsecops/stage2-build/README|Stage 2 — Build]]

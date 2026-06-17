---
title: "Stage 1 — Code"
tags: [devsecops, stage1, code, hub]
date: 2026-06-16
description: "Stage 1 of the 20-module DevSecOps curriculum — scanners that run on code, dependencies, and the artifacts that come out of the build. The first line of automated defense."
---

# Stage 1 — Code

Four modules covering the scanners that touch your code and dependencies. These run at PR time and nightly. They are the highest-frequency controls in the pipeline: every commit goes through them.

## Modules

  - [[DevOps/devsecops/stage1-code/05-static-analysis-sast|M05: Static Application Security Testing (SAST)]]
  - [[DevOps/devsecops/stage1-code/06-secrets-detection|M06: Secrets Detection & Prevention]]
  - [[DevOps/devsecops/stage1-code/07-sca-dependency-scanning|M07: SCA & Dependency Scanning]]
  - [[DevOps/devsecops/stage1-code/08-sbom-generation|M08: SBOM Generation & Consumption]]

## What You Should Be Able to Do After Stage 1

  - Run SAST, secrets, SCA, and SBOM generation in CI without flooding the team with findings
  - Tune a rule set to <10% false positives in 90 days
  - Generate a signed SBOM and attach it to a container image
  - Triage a "vulnerable dep" alert in under 5 minutes
  - Set up pre-commit hooks that engineers actually use
  - Explain the difference between SAST, SCA, secrets, and SBOM tools

## The Order Matters

  - **M05 (SAST)** is the entry point — it scans code you wrote
  - **M06 (secrets)** runs alongside SAST but at the *prevent* layer, not the *detect* layer
  - **M07 (SCA)** is the highest-volume scanner — 80% of findings come from here
  - **M08 (SBOM)** is the artifact that makes M07 continuous — re-scan the same SBOM as new CVEs drop

If you implement only one of the four, do M07. Modern codebases have more dependency vulns than first-party code vulns by an order of magnitude.

## Related

  - [[DevOps/devsecops/README|DevSecOps Hub]]
  - [[DevOps/devsecops/stage0-foundations/README|Stage 0 — Foundations]]
  - [[DevOps/devsecops/stage2-build/README|Stage 2 — Build]]

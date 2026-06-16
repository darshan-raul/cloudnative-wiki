---
title: "Stage 4 — Runtime"
tags: [devsecops, stage4, runtime, hub]
date: 2026-06-16
description: Stage 4 of the 20-module DevSecOps curriculum — the runtime. Detection, secret management, compliance evidence, incident response, and the capstone end-to-end pipeline.
---

# Stage 4 — Runtime

Five modules covering the runtime half of DevSecOps: the controls that operate after the artifact is deployed. Stage 0–3 catch issues at design, code, build, and deploy. Stage 4 catches what gets through.

## Modules

  - [[DevOps/devsecops/stage4-runtime/16-secret-management|M16: Runtime Secret Management]]
  - [[DevOps/devsecops/stage4-runtime/17-runtime-detection|M17: Runtime Detection & Response]]
  - [[DevOps/devsecops/stage4-runtime/18-compliance-evidence|M18: Compliance Evidence & Audit Trail]]
  - [[DevOps/devsecops/stage4-runtime/19-incident-response-in-ci|M19: Incident Response in CI]]
  - [[DevOps/devsecops/stage4-runtime/20-capstone-end-to-end-pipeline|M20: Capstone — End-to-End Secure Pipeline]]

## What You Should Be Able to Do After Stage 4

  - Replace static secrets in workloads with workload identity or Vault dynamic secrets
  - Deploy and tune Falco for runtime detection
  - Run a continuous evidence collection pipeline
  - Conduct a blameless postmortem and ship the improvements
  - Design a chaos game day
  - Assemble the full reference pipeline from M05–M19

## The Shift-Right Half

```
  Shift-Left (M05-M15)                Shift-Right (M16-M20)
  -------------------                 ----------------------
  SAST, secrets, SCA, SBOM            Secret management
  Image scan, IaC scan                Runtime detection
  Pipeline hardening, OIDC            IR, compliance
  Signing, attestations, policy       Capstone
  ---------------                     ---------------
  Prevent the issue                   Catch the issue
  Cheap, fast, deterministic         Costlier, slower, exploratory
  Coverage = "we ran the scanner"     Coverage = "we know what to do"
```

The two halves are not redundant; they are complementary. A mature DevSecOps program has both, integrated.

## The Mature State

The capstone (M20) is the destination. The path is the 19 prior modules. After the capstone, the pipeline is:

  - Preventing 95% of issues at design/code/build (M01–M15)
  - Detecting 99% of remaining issues at runtime (M17)
  - Responding to detected issues in under 30 minutes (M19)
  - Producing audit evidence continuously (M18)
  - Improving with every incident (the loop-back)

The pipeline is never "done." It is a living system that grows with the org, the threats, and the regulations.

## Related

  - [[DevOps/devsecops/README|DevSecOps Hub]]
  - [[DevOps/devsecops/stage0-foundations/README|Stage 0 — Foundations]]
  - [[DevOps/devsecops/stage1-code/README|Stage 1 — Code]]
  - [[DevOps/devsecops/stage2-build/README|Stage 2 — Build]]
  - [[DevOps/devsecops/stage3-deploy/README|Stage 3 — Deploy]]

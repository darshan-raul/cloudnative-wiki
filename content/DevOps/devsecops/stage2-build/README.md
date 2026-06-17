---
title: "Stage 2 — Build"
tags: [devsecops, stage2, build, hub]
date: 2026-06-16
description: "Stage 2 of the 20-module DevSecOps curriculum — what happens after the code is written and the build is running. Image hardening, IaC scanning, and the pipeline itself as code that needs securing."
---

# Stage 2 — Build

Three modules covering the build phase: the artifacts (container images), the inputs (IaC), and the build system (CI/CD). The build is the moment your source code becomes a deployable thing. Everything that goes wrong here propagates to production.

## Modules

  - [[DevOps/devsecops/stage2-build/09-container-image-scanning|M09: Container Image Scanning & Hardening]]
  - [[DevOps/devsecops/stage2-build/10-iac-security|M10: Infrastructure-as-Code Security]]
  - [[DevOps/devsecops/stage2-build/11-cicd-pipeline-hardening|M11: CI/CD Pipeline Hardening]]

## What You Should Be Able to Do After Stage 2

  - Build a multi-stage, distroless, non-root image
  - Pin base images to digests; scan every image at build, deploy, and continuously
  - Run Checkov/tfsec on every Terraform PR
  - Build and maintain a paved-road module library
  - Pin third-party actions to commit SHAs
  - Use ephemeral, isolated runners
  - Identify and defend against the top 5 CI/CD attack patterns

## The Order Matters

  - **M09** is the artifact — if the image is bloated or runs as root, no downstream control can fix it
  - **M10** is the cloud configuration — most breaches start here, not in the app
  - **M11** is the system that runs M05–M10. If the pipeline is compromised, every scanner is bypassed

## The Paved Road

Stage 2 is where the paved-road metaphor earns its keep. The defaults your team inherits should be safe by default:

  - Distroless images by default; alpine if distroless doesn't work
  - Paved-road module library for Terraform resources
  - Ephemeral GitHub Actions runners; OIDC for cloud
  - Pre-commit hooks for secrets and SAST

Engineers who stay on the paved road cannot create an insecure build. The scanners catch the ones who don't.

## Related

  - [[DevOps/devsecops/README|DevSecOps Hub]]
  - [[DevOps/devsecops/stage1-code/README|Stage 1 — Code]]
  - [[DevOps/devsecops/stage3-deploy/README|Stage 3 — Deploy]]

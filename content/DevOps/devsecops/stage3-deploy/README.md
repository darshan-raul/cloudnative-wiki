---
title: "Stage 3 — Deploy"
tags: [devsecops, stage3, deploy, hub]
date: 2026-06-16
description: Stage 3 of the 20-module DevSecOps curriculum — the moment the artifact meets the cluster. OIDC, signing, attestations, and policy-as-code. The gates that stand between the build and a running workload.
---

# Stage 3 — Deploy

Four modules covering the moment between "artifact is in the registry" and "workload is running." This is where most security controls either hold or fall over. The build is past; the runtime is not yet there. The four modules in this stage are the gate.

## Modules

  - [[DevOps/devsecops/stage3-deploy/12-pipeline-identity-oidc|M12: Pipeline Identity & OIDC]]
  - [[DevOps/devsecops/stage3-deploy/13-artifact-signing|M13: Artifact Signing]]
  - [[DevOps/devsecops/stage3-deploy/14-supply-chain-attestations|M14: Supply Chain Attestations & SLSA]]
  - [[DevOps/devsecops/stage3-deploy/15-policy-as-code|M15: Policy-as-Code]]

## What You Should Be Able to Do After Stage 3

  - Replace every static cloud credential in CI with OIDC
  - Sign every container image and verify the signature at deploy
  - Generate and verify SLSA provenance
  - Write a Kyverno admission policy, test it, and roll it out
  - Explain the difference between signing and attestations
  - Map policy to compliance controls

## The Gate

Stage 3 is the gate. The build has run, scans have run, artifacts are signed. Now the deploy target must verify:

  - The artifact is signed (M13)
  - The signature is from the expected identity (M13, M14)
  - The build provenance is valid (M14)
  - The deploy itself complies with policy (M15)
  - The pipeline that pushed the artifact had a valid identity (M12)

Skip any one of these and the previous stages' work is partially wasted.

## Static Creds → OIDC → Signing → Policy → SLSA

The maturity arc for this stage:

  - **Tier 1** — Use OIDC for at least one cloud; remove static keys
  - **Tier 2** — Sign all images with cosign keyless; verify at admission
  - **Tier 3** — Generate SLSA L2 provenance; verify provenance at admission
  - **Tier 4** — SLSA L3 with hardened build platform

## Related

  - [[DevOps/devsecops/README|DevSecOps Hub]]
  - [[DevOps/devsecops/stage2-build/README|Stage 2 — Build]]
  - [[DevOps/devsecops/stage4-runtime/README|Stage 4 — Runtime]]

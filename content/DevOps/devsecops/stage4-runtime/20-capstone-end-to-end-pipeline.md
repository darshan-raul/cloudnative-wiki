---
title: "M20: Capstone — End-to-End Secure Pipeline"
tags: [devsecops, stage4, runtime, capstone, end-to-end, slsa, signed, audited]
date: 2026-06-16
description: "Module 20 of 20 — capstone. Build the entire pipeline end-to-end: code to runtime, with all 19 prior modules applied. The deliverable is a working pipeline that satisfies Tier 3 SSDLC, SLSA L3, and survives a real audit."
---

# M20: Capstone — End-to-End Secure Pipeline

This is the integration module. The previous 19 modules gave you the components. This one shows them working together as a single, end-to-end pipeline. The deliverable is a working reference pipeline that you can adapt to your own environment, plus the architecture, runbook, and audit evidence that demonstrate it satisfies the controls from M03, M08, M14, and M18.

## Learning Objectives

By the end of this module you should be able to:

  - Assemble the components from M05–M19 into a single pipeline
  - Map every pipeline stage to the SSDLC phases from M03
  - Demonstrate SLSA L3 provenance end-to-end
  - Produce a continuous evidence stream for a SOC2 audit
  - Identify the gaps in your current pipeline relative to this reference

## 1. The Reference Architecture

A single application service going from `git push` to a running pod, with every security control from this curriculum applied.

```
   Developer            Pipeline (GitHub Actions)                Runtime
   ----------           --------------------------                -------
   git commit                                                  [K8s Cluster]
   git push     ───>     [PR opened]
                              │
                              ▼
                       [Pre-commit hooks] ◄───── M06 (gitleaks)
                              │
                              ▼
                       [PR CI]
                              │
                              ├─► SAST ──────────── M05 (Semgrep)
                              ├─► Secrets ───────── M06 (gitleaks, second layer)
                              ├─► SCA ───────────── M07 (Trivy fs)
                              ├─► IaC ───────────── M10 (Checkov, if IaC touched)
                              ├─► Unit tests
                              │
                              ▼
                       [Threat model 4Q attached]  ◄── M02, M04
                              │
                              ▼
                       [Required approvals: 1+]
                              │
                              ▼  (on merge to main)
                       [Build CI]
                              │
                              ├─► Multi-stage Dockerfile ─── M09 (distroless)
                              ├─► Image build
                              ├─► SBOM generation ────────── M08 (Syft)
                              ├─► Image scan ─────────────── M09 (Trivy image)
                              ├─► SLSA L3 provenance ─────── M14
                              ├─► cosign sign ─────────────── M13
                              │
                              ▼
                       [Push to registry]
                              │
                              ├─► Image (with SBOM attached)
                              ├─► Signature
                              ├─► Provenance
                              │
                              ▼
                       [Continuous re-scan]  ◄── M07, M09
                              │
                              ▼
                       [Argo CD / Flux picks up]
                              │
                              ▼
                       [Admission control]  ◄── M15 (Kyverno)
                              │
                              ├─► Image signed? (M13)
                              ├─► Provenance valid? (M14)
                              ├─► Pod spec compliant? (M15)
                              │
                              ▼
                       [Pod scheduled]
                              │
                              ▼
                       [Runtime]  ◄── M17
                              │
                              ├─► Falco eBPF rules
                              ├─► Wazuh SIEM correlation
                              │
                              ▼
                       [Continuous evidence]  ◄── M18
                              │
                              └─► SOC2 / ISO / PCI evidence stream
```

## 2. The Pipeline as Code

A single `.github/workflows/release.yml` that demonstrates the pattern. For brevity, several steps are abbreviated.

```yaml
name: release

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
    tags: ['v*']

permissions:
  id-token: write   # OIDC for cosign keyless
  contents: read
  pull-requests: read

env:
  IMAGE_NAME: ghcr.io/${{ github.repository }}

jobs:
  pr-checks:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # M06 — secrets prevention
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      # M05 — SAST
      - uses: returntocorp/semgrep-action@v1
        with:
          config: >-
            p/default
            p/security-audit
            p/owasp-top-ten

      # M07 — SCA
      - uses: aquasecurity/trivy-action@master
        with:
          scan-type: fs
          scan-ref: .
          severity: HIGH,CRITICAL
          exit-code: 1

      # M10 — IaC (if changed)
      - uses: bridgecrewio/checkov-action@master
        if: hashFiles('terraform/**') != ''
        with:
          directory: terraform/
          framework: terraform
          quiet: true

      # M04 — threat model 4Q attached
      - name: Verify threat model 4Q
        run: |
          if ! grep -q "Q1\|Q2\|Q3\|Q4" PR_BODY.md; then
            echo "::error::Threat model 4Q not attached to PR description"
            exit 1
          fi

  build:
    needs: pr-checks
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.build.outputs.digest }}
    steps:
      - uses: actions/checkout@v4

      # M12 — OIDC for cloud
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE }}
          aws-region: us-east-1

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      # M09 — multi-stage, distroless build
      - name: Build image
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ env.IMAGE_NAME }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: true  # SLSA provenance
          sbom: true        # SBOM embedded in build output

      # M08 — SBOM emit + attach
      - name: Generate CycloneDX SBOM
        run: |
          syft scan registry:${{ env.IMAGE_NAME }}:${{ github.sha }} \
            -o cyclonedx-json > sbom.cdx.json
          cosign attach sbom --sbom sbom.cdx.json \
            ${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}

      # M09 — image scan
      - name: Trivy image scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.IMAGE_NAME }}:${{ github.sha }}
          severity: HIGH,CRITICAL
          exit-code: 1
          format: sarif
          output: trivy.sarif

      # M13 — sign with cosign keyless
      - name: cosign sign (keyless)
        env:
          COSIGN_EXPERIMENTAL: 1
        run: |
          cosign sign --yes \
            ${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}

      # M14 — SLSA L3 provenance
      - name: SLSA provenance
        uses: slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@v1.9.0
        with:
          image: ${{ env.IMAGE_NAME }}
          digest: ${{ steps.build.outputs.digest }}

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Update deployment manifest
        run: |
          # Bump image tag in gitops repo
          IMAGE_SHA=${{ needs.build.outputs.digest }}
          cd gitops-repo
          kustomize edit set image my-app=${{ env.IMAGE_NAME }}@$IMAGE_SHA
          git commit -am "Deploy $IMAGE_SHA"
          git push
```

The companion cluster-side controls (M15 — Kyverno) verify the image at admission time. The runtime side (M17 — Falco) watches the running pod. The SIEM (M17 — Wazuh) correlates. The evidence stream (M18) flows continuously to the audit log.

## 3. Mapped to SSDLC Phases (M03)

| SSDLC phase | Pipeline stage | Module(s) |
| ----------- | -------------- | --------- |
| Plan | Story template, security champion review | M01, M04 |
| Design | Threat model 4Q in PR | M02, M04 |
| Code | Pre-commit, IDE plugin, PR review | M05, M06 |
| Build | SAST, SCA, secrets, IaC scan | M05, M06, M07, M10 |
| Test | Unit, integration, DAST | M05, M11 |
| Deploy | Signed image, provenance, admission control | M13, M14, M15 |
| Operate | Falco, Wazuh, alerts | M17 |
| Respond | IR cycle, postmortem | M19 |
| Learn | Compliance evidence, audit | M18 |

Every SSDLC phase has at least one control. The pipeline enforces them; the evidence is continuous.

## 4. Mapped to SLSA L3

| SLSA L3 requirement | Implementation |
| ------------------- | -------------- |
| Build provenance generated | `slsa-github-generator` step in CI |
| Provenance signed | GitHub's OIDC issuer signs the provenance |
| Provenance non-forgeable | Provenance generated by GitHub, not the build script |
| Source verified | Provenance includes source commit SHA |
| Build platform hardened | GitHub-hosted ephemeral runners |
| Build isolated | Each job in a fresh VM |
| Two-party review (L3 → L4) | Required PR approvals + branch protection |

A consumer verifying the artifact can:
  1. Pull the image by digest
  2. Pull the signature
  3. Pull the provenance
  4. Verify signature against Fulcio root
  5. Verify provenance was issued by GitHub for this commit
  6. Verify the source matches the expected repo and ref
  7. Accept or reject

## 5. Mapped to SOC2 Type II

| TSC | Control | Pipeline evidence |
| --- | ------- | ----------------- |
| CC6.1 | Logical access | OIDC role assumption logs (CloudTrail) |
| CC6.6 | Network boundaries | K8s network policies + admission logs |
| CC6.8 | Malware protection | Image scan results, Trivy SARIF |
| CC7.1 | Vulnerability detection | SAST, SCA, IaC scan logs |
| CC7.2 | System monitoring | Falco alerts, Wazuh indexer logs |
| CC7.3 | Anomaly evaluation | SIEM correlation rules + alerts |
| CC7.4 | Incident response | PagerDuty alerts, runbooks, postmortems |
| CC8.1 | Change management | PR approvals, signed images, Argo CD sync logs |
| CC9.1 | Risk mitigation | Risk register, exception register with expiry |
| CC9.2 | Vendor risk | SBOMs, vendor security questionnaires |

The auditor pulls a sample of releases from the audit period; the pipeline produces the evidence in minutes, not days.

## 6. The Cost of the Reference Pipeline

Roughly, for a mid-size engineering org (50 engineers, 100 services, 5000 deploys/year):

| Component | Cost (annual) | Notes |
| --------- | ------------- | ----- |
| GitHub Enterprise + Actions | $20k | Includes OIDC, advanced security |
| AWS (OIDC, KMS, registry) | $5k | KMS is the big line |
| Trivy Enterprise (optional) | $0–$10k | OSS works for most |
| Cosign / Sigstore | $0 | Free |
| Falco | $0 | Open source |
| Wazuh (self-hosted) | $0–$3k | 1 FTE time, minimal infra |
| Kyverno | $0 | Open source |
| SLSA GitHub generator | $0 | Free |
| Renovate / Dependabot | $0 | Free for OSS; paid for private |
| Auditor portal / Drata | $10k–$30k | Optional; manual works |
| **Total** | **$40k–$70k** | Plus ~0.5 FTE for security engineering |

Compare to the cost of a single major incident: $1M–$100M. The pipeline pays for itself in the first avoided incident.

## 7. The 1-Year Implementation Plan

The capstone is a year of work, not a week. Phased rollout:

### Quarter 1: Foundation

  - M01–M04: culture, threat modeling, SDLC, requirements
  - M05–M08: SAST, secrets, SCA, SBOM
  - M18: control matrix drafted

### Quarter 2: Build & Deploy

  - M09: distroless images; image scan gates
  - M10: IaC scanning; paved-road module library
  - M11: pipeline hardening; ephemeral runners
  - M12: OIDC for at least one cloud
  - M18: evidence collection automated

### Quarter 3: Signing & Policy

  - M13: cosign signing; verify at admission
  - M14: SLSA L2 provenance
  - M15: Kyverno policies, audit mode
  - M16: Vault dynamic secrets for one workload

### Quarter 4: Runtime & Maturity

  - M17: Falco in production; SIEM correlation
  - M19: IR runbooks; first game day
  - M14 → L3: hardened build platform
  - M15 → Enforce: Kyverno policies switched
  - M20: full pipeline; first audit

After year 1, the pipeline operates at Tier 3 maturity. Maintenance is a continuous process, not a project.

## 8. Common Failure Modes of the Capstone

### Failure 1: Built It, But No One Uses It

The security team built a paved road; engineers are still driving on the dirt road. The reasons:
  - The paved road is slower
  - The paved road is harder to find
  - The paved road is missing the engineer's actual use case

Fix: dogfood the paved road. The security team's own services run on it. The paved road is the default. Exceptions are tracked and expire.

### Failure 2: Audit Theater

The dashboard says green. The auditor asks for evidence of a specific control; the team produces a screenshot of the dashboard. The auditor asks for the underlying data; the team goes silent.

Fix: the dashboard is a view, not the source. The source is the pipeline logs. The dashboard can be wrong; the pipeline logs cannot.

### Failure 3: Compliance Without Security

The control matrix is complete. The evidence stream is continuous. But the controls are not effective. SAST runs with no rules enabled. Image scan is in audit mode. Policy is in audit mode.

Fix: the controls must be *enforced*. Audit mode is for rollout, not steady state. If a control is in audit mode, the date to switch to enforce is on the calendar.

### Failure 4: Security as a Separate Team

The security team maintains the pipeline. The engineering org consumes the pipeline. When the pipeline breaks, the engineering org waits. When the engineering org needs a new feature, the security team is the bottleneck.

Fix: embed security champions. The pipeline is a platform; the platform team owns the runtime; security provides the policy.

## 9. The Self-Assessment

Answer these honestly. Score 0 (no), 1 (partial), 2 (yes) for each.

| # | Question | Score (0–2) |
| - | -------- | ----------- |
| 1 | Is SAST enforced on every PR? |
| 2 | Are secrets blocked at pre-commit? |
| 3 | Is SCA scanning enforced with SLA? |
| 4 | Is SBOM generated for every release, signed? |
| 5 | Are container images scanned at build? |
| 6 | Are containers running non-root, read-only rootfs? |
| 7 | Is IaC scanned on every PR? |
| 8 | Is the pipeline using ephemeral runners? |
| 9 | Are static cloud credentials absent from CI? |
| 10 | Are images signed and verified at deploy? |
| 11 | Is SLSA provenance generated and verified? |
| 12 | Are Kyverno/OPA policies enforced (not audit)? |
| 13 | Is runtime detection (Falco) running in prod? |
| 14 | Are SIEM alerts correlated to IR runbooks? |
| 15 | Are postmortems filed and improvements shipped? |
| 16 | Is compliance evidence collected continuously? |
| 17 | Are incident response runbooks tested via game day? |
| 18 | Is the OIDC trust policy scoped to specific repos/branches? |
| 19 | Are dependencies kept current via Renovate/Dependabot? |
| 20 | Can a new service onboard to the pipeline in < 1 day? |

Total / 40:
  - 0–10: Tier 0 (ad hoc)
  - 11–20: Tier 1 (baseline — M01–M04 mostly done)
  - 21–30: Tier 2 (industry standard — M05–M15 mostly done)
  - 31–38: Tier 3 (differentiator — M16–M20 mostly done)
  - 39–40: Tier 4 (world class)

Re-take the assessment quarterly. Track the trend. The trend is the metric that matters.

## 10. After the Capstone

You have finished the 20 modules. You are not finished with DevSecOps. The discipline is continuous:

  - New CVEs are disclosed daily
  - New attack patterns emerge monthly
  - Compliance frameworks evolve yearly
  - Your application evolves constantly

The pipeline you built in M20 is the *baseline*. The next iteration starts with the next incident, the next CVE, the next customer requirement. The loop is the curriculum.

## 11. Self-Check

  1. Run the self-assessment in section 9. What's your score? Where are the biggest gaps?
  2. Pick the three lowest-scoring items. What is the smallest change to each that gets you to a "1"?
  3. Can you onboard a new service to your pipeline in under a day? If not, that's the next 90 days of work.

## 12. The Day 2 of DevSecOps

The capstone is the destination. Day 2 is what comes after.

The pipeline is never done. The threats evolve. The frameworks evolve. The org evolves. The pipeline evolves with them. Day 2 is the work of continuous improvement.

The disciplines that keep the pipeline healthy on Day 2:

  - **Weekly** — review new CVEs, new advisory patches, new compliance requirements
  - **Monthly** — review SCA findings, image scan results, runtime alerts
  - **Quarterly** — review the control matrix, run a game day, audit a sample
  - **Annually** — full risk assessment, control matrix overhaul, framework update
  - **On incident** — postmortem + improvement stories
  - **On framework change** — re-map controls, update evidence

The cadence is not "build it and forget it." It is a *practice*.

## 13. The Scaling Story

The pipeline that works for 10 services breaks at 100. The patterns:

  - **Centralized vs federated** — a central security team owns the platform; product teams consume the paved road
  - **Self-service** — engineers can onboard a new service without filing a ticket
  - **Default vs opt-in** — the secure path is the default; opt-in for exceptions
  - **Visible vs invisible** — the security posture is visible to engineering leadership
  - **Auditable vs not** — every action is logged

The scaling question: "can a new service go live in 1 day, on the secure path, without filing a ticket?" If yes, the pipeline is scaled.

## 14. The Multi-Cloud Story

The pipeline extends to multiple clouds:

```
  AWS                                  GCP
  -----                                -----
  IRSA + IAM Role (M12)                WIF + Service Account
  ECR + KMS (M08, M13)                 Artifact Registry + KMS
  CloudTrail (M11, M18)                Cloud Audit Logs
  Security Hub (M18)                   Security Command Center
  Config (M15)                         Org Policy (M15)
        |                                      |
        +------------------+-------------------+
                           |
                           v
                  Unified control matrix (M18)
                  Unified evidence pipeline
                  Unified posture (per-cloud + cross-cloud)
```

The pipeline that works for AWS extends to GCP, Azure, and beyond. The control matrix (M18) is unified; the evidence is per-cloud. The posture is multi-cloud.

## 15. The AI/ML DevSecOps Story

The pipeline extends to AI/ML:

  - **Data classification** (M04) — training data is classified
  - **Model SBOM** (M08) — the model + training data + dependencies, all inventoried
  - **SAST on training scripts** (M05) — code that trains the model is scanned
  - **SCA on training dependencies** (M07) — libraries used to train
  - **Image scan on training/inference** (M09) — the runtime container
  - **Threat model for adversarial inputs** (M02) — prompt injection, jailbreaks
  - **VEX for known-not-applicable CVEs** (M14) — explicit non-applicability
  - **Runtime detection for inference anomalies** (M17) — output filtering, drift

The DevSecOps pipeline is the same; the threat catalog is different.

## 16. The Engineering Culture Story

DevSecOps is a cultural shift, not a tooling project. The cultural elements:

  - **Shared ownership** — security is everyone's job
  - **Blameless** — incidents are learning opportunities
  - **Continuous** — improvement is ongoing
  - **Evidence-driven** — decisions are based on data
  - **Customer-centric** — the customer's trust is the goal

The org that has the pipeline but not the culture will see the pipeline decay. The org that has the culture but not the pipeline will build the pipeline faster. Culture first; pipeline second.

## 17. The Industry Direction

The DevSecOps discipline is converging on a few patterns:

  - **SLSA L3+** — the build provenance standard
  - **Sigstore keyless** — the signing standard
  - **SBOMs (CycloneDX / SPDX)** — the inventory standard
  - **OPA / Kyverno** — the policy standard
  - **GitOps (Argo CD / Flux)** — the deploy standard
  - **OIDC federation** — the identity standard
  - **Falco / Tetragon** — the runtime standard
  - **Wazuh** — the SIEM standard (open source)

A pipeline that uses these standards is portable, auditable, and future-proof. A pipeline that uses proprietary tools is locked in.

The recommendation: use the standards, even if the proprietary tool has more features. The cost of lock-in is greater than the cost of the missing features.

## 18. The Final Word

Twenty modules. ~10,000 lines. The discipline:

  - **Shift left** — prevent
  - **Shift right** — detect
  - **Automate** — every gate is a script
  - **Measure** — every control has a metric
  - **Improve** — every incident makes the pipeline stronger

The pipeline is the security program. The security program is the pipeline. They are not separate.

A mature DevSecOps program is *boring*. The alerts fire and resolve quickly. The scans find things early. The IR runbook is followed. The auditor finds no exceptions. The customer trusts the build. The org ships faster, with more confidence, than the org that does not have the pipeline.

That is the goal of M20. Not a single project, but a *practice*.

## Related

  - [[DevOps/devsecops/README|DevSecOps Hub]]
  - [[DevOps/devsecops/stage0-foundations/README|Stage 0 — Foundations]]
  - [[DevOps/devsecops/stage1-code/README|Stage 1 — Code]]
  - [[DevOps/devsecops/stage2-build/README|Stage 2 — Build]]
  - [[DevOps/devsecops/stage3-deploy/README|Stage 3 — Deploy]]
  - [[DevOps/devsecops/stage4-runtime/README|Stage 4 — Runtime]]
  - [[Architecture/solution-architecture-concepts/security/security|Security Foundations]]

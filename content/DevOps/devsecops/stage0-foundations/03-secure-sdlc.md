---
title: "M03: Secure SDLC"
tags: [devsecops, stage0, foundations, sdlc, secure-development, gates]
date: 2026-06-16
description: "Module 3 of 20 — the Secure Software Development Lifecycle in practice. Where each control goes, which gate blocks what, and how to phase in a maturity model without halting feature work."
---

# M03: Secure SDLC

The Secure SDLC (SSDLC) is a development lifecycle that bakes security activities into each phase instead of bolting them on at the end. This module gives you a working SSDLC you can adopt piecemeal: a baseline that protects you from the worst classes of incident, a target model that gets you to industry standard, and a path from one to the other without freezing the roadmap.

## Learning Objectives

By the end of this module you should be able to:

  - Name the six SSDLC phases and the security activity that belongs in each
  - Differentiate between entry, exit, and continuous gates
  - Pick a maturity tier (1/2/3) for your team and justify the next-step investment
  - Write a one-page SSDLC policy that an auditor will accept
  - Identify which gate is missing when given a sample pipeline

## 1. The Six Phases

```
Plan --> Design --> Code --> Build --> Test --> Deploy --> Operate
 |        |         |       |        |        |         |
 +-- sec--+-- sec --+-- sec -+-- sec -+-- sec -+-- sec --+
   reqs    threat    review   SAST    DAST     runtime
   risk    model     secrets  SCA     pen      monitor
   class.  abuse     review   sign    chaos    incident
                    SAST     SBOM    perf     forensics
```

| Phase     | Primary security activity                | Output artifact                          |
| --------- | ---------------------------------------- | ---------------------------------------- |
| Plan      | Security requirements, risk classification | Story acceptance criteria, data classification |
| Design    | Threat model, abuse cases, control mapping | Threat model note (4Q)                   |
| Code      | Peer review, secrets prevention, IDE feedback | PR approvals, pre-commit logs            |
| Build     | SAST, SCA, SBOM, image build hardening    | Signed artifact, SBOM, scan report      |
| Test      | DAST, IaC scan, integration security tests | Test report, IaC findings               |
| Deploy    | Policy gates, signed provenance, approval | Deployment record, approval audit        |
| Operate   | Runtime detection, anomaly response, IR   | Incident reports, control tuning notes  |

## 2. Three Gate Types

A *gate* is a checkpoint that the artifact must pass to advance to the next phase. Three flavors:

### Entry Gates
Run *before* work begins on the phase. Cheap to fail, no rework.
  - Story has acceptance criteria that include a security check
  - Design review checklist signed off before code
  - Threat model attached before code starts

### Exit Gates
Run *after* the phase completes, before the next phase starts. This is where most scanners live.
  - SAST clean at high/critical severity
  - SCA: no vulnerable deps above policy threshold
  - DAST: no high-severity findings on staging

### Continuous Gates
Run throughout, every commit, in the background. Must be fast and incremental.
  - Secrets detection (gitleaks pre-commit + pre-merge)
  - Linting with security rules
  - Dependency CVE feed (Dependabot/Renovate)

```
                  Entry   Exit   Continuous
Plan               ✓
Design             ✓       ✓
Code               ✓               ✓
Build                      ✓       ✓
Test                       ✓
Deploy                     ✓       ✓
Operate                                  ✓
```

## 3. Maturity Tiers

Most teams do not jump from zero to "SOC2 Type II audited" in a quarter. Three tiers give a phased path. Pick the tier you are at; pick the *next* tier's controls and implement them over one quarter.

### Tier 1 — Baseline (weeks 1–4)

You are starting from a near-empty pipeline. Get the highest-leverage controls in.

  - Git repo: branch protection, signed commits, secrets in env (not in code)
  - Pre-commit: gitleaks
  - CI: SAST (Semgrep), SCA (Trivy fs) on every PR
  - Build: image scan (Trivy) on every build
  - Deploy: manual approval for prod

This tier blocks the worst 80% of common vulns: hardcoded secrets, known-CVE dependencies, critical container vulns.

### Tier 2 — Industry Standard (months 2–4)

Add the controls an auditor expects.

  - SBOM emitted and stored (SPDX or CycloneDX)
  - Signed images (cosign) + verified at deploy
  - IaC scan (Checkov, tfsec) on every Terraform PR
  - DAST (ZAP baseline) on every staging deploy
  - Policy-as-code (OPA/Kyverno) gating deploys
  - Incident runbooks exist for top 5 attack scenarios

This tier qualifies you for most enterprise customer security questionnaires.

### Tier 3 — Differentiator (months 6+)

What separates a good team from a great one.

  - SLSA Level 3+ provenance
  - Continuous red-team exercise (quarterly)
  - Threat intel feed integrated into SCA rules
  - Anomaly detection in CI (detect compromised dependencies within hours, not days)
  - Chaos engineering for security controls
  - Federated SSO across all internal tools

This tier is what hyperscalers and security-conscious enterprises (fintech, healthcare) expect.

## 4. A Working SSDLC Policy (One Page)

Copy this template and adapt it to your org.

```
Secure SDLC Policy v1.0
Effective: 2026-XX-XX
Owner: Head of Security

1. Scope
   Applies to all software developed, deployed, or maintained by [org name],
   including third-party integrations and infrastructure code.

2. Risk classification
   Every service is classified T1, T2, or T3 based on data sensitivity.
   T1 services (PII, payment, health) require full Tier 3 controls.
   T3 services (internal tools, no PII) require Tier 1 minimum.

3. Mandatory gates
   All code changes must pass:
   - Pre-commit secrets scan
   - PR-time SAST and SCA at high/critical threshold
   - Build-time container scan at high/critical threshold
   - Deploy-time signed-artifact verification

4. Exception handling
   Deviations from the policy require a written exception in the risk register,
   approved by the service owner and the security lead. Exceptions expire in 90 days.

5. Evidence retention
   Scan results, SBOMs, and approval records are retained for 24 months.

6. Review cadence
   Policy is reviewed annually and on material incident.
```

## 5. Phase-by-Phase, In Detail

### Plan

  - Story template includes a "Security considerations" section (often empty for non-security stories; that's fine)
  - Risk classification assigned at intake (T1/T2/T3)
  - Threat-model-required flag set for stories that touch trust boundaries

### Design

  - 4-question threat model in grooming (M02)
  - Data classification for any new data store
  - Reuse of existing security controls where possible (don't reinvent auth)

### Code

  - Branch protection: at least one approval; required status checks pass
  - Pre-commit: secrets (gitleaks), formatting
  - Pre-merge: SAST, SCA, secrets, IaC scan (if IaC touched)
  - Code review checklist includes authn/authz review for relevant files

### Build

  - Reproducible builds where possible
  - SBOM emitted at build (CycloneDX preferred)
  - Image signed (cosign) with keyless OIDC or KMS
  - Build provenance generated (SLSA)

### Test

  - DAST against staging (ZAP baseline minimum)
  - IaC scan (Checkov/tfsec) on Terraform changes
  - Integration security tests: authn, authz, rate limit, input validation
  - Performance/load tests for DoS-relevant paths

### Deploy

  - Signed image required (cosign verify)
  - Policy gates: PSA restricted, network policies applied, image pulled only from trusted registry
  - Audit log: who deployed, when, with which artifact
  - Manual approval for T1 services (configurable per service)

### Operate

  - Runtime detection (Falco for K8s, agent for VMs)
  - Anomaly response runbook
  - Incident response in CI: if prod incident reveals a control gap, file a story to close it
  - Quarterly review: which gates fired, which fired-but-overridden, which never fired (suspicious)

## 6. Adoption Pattern: Don't Boil the Ocean

A common failure: the security team mandates all of Tier 3 on day one. Engineering grinds to a halt, leadership rolls the policy back, and trust is lost.

### The 90-Day Rollout

  - **Days 1–30** — Tier 1 baseline. Pre-commit secrets, SAST, SCA, container scan. No exceptions.
  - **Days 31–60** — Tier 2 in shadow mode. SBOM emitted, DAST runs but does not block; reports only.
  - **Days 61–90** — Tier 2 enabled as blocking gates. DAST blocks on critical. SBOMs required at deploy.
  - **Day 91+** — Tier 2 stable; begin Tier 3 work (provenance, chaos, red team).

Each tier has a measurable exit criterion. If a tier slips, you have a clear conversation with leadership about cost vs. risk.

## 7. SSDLC Anti-Patterns

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| All gates in prod | Slow prod, slow devs | Move gates earlier; use staging for DAST |
| "100% must pass" with no tuning | Alert fatigue, gates get bypassed | Tune rule set week 1; suppress by exception, not by silence |
| Gates as deployment blockers only | High rework cost | Make gates continuous; fail fast on PRs |
| Security requirements copy-pasted | Boilerplate that nobody owns | Per-story threat model, written by the developer |
| One-off scans for compliance | Audit-time scramble | Continuous scanning, evidence stream |

## 8. SSDLC and Compliance

The SSDLC is the *implementation*; compliance frameworks (SOC2, ISO 27001, PCI-DSS, HIPAA) are the *audits* against it. Map your gates to the framework controls:

| Framework     | Common control      | Your SSDLC gate                      |
| ------------- | ------------------- | ------------------------------------ |
| SOC2 CC7.1    | Vulnerability detection | SCA + container scan continuous     |
| SOC2 CC8.1    | Change management   | PR approval + signed image + audit log |
| ISO 27001 A.8.25 | Secure development | Full SSDLC policy + evidence        |
| PCI-DSS 6.3.3 | Install vendor security patches | Dependabot/Renovate with SLA         |
| PCI-DSS 6.4.1 | Test public-facing apps | DAST in staging + manual pen test annual |

Module M18 goes deeper on audit evidence and control mapping.

## 9. Self-Check

  1. Which tier is your team at? Which tier's controls are you missing? What is the smallest set of changes that gets you to the next tier in one quarter?
  2. Draw your current pipeline. Mark every gate. Which phases have entry, exit, and continuous gates? Where are the gaps?
  3. Pick one control you do not have. What is the cost (in dev-days) to add it? What is the cost (in dollars) of *not* having it if exploited?

## 10. The SSDLC and AI-Generated Code

A 2024–2026 development reality: a significant fraction of code is now written by AI assistants (Copilot, Cursor, Claude Code, internal fine-tunes). This changes the SSDLC in three ways:

### Change 1: SAST Becomes Higher-Value

AI-generated code is more likely to contain certain classes of bugs:
  - Insecure deserialization
  - SQL string concatenation
  - Use of `eval`-style constructs
  - Default credentials in scaffolds

The fix: SAST must run on every PR, not just at release. The IDE plugin (M05) becomes more important because the feedback loop shortens the time-to-fix.

### Change 2: The Threat Model Shifts

AI code is often *correct* in the sense that it does what was asked, but *unsafe* in the sense that the developer did not think through the security implications. The 4Q threat model (M02) is more important than ever — the AI does not threat-model for you.

### Change 3: The Code Review Workload Changes

Engineers reviewing AI code must look for:
  - Did the developer specify security constraints in the prompt?
  - Did the AI's output honor those constraints?
  - Are there unstated assumptions that the AI filled in unsafely?

The "code review" of AI output is a new skill; it is closer to threat modeling than to syntax review. The 4Q lives here.

## 11. The SSDLC and the Regulatory Tail

Compliance frameworks are codifying the SSDLC. The implications:

  - **SOC 2 CC8.1** — "Change management" requires evidence of PR approval, tests passing, deploy records. The SSDLC policy is the document that maps to this control.
  - **ISO 27001 A.8.25** — "Secure development" requires a documented SDLC. The policy is the artifact.
  - **PCI-DSS 6.3** — "Security vulnerabilities are identified and ranked" requires SAST, SCA, and SLA tracking. The pipeline produces the evidence.
  - **HIPAA §164.308** — Administrative safeguards include workforce training and access management. The SSDLC roles (developer, security champion, auditor translator) are the implementation.
  - **FedRAMP AC-6** — Least privilege requires implementation at every layer. The SSDLC's CI/CD roles are the demonstration.

M18 covers evidence collection; this module covers the design.

## 12. The SSDLC vs. Agile Sprints

A common friction: the SSDLC feels like waterfall (a single, sequential lifecycle), but the team is running agile (iterative sprints with constant change). The reconciliation:

  - The SSDLC is the *frame*; the sprint is the *iteration*
  - The SDLC's six phases still apply, but the iteration loops over them in days, not months
  - The DoD (M04) is the per-sprint enforcement
  - The threat model (M02) is per story, not per project
  - The continuous gates run on every commit, not on a quarterly cycle

The shift: from "the SDLC is a phase" to "the SDLC is a property of every PR." The M03 maturity model describes the property.

## 13. The SSDLC Beyond the Application

The same phases apply to other artifacts:

  - **Infrastructure** — Plan (architecture review), Design (threat model), Code (Terraform), Build (apply), Test (drift detection), Deploy (terraform apply), Operate (Cloud Custodian, drift alerts)
  - **ML models** — Plan (data classification), Design (model card, threat model for prompt injection), Code (training script), Build (training run), Test (eval set), Deploy (model registry), Operate (drift, bias, adversarial monitoring)
  - **Data pipelines** — Plan (data classification), Design (lineage, threat model), Code (pipeline), Build (compile), Test (data quality), Deploy (schedule), Operate (SLA, alerts)

The SSDLC is a *pattern* of how to think about software development. It applies wherever software is built.

## 14. Common Questions

### "Isn't the SSDLC just bureaucracy?"

No. The SSDLC is a *framework for thinking*, not a process. The processes (PR review, scanning, threat modeling) are the implementation. The framework is the property: every change goes through the phases, every phase has security activities, every activity produces evidence.

### "We are a startup. Do we really need this?"

Yes, but you can start at Tier 1 (M03's baseline). The Tier 1 controls are mostly free (SAST, secrets, SCA on a single PR template). The maturity comes with the org, not the size.

### "We are a regulated industry. Can we skip ahead to Tier 3?"

You can, but you will pay for it in engineering. The 90-day rollout (section 6) is calibrated to minimize the cost of getting to Tier 2. Skipping ahead to Tier 3 in week 1 typically results in alert fatigue and gates that get bypassed. The tiers are not a marketing checklist; they are a sequence of organizational learning.

### "We use a managed CI vendor. Does the SSDLC still apply?"

Yes, but the *implementation* shifts. The vendor provides the runner; you provide the configuration. M05–M15 cover the tools you put in the runner. M11 covers the runner itself.

## 15. SSDLC and the Audit Trail

Every SSDLC phase leaves evidence:

  - **Plan** — story, risk classification, acceptance criteria (M04)
  - **Design** — threat model 4Q (M02)
  - **Code** — PR, approvals, pre-commit logs
  - **Build** — scan reports, SBOM, signed image (M05, M07, M08, M13)
  - **Test** — DAST report, IaC scan (M10)
  - **Deploy** — admission logs, signed image verified (M15)
  - **Operate** — runtime alerts, postmortems (M17, M19)

The audit trail is a *byproduct* of the SSDLC, not a separate workstream. M18 covers the evidence collection in depth.

## 16. The SSDLC and Open Source

Most modern applications are 70–90% open source. The SSDLC applies to open source in two ways:

  - **Consuming** — the SEC- criteria apply to every dep you pull in (M07); the threat model includes the dep's surface area
  - **Contributing** — if you contribute to OSS, the SEC- criteria apply to your contributions; the PR review is the gate

For OSS contributors, the SSDLC is typically lighter:
  - One reviewer is the bar
  - Threat model may be a single line
  - SAST is run by the project, not by you
  - The build is the project's, not yours

For OSS consumers, the SSDLC is heavier (M07, M08, M09, M13, M14, M15) — you must verify the OSS you consume, because you cannot trust the project.

## 17. The SSDLC in Vendor Procurement

When you buy a SaaS product, the SSDLC of the vendor is part of the deal. The questions to ask:

  - "Show us your SDLC policy"
  - "Do you do SAST, SCA, secrets scanning?"
  - "How do you handle vulnerabilities?"
  - "What's your SLA for critical CVE remediation?"
  - "Can you share your SOC 2 / ISO 27001 report?"

A vendor with a mature SSDLC is a lower-risk vendor. M18 covers the evidence collection that backs this answer.

## 18. The SSDLC and the Audit

The SSDLC is the foundation of the audit. Every framework control maps to a phase:

| Framework | SSDLC phase |
| --------- | ----------- |
| SOC 2 CC8.1 (change mgmt) | Plan, Code, Build, Deploy |
| SOC 2 CC7.1 (vuln detection) | Build, Test |
| SOC 2 CC7.4 (incident response) | Operate |
| ISO A.8.25 (secure dev) | All phases |
| ISO A.8.32 (change mgmt) | Plan, Code, Deploy |
| PCI 6.3 (vuln mgmt) | Build, Test |
| PCI 6.4 (change control) | Plan, Code, Build, Deploy |
| FedRAMP SA-15 (dev process) | All phases |
| HIPAA §164.308 (admin) | Plan, Operate |

A mature SSDLC = mature compliance. M18 covers the evidence.

## 19. The SSDLC Across Frameworks

Different frameworks emphasize different phases:

  - **SOC 2** — emphasizes Operate (monitoring, response)
  - **ISO 27001** — emphasizes Plan (risk management)
  - **PCI-DSS** — emphasizes Build, Test, Deploy
  - **FedRAMP** — emphasizes all phases equally
  - **HIPAA** — emphasizes Plan (administrative safeguards)
  - **NIST CSF** — emphasizes all phases; the Identify → Protect → Detect → Respond → Recover function is the SDLC in disguise

A mature SSDLC satisfies all of these. The SSDLC is the *substrate*; the frameworks are the *views*.

## 20. The SSDLC and the Capstone (M20)

M20 integrates the SSDLC with the implementation. The capstone is the working pipeline that demonstrates the SSDLC properties. After the capstone, the SSDLC is no longer abstract — it is the pipeline you operate.

## Related

  - [[DevOps/devsecops/stage0-foundations/01-devsecops-mindset|M01: DevSecOps Mindset]]
  - [[DevOps/devsecops/stage0-foundations/02-threat-modeling|M02: Threat Modeling]]
  - [[DevOps/devsecops/stage0-foundations/04-security-requirements|M04: Security Requirements]]
  - [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/security|NFR — Security]]

---
title: "M18: Compliance Evidence & Audit Trail"
tags: [devsecops, stage4, runtime, compliance, soc2, iso27001, pci-dss, evidence, audit]
date: 2026-06-16
description: "Module 18 of 20 — generating compliance evidence from your DevSecOps pipeline. SOC2, ISO 27001, PCI-DSS, HIPAA, FedRAMP control mapping, evidence collection automation, and surviving the audit."
---

# M18: Compliance Evidence & Audit Trail

A working DevSecOps pipeline produces a continuous stream of evidence: scan results, SBOMs, signed artifacts, change approvals, access logs. The audit is the moment when that evidence must be assembled, mapped to controls, and presented. This module covers evidence collection automation, control mapping, and the operational practice of "compliance is a side-effect of good engineering."

## Learning Objectives

By the end of this module you should be able to:

  - Map a SOC2 / ISO 27001 / PCI-DSS control to a pipeline artifact
  - Automate evidence collection for continuous compliance
  - Maintain a control matrix as living documentation
  - Survive a SOC2 Type II audit using pipeline artifacts
  - Build a customer-facing compliance posture document
  - Distinguish evidence from policy from implementation

## 1. The Three Layers of Compliance

| Layer | Definition | Example |
| ----- | ---------- | ------- |
| Policy | What we say we do | "We perform SAST on every PR" |
| Implementation | What we actually do | Semgrep runs in `.github/workflows/sast.yml` |
| Evidence | Proof of what we did | GitHub Actions logs from 2026-Q2 showing 1,247 runs, 0 high findings allowed |

Auditors want evidence. Policy is what you wrote; implementation is what you built; evidence is what you can produce. The pipeline produces evidence continuously.

```
  Policy     →    Implementation    →    Evidence
  (wiki)           (code)                  (logs, artifacts)
  "We do SAST"     "Semgrep in CI"         "1,247 runs, 0 high findings"
```

## 2. The Evidence Streams

A mature DevSecOps pipeline generates evidence for most controls automatically. The streams:

| Stream | Source | Retention | What it proves |
| ------ | ------ | --------- | -------------- |
| Scan results | SAST, SCA, secrets, IaC, image | 24+ months | Vulnerability detection |
| SBOMs | Syft/Trivy at build | 24+ months | Software inventory |
| Signatures | cosign at build | 24+ months | Artifact integrity |
| Provenance | SLSA generator at build | 24+ months | Build integrity |
| Change logs | Git commits, PR approvals | Indefinite | Change management |
| Access logs | CloudTrail, K8s audit, GitHub audit | 12+ months | Access control |
| CI/CD logs | GitHub Actions, GitLab CI, Jenkins | 12+ months | Pipeline integrity |
| Deployment logs | Argo CD, Spinnaker, kubectl | 12+ months | Change deployment |
| Runtime alerts | Falco, Wazuh, CloudTrail | 12+ months | Detection and response |
| Incident records | PagerDuty, ServiceNow, Jira | 7+ years | Incident management |
| Training records | LMS, signed acknowledgments | Per regulation | Awareness |

The compliance team does not generate this evidence. The pipeline does. The compliance team's job is to *collect*, *map*, and *present* it.

## 3. The Control Matrix

A control matrix is the document that maps your evidence to the framework. It is a living document, versioned in git.

### Template

| Control ID | Framework | Description | Implementation | Evidence source | Owner | Last verified |
| ---------- | --------- | ----------- | -------------- | --------------- | ----- | ------------- |
| CC6.1 | SOC2 | Logical access controls | OIDC federation, Vault, RBAC | CloudTrail, Vault audit log, GitHub audit | Security | 2026-06-01 |
| CC6.6 | SOC2 | External access boundaries | Kyverno network policies, SG rules | K8s audit log, AWS Config | Platform | 2026-06-01 |
| CC7.1 | SOC2 | Vulnerability detection | Trivy, Snyk, Dependabot | Scan reports, Dependabot PRs | Security | 2026-06-01 |
| CC7.2 | SOC2 | System monitoring | Falco, Wazuh, Prometheus | Alert logs, dashboards | SRE | 2026-06-01 |
| CC8.1 | SOC2 | Change management | PR approvals, signed images, GitOps | GitHub PR history, cosign sigs, Argo CD sync log | Platform | 2026-06-01 |

### How to Maintain

  - **Version-controlled** in git (e.g., `compliance/control-matrix.md` or a Google Sheet with a markdown export)
  - **Reviewed quarterly** by the security team
  - **Linked to evidence** — every row has a path to the actual evidence
  - **Owned** — every row has a person responsible

## 4. Automating Evidence Collection

The work of compliance is collecting, not generating. The pipeline generates; you collect.

### Pattern 1: Log Shipping

Every log stream goes to a long-term store (S3 with Object Lock, CloudWatch, a SIEM).

```bash
# GitHub Actions: export logs to S3
- name: Archive workflow logs
  if: always()
  run: |
    aws s3 cp $RUNNER_TEMP/workflow-log.txt \
      s3://audit-logs/github-actions/${{ github.workflow }}/${{ github.run_id }}.log \
      --sse aws:kms
```

### Pattern 2: Periodic Snapshot

Once a month, snapshot the state:

```bash
# Script: monthly compliance snapshot
#!/bin/bash
DATE=$(date +%Y-%m)

# Vulnerability scan snapshot
trivy image --format json my-app:v1.2.3 > evidence/sca-$DATE.json

# IAM users snapshot
aws iam generate-credential-report > evidence/iam-$DATE.json

# CloudTrail events for the month
aws s3 cp s3://cloudtrail-logs/AWSLogs/.../$DATE evidence/cloudtrail-$DATE/

# Sign the snapshot
cosign sign --key awskms:///alias/audit-key evidence-$DATE.tar.gz
```

### Pattern 3: Continuous Compliance Platforms

Tools that automate the above:

  - **Drata** — SOC2, ISO 27001, HIPAA, PCI
  - **Vanta** — same set
  - **Secureframe** — same set
  - **Tugboat Logic** (OneTrust) — same set
  - **Sprinto** — same set

These platforms connect to your cloud, GitHub, AWS, GCP, etc., and automatically collect evidence. They reduce audit prep from weeks to days. The cost is real but usually less than a headcount.

### Pattern 4: Custom Evidence Pipeline

For orgs that prefer in-house, build a small pipeline:

```
  Sources (CloudTrail, GitHub, K8s, scanners)
       |
       v
  Collectors (small scripts per source)
       |
       v
  Normalizer (to a common schema)
       |
       v
  Storage (S3 with Object Lock, or a compliance DB)
       |
       v
  Mapper (control matrix → evidence paths)
       |
       v
  Auditor portal (UI to find evidence by control)
```

The first three are easy; the auditor portal is where the work is. Many teams buy Drata/Vanta rather than build.

## 5. Surviving a SOC2 Type II Audit

A Type II audit covers a period (typically 6–12 months) and tests both the design *and* the operating effectiveness of controls. The auditor will:

  1. Select a sample of control executions (e.g., 25 PRs from the period)
  2. For each, request the evidence: the PR, the approval, the scan result, the deploy record
  3. Verify the evidence shows the control operated as designed
  4. Note any exceptions (controls that didn't operate as designed in the sample)

The auditor is testing the system, not the people. Make their job easy:

### Pre-Audit Checklist

  - [ ] Control matrix up to date for the audit period
  - [ ] Evidence collected for the full audit period
  - [ ] Evidence stored in a system the auditor can access (read-only portal preferred)
  - [ ] Logs signed and tamper-evident
  - [ ] Change log shows control changes during the period
  - [ ] Incident log shows all incidents and their resolution
  - [ ] Access reviews documented for the period
  - [ ] Training records complete
  - [ ] Policy documents versioned and dated

### Common SOC2 Type II Findings (and How to Avoid)

| Finding | Cause | Fix |
| ------- | ----- | --- |
| "Evidence not available for [date]" | Logs not retained, or scanner was down | Continuous shipping to S3, 24+ month retention |
| "Control did not operate as designed" | Scanner was bypassed, exception not documented | All exceptions in the risk register, with expiry |
| "Insufficient segregation of duties" | Same person wrote and deployed code | PR approval required; deploy via separate identity |
| "Access reviews not performed" | Quarterly access reviews not run | Calendar reminder; document each review |
| "Vulnerabilities not remediated in SLA" | SLA not tracked | SLA tracking dashboard; ticket per finding |

## 6. Mapping Common Frameworks

### SOC2 (Trust Services Criteria)

| TSC | Description | Pipeline evidence |
| --- | ----------- | ----------------- |
| CC6.1 | Logical access | CloudTrail, Vault audit, GitHub audit |
| CC6.6 | Access boundaries | K8s network policies, AWS SGs, VPC flow logs |
| CC6.7 | Data in transit | TLS configs, cert-manager certs |
| CC6.8 | Malicious software | Trivy, Falco, EDR |
| CC7.1 | Vulnerability detection | SAST, SCA, image scan, IaC scan |
| CC7.2 | System monitoring | Falco, Prometheus, Wazuh |
| CC7.3 | Anomaly evaluation | Wazuh correlation, anomaly alerts |
| CC7.4 | Incident response | PagerDuty, postmortems, runbooks |
| CC8.1 | Change management | PR approvals, signed images, GitOps |
| CC9.2 | Vendor management | SBOMs, vendor risk reviews |

### ISO 27001 Annex A (selected)

| Control | Description | Pipeline evidence |
| ------- | ----------- | ----------------- |
| A.5.15 | Access control | IAM policies, RBAC |
| A.5.16 | Identity management | Service accounts, OIDC |
| A.8.7 | Protection against malware | EDR, image scan |
| A.8.8 | Management of vulnerabilities | SCA, SLA tracking |
| A.8.9 | Configuration management | IaC scanning, drift detection |
| A.8.16 | Monitoring activities | SIEM, audit logs |
| A.8.25 | Secure development | Full SDLC (M03) |
| A.8.28 | Secure coding | SAST, code review |
| A.8.32 | Change management | PR approvals, GitOps |
| A.8.33 | Test information | Test plans, pen test reports |

### PCI-DSS v4.0 (selected)

| Requirement | Description | Pipeline evidence |
| ----------- | ----------- | ----------------- |
| 6.2.4 | Software dev security | SAST, code review |
| 6.3.1 | Vulnerability management | SCA, Trivy |
| 6.3.3 | Install vendor security patches | Dependabot, Renovate |
| 6.4.1 | Test public-facing apps | DAST, ZAP |
| 6.4.2 | Review of code changes | PR approvals, threat model |
| 8.3.1 | Strong authentication | MFA, OIDC |
| 10.x | Logging | Audit logs, SIEM |
| 11.3 | Penetration testing | Annual pen test report |
| 11.4 | Intrusion detection | Falco, Wazuh |

## 7. The Customer-Facing Compliance Posture

Customers ask for evidence too. The standard artifacts:

  - **SOC 2 Type II report** (annual)
  - **ISO 27001 certificate** (3-year cycle)
  - **Pen test summary** (annual)
  - **SBOMs** (per release, on request — M08)
  - **VEX** (continuous)
  - **Compliance posture document** (CSA STAR, SIG questionnaire, vendor security questionnaire responses)
  - **Sub-processor list** (GDPR)
  - **Data processing addendum** (GDPR)

The pipeline produces most of this continuously. The compliance team curates and publishes.

## 8. The EU CRA / US EO 14028 Angle

The regulatory pressure is increasing:

  - **US Executive Order 14028** (2021) — SBOMs for federal procurement, supply chain attestations
  - **EU Cyber Resilience Act** (2024) — SBOMs for products with digital elements, vulnerability handling
  - **US Cyber Safety Review Board** — post-incident reporting, lessons learned
  - **NIS2** (EU) — incident reporting, supply chain security

The pipeline artifacts that satisfy these:

  - SBOMs (M08)
  - SLSA provenance (M14)
  - VEX (M14)
  - Vulnerability disclosure policy
  - Incident response process documentation

If you have M08, M14, M17, M19 in place, you are most of the way to CRA/EO compliance.

## 9. Common Anti-Patterns

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| Compliance is a separate team that "owns" it | Engineering has no skin in the game | Embed security champions (M04) |
| Evidence collected manually at audit time | 3-week scramble, incomplete | Continuous collection, automated |
| Policy in a wiki, evidence in a folder | Drift between what you say and what you do | Policy in code, evidence from the same source |
| Auditor portal is read-only but unauditable | Auditor sees the current state but not the history | Object Lock, signed logs, immutable storage |
| SLA for vulnerability remediation is 90 days | Auditor notes exceptions | Tighter SLA with auto-escalation |
| No exception register | Exceptions exist but are untracked | Risk register with expiry dates |

## 10. Self-Check

  1. Pick one control (e.g., "vulnerability management"). Can you produce the evidence for the last 30 days in under 30 minutes?
  2. Is your control matrix in git, versioned, owned, and reviewed quarterly?
  3. What would happen if your auditor asked for the SBOM of a release from 9 months ago? Can you produce it?

## 11. Building the Evidence Pipeline

The evidence pipeline collects, normalizes, and stores evidence. The reference architecture:

```
  Sources
  ───────
  - GitHub (PRs, commits, workflow runs)
  - AWS (CloudTrail, Config, GuardDuty)
  - K8s (audit log, Kyverno logs)
  - Trivy (scan results)
  - Falco (alerts)
  - Wazuh (correlated events)
  - Vault (audit log)
  - Snyk (vuln reports)
  - Dependabot (PRs)
  - cosign (signatures)
       |
       v
  Collectors (small per-source scripts)
       |
       v
  Normalizer (to common schema: control, source, evidence, timestamp)
       |
       v
  Storage (S3 with Object Lock, or compliance DB)
       |
       v
  Mapper (control matrix → evidence paths)
       |
       v
  Auditor portal (UI / API for control evidence)
```

Each stage is a small script. Each stage is testable. The pipeline is auditable because the pipeline itself is auditable.

## 12. The Compliance Automation Spectrum

A spectrum of automation:

```
  Manual                              Automated
  ───────────────────────────────────────────────────────────
  |    |    |    |    |    |    |    |    |    |    |
  Audit-time     Quarterly     Weekly      Daily       Continuous
  evidence       evidence      evidence    evidence    evidence
```

Most orgs start at audit-time (gather evidence in the weeks before). The maturity arc moves to continuous (evidence collected automatically, every day). The savings: 4–6 weeks of audit prep reduced to 0.

The cost: 0.5–1 FTE for the pipeline, plus the platform cost (S3, SIEM).

## 13. Compliance Platforms Comparison

| Platform | Frameworks | Integration | Pricing |
| -------- | ---------- | ----------- | ------- |
| Drata | SOC 2, ISO 27001, HIPAA, PCI, GDPR, NIST | AWS, GCP, Azure, GitHub, GitLab, K8s | Per-employee tier |
| Vanta | Same as Drata | Same | Per-employee tier |
| Secureframe | Same | Same | Per-employee tier |
| Tugboat (OneTrust) | Same | Same | Enterprise |
| Sprinto | SOC 2, ISO 27001, HIPAA, GDPR | Cloud-native | Per-employee |
| Laika | SOC 2, ISO 27001, HIPAA, PCI | Cloud, CI | Per-feature |

The platforms handle the boring parts (collecting logs, mapping to controls, generating reports). The custom parts (org-specific policies, custom evidence) still need in-house effort.

## 14. The Compliance Team Structure

For a mid-size org, the compliance function is typically:

  - **Compliance lead** (1 FTE) — owns the framework, the audit, the evidence
  - **Security engineer** (0.5 FTE) — implements the controls; produces the technical evidence
  - **Platform engineer** (0.25 FTE) — maintains the evidence pipeline
  - **External auditor** — engaged for SOC 2 / ISO 27001 audits

For a regulated industry (FedRAMP, PCI, HIPAA), add specialists.

## 15. The Continuous Audit

The future of compliance is *continuous audit*. Tools like Drata and Vanta support this: a control is tested continuously, not at audit time.

```
  Traditional audit                Continuous audit
  ─────────────────                ────────────────
  Auditor arrives                  Auditor sees live dashboard
  Requests 25 samples              All 100,000 events are tested
  Engineer scrambles               Engineer reads dashboard
  Auditor writes report            Auditor reviews trends
  Audit time: weeks                Audit time: days
  Evidence: snapshot               Evidence: continuous
```

The maturity arc moves from "audit" to "continuous audit" to "continuous attestation" (where the customer attests to their own controls, the auditor verifies the attestation).

## 16. The Customer-Facing Compliance Posture (Deep Dive)

The customer-facing posture document is more than a compliance certificate. It is the *trust* between you and your customer. The components:

  - **Compliance certifications** — SOC 2, ISO 27001, PCI-DSS, HIPAA
  - **Penetration test summary** — annual, redacted
  - **Vulnerability disclosure policy** — how to report a vuln to you
  - **Security white paper** — the architecture, in customer-friendly language
  - **SBOMs** (per release) — M08
  - **SLSA / supply-chain posture** — what level, what evidence (M14)
  - **Sub-processor list** — every vendor that touches customer data
  - **Data processing addendum** (DPA) — GDPR/CCPA
  - **Insurance certificate** — cyber insurance
  - **Compliance questionnaires** — pre-filled CAIQ, SIG, custom

The customer reviews this; the customer decides whether to trust you. The quality of the posture is the quality of the trust.

## 17. The Audit Trail Anti-Patterns

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| "We have evidence" but it's in someone's head | Auditor cannot verify | Evidence in code, not in people |
| Evidence in a folder, not in a system | No immutability, no audit | S3 + Object Lock |
| Different evidence for different auditors | Drift, inconsistency | Single source of truth |
| Evidence lost after the audit | Cannot answer follow-up | 24+ month retention |
| Evidence collated manually | 3-week scramble, incomplete | Continuous collection |
| Auditor portal is read-only but unauditable | Auditor sees current state only | Versioned evidence |
| Compliance team separate from engineering | Engineer does not own the controls | Embed security champions |

## 18. The Self-Audit

Before the auditor arrives, audit yourself. The pattern:

  - Pick a control (e.g., "vulnerability management")
  - Pretend the auditor is asking for evidence
  - Pull the evidence
  - Evaluate: would this pass an audit?
  - If not, fix the gap
  - Repeat for every control

Run a self-audit quarterly. The first self-audit surfaces massive gaps. The fifth is nearly perfect.

## 19. Compliance and Engineering Velocity

A common tension: compliance slows engineering. The right answer: compliance *codifies* engineering good practice. A well-built pipeline *is* the compliance. The auditor verifies what the engineering org already does.

The wrong answer: compliance is a separate workstream that produces evidence in a separate format. The engineering org does its work; the compliance team scrambles to find evidence. The two never meet.

The maturity arc:

```
  Year 1: compliance is separate
  Year 2: compliance reuses engineering artifacts
  Year 3: compliance IS engineering artifacts; the auditor consumes the pipeline output
```

By year 3, the SOC 2 audit is a 1-week exercise, not a 6-week one.

## Related

  - [[DevOps/devsecops/stage0-foundations/03-secure-sdlc|M03: Secure SDLC]]
  - [[DevOps/devsecops/stage1-code/08-sbom-generation|M08: SBOM Generation]]
  - [[DevOps/devsecops/stage3-deploy/14-supply-chain-attestations|M14: Supply Chain Attestations]]
  - [[DevOps/devsecops/stage4-runtime/17-runtime-detection|M17: Runtime Detection]]
  - [[DevOps/devsecops/stage4-runtime/19-incident-response-in-ci|M19: Incident Response in CI]]
  - [[DevOps/devsecops/stage4-runtime/README|Stage 4 — Runtime]]

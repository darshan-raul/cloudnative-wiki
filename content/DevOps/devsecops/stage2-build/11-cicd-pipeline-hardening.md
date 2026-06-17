---
title: "M11: CI/CD Pipeline Hardening"
tags: [devsecops, stage2, build, cicd, github-actions, gitlab, jenkins, runners, hardening]
date: 2026-06-16
description: "Module 11 of 20 — the pipeline itself is an attack surface. Securing GitHub Actions, GitLab CI, Jenkins, and self-hosted runners. Least-privilege tokens, ephemeral runners, secrets hygiene, and SLSA L3 build provenance."
---

# M11: CI/CD Pipeline Hardening

The pipeline runs code from every contributor. It has access to production credentials, deploy keys, and signing keys. It is, by definition, a high-value target. When SolarWinds and 3CX were compromised, the attack vector was the build pipeline. This module covers hardening the pipeline itself: ephemeral runners, least-privilege tokens, secrets hygiene, and the supply-chain attacks that target CI/CD.

## Learning Objectives

By the end of this module you should be able to:

  - Configure ephemeral, isolated CI runners
  - Apply least-privilege to pipeline tokens and cloud credentials
  - Defend against the top 5 CI/CD attack patterns (pwn request, malicious action, runner takeover, cache poisoning, artifact tampering)
  - Run pipelines with OIDC federation (M12 deep-dive)
  - Generate SLSA L3 build provenance
  - Audit a pipeline for the OWASP CICD-SEC-01..10 threats

## 1. The Pipeline Is an Attack Surface

Most engineering orgs treat the pipeline as internal infrastructure. The reality:

  - The pipeline reads source code (often including secrets in env files)
  - The pipeline writes artifacts (images, binaries, SBOMs) that go to production
  - The pipeline holds credentials (cloud, registry, signing, deploy)
  - The pipeline executes code (your code, your deps, your actions)
  - The pipeline is reachable from the internet (PRs from forks can trigger it)

This is a juicy target. The 2022–2024 attack wave (Codecov, ua-parser-js, 3CX, SolarWinds follow-on) all exploited CI/CD. The 2024 OWASP Top 10 for CI/CD enumerates the threats.

### OWASP CICD-SEC Top Threats (Condensed)

| ID | Threat | One-line description |
| -- | ------ | -------------------- |
| 1 | Insufficient Flow Control | No review of pipeline changes |
| 2 | Inadequate Identity & Access Mgmt | Over-privileged service accounts |
| 3 | Dependency Chain Abuse | Malicious action/dependency |
| 4 | Poisoned Pipeline Execution | Code in repo manipulates pipeline |
| 5 | Insufficient PBAC | Pipeline-based access controls missing |
| 6 | Insufficient Credential Hygiene | Long-lived secrets in env |
| 7 | Insecure System Configuration | Runners with default creds, no patches |
| 8 | Ungoverned Usage of 3rd Party Services | Unvetted actions, services |
| 9 | Improper Artifact Integrity Validation | No signature verification on deploy |
| 10 | Insufficient Logging & Visibility | No audit trail |

This module addresses each, with the operational pattern.

## 2. The Build Runner

The runner is the VM/container that executes pipeline steps. Two classes:

### Hosted Runners (GitHub Actions, GitLab SaaS, Buildkite SaaS)

Pros:
  - Managed patches, isolated network, ephemeral
  - Compliance certifications inherited from vendor
  - No runner maintenance

Cons:
  - Cost at scale
  - Limited customization
  - Vendor lock-in

For most orgs under 100 engineers, hosted runners are the right answer.

### Self-Hosted Runners

Pros:
  - Cost at scale
  - Custom hardware (GPU, ARM, bare metal)
  - Air-gapped or restricted network

Cons:
  - You patch them
  - You isolate them
  - You audit them

If you self-host, the bar is higher.

### Self-Hosted Runner Hardening

  - **Ephemeral** — fresh VM per job, destroyed on completion. Never reuse a runner across builds. (GitHub Actions and GitLab CI both support ephemeral runners.)
  - **Minimal base** — Ubuntu minimal + build tools; no extra services
  - **No docker socket in runner** — defeats isolation. Use rootless Docker, kaniko, or buildah
  - **No long-lived credentials on disk** — credentials fetched at job start, never persisted
  - **No SSH access** — if you need to debug, you have a different problem
  - **Network egress restricted** — allowlist of registries, package mirrors; deny by default
  - **Patched weekly** — automatic security updates

```yaml
# GitHub Actions: ephemeral self-hosted runner
jobs:
  build:
    runs-on: [self-hosted, linux, ephemeral]
    steps:
      - uses: actions/checkout@v4
      # ...
```

For GitLab, use the `runner` executor with `cache_dir` and `builds_dir` on tmpfs; the runner is destroyed on job end.

## 3. Secrets in the Pipeline

### The Rule: No Long-Lived Secrets in the Pipeline

If your pipeline has `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in a secret, you have a problem. Those keys have no expiration. If the runner is compromised, the keys are valid until you rotate.

The fix: OIDC federation. The pipeline assumes a cloud role via a short-lived token (15min–1hr TTL). If the runner is compromised, the token expires in an hour.

Module M12 covers OIDC in detail. This module covers the surrounding hygiene.

### Where to Store Secrets

| Secret type | Where | Why |
| ----------- | ----- | --- |
| Cloud creds | OIDC, no static key | Short-lived |
| Deploy tokens | Vault dynamic, fetched at job start | Audited, rotated |
| Registry creds | OIDC to registry, or short-lived token | Short-lived |
| Signing keys | KMS-backed cosign keyless | Not extractable |
| Notification webhooks | GitHub/GitLab secret store | Scoped |
| Test API keys | GitHub/GitLab secret store (synthetic) | Scoped to env |

The last row is important: test API keys should be *synthetic* — keys to a sandbox environment, not production. A leaked test key compromises a sandbox, not a customer.

### Secret Masking

Most CI vendors mask secrets in logs automatically (GitHub, GitLab, CircleCI). Verify:

  - Secrets are referenced via `secrets.X` (not echoed in plaintext)
  - `set -x` in shell scripts is avoided (echoes all variables)
  - PR builds from forks do *not* have access to secrets (most platforms mask secrets from fork PRs by default; verify your config)

```yaml
# GitHub Actions: secrets in fork PRs are NOT available by default
on:
  pull_request_target:  # CAREFUL — secrets ARE available
    branches: [main]
```

The `pull_request_target` trigger is a common footgun. It runs in the context of the base branch with full secret access, but uses the PR's code. An attacker can PR malicious code and exfiltrate secrets. Use `pull_request` (no secrets) or `pull_request_target` only with extreme caution.

## 4. Top 5 Attack Patterns and Defenses

### Attack 1: Pwn Request (Compromise via PR)

**Pattern**: Attacker opens a PR with a malicious change. CI runs the change. The change exfiltrates secrets.

**Defense**:
  - Fork PRs: no secret access (verify)
  - Branch protection: required status checks
  - Workflow `permissions:` block at the top — default deny

```yaml
# Top of every workflow file
permissions:
  contents: read  # default deny for everything else
```

### Attack 2: Malicious Third-Party Action

**Pattern**: A widely-used GitHub Action is compromised (this has happened: tj-actions, cryptomining via compromised action). Any repo using that action executes the malicious code.

**Defense**:
  - Pin actions to a commit SHA, not a tag

```yaml
# BAD
- uses: actions/checkout@v4

# GOOD
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
```

  - Use `dependabot.yml` to get alerts on action updates
  - For high-risk actions, vendor them into your own repo

### Attack 3: Runner Takeover

**Pattern**: Attacker gains shell on the runner (via malicious code or compromised dep). They pivot to cloud using the runner's credentials.

**Defense**:
  - Ephemeral runners (no persistent state)
  - OIDC, not static keys
  - Network egress restricted
  - EDR on the runner (Falco for K8s, osquery for VMs)

### Attack 4: Cache Poisoning

**Pattern**: Caches (e.g., `~/.npm`, `/root/.cache/pip`) are stored across jobs. Attacker poisons a cached file with malicious code that executes on the next job.

**Defense**:
  - Cache key includes a hash of the lockfile; cache invalidates on lockfile change
  - Never cache `node_modules` or compiled binaries across security boundaries
  - Use a separate cache per branch, per PR

```yaml
# GitHub Actions
- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: npm-${{ hashFiles('package-lock.json') }}
    restore-keys: |
      npm-
```

### Attack 5: Artifact Tampering

**Pattern**: Attacker modifies an artifact in the registry between build and deploy.

**Defense**:
  - Sign artifacts at build (M13)
  - Verify signatures at deploy (M15)
  - Use admission controllers (Kyverno, Connaisseur) to reject unsigned artifacts

## 5. Pipeline as Code Discipline

### Pipeline Files Live in Git

The pipeline is code. It is reviewed, tested, and versioned.

  - `.github/workflows/*` — committed, reviewed
  - `Jenkinsfile` — committed, reviewed
  - `gitlab-ci.yml` — committed, reviewed
  - `Makefile`, shell scripts called by CI — committed, reviewed

### Branch Protection on the Pipeline Directory

Protect the directory that holds pipeline config:

```yaml
# GitHub branch protection: require review for changes to .github/
required_pull_request_reviews:
  required_approving_review_count: 2
  restrictions:
    users: ["security-team"]
```

### Pipeline Changes Get Their Own Review

A change to `.github/workflows/deploy.yml` should be reviewed by a security-aware engineer. A change to a workflow that has access to production credentials should be reviewed by *two*.

## 6. SLSA L3 Build Provenance

The build platform is hardened such that even the platform operators cannot forge provenance. GitHub Actions, Google Cloud Build, and Tekton Chains are SLSA L3 compliant out of the box for many build types.

To produce SLSA L3 provenance:

```yaml
# GitHub Actions
- uses: slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v1.9.0
  with:
    base64-subjects: ${{ needs.build.outputs.digests }}
```

The provenance is signed and uploaded as an attestation. At deploy, the admission controller verifies the provenance. Module M14 covers attestation in depth.

## 7. Logging and Audit

The pipeline is auditable infrastructure. Every job run, every secret access, every deploy should leave a trail.

  - **GitHub Actions** — logs retained 90 days on SaaS; export to S3/CloudWatch for longer retention
  - **GitLab CI** — same; export to your SIEM
  - **Jenkins** — log to file; ship to SIEM
  - **CloudTrail / Cloud Logging** — for the runner's cloud activity

What to log:
  - Every job run (workflow name, commit SHA, runner, status, duration)
  - Every secret read (which secret, which step, which job)
  - Every cloud API call from the runner
  - Every artifact push (digest, signature, registry path)
  - Every deploy (who approved, what artifact, what env)

Pipe to Wazuh (covered in [[Security/siem/wazuh/README]]) or your SIEM of choice. Module M19 covers incident response in CI.

## 8. GitHub Actions Hardening Checklist

  - [ ] All actions pinned to commit SHA
  - [ ] `permissions: contents: read` at the top of every workflow
  - [ ] No `pull_request_target` with secret-using steps
  - [ ] Branch protection on `main`; required reviews
  - [ ] Branch protection on `.github/` directory
  - [ ] Secrets stored in GitHub Secrets or OIDC; never in workflow YAML
  - [ ] Fork PRs do not have secret access (verify in test)
  - [ ] Self-hosted runners are ephemeral
  - [ ] Self-hosted runners have no docker socket
  - [ ] Required status checks include SAST, SCA, secrets, IaC
  - [ ] OIDC for cloud authentication (no static keys)
  - [ ] SLSA L3 provenance generated
  - [ ] Workflows run on a hardened runner (patches within 7 days)
  - [ ] Audit log of workflow runs exported to SIEM
  - [ ] Annual review: which workflows have `admin` or `write` permissions?

## 9. GitLab CI Hardening Checklist

  - [ ] All CI images from a private registry, scanned
  - [ ] CI variables protected; masked in logs
  - [ ] `masked: true` and `protected: true` on all secrets
  - [ ] `pull_from_forks` disabled or limited
  - [ ] Runner tags restrict which jobs run on which runner
  - [ ] Self-hosted runners ephemeral, destroyed on job end
  - [ ] ID tokens for cloud federation (OIDC)
  - [ ] `pipeline_triggers` review for new triggers
  - [ ] Compliance framework labels (SOC2, ISO) applied per pipeline
  - [ ] Audit events exported to SIEM

## 10. Jenkins Hardening Checklist

Jenkins is older and harder to harden; for greenfield, prefer GitHub Actions or GitLab CI. For existing Jenkins:

  - [ ] Jenkins on a hardened base; no internet access from controller
  - [ ] All plugins from the official repo, pinned
  - [ ] Credentials stored in HashiCorp Vault (not Jenkins Credentials)
  - [ ] `Agent → Controller` access disabled
  - [ ] Script approval enabled; no Groovy sandbox bypass
  - [ ] Build agents ephemeral (EC2 / k8s plugin)
  - [ ] CSRF protection enabled
  - [ ] Audit log to SIEM
  - [ ] Annual plugin audit (deprecate unmaintained)

## 12. Self-Check

  1. Audit one workflow file. Are all actions pinned to a SHA? Are permissions minimized? Is `pull_request_target` used safely?
  2. Does your pipeline use static cloud credentials? What's the blast radius if a runner is compromised?
  3. Can you produce SLSA L3 provenance for a build today? If not, what changes?

## 13. The Build Platform Threat Model

A CI/CD platform has its own threat model. The actors:

  - **External attacker** — submits malicious PR
  - **Malicious dependency** — compromised npm/PyPI package
  - **Insider** — engineer with access to the pipeline
  - **Compromised dev machine** — credentials stolen
  - **Cloud compromise** — IAM role used to access pipeline

The threats:

  - **Code execution on runner** — via PR, via dependency, via action
  - **Credential theft** — static keys, OIDC tokens
  - **Artifact tampering** — between build and deploy
  - **Source tampering** — code, lockfile, Dockerfile modified
  - **Registry compromise** — image pushed without going through CI

The controls (covered in this module):

  - **Ephemeral runners** — limit dwell time
  - **Pinned actions** — limit supply-chain attacks
  - **OIDC** — limit credential theft
  - **Signing + admission** — limit artifact tampering
  - **Branch protection** — limit source tampering
  - **Admission control** — limit registry compromise

The defense is layered. No single control is sufficient.

## 14. The Cost of Pipeline Compromise

A pipeline compromise can be devastating:

  - **Source code exfiltration** — IP loss
  - **Customer data access** — if the pipeline has prod credentials
  - **Backdoored releases** — like SolarWinds, customers get malicious code
  - **Cryptominer deployment** — cloud bill spike
  - **Ransomware** — pipeline has access to all systems; encrypt them all
  - **Brand damage** — the breach is public

The 2024 OWASP CI/CD Top 10 enumerates the threats in detail. Treat the pipeline as a Tier 1 asset.

## 15. Pipeline Hardening as Continuous Practice

The pipeline is hardened continuously, not once:

  - **Weekly** — review new action versions; check for advisories
  - **Monthly** — review IAM policies; rotate any static keys
  - **Quarterly** — review the entire `.github/` or `gitlab-ci/` config; prune unused workflows
  - **Annually** — full audit, including access reviews
  - **On incident** — review pipeline integrity as part of the postmortem

The pipeline is a living system. It degrades if not maintained.

## 16. Common Misconfigurations in Popular CI Tools

### GitHub Actions Misconfigurations

  - `pull_request_target` with secret access (M11)
  - Actions pinned to tags, not SHAs (M11)
  - `permissions: write-all` (broadest scope)
  - Long-lived PATs in secrets (use GitHub App or OIDC)
  - Workflows without required reviewers
  - `GITHUB_TOKEN` with broad default permissions

### GitLab CI Misconfigurations

  - CI variables not protected (visible to fork PRs)
  - CI variables not masked (visible in logs)
  - Self-hosted runners with docker socket
  - CI images from public registries (not scanned)
  - No `pipeline_triggers` review
  - `when: always` for security gates

### Jenkins Misconfigurations

  - Agent-to-controller access enabled
  - Groovy script console exposed
  - Plugins from unofficial sources
  - Credentials in plain text (not Vault)
  - No CSRF protection
  - No audit logging

A scan with the relevant linter (e.g., `actionlint` for GitHub Actions, `gitlab-ci-lint`, Jenkins configuration-as-code) catches most of these.

## 17. The CI/CD Security Champion

The person who owns CI/CD security:

  - Maintains the workflow templates
  - Reviews new workflows
  - Is the reviewer for changes to existing workflows
  - Audits IAM policies on the pipeline's cloud roles
  - Runs the pipeline threat model quarterly
  - Owns the SLSA posture

The role is 0.5–1 FTE for a mid-size org. Without it, the pipeline degrades and the gates get bypassed.

## 18. CI/CD Security in the Audit Trail

| Control | Pipeline evidence |
| ------- | ----------------- |
| SOC 2 CC6.1 (logical access) | OIDC trust policies, CloudTrail |
| SOC 2 CC8.1 (change management) | PR history, required reviewers |
| ISO A.8.32 (change management) | Workflow PR history |
| ISO A.8.25 (secure dev) | Pipeline config in git |
| PCI 6.4 (change control) | Pipeline PR history |
| FedRAMP SI-7 (software/firmware integrity) | SLSA provenance, cosign signatures |

The pipeline is the *implementation* of change management. The audit evidence is the PR history, the OIDC trust policy, and the SLSA provenance.

## Related

  - [[DevOps/devsecops/stage0-foundations/03-secure-sdlc|M03: Secure SDLC]]
  - [[DevOps/devsecops/stage2-build/09-container-image-scanning|M09: Container Image Scanning]]
  - [[DevOps/devsecops/stage3-deploy/12-pipeline-identity-oidc|M12: Pipeline Identity & OIDC]]
  - [[DevOps/devsecops/stage3-deploy/13-artifact-signing|M13: Artifact Signing]]
  - [[DevOps/devsecops/stage3-deploy/14-supply-chain-attestations|M14: Supply Chain Attestations]]
  - [[DevOps/devsecops/stage2-build/README|Stage 2 — Build]]

---
title: "M06: Secrets Detection & Prevention"
tags: [devsecops, stage1, code, secrets, gitleaks, trufflehog, vault, prevention]
date: 2026-06-16
description: Module 6 of 20 — preventing secrets from ever reaching the repo, detecting them when they do, and rotating them quickly when prevention fails. The full secrets lifecycle.
---

# M06: Secrets Detection & Prevention

A leaked credential in a public repo is a 4-minute problem. Bots scrape GitHub for AWS keys, GitHub PATs, and Slack tokens within minutes of the commit landing. By the time you see the alert, the secret has been harvested. This module is about *prevention* first, *detection* second, and *rotation* third — in that order, because prevention is the only control that survives the 4-minute window.

## Learning Objectives

By the end of this module you should be able to:

  - Layer secrets controls (pre-commit, pre-merge, runtime) for defense in depth
  - Pick the right tool for each layer (gitleaks, trufflehog, native hooks)
  - Run a secrets rotation drill in under 30 minutes
  - Set up pre-commit hooks that engineers actually use
  - Distinguish *real* secrets from test fixtures and doc strings
  - Build a secret-management reference architecture for app runtime

## 1. The 4-Minute Window

A real-world measurement, not a worst case:

  - GitHub PAT pushed to a public repo: harvested in 4–11 minutes
  - AWS access key in a public repo: AWS sends abuse notice within 12 hours; in practice, usage can begin within 60 seconds
  - Slack token: harvested within 5 minutes; spam pivots within 1 hour

The implication: if you rely on *post-commit* detection, you lose. By the time the scanner runs, the secret is in someone else's hands. You need *pre-commit* prevention.

```
  Commit
    |
    +--<--<--<--<--<-- 4 minutes <--<--<--<--<--+
    |                                            |
    v                                            v
  Prevention layer                          Detection layer
  (pre-commit hooks)                        (repo scanners)
  "Secret never lands"                      "Alert fires; rotate"
  ↓                                         ↓
  succeeds → done                          succeeds → quick rotation
  fails   → detection takes over
```

## 2. The Three Layers

### Layer 1: Pre-Commit (Prevention)

The commit never lands. Engineer fixes locally, re-commits, moves on. Fast feedback, no public exposure.

Tools:
  - **gitleaks** — pattern-based, fast (~3s for a typical repo), customizable rules
  - **trufflehog** — entropy + regex + verified secret check (it actually calls the API to check validity)
  - **detect-secrets** (Yelp) — baseline-aware (whitelists known false positives)
  - **pre-commit framework** — the meta-tool that orchestrates them all

### Layer 2: Pre-Merge (Defense in Depth)

CI scan on every PR. If pre-commit was bypassed (`--no-verify`), this catches it before merge. Catches the case where the secret was added in a code review or pasted into a config file.

Tools: same as layer 1, plus:
  - **GitHub secret scanning** — built-in, partner-pattern-based, alerts you via email
  - **GitLab Secret Detection** — analyzer in the standard pipeline
  - **GitHub Advanced Security** — paid, broader pattern set, partner-notified rotation

### Layer 3: Runtime (Limit Blast Radius)

If a secret *does* land and gets harvested, the damage depends on what the secret can do. Runtime controls cap the blast radius.

  - **Short TTLs** — short-lived credentials (IRSA, WIF, OIDC) expire in 1 hour
  - **Scoped permissions** — secret grants only what is needed, not admin
  - **IP allowlists** — secret can only be used from corporate network
  - **Anomaly detection** — usage spike triggers alarm
  - **MFA-protected admin** — privileged actions require human in the loop

If you only have time for one of the three layers, do layer 1. Layer 1 is the only one that survives the 4-minute window.

## 3. gitleaks Setup

### Pre-Commit Hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

Install once per dev: `pip install pre-commit && pre-commit install`. Every subsequent commit runs the scan automatically.

### Custom Rules

Most teams need a few custom rules on top of the default set. For example, an internal API token format:

```toml
# .gitleaks.toml
[[rules]]
id = "internal-api-token"
description = "Internal service token"
regex = '''int_[a-z0-9]{32}'''
tags = ["internal", "api"]
```

### CI Scan (Defense in Depth)

```yaml
# GitHub Actions
name: gitleaks
on: [pull_request, push]
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## 4. Trufflehog for Verification

Gitleaks finds patterns. Trufflehog verifies them. A "secret" that trufflehog can authenticate with is a *live* secret — treat it as compromised the moment it is found.

```bash
# Scan a repo, verify each finding
trufflehog git https://github.com/your-org/your-repo --only-verified
```

The `--only-verified` flag returns only the findings that are real, live credentials. Run this nightly as a deeper scan; the volume is lower than the unverified scan, and the signal is much higher.

## 5. Native GitHub Secret Scanning

If you are on GitHub Enterprise, enable secret scanning natively. It:

  - Detects 200+ partner patterns (AWS, GCP, Azure, Stripe, Slack, GitHub PATs, etc.)
  - Notifies the partner automatically (e.g., AWS is told you leaked a key)
  - Sends an alert to your security team
  - Pushes to a "secret scanning" tab in the repo

This is free for public repos; paid for private repos under GitHub Advanced Security. The partner-notification is the killer feature — by the time you read the alert, AWS has already revoked the key.

### Pre-Receive Hook Equivalent

For self-hosted GitLab or Gitea, set up a pre-receive server-side hook that runs gitleaks on the push. This is the equivalent of GitHub's pre-merge layer.

## 6. What Is *Not* a Secret

False positives eat trust. The rule set must distinguish real secrets from:

  - **Test fixtures** — `api_key = "test-fixture-not-a-real-key"` should be allowed
  - **Documentation** — example keys in `.md` files; redact with placeholders
  - **Generated files** — proto-generated clients may contain structural strings
  - **Public keys** — these are *meant* to be public; do not flag
  - **Hashed values** — bcrypt/argon2 hashes; safe to commit
  - **Short nonces, IVs, salts** — non-secret by design

The mechanism: path-based and content-based allowlists.

```toml
# .gitleaks.toml
[allowlist]
paths = [
  '''tests/.*\.py$''',
  '''docs/.*\.md$''',
  '''.*/testdata/.*''',
]
regexes = [
  '''test[\-_]?fixture''',
  '''example\.com''',
  '''<your-api-key>''',
  '''AKIA[0-9A-Z]{16}-EXAMPLE''',  # AWS docs example
]
```

## 7. The Rotation Drill

The day you find a leaked secret is not the day you want to discover your rotation runbook is missing. Run a drill every quarter.

### The 30-Minute Drill

```
00:00  Security team simulates finding: "AWS key AKIA... leaked in PR #1234"
00:02  Engineer on-call acknowledges
00:04  Identify the scope of the leaked key
       - What does it grant? (check IAM policy)
       - Where else has it been used? (CloudTrail)
       - Is it in a public repo, private repo, or artifact?
00:10  Revoke the credential at the source
       - AWS: deactivate the IAM access key (do not delete yet)
       - GitHub: revoke PAT via user settings
       - Vault: revoke dynamic secret at the path
00:15  Verify no active sessions remain
       - AWS: list active sessions, force sign-out via IAM
       - GitHub: check audit log
00:20  Issue a replacement credential via Vault / IRSA / WIF
00:25  Update the consuming service
       - Restart the workload to pick up new credential
       - Or, for short-lived: no restart needed
00:30  Verify the service is healthy and the new credential is in use
00:35  Post-mortem: how did the secret land, what control failed, what to fix
```

The drill surfaces friction in your rotation process *before* a real incident. The friction points become the next quarter's security backlog.

## 8. Secret Management Architecture

Secrets at runtime come from one of three places, ranked by safety:

### Tier 1: Native Cloud Workload Identity (Best)

The workload authenticates *as itself* to the cloud API. No static credential to leak.

  - **AWS**: IAM Roles for Service Accounts (IRSA) on EKS, or instance profiles on EC2
  - **GCP**: Workload Identity Federation (WIF)
  - **Azure**: Workload Identity for AKS, or Managed Identity for VMs
  - **OIDC federation**: GitHub Actions → cloud via OIDC (covered in M12)

### Tier 2: Dynamic Secrets from Vault

The workload requests a credential at startup. Vault generates it, leases it, and revokes it. TTL is short (e.g., 1 hour).

  - HashiCorp Vault, Akeyless, cloud KMS-backed solutions
  - Best for non-cloud credentials (database passwords, third-party API keys)
  - Audit log of every access; automatic rotation

### Tier 3: Long-Lived Secrets in Vault (Acceptable for Legacy)

A static credential is stored in Vault, retrieved at startup. Better than env vars in plain text, worse than tiers 1 and 2. Acceptable for legacy systems that cannot use workload identity.

### Tier 4: Environment Variables / Config Files (Avoid)

Secrets in environment variables or config files. They end up in logs, crash reports, and (inevitably) source control. Avoid for any new system.

## 9. Incident Playbook: Found a Leaked Secret

```
1. Confirm the secret is real (trufflehog --only-verified)
2. Check if it is in a public repo
   - If yes: assume compromise at time of commit
   - If no: check if the repo has ever been public
3. Revoke at source (IAM, Vault, partner portal)
4. Audit usage since commit timestamp
   - CloudTrail, GitHub audit log, third-party API logs
5. Notify the secret owner and the data-protection officer
6. File a postmortem within 48 hours
7. Add a custom rule to gitleaks to catch the pattern going forward
8. Update the rotation runbook with whatever you learned
```

## 10. Common Pitfalls

| Pitfall | Consequence | Fix |
| ------- | ----------- | --- |
| Scan only on push | Misses pre-push commits | Pre-commit hook |
| `--no-verify` allowed | Bypasses prevention | Disable in CI; honor but audit |
| No baseline file | First run has 1000 false positives | Create baseline, then enforce |
| Scan only git history | Misses current working tree | Scan staged + unstaged |
| Long-lived static keys | Damage compounds | Move to workload identity |
| Vault without audit | No forensic trail | Always log access |

## 11. Tool Comparison

| Tool        | Speed    | Verification | Custom rules | Best for |
| ----------- | -------- | ------------ | ------------ | -------- |
| gitleaks    | Very fast | No           | Yes (TOML)   | Pre-commit + CI |
| trufflehog  | Slower   | Yes          | Yes          | Nightly deep scan |
| detect-secrets | Fast | No       | Yes          | Large monorepos with baselines |
| GitHub native | Fast   | No (partner notify) | Limited | Public + GHAS repos |
| GitLab Secret Detection | Fast | No | Limited | GitLab-native shops |

Run gitleaks at pre-commit + pre-merge, trufflehog nightly for verification, native platform scanning as a third layer.

## 12. Self-Check

  1. Walk through the 4-minute window. If your detection layer takes 30 minutes to alert, what's your exposure?
  2. Can you run the 30-minute rotation drill today? If not, what's missing?
  3. How many of your services use tier-4 secrets (env vars / config files)? Pick one and migrate it to tier 1 or tier 2 this quarter.

## 13. Secret Detection in Monorepos

Monorepos have a specific challenge: thousands of files, multiple teams, varying sensitivity. Patterns:

### Per-Path Rules

```toml
# .gitleaks.toml
[[rules]]
id = "internal-prod-key"
regex = '''int_prod_[a-z0-9]{32}'''

[allowlist]
paths = [
  '''legacy/.*/test/.*''',     # legacy test files, whitelisted
  '''vendor/.*''',              # vendored code, often contains examples
  '''docs/.*\.md$''',            # documentation
  '''.*/migrations/.*\.sql$''',  # DB migrations may have admin URLs
]
```

The path-based allowlist prevents legacy code from generating noise. New code is still scanned.

### Per-File Extension

Some secrets live in specific file types:

```toml
[[rules]]
id = "private-key-pem"
regex = '''-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY( BLOCK)?-----'''
tags = ["key", "asymmetric"]
```

This catches the actual PEM-format private keys regardless of filename. The format is distinctive enough that FP rate is near zero.

### PR-Diff Only

For very large monorepos, scan only the PR diff:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 50

- uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    GITLEAKS_ARGS: --log-opts="${{ github.event.pull_request.base.sha }..${{ github.event.pull_request.head.sha }}"
```

The PR-diff scan is much faster than a full-repo scan. Use this on the PR gate; run a full-repo scan nightly as defense in depth.

## 14. The 4-Layer Secret Detection Reference Architecture

A reference architecture that gives defense in depth:

```
   Layer 1: IDE plugin (real-time, in editor)
   Layer 2: Pre-commit hook (gitleaks, <3s)
   Layer 3: CI/PR scan (gitleaks or trufflehog, <60s)
   Layer 4: Continuous re-scan (trufflehog --only-verified, nightly)
   Layer 5: Native platform scan (GitHub secret scanning)
   Layer 6: Egress monitoring (alert on secrets in outbound data)
```

A secret that makes it past layer 1 is caught at layer 2 within 3 seconds. Past layer 2, layer 3 catches it within 60 seconds. Past layer 3, layer 4 catches it within 24 hours. Past layer 4, layer 5 catches it (with partner notification). Past layer 5, layer 6 catches it via egress anomaly.

In practice, layers 1–3 are the highest-leverage; layers 4–6 are defense in depth.

## 15. Secret Hygiene Metrics

Track these in your weekly security review:

| Metric | Target | Why |
| ------ | ------ | --- |
| Secrets caught at layer 1 (IDE) | >60% | Best feedback loop |
| Secrets caught at layer 2 (pre-commit) | >30% | Catches the rest before commit |
| Secrets caught at layer 3 (CI) | <5% | The layer-2 / layer-1 rate is the goal |
| Secrets caught at layer 4+ (post-commit) | <1% | Drift, attack patterns |
| Mean time to rotate a leaked secret | <30 min | The incident-response metric |
| Pre-commit hooks enabled (% devs) | >95% | Coverage |

If the layer-1 / layer-2 rate drops, the IDE plugin or pre-commit hook is misconfigured. If the layer-3 rate rises, layer 1 / 2 are missing.

## 16. The Cost of a Leaked Credential

A single leaked credential can cost the org:

  - Direct financial loss (stolen funds, fraudulent cloud usage)
  - Customer notification (if customer data is exposed)
  - Regulatory fines (GDPR, PCI, HIPAA)
  - Brand damage (the public disclosure)
  - Forensic and remediation costs
  - Insurance premium increases

The conservative estimate: $50k for a single leaked test API key, $500k for a leaked prod cloud credential, $5M+ for a leaked customer database key. The cost of the 4-layer detection architecture is <$50k/year to set up and <$10k/year to operate. The math: even one prevented incident pays for the system.

## 17. The Trust Boundary for Secrets

A secret's blast radius is determined by:
  - **What it grants** (read vs. write vs. admin)
  - **Where it can be used** (specific IP, region, account)
  - **How long it lives** (1 hour vs. 1 year)
  - **How it's monitored** (CloudTrail, audit log, no log)

The discipline: design each secret to have the *smallest* blast radius possible. A short-lived, scoped, monitored secret is a small incident. A long-lived, broad, unmonitored secret is a catastrophic incident.

## 18. Common Mistakes (Extended)

| Mistake | Consequence | Fix |
| ------- | ----------- | --- |
| Scan only the latest commit | Misses secrets in history | Scan full history on clone |
| `--no-verify` on a single dev's machine | One bypass, one leak | Disable `--no-verify` in CI; audit if used |
| Allow `git commit --no-verify` in CI | Layer 2 is bypassable | Reject in pre-receive hook |
| Vault token in env var | Same risk as plain-text secret | Use Vault Agent sidecar, never env |
| Audit log retention < 1 year | Cannot investigate old incidents | S3 + Object Lock for 7+ years |
| No tier 4 → tier 1 migration plan | Static secrets persist indefinitely | Migration plan with SLA |

## Related

  - [[DevOps/devsecops/stage0-foundations/01-devsecops-mindset|M01: DevSecOps Mindset]]
  - [[DevOps/devsecops/stage1-code/05-static-analysis-sast|M05: SAST]]
  - [[DevOps/devsecops/stage3-deploy/12-pipeline-identity-oidc|M12: Pipeline Identity & OIDC]]
  - [[DevOps/devsecops/stage3-deploy/16-secret-management|M16: Secret Management]]
  - [[DevOps/devsecops/stage1-code/README|Stage 1 — Code]]

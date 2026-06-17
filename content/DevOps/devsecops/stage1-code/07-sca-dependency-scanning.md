---
title: "M07: Software Composition Analysis (SCA) & Dependency Scanning"
tags: [devsecops, stage1, code, sca, dependencies, trivy, snyk, dependabot, renovate, cve]
date: 2026-06-16
description: "Module 7 of 20 — Software Composition Analysis: how to detect vulnerable dependencies, manage license risk, keep dependencies current, and reduce the supply-chain attack surface."
---

# M07: Software Composition Analysis (SCA) & Dependency Scanning

Modern applications are 70–90% third-party code by line count. A vulnerability in a single transitive dependency can compromise your application without you ever touching the affected code. SCA finds those vulns. This module covers how SCA works, the major tools, the cadence of scanning, how to handle transitive vs. direct dependencies, and the human process of actually fixing findings.

## Learning Objectives

By the end of this module you should be able to:

  - Run SCA on every PR, every nightly build, and every container image
  - Distinguish a direct dependency vuln from a transitive one
  - Set a policy that fails the build on critical CVEs
  - Use Dependabot / Renovate to keep dependencies current with low toil
  - Triage a "vulnerable dependency" alert in under 5 minutes
  - Read a CVE entry and decide on fix-vs-accept

## 1. Why SCA Is the Highest-Volume Scanner

In most modern codebases, dependency CVEs outnumber first-party code vulns 10:1. A single image might pull 500 packages; each package has a vulnerability history tracked in the NVD (National Vulnerability Database). This is why "the scanner says 47 findings" is a SCA finding, not a SAST finding.

Two trends amplify the volume:

  - **Transitive depth** — your app depends on `A`, which depends on `B`, which depends on `C`. A vuln in `C` is your problem even if you've never heard of it.
  - **Frequent disclosures** — new CVEs are published daily. A dep that was clean yesterday has a critical CVE today.

You cannot manually track this. You need automation, and you need it scanning continuously.

## 2. The Tool Landscape

### Trivy

Open-source, single binary, fast, broad coverage. Scans filesystem, container images, IaC, and SBOM. The default recommendation for most teams.

  - Data sources: NVD, GitHub Advisory, OSV, multiple distro DBs
  - Output: text, JSON, SARIF, CycloneDX SBOM
  - Speed: ~10s for a typical filesystem scan
  - Pricing: free (open source), commercial Trivy Enterprise for fleet management

### Snyk

Commercial, deep analysis, integrates with IDE and PR. Strong fix-PR automation.

  - Data sources: Snyk's own vulnerability DB (proprietary, broader than NVD)
  - Output: PR comments, JUnit, SARIF, SBOM
  - Strength: fix-recommendations include the exact version to upgrade to
  - Pricing: free tier for OSS; per-developer for commercial

### Grype + Syft (Anchore)

Grype is the scanner, Syft generates SBOM. Both are open-source, fast, and good for SBOM-centric workflows.

  - Strength: SBOM-first design; integrates with Sigstore
  - Pricing: free

### OWASP Dependency-Check

Java-focused, free, broad. Good for JVM shops.

  - Strength: deep Java ecosystem coverage
  - Weakness: slower than Trivy/Snyk; less broad outside Java

### Dependabot vs. Renovate (Automated Updates)

These are not scanners; they are *fixers*. Both:

  - Watch your dependency manifest (package.json, go.mod, etc.)
  - Open PRs to bump to a non-vulnerable version
  - Run your CI on the PR
  - Merge when CI is green

**Dependabot** (GitHub-native, free for public repos, paid for private): best for GitHub-only shops, opinionated config.
**Renovate** (open-source, self-hostable, broader language support): best for complex monorepos, fine-grained config, multi-platform.

Run one of them, not both. Pick Renovate if you have non-GitHub repos or complex monorepo config; Dependabot otherwise.

## 3. The Scanning Cadence

### Pre-Commit
Skip. SCA is too slow for pre-commit. The pre-commit layer is for secrets (M06) and fast SAST rules.

### PR-Time
Run SCA on the diff. Trivy filesystem scan, fail on high/critical at the configured threshold. Target: <60s for the scan.

### Nightly
Run SCA on the full repo. This catches:

  - New CVEs disclosed since yesterday
  - Transitive deps that the PR scan missed (because the PR didn't add them, but the *lockfile* moved)
  - Base-image updates for container images (covered in M09)

### Per-Image Scan
Run SCA on the final container image. This is where the actual runtime dependency tree is visible. M09 covers this in detail.

### Weekly
Run Renovate/Dependabot. The cadence is higher than nightly because the PR is opened but not merged; you want a steady stream of upgrade PRs, not a flood.

## 4. Direct vs. Transitive

A direct dependency is one your manifest lists explicitly. A transitive dependency is pulled in by a direct one.

```
your-app
  └── lodash@4.17.20       (direct)
       └── glob-parent@5.1.0  (transitive, via lodash)
```

If `glob-parent` has a CVE, you have two options:

  - **Bump the direct dep** — wait for `lodash` to update its `glob-parent` dependency, or bump `lodash` to a version that does
  - **Override** — most package managers (npm, yarn, pip) allow you to force a specific version of a transitive dep via overrides/resolutions

The override path is a quick fix. It is also fragile — the override will be lost the next time you bump `lodash` and the override scope no longer matches. Use overrides for emergency patching; use dep updates for the durable fix.

### How to Find Transitive Deps

```bash
# npm
npm ls <package>

# yarn
yarn why <package>

# pip
pip show <package>
# or for the full tree
pipdeptree

# go
go mod why <module>

# maven
mvn dependency:tree
```

Most SCA tools show the dependency path. Trivy's output includes `pkgPath` showing exactly which chain brings in the vulnerable package.

## 5. The Vulnerability Database

The scanner is only as good as its data source. Three sources matter:

  - **NVD** (National Vulnerability Database) — the canonical US gov source. Lag of days to weeks after disclosure.
  - **GitHub Advisory Database** — community-curated, fast, integrates with Dependabot.
  - **OSV** (Open Source Vulnerabilities) — community aggregator, more sources than NVD.
  - **Vendor-specific** (Ubuntu USN, Debian DSA, Alpine, Amazon Linux ALAS) — for base-image packages.

Trivy aggregates NVD + GH + OSV + vendor sources. Snyk has its own. Pick a tool that aggregates broadly; relying on NVD alone misses vulns.

### CVE Anatomy

```
CVE-2024-12345
├── CVSS v3.1 base score: 9.8 (Critical)
├── Vector: AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H
├── CWE: CWE-502: Deserialization of Untrusted Data
├── Affected: package X, versions < 2.0.0
├── Fixed in: 2.0.1
└── References: GitHub advisory, blog post, PoC
```

You care about: severity, affected version range, fixed version, and whether the vuln is reachable in your code. Reachability is the key word — a vuln in a function you never call is a theoretical risk, not an exploitable one. Reachability analysis is a relatively new SCA feature; Trivy and Snyk both have beta support.

## 6. Triage in 5 Minutes

A SCA finding lands. The clock is ticking. Here's the workflow:

```
00:00  Read the finding
         - Which package? Direct or transitive?
         - What CVE? Severity?
         - Fixed in which version?

00:30  Check reachability
         - Does my code call the vulnerable function?
         - If unsure, assume reachable and treat as exploitable

01:00  Check the fix
         - Patch version available? (X.Y.Z → X.Y.Z+1)
         - Minor bump? (X.Y → X.Y+1)
         - Major bump? (X → X+1) — review changelog

03:00  Apply the fix
         - Update manifest
         - Run tests
         - File PR

05:00  If fix is not feasible (compatibility, license, blocked)
         - File an exception with reason and expiry
         - Add a runtime mitigation if possible (network policy, WAF rule)
         - Track the exception in the risk register
```

The 5-minute target is achievable for routine vulns. Complex ones (major-version bumps with breaking changes) go to the next sprint with a tracking ticket.

## 7. Update Strategy: Stay Current, Stay Sane

The goal is to be within N-1 of the latest minor version, and to pick up security patches within 7 days of disclosure. Three patterns:

### Pattern 1: Auto-Merge for Patch Updates

Configure Renovate/Dependabot to auto-merge patch updates (X.Y.Z → X.Y.Z+1) when CI passes. The risk is low; the toil reduction is high.

```json5
// renovate.json
{
  "packageRules": [
    {
      "matchUpdateTypes": ["patch"],
      "automerge": true
    },
    {
      "matchUpdateTypes": ["minor"],
      "automerge": false,
      "labels": ["dependencies"]
    },
    {
      "matchUpdateTypes": ["major"],
      "automerge": false,
      "reviewers": ["team-lead"]
    }
  ]
}
```

### Pattern 2: Grouped Minor Updates

A single PR that bumps 30 minor versions of related deps is easier to review than 30 individual PRs. Use grouping.

```json5
{
  "packageRules": [
    {
      "groupName": "AWS SDK minor",
      "matchPackagePrefixes": ["@aws-sdk/"],
      "schedule": ["before 6am on monday"]
    }
  ]
}
```

### Pattern 3: Lockfile Pinning

For reproducibility, use a lockfile (package-lock.json, go.sum, Pipfile.lock). The lockfile pins exact versions; SCA scans the lockfile, not the manifest.

The discipline: commit the lockfile. Review lockfile changes in PRs. The lockfile is the source of truth for what runs in production.

## 8. License Risk

SCA tools also detect license issues. Most teams use a permissive allowlist (MIT, Apache-2.0, BSD-2/3) and a copyleft review (GPL, AGPL) that requires legal sign-off.

```
allowed:
  - MIT
  - Apache-2.0
  - BSD-2-Clause
  - BSD-3-Clause
  - ISC
  - MPL-2.0

review-required:
  - LGPL-2.1    (dynamic linking OK; static linking requires review)
  - GPL-2.0
  - GPL-3.0
  - AGPL-3.0    (network copyleft; SaaS risk)

banned:
  - SSPL       (mongo-style; commercial use restrictions)
  - BUSL       (Business Source License; check terms)
  - Unlicensed
```

Trivy has license detection built in. Configure it to fail the build on banned licenses.

## 9. Supply-Chain Attacks Beyond CVEs

SCA catches *known* vulns. It does not catch a malicious package uploaded to npm yesterday. For that, you need:

  - **Signature verification** — pin packages to a known author; reject unsigned or unexpectedly-republished packages (M13)
  - **Hash pinning** — `package-lock.json` includes integrity hashes; npm rejects mismatches
  - **Private registries / proxies** — npm with `--registry` set to a vetted internal proxy that blocks typosquats (e.g., `cross-env` vs `crossenv`)
  - **Provenance** — npm and PyPI now support signed provenance (Sigstore); require it for high-risk deps

This is supply-chain attack defense, covered in M14.

## 10. CI Integration

### Trivy on PR

```yaml
name: trivy-sca
on: [pull_request]
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Trivy filesystem scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: fs
          scan-ref: .
          severity: HIGH,CRITICAL
          exit-code: 1
          format: sarif
          output: trivy-fs.sarif
      - name: Upload to GitHub Security tab
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-fs.sarif
```

### Dependabot Config

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    labels: ["dependencies", "security"]
    groups:
      aws-sdk:
        patterns: ["@aws-sdk/*"]
```

## 11. SCA Metrics

| Metric | Target | Why |
| ------ | ------ | --- |
| Mean time to remediate critical CVE | <7 days | Exploit window |
| Direct deps with known-vuln version pinned | 0 | Avoid lazy upgrade |
| % of services with Renovate/Dependabot enabled | 100% | Coverage |
| Transitive vulns overridden without tracking | 0 | Audit gap |
| License-policy violations | 0 | Legal risk |

## 12. Self-Check

  1. Pick a CVE that hit your stack in the last 6 months. Walk through the 5-minute triage. Could you have detected it earlier?
  2. Count your direct dependencies. Count your transitive ones. If the ratio is <1:5, you have a shallow dep tree (rare); if >1:20, you may have a dep-hygiene problem.
  3. Are Renovate/Dependabot PRs being merged within 14 days? If not, why?

## 13. SCA Across the SDLC

SCA appears at every phase, not just one:

| Phase | SCA activity | Why |
| ----- | ------------ | --- |
| Plan | Document which licenses the project depends on | License compliance is a planning concern |
| Design | Pick libraries based on maintenance + vuln history | Avoid known-bad libraries |
| Code | Pre-commit: lightweight SCA on the manifest | Catch the new dep before commit |
| Build | Full SCA on the lockfile | The canonical scan |
| Test | SCA on the container image (M09) | What actually runs |
| Deploy | Re-scan the SBOM (M08) | Catch vulns disclosed after build |
| Operate | Continuous re-scan (Trivy Operator) | Daily vuln-DB updates |

The pre-commit scan catches the *new* dep. The build scan catches the *full* set. The deploy and operate scans catch *new* vulns in *known* deps. Together, they cover the dep vuln space.

## 14. Reachability Analysis

A traditional SCA reports "package X has CVE-2024-XXXX." A reachability-aware scanner reports "package X has CVE-2024-XXXX, AND your code calls the vulnerable function Y, AND there is a path from user input to that function." The latter is the only one that matters operationally.

### Reachability Tools

  - **Snyk Code / Snyk Open Source** — proprietary reachability for many languages
  - **GitHub CodeQL + Dependabot** — free for public repos
  - **Endor Labs** — reachability + dependency graph
  - **Xcally** — open source reachability
  - **Codenotary** — attestation-based

Reachability analysis is the next frontier in SCA. For most orgs, the cost is high (license, integration) but the value is real: you stop chasing false positives.

### Practical Pattern

```
  Trivy (broad, fast) →  Reachability scanner (deep, slow)
        |                          |
        +----------+---------------+
                   |
                   v
             Triage queue
                   |
        +----------+----------+
        |                     |
        v                     v
  Reachability-confirmed    Reachability-unconfirmed
        |                     |
        v                     v
   Fix in 7 days            Mark as accepted risk;
                            review monthly
```

## 15. SCA and the 5-Minute Triage (Extended)

A 5-minute triage assumes a *real* finding. In practice, ~70% of SCA findings are reachability-unconfirmed and may not apply. The right pattern:

  - **Step 0** — Reachability check first
  - **Step 1** — Skip unreachable findings (with documentation)
  - **Step 2** — Triage reachable findings in 5 minutes
  - **Step 3** — Suppress the unreachable ones (not the reachable ones)

The unreachable findings are the *noise*. The reachable findings are the *signal*. Spending 5 minutes per noise is a waste; the reachability check is the filter.

## 16. Dependabot and Renovate Compared (Detail)

| Feature | Dependabot | Renovate |
| ------- | ---------- | -------- |
| Hosted for free | Yes (public) | Yes (public) |
| Private repos | Paid (GHAS) | Free (self-host) or paid (cloud) |
| Multi-platform | GitHub only | GitHub, GitLab, Bitbucket, Gitea, Azure DevOps |
| Grouping | Limited | Powerful regex / package matching |
| Schedule | Weekly (default) | Configurable, can be daily |
| Auto-merge | Limited | Configurable per package / update type |
| Lock file maintenance | Yes | Yes (more languages) |
| Custom registries | Limited | Extensive |
| Vulnerability alerts | Yes (Dependabot security updates) | Yes |
| Docker image updates | Yes | Yes |
| GitHub Actions updates | Yes | Yes |
| Self-hosted | No | Yes |

For a single-platform team on GitHub, Dependabot is the simpler choice. For multi-platform, monorepo, or custom-registry use, Renovate is the better tool.

## 17. SCA and the "Critical CVE of the Week"

Some CVEs are so severe they require emergency response. Examples:
  - Log4Shell (CVE-2021-44228) — RCE in log4j, exploited in the wild within hours
  - Spring4Shell (CVE-2022-22965) — RCE in Spring
  - Heartbleed (CVE-2014-0160) — information disclosure in OpenSSL
  - Shellshock (CVE-2014-6271) — RCE in bash
  - EternalBlue (MS17-010) — SMB RCE

The pattern when a critical CVE drops:
  1. SCA scanner flags the package
  2. Reachability check confirms exploitability
  3. SBOM re-scan (M08) confirms affected artifacts
  4. Emergency PR opened with the patch
  5. Dependabot/Renovate may also auto-PR (if it knows the patch)
  6. PR is auto-merged if tests pass (or fast-tracked)
  7. Deploy is expedited
  8. Postmortem: how long did it take us to detect? to patch? to deploy?

The "critical CVE of the week" is the *test* of your SCA + SBOM + Dependabot pipeline. If you cannot answer in 5 minutes, the pipeline has gaps.

## 18. SCA in the Audit Trail

SCA produces the evidence for several compliance controls:

| Control | SCA evidence |
| ------- | ------------ |
| SOC 2 CC7.1 (vuln detection) | SCA scan reports |
| SOC 2 CC7.4 (incident response) | CVE-to-fix timeline |
| ISO A.8.8 (vuln management) | SCA policy + SLAs |
| PCI 6.3.3 (vendor patches) | Dependabot/Renovate PR history |
| PCI 11.3 (pen test) | SCA pre/post report |
| FedRAMP SI-2 (flaw remediation) | SCA reports + fix timeline |

The audit asks: "How do you know what you depend on?" The answer is the SBOM (M08). "How do you know which deps are vulnerable?" The answer is the SCA report. "How fast do you fix?" The answer is the SLA tracker.

## Related

  - [[DevOps/devsecops/stage0-foundations/01-devsecops-mindset|M01: DevSecOps Mindset]]
  - [[DevOps/devsecops/stage1-code/05-static-analysis-sast|M05: SAST]]
  - [[DevOps/devsecops/stage1-code/06-secrets-detection|M06: Secrets Detection]]
  - [[DevOps/devsecops/stage1-code/08-sbom-generation|M08: SBOM Generation]]
  - [[DevOps/devsecops/stage2-build/09-container-image-scanning|M09: Container Image Scanning]]
  - [[DevOps/devsecops/stage1-code/README|Stage 1 — Code]]

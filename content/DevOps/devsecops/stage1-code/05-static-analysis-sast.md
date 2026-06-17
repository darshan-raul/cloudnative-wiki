---
title: "M05: Static Application Security Testing (SAST)"
tags: [devsecops, stage1, code, sast, semgrep, sonarqube, codeql]
date: 2026-06-16
description: "Module 5 of 20 — Static Application Security Testing in the developer workflow. Semgrep, CodeQL, SonarQube, language-specific scanners, false-positive tuning, and CI integration patterns."
---

# M05: Static Application Security Testing (SAST)

SAST scans source code for vulnerability patterns without executing the program. It is the first scanner that touches your code, the one that catches issues before the build even starts. This module covers what SAST actually detects, the major tools, how to integrate them into the developer loop without breaking flow, and — most importantly — how to tune the rule set so the team trusts the output.

## Learning Objectives

By the end of this module you should be able to:

  - Explain what SAST detects and what it cannot
  - Pick a SAST tool for a given language and team size
  - Integrate SAST into pre-commit, PR, and nightly cadences
  - Tune a SAST rule set to <10% false-positive rate
  - Read a SAST finding and decide on fix-vs-suppress in under 5 minutes
  - Build a developer-experience loop that surfaces findings in the IDE

## 1. What SAST Actually Does

SAST tools parse source code into an abstract syntax tree (AST) or intermediate representation, then run pattern matchers and dataflow analyses against that representation.

Two classes of detection:

### Pattern Matchers
Look for syntactic patterns that match known bug classes. Fast, low false-positive rate, but miss variants.

  - `eval(userInput)` → command injection
  - `innerHTML = userInput` → XSS
  - `md5(password)` → weak crypto
  - `subprocess.run(shell=True, ...)` → shell injection

### Dataflow Analyzers
Trace values from source to sink. Slower, more false positives, but catch the variants.

  - User input → string concat → SQL query → sink (SQLi)
  - File path → open() → sink (path traversal)
  - Crypto key → reuse across requests → sink (key reuse bug)

Most modern tools (Semgrep, CodeQL) combine both.

### What SAST Does Not Do

  - Does not see runtime-only behavior (reflection, dynamic dispatch, framework magic)
  - Does not understand business logic ("can user A read user B's data" — that's authz, covered in M15)
  - Does not detect dependency vulns — that's SCA, M07
  - Does not detect secrets in code — that's M06
  - Does not test the running app — that's DAST, beyond stage 1

If you find a tool that claims to do all five, it does none of them well.

## 2. The Tool Landscape

### Semgrep

Open-source, polyglot, rule-as-code (YAML). Fast (sub-second per file on small repos). Easy to write custom rules. The default recommendation for most teams.

  - Languages: 30+ (Python, Go, JS/TS, Java, Ruby, C#, PHP, Kotlin, Swift, Rust, etc.)
  - Engine: open-source `semgrep` CLI + commercial `semgrep app` for managed scans
  - Strength: rule writing is trivial; community ruleset (`p/default`, `p/security-audit`, `p/owasp-top-ten`)
  - Pricing: open-source free; commercial per-developer

### CodeQL

GitHub-owned, free for public repos, paid for private (GitHub Advanced Security). Best-in-class for deep dataflow. Steeper learning curve for custom queries.

  - Languages: Go, JS/TS, Java, C/C++, C#, Python, Ruby, Kotlin, Swift
  - Engine: semantic analysis of full compiled program
  - Strength: catches variants pattern matchers miss; query language is a real DSL
  - Pricing: free for public OSS; paid for private

### SonarQube / SonarCloud

Long-established, opinionated dashboard, "quality gates" as a first-class concept. Good for organizations that want a single pane of glass.

  - Languages: 25+
  - Engine: AST + dataflow + custom rules
  - Strength: integration with IDE, PR decoration, quality gate enforcement
  - Pricing: Community (free, self-hosted), Developer ($), Enterprise ($$$)

### Language-Specific Tools

Worth running alongside the general-purpose tool:

| Language | Tool         | Detects                          |
| -------- | ------------ | -------------------------------- |
| Python   | Bandit       | Hardcoded passwords, weak crypto, exec |
| Go       | Gosec        | SQLi, weak rand, command injection |
| Java     | SpotBugs + find-sec-bugs | Injection, crypto, deserialization |
| JS/TS    | ESLint security plugins    | XSS, prototype pollution, unsafe-regex |
| Rust     | cargo-audit  | Known CVEs in crates             |
| Terraform | tfsec / Checkov | Misconfigurations, public S3  |

Run one general-purpose tool + one language-specific tool. Do not stack four; the noise compounds.

## 3. Where SAST Fits in the Pipeline

```
       IDE              Pre-commit           PR CI             Nightly
       |                    |                  |                  |
       v                    v                  v                  v
   [linter]            [gitleaks]          [semgrep]          [codeql]
   [IDE plugin]        [secrets]           [sca]              [deep scan]
   (instant)           (~3s)               (~60s)             (~30min)
```

### IDE Feedback Loop

The fastest feedback is the one inside the editor. Both Semgrep and Sonar offer IDE plugins (VSCode, JetBrains, Vim via LSP) that show the finding as a squiggle in the source.

This is the single highest-impact change. A finding in the editor is fixed in seconds; a finding in a CI report is fixed in days (or never).

### Pre-Commit Gate

Run a *small* rule set on pre-commit. The rule set is intentionally narrow: only the highest-confidence, fastest checks.

  - Semgrep `--config p/security-audit --severity ERROR --error`
  - Bandit for Python: `-lll` (low/medium/high all reported as error)
  - Gosec for Go: `-severity=high -confidence=high`

Fail the commit. Do not allow `--no-verify` except for emergencies (and audit those).

### PR Gate

Run the *full* rule set. This is the canonical scan that gates the merge.

  - Semgrep with `--config p/default p/security-audit p/owasp-top-ten`
  - All findings reported; high/critical fail the check
  - PR comment posted automatically with the finding, location, suggested fix
  - Suppression via `# nosemgrep: <rule-id> -- <reason>` with required comment

### Nightly Deep Scan

CodeQL on a full repository scan. Catches interprocedural issues the PR-time scan misses because the PR is one diff, not the whole codebase.

  - Schedule: 02:00 UTC, single-threaded, full repo
  - Output: SARIF file, uploaded to GitHub code scanning
  - New findings page on-call; existing findings auto-tracked

## 4. False Positive Tuning

SAST rule sets come with thousands of rules out of the box. Most are not relevant to your codebase. The first 90 days are a tuning exercise.

### Triage Workflow

```
  Day 1: run full scan; expect 200–2000 findings
  Day 7:  classify each finding as:
          - True positive → file fix
          - True positive, accepted risk → suppress with justification
          - False positive → suppress with justification
          - Wrong language/style rule → disable the rule
  Day 30: <10% of original findings remain; PR-time scan is trustworthy
  Day 90: <5%; nightly scan reports are read in 10 minutes
```

### Suppression Discipline

  - Suppress in source with a comment + reason + ticket ID
  - Suppress at the tool level only for whole-rule disables
  - Re-review suppressions every 6 months
  - Track suppression count as a metric; rising suppression = a tuning problem

### Common Sources of False Positives

  - Framework-provided escaping that the tool does not understand
  - Test files that intentionally contain malicious-looking strings
  - Generated code (proto, OpenAPI clients)
  - Dead code paths that the tool flags

For each, there is a clean fix:
  - Add framework-specific rules to the tool's config
  - Exclude test directories: `exclude: ['**/test/**', '**/tests/**']`
  - Exclude generated: `exclude: ['**/gen/**', '**/proto/**']`
  - Delete the dead code, then re-scan

## 5. Reading a SAST Finding

A typical Semgrep finding:

```
src/api/users.py:42
  rule: python.lang.security.audit.django.security.audit.xss.django-response-no-xss
  message: "Detected a Django response that could contain unescaped user input"
  severity: WARNING
  confidence: MEDIUM
  fix: Use `mark_safe()` only on sanitized data, or use `escape()` on user input
  cwe: CWE-79: Cross-site Scripting
  owasp: A03:2021 Injection
```

What to do in 5 minutes:

  1. Open the file at the line. Is the data path actually user-controllable?
  2. If yes, fix per the tool's suggestion. Add a unit test that catches the regression.
  3. If no, suppress with reason. Re-run the scan. Verify it is gone.
  4. File a follow-up if the same rule fires 5+ times — the rule may need to be customized for your framework.

## 6. Custom Rules

The killer feature of Semgrep and CodeQL is custom rules for your codebase's specific patterns. Two cases drive custom rules:

  - **Banned pattern** — your team has decided against a particular library or approach. Write a rule that fires when it is used.
  - **Domain-specific sink** — your codebase has a custom function that calls into a dangerous primitive. Write a rule that flags untrusted input reaching it.

### Example: Ban `pickle.loads` on External Data

```yaml
rules:
  - id: no-pickle-loads
    patterns:
      - pattern-either:
          - pattern: pickle.loads(...)
          - pattern: cPickle.loads(...)
    message: "pickle.loads is unsafe on untrusted data; use json or protobuf"
    severity: ERROR
    languages: [python]
```

A 5-line rule, deployed via `semgrep ci`, blocks a class of deserialization RCEs across the entire codebase.

## 7. CI Integration Patterns

### GitHub Actions (Semgrep)

```yaml
name: semgrep
on: [pull_request]

jobs:
  semgrep:
    runs-on: ubuntu-latest
    container:
      image: returntocorp/semgrep
    steps:
      - uses: actions/checkout@v4
      - run: semgrep ci --config p/default --config p/security-audit --error
```

### GitLab CI

```yaml
semgrep:
  image: returntocorp/semgrep:latest
  script:
    - semgrep ci --config p/default --config p/security-audit --error
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

### Jenkins

```groovy
stage('SAST') {
  agent { docker { image 'returntocorp/semgrep' } }
  steps {
    sh 'semgrep ci --config p/default --config p/security-audit --error'
  }
}
```

All three return non-zero on findings at the configured severity. The merge is blocked. The PR comment is posted.

## 8. SAST Metrics

Track these in a weekly security review:

| Metric | Target | Why it matters |
| ------ | ------ | -------------- |
| Mean time to fix (MTTF) for new findings | <7 days for high/critical | Flow health |
| Findings per 1k LoC | <0.5 high/critical | Code health |
| Suppression ratio (suppressed / total) | <30% | Rule-set health |
| PRs with new findings | <20% of PRs | Developer adoption |
| IDE plugin installs | >80% of engineers | Feedback loop |
| Nightly scan time | <60 min | Cost of deep scan |

If MTTF drifts up, the rule set is probably mis-tuned. If suppression ratio drifts up, the rule set is probably too broad. The two metrics together tell you whether to add rules or remove them.

## 9. SAST Anti-Patterns

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| Run on master only | Findings arrive after merge | Run on every PR; gate the merge |
| Treat all findings equal | High noise, devs ignore | Severity tiers, fail only on high/critical |
| No IDE plugin | Findings felt as "not my problem" | Mandate plugin install via MDM |
| "We have SAST" with no suppression policy | 4000-finding backlog | Triage sprint, fix or suppress each |
| Disable noisy rules globally | Critical findings pass through | Suppress per-finding, not per-rule |
| Run every 4 hours | Misses PR-time feedback | PR-time fast scan + nightly deep scan |

## 10. SAST and the Wider Pipeline

SAST catches one class of issue. The pipeline needs the other classes too:

  - **Secrets in code** — M06
  - **Vulnerable dependencies** — M07 (SCA)
  - **Insecure build artifacts** — M08/M09
  - **Insecure infrastructure** — M10
  - **Misconfigured deploys** — M15

SAST is the first line, not the only line.

## 11. Self-Check

  1. Pick a recent vulnerability from your bug tracker. Would SAST have caught it pre-commit? If not, write a custom rule that would.
  2. What's your current SAST rule set? Count active rules vs. firing rules. If the ratio is <50%, you have a tuning problem.
  3. Do your developers have the IDE plugin installed? If you don't know, that's the answer.

## 12. SAST for AI-Generated Code

A specific 2024–2026 reality: a growing share of code is written by AI assistants. SAST's role changes:

### What AI Code Gets Wrong

Empirically, AI-generated code is more likely to contain:
  - String-concatenated SQL queries
  - `eval`-style dynamic execution
  - Insecure deserialization (pickle, eval, YAML load)
  - Hardcoded placeholder credentials that survive to prod
  - Disabling of safety features in the interest of "making it work"

### How SAST Catches It

The patterns are *the same* patterns SAST has always caught. The frequency is higher. The implication: SAST must run on every PR, with the IDE plugin enabled, so the AI's output is checked as it is generated, not after.

### The IDE-Plugin-Plus-PR-Gate Pattern

```
  Developer + AI
       |
       v
  IDE plugin (instant feedback)
       |  "Your code has a SQL injection risk"
       v
  Developer edits prompt, regenerates
       |
       v
  PR opened
       |
       v
  CI SAST (final check)
       |
       v
  Pass / fail
```

The IDE plugin is the *first* gate. The CI SAST is the *last*. Both are needed because the AI sometimes generates code that looks fine in the editor but fails the CI scan (e.g., dep is fine in isolation but conflicts with the rest of the codebase).

## 13. SAST for Polyglot Repos

Most modern repos are polyglot. A few patterns for scanning them:

### Pattern 1: Run Per-Language Scanners

```yaml
jobs:
  sast-python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install bandit
      - run: bandit -r ./python -f sarif -o bandit.sarif

  sast-go:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: go install github.com/securego/gosec/v2/cmd/gosec@latest
      - run: gosec -fmt sarif -out gosec.sarif ./...

  sast-js:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npx --yes semgrep ci --config p/owasp-top-ten --config p/javascript --config p/typescript
```

### Pattern 2: Semgrep for Everything

Semgrep's strength is polyglot: one tool, multiple languages. For teams that do not want to maintain N scanner configs, Semgrep is the default.

```yaml
- run: semgrep ci --config p/default --config p/security-audit --config p/owasp-top-ten
```

This catches most patterns across most languages. Add a language-specific tool only for high-value gaps.

## 14. SAST and the False-Positive Budget

Every SAST rule has a false-positive cost. The discipline:

  - **Each rule has a target FP rate** (e.g., <5% per week)
  - **Tune or disable rules above the target**
  - **Track the FP rate over time**
  - **Investigate spikes** (a rule that goes from 5% to 30% FP needs a code change or a configuration change)

```yaml
# .semgrep.yml
rules:
  - id: my-rule
    pattern: ...
    message: ...
    severity: WARNING
    metadata:
      fpa_target: 0.05
      owner: "@security-team"
```

A rule with no owner is a rule that gets ignored. A rule with an owner is a rule that gets tuned.

## 15. SAST and the Audit Trail

Every SAST finding produces an audit record:
  - The rule that fired
  - The file and line
  - The CWE / OWASP category
  - The severity
  - The fix status (fixed, suppressed, accepted)

For SOC 2 / ISO 27001 audits (M18), the SAST report is the evidence for "vulnerability detection" (CC7.1) and "secure coding" (A.8.28).

## 16. SAST vs. SCA vs. Secrets: A Decision Tree

When given a vulnerability, which tool should catch it?

```
  Is the issue in code we wrote?
    YES → SAST (M05)
    NO  → Is the issue in a third-party package?
            YES → SCA (M07)
            NO  → Is the issue a leaked credential?
                    YES → Secrets (M06)
                    NO  → Is the issue in the build/deploy config?
                            YES → IaC (M10)
                            NO  → Is the issue at runtime?
                                    YES → Runtime detection (M17)
                                    NO  → Re-check; the issue is somewhere else
```

A clean classification tells you which control failed and which fix to apply.

## 17. SAST Vendors and Migration

The major vendors and their strengths:

| Vendor | Strength | Best for |
| ------ | -------- | -------- |
| Semgrep | Open, fast, polyglot, custom rules | Default for most teams |
| CodeQL | Deep dataflow, GitHub-native | Deep analysis on GitHub |
| SonarQube | Single pane, quality gates | Enterprises with one platform |
| Snyk Code | Fix-recommendations, IDE | Snyk shops |
| Checkmarx | Enterprise, OWASP-top-10 focus | Large regulated orgs |
| Veracode | SaaS, language breadth | Enterprise, multi-language |

Migration between tools is mostly mechanical:
  - Map rules (most vendors publish their rule → CWE mappings)
  - Run new and old in parallel for 1–2 weeks
  - Compare findings
  - Cut over when the new tool is tuned

## Related

  - [[DevOps/devsecops/stage0-foundations/01-devsecops-mindset|M01: DevSecOps Mindset]]
  - [[DevOps/devsecops/stage1-code/06-secrets-detection|M06: Secrets Detection]]
  - [[DevOps/devsecops/stage1-code/07-sca-dependency-scanning|M07: SCA & Dependency Scanning]]
  - [[DevOps/devsecops/stage1-code/08-sbom-generation|M08: SBOM Generation]]
  - [[DevOps/devsecops/stage1-code/README|Stage 1 — Code]]

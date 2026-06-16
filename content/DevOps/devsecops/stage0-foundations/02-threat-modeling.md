---
title: "M02: Threat Modeling for DevSecOps"
tags: [devsecops, stage0, foundations, threat-modeling, stride, attack-trees]
date: 2026-06-16
description: Module 2 of 20 — practical threat modeling for engineers, not auditors. STRIDE, attack trees, abuse cases, and the "4-question frame" you can run in a 30-minute design session.
---

# M02: Threat Modeling for DevSecOps

Most teams skip threat modeling because the formal versions (PASTA, VAST, full STRIDE workshops) take 2–5 days and produce a 40-page document nobody reads. This module teaches the lightweight version: enough rigor to find the real risks in a 30-minute session, integrated into story design rather than parked in a separate phase.

## Learning Objectives

By the end of this module you should be able to:

  - Run a 4-question threat-model in 30 minutes during story grooming
  - Apply STRIDE to a single data flow in under 10 minutes
  - Build an attack tree for a concrete trust boundary
  - Distinguish a threat, a vulnerability, and a control
  - Score findings with a simple, repeatable risk rubric

## 1. Vocabulary First

Three terms that get conflated. Get them right once and the rest of the module is easier.

  - **Asset** — something with value (data, credential, service, reputation)
  - **Threat** — something bad that *could* happen to an asset (an adversary with capability and intent)
  - **Vulnerability** — a weakness that a threat can exploit (a bug, a misconfig, a missing control)
  - **Risk** — likelihood × impact of a threat exploiting a vulnerability
  - **Control** — a safeguard that reduces risk (preventive, detective, or corrective)

A *threat* is not a *vulnerability*. "SQL injection" is a vulnerability. "An attacker who wants your user database" is a threat. "SQL injection + an attacker + an exposed login form" is a risk. The control is parameterized queries + WAF + rate limiting.

## 2. The 4-Question Frame

For every new feature that touches authentication, authorization, data storage, or external input, ask these four questions in order. If you cannot answer all four in a paragraph, the story is not ready.

```
Q1. What are we building?
    → one sentence; the data flow, not the tech stack

Q2. What can go wrong?
    → list 3–5 specific abuse cases, not "security issues"

Q3. What are we doing about each one?
    → one control per abuse case, named and testable

Q4. Did we check the controls work?
    → test, scan, or review that proves the control is in place
```

### Worked Example: Adding a Password Reset Endpoint

**Q1. What are we building?**
> An unauthenticated POST /reset that takes an email and sends a reset link if the user exists. The link is single-use, 15-minute TTL, and grants a session identical to a normal login.

**Q2. What can go wrong?**
  1. User enumeration — different response time or body for valid vs invalid email
  2. Email flooding — attacker triggers resets for arbitrary addresses
  3. Token predictability — guessable reset tokens
  4. Token leakage via referer — link clicks through to a malicious site that reads the URL
  5. Rate-limit bypass — distributed reset spam

**Q3. What are we doing about each?**
  1. Identical response body and timing for valid/invalid email; log internally for abuse signal
  2. Per-account and per-IP rate limit (e.g., 5/hr); CAPTCHA after threshold
  3. 256-bit random token, hashed at rest, single-use
  4. Token is a path parameter, not a query string; CSP `referrer-policy: no-referrer`
  5. Rate limit at edge (CDN/WAF) in addition to app-level

**Q4. Did we check the controls work?**
  - Unit test asserts response body is byte-identical for valid/invalid email
  - Integration test asserts 6th request from same IP returns 429
  - Load test asserts tokens are not in any known PRNG sequence
  - Manual test: click link in a sandboxed browser with a hostile referer site open; verify no leak

Total time: 25 minutes including the test design. This is the rhythm.

## 3. STRIDE in 10 Minutes

STRIDE is Microsoft's threat-classification taxonomy. It is not a process; it is a checklist. Run it against each data flow.

| Letter  | Threat                  | Question to ask                                    | Common control                     |
| ------- | ----------------------- | -------------------------------------------------- | ---------------------------------- |
| **S**   | Spoofing                | Can I prove this caller is who they say?            | mTLS, signed JWT, OIDC, MFA        |
| **T**   | Tampering               | Can someone modify this in transit or at rest?     | TLS 1.3, signed artifacts, RBAC    |
| **R**   | Repudiation             | Can the actor deny they did this?                  | Audit logs, signed actions         |
| **I**   | Information disclosure  | Can someone read this who shouldn't?               | Encryption at rest + in transit, masking |
| **D**   | Denial of service       | Can someone exhaust capacity or starve legit users? | Rate limits, autoscaling, circuit breakers |
| **E**   | Elevation of privilege  | Can a low-priv actor become high-priv?             | Least privilege, separation of duties, MFA |

You do not need all six for every flow. Skip categories that genuinely do not apply (e.g., for a read-only public docs page, tampering and elevation of privilege may be N/A). The discipline is in the check, not the ceremony.

## 4. Data Flow Diagrams (DFD)

The single most useful artifact in threat modeling. Draw it once, run STRIDE against it, file the findings. Five elements:

```
  +-------+        +-----------+        +---------+
  |       |  --1-> |           |  --2-> |         |
  | User  |        |  Process  |        |  Store  |
  | (ext) |  <-4-- |   (P)     |  <-3-- |   (D)   |
  +-------+        +-----------+        +---------+
       |                |                     |
       +------ trust boundaries -------------+
```

  - **Process (P)** — code that handles data
  - **Data store (D)** — database, queue, file, cache
  - **External entity (E)** — user, third-party service
  - **Data flow** — arrow with a number, labeled with the data
  - **Trust boundary** — dashed line crossing which data must be authenticated/authorized/validated

The trust boundary is the most important part. Every crossing is a candidate finding.

### Minimal DFD for a Login Flow

```
   [User]                  [Auth Service]                [User DB]
      |                          |                            |
      |---(1) email+password--->|                            |
      |                          |---(2) lookup user--------->|
      |                          |<--(3) user record---------|
      |                          |---(4) write session---------->|
      |<--(5) session cookie-----|                            |
      |                          |                            |
      +----- trust boundary ----------------------------------+
```

Run STRIDE per arrow:
  - (1) Spoofing: TLS; Tampering: TLS + signature
  - (2) Information disclosure: TLS; Tampering: TLS + DB auth
  - (3) Repudiation: log the lookup with user/IP
  - (4) Tampering: write to encrypted session store; Repudiation: signed audit
  - (5) Information disclosure: Secure+HttpOnly cookie; Spoofing: bind cookie to user-agent fingerprint

## 5. Attack Trees

Where STRIDE classifies threats, attack trees decompose a single goal into steps. Top-down: the root is the attacker's goal. Each child is a subgoal. Each leaf is a concrete technique.

### Example Tree: "Steal User Session Token"

```
Goal: steal a valid session token
|
+-- 1. Steal from client
|   |
|   +-- 1.1 XSS exfil                     (mitigated by CSP + HttpOnly)
|   +-- 1.2 Network sniff                 (mitigated by TLS 1.3)
|   +-- 1.3 Browser-extension exfil       (mitigated by trusted-extension policy)
|   +-- 1.4 Malware on client             (out of scope for server controls)
|
+-- 2. Steal from server
|   |
|   +-- 2.1 SQLi session store            (mitigated by parameterization)
|   +-- 2.2 SSRF into metadata            (mitigated by IMDSv2 + network policy)
|   +-- 2.3 Backup theft                  (mitigated by encryption + access log)
|   +-- 2.4 Insider read                  (mitigated by RBAC + audit)
|
+-- 3. Forge a token
|   |
|   +-- 3.1 Weak signing key              (mitigated by HSM/KMS)
|   +-- 3.2 Algorithm confusion (alg=none) (mitigated by explicit alg allowlist)
|   +-- 3.3 Long-lived stolen token       (mitigated by short TTL + refresh)
|
+-- 4. Trick the user
    |
    +-- 4.1 Phish credentials             (mitigated by MFA)
    +-- 4.2 OAuth consent phishing        (mitigated by exact-scope match + PKCE)
```

Build the tree to 2–3 levels deep. Stop when each leaf either has a control or is explicitly accepted as residual risk. Anything not in the tree is, by definition, not in your threat model.

## 6. Risk Scoring (Lightweight CVSS-style)

You do not need full CVSS v3.1 vectors. A four-axis qualitative rubric is enough for most engineering decisions.

| Axis     | Low (1)       | Medium (2)       | High (3)        |
| -------- | ------------- | ---------------- | --------------- |
| Impact   | Annoyance     | Single-user data | Mass data leak  |
|          |               | leak             |                 |
| Likelihood | Requires insider | Skilled attacker | Public, automatable |
| Exposure | Internal only | Authenticated    | Unauthenticated |
| Recoverability | Trivial rollback | Manual cleanup | Permanent record |

Score = max of the four. Anything ≥ 3 needs a documented control or an explicit risk-acceptance note signed by the data owner.

## 7. Threat Modeling in Practice

### When to Run It

  - Every story that touches a trust boundary
  - Every new external dependency
  - Every change to authn/authz
  - Annually, on the system as a whole, with a 4-hour session

### Where to Record It

A 5-line note in the story, not a 40-page document:

```
Threat model (M02-4Q):
  Q1: unauthenticated POST /reset accepting email
  Q2: enumeration, flooding, predictable token
  Q3: uniform response, rate limit, 256-bit token
  Q4: tests in PR #482
```

### What to Skip

  - Full PASTA/VAST process — overkill for story-level work
  - Asset inventory spreadsheets — automate from cloud APIs instead
  - Threat intel feeds — not relevant at the story level

## 8. Common Mistakes

| Mistake | Why it fails | Better approach |
| ------- | ------------ | --------------- |
| Modeling "the system" | Too big, paralysis | Model one data flow at a time |
| Listing 50 threats | No prioritization, no fixes | 3–5 per flow, scored, acted on |
| Skipping non-security stories | "It's just a UI change" — until it's a CSRF | Apply 4Q to anything with state |
| Threat-modeling after the fact | Findings don't fit the design | Threat-model before code, in grooming |
| Treating it as a deliverable | Becomes a checkbox, ages out | Treat it as a 30-min conversation |

## 9. Tooling (Optional)

You can threat-model with a whiteboard. If you want tools:

  - **OWASP Threat Dragon** — free, draws DFDs, links to STRIDE
  - **Microsoft Threat Modeling Tool** — older, STRIDE-centric, free
  - **IriusRisk** — commercial, tracks threats across the SDLC
  - **Slate** (from Salesforce) — code-driven threat models

Pick the lightest one your team will actually use. The output is the conversation, not the diagram.

## 11. Self-Check

  1. Pick a feature you shipped in the last month. Can you answer the 4 questions for it in writing?
  2. For the same feature, build a 2-level attack tree. Mark the controls. Are any leaves unmitigated?
  3. Where in your workflow would a 30-min threat-model session fit? (Grooming, design review, PR template?)

## 12. Threat Modeling in Code

For teams that prefer a code-driven approach, models can live alongside the code:

```
threat-models/
├── auth-service/
│   ├── login.md
│   ├── password-reset.md
│   └── oauth-callback.md
├── billing-service/
│   ├── subscription.md
│   └── invoice.md
└── platform/
    ├── api-gateway.md
    └── ingress.md
```

Each file follows the 4Q template. The threat model is part of the service's documentation; it ages with the code, reviewed in PRs.

### Versioned Threat Models

A threat model is a *living document*. As the service evolves, the model evolves. Treat it like code:

  - Committed to git
  - Reviewed in PRs
  - Updated when the architecture changes
  - Dated and signed by the author

A threat model that is two years old is, by definition, wrong.

## 13. When Threat Modeling Fails

The discipline fails when:

  - The model becomes a deliverable (a 40-page doc nobody reads)
  - The model lives in a wiki (drift, no review)
  - The model is done after the fact (findings don't fit the design)
  - The model is run by security alone (engineers don't engage)
  - The model covers the whole system (paralysis; nothing concrete)

The discipline succeeds when:

  - The model is 5 lines, not 40 pages
  - The model is in git, not in a wiki
  - The model is in grooming, not after coding
  - The model is run by the engineer who is building the feature
  - The model is one data flow at a time, not the whole system

The asymmetry: the bad version of threat modeling is a lot of work with little value; the good version is a small amount of work with disproportionate value.

## 14. Threat Modeling for AI/LLM Features

A new class of feature: LLM-driven services. The threats are different:

  - **Prompt injection** — user input manipulates the LLM into bypassing instructions
  - **Data exfiltration** — the LLM is tricked into revealing system prompts or training data
  - **Jailbreak** — the user finds an input that bypasses the safety filter
  - **Hallucinated actions** — the LLM takes an action based on a hallucinated instruction
  - **Token cost attacks** — the user crafts inputs to exhaust the token budget

A 4Q for an LLM feature:

  - **Q1**: User submits a prompt; LLM returns a response; some prompts trigger tool calls.
  - **Q2**: Prompt injection via user-controlled data in retrieved documents; tool-call abuse; token exhaustion.
  - **Q3**: Input validation on retrieved content; tool calls go through a policy gate; rate limit on tokens.
  - **Q4**: Red-team prompts test common jailbreaks; tool-call test cases; load test on token budget.

LLM threat modeling is a new discipline; the patterns are still emerging. The 4Q frame applies; the threat catalog is different.

## 15. Threat Modeling Across the SDLC

Threat modeling has a place at multiple points in the lifecycle, not just design:

| Phase | Threat-modeling activity |
| ----- | ------------------------ |
| Plan | Risk classification of the feature |
| Design | 4Q + attack tree per data flow |
| Code | Review of untrusted input sources and sinks |
| Build | Threat-model the build process itself (M11) |
| Test | Threat-driven test cases (use the attack tree) |
| Deploy | Threat-model the deploy process (M12, M15) |
| Operate | Threat-model the runtime (M17) |

The cost of a missed threat is highest in design and lowest in operate. The cost of threat modeling is highest in design (because it's still plastic) and lowest in operate (because nothing can be changed). Model early; revisit as needed.

## 16. Recommended Reading

  - **"Threat Modeling: Designing for Security"** by Adam Shostack — the canonical text
  - **OWASP Threat Modeling Cheat Sheet** — quick reference
  - **Microsoft STRIDE** documentation
  - **"Tactical Disruption of the Cyber Kill Chain"** — for the threat-intel angle
  - **LINDDUN** — privacy-specific threat modeling, complement to STRIDE

## 17. Common Mistakes in Threat Modeling

| Mistake | Consequence | Fix |
| ------- | ----------- | --- |
| "We did threat modeling" but no record | The work is lost; new team members start over | Always produce the 4Q doc; commit to git |
| Threat model only at design review | Findings arrive after code is written | Model in grooming, before design |
| Threat model is one person | Their blind spots become the system's blind spots | Pair; multiple perspectives |
| Threat model never updated | Drift between model and code | Update when architecture changes |
| Threat model covers "the system" | Too broad, paralysis | One data flow at a time |
| Threats are vague ("XSS") | Hard to act on | Specific threats with specific test cases |
| 40-page threat model document | Nobody reads it | 5 lines, scannable |

## 18. Threat Modeling and the SSDLC

Threat modeling has a place at every SDLC phase:

| SDLC phase | Threat-modeling activity | Output |
| ---------- | ------------------------ | ------ |
| Plan | Risk classification of feature | Story tag |
| Design | Full 4Q for trust-boundary changes | Threat model file in PR |
| Code | Review input sources and sinks | PR review note |
| Build | Threat-model the build (M11) | Build security review |
| Test | Test cases derived from attack tree | Test in suite |
| Deploy | Threat-model the deploy (M12, M15) | Deploy policy |
| Operate | Threat-model the runtime (M17) | Detection rules |

The cost of a missed threat is highest in design; the cost of threat modeling is also highest in design. Model early; revisit as needed.

## 19. The Threat Model in the Audit

A threat model is evidence for several compliance controls:

| Control | Threat model evidence |
| ------- | --------------------- |
| SOC 2 CC7.1 (vuln detection) | Threat model in PR |
| ISO A.8.25 (secure dev) | Threat model in design |
| PCI 6.4.2 (code change review) | Threat model in PR |
| HIPAA §164.308 (admin safeguards) | Risk assessment + threat model |
| FedRAMP PL-8 (security architectures) | Architecture + threat model |

The audit asks "how do you think about threats?" The threat model files are the answer.

## 20. Threat Modeling with AI Assistants

A 2024–2026 reality: AI assistants can help with threat modeling. The patterns:

  - **AI as a sparring partner** — describe the feature; ask "what are the threats?"; AI suggests; engineer refines
  - **AI as a check** — describe the feature; ask "what did I miss?"; AI surfaces blind spots
  - **AI as a generator** — give the AI the 4Q template; ask it to fill in; engineer reviews

The discipline: AI is a tool, not a replacement. The engineer still owns the threat model. The AI accelerates the conversation.

## 21. Threat Modeling Templates Library

A small library of templates for common scenarios:

### Login / Auth Flow

```
Q1: User submits credentials; service verifies; session issued
Q2: Credential stuffing; brute force; session hijacking; password leak
Q3: MFA; rate limit; secure session; password hashing (argon2id)
Q4: Pen test; load test; integration test
```

### File Upload

```
Q1: User uploads file; service stores; admin reviews
Q2: Malicious file (zip bomb, RCE via filename); unencrypted storage; SSRF via URL upload
Q3: File type validation; size limit; AV scan; sandboxed processing; storage encryption
Q4: Unit test (validation); integration test (malware upload); pen test
```

### Payment / Webhook

```
Q1: Third party calls webhook; service verifies signature; action taken
Q2: Replay; tampered payload; signature bypass; secret leak
Q3: HMAC verification; timestamp check; secret rotation; signature log
Q4: Unit test (signature); integration test (end-to-end)
```

### Internal Admin Tool

```
Q1: Admin performs action; service logs; database updates
Q2: Privilege escalation; audit log bypass; session fixation
Q3: Strong auth; audit log; session timeout; least privilege
Q4: Manual test; audit log review
```

The templates are starting points. Each org's reality differs. Customize, but start with the pattern.

## Related

  - [[DevOps/devsecops/stage0-foundations/01-devsecops-mindset|M01: DevSecOps Mindset]]
  - [[DevOps/devsecops/stage0-foundations/03-secure-sdlc|M03: Secure SDLC]]
  - [[Architecture/solution-architecture-concepts/security/security|Security Foundations]]

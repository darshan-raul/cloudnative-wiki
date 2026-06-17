---
title: "M04: Security Requirements & Acceptance Criteria"
tags: [devsecops, stage0, foundations, requirements, acceptance-criteria, data-classification]
date: 2026-06-16
description: "Module 4 of 20 — writing security requirements that survive contact with engineering. Data classification, the SEC-prefix template, and how to fold security criteria into the existing Definition of Done."
---

# M04: Security Requirements & Acceptance Criteria

The single most common reason security work gets deprioritized: the requirements were never written down, so there is nothing to test against. This module gives you a template and a discipline for writing security requirements that ride along with functional requirements, get reviewed in grooming, and show up as testable acceptance criteria on the story.

## Learning Objectives

By the end of this module you should be able to:

  - Classify data and derive minimum security controls from the class
  - Write security acceptance criteria using the SEC- prefix convention
  - Fold security criteria into the Definition of Done without expanding the DoD to infinity
  - Build a one-page security-requirements template for the team
  - Recognize a story whose missing security criteria will cause a real incident

## 1. Why Most Security Requirements Fail

Survey 10 stories from your last sprint. How many have explicit security acceptance criteria? In most orgs, the answer is fewer than three. The reasons are consistent:

  - Security requirements live in a separate document nobody reads
  - "Non-functional" requirements get deferred when sprint capacity tightens
  - Security teams file tickets, not co-author stories
  - The Definition of Done does not include security, so it gets skipped under pressure

The fix is structural: make security acceptance criteria a non-skippable section of the story template, with a default of "N/A — no security implications" if truly none apply.

## 2. Data Classification

Every piece of data has a sensitivity class. The class drives the controls. You do not need 12 levels; four is enough for most orgs.

| Class | Examples                                              | Min encryption        | Min access | Retention    |
| ----- | ----------------------------------------------------- | --------------------- | ---------- | ------------ |
| Public | Marketing copy, public docs, public API responses     | TLS in transit        | None       | Indefinite   |
| Internal | Org charts, internal runbooks, non-PII logs         | TLS in transit        | Authenticated | 24 months    |
| Confidential | Customer email, business metrics, source code   | TLS + at-rest         | Role-based | 12 months    |
| Restricted | PII, payment card data, health data, secrets      | TLS + at-rest + KMS   | Least privilege + audit | Per regulation |

### How to Assign a Class

Default is *Internal*. Promote to *Confidential* if any of:

  - Identifies a specific person
  - Reveals a customer's business metrics
  - Would embarrass the org if leaked

Promote to *Restricted* if any of:

  - Falls under regulation (GDPR special categories, PCI, HIPAA, etc.)
  - Includes credentials or keys that grant access to production
  - Includes payment data, biometrics, or government identifiers

Once a class is assigned, the controls follow. This is the "derive from the class" pattern: you do not have to think about what to do; you read the class table and apply the column.

## 3. The SEC- Acceptance Criteria Convention

Add a section to the story template. Each criterion is a separate testable item.

```markdown
## Security acceptance criteria

- [ ] SEC-1: All inputs to [endpoint] are validated against a server-side allowlist
- [ ] SEC-2: Authorization check verifies [role] before [action]
- [ ] SEC-3: Sensitive fields ([list]) are masked in logs and error responses
- [ ] SEC-4: New dependency [X] is below CVE threshold per M08 policy
- [ ] SEC-5: Threat model 4Q note attached (M02)
- [ ] SEC-6: N/A — no security implications
```

The SEC- prefix matters. It does three things:

  - It is greppable — `grep SEC-` across the story store finds every security commitment
  - It is countable — the number of SEC-N per story is a maturity metric
  - It is reviewable — the security champion can scan for SEC-N in standup

### How to Choose Which SEC- Apply

A short lookup table for common story types:

| Story type                  | Typical SEC- |
| --------------------------- | ------------ |
| New HTTP endpoint           | SEC-1, SEC-2, SEC-3, SEC-5 |
| New dependency              | SEC-4 |
| New data store / schema     | SEC-3, plus data-class row, plus access-control row |
| Authn change                | SEC-1, SEC-2, SEC-5 |
| Internal refactor           | SEC-6 (typically N/A) |
| Infrastructure / IaC        | SEC-2, SEC-4, SEC-5 |
| UI change                   | SEC-3 (PII display), SEC-5 if auth flow |

## 4. The Definition of Done, With Security

The Definition of Done (DoD) is the list of conditions a story must meet to be "done." Most DoDs have functional, testing, and documentation items. Add three security items — no more.

```
Definition of Done (extended)

Functional
  - Acceptance criteria all met
  - Feature flag wiring in place (if applicable)

Testing
  - Unit tests for new logic
  - Integration tests for new flows
  - Manual smoke test on staging

Security (new)
  - All SEC- criteria checked or marked N/A with reason
  - SAST, SCA, secrets, IaC scans clean at policy threshold
  - Threat model 4Q attached (M02) for trust-boundary changes
```

Three items, not thirty. The SEC- criteria carry the specifics; the DoD just enforces that they exist.

## 5. Security Requirements Template

A one-page template your team can paste into the story creation flow.

```
=========================================
SECURITY REQUIREMENTS — STORY [#]
=========================================

1. Data classification
   [ ] Public    [ ] Internal    [ ] Confidential    [ ] Restricted
   New data types introduced: ___________________________

2. Trust boundary
   [ ] Touches a new trust boundary
   [ ] Crosses an existing trust boundary
   [ ] Does not cross a trust boundary

3. Threat model 4Q (M02)
   Q1 ________________________________________________
   Q2 ________________________________________________
   Q3 ________________________________________________
   Q4 ________________________________________________

4. SEC- acceptance criteria
   - [ ] SEC-1: input validation: _____________________
   - [ ] SEC-2: authorization: ________________________
   - [ ] SEC-3: data handling: ________________________
   - [ ] SEC-4: dependency: ___________________________
   - [ ] SEC-5: threat model attached: _________________
   - [ ] SEC-6: N/A — justification: ___________________

5. Compliance impact
   [ ] No frameworks affected
   [ ] SOC2: control ____________
   [ ] PCI-DSS: requirement _____
   [ ] GDPR: article ____________
   [ ] Other: ___________________

6. Security reviewer assigned
   Name: _____________   Required? [ ] Yes  [ ] No
=========================================
```

Fill it in once per story. It takes 5–10 minutes. The SEC- criteria get pasted into the story's acceptance section; the rest is metadata.

## 6. Requirements Anti-Patterns

### Anti-Pattern 1: Vague Verbs

> "The endpoint must be secure."

Untestable. Replace with:

> "Inputs are rejected unless they match `^[a-z0-9_-]{1,64}$`; non-matching inputs return 400 with a generic error body."

The second sentence is testable, code-reviewable, and auditable.

### Anti-Pattern 2: Bolted-on Compliance

> "Must comply with SOC2."

Compliance is an outcome of controls, not a requirement. Specify the controls (audit logging, access reviews, change management) and let compliance follow. Module M18 maps controls to frameworks.

### Anti-Pattern 3: Copy-Pasted Boilerplate

> "Must follow OWASP Top 10 best practices."

Which ones, on which endpoint, validated how? Reference the *specific* checks (input validation, output encoding, parameterized queries) with the *specific* test for each.

### Anti-Pattern 4: Security as a Ticket, Not a Story

The security team files a ticket "fix the IDOR on /user/:id/profile." Engineering treats it as a tax, not a feature. Better: the engineer who built /user/:id/profile is the one who fixes it, and the SEC- on the original story is updated to "as tested by integration test X."

## 7. The Security Champion Pattern

Every squad of 5–8 engineers gets one security champion. Not a separate role; an embedded engineer who:

  - Carries 1–2 chapters of security context from the security team
  - Reviews SEC- criteria in grooming
  - Is the first reviewer for security-sensitive PRs
  - Gets 10% time to maintain security tooling

This is the single highest-leverage organizational change you can make. It does not require headcount, just explicit allocation.

## 8. Requirements Traceability

Every SEC- must trace to a test. Every test must trace to a control. Every control must trace to a risk. The chain:

```
  Risk (from threat model)
    └─> Control (e.g., "rate limit 5/min on /login")
         └─> SEC- criterion (e.g., "SEC-2: 6th attempt returns 429")
              └─> Test (e.g., "integration test: 6th attempt returns 429 within 1s")
                   └─> Evidence (CI log, JUnit output, scan report)
```

If any link is missing, the chain is broken, and an auditor will notice. Tools like [Drata](https://drata.com), [Vanta](https://vanta.com), and [Secureframe](https://secureframe.com) help automate the evidence collection, but the chain itself must exist in your head first.

## 9. Worked Example: "Add Webhook Signature Verification"

Story: accept webhooks from a third-party payment provider. Today, we trust the source IP and the payload. Tomorrow, we verify the signature.

### Data Classification
Restricted — payment events.

### Trust Boundary
Crosses — third-party service into our system.

### 4Q Threat Model
  - **Q1:** Ingest webhook from payment provider; verify HMAC-SHA256 signature; persist event.
  - **Q2:** Replay of old valid webhook; payload tampering; signature bypass; secret leakage.
  - **Q3:** Reject if signature header missing; reject if signature mismatch; reject if timestamp drift > 5 min; secret stored in KMS.
  - **Q4:** Unit tests for each reject path; integration test sends signed and tampered payloads.

### SEC- Criteria
  - SEC-1: Webhook endpoint rejects requests with missing `X-Signature` header (HTTP 401).
  - SEC-2: Webhook endpoint rejects requests with invalid signature (HTTP 401, generic body).
  - SEC-3: Webhook endpoint rejects requests with timestamp drift > 300s (HTTP 401).
  - SEC-4: Signing secret retrieved from KMS at request time; never logged.
  - SEC-5: Replay protection: each event ID is stored for 24h; duplicates rejected.

### Tests
  - 4 unit tests for SEC-1/2/3/5
  - 1 integration test for end-to-end flow with real signed payload
  - 1 chaos test: stop signature verification; assert the test catches it

This is what mature security requirements look like: specific, testable, and traceable.

## 10. Self-Check

  1. Pick a recent story in your backlog. Write the SEC- criteria you *should* have included.
  2. Look at your Definition of Done. Does it enforce security, or just functional completion?
  3. Identify your squad's security champion. If you don't have one, who would you nominate? What 10% allocation would you carve out for them?

## 11. Security Requirements for Different Domains

The SEC- template generalizes. The same pattern works for:

### ML Model Requirements

  - **SEC-ML-1**: Training data classified per M04 data classes
  - **SEC-ML-2**: Threat model includes adversarial inputs (M02, M14-LLM)
  - **SEC-ML-3**: Model card includes known limitations and biases
  - **SEC-ML-4**: Input validation on inference inputs
  - **SEC-ML-5**: Output filtering for PII / restricted content
  - **SEC-ML-6**: Provenance for training data and model weights

### Infrastructure Requirements

  - **SEC-IAC-1**: Resource tagged with owner, env, data-class
  - **SEC-IAC-2**: Module from paved-road library (M10)
  - **SEC-IAC-3**: Threat model 4Q for new data flow
  - **SEC-IAC-4**: Encryption at rest enabled
  - **SEC-IAC-5**: No public ingress without explicit justification
  - **SEC-IAC-6**: Audit log destination configured

### Data Pipeline Requirements

  - **SEC-DP-1**: Data classification assigned at source
  - **SEC-DP-2**: PII handling documented in pipeline
  - **SEC-DP-3**: Encryption at rest and in transit
  - **SEC-DP-4**: Access control on source and sink
  - **SEC-DP-5**: Data retention policy enforced
  - **SEC-DP-6**: Lineage tracked for compliance

The prefix changes; the discipline is the same. Each domain adds its own SEC-* family; the SSDLC's per-story enforcement (M03) is unchanged.

## 12. The Requirements Lifecycle

SEC- criteria live with the story. Their lifecycle:

```
  1. Story created     →  SEC- section added (template)
  2. Grooming          →  SEC- reviewed, expanded
  3. PR opened         →  SEC- checked in DoD
  4. PR merged         →  SEC- tests run, evidence captured
  5. Story closed      →  SEC- archived with the story
  6. Post-incident     →  SEC- updated based on learning
```

A SEC- criterion is not a checkbox. It is a *commitment* that lives with the change. Postmortems review SEC- coverage; gaps become new criteria.

## 13. Requirements Anti-Patterns (Extended)

| Anti-pattern | Example | Fix |
| ------------ | ------- | --- |
| "Security theater" | "Must be secure" with no specifics | Replace with testable criteria |
| "Compliance copy-paste" | "Must comply with SOC2" | Map to specific controls (M18) |
| "Sprint-deferred" | "We will add security next sprint" | SEC- is part of the DoD, non-skippable |
| "Owner-less" | "Someone should add auth" | SEC- owner named, with SLA |
| "Test-less" | "We added validation" | Each SEC- has a corresponding test |
| "Wiki-stale" | Security reqs in a wiki nobody reads | In the story, in the PR, in the code |

## 14. The Requirements as Code Pattern

For orgs that want maximum automation, requirements can be machine-checked. A few patterns:

### YAML-Tested Requirements

```yaml
# security-requirements.yaml
stories:
  - id: AUTH-123
    title: "Add password reset"
    sec:
      - id: SEC-1
        text: "All inputs validated against server-side allowlist"
        test: integration_test
        test_path: "tests/auth/test_reset_input_validation.py"
      - id: SEC-2
        text: "Authorization check before reset"
        test: integration_test
        test_path: "tests/auth/test_reset_authorization.py"
      - id: SEC-5
        text: "Threat model 4Q attached"
        test: manual_review
        test_path: "docs/threat-models/auth-service/password-reset.md"
```

A CI step parses this, verifies the test file exists and passes. The SEC- is enforced by the same CI that enforces the functional criteria.

### Rego-Tested Requirements

For teams already using OPA (M15), the same Rego can encode the SEC- criteria:

```rego
package sec.story_compliance

deny[msg] {
  story := input.stories[_]
  story.sec[_].test == "integration_test"
  not story.sec[_].test_path
  msg := sprintf("Story %s has SEC %s without a test path", [story.id, story.sec[_].id])
}
```

Run with `conftest` in CI; the SEC- criteria become a gate.

### The Maturity Arc

  - **Year 1** — SEC- criteria in story template, manually verified
  - **Year 2** — SEC- criteria parsed, test paths checked
  - **Year 3** — SEC- criteria encoded as policy, fully automated

The trajectory is the same as the SSDLC: codify what was manual, automate what was codified.

## 15. Requirements and Compliance Mapping

The SEC- criteria are the bridge between engineering and compliance. Each framework control maps to one or more SEC- criteria:

| Framework control | Engineering SEC- |
| ----------------- | ---------------- |
| SOC 2 CC6.1 (logical access) | SEC-2 (authorization) |
| SOC 2 CC6.6 (boundary) | SEC-1, SEC-IAC-5 |
| SOC 2 CC7.1 (vuln detection) | M07 (SCA), enforced via DoD |
| SOC 2 CC8.1 (change mgmt) | All SEC-, because PR is the change unit |
| ISO A.8.25 (secure dev) | All SEC-, because SSDLC is the policy |
| PCI 6.3.3 (vendor patches) | M07 (SCA), enforced via DoD |
| PCI 6.4.1 (test public apps) | M04 SEC-DAST, M04 SEC-INT-TEST |
| HIPAA §164.308 (workforce) | SEC-2, training records, champion program |
| FedRAMP AC-6 (least priv) | SEC-2, M15 (policy) |

M18 covers the evidence collection. This module is the source of the criteria that produce the evidence.

## 16. The Security Requirements Anti-Pattern Catalog (Extended)

| Anti-pattern | Why it fails |
| ------------ | ------------ |
| "Penetrate test the app" | Reactive, not proactive |
| "Best practices" | Vague, un-actionable |
| "We follow OWASP" | OWASP is a starting point, not a finish line |
| "Manual review will catch it" | Manual review is inconsistent and unscalable |
| "We have a security team" | Security team cannot review every PR |
| "Security is everyone's job" | Everyone's job is no one's job (without structure) |
| "We use Snyk / Veracode" | Tools are not a substitute for requirements |
| "We do threat modeling" | The output is the requirement, not the activity |

## 17. Requirements and Test Design

Each SEC- criterion is a test. The test design:

  - **Unit test** — for code-level criteria (SEC-1, SEC-2, SEC-3)
  - **Integration test** — for flow-level criteria (SEC-2 with auth, SEC-4 with registry)
  - **Contract test** — for interface-level criteria (SEC-1 input validation)
  - **Manual test** — for threat model (SEC-5), data classification
  - **Compliance evidence** — for framework mapping

The test is the proof that the requirement is met. No test, no requirement.

## 18. The Requirements Review

The SEC- criteria are reviewed at three points:

  - **Grooming** — does the story have SEC- criteria? Are they right?
  - **PR** — are the tests in place? Are the criteria met?
  - **Post-incident** — did the SEC- catch the issue? If not, update the SEC-.

The review is continuous. The criteria improve with each cycle.

## 19. The Cost of a Missing SEC-

A missing or vague SEC- has a cost. Examples:

  - Missing SEC-1 (input validation) → SQL injection vulnerability → incident → fix → 100× the cost of a clear SEC-1 upfront
  - Missing SEC-2 (authorization) → IDOR vulnerability → data exposure → regulator notification → 1000× the cost
  - Missing SEC-4 (dep) → known CVE in prod → exploit → incident → 100× the cost

The cost of a clear SEC- is one engineer-hour. The cost of a missing SEC- is hours to days, plus the incident cost. The math is obvious.

## 20. The Future of Security Requirements

The discipline is evolving. Trends to watch:

  - **SEC- as machine-readable** — already happening; requirements in YAML/JSON, parsed by CI
  - **SEC- in the IDE** — real-time feedback on whether the code meets the criteria
  - **SEC- generated by AI** — given a story, the AI suggests the criteria; the engineer refines
  - **SEC- as policy** — every SEC- maps to a Kyverno/OPA rule that enforces it

The destination: every requirement is encoded, every test is automatic, every gap is caught before merge.

## Related

  - [[DevOps/devsecops/stage0-foundations/01-devsecops-mindset|M01: DevSecOps Mindset]]
  - [[DevOps/devsecops/stage0-foundations/02-threat-modeling|M02: Threat Modeling]]
  - [[DevOps/devsecops/stage0-foundations/03-secure-sdlc|M03: Secure SDLC]]
  - [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/security|NFR — Security]]

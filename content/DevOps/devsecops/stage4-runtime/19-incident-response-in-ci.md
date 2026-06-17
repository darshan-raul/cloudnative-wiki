---
title: "M19: Incident Response in CI"
tags: [devsecops, stage4, runtime, incident-response, ir, chaos, game-day, blameless]
date: 2026-06-16
description: "Module 19 of 20 — incident response for pipeline incidents and the integration with M17. Runbooks, blameless postmortems, chaos game days, and closing the loop so each incident makes the pipeline stronger."
---

# M19: Incident Response in CI

Incidents happen. The goal of the DevSecOps pipeline is to *prevent* them, but prevention is not perfection. The goal of incident response is to *detect* fast, *contain* fast, *recover* fast, and *learn* in a way that makes the next incident less likely. This module covers the IR process for pipeline and security incidents, the runbook pattern, the blameless postmortem, and chaos game days as the practice that makes response muscle memory.

## Learning Objectives

By the end of this module you should be able to:

  - Run an incident response for a pipeline compromise
  - Write a runbook for a top-N alert
  - Conduct a blameless postmortem
  - Design and run a chaos game day
  - Close the loop: incident → control improvement → re-verify
  - Distinguish incident response (this module) from runtime detection (M17)

## 1. Pipeline Incidents vs. Application Incidents

A pipeline incident is one where the build, deploy, or supply chain itself is compromised. The patterns:

  - **CI runner compromised** — attacker has the runner's credentials
  - **Registry compromised** — attacker pushes a malicious image
  - **Signing key compromised** — attacker can sign as you
  - **Source repo compromised** — attacker merges malicious code
  - **Secrets in repo** — discovered in production data
  - **OIDC trust policy misconfigured** — over-broad access
  - **Dependency confusion** — attacker publishes a same-name package

These are different from "the app is down" or "the app is slow." The response is different too: the response involves revoking keys, rotating credentials, and rebuilding from known-good source.

```
  App incident                 Pipeline incident
  -----------                  -----------------
  App is slow                  Malicious image in registry
  App returns 500              Signing key leaked
  DB is full                   Dependency confusion attack
  Network is down              Source repo compromised
                              
  Response: rollback, scale,   Response: revoke, rotate,
  hotfix                      rebuild, re-sign
```

## 2. The IR Cycle

Five phases, repeated for every incident:

```
   1. Detect
       ↓
   2. Contain
       ↓
   3. Eradicate
       ↓
   4. Recover
       ↓
   5. Learn (postmortem)
       ↓
   (back to detect, with improvements)
```

The phases are not always linear. A critical incident may compress all five into minutes. A complex one may span days. The discipline is the same.

## 3. The Pipeline IR Playbook

### Scenario: Signing Key Compromised

**Detect**: Anomalous signature, key exfil alert from SIEM, third-party report.

**Contain (15 min)**:
  1. Revoke the signing key at the source (KMS key disable, or rotate)
  2. Notify the cloud provider if the key grants cloud access
  3. Stop all builds using the compromised key
  4. Block the public key from being trusted (admission controller policy)

**Eradicate (1 hour)**:
  1. Identify how the key was compromised
     - Key was in a CI env var? Check git history, audit log
     - Key was in a developer's machine? Check endpoint EDR
     - Key was in a stolen laptop? Check access logs
  2. Re-issue keys (KMS-issued, with new key ID)
  3. Re-sign all artifacts with the new key
  4. Update admission controller to trust only the new key

**Recover (2 hours)**:
  1. Re-deploy workloads (now signed with new key)
  2. Verify deployments are healthy
  3. Communicate to customers (if their SBOM signatures are affected)
  4. Update the SBOM registry with new signatures

**Learn (1 week)**:
  1. Postmortem: root cause, timeline, contributing factors
  2. Improvements:
     - Move signing to KMS-only (if not already)
     - Add key-access monitoring
     - Reduce signing key scope
     - Add pre-commit secrets scan (M06) if the key was in code
  3. Verify improvements landed in the pipeline

### Scenario: Malicious Image in Registry

**Detect**: Trivy, Falco, or admission controller alerts on unexpected content; third-party report.

**Contain (10 min)**:
  1. Mark the image as `quarantine` in the registry
  2. Identify all clusters that may have pulled the image
  3. Cordon and drain nodes that pulled it
  4. Stop all deploys from that registry account

**Eradicate (1 hour)**:
  1. Identify how the malicious image landed
     - Compromised registry credentials?
     - Compromised CI pushing the image?
     - Direct push bypassing CI?
  2. Revoke the credentials used
  3. Re-build the image from known-good source
  4. Sign and push the new image

**Recover (2 hours)**:
  1. Deploy the new image
  2. Verify all workloads are running the new image
  3. Audit any workloads that ran the malicious image (CloudTrail, K8s audit)

**Learn (1 week)**:
  1. Postmortem
  2. Improvements:
     - Add admission controller to require signed images (M13, M15)
     - Add registry write audit to SIEM
     - Add CI-pushed-only policy (no direct pushes)

## 4. The Runbook Pattern

For every top-N alert, write a runbook. A runbook is not a novel; it's a checklist.

### Template

```markdown
# Runbook: <alert name>

## Summary
One-sentence description of what this alert means.

## Severity
P1 / P2 / P3

## Owner
Team or person on call.

## Detection
What fired this alert? Where does it come from?

## Triage (first 5 minutes)
1. Acknowledge the alert in PagerDuty
2. Check the alert context: <links>
3. Run the triage script: <command>
4. Decide: is this a real incident or a known false positive?

## Containment
Step-by-step commands to limit the blast radius.
- Command 1
- Command 2
- Command 3

## Eradication
Step-by-step commands to remove the threat.
- Command 1
- Command 2

## Recovery
Step-by-step commands to restore service.
- Command 1
- Command 2

## Escalation
Who to call if the on-call is stuck or this is a P1.
- Security lead
- Engineering manager
- Legal (if customer data involved)
- Comms (if external communication needed)

## Related
- Detection rules: <links>
- Past incidents: <links>
- Architecture diagrams: <links>
```

A runbook that has not been tested is fiction. Test every runbook in a game day (below).

## 5. The Blameless Postmortem

After every incident, a blameless postmortem. The rules:

  - **No blame** — focus on systems and decisions, not individuals
  - **Multiple causes** — every incident has 3+ contributing factors
  - **Timeline first** — get the timeline right before assigning cause
  - **Improvements, not punishments** — the output is a list of improvements with owners and SLAs

### Template

```markdown
# Postmortem: <incident title>

## Summary
3-5 sentences: what happened, what was the impact, what was the root cause.

## Impact
- User-facing: <description, duration, % of users affected>
- Internal: <systems affected, data exposed>
- External: <customer impact, regulatory implications>

## Timeline (UTC)
- 14:23  First alert fired
- 14:25  On-call paged
- 14:31  On-call acknowledged
- 14:45  Incident confirmed, severity P1 declared
- 14:50  Containment started
- 15:10  Root cause identified
- 15:35  Fix deployed
- 15:42  Service restored
- 16:00  Incident closed, postmortem scheduled

## Root Cause
What was the underlying issue? (Not "human error" — "the system allowed an action that led to...")

## Contributing Factors
- Factor 1
- Factor 2
- Factor 3

## What Went Well
- Detection was fast (3 minutes)
- Runbook was followed exactly
- Communication was clear

## What Went Poorly
- Runbook had a wrong command (updated)
- Containment took longer than expected
- Customer comms was late

## Improvements
- [ ] Story: Add a pre-commit hook to catch <root cause>
  Owner: @alice  Due: 2026-06-30  Severity: P2
- [ ] Story: Update runbook with correct command
  Owner: @bob  Due: 2026-06-20  Severity: P3
- [ ] Story: Add alerting for <detection gap>
  Owner: @carol  Due: 2026-07-15  Severity: P2

## Lessons Learned
1. The 4-minute secrets window is real
2. Runbooks must be tested, not just written
3. The pipeline-to-SIEM loop is critical
```

### Postmortem Database

Store every postmortem in a searchable database. New incidents are researched for similar past patterns. Patterns recur; the postmortem is how you break the cycle.

## 6. The Loop-Back

The most important part of incident response is the loop-back: each incident makes the pipeline stronger.

```
  Incident
     |
     v
  Postmortem
     |
     +-- Improvement 1: new SAST rule
     +-- Improvement 2: new Falco rule
     +-- Improvement 3: new IaC policy
     +-- Improvement 4: tighter OIDC scope
     +-- Improvement 5: better runbook
     |
     v
  Stories filed
     |
     v
  Improvements ship
     |
     v
  Same incident can't recur
```

The same incident happening twice is a process failure. The first time is a learning; the second time is a sign the postmortem didn't ship.

## 7. Chaos Game Day

A chaos game day is a planned exercise where the team practices incident response against a simulated failure. The goal is not to break the system; it's to break the response process.

### Designing a Game Day

Pick a scenario that exercises:
  - Detection (does the alert fire?)
  - Triage (does the on-call know what to do?)
  - Containment (do the runbook commands work?)
  - Communication (does the right person get paged?)
  - Recovery (does service come back?)

### Example: "Signing Key Compromised" Game Day

```
00:00  Game day facilitator: "scenario starts; the prod signing key was leaked on a developer's laptop"
00:00  Facilitator sends a fake Slack message: "I think I left my laptop in a cab"
00:05  The on-call should:
       - Recognize the risk
       - Page the security lead
       - Open the runbook
00:10  The on-call starts the runbook:
       - Revoke the key (real or simulated)
       - Cordon the affected nodes
       - Re-sign and re-deploy
00:30  Service is restored (or the gap is identified)
00:45  Debrief: what worked, what didn't
01:00  File improvement stories

```

### Frequency

Quarterly. The first game day surfaces massive gaps. The third is noticeably smoother. The fifth is muscle memory.

## 8. The Incident Response Team

A small team that owns the IR process:

  - **Incident commander** — coordinates the response, makes the calls
  - **Security lead** — owns the technical response for security incidents
  - **Comms lead** — internal and external communications
  - **Scribe** — captures the timeline in real time
  - **Subject matter experts** — pulled in as needed

For a 24/7 org, the on-call rotation includes an incident commander and a security responder. For a smaller org, it's a shared rotation with documented escalation.

## 9. Integration with M17

The runtime detection (M17) feeds the IR (this module). The flow:

```
  Runtime alert
     ↓
  M17 triage (5 min)
     ↓
  Real incident? → M19 IR cycle
     ↓
  Postmortem → improvements to M17 rules
     ↓
  M17 rules updated, new alerts covered
```

The IR cycle and the detection cycle are coupled. An alert that doesn't lead to a runbook is an alert that won't be handled well in a real incident.

## 10. Common Anti-Patterns

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| "We have IR" but no runbook | On-call improvises | Runbook per top-N alert |
| Postmortem names the person who "made the mistake" | Blame culture, learning stops | Blameless template; focus on systems |
| Improvements filed but not shipped | Same incident in 6 months | Track postmortem improvements as stories with SLAs |
| Game day never happens | Real incident exposes unprepared team | Quarterly game day, calendar-locked |
| No loop-back to pipeline | Detection works, prevention doesn't | File improvement stories that touch M05–M18 |
| IR only for security | App incidents have no playbook | IR is for all incidents, security-tuned |
| On-call is one person, no backup | Single point of failure | Rotation, escalation policy |

## 11. Self-Check

  1. Pick your top alert from M17. Is there a runbook? If yes, when was it last tested in a game day?
  2. Look at your last 3 postmortems. Did the improvement stories ship? If not, why?
  3. If a signing key was compromised tonight, could your on-call run the response in under 30 minutes?

## 12. The IR Tech Stack

The technical components of a modern IR stack:

```
  Detection
  ─────────
  - Falco (eBPF, container)
  - Wazuh (SIEM)
  - CloudTrail (cloud audit)
  - osquery (host)
  - Auditd (Linux)
  - WAF logs (perimeter)
  - Application logs (structured)
       |
       v
  Triage
  ──────
  - PagerDuty / Opsgenie (alerting, on-call)
  - Slack (coordination)
  - Incident.io (incident management)
  - Zoom (war room)
       |
       v
  Investigation
  ─────────────
  - CloudTrail lookup
  - Falco rule trace
  - Container forensics (snapshot)
  - Memory dump
  - Disk image
       |
       v
  Containment
  ───────────
  - K8s cordon / drain
  - Network policy
  - Service account revocation
  - Cloud quarantine
  - Snapshot for forensics
       |
       v
  Recovery
  ────────
  - Deployment rollback
  - Re-build from known-good
  - Re-issue credentials
  - Verify health
       |
       v
  Postmortem
  ──────────
  - Timeline
  - Root cause
  - Improvements
  - Stories
```

The stack is layered. Each layer produces evidence. The evidence is auditable.

## 13. IR Severity Levels

| Severity | Definition | Response time | Resolution SLA |
| -------- | ---------- | ------------- | -------------- |
| P1 | Customer-impacting outage or active breach | <15 min | <4 hours |
| P2 | Service-degrading issue, no breach | <1 hour | <24 hours |
| P3 | Internal-only, no immediate impact | <4 hours | <1 week |
| P4 | Improvement opportunity | <1 week | Next sprint |

A pipeline compromise (signing key leaked) is typically P1 — active breach, customer data potentially exposed, requires immediate response.

## 14. The Pipeline Compromise Scenarios (Deep Dive)

### Scenario: Malicious Dependency (XZ Utils Style)

**Detect**: SCA scanner flags the dep; Trivy fails the build; or a researcher reports it externally.

**Contain (hours, not minutes)**:
  1. Block the dep at the registry proxy
  2. Identify all images built with the dep
  3. Cordon all nodes running affected images
  4. Stop all deploys from the affected pipeline
  5. Notify the security team + comms

**Eradicate (1–2 days)**:
  1. Re-build all affected images from a known-good version
  2. Roll all deployments
  3. Audit the dep's behavior in any logs (could it have exfiltrated?)
  4. Reset any credentials that may have been touched
  5. Patch the upstream or pin to a clean version

**Recover (2–5 days)**:
  1. Verify all workloads are on clean images
  2. Verify no signs of lateral movement
  3. Communicate to customers (if relevant)

**Learn (1+ week)**:
  1. Postmortem: how did the dep land? Was SCA not catching it? Was the build not hermetic?
  2. Improvements: stricter dep allowlist, SBOM diffing, hermetic builds
  3. Update the dependency-confusion defense (private registry, provenance verification)

### Scenario: Compromised CI Runner

**Detect**: Anomalous cloud API calls from runner IPs; or external report.

**Contain (minutes)**:
  1. Disable the runner pool
  2. Revoke all OIDC tokens issued in the last 24 hours
  3. Identify what was running on the runner during the compromise window
  4. Notify security team

**Eradicate (1+ day)**:
  1. Audit the cloud API calls made from the runner
  2. Identify any cloud resources created/modified by the attacker
  3. Roll back any unauthorized changes
  4. Re-issue credentials (OIDC re-federation)
  5. Patch the runner OS

**Recover (1+ day)**:
  1. Stand up new runner pool
  2. Verify builds run on the new pool
  3. Verify all cloud API calls are from expected identities

**Learn (1+ week)**:
  1. Postmortem: how was the runner compromised?
  2. Improvements: ephemeral-only runners, network egress allowlist, anomaly detection on runner → cloud calls
  3. Update the threat model

## 15. The Incident Database

A searchable database of past incidents:

```
  - Date
  - Title
  - Severity
  - Timeline
  - Root cause
  - Improvements filed
  - Status of improvements
  - Related incidents
```

When a new incident happens, search the database for similar patterns. Patterns recur. The postmortem is how you break the cycle.

## 16. The War Room

For P1 incidents, a war room is the coordination point. The pattern:

  - **Dedicated video call** (Zoom, Meet) — not Slack huddles
  - **Incident commander** — drives the response, makes the calls
  - **Scribe** — captures the timeline in real time
  - **Subject matter experts** — pulled in as needed
  - **Communications lead** — internal/external comms
  - **Decision log** — what was decided, by whom, when

The IC does not code. The IC coordinates. The SME fixes. The scribe documents. The pattern is well-established (Google SRE Book, PagerDuty IR guides).

## 17. The Customer Communication

A P1 security incident may require customer communication. The pattern:

  - **Internal first** — security team, leadership, legal
  - **Affected customers** — direct notification, within hours
  - **Public** — blog post, status page, after customer notification
  - **Regulators** — per regulation (GDPR 72-hour rule, state breach laws)

The communication includes:
  - What happened (in plain language)
  - What data was affected (specific types)
  - What we are doing (response actions)
  - What you should do (customer actions, if any)
  - Who to contact (incident email)

Comms is a separate skill from security. The security team provides the facts; the comms team shapes the message. The legal team reviews both.

## 18. The Blameless Culture (Why It Matters)

The blameless postmortem culture is *operationally* better than the blame culture. The reasons:

  - **Engineers report issues faster** — no fear of punishment
  - **Root causes are more accurate** — engineers share what they actually did, not what they think they should have done
  - **Improvements are systemic** — the focus is on the system, not the person
  - **Retention** — engineers stay where they feel safe
  - **Audit defensibility** — a blameless culture is evidence of a mature security program

The opposite: a blame culture produces cover-ups, slow reporting, and shallow postmortems. The cost is real.

## 19. Common Mistakes (Extended)

| Mistake | Consequence | Fix |
| ------- | ----------- | --- |
| "We have a runbook" but never tested it | Real incident exposes gaps | Game day quarterly |
| Postmortem filed, improvements not | Same incident in 6 months | Track improvement status |
| IC codes during incident | IC loses track of the response | IC is dedicated, no coding |
| No scribe | Timeline reconstructed after, with gaps | Scribe from minute 1 |
| Customer comms delayed | Customers find out from Twitter | Pre-drafted comms templates |
| Legal not in the loop | Compliance violation, regulatory fine | Legal on call for P1 |
| Improvements filed with no owner | They never ship | Owner named, due date set |
| Postmortem not shared internally | Other teams don't learn | Share via internal blog / wiki |
| One person's "postmortem" | Skews to their perspective | Multiple voices in the postmortem |

## 20. The IR Drill Library

For each scenario, maintain a drill script:

```
  drills/
  ├── signing-key-compromised.md
  ├── malicious-dependency.md
  ├── runner-compromise.md
  ├── source-repo-compromise.md
  ├── registry-compromise.md
  └── secrets-in-prod.md
```

Each drill script:
  - Scenario description
  - Roles
  - Steps
  - Expected outcomes
  - Improvements to file if a gap is found

Drill quarterly. The same drill, run twice, surfaces different gaps (the system evolves, the threats evolve, the team evolves).

## Related

  - [[DevOps/devsecops/stage0-foundations/01-devsecops-mindset|M01: DevSecOps Mindset]]
  - [[DevOps/devsecops/stage4-runtime/17-runtime-detection|M17: Runtime Detection]]
  - [[DevOps/devsecops/stage4-runtime/18-compliance-evidence|M18: Compliance Evidence]]
  - [[DevOps/devsecops/stage4-runtime/20-capstone-end-to-end-pipeline|M20: Capstone]]
  - [[DevOps/devsecops/stage4-runtime/README|Stage 4 — Runtime]]

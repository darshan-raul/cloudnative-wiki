---
title: Postmortem
tags: [incident-response, postmortem, blameless, review, learning]
date: 2025-05-24
description: Blameless incident postmortem template and process - structured reviews to prevent recurrence
---

# Postmortem 📝

Blameless reviews focus on system/process failures, not individual blame.

## When to Write a Postmortem

Write one for every Severity-1 or Severity-2 incident, and for any recurring issue.

## Template

```markdown
# Incident Postmortem: <Title>

**Date:** YYYY-MM-DD
**Duration:** X hours Y minutes
**Severity:** SEV1 / SEV2
**Status:** Resolved

## Summary
One-paragraph description of what happened and impact.

## Timeline
- HH:MM — Event
- HH:MM — Detection
- HH:MM — Response started
- HH:MM — Containment
- HH:MM — Resolution

## Root Cause
What was the technical root cause?

## Contributing Factors
- What made this harder to detect/resolve?
- What systems/processes failed?

## What Went Well
- Fast detection
- Good communication
- Effective automation

## What Could Be Improved
- Slower to identify root cause
- Missing monitoring
- Runbook gaps

## Action Items
| Action | Owner | Due Date |
|--------|-------|----------|
| Add alert for X | @analyst | 2025-06-01 |
| Update runbook | @sre | 2025-06-07 |

## Metrics
- Time to Detect (TTD): X min
- Time to Resolve (TTR): Y min
- False positives generated: Z
```

## Blameless Culture

- Assume everyone was acting with good intent given the information they had
- Focus on what in the system allowed the failure, not who made a mistake
- The goal is learning and prevention, not punishment

## Related

- [[Security/incident-response/README|IR Hub]]
- [[Security/siem/alerting/README|Alerting]]
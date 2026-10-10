---
title: On-Call
tags: [devops, sre, on-call, operations, alerting]
date: 2026-10-10
description: Running an on-call rotation that works for the service and for the people — rotation design, what should and should not page, escalation, handoffs, runbooks, measuring load and the practices that prevent burnout.
---

# On-Call

Being on call means being the person who responds when a production system needs a human outside normal working patterns. Done well, it keeps services reliable and gives engineers a direct view of how their software behaves. Done badly, it is the fastest way to lose experienced people.

The quality of on-call is mostly determined before anyone is paged: by what is allowed to page, how the rotation is built, and what happens after each incident.

## Principles

1. **Whoever builds it shares in running it.** Engineers who carry the pager for their own service fix the causes of pages. Throwing operations over a wall removes that feedback.
2. **Every page must be actionable and urgent.** If it can wait until morning or needs no action, it is not a page.
3. **On-call load is finite and measured.** It is a resource to budget, like any other.
4. **Nobody is a hero.** A rotation that depends on one person who knows everything is a single point of failure.
5. **On-call time is working time.** It is compensated, and it displaces other work.

## Designing the rotation

| Decision              | Guidance                                                                                              |
| :-------------------- | :---------------------------------------------------------------------------------------------------- |
| Rotation size         | At least five or six people for a single-site, 24×7 rotation; fewer means too-frequent shifts         |
| Shift length          | One week is common. Shorter if nights are busy.                                                       |
| Time zones            | Follow-the-sun across two or three sites removes night pages entirely when the team is distributed    |
| Primary and secondary | A secondary catches missed pages and is the first escalation                                          |
| Scope                 | A person can only be effective for systems they understand; do not make one rotation cover everything |
| New joiners           | Shadow first, then primary with an experienced secondary, before going solo                           |
| Swaps and overrides   | Easy and self-service — people have lives                                                             |

Responsibilities during a shift are narrow by design: acknowledge within the agreed time, assess, mitigate or escalate, communicate, and hand over. The on-call engineer does not have to fix the root cause at 3 a.m.; restoring service is the job. Planned project work should be light or absent during a shift, because interrupts will take whatever time is given.

## What should page

Ask of every alert:

- Does it indicate that users are affected now or will be very soon?
- Is there an action a human must take?
- Does it need doing before the next working day?

Three yeses make a page. Anything less is a ticket or a dashboard. In practice this means paging on **symptoms** — error-budget burn, a failing critical journey — rather than causes, as described in [[Observability/alerting|alerting]] and [[DevOps/sre/slos-and-error-budgets|SLOs and error budgets]].

Each paging alert needs an owner, a severity, and a runbook link. An alert that fires for something nobody owns should be deleted, not routed to whoever is unlucky.

## Escalation

```
alert ─► primary (acknowledge within 5 min)
            │ no acknowledgement
            ▼
         secondary (5 min)
            │ no acknowledgement
            ▼
         engineering manager / incident commander on duty
```

- Escalation by **time** is automatic, handled by the paging tool.
- Escalation by **judgement** is always acceptable: an on-call engineer who is unsure, out of depth, or facing something large should pull in help immediately. Make this explicitly safe. The cost of waking a colleague is small; the cost of an hour of solo guessing is not.
- Keep an up-to-date list of who to call for each dependency: other teams, the cloud provider's support, critical vendors.

When an incident is more than one person can handle, switch to a structured response — [[DevOps/sre/incident-management|incident management]].

## Runbooks

A runbook is what the alert links to. Its reader is tired, lacks context and wants to be told what to check. A useful one fits on a page:

| Section         | Content                                                                      |
| :-------------- | :--------------------------------------------------------------------------- |
| What this means | One or two sentences: what is broken and who is affected                     |
| First checks    | Three to five commands or dashboard links, in order                          |
| Known causes    | The usual suspects and how to confirm each                                   |
| Mitigations     | Roll back, scale up, fail over, disable a feature flag — with exact commands |
| Escalation      | Who owns this and how to reach them                                          |

Rules: keep them next to the code so they are reviewed with changes; test them during game days; fix them in the postmortem when they were wrong. A runbook step that is always performed the same way is a candidate for automation. Examples of the form: the [[Kubernetes/guides/troubleshooting/index|Kubernetes troubleshooting playbooks]] and [[Security/incident-response/playbooks/README|security playbooks]].

## Handoff

At the end of a shift the outgoing engineer passes on, in writing:

- incidents during the shift and their status,
- anything still degraded or being watched,
- silenced alerts, and when the silences expire,
- risky changes scheduled for the coming shift,
- follow-up items that were raised.

Ten minutes of handoff prevents the incoming person from rediscovering a known problem at night.

## Measuring the load

You cannot improve what you do not count. Track per shift:

| Measure                         | A reasonable target                        |
| :------------------------------ | :----------------------------------------- |
| Pages                           | No more than about two incidents per shift |
| Pages outside working hours     | As close to zero as the service allows     |
| Actionable ratio                | Above 80–90% of pages needed human action  |
| Time to acknowledge             | Within the agreed response time            |
| Repeat pages for the same cause | Zero after the first postmortem            |
| Hours spent on interrupts       | Leaves most of the week for planned work   |

Review these at a regular operations review. Take the three noisiest alerts each month and fix, tune or delete them. If the load stays above target, the team is entitled to stop feature work until it comes down — that is what an error budget policy is for.

## Preventing burnout

- **Sleep matters.** Someone paged repeatedly overnight should start late or take the next day off, without having to ask.
- **Compensate** on-call with pay or time off, according to local norms and law.
- **Spread the load** evenly, including across seniority. Senior engineers leaving the rotation removes the people best placed to fix what pages.
- **Give time to fix causes.** A rotation that only absorbs pain and never removes it will exhaust anyone.
- **Blameless culture.** People who fear consequences hide mistakes and escalate late.
- **Check in.** After a rough shift, a manager should ask how it went and what would have helped.

## Tooling

A paging system (PagerDuty, Opsgenie, Grafana OnCall, incident.io or similar) provides schedules, overrides, escalation policies, multiple notification channels and acknowledgement tracking. It should receive alerts from the alerting pipeline rather than have rules defined inside it, and it should itself be monitored: a dead-man's-switch alert proves that pages can still be delivered.

## Practice

Skills that are only used during real incidents decay. Run regular exercises:

- **Game days** — deliberately break something in a controlled way and respond as if it were real. See [[Kubernetes/guides/non-functional/chaos-engineering|chaos engineering]].
- **Tabletop exercises** — talk through a scenario without touching anything; cheap and surprisingly revealing. An example: [[Architecture/solution-architecture-concepts/authentication/capstone/02-incident-tabletop|identity incident tabletop]].
- **"Wheel of misfortune"** — replay a past incident with a new person in the on-call seat.

## Related

- [[DevOps/sre/README|SRE overview]]
- [[DevOps/sre/incident-management|Incident management and postmortems]]
- [[Linux/troubleshooting/systematic-debugging|Systematic debugging]]
- [[Kubernetes/eks/troubleshooting/README|EKS troubleshooting]]
- [The SRE Book: Being On-Call](https://sre.google/sre-book/being-on-call/)

## Across the wiki

- [[Security/incident-response/README|Incident Response]] — incident response (Security)
- [[Kubernetes/concepts/L08-operations/03-common-failure-modes|Common Failure Modes & Triage]] — incident response (Kubernetes)
- [[Security/incident-response/postmortem/README|Postmortem]] — incident response (Security)

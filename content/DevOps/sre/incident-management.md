---
title: Incident Management and Postmortems
tags: [devops, sre, incident-management, postmortem, reliability]
date: 2026-10-10
description: Responding to production incidents with structure — severity levels, roles, the response lifecycle, mitigation before diagnosis, communication, and blameless postmortems that lead to real changes.
---

# Incident Management and Postmortems

An incident is an unplanned event that degrades a service and needs an urgent, coordinated response. Small ones are handled by the [[DevOps/sre/on-call|on-call engineer]] alone. This note is about the ones that are not: where several people get involved, customers are affected, and the difference between twenty minutes and three hours is whether the response is organised.

Unstructured responses fail in recognisable ways: everyone debugs and nobody coordinates, two people make conflicting changes, stakeholders interrupt engineers for updates, and nobody remembers afterwards what was done or when. Incident management exists to prevent those.

## Severity

Agree on levels in advance so that the scale of the response is not debated during the event.

| Severity | Criteria                                                           | Response                                                   |
| :------- | :----------------------------------------------------------------- | :--------------------------------------------------------- |
| **SEV1** | Critical journey down or data loss for many users; security breach | All hands needed, immediately, any hour; executive updates |
| **SEV2** | Major degradation, or a critical journey down for a subset         | On-call plus owning team, immediately; regular updates     |
| **SEV3** | Minor degradation with a workaround                                | Owning team, in working hours                              |
| **SEV4** | Cosmetic or no user impact                                         | Normal backlog                                             |

Two rules: **anyone can declare an incident**, and **when unsure, declare higher** — it is far cheaper to downgrade than to discover late that something was a SEV1.

## Roles

The central idea, borrowed from emergency services, is to separate _coordinating_ from _doing_.

| Role                            | Responsibility                                                                      |
| :------------------------------ | :---------------------------------------------------------------------------------- |
| **Incident commander (IC)**     | Owns the response: sets priorities, assigns work, decides. Does **not** debug.      |
| **Operations / technical lead** | Investigates and changes the system, with whoever they pull in                      |
| **Communications lead**         | Updates stakeholders, the status page and support, so engineers are not interrupted |
| **Scribe**                      | Keeps a timestamped log of observations, decisions and actions                      |

In a small incident one person holds several roles; the IC role should still be named out loud. Seniority does not determine who is IC — it is a skill, and the IC's decisions hold during the incident regardless of who else joins. Hand over the role explicitly ("you have command") when shifts change.

## The lifecycle

```
detect ─► declare ─► assemble ─► mitigate ─► resolve ─► review ─► follow up
            │                       ▲
            └── assess severity ────┘   (re-assess throughout)
```

### Detect and declare

Detection should come from [[Observability/alerting|alerting]], not from customers. Declaring means opening a dedicated channel and call, naming the IC and stating the severity. Tooling can do this in one command; the important part is that it happens within minutes.

### Mitigate first

The priority is to **stop the impact**, not to understand the cause. Understanding comes later, with the system stable. Standard mitigations, roughly in order of preference:

| Mitigation                | When                                                                   |
| :------------------------ | :--------------------------------------------------------------------- |
| Roll back the last change | Something was deployed or reconfigured recently — the most common case |
| Turn off a feature flag   | The problem is isolated to a feature                                   |
| Fail over                 | One zone, region or replica is unhealthy                               |
| Scale up or out           | Saturation                                                             |
| Shed load or rate limit   | Overload; protect the core at the cost of the periphery                |
| Restart                   | A stuck or leaking process — capture diagnostics first if it is cheap  |
| Block the source          | Abusive or malformed traffic                                           |

"What changed?" is the most productive first question; most incidents follow a change. This is why fast, practised rollback is among the highest-value reliability investments — see [[DevOps/ci-cd/deployment-strategies|deployment strategies]].

While working:

- **One change at a time**, announced before it is made and recorded by the scribe.
- **State hypotheses explicitly** and what would confirm or refute them.
- **Set time boxes.** If an approach has not paid off in fifteen minutes, the IC asks for alternatives.
- **Preserve evidence** where it does not delay recovery: logs, heap dumps, a snapshot of a bad node.

Method is covered in [[Linux/troubleshooting/systematic-debugging|systematic debugging]].

### Communicate

Silence makes stakeholders anxious and makes them interrupt. Send updates on a fixed cadence — every 30 minutes for a SEV1 — even when the update is "no change".

A good update states: what users are experiencing, what is being done, and when the next update will come. It avoids speculation about causes and avoids promises about resolution time. Internal and public messages differ in detail, not in honesty.

### Resolve

The incident is resolved when impact has ended and the system is stable, not when the root cause is fixed. Announce it, note what is still being monitored, and schedule the review.

## Postmortems

A postmortem is a written analysis of an incident whose purpose is that the organisation learns. Write one for every SEV1 and SEV2, for anything that consumed a significant share of an [[DevOps/sre/slos-and-error-budgets|error budget]], and for near misses that were merely lucky.

### Blameless

Blameless means the analysis assumes people acted reasonably given what they knew, the tools they had and the pressures they were under. The question is never "who made the mistake" but "why did the system make that mistake easy, and why did nothing catch it?".

This is not softness. It is the only approach that works:

- Blame makes people hide information, and the review then learns nothing.
- "Human error" is where analysis stops when it should start. The engineer who ran the wrong command was a symptom; the absent confirmation step, the confusing environment names and the missing guardrail are the findings.
- Removing or retraining the individual leaves the trap in place for the next person.

### Contents

| Section              | What goes in it                                                                               |
| :------------------- | :-------------------------------------------------------------------------------------------- |
| Summary              | Two or three sentences a non-engineer can follow                                              |
| Impact               | Who was affected, how, for how long; requests failed, budget consumed, revenue or data effect |
| Timeline             | Timestamped events: first signal, detection, declaration, each action, mitigation, resolution |
| Detection            | How it was found, and how long after it began                                                 |
| Contributing factors | The chain of conditions that made it possible — several, not one "root cause"                 |
| What went well       | Worth keeping                                                                                 |
| What went badly      | Where the response was slowed                                                                 |
| Where we got lucky   | What could easily have been worse                                                             |
| Action items         | Specific, owned, dated and prioritised                                                        |

Complex systems rarely fail for a single reason. Asking "why?" repeatedly is useful, but follow every branch rather than one chain to one cause.

### Action items that happen

Postmortems fail when their actions quietly never get done.

- Each item has **one owner and a due date** and lives in the normal work tracker.
- Prefer changes to the **system** — a guardrail, an automated check, a safer default — over reminders and documentation. "Be more careful" is not an action.
- Classify them: prevent recurrence, detect sooner, mitigate faster.
- Fewer, important items beat a long list. Review completion in a regular operations meeting.

### Share it

Hold a review meeting within a week while memory is fresh, then publish the document widely. Other teams have the same latent problems. Reading postmortems is one of the best ways for new engineers to learn how the system really behaves.

## Measures, used carefully

| Measure                          | Use                                            |
| :------------------------------- | :--------------------------------------------- |
| Time to detect                   | Is monitoring catching things before users do? |
| Time to mitigate                 | How good are rollback, failover and runbooks?  |
| Incident count by cause category | Where to invest                                |
| Action item completion           | Is the organisation actually learning?         |

Averages such as MTTR are dominated by a few long incidents and are poor targets. Never use incident counts to judge people or teams: the count will drop, because incidents will stop being declared.

## Related

- [[DevOps/sre/README|SRE overview]]
- [[Security/incident-response/README|Security incident response]] and [[Security/incident-response/postmortem/README|security postmortems]] — the same structure with forensics and disclosure duties added
- [[Kubernetes/eks/troubleshooting/README|EKS troubleshooting]]
- [[Kubernetes/guides/non-functional/disaster-recovery|Disaster recovery]]
- [The SRE Book: Postmortem Culture](https://sre.google/sre-book/postmortem-culture/)

## Across the wiki

- [[Azure/compute/aks/troubleshooting-runbook|AKS SRE Troubleshooting & Incident Runbook — CrashLoopBackOff, Node NotReady, and CNI Leaks]] — troubleshooting (Azure)
- [[GCP/compute/gke/troubleshooting-runbook|GKE SRE Incident Response & Production Troubleshooting Runbook]] — troubleshooting (GCP)
- [[Linux/troubleshooting/README|Linux Troubleshooting]] — troubleshooting (Linux)

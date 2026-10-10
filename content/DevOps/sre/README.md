---
title: Site Reliability Engineering
tags: [devops, sre, reliability, slo, on-call, incident-management]
date: 2026-10-10
description: An entry point to SRE practice — what distinguishes it from operations and DevOps, the core ideas of SLOs, error budgets, toil and blameless learning, and a path through the notes in this section.
---

# Site Reliability Engineering

Site Reliability Engineering (SRE) treats operations as a software problem. It began at Google and is best summarised by one sentence from its founder: SRE is what happens when you ask a software engineer to design an operations function.

Its distinguishing idea is that **reliability is a feature with a target, not an absolute**. A service does not need to be as reliable as possible; it needs to be reliable _enough_ for its users, and every bit of reliability beyond that costs speed and money. SRE provides the vocabulary and mechanisms to make that trade-off explicit.

## The core ideas

| Idea                            | In one line                                                                             | Note                                                          |
| :------------------------------ | :-------------------------------------------------------------------------------------- | :------------------------------------------------------------ |
| **SLIs and SLOs**               | Measure what users experience, and set a target for it                                  | [[DevOps/sre/slos-and-error-budgets\|SLOs and error budgets]] |
| **Error budgets**               | The allowed unreliability is a budget that pays for change; when it is spent, slow down | [[DevOps/sre/slos-and-error-budgets\|SLOs and error budgets]] |
| **Toil reduction**              | Manual, repetitive, automatable work is a cost to be measured and engineered away       | Below                                                         |
| **On-call that is sustainable** | Few, actionable pages; shared load; time to fix causes                                  | [[DevOps/sre/on-call\|On-call]]                               |
| **Incident management**         | A practised, role-based response instead of improvisation                               | [[DevOps/sre/incident-management\|Incident management]]       |
| **Blameless postmortems**       | Learn from failure by examining systems, not punishing people                           | [[DevOps/sre/incident-management\|Incident management]]       |
| **Gradual change**              | Most outages are caused by change, so make change small, staged and reversible          | [[DevOps/ci-cd/deployment-strategies\|Deployment strategies]] |

## SRE, DevOps and platform engineering

They are related answers to the same problem — the wall between people who write software and people who run it.

|                 | DevOps                                                                | SRE                                               | Platform engineering                      |
| :-------------- | :-------------------------------------------------------------------- | :------------------------------------------------ | :---------------------------------------- |
| Nature          | A culture and set of practices                                        | A specific implementation with defined mechanisms | A product: an internal platform           |
| Central concern | Flow of change from commit to production                              | Reliability of what is running                    | Developer productivity and cognitive load |
| Key measures    | Deployment frequency, lead time, change failure rate, time to restore | SLO attainment, error budget, toil                | Adoption, time to first deploy            |

A longer comparison is in [[DevOps/platform-engineering/platform-vs-devops-vs-sre|platform engineering vs DevOps vs SRE]]. In practice the labels matter less than whether the mechanisms exist: a team with SLOs, a humane rotation and real postmortems is doing SRE whatever it is called.

## Toil

Toil is operational work that is **manual, repetitive, automatable, reactive, without lasting value, and that grows with the size of the service**. Restarting a stuck worker by hand is toil. So is copying a certificate to twelve servers every ninety days, or approving the same kind of access request forty times a week.

Toil is not the same as "work I dislike". Writing a design document, running a postmortem and planning capacity are overhead or engineering, not toil.

Why it matters:

- It scales linearly with the system, so a growing service eventually consumes the whole team.
- It displaces the engineering work that would reduce it.
- It is error-prone, and it burns people out.

What to do about it:

1. **Measure it.** Track where on-call and operations time goes for a few weeks. The largest sources are rarely the ones people guessed.
2. **Cap it.** Google's guideline is that toil should stay below half of an SRE's time; the rest is engineering.
3. **Eliminate in order of return.** Automate the frequent and simple first. Some toil is better removed by fixing the cause — the worker that gets stuck — than by automating the restart.
4. **Make the right thing the default.** Self-service through a platform removes whole categories of request-driven toil: [[DevOps/platform-engineering/golden-paths|golden paths]].

## Where reliability comes from

SRE practices sit on top of sound engineering; they do not substitute for it.

| Foundation                          | Notes                                                                                                                                                                                                                                                                                                                                                                                  |
| :---------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Architecture that tolerates failure | [[Architecture/solution-architecture-concepts/reliability/resilience\|Resilience]], [[Architecture/solution-architecture-concepts/reliability/idempotency\|idempotency]], [[Architecture/solution-architecture-concepts/reliability/load-balancing\|load balancing]]                                                                                                                   |
| Understanding the targets           | [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/availability\|Availability]], [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/reliability\|reliability]], [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/reliability-vs-availability\|the difference between them]] |
| Being able to see                   | [[Observability]] — metrics, logs, traces and [[Observability/alerting\|alerting]]                                                                                                                                                                                                                                                                                                     |
| Capacity                            | [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/capacity-planning\|Capacity planning]], [[Architecture/solution-architecture-concepts/performance-testing\|performance testing]]                                                                                                                                                                 |
| Recovery                            | [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/disaster-recovery\|Disaster recovery]], [[Kubernetes/guides/non-functional/backup-restore\|backup and restore]]                                                                                                                                                                                  |
| Proving it                          | [[Kubernetes/guides/non-functional/chaos-engineering\|Chaos engineering]]                                                                                                                                                                                                                                                                                                              |
| Safe change                         | [[DevOps/ci-cd/README\|CI/CD]], [[Kubernetes/guides/delivery/progressive-delivery/strategies\|progressive delivery]]                                                                                                                                                                                                                                                                   |

## Starting from nothing

A team that wants to adopt this without a reorganisation can do it in a few steps:

1. **Pick one user-facing service and write one SLO** for it. Availability of its most important endpoint is enough.
2. **Build a dashboard that shows the SLO and the remaining error budget.**
3. **Replace cause-based pages with one or two burn-rate alerts** on that SLO.
4. **Write a postmortem for the next incident**, blameless, with owned action items.
5. **Review on-call load monthly** and fix the top source of pages.
6. **Agree what happens when the budget is exhausted** — before it happens.

Each step is useful by itself, and together they are most of the value.

## Notes in this section

- [[DevOps/sre/slos-and-error-budgets|SLOs and error budgets]]
- [[DevOps/sre/on-call|On-call]]
- [[DevOps/sre/incident-management|Incident management and postmortems]]

## Related

- [[DevOps]] hub
- [[Security/incident-response/README|Security incident response]] — the same discipline applied to security events
- [[Kubernetes/guides/non-functional/high-availability|Kubernetes high availability]]
- [Google SRE books](https://sre.google/books/) — free online, and the reference for everything here

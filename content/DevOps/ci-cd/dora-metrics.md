---
title: DORA Metrics
tags: [devops, ci-cd, metrics, dora, delivery-performance]
date: 2026-10-10
description: The DORA software delivery metrics — what each one measures, how to collect it, why speed and stability improve together, how to use the numbers to find constraints, and the ways measuring them goes wrong.
---

# DORA Metrics

The DORA research programme (DevOps Research and Assessment, now part of Google Cloud) has studied thousands of teams for over a decade to find which practices predict good software delivery. Its best-known output is a small set of metrics that describe **delivery performance** — how quickly and how safely an organisation gets changes to users.

The most important finding is not the metrics themselves. It is that **speed and stability are not a trade-off**. Teams that deploy more often also fail less and recover faster. The practices that make change fast — small batches, automation, fast feedback — are the same ones that make it safe.

## The metrics

| Metric                              | Question                                                          | Dimension  |
| :---------------------------------- | :---------------------------------------------------------------- | :--------- |
| **Deployment frequency**            | How often do we deploy to production?                             | Throughput |
| **Lead time for changes**           | How long from a commit to that commit running in production?      | Throughput |
| **Change failure rate**             | What share of deployments cause a failure needing remediation?    | Stability  |
| **Failed deployment recovery time** | How long to restore service after a failed deployment?            | Stability  |
| **Deployment rework rate**          | What share of deployments are unplanned fixes for a previous one? | Stability  |

The first four are the classic "four keys". Recent reports added rework rate, and renamed "time to restore service" to make clear it concerns failures caused by change, not every outage. A separate, fifth idea in earlier reports — **reliability**, meaning whether the service meets its targets — is covered by [[DevOps/sre/slos-and-error-budgets|SLOs]].

## Measuring them

| Metric                | Source of truth                                          | Definition to agree on                                            |
| :-------------------- | :------------------------------------------------------- | :---------------------------------------------------------------- |
| Deployment frequency  | Deployment events from the pipeline or GitOps controller | What counts as a production deployment (per service, per region?) |
| Lead time for changes | Commit timestamps joined to deployment events            | Start at first commit or at merge — pick one and keep it          |
| Change failure rate   | Deployments linked to incidents, rollbacks and hotfixes  | What counts as a failure: any rollback? only user-visible impact? |
| Recovery time         | Incident start and resolution times                      | When the clock starts — at impact, or at detection                |
| Rework rate           | Deployments labelled as fixes for a recent deployment    | How to label them                                                 |

Practical advice:

- **Instrument, do not survey.** Emit an event for every deployment with service, version, commit and timestamp. Most of the metrics fall out of joining that with version control and the incident tracker. The data is the same data that feeds deployment markers on dashboards — [[Observability/grafana|Grafana]].
- **Write the definitions down.** Two teams with different definitions of "failure" cannot be compared, and one team that changes its definition cannot compare with its own past.
- **Use medians and distributions**, not means. A single long incident or a change stuck in review for a month distorts an average.
- **Measure per service or team**, not for the whole organisation in one number.
- **Approximate is fine.** Trends matter far more than precision.

Tools such as Four Keys, Apache DevLake, Sleuth, LinearB and the engineering-insights features of developer portals collect these, but a few queries over pipeline and incident data are enough to start.

## Reading the numbers

DORA publishes performance clusters each year. The exact boundaries shift between reports, so use them as orientation rather than targets:

| Metric                | Stronger performance looks like | Weaker performance looks like |
| :-------------------- | :------------------------------ | :---------------------------- |
| Deployment frequency  | On demand, many times a day     | Monthly or less often         |
| Lead time for changes | Under a day                     | Weeks to months               |
| Change failure rate   | A few percent                   | A large fraction              |
| Recovery time         | Under an hour                   | Days                          |

What matters is your own trend, and the **relationship** between the metrics:

| Pattern                                         | Likely meaning                                                       |
| :---------------------------------------------- | :------------------------------------------------------------------- |
| Low frequency, long lead time, low failure rate | Large, careful, infrequent releases — stability bought with slowness |
| High frequency, high failure rate               | Speed without safety nets: weak tests, no progressive rollout        |
| Long lead time, most of it waiting              | Queues: code review, manual approvals, test environments             |
| Good failure rate, long recovery time           | Failures are rare, so nobody has practised rollback                  |
| Everything improving together                   | The practices are working                                            |

## Using them to improve

The metrics are **outcomes**. You cannot improve them directly; you improve the capabilities that produce them and watch whether the numbers follow.

1. **Find the constraint.** Break lead time into stages: coding, waiting for review, review, waiting for CI, CI, waiting for deployment, deployment. One stage usually dominates, and it is usually a wait, not work.
2. **Change one thing** aimed at that constraint.
3. **Check the metric** over the following weeks.

| Capability                             | Mainly improves             | See                                                                                                             |
| :------------------------------------- | :-------------------------- | :-------------------------------------------------------------------------------------------------------------- |
| Small batches, trunk-based development | Lead time, failure rate     | [[DevOps/ci-cd/git\|Git strategy]]                                                                              |
| Fast, reliable automated tests         | Lead time, failure rate     | [[DevOps/ci-cd/pipeline-design\|Pipeline design]]                                                               |
| Deployment automation                  | Frequency, lead time        | [[Kubernetes/guides/delivery/gitops/basics\|GitOps]]                                                            |
| Progressive delivery and fast rollback | Failure rate, recovery time | [[DevOps/ci-cd/deployment-strategies\|Deployment strategies]]                                                   |
| Monitoring and alerting                | Recovery time               | [[Observability/alerting\|Alerting]]                                                                            |
| Loosely coupled architecture           | All of them                 | [[Architecture/solution-architecture-concepts/foundations/high-cohesion-loose-coupling\|Cohesion and coupling]] |
| Self-service platform                  | Lead time, frequency        | [[DevOps/platform-engineering/README\|Platform engineering]]                                                    |
| Blameless learning from incidents      | Recovery time, failure rate | [[DevOps/sre/incident-management\|Incident management]]                                                         |

DORA's research also consistently finds that **culture** — psychological safety, learning from failure, low-blame collaboration — predicts delivery performance as strongly as any technical practice.

## How measuring goes wrong

These metrics are diagnostic instruments. Turn them into targets and they stop measuring anything (Goodhart's law).

| Misuse                                      | What happens                                                           |
| :------------------------------------------ | :--------------------------------------------------------------------- |
| Ranking teams against each other            | Teams with easy contexts look good; others game the numbers            |
| Tying them to individual performance or pay | Incidents are not declared; deployments are split artificially         |
| Chasing frequency for its own sake          | Empty deployments; no change in what users get                         |
| Comparing unlike systems                    | A mobile app and a backend API have different natural cadences         |
| Treating the benchmark tiers as the goal    | Effort goes into reaching "elite", not into the team's real constraint |
| Looking only at throughput                  | Stability quietly degrades                                             |

Use them **within** a team, over time, to ask "what is slowing us down or hurting us?" — and always look at throughput and stability together.

## What they do not tell you

DORA metrics describe the delivery pipeline. They say nothing about whether you are building the right thing, whether users are happy, or how the work feels to the people doing it. Pair them with:

- **Product outcomes**: adoption, retention, the business metric the work was meant to move.
- **Reliability**: SLO attainment and error budget.
- **Developer experience**: frameworks such as SPACE and DevEx add satisfaction, cognitive load and flow, usually through short regular surveys.

A team can deploy forty times a day and still be shipping things nobody wants.

## AI-assisted development

Recent DORA reports examine AI coding assistants and find a consistent pattern: AI amplifies what is already there. Teams with fast feedback, small batches and good tests convert it into delivery gains; teams without them tend to produce larger changes faster, and stability suffers. The fundamentals above matter more, not less, when code is cheap to write.

## Related

- [[DevOps/ci-cd/README|CI/CD overview]]
- [[DevOps/sre/README|Site reliability engineering]]
- [[DevOps/platform-engineering/platform-vs-devops-vs-sre|Platform engineering vs DevOps vs SRE]]
- [[DevOps/ci-cd/release-and-versioning|Release and versioning]]
- [DORA research](https://dora.dev/research/)

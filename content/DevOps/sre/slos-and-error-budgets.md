---
title: SLOs and Error Budgets
tags: [devops, sre, slo, sli, error-budget, reliability]
date: 2026-10-10
description: Defining and using service level objectives — choosing SLIs that reflect user experience, setting targets, computing error budgets, burn rate, writing an error budget policy, and the pitfalls that make SLOs meaningless.
---

# SLOs and Error Budgets

"Is the service reliable enough?" has no answer until someone defines _enough_. A service level objective does that: it states, as a number, how well the service must work from the user's point of view. The gap between that number and perfection is the **error budget** — the amount of failure you are allowed, and can spend.

## Three terms

| Term    | What it is                                             | Example                                                          |
| :------ | :----------------------------------------------------- | :--------------------------------------------------------------- |
| **SLI** | Indicator: a measurement of service behaviour          | The proportion of checkout requests that succeed in under 500 ms |
| **SLO** | Objective: a target for an SLI over a time window      | 99.9% of checkout requests succeed in under 500 ms, over 30 days |
| **SLA** | Agreement: a contract with consequences for missing it | "99.5% monthly uptime or a 10% service credit"                   |

An SLA is a commercial promise to customers. An SLO is an internal engineering target and should be **stricter** than any SLA, so that you find out you are in trouble before you owe anyone money.

## Choosing SLIs

A good SLI is a ratio of good events to valid events, measured as close to the user as possible:

```
SLI = good events / valid events
```

| Service type               | Useful SLIs                                                                                                         |
| :------------------------- | :------------------------------------------------------------------------------------------------------------------ |
| Request-serving (API, web) | **Availability**: non-5xx responses / all responses. **Latency**: responses faster than a threshold / all responses |
| Data pipeline              | **Freshness**: records processed within N minutes. **Correctness**: valid outputs / all outputs                     |
| Storage                    | **Durability**: objects readable / objects stored                                                                   |
| Scheduled jobs             | **Success**: runs completed on time / runs scheduled                                                                |

Guidelines:

- **Measure the user's experience, not a component's health.** CPU, replica count and "the pod is up" are not SLIs. A service can be fully "up" and failing every request.
- **Measure at the edge where you can.** Load balancer or gateway metrics see failures that the application never logged, such as a crashed process.
- **Express latency as a proportion under a threshold**, not as an average or a percentile value. "99% under 500 ms" composes into a budget; "p99 is 480 ms" does not. See [[Architecture/solution-architecture-concepts/percentile|percentiles]].
- **Decide what counts as valid.** Client errors (4xx) are usually excluded from availability; requests from your own health checks and load tests should be too.
- **Few SLIs.** One availability and one latency SLI on the journeys that matter most beats twenty that nobody watches.

The raw data comes from [[Observability/prometheus/instrumenting|instrumentation]] or from [[Observability/tracing|span metrics]].

## Setting the target

| Target | Allowed downtime per 30 days | What it implies                                                    |
| :----- | :--------------------------- | :----------------------------------------------------------------- |
| 99%    | 7 h 12 min                   | Internal tools, batch systems                                      |
| 99.5%  | 3 h 36 min                   |                                                                    |
| 99.9%  | 43 min                       | A typical target for a user-facing service                         |
| 99.95% | 21 min                       | Needs automated failover; a human cannot respond fast enough alone |
| 99.99% | 4 min                        | Multi-zone or multi-region, automated everything, expensive        |

How to pick:

1. **Start from what you achieve today.** Measure a month. Setting a target far above current performance creates a permanently exhausted budget that everyone learns to ignore.
2. **Ask what users notice.** Past a point, extra nines are invisible: a mobile user on a flaky network cannot distinguish 99.99% from 99.9%.
3. **Respect your dependencies.** A service cannot be more reliable than the things it synchronously depends on, unless it can degrade gracefully without them.
4. **Remember the cost curve.** Each additional nine typically costs several times more than the last in redundancy, engineering effort and slower delivery.
5. **100% is the wrong target.** It is unachievable, forbids all change, and users would not notice the difference anyway.

Use a **rolling** window (28 or 30 days) for operations, so the budget recovers gradually, rather than a calendar month that resets and invites end-of-month risk-taking.

## The error budget

```
error budget = 1 − SLO

SLO 99.9% over 30 days, 10 million requests
→ budget = 0.1% = 10,000 failed requests
```

The budget reframes the relationship between shipping and stability:

- **Budget remaining** → the service is more reliable than it needs to be. Ship faster, take risks, run experiments.
- **Budget exhausted** → users are getting less than promised. Prioritise reliability until it recovers.

This turns an argument of opinions ("we need to slow down" versus "we need to ship") into a shared, measured signal. Everything that consumes budget counts: outages, bad deployments, planned maintenance, dependency failures and chaos experiments alike.

## Burn rate

Burn rate is how fast the budget is being consumed relative to the rate that would spend exactly all of it by the end of the window.

| Burn rate | Meaning                                         |
| :-------- | :---------------------------------------------- |
| 1         | On course to use exactly the budget             |
| 2         | Budget gone in half the window                  |
| 14.4      | 2% of a 30-day budget consumed in one hour      |
| 720       | A total outage: a 30-day budget gone in an hour |

Burn rate is the right basis for paging. A slow leak at burn rate 1.5 deserves a ticket; a burn rate of 14 deserves a page now. The multi-window, multi-burn-rate alert rules are in [[Observability/alerting|alerting]].

## An error budget policy

An SLO without consequences is a dashboard. Write down, in advance and with product and engineering leadership agreeing, what happens as the budget is spent:

| Budget state                             | Agreed response                                                                                      |
| :--------------------------------------- | :--------------------------------------------------------------------------------------------------- |
| Healthy                                  | Normal delivery. Risky changes and experiments are welcome.                                          |
| Burning fast                             | Page on-call; treat as an incident.                                                                  |
| More than half consumed                  | Review recent incidents; reliability work is prioritised in the next planning cycle.                 |
| Exhausted                                | Feature releases pause except for reliability fixes and security patches, until the budget recovers. |
| Exhausted repeatedly                     | Escalate: staffing, architecture, or an SLO that does not match reality.                             |
| A single incident consumed a large share | A postmortem is mandatory.                                                                           |

Agreeing this while calm is the entire point. Negotiating it during an outage does not work.

## Writing an SLO down

```yaml
# OpenSLO-style definition
apiVersion: openslo/v1
kind: SLO
metadata:
  name: checkout-availability
spec:
  service: checkout
  description: Checkout requests succeed
  indicator:
    spec:
      ratioMetric:
        good:
          metricSource:
            type: Prometheus
            spec:
              query: sum(rate(http_requests_total{service="checkout",status!~"5.."}[5m]))
        total:
          metricSource:
            type: Prometheus
            spec:
              query: sum(rate(http_requests_total{service="checkout"}[5m]))
  timeWindow:
    - duration: 30d
      isRolling: true
  objectives:
    - target: 0.999
```

Tools such as Sloth and Pyrra generate recording rules, burn-rate alerts and dashboards from a definition like this, which is far less error-prone than writing them by hand. The query language is covered in [[Observability/prometheus/promql|PromQL]].

Record alongside it: who owns the SLO, why this target was chosen, what is excluded, and when it will next be reviewed.

## Pitfalls

| Pitfall                                          | Result                                                                                            |
| :----------------------------------------------- | :------------------------------------------------------------------------------------------------ |
| SLIs on infrastructure rather than user journeys | Green dashboards during real outages                                                              |
| Targets set by aspiration                        | Budget always exhausted, policy ignored                                                           |
| Too many SLOs                                    | None of them drives a decision                                                                    |
| No policy                                        | Nothing changes when the budget runs out                                                          |
| Averages                                         | The slow tail, which is what users complain about, disappears                                     |
| Low-traffic services                             | One failed request in a quiet hour looks like a disaster — use longer windows or synthetic probes |
| Using SLO attainment to judge people             | Incidents get hidden and SLIs get gamed                                                           |
| Never revisiting                                 | The target drifts away from what users need                                                       |

Review SLOs every quarter. If the objective was met and users were unhappy, the SLI is measuring the wrong thing. If it was missed and nobody noticed, the target is too strict.

## Related

- [[DevOps/sre/README|SRE overview]]
- [[DevOps/sre/incident-management|Incident management]]
- [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/availability|Availability]] — the nines, and how to build for them
- [[Observability/grafana|Grafana]] — an SLO dashboard is the first one to build
- [The SRE Workbook: Implementing SLOs](https://sre.google/workbook/implementing-slos/)

## Across the wiki

- [[Kubernetes/guides/non-functional/high-availability|High Availability]] — high availability (Kubernetes)
- [[AWS/solutions-architect-professional/domain-1/1.3-reliable-and-resilient-architectures|1.3 Design Reliable and Resilient Architectures]] — high availability (AWS)
- [[Azure/compute/aks/cluster-tiers-sla|AKS Cluster Tiers, High Availability Control Plane, and Private Cluster Architecture]] — high availability (Azure)

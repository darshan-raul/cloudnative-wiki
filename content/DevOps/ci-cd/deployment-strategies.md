---
title: Deployment Strategies
tags: [devops, ci-cd, deployment, canary, blue-green, feature-flags, rollback]
date: 2026-10-10
description: The ways to move a new version into production and how to choose — recreate, rolling, blue-green, canary, shadow and feature flags — with deploy versus release, automated analysis, rollback, and database compatibility.
---

# Deployment Strategies

Most production incidents are caused by change. A deployment strategy is how you limit what a bad change can damage and how quickly you can undo it. The choice trades four things against each other: **risk**, **speed**, **cost** and **complexity**.

This note is platform-independent. The Kubernetes mechanics, with manifests, are in [[Kubernetes/guides/delivery/progressive-delivery/strategies|progressive delivery strategies]] and [[Kubernetes/guides/delivery/progressive-delivery/argo-rollouts|Argo Rollouts]].

## Deploy is not release

Two ideas that are usually bundled and should not be:

- **Deploy**: new code is running in production.
- **Release**: users are exposed to it.

Separating them is the most powerful idea on this page. Code can be deployed dark, verified in production, and released later — gradually, to chosen users, by a product decision instead of an engineering event. Every strategy below is a way of controlling that gap.

## The strategies

| Strategy          | How                                                                   | Downtime | Blast radius if bad                 | Rollback                      | Extra cost              |
| :---------------- | :-------------------------------------------------------------------- | :------- | :---------------------------------- | :---------------------------- | :---------------------- |
| **Recreate**      | Stop the old version, start the new                                   | Yes      | Everyone                            | Redeploy the old version      | None                    |
| **Rolling**       | Replace instances a few at a time                                     | No       | Grows as the rollout proceeds       | Roll back the same way — slow | Minimal                 |
| **Blue-green**    | Run a complete new environment beside the old; switch traffic at once | No       | Everyone, after the switch          | Switch back — instant         | Double capacity briefly |
| **Canary**        | Send a small share of traffic to the new version; increase in steps   | No       | The canary share                    | Route traffic away — fast     | Small                   |
| **Shadow**        | Copy live traffic to the new version; discard its responses           | No       | None (if side effects are isolated) | Not applicable                | Duplicate load          |
| **Feature flags** | Deploy code disabled; enable per user, percentage or segment          | No       | Whoever the flag targets            | Turn the flag off — instant   | Flag management         |

### Recreate

Acceptable for development environments, batch systems, and applications that cannot run two versions at once. Otherwise avoid it.

### Rolling

The default almost everywhere, and adequate for most changes. Two caveats: both versions serve traffic simultaneously for the duration, so they must be compatible; and a rollback is another rolling update, which takes as long as the rollout did. Readiness checks must be truthful, or broken instances receive traffic — [[Kubernetes/concepts/L03-workloads/10-probes|probes]].

### Blue-green

A full copy of the environment ("green") is deployed and tested while "blue" serves users. Traffic switches in one step, and blue is kept for a while as an instant rollback. It gives a clean cutover and a real pre-production test against production infrastructure. The costs are temporary double capacity and the fact that after the switch **everyone** is on the new version at once. Details in [[Architecture/solution-architecture-concepts/migration-patterns/blue-green-deployments|blue-green deployments]].

### Canary

A small percentage of real traffic — 1%, then 5%, 25%, 50%, 100% — goes to the new version, with a pause at each step to compare its behaviour with the stable version. Problems affect few users and are caught by real traffic rather than synthetic tests. It needs traffic-splitting capability (a load balancer, [[Kubernetes/concepts/L04-services-networking/09-gateway-api|Gateway API]], or a [[Kubernetes/guides/networking/service-mesh|service mesh]]) and good metrics.

### Shadow

Production requests are mirrored to the new version, whose responses are thrown away. It tests performance and correctness under real load with no user impact. The danger is side effects: the shadow must not send emails, charge cards or write to shared data stores.

### Feature flags

The new behaviour is behind a runtime switch. Flags give the finest control — per user, per tenant, per region — and the fastest rollback, with no deployment at all. They also enable trunk-based development: unfinished work merges continuously, switched off. The cost is discipline. Each flag doubles the paths through the code, so flags need owners and expiry dates, and stale flags must be removed. Old flags left in place are a well-known source of serious incidents.

## Choosing

| Situation                                                  | Reasonable choice                                  |
| :--------------------------------------------------------- | :------------------------------------------------- |
| Routine change to a stateless service                      | Rolling                                            |
| High-traffic or business-critical service                  | Canary with automated analysis                     |
| A change that must cut over atomically; a major version    | Blue-green                                         |
| Risky rewrite of a core path                               | Shadow first, then canary                          |
| A user-visible feature with product uncertainty            | Feature flag, released gradually                   |
| Low traffic (a canary would see too few requests to judge) | Blue-green with synthetic checks, or feature flags |
| Many regions or clusters                                   | Progressive: one region, wait, then the rest       |

The strategies combine. A common production setup deploys with a canary and releases features with flags.

## Automated analysis

A canary watched by a person at a dashboard does not scale and is not reliable at 2 a.m. Automate the promotion decision:

1. Define success **before** deploying: error ratio, latency percentile, saturation, and a business metric where one exists.
2. Compare the canary with a **baseline** running the old version at the same time and scale, not with last week's numbers.
3. Hold each step long enough to gather meaningful data.
4. Promote automatically when the criteria hold; **abort and roll back automatically** when they do not.

The metrics come from the same sources as [[DevOps/sre/slos-and-error-budgets|SLOs]] and [[Observability/alerting|alerting]]. A service whose error budget is exhausted should not be receiving risky deployments at all.

## Rollback

A rollback you have not practised is a hope. Make it routine:

- **Roll back first, investigate second.** Restoring service is the priority; the cause can be found afterwards — [[DevOps/sre/incident-management|incident management]].
- **Rollback must be as automated as deployment** and take minutes.
- **Roll forward only when it is clearly faster and safe** — a one-line fix through a fast pipeline. Under pressure, reverting is nearly always the better call.
- **Keep the previous version available**: the old artifact, the old environment, the old flag state.

## The hard part: state

Code can be rolled back. Data usually cannot. Any strategy in which two versions run at the same time — which is all of them except recreate — requires both versions to work with the same database schema, message formats and API contracts.

- **Schema changes use [[Architecture/solution-architecture-concepts/migration-patterns/expand-contract|expand and contract]]**: add the new structure, deploy code that writes both, migrate data, switch reads, and only then remove the old structure, in separate deployments.
- **APIs and events stay backward-compatible**: add fields, never remove or repurpose them in the same release.
- **Never couple a schema change and a code change in one irreversible step.** If the code must be rolled back, the old code has to work with the new schema.

This is why a rollback plan that says only "redeploy the previous version" is incomplete for any change that touches data. More in [[Architecture/solution-architecture-concepts/migration-patterns/data-migration|data migration]].

## Supporting practices

- **Graceful shutdown and connection draining**, so replacing instances drops no requests.
- **Health checks that reflect real readiness**, including dependencies the instance cannot work without.
- **Sufficient capacity** during the rollout: surge rather than running short.
- **Deployment markers on dashboards**, so cause and effect are visible.
- **Small, frequent changes.** A deployment containing one change is easy to reason about and to revert; one containing fifty is neither. This is the insight behind the [[DevOps/ci-cd/dora-metrics|DORA]] finding that speed and stability improve together.

## Related

- [[DevOps/ci-cd/pipeline-design|Pipeline design]]
- [[DevOps/ci-cd/release-and-versioning|Release and versioning]]
- [[Architecture/solution-architecture-concepts/migration-patterns/strangler-fig|Strangler fig]] — the same gradual idea applied to whole systems
- [[Kubernetes/concepts/L03-workloads/03-deployments|Kubernetes Deployments]]
- [[AWS/compute/ecs/README|Amazon ECS]] — blue-green with CodeDeploy

## Across the wiki

- [[AWS/solutions-architect-professional/domain-2/2.1-deployment-strategy|2.1 Deployment Strategy]] — deployment strategies (AWS)

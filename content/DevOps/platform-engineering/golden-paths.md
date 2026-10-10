---
title: Golden Paths
tags: [devops, platform-engineering, golden-path, paved-road, templates]
date: 2026-10-10
description: Designing golden paths — the supported, opinionated way to do a common task — what one contains, the difference from a mandate, guardrails versus gates, keeping services on the path as it evolves, and how to tell whether a path is working.
---

# Golden Paths

A golden path is the **supported, opinionated, well-lit way** to accomplish a common task in your organisation: creating a service, adding a database, shipping to production. It bundles the organisation's best current answer — the tools, the configuration, the security controls, the documentation — so that a team following it gets a production-ready result without having to make or even understand every decision.

The term comes from Spotify; Netflix calls the same thing a **paved road**. It is the core product of an [[DevOps/platform-engineering/internal-developer-platforms|internal developer platform]].

## The idea

Without golden paths, every team answers the same questions independently: which CI system, how to structure the Dockerfile, how to configure health checks, how to get credentials, how to expose metrics. The answers differ, some are wrong, and each takes days. The organisation ends up with as many ways to deploy a service as it has teams, and nobody can move between them.

A golden path makes the right thing the easy thing:

> Following the path should be faster and less effort than doing anything else.

That sentence is the design constraint. If the path is slower or more awkward than a team's own approach, they will rationally avoid it.

## Paved, not fenced

A golden path is a **recommendation with strong support**, not a mandate.

|                         | Golden path               | Off the path                                             |
| :---------------------- | :------------------------ | :------------------------------------------------------- |
| Allowed?                | Yes, and encouraged       | Yes                                                      |
| Who supports it         | The platform team         | The team that chose it                                   |
| Security and compliance | Built in and pre-approved | The team must demonstrate it meets the same requirements |
| Upgrades                | Largely automated         | The team's responsibility                                |

Teams with unusual needs — a machine-learning workload, a latency-critical service, an acquired codebase — may leave the path. They take on the work the path would have done for them. That trade keeps the platform honest: if many teams leave, the path is not good enough, and that is worth knowing. A mandate hides the signal.

What **is** mandatory are the outcomes: security baselines, compliance controls, cost tagging. The path is simply the cheapest way to meet them.

## What a golden path contains

A path is more than a template. For "a new HTTP service in production" it would include:

| Element                  | Example                                                                                                                                |
| :----------------------- | :------------------------------------------------------------------------------------------------------------------------------------- |
| **Scaffolding**          | A template that creates the repository with a working skeleton service                                                                 |
| **Build**                | A minimal, secure Dockerfile — [[Containers/dockerfile-best-practices\|Dockerfile best practices]]                                     |
| **Pipeline**             | A reusable workflow: test, scan, build, sign, deploy — [[DevOps/ci-cd/pipeline-design\|pipeline design]]                               |
| **Deployment**           | A manifest or a high-level workload resource; GitOps wiring                                                                            |
| **Runtime defaults**     | Resource requests, probes, autoscaling, disruption budgets, security context                                                           |
| **Identity and secrets** | A workload identity and a way to request secrets, with no static credentials                                                           |
| **Observability**        | Standard metrics, structured logs, tracing, a starter dashboard and alerts — [[Observability/prometheus/instrumenting\|instrumenting]] |
| **Catalogue entry**      | Ownership, links to docs and runbooks                                                                                                  |
| **Documentation**        | A tutorial that works on the first try, and an explanation of _why_ each choice was made                                               |
| **Support**              | A channel, an owner and a published support level                                                                                      |

The test of completeness: a new engineer, alone, can go from nothing to a service running in production with monitoring in **under an hour**, without asking anyone.

## Design principles

1. **Start from a real journey**, end to end. Pave "idea to production" for one service type before starting a second path.
2. **Opinionated defaults, few options.** Every choice exposed is a decision pushed onto the developer. Expose what legitimately varies — name, size, language — and decide the rest.
3. **Secure and compliant by default.** The path should produce a non-root container, least-privilege identity, encrypted storage and scanned images without anyone asking. Then security review becomes "are you on the path?".
4. **Explain the choices.** People accept defaults they understand. Document why, and what would be a valid reason to deviate.
5. **Transparent, not magic.** Developers can see the generated configuration and the pipeline steps. When something fails, they can find out why.
6. **Escape hatches.** Provide documented extension points for the 20% of cases the default does not fit, so teams need not abandon the whole path for one difference.
7. **Co-create it.** Build each path with one or two product teams and adopt their feedback. Paths designed in isolation miss real constraints.

## Guardrails over gates

| Gate                                                 | Guardrail                                                                |
| :--------------------------------------------------- | :----------------------------------------------------------------------- |
| A person reviews and approves before you may proceed | An automated check tells you immediately what is wrong and how to fix it |
| Slows everyone, every time                           | Invisible when you are doing the right thing                             |
| Scales with headcount                                | Scales with automation                                                   |

Implement policy as code that runs where developers work: in the editor, in the pull request, and at admission to the cluster. A blocked deployment should come with a message that says exactly what to change. See [[Kubernetes/eks/security/policy-management|policy management]] and [[Architecture/solution-architecture-concepts/security/shift-left|shift left]].

## The day-two problem

Scaffolding is the easy part. A template generates a repository once; a year later the organisation's standards have moved and three hundred services are frozen at whatever the template produced on the day they were created.

Design so that the path can evolve **after** services are created:

| Technique                            | How it keeps services current                                                                                                                                                                        |
| :----------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Reference, do not copy**           | Services call a versioned shared pipeline, base image, Helm chart or module rather than containing a copy                                                                                            |
| **Platform APIs**                    | Services declare intent in a small resource; the platform changes what it expands to — [[DevOps/platform-engineering/crossplane\|Crossplane]], [[Kubernetes/eks/automation/control-planes/kro\|kro]] |
| **Automated update pull requests**   | Bots propose version bumps for shared components across all repositories                                                                                                                             |
| **Scorecards**                       | The catalogue shows which services lag behind current standards                                                                                                                                      |
| **Versioned paths with deprecation** | Old versions are supported for a published period, with a migration guide                                                                                                                            |

The rule of thumb: anything likely to change should be **referenced**, and only what genuinely belongs to the service should be generated into its repository.

## How many paths

Few. Each path is a product with maintenance cost. Typical organisations need a handful:

- an HTTP or gRPC service,
- an asynchronous worker or event consumer,
- a scheduled job,
- a static or frontend web application,
- perhaps a data pipeline or a machine-learning service.

Per language, support the two or three that most teams use. A request for a new path should be met with "how many teams need this?".

## Is the path working?

| Signal                                                   | Meaning                                             |
| :------------------------------------------------------- | :-------------------------------------------------- |
| Time from "new service" to first production deployment   | The headline number; aim for hours, not weeks       |
| Share of new services created through the path           | Whether it is the easy option                       |
| Share of existing services on a current version          | Whether day-two works                               |
| Reasons teams leave the path                             | Your backlog                                        |
| Support requests per service                             | Whether the documentation and defaults are adequate |
| Developer satisfaction                                   | Whether people would choose it                      |
| Security and compliance findings, on versus off the path | Whether "secure by default" is real                 |

Review these with the product teams regularly. They feed the platform metrics in [[DevOps/platform-engineering/internal-developer-platforms|internal developer platforms]] and ultimately the [[DevOps/ci-cd/dora-metrics|DORA metrics]].

## Anti-patterns

| Anti-pattern                            | Result                                          |
| :-------------------------------------- | :---------------------------------------------- |
| The golden cage: no way off the path    | Shadow infrastructure, resentment, lost signal  |
| A template with fifty parameters        | The decisions were not actually made            |
| Scaffold once, never update             | Hundreds of services drifting from the standard |
| A path nobody on the platform team uses | It breaks in ways only real users find          |
| Documentation that is out of date       | The first experience fails, and trust is gone   |
| Paving a road nobody travels            | Effort spent on a rare use case                 |
| Hiding everything                       | Undebuggable failures                           |

## Related

- [[DevOps/platform-engineering/README|Platform engineering overview]]
- [[DevOps/platform-engineering/backstage|Backstage]] — software templates and scorecards
- [[DevOps/ci-cd/github-actions|GitHub Actions]] — reusable workflows as a shared pipeline
- [[DevOps/infrastructure-as-code/terraform|Terraform]] — modules as paved infrastructure
- [[DevOps/sre/README|SRE]] — golden paths are a primary tool for removing toil

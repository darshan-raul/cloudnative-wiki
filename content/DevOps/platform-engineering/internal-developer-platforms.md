---
title: Internal Developer Platforms
tags: [devops, platform-engineering, idp, developer-experience]
date: 2026-10-10
description: What an internal developer platform is and how to build one that gets used — the capabilities it provides, portal versus platform, reference architecture, platform as a product, the thinnest viable platform, team structure, metrics and the common ways platforms fail.
---

# Internal Developer Platforms

An internal developer platform (IDP) is the set of tools, services and automation that an organisation builds so its developers can ship and run software **without needing to be infrastructure experts and without waiting on another team**. It is the product of a platform engineering team; its customers are the organisation's own developers.

The problem it addresses is cognitive load. "You build it, you run it" gave teams ownership, and also handed every team Kubernetes, IAM, networking, CI, observability and security scanning to learn. A platform takes that undifferentiated work and offers it back as a paved, self-service path. The background is in [[DevOps/platform-engineering/README|platform engineering]].

## What a platform provides

| Capability                   | What a developer gets                                                                              |
| :--------------------------- | :------------------------------------------------------------------------------------------------- |
| **Service scaffolding**      | A new service, with repository, pipeline and deployment, from a template                           |
| **Build and delivery**       | A standard pipeline: build, test, scan, deploy — [[DevOps/ci-cd/pipeline-design\|pipeline design]] |
| **Runtime**                  | Somewhere to run it: a namespace, scaling, ingress, certificates                                   |
| **Infrastructure on demand** | A database, queue or bucket through a simple request                                               |
| **Environments**             | Dev, preview and production, created consistently                                                  |
| **Observability**            | Metrics, logs, traces and dashboards wired in by default — [[Observability]]                       |
| **Security and compliance**  | Identity, secrets, scanning and policy applied automatically                                       |
| **Service catalogue**        | Who owns what, what depends on what, where the docs and runbooks are                               |
| **Cost visibility**          | What each service costs                                                                            |

Not every platform needs all of these. Each one should exist because teams were demonstrably struggling without it.

## Portal and platform are different things

A frequent and expensive confusion:

- The **platform** is the machinery: the APIs, automation and infrastructure that actually do things.
- A **developer portal** is one _interface_ to it: a web UI with a catalogue, templates and documentation. [[DevOps/platform-engineering/backstage|Backstage]] is the best-known example.

A portal in front of nothing is a wiki with a nicer skin. Build the capabilities first. Many effective platforms are consumed entirely through Git, a CLI and a few custom resources, and add a portal later — or never.

## Reference architecture

```
        ┌──────────────── developer interfaces ────────────────┐
        │  Git / pull requests    CLI    portal    IDE          │
        └───────────────────────────┬───────────────────────────┘
                                    │  a small, stable API
        ┌───────────────────────────▼───────────────────────────┐
        │ platform orchestration: templates, workload specs,     │
        │ compositions, policy                                   │
        └───────┬─────────────┬─────────────┬───────────────────┘
                ▼             ▼             ▼
        CI/CD and GitOps   runtime      infrastructure control
        (pipelines,        (Kubernetes, (Terraform, Crossplane,
         Argo CD, Flux)     serverless)  cloud APIs)
                ▼             ▼             ▼
        ┌────────────────────────────────────────────────────────┐
        │ cross-cutting: identity · secrets · policy ·           │
        │ observability · cost                                   │
        └────────────────────────────────────────────────────────┘
```

The most important design element is the **API in the middle**: the small set of things a developer specifies. A good platform API asks for intent — "a web service, this image, two replicas, a Postgres database, small" — and derives the dozens of resources behind it. On Kubernetes that API is usually a custom resource, implemented with [[DevOps/platform-engineering/crossplane|Crossplane]], [[Kubernetes/eks/automation/control-planes/kro|kro]], or a Helm chart with a narrow values schema.

## Platform as a product

Platforms fail far more often for product reasons than technical ones. Treat the platform exactly as you would an external product.

- **Know your users.** Interview developers, watch them work, sit in their incident reviews. Find where they lose time; do not assume.
- **Adoption is voluntary.** Mandating a platform hides whether it is any good. If teams choose to go around it, that is information. The goal is that the paved road is so much easier that few leave it.
- **Have a product manager** — a person or a clearly owned role — who decides what _not_ to build.
- **Publish a roadmap and changelog**, and deprecate with notice and a migration path, as for any API.
- **Provide documentation, onboarding and support.** A capability nobody can figure out does not exist.
- **Measure**, as below.

See [[DevOps/platform-engineering/golden-paths|golden paths]] for how to design the paths themselves.

## Thinnest viable platform

Start with the smallest platform that removes real pain — sometimes a documented template repository, a shared pipeline and a wiki page. Team Topologies calls this the **thinnest viable platform**.

A sound order of work:

1. **Find the most common painful journey.** Usually "create a new service and get it to production", which often takes weeks.
2. **Pave that one journey end to end** for one or two willing teams. Depth before breadth.
3. **Measure the before and after.**
4. **Iterate with those teams**, then widen adoption.
5. **Add the next capability** only when a need is clear.

Resist building a complete abstraction over everything on day one. Platforms designed in isolation for a year and then unveiled are the ones nobody adopts.

## Abstraction: how much to hide

| Too little                                       | Too much                                                     |
| :----------------------------------------------- | :----------------------------------------------------------- |
| Developers still write hundreds of lines of YAML | A black box nobody can debug at 3 a.m.                       |
| Every team's setup is different                  | Legitimate needs cannot be met; teams go around the platform |
| The platform is just a pile of tools             | The platform team becomes a bottleneck for every exception   |

Aim for **layered** abstraction: a simple default interface that covers most cases, with documented escape hatches to the layer beneath for the rest. Developers should be able to see what the platform generated on their behalf, even if they rarely need to.

## Team structure

In the Team Topologies model:

- **Stream-aligned teams** own products end to end. They are the customers.
- The **platform team** provides self-service capabilities that reduce their load.
- **Enabling teams** help others adopt new practices, then step away.

The platform team's interaction mode should be **X-as-a-service**: teams consume it without filing tickets. A platform team that fulfils requests by hand has recreated the operations department it was meant to replace. Keep it small, staffed with people who have built products, and resistant to becoming a general "DevOps team" that does other teams' work. The distinctions are drawn in [[DevOps/platform-engineering/platform-vs-devops-vs-sre|platform engineering vs DevOps vs SRE]].

## Measuring it

| Category         | Measure                                                                                                    |
| :--------------- | :--------------------------------------------------------------------------------------------------------- |
| **Adoption**     | Share of services on the golden path; active users; teams that left, and why                               |
| **Speed**        | Time to first deployment for a new service; time for a new engineer's first production change              |
| **Delivery**     | [[DevOps/ci-cd/dora-metrics\|DORA metrics]] for teams on and off the platform                              |
| **Toil removed** | Tickets to the platform team per week — should fall as self-service grows                                  |
| **Satisfaction** | Regular short developer surveys; qualitative interviews                                                    |
| **Reliability**  | The platform's own [[DevOps/sre/slos-and-error-budgets\|SLOs]]: pipeline availability, deploy success rate |
| **Cost**         | Infrastructure cost per service; platform team cost against time saved                                     |

The platform is production infrastructure for everyone. It needs its own on-call, incident process and error budgets.

## How platforms fail

| Failure                                 | Cause                                                                  |
| :-------------------------------------- | :--------------------------------------------------------------------- |
| Built, and nobody uses it               | No user research; solved the platform team's problems, not developers' |
| A portal with nothing behind it         | Started with the UI                                                    |
| The platform team is a ticket queue     | Not self-service                                                       |
| Everything must go through the platform | Mandates instead of quality; no escape hatches                         |
| One team's tools rebranded              | "Platform" used as a new name for the infrastructure team              |
| Abstraction that leaks                  | Developers need to understand everything underneath anyway             |
| Never finished                          | Tried to cover every use case before shipping anything                 |
| Abandoned capabilities                  | Built but not maintained, documented or supported                      |

## Buy, assemble or build

| Option                     | Examples                                                      | Trade-off                                         |
| :------------------------- | :------------------------------------------------------------ | :------------------------------------------------ |
| PaaS                       | Heroku-style platforms, Cloud Run, App Runner, Container Apps | Fastest; limited flexibility                      |
| Commercial IDP products    | Humanitec, Port, Cortex, managed Backstage                    | Less to build; fits their model, not always yours |
| Assembled from open source | Kubernetes, Argo CD, Crossplane, Backstage                    | Fits exactly; you operate and integrate it all    |

For a small organisation, a managed PaaS **is** the platform, and building your own is a distraction. The case for assembling grows with the number of teams and the specificity of requirements.

## Related

- [[DevOps/platform-engineering/README|Platform engineering overview]]
- [[DevOps/platform-engineering/golden-paths|Golden paths]]
- [[DevOps/platform-engineering/backstage|Backstage]]
- [[Kubernetes/guides/non-functional/multi-tenancy|Kubernetes multi-tenancy]]
- [[DevOps/infrastructure-as-code/README|Infrastructure as code]]
- [CNCF platforms white paper](https://tag-app-delivery.cncf.io/whitepapers/platforms/)

## Further reading

- [Internal Developer Platforms (video)](https://www.youtube.com/watch?v=uWhbgHphc3s)

---
title: Backstage
tags:
  [devops, platform-engineering, backstage, developer-portal, service-catalog]
date: 2026-10-10
description: Backstage as a developer portal framework — the software catalog and its entity model, software templates, TechDocs, plugins, the real cost of running it, alternatives, and an adoption path that starts with the catalog.
---

# Backstage

Backstage is an open-source framework for building a **developer portal**: one place where engineers find every service, who owns it, its documentation, its pipelines and its health, and where they start new work from templates. Spotify created it and donated it to the CNCF.

The word _framework_ matters. Backstage is not a product you install and use. It is a TypeScript application you build, extend with plugins and operate yourself. It is also a portal, not a platform: it is the front door to capabilities that must already exist — see [[DevOps/platform-engineering/internal-developer-platforms|internal developer platforms]].

## The four core features

| Feature                | What it does                                                                                                          |
| :--------------------- | :-------------------------------------------------------------------------------------------------------------------- |
| **Software Catalog**   | An inventory of all software — services, libraries, websites, pipelines, resources — with ownership and relationships |
| **Software Templates** | "Create" buttons that scaffold a new component from a template and set up everything around it                        |
| **TechDocs**           | Documentation written in Markdown next to the code, rendered in the portal                                            |
| **Search**             | One search across the catalog, documentation and plugin data                                                          |

Everything else comes from **plugins**, which add pages and cards for other systems.

## The Software Catalog

The catalog is the foundation, and often the most valuable part. It answers questions that are otherwise surprisingly hard: who owns this service? What depends on it? Where is its runbook? Who do I page?

Entities are described in YAML files that live in each repository:

```yaml
# catalog-info.yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: checkout-api
  description: Handles checkout and payment orchestration
  annotations:
    github.com/project-slug: example/checkout-api
    backstage.io/techdocs-ref: dir:.
    backstage.io/kubernetes-id: checkout-api
    pagerduty.com/service-id: PABC123
  tags: [go, payments]
  links:
    - url: https://grafana.example.com/d/checkout
      title: Dashboard
spec:
  type: service
  lifecycle: production
  owner: group:payments
  system: checkout
  providesApis: [checkout-api]
  consumesApis: [payments-api]
  dependsOn: [resource:orders-db]
```

| Kind            | Represents                                                         |
| :-------------- | :----------------------------------------------------------------- |
| `Component`     | A piece of software: a service, website or library                 |
| `API`           | An interface a component exposes: OpenAPI, gRPC, AsyncAPI, GraphQL |
| `Resource`      | Infrastructure a component needs: a database, bucket, queue        |
| `System`        | A group of components that together deliver a capability           |
| `Domain`        | A business area grouping systems                                   |
| `Group`, `User` | The organisation, usually imported from an identity provider       |
| `Template`      | A scaffolder template                                              |

Because the descriptor lives with the code, the team that owns the service owns its metadata, and changes are reviewed in pull requests. Entity providers can also ingest from GitHub organisations, cloud accounts, Kubernetes or an identity provider.

**The catalog is only as good as its data.** An inventory that is 60% complete, with stale owners, is trusted by nobody. Completeness and accuracy are the real work: make registration part of the service template, validate descriptors in CI, and track coverage.

## Software Templates

A template is a form plus a list of actions. This is how [[DevOps/platform-engineering/golden-paths|golden paths]] become a button.

```yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: go-service
  title: Go HTTP service
spec:
  owner: group:platform
  type: service
  parameters:
    - title: Service details
      required: [name, owner]
      properties:
        name:
          type: string
          pattern: "^[a-z][a-z0-9-]{2,30}$"
        owner:
          type: string
          ui:field: OwnerPicker
  steps:
    - id: fetch
      action: fetch:template
      input:
        url: ./skeleton
        values:
          name: ${{ parameters.name }}
          owner: ${{ parameters.owner }}
    - id: publish
      action: publish:github
      input:
        repoUrl: github.com?owner=example&repo=${{ parameters.name }}
        defaultBranch: main
    - id: register
      action: catalog:register
      input:
        repoContentsUrl: ${{ steps.publish.output.repoContentsUrl }}
        catalogInfoPath: /catalog-info.yaml
  output:
    links:
      - title: Repository
        url: ${{ steps.publish.output.remoteUrl }}
```

Actions can create repositories, open pull requests, trigger pipelines, call cloud APIs or create Kubernetes resources. Keep templates thin: have them create a repository that **references** shared pipelines, charts and modules rather than copying them in, so services do not freeze at the moment of creation.

## TechDocs

Documentation is written in Markdown in the service's repository, built with MkDocs, and published to object storage for the portal to serve. Docs live beside the code, change in the same pull request, and are found through the same search as everything else. In production, build them in CI and publish to a bucket rather than generating on demand.

## Plugins

Plugins bring other tools into the service's page, so an engineer sees one view instead of ten tabs:

| Area                 | Typical plugins                                                                                                |
| :------------------- | :------------------------------------------------------------------------------------------------------------- |
| Source and CI/CD     | GitHub or GitLab pull requests, Actions runs, [[Kubernetes/eks/automation/gitops/argocd\|Argo CD]] sync status |
| Runtime              | Kubernetes workloads and pod status                                                                            |
| Observability        | [[Observability/grafana\|Grafana]] dashboards, Prometheus alerts                                               |
| Incidents            | PagerDuty or Opsgenie: who is on call, open incidents                                                          |
| Quality and security | Code quality, vulnerability findings, dependency status                                                        |
| Cost                 | Cloud cost per service                                                                                         |
| Standards            | Scorecards that check each service against organisation rules                                                  |

**Scorecards** deserve a mention: they turn standards into visible, measurable checks — has an owner, has a runbook, is on the current base image, has [[DevOps/sre/slos-and-error-budgets|SLOs]] defined — and make drift from the golden path visible without anyone policing it.

There are hundreds of community plugins of varying quality and maintenance. Each one adopted is a dependency to keep working across upgrades.

## The cost of running it

Be clear-eyed about this before starting.

- **It is a software project.** You own a Node.js and React application: a backend, a PostgreSQL database, authentication against your identity provider, and a deployment. Running it is ordinary [[Kubernetes/concepts/L03-workloads/03-deployments|Deployment]] work; maintaining it is not.
- **Upgrades are frequent.** Backstage releases monthly and moves quickly. Falling behind makes the next upgrade harder.
- **It needs dedicated engineers** with frontend and TypeScript skills — commonly two or more — which many infrastructure teams do not have.
- **Customisation is code**, not configuration.
- **Permissions** must be designed: who may see which entities and run which templates.

Many organisations have underestimated this, stood up a portal, and then found they lacked the capacity to keep it useful. Adoption figures for self-hosted Backstage inside companies are often low for exactly this reason.

## Alternatives

| Option                                                                | Trade-off                                                                     |
| :-------------------------------------------------------------------- | :---------------------------------------------------------------------------- |
| **Managed Backstage** (Roadie, Spotify Portal, Red Hat Developer Hub) | Backstage's model without operating it; less freedom                          |
| **Commercial portals** (Port, Cortex, OpsLevel)                       | Faster to value; configuration over code; a subscription and their data model |
| **No portal**                                                         | Git, a CLI and good documentation — often right for small organisations       |

Below a few dozen engineers, a portal is rarely worth it. A spreadsheet of services and owners plus a template repository gets most of the benefit.

## An adoption path

1. **Start with the catalog, and only the catalog.** Get every production service registered with an accurate owner. This alone is valuable during incidents.
2. **Wire in what people look up most**: on-call, dashboards, repository, pipeline status.
3. **Add TechDocs** so documentation becomes findable.
4. **Add one template** for the most common service type, built on an existing, working golden path.
5. **Add scorecards** once standards are agreed.
6. **Measure usage** — weekly active users, searches, templates run — and talk to the people who are not using it.

Do not begin by building custom plugins, and do not launch the portal before the capabilities behind it work.

## Related

- [[DevOps/platform-engineering/README|Platform engineering overview]]
- [[DevOps/platform-engineering/golden-paths|Golden paths]]
- [[DevOps/platform-engineering/internal-developer-platforms|Internal developer platforms]]
- [[Architecture/solution-architecture-concepts/authentication/stage3/01-oidc-fundamentals|OIDC]] — how portal sign-in works
- [Backstage documentation](https://backstage.io/docs/overview/what-is-backstage)

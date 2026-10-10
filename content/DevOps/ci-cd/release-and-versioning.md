---
title: Release and Versioning
tags: [devops, ci-cd, versioning, semver, releases, artifacts]
date: 2026-10-10
description: How to version, tag and promote what you ship — semantic versioning and its limits, calendar versioning, commit-based automation, immutable artifacts and digests, promotion across environments, changelogs, and dependency update policy.
---

# Release and Versioning

A version is a name for an exact, immutable set of bits. Everything else about release management follows from taking that sentence seriously: if you cannot say precisely what is running in production and reproduce it, you cannot reason about rollbacks, audits or bugs.

## What needs a version

| Thing                    | Versioned how                                                          |
| :----------------------- | :--------------------------------------------------------------------- |
| Source code              | A Git commit; releases marked with an annotated, signed tag            |
| Build artifact           | A content digest; a human-readable tag pointing to it                  |
| Deployment configuration | Its own Git history (a Helm chart version, a Kustomize overlay commit) |
| API                      | A contract version, independent of the implementation's version        |
| Database schema          | Ordered, numbered migrations                                           |
| Infrastructure modules   | Semantic versions on the module repository                             |

These move at different rates and should not be forced to share one number.

## Versioning schemes

### Semantic versioning

`MAJOR.MINOR.PATCH`, with a precise promise to consumers:

| Part      | Increment when                            |
| :-------- | :---------------------------------------- |
| **MAJOR** | You make an incompatible change           |
| **MINOR** | You add functionality in a compatible way |
| **PATCH** | You fix bugs in a compatible way          |

Pre-releases (`2.0.0-rc.1`) sort before the release; build metadata (`+build.47`) is ignored in comparisons. `0.x` versions make no compatibility promise.

SemVer is a communication tool for things **other people depend on**: libraries, APIs, Helm charts, Terraform modules, CLI tools. Its limits are worth knowing. It relies on humans judging what "breaking" means; any behaviour someone depends on can break them, documented or not. And "major versions are scary" leads projects to avoid them, piling up deprecated behaviour instead.

### Calendar versioning

`2026.10.1` or `26.04`. It says when something was released and nothing about compatibility. It suits products released on a schedule and anything where "how old is this?" matters more than "is it compatible?" — operating systems, large applications.

### Just the commit

For an internally deployed service with no external consumers, SemVer adds ceremony without information. The Git SHA, or a build number, is a complete and honest version: `checkout-api:3f9a2c1`. Many teams use the SHA for images and reserve SemVer for their public API and shared libraries.

## Automating the number

Deciding version numbers by hand is error-prone. **Conventional commits** encode the intent in the commit message:

```
feat(cart): add saved-for-later list          → MINOR
fix(checkout): handle expired cards           → PATCH
feat(api)!: remove legacy v1 endpoints        → MAJOR
BREAKING CHANGE: /v1/orders is removed.
```

Tools such as semantic-release, release-please and Changesets read the history since the last tag, compute the next version, generate the changelog, create the tag and publish. A release becomes a consequence of merging, not a manual ritual. The commit conventions are covered in [[DevOps/ci-cd/git|Git strategy]].

## Immutable artifacts

1. **Build once.** One build per commit produces one artifact — see [[DevOps/ci-cd/pipeline-design|pipeline design]].
2. **Identify by digest.** A tag such as `1.4.2` is a movable pointer; `sha256:9b2c…` is the content itself. Deploy by digest, and make tags immutable in the registry so nobody can overwrite `1.4.2` — [[Containers/registries|registries]].
3. **Never use `latest`** for anything deployed. It is not a version, and two machines can disagree about what it means.
4. **Attach evidence to the digest**: signature, SBOM, build provenance, scan results — [[Kubernetes/concepts/L07-security/04-admission-policy/23-sboms|SBOMs]] and the [[DevOps/devsecops/README|DevSecOps curriculum]].
5. **Embed the version in the running software**: a `/version` endpoint, a start-up log line and a `build_info` metric with the commit, so any running instance can be traced to its source — [[Observability/prometheus/instrumenting|instrumenting]].

## Promotion

The same artifact moves through environments; only its **configuration** and the **pointer** change.

```
commit 3f9a2c1 ─► build ─► image @sha256:9b2c… ─► dev ─► staging ─► production
                                 (never rebuilt)     ▲        ▲          ▲
                                                     └── each environment's config references the digest
```

With [[Kubernetes/guides/delivery/gitops/basics|GitOps]], promotion is a commit that changes the digest in the next environment's configuration — reviewable, auditable and revertible. Promotion criteria should be explicit: tests passed, scans clean, healthy in the previous environment for a set time. Rolling back is promoting the previous digest.

Keep enough history to roll back: registry lifecycle policies must not delete what an environment still references, or might need to return to.

## Changelogs and release notes

Two audiences, two documents:

- A **changelog** is for engineers: every notable change, grouped as added, changed, deprecated, removed, fixed and security. Generate it from commits or pull-request labels.
- **Release notes** are for users: what is new, what they must do, and what might break — written by a person.

Announce **deprecations** early and with a removal date, and provide a migration path. Breaking changes that surprise users are the result of process failure, not of version numbers.

## Versioning APIs

The implementation can deploy fifty times a day; the contract should change rarely.

- Prefer **additive, backward-compatible** changes: new optional fields, new endpoints.
- When a breaking change is unavoidable, run both versions in parallel (`/v1`, `/v2`, or a version header) with a published sunset date, and measure remaining `v1` usage before removal.
- Consumer-driven contract tests catch accidental breaks before release.

See [[Architecture/solution-architecture-concepts/api-design/README|API design]] and [[Architecture/solution-architecture-concepts/software-engineering-concepts/api-error-codes|API error codes]].

## Consuming other people's versions

| Practice                                              | Why                                                                         |
| :---------------------------------------------------- | :-------------------------------------------------------------------------- |
| **Commit lockfiles**                                  | Builds resolve the same dependency versions every time                      |
| **Pin base images and actions** to a digest or commit | A mutable tag can change underneath you, or be hijacked                     |
| **Automate updates** (Renovate, Dependabot)           | Pinning without updating is how you end up years behind on security fixes   |
| **Small, frequent upgrades**                          | One minor version at a time is easy; five majors at once is a project       |
| **Group and schedule** updates                        | Avoid a flood of pull requests; auto-merge low-risk patches when tests pass |
| **Know your tree**                                    | An SBOM tells you whether a newly announced vulnerability affects you       |

Range specifiers are worth reading carefully: `^1.2.3` allows minor and patch updates, `~1.2.3` allows patches only. A lockfile makes the range a statement of intent rather than something resolved differently on each build.

## Release cadence

| Model                           | Suits                                                            |
| :------------------------------ | :--------------------------------------------------------------- |
| Continuous deployment           | Services you operate; every green commit ships                   |
| Release trains (fixed schedule) | Coordinated products, mobile apps, anything with external review |
| Long-term support branches      | Software that customers install and upgrade slowly               |

For operated services, releasing more often in smaller pieces lowers risk — the evidence is summarised in [[DevOps/ci-cd/dora-metrics|DORA metrics]]. For installed software, maintaining several supported versions is a real cost; decide the support window deliberately and publish it.

## Related

- [[DevOps/ci-cd/README|CI/CD overview]]
- [[DevOps/ci-cd/deployment-strategies|Deployment strategies]]
- [[Kubernetes/guides/delivery/templating-patching/helm/charts|Helm charts]] — chart version versus app version
- [[Kubernetes/guides/non-functional/deprecations|Kubernetes API deprecations]]
- [Semantic Versioning 2.0.0](https://semver.org/)

## Across the wiki

- [[Linux/packaging/README|Linux Packaging]] — packaging (Linux)
- [[Containers/images-and-layers|Container Images and Layers]] — packaging (Containers)
- [[Linux/concepts/05-package-management|05 — Package Management]] — packaging (Linux)

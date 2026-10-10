---
title: Pipeline Design
tags: [devops, ci-cd, pipelines, continuous-delivery]
date: 2026-10-10
description: Designing a delivery pipeline that is fast, trustworthy and safe — stages and their order, build once and promote, test strategy, speed techniques, environments and gates, pipeline security, flaky tests and the metrics that show whether it is working.
---

# Pipeline Design

A pipeline is the path every change takes from a commit to production. Its job is to answer one question as quickly and reliably as possible: **is this change safe to release?** — and then to release it the same way every time.

A good pipeline is boring. Changes flow through it many times a day without anyone thinking about it. This note is tool-independent; concrete implementations are in [[DevOps/ci-cd/github-actions|GitHub Actions]] and [[Kubernetes/eks/automation/continuous-delivery/codepipeline|CodePipeline]].

## Vocabulary

| Term                       | Meaning                                                                            |
| :------------------------- | :--------------------------------------------------------------------------------- |
| **Continuous integration** | Everyone merges to the main branch at least daily; every merge is built and tested |
| **Continuous delivery**    | Every change that passes the pipeline _can_ be released at the push of a button    |
| **Continuous deployment**  | Every change that passes _is_ released, with no manual step                        |

Continuous integration is a team practice, not a tool. Long-lived branches with a CI server attached are not continuous integration — see [[DevOps/ci-cd/git|Git strategy]].

## Stages

```
commit ─► [ build ]─►[ fast checks ]─►[ package ]─►[ slower tests ]─►[ deploy staging ]─►[ verify ]─►[ deploy prod ]─►[ verify ]
            compile     lint, unit,      image,       integration,      same artifact       smoke,     progressive       health,
                        SAST, secrets    SBOM, sign   contract, e2e                         e2e        rollout           SLOs
          └───────── on every pull request ─────────┘└──────────────── on merge to main ───────────────────────────────┘
```

Order stages by **cost and likelihood of failure**: cheap checks that fail often go first. A lint error should be reported in seconds, not after a twenty-minute integration suite.

## Principles

**1. Build once, promote the same artifact.** Compile and package exactly once. The artifact that passed tests in staging is the one deployed to production, identified by an immutable digest. Rebuilding per environment means production runs something that was never tested. Environment differences are **configuration**, injected at deploy time — the [[Architecture/solution-architecture-concepts/api-design/12-factor-app|twelve-factor]] approach. See [[Containers/registries|registries]] for digests and [[DevOps/ci-cd/release-and-versioning|release and versioning]].

**2. Fast feedback.** Aim for under ten minutes from push to a verdict on a pull request. Beyond that, people stop waiting, batch their changes and context-switch, and the pipeline's value falls sharply.

**3. Keep the main branch releasable.** A red main branch blocks everyone. Fix or revert immediately; do not pile changes on top. Incomplete work ships behind feature flags rather than living on a branch.

**4. Everything as code.** The pipeline definition lives in the repository and is reviewed like any other change. So do infrastructure and configuration — [[DevOps/infrastructure-as-code/README|infrastructure as code]].

**5. Reproducible.** Pin tool versions, base images and dependencies. The same commit should produce the same result next month.

**6. Fail loudly and specifically.** A failure message should say what broke and how to reproduce it locally.

## Test strategy

| Layer           | Scope                                       | Speed        | Share of tests |
| :-------------- | :------------------------------------------ | :----------- | :------------- |
| Static analysis | Types, lint, formatting, security patterns  | Seconds      | —              |
| Unit            | One function or class, no I/O               | Milliseconds | Most           |
| Integration     | A service with its real database or queue   | Seconds      | Some           |
| Contract        | Agreement between a consumer and a provider | Seconds      | Some           |
| End-to-end      | A user journey through the deployed system  | Minutes      | Few            |

The pyramid shape matters because cost and flakiness rise with scope. A handful of end-to-end tests covering critical journeys is valuable; hundreds become a slow, unreliable gate. Contract tests replace many of them by verifying service boundaries without running everything together. Fundamentals are in [[Architecture/solution-architecture-concepts/software-engineering-concepts/testing/README|testing strategies]] and [[Architecture/solution-architecture-concepts/software-engineering-concepts/testing/test-doubles-mocks-stubs-fakes|test doubles]].

Non-functional checks belong too: [[Architecture/solution-architecture-concepts/performance-testing|performance tests]] on a schedule or before release, and security scans throughout — [[DevOps/devsecops/README|DevSecOps]].

## Making it fast

| Technique                     | How                                                                                          |
| :---------------------------- | :------------------------------------------------------------------------------------------- |
| **Parallelise**               | Independent jobs run concurrently; split test suites across runners                          |
| **Cache**                     | Dependencies, build outputs, container layers — keyed on lockfiles                           |
| **Run only what is affected** | Path filters, or a build system that understands the dependency graph (Bazel, Nx, Turborepo) |
| **Fail fast**                 | Cancel the rest when a required job fails; cancel superseded runs                            |
| **Right-size runners**        | More cores are usually cheaper than waiting engineers                                        |
| **Pre-built images**          | Bake tools into the CI image instead of installing them on every run                         |
| **Move slow suites later**    | Nightly or post-merge, not blocking every pull request                                       |

Measure before optimising: most pipelines have one or two stages responsible for most of the time.

## Environments and gates

- **Ephemeral environments** per pull request give reviewers a running system and remove contention for shared staging.
- **Staging should resemble production** in topology and configuration, even if smaller. Differences are where surprises come from.
- **Promotion gates** are automated wherever possible: tests passed, scans clean, staging healthy for N minutes. Manual approval is appropriate for some production changes, but a gate that is always clicked through without looking adds delay and no safety.
- **Deployment is progressive**: a small share of traffic first, automated analysis, then the rest — [[DevOps/ci-cd/deployment-strategies|deployment strategies]].
- **Database changes** ship separately from code, using [[Architecture/solution-architecture-concepts/migration-patterns/expand-contract|expand and contract]], so either can be rolled back.

## Push or pull deployment

|                     | Push (the pipeline deploys)              | Pull (GitOps)                                                             |
| :------------------ | :--------------------------------------- | :------------------------------------------------------------------------ |
| Mechanism           | CI runs `kubectl`, `helm` or an API call | CI commits the new version to Git; a controller in the cluster applies it |
| Cluster credentials | Held by CI                               | Never leave the cluster                                                   |
| Drift               | Uncorrected between deployments          | Continuously reconciled                                                   |
| Audit               | Pipeline logs                            | Git history                                                               |

For Kubernetes, pull is the stronger default — [[Kubernetes/guides/delivery/gitops/basics|GitOps basics]], [[Kubernetes/eks/automation/gitops/argocd|Argo CD]], [[Kubernetes/eks/automation/gitops/flux|Flux]].

## Pipeline security

The pipeline can deploy to production, so it is a prime target.

- **No long-lived secrets.** Use OIDC federation to obtain short-lived cloud credentials per run.
- **Least privilege per job.** A test job needs no deploy rights. Separate roles for pull-request builds and main-branch builds.
- **Untrusted code is untrusted.** Builds from forks must not see secrets or run on privileged runners.
- **Pin third-party actions and plugins** to a commit hash, not a mutable tag.
- **Ephemeral, isolated runners**, so one job cannot poison the next.
- **Sign what you build** and record provenance; verify at deploy time.
- **Protect the main branch and the pipeline definition** with required reviews.

These are covered step by step in the [[DevOps/devsecops/README|DevSecOps curriculum]], including [[DevOps/devsecops/stage1-code/06-secrets-detection|secrets detection]] and [[DevOps/devsecops/stage2-build/09-container-image-scanning|image scanning]].

## Flaky tests

A flaky test passes and fails without a code change. It is worse than no test: people learn to re-run until green, and real failures get re-run too.

- **Detect**: track pass rates per test; flag anything that fails and then passes on retry.
- **Quarantine quickly**: move it out of the blocking path, with a ticket and an owner.
- **Fix the cause**: shared state between tests, timing assumptions and `sleep`, reliance on external services, order dependence, unseeded randomness.
- **Do not normalise automatic retries** of whole suites. They hide the problem and double the time.

## Is it working?

| Measure                       | What good looks like   |
| :---------------------------- | :--------------------- |
| Time from push to verdict     | Under ten minutes      |
| Time from merge to production | Under an hour          |
| Main-branch success rate      | Above about 90%        |
| Time to restore a red main    | Minutes                |
| Flaky-test rate               | Near zero, and tracked |
| Queue time for runners        | Negligible             |

These roll up into the delivery metrics in [[DevOps/ci-cd/dora-metrics|DORA metrics]].

## Anti-patterns

| Anti-pattern                                    | Why it hurts                                                 |
| :---------------------------------------------- | :----------------------------------------------------------- |
| Rebuilding the artifact for each environment    | Production runs untested bits                                |
| A pipeline only one person understands          | It becomes a bottleneck and a risk                           |
| Manual steps "just for production"              | The least-rehearsed path is used for the riskiest deployment |
| Deploying on Fridays is forbidden               | A symptom: deployments are not safe enough                   |
| Hundreds of lines of shell inside pipeline YAML | Untestable; move logic into scripts that run locally too     |
| One giant pipeline for an entire monorepo       | Everyone waits for everything                                |
| Skipping the pipeline for hotfixes              | The emergency path is the one that most needs to be reliable |

## Related

- [[DevOps/ci-cd/README|CI/CD overview]]
- [[Kubernetes/guides/delivery/ci-cd-integration|CI/CD integration for Kubernetes]]
- [[Kubernetes/guides/delivery/pipeline-workflows/tekton-pipelines|Tekton]] and [[Kubernetes/guides/delivery/pipeline-workflows/argo-workflows|Argo Workflows]]
- [[DevOps/platform-engineering/golden-paths|Golden paths]] — pipelines as a reusable platform product

## Across the wiki

- [[Kubernetes/guides/delivery/templating-patching/helm/cicd|Helm CI/CD]] — CI/CD pipelines (Kubernetes)
- [[AI/evals|Evaluating LLM Systems]] — testing (AI)
- [[Kubernetes/guides/delivery/templating-patching/helm/testing|Helm Chart Testing]] — testing (Kubernetes)
- [[Architecture/solution-architecture-concepts/software-engineering-concepts/testing/unit-testing|Unit Testing Principles & Test-Driven Development (TDD)]] — testing (Architecture)

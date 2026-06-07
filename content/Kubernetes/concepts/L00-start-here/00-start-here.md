---
title: "L00 — Start Here"
tags: [kubernetes, k8s, start-here, prerequisites, learning-path]
date: 2026-06-06
description: Prerequisites and the mental model for the Kubernetes concepts section
---

# L00 — Start Here 🚦

The Kubernetes concepts section is a **top-down learning path** — 10 levels, each building on the previous. Before you dive in, set the right mental model and prerequisites.

## What Kubernetes actually is

> Kubernetes is a **portable, extensible, open-source platform for managing containerized workloads** and services, that facilitates both declarative configuration and automation. (CNCF definition)

**Google open-sourced the Kubernetes project in 2014.** The name comes from Greek, meaning "helmsman" or "pilot". The "K8s" abbreviation counts the 8 letters between K and s.

**The mental model in one sentence:** *you describe the desired state, Kubernetes continuously drives the actual state to match.*

That's it. Everything in this section is the details of how that loop works, who participates, and what tools you can build on top.

## What Kubernetes gives you

- **Service discovery and load balancing** — DNS names or IPs, traffic distributed
- **Storage orchestration** — auto-mount local, cloud, or network storage
- **Automated rollouts and rollbacks** — describe desired state, k8s rolls the change out
- **Automatic bin packing** — schedule containers based on CPU/memory requests
- **Self-healing** — restart failed containers, replace unresponsive ones, don't advertise until ready
- **Secret and configuration management** — store and inject sensitive data without rebuilding images
- **Batch execution** — manage Jobs and CronJobs alongside services
- **Horizontal scaling** — `kubectl scale`, or auto-scale on CPU/custom metrics
- **IPv4/IPv6 dual-stack** — assign both address families to pods and services
- **Designed for extensibility** — add features via CRDs, operators, admission webhooks

## What Kubernetes is NOT

- **Not a PaaS.** No built-in app runtime, no source build, no middleware, no opinionated CI/CD.
- **Not just an orchestrator.** Orchestration = "first do A, then B". Kubernetes is a set of **independent composable control processes** driving state toward desired — there's no central workflow engine.
- **Not opinionated about logging, monitoring, alerting.** It exposes the metrics and event stream, you bring the stack.
- **Not a configuration language.** The API is the contract; tools like Helm/Kustomize produce manifests for it.

## Prerequisites

You should be comfortable with these **before** starting L01:

| Topic | Why it matters |
|-------|----------------|
| **Linux command line** | You'll be SSHing into nodes, reading logs, running `kubectl` constantly |
| **Containers (Docker / OCI)** | Pods run containers — know what an image, layer, and registry are |
| **YAML syntax** | Every Kubernetes manifest is YAML; you need to read and write it fluently |
| **Networking basics (IP, port, DNS, TLS)** | L04 is unreadable without this |
| **A vague idea of what an API is** | The Kubernetes API is the product; "I know what a REST API is" is enough |

Helpful but not required: distributed systems basics, an etcd primer, a programming language (Go, Python) for the L09 advanced topics.

## How to read this section

The folder numbers are intentional — **00 → 09 in order**. Each level:

1. Tells you what you'll understand after reading it
2. Lists every note with a status (✅ Core / 🟡 Outline / ⚪ Stub)
3. Suggests a reading order
4. Links to the next level

If you already know k8s and want reference material, jump to the level you need. The wikilinks back to prerequisites are explicit.

## The big picture

```
┌─────────────────────────────────────────────────┐
│  L00  Start Here  ← you are here                │
│  L01  Architecture                              │
│  L02  Objects                                   │
│  L03  Workloads                                 │
│  L04  Services & Networking                     │
│  L05  Config & Storage                          │
│  L06  Scheduling & Scaling                      │
│  L07  Security                                  │
│  L08  Operations                                │
│  L09  Advanced (operators, internals)           │
└─────────────────────────────────────────────────┘
          ↓
    [EKS]  [Guides]  [Certifications]
```

The numbered subfolders are universal Kubernetes. AWS-specific notes (EKS, Karpenter, VPC CNI) live in [[Kubernetes/eks/README|EKS]]. Tooling and walkthroughs (Helm, Argo CD, ingress) live in [[Kubernetes/guides/README|Guides]]. Exam prep is in [[Kubernetes/certifications/README|CKA / CKAD]].

## Where to go next

→ [[Kubernetes/concepts/L01-architecture|L01 — Architecture]]: learn what runs inside a cluster and where.

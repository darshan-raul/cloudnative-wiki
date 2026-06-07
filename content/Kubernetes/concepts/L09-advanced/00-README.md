---
title: "L09 — Advanced"
tags: [kubernetes, k8s, advanced, operators, controllers, etcd, internals]
date: 2026-06-06
description: Advanced Kubernetes internals — operators, custom controllers, finalizers, garbage collection, etcd, the pause container
---

# L09 — Advanced

How Kubernetes is built, and how to **extend** it. After this level, the platform stops being a black box — you understand what runs in your cluster, why, and how to write your own controllers if you need to.

## What you'll understand after this level

- The **controller pattern** in depth — informers, work queues, the reconcile loop
- **Custom Resources (CRDs)** — extending the Kubernetes API with your own object types
- **Operators** — controllers that manage CRs and encode operational knowledge
- **Finalizers** — async cleanup hooks for objects that own external resources
- **Garbage collection** — owner references, cascading deletion, orphan/background policies
- **Admission controllers and webhooks** — reject / mutate objects at admission time
- **The pause container** — what `/pause` does and why every pod has one
- **IPVS** vs iptables for kube-proxy
- **The aggregation layer** — running auxiliary API servers alongside the core one
- **etcd's role**, and what `etcdctl` does
- **Scheduler extenders** — when built-in scheduling primitives aren't enough

## Notes in this level

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L09-advanced/01-operators\|Operators]] | 🟡 | What an operator is, the operator pattern, examples |
| [[Kubernetes/concepts/L09-advanced/02-custom-controllers\|Custom Controllers]] | ⚪ | Writing a controller — informers, work queues, reconcile |
| [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions\|CRDs]] | ✅ | Extending the API with your own object types, schema validation, versions |
| [[Kubernetes/concepts/L09-advanced/04-admission-controllers\|Admission Controllers & Webhooks]] | ✅ | Built-in admission, mutating/validating webhooks, OPA / Kyverno |
| [[Kubernetes/concepts/L09-advanced/05-finalizers\|Finalizers]] | ✅ | Async cleanup, common pitfalls, the deletion lifecycle |
| [[Kubernetes/concepts/L09-advanced/06-garbage-collection\|Garbage Collection]] | 🟡 | Owner references, foreground vs background deletion |
| [[Kubernetes/concepts/L09-advanced/07-aggregation-layer\|Aggregation Layer]] | 🟡 | Running additional API servers behind the kube-apiserver |
| [[Kubernetes/concepts/L09-advanced/08-ipvs\|IPVS]] | 🟡 | kube-proxy's IPVS mode vs iptables mode |
| [[Kubernetes/concepts/L09-advanced/09-pause-container\|Pause Container]] | 🟡 | The `/pause` process holding the pod's network namespace |
| [[Kubernetes/concepts/L09-advanced/10-etcd\|etcd]] | ✅ | The cluster's source of truth, backups, encryption at rest, performance |
| [[Kubernetes/concepts/L09-advanced/11-scheduler-extenders\|Scheduler Extenders]] | ✅ | Out-of-process webhooks that influence scheduling, when to use them |

## Suggested reading order

1. [[Kubernetes/concepts/L09-advanced/01-operators|Operators]] — what you're aiming to understand
2. [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CRDs]] — the API extension mechanism
3. [[Kubernetes/concepts/L09-advanced/06-garbage-collection|Garbage Collection]] → [[Kubernetes/concepts/L09-advanced/05-finalizers|Finalizers]] — controller patterns you'll see everywhere
4. [[Kubernetes/concepts/L09-advanced/04-admission-controllers|Admission Controllers & Webhooks]] — the other half of "policy"
5. [[Kubernetes/concepts/L09-advanced/02-custom-controllers|Custom Controllers]] — write your own reconcile loop
6. [[Kubernetes/concepts/L09-advanced/10-etcd|etcd]] — the storage layer, when you need to operate the cluster
7. [[Kubernetes/concepts/L09-advanced/07-aggregation-layer|Aggregation Layer]] + [[Kubernetes/concepts/L09-advanced/11-scheduler-extenders|Scheduler Extenders]] — advanced extension points
8. [[Kubernetes/concepts/L09-advanced/09-pause-container|Pause Container]] + [[Kubernetes/concepts/L09-advanced/08-ipvs|IPVS]] — reference notes, read as you need them

## Where to go next

If you've made it from L00 to L09, you have the same conceptual model the Kubernetes docs and source code use. From here, the natural next stops are:

- [[Kubernetes/certifications/README|CKA / CKAD prep]] — exercise what you know
- [[Kubernetes/eks/README|EKS]] — same model, AWS-specific implementations
- [[Kubernetes/guides/README|Guides]] — practical tooling on top of the model

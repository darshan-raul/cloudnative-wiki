---
title: "L02 — Objects"
tags: [kubernetes, k8s, api, objects, kubernetes-api]
date: 2026-06-06
description: The Kubernetes API object model — spec/status, desired state, manifest anatomy
---

# L02 — Objects

The Kubernetes **API is the product**. Everything you do — `kubectl apply`, a controller reconciling, an operator watching — talks to the API server using the same object model. This level is about that model.

## What you'll understand after this level

- What a "Kubernetes object" actually is (a record of intent stored in etcd)
- The universal shape: `apiVersion` / `kind` / `metadata` / `spec` / `status`
- The difference between **desired state** (spec) and **observed state** (status)
- How the **reconciliation loop** drives current → desired
- The **field selectors and labels** — how you query and filter objects
- The **apiGroups** structure — how versioning and grouping work

## Notes in this level

|| Note | Status | What's in it |
|------|--------|--------------|
|| [[Kubernetes/concepts/L02-objects/01-kubernetes-objects\|Kubernetes Objects]] | ✅ | The universal object shape, manifest anatomy, dry-run, field selectors, apiGroups |
|| [[Kubernetes/concepts/L02-objects/02-downward-api\|Downward API]] | ✅ | Injecting pod metadata into containers — env vars, volume mounts, field ref path syntax |

## Suggested reading order

1. [[Kubernetes/concepts/L02-objects/01-kubernetes-objects|Kubernetes Objects]] — read this first, it frames everything else
2. [[Kubernetes/concepts/L02-objects/02-downward-api|Downward API]] — small but worth knowing early

## Where to go next

→ [[Kubernetes/concepts/L03-workloads|L03 — Workloads]]: the object model only gets useful when you start creating workload objects.
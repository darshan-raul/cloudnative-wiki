---
title: "L08 — Operations"
tags: [kubernetes, k8s, operations, troubleshooting, day-2]
date: 2026-06-06
description: Kubernetes day-2 operations — troubleshooting, observability hooks, cluster health
---

# L08 — Operations

Day-2: things are running, and now you have to keep them running. This level is the **troubleshooting flow** and the hooks you need to operate a cluster at scale.

## What you'll understand after this level

- A systematic **troubleshooting flow** (is the pod scheduled? is the image pulling? is the app healthy? can traffic reach it?)
- The standard set of **`kubectl` debug commands** and when to use each
- Where **logs** come from (container stdout, kubelet, control plane)
- Where **metrics** come from (cAdvisor, kubelet, kube-state-metrics)
- The most common **failure modes** and how to recognize them
- When to drop down to the **node** (crictl, journalctl, /var/log)

> **Tooling for observability and log routing** (Prometheus, Grafana, Loki, Fluent Bit) lives in [[Kubernetes/guides/README|Guides]] — this level is about understanding the data sources, not deploying the stack.

## Notes in this level

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L08-operations/01-troubleshooting\|Troubleshooting]] | 🟡 | A short decision-tree for "my pod isn't working" |
| [[Kubernetes/concepts/L08-operations/02-kubectl-debug\|kubectl Debug Toolkit]] | ✅ | The `kubectl` commands you reach for when something is wrong — `describe`, `logs`, `exec`, `debug`, ephemeral containers |
| [[Kubernetes/concepts/L08-operations/04-metrics-sources\|Metrics Sources]] | ✅ | Where metrics come from — cAdvisor, kubelet, metrics-server, kube-state-metrics, the full stack |
| [[Kubernetes/concepts/L08-operations/03-common-failure-modes\|Common Failure Modes]] | ✅ | A stage-by-stage triage guide, from "Pod won't schedule" to "cluster is broken" |

## Suggested reading order

1. [[Kubernetes/concepts/L08-operations/03-common-failure-modes|Common Failure Modes]] — start here, it's the decision tree
2. [[Kubernetes/concepts/L08-operations/02-kubectl-debug|kubectl Debug Toolkit]] — the commands you'll use while doing the decision tree
3. [[Kubernetes/concepts/L08-operations/04-metrics-sources|Metrics Sources]] — once you're past "is it running", to "is it healthy"
4. [[Kubernetes/concepts/L08-operations/01-troubleshooting|Troubleshooting]] — the original short guide, useful as a quick reference

## Where to go next

→ [[Kubernetes/concepts/L09-advanced|L09 — Advanced]]: how Kubernetes itself is built — controllers, operators, etcd, internals.

---
title: Kubernetes Troubleshooting Guide
tags: [kubernetes, troubleshooting, debugging, playbooks, operations]
date: 2026-09-06
description: Central index for Kubernetes troubleshooting playbooks, triage flows, and diagnostic commands.
---

# Kubernetes Troubleshooting Index 🛠️

When a Kubernetes workload or node fails, follow the systematic triage flow to isolate whether the failure is at the container, pod, node, network, or storage layer.

## Quick Jump by Symptom

| Symptom | Layer | Detailed Playbook |
| :--- | :--- | :--- |
| **Pod stuck in CrashLoopBackOff** | Container / App | [[Kubernetes/guides/troubleshooting/crashloop-backoff\|CrashLoopBackOff Playbook]] |
| **Pod stuck in Pending** | Scheduling / Capacity | [[Kubernetes/guides/troubleshooting/pod-pending\|Pod Pending Playbook]] |
| **Image pull error (`ImagePullBackOff`)** | Registry / Auth | [[Kubernetes/guides/troubleshooting/image-pull\|ImagePullBackOff Playbook]] |
| **Service unreachable / connection timeout** | CoreDNS / Kube-Proxy | [[Kubernetes/guides/troubleshooting/service-unreachable\|Service Unreachable Playbook]] |
| **DNS query fails inside Pod** | CoreDNS / Resolv | [[Kubernetes/guides/troubleshooting/dns-resolution\|DNS Resolution Playbook]] |
| **Ingress 404 Not Found or 502 Bad Gateway** | Gateway / Ingress | [[Kubernetes/guides/troubleshooting/ingress-404\|Ingress 404 / 502 Playbook]] |
| **PersistentVolumeClaim stuck in Pending** | Storage / CSI | [[Kubernetes/guides/troubleshooting/pvc-stuck\|PVC Stuck Playbook]] |
| **Node status is NotReady** | Kubelet / Runtime | [[Kubernetes/guides/troubleshooting/node-not-ready\|Node NotReady Playbook]] |

## Conceptual Diagnostic Toolkits

- [[Kubernetes/concepts/L08-operations/01-troubleshooting|Troubleshooting Mental Model]]: How Kubernetes reconciles state and where errors surface.
- [[Kubernetes/concepts/L08-operations/02-kubectl-debug|kubectl Debug Toolkit]]: Using `describe`, `logs --previous`, `exec`, and ephemeral debug containers.
- [[Kubernetes/concepts/L08-operations/03-common-failure-modes|Common Failure Modes Reference]]: Comprehensive matrix of exit codes, termination signals, and root causes.

---

*External Reference: [k8s-500-prod-issues](https://github.com/vijay2181/k8s-500-prod-issues)*

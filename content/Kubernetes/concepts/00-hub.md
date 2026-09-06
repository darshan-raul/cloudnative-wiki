---
title: Kubernetes Concepts
tags: [kubernetes, k8s, concepts, learning-path]
date: 2026-06-06
description: Top-down Kubernetes concepts curriculum — from what k8s is to advanced controller internals. Read in numerical order.
---

# Kubernetes Concepts ☸️

A **top-down learning path** for Kubernetes, from "what is it" to "how the controllers actually work". The folders are numbered — work through them in order, and each level builds on the previous.

> **First time here?** Start with [[Kubernetes/concepts/L00-start-here/00-start-here|00 — Start Here]] to see prerequisites, the big picture, and how to use this section.

## The Roadmap

| # | Section | What you'll understand |
|---|---------|------------------------|
| 00 | [[Kubernetes/concepts/L00-start-here/00-start-here\|Start Here]] | What Kubernetes is, the cluster mental model, how to read this section |
| 01 | [[Kubernetes/concepts/L01-architecture/00-README\|Architecture]] | Control plane components, nodes, what runs where, HA topology, namespaces |
| 02 | [[Kubernetes/concepts/L02-objects/00-README\|Objects]] | The Kubernetes API model — `spec` / `status` / `metadata`, declarative intent, how the API server stores state |
| 03 | [[Kubernetes/concepts/L03-workloads/00-README\|Workloads]] | Pods → ReplicaSets → Deployments → StatefulSets → DaemonSets → Jobs/CronJobs — the layered workload model |
| 04 | [[Kubernetes/concepts/L04-services-networking/00-README\|Services & Networking]] | Services, DNS, Gateway API, Ingress, NetworkPolicy, CNI, EndpointSlices |
| 05 | [[Kubernetes/concepts/L05-config-storage/00-README\|Config & Storage]] | ConfigMap, Secret, PersistentVolume, PersistentVolumeClaim, StorageClass, resource quotas |
| 06 | [[Kubernetes/concepts/L06-scheduling-scaling/00-README\|Scheduling & Scaling]] | Scheduling (taints, tolerations, affinity), HPA/VPA/Karpenter, restart policies |
| 07 | [[Kubernetes/concepts/L07-security/00-README\|Security]] | RBAC, ServiceAccounts, certificates, authentication vs authorization, Pod Security Standards |
| 08 | [[Kubernetes/concepts/L08-operations/00-README\|Operations]] | Troubleshooting flow, observability hooks, day-2 ops, node maintenance |
| 09 | [[Kubernetes/concepts/L09-advanced/00-README\|Advanced]] | Operators, custom controllers, finalizers, garbage collection, etcd, pause container, aggregation layer |

## How to read this section

- **Sequential if you're new.** 00 → 01 → 02 → ... → 09. Each level only references forward concepts briefly with a "see L7: security" pointer.
- **Reference if you already know k8s.** Jump to the subfolder you need — every note is self-contained, but wikilinks back to prerequisites are explicit.
- **Practitioner tracks.** If your job is one specific thing, the table below tells you which levels to focus on:

| If you work on… | Read these levels |
|-----------------|-------------------|
| Application deployment / SRE | 00, 01, 02, 03, 04, 06, 08 |
| Platform engineering | 00, 01, 04, 05, 07, 09 |
| Security / compliance | 00, 01, 07 |
| Storage / data on k8s | 00, 01, 05 |
| Building controllers / operators | 00, 01, 02, 09 |

## What's NOT in this section

This section covers **concepts that apply to any Kubernetes cluster** — vanilla k3s, kubeadm, GKE, EKS, AKS, OpenShift. AWS-specific things (VPC CNI tuning, Karpenter, EKS Auto Mode, IRSA) live in [[Kubernetes/eks/README|EKS]]. Tooling and task-oriented walkthroughs (Argo CD, Helm charts, ingress controllers) live in [[Kubernetes/guides/README|Guides]].

## Status legend

Each numbered folder has a README that lists every note with a status:

- ✅ **Core** — solid reference note, read with confidence
- 🟡 **Outline** — real content but incomplete, good for orientation
- ⚪ **Stub** — placeholder, content to be filled in

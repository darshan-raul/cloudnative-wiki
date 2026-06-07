---
title: "L05 — Config & Storage"
tags: [kubernetes, k8s, configmap, secret, storage, pvc]
date: 2026-06-06
description: Kubernetes config and storage — ConfigMap, Secret, PersistentVolume, PersistentVolumeClaim, StorageClass
---

# L05 — Config & Storage

Two intertwined problems: how do containers get their **configuration** (and how do you keep secrets out of images), and how do **stateful workloads** get durable disks.

## What you'll understand after this level

- **ConfigMap** for non-sensitive config, **Secret** for sensitive — what's the same, what's different, why secrets are barely-secret by default
- The **two ways to consume config** in a pod: env vars vs mounted files
- Why you almost never put config in a container image
- The **PV / PVC / StorageClass** dance — how a pod claims durable storage
- Storage **access modes** (RWO, ROX, RWX, RWOP) and what they mean in practice
- The common **volume types** and when to use each (emptyDir, hostPath, CSI, ephemeral)
- **Resource quotas** and **LimitRange** — how to put guardrails on a namespace

## Notes in this level

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L05-config-storage/01-config-maps\|ConfigMaps]] | ✅ | The config-as-object pattern, env vs volume mounts, gotchas, immutable ConfigMaps |
| [[Kubernetes/concepts/L05-config-storage/02-secrets\|Secrets]] | 🟡 | Secret types (Opaque, dockerconfigjson, tls), how they're stored, encryption-at-rest |
| [[Kubernetes/concepts/L05-config-storage/07-storage\|Storage]] | ⚪ | High-level overview of PV/PVC/StorageClass — kept as a quick-reference summary |
| [[Kubernetes/concepts/L05-config-storage/04-persistentvolume\|PersistentVolume]] | ✅ | Cluster-scoped storage resource, lifecycle, reclaim policies, access modes |
| [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim\|PersistentVolumeClaim]] | ✅ | Namespaced storage request, binding, expansion, snapshots |
| [[Kubernetes/concepts/L05-config-storage/06-storageclass\|StorageClass]] | ✅ | Dynamic provisioning, provisioners, WaitForFirstConsumer, the default-class trap |
| [[Kubernetes/concepts/L05-config-storage/03-volumes\|Volume Types]] | ✅ | emptyDir, hostPath, NFS, CSI, ephemeral, mount options |
| [[Kubernetes/concepts/L05-config-storage/08-resource-quota\|Resource Quota]] | ✅ | Quotas on CPU/memory/object counts, LimitRange defaults per namespace |

## Suggested reading order

1. [[Kubernetes/concepts/L05-config-storage/01-config-maps|ConfigMaps]] — most apps need this
2. [[Kubernetes/concepts/L05-config-storage/02-secrets|Secrets]] — once you need credentials or tokens
3. [[Kubernetes/concepts/L05-config-storage/08-resource-quota|Resource Quota]] — before you share a cluster with other teams
4. [[Kubernetes/concepts/L05-config-storage/04-persistentvolume|PersistentVolume]] → [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim|PersistentVolumeClaim]] → [[Kubernetes/concepts/L05-config-storage/06-storageclass|StorageClass]] — read in this order, they're a chain
5. [[Kubernetes/concepts/L05-config-storage/03-volumes|Volume Types]] — once you know the model, the volume sources in a Pod spec
6. [[Kubernetes/concepts/L05-config-storage/07-storage|Storage]] — the original 2-page summary, useful as a quick reference

## Where to go next

→ [[Kubernetes/concepts/L06-scheduling-scaling|L06 — Scheduling & Scaling]]: now that pods exist, decide where they run and what to do when load changes.

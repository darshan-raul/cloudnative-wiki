---
title: "L07 — Security"
tags: [kubernetes, k8s, security, rbac, authentication, pss]
date: 2026-06-06
description: Kubernetes security — RBAC, ServiceAccounts, certificates, authentication vs authorization, Pod Security Standards
---

# L07 — Security

Four distinct concerns that all get called "Kubernetes security":
1. **Who can talk to the API** (authentication, RBAC, ServiceAccounts)
2. **What a pod is allowed to do** (SecurityContext, Pod Security Standards, NetworkPolicy — see L04)
3. **Encrypting data in transit and at rest** (certificates, etcd encryption, secret encryption)
4. **Supply chain** (image scanning, signing, admission) — covered in [[Kubernetes/guides/README|Guides]]

This level covers 1, 2 (config side), and 3.

## What you'll understand after this level

- **Authentication** — who are you (cert, token, OIDC, webhook)
- **Authorization** — what can you do (RBAC, Node, ABAC, Webhook modes)
- **ServiceAccounts** — the identity a pod runs as, and how workloads authenticate to the API
- **RBAC primitives** — Role, ClusterRole, RoleBinding, ClusterRoleBinding — when each applies
- **Certificates** — the PKI that underpins cluster auth, kubelet serving certs, the API server
- **Pod Security Standards** — `privileged` / `baseline` / `restricted` profiles
- **SecurityContext** — the per-container / per-Pod flags that enforce least privilege

## Notes in this level

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L07-security/03-rbac\|RBAC]] | 🟡 | Role/ClusterRole, bindings, common patterns and foot-guns |
| [[Kubernetes/concepts/L07-security/02-service-accounts\|ServiceAccounts]] | ✅ | Pod identity, token projection, default vs custom |
| [[Kubernetes/concepts/L07-security/01-authentication-authorization\|Authentication vs Authorization]] | ⚪ | The conceptual split, what handles each |
| [[Kubernetes/concepts/L07-security/04-certificates\|Certificates]] | 🟡 | Cluster PKI, the CA bundle, kubelet certs |
| [[Kubernetes/concepts/L07-security/05-security-context\|SecurityContext]] | ✅ | runAsUser, capabilities, readOnlyRootFilesystem, seccomp — the per-Pod hardening knobs |
| [[Kubernetes/concepts/L07-security/06-pod-security-standards\|Pod Security Standards]] | ✅ | `privileged` / `baseline` / `restricted` namespace labels, migration strategy |
| [[Kubernetes/concepts/L07-security/07-security\|Security Overview]] | ⚪ | High-level security model summary |

## Suggested reading order

1. [[Kubernetes/concepts/L07-security/01-authentication-authorization|Authentication vs Authorization]] — the conceptual split
2. [[Kubernetes/concepts/L07-security/02-service-accounts|ServiceAccounts]] — what every pod actually has
3. [[Kubernetes/concepts/L07-security/03-rbac|RBAC]] — the most common authorization mode
4. [[Kubernetes/concepts/L07-security/05-security-context|SecurityContext]] — the per-Pod hardening
5. [[Kubernetes/concepts/L07-security/06-pod-security-standards|Pod Security Standards]] — apply it cluster-wide via namespace labels
6. [[Kubernetes/concepts/L07-security/04-certificates|Certificates]] — when you need to debug the cluster PKI
7. [[Kubernetes/concepts/L07-security/07-security|Security Overview]] — the big picture after the pieces are clear

## AWS-specific notes

The EKS-specific versions of these (IRSA, Pod Identity, EKS access entries) live in [[Kubernetes/eks/security/README|EKS Security]] — they're concrete implementations of these primitives on AWS.

## Where to go next

→ [[Kubernetes/concepts/L08-operations|L08 — Operations]]: keep things running.

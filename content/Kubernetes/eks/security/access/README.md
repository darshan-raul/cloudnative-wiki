---
title: Cluster Access Overview
tags: [eks, security, access]
date: 2026-05-17
description: Overview of ways to access EKS clusters - kubectl, API, authentication
---

# Cluster Access on EKS

## Overview

Access to an EKS cluster involves two layers:

1. **Authentication (AuthN)** - Verifying who you are (IAM identity)
2. **Authorization (AuthZ)** - Determining what you can do (RBAC)

## Access Vectors

| Method | Purpose | AuthN |
|--------|---------|-------|
| `kubectl` | Kubernetes API (clusters, workloads) | IAM via `aws eks get-token` |
| Kubernetes API (direct) | Programmatic access | IAM |
| IRSA/Pod Identity | Pods accessing AWS services | IAM role |
| AWS SDK in pods | AWS API calls from workloads | IAM role |

## Authentication Methods

### Human Access

| Method | Setup | Use Case |
|--------|-------|----------|
| AWS CLI + `aws eks update-kubeconfig` | IAM user/role with EKS access | Local development |
| AWS Console | IAM credentials | Web UI |
| Bastion host | EC2 in public subnet with IAM | Private clusters |
| CloudShell | Browser-based shell | Quick access, private clusters |
| Cloud9 IDE | IDE in VPC | Development with VPC access |

### Workload Access (Pods)

| Method | Setup | Use Case |
|--------|-------|----------|
| [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]] | OIDC provider + IAM role trust | Full AWS SDK access |
| [[Kubernetes/eks/security/pod-identity|Pod Identity]] | EKS-managed associations | Simpler than IRSA |
| Node IAM Role | Instance profile | Fallback (not recommended) |

## IAM and RBAC Relationship

```
┌─────────────────────────────────────────────────────────────┐
│                    Access Decision Flow                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Request ──► IAM AuthN ──► Kubernetes RBAC ──► Allow/Deny  │
│                 │                                           │
│                 │                                           │
│         "Who are you?"                              "What can                       │
│                                                             │
│         IAM role or                                 you do in                       │
│         IAM user                                    this cluster?                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Default Access

| Principal | Access |
|-----------|--------|
| Node IAM role | Workers can join cluster (via NodeAuthorizer) |
| IAM users/roles | No access by default |
| Service accounts | No permissions by default |

## Cluster Endpoint Configuration

| Configuration | Public Endpoint | Private Endpoint | Access From |
|---------------|------------------|------------------|-------------|
| Public only | Enabled | Disabled | Internet |
| Public & Private | Enabled | Enabled | Internet + VPC (default) |
| Private only | Disabled | Enabled | VPC only |

See [[Kubernetes/eks/security/access/endpoint-access|Endpoint Access Deep-Dive]] for detailed configuration options.

## Related Topics

- [[Kubernetes/eks/security/access/endpoint-access|Endpoint Access]] - Public/private endpoints, bastion hosts, security groups
- [[Kubernetes/eks/security/access/aws-auth-legacy|Legacy aws-auth]] - Original ConfigMap-based access management
- [[Kubernetes/eks/security/access/authentication-patterns|Auth Patterns]] - IRSA vs Pod Identity comparison
- [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]] - IAM roles for service accounts
- [[Kubernetes/eks/security/pod-identity|Pod Identity]] - EKS-managed pod credentials
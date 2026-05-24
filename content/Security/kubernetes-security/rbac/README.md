---
title: Kubernetes RBAC
tags: [kubernetes, security, rbac, iam]
date: 2025-05-24
description: Kubernetes RBAC (Role-Based Access Control) - roles, clusterRoles, rolebindings, and least-privilege patterns for EKS
---

# Kubernetes RBAC ☸️

RBAC in Kubernetes controls who can do what to which resources.

## Core Concepts

| Object | Scope | Use |
|--------|-------|-----|
| Role | Namespace | Grant permissions within a namespace |
| ClusterRole | Cluster-wide | Grant permissions across all namespaces or cluster-scoped resources |
| RoleBinding | Namespace | Bind a Role/ClusterRole to users within a namespace |
| ClusterRoleBinding | Cluster-wide | Bind a ClusterRole to users across all namespaces |

## Built-in Roles

| Role | Access |
|------|--------|
| `view` | Read-only to most resources |
| `edit` | Read/write but not manage RBAC |
| `admin` | Full read/write within a namespace |
| `cluster-admin` | Superuser on the entire cluster |

## Example: Read-Only Namespace User

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: readonly
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch"]
```

## Example: EKS Cluster Access via IRSA

For AWS IAM-based access to EKS:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: eks-irsa-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: AWSIAMRole
  name: my-app-role  # IRSA role
  namespace: default
```

## IRSA vs RBAC

- **IRSA** — Maps AWS IAM role to a Kubernetes ServiceAccount
- **RBAC** — Controls what that ServiceAccount can do in K8s
- Use IRSA for pod-level AWS access, RBAC for K8s API access

## Related

- [[Security/kubernetes-security/README|K8s Security Hub]]
- [[Kubernetes/eks/security/pod-identity|Pod Identity (IRSA)]]
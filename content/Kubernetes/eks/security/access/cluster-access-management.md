---
title: EKS Cluster Access Management
tags: [kubernetes, eks, security, iam, rbac]
date: 2025-05-24
description: EKS Cluster Access API for fine-grained IAM-based access to Kubernetes clusters
---

# EKS Cluster Access Management ☸️

The EKS Cluster Access API (introduced to replace the legacy `aws-auth` ConfigMap) provides a managed way to grant IAM principals access to Kubernetes RBAC.

## Overview

EKS manages the mapping between AWS IAM principals and Kubernetes RBAC automatically. Instead of editing the `aws-auth` ConfigMap manually, you use the `aws eks update-cluster-config` command or EKS API.

## Granting Access

### Add IAM User/Role to Kubernetes RBAC

```bash
# Grant a role access to the cluster
aws eks create-access-entry \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789012:role/MyRole \
  --type STANDARD_USER \
  --region us-east-1

# Associate with a Kubernetes group
aws eks associate-access-entry \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789012:role/MyRole \
  --kubernetes-groups system:masters
```

### Predefined Kubernetes Groups

| Group | Access |
|-------|--------|
| `system:masters` | Full cluster access (like sudo) |
| `system:authenticated` | All authenticated users |
| `system:node` | Node pool nodes |
| `system:bootstrappers` | Node bootstrapping |

### Custom RBAC Role Mapping

```bash
# Create a role with read-only access
aws eks associate-access-entry \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789012:role/DeveloperRole \
  --kubernetes-groups developers
```

```yaml
# Kubernetes RBAC role for developers group
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer-readonly
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list"]
```

## IRSA (IAM Roles for Service Accounts)

For workloads needing AWS API access:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/MyAppRole
```

## Legacy: aws-auth ConfigMap

The `aws-auth` ConfigMap approach is deprecated. New clusters don't have it by default. Use the Cluster Access API instead.

**Migration:** If you're still using `aws-auth`, the recommended path is to create new access entries and remove entries from the ConfigMap incrementally.

## Related

- [[Kubernetes/eks/security/access/README|EKS Security Access Hub]]
- [[Kubernetes/eks/security/pod-identity|Pod Identity]]
- [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]]
- [[AWS/concepts/iam|IAM]]
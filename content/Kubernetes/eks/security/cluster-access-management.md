---
title: Cluster Access Management API
tags: [eks, security, access]
date: 2026-05-17
description: Manage EKS cluster access with Cluster Access API
---

# Cluster Access Management API

## Overview

EKS Cluster Access API provides programmatic access management without modifying `aws-auth` ConfigMap.

## Enable Access Entry

```bash
# Create access entry
aws eks create-access-entry \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789:user/my-user

# List access entries
aws eks list-access-entries \
  --cluster-name my-cluster
```

## Associate Access Policy

```bash
# Grant cluster admin access
aws eks associate-access-policy \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789:user/my-user \
  --policy-arn arn:aws:eks::aws:cluster-access-policy:AmazonEKSClusterAdmin
```

## Access Policies

| Policy | Description |
|--------|-------------|
| AmazonEKSClusterAdmin | Full cluster access |
| AmazonEKSAdminView | Read-only cluster access |
| AmazonEKSEdit | Developer access (default) |
| AmazonEKSView | Read-only namespaces |

## Configure Kubernetes Access

```yaml
# Create role binding for IAM user
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: my-user-admin
subjects:
- kind: User
  name: my-user
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
```

## Benefits

- No direct ConfigMap manipulation
- Audit trail via CloudTrail
- IAM-based access control
- Principals can be users or roles

## References

- [Cluster Access Management](https://docs.aws.amazon.com/eks/latest/userguide/cluster-access.html)
- [EKS Workshop - Cluster Access API](https://www.eksworkshop.com/docs/security/cluster-access-management/)
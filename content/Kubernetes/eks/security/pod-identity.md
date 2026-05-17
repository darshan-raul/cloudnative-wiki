---
title: EKS Pod Identity
tags: [eks, security, iam, pod-identity]
date: 2026-05-17
description: EKS Pod Identity - managed IAM permissions for pods
---

# EKS Pod Identity

## Overview

Pod Identity is an EKS-managed feature that simplifies IAM permission assignment to pods without requiring OIDC setup.

## How It Works

1. Create Pod Identity Association in EKS
2. Associate IAM role with Kubernetes service account
3. EKS agent injects credentials into pods

## Setup via AWS CLI

```bash
# Create Pod Identity Association
aws eks create-pod-identity-association \
  --cluster-name my-cluster \
  --namespace default \
  --service-account my-app \
  --role-arn arn:aws:iam::123456789:role/my-app-role \
  --profile my-profile

# List associations
aws eks list-pod-identity-associations \
  --cluster-name my-cluster
```

## Pod Configuration

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: default
---
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  serviceAccountName: my-app
  containers:
  - name: app
    image: my-app:latest
```

## Pod Identity vs IRSA

| Aspect | Pod Identity | IRSA |
|--------|--------------|------|
| OIDC setup | Not needed | Required |
| Management | EKS managed | Customer managed |
| Credential refresh | Automatic | Token file rotation |
| Region support | All EKS regions | Varies |

## References

- [Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [EKS Workshop - Pod Identity](https://www.eksworkshop.com/docs/security/amazon-eks-pod-identity/)
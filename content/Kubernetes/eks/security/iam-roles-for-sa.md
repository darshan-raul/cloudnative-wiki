---
title: IAM Roles for Service Accounts (IRSA)
tags: [eks, security, iam, irsa]
date: 2026-05-17
description: IRSA - IAM roles for Kubernetes service accounts
---

# IAM Roles for Service Accounts (IRSA)

## Overview

IRSA allows pods to authenticate as IAM roles, enabling fine-grained access to AWS resources.

## How It Works

1. Create IAM role with trust policy for service account
2. Annotate Kubernetes service account with role ARN
3. Pods use service account and automatically assume role

## Setup

### 1. Create IAM Role

```bash
# Create OIDC provider
eksctl utils associate-iam-oidc-provider \
  --cluster my-cluster \
  --approve

# Create IAM role
aws iam create-role \
  --role-name my-app-role \
  --assume-role-policy-document file://trust-policy.json
```

### trust-policy.json

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E:sub": "system:serviceaccount:default:my-app"
        }
      }
    }
  ]
}
```

### 2. Create Service Account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/my-app-role
```

### 3. Use in Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  serviceAccountName: my-app
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: AWS_ROLE_ARN
      value: arn:aws:iam::123456789:role/my-app-role
    - name: AWS_WEB_IDENTITY_TOKEN_FILE
      value: /var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

## IRSA vs Pod Identity

| Feature | IRSA | EKS Pod Identity |
|---------|------|------------------|
| Setup | Manual IAM role | Managed by EKS |
| OIDC required | Yes | No |
| Per-pod roles | Via SA annotation | Via SA annotation |
| Audit trail | IAM console | CloudTrail |

## References

- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [EKS Workshop - IRSA](https://www.eksworkshop.com/docs/security/iam-roles-for-service-accounts/)
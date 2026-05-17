---
title: AWS Secrets Manager with EKS
tags: [eks, security, secrets, secrets-manager]
date: 2026-05-17
description: Using AWS Secrets Manager to store and retrieve secrets in EKS
---

# AWS Secrets Manager with EKS

## Overview

Store sensitive data in AWS Secrets Manager and access it from EKS pods using IRSA.

## Store a Secret

```bash
# Create a secret
aws secretsmanager create-secret \
  --name my-app/db-password \
  --secret-string "supersecretpassword"

# Store JSON secret
aws secretsmanager create-secret \
  --name my-app/config \
  --secret-string '{"api_key":"xxx","db_host":"db.example.com"}'
```

## Create IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:us-west-2:123456789:secret:my-app/*"
    }
  ]
}
```

## Create Service Account with IRSA

```bash
# Create service account with IRSA
eksctl create iamserviceaccount \
  --name my-app \
  --namespace default \
  --cluster my-cluster \
  --attach-role-arn arn:aws:iam::123456789:role/my-app-role \
  --approve
```

## Access Secret from Pod

### Using CSI Driver

```bash
# Install Secrets Manager CSI driver
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system

# Install AWS provider
helm install aws-secrets-manager aws-secrets-manager \
  --namespace kube-system
```

### SecretProviderClass

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: my-app-secrets
spec:
  provider: aws
  parameters:
    secretArn: arn:aws:secretsmanager:us-west-2:123456789:secret:my-app/db-password
    region: us-west-2
```

### Use in Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  serviceAccountName: my-app
  containers:
  - name: app
    image: my-app
    volumeMounts:
    - name: secrets
      mountPath: /secrets
      readOnly: true
  volumes:
  - name: secrets
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: my-app-secrets
```

## Secret Rotation

Enable automatic rotation with Lambda:

```bash
# Enable rotation
aws secretsmanager rotate-secret \
  --secret-id my-app/db-password \
  --rotation-lambda-arn arn:aws:lambda:us-west-2:123456789:function:my-app-rotation
```

## References

- [Secrets Manager CSI Driver](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html)
- [EKS Workshop - Secrets Manager](https://www.eksworkshop.com/docs/security/secrets-management/secrets-manager/)
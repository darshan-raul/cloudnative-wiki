---
title: AWS Controllers for Kubernetes (ACK)
tags: [eks, automation, ack, infrastructure]
date: 2026-05-17
description: Manage AWS resources from Kubernetes with ACK
---

# AWS Controllers for Kubernetes (ACK)

## Overview

ACK lets you create and manage AWS resources using Kubernetes Custom Resource Definitions (CRDs).

## Available Controllers

| Controller | AWS Service |
|------------|-------------|
| ack-rds-controller | Amazon RDS |
| ack-eks-controller | Amazon EKS |
| ack-s3-controller | Amazon S3 |
| ack-dynamodb-controller | Amazon DynamoDB |
| ack-sqs-controller | Amazon SQS |
| ack-sns-controller | Amazon SNS |
| ack-ec2-controller | Amazon EC2 |
| ack-emrcontainers-controller | Amazon EMR on EKS |

## Install ACK

```bash
# Add Helm repos
helm repo add ack-acm https://aws.github.io/eks-charts
helm repo update

# Install RDS controller
helm install ack-rds-controller aws-controllers-k8s/rds-controller \
  --namespace ack-system \
  --create-namespace \
  --set serviceAccount.create=true \
  --set aws.region=us-west-2
```

## Create RDS Instance

```yaml
apiVersion: rds.services.k8s.aws/v1alpha1
kind: RDSInstance
metadata:
  name: my-database
spec:
  allocatedStorage: 20
  storageType: gp3
  engine: postgres
  engineVersion: "15.3"
  dbInstanceIdentifier: my-database
  dbInstanceClass: db.t3.medium
  masterUsername: admin
  masterUserPasswordSecretRef:
    name: db-creds
    namespace: default
    key: password
  publiclyAccessible: false
  vpcSecurityGroupIDs:
    - sg-1234567890abcdef0
```

## Create Secret for Password

```bash
kubectl create secret generic db-creds \
  --from-literal=password=MySecurePassword123!
```

## Create S3 Bucket

```yaml
apiVersion: s3.services.k8s.aws/v1alpha1
kind: Bucket
metadata:
  name: my-app-bucket
spec:
  name: my-unique-bucket-name
  versioning: true
  tagging:
    - key: environment
      value: production
```

## Create IAM Role for Controller

```bash
# Create IRSA for ACK controller
eksctl create iamserviceaccount \
  --name ack-rds-controller \
  --namespace ack-system \
  --cluster my-cluster \
  --attach-role-arn arn:aws:iam::123456789:role/ACKExecutionRole \
  --approve

# Get controller policy
curl -o rds-controller-policy.json \
  https://raw.githubusercontent.com/aws-controllers-k8s/community/main/templates/cross-account/rds-controller-policy.json

aws iam create-role \
  --role-name ACKExecutionRole \
  --assume-role-policy-document file://trust-policy.json

aws iam put-role-policy \
  --role-name ACKExecutionRole \
  --policy-name ACKExecutionPolicy \
  --policy-document file://rds-controller-policy.json
```

## Reference ACK Resources

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: app
        image: my-app:latest
        env:
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: rds-connection
              namespace: default
              key: host
```

## References

- [ACK Documentation](https://aws-controllers-k8s.github.io/)
- [EKS Workshop - ACK](https://www.eksworkshop.com/docs/automation/controlplanes/ack/)
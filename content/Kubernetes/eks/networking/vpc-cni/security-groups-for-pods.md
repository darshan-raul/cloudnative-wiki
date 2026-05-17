---
title: Security Groups for Pods
tags: [eks, networking, vpc-cni, security]
date: 2026-05-17
description: Assign VPC security groups to individual pods
---

# Security Groups for Pods

## Overview

Security Groups for Pods (SGP) allows you to assign security groups directly to pods, enabling fine-grained network access control.

## Requirements

- VPC CNI addon version >= 1.7.0
- Nitro-based instances
- Linux nodes only

## Create Security Group for Pods

```yaml
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: my-app-sg-policy
spec:
  podSelector:
    matchLabels:
      app: my-app
  securityGroups:
    groupIds:
      - sg-1234567890abcdef0
```

## Use Case: Database Access

```yaml
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: database-access
spec:
  podSelector:
    matchLabels:
      tier: database
  securityGroups:
    groupIds:
      - sg-db-security-group
      - sg-app-security-group
```

## Benefits

- Pod-level security group assignment
- No ENI per pod (shared ENI with warm IPs)
- Fine-grained access control
- Works with AWS services (RDS, ElastiCache)

## Limitations

- Nitro instances only
- Cannot use with Windows nodes
- Limited to certain instance types

## References

- [Security Groups for Pods](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html)
- [EKS Workshop - SGP](https://www.eksworkshop.com/docs/networking/vpc-cni/security-groups-for-pods/)
---
title: Managed Node Groups Basics
tags: [eks, compute, mng]
date: 2026-05-17
description: Creating and managing EKS Managed Node Groups
---

# Managed Node Groups Basics

## Create Node Group

```bash
eksctl create nodegroup \
  --cluster my-cluster \
  --name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed
```

## Node Group with Custom Settings

```bash
eksctl create nodegroup \
  --cluster my-cluster \
  --name custom-workers \
  --node-type t3.medium \
  --nodes 3 \
  --node-ami-family AmazonLinux2 \
  --override-instance-destroy-behavior terminate \
  --ebs-volume-size 50 \
  --ebs-volume-type gp3 \
  --asg-access \
  --external-dns-access \
  --full-ecr-access
```

## Update Node Group

```bash
# Scale node group
eksctl scale nodegroup \
  --cluster my-cluster \
  --name standard-workers \
  --nodes 5

# Update node group
eksctl update nodegroup \
  --cluster my-cluster \
  --name standard-workers \
  --kubernetes-version 1.30

# Rotate node group (drains and replaces nodes)
eksctl rotate nodegroup \
  --cluster my-cluster \
  --name standard-workers
```

## Delete Node Group

```bash
eksctl delete nodegroup \
  --cluster my-cluster \
  --name standard-workers
```

## Node Group Configuration Options

### Instance Types
| Family | Use Case |
|--------|----------|
| t3, m5, c5 | General purpose |
| m5n, c5n | High network bandwidth |
| r5, r5n | Memory optimized |
| p3, p4, g4 | GPU workloads |
| a1, m6g, c6g, r6g | ARM/Graviton |

### Launch Template Customization
```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
  region: us-west-2
managedNodeGroups:
  - name: custom-ng
    launchTemplate:
      id: lt-1234567890abcdef0
      version: "3"
```

## References

- [Creating a managed node group](https://docs.aws.amazon.com/eks/latest/userguide/create-managed-node-group.html)
- [eksctl nodegroup documentation](https://eksctl.io/usage/nodegroup/)
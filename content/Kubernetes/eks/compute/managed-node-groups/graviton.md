---
title: Graviton on EKS
tags: [eks, compute, mng, arm, graviton]
date: 2026-05-17
description: Using ARM-based Graviton instances for cost-effective EKS workloads
---

# Graviton on EKS

## Overview

Graviton instances use AWS-designed ARM processors for better price-performance.

## Instance Types

| Instance | vCPU | Memory | Use Case |
|----------|------|--------|----------|
| m6g.medium | 1 | 4 GB | Small workloads |
| m6g.xlarge | 4 | 16 GB | General purpose |
| c6g.2xlarge | 8 | 16 GB | Compute optimized |
| r6g.large | 2 | 16 GB | Memory optimized |
| m6gd.xlarge | 4 | 16 GB | With local NVMe |

## Create Node Group with Graviton

```bash
eksctl create nodegroup \
  --cluster my-cluster \
  --name graviton-workers \
  --node-type m6g.xlarge \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 10 \
  --managed
```

## Multi-Architecture Images

```yaml
apiVersion: v1
kind: Pod
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
  containers:
  - name: app
    image: myapp:latest
```

## Benefits

- 20% better price-performance vs x86
- Lower memory pricing
- Better performance for ARM-native workloads
- Energy efficient

## Considerations

- Ensure your application is ARM-compatible
- Multi-architecture container images required
- Some AWS integrations may have limitations

## References

- [EKS Workshop - Graviton](https://www.eksworkshop.com/docs/fundamentals/compute/managed-node-groups/graviton/)
- [Graviton Processor](https://aws.amazon.com/ec2/graviton/)
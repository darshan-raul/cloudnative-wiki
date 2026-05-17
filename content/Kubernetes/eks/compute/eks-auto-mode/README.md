---
title: EKS Auto Mode
tags: [eks, compute, auto-mode]
date: 2026-05-17
description: Fully managed compute with automatic node management
---

# EKS Auto Mode

## Overview

EKS Auto Mode automatically manages the data plane (nodes) including provisioning, scaling, updates, and security patches.

## Key Features

- Automatic node provisioning
- Automatic OS and Kubernetes version updates
- Built-in cost optimization
- Integrated security (OS patching)
- Simplified operations

## Enable Auto Mode

```bash
# Create cluster with Auto Mode
eksctl create cluster \
  --name my-cluster \
  --region us-west-2 \
  --with-eks-auto-mode
```

Or enable on existing cluster via AWS Console or API.

## Configure Auto Mode

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
  region: us-west-2
autoModeConfig:
  enabled: true
  nodePools:
    - name: general
      instanceTypes: ["m5.large", "m5.xlarge"]
      minSize: 1
      maxSize: 10
    - name: gpu
      instanceTypes: ["g4dn.xlarge"]
      minSize: 0
      maxSize: 2
      taints:
        - key: "nvidia.com/gpu"
          value: "true"
          effect: "NoSchedule"
```

## Compute Comparison

| Feature | EKS Auto Mode | MNG | Karpenter |
|---------|---------------|-----|-----------|
| Node management | Full | Partial | Partial |
| OS patching | Auto | Manual | Manual |
| Scaling | Policy-based | ASG-based | Workload-based |
| Pricing | EC2 + fee | EC2 | EC2 |

## When to Use Auto Mode

- Want minimal operational overhead
- Prefer opinionated configuration
- Don't need fine-grained node control
- Want automatic security compliance

## References

- [EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [EC2 Managed Instances](https://docs.aws.amazon.com/eks/latest/userguide/automode-learn-instances.html)
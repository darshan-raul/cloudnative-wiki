---
title: AWS Fargate on EKS
tags: [eks, compute, fargate]
date: 2026-05-17
description: Serverless compute for Kubernetes pods with AWS Fargate
---

# AWS Fargate on EKS

## Overview

Fargate provides serverless compute for containers - no need to manage underlying EC2 instances.

## Create Fargate Profile

```bash
eksctl create fargateprofile \
  --cluster my-cluster \
  --name default \
  --namespace default \
  --labels role=web
```

## Fargate Profile Configuration

```yaml
# fargate-profile.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
  region: us-west-2
fargateProfiles:
  - name: default
    selectors:
      - namespace: default
        labels:
          env: production
      - namespace: kube-system
```

## Update /etc/eksctl.yaml

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
  region: us-west-2
iam:
  withOIDC: true
fargateProfiles:
  - name: default
    selectors:
      - namespace: default
```

## Considerations

- Pods get ENI in VPC (security groups apply)
- No SSH access to nodes
- No DaemonSets on Fargate
- EBS volumes not supported
- Longer pod startup time vs EC2

## References

- [EKS Fargate](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html)
- [EKS Workshop - Fargate](https://www.eksworkshop.com/docs/fundamentals/compute/fargate/)
- [[Kubernetes/eks/compute/fargate/fargate-vs-ec2]] - Detailed comparison
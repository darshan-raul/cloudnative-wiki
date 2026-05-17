---
title: Karpenter on EKS
tags: [eks, compute, karpenter]
date: 2026-05-17
description: Intelligent auto-provisioning for Kubernetes with Karpenter
---

# Karpenter

## Overview

Karpenter is an intelligent auto-provisioning system that dynamically creates the right-sized compute capacity based on pod requirements.

## Installation

```bash
# Add Helm repo
helm repo add karpenter https://charts.karpenter.sh
helm repo update

# Install Karpenter
helm install karpenter karpenter/karpenter \
  --namespace kube-system \
  --create-namespace \
  --set settings.aws.defaultInstanceProfile=KarpenterNodeRole \
  --set settings.clusterName=my-cluster \
  --set settings.interruptionQueue=my-cluster \
  --wait
```

## NodePool Configuration

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key:kubernetes.io/arch
          operator: In
          values: [amd64, arm64]
        - key: kubernetes.io/os
          operator: In
          values: [linux]
        - key: karpenter.sh/capacity-type
          operator: In
          values: [on-demand, spot]
      limits:
        cpu: 100
        memory: 100Gi
      consolidation:
        enabled: true
      expireAfter: 720h
  weight: 100
```

## Provisioner with Spot

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot]
        - key: kubernetes.io/arch
          operator: In
          values: [amd64]
      limits:
        cpu: 1000
        memory: 1000Gi
      consolidation:
        enabled: true
```

## AWSNodeTemplate

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: AWSNodeTemplate
metadata:
  name: default
spec:
  subnetSelector:
    karpenter.sh/discovery: my-cluster
  securityGroupSelector:
    karpenter.sh/discovery: my-cluster
  instanceProfile: KarpenterNodeRole
  tags:
    Name: karpenter-node
```

## Key Features

- **Consolidation**: Automatically replaces underutilized nodes
- **Expiration**: Limits node lifetime to force refresh
- **Multiple instance types**: Reduces spot interruption risk
- **Native Spot support**: Uses Spot when possible for cost savings

## References

- [Karpenter Documentation](https://karpenter.sh/)
- [EKS Workshop - Karpenter](https://www.eksworkshop.com/docs/fundamentals/compute/karpenter/)
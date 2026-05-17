---
title: Compute on EKS
tags: [eks, compute]
date: 2026-05-17
description: Compute options on EKS - Managed Node Groups, Fargate, Karpenter, EKS Auto Mode, Hybrid Nodes
---

# Compute on EKS

## Overview

EKS supports multiple compute options to run your workloads.

## Topics

### [[Kubernetes/eks/compute/managed-node-groups/README|Managed Node Groups]]
EKS-managed EC2 instances for running Kubernetes workloads
- [[Kubernetes/eks/compute/managed-node-groups/basics|Basics]]
- [[Kubernetes/eks/compute/managed-node-groups/cluster-autoscaler|Cluster Autoscaler]]
- [[Kubernetes/eks/compute/managed-node-groups/graviton|Graviton (ARM)]]
- [[Kubernetes/eks/compute/managed-node-groups/spot|Spot Instances]]

### [[Kubernetes/eks/compute/fargate/README|Fargate]]
Serverless compute for Kubernetes pods

### [[Kubernetes/eks/compute/karpenter/README|Karpenter]]
Intelligent auto-provisioning for Kubernetes

### [[Kubernetes/eks/compute/eks-auto-mode/README|EKS Auto Mode]]
Fully managed compute with automatic node management

### [[Kubernetes/eks/compute/hybrid-nodes/README|Hybrid Nodes]]
Run EKS on-premises and at the edge

## Compute Comparison

| Feature | MNG | Fargate | Karpenter | Auto Mode |
|---------|-----|---------|-----------|-----------|
| Management | Partial | Full | Partial | Full |
| Pricing | EC2 | per-pod | EC2 | EC2 + fee |
| GPU support | Yes | No | Yes | Yes |
| ARM support | Yes | Yes | Yes | Yes |

## References

- [EKS Compute Documentation](https://docs.aws.amazon.com/eks/latest/userguide/eks-compute.html)
- [EKS Workshop - Compute](https://www.eksworkshop.com/docs/fundamentals/compute/)
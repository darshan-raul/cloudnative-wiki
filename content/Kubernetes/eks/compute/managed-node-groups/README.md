---
title: Managed Node Groups
tags: [eks, compute, mng]
date: 2026-05-17
description: EKS Managed Node Groups - automatically managed EC2 instances for Kubernetes
---

# Managed Node Groups (MNG)

## Overview

Managed Node Groups let you provision and manage EC2 instances for your EKS cluster. EKS automatically handles node lifecycle operations like updates, patching, and scaling.

## Topics

- [[Kubernetes/eks/compute/managed-node-groups/basics|Basics]] - Creating and managing node groups
- [[Kubernetes/eks/compute/managed-node-groups/cluster-autoscaler|Cluster Autoscaler]] - Auto-scale node groups
- [[Kubernetes/eks/compute/managed-node-groups/graviton|Graviton]] - ARM-based instances for cost savings
- [[Kubernetes/eks/compute/managed-node-groups/spot|Spot Instances]] - Cost optimization with interruption handling

## Key Features

- Automatic OS patching and security updates
- EKS-optimized Amazon Linux/Windows AMIs
- Graceful node drain before termination
- Support for custom AMIs via launch templates
- Integration with capacity block for ML

## References

- [EKS Managed Node Groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)
- [EKS Workshop - Managed Node Groups](https://www.eksworkshop.com/docs/fundamentals/compute/managed-node-groups/)
---
title: EKS Hybrid Nodes
tags: [eks, compute, hybrid-nodes]
date: 2026-05-17
description: Run EKS on-premises and at the edge with Hybrid Nodes
---

# EKS Hybrid Nodes

## Overview

EKS Hybrid Nodes extend EKS to on-premises and edge locations using physical or virtual machines.

## Key Use Cases

- Edge computing (retail, manufacturing, telecom)
- On-premises data center integration
- Low-latency local processing
- Data residency requirements

## Architecture

```
EKS Cluster (AWS)
    |
    |-- Cloud Nodes (EC2 - MNG, Karpenter, Fargate)
    |
    |-- Hybrid Nodes (On-premises VMs or bare metal)
```

## Requirements

- VPN or Direct Connect to AWS
- Hybrid node machines must meet requirements
- EKS Connector installed in cluster

## Setup Overview

1. Create EKS cluster (if not exists)
2. Install EKS Connector
3. Prepare on-premises machines
4. Register hybrid nodes with cluster

## Limitations

- Pod networking uses custom CNI configuration
- EBS volumes not supported
- EFS not supported
- Some AWS service integrations may differ

## References

- [EKS Hybrid Nodes](https://docs.aws.amazon.com/eks/latest/userguide/hybrid-nodes-overview.html)
- [EKS Workshop - Hybrid Nodes](https://www.eksworkshop.com/docs/networking/eks-hybrid-nodes/)
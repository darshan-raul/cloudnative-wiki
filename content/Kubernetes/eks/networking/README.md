---
title: Networking on EKS
tags: [eks, networking]
date: 2026-05-17
description: Networking topics for EKS - VPC CNI, Security Groups for Pods, VPC Lattice
---

# Networking on EKS

## Overview

EKS networking integrates with Amazon VPC for pod networking, with support for advanced features like network policies and security groups for pods.

## Topics

### [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]]
Amazon VPC Container Network Interface plugin
- [[Kubernetes/eks/networking/vpc-cni/security-groups-for-pods|Security Groups for Pods]]
- [[Kubernetes/eks/networking/vpc-cni/network-policies|Network Policies]]
- [[Kubernetes/eks/networking/vpc-cni/custom-networking|Custom Networking]]
- [[Kubernetes/eks/networking/vpc-cni/prefix-delegation|Prefix Delegation]]

### [[Kubernetes/eks/networking/vpc-lattice/README|VPC Lattice]]
Service mesh and service networking for EKS

## Architecture

```
Pod --> ENI (Elastic Network Interface) --> VPC --> External
     |
     |-- Security Groups
     |-- VPC CNI assigns IPs from VPC CIDR
```

## Key Components

| Component | Purpose |
|-----------|---------|
| VPC CNI | Pod networking within VPC |
| kube-proxy | Service load balancing |
| CoreDNS | Cluster DNS resolution |
| AWS LB Controller | Ingress and Load Balancer management |

## References

- [EKS Networking](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking.html)
- [EKS Workshop - Networking](https://www.eksworkshop.com/docs/networking/)
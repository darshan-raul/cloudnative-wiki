---
title: Troubleshooting EKS
tags: [eks, troubleshooting]
date: 2026-05-17
description: Common EKS issues and how to resolve them
---

# Troubleshooting EKS

## Common Issues

### [[Kubernetes/eks/troubleshooting/common-issues|Common Issues and Solutions]]
Frequently encountered EKS problems and resolutions

### [[Kubernetes/eks/troubleshooting/support-resources|Support Resources]]
AWS support, documentation, and community resources

## Quick Diagnostics

```bash
# Check cluster status
aws eks describe-cluster --name my-cluster --query 'cluster.status'

# Check nodes
kubectl get nodes

# Check pods in kube-system
kubectl get pods -n kube-system

# View node conditions
kubectl get nodes -o wide --show-labels

# Check system logs
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=100
kubectl logs -n kube-system -l k8s-app=aws-node --tail=100
```

## References

- [EKS Troubleshooting](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [EKS Workshop - Troubleshooting](https://www.eksworkshop.com/docs/troubleshooting/)
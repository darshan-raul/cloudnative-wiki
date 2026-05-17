---
title: EKS Cluster Upgrade Process
tags: [eks, cluster-upgrades, process]
date: 2026-05-17
description: Step-by-step EKS cluster upgrade process
---

# EKS Cluster Upgrade Process

## Pre-upgrade Checklist

### 1. Review Kubernetes Changes
- Read Kubernetes release notes for target version
- Check [EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- Identify deprecated APIs

### 2. Check Addon Compatibility

```bash
# List addons and versions
aws eks describe-addon-versions \
  --kubernetes-version 1.30 \
  --addons-name aws-ebs-csi-driver

# Check VpcCni version
kubectl describe daemonset aws-node -n kube-system | grep Image
```

### 3. Update Addons First

```bash
# Update VPC CNI
aws eks update-addon \
  --cluster-name my-cluster \
  --addon-name vpc-cni \
  --addon-version latest \
  --resolve-conflicts

# Update CoreDNS
kubectl rollout restart -n kube-system deployment/coredns

# Update kube-proxy
kubectl rollout restart -n kube-system deployment/kube-proxy
```

### 4. Review Applications
```bash
# Check for deprecated APIs
kubectl api-resources
kubectl get all -A -o yaml > pre-upgrade-backup.yaml
```

## Upgrade Steps

### 1. Upgrade Control Plane

```bash
# Update cluster version
aws eks update-cluster-version \
  --name my-cluster \
  --kubernetes-version 1.30 \
  --profile my-profile

# Monitor upgrade status
aws eks describe-cluster \
  --name my-cluster \
  --query 'cluster.status'

# Wait for completion
aws eks wait cluster-active --name my-cluster
```

### 2. Upgrade Managed Node Groups

```bash
# Update each node group
aws eks update-nodegroup-version \
  --cluster-name my-cluster \
  --nodegroup-name standard-workers \
  --kubernetes-version 1.30

# Or use eksctl
eksctl upgrade nodegroup \
  --cluster my-cluster \
  --name standard-workers \
  --kubernetes-version 1.30
```

### 3. Verify Upgrade

```bash
# Check cluster version
kubectl version --short
kubectl get nodes

# Check pod status
kubectl get pods -A | grep -v Running

# Verify addons
kubectl get pods -n kube-system
```

## Post-upgrade Tasks

1. **Test applications** - Verify workloads function correctly
2. **Update kubectl** - Ensure local kubectl matches cluster version
3. **Update Helm charts** - Update to latest chart versions
4. **Update CI/CD** - Update kubectl versions in pipelines

## Rollback

Node group can be rolled back to previous version if issues occur:

```bash
# Rollback node group
aws eks update-nodegroup-version \
  --cluster-name my-cluster \
  --nodegroup-name standard-workers \
  --kubernetes-version 1.29 \
  --force
```

Control plane cannot be rolled back.

## References

- [Updating an EKS cluster](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html)
- [AWS EKS Upgrade Workshop](https://catalog.us-east-1.prod.workshops.aws/workshops/693bdee4-bc31-41d5-841f-54e3e54f8f4a/en-US)
---
title: Custom Networking
tags: [eks, networking, vpc-cni, custom-networking]
date: 2026-05-17
description: Custom networking with VPC CNI for EKS
---

# Custom Networking with VPC CNI

## Overview

Custom networking allows pods to use secondary CIDR blocks instead of the primary VPC CIDR, useful for IP address conservation.

## Use Cases

- Large-scale deployments requiring more IPs
- Isolating pod traffic to specific CIDR
- IP address space reuse across clusters

## Configuration

### Enable Custom Networking

```bash
# Set CNI configuration
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
```

### Create ENIConfig for Custom Subnet

```yaml
apiVersion: crd.k8s.aws/v1alpha1
kind: ENIConfig
metadata:
  name: my-custom-subnet
spec:
  subnet: subnet-0123456789abcdef0
  securityGroups:
    - sg-0123456789abcdef0
```

### Assign ENIConfig to Nodes

```yaml
apiVersion: v1
kind: Node
metadata:
  labels:
    k8s.amazonaws.com/eniConfig: my-custom-subnet
```

## Node Group with ENIConfig

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
  region: us-west-2
managedNodeGroups:
  - name: custom-networking
    instanceType: t3.medium
    labels:
      k8s.amazonaws.com/eniConfig: my-custom-subnet
    annotations:
      k8s.amazonaws.com/eniConfig: my-custom-subnet
```

## Limitations

- Requires secondary CIDR block attached to VPC
- Custom subnet must be in same AZ as nodes
- Security groups work differently with custom networking

## References

- [Custom Networking](https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html)
- [EKS Workshop - Custom Networking](https://www.eksworkshop.com/docs/networking/vpc-cni/custom-networking/)
---
title: Amazon VPC CNI
tags: [eks, networking, vpc-cni]
date: 2026-05-17
description: Amazon VPC CNI plugin for Kubernetes networking - architecture, configuration, and troubleshooting
---

# Amazon VPC CNI

## Overview

The Amazon VPC CNI plugin assigns IP addresses from the VPC to each pod, providing native VPC networking. Unlike overlay CNIs (Cilium, Calico in overlay mode), VPC CNI pods appear as regular EC2 instances in your VPC - they have ENIs and IPs directly from your VPC CIDR.

## Architecture

VPC CNI has two main components running in the `aws-node` DaemonSet:

| Component | Container | Purpose |
|-----------|-----------|---------|
| **CNI Plugin** | `aws-cni` | Wires up host/pod network stack when called by kubelet |
| **ipamd** | `aws-node` | Long-running daemon managing IP address allocation |

### CNI Plugin Flow

When kubelet creates a pod, it calls the CNI plugin to configure networking:

```
1. kubelet → CNI plugin (ADD command)
2. CNI plugin → ipamd (via Unix socket /var/run/aws-node/ipam.sock)
3. ipamd → EC2 API (Allocate address)
4. CNI plugin → configures veth pair, routes, iptables
5. Response back to kubelet
```

### ipamd Daemon

The IP Address Management (IPAMD) daemon is responsible for:
- Maintaining warm pool of ENIs and IP addresses
- Tracking assigned/free IPs in `/var/run/aws-node/ipam.json`
- Reconciling desired state with actual EC2 state

### VPC Resource Controller

A separate controller (`vpc-resource-controller`) running on the EKS control plane handles:
- Branch network interface attachment for Security Groups for Pods
- Advertising branch ENIs as extended resources (`vpc.amazonaws.com/pod-enis`)

## Pod Networking Flow

```
Pod ←→ veth0 (host) ←→ eth0 (node)
                          │
                     Primary ENI ←→ VPC
                          │
              Secondary IPs → assigned to pods
```

## IP Limits by Instance Type

| Instance Type | Max ENIs | IPs per ENI | Max Pods* |
|---------------|----------|-------------|----------|
| t3.medium | 3 | 6 | 17 |
| t3.large | 3 | 10 | 27 |
| m5.large | 3 | 10 | 27 |
| m5.xlarge | 4 | 15 | 57 |
| m5.2xlarge | 4 | 15 | 57 |
| c5.2xlarge | 4 | 15 | 57 |
| c5.4xlarge | 8 | 15 | 57 |
| r5.xlarge | 4 | 15 | 57 |

\* *Max pods formula: `(ENIs × IPs_per_ENI) - 1` + 2 for kubelet reserved IPs*

## Sub-commands for Debugging

```bash
# Check pod networking - list ENIs and IPs
kubectl exec -n kube-system aws-node-xxxx -- aws ec2 describe-network-interfaces \
  --filters "Name=tag:Name,Values=*-eni-*"

# Check ipamd state
kubectl exec -n kube-system aws-node-xxxx -- cat /var/run/aws-node/ipam.json

# View CNI logs
kubectl logs -n kube-system -l k8s-app=aws-node -c aws-cni

# View ipamd logs
kubectl logs -n kube-system -l k8s-app=aws-node -c aws-node

# Check introspection endpoint
kubectl exec -n kube-system aws-node-xxxx -- wget -O- 127.0.0.1:61679/stats

# Verify node max pods setting
kubectl get nodes -o custom-columns=NAME:.metadata.name,MAX_PODS:.status.capacity.pods
```

## VPC CNI Version Requirements

| Kubernetes Version | Minimum VPC CNI Version |
|--------------------|------------------------|
| 1.35 | v1.21.1-eksbuild.8 |
| 1.34 | v1.21.1-eksbuild.8 |
| 1.33 | v1.21.1-eksbuild.8 |
| 1.32 | v1.21.1-eksbuild.8 |
| 1.31 | v1.21.1-eksbuild.8 |
| 1.30 | v1.21.1-eksbuild.8 |
| 1.29 | v1.21.1-eksbuild.8 |

## Related Topics

- [[Kubernetes/eks/networking/vpc-cni/architecture|Architecture Deep-Dive]] - Internal components, CNI plugin flow
- [[Kubernetes/eks/networking/vpc-cni/eni-allocation|ENI/IP Allocation]] - Warm pools, WARM_* targets
- [[Kubernetes/eks/networking/vpc-cni/prefix-delegation|Prefix Delegation]] - Increase pod density with /28 prefixes
- [[Kubernetes/eks/networking/vpc-cni/security-groups-for-pods|Security Groups for Pods]] - Per-pod security groups
- [[Kubernetes/eks/networking/vpc-cni/network-policies|Network Policies]] - Pod traffic control
- [[Kubernetes/eks/networking/vpc-cni/custom-networking|Custom Networking]] - Alternate subnets for pods
- [[Kubernetes/eks/networking/vpc-cni/troubleshooting|Troubleshooting]] - Debugging CNI issues
- [[Kubernetes/eks/networking/vpc-cni/configuration-reference|Configuration Reference]] - All env vars

## References

- [VPC CNI GitHub](https://github.com/aws/amazon-vpc-cni-k8s)
- [EKS VPC CNI Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-networking.html)
- [EKS Workshop - VPC CNI](https://www.eksworkshop.com/docs/networking/vpc-cni/)
- [EKS Best Practices - Networking](https://aws.github.io/aws-eks-best-practices/networking/)
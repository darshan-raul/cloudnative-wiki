---
title: Amazon EKS
tags: [eks, aws, kubernetes]
date: 2026-05-17
description: Amazon Elastic Kubernetes Service - managed Kubernetes on AWS
---

# Amazon EKS

[Amazon Elastic Kubernetes Service (EKS)](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html) provides a fully managed Kubernetes control plane with high availability, security, and scalability.

## Categories

### [[Kubernetes/eks/getting-started/README|1. Getting Started]]
Tools, prerequisites, cluster creation, first application deployment

### [[Kubernetes/eks/compute/README|2. Compute]]
Managed Node Groups, Fargate, Karpenter, EKS Auto Mode, Hybrid Nodes

### [[Kubernetes/eks/networking/README|3. Networking]]
VPC CNI, Security Groups for Pods, Network Policies, VPC Lattice

### [[Kubernetes/eks/storage/README|4. Storage]]
EBS CSI, EFS CSI, FSx for NetApp ONTAP, FSx for OpenZFS, Mountpoint for S3

### [[Kubernetes/eks/security/README|5. Security]]
Cluster Access Management, IRSA, Pod Identity, Secrets Management, GuardDuty, Pod Security Standards

### [[Kubernetes/eks/observability/README|6. Observability]]
Control Plane Logs, Pod Logging, CloudWatch Container Insights, Prometheus, ADOT, Kubecost

### [[Kubernetes/eks/cluster-upgrades/README|7. Cluster Upgrades]]
Upgrade process, best practices, upgrade journey experiences

### [[Kubernetes/eks/automation/README|8. Automation]]
GitOps (Flux, Argo CD), ACK, Crossplane, CodePipeline

### [[Kubernetes/eks/advanced/README|9. Advanced]]
Advanced autoscaling (HPA, VPA, KEDA), Advanced networking, Cost optimization

### [[Kubernetes/eks/troubleshooting/README|10. Troubleshooting]]
Common issues, support resources

## Quick Reference

### Common Commands

```bash
# Create cluster
eksctl create cluster --name my-cluster --region us-west-2

# Update kubeconfig
aws eks update-kubeconfig --name my-cluster

# List nodegroups
aws eks list-nodegroups --cluster-name my-cluster

# Scale nodegroup
eksctl scale nodegroup --cluster my-cluster --name workers --nodes 5
```

### Key Addons

| Addon | Purpose |
|-------|---------|
| vpc-cni | Pod networking |
| coredns | DNS service |
| kube-proxy | Service networking |
| aws-ebs-csi-driver | Block storage |
| aws-efs-csi-driver | File storage |

## External Resources

- [EKS Workshop](https://www.eksworkshop.com/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [EKS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/)
- [EKS Upgrade Workshop](https://catalog.us-east-1.prod.workshops.aws/workshops/693bdee4-bc31-41d5-841f-54e3e54f8f4a/en-US)
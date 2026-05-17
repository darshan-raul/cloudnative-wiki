---
title: Cluster Creation
tags: [eks, getting-started, cluster]
date: 2026-05-17
description: Creating EKS clusters using eksctl, Terraform, and AWS Console
---

# Cluster Creation

## Using eksctl (Recommended)

### Basic Cluster
```bash
eksctl create cluster \
  --name my-cluster \
  --region us-west-2 \
  --without-nodegroup
```

### Cluster with Managed Node Group
```bash
eksctl create cluster \
  --name my-cluster \
  --region us-west-2 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed
```

### Cluster with Fargate
```bash
eksctl create cluster \
  --name my-cluster \
  --region us-west-2 \
  --fargate
```

### Cluster with Karpenter
```bash
eksctl create cluster \
  --name my-cluster \
  --region us-west-2 \
  --with-karpenter
```

## Using Terraform

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "my-cluster"
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    standard = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 4
      desired_size   = 2
    }
  }
}
```

## Using AWS Console

1. Navigate to EKS in AWS Console
2. Click "Create cluster"
3. Configure:
   - Name and Kubernetes version
   - IAM role for EKS service
   - VPC and subnets
   - Security groups
   - Endpoint access (public/private)
4. Click "Create"

## Cluster Configuration Options

### Endpoint Access
| Type | Control Plane | Worker Nodes |
|------|---------------|--------------|
| Public | Public endpoint | Same VPC |
| Private | Private endpoint only | Private subnets |
| Public & Private | Both endpoints | Private subnets |

### Networking Considerations
- At least 2 subnets in different AZs
- Subnets must have DNS hostnames enabled
- Consider NAT Gateway costs for private-only clusters
- Security groups must allow EKS control plane communication

## References

- [Creating an EKS cluster with eksctl](https://docs.aws.amazon.com/eks/latest/userguide/creating-a-cluster-with-eksctl.html)
- [EKS Cluster VPC Requirements](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)
- [EKS Workshop - Cluster Creation](https://www.eksworkshop.com/docs/introduction/getting-started/)
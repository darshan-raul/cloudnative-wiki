---
title: Creating an EKS Cluster
tags: [eks, getting-started, eksctl, terraform, cluster-creation]
date: 2026-05-17
description: Creating an EKS cluster with eksctl, Terraform or the console — what each produces, a production-leaning configuration explained line by line, what exists afterwards, verification, and the settings that are hard to change later.
---

# Creating an EKS Cluster

Creating a cluster is a single API call followed by about ten minutes of waiting. The decisions around it matter more than the command: where it runs, who can reach it, and how nodes are provided. Make sure the [[Kubernetes/eks/getting-started/prerequisites|prerequisites]] are in place first.

## Three ways to create one

| Method               | Best for                           | Trade-off                                                                    |
| :------------------- | :--------------------------------- | :--------------------------------------------------------------------------- |
| `eksctl`             | Learning, experiments, small teams | Drives CloudFormation; harder to integrate with existing infrastructure code |
| Terraform / OpenTofu | Anything long-lived                | More to write, but reviewable, repeatable and composable                     |
| Console              | Seeing the options once            | Not reproducible                                                             |

Whichever you choose, the result should end up as code in a repository. A cluster built by hand cannot be rebuilt after a disaster or recreated for a [[Kubernetes/eks/cluster-upgrades/upgrade-process|blue-green upgrade]].

## With eksctl

The one-liner creates a new VPC, the cluster and compute:

```bash
eksctl create cluster --name my-cluster --region eu-west-1 --enable-auto-mode
```

A config file is better, because it can be reviewed and re-applied:

```yaml
# cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
  region: eu-west-1
  version: "1.34"
  tags: { team: platform, environment: dev }

vpc:
  cidr: 10.0.0.0/16
  nat: { gateway: HighlyAvailable } # one NAT gateway per zone
  clusterEndpoints:
    publicAccess: true
    privateAccess: true
  publicAccessCIDRs: ["203.0.113.0/24"]

accessConfig:
  authenticationMode: API
  bootstrapClusterCreatorAdminPermissions: false
  accessEntries:
    - principalARN: arn:aws:iam::111122223333:role/platform-admin
      accessPolicies:
        - policyARN: arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
          accessScope: { type: cluster }

secretsEncryption:
  keyARN: arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab

cloudWatch:
  clusterLogging:
    enableTypes: ["audit", "authenticator", "api"]

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: eks-pod-identity-agent
  - name: aws-ebs-csi-driver

managedNodeGroups:
  - name: general
    amiFamily: AmazonLinux2023
    instanceTypes: ["m7g.large", "m6g.large"]
    minSize: 2
    desiredCapacity: 3
    maxSize: 6
    privateNetworking: true
    volumeSize: 80
```

```bash
eksctl create cluster -f cluster.yaml
```

What the important lines do:

| Setting                                          | Why                                                                                                                     |
| :----------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------- |
| `version`                                        | Pin it. Otherwise you get whatever is the default that day.                                                             |
| `clusterEndpoints` and `publicAccessCIDRs`       | Keep the API reachable from your network only — [[Kubernetes/eks/security/access/endpoint-access\|endpoint access]]     |
| `authenticationMode: API`                        | Use [[Kubernetes/eks/security/access/cluster-access-management\|access entries]], not the legacy ConfigMap              |
| `bootstrapClusterCreatorAdminPermissions: false` | Admin goes to a named role, not to whoever ran the command                                                              |
| `secretsEncryption`                              | Envelope-encrypt Secrets with your own [[AWS/security/kms/README\|KMS]] key                                             |
| `clusterLogging`                                 | Audit logs exist before you need them — [[Kubernetes/eks/observability/logging/control-plane-logs\|control plane logs]] |
| `privateNetworking: true`                        | Nodes in private subnets with no public IPs                                                                             |
| `addons`                                         | Managed add-ons are versioned and upgradable through the EKS API                                                        |

To use Auto Mode instead of node groups, replace `managedNodeGroups` and the compute and storage add-ons with `autoModeConfig: { enabled: true }` — [[Kubernetes/eks/compute/eks-auto-mode/README|EKS Auto Mode]].

## With Terraform

The community `terraform-aws-modules/eks` module covers the same ground:

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "my-cluster"
  kubernetes_version = "1.34"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["203.0.113.0/24"]

  enable_cluster_creator_admin_permissions = false
  access_entries = {
    platform = {
      principal_arn = "arn:aws:iam::111122223333:role/platform-admin"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }
}
```

Keep the VPC, the cluster and the workloads in **separate states**, so a change to an application's queue cannot plan a change to the cluster — [[DevOps/infrastructure-as-code/terraform-state-and-collaboration|Terraform state and collaboration]]. Install in-cluster software with GitOps rather than Terraform's Helm provider where you can; mixing the two creates ordering and drift problems. See [[DevOps/infrastructure-as-code/terraform|Terraform]].

## What exists afterwards

| Resource                                                              | Notes                                                         |
| :-------------------------------------------------------------------- | :------------------------------------------------------------ |
| Control plane                                                         | Managed by AWS, billed per hour                               |
| Cluster security group                                                | Attached to the control plane ENIs and, by default, to nodes  |
| ENIs in your subnets                                                  | How the control plane reaches nodes and webhooks              |
| OIDC issuer URL                                                       | Used by [[Kubernetes/eks/security/iam-roles-for-sa\|IRSA]]    |
| Cluster and node IAM roles                                            | Created by `eksctl`; you supply or create them with Terraform |
| Nodes or Auto Mode node pools                                         | Billed as EC2                                                 |
| With `eksctl`: a VPC, subnets, NAT gateways and CloudFormation stacks | The NAT gateways are a noticeable cost                        |

## Verify

```bash
aws eks describe-cluster --name my-cluster \
  --query 'cluster.{status:status,version:version,endpoint:endpoint,auth:accessConfig.authenticationMode}'

aws eks update-kubeconfig --name my-cluster --region eu-west-1
kubectl get nodes -o wide
kubectl get pods -n kube-system
aws eks list-addons --cluster-name my-cluster
```

All nodes `Ready` and all `kube-system` pods `Running` means the cluster is usable. If nodes never appear, see [[Kubernetes/eks/troubleshooting/common-issues|common EKS issues]].

## Hard to change later

| Decision                                   | Changeable?                            |
| :----------------------------------------- | :------------------------------------- |
| IP family (IPv4 or IPv6)                   | No                                     |
| The VPC                                    | No; subnets can be added               |
| Cluster name                               | No                                     |
| Secrets encryption key                     | Can be enabled, not removed or swapped |
| Authentication mode                        | Forward only                           |
| Kubernetes version                         | Upward only, one minor at a time       |
| Endpoint access, logging, add-ons, compute | Yes                                    |

Subnet sizing deserves the most thought, because every pod uses a VPC address — [[Kubernetes/eks/networking/README|EKS networking]].

## Next

[[Kubernetes/eks/getting-started/first-application|Deploy your first application]].

## Related

- [[Kubernetes/eks/getting-started/README|Getting started with EKS]]
- [[Kubernetes/eks/compute/README|Compute options]]
- [[DevOps/infrastructure-as-code/README|Infrastructure as code]]
- [Create a cluster with eksctl](https://docs.aws.amazon.com/eks/latest/userguide/creating-a-cluster-with-eksctl.html)
- [EKS network requirements](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)
- [EKS Workshop: getting started](https://www.eksworkshop.com/docs/introduction/getting-started/)

## Across the wiki

- [[AWS/management-governance/cloudformation/README|AWS CloudFormation]] — infrastructure as code (AWS)
- [[DevOps/devsecops/stage2-build/10-iac-security|M10: Infrastructure-as-Code Security]] — infrastructure as code (DevOps)
- [[AWS/management-governance/cdk/README|AWS CDK]] — infrastructure as code (AWS)

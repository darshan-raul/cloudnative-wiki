---
title: EKS Tools and Prerequisites
tags: [eks, getting-started, tools, iam, vpc]
date: 2026-05-17
description: What you need before creating an EKS cluster — the command-line tools and what each is for, the IAM permissions and roles involved, VPC and subnet requirements, quotas and a verification checklist.
---

# EKS Tools and Prerequisites

Creating a cluster takes one command. Whether it works — and whether the cluster is usable afterwards — depends on four things being in place first: tools, identity, network and quotas.

If Kubernetes itself is new, start with [[Kubernetes/concepts/L00-start-here/00-start-here|Start Here]] on a local `kind` cluster. EKS adds AWS concerns on top; it does not replace the fundamentals.

## Tools

| Tool                 | Purpose                                                                     | Needed?                  |
| :------------------- | :-------------------------------------------------------------------------- | :----------------------- |
| AWS CLI v2           | Talks to AWS; issues the token `kubectl` uses to authenticate               | Yes                      |
| `kubectl`            | Talks to the Kubernetes API                                                 | Yes                      |
| `eksctl`             | Creates clusters and node groups from one YAML file (drives CloudFormation) | Recommended for learning |
| Helm                 | Installs most add-ons                                                       | Yes, in practice         |
| Terraform / OpenTofu | Manages the cluster as code                                                 | For anything long-lived  |
| `k9s`                | Terminal UI for day-to-day work                                             | Optional                 |

```bash
aws --version          # aws-cli/2.x
kubectl version --client
eksctl version
helm version --short
```

**Version skew matters.** `kubectl` is supported within one minor version of the API server in either direction. An old client against a new cluster mostly works and then fails in confusing ways on newer resources. More in [[Kubernetes/guides/tools/kubectl|kubectl]] and [[Kubernetes/guides/tools/k9s|k9s]].

## Identity

Confirm who you are before anything else — half of all first-day problems are the wrong profile or account:

```bash
aws sts get-caller-identity
aws configure list
```

Use short-lived credentials from IAM Identity Center (`aws sso login`) rather than long-lived access keys.

### Permissions to create a cluster

Cluster creation touches EKS, EC2, [[AWS/security/iam/README|IAM]], CloudFormation, Auto Scaling and KMS. For a sandbox, an administrator role is the practical choice. For a shared account, use a dedicated provisioning role, and remember it must be allowed to `iam:PassRole` the cluster and node roles.

### The roles EKS itself uses

| Role               | Assumed by            | Managed policies                                                                          |
| :----------------- | :-------------------- | :---------------------------------------------------------------------------------------- |
| Cluster role       | The EKS control plane | `AmazonEKSClusterPolicy`                                                                  |
| Node role          | EC2 worker nodes      | `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryPullOnly`, `AmazonEKS_CNI_Policy` |
| Pod execution role | Fargate, when used    | `AmazonEKSFargatePodExecutionRolePolicy`                                                  |
| Workload roles     | Your pods             | Per application, through [[Kubernetes/eks/security/pod-identity\|Pod Identity]]           |

`eksctl` creates the first two for you. See [[AWS/security/iam/various-types-of-roles|types of IAM roles]] for the distinction between service roles and the roles people assume.

### Who can use the cluster afterwards

IAM permission to _create_ a cluster and Kubernetes permission to _use_ it are separate. Plan from the start which roles get [[Kubernetes/eks/security/access/cluster-access-management|access entries]], so access does not depend on whoever happened to run the create command.

## Network

EKS runs in a [[AWS/networking/vpc/README|VPC]] you provide.

| Requirement                                | Why                                                                                          |
| :----------------------------------------- | :------------------------------------------------------------------------------------------- |
| Subnets in at least two Availability Zones | The control plane places its ENIs across zones                                               |
| DNS hostnames and DNS resolution enabled   | Nodes find the API endpoint by name                                                          |
| Enough free IP addresses                   | **Every pod takes a VPC IP.** A /24 holds about 250 pods and nodes combined                  |
| Outbound access from node subnets          | Pull images and call AWS APIs: a NAT gateway, or VPC endpoints for a private cluster         |
| Subnet tags for load balancers             | `kubernetes.io/role/elb=1` on public subnets, `kubernetes.io/role/internal-elb=1` on private |

Address planning is the decision that is hardest to change later. Size subnets for the pod count you expect in two years, not today, and read [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]] to see why. A good default is nodes in private /19 or /20 subnets and only load balancers in small public subnets.

Choose the API endpoint exposure deliberately: public, public restricted to known CIDRs, or private — [[Kubernetes/eks/security/access/endpoint-access|endpoint access]].

## Quotas

Check Service Quotas in the target region before a workshop or a launch:

- **Running On-Demand instances** (counted in vCPUs, per instance family) — the one that most often stops a node group from scaling.
- **Elastic IPs** — one per NAT gateway; the default is five per region.
- **VPCs per region** — default five, and `eksctl` creates a new one unless told otherwise.
- **EKS clusters per region**, and **ENIs per region** for dense clusters.

## Decide before you create

| Decision               | Options                                                                                             | Easy to change later?                           |
| :--------------------- | :-------------------------------------------------------------------------------------------------- | :---------------------------------------------- |
| Kubernetes version     | A version in standard support; avoid starting on one about to enter extended support                | Upgrade only, one minor at a time               |
| Compute model          | [[Kubernetes/eks/compute/eks-auto-mode/README\|Auto Mode]], managed node groups, Karpenter, Fargate | Yes                                             |
| IP family              | IPv4 or IPv6                                                                                        | **No**                                          |
| VPC and subnets        | New or existing                                                                                     | Subnets can be added; the VPC cannot be swapped |
| Authentication mode    | `API` (access entries)                                                                              | Forward only                                    |
| Secrets encryption key | AWS-owned or your own [[AWS/security/kms/README\|KMS]] key                                          | Can be added, not removed                       |
| Endpoint access        | Public, private or both                                                                             | Yes                                             |

## Checklist

```bash
# Right account and region?
aws sts get-caller-identity && aws configure get region

# Subnets: at least two zones, with free addresses
aws ec2 describe-subnets --filters Name=vpc-id,Values=vpc-0abc \
  --query 'Subnets[].{az:AvailabilityZone,cidr:CidrBlock,free:AvailableIpAddressCount}' --output table

# Supported Kubernetes versions
aws eks describe-cluster-versions --query 'clusterVersions[].{v:clusterVersion,status:versionStatus}' --output table
```

Next: [[Kubernetes/eks/getting-started/cluster-creation|create the cluster]].

## Related

- [[Kubernetes/eks/getting-started/README|Getting started with EKS]]
- [[Kubernetes/eks/compute/README|Compute options]]
- [[AWS/compute/eks/README|EKS in the AWS section]]
- [[AWS/management-governance/cli/README|AWS CLI]]
- [Set up to use Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/setting-up.html)

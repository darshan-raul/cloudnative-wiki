---
title: Getting Started with EKS
tags: [eks, getting-started]
date: 2026-05-17
description: A three-step path to a first working EKS cluster — prerequisites, cluster creation and a first deployment — with what EKS manages versus what you own, what it costs to leave running, and where to go next.
---

# Getting Started with EKS

Amazon EKS runs the Kubernetes control plane for you. This section takes you from nothing to an application reachable through an AWS load balancer, and points out along the way where EKS differs from the Kubernetes you may have learned on a laptop.

If Kubernetes itself is new, do [[Kubernetes/concepts/L00-start-here/00-start-here|Start Here]] first on a local `kind` cluster. It is free, fast, and everything learned there carries over.

## What EKS gives you, and what stays yours

| AWS operates                                         | You operate                                                                                                                                    |
| :--------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------- |
| API server and etcd, across three Availability Zones | Worker nodes — unless you use [[Kubernetes/eks/compute/eks-auto-mode/README\|Auto Mode]] or [[Kubernetes/eks/compute/fargate/README\|Fargate]] |
| Control plane scaling, patching and backups          | Add-ons: CNI, DNS, storage drivers, ingress                                                                                                    |
| The Kubernetes version upgrade, when you trigger it  | Deciding when to upgrade, and upgrading nodes and add-ons                                                                                      |
| Integration points with IAM, VPC and load balancers  | Everything you deploy, and its security and cost                                                                                               |

The mental shift from a local cluster is that an EKS cluster lives inside a [[AWS/networking/vpc/README|VPC]] and an [[AWS/security/iam/README|IAM]] boundary. Pods get real VPC addresses, access is granted to IAM principals, and Services of type `LoadBalancer` create billable AWS resources.

## The path

### 1. [[Kubernetes/eks/getting-started/prerequisites|Tools & Prerequisites]]

Install the AWS CLI, `kubectl`, `eksctl` and Helm; confirm your identity and permissions; and check the VPC, subnet and quota requirements. Also covers the decisions that are hard to change later, such as IP family and address planning.

### 2. [[Kubernetes/eks/getting-started/cluster-creation|Cluster Creation]]

Create a cluster with `eksctl`, the console or infrastructure as code, and understand what was created on your behalf.

### 3. [[Kubernetes/eks/getting-started/first-application|Deploying Your First Application]]

Connect `kubectl`, deploy a workload, expose it through an Application Load Balancer, give it AWS permissions, and clean up in the right order.

## What it costs to leave running

A learning cluster is not free, and forgotten ones are a common surprise:

| Item            | Notes                                                           |
| :-------------- | :-------------------------------------------------------------- |
| Control plane   | A fixed hourly charge per cluster, whether or not anything runs |
| Worker nodes    | Normal EC2 prices; the largest part for most clusters           |
| NAT gateway     | Hourly plus per-GB — often more than a small node               |
| Load balancers  | Hourly per load balancer, created by Services and Ingresses     |
| EBS volumes     | Persist after pods are gone unless the claim is deleted         |
| CloudWatch logs | If control plane or container logging is enabled                |

Delete Kubernetes Services, Ingresses and PersistentVolumeClaims **before** deleting the cluster, or the AWS resources behind them are orphaned and keep billing.

## Where to go next

| You want to                               | Read                                                         |
| :---------------------------------------- | :----------------------------------------------------------- |
| Choose how nodes are provided and scaled  | [[Kubernetes/eks/compute/README\|Compute options]]           |
| Understand pod networking and IP planning | [[Kubernetes/eks/networking/README\|Networking]]             |
| Control who can use the cluster           | [[Kubernetes/eks/security/access/README\|Access management]] |
| Give pods AWS permissions                 | [[Kubernetes/eks/security/pod-identity\|Pod Identity]]       |
| Add persistent storage                    | [[Kubernetes/eks/storage/README\|Storage]]                   |
| See what the cluster is doing             | [[Kubernetes/eks/observability/README\|Observability]]       |
| Deploy with GitOps or a pipeline          | [[Kubernetes/eks/automation/README\|Automation]]             |
| Fix something that is broken              | [[Kubernetes/eks/troubleshooting/README\|Troubleshooting]]   |

## Related

- [[Kubernetes/eks/README|EKS implementation track]]
- [[Kubernetes/concepts/00-hub|Kubernetes concepts hub]]
- [[AWS/compute/eks/README|EKS in the AWS section]]
- [[Kubernetes/labs/00-cluster-setup|Lab 00 — local cluster setup]]

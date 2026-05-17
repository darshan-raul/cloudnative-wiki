---
title: Security on EKS
tags: [eks, security]
date: 2026-05-17
description: Security topics for EKS - Cluster access, IRSA, Pod Identity, Secrets, GuardDuty, PSS
---

# Security on EKS

## Overview

EKS provides multiple layers of security for clusters and workloads. AWS and customers share responsibility for security.

## Topics

### Access Control
- [[Kubernetes/eks/security/cluster-access-management|Cluster Access Management API]] - Manage cluster access
- [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]] - IAM Roles for Service Accounts
- [[Kubernetes/eks/security/pod-identity|EKS Pod Identity]] - Pod-level IAM permissions

### Secrets Management
- [[Kubernetes/eks/security/secrets-management/README|Secrets Management]]
  - [[Kubernetes/eks/security/secrets-management/secrets-manager|AWS Secrets Manager]]
  - [[Kubernetes/eks/security/secrets-management/sealed-secrets|Sealed Secrets]]

### Additional Security
- [[Kubernetes/eks/security/pod-security-standards|Pod Security Standards]]
- [[Kubernetes/eks/security/guardduty|GuardDuty for EKS]]
- [[Kubernetes/eks/security/policy-management|Policy Management (Kyverno)]]

## Shared Responsibility

| AWS Responsible | Customer Responsible |
|-----------------|---------------------|
| Control plane | Node OS hardening |
| Kubernetes software | Container security |
| Managed node updates | Network policies |
| Security patches | IAM configuration |
| etcd encryption | Secrets encryption |

## References

- [EKS Security](https://docs.aws.amazon.com/eks/latest/userguide/security.html)
- [EKS Best Practices - Security](https://aws.github.io/aws-eks-best-practices/security/)
- [EKS Workshop - Security](https://www.eksworkshop.com/docs/security/)
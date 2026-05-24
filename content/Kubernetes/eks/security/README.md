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

### Cluster Access & Authentication
- [[Kubernetes/eks/security/access/README|Access Overview]] - Access patterns overview
- [[Kubernetes/eks/security/access/endpoint-access|Endpoint Access]] - Public/private endpoints, bastion hosts
- [[Kubernetes/eks/security/access/aws-auth-legacy|Legacy aws-auth]] - ConfigMap-based access (legacy)
- [[Kubernetes/eks/security/access/authentication-patterns|Auth Patterns]] - IRSA vs Pod Identity comparison

### Pod Authentication
- [[Kubernetes/eks/security/iam-roles-for-sa|IRSA Deep-Dive]] - OIDC trust, token details, multi-cluster patterns
- [[Kubernetes/eks/security/pod-identity|Pod Identity Deep-Dive]] - EKS-managed credentials, agent architecture

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
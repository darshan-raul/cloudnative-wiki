---
title: Automation on EKS
tags: [eks, automation]
date: 2026-05-17
description: GitOps, Infrastructure as Code, and CI/CD automation for EKS
---

# Automation on EKS

## Overview

EKS supports various automation approaches for deploying applications and managing infrastructure.

## Topics

### GitOps
- [[Kubernetes/eks/automation/gitops/flux|Flux]] - GitOps operator for Kubernetes
- [[Kubernetes/eks/automation/gitops/argocd|Argo CD]] - Declarative GitOps continuous delivery

### Control Planes
- [[Kubernetes/eks/automation/control-planes/ack|AWS Controllers for Kubernetes (ACK)]] - Manage AWS resources from K8s
- [[Kubernetes/eks/automation/control-planes/crossplane|Crossplane]] - Cloud-native control planes
- [[Kubernetes/eks/automation/control-planes/kro|kro]] - Kube Resource Orchestrator

### Continuous Delivery
- [[Kubernetes/eks/automation/continuous-delivery/codepipeline|AWS CodePipeline]] - CI/CD for EKS

## GitOps Workflow

```
Git Repository --> GitOps Operator (Flux/ArgoCD) --> EKS Cluster
      |                         |
      v                         v
  Sync Status              Reconciliation
```

## References

- [EKS Workshop - Automation](https://www.eksworkshop.com/docs/automation/)
- [EKS Capabilities](https://docs.aws.amazon.com/eks/latest/userguide/capabilities.html)
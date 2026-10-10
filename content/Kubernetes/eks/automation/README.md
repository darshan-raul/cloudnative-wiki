---
title: Automation on EKS
tags: [eks, automation, gitops, ci-cd, control-planes]
date: 2026-05-17
description: A map of delivery and infrastructure automation on EKS — pipelines, GitOps controllers and Kubernetes-native control planes — with what each layer is for, how they fit together and how to choose.
---

# Automation on EKS

Automation on EKS answers three separate questions, and the tools here each answer one of them:

| Question                                                    | Layer                   | Tools                                                                                                                                                                                                              |
| :---------------------------------------------------------- | :---------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| How does a commit become a tested, published image?         | **Continuous delivery** | [[Kubernetes/eks/automation/continuous-delivery/codepipeline\|AWS CodePipeline]], or any CI system                                                                                                                 |
| How does the cluster come to match what is declared in Git? | **GitOps**              | [[Kubernetes/eks/automation/gitops/argocd\|Argo CD]], [[Kubernetes/eks/automation/gitops/flux\|Flux]]                                                                                                              |
| How do workloads get the AWS resources they depend on?      | **Control planes**      | [[Kubernetes/eks/automation/control-planes/ack\|AWS Controllers for Kubernetes (ACK)]], [[Kubernetes/eks/automation/control-planes/crossplane\|Crossplane]], [[Kubernetes/eks/automation/control-planes/kro\|kro]] |

## How they fit together

```
commit ─► pipeline: build, test, scan, push image ─► updates the image digest in the config repo
                                                              │
                                              GitOps controller watches the repo
                                                              │
                                    applies Deployments, Services … AND infrastructure requests
                                                              │
                                  control plane controllers create queues, buckets, databases, IAM
```

The pipeline never needs credentials for the cluster, the cluster's desired state is entirely in Git, and infrastructure follows the same review and rollback path as application changes.

## Continuous delivery

- [[Kubernetes/eks/automation/continuous-delivery/codepipeline|AWS CodePipeline]] — an AWS-native pipeline with CodeBuild, the EKS deploy action, access for pipeline roles and private clusters.

For pipeline structure regardless of tool, see [[DevOps/ci-cd/pipeline-design|pipeline design]] and [[DevOps/ci-cd/github-actions|GitHub Actions]].

## GitOps

- [[Kubernetes/eks/automation/gitops/argocd|Argo CD]] — a central controller with a UI; hub-and-spoke deployment to many clusters using IAM instead of static credentials.
- [[Kubernetes/eks/automation/gitops/flux|Flux]] — a controller in every cluster, pull-only, with native Helm releases and SOPS decryption through KMS.

Both are sound. Choose Argo CD when people want visibility and a central view; choose Flux when you want each cluster to converge by itself with no hub. The principles are in [[Kubernetes/guides/delivery/gitops/basics|GitOps basics]].

## Control planes

- [[Kubernetes/eks/automation/control-planes/ack|ACK]] — AWS resources as Kubernetes objects, one controller per service, maintained by AWS.
- [[Kubernetes/eks/automation/control-planes/crossplane|Crossplane]] — multi-cloud providers plus your own APIs defined with compositions.
- [[Kubernetes/eks/automation/control-planes/kro|kro]] — group existing resources into a new API with a single definition; pairs naturally with ACK.

|                         | ACK           | Crossplane          | kro                                 |
| :---------------------- | :------------ | :------------------ | :---------------------------------- |
| Creates cloud resources | Yes, AWS only | Yes, many providers | No — orchestrates other controllers |
| Custom platform APIs    | No            | Yes                 | Yes                                 |
| Learning curve          | Low           | High                | Low                                 |

These complement rather than replace [[DevOps/infrastructure-as-code/terraform|Terraform]]: foundations that change rarely and benefit from a reviewed plan stay there; resources that belong to an application's lifecycle can move to a control plane.

## Managed options

EKS offers Argo CD, ACK and kro as managed **EKS Capabilities**, where AWS runs the controllers outside your cluster. That removes upgrades and scaling of the tooling itself, at the cost of some customisation. Worth considering before self-installing, especially for a hub cluster.

## Choosing a starting point

1. **Start with GitOps for workloads.** It gives the largest gain for the least risk.
2. **Keep infrastructure in Terraform** until teams are clearly blocked waiting for it.
3. **Add ACK** for the few resource types teams request most often.
4. **Add kro or Crossplane** when you want to offer those as simple, opinionated APIs — [[DevOps/platform-engineering/golden-paths|golden paths]].

## Related

- [[Kubernetes/eks/README|EKS implementation track]]
- [[Kubernetes/guides/delivery/index|Delivery guides]]
- [[DevOps/platform-engineering/README|Platform engineering]]
- [[Kubernetes/guides/delivery/progressive-delivery/argo-rollouts|Argo Rollouts]]

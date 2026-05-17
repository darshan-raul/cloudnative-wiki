---
title: Cluster Upgrades
tags: [eks, cluster-upgrades]
date: 2026-05-17
description: Upgrading EKS clusters - process, best practices, and upgrade journey
---

# Cluster Upgrades on EKS

## Overview

Regular cluster upgrades ensure you have the latest features, security patches, and Kubernetes version support.

## Topics

### [[Kubernetes/eks/cluster-upgrades/upgrade-process|Upgrade Process]]
Step-by-step guide for upgrading EKS clusters

### [[Kubernetes/eks/cluster-upgrades/upgrade-journey|Upgrade Journey Series]]
Real-world upgrade experiences from Marcincuber's blog series
- [1.23 to 1.24](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-23-to-1-24-b7b0b1afa5b4)
- [1.25 to 1.26](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-25-to-1-26-electrifying-79b287084eef)
- [1.26 to 1.27](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-26-to-1-27-chill-vibes-46f3f979afac)
- [1.27 to 1.28](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-27-to-1-28-welcoming-planternetes-44985e11463a)
- [1.28 to 1.29](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-28-to-1-29-say-hello-to-mandala-858ae0579f4f)
- [1.29 to 1.30](https://medium.com/@marcincuber/amazon-eks-upgrade-journey-from-1-29-to-1-30-say-hello-to-cute-uwubernetes-eba082199cc4)

## Version Support

| Support Type | Duration |
|--------------|----------|
| Standard | ~14 months (3 K8s versions) |
| Extended | ~26 months (additional 12 months) |

## References

- [EKS Kubernetes Versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [EKS Workshop - Cluster Upgrades](https://www.eksworkshop.com/docs/fundamentals/cluster-upgrades/)
- [AWS EKS Upgrade Workshop](https://catalog.us-east-1.prod.workshops.aws/workshops/693bdee4-bc31-41d5-841f-54e3e54f8f4a/en-US)
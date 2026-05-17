---
title: EKS Upgrade Journey
tags: [eks, cluster-upgrades, journey]
date: 2026-05-17
description: Real-world EKS upgrade journey experiences
---

# EKS Upgrade Journey

## Overview

This section documents real-world EKS cluster upgrade experiences from the community.

## Blog Series: Marcincuber's EKS Upgrade Journey

### [1.23 to 1.24](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-23-to-1-24-b7b0b1afa5b4)
Key learnings from upgrading between Kubernetes 1.23 and 1.24.

### [1.25 to 1.26](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-25-to-1-26-electrifying-79b287084eef)
Key learnings from upgrading between Kubernetes 1.25 and 1.26.

### [1.26 to 1.27](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-26-to-1-27-chill-vibes-46f3f979afac)
Key learnings from upgrading between Kubernetes 1.26 and 1.27.

### [1.27 to 1.28](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-27-to-1-28-welcoming-planternetes-44985e11463a)
Key learnings from upgrading between Kubernetes 1.27 and 1.28.

### [1.28 to 1.29](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-28-to-1-29-say-hello-to-mandala-858ae0579f4f)
Key learnings from upgrading between Kubernetes 1.28 and 1.29.

### [1.29 to 1.30](https://medium.com/@marcincuber/amazon-eks-upgrade-journey-from-1-29-to-1-30-say-hello-to-cute-uwubernetes-eba082199cc4)
Key learnings from upgrading between Kubernetes 1.29 and 1.30.

## Common Upgrade Patterns

1. **Update addons before cluster** - Always update VPC CNI, CoreDNS, kube-proxy first
2. **Node group drain** - Use nodegroup update with proper draining strategy
3. **Test in non-prod** - Validate applications on target version first
4. **Backup before upgrade** - Screenshot important configurations

## Common Issues

| Issue | Solution |
|-------|----------|
| Pod disruption | Use PodDisruptionBudgets |
| Image pull errors | Update image references |
| API deprecation | Update manifests before upgrade |
| Addon failures | Delete and recreate addon |

## Workshop

Practice upgrades in a safe environment:
[AWS EKS Upgrade Workshop](https://catalog.us-east-1.prod.workshops.aws/workshops/693bdee4-bc31-41d5-841f-54e3e54f8f4a/en-US)
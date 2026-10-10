---
title: Advanced EKS Topics
tags: [eks, advanced, networking, autoscaling, cost-optimization]
date: 2026-05-17
description: The three areas where an EKS cluster gets hard at scale — networking, autoscaling and cost — with a guide to which note answers which problem and the order to tackle them in.
---

# Advanced EKS Topics

A small EKS cluster mostly works with defaults. The topics here are what you run into as it grows: address space runs out, scaling is too slow or too jumpy, and the bill needs explaining. Each is a system of interacting settings rather than a single feature, which is why they get their own notes.

Read the fundamentals first: [[Kubernetes/eks/networking/README|networking]], [[Kubernetes/eks/compute/README|compute]] and [[Kubernetes/eks/observability/README|observability]].

## Notes

| Note                                                                 | Start here when                                                                                     |
| :------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------- |
| [[Kubernetes/eks/advanced/advanced-networking\|Advanced Networking]] | Pods cannot get IPs, the cluster must be fully private, CIDRs overlap, or egress must be controlled |
| [[Kubernetes/eks/advanced/autoscaling\|Advanced Autoscaling]]        | Scale-up is too slow for your traffic, or the pod and node autoscalers fight each other             |
| [[Kubernetes/eks/advanced/cost-optimization\|Cost Optimization]]     | You need to know what the cluster costs per team, and how to reduce it without hurting reliability  |

## How the three interact

They are not independent, and optimising one in isolation tends to damage another:

- **Autoscaling and cost.** Aggressive consolidation saves money and increases pod disruption. Generous headroom makes scaling fast and costs idle capacity.
- **Networking and autoscaling.** A scale-out burst needs IP addresses and ENI attachments immediately; a subnet that is nearly full, or warm-pool settings tuned too tightly, turn a scaling event into `Pending` pods.
- **Cost and networking.** Cross-zone traffic, NAT gateway data processing and VPC endpoints are frequently a larger line item than people expect, and are decided by topology, not by instance choice.

A sensible order: make scaling **correct** (right-sized requests, PodDisruptionBudgets, limits), then make it **fast enough**, and only then make it **cheap** — with Spot, Graviton and consolidation, once you can see the effect of each change.

## Prerequisites that pay off everywhere

| Have this in place                                                          | Because                                                        |
| :-------------------------------------------------------------------------- | :------------------------------------------------------------- |
| Resource requests on every container                                        | Scheduling, autoscaling and cost allocation all depend on them |
| PodDisruptionBudgets and more than one replica                              | Every optimisation here moves pods around                      |
| Metrics for IP usage, pending pods, node utilisation and cost per namespace | You cannot tune what you cannot see                            |
| Infrastructure and add-ons defined as code                                  | These settings need to be reproducible and reviewable          |

## Related

- [[Kubernetes/eks/README|EKS implementation track]]
- [[Kubernetes/eks/compute/karpenter/README|Karpenter]] and [[Kubernetes/eks/compute/managed-node-groups/spot|Spot]]
- [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]]
- [[Kubernetes/guides/non-functional/index|Non-functional guides]] — the provider-neutral versions of these topics
- [[AWS/cost-management/README|AWS cost management]]

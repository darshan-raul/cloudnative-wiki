---
title: Fargate vs EC2 for EKS
tags: [eks, compute, fargate, ec2, comparison]
date: 2026-05-17
description: Choosing between Fargate and EC2 nodes for EKS workloads — isolation, operations, start-up time, feature support, a worked cost comparison, and patterns for running both in one cluster.
---

# Fargate vs EC2 for EKS

EKS pods run either on EC2 instances that you (or [[Kubernetes/eks/compute/eks-auto-mode/README|Auto Mode]]) manage, or on [[Kubernetes/eks/compute/fargate/README|Fargate]], where each pod gets its own AWS-managed micro-VM. The choice is per workload, not per cluster: both can coexist, and most clusters that use Fargate use it for a subset.

## Side by side

|                         | EC2 nodes                                                         | Fargate                                                            |
| :---------------------- | :---------------------------------------------------------------- | :----------------------------------------------------------------- |
| Unit you pay for        | The instance, used or not                                         | The pod's requested vCPU and memory, per second                    |
| Isolation               | Pods share a kernel                                               | One micro-VM per pod                                               |
| Node operations         | Patch, scale, right-size (or let Auto Mode do it)                 | None                                                               |
| Pod start-up            | Seconds on a warm node                                            | Typically 30–90 seconds: a VM boots first                          |
| DaemonSets              | Yes                                                               | No — use sidecars                                                  |
| Privileged, host access | Yes                                                               | No                                                                 |
| GPUs, Arm, Windows      | Yes                                                               | No                                                                 |
| Storage                 | [[Kubernetes/eks/storage/ebs-csi\|EBS]], EFS, FSx, instance store | Ephemeral storage and [[Kubernetes/eks/storage/efs-csi\|EFS]] only |
| Pod IAM                 | Pod Identity or IRSA                                              | IRSA only                                                          |
| Spot                    | Yes                                                               | No Fargate Spot on EKS                                             |
| Bin-packing             | Yours to optimise                                                 | Not applicable; each pod is rounded up to a fixed size             |
| Max pod size            | The instance size                                                 | 16 vCPU and 120 GiB                                                |

## Cost: where each wins

Fargate's per-vCPU-hour price is noticeably higher than On-Demand EC2. That comparison is misleading on its own, because on EC2 you also pay for capacity that sits idle.

```
break-even utilisation ≈ EC2 price per vCPU-hour ÷ Fargate price per vCPU-hour
```

If Fargate costs roughly 1.3–1.5 times EC2 per unit, EC2 is cheaper once nodes are more than about 65–75% utilised, and Fargate is cheaper below that. In practice:

| Situation                                                                          | Cheaper option |
| :--------------------------------------------------------------------------------- | :------------- |
| Large, steady workloads on well-packed nodes                                       | EC2            |
| Anything that can run on [[Kubernetes/eks/compute/managed-node-groups/spot\|Spot]] | EC2            |
| A handful of small services that would leave nodes mostly empty                    | Fargate        |
| Bursty jobs that run for minutes a few times a day                                 | Fargate        |
| Workloads on [[Kubernetes/eks/compute/managed-node-groups/graviton\|Graviton]]     | EC2            |

Two details shift the numbers. Fargate rounds each pod **up** to the next supported size and adds 256 MiB for Kubernetes components, so many tiny pods are disproportionately expensive. And on EC2, DaemonSets (CNI, logging, monitoring agents) consume part of every node; on Fargate that overhead moves into per-pod sidecars. Count the engineering time for node operations too — unless Auto Mode already removes it. See [[Kubernetes/eks/advanced/cost-optimization|EKS cost optimization]] and [[AWS/cost-management/pricing-models|pricing models]].

## Operational differences that matter

- **Scaling speed.** With [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]], a new replica on a warm EC2 node is serving in seconds; on Fargate it takes most of a minute. Keep more headroom, or scale on a leading indicator.
- **Observability.** No DaemonSets means the log router is built in ([[Kubernetes/eks/observability/logging/pod-logging|pod logging]]) and metrics agents run as sidecars or scrape remotely.
- **Security.** A VM boundary per pod is a stronger isolation story for untrusted or regulated workloads, and there are no nodes to harden or patch — see [[Kubernetes/concepts/L07-security/02-workload-sandboxing/17-runtime-sandboxing|runtime sandboxing]].
- **Limits.** Fargate pods must run in private subnets, and quotas apply per account on concurrent Fargate vCPUs.

## Mixing them in one cluster

A Fargate profile selects pods by namespace and labels, so the split is declarative:

| Pattern                              | How                                                                                                                                       |
| :----------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------- |
| Add-ons on Fargate, workloads on EC2 | Run Karpenter and CoreDNS on Fargate so nothing depends on the nodes they manage                                                          |
| Batch on Fargate                     | A profile for the `batch` namespace; [[Kubernetes/concepts/L03-workloads/06-job\|Jobs]] get capacity on demand and cost nothing when idle |
| Isolation tier                       | Sensitive tenants' namespaces on Fargate, everything else on shared nodes                                                                 |
| Burst overflow                       | Label-selected pods go to Fargate when node capacity is tight                                                                             |

## Decision guide

1. Does the pod need a DaemonSet, privileged mode, a GPU, EBS or Arm? → **EC2.**
2. Is strong per-pod isolation a requirement? → **Fargate.**
3. Is the workload steady and large? → **EC2**, ideally with Karpenter or Auto Mode, Spot and Savings Plans.
4. Is it small, spiky or occasional, and is nobody available to run nodes? → **Fargate.**
5. Do you mainly want to stop operating nodes? → consider **Auto Mode** first: it removes most of the toil without Fargate's restrictions.

## Related

- [[Kubernetes/eks/compute/README|Compute options on EKS]]
- [[Kubernetes/eks/compute/karpenter/README|Karpenter]]
- [[AWS/compute/ecs/README|Amazon ECS]] — where Fargate is more capable (Spot, Arm)
- [[AWS/cost-management/savings-plans|Savings Plans]] — Compute Savings Plans cover both

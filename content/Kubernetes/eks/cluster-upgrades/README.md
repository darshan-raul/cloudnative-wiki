---
title: EKS Cluster Upgrades
tags: [eks, upgrades, lifecycle, operations]
date: 2026-05-17
description: An overview of keeping EKS clusters current — the support lifecycle and what falling behind costs, what an upgrade consists of, who is responsible for each part, and the notes that cover the procedure and per-version hazards.
---

# EKS Cluster Upgrades

Kubernetes ships a new minor version roughly every four months, and EKS supports each one for a limited time. Upgrading is therefore a recurring operational task, and teams that treat it as routine have a very different experience from those that upgrade only when a deadline arrives.

## Notes in this section

- [[Kubernetes/eks/cluster-upgrades/upgrade-process|Upgrade Process]] — the step-by-step procedure: pre-flight checks, control plane, add-ons, nodes, validation, and in-place versus blue-green.
- [[Kubernetes/eks/cluster-upgrades/upgrade-journey|Upgrade Journey Series]] — what actually changes between versions, the patterns that repeat, and community write-ups of real upgrades.

## The support lifecycle

| Phase                | Duration            | What it means                                                                |
| :------------------- | :------------------ | :--------------------------------------------------------------------------- |
| **Standard support** | About 14 months     | Normal control-plane price; patches and security fixes                       |
| **Extended support** | A further 12 months | The same fixes, at a control-plane price several times higher                |
| **End of support**   | —                   | AWS upgrades the control plane automatically to the oldest supported version |

A cluster enters extended support automatically unless its upgrade policy is set to `STANDARD`. The cost difference is per cluster per hour, and it adds up across a fleet. The forced upgrade at the end is the worst outcome: it happens on AWS's schedule, with your workloads untested against the new version.

## What an upgrade consists of

```
control plane  ──►  add-ons  ──►  nodes  ──►  your workloads' manifests
 (AWS does it,      (you: CNI,    (you, or    (you: removed APIs,
  you trigger)       DNS, CSI,     Auto Mode)   changed defaults)
                     controllers)
```

| Part                    | Who                              | Risk                                                           |
| :---------------------- | :------------------------------- | :------------------------------------------------------------- |
| Control plane           | AWS performs, you trigger        | Low during the upgrade itself; **cannot be rolled back**       |
| EKS add-ons             | You                              | Medium: version compatibility, configuration overwritten       |
| Third-party controllers | You                              | Often the real blocker — check support for the target version  |
| Nodes                   | You, or automatic with Auto Mode | Where workload disruption actually occurs                      |
| Workload manifests      | You                              | Removed APIs break the _next_ deployment, not the running pods |

Three rules shape every plan: one minor version at a time, control plane before nodes, and no rollback of the control plane.

## Principles

1. **Upgrade on a schedule**, a few weeks after each version becomes available on EKS — not when support is ending.
2. **Stay within one or two versions of current.** Each version you skip adds its own hazards, and they must still be crossed one at a time.
3. **Rehearse** in an environment that resembles production, with the same add-ons.
4. **Use cluster insights and scan your manifests** for removed APIs before every upgrade.
5. **Keep add-ons current between upgrades**, so that each cluster upgrade is a small step.
6. **Make workloads disruption-tolerant**: multiple replicas, [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudgets]], graceful shutdown. That is what makes node rollouts uneventful.
7. **Have the cluster defined as code**, so a blue-green upgrade — and disaster recovery — is possible.

## How the compute model changes the work

| Compute                                                                    | Node upgrade effort                                        |
| :------------------------------------------------------------------------- | :--------------------------------------------------------- |
| [[Kubernetes/eks/compute/eks-auto-mode/README\|Auto Mode]]                 | None: nodes are replaced automatically                     |
| [[Kubernetes/eks/compute/karpenter/README\|Karpenter]]                     | Update the pinned AMI; drift replaces nodes within budgets |
| [[Kubernetes/eks/compute/managed-node-groups/basics\|Managed node groups]] | One command per group; a rolling replacement               |
| [[Kubernetes/eks/compute/fargate/README\|Fargate]]                         | Restart pods to pick up the new version                    |
| Self-managed nodes                                                         | Entirely yours                                             |

## Related

- [[Kubernetes/guides/non-functional/upgrade-strategy|Kubernetes upgrade strategy]] — provider-neutral guidance
- [[Kubernetes/guides/non-functional/deprecations|API deprecations]]
- [[Kubernetes/updates-along-the-versions|Updates along the versions]]
- [[Kubernetes/MAINTENANCE|Curriculum maintenance playbook]]
- [[Azure/compute/aks/upgrades-maintenance|AKS upgrades and maintenance]] and [[GCP/compute/gke/release-channels-upgrades|GKE release channels and upgrades]] — the same task on other clouds
- [EKS Kubernetes version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)

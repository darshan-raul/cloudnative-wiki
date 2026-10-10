---
title: EKS Upgrade Journey
tags: [eks, upgrades, kubernetes-versions, lessons-learned]
date: 2026-05-17
description: What actually breaks between Kubernetes versions on EKS — the notable removal or behaviour change in each release from 1.22 onward, the recurring patterns behind them, and community write-ups of real upgrades.
---

# EKS Upgrade Journey

The [[Kubernetes/eks/cluster-upgrades/upgrade-process|upgrade process]] is the same every time. What differs is the specific thing each version changes underneath you. This note collects those per-version hazards and the patterns that repeat, so an upgrade several versions long can be planned as a sequence of known obstacles.

It is a planning aid, not a substitute for the release notes of the version you are moving to.

## The hazards, version by version

| Moving to | The change most likely to hurt                                                                                                                 | What to do first                                                                                               |
| :-------- | :--------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------- |
| 1.22      | Many long-deprecated beta APIs removed: `Ingress` `extensions/v1beta1`, `CustomResourceDefinition` `v1beta1`, webhook configurations `v1beta1` | Migrate manifests and charts to `v1`                                                                           |
| 1.23      | In-tree EBS volumes are served through CSI migration                                                                                           | Install the [[Kubernetes/eks/storage/ebs-csi\|EBS CSI driver]] **before** upgrading, or volumes fail to attach |
| 1.24      | Dockershim removed; nodes run containerd only                                                                                                  | Remove anything that mounts the Docker socket — [[Containers/runtimes\|container runtimes]]                    |
| 1.25      | `PodSecurityPolicy` removed; `CronJob` `batch/v1beta1`, `HorizontalPodAutoscaler` `v2beta1`, `PodDisruptionBudget` `v1beta1` removed           | Move to [[Kubernetes/eks/security/pod-security-standards\|Pod Security Admission]] or a policy engine          |
| 1.26      | `HorizontalPodAutoscaler` `v2beta2` removed; flow-control `v1beta1` removed; very old VPC CNI versions unsupported                             | Update HPA manifests to `autoscaling/v2`                                                                       |
| 1.27      | `CSIStorageCapacity` `v1beta1` removed; kubelet default API rate limits raised; seccomp default can be enabled                                 | Few workload changes; a good "catch-up" version                                                                |
| 1.28      | Kubelet skew policy widened to three minor versions; sidecar containers arrive (alpha)                                                         | Useful for batching node upgrades                                                                              |
| 1.29      | Flow-control `v1beta2` removed                                                                                                                 | Check API priority and fairness objects                                                                        |
| 1.30      | New managed node groups default to Amazon Linux 2023; the default `gp2` StorageClass loses its default annotation on new clusters              | Convert `bootstrap.sh` user data to `NodeConfig`; define a default StorageClass                                |
| 1.31      | In-tree cloud provider code removed upstream; AppArmor fields become GA                                                                        | Confirm nothing depends on legacy in-tree behaviour                                                            |
| 1.32      | Flow-control `v1beta3` removed; the last version with Amazon Linux 2 EKS AMIs                                                                  | Finish the move to AL2023 or Bottlerocket                                                                      |
| 1.33      | No Amazon Linux 2 AMIs; in-place pod resource resize (beta); sidecar containers GA                                                             | Rebuild any custom AMIs on AL2023                                                                              |
| 1.34+     | Continued removal of `v1beta1` APIs for newer features; `VolumeAttributesClass` GA                                                             | Run cluster insights and a manifest scan every time                                                            |

The exact contents of each release are tracked in [[Kubernetes/updates-along-the-versions|updates along the versions]]; removed APIs and how to find them are in [[Kubernetes/guides/non-functional/deprecations|deprecations]].

## Patterns that repeat

**1. API removals are announced years ahead and still surprise people.** The failure is rarely the running workload — existing objects are converted on read. It is the **next deployment**, when a Helm chart or manifest in Git still uses the removed version. Scan what you deploy, not just what is live.

**2. Platform prerequisites must land before the upgrade.** The EBS CSI driver before 1.23, containerd readiness before 1.24, a replacement for PodSecurityPolicy before 1.25, AL2023 user data before the AL2 AMIs disappear. Each was a hard cliff for clusters that discovered it during the upgrade.

**3. Add-ons and operators lag.** A cluster upgrade is blocked more often by a third-party controller that does not yet support the new version than by Kubernetes itself. Inventory them and check compatibility matrices first.

**4. Node operating system changes are a separate migration.** AL2 to AL2023 changed bootstrap, cgroup version and IMDS defaults. Treat OS changes as their own project and do not stack them on a version upgrade — [[Kubernetes/eks/compute/managed-node-groups/basics|node group basics]].

**5. Defaults change quietly.** A removed default StorageClass or a new default AMI family does not break the upgrade. It breaks the next new cluster or node group, weeks later.

**6. Falling behind compounds.** Each skipped version adds its own hazards, and they must still be crossed one minor version at a time. Three versions behind is three upgrades, each with a rehearsal. Extended support also bills at several times the standard control-plane price.

## Planning a multi-version catch-up

1. List every version between current and target, and the hazard for each from the table.
2. Resolve all prerequisites up front, at the current version, where possible.
3. Decide per hop whether nodes are upgraded each time or batched (the three-version kubelet skew allows batching from 1.28).
4. Rehearse the whole sequence in a copy of the cluster.
5. Consider a **blue-green cluster** instead: build new at the target version and migrate workloads. Past three or four versions behind, this is often faster and safer than hopping.
6. Afterwards, set a calendar cadence so it does not happen again.

## What to record after each upgrade

Keep a short log per upgrade in your own repository: versions, date, duration, what the insights flagged, what broke, what you would do differently. The value of the community write-ups below is exactly this kind of detail, and your own environment's version is worth more than anyone else's.

## Community write-ups

One long-running series documents each EKS hop with the specific issues met:

- [1.23 to 1.24](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-23-to-1-24-b7b0b1afa5b4)
- [1.25 to 1.26](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-25-to-1-26-electrifying-79b287084eef)
- [1.26 to 1.27](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-26-to-1-27-chill-vibes-46f3f979afac)
- [1.27 to 1.28](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-27-to-1-28-welcoming-planternetes-44985e11463a)
- [1.28 to 1.29](https://marcincuber.medium.com/amazon-eks-upgrade-journey-from-1-28-to-1-29-say-hello-to-mandala-858ae0579f4f)
- [1.29 to 1.30](https://medium.com/@marcincuber/amazon-eks-upgrade-journey-from-1-29-to-1-30-say-hello-to-cute-uwubernetes-eba082199cc4)
- [AWS EKS Upgrade Workshop](https://catalog.us-east-1.prod.workshops.aws/workshops/693bdee4-bc31-41d5-841f-54e3e54f8f4a/en-US)

## Related

- [[Kubernetes/eks/cluster-upgrades/README|Cluster upgrades overview]]
- [[Kubernetes/guides/non-functional/upgrade-strategy|Kubernetes upgrade strategy]]
- [[Kubernetes/MAINTENANCE|Curriculum maintenance playbook]] — how this wiki tracks new releases
- [[Kubernetes/eks/observability/logging/control-plane-logs|Control plane logs]] — the query that finds deprecated API callers

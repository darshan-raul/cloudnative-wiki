---
title: Managed Node Group Basics
tags: [eks, compute, managed-node-groups]
date: 2026-05-17
description: What an EKS managed node group actually is — the Auto Scaling group underneath, AMI families, launch templates, the rolling update process and what blocks it.
---

# Managed Node Group Basics

A managed node group (MNG) is an [[AWS/compute/ec2/README|EC2]] Auto Scaling group that EKS creates and operates for you. EKS picks the AMI, joins the instances to the cluster, and — the real value — performs rolling updates that cordon and drain nodes safely.

You still own the instances: they run in your account, you pay for them, and you decide when to update them.

## What EKS manages and what you manage

| EKS does                                                     | You do                                                                                                                |
| :----------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------- |
| Creates the Auto Scaling group across the subnets you choose | Choose instance types, size, subnets and capacity type                                                                |
| Supplies an EKS-optimized AMI and bootstrap configuration    | Trigger AMI and Kubernetes version updates                                                                            |
| Drains nodes on update, scale-in and Spot interruption       | Define [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget\|PodDisruptionBudgets]] so drains are safe |
| Labels nodes (`eks.amazonaws.com/nodegroup`, capacity type)  | Scale the group — by hand, or with an autoscaler                                                                      |
| Optionally repairs unhealthy nodes (node auto repair)        | Monitor and investigate why nodes became unhealthy                                                                    |

A node group does **not** scale itself in response to pending pods. That is the job of [[Kubernetes/eks/compute/managed-node-groups/cluster-autoscaler|Cluster Autoscaler]]. If you want scaling without managing groups at all, look at [[Kubernetes/eks/compute/karpenter/README|Karpenter]] or [[Kubernetes/eks/compute/eks-auto-mode/README|Auto Mode]].

## Creating one

```yaml
# cluster.yaml (eksctl)
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
  region: eu-west-1
managedNodeGroups:
  - name: general
    amiFamily: AmazonLinux2023
    instanceTypes: ["m7g.large", "m6g.large"]
    minSize: 2
    desiredCapacity: 3
    maxSize: 10
    privateNetworking: true
    volumeSize: 80
    labels: { workload: general }
    updateConfig:
      maxUnavailablePercentage: 25
```

```bash
eksctl create nodegroup -f cluster.yaml
```

Sensible defaults: private subnets, at least two instance types of the same size, and a group spanning three zones. If the group owns [[Kubernetes/eks/storage/ebs-csi|EBS-backed]] workloads and you scale with Cluster Autoscaler, use one group per zone instead so the autoscaler can add capacity in the zone where the volume lives.

## AMI families

| AMI family        | Notes                                                                                                      |
| :---------------- | :--------------------------------------------------------------------------------------------------------- |
| Amazon Linux 2023 | The default. Configured through a `NodeConfig` document (`nodeadm`), cgroup v2, IMDSv2 required by default |
| Bottlerocket      | Minimal, immutable, API-configured OS with atomic updates; smallest attack surface                         |
| Amazon Linux 2    | Legacy; AWS stopped publishing EKS AL2 AMIs in late 2025 — migrate off it                                  |
| Windows           | For Windows containers; requires at least one Linux group for system pods                                  |
| GPU / accelerated | AL2023 and Bottlerocket variants with NVIDIA drivers preinstalled                                          |

Moving from AL2 to AL2023 changes the bootstrap mechanism: `bootstrap.sh` arguments in user data no longer work and must become a `NodeConfig`. Background on the underlying OS concepts is in [[Linux/kernel/cgroups|cgroups]] and [[Linux/boot-init/systemd|systemd]].

## Launch templates

Supplying your own launch template unlocks custom user data, extra security groups, larger or encrypted root volumes with a specific KMS key, IMDS settings and custom AMIs. Two rules:

- If the template specifies an AMI, EKS treats it as a **custom AMI**: you become responsible for bootstrap and for publishing new template versions to update.
- If it does not, EKS still manages the AMI and merges your user data into its own.

## How an update works

Updating the AMI release or Kubernetes version performs a rolling replacement:

1. **Setup** — EKS creates a new launch template version and updates the Auto Scaling group.
2. **Scale up** — the group temporarily grows so new nodes come up before old ones leave.
3. **Upgrade** — old nodes are cordoned and drained, `maxUnavailable` at a time, then terminated.
4. **Scale down** — the group returns to its original size.

A drain waits for PodDisruptionBudgets. If a pod cannot be evicted within 15 minutes, the update **fails** with `PodEvictionFailure`. Fix the PDB (a `maxUnavailable: 0` budget or a single replica is the usual culprit), or rerun with `--force`, which deletes pods without honouring PDBs.

```bash
aws eks update-nodegroup-version \
  --cluster-name my-cluster --nodegroup-name general
aws eks describe-update --name my-cluster --nodegroup-name general --update-id <id>
```

Node groups can lag the control plane by a few minor versions, but always upgrade the control plane first. The full sequence is in [[Kubernetes/eks/cluster-upgrades/upgrade-process|the upgrade process]].

## Common problems

| Symptom                                              | Cause                                                                                             |
| :--------------------------------------------------- | :------------------------------------------------------------------------------------------------ |
| Group status `DEGRADED`, health issue `AccessDenied` | Node role lost a managed policy or its access entry                                               |
| `NodeCreationFailure`: instances launch, never join  | No route to the cluster endpoint, missing ECR/S3/STS endpoints in a private VPC, or bad user data |
| `AsgInstanceLaunchFailures`                          | Instance type unavailable in a zone, or an account quota — add more instance types                |
| Update stuck then fails                              | PDB blocks the drain                                                                              |
| Someone edited the Auto Scaling group directly       | EKS reconciles some settings back; change node groups only through the EKS API                    |

See [[Kubernetes/guides/troubleshooting/node-not-ready|Node NotReady]] for the node-level diagnosis.

## Related

- [[Kubernetes/eks/compute/managed-node-groups/README|Managed node groups overview]]
- [[Kubernetes/eks/compute/managed-node-groups/graviton|Graviton]] and [[Kubernetes/eks/compute/managed-node-groups/spot|Spot]]
- [[Kubernetes/concepts/L08-operations/00-README|Operations: drains and upgrades]]
- [Managed node groups user guide](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)

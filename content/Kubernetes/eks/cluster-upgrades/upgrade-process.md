---
title: EKS Upgrade Process
tags: [eks, upgrades, operations, lifecycle]
date: 2026-05-17
description: A step-by-step EKS upgrade — version support and skew rules, pre-flight checks with cluster insights, upgrading the control plane, add-ons and nodes in order, validation, what cannot be rolled back, and in-place versus blue-green.
---

# EKS Upgrade Process

Kubernetes releases a minor version about three times a year, and EKS supports each for a limited time. Upgrading is therefore routine work, not a project — as long as it is done the same way each time and before deadlines force it.

## The rules that shape everything

| Rule                                                                                                                                        | Consequence                                                  |
| :------------------------------------------------------------------------------------------------------------------------------------------ | :----------------------------------------------------------- |
| The control plane moves **one minor version at a time**                                                                                     | Going from 1.31 to 1.34 is three upgrades                    |
| A control plane upgrade **cannot be rolled back**                                                                                           | Test first; the only "undo" is a new cluster                 |
| The control plane upgrades **before** the nodes                                                                                             | Nodes may lag; they may never lead                           |
| The kubelet may be up to **three minor versions older** than the API server                                                                 | You can batch node upgrades, but do not rely on the full gap |
| **Standard support** lasts about 14 months per version, then **extended support** for 12 more at a significantly higher control-plane price | Staying current is cheaper                                   |
| At the end of extended support, AWS **upgrades the cluster automatically**                                                                  | An unplanned upgrade is the worst kind                       |

Set the cluster's upgrade policy to `STANDARD` if you would rather be forced to upgrade than pay for extended support by accident.

## The order

```
1. prepare ─► 2. control plane ─► 3. add-ons ─► 4. nodes ─► 5. validate
   (days)        (~10–20 min)       (minutes)     (rolling)
```

### 1. Prepare

**Read the release notes** for the target version: removed APIs, changed defaults, and the EKS-specific notes. Track changes in [[Kubernetes/updates-along-the-versions|updates along the versions]] and [[Kubernetes/guides/non-functional/deprecations|deprecations]].

**Check cluster insights.** EKS scans the audit log and configuration for known upgrade blockers:

```bash
aws eks list-insights --cluster-name my-cluster \
  --filter '{"categories":["UPGRADE_READINESS"]}' \
  --query 'insights[].{name:name,status:insightStatus.status}' --output table
```

Insights flag deprecated API usage (and which client is calling it), kubelet and kube-proxy version skew, and add-on incompatibilities. An `ERROR` blocks the upgrade unless you force it.

**Find removed APIs in what you deploy**, not only what is running: scan manifests and Helm charts in Git with tools such as `pluto` or `kubent`. A removed API in a chart breaks the _next_ deployment, after the upgrade looked fine.

**Check everything that talks to the API**: add-ons, operators, admission webhooks, CI tooling, `kubectl` versions. Confirm each supports the target version.

**Check capacity and safety nets**: at least five free IP addresses in the cluster subnets (the upgrade needs them), [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudgets]] on every multi-replica workload, and a recent [[Kubernetes/guides/non-functional/backup-restore|backup]].

**Rehearse** in a non-production cluster that resembles production, with the same add-ons and workloads.

### 2. Control plane

```bash
aws eks update-cluster-version --name my-cluster --kubernetes-version 1.34
aws eks describe-update --name my-cluster --update-id <id>
```

AWS replaces the API server instances with a rolling, health-checked process. The API stays available; expect brief connection resets, which well-behaved clients retry. Running workloads are not touched. If the new control plane fails health checks, AWS rolls the update back itself.

### 3. Add-ons

Update in this order, checking each is healthy before the next:

1. **VPC CNI** — one minor version at a time
2. **CoreDNS**
3. **kube-proxy** — must not be newer than the control plane or more than a few versions older
4. **CSI drivers, Pod Identity agent**, and other EKS add-ons
5. **Self-managed controllers**: load balancer controller, autoscaler (Cluster Autoscaler must match the cluster's minor version), ingress, cert-manager, policy engines

```bash
aws eks describe-addon-versions --kubernetes-version 1.34 --addon-name vpc-cni \
  --query 'addons[].addonVersions[].{v:addonVersion,default:compatibilities[0].defaultVersion}'
aws eks update-addon --cluster-name my-cluster --addon-name vpc-cni \
  --addon-version <version> --resolve-conflicts PRESERVE
```

`PRESERVE` keeps your custom configuration; the default overwrites it.

### 4. Nodes

| Compute                                                                    | How                                                                                     |
| :------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------- |
| [[Kubernetes/eks/compute/managed-node-groups/basics\|Managed node groups]] | `aws eks update-nodegroup-version` — a rolling replacement that respects PDBs           |
| [[Kubernetes/eks/compute/karpenter/README\|Karpenter]]                     | Update the AMI in the `EC2NodeClass`; drift replaces nodes within the disruption budget |
| [[Kubernetes/eks/compute/eks-auto-mode/README\|Auto Mode]]                 | Automatic                                                                               |
| [[Kubernetes/eks/compute/fargate/README\|Fargate]]                         | Restart the pods: `kubectl rollout restart`                                             |
| Self-managed                                                               | New launch template and an instance refresh, or a new group and a drain                 |

Node rollouts are where disruption actually happens. A PDB that allows zero evictions stalls the rollout; a workload with one replica and no PDB takes downtime. Surge rather than running short, and watch error rates as nodes turn over.

### 5. Validate

```bash
kubectl version
kubectl get nodes -o wide                      # all on the new version, all Ready
kubectl get pods -A | grep -v "Running\|Completed"
aws eks list-addons --cluster-name my-cluster
```

Then check what users would notice: [[DevOps/sre/slos-and-error-budgets|SLO]] dashboards, a deployment through the normal pipeline, a scale-up, a DNS lookup from a new pod, and a volume attach.

## In place or blue-green

|                   | In-place                     | Blue-green cluster                                                       |
| :---------------- | :--------------------------- | :----------------------------------------------------------------------- |
| How               | Upgrade the existing cluster | Build a new cluster on the target version, shift traffic                 |
| Rollback          | None for the control plane   | Shift traffic back                                                       |
| Skipping versions | No                           | Yes                                                                      |
| Effort and cost   | Low                          | High: two clusters, data and DNS migration                               |
| Suits             | Routine upgrades             | Several versions behind, high-risk changes, strict rollback requirements |

Blue-green is only practical when cluster configuration is fully reproducible from code ([[DevOps/infrastructure-as-code/README|infrastructure as code]] plus [[Kubernetes/guides/delivery/gitops/basics|GitOps]]) and state lives outside the cluster. If that is true, it is also your disaster-recovery mechanism.

## Making it routine

- Upgrade on a calendar, shortly after each version has been available for a while, not when support is ending.
- Promote through environments with a soak period: dev, staging, then production.
- Keep a checklist in the repository and improve it after every upgrade.
- Alert on cluster insights and on end-of-support dates.
- Keep add-ons current _between_ cluster upgrades, so each upgrade is a small step.

## Related

- [[Kubernetes/eks/cluster-upgrades/README|Cluster upgrades overview]]
- [[Kubernetes/eks/cluster-upgrades/upgrade-journey|Upgrade journey]] — what changed in each version
- [[Kubernetes/guides/non-functional/upgrade-strategy|Kubernetes upgrade strategy]]
- [[Kubernetes/eks/troubleshooting/common-issues|Common EKS issues]]
- [EKS best practices: cluster upgrades](https://docs.aws.amazon.com/eks/latest/best-practices/cluster-upgrades.html)

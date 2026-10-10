---
title: Cluster Autoscaler on EKS
tags: [eks, compute, autoscaling, cluster-autoscaler]
date: 2026-05-17
description: Running Kubernetes Cluster Autoscaler against EKS managed node groups — ASG discovery, IAM, node group design rules, scale-down tuning and when to prefer Karpenter.
---

# Cluster Autoscaler on EKS

Cluster Autoscaler (CA) adjusts the desired size of Auto Scaling groups. When pods are unschedulable it picks a group whose nodes would fit them and raises its size; when nodes sit underused it drains them and lowers the size.

It is the conservative choice: mature, predictable, and bound to the node groups you define. The general algorithm is covered in [[Kubernetes/concepts/L06-scheduling-scaling/09-cluster-autoscaler|Cluster Autoscaler (concepts)]]; this page is about making it work well on EKS.

## How it sees your cluster

CA does not look at real instances when deciding to scale up. It builds a **template node** for each Auto Scaling group from the group's launch template and tags, then simulates the scheduler against that template. Two things follow:

- Every instance type in a group must have **the same vCPU and memory**. If a group mixes `m5.large` and `m5.4xlarge`, CA assumes one shape and its arithmetic is wrong.
- When a group is at zero, CA cannot inspect a live node, so labels, taints and extended resources must be declared as ASG tags. [[Kubernetes/eks/compute/managed-node-groups/basics|Managed node groups]] add these tags for you; self-managed groups need `k8s.io/cluster-autoscaler/node-template/label/<key>` tags by hand.

## Install

Groups are found by tag. Managed node groups carry them automatically:

```
k8s.io/cluster-autoscaler/enabled = true
k8s.io/cluster-autoscaler/<cluster-name> = owned
```

The controller's role, granted through [[Kubernetes/eks/security/pod-identity|Pod Identity]] or [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]]:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:GetInstanceTypesFromInstanceRequirements",
        "eks:DescribeNodegroup"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/k8s.io/cluster-autoscaler/my-cluster": "owned"
        }
      }
    }
  ]
}
```

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=my-cluster \
  --set awsRegion=eu-west-1 \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.expander=least-waste \
  --set extraArgs.skip-nodes-with-system-pods=false
```

Match the CA minor version to the cluster's Kubernetes minor version; the scheduler simulation is compiled in and drifts otherwise.

## Node group design rules

1. **One group per zone for stateful workloads.** An [[Kubernetes/eks/storage/ebs-csi|EBS volume]] pins its pod to a zone. With a multi-AZ group, CA asks the ASG for "one more node" and the ASG may place it in the wrong zone. Per-zone groups plus `balance-similar-node-groups` fix this.
2. **Same-size instance types within a group.** Diversify across families (`m6i.xlarge`, `m6a.xlarge`, `m5.xlarge`), never across sizes.
3. **Separate groups for different capacity types and architectures.** Spot and On-Demand, x86 and Arm, GPU and CPU each get their own group, steered with taints and node selectors.
4. **Fewer, larger groups scale faster.** CA's loop time grows with the number of groups; hundreds of groups make it sluggish.

## Scale-up behaviour

When several groups could host a pending pod, the **expander** decides:

| Expander      | Picks                                                                |
| :------------ | :------------------------------------------------------------------- |
| `least-waste` | The group that leaves the least idle CPU and memory — a good default |
| `priority`    | Follows a ConfigMap ranking, e.g. try Spot groups before On-Demand   |
| `random`      | Any; fine when groups are equivalent                                 |
| `most-pods`   | The group that schedules the most pending pods                       |

End to end, expect two to four minutes from pending pod to running: CA's scan interval, the ASG launch, the node boot and the CNI becoming ready. Workloads that cannot wait should keep headroom with low-priority placeholder pods ([[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption|priority and preemption]]).

## Scale-down behaviour

A node is a removal candidate when its requested resources fall below `scale-down-utilization-threshold` (default 50%) for `scale-down-unneeded-time` (default 10 minutes) **and** every pod on it can move elsewhere. A node is kept if it has:

- a pod with the annotation `cluster-autoscaler.kubernetes.io/safe-to-evict: "false"`,
- a pod blocked by a [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudget]],
- a bare pod not owned by a controller,
- a pod using local storage, unless `skip-nodes-with-local-storage=false`.

"Why won't my cluster scale down?" is nearly always one of these. The status ConfigMap and the logs say which:

```bash
kubectl -n kube-system describe configmap cluster-autoscaler-status
kubectl -n kube-system logs deploy/cluster-autoscaler | grep -i "cannot be removed"
```

## Cluster Autoscaler or Karpenter

|                      | Cluster Autoscaler                   | [[Kubernetes/eks/compute/karpenter/README\|Karpenter]] |
| :------------------- | :----------------------------------- | :----------------------------------------------------- |
| Unit of scaling      | Predefined node groups               | Individual instances chosen per pending pod            |
| Instance flexibility | Same-size types per group            | Any type matching the requirements                     |
| Time to capacity     | Minutes                              | Typically under a minute                               |
| Cost optimisation    | Removes underused nodes              | Also replaces nodes with cheaper ones (consolidation)  |
| Operational model    | Simple, static, easy to reason about | More powerful, more ways to disrupt workloads          |

Stay with CA when node groups are few and stable, or when change control requires fixed instance types. Move to Karpenter when node-group sprawl or Spot diversification becomes painful.

## Related

- [[Kubernetes/eks/advanced/autoscaling|Autoscaling on EKS]]
- [[Kubernetes/guides/non-functional/auto-scaling|Auto-scaling guide]]
- [[Kubernetes/guides/troubleshooting/pod-pending|Pod Pending]]
- [Cluster Autoscaler on AWS](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md)

## Across the wiki

- [[Azure/compute/aks/autoscaling-keda|AKS Autoscaling Architecture — Cluster Autoscaler, KEDA, and Virtual Nodes]] — autoscaling (Azure)
- [[GCP/compute/gke/autoscaling|GKE Autoscaling Architecture — Cluster Autoscaler, NAP, HPA v2, and VPA]] — autoscaling (GCP)
- [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/scalability|Scalability]] — autoscaling (Architecture)

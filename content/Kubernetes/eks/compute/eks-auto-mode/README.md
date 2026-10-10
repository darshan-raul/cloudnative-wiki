---
title: EKS Auto Mode
tags: [eks, compute, auto-mode, karpenter]
date: 2026-05-17
description: What EKS Auto Mode manages for you, how its nodes differ from ordinary nodes, NodePools and NodeClasses, the built-in load balancing and storage, pricing, limits and how to decide whether it fits.
---

# EKS Auto Mode

EKS Auto Mode extends AWS's responsibility from the control plane to the **data plane**. AWS provisions, scales, patches and replaces the nodes, and runs the core add-ons, so a cluster is ready for workloads as soon as it exists. You still see the nodes as EC2 instances in your account and pay for them, but you do not operate them.

It is the lowest-effort way to run EKS on EC2, and the natural default for new clusters unless one of its limits rules it out.

## What moves to AWS

| Capability           | Without Auto Mode, you run                                                                                                                      | With Auto Mode                                             |
| :------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------- |
| Node autoscaling     | [[Kubernetes/eks/compute/karpenter/README\|Karpenter]] or [[Kubernetes/eks/compute/managed-node-groups/cluster-autoscaler\|Cluster Autoscaler]] | A managed Karpenter, outside the cluster                   |
| Node OS and patching | AMI updates and node group rollouts                                                                                                             | Immutable Bottlerocket-based nodes, replaced automatically |
| Pod networking       | The VPC CNI add-on                                                                                                                              | Built into the node                                        |
| Service proxy, DNS   | `kube-proxy`, CoreDNS add-ons                                                                                                                   | Built into the node                                        |
| Load balancers       | AWS Load Balancer Controller                                                                                                                    | Built in                                                   |
| Block storage        | [[Kubernetes/eks/storage/ebs-csi\|EBS CSI driver]]                                                                                              | Built in (`ebs.csi.eks.amazonaws.com`)                     |
| Pod IAM              | Pod Identity agent                                                                                                                              | Built in                                                   |
| GPU support          | Device plugins and drivers                                                                                                                      | Built in                                                   |

Because these run as system processes on the node rather than as pods, `kubectl get pods -n kube-system` is nearly empty on an Auto Mode cluster. That surprises people the first time.

## Enabling it

```bash
eksctl create cluster --name my-cluster --enable-auto-mode
```

On an existing cluster, Auto Mode is switched on by enabling three settings together — compute, block storage and load balancing — and it can run **alongside** existing managed node groups, which makes migration gradual: turn it on, let new pods land on Auto Mode nodes, then drain the old groups.

Two [[AWS/security/iam/README|IAM]] roles are involved: the cluster role gains the Auto Mode managed policies (`AmazonEKSComputePolicy`, `AmazonEKSBlockStoragePolicy`, `AmazonEKSLoadBalancingPolicy`, `AmazonEKSNetworkingPolicy`), and a node role with `AmazonEKSWorkerNodeMinimalPolicy` and ECR pull access.

## NodePools and NodeClasses

Auto Mode ships two built-in NodePools:

- **`general-purpose`** — On-Demand, current-generation C, M and R instances, for your workloads.
- **`system`** — tainted with `CriticalAddonsOnly`, for cluster add-ons.

Create your own when you need Spot, Arm, GPUs or specific instance families. The NodePool API is Karpenter's; the node template is an Auto Mode `NodeClass`:

```yaml
apiVersion: eks.amazonaws.com/v1
kind: NodeClass
metadata:
  name: private
spec:
  role: AmazonEKSAutoNodeRole
  subnetSelectorTerms:
    - tags: { kubernetes.io/role/internal-elb: "1" }
  securityGroupSelectorTerms:
    - tags: { aws:eks:cluster-name: my-cluster }
  ephemeralStorage: { size: 80Gi }
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot-arm
spec:
  template:
    spec:
      nodeClassRef: { group: eks.amazonaws.com, kind: NodeClass, name: private }
      requirements:
        - {
            key: karpenter.sh/capacity-type,
            operator: In,
            values: [spot, on-demand],
          }
        - { key: kubernetes.io/arch, operator: In, values: [arm64] }
        - {
            key: eks.amazonaws.com/instance-category,
            operator: In,
            values: [c, m, r],
          }
  limits: { cpu: "500" }
```

Note the label prefix: Auto Mode uses `eks.amazonaws.com/…` where self-managed Karpenter uses `karpenter.k8s.aws/…`.

## How the nodes differ

- **Immutable and locked down.** No SSH, no Session Manager, read-only root filesystem, SELinux enforcing. You debug with `kubectl debug node/…` and node logs, not a shell.
- **Short-lived by design.** Nodes have a maximum lifetime of 21 days and are replaced on a rolling basis, which is how patching happens. Workloads must tolerate this: more than one replica, a [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudget]], and graceful shutdown.
- **No custom AMIs and no user data.** If you need a host agent, it has to run as a DaemonSet.
- **Consolidation is on.** Underused nodes are removed or replaced with cheaper ones, exactly as with Karpenter.

## Load balancing and storage

Built-in controllers use their own class names:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
spec:
  controller: eks.amazonaws.com/alb
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: auto-ebs
  annotations: { storageclass.kubernetes.io/is-default-class: "true" }
provisioner: ebs.csi.eks.amazonaws.com
volumeBindingMode: WaitForFirstConsumer
parameters: { type: gp3, encrypted: "true" }
```

For a Network Load Balancer, set `loadBalancerClass: eks.amazonaws.com/nlb` on the Service. Volumes created by the self-managed EBS CSI driver are not adopted automatically; migrating them means snapshot and restore.

## Cost

You pay the normal EC2 price for each instance **plus an Auto Mode management fee per instance-hour**, proportional to instance size. Savings Plans and Reserved Instances apply to the EC2 part only. Whether it is cheaper overall depends on what you would otherwise spend on engineering time and on the bin-packing you would achieve yourself — see [[Kubernetes/eks/advanced/cost-optimization|EKS cost optimization]].

## When it fits, and when it does not

| Good fit                                                   | Look elsewhere                                             |
| :--------------------------------------------------------- | :--------------------------------------------------------- |
| New clusters; small platform teams                         | You need a custom AMI, kernel modules or host-level agents |
| Standard stateless and stateful workloads                  | Nodes must live longer than 21 days                        |
| Teams that want Karpenter's behaviour without operating it | You need an alternative CNI such as Cilium                 |
| Compliance regimes that reward immutable, patched nodes    | You rely on node shell access for debugging                |
|                                                            | Windows nodes                                              |

The alternatives are compared in [[Kubernetes/eks/compute/README|compute options on EKS]] and [[Kubernetes/eks/compute/fargate/fargate-vs-ec2|Fargate vs EC2]].

## Related

- [[Kubernetes/eks/compute/managed-node-groups/basics|Managed node group basics]]
- [[Kubernetes/eks/networking/vpc-cni/network-policies|Network policies]] — enabled through the NodeClass on Auto Mode
- [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter|Karpenter (concepts)]]
- [EKS Auto Mode user guide](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Auto Mode managed instances](https://docs.aws.amazon.com/eks/latest/userguide/automode-learn-instances.html)

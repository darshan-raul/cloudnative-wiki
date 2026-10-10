---
title: Security Groups for Pods
tags: [eks, networking, vpc-cni, security-groups, security]
date: 2026-05-17
description: Attaching VPC security groups to individual pods on EKS — trunk and branch ENIs, the SecurityGroupPolicy resource, enforcing modes, instance limits, interaction with network policies and troubleshooting.
---

# Security Groups for Pods

By default every pod on a node shares the node's [[AWS/networking/vpc/security-groups|security groups]]. Anything the node may reach, every pod may reach. **Security groups for pods** gives selected pods their own network interface with their own security groups, so VPC-level rules can distinguish one workload from another.

The typical use: only the `payments` pods may connect to the payments RDS instance, enforced by the database's security group referencing the pods' security group — with no IP addresses involved.

## How it works

```
node (Nitro instance)
├── primary ENI            node SGs ── ordinary pods share these
├── secondary ENIs         node SGs
└── trunk ENI
     ├── branch ENI  ──► pod A   own SGs
     └── branch ENI  ──► pod B   own SGs
```

- The **VPC resource controller**, running in the EKS control plane, creates one **trunk ENI** per node and a **branch ENI** for each pod that needs its own security groups.
- The [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]] wires the branch ENI into the pod's network namespace.
- The node advertises an extended resource, `vpc.amazonaws.com/pod-eni`, and the scheduler only places such pods where a branch ENI is free.

## Enable it

1. Attach `AmazonEKSVPCResourceController` to the **cluster** IAM role.
2. Turn the feature on in the CNI:

```bash
aws eks update-addon --cluster-name my-cluster --addon-name vpc-cni \
  --configuration-values '{"env":{"ENABLE_POD_ENI":"true"}}'
```

3. Verify that nodes received a trunk interface:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,TRUNK:.metadata.labels.'vpc\.amazonaws\.com/has-trunk-attached'
```

Nodes that were running before the change need to be replaced to get a trunk ENI.

## Assign security groups

```yaml
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: payments-db-access
  namespace: payments
spec:
  podSelector:
    matchLabels:
      app: payments-api
  securityGroups:
    groupIds:
      - sg-0aaa1111bbbb2222c # the pod's own group, referenced by the database SG
      - sg-0ddd3333eeee4444f # shared group allowing DNS and cluster traffic
```

Select by `podSelector` or `serviceAccountSelector`. The policy applies when a pod is **created**; existing pods must be restarted.

The pod's security groups must allow what the node's groups used to allow implicitly:

- outbound DNS (TCP and UDP 53) to CoreDNS,
- inbound from the node security group for kubelet health probes,
- traffic to and from other pods it talks to, and from load balancers that target it.

Forgetting DNS or probes is the usual first failure. A common pattern is to include the cluster security group alongside the workload-specific one.

## Enforcing mode

`POD_SECURITY_GROUP_ENFORCING_MODE` decides which rules apply to pod traffic:

| Mode       | Rules applied                                 | Notes                                                                                                                                                                |
| :--------- | :-------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `strict`   | Only the branch ENI's security groups         | Default. All pod traffic leaves through the branch ENI. Kubelet TCP probes need `DISABLE_TCP_EARLY_DEMUX=true`.                                                      |
| `standard` | Both the node's and the pod's security groups | Required for [[Kubernetes/eks/networking/vpc-cni/network-policies\|network policies]], NodeLocal DNSCache and `externalTrafficPolicy: Local` to work with these pods |

Choose `standard` if you use Kubernetes network policies together with pod security groups — which is the usual combination.

## Limits

| Limit                                                                      | Detail                                                                                                       |
| :------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------- |
| Instance types                                                             | Nitro only, and not the burstable `t` family                                                                 |
| Branch ENIs per node                                                       | Fixed per instance type (for example 9 on `m5.large`, 54 on `m5.4xlarge`) — this caps how many such pods fit |
| Pod start-up                                                               | Slower: creating and attaching a branch ENI adds seconds                                                     |
| IP usage                                                                   | Each branch ENI takes an IP from the subnet, outside the warm pool                                           |
| Windows                                                                    | Not supported                                                                                                |
| [[Kubernetes/eks/networking/vpc-cni/custom-networking\|Custom networking]] | Branch ENIs use the subnet from the node's `ENIConfig`                                                       |
| Fargate                                                                    | Supported: each pod already has its own ENI                                                                  |

Because of the per-node cap and the slower start, apply this to the workloads that need it — typically those that reach databases or other VPC resources — not to everything.

## Security groups or network policies?

| Need                                                    | Use                                 |
| :------------------------------------------------------ | :---------------------------------- |
| Restrict pod-to-pod traffic inside the cluster          | Network policies                    |
| Control access to RDS, ElastiCache, other VPC resources | Security groups for pods            |
| Meet an audit requirement expressed in security groups  | Security groups for pods            |
| Egress to the internet by domain                        | A firewall or proxy at the VPC edge |

They combine well: network policy for east-west segmentation, pod security groups for the boundary to AWS services. The wider picture is in [[Kubernetes/eks/advanced/advanced-networking|advanced EKS networking]].

## Troubleshooting

| Symptom                                                 | Cause                                                                               |
| :------------------------------------------------------ | :---------------------------------------------------------------------------------- |
| Pod `Pending`: `Insufficient vpc.amazonaws.com/pod-eni` | No node has a free branch ENI, or nodes have no trunk ENI                           |
| Pod stuck `ContainerCreating`                           | Branch ENI creation failed: subnet out of IPs, or the cluster role lacks the policy |
| Pod runs but cannot resolve names                       | Its security groups do not allow DNS to CoreDNS                                     |
| Readiness probes fail in strict mode                    | `DISABLE_TCP_EARLY_DEMUX` not set                                                   |
| Policy seems ignored                                    | Pod was created before the `SecurityGroupPolicy`; restart it                        |

```bash
kubectl describe pod <pod> | grep -i -A2 "pod-eni\|vpc.amazonaws.com"
kubectl get securitygrouppolicies -A
```

More in [[Kubernetes/eks/networking/vpc-cni/troubleshooting|VPC CNI troubleshooting]].

## Related

- [[Kubernetes/eks/networking/README|EKS networking overview]]
- [[Kubernetes/eks/networking/vpc-cni/eni-allocation|ENI allocation]]
- [[Security/zero-trust|Zero trust]] — per-workload network identity
- [Security groups for pods](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html)

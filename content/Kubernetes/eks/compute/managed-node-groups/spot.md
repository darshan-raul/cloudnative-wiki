---
title: Spot Instances on EKS
tags: [eks, compute, spot, cost-optimization]
date: 2026-05-17
description: Running EKS workloads on EC2 Spot — the interruption contract, how managed node groups and Karpenter handle it, diversification, and how to make workloads tolerate being reclaimed.
---

# Spot Instances on EKS

Spot Instances are spare [[AWS/compute/ec2/README|EC2]] capacity sold at a discount of up to 90%. The catch is one sentence long: **AWS can take the instance back with two minutes' notice.** Kubernetes is well suited to that contract, because rescheduling pods is what it does all day — provided the workloads are built to move.

## The interruption contract

| Signal                       | Lead time               | Meaning                                                                   |
| :--------------------------- | :---------------------- | :------------------------------------------------------------------------ |
| **Rebalance recommendation** | Minutes, sometimes none | The instance is at elevated risk; a good moment to replace it proactively |
| **Spot interruption notice** | 2 minutes               | The instance will be reclaimed                                            |

Spot has no bidding any more. The price moves slowly with long-term supply and demand, and interruptions happen when AWS needs the capacity back, not because someone outbid you. See [[AWS/cost-management/pricing-models|EC2 pricing models]].

## Diversify, or it will not work

Each combination of instance type and Availability Zone is a separate **capacity pool** with its own spare capacity. Asking for one type in one zone means one pool; when it empties, you have nothing. Asking for ten types across three zones gives thirty pools.

- Allow many instance types of the **same size** (required for [[Kubernetes/eks/compute/managed-node-groups/cluster-autoscaler|Cluster Autoscaler]]): `m5.xlarge`, `m5a.xlarge`, `m6i.xlarge`, `m6a.xlarge`, `m7i.xlarge`, `m5d.xlarge`.
- Include older generations and AMD or [[Kubernetes/eks/compute/managed-node-groups/graviton|Graviton]] variants.
- Use every zone your subnets cover.

The allocation strategy does the rest. **Price-capacity-optimized** picks pools that are both cheap and deep, which lowers the interruption rate compared with choosing the lowest price.

## With managed node groups

```yaml
managedNodeGroups:
  - name: spot-xlarge
    capacityType: SPOT
    instanceTypes:
      ["m5.xlarge", "m5a.xlarge", "m6i.xlarge", "m6a.xlarge", "m7i.xlarge"]
    minSize: 0
    maxSize: 30
    labels: { lifecycle: spot }
    taints:
      - { key: spot, value: "true", effect: NoSchedule }
```

A Spot [[Kubernetes/eks/compute/managed-node-groups/basics|managed node group]] handles interruptions without extra software:

- It enables **capacity rebalancing**. On a rebalance recommendation, EKS launches a replacement, waits for it to join, then cordons and drains the at-risk node.
- On the two-minute notice, the node is drained immediately.
- Nodes are labelled `eks.amazonaws.com/capacityType: SPOT`, which you can target with node selectors or affinity.

Self-managed groups get none of this; they need the AWS Node Termination Handler.

## With Karpenter

[[Kubernetes/eks/compute/karpenter/README|Karpenter]] needs only `karpenter.sh/capacity-type In [spot, on-demand]` in a NodePool. It chooses from every instance type that satisfies the requirements, prefers Spot, falls back to On-Demand when Spot is unavailable, and uses the interruption queue to drain nodes on the two-minute notice. Because it is not limited to same-size types, it diversifies far better than node groups can.

## Making workloads tolerate interruption

Two minutes is enough only if the application cooperates:

1. **More than one replica, spread out.** Use [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|topology spread constraints]] across zones and nodes so one reclaim never removes all replicas.
2. **A [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudget]]** so proactive drains happen one pod at a time.
3. **Graceful shutdown within the window.** Handle `SIGTERM`, stop accepting work, finish in-flight requests. Keep `terminationGracePeriodSeconds` comfortably under 120 seconds. See [[Linux/kernel/signals|signals]].
4. **Readiness probes that tell the truth**, so replacement pods receive traffic only when ready — [[Kubernetes/concepts/L03-workloads/10-probes|probes]].
5. **Idempotent, checkpointed batch work.** A [[Kubernetes/concepts/L03-workloads/06-job|Job]] that restarts from scratch after 50 minutes of a 60-minute run wastes the saving.

## What belongs on Spot

| Good fit                                         | Keep on On-Demand                                                             |
| :----------------------------------------------- | :---------------------------------------------------------------------------- |
| Stateless web and API services with ≥ 2 replicas | Single-replica anything                                                       |
| CI runners, batch and data processing            | Databases and quorum systems (etcd, Kafka, ZooKeeper) unless designed for it  |
| Dev and test environments                        | Cluster-critical add-ons: CoreDNS, ingress controllers, the autoscaler itself |
| Horizontally scaled workers behind a queue       | Jobs that cannot checkpoint and run for hours                                 |

A common production shape is an On-Demand baseline, covered by [[AWS/cost-management/savings-plans|Savings Plans]], that carries critical add-ons and a minimum number of replicas, with everything above it on Spot. Enforce it with a taint on Spot nodes plus tolerations, or with a topology spread on the capacity-type label.

## Measuring it

- The **Spot Instance Advisor** shows interruption frequency per instance type and region.
- The **Spot placement score** API estimates how likely a request for N instances is to succeed.
- Track node churn and pod restart counts after moving a workload; rising error rates during reclaims mean the shutdown path needs work, not that Spot is unsuitable.

## Related

- [[Kubernetes/eks/advanced/cost-optimization|EKS cost optimization]]
- [[AWS/cost-management/ec2-cost-optimization|EC2 cost optimization]]
- [[Kubernetes/guides/non-functional/chaos-engineering|Chaos engineering]] — rehearse node loss before Spot does it for you
- [Spot best practices for EKS](https://docs.aws.amazon.com/eks/latest/best-practices/cost-opt-compute.html)

## Across the wiki

- [[Azure/compute/aks/node-pools-heterogeneous|AKS Heterogeneous Node Pools — System vs User, Ephemeral OS Disks, and Azure Linux]] — node pools and spot capacity (Azure)
- [[GCP/compute/gke/node-pools-heterogeneous|GKE Heterogeneous Node Pools, Taints, Tolerations, and Accelerator Topologies]] — node pools and spot capacity (GCP)
- [[Azure/compute/vm/spot-vms|Azure Spot VMs & Scheduled Events Eviction Engineering]] — node pools and spot capacity (Azure)

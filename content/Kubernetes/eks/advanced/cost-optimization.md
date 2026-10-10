---
title: EKS Cost Optimization
tags: [eks, cost-optimization, finops, spot, graviton]
date: 2026-05-17
description: Reducing what an EKS cluster costs without hurting reliability — where the money goes, visibility and allocation, right-sizing, bin-packing, purchase options, network and storage costs, and an ordered plan.
---

# EKS Cost Optimization

An EKS bill is rarely about EKS. The control plane is a small fixed fee; nearly everything else is the EC2, storage and network that workloads consume. Reducing it is mostly a matter of closing three gaps:

```
what you pay for  ≥  what nodes provide  ≥  what pods request  ≥  what pods actually use
        └── purchase options ──┘└──── bin-packing ────┘└──── right-sizing ────┘
```

Work from right to left. Buying discounted capacity for pods that request three times what they use locks in the waste.

## Where the money goes

| Item                  | Typical share    | Driven by                                               |
| :-------------------- | :--------------- | :------------------------------------------------------ |
| EC2 compute           | Largest          | Pod requests, bin-packing, purchase option              |
| Data transfer         | Often surprising | Cross-zone traffic, NAT gateway processing, egress      |
| EBS and other storage | Moderate         | Over-provisioned and orphaned volumes, snapshots        |
| Load balancers        | Moderate         | One per Service or Ingress, unless shared               |
| Observability         | Can be large     | Log volume and metric cardinality                       |
| Control plane         | Small, fixed     | Number of clusters; **much higher in extended support** |

## 1. See it

You cannot optimise what you cannot attribute.

- **Split cost allocation data for EKS** adds pod-level cost to the Cost and Usage Report, by cluster, namespace and workload — query it with Athena or view it in Cost Explorer. See [[AWS/cost-management/cost-usage-report|cost and usage report]] and [[AWS/cost-management/cost-explorer|Cost Explorer]].
- **[[Kubernetes/eks/observability/cost-monitoring/kubecost|Kubecost]] or OpenCost** show cost per namespace, label and deployment in near real time, with idle and efficiency figures.
- **Labels and tags.** Require `team` and `cost-centre` labels on workloads with [[Kubernetes/eks/security/policy-management|admission policy]], and propagate tags to nodes, volumes and load balancers — [[AWS/cost-management/cost-allocation-tags|cost allocation tags]].

Report cost **per team and per unit of work** (per request, per tenant). Showing teams their own number changes behaviour more than any central optimisation.

## 2. Right-size requests

Requests decide how much capacity is reserved. Usage far below requests is paid-for idle.

- Compare requested with actual over two weeks:

  ```promql
  sum by (namespace) (kube_pod_container_resource_requests{resource="cpu"})
    /
  sum by (namespace) (rate(container_cpu_usage_seconds_total[5m]))
  ```

- Run [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler|VPA]] in recommendation mode, or use Kubecost's suggestions, and apply them through normal deployments.
- Set CPU requests near typical usage and memory requests near peak. Memory is not compressible; CPU is.
- Scale replicas with [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] or KEDA instead of provisioning for peak all day, and scale idle workloads to zero — [[Kubernetes/eks/advanced/autoscaling|autoscaling]].
- Turn off non-production environments outside working hours. That alone removes about two thirds of their compute hours.

Details in [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|requests and limits]].

## 3. Pack nodes tightly

- **Consolidation.** [[Kubernetes/eks/compute/karpenter/README|Karpenter]] and [[Kubernetes/eks/compute/eks-auto-mode/README|Auto Mode]] remove underused nodes and replace them with cheaper ones. This is usually the largest single saving after right-sizing.
- **Instance flexibility.** Allow many families and sizes so the autoscaler can pick the cheapest shape for the pending pods.
- **Avoid fragmentation.** Many small node groups with narrow selectors, strict anti-affinity and zone pinning all strand capacity.
- **Watch DaemonSet overhead.** Agents on every node take a larger share of small nodes; fewer, larger nodes dilute it.
- **Raise pod density** where IP limits, not CPU, cap a node — [[Kubernetes/eks/networking/vpc-cni/prefix-delegation|prefix delegation]].

Protect workloads first with [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudgets]]: tight packing means pods move more often.

## 4. Pay less per unit

| Lever                                                             | Typical saving           | Suits                                                  |
| :---------------------------------------------------------------- | :----------------------- | :----------------------------------------------------- |
| [[Kubernetes/eks/compute/managed-node-groups/graviton\|Graviton]] | About 20% and more       | Anything with multi-architecture images                |
| [[Kubernetes/eks/compute/managed-node-groups/spot\|Spot]]         | Up to 90%                | Stateless, replicated, interruption-tolerant workloads |
| [[AWS/cost-management/savings-plans\|Compute Savings Plans]]      | Up to about 66%          | The steady baseline that is always running             |
| Current-generation instances                                      | Better price-performance | Everything                                             |

A common shape: Savings Plans cover the On-Demand baseline, Spot carries everything above it, and Graviton applies to both. Buy commitments **after** right-sizing and consolidation, and size them to the baseline, not the peak. See [[AWS/cost-management/ec2-cost-optimization|EC2 cost optimization]] and [[AWS/cost-management/pricing-models|pricing models]].

## 5. Network

Data transfer is the cost most often overlooked.

| Cost                             | Reduce it by                                                                             |
| :------------------------------- | :--------------------------------------------------------------------------------------- |
| Cross-zone traffic between pods  | Topology-aware routing; keeping chatty services in the same zone where resilience allows |
| NAT gateway data processing      | VPC endpoints for S3, ECR, CloudWatch and STS; an S3 gateway endpoint is free            |
| Image pulls through NAT          | ECR endpoints; pull-through cache for public images                                      |
| Many load balancers              | Share one ALB across Ingresses with `IngressGroup`, or use one Gateway                   |
| Cross-zone load balancer traffic | IP targets and zone-aware settings                                                       |

More in [[AWS/cost-management/network-cost-optimization|network cost optimization]].

## 6. Storage and observability

- Move `gp2` volumes to `gp3`: cheaper per GB with better baseline performance — [[Kubernetes/eks/storage/ebs-csi|EBS CSI]].
- Find orphaned volumes from deleted claims with a `Retain` policy, and old snapshots — [[AWS/cost-management/ebs-cost-optimization|EBS cost optimization]].
- Set retention on every log group, drop noisy logs at the agent, and control metric cardinality — [[Kubernetes/eks/observability/logging/pod-logging|pod logging]] and [[Kubernetes/eks/observability/metrics/prometheus|Prometheus]].

## 7. Clusters themselves

- **Stay out of extended support.** The control plane price is several times higher — [[Kubernetes/eks/cluster-upgrades/README|cluster upgrades]].
- **Consolidate small clusters.** Each has a control plane fee, its own system pods and its own half-empty nodes. Namespaces with [[Kubernetes/guides/non-functional/multi-tenancy|multi-tenancy]] controls are often enough.
- **Delete idle clusters**, including their NAT gateways and load balancers.

## An ordered plan

1. Turn on cost allocation; give each team its number.
2. Right-size requests for the top ten workloads by cost.
3. Enable consolidation and widen instance choice.
4. Move to Graviton where images allow.
5. Put tolerant workloads on Spot.
6. Add VPC endpoints; share load balancers.
7. Buy Savings Plans for what is left as steady baseline.
8. Review monthly; make cost a standing item beside reliability.

## Quick wins checklist

- [ ] Every container has resource requests
- [ ] Non-production scales down out of hours
- [ ] Consolidation enabled, with PodDisruptionBudgets in place
- [ ] `gp3` is the default StorageClass
- [ ] Log groups have retention set
- [ ] S3 gateway and ECR endpoints exist
- [ ] No cluster in extended support
- [ ] Orphaned volumes, snapshots and load balancers cleaned up

## Related

- [[Kubernetes/eks/advanced/README|Advanced EKS topics]]
- [[Kubernetes/guides/non-functional/cost-optimization|Kubernetes cost optimization]] — provider-neutral
- [[AWS/cost-management/README|AWS cost management]]
- [[Kubernetes/eks/compute/fargate/fargate-vs-ec2|Fargate vs EC2]]
- [EKS best practices: cost optimization](https://docs.aws.amazon.com/eks/latest/userguide/cost-optimization.html)

## Across the wiki

- [[Azure/compute/aks/cost-optimization-finops|AKS FinOps, Cost Allocation, and Cloud Spend Optimization]] — Kubernetes cost (Azure)
- [[GCP/compute/gke/cost-optimization-finops|GKE Cost Optimization, FinOps, and GKE Cost Allocation Architecture]] — Kubernetes cost (GCP)
- [[GCP/cost-management/pricing-models/README|GCP Cost Optimization, Committed Use Discounts (CUDs), and FinOps]] — Kubernetes cost (GCP)

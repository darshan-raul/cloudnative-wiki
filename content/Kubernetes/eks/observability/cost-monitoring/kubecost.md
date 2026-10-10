---
title: Kubecost on EKS
tags: [eks, observability, cost-monitoring, kubecost, finops]
date: 2026-05-17
description: Cost visibility for EKS with Kubecost — how it turns usage and prices into cost per namespace and workload, installation, allocation and efficiency views, savings recommendations, accuracy, limits and alternatives.
---

# Kubecost on EKS

The AWS bill says what a cluster's EC2 instances cost. It does not say which team, namespace or deployment is responsible. Kubecost fills that gap: it combines resource usage from the cluster with pricing to show **cost per Kubernetes object**, and how much of what you pay for is actually used.

It is built on **OpenCost**, the CNCF open-source cost model, and adds a UI, savings recommendations and longer retention. AWS distributes an EKS-optimized bundle as an add-on at no extra licence charge.

## How it calculates cost

```
metrics (kube-state-metrics, cAdvisor, node labels)  ─┐
                                                      ├─► cost model ─► cost per container, per hour
prices (public list prices, or your actual bill)     ─┘
```

For each container, per hour:

```
cost = max(requested, used) CPU × CPU price
     + max(requested, used) memory × memory price
     + storage, load balancers and network attributed to it
```

Using the larger of request and usage matters: a pod that requests four cores and uses one still reserves four, and is charged for four. The difference between requested and used is reported as **idle** cost.

Three kinds of cost need a decision about who pays:

| Cost               | What it is                                     | Options                                               |
| :----------------- | :--------------------------------------------- | :---------------------------------------------------- |
| **Idle**           | Node capacity nobody requested                 | Show separately, or spread across tenants             |
| **Shared**         | `kube-system`, ingress controllers, monitoring | Split evenly, or in proportion to each tenant's usage |
| **Out-of-cluster** | RDS, S3 and other resources a team uses        | Attribute by AWS tag                                  |

Decide these with finance before publishing numbers; they change each team's figure noticeably.

## Install

```bash
aws eks create-addon --cluster-name my-cluster --addon-name kubecost_kubecost
```

Or with Helm, from the EKS-optimized chart in Amazon ECR Public:

```bash
helm upgrade --install kubecost \
  oci://public.ecr.aws/kubecost/cost-analyzer \
  --namespace kubecost --create-namespace \
  -f https://raw.githubusercontent.com/kubecost/cost-analyzer-helm-chart/develop/cost-analyzer/values-eks-cost-monitoring.yaml
```

It installs the cost model, a bundled Prometheus and the UI, and needs a persistent volume ([[Kubernetes/eks/storage/ebs-csi|EBS CSI]]). Reach the UI with a port-forward to begin with:

```bash
kubectl port-forward -n kubecost deploy/kubecost-cost-analyzer 9090
```

Do not expose it publicly: it reveals the whole cluster's structure. Put it behind an internal load balancer with authentication.

To avoid running a second Prometheus, point Kubecost at an existing one or at [[Kubernetes/eks/observability/metrics/prometheus|Amazon Managed Prometheus]].

## Making the numbers accurate

Out of the box, Kubecost uses public On-Demand list prices. Real bills differ because of Spot, Savings Plans, Reserved Instances and negotiated discounts.

- **Cloud billing integration.** Give Kubecost read access to the [[AWS/cost-management/cost-usage-report|Cost and Usage Report]] through Athena, and it reconciles its estimates against what you were actually charged, typically a day or two behind.
- **Spot data feed** for accurate Spot prices.
- **Node labels** for instance type, zone and capacity type must be present — they are by default on EKS.

Without billing integration, treat the absolute numbers as indicative and the **relative** numbers — which namespace costs most — as reliable.

## What to look at

| View                   | Question it answers                                                               |
| :--------------------- | :-------------------------------------------------------------------------------- |
| **Allocations**        | What does each namespace, deployment, label or team cost over time?               |
| **Assets**             | What do the nodes, disks and load balancers cost?                                 |
| **Efficiency**         | How much of what each workload requests does it use?                              |
| **Savings**            | Where are over-sized requests, underused nodes, orphaned volumes, idle workloads? |
| **Budgets and alerts** | Has a team exceeded its budget, or did spend jump unexpectedly?                   |

The allocation view grouped by a `team` label is the report most organisations actually need. It only works if workloads carry that label consistently — enforce it with [[Kubernetes/eks/security/policy-management|admission policy]].

## Acting on recommendations

Kubecost suggests request sizes from observed usage. Treat them as input, not instructions:

- Look at a window long enough to include peaks — at least a week, ideally a full business cycle.
- Leave headroom on memory; an under-sized memory request ends in an OOM kill.
- Apply changes through the normal deployment path, one workload at a time, and watch latency and restarts.
- Recommendations for nodes assume pods can move; check [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudgets]] first.

The full optimisation sequence is in [[Kubernetes/eks/advanced/cost-optimization|EKS cost optimization]].

## Useful API calls

Everything in the UI is available over HTTP, for dashboards and chargeback reports:

```bash
# Cost by namespace for the last 7 days
curl -G http://localhost:9090/model/allocation \
  -d window=7d -d aggregate=namespace -d accumulate=true

# Cost by team label, with idle shared proportionally
curl -G http://localhost:9090/model/allocation \
  -d window=30d -d aggregate=label:team -d shareIdle=weighted
```

## Limits

| Limit                                | Detail                                                                                     |
| :----------------------------------- | :----------------------------------------------------------------------------------------- |
| Free tier scope                      | Single-cluster views and limited retention; a unified multi-cluster view is a paid feature |
| Network cost attribution             | Needs an optional network-cost DaemonSet, and is approximate                               |
| Fargate                              | Supported, with less granular data                                                         |
| Accuracy without billing integration | List prices only                                                                           |
| Its own footprint                    | The bundled Prometheus needs memory proportional to cluster size                           |

## Alternatives

| Option                                 | Notes                                                                                                        |
| :------------------------------------- | :----------------------------------------------------------------------------------------------------------- |
| **OpenCost**                           | The open-source core: the same allocation model and API, a simpler UI, no recommendations                    |
| **Split cost allocation data for EKS** | AWS-native: pod-level cost in the Cost and Usage Report, no agent to run, a day behind                       |
| **CloudWatch Container Insights**      | Usage, not cost — [[Kubernetes/eks/observability/metrics/cloudwatch-container-insights\|Container Insights]] |
| Commercial FinOps platforms            | Multi-cloud and automation features                                                                          |

A reasonable minimum is split cost allocation data for monthly chargeback, plus OpenCost or Kubecost when engineers need a live view to act on.

## Related

- [[Kubernetes/eks/observability/README|EKS observability overview]]
- [[AWS/cost-management/README|AWS cost management]]
- [[Kubernetes/guides/non-functional/cost-optimization|Kubernetes cost optimization]]
- [Kubecost](https://www.kubecost.com/)
- [EKS Workshop: Kubecost](https://www.eksworkshop.com/docs/observability/kubecost/)

## Across the wiki

- [[Azure/compute/aks/cost-optimization-finops|AKS FinOps, Cost Allocation, and Cloud Spend Optimization]] — Kubernetes cost (Azure)
- [[GCP/compute/gke/cost-optimization-finops|GKE Cost Optimization, FinOps, and GKE Cost Allocation Architecture]] — Kubernetes cost (GCP)
- [[GCP/cost-management/pricing-models/README|GCP Cost Optimization, Committed Use Discounts (CUDs), and FinOps]] — Kubernetes cost (GCP)

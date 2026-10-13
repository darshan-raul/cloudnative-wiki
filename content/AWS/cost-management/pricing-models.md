---
title: AWS Pricing Models
description: Accurate billing models, decision workflows and scoped examples for pricing models.
tags:
  - aws/cost-management
date: 2026-10-12
---

# AWS Pricing Models

Price exercises in this note use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, unless explicitly identified as a dated published fee. They are assumptions, not current tariffs; exclusions remain material.

Choose a purchasing model after measuring demand and failure tolerance. A discount does not remove storage, networking, support, tax or licensing costs.

## Purchasing choices

| Model                 | Suitable workload                                            | Main constraint                                          |
| --------------------- | ------------------------------------------------------------ | -------------------------------------------------------- |
| On-Demand             | New, variable or short-lived demand                          | No long-term discount commitment                         |
| Spot                  | Restartable batch, distributed workers and flexible capacity | Capacity can be interrupted; checkpoint and diversify    |
| Reserved Instances    | Compatible steady usage in a service offering reservations   | Scope, term, exchange and capacity rules vary by service |
| Savings Plans         | A predictable eligible hourly spend floor                    | Unused hourly commitment is still payable                |
| Capacity Reservations | EC2 capacity availability requirements                       | Capacity reservation is distinct from a discount         |

EC2 per-second billing has a 60-second minimum for supported products, including eligible Windows Server and SQL Server instances. Check the selected AMI/OS/license and product pricing; do not assume every marketplace license follows one rule.

## Worked comparison

Assume 20 instances run for a 30-day month (720 hours), with an illustrative On-Demand rate of \$0.192/instance-hour and a discounted rate of \$0.127/instance-hour:

- On-Demand: 20 × 720 × \$0.192 = \$2,764.80.
- Discounted usage: 20 × 720 × \$0.127 = \$1,828.80.
- Difference: \$936.00, or about 33.9%.

These are assumed rates, not an AWS quote. They exclude upfront payments, unused commitments, storage and transfer. Compare effective total cost over the commitment term rather than discount percentage alone.

## Free Tier cohorts

Accounts created before July 15, 2025 follow the legacy Free Tier rules. Newer accounts use the credit-based experience: up to \$200 in credits, a free plan lasting up to six months, and credit expiration rules distinct from the plan duration. Paid-plan and Organizations eligibility matter; creating member accounts is not a reliable way to multiply benefits.

## Decision exercise

Estimate a workload's hourly minimum, peak and idle hours. Price three options in AWS Pricing Calculator, keeping the same Region, architecture and licenses. Reject a commitment that exceeds the post-rightsizing baseline.

## Payment options and interruption trade-offs

| Payment option  | Cash timing                               | Comparison method                                                            |
| --------------- | ----------------------------------------- | ---------------------------------------------------------------------------- |
| No Upfront      | Recurring commitment charges              | Sum all committed charges over the term                                      |
| Partial Upfront | An initial payment plus recurring charges | Add both; the upfront fraction is offering-specific                          |
| All Upfront     | Term payment at purchase                  | Divide total by term hours for effective cost, then account for unused hours |

Payment choice does not change an RI's matching attributes or create Savings Plans capacity. Discount ceilings are not a quote for a selected configuration. Compare term, flexibility, financing and likelihood of using the benefit.

Spot pools are defined by instance type and AZ. Diversify compatible pools and use capacity-aware allocation rather than chasing one cheapest pool. Checkpoint progress and make workers restartable. A Spot interruption notice is best-effort; hibernation can begin without the normal two-minute lead. Defined-duration Spot blocks are retired, not a current way to buy interruption-free work.

### Second worked scenario: mixed workers

For an illustrative us-east-1 exercise evaluated on 2026-10-12, assume four baseline workers at \$0.10/hour for 720 hours and 20 additional workers for 80 hours. Assume an available Spot rate of \$0.03/hour:

```text
all On-Demand = (4 × 720 + 20 × 80) × $0.10 = $448
mixed         = 4 × 720 × $0.10 + 20 × 80 × $0.03 = $336
gross difference = $112
```

These are hypothetical rates, not a quote or a guaranteed Spot discount. Add retry/checkpoint work, storage and transfer before claiming net savings. If deadline-critical workers cannot recover from interruption, keep sufficient non-Spot capacity.

## Traffic and quota checks

Price both direction and service path: same-AZ exceptions, cross-AZ peering, inter-Region replication, NAT processing and internet delivery differ. Quotas frequently use vCPUs and instance categories per Region rather than an immutable 20-instance allowance. Verify quota headroom before committing to a launch topology.

- [Spot interruptions](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-instance-termination-notices.html)
- [EC2 quotas](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-resource-limits.html)

## References

- [EC2 pricing](https://aws.amazon.com/ec2/pricing/)
- [Windows and SQL Server per-second billing](https://aws.amazon.com/about-aws/whats-new/2021/06/announcing-per-second-billing-for-ec2-windows-server-and-sql-server-instances/)
- [Free Tier FAQ and account cohorts](https://aws.amazon.com/free/free-tier-faqs/)

See [[AWS/cost-management/savings-plans|Savings Plans]] and [[AWS/cost-management/reserved-instances|Reserved Instances]].

## Across the wiki

- [[Kubernetes/eks/compute/managed-node-groups/README|Managed Node Groups]] — node pools and spot capacity (Kubernetes)
- [[Azure/compute/aks/node-pools-heterogeneous|AKS Heterogeneous Node Pools — System vs User, Ephemeral OS Disks, and Azure Linux]] — node pools and spot capacity (Azure)
- [[GCP/compute/gke/node-pools-heterogeneous|GKE Heterogeneous Node Pools, Taints, Tolerations, and Accelerator Topologies]] — node pools and spot capacity (GCP)
- [[Kubernetes/eks/compute/managed-node-groups/spot|Spot Instances on EKS]] — node pools and spot capacity (Kubernetes)

- [Savings Plans application and priority](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-applying.html).
- [RI application scope](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/apply_ri.html).

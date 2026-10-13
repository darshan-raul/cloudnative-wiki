---
title: EC2 Cost Optimization
description: Billing models, trade-offs, safe workflows and scoped examples for ec2 cost optimization.
tags:
  - aws/cost-management
date: 2026-10-12
---

# EC2 Cost Optimization

Price exercises use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, not current tariffs, unless explicitly identified as a dated published fee.

Right-size first, then choose [[AWS/cost-management/pricing-models|purchasing options]]. A discounted oversized instance is still wasteful.

## Evidence for rightsizing

Measure peak and percentile CPU, memory, network, storage IOPS/throughput, latency and burst behavior across representative business cycles. CPU averages alone can hide saturation. EC2 detailed monitoring improves metric frequency; it does **not** collect guest memory. Use the CloudWatch agent or a supported integration for memory and include metric charges.

Compute Optimizer requires at least 30 hours of EC2 metric data in the preceding 14 days, rather than a universal 14-day waiting period. Enhanced settings and resource types have additional requirements. Savings estimation mode can incorporate account-specific discounts; do not assume recommendations always ignore commitments.

Evaluate architecture/AMI support before adopting Graviton. Benchmark licensing, dependencies and performance rather than promising a universal savings percentage. Burstable instances can accrue surplus-credit charges.

## Capacity strategy

Keep reliable baseline capacity across the required AZs. Use diversified Spot pools for interruptible workers, with checkpoints and interruption handling; a low Spot price is not a capacity guarantee. Auto Scaling must use workload-appropriate metrics and account for warm-up, quotas and downstream bottlenecks.

Apply commitments to the post-rightsizing hourly floor. ASG replacement instances can receive matching RI benefits; replacement is not consumption of an RI token. Capacity Reservations and billing discounts solve different problems.

## Scheduling example

Assume 50 development instances, a 30-day month and 22 workdays, running 10 hours each workday:

- Always on: 50 × 720 = 36,000 instance-hours.
- Scheduled: 50 × 220 = 11,000 instance-hours.
- Avoided running hours: 25,000; at an assumed \$0.192/hour, \$4,800.

This is gross compute avoidance, not guaranteed net savings. EBS, networking, scheduler overhead and unused commitments remain. Stopping a fleet covered by fixed hourly commitments might not lower the invoice.

## Review checklist

Record owner, SLO, measured bottleneck, candidate size and rollback criteria. Check stopped instances' attached storage, public IPv4 and load-balancer costs separately. Never terminate resources based only on a low CPU threshold.

## Scaling policy comparison

| Policy          | Suitable signal                                      | Caution                                                  |
| --------------- | ---------------------------------------------------- | -------------------------------------------------------- |
| Target tracking | Proportional load such as CPU or requests per target | Metric must track capacity demand                        |
| Step scaling    | Explicit alarm bands                                 | Tune steps, warm-up and oscillation                      |
| Scheduled       | Known business/batch schedule                        | Timezone and exceptions matter                           |
| Predictive      | Recurring patterns with sufficient history           | Validate forecast; not a Compute Optimizer resizing mode |

An ASG mixed-instance policy specifies `InstancesDistribution` (plural), an On-Demand base capacity and a percentage **above** that base. A value of 20% above the base does not mean exactly 20% of the whole fleet is On-Demand. Check allocation strategy, compatible instance overrides, launch template architecture and weighted capacity.

## Right-sizing worked example

Assume twelve compatible workers run all 8,760 hours/year. Hypothetical us-east-1 prices for this 2026-10-12 study exercise are \$0.384/hour currently and \$0.192/hour after resizing:

```text
gross yearly avoidance = 12 × ($0.384 − $0.192) × 8,760
                       = $20,183.04
```

Do not invent incorrect vCPU/RAM attributes to justify the resize. Measure peak memory, CPU, EBS/network bandwidth and user latency, and test an actual candidate type. Gross avoidance may not become invoice savings if reservations remain unused; discount-aware estimates and normalized-unit eligibility matter.

Lowering an ASG maximum from 20 to 10 does not itself save money when only eight instances run. It changes the allowed ceiling and can cap recovery/peak capacity. Validate this as a reliability/control decision, not a guaranteed \$3,500 monthly reduction.

## Graviton migration and idle-fleet lab

Build/test an ARM64 artifact and AMI, check native libraries and vendor agents, and compare equivalent workload throughput and tail latency with the x86 candidate. Keep rollback artifacts. Avoid a universal 20%/40% savings promise.

Inventory running instances read-only:

```bash
aws ec2 describe-instances --region us-east-1 \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,Launched:LaunchTime,Tags:Tags}' \
  --output json
```

Requires AWS CLI and authorized DescribeInstances access. Old launch time is not evidence of waste; obtain owner, usage and dependency evidence. Include stopped-instance EBS, snapshots, IPv4 and load balancers in the review.

- [Mixed instance policies](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-mixed-instances-groups.html)
- [DescribeInstances contract](https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-instances.html)

## References

- [Compute Optimizer requirements](https://docs.aws.amazon.com/compute-optimizer/latest/ug/requirements.html)
- [Account-discount savings estimation](https://docs.aws.amazon.com/compute-optimizer/latest/ug/activate-savings-estimation-mode.html)
- [EC2 monitoring metrics](https://docs.aws.amazon.com/autoscaling/ec2/userguide/enable-as-instance-metrics.html)
- [EC2 pricing](https://aws.amazon.com/ec2/pricing/)

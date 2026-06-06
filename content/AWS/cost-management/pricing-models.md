---
title: AWS Pricing Models
description: AWS pricing models — On-Demand, Reserved Instances, Savings Plans, Spot Instances, free tier, and how they interact
tags:
  - aws
  - cost-management
---

# AWS Pricing Models

Every AWS service has a pricing model. Understanding the four core compute pricing mechanisms — On-Demand, Reserved Instances, Savings Plans, and Spot — and when each applies is the foundation of cost optimization on AWS.

## On-Demand

Pay per second (Linux, billed per second after first minute) or per hour (Windows, RHEL, other OSes). No commitment. No discount. Highest unit cost but maximum flexibility.

**When to use:** Short-lived workloads, unpredictable traffic, spiky demand, proof-of-concept, disaster recovery, anything you can't forecast.

**Hidden costs to watch:**
- Windows and RHEL are billed per hour, not per second
- Data transfer OUT is priced separately (often the biggest surprise)
- NAT Gateway charges per hour + per GB processed
- Load balancers charge per LCU (ALB) or per hour (NLB)
- EBS volumes charge per GB-month (even when unattached)

## Reserved Instances (RI)

Commit to a usage term (1 or 3 years) in exchange for a significant discount vs On-Demand. Billed as one of three payment options:

| Payment Option | Upfront | Discount vs On-Demand |
|----------------|---------|----------------------|
| No Upfront     | None    | ~40-60%              |
| Partial Upfront| 50%    | ~60-70%              |
| All Upfront    | 100%   | up to 72%            |

**Instance Size Flexibility (EC2 RI):** A single az-style Standard RI automatically applies to any instance of the same family within the purchased AZ. Size flexibility does NOT apply across AZs or across instance families.

**Scope:** Standard RIs apply to a specific AZ. If the AZ fails, the RI is "stuck." Regional RIs don't reserve capacity but get the discount anywhere in the region. Convertible RIs can be exchanged for different instance types/families but carry a lower discount ceiling.

**Windows gotcha:** RI pricing for Windows includes the SQL Server license if you use AWS-provided Windows + SQL AMI. Bring-your-own-license (BYOL) is separate.

## Savings Plans (SP)

AWS's evolution from RI. Two main types:

**Compute Savings Plans:** Most flexible. Apply to EC2, Lambda, Fargate usage regardless of instance family, OS, region, or AZ. Savings vs On-Demand up to 66%. Unlike RIs, no capacity reservation.

**EC2 Instance Savings Plans:** Applies to a specific instance family in a region. Up to 72% savings. More restrictive than Compute SP but better discount. Can still switch OS and instance size within the family.

**How commitment works:** You commit to a $/hour spend amount. If you use less than committed, you pay the difference. If you use more, the excess is billed at On-Demand rates (not SP rates — the SP only covers up to the commitment).

**SP vs RI:** SP is generally better for modern architectures where you might switch between instance families or move workloads. RI is better when you have stable, predictable baseline capacity in a specific AZ that you want to reserve.

## Spot Instances

AWS offers unused capacity at up to 90% off On-Demand pricing. The catch: AWS can reclaim the instance with a 2-minute warning when they need the capacity back.

**Interruption handling:**
- `hibernate` — hibernate the instance (must have supported OS, hibernation enabled in AMI)
- `stop` — stop the instance, resume later (persistent capacity in capacity-optimized pools)
- `terminate` — shut down (default, no recovery)

**Spot Fleet:** Launch a fleet of Spot instances across multiple AZs and instance pools. Define target capacity, allocation strategy (lowest-price, capacity-optimized, price-capacity-optimized). Automatically replenish interrupted instances.

**Spot Blocks:** Request Spot with a defined duration (1-6 hours) that won't be interrupted. Priced at a discount but not as deep as regular Spot.

**Use cases:** Batch processing, ML training, stateless web servers, CI/CD build agents, Hadoop/Spark clusters, anything fault-tolerant.

**Don't use for:** Databases, stateful services, anything requiring guaranteed uptime, SAP/ERP workloads, anything with <2 minute recovery time tolerance.

## Free Tier

AWS offers 12-month free tier for new accounts: 750h EC2 t2.micro/month, 5GB S3, 20GB EBS, 1M Lambda requests, etc.

**Gotcha:** Not all services are free tier eligible. Some services (Lambda, SNS, DynamoDB) have an always-free tier that doesn't expire. CloudWatch Logs has a free tier that expires.

**Hidden trap:** Free tier is account-wide, not per-service. If you have 3 accounts, each gets its own free tier.

## How the Models Interact

At any given time, your running instances are billed in this priority order:

1. **Savings Plans** (covers committed $/hour)
2. **Reserved Instances** (covers reserved capacity)
3. **Spot Instances** (capacity available at discount)
4. **On-Demand** (everything above doesn't cover)

This means if you have a Compute SP covering $100/hour of your $150/hour spend, the remaining $50/hour is covered by On-Demand (or Spot, if you configure mixed policies).

## Data Transfer Pricing

Always the most overlooked cost component:

- **同一AZ内传输**: Free (same AZ, same account)
- **AZ-to-AZ (same region)**: ~$0.01/GB
- **跨区域 (region-to-region)**: ~$0.02-0.09/GB depending on region pair
- **互联网出口**: ~$0.09/GB (varies by region)
- **CloudFront → Internet**: cheaper than NAT Gateway → Internet
- **S3数据传输**: in-bound free, out-bound charged
- **VPC Peering**: free within same region, charged across regions

A common architect mistake: designing a multi-tier system where services in different AZs talk to each other at scale, then discovering the AZ-to-AZ data transfer bill.

## References

- **Homepage:** https://aws.amazon.com/ec2/pricing/
- **Documentation:** https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/concepts.html
- **Pricing:** https://aws.amazon.com/ec2/pricing/on-demand/

## Pricing Examples

**Scenario 1:** Running 20 EC2 instances (m5.xlarge, Linux) in us-east-1, 24/7. On-Demand cost: ~$1,216/month (20 × $0.192/hr × 24 × 30). With a 3-year All Upfront Compute SP at $0.127/hr: ~$800/month (33% savings).

**Scenario 2:** A web application with 4 m5.large instances behind an ALB, processing 500K requests/day with spiky traffic (peaks 10x baseline on weekends). Baseline 4 instances at $0.192/hr = $553/month + 20 Spot m5.large for burst = $280/month (Spot at 90% off). Total: ~$833/month vs $1,540/month all On-Demand.

## Nuggets & Gotchas

- **Windows EC2 bills per hour, not per second:** Unlike Linux (billed per second after first minute), Windows and RHEL instances are billed per hour. A 90-second Windows instance costs 1 hour of billing.
- **Spot interruption is 2-minute warning, not guaranteed:** AWS guarantees the 2-minute warning but capacity can be reclaimed immediately after. Design for interruption in all Spot workloads.
- **On-Demand limits are per account per region:** Default limit is 20 instances per instance type per region. Running a large auto-scaling group requires requesting a limit increase.
- **Data transfer between AZs costs $0.01/GB:** A microservices architecture where services in different AZs communicate heavily will accumulate significant AZ-to-AZ transfer costs. Keep synchronous inter-service communication within the same AZ where possible.
- **Savings Plans don't reserve capacity:** A Compute SP covers the cost of your usage but doesn't guarantee capacity. If AWS needs the capacity back, SP customers are not protected — only zonal RIs reserve actual capacity.
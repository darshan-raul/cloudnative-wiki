---
title: Savings Plans
description: AWS Savings Plans — Compute SP vs EC2 Instance SP vs SageMaker SP, commitment management, flexibility, and SP vs RI trade-offs
tags:
  - aws
  - cost-management
---

# Savings Plans

Savings Plans (SP) are AWS's flexible commitment pricing model. You commit to a consistent hourly spend for a 1 or 3 year term and get discounts up to 72% vs On-Demand rates. They replaced Reserved Instances as the primary commitment mechanism for most workloads.

## Types of Savings Plans

### Compute Savings Plans

The most flexible SP. Applies to:
- EC2 (any instance family, any AZ, any OS)
- Lambda (any runtime)
- Fargate (any configuration)

Coverage example: A Compute SP commitment of $50/hour covers any combination of:
- 10 x t3.medium EC2 in us-east-1
- 5 x c6i.large in eu-west-2
- 1,000 Lambda invocations/hour at 128MB
- 20 Fargate tasks at 1 vCPU

Discount: Up to 66% off On-Demand.

### EC2 Instance Savings Plans

More restrictive — applies to a specific instance family in a specific region. Within that family, you get flexibility on:
- Instance size (t3.large vs t3.medium)
- OS (Linux vs Windows — but Windows is a different charge code)
- AZ (regional scope)

Discount: Up to 72% off On-Demand.

### SageMaker Savings Plans

Apply to SageMaker training, notebook, and processing usage. Up to 64% savings.

## How the Commitment Works

You commit to a **$/hour spend amount**, not a specific instance count.

**Under-commitment:**
```
You commit $50/hour. Your actual usage averages $40/hour.
You still pay $50/hour.
The extra $10 is "wasted" — you bought commitment you didn't use.
```

**Over-commitment:**
```
You commit $50/hour. Your actual usage peaks at $80/hour.
$50 is covered by SP. The $30 above the commitment is billed at On-Demand.
You don't get SP rates on the excess — SP only covers up to the commitment.
```

**Right-sizing your commitment:**
- Look at your 30-day average hourly spend
- Commit 70-80% of your baseline (not peak)
- Let the remaining 20-30% be covered by On-Demand
- RIs/SPs are not meant to cover spikes — that's what On-Demand and Spot are for

## Instance Size Flexibility

EC2 Instance Savings Plans give you size flexibility within the same family:

```
You buy an m6i.large (2 vCPU, 8GB) EC2 Instance SP.
Your actual usage is m6i.xlarge (4 vCPU, 16GB).

The SP covers the xlarge because it falls within the same m6i family.
SP applies to m6i.large, m6i.xlarge, m6i.2xlarge, etc.
```

Compute Savings Plans extend this across families — m6i to c6i to r6i all covered by a single Compute SP.

## SP vs Reserved Instances

| Factor | Savings Plans | Reserved Instances |
|--------|--------------|-------------------|
| Discount | Up to 66% (Compute SP) | Up to 72% (All Upfront) |
| Flexibility | Can change instance family (Compute SP) | Must specify family (Standard RI) |
| Capacity reservation | No | AZ-specific reservation (zonal RI) |
| Scope | Regional | Zonal or Regional |
| Covered services | EC2, Lambda, Fargate | EC2, RDS, ElastiCache, Redshift |
| Windows pricing | Included in SP rate | RI rate + Windows license separate |

**When to choose SP over RI:**
- You run mixed workloads across instance families
- You use Lambda or Fargate
- You want the flexibility to shift architecture without losing coverage
- You prioritize discount ceiling over capacity reservation

**When to choose RI over SP:**
- You need capacity reservation in a specific AZ (zonal RI)
- You run stable, single-family workloads
- You want the maximum possible discount
- You're running RDS, ElastiCache, or Redshift (RIs cover these, SPs don't)

## Buying Strategy

1. **Analyze first.** Use Cost Explorer to understand your 30/90-day average spend by service. Compute SPs cover EC2, Lambda, Fargate. If you have RDS or ElastiCache, RIs still make sense for those.

2. **Buy Compute SP for baseline.** If 60% of your spend is compute and it's reasonably predictable, buy Compute SP covering 70% of that.

3. **Use 3-year for stable workloads.** The discount difference between 1-year and 3-year is significant. If the workload is stable, commit 3-year.

4. **Blend SP + Spot.** A common pattern: SP covers your baseline (70-80% of average), Spot covers bursty workloads at 90% off, On-Demand covers the spikes.

5. **Don't over-buy.** A common mistake is buying SP based on peak usage. SPs that go unused still get charged.

## Checking Coverage

In Cost Explorer, the **Coverage** tab shows:
- What % of your EC2/Lambda/Fargate spend is covered by SP/RI
- How much is still On-Demand (uncovered spend)
- Recommendations for additional SP purchases

Coverage = (SP-covered spend + RI-covered spend) / Total spend × 100

Target: 80-90% coverage for stable production workloads. Lower for dev/test. Higher for always-on baseline.

## References

- **Homepage:** https://aws.amazon.com/savingsplans/
- **Documentation:** https://docs.aws.amazon.com/savingsplans/latest/userguide/
- **Pricing:** https://aws.amazon.com/savingsplans/pricing/

## Pricing Examples

**Scenario 1:** A production workload running 30 EC2 instances (mixed m6i and c6i families) + 500 Lambda functions. Monthly On-Demand spend: $4,200. Buying a 1-year Compute SP at 60% coverage ($2,520/hr commitment × 730hr = $1,840/month): saves $900/month vs pure On-Demand.

**Scenario 2:** A SaaS application with 15 Lambda functions (avg 50GB-s/month total) and 8 Fargate tasks (2 vCPU, 4GB each). On-Demand: Lambda ~$65/month + Fargate ~$380/month = $445/month. A 1-year Compute SP at $300/month commitment covers 90% of spend: saves ~$120/month.

## Nuggets & Gotchas

- **SP commitment is a floor, not a ceiling:** You pay for the committed amount regardless of actual usage. If you commit $50/hour but only use $30/hour, you still pay $50.
- **Over-commitment doesn't get SP rates:** Usage above your SP commitment is billed at On-Demand rates. A $50/hour SP with $80/hour actual usage means $50 at SP rate + $30 at On-Demand.
- **Compute SP does not cover RDS, ElastiCache, or Redshift:** Only EC2, Lambda, and Fargate. For databases you still need RIs.
- **EC2 Instance SP doesn't cover other instance families:** If you buy an m6i Instance SP, it won't cover your c6i or r6i instances — they'll be On-Demand.
- **SP commitment is per account:** A SP bought in account A doesn't cover usage in account B, even within the same AWS Organization (use consolidated billing for RI/SP sharing instead).
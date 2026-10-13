---
title: Reserved Instances
description: Accurate billing models, decision workflows and scoped examples for reserved instances.
tags:
  - aws/cost-management
date: 2026-10-12
---

# Reserved Instances

Price exercises in this note use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, unless explicitly identified as a dated published fee. They are assumptions, not current tariffs; exclusions remain material.

A Reserved Instance (RI) is a billing benefit with service-specific rules. An EC2 RI is not a particular instance, and Auto Scaling replacements do not consume or destroy the purchase.

## EC2 scope and flexibility

| Scope or class | Billing behavior                                         | Capacity and change considerations                            |
| -------------- | -------------------------------------------------------- | ------------------------------------------------------------- |
| Regional       | Can apply across AZs in the Region                       | No AZ capacity reservation                                    |
| Zonal          | Matches the specified AZ and attributes                  | Provides capacity reservation for matching EC2 usage          |
| Standard       | Generally more constrained configuration changes         | Eligible EC2 Standard RIs can be sold under Marketplace rules |
| Convertible    | Can exchange within documented value/configuration rules | Cannot be sold on the RI Marketplace                          |

Instance-size flexibility applies to eligible **regional Linux/UNIX, default-tenancy** RIs, not universally to zonal RIs or licensed operating systems. Normalization factors include large = 4, xlarge = 8 and 2xlarge = 16. Eight matching large units can be covered by two matching 2xlarge regional RIs, subject to eligibility. Family, platform and tenancy still matter.

RDS, ElastiCache and other service reservations must be evaluated under their own billing rules. Do not infer EC2 capacity reservation or size-flexibility semantics. An RDS Multi-AZ standby is not free merely because the primary has a reservation: match the purchased offering to deployment and instance requirements.

## Effective-cost calculation

Assume \$3,800 upfront plus \$120 per month for a one-year offering:

- Total: \$3,800 + 12 × \$120 = \$5,240.
- Effective hourly cost, using 8,760 hours: \$5,240 ÷ 8,760 ≈ \$0.5982.
- Compare against equivalent On-Demand usage and any unused hours.

For a three-year \$980 all-upfront example, \$980 ÷ (3 × 8,760) ≈ \$0.03729/hour. These are arithmetic exercises, not current offers.

## Marketplace caution

Only eligible EC2 Standard RIs are sellable; Convertible and other services' reservations are not. Seller location, bank-account, ownership duration and remaining-term conditions apply. A listed RI may not sell. Treat resale proceeds and fees as uncertain, not guaranteed savings.

## Normalized-unit worksheet

For eligible regional Linux/UNIX default-tenancy usage, take ten large RIs in one matching family/Region: 10 × 4 = 40 normalized units/hour.

| Running usage                       | Normalized units/hour | Outcome                               |
| ----------------------------------- | --------------------- | ------------------------------------- |
| Ten large                           | 40                    | Fully covered                         |
| Five xlarge                         | 40                    | Fully covered                         |
| Five large plus three xlarge        | 20 + 24 = 44          | Four units uncovered                  |
| Eight large                         | 32                    | Eight purchased units unused          |
| Matching size in a different family | Not matching          | No automatic cross-family flexibility |

The four uncovered units are one large-equivalent hour, not an eleventh purchased RI. Zonal reservations and noneligible platforms require exact matching under their rules. Do not apply this table to RDS or dedicated tenancy.

## Payment and workload break-even

Use the payment table in [[AWS/cost-management/pricing-models|pricing models]], then compare against realistic hours. For a hypothetical us-east-1 offer assessed on 2026-10-12, assume \$5,240 annual total and \$0.80/hour equivalent On-Demand:

```text
break-even running hours = $5,240 / $0.80 = 6,550
fraction of 8,760-hour year = 74.77%
```

At only 2,600 hours/year, On-Demand would be \$2,080, below the commitment's \$5,240. Lower hourly prices are not enough when utilization is poor. Sharing compatible benefit with other workloads changes the comparison; switching off one workload does not automatically recover the payment.

## Reservation decision checklist

- Identify service, Region, platform/license, tenancy and scope.
- Distinguish an AZ capacity need from a billing-discount objective.
- Match term to known business/architecture changes.
- Compare actual payment options rather than assumed upfront percentages.
- Assess utilization during nights, outages and planned migrations.
- Include independently billed replicas/storage/networking.
- Document modification/exchange/Marketplace conditions and uncertainty.

Low CPU is separate from reservation utilization: a matching instance can receive a benefit all day while wasting application capacity. Rightsize before renewal. A three-year reservation for an uncertain migration target is a financial risk even if its published discount is attractive.

## References

- [EC2 RI application and normalization](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/apply_ri.html)
- [RI billing and sharing](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/concepts-reserved-instances-application.html)
- [Marketplace restrictions](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ri-market-general.html)

See [[AWS/cost-management/ri-management|RI Management]].

## Across the wiki

- [[GCP/cost-management/pricing-models/README|GCP Cost Optimization, Committed Use Discounts (CUDs), and FinOps]] — cost management (GCP)
- [[Kubernetes/guides/non-functional/cost-optimization|Cost Optimization]] — cost management (Kubernetes)

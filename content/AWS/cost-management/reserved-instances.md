---
title: Reserved Instances
description: AWS Reserved Instances — Standard vs Convertible, regional vs zonal, payment options, instance size flexibility, and management
tags:
  - aws
  - cost-management
---

# Reserved Instances

Reserved Instances (RI) let you reserve EC2, RDS, ElastiCache, Redshift, or other capacity for 1 or 3 years in exchange for a discount vs On-Demand pricing. They're the older sibling to Savings Plans — more restrictive in some ways, but with capacity reservation options that SPs don't offer.

## RI vs On-Demand

| Factor | On-Demand | Reserved Instance |
|--------|-----------|-------------------|
| Price | Full rate | Up to 72% discount |
| Commitment | None | 1 or 3 years |
| Capacity | Not reserved | Reserved (zonal RI) |
| Billing | Per second (Linux) | Per second (Linux, no upfront) |

## RI Types

### Standard RI

The original RI type. Reserved for a specific instance configuration:
- Instance family (e.g., m6i, c6i)
- Instance size (e.g., large, xlarge) — with size flexibility within the AZ
- Region or specific AZ
- Tenancy: Default or Dedicated

**Zonal RI:** Reserves capacity in a specific AZ. Higher discount but the reservation is stranded if the AZ has issues. Use for predictable baseline workloads that need the capacity guarantee.

**Regional RI:** No capacity reservation — just a pricing discount that applies anywhere in the region. Lower discount than zonal but no stranded capacity risk. Good when you want the discount but need availability across AZs.

### Convertible RI

Can be exchanged for different instance types, families, or operating systems within the same instance family group. Lower discount ceiling (~60%) but maximum flexibility.

Use Convertible when:
- You might switch from Intel to AMD or Graviton
- You might resize instances as needs change
- You want RI-level discount but aren't certain of exact requirements

## Payment Options

| Option | Upfront | Effective Discount |
|--------|---------|-------------------|
| No Upfront | $0 | ~40-60% |
| Partial Upfront | ~50% | ~60-70% |
| All Upfront | 100% | up to 72% |

All Upfront with 3-year term gives the maximum discount. Partial/No Upfront with 1-year is the minimum commitment option.

## Instance Size Flexibility

**Zonal Standard RI:** Size flexibility within the same instance family, within the same AZ. Buy 10 x m6i.large in us-east-1a, and those RI units automatically apply to any m6i instance size in us-east-1a.

```
1 RI unit = 1 x m6i.large (2 vCPU, 8GB)

Consuming instance: m6i.xlarge (4 vCPU, 16GB)
RI units consumed: 2 (each xlarge = 2 x large)

If you have 10 RIs:
- 10 x large = 10 consumed (all covered)
- 5 x xlarge = 10 consumed (5 xlarge use all 10 RIs)
- 15 x large = 10 consumed (5 uncovered, billed On-Demand)
```

**Regional RI:** No size flexibility — each RI unit covers exactly what you bought.

**Convertible RI:** Size flexibility via instance family exchanges. Can exchange a large for an xlarge of a different family, as long as the OS and tenancy match.

## Services Covered by RI

RI pricing is available for:
- EC2 (all instance families)
- RDS (MySQL, PostgreSQL, MariaDB, Oracle, SQL Server)
- ElastiCache (Redis, Memcached)
- Redshift
- OpenSearch (formerly Elasticsearch)
- SageMaker (not via RI — use SageMaker SP instead)

**Note:** Lambda, Fargate, and ECS do NOT support RI pricing — use Savings Plans for serverless.

## RI Marketplace

Unused RI capacity can be sold on the RI Marketplace. Requirements:
- At least 30 days remaining on the term
- No more than 3 years total remaining
- Account must be in good standing

This is useful when you migrate workloads mid-term and want to recover some of the upfront cost.

## Coverage vs Utilization

These two metrics measure different things:

**Coverage:** What % of your instances are covered by RI/SP. Target: 80-90%+ for production baseline.

```
Coverage = (Instance hours covered by RI/SP) / (Total instance hours) × 100
```

**Utilization:** Are you fully using the instances you reserved?

```
Utilization = (Hours of RI capacity actually used) / (Hours of RI capacity purchased) × 100
```

An RI with 50% utilization means half the reserved capacity sat idle. You paid for it but didn't use it. This isn't necessarily bad — it's often better than running On-Demand and risking capacity unavailability — but it's a cost efficiency signal.

## When to Use RIs

- **Baseline always-on workloads** in RDS, ElastiCache, Redshift
- **Predictable capacity needs** in a specific AZ (zonal RI)
- **Migrated databases** where you know the exact instance size
- **Multi-AZ with known read replica count** — buy the primary RI, let replicas be On-Demand or covered by regional RI

## Common Mistakes

1. **Buying on peak, not baseline.** If you buy 100 RIs for a workload that peaks at 100 but averages 40, you're paying for 60 unused RIs most of the time.

2. **Ignoring regional vs zonal.** Zonal RIs give better discounts but strand if the AZ has issues. Always know which you're buying.

3. **Buying RI for development workloads.** Dev/test environments that run 8-5 Monday-Friday are better served by Savings Plans + auto stoppage schedules, not RIs.

4. **Buying 3-year for fast-changing workloads.** If you're mid-migration to Graviton or constantly resizing, a 3-year RI locks you into a decision that might not fit in 18 months.

## References

- **Homepage:** https://aws.amazon.com/ec2/pricing/reserved-instances/
- **Documentation:** https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-reserved-instances.html
- **Pricing:** https://aws.amazon.com/ec2/pricing/reserved-instances/pricing/

## Pricing Examples

**Scenario 1:** A production RDS PostgreSQL instance (db.r6g.large, Multi-AZ) running 24/7. 3-year All Upfront RI: ~$1,350/year vs On-Demand ~$2,400/year. Savings: ~$1,050/year (44%). Add the secondary AZ (same RI covers it via regional RI): no additional cost.

**Scenario 2:** A data processing cluster of 8 c6i.2xlarge instances running batch jobs 10 hours/day, 5 days/week. 1-year Partial Upfront RI: $3,800 upfront + $120/month vs On-Demand ~$650/month. Annual: $4,200 vs $7,800. Savings: ~$3,600/year.

## Nuggets & Gotchas

- **Zonal RIs can strand if the AZ fails:** You bought capacity in us-east-1a and us-east-1a has an outage. Your RI is stranded — you can't move it to another AZ. Use regional RIs if AZ resilience matters more than the discount differential.
- **RI size flexibility only works within the same AZ:** A zonal m6i.large RI covers any m6i size in the same AZ (large=1 unit, xlarge=2 units, etc.) but not across AZs. Regional RIs have no size flexibility.
- **Windows RIs have separate license billing:** RI pricing for Windows is the base compute rate. If you need SQL Server licensing through AWS, that's a separate charge on top of the RI price.
- **RI coverage doesn't mean RI utilization:** You can have 100% coverage (all instances covered by RI) but only 60% utilization (your RIs are 40% idle because you over-bought). Coverage is about financial coverage, not efficiency.
- **Selling on RI Marketplace requires 30 days minimum remaining:** If you migrate a workload 60 days into a 3-year RI, you can sell the remaining ~1,000 days on the RI Marketplace. But not if less than 30 days remain.
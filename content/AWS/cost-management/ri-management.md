---
title: Reserved Instance Management
description: Reserved Instance management — coverage reports, utilization reports, instance size flexibility, RI marketplace reselling, and commitment optimization
tags:
  - aws
  - cost-management
---

# Reserved Instance Management

Buying RIs is only half the battle — managing them after purchase is where most organizations leave money on the table. RI management means tracking coverage (are your instances covered by RIs), utilization (are you fully using what you bought), and making buy/sell decisions as your workload changes.

## Coverage Reports

Coverage measures what percentage of your instances are covered by RI or Savings Plan commitments.

```
Coverage = (Instance hours covered by RI/SP) / (Total instance hours) × 100
```

**Where to see it:** Cost Explorer → RI & Savings Plan Coverage → Coverage by instance family

**Coverage targets by environment:**

| Environment | Target Coverage | Rationale |
|------------|----------------|-----------|
| Production (stable) | 80-90% | Predictable baseline, always-on |
| Production (variable) | 60-80% | Unpredictable growth, leave room |
| Staging | 40-60% | Test environments that might change |
| Development | 0-20% | Unpredictable, use Savings Plans instead |

**Low coverage signals:**
- New instance families added that weren't covered
- Workload migration in progress
- RIs expiring and not being renewed

**Coverage vs utilization:** Coverage tells you if your running instances are covered. Utilization tells you if your purchased RIs are being used. You can have high coverage but low utilization (buying RIs for instances that run 30% of the time) or low coverage but high utilization (running instances consistently but not buying RIs).

## Utilization Reports

Utilization measures whether you're fully using the RIs you purchased.

```
Utilization = (Hours of RI capacity actually used) / (Hours of RI capacity purchased) × 100
```

**Where to see it:** Cost Explorer → RI & Savings Plan Coverage → Utilization tab

**What low utilization means:**
- You bought more RI capacity than you used
- The unused portion is still charged — you paid for it and it sat idle
- Common during migrations when you buy RIs for a workload you then migrate to a different instance family

**Example:**
```
You buy 100 m6i.large RIs.
Your actual usage averages 60 instances (40% of purchased).
Utilization = 60/100 × 100 = 60%

You paid for 100 RIs but only used 60.
40 RIs worth of capacity sat idle and still cost money.
```

## Instance Size Flexibility

For zonal Standard RIs, instance size flexibility automatically applies within the same instance family and AZ. This means:
- Buying an m6i.large RI covers any m6i instance size in that AZ
- Buying m6i.2xlarge RI covers 2 m6i.large equivalents

**How it works:**
```
You buy 10 x m6i.large RIs in us-east-1a.

Running: 5 x m6i.large + 3 x m6i.xlarge
- 5 x large = 5 RIs consumed
- 3 x xlarge = 6 RIs consumed (2 large per xlarge)
- Total RIs consumed: 11

Your 10 RIs cover 11 instance-hours, but you only bought 10.
1 instance-hour is uncovered (On-Demand rate).

Alternatively:
- 10 x large = 10 RIs consumed (fully covered)
- 5 x xlarge = 10 RIs consumed (fully covered from 10 RIs)
```

**Limitation:** Size flexibility doesn't work across AZs or across instance families. A m6i.large RI in us-east-1a doesn't apply to m6i.large in us-east-1b, and doesn't apply to c6i.large.

## RI Marketplace

If your workload changes mid-term and you no longer need certain RIs, you can sell them on the RI Marketplace.

**Requirements to sell:**
- At least 30 days remaining on the RI term
- No more than 3 years total remaining
- Account in good standing

**What you get:** The buyer pays for the remaining RI term. You recover some of the upfront cost.

**Limitations:**
- The marketplace isn't very liquid — finding a buyer for a specific instance type in a specific AZ can be hard
- You typically recover 30-70% of the remaining value depending on market demand
- Convertible RIs cannot be sold (but can be exchanged for different instance configurations)

**Exchange vs sell:** If you have Convertible RIs and no longer need them, consider exchanging them for different instance types you do need rather than letting them sit idle.

## RI Expiration Management

RI terms run for 1 or 3 years. As RIs approach expiration, you need a decision:

1. **Renew:** Buy new RIs to cover the same instance type and AZ
2. **Upgrade:** Buy RIs for a different (usually newer) instance type
3. **Let expire:** Switch to On-Demand or Savings Plans

**Expiration notification:** AWS sends email 30, 60, and 90 days before RI expiration. These are easy to miss.

**Automation:** Use AWS Budgets with RI expiration alerts to get proactive notifications. Set up a budget that fires at 90 days before expiration so you have time to plan.

## RI vs Savings Plan Decision Framework

**Use RIs when:**
- You need capacity reservation in a specific AZ
- You're buying for RDS, ElastiCache, or Redshift (SPs don't cover these)
- You want the highest possible discount for stable, predictable baseline
- You have a specific instance type and AZ that won't change for 1-3 years

**Use Savings Plans when:**
- You want flexibility to change instance families
- You use Lambda or Fargate
- You want regional (not AZ-specific) coverage
- You're buying for a workload that might evolve

**Common strategy:**
```
Baseline: RIs for RDS, ElastiCache, stable production EC2 baseline
Variable: Savings Plans for compute that might shift families
Burst: On-Demand + Spot for unpredictable traffic
```

## RI Reporting for Chargeback

In Organizations with multiple linked accounts, RI coverage and utilization reports help with chargeback:

- Show each business unit what their RI coverage is
- Chargeback the "waste" from underutilized RIs to the team that bought them
- Use coverage reports to decide whether teams need to buy more RI

**Per-account RI utilization:**
```sql
-- Athena query against CUR for RI utilization by account
SELECT 
  line_item_usage_account_id,
  product_instance_type,
  pricing_unit,
  SUM(line_item_usage_amount) as usage_hours,
  SUM(reserved_instance_hours) as ri_hours,
  ri_hours / NULLIF(usage_hours, 0) as utilization_pct
FROM cost_and_usage
WHERE product_product_family = 'EC2'
  AND reservation_reservation_a_r_n IS NOT NULL
GROUP BY 1, 2, 3
```

## Anti-Patterns

1. **Buying RI for dev/test.** Dev environments that run 8-5 Mon-Fri are better with Savings Plans + scheduled stoppage. RI coverage on 10 hours/week is poor utilization.

2. **Buying 3-year for migrating workloads.** If you're mid-migration to Graviton or changing instance families, a 3-year RI locks you in. Use 1-year or Savings Plans during transitions.

3. **Ignoring RI expiration.** 30-day expiration notice means you might miss the window to renew at the same pricing. Set your own 60-day alert.

4. **Buying RI for instances that get terminated regularly.** If your ASG terminates instances every 24 hours as part of its lifecycle, the instances are covered by RIs but the coverage is applied to a constantly changing pool — the RIs are being consumed by the churn rather than providing consistent savings.

## References

- **Homepage:** https://aws.amazon.com/ec2/pricing/reserved-instances/marketplace/
- **Documentation:** https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ri-market-general.html
- **Pricing:** https://aws.amazon.com/ec2/pricing/reserved-instances/marketplace/

## Pricing Examples

**Scenario 1:** You bought a 3-year All Upfront m6i.large RI in us-east-1 for $980 (amortized ~$0.093/hr effective rate vs $0.192/hr On-Demand). After 18 months you migrate to Graviton. You sell the remaining 18 months on the RI Marketplace at $650. Net cost: $980 - $650 = $330 for 18 months of coverage = $18/month effective cost vs $277/month On-Demand. Net savings: ~$259 for the period.

**Scenario 2:** You buy 10 RIs for 8 c6i.xlarge instances (2 per instance = 20 units). After 6 months, you downsize to c6i.large. Your 20 large RI units still cover the large instances — the flexibility works automatically within the family. No action needed.

## Nuggets & Gotchas

- **RI Marketplace minimum 30 days remaining:** You can only sell RIs on the marketplace if they have 30+ days left. If you're within 30 days of expiration, you can't sell — the RI just expires unused.
- **Convertible RIs sell at a deeper discount than Standard:** Because Convertible RIs allow exchanging for different instance types, buyers on the marketplace demand a bigger discount to compensate for the flexibility risk.
- **Regional RIs sell faster than zonal RIs:** Zonal RIs only sell to buyers in the same AZ — much smaller market. Regional RIs can be bought by anyone in the region.
- **Unused RI capacity doesn't roll over:** If you buy 10 RIs but only use 8, the 2 unused RIs just expire. You can't bank them for future months. Right-size your RI purchases to actual utilization.
- **Coverage % vs Utilization % are different metrics:** 100% coverage means 100% of your running instances have RI pricing applied. But if you're running 10 instances all idle at 5% CPU, your RI utilization is still 100% — you're paying for capacity you're not using.
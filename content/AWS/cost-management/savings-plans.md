---
title: Savings Plans
description: Accurate billing models, decision workflows and scoped examples for savings plans.
tags:
  - aws/cost-management
date: 2026-10-12
---

# Savings Plans

Price exercises in this note use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, unless explicitly identified as a dated published fee. They are assumptions, not current tariffs; exclusions remain material.

Savings Plans exchange a term commitment, measured in dollars per hour at Savings Plans rates, for discounts on eligible usage. They do not reserve capacity.

## Plan selection

The current family includes Compute, EC2 Instance, SageMaker AI and Database Savings Plans. Compute plans cover eligible EC2, Fargate and Lambda usage with broad flexibility. EC2 Instance plans constrain the instance family and Region. SageMaker AI and Database plans have their own eligible usage and term rules; Database Savings Plans use a one-year term. Check the official eligibility list before assuming a database product is covered.

## Hourly commitment accounting

Assume eligible usage would cost \$10/hour On-Demand, but costs \$7/hour at the selected plan's rates. A \$7/hour commitment covers that discounted usage, not merely 70% of an arbitrary monthly bill.

- At 730 hours, the commitment is \$7 × 730 = \$5,110.
- If eligible discounted usage is only \$4 in an hour, the remaining \$3 is unused and does not roll forward.
- Additional eligible usage is charged according to plan application and remaining coverage; uncovered usage pays its applicable price.
- Reserved Instance benefits apply before Savings Plans. The same usage does not receive both discounts; Spot is not covered by Savings Plans.

A previously quoted \$2,520/hour commitment would cost \$1,839,600 over 730 hours, not \$1,840. Always label hourly versus monthly amounts.

## Purchase workflow

1. Right-size and remove idle resources first.
2. Review hourly eligible spend and upcoming architectural changes, not just monthly totals.
3. Model low-demand and outage periods and existing reservations.
4. Buy conservatively, then monitor utilization and coverage separately.
5. Track expiration and reassess before renewal.

A daytime-only development fleet is a poor standalone commitment target because nights still incur the commitment. It can make sense only when other eligible organizational usage consumes those hours. Benefits can be shared from member-account purchases, subject to management-account sharing preferences.

## Flexibility comparison

| Plan         | What may change within eligible usage                        | What still constrains coverage                           |
| ------------ | ------------------------------------------------------------ | -------------------------------------------------------- |
| Compute      | EC2 family/size/Region/OS and eligible Fargate/Lambda mix    | Hourly dollars, eligible usage and rate schedule         |
| EC2 Instance | Size, AZ, OS and tenancy within purchased family/Region      | Family and Region                                        |
| SageMaker AI | Eligible instance families, sizes, Regions and components    | Product-specific eligibility; not all AI service charges |
| Database     | Eligible database service/generation/serverless combinations | One-year term and published eligibility                  |

An EC2 Instance plan is not purchased as “one m6i.large.” It buys hourly dollars for the selected family/Region. Switching to a larger instance is eligible but can exhaust commitment sooner. Compute plans are not a guarantee that every surrounding Lambda charge is discounted.

## Three-hour commitment ledger

Assume hypothetical us-east-1 eligible compute rates for a study exercise dated 2026-10-12. The same workload's Savings Plans rate is 70% of its On-Demand rate. Purchase \$7/hour:

| Hour     | On-Demand-equivalent usage | Discounted-rate usage | Commitment used | Additional On-Demand charge |
| -------- | -------------------------- | --------------------- | --------------- | --------------------------- |
| Quiet    | \$5                        | \$3.50                | \$3.50 of \$7   | \$0                         |
| Baseline | \$10                       | \$7                   | \$7 of \$7      | \$0                         |
| Peak     | \$20                       | \$14                  | \$7 of \$7      | \$10                        |

Total commitment is \$21; additional charge is \$10; total \$31 versus \$35 On-Demand. Utilization is (\$3.50 + \$7 + \$7) ÷ \$21 = 83.33%. The quiet hour's \$3.50 unused commitment cannot cover the peak. Real application uses each usage item's eligible rates and benefit ordering, not one universal multiplier.

## Buying and reporting lab

Export or inspect authorized hourly eligible usage. Remove existing RI-covered usage from the candidate baseline, classify expected migrations and model nights/weekends. Compare one- and three-year alternatives where offered; do not apply three years to Database plans. A fixed 70–80% purchase target is not universally appropriate.

Record coverage, utilization, owner and expiration separately. Compare actual cash charges with amortized reporting, and track whether benefit sharing was enabled. Use a recommendation as an input, not permission to purchase. The exercise stops at a written recommendation; no paid plan is bought.

## References

- [Plan types and eligible usage](https://docs.aws.amazon.com/savingsplans/latest/userguide/plan-types.html)
- [Savings Plans application](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-applying.html)
- [Organizations sharing preferences](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/ri-turn-off.html)

See [[AWS/cost-management/ri-management|Commitment management]].

## Across the wiki

- [[GCP/cost-management/pricing-models/README|GCP Cost Optimization, Committed Use Discounts (CUDs), and FinOps]] — cost management (GCP)
- [[Kubernetes/guides/non-functional/cost-optimization|Cost Optimization]] — cost management (Kubernetes)

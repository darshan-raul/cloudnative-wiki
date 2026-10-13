---
title: Cost Explorer
description: Accurate billing models, decision workflows and scoped examples for cost explorer.
tags:
  - aws/cost-management
date: 2026-10-12
---

# Cost Explorer

Price exercises in this note use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, unless explicitly identified as a dated published fee. They are assumptions, not current tariffs; exclusions remain material.

Cost Explorer is an interactive billing analysis tool, not a real-time resource monitor. Enable it and allow initial processing; source billing data and refresh timing can delay visible costs.

## Analysis workflow

Choose a cost metric deliberately: unblended reflects line-item charges, while amortized views spread upfront commitment fees over their term. Net views incorporate applicable discounts. Group by service, linked account, Region, usage type, activated tag or Cost Category; investigate credits, refunds and upfront fees separately.

Standard chart history includes the current month plus 13 prior months. Optional extended monthly history reaches up to 38 months. Forecasts can extend up to 12 months and express uncertainty; they are not guaranteed future bills. Optional hourly/resource-level data has separate retention, eligibility and charges.

The console interface is available without an ordinary per-query console fee. API requests and optional granular data features have their own pricing. Hourly data is limited to a recent window rather than years of hourly history.

## Useful investigations

- Compare month-to-date with the same elapsed period last month.
- Group a spike by service, account and usage type before guessing its cause.
- Compare commitment utilization and coverage separately.
- Check amortized cost when an upfront purchase distorts cash-basis trends.
- Correlate resource activity with billing, recognizing that CloudWatch operational metrics do not automatically become Cost Explorer cost records.

## Read-only CLI example

Requires AWS CLI credentials authorized for `ce:GetCostAndUsage`. Replace the dates; the end date is exclusive. This queries recorded costs and makes no resource changes. Cost Explorer API charges may apply.

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-09-01,End=2026-10-01 \
  --granularity MONTHLY \
  --metrics AmortizedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

Do not interpret an empty/estimated result as zero final liability. Pagination and access scope matter in automated reports.

## Core views and metric selection

| View                        | Question                            | Follow-up                                 |
| --------------------------- | ----------------------------------- | ----------------------------------------- |
| Daily service trend         | Which product changed?              | Separate usage quantity, rate and credits |
| Linked account              | Which team/account owns it?         | Confirm shared benefits and allocation    |
| Usage type                  | Which billed unit grew?             | Do not add incompatible units together    |
| Activated tag/Cost Category | Which business dimension?           | Report missing/unallocated values         |
| Amortized commitments       | What is the period's economic cost? | Reconcile upfront cash charges separately |
| Coverage/utilization        | Are benefits sufficient and used?   | Inspect eligible matching usage by hour   |

Unblended and amortized totals can differ dramatically in a purchase month without any resource growth. Net views additionally reflect applicable discounts; use the same metric in dashboards, thresholds and comparisons.

## Two investigations

**Month-end spike:** a \$12,000 upfront purchase appears beside \$4,000 recurring usage. The cash-oriented total is \$16,000 before other adjustments; an illustrative one-year amortization attributes \$1,000/month plus recurring usage. Do not call the whole \$12,000 a runaway workload or treat amortization as a refund.

**Changed network usage:** an account's compute is flat while NAT processing rises. Group by service/usage type, then investigate traffic paths and operational evidence. Cost Explorer alone cannot prove a particular request or deployment caused the charge.

These are hypothetical us-east-1 accounting examples dated 2026-10-12, not product prices or a guarantee of the service's exact amortization schedule.

## Forecast and export workflow

Compare equal elapsed periods and include seasonality, new deployments and scheduled shutdowns. Forecast confidence bounds quantify uncertainty; they do not ensure a future bill stays below a budget. Recommendations reflect configured historical assumptions and cannot know every planned migration.

For recurring detailed/resource queries, evaluate Data Exports/CUR rather than repeatedly paying API query charges. Extended monthly history is not years of retained hourly granularity. Record all opt-in data features and retention settings in the reporting design.

### Reporting lab

Run the existing read-only CLI query with an approved account and historical dates. Check response pagination, `Estimated` flags and currency/unit fields. Re-run by linked account and explain discrepancies with service totals using the same metric. API access must be authorized separately from browser-console visibility.

## References

- [Charts, history and forecasts](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-chart.html)
- [Hourly data](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-hourly-granularity.html)
- [Cost Explorer pricing](https://aws.amazon.com/aws-cost-management/aws-cost-explorer/pricing/)
- [CLI request contract](https://docs.aws.amazon.com/cli/latest/reference/ce/get-cost-and-usage.html)

## Across the wiki

- [[GCP/cost-management/pricing-models/README|GCP Cost Optimization, Committed Use Discounts (CUDs), and FinOps]] — cost management (GCP)
- [[Kubernetes/guides/non-functional/cost-optimization|Cost Optimization]] — cost management (Kubernetes)

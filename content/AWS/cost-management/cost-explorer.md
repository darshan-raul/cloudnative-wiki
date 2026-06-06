---
title: Cost Explorer
description: AWS Cost Explorer — spend visualization, RI/SP coverage reports, forecasting, tag-based cost allocation, and known limitations
tags:
  - aws
  - cost-management
---

# Cost Explorer

Cost Explorer is AWS's built-in cost analysis tool. It visualizes your spending over time, breaks it down by service/account/tag, shows Reserved Instance and Savings Plan coverage, and provides 3-month cost forecasts.

Access it via: AWS Console → Cost Management → Cost Explorer

## Core Views

### Spending Over Time

The default view shows daily or monthly spend as a bar chart. You can:
- Filter by date range (last 7 days, 30 days, 3 months, custom)
- Group by: Service, Linked Account, Region, Tag, Availability Zone
- Compare periods (this month vs last month, MoM growth)

The chart is interactive — click a bar to drill into what drove that spend spike.

### Cost by Service

Sorts all AWS services by spend. At scale you'll typically see:
1. EC2 (compute + NAT Gateway + EBS)
2. S3 (storage + requests + data transfer)
3. RDS / Aurora (compute + storage + backup snapshot storage)
4. CloudWatch (ingestion + storage + data transfer)
5. Data transfer (often split across multiple services)

### Linked Account View

For AWS Organizations with consolidated billing, shows spend per account. Useful for chargeback — each business unit or team gets an account, and you can see exactly what each is spending.

### Tag-Based Allocation

If you've set up cost allocation tags (user-defined or AWS-generated), you can group spend by tag. For example, `Environment=prod` shows what prod costs across all accounts and services. `Application=payments` shows total payments infrastructure spend regardless of which account it's in.

**AWS-generated tags** are automatically applied: `aws:createdBy`, `aws:_REQUEST_ID`, `aws:cloudformation:stack-name`, etc.

## RI and Savings Plan Reports

Cost Explorer has dedicated views for commitment coverage:

### Coverage

Shows what percentage of your EC2, Lambda, Fargate, RDS, ElastiCache, and Redshift spend is covered by RIs and Savings Plans.

```
Coverage = (Spend covered by RI + SP) / Total eligible spend × 100
```

**Breakdown by service:**
- EC2 Coverage: How much EC2 spend is covered
- RDS Coverage: How much RDS spend is covered
- Lambda Coverage: How much Lambda spend is covered (SP only, no RI for Lambda)

**Breakdown by instance family:** Shows which instance families have high/low coverage. If m6i is at 95% but c6i is at 20%, you might buy more c6i coverage or shift workloads.

### Utilization

Shows whether you're fully using the RIs you bought:

```
RI Utilization = (Hours used by RI) / (Hours purchased) × 100
```

Low utilization (below 70%) suggests you bought too much. But don't just buy based on utilization — if you're running 100 RIs at 50% utilization, it might mean half your instances are idle (a sizing problem), not that you should buy fewer RIs.

### Recommendations

Cost Explorer generates purchase recommendations:
- "Buy 50 more m6i.large RIs to improve coverage from 67% to 85%"
- "Switch from No Upfront to All Upfront for better savings"

Take these with a grain of salt — the recommendation algorithm is conservative. Your actual needs may differ.

## Forecasting

Cost Explorer provides a 3-month forward forecast based on your historical spend pattern. It's a simple linear projection with seasonality detection.

**Limitations:**
- Doesn't account for known upcoming changes (new product launches, expected traffic spikes)
- Doesn't model Savings Plan commitments into the forecast
- Can be wildly off during growth phases or before migrations
- Doesn't include Cost Explorer itself (which is free tier based)

The forecast is useful for budgeting, not for commitment buying decisions.

## CUR Integration

For advanced analysis, Cost Explorer reads from the Cost and Usage Report (CUR). If you've set up CUR with Athena integration, you can write SQL queries against your billing data that go far beyond what Cost Explorer shows in the UI.

Common queries:
- Exact AZ-to-AZ data transfer by account
- Per-ENI network traffic breakdown
- Cross-account RI utilization comparison
- Tag-level cost allocation with tax adjustment

## Limitations

1. **12-month maximum lookback** in the UI. For longer-term trend analysis you need CUR + Athena.

2. **Blended billing view** for Organizations. Shows blended rates across accounts, not individual account list prices. Makes it harder to see which account is driving costs.

3. **Forecast accuracy degrades** for fast-growing or highly seasonal workloads.

4. **No real-time data.** Cost Explorer data is typically 24-48 hours old.

5. **SP/RI recommendations are conservative.** AWS doesn't want you to over-buy, so recommendations are often below optimal coverage levels.

6. **Amortized vs cash** — by default, RI costs show as amortated (spread across the term), not as upfront cash cost. Useful for accounting, confusing for operational cost monitoring.

## References

- **Homepage:** https://aws.amazon.com/cost-management/aws-cost-explorer/
- **Documentation:** https://docs.aws.amazon.com/cost-management/latest/userguide/what-is-cost-explorer.html
- **Pricing:** https://aws.amazon.com/cost-management/aws-cost-explorer/pricing/

## Pricing Examples

**Scenario 1:** A company with 15 AWS accounts (multi-account landing zone). Using Cost Explorer with tag-based filtering (`Application`, `Environment`, `Owner`), they identify that the `payments-service` tag group spends $28K/month but only $8K of that is production — $20K is development environments running 24/7. Setting tag-based budgets cuts the dev spend by 40% via scheduled stoppage.

**Scenario 2:** An engineering team uses Cost Explorer RI Coverage report to find they have 65% RI/SP coverage on EC2. Cost Explorer recommends buying more SP to reach 80%. After buying a 1-year Compute SP covering an additional $30/hour, monthly savings on previously On-Demand spend: ~$600/month.

## Nuggets & Gotchas

- **Cost Explorer has 3-5 minute query latency:** Large accounts with thousands of resources can see slow dashboard load times. Filter to specific accounts or time ranges to improve performance.
- **Forecast is based on historical patterns:** If your spend is seasonal or growing rapidly, the forecast will be wrong. It models yesterday's pattern and extends it forward — it doesn't know about planned launches or deprecations.
- **Blended costs in Organizations show averaged rates:** In an Organization, linked account costs are blended across the org — which can mask that one account is paying On-Demand rates while another is getting RIs.
- **RI recommendations are generated by AWS algorithms and are conservative:** They err on the side of not over-recommending. For stable production baselines, you can often safely buy more coverage than recommended.
- **Cost Allocation Tags take 24 hours to activate:** After you activate a new tag in the Billing console, it takes a full day before it appears in Cost Explorer data. Plan tag activation ahead of budget reviews.
---
title: Cost Anomaly Detection
description: AWS Cost Anomaly Detection — ML-based spend monitoring, alert subscriptions, root cause investigation, and integration with ChatOps
tags:
  - aws
  - cost-management
---

# Cost Anomaly Detection

Cost Anomaly Detection uses machine learning to detect unusual spend patterns in your AWS account. Unlike budgets (which alert you when you hit a threshold you've set), anomaly detection alerts you when something unexpected happens — a cost spike that wasn't planned for.

It's a free service available in Cost Explorer for Business and Enterprise support customers.

## How It Works

AWS trains ML models on your historical spend patterns across:
- Service-level spend (EC2, S3, RDS, etc.)
- Linked account spend
- Region-level spend
- Time-of-day and day-of-week patterns

The model learns what "normal" looks like for your account. When spend deviates significantly from the predicted pattern, it generates an anomaly alert.

**Key concept:** The model understands seasonality, growth trends, and known recurring events (monthly billing cycles, product launches). A spike that follows a normal pattern doesn't generate an alert. A spike that's unexpected for your account's pattern does.

## Anomaly Alerts

When an anomaly is detected, you receive:
- **Anomaly alert:** Which service/account/region has unusual spend
- **Root cause estimate:** AWS's ML estimate of what drove the spike
- **Cost impact:** How much the anomaly added above normal

**Alert example:**
```
Anomaly Detected: Amazon EC2
Estimated monthly impact: $2,400 above normal
Detected at: 2024-06-15 14:00 UTC
Root cause estimate: New EC2 instances launched in us-east-1
Account(s) affected: 123456789012 (production)
```

## Alert Subscriptions

Subscribe to anomaly alerts via:
- **Email:** Simple alert to a specific address
- **SNS:** Integrates with Slack, Teams, PagerDuty

**Slack integration (via SNS → Lambda):**
```python
# Lambda triggered by SNS anomaly alert
# Formats the alert into a Slack message with:
# - Service and estimated impact
# - Account(s) affected
# - Root cause estimate
# - Link to Cost Explorer for investigation
```

**ChatOps setup:**
```
Cost Anomaly Detection → SNS Topic → Lambda → Slack #cost-alerts channel
```

## Investigation Workflow

When an anomaly alert fires:

1. **Check the alert details** — which service, which account, estimated impact
2. **Check recent changes** — new deployments, new accounts, infrastructure changes
3. **Look at Cost Explorer** — drill into the specific service and account
4. **Check CloudTrail** — API calls that might indicate new resource creation
5. **Identify the root cause** — was it planned (product launch) or unplanned (misconfigured automation)?

**Common causes:**
- New environment spun up and left running
- Auto Scaling scaling up unexpectedly
- Lambda function hitting a cold start storm
- EBS volume snapshot accumulation
- Data transfer spike from cross-region replication
- Reserved Instance not covering new workload

## Anomaly Detection vs Budgets

| | Cost Anomaly Detection | Cost Budgets |
|--|----------------------|-------------|
| Trigger | Unexpected spend spike | Planned threshold |
| Latency | Near real-time | 24-48 hours |
| What it detects | Unexpected changes | Over-budget situations |
| Action | Alert only | Alert + optional automation |

**Use both:** Anomaly detection catches surprises. Budgets catch gradual over-consumption that might not trigger an anomaly.

## Coverage and Responsiveness

Anomaly detection monitors:
- All services across all linked accounts
- Spend by account, region, and service
- Anomalies down to the linked account level

**What it doesn't detect:**
- Gradual cost growth (e.g., storage growing 5% per month as data accumulates)
- Small anomalies below the sensitivity threshold
- Anomalies in very new accounts (not enough history for ML model)

**Sensitivity settings:** You can adjust sensitivity (low/medium/high) to control how quickly alerts fire. Higher sensitivity means more alerts but also more false positives.

## Cost Impact Estimation

The ML model estimates the monthly cost impact of the anomaly at the time of detection. This is an estimate — the actual impact might be higher or lower depending on whether the anomaly continues.

**Why it matters:** A $500 anomaly alert might actually be a $5,000/month problem if you don't catch it. Set up response procedures so that anomaly alerts get investigated same-day.

## References

- **Homepage:** https://aws.amazon.com/cost-management/aws-cost-anomaly-detection/
- **Documentation:** https://docs.aws.amazon.com/cost-management/latest/userguide/getting-started_cost_anomaly_detection.html
- **Pricing:** https://aws.amazon.com/cost-management/aws-cost-anomaly-detection/pricing/

## Pricing Examples

**Scenario 1:** A devops team sets up Cost Anomaly Detection with a weekly alert to their #cost-alerts Slack channel. In week 2, an alert fires for a $3,200 unexpected charge on an S3 bucket. Investigation reveals a new Lambda function was writing 50GB/day of debug logs to S3. Fixing the Lambda logging reduces the bill by $3,200/month.

**Scenario 2:** A company with multi-account setup enables Cost Anomaly Detection at the payer level with alert subscriptions to finance@company.com. The system detects a $12K anomaly in account-123 that is $4K above expected spend. The root cause: an engineer ran a Glue job that scanned a 50TB DynamoDB table. They implement S3 prefix isolation and query-level cost controls, preventing a $48K monthly recurrence.

## Nuggets & Gotchas

- **Cost Anomaly Detection uses ML and needs history:** The model requires 14 days of baseline data before it can detect anomalies. New accounts or accounts with rapidly changing spend patterns may see delayed or inaccurate anomaly detection.
- **Alert subscriptions are per-detection threshold, not per-dollar-amount:** You set a sensitivity level (1-10) and a threshold dollar amount. Alerts fire when both conditions are met — not just when spend exceeds the dollar amount.
- **Anomaly detection is free for the first 30 days:** After that, AWS charges per anomaly detection per account per month. At large scale (hundreds of linked accounts), this adds up — evaluate whether the value justifies the cost.
- **The cost impact estimate is forward-looking but bounded:** The model estimates the monthly cost if the anomaly continues at the current rate. If the anomaly stops after 3 days (e.g., a one-time large data transfer), the actual impact is much lower than the estimate.
- **Cost Anomaly Detection doesn't block actions:** It only alerts. You need CloudWatch + Lambda automation or manual investigation to remediate. An alert without a response procedure is just noise.
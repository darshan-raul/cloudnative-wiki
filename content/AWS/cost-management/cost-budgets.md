---
title: Cost Budgets
description: AWS Cost Budgets — creating cost and usage budgets, alert thresholds, SNS and ChatOps notifications, budget actions, and RI/SP coverage budgets
tags:
  - aws
  - cost-management
---

# Cost Budgets

Cost Budgets let you set custom cost thresholds and get alerted when spend approaches or exceeds them. They're the operational control layer for cost management — you know what's happening before it becomes a surprise on the invoice.

## Budget Types

### Cost Budget

The most common type. Set a target spend amount (e.g., $10,000/month) and get alerted when actual spend reaches a percentage of that target.

**Configuration options:**
- **Fixed:** $X per month
- **Variable:** Dynamic based on a metric (e.g., last month's spend × 1.1)
- **Auto-adjusting:** AWS adjusts the budget based on your forecast

**Alert thresholds:**
```
[100%] — You've hit the budget
[80%] — Warning before you hit it
[50%] — Early warning
```

You can set multiple thresholds with different notification recipients.

### Usage Budget

Track a specific usage dimension — for example, "I want to be alerted when my EC2 running hours exceed 10,000 in a month." Useful for tracking usage-based services where cost is proportional to a specific metric.

### RI/SP Coverage Budget

Track Reserved Instance and Savings Plan coverage. Set a target coverage percentage (e.g., 80%) and get alerted when coverage drops below that threshold.

**Example:** "Alert me when my EC2 RI coverage drops below 70%." This happens when you launch new instances that aren't covered by RI/SP, causing the coverage percentage to fall.

### RI/SP Utilization Budget

Track whether you're fully utilizing the RIs/SPs you bought. "Alert me when my RI utilization drops below 60%." Useful for identifying over-purchased capacity.

## Notification Destinations

Budget alerts can go to:
- **Email:** Simple, no integration required
- **SNS:** Integrates with Slack, Teams, PagerDuty, or any webhook
- **ChatOps:** SNS → Lambda → Slack webhook is the common pattern
- **AWS Chatbot:** Direct Slack/Teams integration with minimal setup

**ChatOps integration example (Slack):**
```
Budget Alert → SNS Topic → Lambda → Slack webhook → #cost-alerts channel
```

The Lambda function formats the alert into a Slack message with:
- Budget name
- Actual spend vs budgeted
- % of budget consumed
- Trend (spending faster or slower than expected)
- Link to Cost Explorer for drill-down

## Budget Actions

Budgets can trigger automated responses when thresholds are exceeded:
- **IAM Policy:** Restrict certain actions (e.g., deny new EC2 instance creation above a certain size)
- **SCP:** Applied at the Organization level
- **Lambda:** Trigger a custom remediation function

**Example:** A budget action that triggers when spend exceeds 90% of budget:
```json
{
  "actionThresholdValue": 90,
  "actionThresholdType": "PERCENTAGE",
  "notificationModel": {
    "immediatelyNotifyConsumers": true
  },
  "actionType": "lambda",
  "lambdaFunctionArn": "arn:aws:lambda:us-east-1:123456789:function:cost-alert-remediation",
  "region": "us-east-1"
}
```

The Lambda function might:
- Stop non-production EC2 instances
- Delete unattached EBS volumes
- Send a more detailed Slack alert to the finance team
- Disable an auto-scaling policy to prevent further cost growth

## Multi-Account Budgets

In AWS Organizations, you can create budgets at:
- **Payer account level:** Total organization spend
- **Linked account level:** Individual account spend
- **Tag-based:** Spend filtered by tag (e.g., `Environment=prod`)

**Tag-based budgets** are powerful for chargeback:
- Set a budget for `Team=platform` and alert when that tag's spend exceeds threshold
- The actual spend includes all resources tagged `Team=platform` across all accounts

## Budget vs Cost Anomaly Detection

| | Budgets | Cost Anomaly Detection |
|--|---------|----------------------|
| Trigger | Budget threshold | ML-detected unusual spend |
| Latency | Daily updates (24h delay) | Near real-time |
| Use case | Planned spend tracking | Unexpected spikes |
| Response | Alert + optional automation | Alert only |

Use both together: Budgets for planned spend visibility, Anomaly Detection for unexpected surprises.

## Common Budget Configuration Mistakes

1. **Setting only one threshold at 100%.** By the time you hit 100%, you've already overspent. Set alerts at 50%, 75%, 90%.

2. **Alerting to only one person.** Finance, engineering leads, and the AWS account owner should all get alerts.

3. **Not setting a monthly cadence.** If a budget fires at $X and you ignore it, you keep spending. Make sure someone owns the response.

4. **Budgets on linked accounts that aren't checked.** In Organizations, linked account owners often ignore payer-level budgets. Set linked account budgets with their own thresholds.

5. **Variable budgets without tracking why.** If a budget auto-adjusts to $20K one month because of a product launch, understand why — it might mean you need a different budget structure for growth scenarios.

## References

- **Homepage:** https://aws.amazon.com/cost-management/aws-cost-budgets/
- **Documentation:** https://docs.aws.amazon.com/cost-management/latest/userguide/budgets.html
- **Pricing:** https://aws.amazon.com/cost-management/aws-cost-budgets/pricing/

## Pricing Examples

**Scenario 1:** A startup sets a $2,000/month cost budget on their entire account with an 80% alert threshold. When spend hits $1,600 in the first week of the month, they get an alert and discover a developer left 20 large EC2 instances running from a test. Budget action stops the instances: saved ~$2,800 for the month.

**Scenario 2:** A fintech company with multi-account setup creates a $50K/month budget for their production OU and a separate $10K/month budget for their dev OU. Production budget has 90% threshold alerting to finance@company.com. Dev budget has 50% threshold alerting to engineering leads. Dev budget fires first — engineers discover 47 idle test instances. Saved $3,200 that month.

## Nuggets & Gotchas

- **Budget actions are best-effort:** Budget actions (e.g., stop EC2, delete EBS snapshots) are triggered by CloudWatch Events but can fail if the Lambda lacks IAM permissions or the target doesn't match the action filter. Test your budget actions.
- **RI/SP coverage budgets measure financial coverage, not capacity:** A budget that says 70% coverage means 70% of your spend has RI/SP pricing — not that 70% of your instances are covered. You could have 100% coverage with 40% utilization.
- **Budgets in Organizations apply to the entire org by default:** Set explicit linked account filters or OU filters so you know which account triggered the alert. A $100K org-wide budget can be exceeded by a single linked account going rogue.
- **Monthly budgets refresh at UTC month boundaries:** If you're in a different timezone, the budget reset might not align with your fiscal month. Use daily or weekly budgets if your cost reporting is timezone-sensitive.
- **Zero-amount budgets fire on any spend:** Setting a $0 budget for a service you want to monitor for unexpected spend will fire immediately. Use a small threshold ($10) instead.
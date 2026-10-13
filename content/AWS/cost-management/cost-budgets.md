---
title: Cost Budgets
description: Accurate billing models, decision workflows and scoped examples for cost budgets.
tags:
  - aws/cost-management
date: 2026-10-12
---

# Cost Budgets

Price exercises in this note use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, unless explicitly identified as a dated published fee. They are assumptions, not current tariffs; exclusions remain material.

AWS Budgets tracks cost, usage and commitment objectives and sends threshold notifications. Billing latency means it is **not a real-time hard spending limit**.

## Budget design

Choose the metric, period, filters and treatment of credits, refunds, taxes and commitments before choosing a number. Use separate budgets for organization-wide spend, owner/team spend and important service usage. A forecast threshold warns about an estimated outcome; an actual threshold observes recorded charges.

For example, a \$1,000 monthly team budget can notify at 80% actual and 100% forecast. These values are policy choices, not proof that remaining resources can safely be stopped. A new or changing workload may not have enough history for a useful forecast.

RI/Savings Plans coverage and utilization budgets answer different questions from dollar budgets. Track expiration from purchase inventory, not from an invented budget expiry trigger.

## Actions and limitations

Budget actions can apply supported IAM/SCP controls or target supported EC2/RDS resources, with an execution role and optional approval. They do not universally stop every AWS service. Stopping compute can leave storage, networking, commitments and other charges running. A denied provisioning permission does not shut down existing usage.

Budget monitoring and notifications have no Budgets charge. Under the pricing published when this note was reviewed, the first two action-enabled budgets per month are free; additional action-enabled budgets cost \$0.10 per day each. Delivered Budgets Reports cost \$0.01 each. Notification dependencies can add their own charges. Recheck the pricing source before estimating a deployment.

## Safe setup drill

1. Record account scope, metric, monthly limit and owner.
2. Configure email/SNS recipients and verify notification delivery.
3. Begin with alert-only behavior.
4. In a sandbox, inspect supported action types and required permissions.
5. Add approval, exclusions, a rollback procedure and an audit record before enabling actions.
6. Review the budget after architecture or commitment changes.

Use an authorized test account and small thresholds; this is a proposed exercise, not an executed deployment. Never automatically delete backups or production data in response to a budget alert.

## Budget type comparison

| Type                         | What it measures                              | Example objective                             |
| ---------------------------- | --------------------------------------------- | --------------------------------------------- |
| Cost                         | Recorded/forecast cost under selected filters | Warn before a team exceeds its monthly target |
| Usage                        | A specific billable usage quantity            | Monitor a selected service's GB or hours      |
| RI/Savings Plans utilization | Consumed purchased benefit                    | Detect idle financial commitments             |
| RI/Savings Plans coverage    | Eligible usage receiving benefit              | Detect uncovered baseline or expiry effects   |

Do not combine GB, requests and hours into one meaningful usage sum. Set scope and units explicitly. A low-coverage alert is not automatically permission to buy; low utilization can indicate an existing overpurchase.

## Notification and action design

Email is simple but ownership can lapse. SNS supports integrations with explicit topic policy, encryption and subscriber configuration. Test actual delivery and maintain contacts. Central budgets should summarize organizational risk; member/owner budgets should be actionable, not dozens of duplicate escalations.

For a hypothetical us-east-1 team budget reviewed on 2026-10-12, a \$1,000 target with an 80% actual threshold alerts near \$800 of recorded cost. A 100% forecast threshold warns that projected period-end cost exceeds \$1,000. Neither says the next \$200 of spend can be prevented, because billing arrives after usage and dependencies continue charging.

## Practical configuration worksheet

Before creating a budget, complete account ID, period, metric, amount/currency, filters, cost treatment, thresholds, recipients, owner and escalation. Check whether upfront reservations, taxes, support, refunds and credits belong in the selected objective. Forecast availability and accuracy depend on history.

For an action, add target resources, execution role, approval mode, protection exclusions, rollback and residual charges. Start with approval-required responses. Applying an SCP to prevent new resources cannot stop an already running database or cancel a Savings Plan.

## Common mistakes to test

- Comparing a net-cost budget with a gross invoice dashboard.
- Excluding shared platform charges and claiming team totals reconcile.
- Selecting a usage dimension with mixed units.
- Assuming stopped EC2/RDS eliminates storage and backup costs.
- Setting recipients without delivery verification.
- Using a forecast crossing as evidence of unauthorized activity.

A monthly review should reconcile alerts to actual decisions and update owners, scope and thresholds after architecture changes. Keep RI/Savings Plans expiry tracking in a dated purchase inventory rather than inventing an expiry budget type.

## References

- [Budgets overview](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- [Budget actions and execution roles](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-action-configure.html)
- [Budgets pricing](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/)

See [[AWS/cost-management/cost-anomaly-detection|Anomaly Detection]] for unexpected changes rather than fixed limits.

---
title: Cost Anomaly Detection
description: Accurate billing models, decision workflows and scoped examples for cost anomaly detection.
tags:
  - aws/cost-management
date: 2026-10-12
---

# Cost Anomaly Detection

Price exercises use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, not current tariffs, unless explicitly identified as a dated published fee.

AWS Cost Anomaly Detection learns spending patterns and identifies unexpected changes. It is available to eligible Cost Explorer users without an additional feature charge; it is not restricted to Business or Enterprise Support. Notification and investigation services may have their own charges.

## Timing and alert semantics

The service evaluates billing data approximately three times per day. Underlying data can lag up to 24 hours, so it cannot guarantee an immediate response to a runaway resource. A newly subscribed service needs at least 10 days of history for detection.

An anomaly's cost impact is the difference between actual and expected spend over the anomaly duration, not a projected full month's charge. Alert subscriptions use documented absolute and/or percentage impact thresholds. There is no generic sensitivity slider or invented 1–10 severity configuration.

## Monitor strategy

Create monitors around meaningful spending dimensions such as service, linked account, tags or Cost Categories, subject to supported monitor types and limits. Avoid overlapping monitors that repeatedly alert the same responders. Thresholds should reflect financial significance and investigation capacity.

For a small team, a \$50 impact might warrant attention; for a large central platform, combine amount and percentage to avoid alert fatigue. Those are illustrative policy values, not AWS defaults.

## Investigation runbook

1. Read the anomaly's affected account, service, usage type, time range and actual/expected costs.
2. Compare Cost Explorer or export records and recent deployments.
3. Identify an owner; verify whether the change was planned.
4. Inspect resource activity using appropriate operational logs.
5. Obtain approval before stopping capacity or modifying retention.
6. Document the cause and adjust ownership/routing or thresholds if needed.

Do not assume a generic EventBridge JSON shape is the CAD notification contract. Validate the actual subscription/SNS payload, delivery permissions and retry behavior before building automation. CAD and Budgets are complementary; neither is a guaranteed hard cap.

## Detection versus fixed objectives

| Requirement                             | Anomaly Detection                          | Budgets                                          |
| --------------------------------------- | ------------------------------------------ | ------------------------------------------------ |
| Unexpected change from learned behavior | Primary purpose                            | May alert only if a configured target is crossed |
| Fixed monthly cost/usage objective      | Not a replacement for a target             | Primary purpose                                  |
| Planned seasonal growth                 | Can affect learned expectations            | Still compared with selected threshold           |
| Guaranteed instant cutoff               | Not provided                               | Not provided                                     |
| Response                                | Investigate an anomaly and route ownership | Notify or apply supported approved actions       |

A root-cause contribution is a lead, not proof that a specific engineer or deployment caused spending. Correlate billing dimensions with change records and resource telemetry. Sudden growth can be legitimate; a forecast can be wrong; neither justifies deleting data.

## Impact worksheet

For hypothetical us-east-1 billing observations reviewed on 2026-10-12:

```text
expected cost over anomaly duration = $8,000
actual cost over anomaly duration   = $12,000
impact                             = $4,000
percentage impact                  = $4,000 / $8,000 × 100 = 50%
```

This is an observed-period comparison, not \$12,000 of impact and not a \$48,000 monthly projection. The alert subscription's amount/percentage conditions determine notification routing; no undocumented sensitivity score is needed.

## Notification integration lab

Create a design for CAD subscription → SNS → authorized notification consumer → incident channel. Specify the SNS topic policy, subscriber permissions, optional KMS access, message format validation and duplicate-delivery handling. Capture a sanitized real/test payload before implementing its parser; fields must follow that documented notification contract.

A message should contain monitor/anomaly identifiers, time range, affected billing dimensions, actual/expected impact, owner and investigation link. Avoid secrets or broad account metadata in public channels. Use least privilege and treat Slack/Teams integrations as separate authorization.

For an unexpected storage increase, verify stored bytes, versions and retention; do not infer a \$3,200 saving merely from observing 50 GB/day of logs. For a compute spike, distinguish scaling, discounted coverage changes and price/licensing changes. Close the incident only after source usage and subsequent billing support the resolution.

## References

- [Detection behavior and limitations](https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html)
- [Monitor and subscription setup](https://docs.aws.amazon.com/cost-management/latest/userguide/getting-started-ad.html)
- [Availability and pricing FAQ](https://aws.amazon.com/aws-cost-management/aws-cost-anomaly-detection/faqs/)

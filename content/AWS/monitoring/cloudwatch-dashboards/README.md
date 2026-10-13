---
title: CloudWatch Dashboards
description: CloudWatch Dashboards — custom metric visualization with widgets, live data, cross-service views, and cross-account sharing.
tags:
  - aws/monitoring
date: 2026-10-12
---

# CloudWatch Dashboards

Prerequisites: [[AWS/security/iam/README|scoped IAM access]] and [[AWS/monitoring/README|telemetry, SLI and retention design]].

CloudWatch dashboards are views of operational evidence, not alerting or access-control boundaries. Design them around user outcomes and diagnostic questions rather than every available graph.

## Design

Use [[AWS/monitoring/cloudwatch-metrics/README|metric]] widgets for traffic/errors/latency/saturation, [[AWS/monitoring/cloudwatch-insights/README|log queries]] for investigation, and text widgets for owners/runbooks. State the time range, Region, account and unit so screenshots do not obscure scope. Dashboard variables can parameterize supported properties and patterns.

A dashboard does not grant cross-account metric access. Prefer documented CloudWatch cross-account observability (OAM) links/sinks or the separate legacy cross-account dashboard role workflow. Do not invent cloudwatch:CrossAccountLink permissions. Read authorization and account/Region settings still apply.

## Minimal reproducible dashboard

Create a local file dashboard.json with this valid body:

```json
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "region": "us-east-1",
        "title": "Sandbox latency",
        "metrics": [["WikiLab", "Latency", "Service", "demo"]],
        "stat": "Average",
        "period": 60
      }
    }
  ]
}
```

Use the Region of [[AWS/monitoring/cloudwatch-metrics/README|your metric fixture]], then with dashboard write/read permissions:

```bash
aws cloudwatch put-dashboard --dashboard-name wiki-lab --dashboard-body file://dashboard.json
aws cloudwatch get-dashboard --dashboard-name wiki-lab
```

Inspect DashboardValidationMessages; successful HTTP/API transport is not proof every widget is valid. Open the dashboard and verify the fixture value. Test the wrong Region deliberately: an empty graph is expected, not a missing global metric.

## Cost and cleanup

Dashboards are not universally free. The published allowance is limited to three custom dashboards of up to fifty metrics each; additional dashboards incur charges under the current pricing model. Metrics, queries and other features can add charges independently.

Remove your disposable view with `aws cloudwatch delete-dashboards --dashboard-names wiki-lab`. This deletes the dashboard configuration, not the underlying metrics/logs. Restrict production dashboard changes through version-controlled definitions and review.

## Widget catalogue and operational layout

| Widget             | Intended use                         | Review requirement                        |
| ------------------ | ------------------------------------ | ----------------------------------------- |
| Metric/time series | Traffic, errors, latency, saturation | Region/account, unit, statistic, period   |
| Number/gauge       | Current summary                      | Baseline/window and missing-data meaning  |
| Log query          | Drill into events                    | Time/groups/language and scan costs       |
| Alarm status       | Triage/owner attention               | Not a replacement for notifications       |
| Text               | Runbook/owner/assumptions            | Maintain links with the deployed workload |

```text
customer outcome: error ratio + latency + synthetic availability
request path: ALB → service → database/queue
diagnosis: deployment revision + trace/log links + dependency signal
response: alarms + owner/runbook + rollback/recovery links
```

Automatic service dashboards provide a starting view, not a reviewed application dashboard or a guarantee of no charges. Browser/live-data choices affect display; they do not increase a metric's publication frequency.

## Cross-service and metric-math configuration

A widget can include several explicitly defined series and an expression. This valid widget fragment can be inserted into the existing dashboard's widgets array after replacing identifiers:

```json
{
  "type": "metric",
  "x": 0,
  "y": 6,
  "width": 12,
  "height": 6,
  "properties": {
    "region": "us-east-1",
    "title": "ALB target error percent",
    "period": 60,
    "stat": "Sum",
    "metrics": [
      [
        "AWS/ApplicationELB",
        "HTTPCode_Target_5XX_Count",
        "LoadBalancer",
        "app/REPLACE/REPLACE",
        { "id": "e", "visible": false }
      ],
      [
        "AWS/ApplicationELB",
        "RequestCount",
        "LoadBalancer",
        "app/REPLACE/REPLACE",
        { "id": "r", "visible": false }
      ],
      [
        {
          "expression": "IF(r>0,100*e/r,0)",
          "id": "errorrate",
          "label": "Target error percent"
        }
      ]
    ]
  }
}
```

Add EC2/RDS widgets with their own actual dimension identities; do not imply an ALB label identifies its database. Annotations mark known thresholds/deployments but do not create alarms. Dashboard variables must target supported properties/patterns and preserve account/Region context.

## Console, CLI, IaC and cross-account ownership

The existing CLI lab's body can be stored in an AWS::CloudWatch::Dashboard DashboardBody string through CloudFormation. Export or version the body, validate messages and review intended diffs; an IaC success event is not proof every graph has data.

For cross-account widgets, first establish supported OAM source/sink or the legacy role workflow. Widget accountId/region settings select data, not permission. Avoid nonexistent cloudwatch:CrossAccountLink actions or placing AccountId as a made-up metric dimension.

## Investigation and cleanup

Compare dashboard selected interval with alarm evaluation time; auto-refresh, live display and graph aggregation can show different evidence. An empty widget warrants checking Region/account, exact metric dimensions, credentials and absence versus zero—not immediate alarm deletion.

A dashboard is a configuration object. Deleting it does not stop agents, logs, metrics, alarms, queries or paid underlying resources. Delete only the disposable dashboard/variables and associated owned query definitions; preserve operational views used by other teams.

References: [widget schema](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/CloudWatch-Dashboard-Body-Structure.html), [dashboard variables](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_dashboard_variables.html), [CloudFormation dashboard](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-cloudwatch-dashboard.html).

## References

- [Dashboard body schema](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/CloudWatch-Dashboard-Body-Structure.html)
- [Cross-account observability](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Unified-Cross-Account.html)
- [Dashboard API](https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/put-dashboard.html)
- [Pricing](https://aws.amazon.com/cloudwatch/pricing/)

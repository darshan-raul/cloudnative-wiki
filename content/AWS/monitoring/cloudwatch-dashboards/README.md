---
title: CloudWatch Dashboards
description: CloudWatch Dashboards — custom metric visualization with widgets, live data, cross-service views, and cross-account sharing.
tags:
  - aws
  - monitoring
  - dashboards
  - cloudwatch
---

# CloudWatch Dashboards

CloudWatch Dashboards create customizable views of your metrics and logs. You can build operational dashboards for SREs, business dashboards for stakeholders, and share them across accounts.

## Dashboard Concepts

### Widget Types

| Widget | Use |
|--------|-----|
| Line | Time-series metrics (CPU, latency) |
| Stacked Area | Multiple metrics stacked (request count by status code) |
| Bar | Comparative metrics (error rate by service) |
| Number | Single metric value (current p99 latency) |
| Text | Static text, markdown (annotations, team info) |
| Pie/Donut | Percentage breakdown (error types) |

### Dashboard Structure

```json
{
  "widgets": [
    {
      "type": "metric",
      "x": 0, "y": 0, "width": 12, "height": 6,
      "properties": {
        "title": "API Latency",
        "metrics": [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "app/my-alb"],
          [".", "HealthyHostCount", ".", "."]
        ],
        "period": 60,
        "stat": "Average",
        "view": "timeSeries"
      }
    },
    {
      "type": "text",
      "x": 12, "y": 0, "width": 12, "height": 3,
      "properties": {
        "markdown": "# Production Dashboard\nLast updated: 2024-01-15"
      }
    }
  ]
}
```

## Creating Dashboards

### Via Console

Console: CloudWatch → Dashboards → Create dashboard

### Via AWS CLI

```bash
aws cloudwatch put-dashboard \
  --dashboard-name production-overview \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "properties": {
          "title": "CPU Utilization",
          "metrics": [["AWS/EC2","CPUUtilization"]],
          "period": 300,
          "stat": "Average"
        }
      }
    ]
  }'
```

### Via CloudFormation

```yaml
Resources:
  Dashboard:
    Type: AWS::CloudWatch::Dashboard
    Properties:
      DashboardName: production-overview
      DashboardBody: !Sub |
        {
          "widgets": [
            {
              "type": "metric",
              "properties": {
                "title": "CPU Utilization",
                "metrics": [["AWS/EC2","CPUUtilization",{"value": "*"}]],
                "period": 300,
                "stat": "Average"
              }
            }
          ]
        }
```

## Dashboard Features

### Live Data

Enable "Live Data" to show real-time metrics (refreshes every 10 seconds). Useful for monitoring active incidents.

### Annotations

Add vertical lines for significant events (deployments, incidents):

```json
{
  "type": "metric",
  "properties": {
    "annotations": {
      "horizontal": [
        {
          "label": "Deployment",
          "value": 1642233600
        }
      ]
    }
  }
}
```

### Metric Math on Dashboards

Use metric math expressions directly in dashboard widgets:

```json
{
  "type": "metric",
  "properties": {
    "title": "Error Rate %",
    "metrics": [
      {"expression": "100 * (m1/m2)", "label": "Error Rate"}
    ]
  }
}
```

## Cross-Service Dashboards

### ALB + EC2 + RDS Dashboard

```json
{
  "widgets": [
    {
      "type": "metric", "x": 0, "y": 0, "width": 12, "height": 6,
      "properties": {
        "title": "ALB Metrics",
        "metrics": [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/my-alb"],
          [".", "TargetResponseTime", ".", "."],
          [".", "UnHealthyHostCount", ".", "."]
        ]
      }
    },
    {
      "type": "metric", "x": 12, "y": 0, "width": 12, "height": 6,
      "properties": {
        "title": "EC2 Metrics",
        "metrics": [
          ["AWS/EC2", "CPUUtilization", {"value": "*"}],
          ["AWS/EC2", "NetworkOut", {"value": "*"}]
        ]
      }
    },
    {
      "type": "metric", "x": 0, "y": 6, "width": 12, "height": 6,
      "properties": {
        "title": "RDS Metrics",
        "metrics": [
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "my-db"],
          [".", "CPUUtilization", ".", "."],
          [".", "FreeStorageSpace", ".", "."]
        ]
      }
    }
  ]
}
```

## Cross-Account Dashboards

CloudWatch cross-account dashboards aggregate metrics from multiple AWS accounts:

```
Management Account (Observability account)
  └── CloudWatch Dashboard (cross-account view)
        ← /aws/lambda/app (Account A)
        ← /aws/lambda/api (Account B)
        ← /aws/ec2/fleet (Account C)
```

### Configuration

```bash
# In the monitoring account
aws cloudwatch put-dashboard \
  --dashboard-name cross-account-prod \
  --dashboard-body '...'

# Widget with cross-account dimension
{
  "type": "metric",
  "properties": {
    "metrics": [
      ["AWS/Lambda", "Invocations", "FunctionName", "my-function", "Account", "111122223333"]
    ]
  }
}
```

## Automatic Dashboards

CloudWatch can auto-generate service-level dashboards:

- **EC2:** CPU, network, disk for all instances
- **RDS:** Connections, CPU, storage, replication lag
- **Lambda:** Invocations, duration, errors, throttles
- **ALB:** Request count, latency, unhealthy hosts

## Widget Syncing

Dashboard widgets can sync to a specific time range — when you zoom in on one widget, all other widgets update to the same time range. Enable "Synced" in the widget settings.

## Limits

| Resource | Limit |
|----------|-------|
| Dashboards per account | 100 |
| Widgets per dashboard | 100 |
| Metrics per widget | 100 |
| Dashboard body size | 512KB |

## References

- **Homepage:** https://aws.amazon.com/cloudwatch/
- **Documentation:** https://docs.aws.amazon.com/cloudwatch/
- **Pricing:** https://aws.amazon.com/cloudwatch/pricing/

## Pricing Examples

**Scenario 1:** A startup's SRE team building a production dashboard with 20 widgets (CPU, memory, latency, errors per service, 10 services × 2 widgets each). Dashboards are free (you only pay for the underlying metrics). Total: $0/month for the dashboard itself.

**Scenario 2:** A multi-account enterprise with 5 member accounts sharing dashboards from a central monitoring account. Each account has 50 custom metrics. CloudWatch charges $0.30/metric/month for detailed monitoring. 5 × 50 × $0.30 = $75/month. Without a central dashboard, each team manages their own — chaos.

## Nuggets & Gotchas

- **Dashboard widgets without a time range show the last 3 hours by default — not 24 hours:** When you create a widget, it inherits the dashboard's time range. If the dashboard has no default, widgets default to 3 hours. Always set an explicit default time range for operational dashboards.
- **Metric math expressions in widgets are evaluated at display time — not stored:** If you use `SEARCH()` in a dashboard metric math expression, it re-evaluates every time the dashboard loads. This can be slow for complex searches and may hit API rate limits on high-frequency refresh.
- **Cross-account dashboards require the `cloudwatch:CrossAccountLink` permission in the monitoring account:** If you create a cross-account dashboard and see no data, check that the member accounts have granted the monitoring account `cloudwatch:CrossAccountLink` via the CloudWatch cross-account settings.
- **Auto-refresh on dashboards has a minimum of 10 seconds:** You cannot set auto-refresh faster than 10 seconds. For real-time monitoring (faster than 10 seconds), use a third-party tool or direct CloudWatch API polling.
- **Dashboard JSON has a 512KB limit — complex dashboards may exceed this:** If you hit this limit, split into multiple dashboards (one per service) and use a "dashboard of dashboards" text widget to link them.
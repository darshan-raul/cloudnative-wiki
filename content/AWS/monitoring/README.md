---
title: AWS Monitoring
description: AWS monitoring and observability — CloudWatch Metrics, Logs, Alarms, Dashboards, and Insights for unified monitoring across your AWS infrastructure and applications.
tags:
  - aws
  - monitoring
  - observability
---

# AWS Monitoring

AWS monitoring is built around CloudWatch — a centralized service for metrics, logs, alarms, and dashboards. CloudWatch provides visibility into how your applications and infrastructure are performing.

## Service Map

| Service | What It Does | When to Use |
|---------|-------------|-------------|
| [[cloudwatch-metrics/README|Metrics]] | Time-series data for AWS and custom resources | Every service emits metrics — query with GetMetricData |
| [[cloudwatch-logs/README|Logs]] | Centralized log storage and management | Every application should stream logs here |
| [[cloudwatch-alarms/README|Alarms]] | Alerting based on metric thresholds | Alert when latency spikes, error rate rises |
| [[cloudwatch-dashboards/README|Dashboards]] | Custom metric visualization | Build custom views for business/SRE metrics |
| [[cloudwatch-events/README|Events]] | Event-driven automation via rules | React to AWS API events, schedules |
| [[cloudwatch-insights/README|Insights]] | Log query language for CloudWatch Logs | Debug production issues, search logs |

## Three Pillars of Observability

```
Metrics (What happened?)
  → CloudWatch Metrics (numerical time-series data)
  → How many requests? What's p99 latency?

Logs (Why did it happen?)
  → CloudWatch Logs (application and infrastructure logs)
  → What error occurred? What was the request trace?

Traces (How did it happen?)
  → AWS X-Ray (distributed tracing, not in this section)
  → Request flow through services
```

## Core Concepts

### Namespaces

Metrics are organized by namespace — each AWS service has its own namespace:

```
AWS/EC2          → CPUUtilization, NetworkIn, DiskWriteBytes
AWS/RDS          → DatabaseConnections, CPUUtilization, FreeStorageSpace
AWS/Lambda       → Invocations, Duration, Errors
MyApp/Production → Custom metrics you define
```

### Dimensions

A dimension is a name/value pair that uniquely identifies a metric. Common dimensions:

```
InstanceId          → CPU for a specific EC2 instance
InstanceType        → CPU across all instances of a type
ServiceName         → Latency for a specific microservice
AvailabilityZone    → NetworkIn per AZ
```

### Resolution

| Resolution | Retention |
|-----------|-----------|
| Basic (5 min) | 15 days |
| High (1 min) | 15 days |
| Detailed (1 sec) | 3 hours |

## Architecture: Unified Monitoring Stack

```
Application (EC2/ECS/Lambda)
  │  (emit metrics via StatsD / CloudWatch Agent)
  ↓
CloudWatch Metrics (custom + basic monitoring)
  │
  ├→ CloudWatch Alarms → SNS → Email/PagerDuty
  │
  ├→ CloudWatch Dashboards → SRE / Business view
  │
  └→ CloudWatch Contributor Insights → Top contributors

Application Logs
  │  (via CloudWatch Agent / SDK)
  ↓
CloudWatch Logs
  │
  ├→ CloudWatch Logs Insights (query)
  ├→ Subscription Filters → Lambda / Kinesis
  └→ Cross-Account Logs → Logs bucket (S3)
```

## AWS Services Organized by Category

**CloudWatch Core**
- [[cloudwatch-metrics/README|Metrics]] — Time-series data, GetMetricData API, custom metrics
- [[cloudwatch-logs/README|Logs]] — Log groups, streams, CloudWatch Agent, retention
- [[cloudwatch-alarms/README|Alarms]] — Metric alarms, composite alarms, anomaly detection
- [[cloudwatch-dashboards/README|Dashboards]] — Custom widgets, live charts, cross-service
- [[cloudwatch-events/README|Events]] — CloudWatch Events rules (legacy EventBridge API)
- [[cloudwatch-insights/README|Insights]] — Log query language, saved queries, dashboards

## Cross-Account Observability

CloudWatch Application Insights can automatically discover and monitor applications across accounts in AWS Organizations.

```
Management Account
  └── CloudWatch Cross-Account Dashboards
        → Aggregates metrics from member accounts
        → Single pane of glass for all accounts

Member Account
  └── CloudWatch Metrics
        └── Shared via CloudWatch Dashboard sharing
```

## References

- **Homepage:** https://aws.amazon.com/cloudwatch/
- **Documentation:** https://docs.aws.amazon.com/cloudwatch/
- **Pricing:** https://aws.amazon.com/cloudwatch/pricing/

## Nuggets & Gotchas

- **CloudWatch Metrics have a 1-second resolution limit — for sub-second metrics, use custom SDK:** AWS services emit metrics at 1-minute (basic) or 1-second (detailed) resolution. For sub-second granularity, you must use the PutMetricData API with higher resolution timestamps.
- **CloudWatch Logs is priced per GB ingested + per GB stored — logging everything is expensive:** At $0.50/GB for ingestion and $0.03/GB/month for storage, a high-traffic application generating 1GB/day of logs costs $15/month + $0.90/month = $15.90/month. Use subscription filters to selectively route logs to S3 or Lambda for cheaper storage.
- **Metric math with GetMetricData is cheaper than multiple GetMetricStatistics calls:** One GetMetricData call with math on 500 metrics costs the same as one GetMetricStatistics call. Batch your metric queries.
- **CloudWatch Agent uses the StatsD protocol — you can emit custom metrics from any application:** The CloudWatch Agent listens on UDP port 8125 for StatsD messages. Any application can send `nginx.requests:100|c` and it appears in CloudWatch as a custom metric.
- **Alarms have a 10-second evaluation period minimum — you cannot set sub-10-second alerting:** For real-time alerting with sub-10-second detection, use CloudWatch Contributor Insights or a third-party monitoring tool like Datadog or Grafana.
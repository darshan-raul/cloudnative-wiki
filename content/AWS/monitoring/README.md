---
title: AWS Monitoring
description: AWS monitoring and observability — CloudWatch Metrics, Logs, Alarms, Dashboards, and Insights for unified monitoring across your AWS infrastructure and applications.
tags:
  - aws/monitoring
date: 2026-10-12
---

# AWS Monitoring

Observability answers whether users are receiving the service you promised, then helps explain failures. Metrics summarize behavior; logs preserve events; traces connect work across boundaries. Audit logs are a separate security requirement.

## Learning path

1. Define an SLI (for example successful requests / valid requests), an SLO and an error budget before choosing dashboards.
2. Publish bounded-cardinality [[AWS/monitoring/cloudwatch-metrics/README|metrics]] and retain structured [[AWS/monitoring/cloudwatch-logs/README|logs]] according to data sensitivity.
3. Use [[AWS/monitoring/cloudwatch-insights/README|Logs Insights]] to investigate and [[AWS/monitoring/cloudwatch-alarms/README|alarms]] to notify an owner with a runbook.
4. Assemble [[AWS/monitoring/cloudwatch-dashboards/README|dashboards]], then correlate [[AWS/monitoring/tracing-and-observability|traces and cross-account telemetry]].
5. Route operational events through [[AWS/application-integration/eventbridge/README|EventBridge]]. [[AWS/monitoring/cloudwatch-events/README|CloudWatch Events]] is the historical naming path, not another current event platform.

## Architecture and boundaries

An application should propagate a request/trace ID into structured logs and traces. Metrics use low-cardinality dimensions such as service and environment, not user IDs or unique request IDs. Use an agent, Embedded Metric Format, direct metric APIs or OpenTelemetry according to the data model and runtime; those are not interchangeable billing and storage models.

Classic high-resolution custom metrics support one-second resolution. Newer OpenTelemetry metric capabilities have their own resolution and retention model: do not apply the classic rollup table to every CloudWatch data type. Cross-account observability links telemetry for query; log centralization actually copies records and can duplicate ingestion/storage costs.

## Operational exercise

Pick a sandbox workload and record baseline request rate, failure rate and latency. Inject a controlled dependency failure, confirm logs and traces carry the same correlation ID, and verify the alarm notifies a subscribed responder. Record detection time, user impact and recovery time. Restore the dependency, confirm alarm recovery and remove temporary telemetry or set bounded retention. Keep security audit coverage enabled.

## Cost and limits

Estimate each dimension separately: unique metrics, API requests, logs ingested/stored/scanned, dashboard count, alarms, trace volume and optional insights features. Query narrow time windows and indexed fields where applicable. Check current account/Region quotas before load tests; a service quota is not reserved capacity.

## Unified telemetry architecture

```text
applications ── structured logs ── CloudWatch Logs ── Insights queries
     ├──────── bounded metrics ── CloudWatch ── alarms ── SNS/runbook
     └──────── trace context ──── ADOT/X-Ray ── correlated spans
security/API activity ─────────── CloudTrail (separate audit coverage)
selected state events ─────────── EventBridge → authorized targets
```

| Telemetry   | Question                                             | Important boundary                                          |
| ----------- | ---------------------------------------------------- | ----------------------------------------------------------- |
| Metric      | Is the service failing or saturated?                 | Aggregation/cardinality/resolution                          |
| Log         | What happened to a request/entity?                   | Sensitivity, retention, schema and scan cost                |
| Trace       | Which instrumented dependency consumed time?         | Propagation, sampling and incomplete spans                  |
| Audit event | Which principal changed/called a supported resource? | Event selectors and retention, not every application action |

A namespace groups metric names; dimensions identify a time series. A period is the aggregation interval, not the publishing interval. A namespace is not an authorization or account-isolation boundary. Service metrics, custom metrics and new OTel metrics must be interpreted using their actual contracts.

## Cross-account and cross-service operations

OAM source links/sinks provide supported monitoring-account visibility. Central log copying additionally creates storage/ingestion ownership, data residency and duplicate-cost questions. An organization-wide dashboard does not grant arbitrary query/remediation authority.

For an ALB→application→database path, monitor request/error/latency, application dependency errors, database capacity/lag and queue age together. Distinguish an AWS Health event from the workload's measured health. Include deployment revision and request IDs to correlate change and failure.

A handoff contains owners, SLO/error-budget decision, dashboard time/account/Region, alert subscription, runbook, telemetry retention and a tested recovery story. Deleting a dashboard does not stop telemetry production.

## Cross-wiki comparisons

- [[Azure/monitoring/log-analytics/README|Azure Monitor & Log Analytics Architecture, KQL, and Observability]] — cloud logging and monitoring (Azure)
- [[Observability/logging|Logging]] — cloud logging and monitoring (Observability)
- [[Linux/observability/README|Linux Observability]] — cloud logging and monitoring (Linux)

## References

- [CloudWatch concepts](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html)
- [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/)

## Across the wiki

- [[GCP/monitoring/cloud-logging/README|Cloud Logging Architecture, Log Router, and Log Analytics]]

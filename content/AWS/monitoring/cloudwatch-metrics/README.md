---
title: CloudWatch Metrics
description: CloudWatch Metrics — time-series numerical data for AWS services and custom applications. Namespaces, dimensions, metric math, GetMetricData API, and high-resolution metrics.
tags:
  - aws/monitoring
date: 2026-10-12
---

# CloudWatch Metrics

Prerequisites: [[AWS/security/iam/README|scoped IAM access]] and [[AWS/monitoring/README|telemetry, SLI and retention design]].

CloudWatch metrics are time series identified by namespace, metric name and dimensions. Publishing a new dimension combination creates a different metric; cardinality is a design and cost decision.

## Model and retention

Classic custom metrics use standard one-minute or high-resolution one-second storage resolution. Aggregation period and an AWS service's publishing interval are different settings. EC2 basic monitoring commonly publishes at five-minute intervals; detailed monitoring changes that interval, not every metric's retention.

Classic rollups retain sub-minute data for 3 hours, one-minute data for 15 days, five-minute data for 63 days and hourly data for 455 days. Query old data using an available period. OpenTelemetry metrics use a separately documented model.

Use the correct service namespace: Application Load Balancer metrics use `AWS/ApplicationELB`, not `AWS/ALB`. A dimension must match the metric's exact identity. Metric math references explicitly defined metric/query IDs; a graph expression is not a newly published metric.

## Reversible custom-metric lab

Prerequisites: [[AWS/security/iam/README|a sandbox role]] with `cloudwatch:PutMetricData` constrained to namespace `WikiLab` and read permission for metric retrieval. Set your intended Region explicitly. Publishing is billable; this is not an automatic free-tier promise.

```bash
aws cloudwatch put-metric-data --namespace WikiLab \
  --metric-data '[{"MetricName":"Latency","Dimensions":[{"Name":"Service","Value":"demo"}],"Value":120,"Unit":"Milliseconds","StorageResolution":60}]'
aws cloudwatch get-metric-statistics --namespace WikiLab --metric-name Latency \
  --dimensions Name=Service,Value=demo --statistics Average --period 60 \
  --start-time 2026-10-12T00:00:00Z --end-time 2026-10-13T00:00:00Z
```

Replace the UTC interval with a window surrounding your publication. Expected: after ingestion, a datapoint near 120 ms. An empty result suggests the wrong Region, interval, dimension or ingestion delay; an AccessDenied error is an authorization problem, not a reason to widen the role to administrator.

Publish another value (80) in the same minute to observe aggregate statistics. A production Python publisher must import any timestamp helper and handle API errors/retries; this CLI fixture avoids undefined helpers.

## Scale and cost

PutMetricData accepts up to 1,000 metrics per request subject to its payload limit. Batch deliberately; unique dimensions, not emitted-point count alone, drive traditional custom metric-month charges. API requests and detailed monitoring are additional dimensions. Avoid customer IDs as dimensions; use logs/traces for per-request detail.

You cannot delete an individual CloudWatch metric. Stop publishing after the exercise; unused metrics age out under retention. Delete associated alarms/dashboards separately.

## Service namespaces and measurement choices

| Source      | Namespace/model                        | Useful measurement                                              |
| ----------- | -------------------------------------- | --------------------------------------------------------------- |
| EC2         | AWS/EC2                                | CPU and supported instance metrics; guest memory needs an agent |
| ALB         | AWS/ApplicationELB                     | Request count, target errors, response time and health          |
| RDS         | AWS/RDS                                | Engine/instance metrics with documented dimensions              |
| Lambda      | AWS/Lambda                             | Invocations/errors/duration/concurrency                         |
| Application | Chosen custom namespace/EMF/OTel model | Business latency/outcomes with bounded cardinality              |

ListMetrics discovers identities; it does not retrieve datapoints or prove an old series no longer exists. For GetMetricStatistics use an actual time interval, matching dimensions and valid available period. Missing results can mean identity/Region/rollup mismatch, not zero.

## GetMetricData and math walkthrough

Save this complete query array as metric-queries.json; it references the WikiLab fixture:

```json
[
  {
    "Id": "latency",
    "MetricStat": {
      "Metric": {
        "Namespace": "WikiLab",
        "MetricName": "Latency",
        "Dimensions": [{ "Name": "Service", "Value": "demo" }]
      },
      "Period": 60,
      "Stat": "Average"
    },
    "ReturnData": false
  },
  {
    "Id": "seconds",
    "Expression": "latency/1000",
    "Label": "Latency seconds",
    "ReturnData": true
  }
]
```

```bash
aws cloudwatch get-metric-data --metric-data-queries file://metric-queries.json \
  --start-time 2026-10-12T00:00:00Z --end-time 2026-10-13T00:00:00Z
```

Replace dates; expect about 0.12 seconds for the 120-ms fixture. Handle result status/messages and pagination when retrieving large intervals. An expression's IDs must exist in that request; math does not publish a new metric or change its unit identity.

## Complete Python publisher

```python
from datetime import datetime, timezone
import boto3

cloudwatch = boto3.client("cloudwatch")
cloudwatch.put_metric_data(
    Namespace="WikiLab",
    MetricData=[{
        "MetricName": "Latency",
        "Dimensions": [{"Name": "Service", "Value": "demo"}],
        "Timestamp": datetime.now(timezone.utc),
        "Value": 120,
        "Unit": "Milliseconds",
        "StorageResolution": 60,
    }],
)
```

Use the verified SDK profile/Region session, catch failures in a real application and retry only according to the SDK/service guidance. StatsD requires a configured running agent/collector and UDP reachability; sending bytes to port 8125 without one is not ingestion. EMF writes a structured log envelope from which metrics are extracted; raw JSON values are not automatically custom metrics.

High-resolution uses StorageResolution=1 and adds applicable alarm/API cost. It is not a request for arbitrary subsecond classic storage. Metric-widget image rendering accepts a documented widget JSON string and returns binary/base64 according to SDK/CLI representation; separate output decoding from shell/API JSON examples.

## Troubleshooting and worked cardinality

A metric with Environment×Service×Customer produces one identity per observed combination. If ten services each emit five bounded environments, budget up to fifty series; adding 100,000 customer IDs can explode that design. Price the actual unique series and API usage, not only points/sec.

Inspect role namespace conditions, future/stale timestamps, units, dimension spelling and ingestion delay. Stop agent/application publication and remove associated lab alarms/dashboards; there is no DeleteMetric command.

References: [GetMetricData](https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/get-metric-data.html), [EMF](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html), [agent metric configuration](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html).

## Cross-wiki comparisons

- [[Azure/monitoring/log-analytics/README|Azure Monitor & Log Analytics Architecture, KQL, and Observability]] — cloud logging and monitoring (Azure)
- [[Observability/logging|Logging]] — cloud logging and monitoring (Observability)
- [[Linux/observability/README|Linux Observability]] — cloud logging and monitoring (Linux)

## References

- [Metric concepts and retention](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html)
- [PutMetricData contract](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/API_PutMetricData.html)
- [Pricing dimensions](https://aws.amazon.com/cloudwatch/pricing/)

## Across the wiki

- [[GCP/monitoring/cloud-logging/README|Cloud Logging Architecture, Log Router, and Log Analytics]]

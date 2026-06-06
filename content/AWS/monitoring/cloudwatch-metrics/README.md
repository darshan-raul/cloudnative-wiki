---
title: CloudWatch Metrics
description: CloudWatch Metrics — time-series numerical data for AWS services and custom applications. Namespaces, dimensions, metric math, GetMetricData API, and high-resolution metrics.
tags:
  - aws
  - monitoring
  - metrics
  - cloudwatch
---

# CloudWatch Metrics

CloudWatch Metrics is a time-series data store for numerical measurements. Every AWS service emits metrics by default (basic monitoring), and you can emit custom metrics from your applications.

## Core Concepts

### Metric Structure

```
Namespace: AWS/EC2
MetricName: CPUUtilization
Dimensions: [InstanceId=i-xxxxx]
Value: 72.5
Unit: Percent
Timestamp: 2024-01-15T10:30:00Z
Period: 60 seconds
```

### AWS Service Namespaces

| Namespace | Common Metrics |
|-----------|----------------|
| AWS/EC2 | CPUUtilization, NetworkIn, NetworkOut, DiskReadBytes |
| AWS/RDS | CPUUtilization, DatabaseConnections, FreeStorageSpace |
| AWS/Lambda | Invocations, Duration, Errors, Throttles |
| AWS/ALB | RequestCount, TargetResponseTime, UnHealthyHostCount |
| AWS/S3 | BucketSizeBytes, NumberOfObjects, AllRequests |
| AWS/DynamoDB | ConsumedReadCapacityUnits, ConsumedWriteCapacityUnits |

### Basic vs Detailed Monitoring

| | Basic (default) | Detailed (costs extra) |
|--|--|--|
| Resolution | 5 minutes | 1 minute |
| Cost | Free | $0.30/metric/month |
| Data retention | 15 days | 15 days |
| Use | Cost optimization, low-traffic | Production, real-time |

## Retrieving Metrics

### GetMetricStatistics (single metric)

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-15T12:00:00Z \
  --period 300 \
  --statistics Average,Maximum \
  --dimensions Name=InstanceId,Value=i-xxxxx
```

### GetMetricData (multiple metrics, metric math)

```bash
aws cloudwatch get-metric-data \
  --metric-data-queries '[
    {
      "Id": "cpu",
      "MetricStat": {
        "Metric": {
          "Namespace": "AWS/EC2",
          "MetricName": "CPUUtilization",
          "Dimensions": [{"Name": "InstanceId", "Value": "i-xxxxx"}]
        },
        "Period": 300,
        "Stat": "Average"
      }
    },
    {
      "Id": "mem",
      "MetricStat": {
        "Metric": {
          "Namespace": "CWAgent",
          "MetricName": "mem_used_percent",
          "Dimensions": [{"Name": "InstanceId", "Value": "i-xxxxx"}]
        },
        "Period": 300,
        "Stat": "Average"
      }
    }
  ]' \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-15T12:00:00Z
```

### Metric Math

```json
[
  {
    "Id": "total_cost",
    "Expression": "m1 * 0.10 + m2 * 0.05",
    "Period": 300
  }
]
```

Common expressions:
- `m1 + m2` — sum of two metrics
- `SEARCH('{AWS/EC2}, Average)', 300)` — search for metrics matching a pattern

## Custom Metrics

Emit custom metrics from your application using the AWS SDK:

```python
import boto3

cloudwatch = boto3.client('cloudwatch')

# Put a single data point
cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricData=[{
        'MetricName': 'OrderCount',
        'Value': 150,
        'Unit': 'Count',
        'Timestamp': datetime.utcnow(),
        'Dimensions': [
            {'Name': 'Service', 'Value': 'Checkout'},
            {'Name': 'Region', 'Value': 'us-east-1'}
        ]
    }]
)
```

### StatsD Protocol (via CloudWatch Agent)

The CloudWatch Agent can receive StatsD metrics on UDP port 8125:

```
# Send a metric via netcat
echo "app.orders:150|c" | nc -u -w0 127.0.0.1 8125
```

```json
{
  "metrics": {
    "namespace": "MyApp",
    "metrics_collection_interval": 60,
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "statsd": {
      "service_address": ":8125",
      "metrics": [
        {
          "metric_name": "orders",
          "unit": "Count"
        }
      ]
    }
  }
}
```

### High-Resolution Metrics

Standard metrics: 1-minute resolution. High-resolution: 1-second resolution (costs 10x more).

```python
cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricData=[{
        'MetricName': 'Latency',
        'Value': 45.2,
        'Unit': 'Milliseconds',
        'Timestamp': datetime.utcnow(),
        'StorageResolution': 1  # 1-second resolution
    }]
)
```

## GetMetricWidgetImage

Generate a PNG of a metric graph without using dashboards:

```bash
aws cloudwatch get-metric-widget-image \
  --metric-widget '{"metrics": [["AWS/EC2","CPUUtilization","InstanceId","i-xxxxx"]]}' \
  --output-format png
```

## Integration with Other Services

| Service | How It Uses Metrics |
|---------|--------------------|
| CloudWatch Alarms | Trigger alerts when thresholds are breached |
| CloudWatch Dashboards | Visualize metrics in real-time |
| CloudWatch Contributor Insights | Identify top contributors to a metric |
| Auto Scaling | Scale EC2/ECS based on metrics |
| EventBridge | Trigger rules based on metric math results |

## Limits

| Resource | Limit |
|----------|-------|
| Metrics per call (PutMetricData) | 20 |
| Dimensions per metric | 30 |
| Metric name length | 255 characters |
| Namespace name length | 255 characters |
| GetMetricData metrics per call | 500 |
| GetMetricStatistics period minimum | 60 seconds (1 second for high-res) |

## References

- **Homepage:** https://aws.amazon.com/cloudwatch/
- **Documentation:** https://docs.aws.amazon.com/cloudwatch/
- **Pricing:** https://aws.amazon.com/cloudwatch/pricing/

## Pricing Examples

**Scenario 1:** An application with 50 custom metrics (order count, latency, error rate) emitted every minute. 50 metrics × 60 minutes × 24 hours × 30 days = 2.16M metric data points/month. At $0.30/million = $0.65/month. CloudWatch Logs ingestion for application logs (1GB/month) = $0.50/month. Total CloudWatch: ~$1.15/month.

**Scenario 2:** A production system using detailed monitoring on 50 EC2 instances. 50 × $0.30/month = $15/month. Without detailed monitoring, you'd only see 5-minute averages — missing 1-minute spikes in CPU. At $0.02/vCPU-hour (spot instance), a 4-vCPU instance running at 100% during a 1-minute spike (missed by 5-min monitoring) costs $0.0013. Detailed monitoring costs $0.30/instance/month. The cost is justified by the visibility.

## Nuggets & Gotchas

- **PutMetricData has a 20-metric limit per call — use batching for high-volume:** If you emit 100 custom metrics per minute, batch them into 5 calls of 20 metrics each. For ultra-high-volume applications (10K+ metrics/minute), use the metric math API or the CloudWatch Agent's batch feature.
- **Basic monitoring (5-min) is free but has a 15-day retention — you can't query older data:** If you need historical data beyond 15 days, you must either use detailed monitoring (1-min resolution, 15-day retention) or stream metrics to S3 via Kinesis for long-term storage.
- **Metric math expressions are evaluated independently of source metrics' retention periods:** If you use SEARCH() to aggregate metrics, the resulting metric math metric inherits the minimum retention period of the source metrics. For 5-minute basic monitoring, the math result is also 5-minute.
- **Dimensions are case-sensitive — "InstanceId" not "instanceid":** If you query a metric with dimensions and get no results, check the dimension name casing. The CloudWatch API treats `InstanceId` and `instanceId` as different dimensions.
- **EC2 basic monitoring (5-min) is free but detailed monitoring (1-min) costs $0.30/instance/month:** Before enabling detailed monitoring on all instances, consider that for a 100-instance fleet, that's $30/month. For production, detailed monitoring is worth it. For dev/test, basic monitoring is sufficient.
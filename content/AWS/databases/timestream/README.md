---
title: Amazon Timestream
description: Amazon Timestream — managed time-series database. High write throughput, hot/warm/cold storage tiering, scheduled queries, interpolation, and ML-powered anomaly detection.
tags:
  - aws
  - databases
  - timestream
  - time-series
  - iot
---

# Amazon Timestream

Timestream is a managed time-series database optimized for IoT sensor data, application metrics, and operational events. It handles millions of events per second, auto-partitions by time, and offers tiered storage (hot → warm → cold) with automatic data lifecycle management.

## Core Concepts

### Time-Series Data

```
Timestamp          device_id    temperature    humidity    status
2024-01-15T10:00:00Z  sensor-001    22.5          45         OK
2024-01-15T10:00:05Z  sensor-001    22.7          45         OK
2024-01-15T10:00:10Z  sensor-001    23.1          44         OK
2024-01-15T10:00:00Z  sensor-002    18.2          62         OK
```

Each row has a timestamp, measure names (temperature, humidity), and dimensions (device_id).

### Table Structure

| Component | Description |
|-----------|-------------|
| Time column | Timestamp (required, indexed) |
| Dimensions | Metadata attributes (device_id, region) |
| Measures | Time-series values (temperature, CPU) |
| Attributes | Table-level metadata |

### Multi-Measure Records

```sql
CREATE TABLE device_metrics (
  device_id VARCHAR,
  region VARCHAR,
  temperature DOUBLE,
  humidity DOUBLE,
  status VARCHAR
) WITH (
  TIME_SERIES = TRUE,
  PARTITION_KEY = (device_id)
)
```

## Storage Tiers

Timestream automatically moves data between tiers:

```
Hot Store ──────► Warm Store ──────► Cold Store ──────► S3 (optional)
(< 24 hours)     (24h - 7 days)    (7 - 365 days)    (> 365 days)
  In-memory        Magnetic          Magnetic
  $0.018/GB-hr    $0.008/GB-hr      $0.004/GB-hr
```

You define retention policies per tier. Data automatically moves to the next tier.

## Creating a Database and Table

```bash
# Create database
aws timestream create-database \
  --database-name '{
    "DatabaseName": "iot-sensors"
  }' \
  --tags '[{"Key": "Environment", "Value": "production"}]'

# Create table
aws timestream create-table \
  --database-name iot-sensors \
  --table-name '{
    "TableName": "device_metrics",
    "TimeColumnName": "timestamp",
    "DimensionName": "device_id",
    "MeasureNameColumnName": "measure_value",
    "MeasureValueType": "DOUBLE"
  }' \
  --retention-properties '{
    "MemoryStoreRetentionPeriodInHours": "24",
    "WarmStoreRetentionPeriodInDays": "7",
    "MagneticStoreRetentionPeriodInDays": "365"
  }' \
  --tags '[{"Key": "Environment", "Value": "production"}]'
```

## Writing Data

### Via Write API

```python
import boto3
import time

client = boto3.client('timestream-write')

# Single record
records = [{
    'Dimensions': [
        {'Name': 'device_id', 'Value': 'sensor-001'},
        {'Name': 'region', 'Value': 'us-east-1'}
    ],
    'MeasureName': 'temperature',
    'MeasureValue': '22.5',
    'MeasureValueType': 'DOUBLE',
    'Time': str(int(time.time() * 1000)),  # milliseconds
    'TimeUnit': 'MILLISECONDS'
}]

client.write_records(
    DatabaseName='iot-sensors',
    TableName='device_metrics',
    Records=records,
    CommonAttributes={
        'Dimensions': [
            {'Name': 'device_id', 'Value': 'sensor-001'}
        ]
    }
)
```

### Via MQTT (IoT Core)

```
IoT Sensors → IoT Core (MQTT) → IoT Analytics → Timestream
```

Use IoT Rules to route MQTT messages to Timestream:

```json
{
  "rule": {
    "sql": "SELECT * FROM 'sensors/+'",
    "actions": [{
      "timestream": {
        "database": "iot-sensors",
        "table": "device_metrics",
        "dimensions": [{"name": "device_id", "value": "${topic()}"}],
        "measureName": "temperature"
      }
    }]
  }
}
```

## Querying

### SELECT

```sql
SELECT
  device_id,
  CREATE_TIME_SERIES(timestamp, temperature) AS temp_series
FROM iot-sensors.device_metrics
WHERE device_id = 'sensor-001'
  AND timestamp BETWEEN '2024-01-15 10:00:00' AND '2024-01-15 11:00:00'
GROUP BY device_id
ORDER BY device_id
```

### INTERPOLATE (fill gaps)

Sensors may have missing data points:

```sql
SELECT
  device_id,
  INTERPOLATE_LINEAR(
    CREATE_TIME_SERIES(timestamp, temperature),
    SEQUENCE('2024-01-15 10:00:00', '2024-01-15 11:00:00', 5m)
  ) AS filled_series
FROM iot-sensors.device_metrics
WHERE device_id = 'sensor-001'
GROUP BY device_id
```

### Window Functions

```sql
SELECT
  device_id,
  BIN(timestamp, 5m) AS t,
  AVG(temperature) AS avg_temp,
  MAX(temperature) AS max_temp,
  MIN(temperature) AS min_temp
FROM iot-sensors.device_metrics
WHERE timestamp > NOW() - INTERVAL '1' HOUR
GROUP BY device_id, BIN(timestamp, 5m)
ORDER BY device_id, t
```

## Scheduled Queries

Run queries on a schedule, output to S3 or another table:

```bash
aws timestream create-scheduled-query \
  --name 'hourly-aggregates' \
  --database-name iot-sensors \
  --target-destination '{
    "TimestreamConfiguration": {
      "DatabaseName": "iot-sensors",
      "TableName": "hourly_metrics"
    }
  }' \
  --schedule-configuration '{
    "ScheduleExpression": "cron(0 * * * ? *)"
  }' \
  --query 'SELECT device_id, AVG(temperature) AS avg_temp ...'
```

## Anomaly Detection (ML)

Timestream ML-powered anomaly detection:

```sql
SELECT
  device_id,
  ANOMALY_DETECTION(temperature) AS anomaly_score
FROM iot-sensors.device_metrics
WHERE timestamp > NOW() - INTERVAL '1' DAY
  AND device_id = 'sensor-001'
```

This uses Random Cut Forest (RCF) to score each data point. Scores > 2 standard deviations are anomalies.

## Connecting from BI Tools

Timestream integrates with:
- Amazon QuickSight (visualization)
- Grafana (via Timestream plugin)
- Tableau (via JDBC driver)

## Monitoring

```bash
# Key metrics
# IncomingRecords, IncomingBytes, QueryLatency, StorageUtilization

aws cloudwatch get-metric-statistics \
  --namespace AWS/Timestream \
  --metric-name IncomingRecords \
  --dimensions Name=DatabaseName,Value=iot-sensors
```

## Pricing

| Component | Cost |
|-----------|------|
| Write (records) | $0.50 per million |
| Hot storage | $0.018/GB-hour |
| Warm storage | $0.008/GB-hour |
| Cold storage | $0.004/GB-hour |
| Query (Compute) | $0.01 per GB scanned |
| Scheduled query | $0.008 per query |

## Limits

| Resource | Limit |
|----------|-------|
| Max record size | 1 MB |
| Max dimensions per table | 128 |
| Max attributes per record | 1,024 |
| Max query timeout | 60 seconds |
| Max results | 100,000 rows |
| Max concurrent queries | 10 |

## References

- **Homepage:** https://aws.amazon.com/timestream/
- **Documentation:** https://docs.aws.amazon.com/timestream/
- **Pricing:** https://aws.amazon.com/timestream/pricing/

## Pricing Examples

**Scenario 1:** An IoT deployment with 10,000 sensors, 1 reading/second each. 10,000 sensors × 1 reading/sec × 3600 sec/hr = 36M records/hour. Write cost: 36M/hr × $0.50/M = $18/hr × 24hr = $432/day × 30 = $12,960/month. That's expensive! Use batch writes (aggregate every 10 seconds): 3.6M records/hr × $0.50/M = $1.80/hr × 24 × 30 = $1,296/month. 90% savings.

**Scenario 2:** A metrics dashboard (1M records/day, 30-day retention). Storage: 1M × 30 days = 30M records. Average record 500 bytes = 15GB hot (1 day) + 105GB warm (7 days) + 300GB cold (22 days). Storage: 15GB × $0.018 × 24hr × 30 + 105GB × $0.008 × 24hr × 7 + 300GB × $0.004 × 24hr × 22 = $259/month. Query: 1000 queries/day × 1MB scanned × $0.01/GB = $0.01/month. Total: ~$260/month.

## Nuggets & Gotchas

- **Timestream's write API has a batch limit — you can't write unlimited records per call:** Max 100 records per batch, 1MB per record. For 10,000 sensors, you'll need to batch writes or use IoT Core + Rules for ingestion.
- **Timestream has no UPDATE or DELETE — time-series data is append-only:** Like QLDB, you can't modify historical data. If you need to correct bad data, insert a new record with the corrected value and use the latest value in queries.
- **Timestream query pricing is per GB scanned — full table scans are expensive:** Always filter by time range. A query without a time filter on 1TB of data costs $10. Use `WHERE timestamp BETWEEN ...` to limit scanned data.
- **Timestream's INTERPOLATE function requires at least 2 known data points:** If your sensor has a gap of 1 hour and you try to interpolate, it will only fill if there are data points before and after the gap. Use `FILL` for forward-fill of missing values.
- **Timestream's Memory Store (hot tier) has a 24-hour minimum retention — you can't set it to 0:** If you want everything in warm immediately, set Memory Store to 1 hour (minimum) and warm store to 0. Or use S3 Direct Query for cold data without warm tier.
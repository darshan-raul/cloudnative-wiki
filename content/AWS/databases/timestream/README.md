---
title: "Amazon Timestream"
description: "Distinguish Timestream for LiveAnalytics from Timestream for InfluxDB."
tags:
  - aws/databases
date: 2026-10-12
---

# Amazon Timestream

Distinguish Timestream for LiveAnalytics from Timestream for InfluxDB. LiveAnalytics closed to new customers June 20, 2025; existing customers remain supported. InfluxDB is a separate deployment/query/client model, not a replacement CLI namespace for LiveAnalytics. New customers must check eligibility before attempting this lesson's LiveAnalytics workflow.

Prerequisites: [[AWS/architecture/data-store-selection|data-store selection]], [[AWS/security/iam/README|IAM]] and [[AWS/analytics/README|analytics]].

## LiveAnalytics data and retention

Records have dimensions, measure values/names and timestamps; multi-measure records can reduce repeated dimensions. Storage has memory and magnetic tiers, not invented warm/cold tiers. Minimum retention is one hour in memory and one day in magnetic storage. Expiry removes data under retention rules; it does not automatically export every expired record to S3.

Maximum record size is 2 KB and WriteRecords accepts up to 100 records per call. LiveAnalytics lacks SQL UPDATE/DELETE, but WriteRecords supports upserts of the same record identity with a higher Version; “append-only and never modifiable” is inaccurate.

## Real API namespaces and query model

Use timestream-write for database/table/write operations and timestream-query for SQL. Table/database names are strings; schema comes from writes rather than invented table-name JSON.

```bash
aws timestream-write create-database --database-name sandbox_timeseries
aws timestream-write create-table --database-name sandbox_timeseries \
  --table-name readings \
  --retention-properties MemoryStoreRetentionPeriodInHours=1,MagneticStoreRetentionPeriodInDays=1
```

These CLI v2 commands are for eligible existing LiveAnalytics customers with permissions and a budget. They create chargeable resources; they were not deployed during documentation validation.

SQL can aggregate time bins, create supported time-series values, interpolate and use window functions. Scheduled queries materialize supported derived data with configured permissions; do not label them an automatic CSV-to-S3 export. No documented built-in ANOMALY_DETECTION/Random Cut Forest function is assumed here: perform anomaly analysis through explicitly supported SQL or an external ML pipeline.

## Eligible-account exercise

Write a few timestamped readings through WriteRecords, then query one sensor over a bounded time interval. Re-write the same identity with a higher Version and verify the update; a stale/lower version should be rejected according to the contract. Include an unauthorized-identity denial and bounded query/polling limits.

Inspect memory/magnetic retention and expected expiry; do not promise archival preservation. Remove disposable tables/database and any query outputs/roles created for the exercise. New customers should instead follow the owning InfluxDB guide and adapt the exercise to its API, not force LiveAnalytics access.

## Cost and recovery

For 1M records/day × 500 bytes, raw volume is 0.5 decimal GB/day and approximately 15 GB across thirty days, before actual record overhead/retention. Price writes, memory GB-hours, magnetic GB-months and the selected query-capacity model separately; counts of queries alone are not a complete bill. Use [[AWS/reliability/backup-and-recovery|recovery planning]] for durable exports/retention rather than treating expiry as a backup.

## Single-measure data and a valid write

```text
record identity: dimensions + measure name + timestamp
record value: typed measure value
Version: increasing revision for supported upsert
```

For an eligible LiveAnalytics account, this SDK example writes to the sandbox_timeseries/readings table created earlier. It avoids repeating the same dimension in both record and CommonAttributes.

```python
import time
import boto3

writer = boto3.client("timestream-write")
record_time = str(time.time_ns() // 1_000_000)  # Capture ONCE for this identity.
record = {
    "Dimensions": [{"Name": "device_id", "Value": "sandbox-sensor"}],
    "MeasureName": "temperature",
    "MeasureValue": "22.5",
    "MeasureValueType": "DOUBLE",
    "Time": record_time,
    "TimeUnit": "MILLISECONDS",
    "Version": 1,
}

def write(reading):
    return writer.write_records(
        DatabaseName="sandbox_timeseries", TableName="readings", Records=[reading]
    )

write(record)
write({**record, "MeasureValue": "23.0", "Version": 2})
try:
    write({**record, "MeasureValue": "99.0", "Version": 1})
except writer.exceptions.RejectedRecordsException as error:
    rejected = error.response["RejectedRecords"]
    assert rejected[0]["RecordIndex"] == 0
    assert rejected[0]["ExistingVersion"] == 2
    print("Expected stale revision rejection; Version 2 remains current")
else:
    raise AssertionError("Expected stale same-identity revision to be rejected")

sql = f"""SELECT time, measure_value::double AS temperature
FROM sandbox_timeseries.readings
WHERE device_id = 'sandbox-sensor' AND measure_name = 'temperature'
  AND time = from_milliseconds({record_time})"""
print(sql)  # Run through timestream-query with bounded retries below.
```

Keep dimensions, measure name and `record_time` unchanged across all three requests. Re-running the entire block captures a different timestamp and normally creates another record; it does not demonstrate updating the prior record. Query the printed exact-identity SQL and expect temperature 23.0, not 99.0. LiveAnalytics reads are eventually consistent: allow bounded retry/backoff (for example at most five queries over thirty seconds), then report unresolved visibility rather than looping indefinitely. Confirm exactly one identity row, not an average across both versions or all historical readings. The [write/upsert contract](https://docs.aws.amazon.com/timestream/latest/APIReference/API_WriteRecords.html) and [timestamp conversion functions](https://docs.aws.amazon.com/timestream/latest/developerguide/date-time-functions.html) own these behaviors. This SDK sequence is an eligible-account proposal, not an executed AWS lab.

Writes can return rejected-record information; inspect reasons/indices and do not retry permanently invalid data indefinitely. Multi-measure records have a different shape and query columns, so do not copy single-measure SQL unchanged.

## Query, time-binning and interpolation workflow

Use the time column and measure_value type appropriate to the write model, rather than invented timestamp/temperature columns:

```sql
SELECT device_id,
       bin(time, 5m) AS interval_start,
       avg(measure_value::double) AS average_temperature
FROM sandbox_timeseries.readings
WHERE measure_name = 'temperature'
  AND time > ago(1h)
GROUP BY device_id, bin(time, 5m)
ORDER BY device_id, interval_start;
```

For interpolation, first construct a supported time-series value from time plus the measure value, then interpolate over a valid timestamp sequence within bounds. Inspect gaps and sampling frequency before fabricating values; an interpolated sensor series is an analytical estimate, not a raw reading.

Memory retention provides hot data access and magnetic retention longer-lived data. Scheduled queries can materialize derived tables through configured roles/notifications; their output schema/recovery is a separate design, not automatic S3 archiving. For MQTT, use the current IoT rule-action contract directly if supported; the old IoT Analytics bridge is not a generic current prerequisite.

## Monitoring and comparison with InfluxDB

Track write/query failures, latency, rejection reasons and capacity/retention behavior through supported telemetry. Watch late/out-of-retention records and the query model actually selected. A metric name invented in an old table is not evidence of availability.

InfluxDB has different engine/provisioning/client/backup responsibilities. Evaluate API/language compatibility, network/auth, retention and cost separately rather than presenting two products as storage tiers of one database. New customers should use the supported eligible product workflow, while the LiveAnalytics example remains explicitly existing-customer scoped.

## References

- [Availability changes](https://aws.amazon.com/about-aws/whats-new/2025/05/aws-service-changes/)
- [Timestream variants](https://aws.amazon.com/timestream/faqs/)
- [LiveAnalytics quotas](https://docs.aws.amazon.com/timestream/latest/developerguide/ts-limits.html)
- [WriteRecords/upsert contract](https://docs.aws.amazon.com/timestream/latest/developerguide/API_WriteRecords.html)
- [SQL reference](https://docs.aws.amazon.com/timestream/latest/developerguide/reference.html)
- [Timestream pricing](https://aws.amazon.com/timestream/pricing/)

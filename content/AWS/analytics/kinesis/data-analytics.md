---
title: Kinesis Data Analytics
description: Kinesis Data Analytics — real-time stream processing with SQL or Apache Flink, windows, joins, reference data, and use cases
tags:
  - aws
  - analytics
  - kinesis
---

# Kinesis Data Analytics

Kinesis Data Analytics is a managed stream processing service. You write SQL queries (or Apache Flink applications) against Kinesis Data Streams or Firehose, and the service processes data in real-time — continuously running queries that output results to destinations.

## Two Processing Options

### SQL Applications

Write standard SQL against input streams. The SQL runtime handles ordering, windowing, and state management. Simpler than Flink, covers 80% of use cases.

### Apache Flink

Write Java, Scala, or Python applications using the Flink framework. Full Flink API including complex event processing, custom state management, and exact-once semantics. For advanced streaming use cases.

## How SQL Processing Works

### Input Streams

You connect one or more Kinesis data streams as inputs to your SQL application. Each shard maps to a parallel SQL query instance.

```
Input Stream (Kinesis)
  ├── Shard 1 → SQL Query Instance 1 (processes shard 1 data)
  ├── Shard 2 → SQL Query Instance 2 (processes shard 2 data)
  └── Shard 3 → SQL Query Instance 3 (processes shard 3 data)
```

Each instance maintains its own state and runs the same SQL query. Kinesis Data Analytics automatically distributes query execution across shard instances.

### Reference Data

You can enrich stream data with reference data stored in S3 (CSV, JSON). Reference data is loaded into in-memory tables and joined with stream data at query time.

```sql
CREATE STREAM enriched_events AS
SELECT 
  s.event_id,
  s.user_id,
  s.action,
  r.user_name,
  r.plan_type,
  s.event_time
FROM source_stream s
LEFT JOIN reference_table r
  ON s.user_id = r.user_id;
```

The reference table is refreshed periodically from S3. Use this for dimension lookups (user profiles, product catalogs, geo data).

## Windowed Queries

Kinesis Data Analytics supports standard SQL window functions with tumbling, sliding, and session windows.

### Tumbling Windows (fixed size, non-overlapping)

```sql
CREATE STREAM pageview_counts AS
SELECT 
  STEP(s.timestamp) AS window_end,
  page_url,
  COUNT(*) AS view_count,
  COUNT(DISTINCT user_id) AS unique_users
FROM source_stream
GROUP BY STEP(s.timestamp), page_url;
```

`STEP()` defines a tumbling window that aligns to fixed time boundaries. Every 5 minutes, results are emitted for the previous 5-minute window.

### Sliding Windows (overlapping, with slide interval)

```sql
SELECT 
  FLOOR(s.timestamp TO HOUR) AS window_start,
  product_id,
  SUM(sale_amount) AS total_sales,
  AVG(sale_amount) AS avg_sale
FROM sales_stream
GROUP BY FLOOR(s.timestamp TO HOUR), product_id;
```

### Session Windows (activity-based)

Session windows close after a period of inactivity. Useful for user sessionization:

```sql
-- Session window: group events with gap > 30 seconds = new session
SELECT 
  user_id,
  SESSION_TIMESTAMP AS session_start,
  SESSION_RUNTIME() AS session_duration,
  COUNT(*) AS events_in_session
FROM user_events
GROUP BY user_id, SESSION(gap => INTERVAL '30' SECOND);
```

## Stream-to-Stream Joins

Kinesis Data Analytics supports JOINs between two input streams. This enables correlation of events from different sources:

```sql
-- Correlate page views with purchases (within 1 hour)
CREATE STREAM purchase_after_view AS
SELECT 
  v.user_id,
  v.page_url,
  p.purchase_id,
  p.purchase_amount
FROM page_views v
LEFT JOIN purchases p
  ON v.user_id = p.user_id
  AND FLOOR(v.event_time TO HOUR) = FLOOR(p.event_time TO HOUR)
  AND p.event_time BETWEEN v.event_time AND v.event_time + INTERVAL '1' HOUR;
```

**Important:** JOINs between streams require a watermark strategy for handling late data. Records older than the watermark are dropped from the join window.

## Output Destinations

SQL results can be written to:
- **Kinesis Data Streams** — for chaining multiple analytics applications
- **Kinesis Data Firehose** — for delivery to S3, Redshift, Elasticsearch
- **Lambda** — for custom processing and alerts
- **Kinesis Data Analytics for Apache Flink** — as input to Flink applications

## Exactly-Once Semantics

Kinesis Data Analytics provides exactly-once delivery to output destinations when combined with Kinesis Data Streams (not Firehose). This means:
- Each input record is processed exactly once
- Output records are delivered exactly once
- No duplicate results from reprocessing

**Limitation:** When outputting to Firehose or Lambda, only at-least-once semantics are guaranteed. Firehose and Lambda destinations can receive duplicates. Design your downstream consumers to handle duplicate records (use deduplication keys).

## Use Cases

### Real-time Metrics and Dashboards

```sql
-- Rolling average response time by API endpoint, per minute
CREATE STREAM api_latency AS
SELECT 
  STEP(event_time TO MINUTE) AS minute,
  api_endpoint,
  AVG(response_time_ms) AS avg_latency,
  PERCENTILE_APPROX(response_time_ms, 0.95) AS p95_latency,
  COUNT(*) AS request_count
FROM api_requests
GROUP BY STEP(event_time TO MINUTE), api_endpoint;
```

### Anomaly Detection

```sql
-- Alert when error rate exceeds 5% in a 5-minute window
CREATE STREAM error_alerts AS
SELECT 
  STEP(event_time TO MINUTE) AS window,
  service_name,
  COUNT(*) AS total_requests,
  SUM(CASE WHEN status >= 500 THEN 1 ELSE 0 END) AS error_count,
  CAST(SUM(CASE WHEN status >= 500 THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(*) AS error_rate
FROM api_requests
GROUP BY STEP(event_time TO MINUTE), service_name
HAVING CAST(SUM(CASE WHEN status >= 500 THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(*) > 0.05;
```

### Sessionization

```sql
-- User sessions with timeout of 5 minutes
CREATE STREAM user_sessions AS
SELECT 
  user_id,
  SESSION_TIMESTAMP AS session_start,
  COUNT(*) AS events,
  MAX(event_time) AS session_end,
  SESSION_RUNTIME() AS duration_seconds
FROM user_events
GROUP BY user_id, SESSION(gap => INTERVAL '5' MINUTE);
```

## Monitoring

CloudWatch metrics for Kinesis Data Analytics:
- `BytesReceived` — input data volume
- `RecordsReceived` — input record count
- `BytesProcessed` — data processed by the application
- `RecordsProcessed` — records processed
- `Hostname` — number of KCU (Kinesis Processing Units) being used
- `InputDataBytes` / `OutputDataBytes` — throughput tracking

**Duration metric:** `Duration` shows end-to-end processing time from input to output. High duration means the application is falling behind.

## Application Lifecycle

### In-Application Streams and Pumps

In Kinesis Data Analytics terminology:
- **In-application stream:** An intermediate stream created by a SQL query (virtual, not a Kinesis stream)
- **Pump:** The continuous query that reads from an input and writes to an in-application stream

You chain these together: input stream → pump → in-application stream → pump → output stream.

### Checkpointing

Kinesis Data Analytics continuously checkpoints application state (window state, join state) to S3. If the application restarts, it resumes from the last checkpoint, not from the beginning of the stream.

### Application Updates

You can update a running SQL application without data loss. Kinesis Data Analytics performs a rolling update, maintaining the checkpoint state while applying the new query logic.

## Limits

- Maximum 1,000 input shards per application
- Maximum 1,000 in-application streams per application
- Maximum application runtime: unlimited (no timeout)
- SQL query result row size: max 512KB
- Reference data file size: max 1GB (loaded into memory)

## References

- **Homepage:** https://aws.amazon.com/kinesis/data-analytics/
- **Documentation:** https://docs.aws.amazon.com/kinesisanalytics/latest/dev/
- **Pricing:** https://aws.amazon.com/kinesis/data-analytics/pricing/

## Pricing Examples

**Scenario 1:** A real-time fraud detection application with Kinesis Data Analytics (SQL). Ingesting 1M events/day, running a 10-minute sliding window aggregation. 1 Kinesis Processing Unit (KPU): $0.11/hr. Monthly: $0.11 × 720 = $79.20/month. vs a Spark Streaming job on EMR (3 m5.xlarge nodes): ~$450/month. KDA SQL is5x cheaper for this use case.

**Scenario 2:** A real-time ETL pipeline: IoT sensor data → Kinesis → KDA (SQL) → Firehose → S3 → Athena. 500GB/day throughput. KDA10 KPU (10MB/s): $0.11 × 10 × 720 = $792/month. EMR Spark Streaming equivalent: ~$1,200/month. KDA saves ~$400/month but has SQL limitations for complex joins.

## Nuggets& Gotchas

- **KDA SQL doesn't support all SQL features:** No CTEs (WITH clause), limited window functions compared to standard SQL. Complex analytics often need Apache Flink instead.
- **In-application streams are separate from input streams:** You can pump data from one in-application stream to another for multi-stage processing. But if you misconfigure the pump, data flows forever with no backpressure mechanism.
- **Reference data is loaded into memory:** Max 1GB reference data loaded into each KPU's memory. Large reference datasets (e.g., a 5GB product catalog) won't fit. Use S3-backed lookups instead (query S3 on each row, slower but scalable).
- **KDA Flink is a separate runtime from KDA SQL:** If you need Flink features (exactly-once semantics, complex event processing, custom watermarks), you use the Apache Flink runtime which has different pricing (KPU-based, same as SQL) but different operational complexity.
- **Checkpointing to S3 means you're paying S3 costs for state storage:** For applications with large window state (e.g., session windows with 24-hour sessions), the checkpoint data in S3 can be significant. Monitor S3 costs for state snapshots.
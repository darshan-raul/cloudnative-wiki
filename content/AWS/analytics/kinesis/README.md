---
title: Amazon Kinesis
description: "Amazon Kinesis - real-time data streaming services: Data Streams for real-time ingestion, Data Firehose for managed delivery to S3/Redshift, and Data Analytics for SQL/Flink stream processing"
tags:
  - aws
  - analytics
  - kinesis
---

# Amazon Kinesis

Kinesis is AWS's real-time data streaming platform. Three services cover different parts of the streaming pipeline:

```
Data Sources (IoT, Logs, Events, Clicks)
    ↓
Kinesis Data Streams     ← Ingest and process real-time
    ↓
Kinesis Data Firehose   ← Deliver to S3/Redshift/OpenSearch (managed, no custom code)
    ↓
Kinesis Data Analytics  ← SQL/Flink queries on streams
```

## Services at a Glance

| Service | Use When | Key Benefit |
|---------|----------|-------------|
| **Data Streams** | You need real-time consumers, replay, custom processing | Full control, exactly-once, consumer groups |
| **Data Firehose** | You just need data delivered to S3/Redshift | Fully managed, no consumer apps needed |
| **Data Analytics** | You want to query streams with SQL | Managed SQL/Flink, no cluster to manage |

## Data Streams vs Firehose

```
Kinesis Data Streams:
  Producer → Stream (shards) → Consumer (KCL/KPL) → Processing
  You manage: shard count, consumer apps, scaling

Kinesis Data Firehose:
  Producer → Firehose → Buffer → Transform (optional) → S3/Redshift/OpenSearch
  You manage: nothing — AWS handles buffering, delivery, retries
```

**Common pattern:** Data Streams for real-time processing + Firehose for durable S3 archival. Use Data Streams when you need to consume and process data in real-time. Use Firehose when you just need to land data in storage with minimal latency.

## Kinesis Data Streams

- **Shards:** Throughput unit. 1MB/s ingress, 2MB/s egress, 1,000 records/s per shard.
- **Producers:** KPL (Producer Library) for high-throughput, batching, aggregation.
- **Consumers:** KCL (Consumer Library) for automatic shard distribution, checkpointing, lease management.
- **Enhanced fan-out:** Dedicated 2MB/s per consumer (vs shared 2MB/s in standard).
- **Scaling:** Split or merge shards, or use on-demand mode for auto-scaling.
- **Retention:** 24 hours default, up to 365 days with extended retention.
- **Max record size:** 1MB.

## Kinesis Data Firehose

- **Buffer:** Configurable size (1-128MB) and interval (60-900s). Delivery triggers when either is reached.
- **Destinations:** S3, Redshift (via S3 staging), Elasticsearch, Splunk, HTTP endpoint.
- **Transformation:** Lambda invoked on each batch for transformation before delivery.
- **Formats:** JSON, CSV, Parquet, ORC. Parquet recommended for analytical queries.
- **No replay:** Firehose is append-only, no way to replay from a timestamp.

## Kinesis Data Analytics

- **SQL applications:** Write standard SQL against input streams. Tumbling, sliding, session windows.
- **Apache Flink:** Full Flink API for complex event processing, custom state management.
- **Reference data:** Enrich stream data with S3-hosted lookup tables (user profiles, product catalog).
- **Windows:** `STEP()` for tumbling, `FLOOR(timestamp TO HOUR)` for sliding, `SESSION(gap => INTERVAL)` for session.
- **Output:** Kinesis Streams, Firehose, Lambda.
- **Checkpointing:** Automatic checkpoint to S3 for fault tolerance and exactly-once semantics.
- **Exactly-once:** Guaranteed with Kinesis Streams destination. At-least-once with Firehose/Lambda.

## Partition Key Strategy

Partition key determines which shard a record goes to:

```
Low cardinality (e.g., "all-events") → one shard → bottleneck
High cardinality (e.g., user_id, device_id) → even distribution → scales
```

For time-series data, include a time component in the partition key if you need ordering within a time window, or use a UUID if ordering doesn't matter.

## Cost Optimization

- **Aggregation (KPL):** Combine multiple application records into one Kinesis record → more records per second per shard.
- **On-demand mode:** Pay per stream-hour and per MB, auto-scales. Good for variable workloads.
- **Enhanced fan-out:** Additional cost per shard-hour and per GB delivered. Only use when multiple consumers need dedicated throughput.
- **Firehose buffer tuning:** Larger buffers (128MB, 900s) reduce S3 write frequency and cost.

## Common Architecture Patterns

### Lambda Architecture (classic)
```
Kinesis Streams → Kinesis Analytics (real-time) → DynamoDB/Kinesis Firehose
S3 → Glue → Redshift (batch layer)
Merge at query time (Athena, Redshift)
```

### Kappa Architecture (simplified)
```
Kinesis Streams → Kinesis Analytics → Kinesis Firehose → S3
S3 as immutable log — no separate batch layer
Re-process by seeking to beginning of stream
```

### Event Sourcing
```
User actions → Kinesis Streams → multiple consumers
  ├── Fraud detection (Lambda)
  ├── Personalization engine (Lambda)
  ├── Audit log archival (Firehose → S3)
  └── Real-time dashboards (Kinesis Analytics)
```
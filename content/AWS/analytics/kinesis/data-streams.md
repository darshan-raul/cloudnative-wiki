---
title: Kinesis Data Streams
description: Kinesis Data Streams — shards, producers, consumers, enhanced fan-out, scaling, capacity planning, and use cases
tags:
  - aws
  - analytics
  - kinesis
---

# Kinesis Data Streams

Kinesis Data Streams is AWS's real-time ingestion service. You push data records into a stream, and consumers read and process them with sub-second latency. It's the foundation of most real-time AWS data architectures.

## Core Concepts

### Stream

A stream is the top-level resource. You configure its shard count, and AWS provisions underlying storage and throughput capacity.

**Data flow:**
```
Producer → Record (partition key + data) → Stream (ordered per shard) → Consumer
```

### Shard

A shard is the throughput unit. Each shard supports:
- **1 MB/second** ingress (producer writes)
- **2 MB/second** egress (consumer reads)
- **1,000 records/second** write throughput

**Partition key:** When a producer writes a record, it specifies a partition key. Records with the same partition key always go to the same shard. This ensures ordering for records with the same key.

**Sequence number:** Each record gets an auto-incrementing sequence number within its shard. Consumers can use this for exactly-once processing or resume after failure.

### Records

A record has three components:
- **Partition key** — determines which shard handles the record
- **Data blob** — your payload (up to 1 MB)
- **Sequence number** — assigned by Kinesis, unique per shard

## Producers

Producers inject data into a stream. The SDK provides low-level and high-level (KPL) interfaces.

### KPL (Kinesis Producer Library)

The KPL is a higher-level library with batching, retries, and metrics built in:

```python
from amazon_kinesis_producer import KinesisProducer
import json

producer = KinesisProducer(firehose=True, aggregation=True)

# Aggregation: multiple user records combined into one Kinesis record
# This increases the number of records per shard without increasing MB/s
for event in events:
    producer.add_record(
        stream_name='my-stream',
        partition_key=str(event['user_id']),
        data=json.dumps(event).encode('utf-8')
    )

producer.flush()
```

**Key features:**
- **Aggregation:** Combine multiple application records into one Kinesis record → more records per second per shard
- **Batching:** KPL batches records and uses HTTP chunked transfer to maximize throughput
- **CloudWatch metrics:** Emits `UserRecordsPut`, `BytesPut`, `ErrorsByType`

### KCL (Kinesis Consumer Library)

The KCL abstracts consumer group management — checkpointing, lease management, and shard distribution across consumer instances.

```python
from amazon_kinesis_library import KinesisClientLibrary

kcl = KCL(
    application_name='my-consumer',
    stream_name='my-stream',
    initial_position_in_stream=InitialPositionInStream.LATEST,
    checkpoint_filename='/tmp/checkpoint'
)

# KCL handles: shard assignment, checkpointing, lease expiry
# Run multiple instances for parallel consumption
```

**How it works:**
1. KCL leases shards to consumer instances
2. Each instance processes its assigned shards
3. Checkpoints are stored in DynamoDB (you provide the table)
4. If an instance dies, KCL reassigns its shards to surviving instances

## Enhanced Fan-Out

Standard consumers share read throughput across all consumers — 2MB/s per shard divided among all consumers. Enhanced fan-out gives each consumer its own 2MB/s per shard.

**Use when:**
- Multiple consumer applications read from the same stream
- A consumer needs dedicated throughput (e.g., real-time dashboard + batch processor)
- Latency requirements are strict (< 100ms from write to read)

**How it works:**
- Push-based delivery to registered consumers via HTTP/2
- Each enhanced fan-out consumer registers with a consumer name
- Kinesis delivers records directly to the consumer's registered endpoint

**Cost:** Enhanced fan-out is charged per shard-hour and per GB of data delivered. Standard consumers share the 2MB/s per shard at no extra charge.

## Capacity Planning

### Shard Estimation

```
Required shards = max(
  peak_records_per_second / 1000,
  peak_MB_per_second / 1
)

Example:
- 5,000 records/sec at 2KB each = 10 MB/sec
- Shards needed = max(5000/1000, 10/1) = max(5, 10) = 10 shards
```

### On-Demand vs Provisioned

**On-demand mode:**
- AWS automatically scales shard count based on incoming traffic
- Pay per stream-hour and per payload MB
- Simpler, no capacity planning needed
- Good for variable/unpredictable workloads

**Provisioned mode:**
- You specify shard count manually
- Pay per shard-hour
- You manage scaling (increase shards before traffic spikes)
- Good for predictable, stable workloads

**Scaling operations:**
- **Split:** One shard → two shards (divide traffic, increase capacity)
- **Merge:** Two shards → one shard (combine traffic, reduce cost)
- Both are async, take time to complete
- On-demand streams auto-scale, no manual split/merge needed

## Use Cases

**Real-time analytics:** Web analytics events → Kinesis → Kinesis Data Analytics (Flink/SQL) → real-time dashboards

**Log aggregation:** Application logs → Kinesis → S3 via Firehose → Athena for querying

**Event sourcing:** User actions → Kinesis → multiple consumers (fraud detection, personalization, archive)

**ETL streaming:** IoT sensor data → Kinesis → Lambda (transform) → Kinesis Data Firehose → Redshift

## Limits and Gotchas

- **Record lifetime:** Records are accessible for 24 hours (default) up to 365 days (extended retention)
- **Max record size:** 1 MB payload (partition key can be up to 256 bytes)
- **Provisioned throughput exceeded:** `ProvisionedThroughputExceededException` — add shards or enable on-demand
- **Consumer lag:** If consumer can't keep up with producer, records age out and are lost — monitor `MillisBehindLatest` CloudWatch metric
- **Replaying:** Set `StartingPosition` to `TRIM_HORIZON` or timestamp to replay from beginning or a specific time
- **Partition key cardinality:** Low cardinality keys (e.g., "all-events") concentrate all traffic in one shard — use high-cardinality keys (e.g., user_id, device_id)

## References

- **Homepage:** https://aws.amazon.com/kinesis/data-streams/
- **Documentation:** https://docs.aws.amazon.com/streams/latest/dev/
- **Pricing:** https://aws.amazon.com/kinesis/data-streams/pricing/

## Pricing Examples

**Scenario 1:** A real-time analytics pipeline processing 10M events/day with5 shards. Each shard: $0.015/hr. 5 shards × $0.015 × 24 × 30 = $54/month for shards + data PUT fees (~$0.014/GB/month at typical event size). Total: ~$75-100/month. Compare to Kafka managed (MSK): ~$0.10/shard-hour for MSK, similar cost but more operational overhead.

**Scenario 2:** A startup building a live dashboard with1 shard, ingesting 500K events/day (avg 1KB/event = 0.5GB/day). Monthly shard cost: $0.015 × 720hr = $10.80/month. Data PUT:0.5GB × 30 =15GB × $0.014 = $0.21/month. Total: ~$11/month. Plus S3 costs for the Firehose backup if used.

## Nuggets& Gotchas

- **Shard count is the bottleneck:** Each shard supports 1MB/s write and 2MB/s read. If your producers exceed shard capacity, you'll get `ProvisionedThroughputExceededException`. Right-size shard count before launch.
- **Enhanced fan-out costs more per consumer:** Enhanced fan-out (KCL with `ENHANCED_FAN_OUT`) adds $0.015/shard-hour per consumer. With 3 consumers, a 5-shard stream costs 5 × ($0.015 + 3 × $0.015) = $0.30/shard-hour vs $0.075 without fan-out.
- **On-demand scaling has a 4x multiplier:** When you enable on-demand mode, each shard supports 1MB/s write — same as provisioned. But you pay per streaming unit (1MB/s) at $0.015/hour. You can't just add 1 streaming unit; you add in4x increments.
- **Records older than the retention period are lost:** Default retention is 24 hours. If your consumer goes down for 2 days,2 days of data are gone. Set retention to 365 days if replay or consumer downtime is a concern.
- **Provisioned throughput doesn't auto-scale:** You pre-allocate shards. If traffic grows beyond your allocation, you get throttled. Either manage shard splitting/merging manually or use on-demand mode.
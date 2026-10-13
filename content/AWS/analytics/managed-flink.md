---
title: "Managed Service for Apache Flink"
description: "Design stateful stream processing with event time, checkpoints, compatible connectors and bounded replay/failure tests."
tags:
  - cloud/aws/analytics
date: 2026-10-12
---

# Managed Service for Apache Flink

Managed Service for Apache Flink runs supported Flink applications; Studio offers an interactive development path. It is distinct from [[AWS/analytics/kinesis/data-analytics|the retired Kinesis SQL product]]. Start with [[AWS/analytics/kinesis/data-streams|stream ingestion]].

## Processing decisions

Choose DataStream/Table/SQL APIs according to state, timers, connectors and operational requirements. Pin the supported runtime and matching connector versions. Event time is the event's timestamp; processing time is when an operator handles it. Watermarks and late-event handling define what a window result means.

Partition keys and operator parallelism determine hotspots and state distribution. Monitor backpressure, checkpoint duration/failures, input lag and output correctness; increasing compute cannot fix every downstream bottleneck.

Checkpoints capture state for recovery. Exactly-once is scoped to the source/state/sink protocol; an HTTP request, email or non-transactional downstream write can repeat after recovery. Use idempotency or a compatible transactional sink where required.

## Advanced experiment specification: event-time windowing, watermarks, and checkpoints

This specification defines the input fixture, windowing semantics, and expected outputs for stateful verification. Deploying this experiment in Amazon Managed Service for Apache Flink requires building the official [Java DataStream application](https://docs.aws.amazon.com/managed-flink/latest/java/getting-started.html) with Maven, packaging a JAR, uploading to an S3 artifacts bucket, and creating the application with `aws kinesisanalyticsv2 create-application`.

### Fixed input fixture

Use a dedicated Kinesis input stream or local test generator publishing these five JSON records with millisecond epoch timestamps:

| Event ID | Sensor ID  | Temperature | Event time (`event_time_ms`) | Clock time (UTC) | Category                         |
| -------- | ---------- | ----------- | ---------------------------- | ---------------- | -------------------------------- |
| `e-1`    | `sensor-1` | 20.0        | `1700000000000`              | 00:00:00.000     | In-order                         |
| `e-2`    | `sensor-1` | 22.0        | `1700000015000`              | 00:00:15.000     | In-order                         |
| `e-3`    | `sensor-1` | 22.0        | `1700000015000`              | 00:00:15.000     | Duplicate of `e-2`               |
| `e-4`    | `sensor-1` | 24.0        | `1700000045000`              | 00:00:45.000     | In-order                         |
| `e-5`    | `sensor-1` | 18.0        | `1700000005000`              | 00:00:05.000     | Late event (arrives at 00:01:10) |

### Stream pipeline configuration

1. **Watermark Strategy**:
   - Out-of-orderness allowance: **5 seconds** (`Duration.ofSeconds(5)`).
   - Watermark generator: `WatermarkStrategy.forBoundedOutOfOrderness(Duration.ofSeconds(5)).withTimestampAssigner(...)`.
2. **Deduplication Operator**:
   - `KeyedProcessFunction` keyed by `sensor_id` tracking recently processed event IDs in Flink managed `ValueState` with a 10-minute state TTL.
   - Drops `e-3` before window aggregation.
3. **Window Assignment**:
   - 1-minute tumbling event-time window: `TumblingEventTimeWindows.of(Time.minutes(1))`.
   - Window range: `[1700000000000, 1700000060000)` (00:00:00 to 00:01:00).
4. **Late Data Policy**:
   - Routed to a dedicated side-output: `.sideOutputLateData(new OutputTag<Reading>("late-events") {})`.

### Expected output reconciliation

- **Window `[00:00:00, 00:01:00)` output**:
  - Events aggregated: `e-1` (20.0), `e-2` (22.0), `e-4` (24.0).
  - Deduplicated count: **3** (duplicate `e-3` filtered).
  - Average temperature: **22.0**.
  - Window trigger fires when the watermark passes `00:01:00` (driven by subsequent records).
- **Side output stream (`late-events`)**:
  - Emits late record `e-5` (event time 00:00:05, received after watermark passed 00:01:00).
  - Confirms late data was segregated rather than corrupting the closed window.

### Checkpoint and restart validation

1. Enable RocksDB incremental checkpoints at a 60-second interval (`CheckpointingMode.EXACTLY_ONCE`).
2. Trigger an application snapshot before updating code:
   ```bash
   aws kinesisanalyticsv2 create-application-snapshot \
     --application-name dg11-flink-lab \
     --snapshot-name checkpoint-v1
   ```
3. Stop the application, update the application configuration to restore from `checkpoint-v1`, and restart.
4. Verify from CloudWatch metrics (`lastCheckpointDuration`, `numLateRecordsDropped`, `downtime`) that the deduplication state persisted: resending `e-2` does not produce a new count.
5. Cleanup: stop and delete the application (`delete-application`), delete application snapshots (`delete-application-snapshot`), and remove dedicated S3 JAR artifacts and Kinesis streams.

## Cost and migration

Size compute/state from a representative workload and include running capacity, application/storage/backup and ingestion/sink charges. Compare state growth, replay cost and recovery time rather than only events per second. A legacy SQL migration must validate windows and external delivery, not just translate query syntax.

## References

- [Service and API choices](https://docs.aws.amazon.com/managed-flink/latest/java/what-is.html).
- [Getting started](https://docs.aws.amazon.com/managed-flink/latest/java/getting-started.html).
- [Fault tolerance](https://docs.aws.amazon.com/managed-flink/latest/java/how-fault.html).
- [Pricing](https://aws.amazon.com/managed-service-apache-flink/pricing/).

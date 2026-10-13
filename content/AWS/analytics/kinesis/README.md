---
title: "Amazon Kinesis and streaming choices"
description: "A stream is a replayable event log, not a work queue whose messages vanish after one consumer receives them."
tags:
  - aws/analytics
date: 2026-10-12
---

# Amazon Kinesis and streaming choices

A stream is a replayable event log, not a work queue whose messages vanish after one consumer receives them. Start with [[AWS/analytics/README|analytics]], [[AWS/security/iam/README|IAM]] and [[AWS/storage/s3/README|S3]].

## Service boundaries

| Lesson                                                        | Purpose                                                                             |
| ------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| [[AWS/analytics/kinesis/data-streams\|Kinesis Data Streams]]  | Event retention/replay with independently progressing consumers.                    |
| [[AWS/analytics/kinesis/data-firehose\|Amazon Data Firehose]] | Managed buffered delivery to supported destinations; firehose API name unchanged.   |
| [[AWS/analytics/managed-flink\|Managed Apache Flink]]         | Stateful continuous processing/windows with connector-specific delivery semantics.  |
| [[AWS/analytics/msk\|MSK]]                                    | Managed Kafka for supported Kafka ecosystems.                                       |
| [[AWS/analytics/kinesis/data-analytics\|Retired Kinesis SQL]] | Historical migration context only; SQL application deletion began January 27, 2026. |

## Partitioning, checkpoints and duplicates

A partition key directs records to shards; ordering is scoped to the supported shard/key behavior, not automatically global. Avoid hot keys and size sustained throughput by bytes and records. Consumers checkpoint progress independently; replay requires retention long enough for outages/backfills.

Kinesis and historical Kinesis SQL external delivery can produce duplicates. Flink state/checkpoints do not alone certify exactly-once effects in every external sink. Include event IDs, idempotent writes and connector-specific transaction/retry semantics in the design.

## Buffered delivery versus processing

Firehose can transform through Lambda and perform supported JSON-to-Parquet/ORC conversion before delivery. Destination-specific buffering can include zero seconds where supported; S3 backup and dynamic partitioning have different restrictions. It is not a general arbitrary-language processing engine or a durable consumer checkpoint service.

Choose a direct stream consumer for custom replay/control, Firehose for managed delivery and Flink for stateful/event-time processing. Event sourcing requires durable retention/snapshots and domain semantics beyond simply selecting Kinesis.

## Streaming exercise

Produce a small synthetic sequence with event IDs and event timestamps. Compare direct stream consumption with a delivery path into S3. Inject a repeated event and delayed event; verify ordering scope, observed duplicates and application idempotency.

Stop/restart a consumer in a sandbox and measure replay/lag from its checkpoint. Test unauthorized reading, monitor throttling/delivery failures and establish an explicit budget. Remove streams, consumers, delivery resources, output files and Flink/MSK compute created for the exercise.

## Partition-key strategy and architecture comparisons

```text
same customer key → stable partition mapping at a point in time
different consumers → independent checkpoints and processing lag
resharding/retries → ordering and duplicate handling remain explicit
```

Choose a key with enough distribution for sustained traffic while preserving the ordering the application actually needs. A single tenant key can become hot; randomizing every key can destroy useful per-entity order. Shard changes and producer retry strategies mean “globally ordered exactly once” is not a default stream property.

| Requirement                          | Data Streams              | Firehose                                   | Managed Flink                                     |
| ------------------------------------ | ------------------------- | ------------------------------------------ | ------------------------------------------------- |
| Read from a chosen retained position | Consumer-controlled       | No general consumer replay interface       | Depends on source/checkpoint/state configuration. |
| Custom consumer logic                | Your application/KCL      | Supported transform/delivery configuration | Stateful application with supported connectors.   |
| Buffered storage delivery            | Build/configure a sink    | Managed destination delivery               | Connector/application responsibility.             |
| Windowed event-time aggregation      | Build a processor         | Not the central abstraction                | Natural supported use case.                       |
| Scaling responsibility               | Mode/shards and consumers | Service configuration/quotas               | Application parallelism and state behavior.       |

For event sourcing, define the durable system of record and reconstruction process. Kinesis retention alone is not perpetual business history. For log aggregation, replayable input plus Firehose/S3 delivery gives different recovery options from direct Firehose-only ingress. Cost includes idle capacity/mode charges, retention, fan-out, dependent tables/metrics and downstream compute, not just event payload size.

## References

- [Stream duplicate handling](https://docs.aws.amazon.com/streams/latest/dev/kinesis-record-processor-duplicates.html)
- [Firehose buffering](https://docs.aws.amazon.com/firehose/latest/dev/create-configure-backup.html)
- [Kinesis SQL discontinuation](https://docs.aws.amazon.com/kinesisanalytics/latest/dev/discontinuation.html)
- [Kinesis pricing](https://aws.amazon.com/kinesis/data-streams/pricing/)

## Across the wiki

- [[Azure/messaging/service-bus/README|Azure Service Bus Architecture, Queues, Topics, and Enterprise Messaging]] — messaging and streaming (Azure)
- [[GCP/analytics/pubsub/README|Cloud Pub/Sub Architecture & Streaming Mechanics]] — messaging and streaming (GCP)
- [[Architecture/solution-architecture-concepts/event-driven-architecture/kafka/README|Apache Kafka]] — messaging and streaming (Architecture)
- [[Azure/messaging/event-hubs/README|Azure Event Hubs Architecture, Kafka Compatibility, and Streaming Ingestion]] — messaging and streaming (Azure)

---
title: Kinesis Data Analytics for SQL (retired)
description: Separate the retired SQL streaming product from current Managed Service for Apache Flink and plan a stateful-streaming migration.
tags:
  - cloud/aws/analytics
  - cloud/aws/legacy
date: 2026-10-12
---

# Kinesis Data Analytics for SQL (retired)

Kinesis Data Analytics for SQL applications was discontinued on **January 27, 2026**. Legacy SQL deployment, pricing and quota instructions are not a current learning lab. The SQL service and the former Flink-branded service must not be treated as one interchangeable runtime.

Use [[AWS/analytics/managed-flink|Amazon Managed Service for Apache Flink]] for supported stateful stream processing after checking source/sink compatibility and Region availability. Flink SQL is not a drop-in promise that an old Kinesis SQL application can run unchanged.

## Migration reasoning

Inventory input schemas, key distribution, windows, time semantics, reference-data updates and external delivery requirements. Test late events, replay, duplicates and failures before cutover.

Flink checkpoints and compatible transactional sinks can provide scoped exactly-once semantics. They do not turn all external sinks into exactly-once business effects. The historical SQL service's external delivery was at least once; design downstream idempotency.

For a migration, compare old and new outputs over a known replay window, define acceptable lag and reconciliation, then switch consumers with a rollback path. Preserve evidence and retained input data for the agreed audit window.

## Historical architecture and processing vocabulary

This section preserves useful concepts from Kinesis Data Analytics SQL, which is retired; it is not active deployment guidance. Current applications should use the supported [[AWS/analytics/managed-flink|Managed Service for Apache Flink]] or another justified processor.

```text
Historical SQL input mapping
  → in-application stream
  → pump (continuous query)
  → intermediate/output stream
  → external destination (duplicates possible)

Current migration:
retained source → supported Flink source
  → keyed state/window/lookup processing
  → supported sink + explicit delivery guarantees
```

An in-application stream was an internal SQL dataflow object, not a separate Kinesis Data Stream. A pump ran a continuous query. Reference data enriched events through a configured loading/update path; do not assume arbitrary S3 updates were automatically refreshed at a fixed period.

## Window and join concepts worth retaining

| Concept          | Definition                                  | Migration test                                        |
| ---------------- | ------------------------------------------- | ----------------------------------------------------- |
| Tumbling window  | Fixed nonoverlapping intervals              | Boundary/timezone and late-event treatment            |
| Sliding window   | Overlapping intervals with chosen advance   | Multiple contributions and expected aggregate count   |
| Session window   | Activity separated by a configured idle gap | Gap semantics and ordering/late sessions              |
| Stream join      | Correlates bounded events from two inputs   | State bounds, timestamps and unmatched/late rows      |
| Reference lookup | Enriches events from a separate dataset     | Version/refresh/failure behavior and join cardinality |

These concepts remain useful, but SQL syntax and time semantics are runtime-specific. STEP, session functions and watermark handling are not interchangeable across historical SQL and Flink runtimes. Describe the desired semantics first, then implement using the supported Flink API/version and connectors.

## Delivery, state and migration reasoning

Checkpointed state is different from exactly-once effects in every external destination. Historical SQL external delivery was at least once, including Kinesis outputs; consumers therefore needed duplicate handling even when the destination was Data Streams.

For migration, inventory source schemas, parallelism, keys, window/state size, reference data, output consumers and idempotency. Replay a bounded representative dataset containing duplicates, out-of-order events and late arrivals; compare totals at window boundaries, not only final counts. Exercise checkpoint restart and destination failure separately.

## Reusable learning examples

An API-latency dashboard needs a defined timestamp, aggregate interval, late-event policy and supported percentile implementation. An error-rate alert needs numerator/denominator, minimum sample policy and how corrections are emitted. Sessionization needs a key, inactivity gap and reconciliation for late activity.

Translate these requirements into supported current operations; don't promise the historical feature covered “80%” of cases or that updates never caused data loss. Retain enough raw input/configuration to explain differences during migration. Monitor source lag, backpressure, checkpoint failures and sink errors using the current processor's actual metrics, not an invented Hostname capacity metric.

AWS began deleting SQL applications January 27, 2026 after stopping creation October 15, 2025. Preserving these concepts/history does not justify restoring obsolete create/update commands or numeric SQL quotas as current recommendations.

## References

- [SQL discontinuation and migration guidance](https://docs.aws.amazon.com/kinesisanalytics/latest/dev/discontinuation.html).
- [Managed Service for Apache Flink introduction](https://docs.aws.amazon.com/managed-flink/latest/java/what-is.html).

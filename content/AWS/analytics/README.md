---
title: "AWS Analytics"
description: "An analytical system ingests events/files, stores governed datasets, computes results and exposes them to consumers."
tags:
  - aws/analytics
date: 2026-10-12
---

# AWS Analytics

An analytical system ingests events/files, stores governed datasets, computes results and exposes them to consumers. Choose latency, replay, data format and authorization before selecting services. Start with [[AWS/storage/s3/README|S3]], [[AWS/security/iam/README|IAM]] and [[AWS/architecture/data-store-selection|data-store selection]].

## Learning path

| Lesson                                                                | Boundary it owns                                                          |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| [[AWS/analytics/kinesis/README\|Streaming fundamentals]]              | Replay, partitioning, consumer checkpoints and duplicates.                |
| [[AWS/analytics/kinesis/data-streams\|Kinesis Data Streams]]          | Durable event stream with consumers.                                      |
| [[AWS/analytics/kinesis/data-firehose\|Amazon Data Firehose]]         | Managed buffered delivery and supported transformations/destinations.     |
| [[AWS/analytics/managed-flink\|Managed Service for Apache Flink]]     | Stateful streaming windows/checkpoints and connector-specific guarantees. |
| [[AWS/analytics/msk\|Amazon MSK]]                                     | Managed Kafka and its topic/consumer operational model.                   |
| [[AWS/analytics/glue/README\|Glue]]                                   | Catalog, discovery and ETL.                                               |
| [[AWS/analytics/lake-formation/README\|Lake Formation]]               | Governed data permissions and filters.                                    |
| [[AWS/analytics/athena/README\|Athena]]                               | SQL over supported sources, including S3 datasets.                        |
| [[AWS/analytics/emr/README\|EMR]]                                     | Managed big-data runtimes for Spark and related workloads.                |
| [[AWS/analytics/redshift/README\|Redshift]]                           | Analytical warehouse, Serverless and BI consumption.                      |
| [[AWS/analytics/opensearch/README\|OpenSearch]]                       | Search, indexing and operational analytics.                               |
| [[AWS/analytics/kinesis/data-analytics\|Retired Kinesis SQL history]] | Historical migration context, not a currently deployable recommendation.  |

## Architectural choices

Batch favors bounded files, scheduled ETL and reproducible replay; streaming favors continuous event ingestion and event-time/window semantics. A lambda architecture maintains batch and streaming paths but adds reconciliation complexity. A kappa-style system replays a durable log through one processing approach; it still needs retention and backfill planning.

For a lake, S3 holds data, Glue Catalog describes it and Athena/EMR/Redshift consume supported formats. Lake Formation adds permissions but only if its enforcement pathways are correctly configured. Apache Iceberg adds table metadata/snapshot semantics to supported query engines; compatibility and concurrent-write behavior require explicit engine/catalog choices. BI dashboards need governed datasets, refresh cadence and cost limits—not merely warehouse credentials.

Kinesis Data Analytics SQL applications began deletion January 27, 2026. Current streaming architectures should evaluate Managed Flink, not copy historical SQL creation commands. Firehose's current name is Amazon Data Firehose; its firehose API remains.

## End-to-end exercise

Use disposable, non-sensitive events containing event ID and timestamp. Ingest, deliver to private S3, catalog/query a partitioned dataset and reconcile counts/amounts against the producer. Inject a duplicate and a late event: expected behavior must be documented by the application, not hidden by an “exactly once” label.

Test an unauthorized reader, measure ingestion-to-query latency and set scan/compute budgets. Retain enough raw input to reproduce results; use [[AWS/reliability/backup-and-recovery|recovery planning]] for catalog/configuration as well as data. Delete sandbox streams, jobs, endpoints, output files and compute resources after the exercise.

## Data-flow patterns and choosing latency

```text
Batch lake:
files → private S3 → Glue catalog/ETL → Athena or Redshift → BI

Continuous analytics:
events → Data Streams/MSK → Managed Flink → supported sink → application/BI

Managed delivery:
events → Firehose → private S3 → catalog → SQL queries
```

For batch, define a bounded input interval and a repeatable output. For streaming, distinguish processing time from event time: events can arrive late, duplicated or out of order. Decide allowed lateness, watermark behavior and whether a corrected aggregate replaces or appends output.

| Requirement            | Questions to ask                                                          |
| ---------------------- | ------------------------------------------------------------------------- |
| Seconds-level response | Can the sink absorb continuous updates, and how is backpressure observed? |
| Hourly/daily reporting | Can partitioned batch data meet freshness without continuous compute?     |
| Replay after a bug     | Is raw input retained long enough, and can output be safely replaced?     |
| Multiple readers       | Which consumer owns its checkpoint and permissions?                       |
| Auditable totals       | How are dropped, duplicated and late records reconciled?                  |

A lambda architecture keeps separate batch and streaming pipelines; it can repair a provisional real-time answer with a complete batch result, but requires reconciling two implementations. A kappa design replays one log through one processor; long retention and deterministic/idempotent replay are still necessary.

For BI, publish a stable semantic dataset rather than exposing raw ingestion tables without ownership. Track refresh time, schema changes, row-level authorization and query budgets. Read [[AWS/analytics/glue/README|ETL and catalog design]] for broader pipeline concepts and [[AWS/monitoring/README|AWS monitoring]] for operational evidence.

## References

- [AWS analytics selection guide](https://docs.aws.amazon.com/decision-guides/latest/analytics-on-aws-how-to-choose/analytics-on-aws-how-to-choose.html)
- [Kinesis SQL discontinuation](https://docs.aws.amazon.com/kinesisanalytics/latest/dev/discontinuation.html)
- [Athena Iceberg tables](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html)

## BI and lakehouse practice

Use [[AWS/analytics/lakehouse-and-bi|governed datasets, refresh and two-reader BI tests]] for interoperability and current Quick Sight semantics.

## Across the wiki

- [[GCP/databases/bigquery|Google BigQuery]] — analytics and warehouses (GCP)
- [[Architecture/solution-architecture-concepts/data-architecture/databases/columnar-databases|Columnar Databases]] — analytics and warehouses (Architecture)
- [[GCP/analytics/dataflow/README|Cloud Dataflow Architecture & Streaming Pipelines]] — analytics and warehouses (GCP)

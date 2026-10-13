---
title: "Amazon Redshift"
description: "Redshift is a columnar analytical warehouse for large joins, aggregates and BI."
tags:
  - aws/analytics
date: 2026-10-12
---

# Amazon Redshift

Redshift is a columnar analytical warehouse for large joins, aggregates and BI. This is the canonical implementation lesson; [[AWS/databases/redshift/README|the database architecture view]] explains where it fits beside operational stores. Prerequisites: [[AWS/storage/s3/README|S3]], [[AWS/security/iam/README|IAM]] and [[AWS/analytics/README|analytics]].

## Compute, storage and table design

Choose provisioned clusters or Redshift Serverless based on workload/runtime features and operational goals. Serverless uses workgroups/namespaces and RPU usage/capacity controls; provisioned node families and capabilities evolve. Discover supported node/Region options rather than recommending legacy hardware by a fixed table.

Distribution style defaults to AUTO. KEY can colocate join keys, ALL replicates suitable smaller tables and EVEN distributes rows; measure skew and query plans. Sort design and compression influence scans. Redshift can automatically vacuum/analyze applicable tables; manual work is an informed supplement, not proof that autovacuum must be enabled through a fictional PostgreSQL setting.

## Loading, exports and views

COPY loads supported sources such as S3 with an authorized role. UNLOAD writes query results; nested SQL quotes require escaping. The following SQL requires your own table, approved role and private disposable output prefix:

```sql
UNLOAD ('SELECT * FROM sandbox_events WHERE category = ''test''')
TO 's3://example-unique-bucket/disposable/unload/'
IAM_ROLE 'arn:aws:iam::123456789012:role/ApprovedWarehouseRole'
FORMAT AS PARQUET;

VACUUM DELETE ONLY sandbox_events;
VACUUM SORT ONLY sandbox_events;

CREATE VIEW sandbox_view AS
SELECT * FROM public.sandbox_events
WITH NO SCHEMA BINDING;
```

Late-binding syntax is CREATE VIEW … WITH NO SCHEMA BINDING, not CREATE LATE BINDING VIEW. External schema/catalog permissions and relation qualification must match the actual dataset.

## Workload management and data lakes

Provisioned WLM uses the parameter group's wlm_json_configuration; concurrency_scaling is a queue property set to auto where supported. Neither is configured with invented ALTER DATABASE/ALTER CLUSTER SQL. Use supported queue fields, concurrency controls and current service mode guidance.

Spectrum uses dedicated Redshift scan infrastructure for applicable node types; catalog integration does not mean Athena is the underlying engine. Newer integrated compute modes differ. Supported Iceberg/data-lake access requires explicit catalog, engine and permissions. BI consumers need least privilege, workload isolation and refresh/cost limits.

Resize mode is explicit: CLI default is elastic; --classic requests classic. Supported sizes/modes determine restrictions/downtime. The current CREATE SCHEMA limit is 9,900 schemas per database, not 100; other quotas must be discovered by deployment mode.

## Warehouse exercise and cost

Load a tiny synthetic dataset from private S3; reconcile counts plus totals and inspect distribution/skew. Compare a filtered aggregate query to a baseline, then UNLOAD into an isolated prefix and verify files. Demonstrate denied access for an unauthorized BI identity.

Test snapshot/restore or supported recovery separately from analytics correctness. Remove sandbox warehouse/workgroup/namespace resources, retained snapshots and S3 outputs as appropriate. Bill compute/RPU usage, storage, scans, concurrency scaling, transfer and backups using current regional dimensions—not mixed node/Serverless arithmetic.

## Distribution, sorting and compression examples

These are independent illustrative table designs; choose unique names or drop only disposable tables between experiments. AUTO is a valid starting point; a manually selected key should be justified with actual joins/skew.

```sql
CREATE TABLE sandbox_sales_auto (
  sale_id BIGINT,
  customer_id BIGINT,
  sale_date DATE,
  amount DECIMAL(10,2)
)
DISTSTYLE AUTO
SORTKEY (sale_date);

CREATE TABLE sandbox_sales_key (
  sale_id BIGINT,
  customer_id BIGINT,
  sale_date DATE,
  amount DECIMAL(10,2)
)
DISTSTYLE KEY
DISTKEY (customer_id)
SORTKEY (sale_date, customer_id);
```

| Design               | Useful when                                      | Risk to test                                             |
| -------------------- | ------------------------------------------------ | -------------------------------------------------------- |
| AUTO distribution    | Let supported automatic optimization choose      | Observe decisions and workload evolution.                |
| KEY                  | Large joins benefit from colocated rows          | Hot/skewed values or incompatible join keys.             |
| ALL                  | A suitably sized dimension justifies replication | Storage/load overhead; not a universal ten-MB threshold. |
| EVEN                 | Balanced distribution without key colocations    | Redistribution during joins.                             |
| Compound sort key    | Leading predicates narrow scans                  | Queries omitting leading columns may benefit less.       |
| Interleaved sort key | Supported multi-column access patterns fit       | Maintenance and deployment-mode constraints.             |

High cardinality alone does not cause skew; value-frequency distribution matters. A date key can skew loading/queries if most active records share a small set of values. Compression should use supported automatic encodings or measured alternatives, not one “best for every type” list.

## Workload, sharing and security walkthrough

Separate ingestion/ETL and BI workloads through supported WLM/Serverless controls. Inspect queue time, execution time and scan/redistribution separately. Concurrency scaling is a supported queue/capacity configuration, not a SQL statement invented from the console label.

Data sharing exposes supported live data to authorized consumers without copying the dataset into an independently owned snapshot. Define producer namespace/account/Region, consumer authorization, shared objects and catalog ownership using the documented workflow; a consumer CREATE DATABASE example missing producer namespace is not a complete cross-account procedure.

Use database privileges and supported row-level security policies/column grants alongside IAM/network/TLS controls. A view filtered by current_user is not a universal substitute for robust row authorization. A cluster can be configured publicly accessible; choose private access deliberately rather than claiming public mode is impossible.

## Performance investigation checklist

- Compare EXPLAIN/runtime evidence for scans, joins and redistribution.
- Inspect table skew and stats before changing distribution/sort design.
- Analyze after significant changes when automatic behavior is insufficient.
- Evaluate deleted-row/sort maintenance and automatic vacuum before manual work.
- Separate queue delay from slow execution and cap runaway BI queries.
- Reconcile source-to-warehouse row counts and totals after loading.
- Test restore/share/authorization workflows independently of query speed.

## Loading and export walkthrough

Prepare a private synthetic CSV without ambiguous quoting/schema, an approved warehouse IAM role and a disposable target table. The following COPY shape uses that role and S3 prefix; engine/account/Region, object format and permissions must match the actual dataset.

```sql
CREATE TABLE sandbox_load_sales (
  sale_id BIGINT,
  customer_id BIGINT,
  sale_date DATE,
  amount DECIMAL(10,2)
)
DISTSTYLE AUTO
SORTKEY (sale_date);

COPY sandbox_load_sales
FROM 's3://example-unique-bucket/sandbox/sales/'
IAM_ROLE 'arn:aws:iam::123456789012:role/ApprovedWarehouseRole'
CSV
IGNOREHEADER 1
DATEFORMAT 'auto';

SELECT count(*) AS rows_loaded,
       sum(amount) AS revenue
FROM sandbox_load_sales;
```

COPY reads the chosen source, not every file in an account; ensure the prefix contains only compatible data. Inspect supported load-error/system evidence if parsing or permission fails. A retry may duplicate data unless loading/reconciliation is designed to be idempotent. For manifest or columnar input, use the appropriate supported COPY options rather than leave CSV settings in place.

UNLOAD writes a query's output into separate S3 objects. Compare the exported row/amount totals and protect its IAM/KMS/destination policy. Dropping a warehouse table does not remove external staging/export objects; delete only reviewed disposable prefixes.

## Provisioned versus Serverless operating comparison

| Decision              | Provisioned warehouse                           | Serverless                                      |
| --------------------- | ----------------------------------------------- | ----------------------------------------------- |
| Resource unit         | Supported cluster/node configuration            | Namespace/workgroup and applicable RPU capacity |
| Scaling               | Supported resize/concurrency settings           | Supported capacity/usage limits                 |
| Maintenance           | Managed service plus cluster-specific lifecycle | Different managed lifecycle/feature constraints |
| Data lake integration | Supported Spectrum/integrated mode              | Supported integrated configuration              |
| Cost evidence         | Node-hours + storage/other dimensions           | Actual RPU usage + storage/other dimensions     |

Current node families/capabilities and supported resize targets are discovery inputs, not a fixed historical DS2/DC2 recommendation. Elastic resize is the CLI default where supported; --classic selects classic with its restrictions. Observe operation status and client downtime rather than claiming an exact guaranteed resize time.

## Monitoring and reconciliation scenario

Separate waiting/queue time from execution time. Inspect supported query/system views for the engine/mode, distribution/skew, I/O, load errors and concurrency. An invented QUEUE_METRICS name is not a CloudWatch metric contract. Examine plans/runtime evidence before tuning.

For a batch of ten thousand orders, reconcile loaded count, duplicate keys, total amount, min/max event dates and a sample of source rows. Then compare the same BI query before/after a justified sort/distribution change, holding data and filters constant. Record scan/redistribution and runtime; faster output is not valuable if a predicate silently excluded required orders.

Retain approved snapshots/replay inputs and record role/key dependencies for recovery. Warehouse data sharing is live authorized access, not an independent backup. Review dedicated data-sharing/database-security documentation before cross-account rollout.

## References

- [CREATE TABLE and AUTO distribution](https://docs.aws.amazon.com/redshift/latest/dg/r_CREATE_TABLE_NEW.html)
- [UNLOAD syntax](https://docs.aws.amazon.com/redshift/latest/dg/r_UNLOAD.html)
- [VACUUM/automatic maintenance](https://docs.aws.amazon.com/redshift/latest/dg/r_VACUUM_command.html)
- [CREATE VIEW](https://docs.aws.amazon.com/redshift/latest/dg/r_CREATE_VIEW.html)
- [WLM configuration](https://docs.aws.amazon.com/redshift/latest/dg/cm-c-defining-query-queues.html)
- [Serverless](https://docs.aws.amazon.com/redshift/latest/mgmt/working-with-serverless.html)
- [Redshift pricing](https://aws.amazon.com/redshift/pricing/)

## Across the wiki

- [[GCP/databases/bigquery|Google BigQuery]] — analytics and warehouses (GCP)
- [[Architecture/solution-architecture-concepts/data-architecture/databases/columnar-databases|Columnar Databases]] — analytics and warehouses (Architecture)
- [[GCP/analytics/dataflow/README|Cloud Dataflow Architecture & Streaming Pipelines]] — analytics and warehouses (GCP)

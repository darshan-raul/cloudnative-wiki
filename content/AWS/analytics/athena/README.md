---
title: "Amazon Athena"
description: "Athena runs SQL against supported datasets without managing a traditional database server."
tags:
  - aws/analytics
date: 2026-10-12
---

# Amazon Athena

Athena runs SQL against supported datasets without managing a traditional database server. S3, catalog metadata, query execution and result storage are separate permissions/cost boundaries. Prerequisites: [[AWS/storage/s3/README|S3]], [[AWS/analytics/glue/README|Glue Catalog]], [[AWS/security/iam/README|IAM]] and [[AWS/analytics/lake-formation/README|Lake Formation]] where enforced.

## Query design

Partition by useful predicates, prune columns and prefer appropriate columnar formats/compression. A LIMIT does not necessarily bound bytes scanned. Workgroups can enforce output location/encryption and query controls; select a supported engine version and measure actual scanned bytes.

External table definitions describe data; CTAS executes a SELECT and writes new S3 data. It is not free metadata-only DDL.

```sql
CREATE TABLE sandbox_daily
WITH (
  format = 'PARQUET',
  external_location = 's3://example-unique-bucket/disposable/daily/'
)
AS
SELECT event_date, count(*) AS events
FROM sandbox_events
GROUP BY event_date;
```

This schema-specific example requires the source table and an appropriate empty output location, permissions and a budget. It incurs query/storage costs and is not an executed deployment.

## Formats, archives and federation

Supported Iceberg tables add table/snapshot operations with engine/catalog/version constraints; they are not ordinary Hive tables with identical mutation behavior. Row/column size is limited to 32 MB, not 100 MB.

Archived S3 data must be restored before querying where supported. Engine-v3 Hive tables can use read_restored_glacier_objects; this is not direct S3 Select over unrestored Deep Archive.

Federated queries require a configured connector/catalog and corresponding networking/IAM. For the CloudWatch connector, log groups map to databases, streams to tables and all_log_streams is available; there is no universal cloudwatch table function that automatically creates integration. Connector/lambda/source costs can add to query charges.

## Scan and authorization exercise

Create a tiny private partitioned dataset, catalog it and query through a sandbox workgroup with a known output prefix. Compare SELECT \* with a column/predicate-pruned query and record bytes scanned. Run CTAS into a separate disposable prefix and inspect resulting Parquet files; expected evidence is data written, not merely a catalog object.

Deny an unauthorized identity and check both source and result-bucket permissions. Use bounded query polling, terminal-failure handling and output pagination. Delete sandbox tables and S3 outputs separately: dropping an external catalog table does not generally remove underlying objects.

## Schema-on-read: concrete table definitions

The catalog describes where files live and how to interpret them; it does not convert a CSV file into Parquet. Use different locations for datasets with different formats. Replace bucket names and define the corresponding data before executing these independent examples.

```sql
CREATE EXTERNAL TABLE sandbox_csv (
  user_id string,
  event_time string,
  action string,
  page_url string
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3://example-unique-bucket/csv/'
TBLPROPERTIES ('skip.header.line.count'='1');

CREATE EXTERNAL TABLE sandbox_parquet (
  user_id string,
  event_time timestamp,
  action string
)
STORED AS PARQUET
LOCATION 's3://example-unique-bucket/parquet/';
```

Simple delimiter parsing is not a universal CSV solution: quoted delimiters, escaped newlines and mixed schemas require a compatible SerDe/data preparation. Validate a few rows and types before relying on aggregates.

## Partition walkthrough

```text
s3://example-unique-bucket/events/
  year=2026/month=10/day=11/part-001.parquet
  year=2026/month=10/day=12/part-001.parquet
```

```sql
CREATE EXTERNAL TABLE sandbox_partitioned (
  user_id string,
  event_time timestamp,
  action string
)
PARTITIONED BY (year string, month string, day string)
STORED AS PARQUET
LOCATION 's3://example-unique-bucket/events/';

ALTER TABLE sandbox_partitioned ADD IF NOT EXISTS
PARTITION (year='2026', month='10', day='12')
LOCATION 's3://example-unique-bucket/events/year=2026/month=10/day=12/';

SELECT action, count(*) AS events
FROM sandbox_partitioned
WHERE year='2026' AND month='10' AND day='12'
GROUP BY action;
```

Partition metadata comes from the catalog or configured projection, not solely from folder spelling. MSCK REPAIR TABLE can discover compatible Hive-style partitions, but does not automatically remove stale entries or repair every layout. Match partition value types to your table and test predicate pruning by inspecting execution statistics.

## Format and workgroup comparisons

| Format/design          | Benefit                         | Trade-off                                                              |
| ---------------------- | ------------------------------- | ---------------------------------------------------------------------- |
| CSV/JSON               | Simple ingestion and inspection | More parsing and potentially larger scans; schema consistency matters. |
| Parquet/ORC            | Column pruning and compression  | Requires producing compatible columnar files.                          |
| Many tiny files        | Easy incremental writes         | Per-file scheduling/metadata overhead; compaction can help.            |
| Very coarse partitions | Simple layout                   | Broad scans when predicates cannot eliminate much data.                |
| Very fine partitions   | Narrow targeted reads           | Catalog/metadata management and sparse partitions.                     |

Workgroups separate query configuration, budgets and metrics; they do not themselves authorize source data. Enforce encrypted result locations, inspect failed/queued queries and track bytes scanned by team. Use execution IDs to fetch status/results with bounded polling and paginate results. SQL comments cannot select a workgroup; supply it through the actual client/console configuration.

## Bounded SDK query execution and result pagination

This SDK workflow runs a small billable SELECT against the sandbox_partitioned table defined above. It needs an existing sandbox-workgroup with an authorized result location, suitable Region/credentials and source/catalog permissions. It stops on a deadline/terminal failure and retrieves all returned pages.

```python
import time
import boto3

client = boto3.client("athena")
query_id = client.start_query_execution(
    QueryString=(
        "SELECT action, count(*) AS events FROM sandbox_partitioned "
        "WHERE year='2026' AND month='10' AND day='12' GROUP BY action"
    ),
    QueryExecutionContext={"Database": "sandbox_catalog"},
    WorkGroup="sandbox-workgroup",
)["QueryExecutionId"]

deadline = time.monotonic() + 120
while True:
    execution = client.get_query_execution(QueryExecutionId=query_id)["QueryExecution"]
    state = execution["Status"]["State"]
    if state == "SUCCEEDED":
        break
    if state in {"FAILED", "CANCELLED"}:
        raise RuntimeError(execution["Status"].get("StateChangeReason", state))
    if time.monotonic() >= deadline:
        client.stop_query_execution(QueryExecutionId=query_id)
        raise TimeoutError("Sandbox query exceeded its deadline")
    time.sleep(2)

rows = []
for page in client.get_paginator("get_query_results").paginate(
    QueryExecutionId=query_id
):
    rows.extend(page["ResultSet"]["Rows"])
print("Returned rows including any header:", len(rows))
print("Scanned bytes:", execution.get("Statistics", {}).get("DataScannedInBytes"))
```

The database/workgroup must match the actual table setup; change the example names deliberately. Results contain typed/string representations and a header according to the API result schema—do not silently treat that header as a data row. Restrict result-bucket permissions independently from source-table access.

## Worked scan-cost comparison

Suppose a controlled measurement scans 1,000 GB for a full text dataset and 80 GB after validated columnar/partition pruning. The measured byte reduction is 92%; billed query cost uses each actual scanned quantity, the applicable regional rate and minimum/rounding. This is not a promise that Parquet always reduces scans by a fixed percentage.

CTAS adds query execution and writes output; the produced files incur S3 storage/requests. Federated sources can add connector/runtime/source costs. Compare total completion time, scanned bytes and identical query results so an apparent “cheaper” query does not simply omit required records.

Configure workgroup enforcement/scan limits and alerting appropriate to the team's risk. A bytes-scanned cutoff is a safety mechanism, not assurance that every federated/capacity charge is bounded. Clean up source/catalog/output artifacts separately and retain only approved benchmark evidence.

## Cost and references

Model bytes scanned × applicable rate or reserved/provisioned capacity, plus result storage, catalog/connector and source charges. Apply Region/operation-specific minimum/rounding rules from current pricing. Monitor failed queries and scan growth; do not certify old flat-price examples as universal.

- [CTAS behavior and syntax](https://docs.aws.amazon.com/athena/latest/ug/ctas.html)
- [Athena limitations](https://docs.aws.amazon.com/athena/latest/ug/other-notable-limitations.html)
- [Archived S3 queries](https://docs.aws.amazon.com/athena/latest/ug/querying-glacier.html)
- [CloudWatch connector](https://docs.aws.amazon.com/athena/latest/ug/connectors-cloudwatch.html)
- [Iceberg support](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html)
- [Athena pricing](https://aws.amazon.com/athena/pricing/)

## Across the wiki

- [[GCP/databases/bigquery|Google BigQuery]] — analytics and warehouses (GCP)
- [[Architecture/solution-architecture-concepts/data-architecture/databases/columnar-databases|Columnar Databases]] — analytics and warehouses (Architecture)
- [[GCP/analytics/dataflow/README|Cloud Dataflow Architecture & Streaming Pipelines]] — analytics and warehouses (GCP)

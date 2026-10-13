---
title: "AWS Glue"
description: "Glue provides a Data Catalog, crawlers and managed ETL runtimes."
tags:
  - aws/analytics
date: 2026-10-12
---

# AWS Glue

Glue provides a Data Catalog, crawlers and managed ETL runtimes. Catalog metadata is not the data itself; ETL compute, data access and governance have separate boundaries. Prerequisites: [[AWS/storage/s3/README|S3]], [[AWS/security/iam/README|IAM]] and [[AWS/analytics/README|analytics]].

## Catalog, crawler and job contracts

A Glue database groups table metadata. CreateDatabase requires DatabaseInput containing Name; TargetDatabase creates a resource link to another catalog/database rather than an ordinary self-referencing database.

```python
import boto3

glue = boto3.client("glue")
glue.create_database(DatabaseInput={"Name": "sandbox_catalog"})
```

This minimal SDK example requires configured credentials/Region and permission; it is not a crawler or ETL job. Crawlers need an execution role, supported targets and explicit schema/update policies. Glue native conditional triggers use Condition.CrawlerName/CrawlState for crawlers and JobName/State for jobs; those fields are not an EventBridge event-detail schema.

Spark jobs should be ordinary executable scripts with defined input/output and actual transformations. A Python-shell script that only defines a Lambda handler never performs ETL unless invoked. If producing monthly totals, group by the actual month key, not a daily field labelled monthly.

## Incremental processing and schema

Bookmarks need supported source readers, stable transformation_ctx identifiers, job.init/job.commit and the configured job-bookmark option. State is maintained by Glue, not an invented S3 bookmark prefix. Reset/replay changes processing state and can duplicate outputs unless the destination is idempotent.

Schema Registry uses the documented glue client contracts, RegistryId and valid compatibility enums such as BACKWARD. It is not an awscharm client or BACKWARD_COMPATIBLE setting. Distinguish catalog schema evolution, registry compatibility and downstream data-quality contracts.

## ETL exercise

Create small private CSV input with a known month/date/category and an expected total. Provision a budgeted sandbox job using an official supported runtime example, transform to partitioned Parquet and query it through [[AWS/analytics/athena/README|Athena]]. Inspect output types, totals and partitions.

Run incremental processing twice with the same input, then add one file; record bookmark behavior and verify destination duplicate handling. Introduce a malformed row and demonstrate a controlled failure/quarantine policy. Test unauthorized data access. Delete jobs/crawlers/catalog objects and S3 outputs separately, plus temporary roles/connections only if created for the sandbox.

## Cost and operations

Glue ETL is already serverless. Compute billing is DPUs × elapsed hours × the selected runtime/Region rate; Python shell supports 0.0625 or 1 DPU, not two. Minimum-duration/per-second rules depend on operation; 61 seconds is not automatically two billed minutes. Crawlers, Catalog, interactive sessions, registry and data-quality features have separate dimensions. Monitor job failures, retries, skew, data quality and runaway output volume.

## Catalog and crawler walkthrough

```text
Private raw S3 prefix
  → crawler (scoped execution role, schema policy)
  → Glue database/table/partition metadata
  → Athena, Glue Spark or supported warehouse reader
```

A crawler samples supported source data; it does not certify every row against a business schema. Avoid the unsupported universal “first 10 MB or ten files” promise. Choose classifiers/schema-change policies, inspect inferred types and define what happens when a column changes.

```python
import boto3

glue = boto3.client("glue")
glue.create_database(DatabaseInput={"Name": "sandbox_sales"})
glue.create_table(
    DatabaseName="sandbox_sales",
    TableInput={
        "Name": "sales_csv",
        "TableType": "EXTERNAL_TABLE",
        "StorageDescriptor": {
            "Columns": [
                {"Name": "sale_id", "Type": "bigint"},
                {"Name": "sale_date", "Type": "string"},
                {"Name": "amount", "Type": "double"},
            ],
            "Location": "s3://example-unique-bucket/sales/",
            "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
            "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
            "SerdeInfo": {
                "SerializationLibrary": "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe",
                "Parameters": {"field.delim": ","},
            },
        },
    },
)
```

This is a schema-specific SDK example, not a data upload/crawler deployment. It needs actual headerless compatible files and permission; existing names cause conflicts. Resource links use TargetDatabase intentionally and should not point to the same ordinary database by accident.

## Executable ETL: actual monthly grouping

A Python-shell script must execute its entry point; defining a Lambda handler alone does nothing. This local transformation core can be tested on a CSV with sale_id, sale_date and amount. It needs a pinned pandas dependency and local input; adapt I/O to authorized S3 paths for a Glue job.

```python
import pandas as pd

def summarize_sales(csv_path):
    frame = pd.read_csv(csv_path)
    frame["sale_date"] = pd.to_datetime(frame["sale_date"], errors="raise")
    frame["sale_month"] = frame["sale_date"].dt.strftime("%Y-%m")
    return frame.groupby("sale_month", as_index=False).agg(
        total_revenue=("amount", "sum"),
        transaction_count=("sale_id", "count"),
    )

if __name__ == "__main__":
    summarize_sales("sales.csv").to_csv("monthly.csv", index=False)
```

For Spark, derive a true month key (for example date_trunc month) before grouping. Partition output by the intended aggregation grain, and isolate output from raw input so subsequent reads do not recursively ingest their own summaries.

## Bookmark and workflow decisions

| Concern            | Design decision                                                                          |
| ------------------ | ---------------------------------------------------------------------------------------- |
| Incremental source | Supported Glue reader, stable transformation context and bookmark configuration.         |
| Replay/reset       | Determine whether output overwrites a partition or deduplicates rows.                    |
| Schema evolution   | Evaluate catalog updates, registry compatibility and downstream consumers independently. |
| Dependencies       | Workflow/triggers should use the actual job/crawler state schema.                        |
| Failed run         | Inspect terminal job state, logs and partial output before retrying.                     |

A bookmark is source progress, not a transaction covering every destination. Job commit, retries and destination idempotency must be considered together. Glue Studio's visual graph generates/configures jobs; inspect the generated script and data types rather than trusting the canvas alone.

## Native trigger conditions versus EventBridge events

A native Glue trigger can wait for supported crawler terminal conditions SUCCEEDED, FAILED or CANCELLED. This example is a Condition object to embed in the owning trigger Predicate, not a complete CreateTrigger request:

```json
{
  "CrawlerName": "sandbox-crawler",
  "CrawlState": "SUCCEEDED",
  "LogicalOperator": "EQUALS"
}
```

EventBridge uses source/detail-type plus the actual event payload. Glue Crawler State Change events describe Started, Succeeded or Failed; those values/capitalization differ from native trigger conditions. A broad discovery rule can select only the service/event type:

```json
{
  "source": ["aws.glue"],
  "detail-type": ["Glue Crawler State Change"]
}
```

Capture a sandbox event and compare it with the documented detail contract before adding crawler-name/state predicates. Do not copy native Condition fields or enums into an EventBridge detail filter. Validate matched and unmatched events and ensure the target has permission and idempotent handling.

## References

- [CreateDatabase contract](https://docs.aws.amazon.com/boto3/latest/reference/services/glue/client/create_database.html)
- [Bookmark behavior](https://docs.aws.amazon.com/glue/latest/dg/monitor-continuations.html)
- [Crawler events](https://docs.aws.amazon.com/glue/latest/dg/automating-awsglue-with-cloudwatch-events.html)
- [Native trigger Condition contract](https://docs.aws.amazon.com/glue/latest/webapi/API_Condition.html)
- [CreateSchema contract](https://docs.aws.amazon.com/boto3/latest/reference/services/glue/client/create_schema.html)
- [Glue pricing](https://aws.amazon.com/glue/pricing/)

## Complete bookmark lab: three runs and duplicate-safe output

Use a private **dedicated** S3 prefix, CLI v2, Python/Boto3 for the driver, and Glue **5.0**, Spark with G.1X × 2 workers in a supported Region. Verify this release is offered before creation. The Glue role trusts glue.amazonaws.com, has the appropriate managed Glue service-role permissions, GetObject/ListBucket on the input/script prefixes, PutObject/GetObject on the output prefix, CloudWatch logging and any selected KMS permissions. The operator needs job operations, upload access and scoped iam:PassRole. No production catalog/table is used.

Create these two local files; upload only part-001.csv before the first run:

```csv
sale_id,sale_date,amount
1,2026-01-01,10.00
2,2026-01-15,20.00
```

Save that as part-001.csv. Save the following as part-002.csv, but upload it only before run three:

```csv
sale_id,sale_date,amount
3,2026-01-20,5.00
4,2026-02-01,7.00
```

Save the complete job as bookmark_job.py. Its source context is stable across runs. Each immutable input object's monthly aggregates overwrite one deterministic output key; a retry/reset cannot append that object's totals twice.

```python
import hashlib
import json
import sys
from urllib.parse import urlparse

import boto3
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ["JOB_NAME", "SOURCE_URI", "DEST_URI"])
context = GlueContext(SparkContext.getOrCreate())
job = Job(context)
job.init(args["JOB_NAME"], args)
source = context.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={"paths": [args["SOURCE_URI"]], "recurse": True},
    format="csv",
    format_options={"withHeader": True},
    transformation_ctx="sales_source_v1",
).toDF()
count = source.count()
print(json.dumps({"new_source_rows": count}))
if count:
    prepared = (
        source.withColumn("_source", F.input_file_name())
        .withColumn("sale_month", F.date_format(F.to_date("sale_date"), "yyyy-MM"))
        .withColumn("amount_decimal", F.col("amount").cast("decimal(12,2)"))
    )
    if prepared.filter(
        F.col("sale_month").isNull() | F.col("amount_decimal").isNull()
    ).count():
        raise ValueError("Invalid date or amount; bookmark must not commit")
    rows = prepared.groupBy("_source", "sale_month").agg(
        F.sum("amount_decimal").alias("total"),
        F.count("*").alias("transactions"),
    ).collect()
    by_source = {}
    for row in rows:
        by_source.setdefault(row["_source"], []).append({
            "sale_month": row["sale_month"],
            "total": str(row["total"]),
            "transactions": row["transactions"],
        })
    destination = urlparse(args["DEST_URI"])
    if destination.scheme != "s3" or not destination.netloc:
        raise ValueError("DEST_URI must be an isolated s3:// prefix")
    prefix = destination.path.lstrip("/").rstrip("/") + "/"
    client = boto3.client("s3")
    for uri, totals in by_source.items():
        key = prefix + hashlib.sha256(uri.encode()).hexdigest() + ".json"
        payload = "\n".join(json.dumps(x) for x in sorted(
            totals, key=lambda x: x["sale_month"]
        )) + "\n"
        client.put_object(
            Bucket=destination.netloc, Key=key,
            Body=payload.encode(), ContentType="application/x-ndjson",
        )
job.commit()
```

This deliberately small lab collects the per-file groups to the driver. It is not a scalable production aggregation pattern. Keep input files immutable and uniquely named, keep output outside input, and do not change source identity/context between the three runs. Deleted input is not automatically removed from output.

Set your bucket/role, then upload the script and first file. Changing the example prefix must change SOURCE_URI/DEST_URI consistently:

```bash
if [ -z "$GLUE_LAB_BUCKET" ] || [ -z "$GLUE_LAB_ROLE" ]; then
  echo "Set GLUE_LAB_BUCKET and approved GLUE_LAB_ROLE first"; exit 1
fi
aws s3 cp bookmark_job.py "s3://$GLUE_LAB_BUCKET/dg04/scripts/bookmark_job.py"
aws s3 cp part-001.csv "s3://$GLUE_LAB_BUCKET/dg04/input/part-001.csv"
```

Save/run this driver. Boto3 uses your selected profile/Region; record the printed run IDs. Each cloud job incurs charges. The driver fails on terminal error/deadline instead of reporting submission as success.

```python
import os
import time
import boto3

glue = boto3.client("glue")
bucket = os.environ["GLUE_LAB_BUCKET"]
name = "dg04-bookmark-lab"
glue.create_job(
    Name=name, Role=os.environ["GLUE_LAB_ROLE"],
    GlueVersion="5.0", WorkerType="G.1X", NumberOfWorkers=2,
    Command={
        "Name": "glueetl", "PythonVersion": "3",
        "ScriptLocation": f"s3://{bucket}/dg04/scripts/bookmark_job.py",
    },
    DefaultArguments={
        "--job-bookmark-option": "job-bookmark-enable",
        "--SOURCE_URI": f"s3://{bucket}/dg04/input/",
        "--DEST_URI": f"s3://{bucket}/dg04/output/",
    },
    Timeout=10, MaxRetries=0,
)
def run_once():
    run_id = glue.start_job_run(JobName=name)["JobRunId"]
    print("JobRunId:", run_id)
    deadline = time.monotonic() + 900
    while time.monotonic() < deadline:
        run = glue.get_job_run(JobName=name, RunId=run_id)["JobRun"]
        state = run["JobRunState"]
        if state == "SUCCEEDED":
            return run_id
        if state in {"FAILED", "STOPPED", "TIMEOUT", "ERROR", "EXPIRED"}:
            raise RuntimeError(run.get("ErrorMessage", state))
        time.sleep(5)
    glue.batch_stop_job_run(JobName=name, JobRunIds=[run_id])
    raise TimeoutError("Stop requested; inspect terminal state before cleanup")

if __name__ == "__main__":
    run_once()
    run_once()
    boto3.client("s3").upload_file(
        "part-002.csv", bucket, "dg04/input/part-002.csv"
    )
    run_once()
```

Expected observations, not claimed cloud execution:

| Run                  | new_source_rows log | Output reconciliation                                     |
| -------------------- | ------------------- | --------------------------------------------------------- |
| One                  | 2                   | January total 30.00, 2 transactions                       |
| Two, unchanged input | 0                   | Still January 30.00, 2; no added output                   |
| Three, new part-002  | 2                   | Sum all output files: January 35.00/3 and February 7.00/1 |

Download only dg04/output objects and add the decimal totals. ResetJobBookmark followed by a replay reads both files again but overwrites the same two keys: totals stay 35.00 and 7.00. Resetting bookmarks itself does **not** clean targets. This strategy is valid for independent immutable-source contributions, not arbitrary merged mutable datasets.

Cleanup: wait for every recorded run to be terminal, delete only dg04-bookmark-lab, then review/remove the exact dg04 input/output/script objects and dedicated log groups. Preserve shared roles/buckets/KMS keys. Stop failures still need inspection; deleting a definition is not a running-job cancellation.

Sources: [bookmarks](https://docs.aws.amazon.com/glue/latest/dg/monitor-continuations.html), [Glue versions](https://docs.aws.amazon.com/glue/latest/dg/release-notes.html), [CreateJob](https://docs.aws.amazon.com/boto3/latest/reference/services/glue/client/create_job.html), [GetJobRun](https://docs.aws.amazon.com/boto3/latest/reference/services/glue/client/get_job_run.html).

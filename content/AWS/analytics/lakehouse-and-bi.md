---
title: Lakehouse interoperability and BI
description: Connect governed lake/warehouse data to a BI dataset and prove refresh correctness and reader isolation.
tags:
  - cloud/aws/analytics
date: 2026-10-12
---

# Lakehouse interoperability and BI

A lake holds files, a table format manages supported metadata and engines compute results. BI adds datasets, calculations, refresh and reader access. Start with [[AWS/analytics/README|analytics]], [[AWS/analytics/lake-formation/README|governance]] and [[AWS/analytics/redshift/README|warehouse operations]].

## Interoperability is conditional

Glue Catalog registration does not guarantee every engine supports every format/version. For Iceberg, choose compatible catalog, read/write engine and snapshot/maintenance behavior. Test schema evolution, partition changes and concurrent writers against the owning contracts.

Redshift Serverless has supported workgroup/namespace and compute controls, not an unlimited free endpoint. Compare warehouse queries with Athena scans using freshness, latency, concurrency and cost requirements.

Current documentation names Amazon Quick Sight as the BI feature within Amazon Quick, evolved from QuickSight; existing QuickSight APIs/SDKs continue. Use current owning documentation rather than inventing a new API namespace from the name.

## Dataset and access choices

Direct query reaches a supported source at query time. SPICE imports data and requires refresh/ingestion planning; a source update does not prove a cached dashboard refreshed. Check capacity/source/mode/edition constraints.

Row-level security has supported edition/rule semantics. Test as an actual reader: dataset owners may see all rows even with reader rules configured. Source credentials, BI sharing and warehouse/Lake Formation permissions are separate controls.

## Two-reader fixture exercise

Prerequisites: approved BI subscription/sandbox, supported source/engine, scoped roles/credentials and two reader identities. Use synthetic tenant=A/B rows with known totals.

1. Create a private test table/dataset and reconcile source totals before visualization.
2. Choose direct query or SPICE deliberately and record refresh policy.
3. Create an analysis/dashboard with a tenant-total visual.
4. Apply supported reader RLS rules; A sees only A and B only B. Do not use an owner as the negative-isolation test.
5. Change a source row; compare before/after refresh and document the freshness boundary.
6. Deny an unauthorized source/reader identity and diagnose the correct access layer.
7. Delete dedicated dashboard/analysis/dataset/data source and lab source objects/compute/SPICE allocation as applicable. Verify recurring subscription/capacity charges separately.

For Iceberg, add a compatible schema change and compare two supported engines against the same committed snapshot. Reconcile totals, not only query success.

## Worked Athena → SPICE → reader RLS fixture

Choose an approved **Enterprise-edition** Quick Sight sandbox, a dedicated Athena workgroup/result prefix, a private S3 input prefix and two existing Quick reader identities. Have an author/operator identity to create datasets and publish dashboards. Use the actual readers' Quick **UserName** values (from `aws quicksight list-users --aws-account-id ... --namespace default`), not IAM role names or guessed email aliases. In the examples, `wiki-reader-a` and `wiki-reader-b` denote those two verified usernames; replace them consistently if your account uses different names. Never make these test readers dataset owners.

Follow [[AWS/analytics/athena/README|Athena's setup]] for the workgroup, result location and query execution. The BI service role also needs that workgroup's Athena/Glue and exact source/result S3 permissions, plus Lake Formation grants if the selected catalog is governed. Authorize the specific sandbox resources through Quick's supported service-access settings; do not grant all buckets to make a failed query work. No new production catalog permission mode is implied.

### Source and rules files

Save this complete synthetic input as `wiki-bi-lab-orders.csv`:

```csv
order_id,tenant,total
lab-a1,A,25
lab-a2,A,40
lab-b1,B,10
lab-b2,B,20
```

Set BI_LAB_BUCKET to your verified private bucket, upload the file, then run the DDL in the approved Athena workgroup. Substitute that bucket name in LOCATION before execution:

```bash
aws s3 cp wiki-bi-lab-orders.csv \
  "s3://${BI_LAB_BUCKET:?}/wiki-bi-lab/orders/orders.csv"
```

```sql
CREATE DATABASE wiki_bi_lab;
CREATE EXTERNAL TABLE wiki_bi_lab.orders (
  order_id string, tenant string, total double
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3://REPLACE_WITH_BI_LAB_BUCKET/wiki-bi-lab/orders/'
TBLPROPERTIES ('skip.header.line.count'='1');

SELECT tenant, count(*) AS rows, sum(total) AS total
FROM wiki_bi_lab.orders GROUP BY tenant ORDER BY tenant;
```

Expected source results: A/2/65 and B/2/30, grand total 95. Use an unused sandbox database name if wiki_bi_lab already exists; do not drop someone else's database to fit the example. The four-field-free CSV is intentionally simple: arbitrary quoted commas need a suitable SerDe rather than this delimiter-only recipe.

Save the permissions file separately as `wiki-bi-lab-reader-rules.csv`, using the verified Quick usernames:

```csv
UserName,tenant
wiki-reader-a,A
wiki-reader-b,B
```

Both columns are strings, field names/values are case-sensitive and tenant matches the source exactly. A **named user** with a blank tenant rule would be permitted all tenant values: do not add such a wildcard accidentally. An entirely empty rules row has different skip semantics. A reader without a matching rule has no permitted rows; owners can still see all data. These are user-based grant rules, not IAM principal tags.

### Dataset, rules and dashboard procedure

1. In Quick's Data/Datasets workflow, choose New dataset → Athena. Name the dedicated data source `wiki-bi-lab-athena`, select the approved workgroup, database wiki_bi_lab and orders table.
2. Import into **SPICE**, not direct query, for this freshness test. Verify order_id/tenant are strings and total is numeric; record successful ingestion ID/time and reconcile all four source rows as the author.
3. Under New dataset, create a **New rules dataset** from the reader-rules CSV. Name it `wiki-bi-lab-rules`; confirm its rules-dataset classification and all-string columns before completing ingestion. A normal dataset cannot simply be renamed into a rules dataset; use the supported create/duplicate-as-rules workflow.
4. Open the orders dataset's Row-level security settings, select User-based rules, choose wiki-bi-lab-rules, choose Grant access to dataset, and Apply/activate. Record the active rules dataset. Attaching a second permissions dataset overwrites the first rather than combining arbitrary rule sets.
5. Create an analysis using orders with a table visual grouped by tenant and sum(total), and add order_id detail in a second visual. Publish a dedicated dashboard and grant reader access to the two intended readers only.
6. In separate reader sessions, A must see lab-a1/lab-a2 and total 65, while B must see lab-b1/lab-b2 and total 30. Neither should see the other tenant's detail. The author/owner's total 95 is expected and is not an RLS negative test.
7. Attempt dashboard access from an approved identity with **no dashboard share** and record the sharing denial. If testing an already shared reader absent from the permissions dataset, expect no permitted rows instead; these are different layers.

If the rules dataset does not appear, inspect its classification, ingestion result, account/Region and schema before relaxing access. A source AccessDenied is not an RLS filtering result. Diagnose workgroup/Glue/S3/Lake Formation authority separately from Quick dataset/dashboard sharing.

### Prove the freshness boundary

Change lab-a2's total from 40 to 50 in the local source CSV and upload it over the **same exact** orders.csv key. Re-run the Athena aggregate: A is now 75, B remains 30 and grand total is 105. Before a new SPICE ingestion, the published SPICE dashboard should still show its previous successfully imported totals, 65/30. That cached result is not a failed source update.

Use the orders dataset's supported Refresh now/full-refresh action, wait with a chosen deadline (for example ten minutes) and inspect its successful ingestion status/time. Reload the reader dashboard; A should now show 75 and B 30. If refresh fails/times out, retain the failure details and do not claim refreshed data based on request submission. Record source query time, ingestion time and reader observation separately. Test a failed data-source role permission only in a disposable role, then restore it before the final refresh.

Delete the dedicated dashboard, analysis, source dataset and rules dataset in dependency order; remove the data source if unused. Drop only wiki_bi_lab.orders and the dedicated database after checking it contains no other objects. Delete the exact source CSV and reviewed Athena result objects/versions. Review released SPICE capacity, retained query results and subscription/user charges separately—dataset deletion does not cancel the account subscription.

[User-based RLS and rules-dataset workflow](https://docs.aws.amazon.com/quick/latest/userguide/restrict-access-to-a-data-set-using-row-level-security.html), [Athena as a BI source](https://docs.aws.amazon.com/quick/latest/userguide/create-a-data-set-athena.html), [SPICE refresh](https://docs.aws.amazon.com/quick/latest/userguide/refreshing-imported-data.html).

## References

- [Current Quick/Quick Sight boundary](https://docs.aws.amazon.com/quick/latest/userguide/what-is.html).
- [Reader RLS](https://docs.aws.amazon.com/quick/latest/userguide/restrict-access-to-a-data-set-using-row-level-security.html).
- [Dataset/SPICE constraints](https://docs.aws.amazon.com/quick/latest/userguide/data-source-limits.html).
- [Athena Iceberg](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html).
- [Redshift Serverless](https://docs.aws.amazon.com/redshift/latest/mgmt/working-with-serverless.html).

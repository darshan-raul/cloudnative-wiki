---
title: Cost and Usage Report (CUR)
description: Accurate billing models, decision workflows and scoped examples for cost usage report.
tags:
  - aws/cost-management
date: 2026-10-12
---

# Cost and Usage Report (CUR)

Price exercises use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, not current tariffs, unless explicitly identified as a dated published fee.

Detailed billing exports support repeatable cost analysis beyond the console. Distinguish legacy Cost and Usage Reports (CUR) from **AWS Data Exports and CUR 2.0**; their schema, configuration and delivery behavior are not identical.

## Export choices

CUR 2.0 provides selectable columns and filtering through Data Exports. Supported delivery formats include Parquet and CSV with the relevant export configuration. Prefer Parquet for columnar analytics when appropriate; do not describe every report as CSV-only.

Resource identifiers are available only for supported line items and configured detail. They do not imply that every cost row can be mapped to a resource. Shared, subscription and commitment charges require additional allocation rules.

Hourly line-item granularity is not an hourly delivery guarantee. Reports can be refreshed and revised as billing data arrives, including credits and finalization adjustments. Use the manifest/schema and export documentation rather than assuming every delivery is append-only.

## Analytics workflow

1. Configure an authorized export and an appropriately protected S3 destination.
2. Record schema version, granularity, resource detail and report update settings.
3. Build an Athena/Glue integration matching that export's actual schema.
4. Filter partitions and select required columns; measure scanned bytes.
5. Reconcile totals to the chosen invoice/cost metric and explain discrepancies.
6. Retain version/schema metadata alongside dashboards.

Legacy SQL column names and partition layouts cannot be pasted unchanged into every CUR 2.0 dataset. Validate against the table schema first. Parquet and partition pruning can reduce query cost, but there is no universal 80% savings guarantee.

S3 storage, Athena scans, Glue/catalog usage, KMS and any visualization services can add charges. Avoid exposing sensitive billing and account metadata through public buckets or unrestricted dashboards.

## Practical drill

Using an existing authorized export, compare one month's service totals with Cost Explorer using the same metric and date boundaries. Explain upfront RI fees, amortization, credits and estimated versus final rows. No new paid export or resource creation is required to perform the planning exercise.

### Local aggregation fixture

This synthetic SQL fixture verifies the aggregation and treatment of a negative adjustment; it is **not** a claim that every export has these three column names. The same query was executed locally against an in-memory SQL engine; no billing data or Athena request was used.

```sql
WITH billing_fixture(account_id, service, amount) AS (
  VALUES
    ('111122223333', 'EC2', 10.0),
    ('111122223333', 'EC2', -2.0),
    ('444455556666', 'S3', 3.0)
)
SELECT account_id, service, ROUND(SUM(amount), 2) AS total
FROM billing_fixture
GROUP BY account_id, service
ORDER BY account_id, service;
```

Expected: account 111122223333/EC2 totals 8.00 and account 444455556666/S3 totals 3.00. Before adapting this to an export, map the actual account/service/cost columns from its dictionary and choose unblended, net or amortized treatment deliberately. Add an explicit billing-period/partition filter, inspect adjustment line types and compare with the same invoice metric. A correct SUM is not proof that unlike cost metrics can be reconciled.

## Architectural pipeline and accounting controls

Billing source → versioned/protected S3 export → schema/catalog integration → Athena queries → reconciled dashboards. S3 delivery/notifications and Glue crawling are optional implementation choices, not proof that every report is delivered hourly. Avoid a crawler running on every object without cost/idempotency analysis.

Parquet can reduce scan volume for suitable queries, but “always 80% cheaper” is not a guarantee. Inspect actual partitions, projection and export schema. Legacy `year/month` partitions are not mandatory `account_id` partitions in every dataset.

## Showback versus chargeback

Showback informs owners without transferring budget. Chargeback assigns internal financial responsibility using an agreed accounting policy. AWS export generation does not itself issue arbitrary internal invoices or decide shared-cost ownership.

Specify cash versus amortized/net cost, credit ownership, shared allocations, unallocated rows and mapping effective dates. Include data quality checks: duplicate report versions, missing tags, null resource IDs and estimated/final revisions.

## SQL adaptation lab

Inspect the actual dataset before adapting a billing query:

```sql
SHOW COLUMNS IN cur_database.cur_table;
```

For a **legacy Athena integration** that really has the following columns/partitions, this ranks identifiable resources. Table/column names are a schema assumption, not a CUR 2.0 contract:

```sql
SELECT
  line_item_resource_id,
  product_product_name,
  SUM(line_item_unblended_cost) AS total_cost
FROM cur_database.cur_table
WHERE year = '2026'
  AND month = '09'
  AND line_item_resource_id IS NOT NULL
  AND line_item_resource_id <> ''
GROUP BY 1, 2
ORDER BY total_cost DESC
LIMIT 10;
```

Do not call those rows the whole invoice: charges lacking resource IDs are excluded. Reconcile their totals separately. For tag analysis, inspect the export's real tag/map representation; do not invent a universal `resource_tags_user_cost_center` column. Check scan bytes, query workgroup limits, result-bucket access and encryption.

- [Athena integration with legacy CUR](https://docs.aws.amazon.com/cur/latest/userguide/cur-query-athena.html)
- [CUR 2.0 field dictionary](https://docs.aws.amazon.com/cur/latest/userguide/table-dictionary-cur2.html)

## References

- [AWS Data Exports](https://docs.aws.amazon.com/cur/latest/userguide/what-is-data-exports.html)
- [CUR 2.0 table dictionary](https://docs.aws.amazon.com/cur/latest/userguide/table-dictionary-cur2.html)
- [Legacy CUR documentation](https://docs.aws.amazon.com/cur/latest/userguide/what-is-cur.html)

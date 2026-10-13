---
title: "AWS Lake Formation"
description: "Lake Formation governs supported catalogued data access."
tags:
  - aws/analytics
date: 2026-10-12
---

# AWS Lake Formation

Lake Formation governs supported catalogued data access. It works with [[AWS/storage/s3/README|S3]], [[AWS/analytics/glue/README|Glue Catalog]] and engines such as [[AWS/analytics/athena/README|Athena]]. IAM permissions, network access, registration and LF permissions are related but distinct.

## Permissions and filters

Database permissions describe/create catalog objects; SELECT applies to a table, selected columns or a data filter—not a database. GrantPermissions uses PermissionsWithGrantOption as a list, not a boolean. Table resources identify Name; excluded columns belong to TableWithColumns/ExcludedColumnNames.

LF-Tags label catalog resources and provide tag-based grants. They do not label individual rows or automatically inherit arbitrary IAM principal tags. Row/cell filtering uses DataCellsFilter with TableData and RowFilter/filter expression plus SELECT on that filter. Current documentation does not apply data filters through LF-Tag grants. An LF-Tag named department=finance alone does not isolate finance rows.

## Full enforcement versus hybrid access

Choose one migration/enforcement strategy explicitly. Full LF enforcement needs deliberate default permissions, IAMAllowedPrincipals and S3 registration configuration. Hybrid mode lets opted-in principals require LF plus IAM, while non-opted-in principals retain IAM-only paths. Leaving a bypass path invalidates claims that every reader sees filtered rows.

Cross-account sharing requires supported LF grants/resource links and, where applicable, AWS RAM workflows. Registry/catalog/data ownership and KMS permissions remain separate. Do not confuse Lake Formation sharing with CloudFormation StackSets.

RegisterResource has no Description field. CreateDataCellsFilter requires the owning nested schema, not fictional top-level Principals/RowExpression. Use official examples rather than a nonexistent create_permissions SDK operation. LF Governed Tables retired December 31, 2024; teach supported transactional table formats instead of that retired feature.

## Two-principal authorization exercise

Prerequisites: an isolated catalog/table with a few labelled department rows, private S3, two distinct test principals, an administrator role and supported query engine. Budget query/storage charges.

Register/configure the data location using the selected enforcement mode. Grant principal A only finance rows through a real data filter and principal B a deliberately different view. Query as each principal and verify exact permitted/forbidden rows and columns. Try a non-opted-in IAM principal in hybrid mode: if IAM-only access remains, document it rather than claiming universal enforcement.

Inspect source/result-bucket and KMS permissions. A successful admin query is not evidence of reader isolation. Revoke sandbox grants/opt-ins, remove filters/resource links/catalog objects and registration only after reviewing dependencies; delete disposable source/result objects separately.

## Lake architecture and permission objects

```text
S3 registered location
  └─ Glue database → table → columns
       ├─ named-resource / LF-Tag grants
       └─ DataCellsFilter → supported row/cell SELECT
            └─ opted-in or full-enforcement query principal
```

| Resource         | Example responsibility                                                             |
| ---------------- | ---------------------------------------------------------------------------------- |
| Data location    | Permission to create catalog resources pointing at registered data where required. |
| Database         | Catalog creation/description/alteration, not a database-wide SELECT shortcut.      |
| Table            | Supported SELECT/INSERT/ALTER and other table permissions.                         |
| TableWithColumns | Explicit column subset/exclusion where supported.                                  |
| DataCellsFilter  | Row expression plus column/cell selection for supported engines.                   |
| LF-Tag policy    | Grants matching labelled catalog resources; not implicit row tagging.              |

The catalog and storage have different ownership. A data-lake administrator's metadata visibility is not a representative end-user test. Cross-account shares can require resource links/acceptance and consumer-side grants; KMS/source-bucket permissions remain part of the full path.

## Governance migration walkthrough

1. Inventory existing S3/IAM/catalog grants and every query-engine identity.
2. Decide full enforcement versus hybrid access per resource/principal.
3. Register the intended data locations with supported roles/default permissions.
4. Review IAMAllowedPrincipals and existing defaults; do not accidentally leave an IAM-only bypass.
5. Grant explicit reader permissions and configure row/column filters where supported.
6. Query using separate real principals, including a non-opted-in principal if hybrid mode is in use.
7. Compare exact results and verify direct source access cannot bypass the intended boundary.
8. Roll out gradually and retain a scoped rollback plan.

A tag named environment=production can simplify grants across tables, but it does not automatically classify sensitive cells or map an IAM user's department to a row predicate. Use explicit expressions and identity-specific tests. Audit grant option carefully: delegating permission to grant is different from granting read access.

## References

- [Lake Formation permissions](https://docs.aws.amazon.com/lake-formation/latest/dg/lf-permissions-reference.html)
- [Data filters and limitations](https://docs.aws.amazon.com/lake-formation/latest/dg/data-filtering.html)
- [Hybrid access pathways](https://docs.aws.amazon.com/lake-formation/latest/dg/hybrid-access-mode.html)
- [CreateDataCellsFilter contract](https://docs.aws.amazon.com/cli/latest/reference/lakeformation/create-data-cells-filter.html)
- [Retired feature lifecycle](https://docs.aws.amazon.com/general/latest/gr/full_shutdown_services.html)

## Concrete full-enforcement row-filter lab

This lab uses **full Lake Formation enforcement**, not hybrid opt-in, on one new table. Use a private dedicated bucket/prefix, Athena engine v3 workgroup, an authorized Lake Formation administrator, and two **ordinary** IAM roles. Set LF_LAB_BUCKET, LF_LAB_ADMIN_ROLE, LF_LAB_FINANCE_ROLE and LF_LAB_HR_ROLE to actual approved values. Do not use an administrator/owner as the reader.

The administrator needs catalog/S3 fixture setup and LF register/filter/grant/revoke operations. Reader roles need Athena query/status/result operations on the sandbox workgroup, Glue GetDatabase/GetTable/GetPartitions for this catalog, lakeformation:GetDataAccess, and their protected Athena result-prefix access. Do **not** grant readers direct GetObject on the source prefix or broad LF table SELECT; either defeats the isolation test. Configure role-assumption trust and any KMS access separately. No global DataLakeSettings are changed.

The three source records are:

```jsonl
{"id":"f1","department":"finance","amount":10}
{"id":"h1","department":"hr","amount":99}
{"id":"f2","department":"finance","amount":20}
```

Save the following setup as lf_setup.py. Run only as the authorized administrator; all names/locations are dedicated. Service-linked registration requires the corresponding approved IAM/service-linked-role setup.

```python
import json
import os
import boto3

session = boto3.Session()
account = session.client("sts").get_caller_identity()["Account"]
bucket = os.environ["LF_LAB_BUCKET"]
admin = os.environ["LF_LAB_ADMIN_ROLE"]
finance = os.environ["LF_LAB_FINANCE_ROLE"]
hr = os.environ["LF_LAB_HR_ROLE"]
glue = session.client("glue")
lf = session.client("lakeformation")
s3 = session.client("s3")
database, table = "dg05_lab", "ledger"
location = f"arn:aws:s3:::{bucket}/dg05/source"
records = [
    {"id": "f1", "department": "finance", "amount": 10},
    {"id": "h1", "department": "hr", "amount": 99},
    {"id": "f2", "department": "finance", "amount": 20},
]
s3.put_object(
    Bucket=bucket, Key="dg05/source/rows.json",
    Body=("\n".join(json.dumps(r) for r in records) + "\n").encode(),
)
lf.register_resource(ResourceArn=location, UseServiceLinkedRole=True)
lf.grant_permissions(
    Principal={"DataLakePrincipalIdentifier": admin},
    Resource={"DataLocation": {"CatalogId": account, "ResourceArn": location}},
    Permissions=["DATA_LOCATION_ACCESS"],
)
glue.create_database(DatabaseInput={
    "Name": database, "CreateTableDefaultPermissions": [],
})
glue.create_table(
    DatabaseName=database,
    TableInput={
        "Name": table, "TableType": "EXTERNAL_TABLE",
        "StorageDescriptor": {
            "Columns": [
                {"Name": "id", "Type": "string"},
                {"Name": "department", "Type": "string"},
                {"Name": "amount", "Type": "int"},
            ],
            "Location": f"s3://{bucket}/dg05/source/",
            "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
            "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
            "SerdeInfo": {
                "SerializationLibrary": "org.openx.data.jsonserde.JsonSerDe"
            },
        },
    },
)
# Remove any legacy IAM-only grants on these new resources, never globally.
resources = [
    {"Database": {"CatalogId": account, "Name": database}},
    {"Table": {"CatalogId": account, "DatabaseName": database, "Name": table}},
]
for resource in resources:
    for page in lf.get_paginator("list_permissions").paginate(Resource=resource):
        for grant in page["PrincipalResourcePermissions"]:
            if grant["Principal"]["DataLakePrincipalIdentifier"] == "IAM_ALLOWED_PRINCIPALS":
                lf.revoke_permissions(
                    Principal=grant["Principal"], Resource=grant["Resource"],
                    Permissions=grant["Permissions"],
                    PermissionsWithGrantOption=grant.get("PermissionsWithGrantOption", []),
                )
for name, department, role in [
    ("finance_rows", "finance", finance),
    ("hr_rows", "hr", hr),
]:
    lf.create_data_cells_filter(TableData={
        "TableCatalogId": account, "DatabaseName": database,
        "TableName": table, "Name": name,
        "RowFilter": {"FilterExpression": f"department = '{department}'"},
        "ColumnNames": ["id", "department", "amount"],
    })
    lf.grant_permissions(
        Principal={"DataLakePrincipalIdentifier": role},
        Resource={"Database": {"CatalogId": account, "Name": database}},
        Permissions=["DESCRIBE"],
    )
    lf.grant_permissions(
        Principal={"DataLakePrincipalIdentifier": role},
        Resource={"DataCellsFilter": {
            "TableCatalogId": account, "DatabaseName": database,
            "TableName": table, "Name": name,
        }},
        Permissions=["SELECT"],
    )
print("Registered", location, "catalog", account, database, table)
```

Before reading, inspect each reader's effective IAM/LF grants: any extra table SELECT, all-rows filter, source-bucket read or administrator membership invalidates the lab. Configure two CLI/Boto3 profiles that assume the real finance/hr roles. Do not merely set a string variable while leaving administrator credentials active.

Save/run this bounded Athena reader with LF_LAB_READER_PROFILE, LF_LAB_WORKGROUP and LF_LAB_RESULT_URI. The workgroup must permit/enforce the matching protected result location.

```python
import os
import time
import boto3

session = boto3.Session(profile_name=os.environ["LF_LAB_READER_PROFILE"])
print("Reader:", session.client("sts").get_caller_identity()["Arn"])
athena = session.client("athena")
query = athena.start_query_execution(
    QueryString="SELECT id, department, amount FROM dg05_lab.ledger ORDER BY id",
    WorkGroup=os.environ["LF_LAB_WORKGROUP"],
    ResultConfiguration={"OutputLocation": os.environ["LF_LAB_RESULT_URI"]},
)["QueryExecutionId"]
deadline = time.monotonic() + 120
while time.monotonic() < deadline:
    status = athena.get_query_execution(QueryExecutionId=query)["QueryExecution"]["Status"]
    if status["State"] == "SUCCEEDED":
        break
    if status["State"] in {"FAILED", "CANCELLED"}:
        raise RuntimeError(status.get("StateChangeReason", status["State"]))
    time.sleep(2)
else:
    athena.stop_query_execution(QueryExecutionId=query)
    raise TimeoutError("Reader query exceeded deadline")
for page in athena.get_paginator("get_query_results").paginate(QueryExecutionId=query):
    for row in page["ResultSet"]["Rows"]:
        print([x.get("VarCharValue") for x in row["Data"]])
```

Expected data rows (exclude the result header): finance sees f1/finance/10 and f2/finance/20, never h1; HR sees h1/hr/99, never f1/f2. Finance SUM(amount) is 30 and HR is 99. Direct S3 GetObject on dg05/source/rows.json by either reader must be denied. A third role with no LF grant must fail the query; failure due only to missing network/result permission is not a successful row-filter test.

Cleanup as administrator: revoke each reader's SELECT on its exact DataCellsFilter and DESCRIBE on dg05_lab; delete those filters with delete_data_cells_filter(TableCatalogId=account, DatabaseName="dg05_lab", TableName="ledger", Name=...), then delete the dedicated Glue table/database. Revoke the lab DATA_LOCATION_ACCESS grant, deregister only the recorded location ARN, and review/remove exact source/result objects. Do not disable global LF settings or delete shared service-linked roles.

Sources: [data filters](https://docs.aws.amazon.com/lake-formation/latest/dg/data-filtering.html), [CreateDataCellsFilter](https://docs.aws.amazon.com/boto3/latest/reference/services/lakeformation/client/create_data_cells_filter.html), [GrantPermissions](https://docs.aws.amazon.com/boto3/latest/reference/services/lakeformation/client/grant_permissions.html), [IAM-to-LF migration](https://docs.aws.amazon.com/lake-formation/latest/dg/upgrade-glue-lake-formation.html).

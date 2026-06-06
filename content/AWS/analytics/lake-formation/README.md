---
title: AWS Lake Formation
description: AWS Lake Formation — data lake governance, fine-grained permissions, row-level security, table-level access, cross-account sharing, and data catalog security
tags:
  - aws
  - analytics
  - lake-formation
---

# AWS Lake Formation

Lake Formation is AWS's data lake governance service. It sits on top of the Glue Data Catalog and provides centralized permission management — who can access what data at what granularity (database, table, column, row).

## Core Concepts

### Data Lake Architecture

```
Raw S3 (immutable) → Trusted S3 (processed) → Consumer S3 (curated)
     ↓                    ↓                      ↓
  Glue Crawler       Glue ETL              Analytics
  (raw tables)       (trusted tables)      (Athena, Redshift)
         ↓                 ↓                      ↓
      Lake Formation Permissions Layer
```

Lake Formation manages access to all these layers from a single interface.

### Data Lake Formation Workflow

1. **Register S3 locations** — tell Lake Formation which S3 buckets contain your data
2. **Create databases and tables** — either via Glue crawlers or manual creation
3. **Define permissions** — who can access which databases, tables, columns
4. **Enforce LF tags** — tag-based permission policies across many tables

## Registering S3 Locations

```python
import boto3

lf = boto3.client('lakeformation')

# Register an S3 location as a data lake location
lf.register_resource(
    ResourceArn='arn:aws:s3:::my-data-lake-bucket',
    RoleArn='arn:aws:iam::123456789:role/LakeFormationS3Role',
    Description='Main data lake bucket'
)
```

**Requirement:** The Lake Formation service role must have `s3:GetBucketLocation` and `s3:ListBucket` on the bucket.

## Permission Model

Lake Formation permissions work on top of IAM and Lake Formation tag (LF-Tag) based access control.

### Database-Level Permissions

```python
lf.grant_permissions(
    Principal={'DataLakePrincipalIdentifier': 'arn:aws:iam::123456789:user/analyst'},
    Resource={
        'Database': {
            'CatalogId': '123456789012',
            'Name': 'sales_db'
        }
    },
    Permissions=['SELECT'],
    PermissionsWithGrantOption=False
)
```

### Table-Level Permissions

```python
lf.grant_permissions(
    Principal={'DataLakePrincipalIdentifier': 'arn:aws:iam::123456789:user/analyst'},
    Resource={
        'Table': {
            'CatalogId': '123456789012',
            'DatabaseName': 'sales_db',
            'TableName': 'monthly_sales'
        }
    },
    Permissions=['SELECT']
)
```

### Column-Level Permissions

```python
lf.grant_permissions(
    Principal={'DataLakePrincipalIdentifier': 'arn:aws:iam::123456789:user/analyst'},
    Resource={
        'Table': {
            'CatalogId': '123456789012',
            'DatabaseName': 'sales_db',
            'TableName': 'customer_pii',
            'ColumnWildcard': {
                'ExcludedColumns': ['ssn', 'credit_card_number', 'email']
            }
        }
    },
    Permissions=['SELECT']
)
```

**ExcludedColumns** makes those columns invisible to the user — they can't be selected, filtered, or seen in results. This is column-level security without row-level complexity.

### Row-Level Security (Lake Formation)

Row-level security uses LF-Tags to filter data at query time. You tag data with a `department` attribute, and users only see rows matching their department.

```python
# Tag a table with row-level access tag
lf.add_lf_tags(
    LfTags=[
        {'TagKey': 'department', 'TagValues': ['finance', 'analytics']},
        {'TagKey': 'data_classification', 'TagValues': ['internal']}
    ],
    Resource={
        'Table': {
            'CatalogId': '123456789012',
            'DatabaseName': 'sales_db',
            'TableName': 'transactions'
        }
    }
)

# User gets LF-Tag from their IAM principal
# Lake Formation enforces row filter based on tag values at query time
```

## LF-Tags (Tag-Based Access Control)

LF-Tags enable attribute-based access control (ABAC) across your data lake.

### Define LF-Tags

```python
lf.create_lf_tag(
    CatalogId='123456789012',
    TagKey='department',
    TagValues=['finance', 'marketing', 'engineering', 'analytics', 'hr']
)

lf.create_lf_tag(
    CatalogId='123456789012',
    TagKey='data_classification',
    TagValues=['public', 'internal', 'confidential', 'pii']
)
```

### Tag-Based Policies

```python
# Allow users with 'department=finance' tag to access tables tagged with 'department=finance'
lf.create_permissions(
    Principal={'DataLakePrincipalIdentifier': 'arn:aws:iam::123456789:user/finance-user'},
    Resource={
        'LFTagPolicy': {
            'CatalogId': '123456789012',
            'ResourceType': 'TABLE',
            'Expression': [
                {'TagKey': 'department', 'TagValues': ['finance']},
                {'TagKey': 'data_classification', 'TagValues': ['internal', 'confidential']}
            ]
        }
    },
    Permissions=['SELECT', 'ALTER']
)
```

**Use case:** Instead of granting permissions to each table individually, tag all finance-related tables with `department=finance`, then grant access to the tag. New tables with the same tag automatically get access.

## Cross-Account Data Sharing

Lake Formation supports sharing data with other AWS accounts without copying data.

### Share a Table with Another Account

```python
# Create a data cell filter (row-level share)
lf.create_data_cells_filter(
    TableName='sales',
    DatabaseName='sales_db',
    Name='finance-rows',
    RowExpression='department = "finance"',
    Principals=[{'DataLakePrincipalIdentifier': 'arn:aws:iam::123456789012:user/finance-user'}]
)

# Grant access to another account
lf.grant_permissions(
    Principal={'DataLakePrincipalIdentifier': 'arn:aws:iam::123456789012:user/analyst'},
    Resource={
        'Table': {
            'CatalogId': '123456789012',
            'DatabaseName': 'sales_db',
            'TableName': 'sales'
        }
    },
    Permissions=['SELECT']
)
```

### Data Lake Readers (read-only access)

```python
lf.grant_permissions(
    Principal={'DataLakePrincipalIdentifier': 'arn:aws:iam::123456789012:role/DataReaderRole'},
    Resource={
        'Database': {'Name': 'sales_db'}
    },
    Permissions=['DESCRIBE']
)
```

## Integration with Athena and Redshift

Athena and Redshift Spectrum respect Lake Formation permissions. When a user queries a table through Athena, Lake Formation checks their permissions and applies column-level and row-level filters automatically.

**Athena with Lake Formation:**
```sql
-- User can only see columns and rows they're permitted to access
SELECT user_id, department, SUM(amount)
FROM sales_db.transactions
WHERE date >= '2024-01-01'
GROUP BY user_id, department;
-- Returns only rows matching the user's LF-Tag permissions
```

**Redshift Spectrum with Lake Formation:**
```sql
-- Same enforcement — Spectrum queries go through Lake Formation permissions
SELECT * FROM spectrum.transactions WHERE amount > 1000;
```

## Security Best Practices

1. **Register only specific S3 buckets**, not entire accounts
2. **Use LF-Tags for scalable permission management** instead of per-table grants
3. **Enable column-level security** for PII columns (exclude from analyst access)
4. **Use row-level filters** for department isolation
5. **Audit with CloudTrail** — Lake Formation API calls are logged
6. **Separate data lake access roles** — ETL role vs analyst role vs data engineer role

## Blueprint Templates

Lake Formation provides blueprint templates for common data lake architectures:

- **Incremental data:** CDC (change data capture) from RDS MySQL/PostgreSQL
- **Transformed data:** ETL pipeline from raw S3 to curated tables
- **Full load:** Full table replication from JDBC sources

Blueprints create CloudFormation stacks with Step Functions, Glue crawlers, and Glue jobs that implement the pattern.

## Migration from IAM-Only to Lake Formation Permissions

If you previously managed access via IAM policies on S3/Glue, Lake Formation provides a migration path:

1. **Enable Lake Formation permissions mode** in the Data Catalog settings
2. **Grant temporary elevated permissions** to administrators during transition
3. **Gradually migrate** IAM-based access to Lake Formation permission grants
4. **Revoke IAM-only access** once all access is managed through Lake Formation

**Important:** After enabling Lake Formation, IAM policies alone no longer grant access to data lake resources. You must use Lake Formation permission grants.
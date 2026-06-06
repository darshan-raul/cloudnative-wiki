---
title: Database Migration Service (DMS)
description: AWS DMS — database migration types (full load, CDC, full+CDC), endpoint configuration, replication instance sizing, schema conversion with SCT, and best practices
tags:
  - aws
  - migration
  - database
---

# Database Migration Service (DMS)

DMS migrates databases between on-premises and AWS, or between different database engines. It handles the data migration with continuous replication capability, minimizing downtime during cutover.

## Architecture

```
Source Database          Replication Instance         Target Database
(on-prem or AWS)         (DMS EC2-based)              (RDS, Aurora, EC2)
       ↓                        ↓                        ↑
Full Load ────────────────────→│                        │
       ↓                        │                        │
CDC Changes ─────────────────→│────────────────────────→
```

The replication instance is a managed EC2 instance that runs the migration logic. It connects to source and target endpoints, extracts data, transforms if needed, and loads into the target.

## Migration Types

### Full Load

One-time bulk copy of all tables. Fast, but source must be offline during cutover.

**Best for:** Non-production migrations, small databases with low tolerable downtime.

### Change Data Capture (CDC)

Captures ongoing changes from the source after the initial load and applies them to the target. Requires the source database to support change tracking (binlog for MySQL, redo log for Oracle, WAL for PostgreSQL).

**Best for:** Production databases where downtime must be minimized.

### Full Load + CDC

Initial bulk load + continuous replication of changes. Best of both worlds — fast initial load, then catch up with CDC before final cutover.

**Best for:** Production databases with large datasets and minimal downtime requirements.

## Key Concepts

### Endpoints

```bash
# Create source endpoint (MySQL)
aws dms create-endpoint \
  --endpoint-identifier prod-mysql-source \
  --endpoint-type source \
  --engine-name mysql \
  --mysql-settings '{"Port": 3306, "HostName": "mysql-source.example.com", "DatabaseName": "orders"}' \
  --secrets-manager-arn 'arn:aws:secretsmanager:us-east-1:123456789012:secret:dms/mysql-creds'

# Create target endpoint (RDS PostgreSQL)
aws dms create-endpoint \
  --endpoint-identifier prod-rds-target \
  --endpoint-type target \
  --engine-name postgres \
  --rds-settings '{"InstanceArn": "arn:aws:rds:us-east-1:123456789012:db:orders-rds"}'

# Create target endpoint (S3 for data lake migration)
aws dms create-endpoint \
  --endpoint-identifier s3-target \
  --endpoint-type target \
  --engine-name s3 \
  --s3-settings '{
    "BucketName": "orders-landing-zone",
    "BucketFolder": "raw/orders",
    "ServiceAccessRoleArn": "arn:aws:iam::123456789012:role/dms-s3-role"
  }'
```

### Replication Instance

```bash
aws dms create-replication-instance \
  --replication-instance-identifier dms-repl-prod \
  --replication-instance-class dms.t3.large \
  --allocated-storage 100 \
  --vpc-security-group-ids sg-0123456789abcdef0 \
  --subnet-group-name dms-subnet-group \
  --no-multi-az
```

**Sizing guide:**
- `dms.t3.small` — Small databases (< 100GB), no CDC
- `dms.t3.medium` — Medium databases (100GB-1TB), simple CDC
- `dms.t3.large` — Large databases (1TB+), complex transformations
- `dms.c7g.large` — Graviton-based, better price/performance

### Table Mappings

```json
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": 1,
      "rule-name": "migrate-public-schema",
      "object-locator": {
        "schema-name": "public",
        "table-name": "%"
      },
      "rule-action": "include"
    },
    {
      "rule-type": "transformation",
      "rule-id": 2,
      "rule-name": "lowercase-table-names",
      "object-locator": {
        "schema-name": "public",
        "table-name": "%"
      },
      "rule-action": "rename",
      "rule-target": "table",
      "parameters": {
        "target-table-name-template": "${table-name}"
      }
    }
  ]
}
```

**Transformation examples:**
- Rename tables (lowercase, remove prefixes)
- Add columns (e.g., `migration_timestamp`)
- Convert data types
- Filter rows (only migrate where `status = 'active'`)

## Homogeneous vs Heterogeneous

### Homogeneous (Same Engine)

```bash
# MySQL → RDS MySQL (homogeneous)
# No schema conversion needed — DMS handles everything
aws dms create-replication-task \
  --replication-task-identifier mysql-to-rds \
  --source-endpoint-arn $SOURCE_ARN \
  --target-endpoint-arn $TARGET_ARN \
  --replication-instance-arn $REPL_ARN \
  --migration-type full-load-and-cdc \
  --table-mappings file://table-mappings.json
```

### Heterogeneous (Different Engine)

Requires the Schema Conversion Tool (SCT) as a pre-processing step:

```
1. Use SCT to convert schema (Oracle schema → PostgreSQL schema)
2. Apply converted schema to target database
3. Use DMS to migrate data (now schemas match)
```

**Typical heterogeneous scenarios:**
- Oracle → PostgreSQL (RDS/Aurora)
- SQL Server → PostgreSQL
- Oracle → MySQL
- PostgreSQL → Oracle

```bash
# After SCT converts schema, run DMS
aws dms create-replication-task \
  --replication-task-identifier oracle-to-postgres \
  --source-endpoint-arn $ORACLE_ARN \
  --target-endpoint-arn $POSTGRES_ARN \
  --replication-instance-arn $REPL_ARN \
  --migration-type full-load-and-cdc \
  --table-mappings file://table-mappings.json
```

## CDC Configuration

### MySQL (binlog-based CDC)

On the source MySQL:
```sql
-- Ensure binlog is enabled
SHOW VARIABLES LIKE 'log_bin';

-- Set binlog format to ROW
SET GLOBAL binlog_format = ROW;

-- Set binlog_row_image = FULL
SET GLOBAL binlog_row_image = FULL;

-- Create DMS user with appropriate permissions
CREATE USER 'dms_user'@'%' IDENTIFIED BY 'password';
GRANT REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'dms_user'@'%';
GRANT SELECT ON orders.* TO 'dms_user'@'%';
```

### PostgreSQL (WAL-based CDC)

On the source PostgreSQL:
```sql
-- Enable logical replication
ALTER DATABASE orders SET wal_level = logical;

-- Create replication slot for DMS
SELECT * FROM pg_create_logical_replication_slot('dms_slot', 'pgoutput');

-- Create DMS user with replication permissions
CREATE USER dms_user WITH REPLICATION PASSWORD 'password';
GRANT CONNECT ON DATABASE orders TO dms_user;
GRANT USAGE ON SCHEMA public TO dms_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dms_user;
```

### Oracle (redo log-based CDC)

Oracle uses Oracle LogMiner (built-in) or AWS XDB (more efficient for large volumes):
```sql
-- Enable supplemental logging
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Create DMS user
CREATE USER dms_user IDENTIFIED BY password;
GRANT CONNECT TO dms_user;
GRANT SELECT ON V_$LOG TO dms_user;
GRANT SELECT ON V_$LOGFILE TO dms_user;
GRANT SELECT ON V_$INSTANCE TO dms_user;
GRANT SELECT ANY TRANSACTION TO dms_user;
```

## Monitoring

```bash
# Check task status
aws dms describe-replication-tasks \
  --filters "Name=replication-task-id,Values=migrate-orders"

# Get table statistics
aws dms describe-table-statistics \
  --replication-task-arn $TASK_ARN

# CloudWatch metrics to monitor
# - CDCChangesMemorySourceRate (changes being captured)
# - CDCChangesTargetRate (changes being applied to target)
# - FullLoadBytes (data loaded so far)
# - CDCIncomingChanges (pending changes from source)
# - ReplicationSlotStorage (WAL retention for PostgreSQL)
```

**Key metrics to watch:**
- `CDCIncomingChanges` — if this grows continuously, the instance can't keep up
- `FreeStorageSpace` — low space on replication instance = performance issues
- `FreeMemory` — low memory = DMS struggling to handle data volume

## Troubleshooting

### Common Errors

**Error: "Table X does not exist"**
→ Target table doesn't exist. Run the schema conversion step (SCT for heterogeneous) or create the table manually.

**Error: "Binary logging is not enabled"**
→ Source MySQL doesn't have binlog enabled. Enable it and restart MySQL.

**Error: "WAL level is not set to logical"**
→ Source PostgreSQL needs `wal_level = logical` in postgresql.conf.

**Error: "ORA-00845: MEMORY_TARGET not supported"**
→ Oracle on AWS RDS with incorrect memory settings. Adjust `memory_target` parameter.

### Performance Tuning

```bash
# For large tables, increase task parallel threads
aws dms modify-replication-task \
  --replication-task-arn $TASK_ARN \
  --cdc-timeout=120

# Adjust max capacity for the replication instance
aws dms describe-replication-instances
aws dms reboot-instance --replication-instance-arn $REPL_ARN
```

**Sizing tips:**
- If source has many large tables, use higher ParallelThreads setting
- If target is slow (indexes being built), reduce `MaxBatchSize`
- Monitor replication instance CPU/memory — if consistently high, upgrade instance class

## Best Practices

1. **Test with small subset first:** Migrate one table or schema as a test before full migration
2. **Use SCT for heterogeneous migrations:** Don't skip schema conversion step
3. **Set appropriate WAL retention:** For CDC on PostgreSQL, ensure `wal_keep_size` is large enough to cover migration window
4. **Validate after full load:** Run row count checks and spot checks on data before enabling CDC
5. **Pause source schema changes during migration:** Any schema change (ALTER TABLE) during migration can break the task
6. **Use tasks for validation, not just migration:** Create a validation task to compare source and target counts automatically

## S3 Target for Data Lake Migration

For migrating databases into a data lake format (Parquet/ORC in S3):

```bash
aws dms create-endpoint \
  --endpoint-identifier s3-orders-landing \
  --endpoint-type target \
  --engine-name s3 \
  --s3-settings '{
    "BucketName": "orders-landing-zone",
    "BucketFolder": "raw/orders",
    "ServiceAccessRoleArn": "arn:aws:iam::123456789012:role/dms-s3-role",
    "DatePartitionEnabled": true,
    "DatePartitionSequence": "YYYY/MM/DD",
    "CsvRowDelimiter": "\\n",
    "CsvDelimiter": ","
  }'
```

The S3 target writes database tables as CSV or Parquet files in S3, with optional date partitioning for Hive-style folder structures.

## Cost

- **Replication instance:** Charged per hour based on instance class (~$0.10-$0.50/hr for typical sizes)
- **Storage:** EBS volumes for replication instance
- **Data transfer:** In same AZ, no charge. Cross-AZ or cross-region, standard data transfer rates apply
- **Secrets Manager:** If using, costs for secret storage

**Cost tip:** Stop the replication instance after migration completes. You don't need it running if you're not doing ongoing replication.
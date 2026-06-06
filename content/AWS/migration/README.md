---
title: AWS Migration
description: AWS migration services — DMS for database migration, DataSync for file transfer, Application Migration Service (MGN) for lift-and-shift, Migration Evaluator, and Application Discovery Service
tags:
  - aws
  - migration
---

# AWS Migration

AWS offers a suite of migration services spanning discovery, assessment, and actual data/cluster migration. These services cover the full migration lifecycle from lift-and-shift to re-architecting.

## Service Map

| Service | What It Does | When to Use |
|---------|--------------|-------------|
| **Application Discovery Service** | Discovers on-prem infrastructure (servers, dependencies) via agentless/agent-based collectors | Before migration — planning and sizing |
| **Migration Evaluator** | Analyzes on-prem environment and generates TCO report for AWS | Business case and cost estimation |
| **Application Migration Service (MGN)** | Lift-and-shift — replicates live servers to AWS, cutover with near-zero downtime | Lift-and-shift migrations |
| **Database Migration Service (DMS)** | Migrates databases (homogeneous and heterogeneous) with continuous replication | Database migrations |
| **DataSync** | Transfers files between on-prem storage and S3/EFS/FSx | Bulk data transfer for migrations |
| **Server Migration Service (SMS)** | Older service, superseded by MGN | Legacy — use MGN instead |

## Migration Strategies

### The 6 Rs

1. **Rehost** (lift-and-shift) — Move without changes. MGN for servers, DMS for databases.
2. **Replatform** (lift-tinker-and-shift) — Make minimal changes to exploit cloud capabilities. Example: migrate to RDS.
3. **Repurchase** — Move to a different product (SaaS).
4. **Refactor** (re-architect) — Change architecture to use cloud-native services.
5. **Retire** — Decommission instead of migrating.
6. **Retain** — Keep on-premises for now.

### Migration Hub

AWS Migration Hub provides a single dashboard to track the progress of migrations across multiple AWS tools (MGN, DMS, DataSync). It maps applications to migration tools and shows status in one place.

```
Application Portfolio
    ↓
Discovery → Assessment → Migration Strategy → Execution → Validation
    ↓           ↓              ↓                ↓
  ADS       Evaluator        MGN              DMS
                              ↓              DataSync
                          Migration Hub (track all)
```

## Discovery and Assessment Phase

### Application Discovery Service

```bash
# Agentless discovery (no software on source)
aws discovery start-agentless-collector-scan \
  --region us-east-1 \
  --collectors ['AGENTLESS']

# Agent-based discovery (install on each server)
# Download the collector agent from AWS console
# Agent collects: server specs, running processes, network connections, performance data

# Get discovered servers
aws discovery list-servers --region us-east-1

# Export discovered data as CSV for analysis
aws discovery get-discovered-resource-summary --region us-east-1
```

**What it discovers:**
- Server hardware specs (CPU, RAM, storage)
- Installed software and versions
- Network connections between servers (dependency mapping)
- Performance utilization (CPU, memory, disk I/O over time)
- Running processes and services

**Output:** Server dependency diagram showing which servers communicate with which. Critical for understanding blast radius when migrating.

### Migration Evaluator

Migration Evaluator (formerly TSO Logic) analyzes your on-prem environment and generates a Total Cost of Ownership (TCO) comparison:

```bash
# Create an assessment
aws migrationevaluator create-assessment \
  --name "prod-migration" \
  --s3-bucket-config '{"Bucket": "my-assessments", "KeyPrefix": "assessments/"}'
```

**Assessment output:**
- Monthly AWS cost estimate (compute, storage, networking)
- Right-sized EC2 recommendations
- Recommended instance families
- Migration strategy per server (rehost, replatform, refactor)
- 3-year TCO comparison vs on-premises

### Discovery Data Import

You can import existing discovery data (from CMDBs, cloud providers) into Migration Hub:

```bash
# Import connector data
aws discovery start-import-task \
  --name "import-cmdb" \
  --import-data-format "AGENTLESS"
```

## Replication and Cutover Phase

### Application Migration Service (MGN)

MGN is the current-generation lift-and-shift service for Windows and Linux servers.

**How it works:**
1. Install the MGN agent on the source server
2. Agent continuously replicates changes to a staging area in your AWS account (S3 + EBS snapshots)
3. When ready to cut over, initiate a test launch or final cutover
4. MGN converts the replicated server to a proper AWS-native instance

```bash
# Install MGN agent on source server (Linux)
# Download from: https://docs.aws.amazon.com/mgn/latest/ug/download-replication-agent.html
sudo ./install replication agent --aws-region us-east-1 --registration-endpoint https://mgn.us-east-1.amazonaws.com
# Follow prompts to provide Source Server ID and VPC/Subnet for replication

# Install MGN agent on source server (Windows)
# Download the installer, run as Administrator, follow wizard

# Create a wave (group of servers for coordinated cutover)
aws mgn create-wave \
  --account-id 123456789012 \
  --name "production-wave-1"

# Add servers to wave
aws mgn add-source-servers-to-wave \
  --wave-id w-1234567890abcdef0 \
  --source-server-ids s-1234567890abcdef0 s-0987654321fedcba0

# Initiate cutover (test launch)
aws mgn start-cutover \
  --source-server-id s-1234567890abcdef0 \
  --target-instance '{"instanceType": "t3.medium", "vpcSecurityGroupIds": ["sg-0123456789abcdef0"], "subnetId": "subnet-0123456789abcdef0"}'

# Complete cutover (finalize the migration)
aws mgn complete-cutover \
  --source-server-id s-1234567890abcdef0
```

**Key features:**
- **Continuous replication:** Data synced continuously, not batch
- **Wave management:** Group servers into waves for coordinated cutover
- **Throttling:** Control replication bandwidth to avoid impacting production workloads
- **Post-launch validation:** Automated checks after launch (ping, port, performance)
- **Cutover modes:** Test launch (non-destructive), final cutover

**Cutover workflow:**
```
Agent installed → Continuous replication (hours/days)
    ↓
User ready to migrate → Test launch (validates it works)
    ↓
Post-migration validation → Checks pass?
    ↓
Final cutover → Original server can be shut down
```

### Database Migration Service (DMS)

DMS migrates databases with minimal downtime using change data capture (CDC).

```bash
# Create an endpoint (source)
aws dms create-endpoint \
  --endpoint-identifier source-postgres \
  --endpoint-type source \
  --engine-name postgres \
  --mysql-settings '{"Port": 5432, "HostName": "source-db.example.com", "DatabaseName": "production"}' \
  --secrets-manager-arn 'arn:aws:secretsmanager:us-east-1:123456789012:secret:dms/source-postgres'

# Create an endpoint (target)
aws dms create-endpoint \
  --endpoint-identifier target-rds \
  --endpoint-type target \
  --engine-name postgres \
  --rds-settings '{"InstanceArn": "arn:aws:rds:us-east-1:123456789012:db:target-rds-instance"}'

# Create a replication instance
aws dms create-replication-instance \
  --replication-instance-identifier dms-repl \
  --replication-instance-class dms.t3.medium \
  --allocated-storage 50 \
  --vpc-security-group-ids sg-0123456789abcdef0 \
  --subnet-group-name dms-subnet-group

# Create a migration task
aws dms create-replication-task \
  --replication-task-identifier migrate-orders \
  --source-endpoint-arn arn:aws:dms:us-east-1:123456789012:endpoint:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij \
  --target-endpoint-arn arn:aws:dms:us-east-1:123456789012:endpoint:ABCDEFGHIJKLMNOPQRSTUVWXYZ123456 \
  --replication-instance-arn arn:aws:dms:us-east-1:123456789012:rep:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij \
  --migration-type full-load-and-cdc \
  --table-mappings '{"rules": [{"rule-type": "selection", "rule-id": 1, "rule-name": "migrate-all", "object-locator": {"schema-name": "public", "table-name": "orders"}, "rule-action": "include"}]}'

# Start the task
aws dms start-replication-task \
  --replication-task-arn arn:aws:dms:us-east-1:123456789012:task:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij
```

**Migration types:**
- **Full load:** One-time bulk copy. Fast but requires downtime during cutover.
- **Full load + CDC:** Bulk copy + continuous replication of changes. Best for minimal downtime.
- **CDC only:** Migrate existing data first manually, then use CDC for changes.

**Homogeneous vs Heterogeneous:**
- **Homogeneous:** Same engine (Postgres to Postgres). DMS handles schema conversion automatically.
- **Heterogeneous:** Different engines (Oracle to PostgreSQL). Requires schema conversion step using AWS SCT (Schema Conversion Tool).

### Schema Conversion Tool (SCT)

For heterogeneous database migrations (Oracle → PostgreSQL, SQL Server → MySQL):

```bash
# Install SCT on a Windows/Linux workstation
# Download from: https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/WhatIs.html

# Convert schema:
# 1. Connect to source (Oracle)
# 2. Connect to target (PostgreSQL/RDS)
# 3. Select schema to convert
# 4. Review conversion report (action items, unsupported features)
# 5. Apply converted schema to target

# Generate assessment report
aws schema-conversion-tool create-assessment \
  --source-engine oracle \
  --target-engine postgres
```

**When to use SCT:**
- Oracle → RDS PostgreSQL / Aurora PostgreSQL
- SQL Server → RDS SQL Server / RDS PostgreSQL
- Teradata → Redshift
- Netezza → Redshift

### DataSync

For migrating large file datasets to S3, EFS, or FSx:

```bash
# Create an agent (for on-prem NFS/SMB storage)
aws datasync create-agent \
  --agent-arn 'arn:aws:datasync:us-east-1:123456789012:agent/agent-abcdef01234567890' \
  --activation-key 'XXXX-YYYY-ZZZZ'

# Create a location (source NFS on-prem)
aws datasync create-location-nfs \
  --server-hostname 192.168.1.100 \
  --subdirectory /data/shared \
  --on-prem-config AgentArns=['arn:aws:datasync:us-east-1:123456789012:agent/agent-abcdef01234567890']

# Create a location (target S3)
aws datasync create-location-s3 \
  --s3-bucket-arn arn:aws:s3:::my-migration-bucket \
  --s3-prefix "migration/2024-06/" \
  --s3-config '{"BucketAccessRoleArn": "arn:aws:iam::123456789012:role/DataSyncS3Role"}'

# Create a task
aws datasync create-task \
  --source-location-arn arn:aws:datasync:us-east-1:123456789012:location/loc-abcdef01234567890 \
  --destination-location-arn arn:aws:datasync:us-east-1:123456789012:location/loc-987654321abcdef0 \
  --cloud-watch-log-group-arn arn:aws:logs:us-east-1:123456789012:log-group:/aws/datasync/migration \
  --options '{"VerifyMode": "POINT_IN_TIME_CONSISTENT", "Atime": "NONE", "Mtime": "PRESERVE", "Uid": "INT preserved", "Gid": "INT preserved", "PreserveDeletedFiles": "PRESERVE"}'

# Start the task
aws datasync start-task-execution \
  --task-arn arn:aws:datasync:us-east-1:123456789012:task/task-abcdef01234567890
```

**DataSync options:**
- `Mtime`: Preserve modification time (important for incremental sync)
- `VerifyMode`: NONE (skip verify), POINT_IN_TIME_CONSISTENT (verify full), OVERWRITE (verify overwritten files)
- `PreserveDeletedFiles`: Keep deleted files in target or remove them
- `TaskScheduling`: Schedule recurring transfers (cron-like)

**DataSync vs DMS:**
- DataSync: File-based transfers (NFS, SMB, S3). No database support.
- DMS: Database migrations (full load or CDC). Not for files.

## Cutover and Validation

### Validating After Migration

```bash
# DMS: Compare row counts between source and target
aws dms describe-replication-tasks --filters "Name=replication-task-id,Values=migrate-orders"

# MGN: Check replication status
aws mgn describe-source-servers --filters "Name=source-server-id,Values=s-1234567890abcdef0"

# DataSync: Check task execution status
aws datasync describe-task-execution --task-execution-arn arn:aws:datasync:us-east-1:123456789012:task-execution/...
```

### Post-Migration Validation

After cutover, validate:
1. **Data integrity:** Row counts match, no missing records
2. **Application connectivity:** App can connect to migrated database
3. **Performance:** Query latency within acceptable range
4. **Replication lag:** For CDC migrations, lag is near zero after cutover
5. **DNS cutover:** All applications pointing to new endpoint

## TCO Estimation

```python
# Rough TCO estimation for migration
def estimate_monthly_cost(servers):
    """Estimate AWS monthly cost for migrated servers"""
    total = 0
    for srv in servers:
        # EC2 instance cost (rough estimates, check AWS pricing)
        instance_costs = {
            'small': 30,    # t3.micro
            'medium': 60,   # t3.small
            'large': 120,   # t3.medium
            'xlarge': 240,  # t3.xlarge
        }
        # EBS storage cost
        storage_cost_per_gb = 0.10  # gp3
        # Network cost estimate
        network_cost = 20  # rough estimate
        
        monthly = (
            instance_costs[srv['size']] +
            (srv.get('storage_gb', 100) * storage_cost_per_gb) +
            network_cost
        )
        total += monthly
    return total
```

## Migration Hub Tracking

```bash
# Register an application in Migration Hub
aws migrationhub create-application \
  --name "order-service" \
  --description "Order processing service" \
  --integration-template '{"MGN": true, "DMS": true}'

# Update migration status
aws migrationhub update-application-state \
  --application-id app-1234567890abcdef0 \
  --status COMPLETED
```

## Cost Optimization for Migration

- **MGN:** Pay per replicated server-hour. Stop replication after cutover.
- **DMS:** Pay per replication instance hour + data transfer. Stop after full migration if not needed for ongoing replication.
- **DataSync:** Pay per GB transferred. For large migrations, DataSync is cheaper than manual transfer.
- **S3 Intelligent-Tiering:** For migration staging areas (temporary data), use Intelligent-Tiering to avoid paying for Standard storage.

## References

- **Homepage:** https://aws.amazon.com/products/database-migration/
- **Documentation:** https://docs.aws.amazon.com/dms/latest/userguide/
- **Pricing:** https://aws.amazon.com/database-migration-service/pricing/

## Pricing Examples

**Scenario 1:** Migrating a 10TB PostgreSQL database to RDS PostgreSQL using DMS. One replication instance (dms.t3.medium = $0.168/hr = $120/month) + 10TB one-time transfer over DataSync (10TB × $0.003/GB = $30). Total migration cost: ~$150 one-time + minimal ongoing replication (stop after cutover). Manual approach: shipping 10TB Snowball would cost ~$200 + transfer time.

**Scenario 2:** An ongoing CDC migration from Oracle to Aurora PostgreSQL for a 1TB database. DMS replication instance (dms.t3.large = $0.336/hr = $240/month) + CDC data transfer (1TB/month × $0.02/GB = $20). Total: ~$260/month ongoing. vs Oracle licensing for the source: $40K/year. The DMS cost is a fraction of the licensing savings.

## Nuggets & Gotchas

- **DMS replication instance runs 24/7 during migration:** A dms.r5.large at $0.51/hr runs $367/month. Even if you're only actively migrating for 2 weeks, you're paying for the full month. Size the instance appropriately and terminate when done.
- **DMS CDC uses CDC credits:** Small replication instances have CDC credit limits. For busy OLTP databases with high write rates, the CDC backlog can exceed the credit limit, causing replication lag. Monitor `CDCIncomingChanges` CloudWatch metric.
- **DataSync has a per-TB cost that jumps at 50TB:** First 50TB/month is $0.003/GB ($3/TB). Above 50TB, the rate changes. For very large migrations, calculate the total cost and compare to Snowball ($0.003/GB + shipping).
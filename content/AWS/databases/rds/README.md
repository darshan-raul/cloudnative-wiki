---
title: Amazon RDS
description: Amazon RDS — managed relational database. Multi-AZ, read replicas, automated backups, parameter groups, option groups, engine comparison (MySQL, PostgreSQL, MariaDB, Oracle, SQL Server).
tags:
  - aws
  - databases
  - rds
---

# Amazon RDS (Relational Database Service)

RDS provides managed relational databases: MySQL, PostgreSQL, MariaDB, Oracle, and SQL Server. AWS handles provisioning, patching, backups, Multi-AZ, and monitoring. You manage application-level optimization, query performance, and instance sizing.

## Engines

| Engine | Version | Use Case | License |
|--------|---------|----------|---------|
| MySQL | 5.7, 8.0 | Web apps, SaaS | Open source |
| PostgreSQL | 13, 14, 15, 16 | Enterprise, geospatial | Open source |
| MariaDB | 10.2, 10.3, 10.4, 10.5, 10.6, 10.11 | MySQL drop-in replacement | Open source |
| Oracle | 19c, 21c | Enterprise (existing Oracle apps) | BYOL or Oracle License |
| SQL Server | 2014, 2016, 2017, 2019, 2022 | Windows/.NET apps | BYOL or SQL Server License |

## Instance Classes

```
db.t3.micro      → Burstable (2 vCPU, 1 GB)
db.m5.large      → General (2 vCPU, 8 GB)
db.m5.xlarge     → General (4 vCPU, 16 GB)
db.r6g.large     → Memory optimized (2 vCPU, 16 GB)
db.r6g.xlarge    → Memory optimized (4 vCPU, 32 GB)
db.r6g.2xlarge   → Memory optimized (8 vCPU, 64 GB)
db.m5.24xlarge   → High CPU (96 vCPU, 384 GB)
```

**Current gen (use these):** T3, M5, M6I, R5, R6I, R6G
**Previous gen (avoid for new):** T2, M4, R4

## Creating a DB Instance

### Via Console

RDS → Create database → Choose engine → Select use case (Production/Dev) → Configure settings

### Via CLI

```bash
aws rds create-db-instance \
  --db-instance-identifier my-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 15.3 \
  --master-username postgres \
  --master-user-password SecretPassword \
  --allocated-storage 20 \
  --storage-type gp3 \
  --vpc-security-group-ids sg-xxxxx \
  --db-subnet-group my-subnet-group \
  --backup-retention-period 7 \
  --multi-az \
  --preferred-backup-window 03:00-04:00 \
  --preferred-maintenance-window sun:04:00-sun:05:00
```

## High Availability (Multi-AZ)

### How It Works

```
Primary (AZ-1) ◄─────── Sync replication ────────► Standby (AZ-2)
     │
     │  Async replication
     ▼
Read Replica (AZ-3)
```

When Multi-AZ is enabled:
- Synchronous replication to standby in different AZ
- Automatic failover (< 60 seconds, typically 20-30 seconds)
- No application code changes needed (endpoint stays the same)
- Standby cannot be used for reads (it's a hot standby)

### Failover Trigger Conditions

- AZ outage (primary AZ goes down)
- Instance failure (EC2 host hardware/software failure)
- Manual failover (`aws rds reboot-db-instance --force-failover`)
- Maintenance events requiring reboot

## Read Replicas

Asynchronous replication for read scaling:

```bash
# Create read replica
aws rds create-db-instance-read-replica \
  --db-instance-identifier my-db-replica \
  --source-db-instance-identifier my-db \
  --db-instance-class db.t3.micro \
  --no-multi-az
```

### Use Cases

- Scale read-heavy workloads
- Analytics/reporting queries
- Cross-region DR
- Major version upgrades (by promoting replica)

### Limitations

- Asynchronous (some lag, typically < 1 second)
- Not automatically promoted on primary failure
- Replica lag is visible in CloudWatch (`ReplicaLag` metric)
- Binary log (MySQL) or WAL (PostgreSQL) must be enabled

## Automated Backups

```bash
# Backup settings (set at creation)
--backup-retention-period 7      # days (0 to disable)
--backup-window 03:00-04:00      # start time
--preferred-backup-window 03:00-04:00
```

### Restoring

```bash
# Restore to point in time
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier my-db \
  --target-db-instance-identifier my-db-restored \
  --restore-time 2024-01-15T10:00:00Z

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier my-db-restored \
  --db-snapshot-identifier my-snapshot
```

**Important:** Restoring creates a NEW instance with a new endpoint. You must update your application to point to the new endpoint.

## Parameter Groups

Database configuration (like `my.cnf` or `postgresql.conf`):

```bash
# Create parameter group
aws rds create-db-parameter-group \
  --db-parameter-group-name my-custom-params \
  --db-parameter-group-family postgres15 \
  --description "Custom parameters"

# Modify parameters
aws rds modify-db-parameter-group \
  --db-parameter-group-name my-custom-params \
  --parameters '[
    {"ParameterName": "max_connections", "ParameterValue": "200", "ApplyMethod": "pending-reboot"},
    {"ParameterName": "work_mem", "ParameterValue": "4096", "ApplyMethod": "immediate"}
  ]'
```

Common parameters:
- `max_connections` — max concurrent connections
- `shared_buffers` — PostgreSQL buffer cache
- `innodb_buffer_pool_size` — MySQL buffer pool
- `log_min_duration_statement` — slow query threshold

## Option Groups

Add features (Oracle ASM, SQL Server Transparent Data Encryption, etc.):

```bash
# Add option to option group
aws rds modify-option-group \
  --option-group-name my-option-group \
  --options '[{"OptionName": "MEMCACHED", "VpcSecurityGroupMemberships": ["sg-xxxxx"]}]'
```

## Enhanced Monitoring

```bash
# Enable enhanced monitoring
aws rds modify-db-instance \
  --db-instance-identifier my-db \
  --monitoring-interval 60 \
  --monitoring-role-arn arn:aws:iam::123456789012:role/rds-monitoring-role
```

Key metrics (CloudWatch vs Enhanced Monitoring):
- CloudWatch: CPU, Connections, Disk queue depth, Swap usage
- Enhanced: OS-level (processes, memory, I/O per process)

## Connecting

```bash
# Get endpoint
aws rds describe-db-instances \
  --db-instance-identifier my-db \
  --query 'DBInstances[0].Endpoint'

# PostgreSQL
psql -h my-db.xxxxx.us-east-1.rds.amazonaws.com -U postgres -d mydb

# MySQL
mysql -h my-db.xxxxx.us-east-1.rds.amazonaws.com -u postgres -p mydb

# SSL
psql "host=my-db.xxxxx.rds.amazonaws.com port=5432 dbname=mydb sslmode=require"
```

## Performance Insights

DBA (Database Inspector) for real-time SQL analysis:

```bash
# Enable Performance Insights
aws rds modify-db-instance \
  --db-instance-identifier my-db \
  --enable-performance-insights \
  --performance-insights-kms-key-id arn:aws:kms:us-east-1:123456789012:key/xxxxx
```

View in Console: RDS → Instances → my-db → Performance Insights

## Pricing

| Component | Cost |
|-----------|------|
| db.t3.micro | $0.017/hr (~$12/month) |
| db.m5.large | $0.136/hr (~$98/month) |
| db.r6g.xlarge | $0.252/hr (~$181/month) |
| Multi-AZ | 2x instance cost |
| Read Replica | Same as single instance |
| Storage (gp3) | $0.08/GB/month |
| Backup storage | $0.095/GB/month |
| Data transfer | $0.02-0.09/GB |

## Storage Types

| Type | Description | Use |
|------|-------------|-----|
| gp3 | General purpose SSD, 3000 IOPS baseline | General workloads |
| gp2 | General purpose SSD, burst to 3000 IOPS | Legacy |
| io1 | Provisioned IOPS (up to 64,000) | High IOPS (64K+) |
| io2 | Provisioned IOPS (up to 256,000) | Highest IOPS |
| io2 Block Express | Up to 256,000 IOPS, 64 TB | Maximum performance |

## Limits

| Resource | Limit |
|----------|-------|
| DB instances per region | 40 (soft) |
| Storage per instance | 64 TB |
| Max databases per instance | MySQL: unlimited, PostgreSQL: unlimited |
| Max connections | db.t3.micro: 100, db.m5.xlarge: 1000+ |
| Parameter groups per region | 50 |
| Read replicas per primary | 5 (MySQL/MariaDB), 5 (PostgreSQL) |

## References

- **Homepage:** https://aws.amazon.com/rds/
- **Documentation:** https://docs.aws.amazon.com/AmazonRDS/
- **Pricing:** https://aws.amazon.com/rds/pricing/

## Pricing Examples

**Scenario 1:** A small production PostgreSQL database (db.m5.large, Multi-AZ). On-Demand: $0.136/hr × 2 (Multi-AZ) × 24 × 30 = $195.84/month + storage 100GB × $0.08 = $8/month. Total: ~$204/month. With RDS Reserved Instance (1 year, no upfront): $0.083/hr effective = $119.52/month + storage = $127.52/month. Savings: 38%.

**Scenario 2:** A dev PostgreSQL database (db.t3.micro, single-AZ). On-Demand: $0.017/hr × 24 × 30 = $12.24/month. Storage 20GB × $0.08 = $1.60/month. Total: ~$14/month. Dev instances can use `db.t3.micro` (covered by free tier for new accounts) or stop/start to avoid charges.

## Nuggets & Gotchas

- **RDS storage auto-scales but only UP — you cannot shrink storage once increased:** If you provision 100GB and only use 20GB, you still pay for 100GB. Start with minimal storage and let RDS auto-scale as needed.
- **RDS parameter groups require reboot to apply many parameters — not all changes are immediate:** If you change `max_connections` or `shared_buffers`, you typically need to reboot the instance. Check `pending-reboot` status in parameter group.
- **MySQL/RDS read replicas use binary log replication — this adds load to the primary:** For heavily write-intensive workloads, binary log replication can cause replication lag. Use PostgreSQL's WAL-based replication if you need less overhead.
- **RDS automated backups run in the maintenance window — don't schedule backups during peak hours:** The default 30-minute window runs during your configured time. Set it to off-peak (e.g., 3 AM).
- **You cannot connect to RDS from the internet — it must be in a VPC with proper security groups:** If you try to `telnet rds-endpoint 5432` from outside AWS and it fails, check your VPC (should be private subnet), security group (allow your IP on port 5432), and subnet routing (should not have IGW, should use NAT for outbound).
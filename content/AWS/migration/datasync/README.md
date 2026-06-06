---
title: DataSync
description: AWS DataSync — managed file transfer between on-premises storage and AWS (S3, EFS, FSx), agent deployment, task scheduling, and bandwidth throttling
tags:
  - aws
  - migration
  - storage
---

# DataSync

DataSync is a managed file transfer service for migrating large datasets between on-premises storage (NFS, SMB) and AWS storage services (S3, EFS, FSx). It handles the heavy lifting of bulk transfer — bandwidth throttling, scheduling, encryption, and validation.

## When to Use DataSync

| Scenario | Use DataSync? | Alternative |
|----------|--------------|-------------|
| Migrate 100TB+ to S3 | Yes | Snowball if bandwidth is limited |
| Sync ongoing file changes to S3 | Yes | S3 File Gateway or DataSync |
| Transfer from NAS to EFS | Yes | Direct connect + manual |
| Quick one-time transfer (< 10TB) | Maybe | AWS Transfer (SFTP → S3) |
| Database migration | No | DMS |

## How It Works

```
On-Prem Storage (NFS/SMB) ──→ DataSync Agent ──→ DataSync Service ──→ AWS Storage
      [DataSync]                                    (managed, AWS)
      deployed on-prem                              orchestrates transfer
```

The DataSync agent is a small VM (VMware, Hyper-V, or as an EC2 instance) that runs on-premises and connects to your storage. It transfers data to the DataSync service (AWS-managed), which then writes to your target AWS storage.

**No agent needed for S3 → S3 transfers** — DataSync can transfer directly between S3 buckets.

## Core Concepts

### Agent

The agent is a VM you deploy on-premises. It reads data from your NFS or SMB share and uploads it to DataSync.

```bash
# Create an agent
aws datasync create-agent \
  --agent-arn 'arn:aws:datasync:us-east-1:123456789012:agent/agent-abcdef01234567890' \
  --activation-key 'XXXX-YYYY-ZZZZ-AAAA-BBBB'  # From DataSync console

# Download agent OVA (VMware/Hyper-V) from DataSync console
# Deploy on-premises, run activation key to register with your account
```

**Agent deployment:**
- VMware ESXi, Hyper-V, or KVM
- EC2 (for AWS-native transfers or testing)
- 4 vCPU, 8GB RAM minimum
- Agent must have outbound HTTPS access to DataSync endpoints

### Location

A location is a storage endpoint — either source or destination.

```bash
# NFS location (on-premises)
aws datasync create-location-nfs \
  --server-hostname 192.168.1.100 \
  --subdirectory /shared/data \
  --on-prem-config '{
    "AgentArns": ["arn:aws:datasync:us-east-1:123456789012:agent/agent-abcdef01234567890"]
  }'

# SMB location (on-premises)
aws datasync create-location-smb \
  --server-hostname 192.168.1.100 \
  --subdirectory /shared/data \
  --on-prem-config '{
    "AgentArns": ["arn:aws:datasync:us-east-1:123456789012:agent/agent-abcdef01234567890"],
    "User": "datasync-user",
    "Password": "secret",
    "Domain": "EXAMPLE.COM"
  }'

# S3 location (as source or destination)
aws datasync create-location-s3 \
  --s3-bucket-arn arn:aws:s3:::migration-source-bucket \
  --s3-prefix "data/" \
  --s3-config '{
    "ServiceAccessRoleArn": "arn:aws:iam::123456789012:role/DataSyncS3Role"
  }'

# EFS location
aws datasync create-location-efs \
  --ec2-file-system-arn arn:aws:elasticfilesystem:us-east-1:123456789012:file-system/fs-01234567

# FSx for Windows File Server location
aws datasync create-location-fsx-windows \
  --fsx-filesystem-arn arn:aws:fsx:us-east-1:123456789012:file-system/fs-01234567 \
  --security-connector-arn arn:aws:fsx:us-east-1:123456789012:security-connector/...
```

### Task

A task defines what to transfer (source → destination) and how.

```bash
# Create task
aws datasync create-task \
  --source-location-arn arn:aws:datasync:us-east-1:123456789012:location/loc-source-nfs \
  --destination-location-arn arn:aws:datasync:us-east-1:123456789012:location/loc-target-s3 \
  --cloud-watch-log-group-arn arn:aws:logs:us-east-1:123456789012:log-group:/aws/datasync/migration \
  --options '{
    "VerifyMode": "POINT_IN_TIME_CONSISTENT",
    "Atime": "NONE",
    "Mtime": "PRESERVE",
    "Uid": "INT preserved",
    "Gid": "INT preserved",
    "PreserveDeletedFiles": "PRESERVE",
    "TaskQueueing": "ENABLED"
  }'

# Start task
aws datasync start-task-execution \
  --task-arn arn:aws:datasync:us-east-1:123456789012:task/task-abcdef01234567890

# Schedule recurring task (every day at midnight)
aws datasync create-task \
  ...
  --schedule '{
    "ScheduleExpression": "cron(0 0 * * ? *)"
  }'
```

## Transfer Options

| Option | Default | Description |
|--------|---------|-------------|
| `VerifyMode` | `POINT_IN_TIME_CONSISTENT` | Verify transferred files match source |
| `Mtime` | `PRESERVE` | Preserve file modification time |
| `Atime` | `NONE` | Don't update access time (performance) |
| `Uid` | `INT preserved` | Preserve Unix user ID |
| `Gid` | `INT preserved` | Preserve Unix group ID |
| `PreserveDeletedFiles` | `PRESERVE` | Keep deleted files in target (or remove) |
| `OverwriteMode` | `ALWAYS` | Overwrite if file changed |
| `TaskQueueing` | `ENABLED` | Queue multiple executions |

**Important options:**
- `Mtime = PRESERVE`: Required for incremental sync. If you don't preserve mtime, subsequent incremental syncs will re-transfer everything.
- `Atime = NONE`: Don't update access time — skipping this improves performance significantly.

## Incremental Sync

DataSync tracks file changes by comparing mtime and file size. For incremental sync:

1. First transfer: Full copy
2. Subsequent transfers: Only files with newer mtime or different size

```bash
# Incremental transfer (same task, run again)
aws datasync start-task-execution \
  --task-arn arn:aws:datasync:us-east-1:123456789012:task/task-abcdef01234567890
# DataSync automatically skips files where mtime hasn't changed
```

**For NFS specifically:** If mtime isn't reliable (some NFS mounts don't update mtime on writes), use `VerifyMode = NONE` and rely on file size comparison only.

## Filtering Files

```bash
# Include only specific file types
aws datasync create-task \
  --source-location-arn $NFS_ARN \
  --destination-location-arn $S3_ARN \
  --includes '[{"FilterType": "INCLUDE", "Value": "*.pdf"}, {"FilterType": "INCLUDE", "Value": "*.docx"}]'

# Exclude certain paths
aws datasync create-task \
  ...
  --excludes '[{"FilterType": "EXCLUDE", "Value": "**/.tmp"}, {"FilterType": "EXCLUDE", "Value": "**/node_modules/**"}]'
```

## Bandwidth Throttling

Limit DataSync's network usage to avoid impacting production workloads:

```bash
# Throttle to 50 Mbps during business hours
aws datasync create-task \
  --source-location-arn $NFS_ARN \
  --destination-location-arn $S3_ARN \
  --bandwidth '[{"StartTime": "17:00", "EndTime": "09:00", "Capacity": 50}]'
```

**Throttling tips:**
- Set lower bandwidth during business hours, full speed off-hours
- Monitor with CloudWatch metrics to tune
- Bandwidth is per-agent — if you need 500 Mbps total, deploy multiple agents

## Monitoring

```bash
# Describe task execution (check status)
aws datasync describe-task-execution \
  --task-execution-arn arn:aws:datasync:us-east-1:123456789012:task-execution/exec-abcdef01234567890

# CloudWatch metrics for DataSync
# - BytesTransferred (total bytes transferred)
# - FilesTransferred (total file count)
# - BytesWritten (bytes written to destination)
# - FilesSkipped (files skipped because unchanged)
# - FilesDeleted (files deleted per policy)
```

**Status flow:** `QUEUED` → `LAUNCHING` → `PREPARING` → `TRANSFERRING` → `VERIFYING` → `SUCCESS` (or `ERROR`)

## Agent High Availability

For large migrations, deploy multiple agents:

```bash
# Create location with multiple agents (for HA/throughput)
aws datasync create-location-nfs \
  --server-hostname 192.168.1.100 \
  --subdirectory /shared/data \
  --on-prem-config '{
    "AgentArns": [
      "arn:aws:datasync:us-east-1:123456789012:agent/agent-1",
      "arn:aws:datasync:us-east-1:123456789012:agent/agent-2"
    ]
  }'
# DataSync distributes files across agents automatically
# If one agent fails, its transfers are retried by remaining agents
```

## S3 Destination and Data Format

```bash
# S3 destination with Parquet output
aws datasync create-location-s3 \
  --s3-bucket-arn arn:aws:s3:::data-lake-raw \
  --s3-prefix "files/" \
  --s3-config '{
    "ServiceAccessRoleArn": "arn:aws:iam::123456789012:role/DataSyncS3Role",
    "FileExtension": "parquet"
  }'
```

DataSync can write to S3 as-is (preserve original format) or convert to different formats.

## IAM Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "datasync:ListAgents",
      "datasync:CreateAgent",
      "datasync:CreateTask",
      "datasync:StartTaskExecution"
    ],
    "Resource": "*"
  }]
}
```

For S3 destination, the DataSync service role needs:
```json
{
  "Effect": "Allow",
  "Action": ["s3:GetBucketLocation", "s3:ListBucket", "s3:PutObject"],
  "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
}
```

## Cost

- **Per GB transferred:** ~$0.04/GB (varies by region)
- **Per task execution:** Minimum 1 task execution charge even for small transfers
- **Agent:** Runs as EC2 (if deployed in AWS) or as on-prem VM (no AWS cost for on-prem agent)

**Cost tips:**
- For very large migrations (100TB+), consider Snowball Edge instead — DataSync becomes expensive at that scale
- Schedule transfers for off-hours to avoid production impact, but DataSync doesn't have off-peak pricing

## Common Patterns

### Migration: On-Prem NFS → S3

```bash
# 1. Create agent (deployed on-prem)
# 2. Create source NFS location
# 3. Create target S3 location
# 4. Create task and start
aws datasync create-task \
  --source-location-arn $NFS_LOC \
  --destination-location-arn $S3_LOC \
  --options '{"Mtime": "PRESERVE", "VerifyMode": "POINT_IN_TIME_CONSISTENT"}'

aws datasync start-task-execution --task-arn $TASK_ARN
```

### Ongoing Sync: S3 → EFS (for hybrid cloud)

```bash
# Keep EFS in sync with S3 as a data lake cache
aws datasync create-task \
  --source-location-arn $S3_LOC \
  --destination-location-arn $EFS_LOC \
  --schedule '{"ScheduleExpression": "cron(0 */4 * * ? *)"}'  # Every 4 hours
```

### Disaster Recovery: Replicate to Secondary Region

```bash
# Cross-region S3 → S3 replication
aws datasync create-task \
  --source-location-arn $S3_US_EAST \
  --destination-location-arn $S3_US_WEST \
  --schedule '{"ScheduleExpression": "cron(0 0 * * ? *)"}'  # Daily
```

## Limitations

- Maximum file size: 5TB (same as S3 limit)
- Maximum file count per task: Unlimited (but large counts slow down listing)
- Supported protocols: NFS v3, SMB v2+, S3 (as source or destination), EFS, FSx for Windows, FSx for OpenZFS
- Agent must be able to reach DataSync service endpoints (port 443)
- For SMB, the agent must be able to resolve the SMB server's hostname
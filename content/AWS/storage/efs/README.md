---
title: Amazon EFS
description: Amazon EFS — scalable NFS file system for cloud workloads. Multi-AZ, POSIX-compliant, throughput modes (bursting/scaled), encryption, and access patterns.
tags:
  - aws
  - storage
  - efs
  - nfs
---

# Amazon EFS (Elastic File System)

EFS is a managed NFS (Network File System) file system that scales automatically. It's designed for workloads that need shared file storage across multiple EC2 instances — CI/CD runners, CMS platforms, ML training data, content management systems.

## Core Concepts

### How EFS Works

```
EC2 Instance A                    EC2 Instance B
     │                                 │
     └──────────┬──────────────────────┘
                │
                ▼
         EFS File System
         (Multi-AZ, managed NFS)
                │
         ┌──────┴──────┐
         ▼              ▼
    us-east-1a      us-east-1b
    (AZ 1)          (AZ 2)
         └──────────┬──────────┘
                    ▼
              S3 (optional backup)
```

EFS is an NFSv4 share — you mount it on Linux as a directory. It's accessible from multiple AZs simultaneously (unlike EBS which is single-AZ).

### EFS vs EBS

| | EFS | EBS |
|--|--|--|
| Attachment | Multiple instances (NFS) | Single instance (block) |
| AZ span | Multi-AZ | Single AZ |
| Performance | Network NFS (0.5-2ms) | Network block (0.5-2ms) |
| Max throughput | 10 GB/s (provisioned) | 1,000 MB/s (io2 Block Express) |
| Max IOPS | 500,000 (provisioned) | 256,000 (io2 Block Express) |
| Use case | Shared storage, CI runners | Databases, app data |

## Mounting EFS

### Using mount helper (recommended)

```bash
# Install amazon-efs-utils
sudo yum install -y amazon-efs-utils  # Amazon Linux
sudo apt install -y amazon-efs-utils   # Ubuntu/Debian

# Mount
sudo mount -t efs fs-xxxxx:/ /mnt/efs
```

### With TLS (default)

```bash
sudo mount -t efs -o tls fs-xxxxx:/ /mnt/efs
```

### Mount via /etc/fstab (persistent)

```
fs-xxxxx:/ /mnt/efs efs defaults,_netdev 0 0
```

### From multiple AZs

```bash
# Mount from instance in us-east-1a
sudo mount -t efs -o az=us-east-1a fs-xxxxx:/ /mnt/efs

# Mount from instance in us-east-1b
sudo mount -t efs -o az=us-east-1b fs-xxxxx:/ /mnt/efs
```

## Performance Modes

### General Purpose (default)

For most workloads: web servers, CMS, CI/CD. Latency-sensitive applications.

### Max I/O

For highly parallel workloads: HPC, genomics, media processing. Higher latency but scales to petabytes and thousands of concurrent connections.

### Throughput Modes

| Mode | How It Works | Use Case |
|------|-------------|----------|
| Bursting | 100 MB/s per TB, bursts to 100 MB/s per TB | Variable, predictable |
| Provisioned | Fixed throughput regardless of size | Consistent high throughput |
| Elastic | Auto-scales with workload | Unknown/variable patterns |

### Throughput Calculation

```
EFS file system: 100 GB
Bursting throughput: 100 MB/s per TB = 10 MB/s base

Provisioned: 1,000 MB/s (fixed, independent of size)
Elastic: auto-scales, 1-10 MB/s per GB
```

## EFS Access Patterns

### Standard Storage Class

Multi-AZ, for frequently accessed files.

### One Zone Storage Class

Single AZ (no multi-AZ redundancy). For workloads that don't need AZ resilience (or data is already backed up elsewhere). ~50% cheaper.

### EFS Infrequent Access (EFS IA)

For files accessed less than once per month. Auto-tiered based on last access time. Storage cost ~$0.025/GB/mo vs $0.08/GB/mo for Standard. Lifecycle policies move files automatically.

## Encryption

EFS encryption is enabled at creation (default or CMK):

```bash
aws efs create-file-system \
  --creation-token my-efs \
  --encrypted \
  --kms-key-id arn:aws:kms:us-east-1:123456789012:key/xxxxx \
  --throughput-mode bursting \
  --backup-enabled
```

## Access Points

Simplify access for multiple applications:

```bash
aws efs create-access-point \
  --file-system-id fs-xxxxx \
  --posix-user "Uid=1000,Gid=1000" \
  --posix-group "Gid=1000" \
  --root-directory "Path=/app-data,CreationInfo=OwnedByUID=1000,GID=1000,Permission=0755"
```

Use access points to:
- Isolate different applications' data
- Enforce different POSIX permissions per application
- Restrict access to specific directories

## EFS Lifecycle Management

Auto-move files to EFS IA after N days of not being accessed:

```bash
aws efs put-lifecycle-configuration \
  --file-system-id fs-xxxxx \
  --lifecycle-policies '[{"TransitionToIA": "AFTER_30_DAYS"}]'
```

## Sharing EFS Across Accounts

```bash
# Account A: share via Resource Policy
aws efs put-file-system-policy \
  --file-system-id fs-xxxxx \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::111122223333:root"},
      "Action": ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"],
      "Resource": "arn:aws:elasticfilesystem:us-east-1:123456789012:file-system/fs-xxxxx"
    }]
  }'

# Account B: mount using account A's EFS
sudo mount -t efs -o tls,accesspoint=ap-xxxxx fs-xxxxx:/ /mnt/efs
```

## Performance Tuning

### Throughput vs IOPS

EFS throughput and IOPS scale with file system size:

```
File System Size | Bursting Throughput | Max IOPS
1 TB             | 100 MB/s            | ~35,000
10 TB            | 1,000 MB/s          | ~350,000
100 TB           | 10,000 MB/s         | ~500,000 (cap)
```

Larger file systems = more throughput headroom.

### CloudWatch Metrics for EFS

```bash
# Permitted throughput
aws cloudwatch get-metric-statistics \
  --namespace AWS/EFS \
  --metric-name PermittedThroughput \
  --dimensions Name=FileSystemId,Value=fs-xxxxx
```

Key metrics:
- `BurstCreditBalance` — remaining burst credits
- `PercentIOLimit` — how close to max IOPS
- `ClientConnections` — number of NFS connections
- `DataReadIOPS` / `DataWriteIOPS`

## EFS Backup with AWS Backup

```bash
# Create backup plan
aws backup create-backup-plan \
  --backup-plan '{
    "Rules": [{
      "RuleName": "daily-efs-backup",
      "TargetBackupVaultName": "default",
      "ScheduleExpression": "cron(0 5 * * ? *)",
      "StartBackupWindowMinutes": 60,
      "Lifecycle": {"DeleteAfterDays": 30}
    }]
  }'
```

## Limits

| Resource | Limit |
|----------|-------|
| File system size | Petabytes |
| Max throughput (provisioned) | 10 GB/s |
| Max IOPS (provisioned) | 500,000 |
| Concurrent connections | Thousands |
| File size | 47.9 TiB |
| Max files | Billions |

## References

- **Homepage:** https://aws.amazon.com/efs/
- **Documentation:** https://docs.aws.amazon.com/efs/
- **Pricing:** https://aws.amazon.com/efs/pricing/

## Pricing Examples

**Scenario 1:** A CI/CD system with 5 EC2 runners sharing 100GB EFS (General Purpose, Bursting). 100GB × $0.08/GB = $8/month. Throughput: burst mode, included. Total: $8/month. Compare to separate EBS volumes per runner: 5 × 50GB × $0.08 = $20/month. Shared EFS is 60% cheaper.

**Scenario 2:** An ML training platform processing 10TB of training data on 20 EC2 instances. Using EFS with provisioned throughput (1,000 MB/s). 10TB × $0.08/GB = $800/month + provisioned throughput (1,000 MB/s × $6.90 per MB/s-month = $6,900/month!). Total: ~$7,700/month. Instead: use EFS with Elastic throughput (auto-scales, $0.08/GB + $0.06/GB for throughput) = ~$1,400/month. Or copy training data to FSx Lustre (S3-linked) during job run, process, then delete — $500/month.

## Nuggets & Gotchas

- **EFS uses NFS over the network — latency is higher than local SSD:** For latency-sensitive databases (PostgreSQL, MySQL), EFS is not suitable. Use io2 Block Express EBS volumes instead. For a 100GB database with 10K TPS, EFS will bottleneck at ~500 IOPS.
- **EFS bursting mode credits deplete during heavy write periods — then throughput drops to 50 MB/s per TB:** If you're doing a large batch job (ML training, video processing) on EFS, monitor `BurstCreditBalance`. If it drops to 0, throughput tanks and jobs take 10x longer. Use provisioned throughput for critical batch workloads.
- **EFS One Zone has no cross-AZ redundancy — a single AZ failure loses your data:** EFS One Zone is cheaper but a AZ failure means data loss. Use it only for non-critical data, or ensure you have S3 backups via DataSync or a custom sync script.
- **Lifecycle policies move files to EFS IA based on last access time, not last modification:** A file that was read last week (for a report) but modified 6 months ago will be moved to IA because access time is recent. This is correct for some use cases (cold storage) but wrong for active datasets.
- **Mounting EFS from an instance in a different AZ adds cross-AZ traffic costs:** EFS in us-east-1a mounted from an instance in us-east-1b costs $0.02/GB for cross-AZ traffic. For high-throughput workloads, deploy EC2 instances in the same AZ as the EFS mount target.
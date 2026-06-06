---
title: Amazon EBS
description: Amazon EBS — block storage volumes for EC2 instances. Volume types (gp3/gp2/io2/io2BlockExpress), snapshots, encryption, and performance optimization.
tags:
  - aws
  - storage
  - ebs
---

# Amazon EBS (Elastic Block Store)

EBS provides persistent block storage volumes for EC2 instances. Each volume is automatically replicated within its Availability Zone for durability. EBS volumes are physically attached to EC2 instances via the network (not a shared bus like SAN).

## Core Concepts

### How EBS Works

```
EC2 Instance (in AZ us-east-1a)
  └── Network attachment (not local disk)
       └── EBS Volume (in us-east-1a)
            └── File System (ext4, xfs, ntfs)
                 └── Data
```

EBS is network-attached — not like a local SSD. Latency is ~0.5-2ms vs local NVMe at ~0.1ms. For most applications, this difference is negligible.

### Volume Types

| Type | Performance | Use Case | Cost (per GB/mo) |
|------|-------------|----------|-------------------|
| gp3 | 3,000 IOPS, 125 MB/s (base) | General purpose, lower cost | ~$0.08 |
| gp2 | 3,000 IOPS burst | Legacy general purpose | ~$0.10 |
| io2 | 256,000 IOPS, 1,000 MB/s | High-performance databases | ~$0.125 |
| io2 Block Express | 256,000 IOPS, 4,000 MB/s | Ultra-performance | ~$0.125 |
| st1 | 500 IOPS, 250 MB/s | Throughput-intensive (Hadoop, log processing) | ~$0.045 |
| sc1 | 250 IOPS, 250 MB/s | Infrequent access | ~$0.025 |

### gp3 vs gp2

gp3 is the newer, cheaper option with configurable throughput independent of IOPS:

```
gp3: 3,000 IOPS + 125 MB/s (base) → configurable up to 16,000 IOPS / 1,000 MB/s
gp2: 3,000 IOPS burst, throughput tied to IOPS
```

gp3 is ~20% cheaper than gp2 for equivalent performance.

## Creating a Volume

```bash
# Create a 100GB gp3 volume
aws ec2 create-volume \
  --volume-type gp3 \
  --size 100 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=my-data-volume}]'
```

### Attaching to EC2

```bash
aws ec2 attach-volume \
  --volume-id vol-xxxxx \
  --instance-id i-xxxxx \
  --device /dev/sdf
```

### On the EC2 Instance

```bash
# Check available devices
lsblk

# Format (first time only)
sudo mkfs.ext4 /dev/sdf

# Mount
sudo mount /dev/sdf /mnt/data

# Add to /etc/fstab for auto-mount
echo "/dev/sdf /mnt/data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
```

## EBS Snapshots

Snapshots are incremental backups stored in S3. First snapshot copies all data; subsequent snapshots only copy changed blocks.

### Creating a Snapshot

```bash
aws ec2 create-snapshot \
  --volume-id vol-xxxxx \
  --description "pre-migration-backup" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=my-volume-snapshot}]'
```

### Sharing Snapshots

```bash
# Make snapshot public (all AWS accounts)
aws ec2 modify-snapshot-attribute \
  --snapshot-id snap-xxxxx \
  --attribute-type createVolumePermission \
  --operation-type add \
  --group-names all

# Share with specific account
aws ec2 modify-snapshot-attribute \
  --snapshot-id snap-xxxxx \
  --attribute-type createVolumePermission \
  --operation-type add \
  --user-ids 111122223333
```

### Restoring from Snapshot

```bash
# Create volume from snapshot
aws ec2 create-volume \
  --snapshot-id snap-xxxxx \
  --availability-zone us-east-1a

# Attach to instance
aws ec2 attach-volume --volume-id vol-yyyyy --instance-id i-xxxxx --device /dev/sdg
```

## Encryption

EBS volumes are encrypted by default (AWS-managed keys). You can also use customer-managed keys (CMK):

```bash
# Encrypted volume (default)
aws ec2 create-volume \
  --volume-type gp3 \
  --size 50 \
  --encrypted \
  --kms-key-id arn:aws:kms:us-east-1:123456789012:key/xxxxx
```

Encryption is transparent — no performance impact. Snapshots of encrypted volumes are also encrypted.

## Volume Performance

### IOPS and Throughput

```
gp3: 3,000 IOPS base (configurable to 16,000)
gp2: 3,000 IOPS burst (scales with volume size, 3,000 max)
io2: 256,000 IOPS (Block Express: 256,000)
```

### Volume Size and Performance (gp2/gp3)

gp2 and gp3 IOPS scale with volume size:
- < 1TB → 3,000 IOPS
- 1-2TB → 6,000 IOPS
- 2-3TB → 9,000 IOPS
- 3-4TB → 12,000 IOPS

For gp3, you can configure IOPS and throughput independently. For gp2, IOPS and throughput are coupled.

### Monitoring EBS Performance

```bash
# Volume metrics (CloudWatch)
aws cloudwatch get-metric-statistics \
  --namespace AWS/EBS \
  --metric-name VolumeReadOps \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-15T12:00:00Z \
  --period 300 \
  --statistics Sum \
  --dimensions Name=VolumeId,Value=vol-xxxxx
```

Key metrics:
- `VolumeReadOps` / `VolumeWriteOps` — I/O operations
- `VolumeQueueLength` — wait time (should be < 10 for good performance)
- `VolumeBurstBalance` (gp2 only) — burst IOPS remaining
- `VolumeConsumedReadWriteHours` — io2 only

## Multi-Attach

io2 volumes can be attached to multiple EC2 instances in the same AZ:

```bash
aws ec2 modify-volume \
  --volume-id vol-xxxxx \
  --multi-attach-enabled
```

Use case: Oracle RAC (shared disk cluster), Windows Scale-Out File Server. Requires a cluster-aware file system (OCFS2, GFS2, AWS FSx).

## Instance Store vs EBS

| | Instance Store | EBS |
|--|--|--|
| Location | Local to host (NVMe) | Network attached |
| Durability | 0 (ephemeral) | 99.999% (replicated in AZ) |
| Size | Limited by instance type | Up to 16TB |
| Performance | Very high (0.1ms) | High (0.5-2ms) |
| Cost | Included in instance price | Additional cost |
| Use | Temporary, non-critical data | Persistent data |

## Limits

| Resource | Limit |
|----------|-------|
| Volumes per account | 5,000 (soft limit) |
| Max volume size | 16TB |
| Max IOPS (gp3) | 16,000 (independent of size) |
| Max IOPS (io2 Block Express) | 256,000 |
| Max throughput (gp3) | 1,000 MB/s |
| Snapshots per volume | Unlimited |

## References

- **Homepage:** https://aws.amazon.com/ebs/
- **Documentation:** https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AmazonEBS.html
- **Pricing:** https://aws.amazon.com/ebs/pricing/

## Pricing Examples

**Scenario 1:** A production database with 500GB gp3 volume + 3,000 IOPS. 500GB × $0.08 = $40/month. Volume usage: $0.08/GB/mo × 500 = $40/month. Plus snapshots: 500GB first snapshot (full) = $23/month (S3 storage). Monthly snapshots (incremental, ~10GB changed) = $0.23/month. Total: ~$64/month.

**Scenario 2:** A dev environment with 100GB gp3. 100GB × $0.08 = $8/month. Snapshots (30-day retention, 5GB changed each): 5GB × $0.05/GB = $0.25/month. Total: ~$8.25/month. Compare to gp2: 100GB × $0.10 = $10/month + worse performance.

## Nuggets & Gotchas

- **EBS volumes are AZ-locked — you can't attach a volume from us-east-1a to an instance in us-east-1b:** To move a volume between AZs, create a snapshot and restore in the target AZ. To move between regions, copy the snapshot to the target region first.
- **gp2 has a burst bucket — if you exhaust it, IOPS drops to 100:** gp2 bursts at 3,000 IOPS for volumes up to 1TB. After burst exhaustion, you get 100 IOPS until the bucket refills (at ~1 IOPS per GB of volume size per minute). Use gp3 for consistent performance or io2 for high IOPS.
- **EBS snapshots are incremental — but deleting a snapshot doesn't free space if dependent snapshots exist:** Only the blocks not referenced by any remaining snapshot are actually deleted. You can't reduce S3 storage used by snapshots without deleting all dependent snapshots.
- **Volume performance (IOPS/throughput) is measured at the volume level, not the instance level:** An m5.xlarge with 2 volumes can achieve up to 6,000 IOPS (3,000 per volume). If you need more IOPS, stripe multiple volumes with LVM or use io2 Block Express.
- **The `VolumeBurstBalance` metric for gp2 tells you how much burst credit you have remaining:** If this drops to 0, your IOPS drops to 100. For production databases, monitor this and consider switching to gp3 (no burst, consistent performance) or io2 (predictable high IOPS).
---
title: EBS Cost Optimization
description: EBS cost optimization — volume types, gp2 vs gp3, io2 trade-offs, unattached volumes, snapshot lifecycle, and Amazon Data Lifecycle Manager
tags:
  - aws
  - cost-management
  - storage
---

# EBS Cost Optimization

EBS costs come from three sources: **volume storage** (per GB-month), **IOPS** (for io1/io2/io3), and **snapshots** (per GB-month). Most waste comes from over-sized volumes, old snapshots, and unattached volumes left behind after instance termination.

## Volume Types and When to Use Them

| Type | Use When | GB/Month | IOPS/GB | Max IOPS | Max Throughput |
|------|----------|----------|---------|---------|---------------|
| **gp3** | General purpose, most workloads | ~$0.08 | N/A (baseline 3,000 IOPS + 125MB/s included) | 16,000 | 1,000 MB/s |
| **gp2** | Legacy, burst to 3,000 IOPS | ~$0.10 | Burst model | 3,000 | 250 MB/s |
| **io2** | High-performance databases | ~$0.125 + $0.065 per IOPS | 500:1 ratio | 64,000 | 1,000 MB/s |
| **io2 Block Express** | Ultra-high performance | ~$0.125 + $0.065 per IOPS | 1,000:1 ratio | 256,000 | 4,000 MB/s |
| **st1** | Throughput-intensive (Hadoop, log processing) | ~$0.045 | N/A | 500 | 500 MB/s |
| **sc1** | Cold storage (infrequently accessed) | ~$0.015 | N/A | 250 | 250 MB/s |

**gp3 vs gp2:** gp3 is newer and cheaper. It includes a baseline of 3,000 IOPS and 125MB/s regardless of volume size, and you can provision IOPS up to 16,000 independently of volume size. gp2 uses a burst model — small volumes get burst IOPS up to 3,000 but deplete a burst balance. gp3 is almost always the better choice for new workloads.

**io2 vs gp3 for databases:** io2 charges per provisioned IOPS. If your database needs 10,000 IOPS and you're using io2 at $0.065/IOPS-month, that's $650/month just for IOPS on top of storage. gp3 at the same 10,000 IOPS is included in the price. io2 only makes sense when you need the higher durability (99.999%) or the multi-attach capability.

## Unattached Volumes

The single biggest source of EBS waste is volumes left attached to stopped or terminated instances. EBS volumes persist independently of EC2 instances — when you stop or terminate an instance, the root volume is deleted (if `DeleteOnTermination=true`) but data volumes are detached and remain.

**Finding unattached volumes:**
```bash
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].[VolumeId,Size,VolumeType,CreateTime]'
```

**Unattached volume detection strategies:**
- AWS Config rule: `ebs-volume-inuse-check` detects volumes not attached to running instances
- AWS Trusted Advisor (Business plan): checks for unattached volumes
- Lambda function scheduled daily to report untagged unattached volumes
- AWS Instance Scheduler solution tags volumes with `Duration` and stops idle instances before volumes become orphaned

## Snapshot Storage Costs

EBS snapshots are stored in S3. Snapshot pricing: ~$0.05/GB-month (standard, varies by region).

**Sources of snapshot waste:**
1. **Old snapshots from deleted instances** — the instance is gone but the snapshot remains
2. **Multiple snapshots of the same volume** — accumulated over time with no cleanup policy
3. **Snapshots from test/dev environments** — left behind after test runs
4. **Encrypted snapshots with old KMS keys** — can't be deleted because the key is still referenced

**Amazon Data Lifecycle Manager (DLM):**
Automate snapshot creation and deletion. Configure policies to:
- Create daily snapshots with a 7-day retention → auto-delete after 7 days
- Create weekly snapshots with 90-day retention → auto-delete after 90 days
- Tag-based policies for fine-grained control (only snapshot volumes with `Backup=true` tag)

DLM policies are free — you only pay for the snapshot storage.

**Snapshot cleanup gotcha:** DLM only manages snapshots it creates. Manually created snapshots need manual cleanup or a separate lifecycle policy.

## Volume Sizing and Right-Sizing

**Over-sized volumes:** The most common issue. You provision 500GB because "we might need it" but actual usage is 50GB. You're paying for 450GB of unused storage.

**Under-sized volumes:** Less common but causes performance issues. If IOPS requirements are high but volume is too small, you can't provision enough IOPS (gp3 has a 50:1 IOPS-to-GB ratio for provisioned IOPS).

**Right-sizing approach:**
- CloudWatch `VolumeConsumedReadWriteBytes` metric shows actual I/O
- EBS I/O stats in the EC2 console shows if you're consistently hitting volume limits
- Compute Optimizer recommends volume changes for instances with high EBS I/O

## Multi-Attach Costs

io2 volumes support multi-attach (up to 16 instances). This is useful for clustered filesystems (GFS2, OCFS2) but adds complexity and cost. Multi-attach is almost never needed for application workloads — shared file storage should use EFS or FSx instead.

## Encryption Costs

EBS encryption with AWS-managed keys (SSE-S3) is free — no additional charge. Customer-managed KMS keys incur charges only if you're storing keys in a region with per-key charges ($1/month) or if you're using CMK for volumes encrypted with a custom key (charged per volume-month for the key resource).

The only scenario where encryption adds cost: CMK with a dedicated HSM (CloudHSM), which has ongoing per-hour costs. Standard KMS CMK is effectively free for EBS encryption.

## Monitoring EBS Costs

CloudWatch metrics for EBS:
- `VolumeReadOps`, `VolumeWriteOps` — I/O operations
- `VolumeReadBytes`, `VolumeWriteBytes` — throughput
- `VolumeQueueLength` — I/O waiting (high queue = volume is saturated)
- `BurstBalance` (gp2) — remaining burst IOPS credits

Use these to identify volumes that are:
- Consistently under-utilized (right-size down)
- Consistently over-utilized (upgrade to io2 or larger gp3)
- Showing low BurstBalance (gp2) indicating IOPS throttling

## References

- **Homepage:** https://aws.amazon.com/ebs/pricing/
- **Documentation:** https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AmazonEBS.html
- **Pricing:** https://aws.amazon.com/ebs/pricing/

## Pricing Examples

**Scenario 1:** A database server using a500GB gp2 volume. Switching to gp3 with provisioned IOPS (500GB gp3 + 3000 IOPS): gp2 cost = 500GB × $0.10 = $50/month. gp3 cost = 500GB × $0.08 + 3000 IOPS × $0.006 = $40 + $18 = $58/month. The gp3 upgrade costs $8 more but provides consistent3000 IOPS vs burst gp2. For an IOPS-sensitive DB, worth it. For a lightly-used DB: gp3 at500GB with no extra IOPS = $40/month, saving $10/month.

**Scenario 2:** A development environment with 8 unattached EBS volumes (4 × 100GB gp2, 4 × 50GB gp2) sitting around from old test instances. Monthly cost: 8 × 100GB × $0.10 = $80/month wasted. Deleting them saves $960/year. Set up a Lambda function to alert on unattached volumes older than 7 days and auto-delete after 30 days.

## Nuggets & Gotchas

- **gp2 burst IOPS are finite and deplete:** gp2 volumes up to 1TB get 3 IOPS/GB burst capacity. A 100GB gp2 volume has 300 burst IOPS. If you sustain 400 IOPS, you burn through credits and drop to 300 baseline IOPS. gp3 eliminates this with consistent performance.
- **EBS snapshots cost money even after you delete the volume:** Snapshots are stored in S3 and charged per GB-month. A 500GB volume deleted but with 30 days of snapshots still costs $0.023/GB for those snapshots. Clean up old snapshots with lifecycle policies.
- **io2 block express costs more but is cheaper at high IOPS:** At > 64,000 IOPS per volume, io2 Block Express ($0.125/GB + $0.065/provisioned IOPS) becomes cheaper than io1 ($0.125/GB + $0.10/provisioned IOPS). For high-IOPS databases, do the math.
- **EBS encryption is free (uses KMS CMK at no additional cost):** There's no cost for EBS encryption with the default AWS-managed CMK. Only custom CMKs cost $1/month. Don't skip encryption for cost reasons.
- **EBS volume performance is tied to the instance type:** A nitro-based instance (e.g., c6i) can drive more IOPS from the same EBS volume than a non-nitro instance (e.g., c5). The volume type sets the ceiling, the instance type determines if you can reach it.
---
title: "Amazon EBS"
description: "EBS provides persistent AZ-scoped block storage for EC2."
tags:
  - aws/storage
date: 2026-10-12
---

# Amazon EBS

EBS provides persistent AZ-scoped block storage for [[AWS/compute/ec2/README|EC2]]. The application/operating system owns partitioning, filesystem correctness and database consistency. EBS is not a shared NFS service; eligible io1/io2 Multi-Attach requires a cluster-aware filesystem/application and does not coordinate writers for you.

## Volume and performance decisions

gp3 separates capacity from provisioned IOPS and throughput. Its included baseline is 3,000 IOPS and 125 MiB/s; additional performance is billed separately. Current regional gp3 reaches 64 TiB, 80,000 IOPS and 2,000 MiB/s subject to capacity/performance ratios. Outposts has different limits, so do not reuse a regional maximum there.

gp2 baseline is max(100, 3 × GiB) IOPS up to 16,000; small volumes can burst using credits. Exhausted credits fall to that volume's baseline, not universally 100 IOPS. Monitor BurstBalance for applicable volumes. Provisioned-IOPS SSD targets latency-sensitive workloads; throughput HDD choices suit sequential I/O and are not boot volumes. Match EC2 EBS bandwidth limits as well as volume capability.

## Encryption and snapshots

Encryption by default is an account/Region setting, not automatic because an AWS-managed key exists. Enabling it does not rewrite existing volumes/snapshots. Explicitly verify the volume's encryption/key and allow the necessary KMS grants for restore/sharing.

Snapshots are incremental recovery artifacts priced as EBS snapshots, not customer S3 Standard objects. Deleting one releases blocks no longer referenced by remaining snapshots; you need not delete every snapshot first. Quiesce the application or use application-aware backup for consistent recovery. [[AWS/storage/ebs/amazon-data-lifecycle-manager|DLM]] automates retention but does not prove a usable restore.

## Sandbox recovery exercise

Prerequisites: a disposable EC2 instance, a volume in its AZ, permissions and a budget for volume/snapshot charges. Confirm the exact device using lsblk; never format a disk containing data. Write a test file, flush/quiesce writes, snapshot the volume and restore to a second volume in the same AZ.

```bash
aws ec2 get-ebs-encryption-by-default
aws ec2 describe-volumes --volume-ids vol-0123456789abcdef0
aws ec2 create-snapshot --volume-id vol-0123456789abcdef0 \
  --description "Disposable recovery exercise"
```

Wait for snapshot completion and attach/mount the restored volume without formatting it. Verify the test file's checksum. A direct cross-AZ attachment should fail; restoration into a new volume in the target AZ is the recovery path. Detach/delete only sandbox volumes and snapshots after verification. Do not publish snapshots or modify production mounts for this exercise.

## Cost and observability

Bill provisioned capacity × elapsed month fraction plus excess provisioned IOPS/throughput, snapshots/archive and any fast snapshot restore. Compare equal capacity: 2 TB cannot be costed as 200 GB. Watch volume latency/queue/throughput and instance limits; VolumeConsumedReadWriteOps is a documented metric, not VolumeConsumedReadWriteHours.

## Volume/device lifecycle

```text
EBS volume (one AZ)
  → attachment to a compatible EC2 instance in that AZ
  → OS device / optional partition
  → filesystem
  → mounted application data
```

| Family         | Workload direction                                        | What to measure                                         |
| -------------- | --------------------------------------------------------- | ------------------------------------------------------- |
| gp3            | General-purpose SSD with independent performance settings | Volume and instance throughput/IOPS ceilings.           |
| gp2            | General-purpose SSD with size-linked baseline/credits     | Actual baseline and BurstBalance.                       |
| io1/io2        | Supported high-IOPS/latency-sensitive workloads           | Required instance support, consistency and cost.        |
| st1/sc1        | Applicable sequential HDD workloads                       | Throughput, workload suitability; not boot volumes.     |
| Instance store | Local ephemeral capacity                                  | Host/stop/termination loss and application replication. |

## Attach, mount and grow safely

1. Describe the volume/instance and verify the exact AZ and identifiers.
2. Attach only the sandbox volume; inspect lsblk and filesystem signatures.
3. Format only a confirmed empty new device. NVMe naming can differ from requested device names.
4. Mount by filesystem UUID where appropriate and validate a temporary fstab change before reboot.
5. Write/checksum a labelled file and verify ownership/application access.
6. For growth, modify the supported volume settings, wait for modification state, then expand the partition/filesystem with OS-specific tools.
7. Verify usable filesystem capacity; EBS allocation alone does not expand a filesystem automatically.

Run mkfs only on a verified empty new device: formatting an existing filesystem destroys data. Changing a volume's performance settings may be independent of capacity, but filesystem operations and supported constraints still apply.

## Snapshot, sharing and restore

```bash
aws ec2 describe-snapshots --owner-ids self
aws ec2 describe-volumes-modifications --volume-ids vol-0123456789abcdef0
```

These read-only calls require permissions and can reveal asset metadata. Snapshot creation/restoration need a consistent application state and appropriate KMS permissions. Share with explicit approved account IDs and keys; public snapshot sharing is not a safe default learning recipe.

A restore creates a new volume in the selected AZ. Initialization/lazy loading or supported fast-restore settings can affect first-read latency. After mounting the restored filesystem without formatting, compare checksums/application state and record observed RTO.

Monitor queue length, latency, throughput and IOPS along with EC2 limits; a busy filesystem can be bottlenecked at the instance rather than the volume. Snapshots, archive, fast snapshot restore and provisioned performance are separate cost controls.

## References

- [gp3 performance and constraints](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html)
- [Encryption by default](https://docs.aws.amazon.com/ebs/latest/userguide/encryption-by-default.html)
- [Snapshot deletion](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-deleting-snapshot.html)
- [EBS metrics](https://docs.aws.amazon.com/ebs/latest/userguide/using_cloudwatch_ebs.html)
- [EBS pricing](https://aws.amazon.com/ebs/pricing/)

## Across the wiki

- [[Kubernetes/eks/storage/README|Storage on EKS]] — block storage (Kubernetes)
- [[Azure/compute/aks/storage-csi-disks|AKS Storage CSI Architecture — Azure Managed Disks, Premium SSD v2, and Elastic SAN]] — block storage (Azure)
- [[GCP/compute/gke/storage-csi|GKE Storage Architecture — Compute Persistent Disk CSI, Hyperdisk, and Volume Snapshots]] — block storage (GCP)
- [[Linux/storage/README|Linux Storage]] — block storage (Linux)

---
title: AWS Storage
description: AWS storage services — S3 for object storage, EBS for block storage, EFS for network file system, FSx for Windows/Lustre file systems, Glacier for archival, and Storage Gateway for hybrid storage.
tags:
  - aws
  - storage
---

# AWS Storage

AWS offers a comprehensive suite of storage services across three categories: **object storage** (S3, Glacier), **block storage** (EBS), and **file storage** (EFS, FSx). Each serves different access patterns and performance requirements.

## Service Map

| Service | Type | Access Pattern | Common Use |
|---------|------|---------------|------------|
| [[s3/README|S3]] | Object | HTTP REST API (PUT/GET/DELETE) | Static assets, data lake, backup |
| [[ebs/README|EBS]] | Block | EC2 attachment (iSCSI) | OS disks, databases, app data |
| [[efs/README|EFS]] | File | NFSv4 (mounted as drive) | Shared file system, CI runners |
| [[fsx/README|FSx]] | File | SMB/NFS (Windows/Lustre) | Enterprise apps, HPC |
| [[glacier/README|Glacier]] | Object | HTTP (via S3 or direct) | Long-term archive, compliance |
| [[storage-gateway/README|Storage Gateway]] | Hybrid | SMB/NFS/iSCSI | On-prem to cloud backup |

## Storage Hierarchy

```
Object Storage (S3, Glacier)
  └── Bucket
       ├── Object (key-value, no hierarchy)
       ├── Prefix (logical folder: "logs/2024/")
       └── Lifecycle rules

File Storage (EFS, FSx)
  └── File System
       ├── Directory
       └── File

Block Storage (EBS)
  └── Volume
       └── Partition
            └── File System (ext4, xfs, ntfs)
```

## Storage Decision Tree

```
Is it attached to a single EC2 instance?
  YES → EBS (block, high-performance, single attachment)
  NO ↓

Is it shared across multiple instances?
  YES → Is it Windows-based?
      YES → FSx for Windows (SMB, AD integration)
      NO → Is it high-performance computing (HPC)?
          YES → FSx for Lustre (parallel, petabyte scale)
          NO → EFS (NFS, scalable, multi-AZ)
  NO ↓

Is it accessed over HTTP?
  YES → S3 (REST API, global, infinitely scalable)
  NO ↓

Is it long-term archive (months to years)?
  YES → S3 Glacier (or S3 Glacier Instant Retrieval)
  NO ↓

Is it a hybrid cloud backup from on-premises?
  YES → Storage Gateway (File/Snapshot/Tape)
  NO → Re-evaluate access pattern
```

## Architecture Patterns

### Tiered Storage (Hot → Warm → Cold)

```
S3 Standard         → Frequently accessed (CDN origin, app assets)
         ↓ lifecycle (30 days)
S3 IA               → Less frequently accessed (backups, analytics)
         ↓ lifecycle (90 days)
S3 Glacier          → Rarely accessed (compliance, legal hold)
```

### Hybrid Cloud Storage

```
On-Premises Data Center
  └── Storage Gateway (VM)
        ├── File Mode → S3 (NFS/SMB)
        ├── Tape Mode → S3 → Glacier (virtual tape library)
        └── Volume Mode → EBS Snapshots → S3
              ↓
        AWS Cloud (S3/Glacier)
```

## AWS Services Organized by Category

**Object Storage**
- [[s3/README|S3]] — The primary object storage service
- [[glacier/README|Glacier]] — Long-term archival storage

**Block Storage**
- [[ebs/README|EBS]] — EC2 instance block storage

**File Storage**
- [[efs/README|EFS]] — NFS file system for Linux workloads
- [[fsx/README|FSx]] — Managed Windows (SMB) and Lustre file systems

**Hybrid Storage**
- [[storage-gateway/README|Storage Gateway]] — Connect on-premises to cloud storage

## References

- **Homepage:** https://aws.amazon.com/products/storage/
- **Documentation:** https://docs.aws.amazon.com/storage/
- **Pricing:** https://aws.amazon.com/pricing/storage/

## Nuggets & Gotchas

- **S3 is object storage, not a file system — you can't mount it as a drive:** Applications expecting POSIX semantics (directory rename, file locking) may not work with S3. Use EFS or FSx for those use cases.
- **EBS volumes are AZ-specific — they cannot span multiple AZs:** If you need cross-AZ storage, use EFS (NFS) or S3. EBS is a single-AZ resource with 99.999% uptime SLA (not multi-AZ like RDS).
- **EFS and FSx are network file systems — latency is higher than EBS:** EFS uses NFS over the network, so expect 0.5–2ms additional latency vs local EBS. For latency-sensitive databases, use EBS.
- **S3 storage class selection is a trade-off between cost and retrieval time:** S3 Standard retrieval: milliseconds. S3 IA retrieval: 1-5ms. S3 Glacier retrieval: 1-12 hours (or 1-5 minutes with expedited). Choose based on access frequency.
- **Storage Gateway has ongoing bandwidth costs for data transfer:** While the gateway VM is free, data transfer from on-premises to S3 via Storage Gateway costs $0.02–$0.09/GB depending on region. Model bandwidth costs before committing.
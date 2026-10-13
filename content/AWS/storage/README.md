---
title: "AWS Storage"
description: "Choose storage by the interface your application requires, then by recovery objectives, access frequency and failure domain."
tags:
  - aws/storage
date: 2026-10-12
---

# AWS Storage

Choose storage by the interface your application requires, then by recovery objectives, access frequency and failure domain. A block volume, shared filesystem and object bucket are not interchangeable.

## Learning path and service selection

Start with [[AWS/foundations/README|AWS foundations]], [[AWS/security/iam/README|IAM]] and [[AWS/networking/README|networking]]. Then work through the service matching your workload:

| Lesson                                                                    | Interface and decision                                                                        |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| [[AWS/storage/s3/README\|S3]]                                             | Regional buckets, object keys and HTTP APIs; data lakes, assets and durable backups.          |
| [[AWS/storage/ebs/README\|EBS]]                                           | AZ-scoped block devices for EC2; filesystem/database management remains yours.                |
| [[AWS/storage/efs/README\|EFS]]                                           | Managed shared NFS; Regional or One Zone durability/failure-domain choices.                   |
| [[AWS/storage/fsx/README\|FSx]]                                           | Windows SMB, Lustre, OpenZFS or ONTAP, selected for protocol and application compatibility.   |
| [[AWS/storage/glacier/README\|S3 archival classes]]                       | Object archival chosen by retrieval delay and retention, not a separate filesystem.           |
| [[AWS/storage/storage-gateway/README\|Storage Gateway]]                   | Local appliance bridges NFS/SMB, iSCSI volumes or virtual tapes to cloud storage.             |
| [[AWS/storage/ebs/amazon-data-lifecycle-manager\|Data Lifecycle Manager]] | Scheduled EBS snapshots/AMI lifecycle; verify restores rather than only successful schedules. |

## Architecture decisions

An EC2 database normally needs EBS or a supported managed database, not S3 mounted as a transparent POSIX disk. Applications sharing Linux files can use EFS; Windows domain integrations suggest FSx for Windows. HPC applications needing parallel file access should evaluate Lustre. Object APIs favor S3.

S3 Standard buckets are regional; there is no bucket “same AZ” placement knob. One Zone services intentionally have a narrower failure domain. EBS volumes attach in their AZ; cross-AZ recovery uses snapshots/new volumes, not ordinary direct attachment. Stored Volume Gateway keeps primary data on premises and backs it up as cloud snapshots; Cached Volume Gateway uses local cache with primary cloud data.

## Design exercise

Given 2 TiB of application data, document the protocol, concurrent writers, acceptable data loss (RPO), recovery time (RTO), encryption ownership and restore path before comparing prices. Compare equal capacity and elapsed time. Include requests, performance provisioning, backup, retrieval and network charges. A cheaper storage rate does not imply a cheaper complete application.

Create a small disposable dataset in your chosen service, deny an unauthorized identity, recover a deleted/test-corrupted copy, and measure restoration time. [[AWS/reliability/backup-and-recovery|Recovery planning]] owns shared RPO/RTO and restore verification. Retention and encryption are not substitutes for a tested backup. Remove sandbox data and chargeable infrastructure afterward; do not weaken production retention to simplify cleanup.

## Storage hierarchy and application interfaces

```text
Object: bucket → key → version / metadata / tags
File: filesystem → directory → path / POSIX or Windows permissions
Block: volume → partition → filesystem → application files
Hybrid: local protocol endpoint → cache/primary data → cloud artifact
```

These models determine application changes. A backup tool expecting a virtual tape library does not become an S3-native application merely because its tapes ultimately archive in AWS. A relational database expecting a supported block filesystem cannot safely substitute an object-store mount without evaluating semantics.

| Question                                     | Direction                       | Follow-up                                                  |
| -------------------------------------------- | ------------------------------- | ---------------------------------------------------------- |
| Application speaks HTTP/object APIs?         | S3                              | Key design, IAM, versioning and restore.                   |
| Single EC2 needs a block device?             | EBS                             | AZ attachment, filesystem, snapshot consistency.           |
| Linux clients share files?                   | EFS or suitable FSx             | NFS/POSIX, throughput and ownership.                       |
| Windows/AD filesystem required?              | FSx Windows or applicable ONTAP | SMB and identity/network prerequisites.                    |
| Parallel HPC I/O?                            | Lustre                          | Client compatibility, deployment and repository semantics. |
| Local iSCSI/tape/file interface must remain? | Appropriate gateway             | Where primary data lives and outage behavior.              |

## Tiering versus backup comparison

Moving cold files/objects to a cheaper class is lifecycle optimization, not a second independent copy. Replication can propagate logical changes and requires its own deletion/retention design. A backup should meet a documented restore objective and be protected from the same accidental/malicious change path where required.

Compare both steady-state operation and disaster recovery: protocol correctness, latency, throughput, read/write concurrency, encryption key recovery, copy locality and restore dependency. For a 2-TiB dataset, specify the same units/capacity and timeframe across candidates; add retrieval, requests and bandwidth rather than comparing only advertised storage rates.

## References

- [AWS storage services and selection overview](https://aws.amazon.com/products/storage/)
- [S3 storage classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html)
- [Storage Gateway volume architecture](https://docs.aws.amazon.com/storagegateway/latest/vgw/StorageGatewayConcepts.html)

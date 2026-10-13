---
title: "Amazon EFS"
description: "EFS is managed shared NFS storage."
tags:
  - aws/storage
date: 2026-10-12
---

# Amazon EFS

EFS is managed shared NFS storage. Choose Regional or One Zone, an appropriate performance/throughput mode and lifecycle policies from your workload and recovery objectives. Prerequisites: [[AWS/networking/README|VPC networking]], [[AWS/security/iam/README|IAM]] and [[AWS/storage/README|storage selection]].

## Mounting and access

Mount targets expose the filesystem in selected subnets. Permit TCP 2049 only between authorized clients and mount-target security groups; reachability and filesystem authorization are separate. Use amazon-efs-utils for TLS and IAM-authorized mounts. An access point can enforce a POSIX UID/GID and root directory; it is not an IAM principal or a way to bypass Unix permissions.

For cross-account access, coordinate routing/DNS, mount targets, filesystem resource policy, IAM and KMS where applicable. Do not treat a policy alone as network connectivity. Apply least privilege and verify denied identities as well as successful clients.

## Performance and lifecycle

General Purpose is the normal performance choice; availability of alternative modes depends on deployment type. Elastic throughput follows demand rather than a fixed MB/s-per-GB formula. Bursting throughput earns a 50 KiB/s-per-GiB Standard-storage baseline, with read operations metered at one-third; credits permit bursts. Provisioned throughput is explicitly selected. Consult mode/Region tables for limits rather than assuming a 500-IOPS ceiling or database suitability.

Lifecycle policies use an internal inactivity timer: successful content access resets it. IA/Archive transition and transition back to Standard are separate controls with access/transition/minimum billing implications. A recently read file is not older merely because its metadata timestamp differs.

## Configuration contracts

CreateFileSystem does not accept backup-enabled. Configure backup through PutBackupPolicy or [[AWS/storage/README|AWS Backup]] workflows. CreateAccessPoint uses PosixUser and RootDirectory; root creation requires OwnerUid, OwnerGid and Permissions. AWS Backup plans require BackupPlanName and correct StartWindowMinutes. Use the owning schemas before applying an example.

```bash
aws efs describe-file-systems
aws efs describe-mount-targets --file-system-id fs-0123456789abcdef0
aws efs describe-backup-policy --file-system-id fs-0123456789abcdef0
```

These read-only CLI v2 calls require your actual filesystem ID and permissions.

## Shared-file and recovery exercise

Create a small isolated filesystem with two authorized clients; budget filesystem and backup charges. Mount using TLS, write a test file from client A and verify content/ownership from B. Try a restricted access point/identity and demonstrate permission denial, not just an inaccessible network. Compare measured throughput/latency to application needs.

Create an authorized backup and restore to a separate test filesystem, verifying checksums and POSIX ownership. Remove sandbox mount targets/access points/filesystems and recovery artifacts according to retention policy; preserve production backups. Monitor throughput, burst credits where applicable and client I/O. Cost includes storage by class, throughput/access charges, backups and network paths.

## Shared-file architecture

```text
Authorized client A (AZ A) ─ mount target A ┐
                                          ├─ EFS filesystem
Authorized client B (AZ B) ─ mount target B ┘
                         TLS + optional IAM + POSIX/access-point rules
```

Regional EFS and One Zone have different failure domains. Mount-target topology, client routes/DNS, TCP 2049 security groups and file permissions are separate prerequisites. Unlike EBS, many clients can use the shared filesystem; concurrency correctness still belongs to the application.

## Mount and access-point walkthrough

Using an installed compatible amazon-efs-utils mount helper, a deliberate TLS/IAM mount is illustrative:

```bash
sudo mkdir -p /mnt/sandbox-efs
sudo mount -t efs -o tls,iam fs-0123456789abcdef0:/ /mnt/sandbox-efs
```

The caller/node role, filesystem policy and network must support this path. sudo and the mount point are local administrator operations; do not modify production fstab merely to follow a tutorial.

CreateAccessPoint uses PosixUser and RootDirectory, with optional CreationInfo:

```json
{
  "FileSystemId": "fs-0123456789abcdef0",
  "PosixUser": { "Uid": 1001, "Gid": 1001 },
  "RootDirectory": {
    "Path": "/sandbox-app",
    "CreationInfo": {
      "OwnerUid": 1001,
      "OwnerGid": 1001,
      "Permissions": "0750"
    }
  }
}
```

This is an API input structure for review, not an applied configuration. Existing directories are not necessarily rewritten to desired ownership; verify effective access from actual clients. No fictional posix-group flag is required.

## Throughput and class comparison

| Dimension              | Decision                                                                 |
| ---------------------- | ------------------------------------------------------------------------ |
| Performance mode       | Supported latency/IOPS behavior for the chosen filesystem/deployment.    |
| Bursting throughput    | Size-linked baseline and credit behavior; reads have different metering. |
| Elastic throughput     | Workload-driven throughput with its applicable charge/constraints.       |
| Provisioned throughput | Explicit capacity with mode-specific pricing/constraints.                |
| IA/Archive lifecycle   | Inactivity, access charges, minimum duration and transition-back policy. |

Do not use a fixed “MB/s per GB” claim for all modes. Small-file/metadata-heavy workloads can have different bottlenecks from large sequential I/O. Benchmark actual application patterns and watch permitted throughput/consumption and client latency.

## Backup and cross-account operations

Configure EFS backup policy separately from filesystem creation. An AWS Backup plan needs a name, rules/windows and authorized selections/role; backup creation without a selection does not cover the filesystem. Restore to a separate target and compare content, ownership and access.

For cross-account mounts, plan routing/DNS/targets, resource/identity policies and supported IAM/TLS behavior together. Successful network connection does not mean the client can read every path. Unmount sandbox clients before removing targets/filesystem and inspect retained recovery artifacts afterward.

## References

- [EFS performance and throughput modes](https://docs.aws.amazon.com/efs/latest/ug/performance.html)
- [Access-point creation contract](https://docs.aws.amazon.com/cli/latest/reference/efs/create-access-point.html)
- [Filesystem backup policy](https://docs.aws.amazon.com/cli/latest/reference/efs/put-backup-policy.html)
- [Lifecycle management](https://docs.aws.amazon.com/efs/latest/ug/lifecycle-management-efs.html)
- [EFS pricing](https://aws.amazon.com/efs/pricing/)

## Across the wiki

- [[Kubernetes/eks/storage/efs-csi|EFS CSI Driver]] — shared file storage (Kubernetes)
- [[Azure/compute/aks/storage-csi-files-blob|AKS Shared Storage CSI — Azure Files (NFS/SMB) and Azure Blob CSI Architecture]] — shared file storage (Azure)
- [[GCP/compute/gke/filestore-csi|GKE Filestore CSI Driver — Managed NFS and ReadWriteMany (RWX) Architecture]] — shared file storage (GCP)

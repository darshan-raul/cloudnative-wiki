---
title: Storage on EKS
tags: [eks, storage]
date: 2026-05-17
description: Storage options for EKS - EBS, EFS, FSx, Mountpoint for S3
---

# Storage on EKS

## Overview

EKS supports multiple storage options through Container Storage Interface (CSI) drivers.

## Topics

### Block Storage
- [[Kubernetes/eks/storage/ebs-csi|EBS CSI]] - Persistent block storage
- [[Kubernetes/eks/storage/fsx-openzfs|FSx for OpenZFS]] - Managed ZFS file system
- [[Kubernetes/eks/storage/fsx-netapp-ontap|FSx for NetApp ONTAP]] - NetApp ONTAP file system

### File Storage
- [[Kubernetes/eks/storage/efs-csi|EFS CSI]] - Managed NFS file storage
- [[Kubernetes/eks/storage/fsx-netapp-ontap|FSx for NetApp ONTAP]]
- [[Kubernetes/eks/storage/fsx-openzfs|FSx for OpenZFS]]

### Object Storage
- [[Kubernetes/eks/storage/mountpoint-s3|Mountpoint for S3]] - S3 as a file system

## Storage Comparison

| Type | Driver | Use Case | Scaling |
|------|--------|----------|---------|
| Block | EBS CSI | Databases | Single AZ |
| File | EFS CSI | Shared storage | Multi-AZ |
| File | FSx ONTAP | Enterprise NAS | Multi-AZ |
| Object | Mountpoint | S3 access | Unlimited |

## References

- [EKS Storage](https://docs.aws.amazon.com/eks/latest/userguide/storage.html)
- [EKS Workshop - Storage](https://www.eksworkshop.com/docs/fundamentals/storage/)
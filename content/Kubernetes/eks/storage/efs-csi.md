---
title: EFS CSI Driver
tags: [eks, storage, efs, csi]
date: 2026-05-17
description: Shared NFS storage on EKS with the Amazon EFS CSI driver — access-point provisioning, networking requirements, identity, performance trade-offs and Fargate support.
---

# EFS CSI Driver

The EFS CSI driver mounts an [[AWS/storage/efs/README|Amazon EFS]] file system into pods over NFS. Reach for it when several pods, possibly on different nodes and in different zones, need to read and write the same files: shared uploads, CMS content, ML training data, build caches.

It is the opposite trade-off from [[Kubernetes/eks/storage/ebs-csi|EBS]]: you gain `ReadWriteMany` and multi-AZ access, and you pay with higher per-operation latency.

## How it works

One EFS file system is shared by many PersistentVolumes. Isolation between them comes from **EFS access points**: each access point is a directory inside the file system with an enforced POSIX user, group and root path. With dynamic provisioning, every PVC gets its own access point.

```
EFS file system fs-0123 (regional, mount target in each AZ)
├── /dynamic/pvc-aaa   ← access point, uid 1001   → PVC "uploads"
├── /dynamic/pvc-bbb   ← access point, uid 1002   → PVC "reports"
└── /shared            ← static PV, mounted by several teams
```

Pods reach the file system through a **mount target**, an ENI in each Availability Zone. This is plain [[AWS/networking/vpc/README|VPC]] networking, so two things must be true before anything mounts:

1. A mount target exists in every zone where nodes run.
2. The mount target's [[AWS/networking/vpc/security-groups|security group]] allows inbound TCP 2049 from the node security group (or the pod security group, if you use [[Kubernetes/eks/networking/vpc-cni/security-groups-for-pods|security groups for pods]]).

A missing rule here is the most common EFS failure on EKS, and it shows up as a pod stuck in `ContainerCreating` with a mount timeout.

## Install

```bash
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name aws-efs-csi-driver \
  --pod-identity-associations \
    serviceAccount=efs-csi-controller-sa,roleArn=arn:aws:iam::111122223333:role/efs-csi-controller
```

The role uses the managed policy `AmazonEFSCSIDriverPolicy`, which lets the controller create and delete access points. Static provisioning needs no AWS permissions at all, because nothing is created — the driver only mounts.

## Dynamic provisioning

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-0123456789abcdef0
  directoryPerms: "700"
  basePath: /dynamic
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: uploads
spec:
  accessModes: [ReadWriteMany]
  storageClassName: efs
  resources:
    requests:
      storage: 5Gi # required by the API, ignored by EFS
```

The `storage` request is not a quota. EFS is elastic and the driver does not enforce the size, so a single noisy PVC can grow without limit and you are billed for what is stored.

## Static provisioning

Use a hand-written PV when the file system already holds data or is shared across clusters:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: shared-assets
spec:
  capacity:
    storage: 5Gi
  accessModes: [ReadWriteMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  csi:
    driver: efs.csi.aws.com
    volumeHandle: fs-0123456789abcdef0::fsap-0aaaabbbbccccdddd
```

The `volumeHandle` format is `fileSystemId:subPath:accessPointId`; leave parts empty to mount the root.

## Performance and cost

- **Latency.** Every operation is a network round trip, typically low single-digit milliseconds. Databases, anything doing many small fsyncs, and tools that walk large directory trees (`node_modules`, Git checkouts) run badly on EFS.
- **Throughput mode.** Elastic throughput scales automatically and bills per GB transferred; it suits spiky workloads. Provisioned throughput is cheaper when load is steady and predictable.
- **Storage classes.** Lifecycle policies move cold files to Infrequent Access and Archive automatically. See [[AWS/cost-management/efs-cost-optimization|EFS cost optimization]].
- **Encryption.** In transit is on by default through the driver's TLS tunnel; at rest is a property of the file system and must be chosen at creation.

## Limits

| Limit                         | Detail                                                                                                      |
| :---------------------------- | :---------------------------------------------------------------------------------------------------------- |
| Access points per file system | 1,000, which caps dynamically provisioned PVCs per file system                                              |
| Fargate                       | Static provisioning only; the driver is built into [[Kubernetes/eks/compute/fargate/README\|Fargate]] nodes |
| File locking and ownership    | An access point forces one uid/gid, so `chown` inside the container fails — set `fsGroup` to match instead  |
| Windows nodes                 | Not supported                                                                                               |

## Related

- [[Kubernetes/eks/storage/README|Storage on EKS]]
- [[Kubernetes/eks/storage/fsx-netapp-ontap|FSx for NetApp ONTAP]] — when you need NFS with snapshots, clones or lower latency
- [[Kubernetes/concepts/L05-config-storage/03-volumes|Volumes]] and [[Kubernetes/concepts/L05-config-storage/04-persistentvolume|PersistentVolumes]]
- [Amazon EFS CSI driver user guide](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)

## Across the wiki

- [[Azure/compute/aks/storage-csi-files-blob|AKS Shared Storage CSI — Azure Files (NFS/SMB) and Azure Blob CSI Architecture]] — shared file storage (Azure)
- [[GCP/compute/gke/filestore-csi|GKE Filestore CSI Driver — Managed NFS and ReadWriteMany (RWX) Architecture]] — shared file storage (GCP)
- [[AWS/storage/fsx/README|Amazon FSx]] — shared file storage (AWS)

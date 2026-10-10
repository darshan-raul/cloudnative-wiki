---
title: FSx for OpenZFS on EKS
tags: [eks, storage, fsx, openzfs, csi]
date: 2026-05-17
description: Low-latency shared NFS storage on EKS with the Amazon FSx for OpenZFS CSI driver — file system versus volume provisioning, snapshots, quotas and how it compares with EFS and FSx ONTAP.
---

# FSx for OpenZFS on EKS

[[AWS/storage/fsx/README|FSx for OpenZFS]] is a managed NFS file server built on ZFS. It gives pods `ReadWriteMany` storage with latency close to a local disk — far lower than [[Kubernetes/eks/storage/efs-csi|EFS]] — at the price of provisioning capacity and throughput up front.

Typical uses: build and CI caches, media processing, analytics scratch space, and migrating applications that already expect an NFS server with ZFS features.

## How it compares

|                      | EFS                        | FSx for OpenZFS | FSx for NetApp ONTAP                |
| :------------------- | :------------------------- | :-------------- | :---------------------------------- |
| Capacity             | Elastic, pay per GB stored | Provisioned     | Provisioned SSD + elastic cold tier |
| Latency              | Milliseconds               | Sub-millisecond | Sub-millisecond                     |
| Protocols            | NFS                        | NFS             | NFS, SMB, iSCSI                     |
| Snapshots and clones | No                         | Yes             | Yes                                 |
| Per-volume quotas    | No                         | Yes             | Yes                                 |
| Operational weight   | Lowest                     | Medium          | Highest                             |

If you only need shared files and do not care about latency, EFS is simpler. If you need multi-protocol access or SnapMirror, use [[Kubernetes/eks/storage/fsx-netapp-ontap|ONTAP]]. OpenZFS is the middle option.

## Two things the driver can provision

The CSI driver (`fsx.openzfs.csi.aws.com`) understands two resource types:

- **File system** — each PVC creates an entire FSx file system. Slow (minutes) and expensive; only sensible when a workload needs dedicated hardware.
- **Volume** — each PVC creates a child ZFS dataset inside an existing file system. Fast and cheap, and the normal choice. Each volume can have its own quota, reservation, compression setting and record size.

```
FSx file system fs-0123 (throughput and SSD provisioned once)
└── root volume fsvol-root
    ├── fsvol-aaa   ← PVC "ci-cache"    quota 200 GiB, zstd
    └── fsvol-bbb   ← PVC "render-out"  quota 1 TiB,  lz4
```

## Install

The driver is installed with Helm, and the controller gets its role through [[Kubernetes/eks/security/pod-identity|Pod Identity]] or [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]]:

```bash
helm repo add aws-fsx-openzfs-csi-driver \
  https://kubernetes-sigs.github.io/aws-fsx-openzfs-csi-driver
helm upgrade --install aws-fsx-openzfs-csi-driver \
  aws-fsx-openzfs-csi-driver/aws-fsx-openzfs-csi-driver \
  --namespace kube-system
```

The role needs `fsx:CreateVolume`, `fsx:DeleteVolume`, `fsx:UpdateVolume`, `fsx:CreateSnapshot`, the matching `Describe*` and tagging actions, and the file-system equivalents if you provision file systems.

## Volume provisioning

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fsx-openzfs-volume
provisioner: fsx.openzfs.csi.aws.com
parameters:
  ResourceType: "volume"
  ParentVolumeId: '"fsvol-0123456789abcdef0"'
  DataCompressionType: '"ZSTD"'
  NfsExports: '[{"ClientConfigurations": [{"Clients": "10.0.0.0/16", "Options": ["rw","crossmnt","no_root_squash"]}]}]'
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - nfsvers=4.1
  - rsize=1048576
  - wsize=1048576
```

Parameter values are passed straight to the FSx API as JSON, which is why strings carry an extra layer of quotes. Check the driver's parameter reference for the exact set supported by your driver version.

For volumes, the PVC's `storage` request becomes the ZFS quota, so unlike EFS the size is enforced.

## Snapshots

ZFS snapshots are instant and space-efficient. With the `snapshot-controller` add-on and a `VolumeSnapshotClass` for this driver you can snapshot a PVC and restore it to a new one. A restored volume can be a **clone** (shares blocks with the snapshot, instant) or a **full copy** (independent, takes time), selected through the StorageClass.

## Networking and availability

- Allow NFS from the nodes to the file system's [[AWS/networking/vpc/security-groups|security group]]: TCP and UDP 111, 2049 and 20001–20003.
- A Single-AZ file system is one server in one zone. Pods in other zones can mount it, but they pay cross-AZ data transfer and lose access if that zone fails.
- Multi-AZ deployments fail over to a standby in another zone. As with ONTAP, the endpoint IP floats through route-table entries, so every route table used by node subnets must be associated with the file system.

## Limits worth knowing

- Storage capacity can be increased but not decreased.
- Throughput is a property of the file system and shared by all volumes; one busy volume can starve the others.
- Not available on [[Kubernetes/eks/compute/fargate/README|Fargate]] — the driver needs a node DaemonSet.

## Related

- [[Kubernetes/eks/storage/README|Storage on EKS]]
- [[Kubernetes/concepts/L05-config-storage/06-storageclass|StorageClass]]
- [[Linux/storage/filesystems|Linux filesystems]] — background on ZFS-style copy-on-write
- [aws-fsx-openzfs-csi-driver on GitHub](https://github.com/kubernetes-sigs/aws-fsx-openzfs-csi-driver)

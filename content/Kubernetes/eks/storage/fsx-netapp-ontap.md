---
title: FSx for NetApp ONTAP on EKS
tags: [eks, storage, fsx, netapp, trident, csi]
date: 2026-05-17
description: Using Amazon FSx for NetApp ONTAP from EKS through the NetApp Trident CSI driver — NAS versus SAN backends, snapshots and clones, multi-AZ behaviour and when it beats EBS or EFS.
---

# FSx for NetApp ONTAP on EKS

[[AWS/storage/fsx/README|FSx for NetApp ONTAP]] is a managed ONTAP file system. On EKS it is consumed through **NetApp Trident**, NetApp's CSI driver, which AWS distributes as an EKS add-on. It fills the gap between [[Kubernetes/eks/storage/ebs-csi|EBS]] and [[Kubernetes/eks/storage/efs-csi|EFS]]: shared or block storage that survives a zone failure, with storage-level snapshots and instant clones.

## When to choose it

| Need                                                    | EBS           | EFS             | FSx ONTAP                  |
| :------------------------------------------------------ | :------------ | :-------------- | :------------------------- |
| `ReadWriteMany`                                         | No            | Yes             | Yes (NAS backend)          |
| Stateful pod must fail over to another AZ with its data | No            | Yes             | Yes (Multi-AZ file system) |
| Sub-millisecond latency for databases                   | Yes           | No              | Yes (SSD tier)             |
| Instant, space-efficient clones for test environments   | No            | No              | Yes (FlexClone)            |
| Replication to another region                           | Snapshot copy | EFS replication | SnapMirror                 |
| Same storage for Linux and Windows pods (NFS and SMB)   | No            | No              | Yes                        |

The cost is operational: you run a file system with fixed provisioned capacity and throughput, and you learn a little ONTAP vocabulary.

## Concepts

- **File system** — the FSx resource: an HA pair of file servers, single-AZ or multi-AZ, with a provisioned SSD tier and an elastic capacity pool tier.
- **SVM (storage virtual machine)** — an isolated tenant inside the file system with its own endpoints and credentials. Trident talks to one SVM.
- **Volume** — the unit Trident creates for each PVC (or shares between PVCs, depending on the driver).
- **Backend** — Trident's description of how to reach an SVM and which protocol to use.

## Install Trident

```bash
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name netapp_trident-operator
```

Trident needs credentials for the SVM. Store them in [[AWS/security/secrets-manager/README|Secrets Manager]] and let Trident read them through [[Kubernetes/eks/security/pod-identity|Pod Identity]], rather than keeping a password in a Kubernetes Secret.

## Backends: NAS or SAN

```yaml
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: fsx-nas
  namespace: trident
spec:
  version: 1
  storageDriverName: ontap-nas
  svm: svm1
  aws:
    fsxFilesystemID: fs-0123456789abcdef0
  credentials:
    name: arn:aws:secretsmanager:eu-west-1:111122223333:secret:fsx-svm1-abc123
    type: awsarn
```

| Driver      | Protocol | Access modes      | Use it for                             |
| :---------- | :------- | :---------------- | :------------------------------------- |
| `ontap-nas` | NFS      | RWO, RWX, ROX     | Shared files, most general workloads   |
| `ontap-san` | iSCSI    | RWO (block or fs) | Databases that want a raw block device |

SAN volumes need `iscsid` and multipath running on the nodes, which means a custom AMI or user data. NAS works on the stock EKS AMIs and is the sensible default.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fsx-ontap-nas
provisioner: csi.trident.netapp.io
parameters:
  backendType: ontap-nas
  fsType: nfs
allowVolumeExpansion: true
reclaimPolicy: Delete
```

## Snapshots and clones

ONTAP snapshots are pointer-based: they take no time and no extra space until data diverges. Through the standard `VolumeSnapshot` API you get:

- point-in-time recovery of a PVC,
- a writable clone of a production volume for a test namespace in seconds, by creating a PVC with `dataSource` set to the snapshot,
- fast environment refreshes in CI without copying data.

This is the feature that most often justifies FSx ONTAP over EFS.

## Networking and failover

- Nodes must reach the SVM's NFS or iSCSI endpoints. Allow the ONTAP ports from the node [[AWS/networking/vpc/security-groups|security group]] (NFS 2049 and 111, iSCSI 3260, plus the management endpoint on 443 for Trident).
- A **Multi-AZ** file system exposes floating endpoint IPs from a range outside the subnet CIDRs and adds routes to the route tables you choose. Pods in every route table that carries those routes keep the same mount across a failover; forget a route table and pods in those subnets cannot mount.
- Failover takes tens of seconds. NFS clients retry transparently; applications see a pause, not an error.

## Cost levers

Capacity is provisioned, so idle SSD costs money. Enable tiering so cold blocks move to the cheaper capacity pool, turn on deduplication and compression (on by default with Trident-created volumes), and size throughput to the workload rather than the peak. See [[AWS/storage/fsx/README|FSx]] for pricing dimensions.

## Related

- [[Kubernetes/eks/storage/README|Storage on EKS]]
- [[Kubernetes/eks/storage/fsx-openzfs|FSx for OpenZFS]] — simpler NFS-only alternative
- [[Kubernetes/guides/non-functional/disaster-recovery|Disaster recovery]] and [[Kubernetes/guides/non-functional/backup-restore|backup and restore]]
- [Trident documentation for FSx for ONTAP](https://docs.netapp.com/us-en/trident/trident-use/trident-fsx.html)

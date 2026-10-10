---
title: EBS CSI Driver
tags: [eks, storage, ebs, csi]
date: 2026-05-17
description: How the Amazon EBS CSI driver provisions block volumes on EKS — identity, StorageClass design, zone binding, attachment limits, resizing, snapshots and failure modes.
---

# EBS CSI Driver

The EBS CSI driver is what turns a `PersistentVolumeClaim` into an [[AWS/storage/ebs/README|EBS]] volume attached to the node running the pod. It is the default answer for anything that needs a fast disk owned by a single pod: databases, queues, search indexes.

Before reading on, make sure the Kubernetes side is clear: [[Kubernetes/concepts/L05-config-storage/04-persistentvolume|PersistentVolume]], [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim|PersistentVolumeClaim]] and [[Kubernetes/concepts/L05-config-storage/06-storageclass|StorageClass]].

## How it works

The driver has two halves:

| Component            | Runs as                 | What it does                                                                             |
| :------------------- | :---------------------- | :--------------------------------------------------------------------------------------- |
| `ebs-csi-controller` | Deployment (2 replicas) | Calls the EC2 API: `CreateVolume`, `AttachVolume`, `ModifyVolume`, `CreateSnapshot`      |
| `ebs-csi-node`       | DaemonSet on every node | Formats the device, mounts it into the pod, reports the node's zone and attachment limit |

Only the controller needs AWS permissions. The node plugin works with the local block device and never calls AWS for volume operations.

The consequence that matters most: **an EBS volume lives in exactly one Availability Zone**. A pod that owns a volume in `eu-west-1a` can only ever be scheduled in `eu-west-1a`. Everything else on this page follows from that.

## Install

Install it as an EKS add-on so AWS manages the version, and give the controller its role through [[Kubernetes/eks/security/pod-identity|EKS Pod Identity]] (or [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]] on older setups):

```bash
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name aws-ebs-csi-driver \
  --pod-identity-associations \
    serviceAccount=ebs-csi-controller-sa,roleArn=arn:aws:iam::111122223333:role/ebs-csi-controller
```

The role needs the AWS managed policy `AmazonEBSCSIDriverPolicy`. If you encrypt with a customer managed [[AWS/security/kms/README|KMS]] key, add `kms:CreateGrant`, `kms:Decrypt`, `kms:GenerateDataKeyWithoutPlaintext` and `kms:DescribeKey` on that key — the managed policy does not cover it, and the symptom is a PVC stuck in `Pending` with an access-denied event.

On [[Kubernetes/eks/compute/eks-auto-mode/README|EKS Auto Mode]] you do not install anything: block storage is built in and the provisioner name is `ebs.csi.eks.amazonaws.com` instead of `ebs.csi.aws.com`.

## A StorageClass worth using

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
parameters:
  type: gp3
  encrypted: "true"
  # iops: "6000"        # gp3 baseline is 3000
  # throughput: "250"   # MiB/s, gp3 baseline is 125
```

Why each line is there:

- **`WaitForFirstConsumer`** delays volume creation until the scheduler has picked a node. With `Immediate`, the volume is created in a random zone first and the pod may then be unschedulable because no node in that zone has room.
- **`gp3`** decouples IOPS and throughput from size. The legacy `gp2` class that older clusters shipped with ties performance to volume size, and recent EKS versions no longer mark any class as default — create one explicitly.
- **`allowVolumeExpansion`** lets you grow a volume by editing the PVC. Volumes can grow but never shrink.
- **`reclaimPolicy: Delete`** removes the EBS volume with the PVC. Use `Retain` for data you cannot afford to lose to a mistaken `kubectl delete`.

## Day-2 operations

**Resize.** Edit `spec.resources.requests.storage` on the PVC. The controller calls `ModifyVolume` and the node plugin grows the filesystem online. EBS allows one modification per volume roughly every six hours.

**Change performance without recreating.** A `VolumeAttributesClass` lets you move a live volume to different IOPS, throughput or type by setting `volumeAttributesClassName` on the PVC.

**Snapshots.** Install the `snapshot-controller` add-on, create a `VolumeSnapshotClass` with driver `ebs.csi.aws.com`, then create `VolumeSnapshot` objects. Restoring is a new PVC with a `dataSource` pointing at the snapshot. For scheduled backups across a fleet, [[AWS/storage/ebs/amazon-data-lifecycle-manager|Data Lifecycle Manager]] or Velero ([[Kubernetes/guides/non-functional/backup-restore|backup and restore]]) is the usual choice.

## Limits and failure modes

| Symptom                                             | Cause                                                                                               | Fix                                                                                              |
| :-------------------------------------------------- | :-------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------- |
| PVC `Pending`, event says `UnauthorizedOperation`   | Controller has no role, or the role lacks KMS permissions                                           | Check the Pod Identity association and the key policy                                            |
| Pod `Pending` with "volume node affinity conflict"  | The volume is in a zone with no schedulable capacity                                                | Run node groups in every zone the workload uses; with Karpenter, allow that zone in the NodePool |
| Pod stuck `ContainerCreating`, "Multi-Attach error" | The old pod's node died and the volume is still attached to it                                      | Wait for the six-minute force-detach, or delete the stale `VolumeAttachment`                     |
| `AttachVolume` fails on a busy node                 | Per-instance attachment limit reached (on many Nitro types volumes and ENIs share one budget of 28) | Spread stateful pods, or use instance types with a dedicated volume limit                        |
| StatefulSet will not move after a zone outage       | The data is in the failed zone                                                                      | Restore from snapshot into another zone; replicate at the application layer                      |

EBS volumes are `ReadWriteOnce`. If several pods need the same files, that is a job for [[Kubernetes/eks/storage/efs-csi|EFS]], not EBS.

## Related

- [[Kubernetes/eks/storage/README|Storage on EKS]] — choosing between block, file and object
- [[Kubernetes/guides/troubleshooting/pvc-stuck|PVC stuck in Pending]] — generic diagnosis flow
- [[Kubernetes/concepts/L03-workloads/04-statefulsets|StatefulSets]] — the workload type that normally owns EBS volumes
- [[AWS/cost-management/ebs-cost-optimization|EBS cost optimization]]
- [Amazon EBS CSI driver user guide](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)

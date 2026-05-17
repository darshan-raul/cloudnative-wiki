---
title: FSx for NetApp ONTAP
tags: [eks, storage, fsx, netapp]
date: 2026-05-17
description: FSx for NetApp ONTAP CSI driver for EKS
---

# FSx for NetApp ONTAP

## Overview

FSx for NetApp ONTAP provides enterprise-grade NFS storage with advanced features like snapshots, clones, and data replication.

## Install FSx ONTAP CSI Driver

```bash
helm repo add aws-fsx-openzfs-csi-driver https://kubernetes-sigs.github.io/aws-fsx-openzfs-csi-driver
helm repo update

helm install aws-fsx-openzfs-csi-driver aws-fsx-openzfs-csi-driver/aws-fsx-openzfs-csi-driver \
  --namespace kube-system
```

## Create StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fsx-ontap-sc
provisioner: fsxn.csi.netapp.com
parameters:
  svName: fsx-ontap-svm
  snapshotDirectory: "false"
  exportPolicyName: default
  nfsMountOptions: "rsize=1048576,wsize=1048576"
```

## Use in Pod

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fsx-ontap-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: fsx-ontap-sc
  resources:
    requests:
      storage: 100Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: app-with-fsx
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - mountPath: /data
      name: fsx-volume
  volumes:
  - name: fsx-volume
    persistentVolumeClaim:
      claimName: fsx-ontap-claim
```

## Key Features

- Snapshot and clone support
- Data replication
- Compression and deduplication
- Multi-protocol (NFS, SMB)

## References

- [FSx for NetApp ONTAP CSI](https://docs.aws.amazon.com/eks/latest/userguide/fsx-csi.html)
- [EKS Workshop - FSxN](https://www.eksworkshop.com/docs/fundamentals/storage/fsx-for-netapp-ontap/)
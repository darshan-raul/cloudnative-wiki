---
title: FSx for OpenZFS
tags: [eks, storage, fsx, openzfs]
date: 2026-05-17
description: FSx for OpenZFS CSI driver for EKS
---

# FSx for OpenZFS

## Overview

FSx for OpenZFS provides managed ZFS file storage with features like snapshots, compression, and replication.

## Install OpenZFS CSI Driver

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
  name: fsx-openzfs-sc
provisioner: openzfs.csi.aws.com
parameters:
  fileSystemId: fs-12345678
  dataSetName: /k8s-volume
```

## Use in Pod

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fsx-openzfs-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: fsx-openzfs-sc
  resources:
    requests:
      storage: 50Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: app-with-zfs
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - mountPath: /data
      name: zfs-volume
  volumes:
  - name: zfs-volume
    persistentVolumeClaim:
      claimName: fsx-openzfs-claim
```

## Key Features

- Snapshots (point-in-time copies)
- Clones (copy-on-write)
- Compression
- Low latency

## References

- [FSx for OpenZFS CSI](https://docs.aws.amazon.com/eks/latest/userguide/fsx-csi.html)
- [EKS Workshop - OpenZFS](https://www.eksworkshop.com/docs/fundamentals/storage/fsx-for-openzfs/)
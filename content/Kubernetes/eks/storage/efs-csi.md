---
title: EFS CSI Driver
tags: [eks, storage, efs, csi]
date: 2026-05-17
description: Amazon EFS Container Storage Interface driver for EKS
---

# EFS CSI Driver

## Overview

The EFS CSI driver provides persistent multi-az file storage for EKS pods.

## Install EFS CSI Driver

```bash
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver
helm repo update

helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system
```

## Create EFS File System

```bash
# Create security group for EFS
aws ec2 create-security-group \
  --group-name efs-sg \
  --description "EFS for EKS"

# Create EFS file system
aws efs create-file-system \
  --creation-token eks-storage \
  --tags Key=Name,Value=eks-efs
```

## Create StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-12345678
  directoryPerms: "700"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
```

## Dynamic Provisioning

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi
```

## Use in Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-efs
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - mountPath: /shared-data
      name: efs-volume
  volumes:
  - name: efs-volume
    persistentVolumeClaim:
      claimName: efs-claim
```

## Access Points

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-pv
spec:
  capacity:
    storage: 5Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc
  csi:
    driver: efs.csi.aws.com
    volumeHandle: fs-12345678
    volumeArn: arn:aws:efs:us-west-2:123456789:file-system/fs-12345678
    directoryPerms: "700"
    fsxDirPath: /my-access-point
```

## References

- [EFS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
- [EKS Workshop - EFS](https://www.eksworkshop.com/docs/fundamentals/storage/efs/)
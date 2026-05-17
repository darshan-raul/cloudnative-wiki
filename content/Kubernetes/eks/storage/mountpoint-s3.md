---
title: Mountpoint for Amazon S3
tags: [eks, storage, s3, mountpoint]
date: 2026-05-17
description: Mountpoint for S3 CSI driver - S3 as a file system
---

# Mountpoint for S3

## Overview

Mountpoint for S3 enables mounting S3 buckets as a file system in EKS pods.

## Install Mountpoint CSI Driver

```bash
helm repo add aws-mountpoint-s3-csi-driver https://kubernetes-sigs.github.io/mountpoint-for-s3-csi-driver
helm repo update

helm install aws-mountpoint-s3-csi-driver aws-mountpoint-s3-csi-driver/aws-mountpoint-s3-csi-driver \
  --namespace kube-system
```

## Create StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: s3-sc
provisioner: s3.amazonaws.com
parameters:
  bucketName: my-bucket
  mountOptions: "allow-delete,allow-write"
```

## Use in Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-s3
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - mountPath: /data
      name: s3-volume
  volumes:
  - name: s3-volume
    persistentVolumeClaim:
      claimName: s3-claim
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: s3-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: s3-sc
  resources:
    requests:
      storage: 1000Gi  # Virtual size, S3 is unlimited
```

## Use Cases

- Machine learning datasets
- Data lakes
- Log archival
- Backup storage

## Limitations

- Eventually consistent
- No rename/rename directories
- No hard links
- Higher latency than EBS/EFS

## References

- [Mountpoint for S3](https://docs.aws.amazon.com/eks/latest/userguide/s3-csi.html)
- [EKS Workshop - Mountpoint](https://www.eksworkshop.com/docs/fundamentals/storage/mountpoint-s3/)
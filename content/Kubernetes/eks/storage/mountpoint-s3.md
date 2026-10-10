---
title: Mountpoint for Amazon S3 CSI Driver
tags: [eks, storage, s3, mountpoint, csi]
date: 2026-05-17
description: Mounting S3 buckets into EKS pods with the Mountpoint CSI driver — what file operations work, static provisioning, IAM scoping, caching and when to use the S3 API instead.
---

# Mountpoint for Amazon S3 CSI Driver

The Mountpoint CSI driver presents an [[AWS/storage/s3/README|S3]] bucket as a directory inside a pod. It exists for applications that read large objects through file APIs and cannot easily be changed to use the S3 SDK: ML training jobs, genomics pipelines, analytics engines, legacy batch tools.

It is **not** a general-purpose file system. Understanding what it refuses to do is most of what there is to know.

## What works and what does not

Mountpoint translates file operations into S3 API calls and deliberately rejects anything that S3 cannot do efficiently.

| Operation                                   | Supported | Notes                                                                  |
| :------------------------------------------ | :-------- | :--------------------------------------------------------------------- |
| Sequential and random reads                 | Yes       | The main use case; very high throughput                                |
| Listing directories                         | Yes       | Backed by `ListObjectsV2`; large prefixes are slow                     |
| Writing a new file sequentially             | Yes       | Uploaded as a multipart upload; visible to others only after `close()` |
| Overwriting an existing file                | Opt-in    | Needs `allow-overwrite`, and the file must be rewritten from the start |
| Deleting files                              | Opt-in    | Needs `allow-delete`                                                   |
| Appending to or editing in place            | No        | S3 objects are immutable (append exists only on S3 Express One Zone)   |
| Renaming files or directories               | No        | Except on S3 Express One Zone directory buckets                        |
| Symlinks, hard links, file locking, `chmod` | No        | Permissions are fixed by mount options, not stored                     |

Anything that needs a real POSIX file system — a database, a Git working tree, `pip install` — will fail, usually with `Operation not permitted`. Use [[Kubernetes/eks/storage/efs-csi|EFS]] or [[Kubernetes/eks/storage/ebs-csi|EBS]] for those.

## Install

```bash
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name aws-mountpoint-s3-csi-driver \
  --pod-identity-associations \
    serviceAccount=s3-csi-driver-sa,roleArn=arn:aws:iam::111122223333:role/s3-csi-driver
```

Scope the role to the buckets that are actually mounted:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::training-data"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::training-data/*"
    }
  ]
}
```

Drop the write actions for read-only mounts. If the bucket uses a customer managed [[AWS/security/kms/README|KMS]] key, the role also needs `kms:Decrypt` and `kms:GenerateDataKey`.

By default every pod on the cluster shares the driver's role. Version 2 of the driver runs Mountpoint in its own pods and can use the **consuming pod's** identity instead (`authenticationSource: pod` in the volume attributes), which is what you want in a multi-tenant cluster so that each workload only reaches its own buckets. See [[Kubernetes/eks/security/pod-identity|Pod Identity]].

## Static provisioning

Only static provisioning is supported: the bucket must already exist, and you write the PV by hand.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: training-data
spec:
  capacity:
    storage: 1Ti # required by the API, ignored
  accessModes: [ReadOnlyMany]
  storageClassName: ""
  mountOptions:
    - region eu-west-1
    - prefix datasets/v3/
    - uid=1000
    - gid=1000
    - allow-other
  csi:
    driver: s3.csi.aws.com
    volumeHandle: training-data-pv # any unique string
    volumeAttributes:
      bucketName: training-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: training-data
spec:
  accessModes: [ReadOnlyMany]
  storageClassName: ""
  volumeName: training-data
  resources:
    requests:
      storage: 1Ti
```

Use `ReadWriteMany` plus `allow-delete` / `allow-overwrite` when pods must write. Set `uid`/`gid` to the container's user or the files will be unreadable to a non-root process.

## Performance

- **Throughput** scales with object size and parallelism. Mountpoint issues parallel range requests, so one large file read sequentially can saturate the node's network.
- **Local cache.** The `cache` mount option keeps object data on node storage, which helps jobs that re-read the same files across epochs. Size the node's ephemeral storage accordingly.
- **Metadata** is the weak spot. Each `stat` or directory listing is an API call; millions of small files will be slow and will generate request charges. Pack small files into archives or use a format such as Parquet or WebDataset.
- **Network cost.** Reads from a bucket in the same region are free of transfer charges; route them through an S3 gateway endpoint so they do not traverse a NAT gateway — see [[AWS/cost-management/network-cost-optimization|network cost optimization]].

## When to skip it

If you control the application code, calling S3 directly is simpler, has clearer error handling and avoids a privileged node component. Mountpoint earns its place when the code is not yours or when a framework only accepts file paths.

## Related

- [[Kubernetes/eks/storage/README|Storage on EKS]]
- [[AWS/cost-management/s3-cost-optimization|S3 cost optimization]]
- [[Kubernetes/concepts/L05-config-storage/04-persistentvolume|PersistentVolume]] — static provisioning mechanics
- [Mountpoint for Amazon S3 CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/s3-csi.html)

## Across the wiki

- [[Azure/storage/blob|Azure Blob Storage & Data Lake Storage Gen2]] — object storage (Azure)
- [[GCP/storage/gcs|Google Cloud Storage (GCS)]] — object storage (GCP)
- [[GCP/compute/gke/cloud-storage-fuse|GKE Cloud Storage FUSE CSI Driver — AI/ML Object Storage as a File System]] — object storage (GCP)

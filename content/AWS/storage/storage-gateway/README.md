---
title: "AWS Storage Gateway"
description: "Storage Gateway connects on-premises applications to supported cloud-backed storage interfaces."
tags:
  - aws/storage
date: 2026-10-12
---

# AWS Storage Gateway

Storage Gateway connects on-premises applications to supported cloud-backed storage interfaces. Choose the gateway type from the application protocol and where primary data must live, then provision the appliance/cache, network and IAM role. Prerequisites: [[AWS/storage/README|storage selection]], [[AWS/storage/s3/README|S3]] and [[AWS/networking/README|networking]].

## Gateway types and failure domains

| Gateway               | Interface            | Data placement                                                                                   |
| --------------------- | -------------------- | ------------------------------------------------------------------------------------------------ |
| S3 File Gateway       | NFS/SMB shares       | Files become S3 objects with local caching.                                                      |
| Cached Volume Gateway | iSCSI block volumes  | Primary data in AWS, frequently accessed blocks cached locally.                                  |
| Stored Volume Gateway | iSCSI block volumes  | Primary data local; asynchronous cloud snapshots provide recovery artifacts.                     |
| Tape Gateway          | Virtual tape library | Backup applications write virtual tapes; archival follows the documented eject/archive workflow. |

A local cache is not an independent cloud backup, and loss of the appliance/network has mode-specific impact. S3 buckets are regional, not placed in an appliance's “same AZ.” Incoming transfer into AWS is not a universal per-GB gateway egress tariff: gateway data-written charges, storage/request/retrieval and network charges are separate.

## Configuration and access contracts

File-share creation needs the gateway ARN, IAM Role and ClientToken plus a supported storage-class value such as S3_STANDARD; S3 alone is not that enum. NFS clients, default permissions and SMB authentication use different schemas. Authorize the gateway role for its bucket/KMS operations; avoid broad public bucket access.

There is no storagegateway/archive-tape command. Archival is initiated through the backup application's virtual-tape eject workflow. Distinguish changing a file gateway object's S3 class from archival of a virtual tape.

## Hybrid recovery exercise

Use a non-production appliance/client and small disposable dataset, with capacity and recurring-charge budget. Follow the selected gateway's requirements before activation; existing production backup applications are not sandbox targets.

Create one restricted share/volume/tape, write data and confirm cloud synchronization using mode-specific monitoring. Demonstrate a denied unauthorized client. Interrupt the sandbox network and observe cache/queued-upload behavior; do not assume uncached reads continue.

For a file gateway, verify object visibility and file metadata expectations; for a volume/tape gateway, perform an actual supported restore into an isolated target. Compare measured RPO/RTO to the workload. Remove sandbox shares/volumes/tapes according to retention, gateway resources and local appliance; track retained snapshots/tapes separately.

## Operations and cost

Monitor cache utilization, dirty cache/queued uploads, upload bandwidth and health metrics relevant to the mode. Size local disk and bandwidth for outage duration and write rate. Estimate gateway service data-written units, cloud storage, requests, retrieval, local appliance and network charges separately. Cloud snapshot durability does not mean the local primary volume is immune to disaster.

## Local/cloud placement diagrams

```text
File Gateway:
NFS/SMB client → local cache → S3 objects

Cached Volume Gateway:
iSCSI client → local cache → primary cloud-backed volume data

Stored Volume Gateway:
iSCSI client → primary local disk → asynchronous EBS snapshots

Tape Gateway:
backup application → virtual tape library → supported cloud archive
```

Gateway cache sizing and appliance availability must match write rate and outage duration. Stored primary data remaining local is a different failure model from cached primary data in AWS; evaluate local disaster recovery and cloud access separately.

## File share and volume setup sequence

1. Choose the protocol/gateway type and supported appliance environment.
2. Provision required local disks/compute and connectivity; distinguish cache, upload buffer and primary data where applicable.
3. Activate the appliance using the supported workflow and protect activation material.
4. Configure a scoped service role/KMS access and the actual bucket/volume/tape target.
5. Create a share/volume with its real API schema: NFS and SMB authentication/client fields differ.
6. Mount/connect from an authorized test client and verify sync/upload status.
7. Exercise an outage and recovery with bounded disposable data before adopting production RPO/RTO.

CreateNFSFileShare/CreateSMBFileShare require Role and ClientToken plus supported storage-class values; an invented S3 enum or omitted role does not become valid merely because the JSON parses.

## Protocol and consistency decisions

File Gateway bridges files to objects; verify supported file attributes, ownership and refresh behavior when other clients change S3 objects. A gateway cache is not a general distributed lock manager for independent object writers. SMB authentication/domain setup and NFS allowed-client rules require separate design.

For Volume Gateway, snapshot recovery creates a supported recovered volume/state; it does not reconstruct arbitrary application consistency without quiescing. For Tape Gateway, the backup application drives eject/archive behavior and its own catalog remains important for restores. There is no generic archive-tape CLI command.

Watch dirty cache, upload queue, local disk pressure and gateway health. Model service data written, retained storage/snapshots/tapes, requests, retrieval, appliance and network costs individually. Delete sandbox shares/volumes/tapes only through approved retention-aware workflows; keeping a tape archive or snapshot is still retained billable data.

## Worked S3 File Gateway NFS lab

Choose **S3 File Gateway (`FILE_S3`) + NFS**, a dedicated private SSE-S3 bucket and one authorized Linux client. This is not a Volume/Tape Gateway recipe. Follow the [appliance/disk/network requirements](https://docs.aws.amazon.com/filegateway/latest/files3/Requirements.html) to deploy a disposable supported gateway VM/EC2 appliance with a separate blank cache disk. Keep local-console recovery access. Confirm Region STS availability, gateway endpoint connectivity, the client's private routing and the required NFS ports. Budget appliance compute/disks plus gateway/S3/network usage.

Before activation, obtain its short-lived activation key through the gateway console/local activation workflow; do not publish it or activate a production appliance. Set GATEWAY_LAB_ACTIVATION_KEY, GATEWAY_LAB_BUCKET and GATEWAY_LAB_CLIENT_CIDR (the single authorized client's actual /32 address). Python/Boto3 uses temporary operator credentials in the intended Region.

```python
import os
import time
import uuid
import boto3

gateway = boto3.client("storagegateway")
region = gateway.meta.region_name
gateway_arn = gateway.activate_gateway(
    ActivationKey=os.environ["GATEWAY_LAB_ACTIVATION_KEY"],
    GatewayName="cloudnative-wiki-nfs-lab", GatewayTimezone="GMT",
    GatewayRegion=region, GatewayType="FILE_S3",
)["GatewayARN"]
print(gateway_arn)
print(gateway.list_local_disks(GatewayARN=gateway_arn)["Disks"])
```

Match the additional blank disk's path/size to the appliance configuration, then set GATEWAY_LAB_CACHE_DISK_ID to that returned DiskId. Never select the boot disk or an allocated disk automatically. Allocate only that verified disk:

```python
gateway.add_cache(GatewayARN=gateway_arn,
                  DiskIds=[os.environ["GATEWAY_LAB_CACHE_DISK_ID"]])
```

Create a dedicated gateway data role and set GATEWAY_LAB_ROLE_ARN to its ARN. Its trust policy allows `storagegateway.amazonaws.com` to call `sts:AssumeRole`, constrained with your account's `aws:SourceAccount` and the returned gateway's `aws:SourceArn` per [the gateway role guide](https://docs.aws.amazon.com/filegateway/latest/files3/security_iam_id-based-policy-examples.html). Use this bucket-scoped permission policy, replacing both bucket names; do not attach it to the operator's human identity:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:GetBucketAcl",
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:ListBucketMultipartUploads"
      ],
      "Resource": "arn:aws:s3:::REPLACE_WITH_DEDICATED_BUCKET"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:PutObjectAcl",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::REPLACE_WITH_DEDICATED_BUCKET/*"
    }
  ]
}
```

Check bucket ownership/ACL compatibility with the current gateway guide; this lab does not request a public object ACL. An SSE-KMS bucket additionally requires the actual encryption configuration and key authorization, not just this S3 policy. The operator needs PassRole for this specific service role.

Create the share, keeping its token for retries. ClientList is deliberately not the default everyone-accessible network range. AllSquash maps this one test client's users to the anonymous account; NFS/IP restrictions do not authenticate end-user identities like SMB/AD.

```python
share_token = str(uuid.uuid4())
share_arn = gateway.create_nfs_file_share(
    ClientToken=share_token, GatewayARN=gateway_arn,
    Role=os.environ["GATEWAY_LAB_ROLE_ARN"],
    LocationARN="arn:aws:s3:::" + os.environ["GATEWAY_LAB_BUCKET"],
    DefaultStorageClass="S3_STANDARD", ReadOnly=False,
    ClientList=[os.environ["GATEWAY_LAB_CLIENT_CIDR"]], Squash="AllSquash",
    NFSFileShareDefaults={"FileMode": "0660", "DirectoryMode": "0770",
                          "GroupId": 65534, "OwnerId": 65534},
    Tags=[{"Key": "Purpose", "Value": "cloudnative-wiki-nfs-lab"}],
)["FileShareARN"]
deadline = time.monotonic() + 600
while time.monotonic() < deadline:
    share = gateway.describe_nfs_file_shares(FileShareARNList=[share_arn])["NFSFileShareInfoList"][0]
    if share["FileShareStatus"] == "AVAILABLE":
        break
    if share["FileShareStatus"] == "DELETING":
        raise RuntimeError("Share was deleted during setup")
    time.sleep(10)
else:
    raise TimeoutError(f"Inspect share {share_arn} and gateway role/connectivity")
print(share_arn, share["Path"])
```

On the authorized Linux client, install its distribution's supported NFS client package. Set GATEWAY_LAB_IP to the gateway's private IP and GATEWAY_LAB_EXPORT to the returned Path, not an invented `/sfshare`:

```bash
sudo mkdir -p /mnt/cloudnative-wiki-gateway-lab
sudo mount -t nfs -o vers=3,nolock,hard \
  "${GATEWAY_LAB_IP:?}:${GATEWAY_LAB_EXPORT:?}" \
  /mnt/cloudnative-wiki-gateway-lab
printf 'order_id,total\nlab-001,25\nlab-002,40\n' \
  > /mnt/cloudnative-wiki-gateway-lab/gateway-lab-orders.csv
sha256sum /mnt/cloudnative-wiki-gateway-lab/gateway-lab-orders.csv
sync
```

Record that SHA-256. In the same Python control session, set GATEWAY_LAB_EXPECTED_SHA256 to it and verify the actual uploaded object rather than treating a successful NFS write as cloud durability:

```python
import hashlib
from botocore.exceptions import ClientError

s3 = boto3.client("s3")
deadline = time.monotonic() + 300
while time.monotonic() < deadline:
    try:
        data = s3.get_object(Bucket=os.environ["GATEWAY_LAB_BUCKET"],
                             Key="gateway-lab-orders.csv")["Body"].read()
        if hashlib.sha256(data).hexdigest() == os.environ["GATEWAY_LAB_EXPECTED_SHA256"]:
            break
    except ClientError as error:
        if error.response["Error"]["Code"] != "NoSuchKey":
            raise  # AccessDenied is not a synchronization delay.
    time.sleep(5)
else:
    raise TimeoutError("Object did not match; inspect upload/cache/errors")
print("Verified uploaded bytes", len(data))
print(gateway.notify_when_uploaded(FileShareARN=share_arn)["NotificationId"])
```

NotifyWhenUploaded returns a correlation ID; completion is asynchronous via the documented event, not that API response. The checksum proves this file's upload, not every file in the share. Test a client outside ClientList and expect mount/access denial; use a bounded mount attempt and inspect the actual server/client error.

For the outage drill, close file handles and unmount first: hard NFS I/O can block while the server is unavailable. Temporarily interrupt only the disposable appliance's upstream S3 connectivity through an approved, reversible lab network change while preserving local console recovery. Observe cached/dirty data and upload failures, restore connectivity, remount and reconcile a second uniquely named file. Do not use uncached-file availability or a VM write acknowledgement as an RPO guarantee.

Unmount the client, confirm uploads are drained, and delete only share_arn using `gateway.delete_file_share(FileShareARN=share_arn, ForceDelete=False)`. Inspect completion before deleting gateway_arn with `gateway.delete_gateway`; forced share deletion can lose pending writes and is not the normal cleanup path. Decommission only the dedicated appliance/disks/role/network rules. Delete the exact disposable objects and their versions after retention review; do not empty an unrelated bucket. [Activation API](https://docs.aws.amazon.com/cli/latest/reference/storagegateway/activate-gateway.html), [NFS share schema](https://docs.aws.amazon.com/cli/latest/reference/storagegateway/create-nfs-file-share.html), [NFS mounting](https://docs.aws.amazon.com/filegateway/latest/files3/GettingStartedAccessFileShare.html), [upload notification](https://docs.aws.amazon.com/cli/latest/reference/storagegateway/notify-when-uploaded.html).

## References

- [Gateway architecture](https://docs.aws.amazon.com/storagegateway/latest/vgw/StorageGatewayConcepts.html)
- [NFS file-share contract](https://docs.aws.amazon.com/cli/latest/reference/storagegateway/create-nfs-file-share.html)
- [SMB file-share contract](https://docs.aws.amazon.com/cli/latest/reference/storagegateway/create-smb-file-share.html)
- [Tape archiving workflow](https://docs.aws.amazon.com/storagegateway/latest/tgw/archiving-tapes.html)
- [Storage Gateway pricing](https://aws.amazon.com/storagegateway/pricing/)

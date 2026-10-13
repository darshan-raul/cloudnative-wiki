---
title: "Amazon S3"
description: "S3 stores objects in regional buckets."
tags:
  - aws/storage
date: 2026-10-12
---

# Amazon S3

S3 stores objects in regional buckets. An object key is unique within a bucket, not globally; slashes are prefix characters, not directories. Versioning adds version IDs, while metadata and tags serve different application and policy purposes.

Prerequisites: [[AWS/security/iam/README|IAM]], [[AWS/storage/README|storage selection]] and [[AWS/networking/README|networking]]. Learn identity permissions, bucket policies, KMS permissions and network access separately.

## Consistency and capacity

PUTs, overwrites, DELETEs, reads and listings are strongly consistent automatically, in every Region, without an extra consistency charge. This does not make a sequence of updates to multiple objects a transaction.

A single PUT supports up to 5 GB. Larger objects use multipart upload: the current limit is 48.8 TiB, with up to 10,000 parts; parts are 5 MiB–5 GiB except that the last has no minimum. Abandoned multipart uploads retain billable parts, so configure their lifecycle cleanup. Parallel requests, sensible prefix distribution and retry/backoff help throughput; do not confuse request-rate guidance with a maximum bucket size.

## Storage-class decisions

| Class                      | Access and retention trade-off                                                                                                               |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Standard                   | Frequent access, multiple AZs.                                                                                                               |
| Standard-IA / One Zone-IA  | Infrequent access; retrieval and minimum-size/duration charges. One Zone-IA is for data whose AZ loss is acceptable.                         |
| Intelligent-Tiering        | Automatic access-tier movement; eligible objects incur monitoring/automation charges. Archive Access and Deep Archive Access require opt-in. |
| Glacier Instant Retrieval  | Millisecond access, 90-day minimum storage duration.                                                                                         |
| Glacier Flexible Retrieval | Restore before ordinary access; 90-day minimum, expedited/standard/bulk options.                                                             |
| Glacier Deep Archive       | Longer restore delay and 180-day minimum.                                                                                                    |

Minimum duration is a billing condition, not mandatory retention protection. Learn [[AWS/storage/glacier/README|archive restores and Object Lock]] before committing compliance data.

## Security and lifecycle

Prefer Block Public Access and Bucket owner enforced Object Ownership (ACLs disabled). A public-read policy is not a baseline security recipe. Use least-privilege bucket/access-point policies; default SSE-S3 encryption does not imply a customer-managed KMS key. SSE-KMS adds key permissions and request costs.

Versioning makes overwrites recoverable but does not prevent deletion of versions. Lifecycle rules can transition/expire current and noncurrent versions and remove incomplete multipart uploads. Replication uses configured rules/roles and versioned source/destination buckets; it is not automatically a backup of every existing object. [[AWS/storage/s3/protection-and-recovery|S3 protection and recovery]] develops the combined retention, authorization and restore design.

Use a private S3 origin with CloudFront Origin Access Control for website delivery where applicable. The S3 website endpoint has different HTTPS/access characteristics. Transfer Acceleration is optional and should be measured against its surcharge.

Inventory reports are periodic datasets, not a real-time listing. Its configuration uses IsEnabled and a required configuration ID. Event notification configurations use TopicConfigurations/TopicArn, QueueConfigurations/QueueArn or LambdaFunctionConfigurations/LambdaFunctionArn, with matching destination permissions. Expect duplicate/out-of-order notifications and implement idempotency. S3 Select is closed to new customers; use [[AWS/analytics/athena/README|Athena]] or another supported query path.

## Sandbox version-recovery exercise

Create a private bucket in a chosen Region with a globally unique name, enable versioning and keep public access blocked. These are CLI v2 examples requiring your own bucket; request/storage charges can apply.

```bash
aws s3api put-bucket-versioning --bucket example-unique-bucket \
  --versioning-configuration Status=Enabled
aws s3api get-bucket-versioning --bucket example-unique-bucket
aws s3api list-object-versions --bucket example-unique-bucket
```

Upload two different versions of a small file, verify the current content immediately and retrieve an earlier version using its version ID. An identity without GetObject permission should receive AccessDenied, even with the correct object URL. Observe actual policy/KMS errors rather than opening the bucket publicly.

Cleanup includes all versions and delete markers, not merely current keys; empty the disposable bucket before deleting it. Do not run bulk deletion on a production bucket. Separately test one lifecycle rule on an isolated prefix and examine the rule schema before applying it.

## Bucket, key and version anatomy

```text
Bucket: example-unique-bucket
  └─ key: logs/2026/10/12/app.json
       ├─ object bytes and Content-Type metadata
       ├─ object tags (separate from key prefix)
       └─ version ID when versioning is enabled
```

Prefixes group keys for listing/lifecycle/policies; they are not real directories. General-purpose bucket names follow the documented uniqueness/naming scope, while other bucket types have distinct rules. Use s3://bucket/key for CLI object references and the correct access-point ARN/alias when using an access point—not a fabricated access-point hostname.

## Object-operation walkthrough

These CLI v2 commands operate on a disposable private bucket and an existing local file. Replace the exact bucket/key and budget storage/requests.

```bash
aws s3 cp ./sample.json s3://example-unique-bucket/sandbox/sample.json
aws s3api head-object --bucket example-unique-bucket --key sandbox/sample.json
aws s3 cp s3://example-unique-bucket/sandbox/sample.json ./downloaded-sample.json
aws s3api list-objects-v2 --bucket example-unique-bucket --prefix sandbox/
```

Verify checksum/content, not only exit status. A recursive sync/rm can affect many objects and versioning changes deletion semantics; do not copy production bulk deletion commands into a lab. HeadObject authorization errors can differ from nonexistent-object results depending on permissions.

## Lifecycle configuration with a restricted prefix

Applying PutBucketLifecycleConfiguration replaces the configuration, so first inspect/preserve existing rules. The example uses one sandbox prefix; its future expiration is an intentional deletion policy, not retention protection.

```json
{
  "Rules": [
    {
      "ID": "sandbox-archive",
      "Status": "Enabled",
      "Filter": { "Prefix": "sandbox/archive/" },
      "Transitions": [
        { "Days": 30, "StorageClass": "STANDARD_IA" },
        { "Days": 90, "StorageClass": "GLACIER" },
        { "Days": 365, "StorageClass": "DEEP_ARCHIVE" }
      ],
      "Expiration": { "Days": 730 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    }
  ]
}
```

Save as a reviewed JSON file and pass it through --lifecycle-configuration file://... with the actual bucket. Small-object transition defaults/minimum billing and class constraints affect applicability. Noncurrent versions need their own actions; expiring current objects does not necessarily remove all stored versions.

## Replication, inventory and notifications

For replication, enable required versioning, authorize the replication role for source/destination/KMS operations and define prefix/tag/deletion/version rules. Existing objects may need a supported batch workflow rather than automatic retroactive replication. Same-Region and cross-Region replication solve different locality/account requirements.

An Inventory report can include all versions and supported optional fields; configure IsEnabled, required ID, destination policy and schedule from the owning schema. It is periodic evidence, not immediate object-change detection. For notifications, give the target permission to accept S3 delivery, choose actual TopicConfigurations/QueueConfigurations/LambdaFunctionConfigurations fields and account for duplicates/out-of-order events. EventBridge is a distinct supported route.

Static website endpoints and REST/CloudFront origins have different HTTPS/access behavior. Prefer a private origin with OAC where supported; a public-read policy is a deliberate exception, not a default setup step. Transfer Acceleration is opt-in and should be tested against geographical/client behavior and added fees.

## Cost and references

Model storage GB-months + request counts + retrieval/transition fees + replication/network + eligible monitoring/KMS fees. Rates depend on Region, class and operation; do not multiply a monthly subtotal by retention months twice.

- [Strong consistency](https://aws.amazon.com/s3/consistency/)
- [Multipart limits](https://docs.aws.amazon.com/AmazonS3/latest/userguide/qfacts.html)
- [Storage classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html)
- [Intelligent-Tiering](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering-overview.html)
- [Inventory CLI contract](https://docs.aws.amazon.com/cli/latest/reference/s3api/put-bucket-inventory-configuration.html)
- [Notification CLI contract](https://docs.aws.amazon.com/cli/latest/reference/s3api/put-bucket-notification-configuration.html)
- [S3 Select availability](https://docs.aws.amazon.com/AmazonS3/latest/userguide/selecting-content-from-objects.html)
- [S3 pricing](https://aws.amazon.com/s3/pricing/)

## Across the wiki

- [[Azure/storage/blob|Azure Blob Storage & Data Lake Storage Gen2]] — object storage (Azure)
- [[GCP/storage/gcs|Google Cloud Storage (GCS)]] — object storage (GCP)
- [[Kubernetes/eks/storage/mountpoint-s3|Mountpoint for Amazon S3 CSI Driver]] — object storage (Kubernetes)
- [[GCP/compute/gke/cloud-storage-fuse|GKE Cloud Storage FUSE CSI Driver — AI/ML Object Storage as a File System]] — object storage (GCP)

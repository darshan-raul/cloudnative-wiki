---
title: Amazon S3
description: Amazon S3 — object storage with 11 9s of durability. Buckets, objects, prefixes, storage classes, lifecycle rules, replication, versioning, and access control.
tags:
  - aws
  - storage
  - s3
---

# Amazon S3 (Simple Storage Service)

S3 is the primary object storage service in AWS. Objects (files) are stored in buckets (containers) with a flat namespace identified by a globally unique key. Durability is 99.999999999% (11 9s) across multiple AZs.

## Core Concepts

### Buckets and Objects

```
Bucket: my-app-assets (globally unique name)
  └── Object
       ├── Key: "images/logo.png"
       ├── Value: [binary data]
       ├── VersionId: "abc123"
       ├── Metadata: {Content-Type: "image/png"}
       └── Tags: {Environment: "Production"}
```

### S3 URI

```
s3://my-app-assets/images/logo.png
        ↑bucket         ↑key
```

### Object Key Structure

S3 keys can simulate folder structure with prefixes:

```
logs/
  2024/
    01/
      15/
        app.log
        error.log
    02/
      app.log
```

The `/` in keys is just a character — S3 has no real directory hierarchy. Prefix `logs/` groups all log objects.

## Storage Classes

| Class | Durability | Availability | Use Case | Cost (per GB/mo) |
|-------|-----------|--------------|----------|-------------------|
| S3 Standard | 11 9s | 99.99% | Hot data, frequent access | ~$0.023 |
| S3 Intelligent-Tiering | 11 9s | 99.9% | Unknown access patterns | ~$0.023 (monitoring) |
| S3 Standard-IA | 11 9s | 99.9% | Infrequent (30+ days) | ~$0.0125 |
| S3 Glacier IA | 11 9s | 99.99% | Rare (90+ days) | ~$0.004 |
| S3 Glacier | 11 9s | 99.99% | Archive (180+ days) | ~$0.00099 |
| S3 Glacier Deep Archive | 11 9s | 99.99% | Very rare (365+ days) | ~$0.00099 |
| S3 One Zone-IA | 11 9s | 99.5% | Re-creatable infrequent | ~$0.01 |

### Intelligent-Tiering

Automatically moves objects between tiers based on access patterns:
- Frequent → Infrequent → Archive → Deep Archive
- 0 monitoring/automation charge per object
- Best for unpredictable access patterns

## Creating a Bucket

```bash
aws s3 mb s3://my-unique-bucket-name
```

### Enabling Versioning

```bash
aws s3api put-bucket-versioning \
  --bucket my-bucket \
  --versioning-configuration Status=Enabled
```

### Enabling Encryption

```bash
aws s3api put-bucket-encryption \
  --bucket my-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

## Working with Objects

```bash
# Upload
aws s3 cp myfile.txt s3://my-bucket/
aws s3 cp ./local-dir s3://my-bucket/ --recursive

# Download
aws s3 cp s3://my-bucket/myfile.txt ./
aws s3 sync s3://my-bucket/ ./local-dir

# Delete
aws s3 rm s3://my-bucket/myfile.txt

# List
aws s3 ls s3://my-bucket/
aws s3 ls s3://my-bucket/logs/
aws s3api list-objects-v2 --bucket my-bucket
```

## Access Control

### Bucket Policies

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicRead",
    "Effect": "Allow",
    "Principal": "*",
    "Action": ["s3:GetObject"],
    "Resource": "arn:aws:s3:::my-public-bucket/*"
  }]
}
```

### ACLs (less common now)

```
Private          → Owner only (default)
PublicRead       → Read object
PublicReadWrite  → Read and write
AuthenticatedRead → Any AWS authenticated user
```

### Access Points

Simplify access for multiple applications:

```bash
aws s3control create-access-point \
  --account-id 123456789012 \
  --bucket my-bucket \
  --name mobile-app-access
# Access: s3://ap，移动应用-access.my-bucket.s3.amazonaws.com/
```

## Lifecycle Rules

Automate storage class transitions:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-bucket \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "log-retention",
      "Prefix": "logs/",
      "Status": "Enabled",
      "Transitions": [
        {"Days": 30, "StorageClass": "STANDARD_IA"},
        {"Days": 90, "StorageClass": "GLACIER"},
        {"Days": 365, "StorageClass": "DEEP_ARCHIVE"}
      ],
      "Expiration": {"Days": 730}
    }]
  }'
```

## Replication

### Cross-Region Replication (CRR)

```bash
aws s3api put-bucket-replication \
  --bucket my-source-bucket \
  --replication-configuration '{
    "Role": "arn:aws:iam::123456789012:role/s3-replication-role",
    "Rules": [{
      "ID": "replicate-to-us-west-2",
      "Status": "Enabled",
      "Destination": {
        "Bucket": "arn:aws:s3:::my-dest-bucket-us-west-2"
      }
    }]
  }'
```

### Same-Region Replication (SRR)

For compliance, multi-account, or analytics.

## Static Website Hosting

```bash
aws s3 website s3://my-bucket \
  --index-document index.html \
  --error-document error.html

# Make objects publicly readable
aws s3api put-bucket-policy \
  --bucket my-bucket \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::my-bucket/*"
    }]
  }'
```

Website endpoint: `http://my-bucket.s3-website-us-east-1.amazonaws.com`

## S3 Transfer Acceleration

Speed up uploads via edge locations:

```bash
aws s3api put-bucket-accelerate-configuration \
  --bucket my-bucket \
  --accelerate-configuration Status=Enabled
```

Upload to: `my-bucket.s3-accelerate.amazonaws.com`

## Performance Optimization

### Prefix Partitioning

S3 auto-scales, but partitioning keys helps:
- Good: `logs/2024/01/15/app.log` (year/month/day/hour)
- Bad: `logs/app.log` (single hot prefix)

### Multipart Upload

For files > 100MB:

```bash
aws s3 cp large-file.zip s3://my-bucket/  # SDK handles multipart automatically
```

### S3 Select

Query CSV/JSON/Parquet without fetching the whole object:

```bash
aws s3 select-object-content \
  --bucket my-bucket \
  --key data.csv \
  --expression "SELECT * FROM s3object WHERE price > 100" \
  --input-serialization CSV \
  --output-serialization JSON
```

## S3 Inventory

Audit all objects in a bucket:

```bash
aws s3api put-bucket-inventory-configuration \
  --bucket my-bucket \
  --inventory-configuration '{
    "Id": "full-inventory",
    "Enabled": true,
    "Destination": {
      "S3BucketDestination": {
        "Format": "Parquet",
        "Bucket": "arn:aws:s3:::my-inventory-bucket"
      }
    },
    "Schedule": {"Frequency": "Daily"},
    "IncludedObjectVersions": "All"
  }'
```

## Event Notifications

Trigger Lambda or SNS on S3 events:

```bash
aws s3api put-bucket-notification-configuration \
  --bucket my-bucket \
  --notification-configuration '{
    "TopicConfiguration": [{
      "Topic": "arn:aws:sns:us-east-1:123456789012:my-topic",
      "Events": ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    }]
  }'
```

## S3 Access Analyzer

Analyze access to prevent accidental exposure:

```bash
aws s3control get-access-point-policy \
  --account 123456789012 \
  --name mobile-app-access
```

## Limits

| Resource | Limit |
|----------|-------|
| Bucket name | 3-63 chars, globally unique, lowercase |
| Object size | 5TB (single PUT), 5GB (multipart) |
| Objects per bucket | Unlimited |
| Buckets per account | 100 (soft limit) |
| PUT request | 5GB |
| Multipart upload | 10000 parts, 5MB-5GB per part |

## References

- **Homepage:** https://aws.amazon.com/s3/
- **Documentation:** https://docs.aws.amazon.com/AmazonS3/latest/userguide/
- **Pricing:** https://aws.amazon.com/s3/pricing/

## Pricing Examples

**Scenario 1:** A media application storing 100GB of images. 100GB = ~$2.30/month (S3 Standard). PUT requests: 100K/month × $0.005/1K = $0.50. GET requests: 500K/month × $0.0004/1K = $0.20. Data transfer: 50GB egress/month × $0.09/GB = $4.50. Total: ~$7.50/month for storage and requests.

**Scenario 2:** A data lake storing 10TB of analytics data. With S3 Intelligent-Tiering (monitoring $0.0025/1K objects × 1M objects = $2.50/month, storage $0.023/GB = $230/month). Total: ~$232/month. Compare to S3 Standard: $230 + negligible = ~$230/month. Intelligent-Tiering wins for unknown access patterns. After 6 months, 30% of data auto-tiers to Infrequent: savings ~$69/month.

## Nuggets & Gotchas

- **S3 bucket names are globally unique — you can't create a bucket with a name someone else already uses:** Even if the bucket is in a different account. This is why `terraform-state-bucket-prod` style names with account IDs or random suffixes are common.
- **S3 DELETE is permanent — there is no recycle bin:** Unless you have versioning enabled (then you can delete a version marker to recover). For production buckets, use lifecycle rules with `NoncurrentVersionExpiration` to clean up old versions instead of manually deleting.
- **S3's eventual consistency applies to DELETE and PUT in certain regions — reads may return stale data briefly:** For critical reads, use strong consistency (available since 2020). But note: strong consistency costs more and has higher latency.
- **S3 costs come from storage + requests + data transfer — storage is usually the smallest line item:** A bucket with 10M small objects ($0.023/GB = $0.23/month for 10GB) may cost $50/month in GET requests (10M × $0.0004/1K). Monitor request costs separately.
- **S3 Transfer Acceleration can double data transfer costs — use it only for global uploads:** Transfer Acceleration adds $0.04-$0.08/GB on top of normal egress. For uploads from a single region, use standard S3. For global CDN origin pull, it's worth it.
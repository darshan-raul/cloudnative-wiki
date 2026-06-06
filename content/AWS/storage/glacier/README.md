---
title: Amazon S3 Glacier
description: Amazon S3 Glacier — long-term archival storage. Vaults, archives, retrieval options (expedited/standard/bulk), vault locks, and DataSync for automated archiving.
tags:
  - aws
  - storage
  - glacier
  - archive
---

# Amazon S3 Glacier

Glacier is S3's archival storage class — designed for data that is rarely accessed but must be retained for years. Pricing is very low ($0.00099/GB/mo for Deep Archive) but retrieval costs and latency are high.

## Core Concepts

### Storage Architecture

```
S3 Glacier
  └── Vault (container)
       └── Archive (the actual data)
            ├── Archive ID
            ├── SHA-256 tree hash (integrity)
            └── Description (optional)
```

### Storage Classes

| Class | Retrieval Time | Cost (per GB/mo) | Use |
|-------|--------------|------------------|-----|
| S3 Glacier | 1-5 min (expedited) / 3-5 hr (standard) | $0.004 | Rare (< 90 days) |
| S3 Glacier Deep Archive | 12 hr (standard) / 48 hr (bulk) | $0.00099 | Very rare (180+ days) |

### S3 Glacier vs S3 Standard-IA vs S3

```
S3 Standard        → Immediate access ($0.023/GB)
S3 Standard-IA     → 30+ days infrequent ($0.0125/GB)
S3 Glacier         → 90+ days archive ($0.004/GB)
S3 Glacier Deep Archive → 180+ days archive ($0.00099/GB)
```

## Creating a Vault

```bash
aws glacier create-vault \
  --vault-name my-archive-vault \
  --account-id 123456789012
```

### Uploading Archives

```bash
# Single file (under 100MB)
aws glacier upload-archive \
  --vault-name my-archive-vault \
  --body my-data.tar.gz \
  --content-type application/octet-stream

# Larger files: use multipart upload
aws glacier multipart-upload \
  --vault-name my-archive-vault \
  --part-size 1048576 \
  --archive-description "backup-2024-01"
```

### Downloading Archives

```bash
# Initiate job (retrieval request)
aws glacier initiate-job \
  --vault-name my-archive-vault \
  --job-parameters '{"Type": "archive-retrieval", "ArchiveId": "xxxxx", "Tier": "Standard"}'

# Standard: 3-5 hours
# Expedited: 1-5 minutes (costs more)
# Bulk: 5-12 hours (cheapest)

# Check job status
aws glacier describe-job \
  --vault-name my-archive-vault \
  --job-id xxxxx

# Download completed archive
aws glacier get-job-output \
  --vault-name my-archive-vault \
  --job-id xxxxx \
  output.json
```

## Vault Access Policies

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::123456789012:user/backup-admin"},
    "Action": ["glacier:UploadArchive", "glacier:DeleteArchive"],
    "Resource": "arn:aws:glacier:us-east-1:123456789012:vaults/my-archive-vault"
  }]
}
```

```bash
aws glacier set-vault-access-policy \
  --vault-name my-archive-vault \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Deny",
      "Principal": "*",
      "Action": "glacier:DeleteArchive",
      "Resource": "arn:aws:glacier:us-east-1:123456789012:vaults/my-archive-vault",
      "Condition": {"NumericLessThan": {"glacier:VaultAccessTime": "2024-12-31T00:00:00Z"}}
    }]
  }'
```

## Vault Lock (WORM Compliance)

Vault Lock enforces immutable retention policies:

```bash
# Initiate lock (7-day evaluation period)
aws glacier initiate-vault-lock \
  --vault-name my-compliance-vault \
  --lock-duration-days 7 \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": "*",
      "Action": "glacier:GetVaultAccessPolicy",
      "Resource": "arn:aws:glacier:us-east-1:123456789012:vaults/my-compliance-vault"
    }]
  }'
```

After the lock is applied (after evaluation period), no one — including the root account — can delete archives before the retention date.

## S3 Lifecycle to Glacier

Using S3 lifecycle rules to auto-archive:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-data-lake \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "archive-old-logs",
      "Prefix": "logs/",
      "Status": "Enabled",
      "Transitions": [
        {"Days": 30, "StorageClass": "STANDARD_IA"},
        {"Days": 90, "StorageClass": "GLACIER"},
        {"Days": 365, "StorageClass": "DEEP_ARCHIVE"}
      ],
      "Expiration": {"Days": 2555}
    }]
  }'
```

## Glacier DataSync

DataSync can automatically sync on-premises file data to S3 Glacier:

```bash
aws datasync create-task \
  --name "archive-to-glacier" \
  --source-location-arn arn:aws:datasync:us-east-1:123456789012:location/loc-xxxxx \
  --destination-location-arn arn:aws:datasync:us-east-1:123456789012:location/loc-yyyyy \
  --schedule '{
    "ScheduleExpression": "cron(0 3 * * ? *)"
  }'
```

## Comparison: Glacier vs S3 + Lifecycle

| | Direct Glacier | S3 → Glacier (via lifecycle) |
|--|--|--|
| Access | Via Glacier API | Via S3 API (S3 Glacier objects) |
| Retrieval options | Expedited/Standard/Bulk | Standard only |
| Vault Lock | Yes | No (use Object Lock) |
| Vault policies | Yes | No |
| Use | Native Glacier (legacy) | S3 Glacier (modern) |

**Use S3 Glacier storage class** (via S3 API) for new workloads. Direct Glacier API is for legacy compatibility.

## Limits

| Resource | Limit |
|----------|-------|
| Vaults per region | Unlimited |
| Archives per vault | Unlimited |
| Archive size | 50 TB (single upload) |
| Multipart upload parts | 10,000 |
| Vault lock policy evaluation | 7 days |

## References

- **Homepage:** https://aws.amazon.com/glacier/
- **Documentation:** https://docs.aws.amazon.com/amazonglacier/
- **Pricing:** https://aws.amazon.com/glacier/pricing/

## Pricing Examples

**Scenario 1:** A compliance requirement to retain 10TB of financial records for 7 years. 10TB × 84 months (7 years) × $0.00099/GB = $850/month. Total lifetime cost: $850 × 84 = $71,400. Compare to S3 Standard: $0.023/GB × 10TB = $230/month × 84 = $19,320. Glacier is 3.7x more expensive for this use case because the data is actively accessed (compliance audits). For rarely accessed data, Glacier wins.

**Scenario 2:** A legal hold requiring 5TB of email archives for 10 years (litigation hold). 5TB × $0.00099/GB × 120 months = $600/month lifetime. With S3 Object Lock (governance mode), you can use S3 Standard-IA for $0.0125/GB = $62.50/month × 120 = $7,500 lifetime. S3 is 12.5x cheaper for long-term legal hold if retrieval isn't needed.

## Nuggets & Gotchas

- **Glacier retrieval has three tiers with very different costs — always check which you're using:** Expedited: $0.03/GB + $0.05 per 1,000 requests. Standard: $0.01/GB. Bulk: $0.0025/GB. A 10GB archive with Expedited retrieval costs $0.30 (data) + $0.05 (request) = $0.35. Standard costs $0.10. Bulk costs $0.025. For a one-time retrieval of 10TB, bulk saves $75.
- **Vault Lock is irreversible — once locked, you cannot change or remove the policy:** This is a WORM compliance feature. Test your lock policy on a non-production vault first. A misconfigured lock can prevent legitimate access or deletion for years.
- **Glacier archives are immutable once created — you can't append or modify:** You must delete and re-upload to "modify" an archive. If you need to update archived data, use S3 with versioning instead (allows overwrite via new version).
- **Glacier Deep Archive has a minimum 90-day storage duration:** If you store data for 30 days and delete, you pay for 90 days. For data with uncertain retention, start with S3 Standard-IA (30-day minimum) and transition to Glacier later.
- **Initiating a Glacier job doesn't mean immediate retrieval — Expedited takes 1-5 minutes:** Standard: 3-5 hours. Bulk: 5-12 hours. Plan retrieval ahead of time. For urgent compliance requests (e.g., legal discovery), use Expedited retrieval ($0.03/GB) or keep a hot copy in S3 Standard.
---
title: AWS Macie
description: AWS Macie — data privacy and S3 data classification. PII/PHI/credentials detection, sensitivity scoring, policy findings, and automated remediation. Macie Classic vs Macie v2.
tags:
  - aws
  - security
  - macie
  - data-privacy
---

# AWS Macie

Macie uses machine learning to automatically discover, classify, and protect sensitive data in S3. It identifies PII (personally identifiable information), PHI (health records), credentials, and intellectual property.

## What Macie Does

```
Macie scans S3:
  │
  ├── Classification
  │   ├── Sensitive data types (PII, PHI, credentials)
  │   ├── Custom data identifiers (regex, keywords)
  │   └── Pre-built data types (credit cards, SSNs, etc.)
  │
  └── Monitoring
      ├── S3 policy changes (bucket made public)
      ├── Access patterns (unusual data access)
      └── Data egress alerts
```

## Macie Classic vs Macie v2

| Feature | Macie Classic | Macie v2 (Current) |
|---------|---------------|-------------------|
| Scope | All S3 buckets in account | Specific buckets or all |
| Classification | One-time or scheduled | Continuous (jobs) |
| Pricing | Per object scanned | Per GB classified |
| Custom identifiers | No | Yes |
| Integrations | CloudWatch | Security Hub, EventBridge |

## Enabling Macie

```bash
# Enable Macie v2
aws macie2 enable

# Accept the service linked role
aws macie2 enable --no-ignore-previous-warnings
```

## Creating a Classification Job

```bash
# One-time job (all S3, all objects)
aws macie2 create-classification-job \
  --name "full-scan" \
  --job-type ONE_TIME \
  --s3-job-definition '{
    "bucketDefinitions": [{"accountId": "123456789012", "buckets": ["my-bucket"]}]
  }'

# Scheduled job (weekly)
aws macie2 create-classification-job \
  --name "weekly-scan" \
  --job-type SCHEDULED \
  --schedule-frequency '{
    "daily": {}
  }' \
  --s3-job-definition '{
    "bucketDefinitions": [{"accountId": "123456789012", "buckets": ["my-bucket"]}]
  }'
```

## Sensitivity Scoring

Macie assigns a sensitivity score (0-100) to each S3 object:

| Score | Classification |
|-------|---------------|
| 0-49 | Low — no sensitive data |
| 50-69 | Medium — some sensitive data |
| 70-89 | High — significant sensitive data |
| 90-100 | Critical — large amounts of sensitive data |

## Finding Types

```json
{
  "type": "SensitiveData:S3Object/PII",
  "severity": {
    "score": 85
  },
  "title": "PII detected in S3 object",
  "description": "Amazon Macie detected 5 occurrences of Social Security Numbers (US) in my-bucket/finance/employees.csv",
  "resourcesAffected": {
    "s3Bucket": {"name": "my-bucket", "arn": "arn:aws:s3:::my-bucket"},
    "s3Object": {"key": "finance/employees.csv", "size": 1024, "versionId": "xxx"}
  },
  "classificationDetails": {
    "detectedAt": "2024-01-15T10:00:00Z",
    "jobId": "xxxxx",
    "result": {
      "sensitiveData": [{"category": "PII", "occurrences": 5}],
      "customDataIdentifiers": null
    }
  }
}
```

## Custom Data Identifiers

```bash
# Create custom regex identifier
aws macie2 create-custom-data-identifier \
  --name "employee-id" \
  --regex "EMP-[0-9]{6}" \
  --description "Employee ID pattern" \
  --keywords '["employee", "id"]'

# Create custom managed data identifier (keywords)
aws macie2 create-custom-data-identifier \
  --name "project-code" \
  --regex "[A-Z]{3}-[0-9]{4}" \
  --keywords '["project", "code"]'
```

## S3 Policy Monitoring

```bash
# Get policy findings
aws macie2 list-findings \
  --finding-criteria '{
    "type": [{"eq": ["EXTERNAL_BUCKET"]}]
  }'
```

Macie alerts on:
- S3 bucket made public
- S3 bucket policy changed to allow external access
- S3 bucket shared with another AWS account
- S3 bucket ACL changed

## Integration with Security Hub

```bash
# Macie sends findings to Security Hub automatically (when enabled)
aws securityhub enable-import-findings-for-product \
  --product-arn "arn:aws:securityhub:us-east-1::product/aws/macie"
```

## Automated Response

```bash
# EventBridge rule for sensitive data findings
aws events put-rule \
  --name macie-sensitive-data \
  --event-pattern '{
    "source": ["aws.macie"],
    "detail": {
      "type": ["SensitiveData:S3Object/PII"]
    }
  }'

# Target: Lambda to remediate
aws events put-targets \
  --rule macie-sensitive-data \
  --targets '[{
    "Id": "remediate",
    "Arn": "arn:aws:lambda:us-east-1:123456789012:function:macie-remediate",
    "Input": "{\"detail\": <see full event>}"
  }]'
```

### Example Remediation Lambda

```python
def lambda_handler(event, context):
    bucket = event['detail']['resourcesAffected']['s3Bucket']['name']
    key = event['detail']['resourcesAffected']['s3Object']['key']
    
    # Block public access
    s3 = boto3.client('s3')
    s3.put_public_access_block(
        Bucket=bucket,
        PublicAccessBlockConfiguration={
            'BlockPublicAcls': True,
            'IgnorePublicAcls': True,
            'BlockPublicPolicy': True,
            'RestrictPublicBuckets': True
        }
    )
    
    # Move to quarantine prefix
    s3.copy_object(
        Bucket=bucket,
        Key=f"quarantine/{key}",
        CopySource={'Bucket': bucket, 'Key': key}
    )
    s3.delete_object(Bucket=bucket, Key=key)
    
    # Notify
    sns.publish(
        TopicArn='arn:aws:sns:us-east-1:123456789012:sensitive-data-alerts',
        Message=f"Sensitive data detected in {bucket}/{key}. Moved to quarantine."
    )
```

## Pricing

| Component | Cost |
|-----------|------|
| Classification (first 10GB/month) | Free |
| Classification (after 10GB) | $0.10/GB |
| Custom data identifiers | Free |
| S3 policy monitoring | Free |

## Limits

| Resource | Limit |
|----------|-------|
| Classification jobs | 20 per account |
| Custom data identifiers | 50 per account |
| S3 buckets | Unlimited |
| Objects per job | Unlimited |

## References

- **Homepage:** https://aws.amazon.com/macie/
- **Documentation:** https://docs.aws.amazon.com/macie/
- **Pricing:** https://aws.amazon.com/macie/pricing/

## Pricing Examples

**Scenario 1:** A company with 100GB of S3 data. First 10GB free. 90GB × $0.10 = $9/month. Macie is extremely cheap for typical workloads.

**Scenario 2:** A data analytics company with 5TB of S3 data. 5TB - 10GB free = 5TB × $0.10/GB = $512/month. For 5TB of data, consider whether continuous classification is necessary or if one-time classification jobs are sufficient.

## Nuggets & Gotchas

- **Macie only scans S3 — it doesn't scan RDS, DynamoDB, or EBS:** Macie is specifically for object storage. For database-level sensitive data classification, use different tools (e.g., AWS CloudWatch Data Protection for logs).
- **Macie v2's continuous classification runs on NEW and MODIFIED objects only — not all existing objects:** If you need full initial classification, run a one-time job first, then continuous jobs will maintain it. Don't assume continuous = all historical data classified.
- **Macie's PII detection for custom formats (internal employee IDs, etc.) requires custom data identifiers ($0.10/GB still applies):** Pre-built identifiers (SSN, credit card) are free. Custom regex/keyword identifiers cost the same as standard classification.
- **Macie findings auto-sent to Security Hub if both are enabled — no additional cost:** If you already use Security Hub, enabling Macie is "free" in terms of integration effort. Just make sure to filter Macie findings in Security Hub.
- **Macie can trigger on EVERY new object in a busy S3 bucket — set up job frequency carefully:** If you upload 100K objects/day, Macie will scan each one. For high-volume buckets, consider daily or weekly scheduled jobs instead of continuous.
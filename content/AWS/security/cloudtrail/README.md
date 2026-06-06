---
title: AWS CloudTrail
description: AWS CloudTrail — API audit logging. Trails, event history, S3 log delivery, CloudWatch integration, encryption, and compliance.
tags:
  - aws
  - security
  - audit
  - cloudtrail
---

# AWS CloudTrail

CloudTrail records AWS API calls made in your account. Every AWS action (Console, CLI, SDK) generates a CloudTrail event. It's the primary tool for security auditing, compliance, and incident investigation.

## Core Concepts

### Event Types

| Event Type | Description | Examples |
|------------|-------------|----------|
| Management Events | Control plane operations | CreateInstance, DeleteBucket, AttachRolePolicy |
| Data Events | Data plane operations | GetObject, PutObject, PutItem, Query |
| Insight Events | Unusual API call patterns | Spike in Delete*, abnormal Create* activity |

### CloudTrail vs CloudWatch Logs vs VPC Flow Logs

```
CloudTrail     → AWS API calls (who did what, when, from where)
CloudWatch Logs → Application logs, custom logs (not AWS API)
VPC Flow Logs  → Network traffic (who talked to whom, not API calls)
```

### Event Structure

```json
{
  "eventVersion": "1.08",
  "userIdentity": {
    "type": "IAMUser",
    "arn": "arn:aws:iam::123456789012:user/alice",
    "principalId": "AIDAXXXXXXXXXXXXX",
    "accountId": "123456789012"
  },
  "eventTime": "2024-01-15T10:30:00Z",
  "eventSource": "ec2.amazonaws.com",
  "eventName": "RunInstances",
  "awsRegion": "us-east-1",
  "sourceIPAddress": "203.0.113.10",
  "userAgent": "aws-cli/2.0",
  "requestParameters": {
    "instanceType": "t3.micro",
    "imageId": "ami-xxxxx"
  },
  "responseElements": {
    "reservationId": "r-xxxxx",
    "instancesSet": [{"instanceId": "i-xxxxx"}]
  },
  "requestID": "xxxxx-xxxxx",
  "eventID": "xxxxx-xxxxx",
  "readOnly": false,
  "eventType": "AwsApiCall",
  "managementEvent": true,
  "recipientAccountId": "123456789012"
}
```

## Creating a Trail

```bash
# Create trail (logs to S3)
aws cloudtrail create-trail \
  --name my-trail \
  --s3-bucket-name my-cloudtrail-logs \
  --s3-key-prefix cloudtrail/ \
  --is-multi-region \
  --include-global-service-events

# Start logging
aws cloudtrail start-logging --name my-trail

# Enable log file validation
aws cloudtrail update-trail \
  --name my-trail \
  --enable-log-file-validation
```

### S3 Bucket Policy for CloudTrail

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "cloudtrail.amazonaws.com"},
    "Action": "s3:PutObject",
    "Resource": "arn:aws:s3:::my-cloudtrail-logs/*",
    "Condition": {
      "StringEquals": {
        "s3:x-amz-acl": "bucket-owner-full-control",
        "aws:SourceAccount": "123456789012"
      }
    }
  }]
}
```

## CloudWatch Integration

```bash
# Create CloudWatch Logs group
aws logs create-log-group --log-group-name cloudtrail-logs

# Configure trail to send to CloudWatch
aws cloudtrail update-trail \
  --name my-trail \
  --cloud-watch-logs-log-group-arn arn:aws:logs:us-east-1:123456789012:log-group/cloudtrail-logs:* \
  --cloud-watch-logs-role-arn arn:aws:iam::123456789012:role/CloudTrail-CloudWatchLogs

# Set log retention
aws logs put-retention-policy \
  --log-group-name cloudtrail-logs \
  --retention-in-days 90
```

CloudWatch integration enables real-time alerting on API calls:

```json
{
  "filterPattern": "{$.eventName = \"DeleteBucket\"}",
  "logGroupName": "/aws/cloudtrail/my-trail"
}
```

## Querying CloudTrail Logs

### Via Athena

```sql
CREATE TABLE cloudtrail_logs (
  eventTime STRING,
  eventName STRING,
  userIdentity_arn STRING,
  sourceIPAddress STRING,
  userAgent STRING,
  eventSource STRING,
  awsRegion STRING
)
PARTITIONED BY (region string, year string, month string)
LOCATION 's3://my-cloudtrail-logs/AWSLogs/123456789012/CloudTrail/';

-- Query for suspicious activity
SELECT * FROM cloudtrail_logs
WHERE eventName = 'ConsoleLogin'
  AND sourceIPAddress NOT IN ('203.0.113.0/24')
  AND eventTime > '2024-01-01'
```

### Via CloudWatch Insights

```bash
# CloudWatch Insights query
aws cloudwatch-insights run-query \
  --log-group-name cloudtrail-logs \
  --query-string 'fields @timestamp, userIdentity.arn, eventName, sourceIPAddress | filter eventName like /Delete|Remove/ | sort @timestamp desc | limit 20'
```

## Event History

CloudTrail retains 90 days of events in Event History (free, no trail required):

```bash
# Look up specific events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --start-time 2024-01-01T00:00:00Z

# Look up by user
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=alice
```

## Log File Encryption

```bash
# Enable SSE-KMS encryption for CloudTrail logs
aws cloudtrail update-trail \
  --name my-trail \
  --kms-key-id xxxxx-xxxxx-xxxxx \
  --enable-kms-log-encryption
```

CloudTrail encrypts log files with the specified CMK. You pay for KMS API calls (~$0.03/10K calls).

## Security Recommendations

| Recommendation | Why |
|----------------|-----|
| Enable multi-region trail | Capture events from all regions |
| Enable global service events | Capture IAM, STS, Lambda events |
| Enable log file validation | Detect tampering with log files |
| Send to CloudWatch | Real-time alerting (not just post-hoc) |
| Use S3 Object Lock | Prevent log deletion (compliance) |
| Enable Insights events | Detect abnormal activity |

## Pricing

| Component | Cost |
|-----------|------|
| Management events | Free (90-day event history) |
| Data events | $0.10/100,000 events (S3), $0.05/100,000 events (DynamoDB) |
| Insight events | $0.10/100,000 events |
| S3 storage | $0.023/GB |
| CloudWatch Logs | $0.50/GB ingested |

## References

- **Homepage:** https://aws.amazon.com/cloudtrail/
- **Documentation:** https://docs.aws.amazon.com/cloudtrail/
- **Pricing:** https://aws.amazon.com/cloudtrail/pricing/

## Pricing Examples

**Scenario 1:** A medium account (100 users, moderate activity). Management events: free. Data events disabled. 1GB CloudTrail logs/month × $0.023 = $0.023/month. Plus CloudWatch ($0.50/GB = $0.50/month). Total: ~$0.50/month.

**Scenario 2:** An active account with S3 data events enabled. 10M PUT requests/day × 30 = 300M S3 PUT events/month. Data events: 300M × $0.10/100K = $300/month. That's expensive. Recommendation: disable S3 data events for all buckets, enable only for critical buckets.

**Scenario 3:** A compliance account requiring 7-year log retention. 10GB/month × 12 months × 7 years = 840GB S3 storage. With S3 Glacier Instant Retrieval: 840GB × $0.004/GB = $3.36/month. Plus S3 storage cost for hot data (30 days): 10GB × $0.023 = $0.23/month. Total: ~$3.60/month.

## Nuggets & Gotchas

- **CloudTrail doesn't log read operations by default (GetObject, Describe*) — enable data events:** Management events are free and cover control plane (who created/deleted resources). For data plane operations (who accessed what data), you need data events at $0.10/100K (S3) or disable them.
- **CloudTrail log files are delivered every 5 minutes — not real-time:** If you need immediate alerting (e.g., someone deleting a bucket), use CloudWatch integration with a 1-minute filter. CloudTrail delivers to S3 every 5 minutes.
- **S3 data events generate 2 events per object operation (List and Get/Put):** A single `aws s3 cp file.txt s3://bucket/` generates 2 CloudTrail events. For heavy S3 use, this multiplies costs fast.
- **CloudTrail log validation (hash chain) detects deletion but not modification:** File validation uses a hash chain to prove integrity. If someone deletes a log file, validation fails. If someone modifies a log file, the hash won't match. But the hash is stored in a separate file.
- **CloudTrail Insights costs extra ($0.10/100K) — it auto-detects unusual API patterns:** If you don't need automated anomaly detection, skip Insights. It's useful for security but adds cost. Monitor your CloudTrail costs and enable selectively.
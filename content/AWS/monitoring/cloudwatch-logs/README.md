---
title: CloudWatch Logs
description: CloudWatch Logs — centralized log management for applications and AWS services. Log groups, streams, the CloudWatch Agent, retention policies, and subscription filters.
tags:
  - aws
  - monitoring
  - logs
  - cloudwatch
---

# CloudWatch Logs

CloudWatch Logs provides a centralized repository for application and infrastructure logs. It ingests logs from EC2 instances, Lambda, ECS, on-premises servers, and any application via the SDK or syslog.

## Core Concepts

### Log Groups

A log group is a container for log streams. You define a log group and then create log streams within it.

```
Log Group: /aws/lambda/my-function
  ├── Log Stream: 2024/01/15/[$LATEST]abc123
  └── Log Stream: 2024/01/15/[$LATEST]def456

Log Group: /var/app/myapp
  ├── Log Stream: i-xxxxx
  └── Log Stream: i-yyyyy
```

### Log Streams

A log stream is a sequence of log events from a specific source (an EC2 instance, a Lambda function, a container).

### Log Events

```
Timestamp: 2024-01-15T10:30:00.000Z
Message: ERROR: Connection refused to database
IngestionTime: 2024-01-15T10:30:00.123Z
SequenceToken: 495623726896828886...
```

### Retention Policy

Control how long logs are kept:

| Retention | Cost Implication |
|-----------|-----------------|
| 1 day | Lowest storage cost |
| 30 days | Common for most applications |
| 90 days | For compliance requirements |
| 1 year | Long-term retention |
| Forever | Most expensive |

```bash
aws logs put-retention-policy \
  --log-group-name /var/app/myapp \
  --retention-in-days 30
```

## CloudWatch Agent

The CloudWatch Agent collects logs and metrics from EC2 instances and on-premises servers.

### Installation

```bash
# Linux
sudo yum install -y amazon-cloudwatch-agent
# or
curl -O https://amazoncloudwatch-agent.s3.amazonaws.com/amazon-cloudwatch-agent.rpm
sudo rpm -i ./amazon-cloudwatch-agent.rpm
```

### Configuration (agent.json)

```json
{
  "agent": {
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app.log",
            "log_group_name": "/var/app/myapp",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/var/nginx/access",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%d/%b/%Y:%H:%M:%S"
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      }
    }
  }
}
```

### Starting the Agent

```bash
# Start
sudo systemctl start amazon-cloudwatch-agent

# Status
sudo systemctl status amazon-cloudwatch-agent

# Configuration wizard
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard
```

## Subscription Filters

Subscription filters route log events to other AWS services in real-time:

```
Log Group → Subscription Filter → Kinesis Data Firehose → S3
Log Group → Subscription Filter → Lambda (for processing)
Log Group → Subscription Filter → Kinesis Data Analytics
```

### Real-Time Log Streaming to S3

```bash
# Create a Kinesis Data Firehose delivery stream first
aws firehose create-delivery-stream \
  --delivery-stream-name my-log-stream \
  --s3-destination-configuration ...

# Create subscription filter
aws logs put-subscription-filter \
  --log-group-name /var/app/myapp \
  --filter-name "to-s3" \
  --filter-pattern "" \
  --destination-arn arn:aws:firehose:us-east-1:123456789012:deliverystream/my-log-stream
```

### Real-Time Log Processing with Lambda

```bash
aws logs put-subscription-filter \
  --log-group-name /aws/lambda/my-function \
  --filter-name "process-logs" \
  --filter-pattern "ERROR" \
  --destination-arn arn:aws:lambda:us-east-1:123456789012:function:process-logs
```

## Cross-Account Log Streaming

Send logs from member accounts to a central log account:

```
Member Account (Prod VPC)
  → CloudWatch Logs
    → Subscription Filter (cross-account)
      → Central Log Account (Security VPC)
        → Log Group in Security Account

Configuration: Use an IAM role in the destination account
```

```bash
# In the destination account (centralized logging)
aws logs create-log-group --log-group-name /aws/prod/myapp

# In the source account (producer)
aws logs put-subscription-filter \
  --log-group-name /var/app/myapp \
  --destination-arn arn:aws:logs:us-east-1:111122223333:目的地 \
  --filter-pattern "" \
  --distribution-field aws:AccountId
```

## Live Tail

CloudWatch Logs Live Tail provides real-time streaming of log events in the Console (near real-time, not programmatic). Useful for debugging in production without running `tail -f` on an EC2 instance.

## Integrating with Other AWS Services

| Service | How It Integrates with Logs |
|---------|----------------------------|
| Lambda | Lambda automatically logs to /aws/lambda/{function-name} |
| ECS | Container logs via awslogs driver |
| EC2 | CloudWatch Agent (syslog, application logs) |
| VPC Flow Logs | Export to CloudWatch Logs |
| CloudTrail | CloudTrail logs written to CloudWatch Logs |
| RDS | Export logs to CloudWatch (MySQL, PostgreSQL, Aurora) |
| API Gateway | Access logs and execution logs |

### ECS Container Logging

```json
{
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/myapp",
      "awslogs-region": "us-east-1",
      "awslogs-stream-prefix": "ecs"
    }
  }
}
```

## Limits

| Resource | Limit |
|----------|-------|
| Log groups per account | 10,000 |
| Log streams per log group | Unlimited (performance degrades above 50,000) |
| Log events per PutLogEvents call | 1MB (max 10,000 events) |
| Log event size | 256KB (max 26,000 bytes per log event) |
| Retention policy range | 1 day to 10 years |
| Subscription filters per log group | 3 (can request increase) |

## References

- **Homepage:** https://aws.amazon.com/cloudwatch/
- **Documentation:** https://docs.aws.amazon.com/cloudwatch/
- **Pricing:** https://aws.amazon.com/cloudwatch/pricing/

## Pricing Examples

**Scenario 1:** A production application generating 500MB/day of application logs. 500MB × 30 days = 15GB/month stored (30-day retention). Ingestion: 15GB × $0.50/GB = $7.50/month. Storage: 15GB × $0.03/GB/month = $0.45/month. Total: ~$8/month for log storage.

**Scenario 2:** A compliance requirement to retain logs for 7 years. 500MB/day × 365 days = 182.5GB/year. After 7 years: 1,277.5GB stored. Storage cost: 1,277.5GB × $0.03/GB/month × 84 months = $3,221/month. This is expensive — consider streaming to S3 Glacier for long-term retention at $0.004/GB/month = $5/month instead.

## Nuggets & Gotchas

- **Log ingestion has a ~10-second delay — not real-time:** CloudWatch Logs has a latency of 5-15 seconds from when a log event is produced to when it's searchable. For real-time alerting (sub-second), you need a different approach (Lambda + CloudWatch Contributor Insights or a third-party tool).
- **The 3 subscription filter limit per log group is a hard limit:** If you need more than 3 destinations from a single log group, you must create multiple log groups (fan-out pattern) or request a limit increase from AWS.
- **CloudWatch Agent logs can silently fail if permissions are wrong:** If the IAM role attached to the EC2 instance doesn't have `logs:CreateLogGroup` and `logs:PutLogEvents`, the agent logs to its own local file (`/opt/aws/amazon-cloudwatch-agent/logs/`) but nothing appears in CloudWatch. Check the agent log file when debugging.
- **PutLogEvents has a 1MB batch limit and 10,000 events per call:** For high-volume log producers (100K+ events/minute), you must batch correctly. The CloudWatch Agent handles this automatically, but if you're using the SDK directly, you must implement batching.
- **Log group names with special characters (like forward slashes) create confusing Console navigation:** `/aws/lambda/my-function` shows under "AWS" in the Console. `/var/app/myapp` shows under "/var". This is cosmetic but can confuse team members navigating logs.
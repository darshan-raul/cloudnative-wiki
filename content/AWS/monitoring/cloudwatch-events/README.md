---
title: CloudWatch Events
description: CloudWatch Events (EventBridge) — event-driven automation using rules that react to AWS API events, schedules, or custom application events. Rules, targets, and event patterns.
tags:
  - aws
  - monitoring
  - events
  - cloudwatch
---

# CloudWatch Events

CloudWatch Events (now unified under EventBridge) routes events from AWS services, applications, and schedules to targets for automation.

## Core Concepts

### Event Types

| Event Type | Source | Example |
|-----------|--------|---------|
| AWS API events | AWS services | `aws.ec2.describeinstances` |
| Schedule events | EventBridge scheduler | Every 5 minutes |
| Custom events | Your application | Application-level events |
| Security events | AWS services | `aws.cloudtrail` |

### Event Structure

```json
{
  "version": "0",
  "id": "6b57e5e1-xxxx-xxxx-xxxx-xxxx",
  "detail-type": "EC2 Instance State Change",
  "source": "aws.ec2",
  "account": "123456789012",
  "time": "2024-01-15T10:30:00Z",
  "region": "us-east-1",
  "detail": {
    "instance-id": "i-xxxxx",
    "state": "stopped"
  }
}
```

### Event Pattern vs Schedule

**Event Pattern:** Trigger when something happens (EC2 instance stops, S3 bucket created)

**Schedule:** Trigger on a cron-like schedule (every 5 minutes, every day at 2am)

## Event Rules

### Creating an Event Pattern Rule

```bash
aws events put-rule \
  --name ec2-stopped-alert \
  --event-pattern '{
    "source": ["aws.ec2"],
    "detail-type": ["EC2 Instance State Change"],
    "detail": {"state": ["stopped"]}
  }' \
  --targets '[{"Arn": "arn:aws:sns:us-east-1:123456789012:my-alert","Id":"sns"}]'
```

### Creating a Schedule Rule

```bash
aws events put-rule \
  --name every-5-minutes \
  --schedule-expression "rate(5 minutes)" \
  --targets '[{"Arn": "arn:aws:lambda:us-east-1:123456789012:function:my-function","Id":"lambda"}]'
```

### Schedule Expressions

| Expression | Meaning |
|-----------|---------|
| `rate(5 minutes)` | Every 5 minutes |
| `rate(1 hour)` | Every hour |
| `rate(1 day)` | Every day |
| `cron(0 10 * * ? *)` | Every day at 10:00 UTC |
| `cron(0/15 * * * ? *)` | Every 15 minutes |

## Targets

| Target | Use |
|--------|-----|
| Lambda function | Run serverless code |
| SNS topic | Send notifications |
| SQS queue | Enqueue for processing |
| ECS task | Run ECS task |
| Step Functions | Start a state machine |
| Kinesis stream | Fan-out to stream |
| API Gateway | Trigger REST endpoint |
| EventBridge event bus | Forward to another account/bus |
| SSM Run Command | Run command on managed instances |

## Common Patterns

### EC2 State Change Alert

```bash
aws events put-rule \
  --name ec2-state-alerts \
  --event-pattern '{
    "source": ["aws.ec2"],
    "detail-type": ["EC2 Instance State Change"],
    "detail": {
      "state": ["stopping", "stopped", "terminated"],
      "previous-state": ["running"]
    }
  }' \
  --targets '[{"Arn":"arn:aws:sns:us-east-1:123456789012:alerts","Id":"sns"}]'
```

### S3 Object Created Trigger

```bash
aws events put-rule \
  --name s3-upload-trigger \
  --event-pattern '{
    "source": ["aws.s3"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventSource": ["s3.amazonaws.com"],
      "eventName": ["PutObject", "CopyObject"],
      "requestParameters": {
        "bucketName": ["my-upload-bucket"]
      }
    }
  }' \
  --targets '[{"Arn":"arn:aws:lambda:us-east-1:123456789012:function:process-upload","Id":"lambda"}]'
```

### Scheduled Database Maintenance

```bash
aws events put-rule \
  --name nightly-db-cleanup \
  --schedule-expression "cron(0 3 * * ? *)" \
  --targets '[{"Arn":"arn:aws:ecs:us-east-1:123456789012:cluster/my-cluster","Id":"ecs","RoleArn":"arn:aws:iam::123456789012:role/ecs-events-role"}]'
```

## Event Bus

Each AWS account has a **default event bus** for events from AWS services. You can create **custom event buses** for your applications or partner event buses for SaaS integration.

### Event Bus Types

| Type | Use |
|------|-----|
| Default | AWS service events |
| Custom | Your application events |
| Partner | Third-party SaaS events (Datadog, Zendesk, etc.) |

### Cross-Account Events

```bash
# Account A (source) — put events to Account B's event bus
aws events put-events \
  --entries '[{"DetailType":"my-event","Source":"my.app","Detail":"{\"key\":\"value\"}","EventBusName":"arn:aws:events:us-east-1:444455556666:event-bus/default"}]'
```

## EventBridge Schema Registry

EventBridge can discover and register event schemas:

```bash
# Discover schema
aws events list-schemas

# Generate code binding for a schema
aws events get-schema \
  --registry-name my-registry \
  --schema-name my-event-schema
```

## Dead Letter Queue (DLQ)

When a target fails to process an event, EventBridge can send it to a DLQ:

```bash
aws events put-rule \
  --name my-rule \
  --event-pattern '...' \
  --targets '[{
    "Arn": "arn:aws:lambda:us-east-1:123456789012:function:my-function",
    "Id": "lambda-target",
    "DeadLetterConfig": {
      "Arn": "arn:aws:sqs:us-east-1:123456789012:my-dlq"
    }
  }]'
```

## Limits

| Resource | Limit |
|----------|-------|
| Rules per event bus | 100 |
| Targets per rule | 5 |
| Events per second (default) | Variable by target |
| Event size | 256KB |

## References

- **Homepage:** https://aws.amazon.com/eventbridge/
- **Documentation:** https://docs.aws.amazon.com/eventbridge/
- **Pricing:** https://aws.amazon.com/eventbridge/pricing/

## Pricing Examples

**Scenario 1:** An automated backup system that triggers a Lambda function every hour to back up a database. 24 events/day × 30 = 720 events/month. EventBridge free tier: 1M events/month free. Total: $0/month.

**Scenario 2:** An enterprise processing 1M events/day from AWS services (EC2 state changes, S3 operations, IAM events). 30M events/month. EventBridge beyond free tier: $1.00/million events = $29/million... actually: $0.08/million events (ingestion) + $0.02/million events (processed). 30M events = $3.00/month. Very affordable for enterprise automation.

## Nuggets & Gotchas

- **EventBridge is the evolution of CloudWatch Events — the API is the same:** The `aws events` CLI commands are now EventBridge commands. The service is called EventBridge, but the API namespace is still `aws.events`. This is confusing but consistent.
- **The 5-target limit per rule is a hard limit — use a Lambda fan-out for more:** If you need to trigger more than 5 targets from one event, write a Lambda function that reads the event and calls the other targets. Or use Step Functions for complex workflows.
- **EventBridge can't trigger cross-region Lambda functions by default:** A rule in us-east-1 can only trigger Lambda in us-east-1. For cross-region automation, use EventBridge in the target region or trigger a Lambda that calls the other region's resources.
- **Schedule expressions use UTC — always specify timezone:** `cron(0 10 * * ? *)` means 10:00 UTC, not 10:00 local time. If your team is in New York (EST), 10:00 UTC is 5:00 AM EST. Use `cron(0 15 * * ? *)` for 10:00 EST.
- **Dead letter queue is per target, not per rule:** If a rule has 3 targets and one fails, only that target's events go to the DLQ. The other 2 targets continue to receive events. This is the correct behavior but can be confusing when debugging.
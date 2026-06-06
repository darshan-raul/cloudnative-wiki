---
title: Amazon SNS
description: Amazon SNS — pub/sub messaging and mobile notifications. Topics, subscriptions, fan-out patterns, mobile push, SMS, email, and filtering.
tags:
  - aws
  - application-integration
  - sns
  - pub-sub
  - notifications
---

# Amazon SNS

SNS is a pub/sub messaging service. Publishers send messages to a topic; all subscribers to that topic receive the message. Supports multiple protocols: SQS, Lambda, HTTP, email, SMS, mobile push.

## Core Concepts

```
Publisher ──► Topic ──┬──► SQS Queue ──► Consumer
                      ├──► Lambda ────► Processing
                      ├──► HTTP/HTTPS ──► Webhook
                      ├──► Email ───────► Inbox
                      ├──► SMS ─────────► Phone
                      └──► Mobile Push ──► App
```

## Creating a Topic

```bash
# Standard topic
aws sns create-topic --name my-topic

# FIFO topic
aws sns create-topic \
  --name my-topic.fifo \
  --attributes '{"FifoTopic": "true", "ContentBasedDeduplication": "true"}'

# Get topic ARN
TOPIC_ARN=$(aws sns create-topic --name my-topic --query TopicArn --output text)
echo $TOPIC_ARN
# arn:aws:sns:us-east-1:123456789012:my-topic
```

## Subscriptions

```bash
# Subscribe an SQS queue
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789012:my-topic \
  --protocol sqs \
  --notification-endpoint arn:aws:sqs:us-east-1:123456789012:my-queue

# Subscribe a Lambda
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789012:my-topic \
  --protocol lambda \
  --notification-endpoint arn:aws:lambda:us-east-1:123456789012:function:my-function

# Subscribe an HTTP endpoint
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789012:my-topic \
  --protocol https \
  --notification-endpoint https://my-api.example.com/webhook

# Subscribe with email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789012:my-topic \
  --protocol email \
  --notification-endpoint ops@example.com
```

## Publishing Messages

```python
import boto3
import json

sns = boto3.client('sns')
topic_arn = 'arn:aws:sns:us-east-1:123456789012:my-topic'

# Publish simple message
response = sns.publish(
    TopicArn=topic_arn,
    Message='Hello from SNS!',
    Subject='Alert'
)
print(f"MessageId: {response['MessageId']}")

# Publish with attributes (for filtering)
response = sns.publish(
    TopicArn=topic_arn,
    Message=json.dumps({'order_id': '12345', 'status': 'shipped'}),
    MessageAttributes={
        'severity': {'DataType': 'String', 'StringValue': 'high'},
        'region': {'DataType': 'String', 'StringValue': 'us-east-1'}
    }
)

# Publish to specific endpoint (no topic)
response = sns.publish(
    TopicArn=topic_arn,
    Message='Urgent alert',
    TargetArn='arn:aws:sns:us-east-1:123456789012:my-topic:subscription-id'
)
```

## Message Filtering

### Configure on Subscription

```python
# Subscribe with filter policy
sns.subscribe(
    TopicArn=topic_arn,
    Protocol='lambda',
    Endpoint='arn:aws:lambda:us-east-1:123456789012:function:my-function',
    ReturnSubscriptionArn=True,
    Attributes={
        'FilterPolicy': json.dumps({
            'severity': ['high', 'critical'],
            'region': ['us-east-1', 'us-west-2'],
            'event_type': [{'anything-but': 'test'}]  # anything-but
        })
    }
)
```

### Filter Policy Examples

```json
{
  "severity": ["high", "critical"],          // exact match in array
  "order_total": [{"numeric": [">=", 1000]}], // numeric comparison
  "category": [{"exists": true}],             // attribute must exist
  "event_type": [{"anything-but": "test"}],  // exclude value
  "status": ["pending", "processing"],        // match any in list
  "country": [{"prefix": "us-"}]              // prefix match
}
```

## Fan-out Pattern (SNS → Multiple SQS)

```
Orders Topic ──┬──► Shipping Queue ──► Shipping Lambda
               ├──► Billing Queue ──► Billing Lambda
               ├──► Analytics Queue ──► Analytics Lambda
               └──► Email Queue ──► Email Lambda
```

```python
# SNS subscription to multiple SQS queues
queues = ['shipping-queue', 'billing-queue', 'analytics-queue', 'email-queue']
for queue in queues:
    queue_arn = f'arn:aws:sqs:us-east-1:123456789012:{queue}'
    sns.subscribe(
        TopicArn=topic_arn,
        Protocol='sqs',
        Endpoint=queue_arn
    )
```

## Mobile Push Notifications

```python
# Publish to mobile platform (APNS, FCM, etc.)
response = sns.publish(
    TargetArn='arn:aws:sns:us-east-1:123456789012:endpoint/APNS/my-app/xxxxx',
    Message=json.dumps({
        'APNS': json.dumps({
            'aps': {'alert': 'You have a new order!', 'sound': 'default'}
        })
    })
)
```

## SMS

```python
# Publish SMS
response = sns.publish(
    PhoneNumber='+15551234567',
    Message='Your verification code is 123456.'
)

# Check SMS spend (in sandbox, must verify numbers)
sns.get_sms_attributes()
```

## Pricing

| Protocol | Cost |
|----------|------|
| Publish to topic | $0.50/million |
| SQS subscription | $0.00 (free) |
| Lambda subscription | $0.00 (free) |
| HTTP/HTTPS | $0.06/million |
| Email | $2.00/million |
| SMS (US) | $0.00645/message |
| Mobile push | $0.00 (AWS pays carrier fees) |

## Limits

| Resource | Limit |
|----------|-------|
| Topic name | 256 characters |
| Message size | 256KB |
| Subscription per topic | 12.5M (default) |
| Message attributes | 10 per message |
| Filter policy size | 256KB |

## References

- **Homepage:** https://aws.amazon.com/sns/
- **Documentation:** https://docs.aws.amazon.com/sns/
- **Pricing:** https://aws.amazon.com/sns/pricing/

## Pricing Examples

**Scenario 1:** An e-commerce platform publishing 10M order events/month to an SNS topic with 5 SQS queue subscribers. 10M publishes × $0.50/million = $5/month. Subscriptions are free. Total: $5/month.

**Scenario 2:** A notification system sending 100K SMS/month to customers. 100K × $0.00645 = $645/month. Consider using email instead (100K × $2.00/million = $0.20/month) or batching SMS messages.

## Nuggets & Gotchas

- **SNS does NOT retry failed deliveries to HTTP/HTTPS endpoints — only SQS and Lambda get automatic retries:** If your HTTP endpoint returns non-2xx, SNS marks it as failed and does NOT retry. Use CloudWatch alarms to detect failed deliveries. For Lambda/HTTPS, use EventBridge as the dead-letter destination.
- **SNS SMS has a SPENDING LIMIT ($1/day by default) — you'll get blocked if you exceed it:** In sandbox mode, SMS is capped at $1/day. Request production access to increase the limit. Monitor spend with CloudWatch and SNS attributes.
- **SNS message filtering is evaluated at the SUBSCRIPTION level, not the topic level:** Each subscription can have its own filter policy. Messages not matching a subscription's filter are silently discarded (no error to publisher).
- **SNS FIFO topics have lower throughput than standard (300/s vs unlimited) — plan accordingly:** FIFO topics are limited to 300 messages/second per topic. For higher throughput, shard across multiple FIFO topics.
- **SNS doesn't guarantee delivery order to multiple subscribers — use SQS FIFO if ordering matters across subscribers:** If subscriber A and subscriber B both receive the same SNS message, the timing of their processing is not coordinated.
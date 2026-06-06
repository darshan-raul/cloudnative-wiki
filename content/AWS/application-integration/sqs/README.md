---
title: Amazon SQS
description: Amazon SQS — managed message queue. Standard and FIFO queues, dead-letter queues, visibility timeout, long/short polling, cost, and scaling patterns.
tags:
  - aws
  - application-integration
  - sqs
  - queue
  - messaging
---

# Amazon SQS

SQS is a fully managed message queue. Producers send messages to a queue; consumers poll for messages and process them. Messages are stored redundantly across multiple AZs.

## Standard vs FIFO

| Feature | Standard Queue | FIFO Queue |
|---------|--------------|------------|
| Throughput | Unlimited | 300 msg/s (batch: 3000/s) |
| Ordering | At-least-once, no guarantee | Exactly-once, strict order |
| Duplicates | May be delivered multiple times | Deduplicated (5-min window) |
| Price | $0.40/million requests | $0.50/million requests |
| Use case | High throughput, can tolerate duplicates | Financial transactions, strict order |

## Core Concepts

```
Producer                          Consumer
    │                                  │
    ├──► Message 1 ──────────────────►│ (Delete after processing)
    ├──► Message 2 ──────────────────►│
    ├──► Message 3 ──────────────────►│
    │                                  │
    └──► Dead Letter Queue (after maxReceiveCount)
```

## Creating a Queue

```bash
# Standard queue
aws sqs create-queue \
  --queue-name my-queue \
  --attributes '{
    "VisibilityTimeout": "30",
    "MessageRetentionPeriod": "345600",
    "MaximumMessageSize": "262144",
    "ReceiveMessageWaitTimeSeconds": "0"
  }'

# FIFO queue
aws sqs create-queue \
  --queue-name my-queue.fifo \
  --queue-name-attributes '{
    "FifoQueue": "true",
    "ContentBasedDeduplication": "true"
  }'
```

## Sending Messages

```python
import boto3
import json

sqs = boto3.client('sqs')
queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/my-queue'

# Send single message
response = sqs.send_message(
    QueueUrl=queue_url,
    MessageBody=json.dumps({'order_id': '12345', 'amount': 99.99}),
    MessageAttributes={
        'OrderType': {'StringValue': 'premium', 'DataType': 'String'}
    }
)
print(f"MessageId: {response['MessageId']}")

# Send batch (up to 10 messages)
response = sqs.send_message_batch(
    QueueUrl=queue_url,
    Entries=[
        {'Id': '1', 'MessageBody': json.dumps({'item': 'a'})},
        {'Id': '2', 'MessageBody': json.dumps({'item': 'b'})}
    ]
)
```

## Receiving and Processing

```python
# Receive messages
response = sqs.receive_message(
    QueueUrl=queue_url,
    MaxNumberOfMessages=10,
    VisibilityTimeout=30,
    WaitTimeSeconds=20  # Long polling
)

for msg in response.get('Messages', []):
    receipt = msg['ReceiptHandle']
    body = json.loads(msg['Body'])
    
    # Process the message
    print(f"Processing: {body}")
    
    # Delete after successful processing
    sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt)
```

## Dead Letter Queue (DLQ)

```bash
# Create DLQ first
DLQ_URL=$(aws sqs create-queue --queue-name my-dlq --query QueueUrl --output text)

# Create main queue with DLQ
aws sqs create-queue \
  --queue-name my-queue \
  --attributes '{
    "RedrivePolicy": "{\"deadLetterTargetArn\": \"arn:aws:sqs:us-east-1:123456789012:my-dlq\",\"maxReceiveCount\": 3}"
  }'
```

## Visibility Timeout

```
Time ──────────────────────────────────────────────────────►

t=0  Message delivered to Consumer A
     Visibility timeout = 30 seconds
     │
     │  If Consumer A crashes at t=25s (before delete):
     │  Message becomes visible again at t=30s
     │  Another consumer can pick it up
     │
t=30 Message visible again (if not deleted)
     Visibility timeout resets (30 more seconds)
     │
t=60 Message visible again (if not deleted)
     ... up to maxReceiveCount, then DLQ
```

## Lambda Integration (Event Source Mapping)

```python
# SQS trigger Lambda (event source mapping)
import json

def handler(event, context):
    for record in event['Records']:
        body = json.loads(record['body'])
        print(f"Processing message: {body}")
        
        # Lambda automatically deletes the message after successful execution
        # If Lambda throws an error, the message becomes visible again
```

### Lambda Event Source Mapping (via CLI)

```bash
# Create event source mapping
aws lambda create-event-source-mapping \
  --function-name my-function \
  --event-source-arn arn:aws:sqs:us-east-1:123456789012:my-queue \
  --batch-size 10 \
  --maximum-batching-window-in-seconds 10 \
  --maximum-concurrency 5
```

## Cost Optimization

| Strategy | Savings |
|----------|---------|
| Long polling (WaitTimeSeconds=20) | Reduces API calls, improves efficiency |
| Batch operations (SendMessageBatch, DeleteMessageBatch) | 10x fewer API calls |
| Reduce VisibilityTimeout | Match to your processing time |
| Short polling only when needed | Avoid empty receive_message calls |

## Pricing

| Component | Cost |
|-----------|------|
| Standard queue | $0.40/million requests |
| FIFO queue | $0.50/million requests |
| FIFO (batching) | $0.017/million messages (after 1M) |
| Data transfer (same region) | Free |
| Data transfer (cross-region) | $0.02-0.09/GB |

## Limits

| Resource | Limit |
|----------|-------|
| Message size | 256KB (max 2GB with S3 extended client library) |
| Queue retention | 1 minute to 14 days |
| In-flight messages | 120,000 (standard), 20,000 (FIFO) |
| Max messages per ReceiveMessage | 10 |

## References

- **Homepage:** https://aws.amazon.com/sqs/
- **Documentation:** https://docs.aws.amazon.com/AWSSimpleQueueService/
- **Pricing:** https://aws.amazon.com/sqs/pricing/

## Pricing Examples

**Scenario 1:** An e-commerce checkout processing 1M orders/month. Each order triggers 1 SQS message. 1M requests × $0.40/million = $0.40/month. Plus Lambda invocations (~$0.20/month). Total: ~$0.60/month for message queuing.

**Scenario 2:** A high-throughput image processing pipeline with 50M messages/day. 50M/day × 30 = 1.5B/month. Using batch operations (10 messages/batch), that's 150M API calls. $0.40 × 150 = $60/month. Switching to FIFO with batching: $0.50 × 150 = $75/month.

## Nuggets & Gotchas

- **SQS does NOT delete messages after ReceiveMessage — you MUST call DeleteMessage yourself:** The message stays invisible for the VisibilityTimeout period, then reappears if not deleted. For Lambda, the SDK handles this automatically. For manual polling, you MUST call delete_message after successful processing.
- **SQS long polling (WaitTimeSeconds > 0) can delay empty responses up to that wait time:** If you call receive_message with WaitTimeSeconds=20 and the queue is empty, the call blocks for up to 20 seconds. Design your consumer loops accordingly.
- **SQS message size is 256KB hard limit — for larger payloads, store in S3 and send S3 reference:** Use the SQS extended client library which automatically stores large payloads in S3 and sends the reference in SQS.
- **SQS FIFO ordering is per message group ID — messages with different group IDs can be delivered out of order:** If you need global ordering, use a single group ID. For partial ordering (per customer), use customer ID as group ID.
- **SQS visibility timeout doesn't pause while your consumer is idle — it counts down from the moment the message is received:** If your VisibilityTimeout is 30s and you spend 25s on processing before calling delete, you only have 5s left. Set it to 2-3x your expected processing time.
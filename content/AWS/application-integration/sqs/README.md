---
title: Amazon SQS
description: Amazon SQS — managed message queue. Standard and FIFO queues, dead-letter queues, visibility timeout, long/short polling, cost, and scaling patterns.
tags:
  - aws/application-integration
date: 2026-10-12
---

# Amazon SQS

Prerequisites: [[AWS/security/iam/README|scoped IAM roles]] and [[AWS/monitoring/README|delivery/processing observability]].

SQS is a durable queue, not a broadcast bus. Consumers receive messages, complete work and delete them using a receipt handle; an unacknowledged message becomes visible again.

## Semantics and quotas

Standard queues provide at-least-once delivery and best-effort ordering. FIFO queues order messages within a MessageGroupId and deduplicate sends within the documented interval. Neither removes the need for transactional or idempotent business processing.

Maximum message size is 1 MiB. SNS fan-out retains SNS's own smaller payload limit; larger payloads can be stored separately with an authorized object reference. FIFO throughput depends on mode, batching, Region, partitions and distribution across groups; 300/3,000 is not a universal account ceiling.

Set visibility timeout longer than processing time, extend it for long work and acknowledge only after success. A DLQ redrive policy uses a queue ARN and maxReceiveCount; monitor poison messages and authorize controlled redrive. Retention and FIFO group blocking matter during failure recovery.

## Complete queue lab

With scoped CreateQueue/GetQueueAttributes/SendMessage/ReceiveMessage/DeleteMessage/DeleteQueue permissions, create a disposable queue:

```bash
aws sqs create-queue --queue-name wiki-lab-work \
  --attributes VisibilityTimeout=30,ReceiveMessageWaitTimeSeconds=20
```

Save the returned QueueUrl as QUEUE_URL; substitute it in these requests:

```bash
aws sqs send-message --queue-url QUEUE_URL --message-body '{"eventId":"order-1","amount":10}'
aws sqs receive-message --queue-url QUEUE_URL --max-number-of-messages 1 --wait-time-seconds 20
```

Expected: the JSON body and a ReceiptHandle. Do not delete the first receive; after visibility expiry receive it again and demonstrate why eventId must prevent a second charge. Finally acknowledge using the most recent handle:

```bash
aws sqs delete-message --queue-url QUEUE_URL --receipt-handle RECEIPT_HANDLE
aws sqs delete-queue --queue-url QUEUE_URL
```

Deletion is irreversible; only delete your disposable queue after recording the test. If receiving returns nothing, check visibility, delay, Region and queue URL before treating the message as lost.

## Lambda integration

A [[AWS/serverless/lambda/README|Lambda]] event-source mapping polls the queue. Configure partial batch responses (ReportBatchItemFailures) and return failed message identifiers; throwing an exception fails the whole batch. FIFO consumers must preserve ordering when reporting failures.

Mapping maximum concurrency uses `--scaling-config MaximumConcurrency=5` on the applicable mapping command, not a top-level --maximum-concurrency flag. It is distinct from function reserved concurrency; insufficient function capacity causes throttling/retries. Standard and FIFO batch/window contracts differ.

## Costs

Count sends, receives, deletes, empty polls, request-size billing and optional KMS/object-storage charges. Batching reduces API request count; it does not invent a special FIFO unit tariff.

## Standard versus FIFO and the processing timeline

| Concern             | Standard                           | FIFO                                                       |
| ------------------- | ---------------------------------- | ---------------------------------------------------------- |
| Ordering            | Best effort                        | Ordered within a message group                             |
| Producer duplicates | At-least-once model                | Deduplication interval/ID rules                            |
| Consumer retries    | Visibility timeout can redeliver   | Visibility timeout can also redeliver                      |
| Parallelism         | Many consumers                     | Different groups run independently; a blocked group stalls |
| Throughput sizing   | Applied quotas/downstream capacity | Mode, Region, partition/group distribution and batching    |

```text
send → queue → receive (invisible) → durable processing → delete
                         └─ worker crashes/timeout → visible again
retry budget exhausted → DLQ → inspect/fix → authorized redrive
```

## FIFO and batch API walkthrough

Create a separate disposable FIFO queue; the .fifo suffix and FifoQueue attribute are both required.

```bash
aws sqs create-queue --queue-name wiki-lab-orders.fifo \
  --attributes FifoQueue=true,ContentBasedDeduplication=false
aws sqs send-message --queue-url FIFO_QUEUE_URL \
  --message-body '{"eventId":"order-7","action":"reserve"}' \
  --message-group-id customer-7 --message-deduplication-id order-7
```

Repeat the identical deduplication ID within its documented interval and compare enqueue behavior. Then receive without deleting and observe visibility expiry: consumer idempotency is still necessary. Distinct groups permit concurrency but cannot preserve one global order.

SendMessageBatch/ReceiveMessage/DeleteMessageBatch have separate contracts. A successful batch transport can contain failed entries; handle each result. Always delete with the latest receipt handle. Long polling reduces empty requests; batching and message-size chunks change billed requests.

## DLQ configuration walkthrough

Create a standard DLQ for a standard main queue (FIFO for FIFO). Get its QueueArn. Save this complete attribute request with substituted URLs/ARNs:

```json
{
  "QueueUrl": "MAIN_QUEUE_URL",
  "Attributes": {
    "RedrivePolicy": "{\"deadLetterTargetArn\":\"DLQ_ARN\",\"maxReceiveCount\":\"5\"}"
  }
}
```

```bash
aws sqs set-queue-attributes --cli-input-json file://redrive.json
aws sqs change-message-visibility --queue-url MAIN_QUEUE_URL \
  --receipt-handle RECEIPT_HANDLE --visibility-timeout 60
```

A visibility extension is per receipt, not permanent queue configuration. For Standard DLQs, set retention sufficiently longer than source retention; source enqueue time matters for expiry. Restrict redrive permission/allow policy and use bounded replay, preserving the event ID.

## Lambda handler walkthrough

This standard-queue fixture validates messages and reports individual failures; it intentionally performs no external side effect.

```python
import json

def handler(event, context):
    failures = []
    for record in event["Records"]:
        try:
            body = json.loads(record["body"])
            if not isinstance(body, dict) or not isinstance(body.get("eventId"), str):
                raise ValueError("eventId required")
        except (ValueError, TypeError):
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
```

Exercise the handler locally with a mixed batch; valid JSON is not necessarily an object. The malformed JSON and non-object JSON records must be reported individually, while the valid object must not be retried:

```python
fixture = {"Records": [
    {"messageId": "good", "body": '{"eventId":"evt-1"}'},
    {"messageId": "bad-json", "body": '{'},
    {"messageId": "list", "body": '[]'},
    {"messageId": "null", "body": 'null'},
    {"messageId": "number", "body": '42'},
    {"messageId": "string", "body": '"evt-2"'},
    {"messageId": "missing-id", "body": '{}'},
    {"messageId": "wrong-id", "body": '{"eventId":42}'}
]}
expected_ids = ["bad-json", "list", "null", "number", "string", "missing-id", "wrong-id"]
assert handler(fixture, None) == {
    "batchItemFailures": [{"itemIdentifier": item_id} for item_id in expected_ids]
}
```

This fixture checks local validation only, not AWS polling, deployment or side effects. An exception escaping the handler fails the whole batch, even when partial responses are configured. Production processing must contain intended per-record failures and implement idempotency; do not silently acknowledge a failed external effect.

Enable ReportBatchItemFailures on the mapping; otherwise the response does not enable partial failure behavior. For FIFO, stop after the first failed message and report unprocessed records to preserve ordering. Replace validation with a transactional idempotency/effect implementation before using this as a worker.

Monitor AWS/SQS ApproximateAgeOfOldestMessage, visible/not-visible counts and DLQ depth; approximate values are not an exact ledger. Rising age with stable arrivals suggests consumer capacity/errors; high in-flight counts suggest slow work/visibility settings. During cleanup remove the mapping, main queue and separately owned DLQ only after preserving required failures.

References: [DLQs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html), [batch APIs](https://docs.aws.amazon.com/cli/latest/reference/sqs/send-message-batch.html), [partial responses](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html).

## Cross-wiki comparisons

- [[Azure/messaging/service-bus/README|Azure Service Bus Architecture, Queues, Topics, and Enterprise Messaging]] — messaging and streaming (Azure)
- [[Azure/messaging/event-hubs/README|Azure Event Hubs Architecture, Kafka Compatibility, and Streaming Ingestion]] — messaging and streaming (Azure)

## References

- [Message quotas](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-messages.html)
- [Visibility timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html)
- [Lambda scaling](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-scaling.html)
- [Pricing](https://aws.amazon.com/sqs/pricing/)

## Across the wiki

- [[GCP/analytics/pubsub/README|Cloud Pub/Sub Architecture & Streaming Mechanics]]
- [[Architecture/solution-architecture-concepts/event-driven-architecture/kafka/README|Apache Kafka]]

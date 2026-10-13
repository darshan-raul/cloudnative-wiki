---
title: Amazon SNS
description: Amazon SNS — pub/sub messaging and mobile notifications. Topics, subscriptions, fan-out patterns, mobile push, SMS, email, and filtering.
tags:
  - aws/application-integration
date: 2026-10-12
---

# Amazon SNS

Prerequisites: [[AWS/security/iam/README|scoped IAM roles]] and [[AWS/monitoring/README|delivery/processing observability]].

SNS publishes messages to subscriptions. Use SNS plus SQS when subscribers need independent buffering; topic acceptance alone is not proof that every subscriber processed an event.

## Delivery, filtering and security

Standard topics support multiple destination protocols. FIFO topics provide ordered/deduplicated delivery to supported subscribers, with documented throughput scope; downstream processing still needs idempotency. SNS's 256-KiB payload ceiling is distinct from SQS's 1-MiB maximum.

HTTP/S delivery retries retryable failures such as throttling/server errors according to delivery policy; other protocols have their own policies. Configure subscription DLQs and delivery-status logging where supported. Distinguish a publish API failure from exhausted endpoint delivery.

Topic policies authorize publishing/subscription; queue policies authorize delivery. For SNS-to-SQS, restrict the queue's SQS SendMessage resource-policy principal to sns.amazonaws.com and condition aws:SourceArn to the specific topic. Encryption adds KMS authorization, not automatic cross-service access.

## Fan-out lab

Prerequisites: complete [[AWS/application-integration/sqs/README|the queue lab]] but retain the disposable queue, get its QueueArn, and have scoped SNS CreateTopic/Subscribe/Publish/DeleteTopic plus queue SetQueueAttributes permission.

```bash
aws sns create-topic --name wiki-lab-notifications
aws sqs get-queue-attributes --queue-url QUEUE_URL --attribute-names QueueArn
```

Record TOPIC_ARN and QUEUE_ARN. In the SQS access-policy editor apply this policy with the exact account/Region/resource values substituted:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "sns.amazonaws.com" },
      "Action": "sqs:SendMessage",
      "Resource": "QUEUE_ARN",
      "Condition": { "ArnEquals": { "aws:SourceArn": "TOPIC_ARN" } }
    }
  ]
}
```

This is valid JSON with illustrative ARN strings, not commented JSON. Then:

```bash
aws sns subscribe --topic-arn TOPIC_ARN --protocol sqs --notification-endpoint QUEUE_ARN
aws sns publish --topic-arn TOPIC_ARN --message '{"eventId":"notification-1"}'
aws sqs receive-message --queue-url QUEUE_URL --wait-time-seconds 20
```

Expected: an SNS envelope containing the message (unless raw delivery was enabled). Test a second topic without queue permission; no delivery is expected. Inspect publish and delivery evidence instead of widening the queue policy to everyone.

Delete your lab topic and queue after testing, including any independent DLQ.

## SMS, mobile push and pricing

SMS spending quotas are monthly, not daily; distributed enforcement can overshoot briefly. SMS sandbox, destination registration, origination identity and country/carrier rules are separate constraints. Mobile-push platform credentials and endpoint lifecycle differ from SMS subscriptions.

Price requests, destination-specific delivery, payload-size metering, SMS country rates and data transfer separately. Do not apply an SMS or mobile-push rate universally.

## Subscription protocols and independent failure paths

| Destination     | Setup/authorization                              | Recovery consideration                                                               |
| --------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------ |
| SQS             | Queue policy; KMS access if encrypted            | Queue retention, consumer retry and queue DLQ are separate from SNS subscription DLQ |
| Lambda          | Function resource policy                         | SNS delivery and Lambda processing have different failure stages                     |
| HTTP/S          | Reachable endpoint and subscription confirmation | Verify message signature; respond correctly; protocol-specific delivery retries      |
| Email           | Recipient confirmation                           | Human notification, not a transactional worker                                       |
| SMS/mobile push | Registration/platform endpoint workflow          | Destination credentials, carrier/platform outcome and operation-specific costs       |

```text
                       ┌─ billing queue → billing worker → its DLQ
Order publisher → SNS ├─ shipping queue → shipping worker → its DLQ
                       └─ notification endpoint → subscription DLQ
```

Do not treat publisher MessageId as evidence of all three business outcomes. Each subscriber needs a monitored owner and replay policy.

## Attribute and payload filtering

With an existing disposable topic/subscription, publish typed attributes:

```bash
aws sns publish --topic-arn TOPIC_ARN --message '{"eventId":"sale-1","tenant":"A"}' \
  --message-attributes '{"eventType":{"DataType":"String","StringValue":"sale"},"amount":{"DataType":"Number","StringValue":"120"}}'
aws sns set-subscription-attributes --subscription-arn SUBSCRIPTION_ARN \
  --attribute-name FilterPolicy --attribute-value '{"eventType":["sale"],"amount":[{"numeric":[">=",100]}]}'
```

The default filtering scope is message attributes. For JSON-body filtering set FilterPolicyScope to MessageBody and use a policy matching that body's fields, not the attribute schema. Allow documented propagation time before testing changes. Test matching/nonmatching events and inspect the recipient; a filtered event is not a delivery failure.

Raw SQS delivery removes the SNS envelope and changes attribute constraints. Choose it deliberately, document the consumer schema and test the actual event shape.

## FIFO, HTTP signatures and endpoint lifecycle

For FIFO publish, include MessageGroupId and the required deduplication ID/settings. Topic throughput scope and supported subscription types differ from Standard; use the owning FIFO contract rather than importing SQS throughput numbers.

For HTTP/S receivers use the documented signature validation, trusted certificate URL checks and subscription-confirmation workflow. Do not fetch an arbitrary SigningCertURL supplied by an untrusted caller. Return success only after safe acceptance; idempotent handling accommodates retry.

Mobile push distinguishes platform application credentials from device endpoints. Invalid tokens/platform feedback require endpoint lifecycle management. SMS requires consent, origination/registration and monthly spending controls, not merely a phone number.

## Worked request accounting and diagnosis

Suppose a workload makes 100,000 publish requests and fans out to two queues. Price publish metering and each applicable destination dimension separately, then add SQS send/receive/delete, KMS and transfer. A rate displayed per million requests must be multiplied by 0.1, not by 100,000 directly. Confirm payload chunking and current destination tariffs.

Check confirmation state, subscription filter/scope, topic policy, recipient policy, KMS and delivery-status evidence before retrying blindly. Preserve the exact MessageId/eventId and timestamps; never log SMS recipient data unnecessarily.

References: [filtering](https://docs.aws.amazon.com/sns/latest/dg/sns-message-filtering.html), [signature verification](https://docs.aws.amazon.com/sns/latest/dg/sns-verify-signature-of-message.html), [FIFO publishing](https://docs.aws.amazon.com/sns/latest/dg/fifo-message-grouping.html).

## Cross-wiki comparisons

- [[Azure/messaging/service-bus/README|Azure Service Bus Architecture, Queues, Topics, and Enterprise Messaging]] — messaging and streaming (Azure)
- [[Azure/messaging/event-hubs/README|Azure Event Hubs Architecture, Kafka Compatibility, and Streaming Ingestion]] — messaging and streaming (Azure)

## References

- [Retry policies](https://docs.aws.amazon.com/sns/latest/dg/sns-message-delivery-retries.html)
- [SNS-to-SQS authorization](https://docs.aws.amazon.com/sns/latest/dg/subscribe-sqs-queue-to-sns-topic.html)
- [Monthly SMS spend quota](https://docs.aws.amazon.com/sns/latest/dg/channels-sms-awssupport-spend-threshold.html)
- [Pricing](https://aws.amazon.com/sns/pricing/)

## Across the wiki

- [[GCP/analytics/pubsub/README|Cloud Pub/Sub Architecture & Streaming Mechanics]]
- [[Architecture/solution-architecture-concepts/event-driven-architecture/kafka/README|Apache Kafka]]

---
title: AWS Application Integration
description: AWS messaging and integration services — SQS (queues), SNS (pub/sub), EventBridge (event bus), Step Functions (workflows), Amazon MQ (ActiveMQ/RabbitMQ), AppSync (GraphQL).
tags:
  - aws/application-integration
date: 2026-10-12
---

# AWS Application Integration

Integration services separate producers from consumers and coordinate work. Choose by delivery semantics, protocol compatibility and failure recovery—not by a single feature checklist.

## Service selection

| Requirement                 | Lesson                                                                | Design question                                              |
| --------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------ |
| Buffered work queue         | [[AWS/application-integration/sqs/README\|SQS]]                       | Who owns retry, visibility and poison-message recovery?      |
| Publish/subscribe fan-out   | [[AWS/application-integration/sns/README\|SNS]]                       | Which subscribers need independent durable queues?           |
| Content-based event routing | [[AWS/application-integration/eventbridge/README\|EventBridge]]       | What schema, idempotency and replay guarantees are required? |
| Stateful orchestration      | [[AWS/application-integration/step-functions/README\|Step Functions]] | Which steps can safely retry and compensate?                 |
| GraphQL/realtime API        | [[AWS/application-integration/appsync/README\|AppSync]]               | Who may read each field and subscribe to each tenant?        |
| Existing broker protocol    | [[AWS/application-integration/amazon-mq/README\|Amazon MQ]]           | Which engine/version/client capabilities must be retained?   |

The default EventBridge bus accepts AWS service events and custom events. A custom bus is often a better ownership boundary. SNS retries transient delivery failures according to the destination protocol; durable queues and subscription DLQs address different failure stages.

FIFO ordering/deduplication does not make arbitrary downstream side effects exactly-once. Queue visibility expiry, consumer retries, redrive and event replay all require an application idempotency key. Standard Step Functions can run up to one year; Express is capped at five minutes, not a solution for longer executions.

## Learning exercise

Complete the SQS send/receive/delete lab, then wire SNS to that queue using a topic-scoped resource policy. Publish a message, stop consumption and inspect queue age. Resume consumption with an idempotent handler; fail one message deliberately and verify dead-letter handling. Record the retry owner at every hop.

For a multi-step workflow, implement a bounded timeout and compensation rather than an infinite retry. Use [[AWS/monitoring/README|monitoring]] to observe message age, failed delivery, workflow failures and consumer error rate. Create only sandbox resources and remove queues/topics/workflows after inspecting evidence.

## Production checklist

Define a versioned event envelope with event ID, type, source, occurred-at timestamp and schema version. Classify payload sensitivity, choose encryption and least-privilege policies, and design backpressure. Check payload/throughput quotas in the target Region, estimate send/receive/delete and empty-poll costs, and establish replay authorization and retention ownership.

## Choosing an integration pattern

```text
Producer
├─ Work must wait for a worker → SQS queue
├─ Each subscriber needs a copy → SNS → independent SQS queues
├─ Route by event content/owner → EventBridge bus → matching rules
├─ Coordinate steps/compensation → Step Functions
├─ Preserve broker/client protocols → MQ (verify engine compatibility)
└─ Client requests/subscriptions → AppSync (authorize fields and tenants)
```

| Property            | Queue                                    | Topic/bus                                        | Workflow                                        |
| ------------------- | ---------------------------------------- | ------------------------------------------------ | ----------------------------------------------- |
| Backpressure        | Buffer plus consumer capacity            | Target-dependent; often add queues               | Concurrency/step limits and downstream capacity |
| Failure unit        | Message/batch                            | Each target delivery                             | Task/state/execution                            |
| Recovery            | Visibility retry, DLQ and redrive        | Retry/DLQ and optionally archive replay          | Retry/Catch, compensation, human action         |
| Ordering            | Queue-mode/group scoped                  | Product/target scoped, not global                | Explicit state dependencies                     |
| Completion evidence | Durable side effect plus acknowledgement | Subscriber evidence, not publish acknowledgement | Business outcome, not only execution status     |

For an order, publish a versioned event ID only after the database transaction commits (consider an outbox). Fan out to invoicing and fulfillment queues so one slow consumer does not block the other. A charge operation stores its idempotency key with the effect, not just an in-memory processed list. Define who owns failed-event replay, how schemas evolve and how missing events are reconciled.

Troubleshoot in order: producer outcome → accepted envelope → matching subscription/rule → target policy/KMS → queue backlog/visibility → consumer effect. Use this request-path model instead of assuming exactly-once effects or unlimited throughput.

## References

- [AWS integration services](https://aws.amazon.com/products/application-integration/)
- [Workflow types](https://docs.aws.amazon.com/step-functions/latest/dg/choosing-workflow-type.html)
- [SNS retry behavior](https://docs.aws.amazon.com/sns/latest/dg/sns-message-delivery-retries.html)

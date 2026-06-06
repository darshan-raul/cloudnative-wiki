---
title: AWS Application Integration
description: AWS messaging and integration services — SQS (queues), SNS (pub/sub), EventBridge (event bus), Step Functions (workflows), Amazon MQ (ActiveMQ/RabbitMQ), AppSync (GraphQL).
tags:
  - aws
  - application-integration
---

# AWS Application Integration

These services connect applications and microservices through asynchronous messaging, event-driven architectures, and workflow orchestration.

## Service Map

| Service | Pattern | Use Case |
|---------|---------|----------|
| [[sqs/README\|SQS]] | Queue | Decouple producers/consumers, task queue |
| [[sns/README\|SNS]] | Pub/Sub | Fan-out to many subscribers |
| [[eventbridge/README\|EventBridge]] | Event Bus | Schema registry, rules, SaaS ingestion |
| [[step-functions/README\|Step Functions]] | Workflow | Multi-step orchestration, long-running processes |
| [[amazon-mq/README\|Amazon MQ]] | Broker | ActiveMQ/RabbitMQ migration, JMS, protocol support |
| [[appsync/README\|AppSync]] | GraphQL | Managed GraphQL API, real-time subscriptions |

## Choosing a Messaging Service

```
Need to send messages between services?
  │
  ├── One-to-one (point to point)
  │   └── SQS Queue — decouple, buffer, retry
  │
  ├── One-to-many (fan-out)
  │   ├── SNS Topic — push to many subscribers (SQS, HTTP, Lambda, etc.)
  │   └── EventBridge — rules-based routing, schema registry
  │
  ├── Event-driven (react to changes)
  │   └── EventBridge — rules, schedules, SaaS events
  │
  ├── Multi-step workflow
  │   └── Step Functions — state machines, human approval
  │
  └── Existing broker (migrating from ActiveMQ/RabbitMQ)
      └── Amazon MQ — managed ActiveMQ/RabbitMQ
```

## References

- **Homepage:** https://aws.amazon.com/products/application-integration/
- **Documentation:** https://docs.aws.amazon.com/eventbridge/, https://docs.aws.amazon.com/sns/, etc.
- **Pricing:** https://aws.amazon.com/pricing/

## Nuggets & Gotchas

- **SQS doesn't guarantee FIFO within a queue across multiple readers — use SQS FIFO queues if you need strict ordering:** Standard SQS queues provide at-least-once delivery with no ordering guarantee. FIFO queues guarantee ordering but have a 300msg/s limit (vs unlimited for standard).
- **SNS doesn't persist messages — subscribers must be online when published:** If a subscriber is offline (Lambda error, SQS queue temporarily empty), the message is NOT retried by SNS. Use SQS with SNS subscription (SQS queues persist messages) or EventBridge for retry logic.
- **EventBridge's default event bus only receives AWS events — for custom events, you create a custom event bus:** The `default` event bus receives AWS service events. Custom applications publish to a custom event bus you create.
- **Step Functions standard workflows have a 1-year execution limit — for longer workflows, use express workflows or redesign:** Standard workflow executions can run up to 1 year. Express workflows have a 5-minute limit but handle 100K+ executions/second.
- **Amazon MQ is NOT serverless — you pay for the broker instance 24/7:** If you want managed messaging without fixed costs, use SQS/SNS (serverless, pay-per-request) instead of Amazon MQ.
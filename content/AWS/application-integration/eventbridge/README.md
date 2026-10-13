---
title: Amazon EventBridge
description: Amazon EventBridge — serverless event bus. Default/custom/event buses, rules, schema registry, SaaS ingestion, replay, event replay, and cross-account event delivery.
tags:
  - aws/application-integration
date: 2026-10-12
---

# EventBridge

Prerequisites: [[AWS/security/iam/README|scoped IAM roles]] and [[AWS/monitoring/README|delivery/processing observability]].

EventBridge routes events by matching patterns on a bus. Scheduler triggers work at configured times; Pipes connect a source to a target with optional filtering/enrichment. They are related products, not one interchangeable API.

## Routing and reliability

The default bus accepts AWS service and custom events; a custom bus gives application-specific ownership. Every matching rule can deliver to its targets—there is no first-match-only priority. Target IAM/resource policies, retry policies and dead-letter queues determine delivery behavior.

Consumers need idempotency for retry and replay. Archives have configurable retention, with indefinite retention by default; a replay resource's ninety-day lifetime is not an archive-retention ceiling. Replay can duplicate side effects, so establish authorization and dry-run strategy.

## Pattern fixture

Save pattern.json:

```json
{
  "source": ["wiki.demo"],
  "detail-type": ["OrderCreated"],
  "detail": { "status": ["paid"] }
}
```

Save event.json (this is the matching envelope, not the PutEvents entries array):

```json
{
  "version": "0",
  "id": "fixture-1",
  "detail-type": "OrderCreated",
  "source": "wiki.demo",
  "account": "123456789012",
  "time": "2026-10-12T00:00:00Z",
  "region": "us-east-1",
  "resources": [],
  "detail": { "status": "paid", "orderId": "1" }
}
```

```bash
aws events test-event-pattern --event-pattern file://pattern.json --event file://event.json
```

Expected Result=true. Change status to unpaid and expect false; this read-only match test creates no infrastructure.

## End-to-end sandbox

Create a custom bus and a rule with the fixture pattern using create-event-bus and put-rule. Create a disposable [[AWS/application-integration/sqs/README|SQS queue]], get its ARN and grant events.amazonaws.com sqs:SendMessage on that queue, constrained by aws:SourceArn to this rule's ARN. Attach the queue with put-targets (Id, Arn); configure a separate standard-queue DLQ and its delivery policy if testing exhausted retries.

Publish using a complete request:

```bash
aws events put-events --entries '[{"EventBusName":"wiki-lab","Source":"wiki.demo","DetailType":"OrderCreated","Detail":"{\"status\":\"paid\",\"orderId\":\"1\"}"}]'
```

Inspect FailedEntryCount and every entry's error; API transport success is insufficient. Receive from SQS and verify the detail. Deliberately remove target permission in the sandbox, observe delivery failures and restore it. With several matching rules, expect multiple target deliveries.

Cleanup order: remove-targets, delete-rule, delete-event-bus, delete disposable queue/DLQ. Disable replay before teardown. Role permissions must cover only these resources.

## Costs and preflight

Bus events, Scheduler, Pipes, archives/replay, API destinations and schema features have separate pricing dimensions. AWS service-originated and custom events do not have identical tariffs. Check target quotas and adjustability in the actual Region instead of copying a static table.

## Bus, Scheduler and Pipes comparison

| Capability         | Model                          | Configuration boundary                                 |
| ------------------ | ------------------------------ | ------------------------------------------------------ |
| Default/custom bus | Many rules match an event      | Bus policy, rule pattern, target authorization         |
| Partner bus        | Eligible SaaS event source     | Partner source activation and ownership                |
| Scheduler          | Time-based target invocation   | Schedule group, timezone/window, target execution role |
| Pipes              | One supported source to target | Source polling, filter, enrichment, target role        |

These are parallel product choices, not a default→custom→partner processing pipeline. Schedules do not publish business events automatically unless configured to do so.

## Rules and complete target attachment

The existing pattern lab supplies pattern.json. With an existing sandbox queue and the documented queue resource policy:

```bash
aws events create-event-bus --name wiki-lab
aws events put-rule --name paid-orders --event-bus-name wiki-lab \
  --event-pattern file://pattern.json --state ENABLED
aws events put-targets --event-bus-name wiki-lab --rule paid-orders \
  --targets '[{"Id":"work-queue","Arn":"QUEUE_ARN"}]'
```

Replace QUEUE_ARN, then inspect FailedEntryCount/FailedEntries. PutRule does **not** accept Targets; PutTargets is separate. A target requiring an execution role needs its exact RoleArn/trust/action resources; SQS/Lambda targets need the applicable resource policy. Configure retry age/attempts and an authorized standard-queue DLQ when testing delivery failure.

## Content patterns

Save each pattern as its own valid JSON document, not commented/concatenated JSON:

```json
{
  "source": ["wiki.demo"],
  "detail": {
    "amount": [{ "numeric": [">", 1000] }],
    "status": [{ "anything-but": "pending" }]
  }
}
```

Arrays express alternatives for that field; fields combine according to the pattern contract. Test missing fields, strings versus numbers and boundary values with test-event-pattern. Pattern matching is not business schema validation.

## Archive/replay and schema workflow

Archive creation selects an event source bus and optional pattern/retention. Replay uses start-replay, with source archive ARN, start/end times and destination bus; there is no put-replay/StartingPosition recipe.

```bash
aws events start-replay --replay-name wiki-lab-replay \
  --event-source-arn ARCHIVE_ARN \
  --event-start-time 2026-10-12T00:00:00Z --event-end-time 2026-10-12T01:00:00Z \
  --destination '{"Arn":"EVENT_BUS_ARN"}'
```

Substitute a real retained interval and bus. Replay only after approval/idempotency tests; inspect describe-replay and handle terminal failure/cancel. These commands add delivery work and charges, not a free inspection.

Schema registry uses the separate schemas API, not events.discover_schema/create_schema. Discovery/code bindings help clients understand shapes but do not authorize access or guarantee all publishers conform. Review discovered sensitive fields and generated-code/version ownership.

## Cross-account delivery and troubleshooting

```text
Producer account → forwarding rule + role → destination bus policy
                                             ↓
                                   destination rules → targets
```

Authorize the destination bus to accept events from the intended source; authorize the sending role's PutEvents action on that bus. Restrict source/account conditions where appropriate, and distinguish direct PutEvents from forwarding. A receiving rule then routes to its own authorized targets.

Inspect producer entry errors, rule matched events, target invocations/failures and DLQ evidence. An unmatched pattern, expired retry window and KMS/policy denial require different fixes. Remove targets before deleting rules/bus; cancel lab replay and remove owned archives/discoverers separately.

References: [PutTargets](https://docs.aws.amazon.com/cli/latest/reference/events/put-targets.html), [StartReplay](https://docs.aws.amazon.com/cli/latest/reference/events/start-replay.html), [cross-account events](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cross-account.html), [schemas](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-schema.html).

## Cross-wiki comparisons

- [[Azure/messaging/service-bus/README|Azure Service Bus Architecture, Queues, Topics, and Enterprise Messaging]] — messaging and streaming (Azure)
- [[Azure/messaging/event-hubs/README|Azure Event Hubs Architecture, Kafka Compatibility, and Streaming Ingestion]] — messaging and streaming (Azure)

## References

- [Rules](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-rules.html)
- [Archives](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-archive.html)
- [SQS target policies](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-use-resource-based.html)
- [PutEvents contract](https://docs.aws.amazon.com/cli/latest/reference/events/put-events.html)
- [Pricing](https://aws.amazon.com/eventbridge/pricing/)

## Across the wiki

- [[GCP/analytics/pubsub/README|Cloud Pub/Sub Architecture & Streaming Mechanics]]
- [[Architecture/solution-architecture-concepts/event-driven-architecture/kafka/README|Apache Kafka]]

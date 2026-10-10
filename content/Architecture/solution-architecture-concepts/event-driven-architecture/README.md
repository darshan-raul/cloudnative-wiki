---
title: Event-Driven Architecture
tags: [architecture, event-driven, messaging, kafka, async]
date: 2026-10-10
description: Designing systems around events — events versus commands, queues versus logs, the main patterns (notification, state transfer, sourcing, CQRS), the outbox, sagas, ordering and idempotency, schema evolution, and when synchronous calls are the better choice.
---

# Event-Driven Architecture

In an event-driven system, a service announces that something **happened** and does not know or care who reacts. Other services subscribe and act independently. Compared with one service calling another and waiting, this removes knowledge and timing dependencies between them — and replaces them with new problems of ordering, duplication and visibility.

## Events, commands and queries

| Kind        | Meaning                    | Named in       | Sender expects                  | Example          |
| :---------- | :------------------------- | :------------- | :------------------------------ | :--------------- |
| **Event**   | A fact: something happened | The past tense | Nothing; zero or many consumers | `OrderPlaced`    |
| **Command** | A request to do something  | The imperative | One handler to act              | `ChargeCard`     |
| **Query**   | A request for information  | A question     | An answer                       | `GetOrderStatus` |

The distinction matters for coupling. A command says "I know you exist and what you should do". An event says "this happened" and leaves the decision to whoever listens. A service that publishes `OrderPlaced` does not change when a new consumer — loyalty points, fraud scoring, analytics — is added.

## Why, and at what cost

| Benefit                                                               | Cost                                                          |
| :-------------------------------------------------------------------- | :------------------------------------------------------------ |
| **Loose coupling**: producers do not know consumers                   | The overall flow is not written down anywhere; it emerges     |
| **Resilience**: a consumer can be down and catch up later             | **Eventual consistency**: other services lag behind the truth |
| **Elasticity**: the broker absorbs bursts; consumers scale separately | Duplicates and out-of-order delivery must be handled          |
| **Extensibility**: add consumers without touching producers           | Schema changes affect consumers you may not know about        |
| **Audit and replay**, when events are retained                        | Debugging needs correlation IDs and tracing                   |

## Queues and logs

Two different broker models are often conflated.

|                   | Queue                                                                                                                                                                                                      | Log (stream)                                                                                                                                     |
| :---------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------- |
| After consumption | The message is removed                                                                                                                                                                                     | The record remains until retention expires                                                                                                       |
| Consumers         | Compete: each message goes to one worker                                                                                                                                                                   | Each consumer group reads everything, at its own offset                                                                                          |
| Replay            | No                                                                                                                                                                                                         | Yes                                                                                                                                              |
| Ordering          | Usually best effort                                                                                                                                                                                        | Strict within a partition                                                                                                                        |
| Good for          | Distributing tasks                                                                                                                                                                                         | Distributing facts to many consumers, and stream processing                                                                                      |
| Examples          | [[Architecture/solution-architecture-concepts/event-driven-architecture/rabbitmq\|RabbitMQ]], [[AWS/application-integration/sqs/README\|SQS]], [[AWS/application-integration/amazon-mq/README\|Amazon MQ]] | [[Architecture/solution-architecture-concepts/event-driven-architecture/kafka/README\|Kafka]], [[AWS/analytics/kinesis/README\|Kinesis]], Pulsar |

Pub/sub routers — [[AWS/application-integration/sns/README|SNS]], [[AWS/application-integration/eventbridge/README|EventBridge]], Azure Event Grid — fan events out by topic or content and are often combined with queues: one topic, a queue per subscriber.

## Four patterns

"Event-driven" covers several distinct designs.

**1. Event notification.** The event is small: "order 42 was placed". Consumers call back to the source for details. Minimal coupling on data, but it creates load on the source and a runtime dependency on it.

**2. Event-carried state transfer.** The event carries the data consumers need. They keep their own copy and never call back. This gives autonomy and resilience at the price of duplicated, eventually consistent data.

**3. Event sourcing.** The sequence of events _is_ the system of record. Current state is derived by replaying them. You get a complete audit trail and the ability to rebuild state or answer "what did we know on that day?". You pay with complexity: event versioning, snapshots, and no simple way to "just update a row".

**4. CQRS.** Separate models for writing and reading. Writes go through a model that enforces rules; events update one or more read models shaped for queries. Useful when read and write patterns differ sharply; unnecessary overhead when they do not.

Most systems need only the first two. Event sourcing and CQRS are powerful and frequently adopted for problems that did not require them.

## Reliable publishing: the outbox

A service that updates its database and then publishes an event has a **dual-write** problem: if it crashes between the two, either the event is lost or it describes a change that was rolled back.

The **transactional outbox** solves it:

```
BEGIN;
  UPDATE orders SET status = 'placed' WHERE id = 42;
  INSERT INTO outbox (id, topic, key, payload) VALUES (…, 'orders', '42', '{…}');
COMMIT;

a relay — a poller, or change data capture on the outbox table — publishes each row to the broker
```

The business change and the intent to publish commit atomically. The relay delivers at least once, so consumers must be idempotent. Reading the database log directly is [[Architecture/solution-architecture-concepts/migration-patterns/change-data-capture|change data capture]].

## Consuming safely

Assume every event may arrive **more than once** and possibly **out of order**.

- **Idempotency.** Processing the same event twice must have the same effect as once. Record processed event IDs, use upserts, or make operations naturally idempotent ("set status to shipped", not "increment"). See [[Architecture/solution-architecture-concepts/reliability/idempotency|idempotency]].
- **Ordering.** Brokers order only within a partition or message group. Key events by the entity whose order matters, and carry a version or sequence number so stale events can be ignored.
- **Poison messages.** An event that always fails must not block the rest. Retry with backoff a bounded number of times, then move it to a **dead-letter queue** and alert.
- **Back-pressure.** Bound consumer concurrency and watch lag; a queue hides overload until it does not. See [[Architecture/solution-architecture-concepts/reliability/resilience|resilience]].

## Transactions across services: sagas

There is no distributed transaction across services that anyone wants to operate. A **saga** is a sequence of local transactions, each publishing an event that triggers the next, with a **compensating action** for each step in case a later one fails.

| Style             | How                                                          | Trade-off                                                             |
| :---------------- | :----------------------------------------------------------- | :-------------------------------------------------------------------- |
| **Choreography**  | Each service reacts to events and emits its own              | No central point; the flow is hard to see and to change               |
| **Orchestration** | A coordinator tells each service what to do and tracks state | The flow is explicit and observable; the orchestrator is a dependency |

Orchestration scales better in complexity. Workflow engines — Temporal, [[AWS/application-integration/step-functions/README|Step Functions]], Camunda — exist for it. Compensations are business operations (refund, release stock), not rollbacks, and some steps cannot be undone at all; order the saga so those come last.

## Designing events

- **Name facts in the past tense** and model them on the business, not on table rows.
- **Include an envelope**: event ID, type, source, time, schema version, correlation ID and trace context. The CloudEvents specification standardises this.
- **Version the schema** and keep changes backward-compatible: add optional fields, never rename or repurpose. A schema registry enforces compatibility at publish time.
- **Do not leak internals.** Publishing your database rows as events couples every consumer to your schema.
- **Mind personal data.** Events are copied widely and retained; deleting a person's data from an immutable log is difficult, so reference or encrypt it.
- **Document them.** AsyncAPI plays the role for events that OpenAPI plays for HTTP.

## Seeing what is happening

Asynchronous flows are hard to follow, so build observability in from the start: propagate a correlation ID and [[Observability/tracing|trace context]] in message headers, monitor consumer lag and dead-letter queue depth, and alert on the age of the oldest unprocessed message rather than on queue length.

## When not to use it

Prefer a synchronous call when the caller needs an answer to continue, when strong consistency is required, when the flow is simple and linear, or when the team is small and the overhead of a broker is not yet justified. A well-structured monolith with in-process events is a perfectly good starting point — see [[Architecture/solution-architecture-concepts/architecture-patterns/microservices|microservices]] and [[Architecture/solution-architecture-concepts/foundations/high-cohesion-loose-coupling|cohesion and coupling]].

## Notes in this section

- [[Architecture/solution-architecture-concepts/event-driven-architecture/kafka/README|Apache Kafka]]
- [[Architecture/solution-architecture-concepts/event-driven-architecture/kafka/kraft-vs-zookeeper|KRaft vs ZooKeeper]]
- [[Architecture/solution-architecture-concepts/event-driven-architecture/rabbitmq|RabbitMQ]]

## Related

- [[Architecture/solution-architecture-concepts/migration-patterns/strangler-fig|Strangler fig]] — events as the seam for incremental migration
- [[Architecture/solution-architecture-concepts/data-architecture/databases/redis|Redis]] Streams and Pub/Sub
- [[AWS/application-integration/README|AWS application integration]]
- [[Azure|Azure messaging]]
- [[Kubernetes/concepts/L06-scheduling-scaling/10-keda|KEDA]] — scaling consumers on queue depth

## Further reading

- [Event Driven Architecture — eda-visuals.boyney.io](https://eda-visuals.boyney.io/)

## Across the wiki

- [[Azure/messaging/service-bus/README|Azure Service Bus Architecture, Queues, Topics, and Enterprise Messaging]] — messaging and streaming (Azure)
- [[GCP/analytics/pubsub/README|Cloud Pub/Sub Architecture & Streaming Mechanics]] — messaging and streaming (GCP)

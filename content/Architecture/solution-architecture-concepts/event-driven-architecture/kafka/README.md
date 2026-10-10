---
title: Apache Kafka
tags: [architecture, kafka, event-driven, streaming, messaging]
date: 2026-10-10
description: Kafka as a distributed commit log — topics, partitions and offsets, how ordering and scaling follow from partitioning, replication and durability settings, consumer groups and rebalancing, delivery semantics, retention and compaction, and the ecosystem around it.
---

# Apache Kafka

Kafka is a distributed, durable, append-only log. Producers append records to the end; consumers read from wherever they choose and keep track of their own position. Records are not removed when they are read — they stay until a retention policy deletes them.

That one design decision is what separates Kafka from a traditional message queue. Many independent consumers can read the same data at their own pace, a new consumer can start from the beginning, and a broken consumer can rewind and reprocess. It makes Kafka useful not only for messaging but as the backbone that moves data between systems.

## Core concepts

```
topic "orders"  (3 partitions, replication factor 3)

partition 0:  [0][1][2][3][4][5][6] ──► append
partition 1:  [0][1][2][3][4]
partition 2:  [0][1][2][3][4][5]
                     ▲        ▲
                     │        └─ consumer group "analytics" is at offset 5
                     └─ consumer group "billing" is at offset 2
```

| Term                    | Meaning                                                     |
| :---------------------- | :---------------------------------------------------------- |
| **Record**              | A key, a value, headers and a timestamp                     |
| **Topic**               | A named stream of records                                   |
| **Partition**           | One ordered, append-only log; a topic is split into several |
| **Offset**              | A record's position within its partition                    |
| **Broker**              | A Kafka server; a cluster is a set of brokers               |
| **Producer / consumer** | Clients that write and read                                 |
| **Consumer group**      | A set of consumers sharing the work of reading a topic      |

## Partitions decide everything

Partitions are the unit of **ordering**, **parallelism** and **scaling** at once.

- **Order is guaranteed only within a partition.** There is no ordering across a topic.
- **The record key selects the partition** (by hash). All records with the same key land in the same partition, in order. Choose the key to be the entity whose events must stay ordered: an order ID, an account ID.
- **A partition is read by at most one consumer in a group.** The partition count is therefore the ceiling on a group's parallelism.
- **Records without a key** are spread across partitions for balance, with no ordering relationship.

Choosing the partition count is a real design decision. Too few limits throughput; too many increases broker memory, open files and recovery time. Adding partitions later changes which partition a key maps to, which breaks ordering for existing keys — so size with headroom. A **hot key** (one customer producing most of the traffic) creates a hot partition that no amount of scaling fixes; the key needs rethinking.

## Replication and durability

Each partition has one **leader** and several **followers** on different brokers. Producers and consumers talk to the leader; followers copy it. Followers that are caught up form the **in-sync replica set (ISR)**. If the leader fails, a member of the ISR takes over.

Durability is the product of three settings working together:

| Setting                       | Recommended | Effect                                                       |
| :---------------------------- | :---------- | :----------------------------------------------------------- |
| `replication.factor` (topic)  | 3           | Three copies of every partition                              |
| `min.insync.replicas` (topic) | 2           | A write needs at least two in-sync copies, or it is rejected |
| `acks` (producer)             | `all`       | The producer waits for all in-sync replicas to acknowledge   |

With these, an acknowledged write survives the loss of any one broker, and the cluster stays writable with one broker down. With `acks=1`, a write acknowledged by a leader that then dies is lost. Keep `unclean.leader.election.enable=false`, so an out-of-date replica is never promoted — that trades availability for not losing data, as discussed in [[Architecture/solution-architecture-concepts/api-design/cap-theorem|the CAP theorem]].

Spread replicas across availability zones with rack awareness.

Cluster metadata is managed by Kafka's own Raft-based quorum, **KRaft**. ZooKeeper is no longer used; it was removed entirely in Kafka 4.0 — see [[Architecture/solution-architecture-concepts/event-driven-architecture/kafka/kraft-vs-zookeeper|KRaft vs ZooKeeper]] and [[Architecture/solution-architecture-concepts/cluster-management/raft|Raft]].

## Producers

A producer batches records per partition, optionally compresses the batch, and sends it to the partition's leader.

| Setting                   | Purpose                                                                       |
| :------------------------ | :---------------------------------------------------------------------------- |
| `enable.idempotence`      | On by default: retries cannot create duplicates or reorder within a partition |
| `linger.ms`, `batch.size` | Wait a few milliseconds to fill larger batches — a big throughput gain        |
| `compression.type`        | `zstd` or `lz4`; cuts network and disk use substantially                      |
| `acks`                    | `all` for durability                                                          |

## Consumers and consumer groups

Consumers in a group divide a topic's partitions among themselves. Each periodically **commits** the offset it has processed, to an internal topic, so that a restart resumes from there.

```
topic with 6 partitions

group "billing", 3 consumers:   C1 ← p0 p1     C2 ← p2 p3     C3 ← p4 p5
group "analytics", 1 consumer:  C1 ← p0 p1 p2 p3 p4 p5        (independent offsets)
```

When a consumer joins, leaves or stops sending heartbeats, the group **rebalances**: partitions are reassigned. Older protocols paused the whole group during this; cooperative rebalancing and the newer broker-coordinated protocol move only the partitions that need to move. Still, frequent rebalances are a common cause of poor throughput. The usual trigger is processing that takes longer than `max.poll.interval.ms`, so the consumer is considered dead — reduce the batch size or increase the interval.

**Consumer lag** — the distance between the latest offset and the group's committed offset — is the most important thing to monitor. Growing lag means consumers cannot keep up.

Share groups (queues for Kafka) are a newer alternative for workloads that want queue semantics — per-record acknowledgement and more consumers than partitions — without ordering.

## Delivery semantics

| Semantic          | How it arises                                                                          | Result                                   |
| :---------------- | :------------------------------------------------------------------------------------- | :--------------------------------------- |
| **At most once**  | Commit the offset, then process                                                        | A crash loses the record                 |
| **At least once** | Process, then commit                                                                   | A crash causes reprocessing — duplicates |
| **Exactly once**  | Idempotent producer plus transactions that atomically write outputs and commit offsets | No duplicates **within Kafka**           |

At least once is the default and the practical norm. "Exactly once" holds for read-process-write pipelines that stay inside Kafka. The moment a consumer writes to a database or calls an API, the guarantee stops at that boundary. The robust answer is to make the consumer **idempotent**: record a processed-event ID, use upserts, or use natural keys. See [[Architecture/solution-architecture-concepts/reliability/idempotency|idempotency]].

Records that repeatedly fail should not block the partition forever. Send them to a **dead-letter topic** after bounded retries, with the error attached, and alert on it.

## Retention and compaction

| Policy                  | Behaviour                                                                    | Use for                          |
| :---------------------- | :--------------------------------------------------------------------------- | :------------------------------- |
| `delete` (time or size) | Segments older than the limit are removed                                    | Event streams                    |
| `compact`               | Keeps at least the latest record for every key; a null value deletes the key | Changelogs, current-state tables |

A compacted topic is a durable key-value snapshot that can be replayed to rebuild state. **Tiered storage** moves older segments to object storage, so long retention no longer requires large broker disks.

## The ecosystem

| Component           | Role                                                                                                                                                            |
| :------------------ | :-------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Kafka Connect**   | Runs connectors that move data in and out: databases, object stores, search, warehouses                                                                         |
| **Debezium**        | Connect source connectors that read database logs — [[Architecture/solution-architecture-concepts/migration-patterns/change-data-capture\|change data capture]] |
| **Schema Registry** | Stores Avro, Protobuf or JSON schemas and enforces compatibility between producers and consumers                                                                |
| **Kafka Streams**   | A library for stateful stream processing inside your application                                                                                                |
| **Apache Flink**    | A cluster engine for stream processing at larger scale                                                                                                          |
| **MirrorMaker 2**   | Replicates topics between clusters and regions                                                                                                                  |

Use a schema registry from the start. Without one, a producer changing a field silently breaks every consumer.

## Running it

| Option                                                                    | Notes                                                  |
| :------------------------------------------------------------------------ | :----------------------------------------------------- |
| Managed: Amazon MSK, Confluent Cloud, Aiven, Azure Event Hubs (Kafka API) | Least operational work                                 |
| Kubernetes: the **Strimzi** operator                                      | Clusters, topics and users as custom resources         |
| Compatible alternatives: Redpanda, WarpStream, AutoMQ                     | The same protocol with different storage architectures |

Kafka relies heavily on the operating system page cache and sequential disk I/O, so give brokers memory beyond the JVM heap and fast disks — [[Linux/storage/storage-performance-tuning|storage performance tuning]]. Autoscaling consumers on lag is a standard use of [[Kubernetes/concepts/L06-scheduling-scaling/10-keda|KEDA]].

## When Kafka is the wrong tool

| You need                                                          | Consider                                                                                                                                      |
| :---------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------- |
| A work queue with per-message acknowledgement, priorities, delays | [[Architecture/solution-architecture-concepts/event-driven-architecture/rabbitmq\|RabbitMQ]], [[AWS/application-integration/sqs/README\|SQS]] |
| Request and reply                                                 | A direct call: HTTP or gRPC                                                                                                                   |
| A few messages a minute                                           | Almost anything simpler, including a database table                                                                                           |
| Routing by content with many small subscribers                    | [[AWS/application-integration/eventbridge/README\|EventBridge]], [[AWS/application-integration/sns/README\|SNS]]                              |

Kafka is justified by high throughput, replay, many independent consumers, or stream processing. Without one of those it is operational weight you do not need.

## Related

- [[Architecture/solution-architecture-concepts/event-driven-architecture/README|Event-driven architecture]]
- [[AWS/analytics/kinesis/README|Amazon Kinesis]] — the AWS-native log
- [[Architecture/solution-architecture-concepts/data-architecture/databases/redis|Redis]] Streams — a lighter alternative
- [[Observability/tracing|Distributed tracing]] — propagating context through message headers

## Further reading

- [Kafka — towardsdev.com](https://towardsdev.com/kafka-101-a-beginners-guide-to-understanding-kafka-2cd797864614)
- [Apache Kafka documentation](https://kafka.apache.org/documentation/)

## Across the wiki

- [[Azure/messaging/service-bus/README|Azure Service Bus Architecture, Queues, Topics, and Enterprise Messaging]] — messaging and streaming (Azure)
- [[GCP/analytics/pubsub/README|Cloud Pub/Sub Architecture & Streaming Mechanics]] — messaging and streaming (GCP)

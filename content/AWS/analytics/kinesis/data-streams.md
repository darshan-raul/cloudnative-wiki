---
title: "Kinesis Data Streams"
description: "Data Streams retains events for independent consumers/replay."
tags:
  - aws/analytics
date: 2026-10-12
---

# Kinesis Data Streams

Data Streams retains events for independent consumers/replay. Producers choose partition keys; consumers manage progress, retries and duplicate effects. Prerequisites: [[AWS/analytics/kinesis/README|streaming fundamentals]], [[AWS/security/iam/README|IAM]] and [[AWS/analytics/managed-flink|stateful processing]] where needed.

## Capacity and records

Provisioned shards have byte/record throughput limits; on-demand modes have their own scaling/burst/billing characteristics. Plan sustained records/bytes per key, shard distribution, outage retention and consumers. The default record maximum is 1 MiB, with opt-in intermittent records up to 10 MiB; sustained shard limits and downstream compatibility remain relevant. Larger record support is not a sustained-capacity increase.

Provisioned write pricing uses million 25-KB PUT payload units, not a generic GB rate. Aggregation by the Kinesis Producer Library can reduce record overhead but changes consumer deaggregation requirements. On-demand is not an invented mandatory four-times unit purchase.

## Consumers and delivery semantics

Polling consumers call shard APIs; enhanced fan-out uses a consumer-initiated SubscribeToShard HTTP/2 connection. It is not a callback endpoint registered for push. Registered-consumer, read throughput and billing limits must match the chosen mode.

KCL coordinates leases, shard ownership and checkpoints through its supported runtime/dependencies. KCL 1.x reached end of support January 30, 2026; old 1.x/2.x documentation is marked outdated. Use the current AWS-maintained KCL/multilang Python example and pin its release rather than a fictional Python KinesisConsumer import.

A simple Boto3 producer is valid but does not create a stream or implement consumer leases:

```python
import boto3

client = boto3.client("kinesis")
response = client.put_record(
    StreamName="sandbox_events",
    Data=b'{"event_id":"test-1","value":7}',
    PartitionKey="customer-1",
)
print(response["ShardId"], response["SequenceNumber"])
```

This requires a configured account/Region, stream and permission; PutRecord charges can apply. Do not print sensitive payloads.

## Worked single-shard polling and duplicate-safe replay lab

Use a dedicated disposable one-shard stream (`dg11-kinesis-replay-lab`) in an authorized sandbox account. Budget shard-hour and PutRecord charges. This lab demonstrates shard iterator advancement, base64 payload decoding, destination deduplication, and a simulated replay pass.

```python
import json
import time
import boto3

kinesis = boto3.client("kinesis")
stream_name = "dg11-kinesis-replay-lab"

# 1. Produce keyed records with a deliberate duplicate event ID
records = [
    {"event_id": "evt-101", "account_id": "acct-1", "amount": 50.0},
    {"event_id": "evt-102", "account_id": "acct-1", "amount": 25.0},
    {"event_id": "evt-101", "account_id": "acct-1", "amount": 50.0},  # Duplicate
    {"event_id": "evt-103", "account_id": "acct-1", "amount": 15.0},
]
for record in records:
    kinesis.put_record(
        StreamName=stream_name,
        Data=json.dumps(record).encode("utf-8"),
        PartitionKey=record["account_id"],
    )

# 2. Acquire starting iterator from TRIM_HORIZON
shards = kinesis.list_shards(StreamName=stream_name)["Shards"]
shard_id = shards[0]["ShardId"]
iterator = kinesis.get_shard_iterator(
    StreamName=stream_name,
    ShardId=shard_id,
    ShardIteratorType="TRIM_HORIZON",
)["ShardIterator"]

# 3. Bounded consumer with idempotent destination state
processed_events = set()
total_revenue = 0.0
deadline = time.monotonic() + 30

while iterator and time.monotonic() < deadline and len(processed_events) < 3:
    response = kinesis.get_records(ShardIterator=iterator, Limit=10)
    for record in response.get("Records", []):
        payload = json.loads(record["Data"].decode("utf-8"))
        eid = payload["event_id"]
        if eid in processed_events:
            print(f"Duplicate detected and ignored: {eid}")
            continue
        processed_events.add(eid)
        total_revenue += payload["amount"]
    iterator = response.get("NextShardIterator")
    time.sleep(1)

assert total_revenue == 90.0, f"Expected 90.0, got {total_revenue}"
assert len(processed_events) == 3, f"Expected 3 unique events, got {len(processed_events)}"
print("Initial run complete: 3 unique events, total =", total_revenue)

# 4. Simulate replay by obtaining a new TRIM_HORIZON iterator
replay_iterator = kinesis.get_shard_iterator(
    StreamName=stream_name,
    ShardId=shard_id,
    ShardIteratorType="TRIM_HORIZON",
)["ShardIterator"]

replayed_records = 0
deadline = time.monotonic() + 30
while replay_iterator and time.monotonic() < deadline and replayed_records < 4:
    response = kinesis.get_records(ShardIterator=replay_iterator, Limit=10)
    for record in response.get("Records", []):
        replayed_records += 1
        payload = json.loads(record["Data"].decode("utf-8"))
        eid = payload["event_id"]
        if eid in processed_events:
            print(f"Replay duplicate absorbed: {eid}")
            continue
        processed_events.add(eid)
        total_revenue += payload["amount"]
    replay_iterator = response.get("NextShardIterator")
    time.sleep(1)

# Revenue remains 90.0 because destination state filtered replayed items
assert total_revenue == 90.0, f"Replay corrupted state: {total_revenue}"
print("Replay verified: all records re-read, duplicate effects absorbed without state mutation.")
```

A raw single-shard polling loop with `GetShardIterator` and `GetRecords` is an educational primitive. It **does not coordinate leases** across multiple consumer nodes, handle dynamic child shard progression on resharding, or persist lease state across crashes. Production distributed consumers should use the [AWS Kinesis Client Library (KCL)](https://github.com/awslabs/amazon-kinesis-client) with DynamoDB lease coordination or [[AWS/analytics/managed-flink|Managed Service for Apache Flink]].

Clean up by deleting the test stream:

```python
kinesis.delete_stream(StreamName=stream_name, EnforceConsumerDeletion=True)
```

## Operations and cost

Monitor incoming bytes/records, write/read throttling, iterator age and processing lag. Cost includes the selected stream mode, writes/read/fan-out, retention and dependent services. Retention plus checkpoints permits replay only inside the retention window; use [[AWS/reliability/backup-and-recovery|recovery planning]] for durable archival/backfills.

## Record and shard anatomy

```text
Producer
  └─ record: partition key + payload
       └─ selected shard: sequence number + retained data
            ├─ consumer A: checkpoint A
            └─ consumer B: checkpoint B
```

Provisioned shard baseline guidance is 1 MiB/s or 1,000 records/s for writes, and shared polling reads are subject to their documented throughput/API constraints. Large-record opt-in changes permitted individual record size, not sustained shard capacity. Sequence numbers identify shard positions; they are not a simple gap-free counter and do not provide exactly-once business effects.

Estimate required capacity from both rounded record rate and bytes. If 2,000 small records/s are all assigned to one hot key, adding aggregate capacity does not automatically distribute that key's load. Measure key distribution, throttling and producer retry/aggregation behavior.

## Consumer lifecycle and replay walkthrough

1. Select a starting position inside retention and acquire the required shard iterator/subscription.
2. Read batches/events with a bounded poll/subscription loop.
3. Validate/deaggregate payloads as applicable.
4. Write idempotently to the destination and checkpoint only after the intended durable effect.
5. Back off on throughput/service errors and handle expired iterators.
6. Handle shard completion and child-shard progression; one hard-coded shard is not a distributed consumer.
7. Restart from recorded progress and deliberately replay a batch to test duplicates.

KCL automates lease and checkpoint coordination but still leaves business idempotency to the application. Its lease/state tables, metrics and worker lifecycle are real dependencies with costs/permissions. Enhanced fan-out subscriptions dedicate supported read throughput per registered consumer; they are not webhooks.

## Operational observations

Track incoming bytes/records, write throttling, read throttling and consumer iterator age separately. Rising iterator age may be caused by slow processing or destination backpressure even if the stream itself is healthy. Define a lag alarm relative to the remaining retention window.

Use cases include fraud/personalization consumers, replayable application events, log archival and IoT processing. Current stateful pipelines should link to [[AWS/analytics/managed-flink|Managed Flink]], not retired Kinesis SQL. Remove only your sandbox stream/consumer/KCL tables, not shared lease resources used by other workers.

## References

- [Quotas and large records](https://docs.aws.amazon.com/streams/latest/dev/service-sizes-and-limits.html)
- [Enhanced fan-out](https://docs.aws.amazon.com/streams/latest/dev/enhanced-consumers.html)
- [Current KCL source](https://github.com/awslabs/amazon-kinesis-client)
- [KCL version notice](https://docs.aws.amazon.com/streams/latest/dev/developing-consumers-with-kcl-v2.html)
- [PutRecord contract](https://docs.aws.amazon.com/boto3/latest/reference/services/kinesis/client/put_record.html)
- [Pricing](https://aws.amazon.com/kinesis/data-streams/pricing/)

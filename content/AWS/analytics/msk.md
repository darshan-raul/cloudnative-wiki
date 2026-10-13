---
title: "Amazon MSK and streaming guarantees"
description: "Compare Kafka/MSK boundaries with Kinesis and test partition ordering, consumer replay and failure-aware side effects."
tags:
  - cloud/aws/analytics
date: 2026-10-12
---

# Amazon MSK and streaming guarantees

MSK manages supported Kafka infrastructure. Applications still own event schemas, key selection, consumer behavior, access and downstream correctness. Start with [[AWS/analytics/kinesis/README|the streaming comparison]].

## Kafka model

A topic has partitions; ordering is scoped to a partition, not the entire topic. Producers choose keys/partitioning. Consumer groups distribute partition processing and track offsets. Retention enables replay within configured bounds but is not infinite history.

Compare supported provisioned/serverless modes, versions, authentication/network access and capacity requirements. MSK Connect runs supported connector workloads; a connector does not automatically make an external destination transactionally consistent.

Exactly-once claims require a defined boundary. Kafka transactional processing does not by itself prevent duplicate emails/payments in an external system. Idempotent writes and offset/effect coordination remain application decisions.

## Worked client recipe and idempotent replay fixture

Use an authorized Amazon MSK cluster (provisioned or serverless) within a dedicated private VPC subnet. Configure SASL/SCRAM or AWS MSK IAM authentication. The client requires network reachability to broker ports (`9096` for IAM or `9098` for SASL/SCRAM).

### Pinned consumer configuration

When using `kafka-python` or `confluent-kafka` against MSK:

- Set `enable_auto_commit=False` to ensure offsets are only committed **after** the downstream business effect is persisted.
- Set `auto_offset_reset='earliest'` for replay capability.
- Isolate consumer group IDs (`group_id='dg11-audit-group'`).

### Idempotent destination fixture and replay test

The snippet below demonstrates the exact per-message manual commit loop and duplicate-safe state store:

```python
import json
from collections import defaultdict

# Fixture representing ordered partition messages with a duplicate
events_fixture = [
    {"topic": "dg11-orders", "partition": 0, "offset": 100, "key": "acct-1",
     "value": {"order_id": "ord-001", "amount": 100.0}},
    {"topic": "dg11-orders", "partition": 0, "offset": 101, "key": "acct-1",
     "value": {"order_id": "ord-002", "amount": 50.0}},
    {"topic": "dg11-orders", "partition": 0, "offset": 102, "key": "acct-1",
     "value": {"order_id": "ord-001", "amount": 100.0}},  # Duplicate order
    {"topic": "dg11-orders", "partition": 0, "offset": 103, "key": "acct-1",
     "value": {"order_id": "ord-003", "amount": 25.0}},
]

class IdempotentOrderStore:
    def __init__(self):
        self.seen_order_ids = set()
        self.account_totals = defaultdict(float)
        self.applied_orders = []

    def apply_order(self, order_id, account_id, amount):
        if order_id in self.seen_order_ids:
            return False  # Duplicate detected; skip side effect
        self.seen_order_ids.add(order_id)
        self.account_totals[account_id] += amount
        self.applied_orders.append(order_id)
        return True

store = IdempotentOrderStore()
committed_offsets = {}

# Pass 1: Normal processing with manual commit per record
for record in events_fixture:
    val = record["value"]
    applied = store.apply_order(val["order_id"], record["key"], val["amount"])
    # In live Kafka: consumer.commit(offsets={TopicPartition(...): OffsetAndMetadata(...)})
    committed_offsets[record["partition"]] = record["offset"]

assert store.account_totals["acct-1"] == 175.0, store.account_totals
assert store.applied_orders == ["ord-001", "ord-002", "ord-003"]
print("Pass 1 succeeded: 3 unique orders applied, total =", store.account_totals["acct-1"])

# Pass 2: Replay from partition beginning
for record in events_fixture:
    val = record["value"]
    applied = store.apply_order(val["order_id"], record["key"], val["amount"])
    assert not applied, f"Duplicate order {val['order_id']} was re-applied"

assert store.account_totals["acct-1"] == 175.0
print("Pass 2 replay verified: total remained 175.0, duplicate side-effects prevented.")
```

### Transactional boundaries

- **Kafka-internal EOS**: When writing from Kafka topic to Kafka topic, Kafka transactions (`send_offsets_to_transaction`) achieve atomic read-process-write across topics.
- **External sinks**: If writing to an external database or external API, Kafka offset commit and the external write are two independent systems without a 2PC coordinator. Exactly-once end-to-end requires either an idempotent destination key or an outbox pattern with transactional offset storage.

Cleanup: delete the test topic using `kafka-topics.sh --delete --topic dg11-orders` and terminate test client instances and connectors. Verify no idle provisioned brokers remain billing.

## References

- [MSK overview](https://docs.aws.amazon.com/msk/latest/developerguide/what-is-msk.html).
- [MSK getting started](https://docs.aws.amazon.com/msk/latest/developerguide/getting-started.html).
- [Kafka design and delivery semantics](https://kafka.apache.org/documentation/#design).
- [MSK pricing](https://aws.amazon.com/msk/pricing/).

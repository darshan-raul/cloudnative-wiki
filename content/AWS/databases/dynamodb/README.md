---
title: Amazon DynamoDB
description: Amazon DynamoDB — fully managed NoSQL key-value and document database. Tables, partitions, sort keys, GSI, LSI, operations, DynamoDB Streams, TTL, DAX, and pricing.
tags:
  - aws
  - databases
  - dynamodb
  - nosql
---

# Amazon DynamoDB

DynamoDB is a fully managed NoSQL database with single-digit millisecond latency at any scale. It supports key-value and document data models. No servers to manage, automatic partitioning, and on-demand capacity or provisioned capacity with auto-scaling.

## Core Concepts

### Data Model

```
Table
  └── Item (row)
        ├── Attribute (column)
        ├── Partition Key (required, hash)
        └── Sort Key (optional, range)
```

### Primary Key

**Partition Key (PK) only:**
```
UserID (PK) → Hash function → Partition
```
All items with the same PK are stored together.

**Partition Key + Sort Key (SK):**
```
UserID (PK) + OrderID (SK) → Partition
```
Items are sorted within a partition. Allows efficient range queries within a partition.

### Example Table: Orders

| UserID (PK) | OrderID (SK) | Date | Total | Status |
|-------------|--------------|------|-------|--------|
| user123 | order-001 | 2024-01-15 | 99.99 | shipped |
| user123 | order-002 | 2024-02-20 | 149.99 | pending |
| user456 | order-001 | 2024-01-10 | 29.99 | delivered |

Query: Get all orders for user123:
```bash
aws dynamodb query \
  --table-name Orders \
  --key-condition-expression "UserID = :uid" \
  --expression-attribute-values '{":uid": {"S": "user123"}}'
```

## Creating a Table

```bash
aws dynamodb create-table \
  --table-name Orders \
  --attribute-definitions '[
    {"AttributeName": "UserID", "AttributeType": "S"},
    {"AttributeName": "OrderID", "AttributeType": "S"}
  ]' \
  --key-schema '[
    {"AttributeName": "UserID", "KeyType": "HASH"},
    {"AttributeName": "OrderID", "KeyType": "RANGE"}
  ]' \
  --billing-mode PAY_PER_REQUEST \
  --table-class STANDARD
```

### With Provisioned Capacity

```bash
aws dynamodb create-table \
  --table-name Orders \
  --attribute-definitions '[...]' \
  --key-schema '[...]' \
  --provisioned-throughput '{
    "ReadCapacityUnits": 10,
    "WriteCapacityUnits": 5
  }'
```

## Reading and Writing

### PutItem (insert/replace)

```bash
aws dynamodb put-item \
  --table-name Orders \
  --item '{
    "UserID": {"S": "user123"},
    "OrderID": {"S": "order-001"},
    "Date": {"S": "2024-01-15"},
    "Total": {"N": "99.99"},
    "Status": {"S": "shipped"}
  }'
```

### GetItem (read by PK + SK)

```bash
aws dynamodb get-item \
  --table-name Orders \
  --key '{"UserID": {"S": "user123"}, "OrderID": {"S": "order-001"}}'
```

### Query (range of items by SK within a partition)

```bash
aws dynamodb query \
  --table-name Orders \
  --key-condition-expression "UserID = :uid AND OrderID BETWEEN :start AND :end" \
  --expression-attribute-values '{
    ":uid": {"S": "user123"},
    ":start": {"S": "order-001"},
    ":end": {"S": "order-999"}
  }'
```

### Scan (full table, expensive)

```bash
aws dynamodb scan \
  --table-name Orders \
  --filter-expression "Status = :status" \
  --expression-attribute-values '{":status": {"S": "shipped"}}'
```

**Warning:** Scan reads every item in the table. Use `FilterExpression` to reduce response size, but you still pay for all the reads. Never scan large tables in production.

### Batch Operations

```bash
# BatchGetItem (up to 100 items)
aws dynamodb batch-get-item \
  --request-items '{
    "Orders": {
      "Keys": [
        {"UserID": {"S": "user123"}, "OrderID": {"S": "order-001"}},
        {"UserID": {"S": "user456"}, "OrderID": {"S": "order-001"}}
      ]
    }
  }'

# BatchWriteItem (up to 25 items, 16MB)
aws dynamodb batch-write-item \
  --request-items '{
    "Orders": [
      {"PutRequest": {"Item": {"UserID": {"S": "user789"}, "OrderID": {"S": "order-001"}}}}
    ]
  }'
```

## Secondary Indexes

### Global Secondary Index (GSI)

A GSI has a different PK and optional SK from the base table. It has its own provisioned throughput.

```bash
aws dynamodb update-table \
  --table-name Orders \
  --attribute-definitions '[{"AttributeName": "Status", "AttributeType": "S"}]' \
  --global-secondary-index-updates '[{
    "Create": {
      "IndexName": "StatusIndex",
      "KeySchema": [{"AttributeName": "Status", "KeyType": "HASH"}],
      "Projection": {"ProjectionType": "ALL"},
      "ProvisionedThroughput": {"ReadCapacityUnits": 5, "WriteCapacityUnits": 5}
    }
  }]'
```

Query GSI:
```bash
aws dynamodb query \
  --table-name Orders \
  --index-name StatusIndex \
  --key-condition-expression "#st = :status" \
  --expression-attribute-names '{"#st": "Status"}' \
  --expression-attribute-values '{":status": {"S": "shipped"}}'
```

### Local Secondary Index (LSI)

LSI has the same PK as the base table but a different SK. Shares the base table's partition throughput.

```bash
aws dynamodb create-table \
  --table-name Orders \
  --attribute-definitions '[
    {"AttributeName": "UserID", "AttributeType": "S"},
    {"AttributeName": "OrderID", "AttributeType": "S"},
    {"AttributeName": "Date", "AttributeType": "S"}
  ]' \
  --key-schema '[
    {"AttributeName": "UserID", "KeyType": "HASH"},
    {"AttributeName": "OrderID", "KeyType": "RANGE"}
  ]' \
  --local-secondary-indexes '[{
    "IndexName": "DateIndex",
    "KeySchema": [
      {"AttributeName": "UserID", "KeyType": "HASH"},
      {"AttributeName": "Date", "KeyType": "RANGE"}
    ],
    "Projection": {"ProjectionType": "ALL"}
  }]'
```

### GSI vs LSI

| | GSI | LSI |
|--|--|--|
| PK | Different from base table | Same as base table |
| SK | Different (optional) | Different |
| Throughput | Own provisioned capacity | Shares base table capacity |
| Size limit | 10GB per partition key value | No limit |
| Projections | ALL, KEYS_ONLY, INCLUDE | ALL, KEYS_ONLY, INCLUDE |
| Use when | Need different PK access patterns | Need different SK with same PK |

## DynamoDB Streams

Capture item-level changes (insert, modify, remove):

```bash
aws dynamodb update-table \
  --table-name Orders \
  --stream-specification '{
    "StreamEnabled": true,
    "StreamViewType": "NEW_AND_OLD_IMAGES"
  }'
```

`StreamViewType` options:
- `KEYS_ONLY` — only PK/SK
- `NEW_IMAGE` — entire new item
- `OLD_IMAGE` — entire old item
- `NEW_AND_OLD_IMAGES` — both

## Time To Live (TTL)

Automatically delete items after expiration:

```bash
aws dynamodb update-time-to-live \
  --table-name Orders \
  --time-to-live-specification '{
    "Enabled": true,
    "AttributeName": "ExpiresAt"
  }'
```

Set `ExpiresAt` to Unix timestamp. Items expire and are deleted within 48 hours.

## DAX (DynamoDB Accelerator)

In-memory cache (write-through) for microsecond latency:

```bash
# Create DAX cluster
aws dax create-cluster \
  --cluster-name my-dax \
  --node-type dax.r4.large \
  --replication-factor 2 \
  --iam-role-arn arn:aws:iam::123456789012:role/dax-role

# Update table to enable DAX
# DAX is accessed via a separate endpoint (not the DynamoDB endpoint)
```

**Note:** DAX is not a read-through cache — only write-through. For read-heavy workloads, use DAX or ElastiCache (DynamoDB doesn't natively support read-through caching).

## Partition Behavior

DynamoDB distributes data across partitions by hashing the PK:

```
PK Hash (MD5) → 0 to 2^128 → Partition
```

Each partition supports:
- Up to 1,000 WCUs
- Up to 3,000 RCUs
- 10GB of data

### Hot Partitions

If one PK gets more traffic than others (celebrity problem):

- Use write sharding: `userID + "#" + random(1-10)` to spread writes
- Use random suffixes in sort key
- Consider provisioned capacity with higher RCU/WCU for hot items

## Pricing

### On-Demand Mode

| | Cost |
|--|--|
| WCU (write) | $1.25 per million |
| RCU (read) | $0.25 per million (strongly consistent), $0.125 (eventually consistent) |
| Data storage | $0.25/GB/month |

### Provisioned Mode

| | Cost |
|--|--|
| WCU | $0.00065 per hour |
| RCU | $0.00013 per hour |
| Data storage | $0.25/GB/month |

### Reserved Capacity

1 or 3 year commitment: 50-70% savings.

## References

- **Homepage:** https://aws.amazon.com/dynamodb/
- **Documentation:** https://docs.aws.amazon.com/dynamodb/
- **Pricing:** https://aws.amazon.com/dynamodb/pricing/

## Pricing Examples

**Scenario 1:** A table with 10M items, 5KB average item size. 1000 writes/day, 10,000 reads/day. On-Demand: 1000 × 1 WCU = 1,000,000 WCUs/month. 10,000 × 1 RCU = 10,000,000 RCUs/month. WCU cost: 1M × $1.25/M = $1.25/month. RCU cost: 10M × $0.25/M = $2.50/month. Storage: 10M × 5KB = 50GB × $0.25 = $12.50/month. Total: ~$16/month.

**Scenario 2:** Same table with heavy write load (1000 writes/second, 24/7). Provisioned: 1000 WCU = $0.65/hr × 24 × 30 = $468/month. On-Demand: 1000 writes/sec × 3600 sec/hr × 24hr × 30 days = 2.16 billion writes/month. 2.16B × $1.25/M = $2,700/month. Provisioned is 5.7x cheaper for consistent high throughput.

## Nuggets & Gotchas

- **DynamoDB has no schema — items in the same table can have completely different attributes:** One item can have `{"email": "x"}` and another `{"count": 42}`. Enforce schema at the application layer or use a separate attribute to indicate type.
- **DynamoDB transactions (TransactWriteItems) have a 25-item limit — you can't update 30 items atomically:** If you need atomic updates across more than 25 items, use a Saga pattern (orchestrated compensation) instead of a single transaction.
- **GSIs have their own provisioned throughput and cannot be updated without recreating the index:** If you need to change the GSI key schema, you must create a new GSI, backfill data, and switch. Plan your GSI design carefully.
- **On-demand DynamoDB is more expensive than provisioned for consistent high-throughput workloads:** If you know your traffic pattern, use provisioned with auto-scaling. On-demand is for unpredictable, spiky, or low-traffic tables.
- **DynamoDB doesn't support joins — you must denormalize or use multiple queries:** If you need related data (orders + customer info), embed it in the item or make separate queries. For complex queries, consider using Elasticsearch or Athena.
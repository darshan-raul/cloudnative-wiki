---
title: "Amazon DynamoDB"
description: "DynamoDB provides key/value and document storage."
tags:
  - aws/databases
date: 2026-10-12
---

# Amazon DynamoDB

DynamoDB provides key/value and document storage. Design the partition key, optional sort key and indexes around known access patterns; adding a table does not turn arbitrary joins/scans into efficient queries. Prerequisites: [[AWS/databases/README|database selection]], [[AWS/security/iam/README|IAM]] and [[AWS/architecture/data-store-selection|data-store selection]].

## Access patterns and consistency

GetItem addresses a primary key; Query selects a partition-key value and optionally sort-key conditions; Scan visits the dataset and can consume substantial capacity. Filter expressions do not make read capacity free. Avoid hot keys and use conditional writes for optimistic concurrency/idempotency. Pagination and retry/backoff are application responsibilities.

LSIs share the partition key and are defined at table creation; the 10-GB item-collection limit applies to tables with LSIs, not GSIs. GSIs use independent key schemas and have their own consistency/capacity behavior. Check consistency rules for table, index and chosen global-table configuration instead of applying one blanket guarantee.

Transactions support up to 100 distinct items and 4 MB, with documented same-account/Region restrictions. A thirty-item atomic change does not inherently require a Saga. Streams enable change-driven processing; consumers must tolerate retry/duplicate events and avoid equating a stream with indefinite archival retention.

## Capacity and cache

On-demand bills request units; provisioned capacity bills configured read/write units and can use autoscaling. Item size and consistency affect units: a 5-KB standard write consumes five write units, and a strongly consistent 5-KB read consumes two read units. Transactions have different multipliers.

DAX is a read-through cache for supported DynamoDB access; it is not an independent database. A single node can be used for development, while production availability calls for a multi-node design. TTL expiry is asynchronous deletion, not a precise alarm clock. Do not invent a thirty-day DAX reservation product.

## Backup and sandbox exercise

PITR supports a configurable one-to-thirty-five-day window. On-demand backups and longer retention are separate. Use [[AWS/reliability/backup-and-recovery|recovery planning]] to include KMS, IAM and application cutover.

Create a small sandbox table with an orders-by-customer key design. Insert/query labelled orders, deliberately attempt a duplicate conditional write and verify the expected ConditionalCheckFailedException. Query an index using its documented consistency, then restore a backup to a new table and verify records. Observe consumed capacity and throttling metrics. Delete sandbox tables/index-related infrastructure/DAX and reviewed backups after testing.

## Cost arithmetic

Compare workloads at identical item size, consistency and Region. 1,000 writes/day × 30 days is 30,000 writes, not a million. 1,000/second × 86,400 × 30 is 2.592 billion operations. Round each request's units before multiplying rates; include storage, indexes, streams/backup, global replication and optional DAX. Provisioned daily usage is not interchangeable with purchased per-second capacity.

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
UserID (PK) → hash-based initial physical placement → item
```

A partition-key-only table permits only one item per PK. With a composite key, same-PK items form a **logical item collection**; this is not a promise of permanent placement on one physical partition.

**Partition Key + Sort Key (SK):**

```
UserID (PK) → logical item collection, ordered by OrderID (SK)
```

Query selects one PK and can constrain/order its SK values efficiently. Physical partitions are service-managed: without an LSI, split-for-heat can divide an item collection by SK across partitions; with an LSI, that within-collection split is unavailable. Do not assume adaptive capacity immediately repairs a hot-key design. [AWS partition splitting and LSI boundaries](https://aws.amazon.com/blogs/database/part-2-scaling-dynamodb-how-partitions-hot-keys-and-split-for-heat-impact-performance/).

### Example Table: Orders

| UserID (PK) | OrderID (SK) | Date       | Total  | Status    |
| ----------- | ------------ | ---------- | ------ | --------- |
| user123     | order-001    | 2024-01-15 | 99.99  | shipped   |
| user123     | order-002    | 2024-02-20 | 149.99 | pending   |
| user456     | order-001    | 2024-01-10 | 29.99  | delivered |

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
  --filter-expression "#status = :status" \
  --expression-attribute-names '{"#status":"Status"}' \
  --expression-attribute-values '{":status": {"S": "shipped"}}'
```

**Warning:** Scan reads every item in the table. Use `FilterExpression` to reduce response size, but you still pay for all the reads. Use scans only when deliberately budgeted/controlled; filtering does not remove the read cost.

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

## Index comparison, streams and TTL

| Dimension             | GSI                                            | LSI                                      |
| --------------------- | ---------------------------------------------- | ---------------------------------------- |
| Partition key         | Can differ from table                          | Same as table                            |
| Sort key              | Independent optional key                       | Different sort key for same partition    |
| Capacity              | Separate provisioned capacity where applicable | Shares table capacity                    |
| Creation              | Supported after table creation                 | At table creation                        |
| Consistency           | Eventually consistent reads                    | Supported eventual/strong reads          |
| Item-collection limit | Not the LSI ten-GB constraint                  | Ten GB per partition-key item collection |

Use attribute-name aliases for reserved names such as Status. Index projections trade storage/write cost against read needs. A low-cardinality GSI partition such as one common status can be hot; model required distribution before creating it. Provisioned index capacity examples do not directly apply to an on-demand table.

Streams expose configured item-change records, not indefinite business history. Choose keys-only/new/old/both image configuration from consumer needs; checkpoint, retry and deduplicate downstream effects. TTL identifies an epoch-time attribute and asynchronously expires eligible items; reads must account for expired-but-not-yet-deleted data where the application requires exact validity.

## Partition and cache investigation

Write down each access pattern as a key condition, expected item count/size and consistency requirement. Observe consumed capacity and throttling for the base table and indexes separately. A filter only reduces returned results after reading; projection and transaction behavior have their own billing rules.

DAX read-through caching can help supported repeated eventually consistent reads, but does not make every access faster or replace DynamoDB durability. Check cache miss/staleness behavior and bypass requirements for strongly consistent reads. Handle UnprocessedKeys/UnprocessedItems with bounded backoff; one successful batch API response need not mean every requested item was processed.

Before cleanup, verify backup retention and downstream stream dependencies. Delete only the sandbox table/cache and reviewed recovery artifacts, not every table sharing a naming prefix.

## References

- [DynamoDB key and index concepts](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.CoreComponents.html)
- [LSI item-collection limit](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/LSI.html)
- [Transactions](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis.html)
- [DAX behavior](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.html)
- [Backup/PITR](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Backup-and-Restore.html)
- [DynamoDB pricing](https://aws.amazon.com/dynamodb/pricing/)

## Across the wiki

- [[Azure/databases/cosmos-db|Azure Cosmos DB]] — NoSQL databases (Azure)
- [[GCP/databases/firestore/README|Google Cloud Firestore]] — NoSQL databases (GCP)
- [[Architecture/solution-architecture-concepts/data-architecture/databases/mongodb/README|MongoDB]] — NoSQL databases (Architecture)
- [[GCP/databases/bigtable/README|Google Cloud Bigtable]] — NoSQL databases (GCP)

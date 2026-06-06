---
title: Amazon DocumentDB
description: Amazon DocumentDB — MongoDB compatible document database. Collections, aggregation pipelines, transactions, change streams, and cluster scaling.
tags:
  - aws
  - databases
  - documentdb
  - mongodb
---

# Amazon DocumentDB (with MongoDB compatibility)

DocumentDB is a managed document database compatible with MongoDB 4.0/5.0/7.0 APIs. It stores JSON-like documents, supports flexible schemas, and provides fully managed HA with 6-node replica set (3 primary + 3 storage replicas across 3 AZs).

## Core Concepts

### Document Model

```json
{
  "_id": "ObjectId('...')",
  "user_id": "user123",
  "name": {
    "first": "Alice",
    "last": "Smith"
  },
  "email": "alice@example.com",
  "orders": [
    {"order_id": "order-001", "total": 99.99},
    {"order_id": "order-002", "total": 149.99}
  ],
  "created_at": "2024-01-15T10:30:00Z"
}
```

Collections group documents (like SQL tables, but schemaless).

## Creating a Cluster

```bash
aws docdb create-db-cluster \
  --db-cluster-identifier my-docdb \
  --engine docdb \
  --engine-version 5.0.0 \
  --master-username admin \
  --master-user-password SecretPassword \
  --replication-group-id my-docdb-rg \
  --num-cache-verticies 3 \
  --vpc-security-group-ids sg-xxxxx \
  --db-subnet-group-name my-subnet-group \
  --backup-retention-period 3 \
  --preferred-backup-window 03:00-04:00
```

### Add Instance

```bash
aws docdb create-db-instance \
  --db-instance-identifier my-docdb-instance \
  --db-cluster-identifier my-docdb \
  --db-instance-class db.r6g.large \
  --engine docdb
```

## Connecting

```bash
# Get cluster endpoint
aws docdb describe-db-clusters \
  --db-cluster-identifier my-docdb \
  --query 'DBClusters[0].Endpoint'

# Connect with mongosh
mongosh --host my-docdb.xxxxx.us-east-1.docdb.amazonaws.com:27017 \
  --username admin --password SecretPassword \
  --ssl --sslCAFile rds-combined-ca-bundle.pem

# Or via Python (pymongo)
pip install pymongo
```

```python
from pymongo import MongoClient

client = MongoClient(
    "mongodb://admin:password@my-docdb.xxxxx.docdb.amazonaws.com:27017/?ssl=true&ssl_ca_certs=rds-combined-ca-bundle.pem"
)
db = client['mydb']
collection = db['users']

# Insert
collection.insert_one({"name": "Alice", "email": "alice@example.com"})

# Find
user = collection.find_one({"name": "Alice"})
```

## Aggregation Pipeline

```javascript
// Find top customers by total order amount
db.orders.aggregate([
  { $unwind: "$items" },
  { $group: {
      _id: "$customer_id",
      total_spent: { $sum: "$items.price" }
  }},
  { $sort: { total_spent: -1 } },
  { $limit: 10 }
])
```

## Indexes

```javascript
// Create index on email field
db.users.createIndex({ "email": 1 }, { unique: true })

// Create compound index
db.orders.createIndex({ "customer_id": 1, "created_at": -1 })

// Create text index for search
db.products.createIndex({ "description": "text" })

// List indexes
db.users.getIndexes()
```

## Change Streams

Track real-time changes (like DynamoDB Streams):

```javascript
// Open change stream
const change_stream = db.users.watch(
  [],
  { fullDocument: "updateLookup" }
);

change_stream.on('change', (change) => {
  console.log(change);
});
```

Use cases:
- Triggers (update related data on change)
- CDC (change data capture to Kinesis)
- Real-time notifications

## Transactions

DocumentDB supports multi-document ACID transactions (MongoDB 4.0+ compatible):

```javascript
// Start session and transaction
const session = client.startSession();

session.startTransaction({
  readConcern: { level: "snapshot" },
  writeConcern: { w: "majority" }
});

try {
  const db1 = client.db('app');
  const db2 = client.db('audit');

  await db1.collection('accounts').updateOne(
    { _id: 1 },
    { $inc: { balance: -100 } },
    { session }
  );

  await db2.collection('transactions').insertOne(
    { from: 1, to: 2, amount: 100 },
    { session }
  );

  await session.commitTransaction();
} catch (e) {
  await session.abortTransaction();
} finally {
  session.endSession();
}
```

## Sharding

DocumentDB uses shard key for horizontal scaling:

```bash
# Enable sharding (cluster parameter group)
aws docdb modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name my-param-group \
  --parameters '[{
    "ParameterName": "enableSharding",
    "ParameterValue": "true",
    "ApplyMethod": "pending-reboot"
  }]'
```

```javascript
// Shard collection by user_id
sh.shardCollection("app.orders", { "user_id": "hashed" })
```

## Backup and Restore

### Point-in-Time Recovery

Enabled by default (1-35 days retention):

```bash
# Restore to point in time
aws docdb restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier my-docdb \
  --restored-db-cluster-identifier my-docdb-restored \
  --restore-to-time 2024-01-15T10:00:00Z
```

### Snapshot

```bash
# Create snapshot
aws docdb create-db-cluster-snapshot \
  --db-cluster-identifier my-docdb \
  --db-cluster-snapshot-identifier my-snapshot

# Restore from snapshot
aws docdb restore-db-cluster-from-snapshot \
  --db-cluster-identifier my-docdb-restored \
  --snapshot-identifier my-snapshot \
  --engine docdb
```

## Monitoring

```bash
# Key metrics
# DatabaseClusterReplicaLag, DatabaseConnections, CPUUtilization

aws cloudwatch get-metric-statistics \
  --namespace AWS/DocDB \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=my-docdb
```

## Pricing

| Component | Cost |
|-----------|------|
| db.r6g.large | $0.096/hr (~$69/month) |
| db.r6g.xlarge | $0.192/hr (~$138/month) |
| Storage | $0.10/GB/month |
| I/O | $0.20 per million requests |
| Backup | $0.02/GB/month |

## Limits

| Resource | Limit |
|----------|-------|
| Max storage | 64 TB |
| Max instances per cluster | 1 primary + 14 replicas |
| Max databases | 640 |
| Max collections per database | Unlimited |
| Max document size | 16 MB |

## MongoDB vs DocumentDB Compatibility

| Feature | MongoDB | DocumentDB |
|---------|---------|-----------|
| API | Native | MongoDB 4.0/5.0/7.0 |
| Change streams | Yes | Yes |
| Multi-document transactions | Yes | Yes |
| Sharding | Yes | Yes (via cluster parameters) |
| $lookup (joins) | Yes | No (use $graphLookup for limited cases) |
| Geospatial indexes | Yes | Limited |
| Text search | Yes | Yes (basic) |
| Atlas-specific features | No | No |

## References

- **Homepage:** https://aws.amazon.com/documentdb/
- **Documentation:** https://docs.aws.amazon.com/documentdb/
- **Pricing:** https://aws.amazon.com/documentdb/pricing/

## Pricing Examples

**Scenario 1:** A production DocumentDB cluster (1 primary + 1 replica, db.r6g.xlarge). On-Demand: 2 × $0.192/hr × 24 × 30 = $276.48/month. Storage 500GB × $0.10 = $50/month. Total: ~$326/month. Compare to self-managed MongoDB on EC2 (2 × m5.xlarge = $138/month + EBS 500GB = $40/month) = $178/month. DocumentDB is 83% more expensive but fully managed with HA and no ops burden.

**Scenario 2:** A dev DocumentDB cluster (db.r6g.large, single instance). On-Demand: $0.096/hr × 24 × 30 = $69/month. With db.t3.medium (not available in DocumentDB), you'd need at least r6g.large. Stop/start not supported — use `delete-cluster` for dev environments or use DocumentDB Serverless (preview).

## Nuggets & Gotchas

- **DocumentDB doesn't support `$lookup` for cross-collection joins in the same database:** You can use `$graphLookup` for recursive graph queries, but for complex joins, denormalize your data or use application-level joins.
- **DocumentDB change streams require a replica set cluster (not single instance):** If you have a single-instance DocumentDB, change streams won't work. Add at least one replica.
- **DocumentDB's $regex doesn't support case-insensitive regex (i) on indexed fields:** Use text indexes instead. For large collections, consider Elasticsearch or OpenSearch for complex text search.
- **DocumentDB doesn't support MongoDB Atlas-specific features (Charts, Realm, Atlas Search):** If you rely on Atlas Search (Lucene-based full-text), you'll need a different approach in DocumentDB — use `$text` search or external search service.
- **DocumentDB's `instance-hour` billing includes partial hours — a 30-minute use = 1 hour:** Unlike some services that bill per second, DocumentDB rounds up to the nearest hour for instance billing.
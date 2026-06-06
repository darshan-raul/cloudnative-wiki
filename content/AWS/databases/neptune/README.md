---
title: Amazon Neptune
description: Amazon Neptune — managed graph database. Gremlin and SPARQL APIs, property graphs, RDF graphs, knowledge graphs, fraud detection, and real-time recommendations.
tags:
  - aws
  - databases
  - graph
  - neptune
---

# Amazon Neptune

Neptune is a managed graph database for storing and querying highly connected data. It supports two graph models: **Property Graph** (Apache TinkerPop Gremlin) and **RDF** (W3C SPARQL). Use cases include social networks, fraud detection, knowledge graphs, and recommendation engines.

## Graph Models

### Property Graph (Gremlin)

Nodes connected by edges with properties:

```javascript
// Node: Alice
{ name: "Alice", age: 35, email: "alice@example.com" }

// Edge: Alice knows Bob
{ type: "knows", since: 2020 }

// Graph traversal with Gremlin
g.V().has('name', 'Alice').out('knows').has('age', gt(30))
```

### RDF Graph (SPARQL)

Subject-Predicate-Object triples:

```sparql
PREFIX ex: <http://example.org/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>

SELECT ?person ?email
WHERE {
  ?person foaf:name "Alice" .
  ?person foaf:mail ?email .
}
```

## When to Use Neptune

| Use Case | Model | Example |
|----------|-------|---------|
| Social network | Property Graph (Gremlin) | "Friends of friends" queries |
| Fraud detection | Property Graph (Gremlin) | Find suspicious patterns in transactions |
| Knowledge graph | RDF (SPARQL) | Biomedical research, linked data |
| Network/IT ops | Property Graph (Gremlin) | Dependencies, impact analysis |
| Recommendation | Property Graph (Gremlin) | "Users who bought X also bought Y" |

## Creating a Neptune Cluster

```bash
aws neptune create-db-cluster \
  --db-cluster-identifier my-neptune \
  --engine neptune \
  --engine-version 1.2.0.0 \
  --db-cluster-instance-class db.r6g.xlarge \
  --num-instances 3 \
  --storage-encrypted \
  --vpc-security-group-ids sg-xxxxx \
  --db-subnet-group-name my-subnet-group
```

### Serverless

```bash
aws neptune create-db-cluster \
  --db-cluster-identifier my-neptune-serverless \
  --engine neptune \
  --serverless-scaling-configuration '{
    "MinCapacityUnits": 1,
    "MaxCapacityUnits": 5
  }'
```

## Connecting

```bash
# Get cluster endpoint
aws neptune describe-db-clusters \
  --db-cluster-identifier my-neptune \
  --query 'DBClusters[0].Endpoint'

# Connect via Gremlin (Python)
pip install gremlinpython

from gremlin_python import Client

client = Client(
    'wss://my-neptune.xxxxx.neptune.amazonaws.com:8182/gremlin',
    'g'
)

# Add a node
client.submit("g.addV('person').property('name', 'Alice').property('age', 35)")

# Traverse
result = client.submit("g.V().has('name', 'Alice').out('knows').values('name')")
print(list(result))
```

### Using SPARQL

```python
pip install rdflib

from rdflib import Graph

g = Graph()
g.parse("http://example.org/data.ttl")

# SPARQL query
result = g.query("""
  SELECT ?s ?p ?o
  WHERE { ?s ?p ?o }
  LIMIT 10
""")
```

## Gremlin Operations

### Nodes

```javascript
// Add vertex (node)
g.addV('Person').property('name', 'Alice').property('age', 35)

// Add vertex with ID
g.addV('Person').property(T.id, 'alice-id').property('name', 'Alice')

// Get vertex by property
g.V().has('Person', 'name', 'Alice')

// Get all vertices
g.V()

// Delete vertex (and edges)
g.V('alice-id').drop()
```

### Edges

```javascript
// Add edge
g.V('alice-id').addE('knows').to(g.V('bob-id'))

// Add edge with properties
g.V('alice-id').addE('knows').property('since', 2020).to(g.V('bob-id'))

// Traverse edge
g.V('alice-id').outE('knows').inV()

// Get all outgoing edges
g.V('alice-id').outE()

// Get all incoming edges
g.V('alice-id').inE()

// Delete edge
g.E('knows-id').drop()
```

### Traversals

```javascript
// Friends of friends
g.V('alice-id').out('knows').out('knows').dedup()

// Common friends
g.V('alice-id').out('knows').in('knows').where(is(neq('alice-id')))

// Friends older than 30
g.V('alice-id').out('knows').filter(values('age').is(gt(30)))

// Count friends
g.V('alice-id').out('knows').count()
```

## SPARQL Operations

### Triple Patterns

```sparql
# Insert
INSERT DATA {
  ex:Alice a ex:Person ;
             foaf:name "Alice" ;
             foaf:age 35 .
}

# Query
SELECT ?person ?name
WHERE {
  ?person foaf:name ?name .
  ?person foaf:age ?age .
  FILTER (?age > 30)
}

# CONSTRUCT (create new graph)
CONSTRUCT {
  ?person foaf:knows ?friend .
}
WHERE {
  ?person foaf:knows ?friend .
}
```

## Bulk Loading

```bash
# Load from S3 to Neptune (property graph)
aws neptune start-load \
  --source s3://my-bulk-data/ \
  --format CSV \
  --iam-role-arn arn:aws:iam::123456789012:role/neptune-load-role \
  --region us-east-1
```

For Gremlin, use the Bulk Load API or gremlin-python with batching.

## Monitoring

```bash
# Key metrics
# Gremlin Op/sec, SPARQL Query/sec, Gremlin Traversal/sec
# Transactions, AverageCommitTime

aws cloudwatch get-metric-statistics \
  --namespace AWS/Neptune \
  --metric-name GremlinRequestsPerSec
```

Key metrics:
- `GremlinOpLatency` — operation latency
- `NeptuneReplicaLag` — replica lag
- `LanguageRequests` — requests by language (Gremlin vs SPARQL)

## Pricing

| Component | Cost |
|-----------|------|
| db.r6g.xlarge | $0.36/hr (~$259/month) |
| db.r6g.2xlarge | $0.72/hr (~$518/month) |
| Serverless | $0.00006 per capacity unit-second |
| Storage | $0.10/GB/month |

## Limits

| Resource | Limit |
|----------|-------|
| Max storage per cluster | 64 TB |
| Max instances per cluster | 1 primary + 14 replicas |
| Max edges per node | ~100,000 |
| Max labels per node | ~100 |
| Max properties per vertex | ~1,000 |
| Max query timeout | 30 seconds (configurable) |

## References

- **Homepage:** https://aws.amazon.com/neptune/
- **Documentation:** https://docs.aws.amazon.com/neptune/
- **Pricing:** https://aws.amazon.com/neptune/pricing/

## Pricing Examples

**Scenario 1:** A fraud detection system using Neptune (db.r6g.2xlarge, 3 instances, Multi-AZ). On-Demand: 3 × $0.72/hr × 24 × 30 = $1,555/month. Compare to Neo4j Aura (comparable graph DB): db.r6g.2xlarge equivalent = ~$2,400/month. Neptune is 35% cheaper for enterprise graph workloads.

**Scenario 2:** A knowledge graph using Neptune Serverless (1-5 capacity units). Average: 2 capacity units. 2 × $0.00006 × 3600 sec/hr × 24hr × 30 days = $311/month. Compare to provisioned (db.r6g.xlarge): $259/month fixed. Serverless is more expensive but scales for variable workloads.

## Nuggets & Gotchas

- **Neptune doesn't support both Gremlin and SPARQL in the same cluster — you must choose one engine at creation:** If you need both, create two clusters (one Gremlin, one SPARQL) and sync data between them. Choose based on your primary access pattern.
- **Neptune's Gremlin doesn't support all TinkerPop 3.x features — some advanced traversals may not work:** Test your Gremlin queries against Neptune's compatibility matrix. Notably, some folding/unfolding operations and custom predicates are limited.
- **Neptune's SPARQL 1.1 support is read-heavy — update operations use isolated transactions:** Bulk updates (LOAD DATA) are not supported in SPARQL. Use the bulk loader (S3) for large data ingestion.
- **Neptune has a 10GB soft limit on query result size — complex traversals may hit this:** If you're returning millions of nodes, paginate your queries. Use `limit()` and `skip()` to process results in batches.
- **Neptune's replica lag is typically < 1 second but can spike during heavy writes:** Monitor `NeptuneReplicaLag` metric. If lag exceeds 10 seconds, reduce write throughput or add read replicas.
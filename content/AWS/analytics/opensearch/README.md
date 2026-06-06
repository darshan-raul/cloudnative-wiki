---
title: Amazon OpenSearch
description: Amazon OpenSearch — managed search and analytics engine, index architecture, shard planning, dashboards, and security
tags:
  - aws
  - analytics
  - opensearch
---

# Amazon OpenSearch

OpenSearch is a managed search and analytics engine derived from Elasticsearch. It's used for full-text search, log analytics, application monitoring, and security analytics. OpenSearch Service is the AWS-hosted version — you get the OpenSearch engine without managing infrastructure.

## Key Concepts

### Index

An index is a collection of documents that share similar characteristics. It's the equivalent of a database in relational terms. Each index has a name and consists of one or more shards.

### Document

A document is the basic unit of information — a JSON object with fields and values. Documents are stored in indices.

```json
{
  "user_id": "12345",
  "action": "purchase",
  "timestamp": "2024-06-15T10:30:00Z",
  "amount": 99.99,
  "properties": {
    "product": "widget",
    "category": "electronics"
  }
}
```

### Shard

An index is split into shards for horizontal scaling. Each shard is an independent Lucene index.

- **Primary shard:** The original shard that holds data
- **Replica shard:** A copy of the primary shard for redundancy and read scaling

```
Index (5 primary shards, 1 replica each = 10 total shards)
  ├── Shard 1 (primary) → replica Shard 1'
  ├── Shard 2 (primary) → replica Shard 2'
  ├── Shard 3 (primary) → replica Shard 3'
  ├── Shard 4 (primary) → replica Shard 4'
  └── Shard 5 (primary) → replica Shard 5'
```

**Sharding decisions:**
- More shards = more parallel processing = faster indexing and searching
- Each shard has overhead — too many small shards is inefficient
- Rule of thumb: 20-50GB per shard is a good target

## Cluster Architecture

### Nodes

An OpenSearch cluster consists of nodes:

- **Master node:** Controls cluster operations (index creation, shard allocation). Doesn't handle search requests.
- **Data node:** Stores data and handles search/query requests.
- **Coordinating node:** Receives requests, fans out to data nodes, aggregates results. No data storage.
- **UltraWarm node:** For infrequently accessed data — cheaper than hot data nodes but slower to query.
- **Cold node:** For rarely accessed data — lowest cost, slowest queries.

### Storage Tiers

```
Hot tier (data nodes) → UltraWarm → Cold → Frozen (archive)

- Hot: Active, frequently queried data. Highest cost, fastest access.
- UltraWarm: Less active data. Lower cost, search still viable (minutes).
- Cold: Rarely queried. Lowest cost, search takes longer.
- Frozen: Archived data, searchable but very slow (requires rehydration).
```

UltraWarm and Cold nodes significantly reduce storage costs for time-series data that doesn't need sub-second query response.

## Index Management

### Create Index with Mappings

```json
PUT /sales-events
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "refresh_interval": "5s"
  },
  "mappings": {
    "properties": {
      "user_id": { "type": "keyword" },
      "action": { "type": "keyword" },
      "timestamp": { "type": "date" },
      "amount": { "type": "double" },
      "product": { "type": "text", "fields": { "keyword": { "type": "keyword" } } }
    }
  }
}
```

**Field types:**
- `keyword` — exact value matching, sorting, aggregation (not analyzed)
- `text` — full-text search (analyzed, tokenized)
- `date` — ISO 8601 timestamps
- `long`, `double`, `integer` — numeric
- `boolean`, `ip`, `geo_point` — specialized types

### Index Lifecycle Management (ILM)

ILM automates index rotation, archival, and deletion:

```json
PUT /_ilm/policy/sales-policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_size": "50GB",
            "max_age": "7d"
          },
          "set_priority": { "priority": 100 }
        }
      },
      "warm": {
        "min_age": "30d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 },
          "set_priority": { "priority": 50 }
        }
      },
      "cold": {
        "min_age": "90d",
        "actions": {
          "set_priority": { "priority": 0 },
          "allocate": { "require": { "warm_nodes": "zone" } }
        }
      },
      "delete": {
        "min_age": "365d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

**Use with index template:**
```json
PUT /_index_template/sales-template
{
  "index_patterns": ["sales-events-*"],
  "template": {
    "settings": { "number_of_shards": 3 },
    "mappings": { ... },
    "aliases": { "sales-events": {} }
  },
  "ilm": { "policy": "sales-policy" }
}
```

## Querying

### Full-Text Search

```json
POST /sales-events/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "product": "widget" } }
      ],
      "filter": [
        { "range": { "timestamp": { "gte": "2024-06-01", "lte": "2024-06-30" } } },
        { "term": { "action": "purchase" } }
      ]
    }
  },
  "aggs": {
    "revenue_by_day": {
      "date_histogram": { "field": "timestamp", "calendar_interval": "day" },
      "aggs": { "total_amount": { "sum": { "field": "amount" } } }
    }
  }
}
```

### Aggregations

```json
{
  "size": 0,
  "aggs": {
    "top_products": {
      "terms": { "field": "product.keyword", "size": 10 },
      "aggs": {
        "avg_amount": { "avg": { "field": "amount" } },
        "total_revenue": { "sum": { "field": "amount" } }
      }
    },
    "revenue_distribution": {
      "percentiles": { "field": "amount", "percents": [25, 50, 75, 95] }
    }
  }
}
```

## Dashboards (OpenSearch Dashboards)

OpenSearch Dashboards (successor to Kibana) provides visualization and exploration:

**Use cases:**
- Log analytics: Search and filter application logs
- Time-series: Visualize metrics over time with line charts
- Saved searches: Save and share query templates
- Dashboard embedding: Embed charts in other applications via iframe or API

**Index pattern:** You define an index pattern in Dashboards (e.g., `sales-events-*`) to connect to your indices. Dashboards then lets you explore data, create visualizations, and build dashboards.

## Security

### Fine-Grained Access Control (FGAC)

OpenSearch Security plugin provides role-based access control:

```json
{
  "reserved_roles": {
    "all_access": { "index_permissions": ["*"], "cluster_permissions": ["*"] },
    "readall": { "index_permissions": ["read"], "cluster_permissions": ["cluster_composite_ops_ro"] }
  }
}
```

**VPC-based access:** OpenSearch domains deployed in a VPC are accessible only via the VPC endpoint. No public internet access by default.

**Encryption:**
- In transit: TLS (automatically enforced on new domains)
- At rest: AES-256 encryption with KMS

## Direct Query Integration

### Lambda Integration

```python
import boto3
from opensearchpy import OpenSearch

def handler(event, context):
    # Query OpenSearch for analytics
    client = OpenSearch(
        hosts=[{'host': os.environ['ES_HOST'], 'port': 443}],
        http_auth=aws_auth,
        use_ssl=True
    )
    
    result = client.search(
        index='sales-events-*',
        body={
            'query': { 'match_all': {} },
            'aggs': {
                'daily_revenue': {
                    'date_histogram': {
                        'field': 'timestamp',
                        'calendar_interval': 'day'
                    }
                }
            }
        }
    )
    
    return {'revenue': result['aggregations']['daily_revenue']['buckets']}
```

## Performance Tuning

**Shards per node:** Aim for 20-50GB per shard. A 3-node cluster with 100GB data should have 3-5 shards, not 100.

**Refresh interval:** Default is 1s. For high-indexing workloads, increase to 5-10s to reduce indexing overhead.

**Bulk API:** Use the bulk API for ingestion — much more efficient than individual document indexing:
```json
POST /_bulk
{ "index": { "_index": "sales-events" } }
{ "user_id": "123", "action": "purchase", "amount": 99 }
{ "index": { "_index": "sales-events" } }
{ "user_id": "456", "action": "view", "amount": 0 }
```

- Circuit breaker: OpenSearch has memory circuit breakers to prevent OOM. If you're hitting circuit breaker errors, reduce the number of shards, increase memory per node, or optimize your query complexity.

## References

- **Homepage:** https://aws.amazon.com/opensearch-service/
- **Documentation:** https://docs.aws.amazon.com/opensearch/
- **Pricing:** https://aws.amazon.com/opensearch-service/pricing/

## Pricing Examples

**Scenario 1:** A 3-node OpenSearch cluster (m6g.large.search, 1 master + 2 data). 3 × $0.194/hr × 720hr = $418.56/month. Storage: 400GB EBS (gp3) = 400 × $0.08 = $32/month. Total: ~$450/month. For the same workload, Elasticsearch Cloud (2 GB memory, 96GB storage): ~$600/month. OpenSearch is ~25% cheaper.

**Scenario 2:** A log analytics platform: 10GB/day ingestion, 30-day retention = 300GB indexed data. 3 m6g.xlarge.search nodes (3.8TB storage each): 3 × $0.339/hr × 720hr = $732/month. Plus UltraWarm (1,000GB storage): $0.288/GB/month = $288/month. Total: ~$1,020/month. Compare to CloudWatch Logs at $0.50/GB ingestion + $0.03/GB storage = $159/month for ingestion + $9/month storage = $168/month.

## Nuggets & Gotchas

- **UltraWarm/Cold tiers have higher per-query costs:** UltraWarm reads from S3, which has higher latency than local NVMe. Queries on UltraWarm tiers are slower and cost $0.008/GB vs $0.003/GB for hot storage. Design for hot-only where query latency matters.
- **OpenSearch has a 20GB shard size recommendation:** Shards > 20GB cause segment merging overhead and slow recovery. Shards < 500MB waste resources. Target 1-10GB per shard. The num_shards = data_size_gb / shard_size_gb.
- **Master nodes handle cluster management, not search:** If your hot/warm tier has 10 data nodes, a 3-node master tier is sufficient. Putting master-eligible nodes in the data tier causes search latency spikes during cluster management operations.
- **Automated snapshot retention is 14 days:** Snapshots for recovery are stored in a managed S3 bucket and retained for 14 days by default. For longer recovery windows, configure longer retention or store snapshots in your own S3 bucket.
- **T3 instances are burstable and can cause cluster instability:** Under heavy load, T3 instances exhaust their CPU credits and drop to baseline (10% CPU). For production clusters, use M6g or R6g instances. T3 is fine for dev/test only.
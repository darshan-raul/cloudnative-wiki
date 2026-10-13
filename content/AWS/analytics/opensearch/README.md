---
title: "Amazon OpenSearch Service"
description: "OpenSearch indexes documents for search and operational analytics; it is not an authoritative relational database or a generic Boto3 index-query client."
tags:
  - aws/analytics
date: 2026-10-12
---

# Amazon OpenSearch Service

OpenSearch indexes documents for search and operational analytics; it is not an authoritative relational database or a generic Boto3 index-query client. Choose managed domains or Serverless from supported features, ingestion, availability and operational requirements. Prerequisites: [[AWS/analytics/README|analytics]], [[AWS/networking/README|networking]] and [[AWS/security/iam/README|IAM]].

## Index and lifecycle concepts

Documents use mappings/analyzers; shards distribute indexes and replicas provide supported redundancy/search capacity. Shard count, heap and master-node sizing depend on workload/version/architecture—there is no universal ratio that replaces load testing.

OpenSearch lifecycle automation is Index State Management using \_plugins/\_ism, not Elasticsearch \_ilm. Domain storage tiers are hot, UltraWarm and cold, not an invented Frozen tier. Cold indexes must attach to UltraWarm to query. Supported tier/version/domain constraints differ from Serverless collections and should not be generalized.

## Three security layers

First establish network reachability; next evaluate the domain resource policy; then enforce fine-grained access control (FGAC). An IAM-principal domain policy requires SigV4 signing. Internal-user basic authentication is a different identity path and cannot substitute for IAM signing at that policy layer.

Use an authenticated OpenSearch data-plane HTTP client for index/search APIs; boto3.client("opensearch") configures service resources. Roles and role mappings use the owning security-plugin schema, with supported index/cluster permissions. Protect credentials, restrict logs containing sensitive documents and authorize dashboard access independently where required.

## Index/search exercise

Provision a small budgeted sandbox with a supported security configuration. Index a few synthetic events with explicit IDs, query a bounded field/time range and verify exact expected results. Updating a repeated ID demonstrates document overwrite/idempotency rather than indefinite event replay.

Create a read-only principal and verify denied writes/forbidden indexes, not merely successful administrator access. Test one ISM policy in an isolated index and inspect state transitions. Load-test latency, rejected requests, heap and storage rather than adopting guessed shard/master heuristics.

Delete disposable indexes/domain/collection and any retained snapshots/ingestion resources as appropriate. Remember that service resource deletion and S3 snapshot cleanup are separate actions.

## Cost and reliability

Managed domains bill instances/storage plus applicable warm/cold, transfer and optional features; Serverless bills its documented capacity/storage dimensions. There is no universal hot-versus-warm per-query GB tariff. Monitor write/search latency, rejections, storage, heap and cluster health. Use source retention/replay and [[AWS/reliability/backup-and-recovery|recovery planning]] because an index is not automatically the source of truth.

## Index, document and shard model

```text
Index: sales-events
  ├─ primary shard A → replica A
  └─ primary shard B → replica B

Document: explicit ID + JSON source + indexed mapped fields
```

An index groups documents and mappings; a document is not a row with a rigid relational schema unless you deliberately impose one. Each primary shard is a Lucene index. Replicas provide supported redundancy/read capacity, but more shards can add coordination/heap overhead rather than always speed up queries.

Use keyword fields for exact filters/terms aggregation, text fields for analyzed search, date fields for time ranges and numeric fields for totals. Dynamic mapping can infer an unsuitable type from the first input; specify mappings for important datasets.

## Querying and aggregations

The following JSON is a search request body, not an SDK provisioning call. Submit it to the supported /sales-events/\_search endpoint using the configured authenticated data-plane client. It assumes action is mapped as keyword, timestamp as date and amount as numeric.

```json
{
  "size": 0,
  "query": {
    "bool": {
      "filter": [
        { "term": { "action": "purchase" } },
        {
          "range": { "timestamp": { "gte": "2026-10-01", "lt": "2026-11-01" } }
        }
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

Compare search hits with aggregation results and account for timezones, missing fields and eventual refresh visibility. A successful indexing request is not necessarily immediate search visibility. Bound result sizes and paginate using the appropriate search mechanism instead of expecting one response to return all documents.

## Dashboards and operations

Create supported index patterns/data views for the intended dataset, then saved searches and visualizations. Dashboard access does not itself authorize every index; test a read-only user's view and denied mutations. Embedding must preserve authentication/tenant boundaries rather than sharing administrator cookies.

Watch indexing/search latency, rejected operations, storage/free space, heap/GC and cluster health. Diagnose expensive aggregations and mapping explosion before blindly adding shards. Hot/UltraWarm/cold lifecycle depends on supported deployment; cold attachment is a step before query access. Protect snapshots and raw replay sources separately from the searchable index.

## Explicit mapping and refresh behavior

This JSON is an index-creation data-plane request body for a disposable index. Submit through the authorized OpenSearch client/Dev Tools using the actual path; it is not a Boto3 service-domain configuration.

```json
{
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "event_id": { "type": "keyword" },
      "action": { "type": "keyword" },
      "timestamp": { "type": "date" },
      "amount": { "type": "double" },
      "description": { "type": "text" }
    }
  }
}
```

Strict dynamic mapping rejects unexpected fields rather than silently expanding the schema; decide whether this suits ingestion. keyword preserves exact values for filters/aggregations, while text applies analysis for search. Validate numeric/date input and handle rejected documents explicitly.

An index operation acknowledges supported write behavior, while refresh controls when indexed changes become searchable. Do not claim S3-style immediate search consistency. Use supported refresh controls only for bounded tests, balancing visibility against indexing overhead.

## Security and lifecycle troubleshooting comparison

| Observation                              | Investigate                                                        |
| ---------------------------------------- | ------------------------------------------------------------------ |
| Cannot reach endpoint                    | VPC/DNS/routes/security groups/client path                         |
| Reachable but denied                     | Domain resource policy, SigV4/basic-auth path and actual principal |
| Can read but cannot write                | FGAC role/index permissions and mapping/read-only state            |
| Indexing succeeds but search misses data | Refresh, wrong index/query/analyzer and time filters               |
| Lifecycle transition fails               | ISM policy/state, supported tier/prerequisites and error details   |
| Query latency grows                      | Shards/heap/rejections, expensive aggregations and data growth     |

Hot, UltraWarm and cold are supported domain choices with restrictions; no generic Frozen tier is assumed. Cold data must be attached to UltraWarm before querying. Serverless collection capacity/lifecycle is a distinct service model; don't reuse managed-domain node/tier recipes unchanged.

Snapshots and raw replay data protect different recovery paths. Restore a representative index and verify mappings, query results and role access as well as document counts. Dashboard objects and external ingestion/configuration may need their own recovery plan.

## References

- [FGAC, authentication and role examples](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/fgac.html)
- [Index State Management](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ism.html)
- [UltraWarm](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ultrawarm.html)
- [Cold storage](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/cold-storage.html)
- [OpenSearch pricing](https://aws.amazon.com/opensearch-service/pricing/)

## Across the wiki

- [[Linux/observability/journalctl|journalctl]] — host and container logs (Linux)
- [[Kubernetes/eks/observability/logging/pod-logging|Pod Logging on EKS]] — host and container logs (Kubernetes)
- [[Security/siem/elastic-security/README|Elastic Security]] — host and container logs (Security)
- [[Linux/concepts/08-logging|08 — Logging]] — host and container logs (Linux)
- [[AI/inner-workings/embeddings|Embeddings]] — embeddings and search (AI)
- [[Architecture/solution-architecture-concepts/data-architecture/databases/indexing|Indexing]] — embeddings and search (Architecture)
- [[AI/vector-databases|Vector Databases]] — embeddings and search (AI)
- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/README|PostgreSQL]] — embeddings and search (Architecture)

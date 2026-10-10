---
title: Vector Databases
tags: [ai, vector-database, embeddings, similarity-search, rag, pgvector]
date: 2026-10-10
description: How vector search works and how to run it — embeddings and distance metrics, exact versus approximate search, HNSW and IVF, quantization, metadata filtering, hybrid search, choosing between pgvector and a dedicated engine, and operational pitfalls.
---

# Vector Databases

A vector database stores **embeddings** — arrays of numbers that represent the meaning of text, images or other data — and finds the ones closest to a query vector. It is what makes "find documents about this topic" work without matching keywords, and it is the retrieval layer of most [[AI/rag|RAG]] systems.

For what embeddings are and how they are produced, see [[AI/inner-workings/embeddings|embeddings]].

## The problem

Given millions of vectors with hundreds or thousands of dimensions, find the _k_ nearest to a query vector, in milliseconds. Comparing against every vector is exact but too slow at scale, so nearly all systems use **approximate nearest neighbour (ANN)** search: an index that returns almost the right answer much faster.

"Almost" is measured by **recall**: the fraction of the true top-_k_ that the index actually returns. Every ANN index trades recall against speed and memory, and that trade-off is the central tuning decision.

## Distance metrics

| Metric                | Measures                  | Notes                                                               |
| :-------------------- | :------------------------ | :------------------------------------------------------------------ |
| **Cosine similarity** | The angle between vectors | Ignores length. The usual choice for text embeddings.               |
| **Dot product**       | Angle and magnitude       | Identical ranking to cosine when vectors are normalised, and faster |
| **Euclidean (L2)**    | Straight-line distance    | Common for image and some scientific embeddings                     |

Use the metric the embedding model was trained with; the model's documentation states it. Using the wrong one silently degrades results.

## Index types

| Index                                | How it works                                                                   | Strengths                                       | Costs                                                               |
| :----------------------------------- | :----------------------------------------------------------------------------- | :---------------------------------------------- | :------------------------------------------------------------------ |
| **Flat**                             | Compare with every vector                                                      | Exact; no build step                            | Linear in the number of vectors                                     |
| **HNSW**                             | A layered graph; search walks from coarse layers to fine, following neighbours | High recall and low latency; the default choice | Memory-hungry; slow to build; deletes leave tombstones              |
| **IVF**                              | Cluster vectors; search only the nearest clusters                              | Less memory; fast to build                      | Needs training data; recall depends on how many clusters are probed |
| **Disk-based (DiskANN and similar)** | A graph laid out for SSDs, with compressed vectors in memory                   | Billions of vectors on modest RAM               | Higher latency than in-memory HNSW                                  |

HNSW has three parameters worth knowing:

| Parameter         | Effect of raising it                                          |
| :---------------- | :------------------------------------------------------------ |
| `M`               | More links per node: better recall, more memory               |
| `ef_construction` | Better graph quality: slower build                            |
| `ef_search`       | Better recall at query time: slower queries — tune this first |

## Quantization

Vectors are large: a million 1,536-dimension float32 vectors need about 6 GB before any index overhead. Quantization compresses them.

| Technique        | Compression | Idea                                                                  |
| :--------------- | :---------- | :-------------------------------------------------------------------- |
| **Scalar**       | 4×          | Store each dimension as an 8-bit integer instead of a 32-bit float    |
| **Binary**       | 32×         | One bit per dimension; very fast comparison                           |
| **Product (PQ)** | 10–100×     | Split the vector into sub-vectors, replace each with a codebook entry |

The standard recipe is a two-stage search: retrieve candidates using the compressed vectors, then **rescore** the top few hundred with full-precision vectors. That recovers most of the lost accuracy at a fraction of the memory.

Some embedding models are trained so that vectors can be **truncated** to fewer dimensions with graceful loss (Matryoshka embeddings), which is another lever for cost.

## Filtering

Real queries are rarely "nearest to this vector". They are "nearest to this vector **among documents this user may see, from the last year, in English**". Combining ANN search with metadata filters is harder than it looks:

| Strategy                | How                                                    | Problem                                          |
| :---------------------- | :----------------------------------------------------- | :----------------------------------------------- |
| **Post-filtering**      | Search first, then drop results that fail the filter   | A selective filter can leave few or zero results |
| **Pre-filtering**       | Filter first, then search exactly within the survivors | Slow when the filtered set is large              |
| **Filtered / in-graph** | The index traversal itself respects the filter         | The right answer; quality varies between engines |

Test your actual filters. An engine that is excellent at unfiltered search can be poor with a filter that matches 1% of the data. For **multi-tenant** applications, partition by tenant (separate namespaces, partitions or collections) rather than relying on a filter — it is faster and it makes cross-tenant leaks structurally impossible.

## Hybrid search

Embeddings capture meaning and miss exact tokens: product codes, error strings, names, rare terms. Keyword search (BM25) does the opposite. **Hybrid search** runs both and merges the rankings, commonly with reciprocal rank fusion, and often feeds the merged candidates to a **reranker** — a slower, more accurate model that reorders the top results.

For most document search, hybrid plus reranking beats pure vector search noticeably. See [[AI/rag|RAG architecture]] for the retrieval pipeline.

## Choosing a system

| Option                                                        | Choose when                                                                                                                                                    |
| :------------------------------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **pgvector** (PostgreSQL extension)                           | You already run Postgres and have up to tens of millions of vectors. Vectors live next to relational data, with transactions, joins and one system to operate. |
| **OpenSearch / Elasticsearch**                                | You already run it, or hybrid keyword-plus-vector search is the core requirement                                                                               |
| **Dedicated engines** — Qdrant, Weaviate, Milvus              | Very large collections, demanding filtered search, or advanced quantization and multi-vector features                                                          |
| **Managed services** — Pinecone, cloud-provider vector stores | You want no operations and usage-based pricing                                                                                                                 |
| **Embedded libraries** — FAISS, LanceDB, sqlite-vec           | Local, offline or in-process use; prototypes; batch jobs                                                                                                       |

Start with what you already operate. Adding `pgvector` to an existing [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/README|PostgreSQL]] database is usually the right first step: it supports HNSW and IVFFlat indexes, half-precision and binary vectors, and filtering with ordinary SQL.

```sql
CREATE EXTENSION vector;

CREATE TABLE chunks (
  id        bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL,
  content   text NOT NULL,
  embedding vector(1024)
);

CREATE INDEX ON chunks USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

SET hnsw.ef_search = 100;

SELECT id, content, 1 - (embedding <=> $1) AS similarity
FROM chunks
WHERE tenant_id = $2
ORDER BY embedding <=> $1      -- <=> is cosine distance
LIMIT 10;
```

Move to a dedicated engine when you can name the limit you have reached: index build time, memory, filtered-search recall, or query throughput. General guidance on that decision is in [[Architecture/solution-architecture-concepts/data-architecture/databases/README|choosing a database]].

## Operating it

- **Measure recall on your own data.** Compute exact results for a sample of queries with a flat search and compare with the index. Benchmarks on public datasets do not transfer.
- **The embedding model is part of the schema.** Vectors from different models, or different versions of one model, are not comparable. Changing models means re-embedding everything; store the model name and version with each vector and plan for a dual-index migration.
- **Embed queries and documents the way the model expects.** Some models need different prefixes or task types for each.
- **Memory drives cost.** In-memory HNSW over full-precision vectors is expensive; quantization and disk-based indexes are how large collections stay affordable.
- **Updates and deletes degrade graph indexes** over time. Schedule compaction or periodic rebuilds.
- **Index builds are slow** and resource-intensive. Build concurrently, and off-peak.
- **Access control belongs in the retrieval query**, not in the prompt. A model cannot be trusted to withhold a document it was given.
- **Embeddings are sensitive data.** Text can be partially reconstructed from them; protect them like the source.

## Do you need one?

Not always. For a few thousand documents, a flat in-memory search is exact and fast. For small corpora that fit in a model's context window, sending the whole thing can beat retrieval. And for many search problems, well-tuned keyword search is a strong baseline that should be measured first. Vector search earns its place when queries and documents use different words for the same thing.

## Related

- [[AI|AI hub]]
- [[AI/rag-in-production|RAG in production]]
- [[AI/evals|Evaluating LLM systems]] — retrieval metrics
- [[Architecture/solution-architecture-concepts/data-architecture/databases/indexing|Database indexing]]
- [[Kubernetes/eks/observability/opensearch|OpenSearch on AWS]]

## Across the wiki

- [[AWS/analytics/opensearch/README|Amazon OpenSearch]] — embeddings and search (AWS)

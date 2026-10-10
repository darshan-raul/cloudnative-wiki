---
title: RAG in Production
tags: [ai, rag, retrieval, production, llm]
date: 2026-10-10
description: What it takes to run retrieval-augmented generation reliably — the ingestion pipeline, freshness and deletion, access control, diagnosing bad answers by stage, grounding and citations, cost and latency, observability, and when RAG is the wrong approach.
---

# RAG in Production

A RAG demo takes an afternoon: split some documents, embed them, retrieve the top five, paste them into a prompt. A RAG system that people trust takes much longer, and almost none of the extra work is about the language model. It is data engineering, search quality, access control and measurement.

This note assumes the techniques in [[AI/rag|RAG architecture]] — chunking, hybrid search, reranking, query transformation — and covers what surrounds them.

## Two pipelines, not one

```
INGESTION (offline, continuous)
 sources ─► extract ─► clean ─► chunk ─► enrich ─► embed ─► index
 (wiki, tickets,  (PDF, HTML,            (titles, dates,     (vector + keyword
  docs, code)      tables, OCR)           ACLs, summaries)    + metadata)

QUERY (online, per request)
 question ─► rewrite ─► retrieve ─► rerank ─► assemble context ─► generate ─► cite ─► respond
              (with       (hybrid,    (cross-    (order, dedupe,    (grounded
               history)    filtered)   encoder)   token budget)      prompt)
```

Most quality problems are created in the top pipeline and only noticed in the bottom one.

## Ingestion is where quality is decided

**Extraction.** Garbage in, garbage retrieved. PDFs lose reading order, tables become word soup, headers and footers repeat on every page, scanned documents need OCR. Inspect extracted text by eye before doing anything else. For tables, figures and complex layouts, layout-aware parsers or vision-capable models are worth the cost.

**Chunking.** Respect the document's structure: split on headings and paragraphs, keep tables and code blocks whole, and carry the section path with each chunk. A chunk that reads "It is enabled by default" is useless without knowing what "it" is.

**Contextual enrichment.** Prepend each chunk with a short, model-generated description of where it sits in the document before embedding and keyword-indexing it. This single step fixes many "the right chunk exists but was not retrieved" failures.

**Metadata.** Store source, title, URL, section, author, timestamps, language, document type and access-control attributes with every chunk. Filters and citations depend on it.

**Idempotent and incremental.** Give each chunk a stable ID derived from the document and its position, and hash the content. Re-ingesting an unchanged document should do nothing; a changed document should replace exactly its own chunks.

## Freshness and deletion

A stale index answers confidently from documents that are no longer true.

- **Sync on change**, not on a monthly schedule: webhooks, [[Architecture/solution-architecture-concepts/migration-patterns/change-data-capture|change data capture]], or frequent incremental crawls.
- **Propagate deletions.** When a document is removed or a person asks for their data to be erased, its chunks and embeddings must go too. Orphaned chunks are a correctness and a compliance problem.
- **Handle versions.** Decide whether superseded documents are deleted, down-ranked or filtered, and record `valid_from` dates so "current policy" queries can prefer the newest.
- **Monitor lag** between a source change and its appearance in the index, like any other data pipeline.

## Access control

The model must never see a document the requesting user may not read. Instructions in the prompt are not a control; the only safe place to enforce permissions is **the retrieval query**.

| Approach              | How                                                                                  |
| :-------------------- | :----------------------------------------------------------------------------------- |
| Filter at query time  | Store ACL attributes (groups, tenant) on each chunk; filter with the user's identity |
| Partition per tenant  | Separate indexes or namespaces — strongest isolation for multi-tenant products       |
| Check after retrieval | Re-verify each candidate against the source system; slower, always current           |

Keep permissions in sync with the source — a revoked permission must take effect promptly. Also remember that the index contains a copy of the content and that embeddings can leak it; protect both as you would the originals. See [[AI/vector-databases|vector databases]] and [[Architecture/solution-architecture-concepts/software-engineering-concepts/multi-tenancy|multi-tenancy]].

Retrieved documents are also an **injection surface**: a document can contain text aimed at the model. Treat retrieved content as data, and limit what the answering model is able to do — [[AI/prompt-injection|prompt injection]].

## Diagnosing a bad answer

Do not start by editing the prompt. Find the stage that failed.

| Question to ask                                  | If the answer is no                                                      |
| :----------------------------------------------- | :----------------------------------------------------------------------- |
| Does the information exist in the corpus at all? | A **coverage** gap. The system should say it does not know.              |
| Was it extracted and chunked intact?             | An **ingestion** problem: fix parsing or chunk boundaries.               |
| Was the right chunk in the top 50 candidates?    | A **retrieval** problem: query rewriting, hybrid search, enrichment.     |
| Was it in the final handful passed to the model? | A **ranking** problem: add or tune a reranker; raise _k_.                |
| Did the model use it correctly?                  | A **generation** problem: prompt, context ordering, or model capability. |

Log the retrieved chunk IDs and scores for every request so that this check takes a minute. The same breakdown structures the metrics in [[AI/evals|evaluating LLM systems]]: retrieval recall and ranking on one side, faithfulness and relevance on the other.

## Grounding and honesty

- **Instruct the model to answer only from the supplied context**, and to say so when the context is insufficient. Test that it actually declines.
- **Require citations.** Have the model reference the chunk each claim comes from, and render them as links. Citations let users verify, and make failures visible.
- **Verify citations** in code: the cited chunk must be one that was supplied, and ideally a quoted span must appear in it.
- **Calibrate "I don't know".** A retrieval score threshold below which the system declines is crude but effective.
- **Put the context first and the question last** in long prompts, and wrap each document in clear delimiters with its metadata.

## Conversations

Follow-up questions ("and what about for contractors?") are not self-contained. Rewrite the latest message into a standalone query using the conversation history before retrieving. Decide what happens to earlier retrieved context — carrying everything forward bloats the prompt, so usually only the rewritten query and a short summary continue.

## Latency and cost

| Stage               | Typical share          | Levers                                                                                    |
| :------------------ | :--------------------- | :---------------------------------------------------------------------------------------- |
| Query rewriting     | A small model call     | Skip it for first-turn or clearly standalone queries                                      |
| Embedding the query | Tens of milliseconds   | Cache; batch                                                                              |
| Retrieval           | Tens of milliseconds   | Index tuning, quantization                                                                |
| Reranking           | Tens to hundreds of ms | Rerank fewer candidates; a smaller reranker                                               |
| Generation          | Dominant               | Fewer, better chunks; a smaller model for easy queries; **streaming**; **prompt caching** |

Streaming the answer changes perceived latency more than any optimisation. Cache at several levels — embeddings, retrieval results for popular queries, and the stable prefix of the prompt. On the ingestion side, embedding the corpus is a one-time cost per model; use batch APIs for it.

More retrieved context is not better: irrelevant chunks cost tokens and distract the model. Find the smallest _k_ that keeps recall.

## Observability

Trace every request end to end: the original and rewritten query, retrieved IDs with scores, reranked order, the final prompt, the answer, citations, tokens, latency and cost per stage. With that you can replay failures and build eval sets from production. Model calls and retrieval steps fit naturally as spans — [[Observability/tracing|distributed tracing]].

Dashboards worth having: answer rate versus decline rate, retrieval score distribution, feedback by topic, zero-result queries, ingestion lag, and cost per answer. Review low-scoring and thumbs-down conversations weekly; that reading is where improvements come from.

## Beyond basic RAG

| Technique                              | Idea                                                                           | Worth it when                                             |
| :------------------------------------- | :----------------------------------------------------------------------------- | :-------------------------------------------------------- |
| **Agentic retrieval**                  | The model decides what to search for, reads results, and searches again        | Multi-hop questions; several sources with different tools |
| **Query decomposition**                | Split a complex question into sub-questions                                    | Comparisons and multi-part questions                      |
| **Parent-document retrieval**          | Search small chunks, return the larger section around the hit                  | Precise matching with enough surrounding context          |
| **Graph RAG**                          | Extract entities and relations; retrieve via the graph and community summaries | Questions about a whole corpus: themes, connections       |
| **Text-to-SQL / structured retrieval** | Query a database instead of documents                                          | The answer is in tables, not prose                        |

Agentic retrieval is increasingly the default for hard questions, with search exposed as a tool — see [[AI/agents|agents]].

## When RAG is the wrong tool

| Situation                                               | Better approach                                                        |
| :------------------------------------------------------ | :--------------------------------------------------------------------- |
| The whole corpus fits comfortably in the context window | Put it in the prompt, with prompt caching                              |
| The answer requires computing over structured data      | Query the database or run code                                         |
| You need a consistent style, format or behaviour        | Prompting, examples, or [[AI/inner-workings/fine-tuning\|fine-tuning]] |
| Questions need aggregation over thousands of documents  | Offline summarisation, analytics, or graph approaches                  |
| Users want to find documents, not get answers           | Plain search                                                           |

## Checklist

- [ ] Extraction quality inspected by eye for each source type
- [ ] Structure-aware chunking with section context and metadata
- [ ] Incremental, idempotent ingestion with deletion propagation
- [ ] Permissions enforced in the retrieval query
- [ ] Hybrid retrieval and reranking, measured on your own queries
- [ ] Grounded answers with verified citations and a tested "I don't know"
- [ ] Per-stage tracing, and an eval set built from real failures
- [ ] A plan for changing the embedding model

## Related

- [[AI|AI hub]]
- [[AI/rag|RAG architecture]]
- [[AI/vector-databases|Vector databases]]
- [[AI/evals|Evaluating LLM systems]]
- [[AI/aws/bedrock|Amazon Bedrock]] — managed knowledge bases

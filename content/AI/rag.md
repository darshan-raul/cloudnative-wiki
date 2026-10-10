---
title: Retrieval-Augmented Generation (RAG) Architecture
description: Deep architectural guide to Retrieval-Augmented Generation (RAG) — chunking strategies, vector databases, hybrid search (BM25 + Dense), cross-encoder re-ranking, and Ragas evaluation
tags:
  - ai
  - llm
  - rag
  - vector-search
  - embeddings
date: 2026-01-30
---

# Retrieval-Augmented Generation (RAG) Architecture

**Retrieval-Augmented Generation (RAG)** is the architectural pattern of dynamically retrieving relevant external context from private or real-time data sources and injecting it into the Large Language Model's (LLM) prompt window prior to generation.

```mermaid
flowchart LR
    User([User Query]) --> PreProc[Query Pre-Processing<br/>HyDE / Multi-Query Expansion]

    subgraph Retrieval Pipeline
        PreProc --> Dense[Dense Vector Search<br/>HNSW / Cosine Similarity]
        PreProc --> Sparse[Sparse Keyword Search<br/>BM25 Full-Text]
        Dense --> RRF[Reciprocal Rank Fusion<br/>Hybrid Merge]
        Sparse --> RRF
        RRF --> Reranker[Cross-Encoder Reranker<br/>Cohere / BGE-Reranker]
    end

    Reranker --> Augment[Context Window Assembly]
    Augment --> LLM[Large Language Model<br/>Claude / GPT-4 / Llama 3]
    LLM --> Response([Grounded Response + Citations])
```

---

## 1. Why RAG Outperforms Fine-Tuning for Enterprise Knowledge

| Dimension               | Standard Pre-Trained LLM               | Fine-Tuning                                   | Retrieval-Augmented Generation (RAG)                         |
| :---------------------- | :------------------------------------- | :-------------------------------------------- | :----------------------------------------------------------- |
| **Knowledge Recency**   | Fixed at training cutoff date          | Fixed at fine-tuning epoch date               | **Real-time (immediate updates on document save)**           |
| **Hallucination Risk**  | High                                   | Moderate (memorization leakage)               | **Extremely Low (anchored strictly to retrieved citations)** |
| **Data Access Control** | Impossible (all data baked in weights) | Difficult (requires training separate models) | **Granular (enforce document-level ACLs before search)**     |
| **Compute Cost**        | High API token cost                    | Very Expensive ($$$ GPU fine-tuning runs)     | **Low (commodity vector database query)**                    |
| **Explainability**      | Zero citations                         | Zero citations                                | **Direct source document and page number citations**         |

---

## 2. Document Ingestion & Chunking Strategies

The quality of a RAG pipeline is constrained by the quality of its chunks. Chunking too small loses semantic context; chunking too large dilutes the vector embedding.

### 1. Fixed-Size Chunking with Overlap

- Splits text into fixed character or token counts (e.g. 500 tokens with 50-token overlap).
- _Downside:_ Frequently cuts across sentences, paragraphs, code blocks, or table structures.

### 2. Recursive Character Chunking

- Splits hierarchically on markdown/prose boundaries: `["\n\n", "\n", " ", ""]`.
- Preserves paragraph integrity whenever possible.

### 3. Semantic Chunking

- Measures cosine similarity between consecutive sentences.
- Places a chunk boundary whenever the similarity drops below a statistical threshold (indicating a topical transition).

### 4. Document-Structure Aware (Hierarchical Chunking)

- Parses Markdown headings (`#`, `##`, `###`) or PDF bounding boxes.
- Associates child chunks (paragraphs) with their parent section titles to preserve context.

---

## 3. Hybrid Search: Dense + Sparse (BM25)

Dense vector search (embeddings) understands semantic concepts (e.g., matching "automobile" to "car"), but frequently fails on:

- Exact part numbers (`CRX-990-B`)
- Acronyms and internal codenames (`PROMETHEUS-V2`)
- Exact error codes (`FATAL_0x8812A`)

### The Solution: Hybrid Search with Reciprocal Rank Fusion (RRF)

Run dense vector search and sparse keyword search (BM25) concurrently, then rank candidates using RRF:

$$\text{RRF Score}(d) = \sum_{m \in M} \frac{1}{k + r_m(d)}$$

where $k \approx 60$ and $r_m(d)$ is the rank of document $d$ in system $m$.

---

## 4. Re-Ranking (Cross-Encoders)

Bi-encoders (embedding models) compare documents fast ($O(1)$ dot product via HNSW index), but compress complex paragraphs into single 1536-dimensional vectors, losing subtle relational nuances.

A **Cross-Encoder Reranker** processes the query and candidate chunk simultaneously through a full transformer attention layer, computing a precise relevance score:

```
Step 1: Hybrid Retrieval retrieves top 50 candidates (Fast Bi-Encoder + BM25)
Step 2: Cross-Encoder Reranker (e.g. Cohere Rerank / BGE-Reranker-Large) scores top 50
Step 3: Select only the top 5 highest-confidence chunks for the prompt window
```

---

## 5. Query Transformation Techniques

1. **Hypothetical Document Embeddings (HyDE):** The LLM generates a hypothetical answer to the query first. The embedding of this hypothetical answer is used for vector search, dramatically bridging the vocabulary gap between short questions and rich documents.
2. **Multi-Query Expansion:** The LLM generates 3 variations of the user's question from different perspectives, retrieves candidate sets for all three, and deduplicates.
3. **Step-Back Prompting:** Generates a broader, more abstract conceptual question before querying.

---

## 6. Production Implementation: Python & LangChain

```python
import os
from langchain_community.vectorstores import PGVector
from langchain_openai import OpenAIEmbeddings, ChatOpenAI
from langchain.retrievers import ContextualCompressionRetriever
from langchain.retrievers.document_compressors import CohereRerank
from langchain.chains import create_retrieval_chain
from langchain.chains.combine_documents import create_stuff_documents_chain
from langchain_core.prompts import ChatPromptTemplate

# 1. Connect to Vector Store (pgvector)
embeddings = OpenAIEmbeddings(model="text-embedding-3-small")
vectorstore = PGVector(
    connection_string="postgresql+psycopg://user:pass@localhost:5432/ragdb",
    embedding_function=embeddings,
    collection_name="enterprise_wiki"
)

# 2. Base Retriever with Hybrid Search
base_retriever = vectorstore.as_retriever(search_kwargs={"k": 20})

# 3. Add Cross-Encoder Reranker
compressor = CohereRerank(model="rerank-english-v3.0", top_n=5)
compression_retriever = ContextualCompressionRetriever(
    base_compressor=compressor,
    base_retriever=base_retriever
)

# 4. Prompt Assembly with Citations
prompt = ChatPromptTemplate.from_template("""
You are an expert platform architect. Answer the question using ONLY the provided context.
Cite the source file and line numbers for every claim. If you don't know, say you don't know.

<context>
{context}
</context>

Question: {input}
Answer:
""")

llm = ChatOpenAI(model="gpt-4o", temperature=0.0)
doc_chain = create_stuff_documents_chain(llm, prompt)
rag_chain = create_retrieval_chain(compression_retriever, doc_chain)

# 5. Query Execution
response = rag_chain.invoke({"input": "What are the requirements for OAuth 2.1 PKCE?"})
print(response["answer"])
```

---

## 7. Evaluating RAG: The Ragas Metric Framework

Do not evaluate RAG using anecdotal eye-tests. Use **Ragas (Retrieval Augmented Generation Assessment)**:

1. **Faithfulness (Generation Quality):** Is every statement in the generated answer supported by the retrieved context? (Catches hallucinations).
2. **Answer Relevance (Generation Quality):** Does the answer directly address the user's question?
3. **Context Precision (Retrieval Quality):** Are all relevant chunks ranked near the top of the context window?
4. **Context Recall (Retrieval Quality):** Did the retriever fetch all facts necessary to answer the question?

## Across the wiki

- [[AWS/machine-learning/bedrock/README|Amazon Bedrock]] — generative AI platforms (AWS)
- [[AWS/machine-learning/sagemaker/README|Amazon SageMaker]] — generative AI platforms (AWS)
- [[AWS/machine-learning/ai-services/README|AWS AI Services]] — generative AI platforms (AWS)
- [[AWS/serverless/README|AWS Serverless]] — generative AI platforms (AWS)

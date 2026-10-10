---
title: AI
tags:
  [ai, ml, llm, genai, rag, langchain, langgraph, prompt-engineering, agents]
date: 2026-09-06
description: "Artificial Intelligence, Machine Learning, and Generative AI: LangChain, LangGraph multi-agent systems, RAG, prompt engineering, local model serving, and cloud AI infrastructure."
---

# AI 🤖

Artificial Intelligence, Large Language Models (LLMs), Agentic Architectures, and Generative AI systems.

---

## 1. Multi-Agent Systems & Orchestration

Production-grade curricula on agentic workflows and LLM orchestration:

### 🕸️ [[AI/langgraph/README|LangGraph Architecture Curriculum]]

Comprehensive 12-part deep dive on cyclic graphs, persistent memory, and agent orchestration:

- [[AI/langgraph/01-mental-model|01 — Mental Model]] — StateGraph, nodes, and edges
- [[AI/langgraph/02-state-and-reducers|02 — State & Reducers]] — Schema definition, channels, and operator reducers
- [[AI/langgraph/03-nodes-and-edges|03 — Nodes & Edges]] — Conditional routing, START, and END nodes
- [[AI/langgraph/04-tools-and-routing|04 — Tools & Routing]] — `ToolNode`, tool calling, and dynamic routing
- [[AI/langgraph/05-command-and-interrupts|05 — Command & Interrupts]] — Dynamic graph mutations and control flow
- [[AI/langgraph/06-subgraphs|06 — Subgraphs]] — Hierarchical multi-agent compositions
- [[AI/langgraph/07-streaming|07 — Streaming]] — Token streaming (`messages` mode) and state updates (`values` mode)
- [[AI/langgraph/08-checkpointers|08 — Checkpointers & Persistence]] — MemorySaver, Postgres, and time-travel debugging
- [[AI/langgraph/09-memory-store|09 — Memory Store]] — Cross-thread memory and semantic recall
- [[AI/langgraph/10-human-in-the-loop|10 — Human-in-the-Loop]] — Breakpoints, approvals, and state edits
- [[AI/langgraph/11-production|11 — Production Deployment]] — LangGraph Cloud, async queues, and resilience
- [[AI/langgraph/12-testing|12 — Testing & Evaluation]] — Unit testing agents and deterministic fixtures

### 🦜 [[AI/langchain/README|LangChain Core Framework]]

- [[AI/langchain/01-mental-model|01 — Mental Model]] — Chains, components, and LCEL
- [[AI/langchain/02-messages|02 — Message Architecture]] — System, Human, AI, and Tool messages
- [[AI/langchain/03-chat-models|03 — Chat Models]] — Providers, parameters, and invocation
- [[AI/langchain/04-tools|04 — Tool Calling]] — Pydantic tool definitions and validation
- [[AI/langchain/05-prompts|05 — Prompt Templates]] — ChatPromptTemplate and message placeholders
- [[AI/langchain/06-runnables-lcel|06 — Runnables & LCEL]] — Composition with `|`, batching, and parallel execution
- [[AI/langchain/07-memory-callbacks|07 — Memory & Callbacks]] — Observability hooks and tracing
- [[AI/langchain/08-langgraph-intro|08 — LangGraph Intro]] — Transition from LCEL chains to cyclic graphs
- [[AI/langchain/09-streaming|09 — Streaming]] — SSE streaming events
- [[AI/langchain/10-testing|10 — Testing]] — Unit testing LCEL chains

---

## 2. Core Concepts & Inner Workings

- **[[AI/inner-workings/README|AI Inner Workings Hub]]** — How transformers and foundation models work
- **[[AI/ai-ml-genai-whats-the-difference|AI vs ML vs GenAI]]** — Core distinctions and taxonomy
- **[[AI/inner-workings/whats-a-t-in-gpt|What is the 'T' in GPT?]]** — Self-attention, multi-head attention, and transformer encoders/decoders
- **[[AI/inner-workings/embeddings|Embeddings & Vector Representations]]** — High-dimensional latent space and cosine similarity
- **[[AI/inner-workings/fine-tuning|Fine-Tuning]]** — SFT, LoRA, QLoRA, and parameter-efficient tuning
- **[[AI/inner-workings/reinforcement-learning-with-human-feedback|RLHF & Alignment]]** — Reward models and PPO/DPO
- **[[AI/prompt-engineering/prompt-engineering-patterns|Prompt Engineering Patterns]]** — Few-shot, chain-of-thought, ReAct, and system instructions

---

## 3. RAG, Agents & Standards

- **[[AI/agents|AI Agents]]** — The agent loop, tool design, workflows versus agents, context management, guardrails
- **[[AI/evals|Evaluating LLM Systems]]** — Datasets, code and model graders, offline and online evaluation, metrics for RAG and agents
- **[[AI/rag|Retrieval-Augmented Generation (RAG)]]** — Advanced RAG pipelines, chunking, hybrid search, and re-ranking
- **[[AI/rag-in-production|RAG in Production]]** — Ingestion, freshness, access control, diagnosing bad answers, cost and latency
- **[[AI/vector-databases|Vector Databases]]** — ANN indexes, quantization, filtering, hybrid search, pgvector versus dedicated engines
- **[[AI/mcp|Model Context Protocol (MCP)]]** — Standardized client-server protocol for connecting AI agents to tools and data
- **[[AI/mcp-in-production|MCP in Production]]** — Transports, OAuth authorization, tool design, security threats, deployment
- **[[AI/prompt-injection|Prompt Injection & Jailbreaks]]** — Security risks, indirect injection, and mitigation guardrails

---

## 4. Local AI & Cloud Infrastructure

- **[[AI/run-locally/ollama-best-practices|Running AI Locally (Ollama)]]** — Local inference, quantization (GGUF), model pulling, and GPU acceleration
- **[[AI/aws/README|AWS AI Services Hub]]** — Cloud machine learning and generative AI
- **[[AI/aws/sagemaker/README|Amazon SageMaker]]** — Managed training, endpoints, and inference options
- **[[AI/aws/bedrock|Amazon Bedrock]]** — Foundation models, Knowledge Bases, and Guardrails

---

## Related Knowledge Bases

- ☸️ **[[Kubernetes/concepts/L06-scheduling-scaling/14-extended-resources|Kubernetes GPU Scheduling]]** — DRA, GPU node pools, and vLLM on K8s
- ☁️ **[[AWS/compute/ec2/README|AWS GPU Compute]]** — P4d/P5 instances, Trainium, and Inferentia
- 🔷 **[[Azure/compute/aks/gpu-orchestration-ai|Azure AKS GPU Infrastructure]]** — InfiniBand, NVIDIA H100/H200, and KubeRay
- 🐧 **[[Linux/kernel/README|Linux Kernel & Drivers]]** — NVIDIA CUDA drivers, NUMA, and sysctl tuning

## Further reading

- [Is AI going to take our jobs? (video)](https://youtu.be/UqYSaAuKwjU)
- [Is AI going to take our jobs? (video)](https://youtu.be/iTjYuHDNooM)
- [GenAI/LLMS: Basics (video)](https://youtu.be/2IK3DFHRFfw)
- [GenAI/LLMS: Basics (video)](https://www.youtube.com/watch?v=zjkBMFhNj_g)
- [Future with AI (video)](https://www.youtube.com/watch?v=SMnH3obzCDk)
- [Future with AI (video)](https://www.youtube.com/watch?v=eUIPFRNxDV8)
- [Future with AI (video)](https://youtu.be/ieH5ZNI1iS0)
- [Is SAAS dead? (video)](https://youtu.be/GuqAUv4UKXo)
- [Jobs — stackoverflow.blog](https://stackoverflow.blog/2024/06/10/generative-ai-is-not-going-to-build-your-engineering-team-for-you/)

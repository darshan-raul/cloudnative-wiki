---
title: LangChain
tags:
  - AI
  - LangChain
  - LCEL
---

# LangChain

LangChain is a framework for building LLM applications. It provides
abstractions for prompts, chat models, tools, memory, and
composition. This section teaches LangChain from first principles,
building concepts slowly before putting them together.

---

## Learning path

Read these in order. Each file builds on the previous one.

| # | File | What you learn |
|---|---|---|
| 1 | [[01-mental-model]] | What LangChain solves, the four core concepts (messages, models, tools, runnables), chains vs agents |
| 2 | [[02-messages]] | The five message types (`SystemMessage`, `HumanMessage`, `AIMessage`, `ToolMessage`, `AIMessageChunk`), the alternation invariant, `RemoveMessage` |
| 3 | [[03-chat-models]] | `ChatOpenAI`, `bind_tools`, `with_structured_output`, `with_retry`, `with_fallbacks`, provider kwargs |
| 4 | [[04-tools]] | `@tool` decorator, schema from type annotations, docstrings as API contract, async tools, error handling, `InjectedToolArg` |
| 5 | [[05-prompts]] | `ChatPromptTemplate`, the four slot types, `MessagesPlaceholder`, `partial`, few-shot, RAG context placement |
| 6 | [[06-runnables-lcel]] | The `Runnable` interface, the `|` operator (LCEL), `RunnableParallel`, `RunnableBranch`, `RunnableWithFallbacks`, `RunnableConfig` |
| 7 | [[07-memory-callbacks]] | `set_llm_cache`, `BaseCallbackHandler`, the hook lifecycle, LangSmith tracing, why legacy memory classes are deprecated |
| 8 | [[08-langgraph-intro]] | `StateGraph`, nodes, edges, `ToolNode`, checkpointers (`MemorySaver`, `SqliteSaver`), `Command`, interrupts |
| 9 | [[09-streaming]] | `stream`/`astream`, `astream_events` (full lifecycle API), building a streaming chat UI, `batch`/`abatch` |
| 10 | [[10-testing]] | `FakeListChatModel`, `FakeMessagesListChatModel`, testing the graph, no-network discipline, `patch_langchain_environment` |

---

## Prerequisites

- Python 3.11+
- An OpenAI-compatible API endpoint (OpenAI, Anthropic via LiteLLM,
  AWS Bedrock via LiteLLM, or local Ollama)

```toml
# pyproject.toml
dependencies = [
    "langchain-core>=0.3",
    "langchain-openai>=0.3",
    "langgraph>=0.2",
]
```

---

## The progression

```
01-mental-model        ← start here
       ↓
02-messages            ← the atom everything uses
       ↓
03-chat-models         ← call a model, get back AIMessage
       ↓
04-tools               ← model can call functions
       ↓
05-prompts             ← template the messages list
       ↓
06-runnables-lcel      ← compose with |
       ↓
07-memory-callbacks    ← cache, observe, trace
       ↓
08-langgraph-intro     ← agent loop (the goal)
       ↓
09-streaming           ← token-by-token output
       ↓
10-testing             ← test without paying
```

By the end, you can build a full agent: a graph with a `call_model`
node, a `ToolNode`, checkpointing for conversation persistence, and
a streaming UI.

---

## What this section is NOT

This is not the LangChain documentation. It is a learner's guide.
Every concept is introduced from scratch, with simple examples
that don't reference a specific project. The focus is on building
mental models, not API signatures.

For the authoritative docs, see [python.langchain.com](https://python.langchain.com/docs/introduction/).

---

## See also

- [[AI/langgraph/README|LangGraph]] — the agent framework built on LangChain (comes after this section)
- [[AI/llm-foundations|llm-foundations]] — the machine learning concepts underneath LLMs
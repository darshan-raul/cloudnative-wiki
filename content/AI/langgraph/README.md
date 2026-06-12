---
title: LangGraph
tags:
  - AI
  - LangGraph
---

# LangGraph

LangGraph is LangChain's extension for building stateful, multi-step
agent workflows. Where a LangChain chain is a linear sequence,
LangGraph adds **cycles**, **branching**, **persistence**, and
**human-in-the-loop**.

You need LangGraph when:
- An agent must loop until a condition is met (tool calls, retries)
- A workflow needs human approval before destructive actions
- State must survive across requests (checkpointers)
- Multiple agents work in parallel (fan-out/fan-in)

## What you already know

If you've worked through [[AI/langchain/README|LangChain]], these
concepts carry over directly:

| LangChain | LangGraph |
|---|---|
| `ChatOpenAI` | same |
| `@tool` | same |
| `ChatPromptTemplate` | same |
| `Runnable` | the `StateGraph` is a `Runnable` |
| `FakeListChatModel` | same |

LangGraph takes the same building blocks and adds a graph execution
model on top.

## What's new in LangGraph

1. **State** — a `TypedDict` with optional reducers, not a plain dict
2. **Nodes** — functions that read and write state
3. **Edges** — unconditional (`add_edge`) or conditional (`add_conditional_edges`)
4. **Checkpointer** — persists state across calls (`MemorySaver`, `PostgresSaver`)
5. **`Command`** — update state and route to a specific node
6. **`interrupt()`** — pause the graph for human-in-the-loop
7. **`Send`** — fan-out to multiple nodes (map-reduce)

## Learning path

Work through these files in order. Each builds on the previous:

| # | File | What you learn |
|---|---|---|
| 1 | [[01-mental-model|01-mental-model]] | The four concepts, the agent loop, why cycles need LangGraph |
| 2 | [[02-state-and-reducers|02-state-and-reducers]] | `TypedDict` state, `add_messages`, custom reducers |
| 3 | [[03-nodes-and-edges|03-nodes-and-edges]] | `add_node`, `add_edge`, conditional routing, `Send` |
| 4 | [[04-tools-and-routing|04-tools-and-routing]] | `ToolNode`, `tools_condition`, `bind_tools` |
| 5 | [[05-command-and-interrupts|05-command-and-interrupts]] | `Command`, `interrupt()`, `Command(resume=...)` |
| 6 | [[06-subgraphs|06-subgraphs]] | Subgraphs, `Send` fan-out/fan-in |
| 7 | [[07-streaming|07-streaming]] | `stream_mode="messages"`, `astream_events` |
| 8 | [[08-checkpointers|08-checkpointers]] | `MemorySaver`, `SqliteSaver`, `PostgresSaver` |
| 9 | [[09-memory-store|09-memory-store]] | `InMemoryStore`, `PostgresStore`, cross-thread memory |
| 10 | [[10-human-in-the-loop|10-human-in-the-loop]] | `interrupt()` + approval UI, resume |
| 11 | [[11-production|11-production]] | Compilation, recursion limits, error handling, deployment |
| 12 | [[12-testing|12-testing]] | `FakeListChatModel`, graph assertions, no-network |

## Quick start

```python
from typing import TypedDict
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage

class AgentState(TypedDict):
    messages: Annotated[list, add_messages]

llm = ChatOpenAI(model="gpt-4o")

def call_model(state: AgentState) -> dict:
    response = llm.invoke(state["messages"])
    return {"messages": [response]}

builder = StateGraph(AgentState)
builder.add_node("call_model", call_model)
builder.add_edge(START, "call_model")
builder.add_edge("call_model", END)
graph = builder.compile()

result = graph.invoke({"messages": [HumanMessage(content="hi")]})
print(result["messages"][-1].content)
```

## Prerequisite knowledge

- Python async (`async def`, `await`, `async for`)
- LangChain core concepts: `BaseMessage`, `AIMessage`, `ToolMessage`,
  `HumanMessage`, `@tool`, `ChatOpenAI`, `Runnable`
- See [[AI/langchain/README|LangChain]] to learn these first
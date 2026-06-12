---
title: "LangGraph — Mental Model"
tags:
  - AI
  - LangGraph
---

> **Start here.** This explains what LangGraph is, why you need it,
> and the four concepts everything else builds on. Read this before
> any other LangGraph file.

## Why LangGraph?

The agent loop looks like this:

```
call model → model decides to call a tool → run tool → call model again → ...
```

This is a **cyclic graph** — after `run_tools`, you go back to
`call_model`. You cannot express this with a chain
(`prompt | model | parser`), because a chain is strictly linear:
start → step1 → step2 → end. No loops.

LangGraph is a state-machine library that gives you:

- **Cyclic graphs** — `add_edge("tools", "call_model")` is a back-edge
- **Conditional routing** — after `call_model`, either go to
  `tools` (if the model called tools) or end (if it didn't)
- **Durable state** — conversation history survives across requests
- **Human-in-the-loop** — pause the agent, ask for approval, resume
- **Time travel** — inspect and replay past states

---

## The four core concepts

Everything in LangGraph is built on four ideas:

### 1. State

A `TypedDict` that gets passed to every node. It's the only thing
that flows through the graph:

```python
from typing import TypedDict
from langchain_core.messages import BaseMessage

class AgentState(TypedDict):
    messages: list[BaseMessage]     # conversation history
    user_id: str
```

Each field can have a **reducer** that controls how updates merge.
The `messages` field uses `add_messages` (appends). Without a
reducer, the field is replaced on update.

### 2. Nodes

A node is a function that reads state and returns a partial update:

```python
def call_model(state: AgentState) -> dict:
    response = llm.bind_tools(tools).invoke(state["messages"])
    return {"messages": [response]}
```

A node returns a **partial update** — only the keys it wants to
change. The graph merges it into the current state.

### 3. Edges

A connection from one node to another. Two kinds:

- **Fixed** — always go here after this node:
  `builder.add_edge("run_tools", "call_model")`
- **Conditional** — decide based on state:
  `builder.add_conditional_edges("call_model", should_continue)`

The routing function `(state) -> str` returns the name of the next
node.

### 4. Channels (reducers)

The plumbing. A reducer is `(current_value, update) -> new_value`.
The `messages` field uses `add_messages` which appends (and
deduplicates by ID). Fields without a reducer are replaced.

---

## The agent loop in code

```python
from langgraph.graph import StateGraph, START, END
from langgraph.prebuilt import ToolNode, tools_condition

# The state
class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]

# The call_model node
def call_model(state: AgentState) -> dict:
    response = llm.bind_tools(tools).invoke([
        SystemMessage(content="You are a helpful assistant."),
        *state["messages"],
    ])
    return {"messages": [response]}

# Routing: after call_model, either run tools or end
def should_continue(state: AgentState) -> str:
    last = state["messages"][-1]
    if hasattr(last, "tool_calls") and last.tool_calls:
        return "run_tools"
    return END

# Build the graph
builder = StateGraph(AgentState)
builder.add_node("call_model", call_model)
builder.add_node("run_tools", ToolNode(tools))
builder.add_edge(START, "call_model")
builder.add_conditional_edges("call_model", should_continue, {
    "run_tools": "run_tools",
    END: END,
})
builder.add_edge("run_tools", "call_model")
graph = builder.compile()

# Run it
result = graph.invoke({"messages": [HumanMessage(content="What's the weather in Tokyo?")]})
```

That's the entire agent loop. Every other LangGraph feature (checkpointers,
subgraphs, interrupts, memory stores) is additive on top of this.

---

## LangGraph vs. LangChain chains

| What you want | Use | Why |
|---|---|---|
| Linear: prompt → model → parser | LangChain chain (`\|`) | No loops needed |
| Agent loop with tools | LangGraph `StateGraph` | Cycles + conditional routing |
| Multi-step branching | LangGraph | Conditional edges + `Send` for fan-out |
| Stateful chat with persistence | LangGraph + checkpointer | Durable, resumable |
| Multi-agent with subgraphs | LangGraph | Each subgraph has its own state |

**The rule:** if your flow has cycles, use LangGraph. If it's
strictly linear, a chain is fine.

---

## The package layout

| Import | What's there |
|---|---|
| `langgraph.graph` | `StateGraph`, `START`, `END`, `MessagesState` |
| `langgraph.prebuilt` | `ToolNode`, `tools_condition` |
| `langgraph.checkpoint.memory` | `MemorySaver` |
| `langgraph.checkpoint.sqlite` | `SqliteSaver` |
| `langgraph.checkpoint.postgres` | `PostgresSaver` |
| `langgraph.store.memory` | `InMemoryStore` |
| `langgraph.store.postgres` | `PostgresStore` |
| `langgraph.types` | `Command`, `Send`, `Interrupt`, `RetryPolicy` |
| `langgraph.func` | `@entrypoint`, `@task` (functional API) |

The graph API (`StateGraph`) is what this section covers. The
functional API (`@entrypoint`) is just syntactic sugar — same
underlying `Pregel` engine.

---

## Common pitfalls

1. **`END` is a sentinel from `langgraph.graph`**, not the string
   `"END"`. Import it explicitly.
2. **`compile()` is not free.** Build the graph once at module
   scope. Don't re-compile per request.
3. **Reducers run on every partial update.** If you return
   `{"messages": [AIMessage(...)]}` and the field has `add_messages`,
   it appends. Without a reducer, it replaces.
4. **`invoke` is synchronous.** In async contexts (FastAPI), use
   `ainvoke` or `astream`.
5. **`recursion_limit` defaults to 25.** If your agent runs more
   than 25 tool calls, it blows the limit. Set it higher or design
   for termination.

---

## See also

- [[AI/langgraph/02-state-and-reducers|02-state-and-reducers]] — the state schema and how reducers work
- [[AI/langgraph/03-nodes-and-edges|03-nodes-and-edges]] — adding nodes, edges, and conditional routing
- [[AI/langgraph/04-tools-and-routing|04-tools-and-routing]] — `ToolNode` and `tools_condition`
- [[AI/langchain/08-langgraph-intro|../langchain/08-langgraph-intro]] — LangChain's view of LangGraph (the agent loop)
---
title: "LangChain — LangGraph Intro"
tags:
  - AI
  - LangChain
  - LangGraph
---

> **Part 8.** Why chains aren't enough, what LangGraph adds (state,
> nodes, edges, the agent loop), and how `StateGraph`, `ToolNode`,
> and checkpointers work together.

## The problem with chains for agents

A chain is a linear pipeline: start → step1 → step2 → end. It can't
do this:

```
call model → tool → tool result → call model again → tool → ...
```

Because that needs **a loop** (the model calls tools, tools return,
model calls again) and **state** (the growing messages list). You
can fake it with recursion, but you lose:

- **Persistence** — crash mid-loop, state is gone
- **Human-in-the-loop** — can't pause for approval before a destructive tool
- **Interruption** — can't stop and resume a running agent
- **Multi-turn memory** — conversation history isn't preserved across requests

LangGraph solves all of this.

---

## LangGraph's four core concepts

### 1. `StateGraph` — the graph itself

```python
from langgraph.graph import StateGraph, END

builder = StateGraph(AgentState)
builder.add_node("call_model", call_model_node)
builder.add_node("run_tools", tool_node)
builder.set_entry_point("call_model")
builder.add_edge("run_tools", "call_model")   # after tools, always back to model
builder.add_edge("call_model", END)           # model without tool_calls = done

graph = builder.compile()
```

The graph is a directed graph of nodes. The state is a dict that
gets passed through the nodes.

### 2. State — the shared memory

```python
from typing import TypedDict
from langchain_core.messages import BaseMessage

class AgentState(TypedDict):
    messages: list[BaseMessage]
    user_id: str
```

Every node receives the current state and returns a partial update.
The `messages` key is the conversation history (the equivalent of
"memory" in legacy LangChain).

The `add_messages` reducer handles appending correctly. If a node
returns `{"messages": [AIMessage(...)]}`, it appends to the list.
If you return `{"messages": [RemoveMessage(id=m.id)]}`, it removes.

### 3. Nodes — Python functions

A node is any function `(state) -> partial_state_update`:

```python
def call_model(state: AgentState) -> dict:
    messages = [SystemMessage(content=SYSTEM_PROMPT)] + state["messages"]
    response = llm.bind_tools(tools).invoke(messages)
    return {"messages": [response]}
```

The function returns a **partial update** — only the keys it wants
to change. The graph merges it into the current state.

### 4. Edges — how to route

Two types of edges:

**Unconditional** — always go here after this node:

```python
builder.add_edge("run_tools", "call_model")   # after tools, always call model
```

**Conditional** — decide based on state:

```python
def should_continue(state: AgentState) -> str:
    last_message = state["messages"][-1]
    if hasattr(last_message, "tool_calls") and last_message.tool_calls:
        return "run_tools"
    return END

builder.add_conditional_edges("call_model", should_continue)
```

This is the routing logic. After `call_model`, either go to `run_tools`
(if the model called tools) or `END` (if the model answered).

---

## The agent loop in LangGraph

Putting it together:

```
┌──────────────────────────────────────────────────────┐
│  AgentState:                                         │
│    messages: list[BaseMessage]                      │
│    user_id: str                                      │
└──────────────────────────────────────────────────────┘
                      │
                      ▼
              ┌─────────────┐
              │ call_model  │  ← SystemMessage + messages → model
              └──────┬──────┘
                     │ AIMessage
                     ▼
          ┌────────────────────────┐
          │ tool_calls present?    │
          └────────────────────────┘
             │ YES              │ NO
             ▼                  ▼
      ┌────────────┐          END
      │ run_tools  │
      └──────┬─────┘
             │ ToolMessage(s)
             ▼
      back to call_model ──────────────────────────────►
```

### The complete graph

```python
from langgraph.graph import StateGraph, END
from langgraph.prebuilt import ToolNode

# The state
class AgentState(TypedDict):
    messages: list[BaseMessage]

# Nodes
def call_model(state: AgentState) -> dict:
    messages = [SystemMessage(content="You are a helpful assistant.")] + state["messages"]
    response = llm.bind_tools(tools).invoke(messages)
    return {"messages": [response]}

# Routing logic
def should_continue(state: AgentState) -> str:
    last = state["messages"][-1]
    if hasattr(last, "tool_calls") and last.tool_calls:
        return "run_tools"
    return END

# Build
builder = StateGraph(AgentState)
builder.add_node("call_model", call_model)
builder.add_node("run_tools", ToolNode(tools))
builder.set_entry_point("call_model")
builder.add_conditional_edges("call_model", should_continue)
builder.add_edge("run_tools", "call_model")
graph = builder.compile()

# Run it
result = graph.invoke({"messages": [HumanMessage(content="What's the weather in Tokyo?")]})
```

`ToolNode` handles the tool call + `ToolMessage` assembly
automatically. It reads `AIMessage.tool_calls`, invokes each tool,
builds `ToolMessage`s with matching `tool_call_id`s, and returns
them as a dict with key `messages`.

---

## `ToolNode` — the tool-execution node

`ToolNode` from `langgraph.prebuilt` is the standard way to run tools:

```python
from langgraph.prebuilt import ToolNode

tool_node = ToolNode(tools)
```

It reads `state["messages"]`, finds `AIMessage.tool_calls`, invokes
each tool, and returns `{"messages": [ToolMessage(...), ToolMessage(...)]}`.

Options:

```python
ToolNode(tools)                        # all tools
ToolNode(["get_weather", "list_clusters"])  # only specific tools (by name)
ToolNode(tools, handle_tool_errors=True)   # catch exceptions as ToolMessage status="error"
```

`handle_tool_errors=True` (default): exceptions become `ToolMessage`
with `status="error"`. The model sees the error and can react.

---

## Checkpointers — persistence across requests

A checkpointer saves the graph state after each step. On the next
call with the same `thread_id`, it resumes from where it left off:

```python
from langgraph.checkpoint.memory import MemorySaver

checkpointer = MemorySaver()   # in-memory (dev)
# or
checkpointer = SqliteSaver.from_connector(conn, "my_graph")   # persistent

graph = builder.compile(checkpointer=checkpointer)

# First call — starts fresh
config = {"configurable": {"thread_id": "thread-abc"}}
result = graph.invoke({"messages": [HumanMessage(content="hi")]}, config=config)

# Second call — resumes from saved state
result2 = graph.invoke({"messages": [HumanMessage(content="what's the weather?")]}, config=config)
```

The `configurable` dict carries the `thread_id`. The checkpointer
uses it to look up the saved state.

### `MemorySaver` vs `SqliteSaver`

| Checkpointer | Persistence | When to use |
|---|---|---|
| `MemorySaver` | RAM only | Dev, single-process |
| `SqliteSaver` | SQLite file | Single-process, persistent |
| `PostgresSaver` | PostgreSQL | Multi-host, production |

```python
# Postgres in prod
from langgraph.checkpoint.postgres import PostgresSaver

checkpointer = PostgresSaver.from_connector(db_pool)
checkpointer.setup()   # create the tables if they don't exist
```

---

## Interrupts — human-in-the-loop

`Command(resume=...)` pauses the graph and returns control to the
caller. The caller can inspect state, show a UI, ask for approval,
then resume:

```python
from langgraph.types import Command

def call_model(state: AgentState) -> dict:
    response = llm.bind_tools(tools).invoke(state["messages"])
    if response.tool_calls:
        # Destructive tool — pause for human approval
        for tc in response.tool_calls:
            if tc.name in ["delete_cluster", "scale_down"]:
                return Command(resume=None, update={"messages": [response]})
    return {"messages": [response]}
```

The graph run returns with an interrupt. The caller shows the user
the proposed action, gets approval, then calls:

```python
# Resume with approval
graph.invoke(Command(resume="approved", name="human_approval"), config=config)
```

Or:

```python
# Resume with modified args
graph.invoke(
    Command(resume={"tool_call_id": "call-1", "approved": False}),
    config=config,
)
```

---

## `Command` — update state and route

`Command` does two things: updates the graph state, and optionally
changes the next node:

```python
from langgraph.types import Command

def lookup_node(state: AgentState) -> Command:
    docs = retriever.invoke(state["messages"][-1].content)
    return Command(
        goto="call_model",   # after this node, go to call_model
        update={
            "messages": [
                SystemMessage(content=f"Use these docs:\n\n{docs}"),
            ],
        },
    )
```

This is the "inject context and re-run model" pattern. The tool (or
node) returns a `Command` that applies the update and routes to a
specific next node.

---

## Common pitfalls

1. **`END` is a sentinel, not a string.** Use `END` from
   `langgraph.graph`, not the string `"END"`.
2. **State keys must match the reducer.** If your state has a
   `messages` key and you return `{"messages": [...]}` from a
   node, the `add_messages` reducer appends. If you return
   `{"messages": state["messages"] + [...]}` you're doubling
   — let the reducer handle it.
3. **Missing `tool_call_id` in `ToolMessage`.** `ToolNode` gets
   this right. If you build `ToolMessage`s by hand, copy the
   `id` from the `ToolCall`.
4. **No checkpointer = no persistence.** Each `invoke` call is
   independent. Add a checkpointer if you need conversation
   continuity.
5. **`ConditionalEdge` receives state, returns a string.** The
   function takes state, returns the name of the next node.
   Not a dict, not a boolean.

---

## See also

- [[AI/langchain/01-mental-model|01-mental-model]] — chains vs agents
- [[AI/langchain/06-runnables-lcel|06-runnables-lcel]] — LCEL (the `|` operator)
- [[AI/langchain/07-memory-callbacks|07-memory-callbacks]] — checkpointers and persistence
- [[AI/langgraph/01-mental-model|../langgraph/01-mental-model]] — LangGraph's own mental model
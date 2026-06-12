---
title: "LangGraph — Nodes & Edges"
tags:
  - AI
  - LangGraph
---

> **Part 3.** How to add nodes and edges to a `StateGraph`,
> unconditional vs conditional routing, the `Send` primitive for
> fan-out/fan-in, and how the graph executes.

## Adding nodes

A node is any callable `(state) -> dict | Command`:

```python
from langgraph.graph import StateGraph

builder = StateGraph(AgentState)

builder.add_node("call_model", call_model_fn)
builder.add_node("run_tools", tool_node)
builder.add_node("log_action", log_fn)
```

The name string is the node's identifier. It can be anything:
`"call_model"`, `"retrieve"`, `"summarize"`. Use it in edges.

### Node names must be unique

You can't add two nodes with the same name. If you need variations,
name them differently: `"call_model_v1"`, `"call_model_v2"`.

### Nodes are reusable

The same function can be used as multiple nodes with different names:

```python
builder.add_node("call_model_gpt4", call_model_fn)
builder.add_node("call_model_haiku", call_model_fn)
```

Useful for A/B testing or routing to different model tiers.

---

## Adding edges

### Unconditional edges — always go here

```python
builder.add_edge("run_tools", "call_model")   # after tools, always call model
builder.add_edge(START, "call_model")         # START is the entry point
builder.add_edge("call_model", END)           # END is the exit point
```

`START` and `END` are sentinels from `langgraph.graph`. `START`
is where every graph run begins. `END` is a terminal node — when
the graph reaches it, the run is done.

### Multiple edges from one node

You can add multiple edges from the same source node:

```python
builder.add_edge("call_model", "log_action")
builder.add_edge("call_model", "audit_action")
# After call_model, both log_action and audit_action run
```

Each edge creates a separate path. The graph fans out.

---

## Conditional edges — routing based on state

```python
from langgraph.graph import StateGraph, END

def should_continue(state: AgentState) -> str:
    last = state["messages"][-1]
    if hasattr(last, "tool_calls") and last.tool_calls:
        return "run_tools"
    return END

builder.add_conditional_edges(
    "call_model",          # source node
    should_continue,       # routing function: (state) -> str
    {
        "run_tools": "run_tools",
        END: END,
    },
)
```

The routing function `(state) -> str` returns the name of the next
node. It runs on every invocation of `call_model`.

The path map (`{"run_tools": "run_tools", END: END}`) maps the
return value to an actual node name. It's optional but recommended
for self-documentation.

### What can a routing function return?

A string — the name of the node to go to next. Or multiple strings
for fan-out (see `Send` below).

### Conditional without a path map

```python
builder.add_conditional_edges("call_model", should_continue)
# The routing function's return value must exactly match a node name
```

Without a path map, the return value must be a valid node name.
The path map lets you return `{"continue": "run_tools"}` and map
`"continue"` to `"run_tools"` — useful for semantic return values.

---

## `Send` — fan-out to multiple nodes

`Send` is for map-reduce patterns: send the current state to
multiple nodes, collect their results, merge:

```python
from langgraph.types import Send

def route_to_analyzers(state: AgentState) -> list[Send]:
    return [
        Send("analyze_sentiment", {"messages": state["messages"]}),
        Send("analyze_topics", {"messages": state["messages"]}),
        Send("analyze_entities", {"messages": state["messages"]}),
    ]

builder.add_conditional_edges("start", route_to_analyzers)
```

Each `Send` target receives its own state copy. The results are
collected and merged via a special `"__root__"` key or custom
reducer.

This is how you do parallel document processing: split a document
into chunks, send each chunk to a `process_chunk` node, collect
the results, merge.

---

## The execution model

When you call `graph.invoke(input_state)`:

1. The input dict becomes the initial state.
2. The graph starts at `START`.
3. The node `START` points to is executed (here, `call_model`).
4. The node returns a partial update.
5. The partial update is merged into the state (using each field's
   reducer).
6. The graph finds the outgoing edges of the node that just ran.
7. If the edge is unconditional, the target is executed next.
   If the edge is conditional, the routing function runs and its
   return value determines the next node.
8. Steps 3–7 repeat until a node points to `END`, or the
   recursion limit is hit.

The graph executes one node at a time. Fan-out via multiple edges
or `Send` creates parallel branches that are resolved before
continuing.

---

## The complete agent graph

```python
from langgraph.graph import StateGraph, START, END
from langgraph.prebuilt import ToolNode, tools_condition

def build_agent(llm, tools):
    tool_node = ToolNode(tools)

    def call_model(state: AgentState) -> dict:
        response = llm.bind_tools(tools).invoke([
            SystemMessage(content="You are a helpful assistant."),
            *state["messages"],
        ])
        return {"messages": [response]}

    def should_continue(state: AgentState) -> str:
        last = state["messages"][-1]
        if hasattr(last, "tool_calls") and last.tool_calls:
            return "run_tools"
        return END

    builder = StateGraph(AgentState)
    builder.add_node("call_model", call_model)
    builder.add_node("run_tools", tool_node)
    builder.add_edge(START, "call_model")
    builder.add_conditional_edges("call_model", should_continue, {
        "run_tools": "run_tools",
        END: END,
    })
    builder.add_edge("run_tools", "call_model")

    return builder.compile()
```

Every node has exactly one outgoing edge (fixed or conditional).
The graph is deterministic given the same state and model output.

---

## Common pitfalls

1. **`END` is a sentinel, not a string.** Use `END` from
   `langgraph.graph`, not `"END"`.
2. **Conditional edge routing functions run on every invocation.**
   Don't put expensive work in them.
3. **`Send` returns a list of `Send` objects**, not a single `Send`.
   If you return a single `Send`, the graph may not fan out correctly.
4. **Multiple edges from one node fan out.** If you add
   `builder.add_edge("call_model", "log")` and
   `builder.add_edge("call_model", "audit")`, both nodes run after
   `call_model` — in sequence, not parallel (unless you use `Send`).
5. **`recursion_limit` defaults to 25.** If your agent runs more
   than 25 tool calls, it hits the limit. Set
   `graph.compile(recursion_limit=100)` to raise it.

---

## See also

- [[AI/langgraph/01-mental-model|01-mental-model]] — the four concepts
- [[AI/langgraph/02-state-and-reducers|02-state-and-reducers]] — how state is defined
- [[AI/langgraph/04-tools-and-routing|04-tools-and-routing]] — `ToolNode` and `tools_condition`
- [[AI/langgraph/06-subgraphs|06-subgraphs]] — `Send` for fan-out/fan-in in depth
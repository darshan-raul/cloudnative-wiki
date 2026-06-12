---
title: "LangGraph — Subgraphs & Fan-out"
tags:
  - AI
  - LangGraph
---

> **Part 6.** Subgraphs (composing graphs inside graphs), the `Send`
> primitive for fan-out/fan-in, and when to use each.

## When to use subgraphs

A subgraph is a compiled graph used as a node inside another graph.
Use it when:

- You have a complex workflow that can be decomposed into independent
  modules (e.g., a document pipeline with parse → extract → validate)
- A team owns one part of the graph and shouldn't see the internal
  graph of another team
- You want to reuse a graph in multiple parent graphs

```python
# Build a sub-graph independently
document_graph = (
    StateGraph(DocumentState)
    .add_node("parse", parse_node)
    .add_node("extract", extract_node)
    .add_node("validate", validate_node)
    .add_edge(START, "parse")
    .add_edge("parse", "extract")
    .add_edge("extract", "validate")
    .add_edge("validate", END)
    .compile()
)

# Use it as a node in the parent graph
builder.add_node("process_document", document_graph)
```

The subgraph runs inside the parent graph. Its state is separate from
the parent state — you pass data in via input edges, the subgraph
runs to completion, and the output is returned to the parent.

---

## `Send` — fan-out to multiple nodes

`Send` is for map-reduce: send the current state to multiple nodes
in parallel, collect their outputs, merge:

```python
from langgraph.types import Send

def route_to_analyzers(state: AgentState) -> list[Send]:
    return [
        Send("analyze_sentiment", {"text": state["text"]}),
        Send("analyze_entities", {"text": state["text"]}),
        Send("analyze_topics", {"text": state["text"]}),
    ]

builder.add_conditional_edges("start", route_to_analyzers)
```

Each target node receives its own state copy and runs independently.
Results are collected via a special `"__root__"` key or custom reducer.

### Fan-out use case: parallel document analysis

```python
def route_to_chunks(state: DocumentState) -> list[Send]:
    chunks = chunk_document(state["content"])
    return [Send("process_chunk", {"chunk": c, "index": i}) for i, c in enumerate(chunks)]

builder.add_conditional_edges("split", route_to_chunks)

def collect_results(state: AgentState) -> dict:
    # All process_chunk results are in state["chunk_results"]
    return {"summary": merge_results(state["chunk_results"])}

builder.add_node("process_chunk", process_chunk_node)
builder.add_node("collect_results", collect_results)
builder.add_edge("collect_results", END)
```

### Fan-in: collecting results

The collected results go into a field with a custom reducer:

```python
class AnalyzerState(TypedDict):
    results: Annotated[list[dict], lambda left, right: left + right]
    text: str

def collect(state: AnalyzerState) -> dict:
    return {}   # state already has results from fan-out
```

Each `Send` target's final state output is merged via the reducer.

---

## `Command.PARENT` — subgraph updating parent state

A subgraph can update the parent graph's state via `Command.PARENT`:

```python
from langgraph.types import Command

def subgraph_node(state: SubgraphState) -> dict:
    result = do_work(state["data"])
    return Command(
        update={"parent_results": result},
        goto=Command.PARENT,   # return to parent graph, keep going
    )
```

`Command.PARENT` tells the subgraph to return control to the parent
graph without terminating. The parent's state is updated with the
`update` dict.

---

## Named subgraph outputs

By default, a subgraph returns its final state. Use named outputs to
return specific values:

```python
# When compiling the subgraph:
subgraph = builder.compile()

# Use with named output
builder.add_node(
    "my_subgraph",
    subgraph,
    input=["some_field"],    # map input key to subgraph input
    output=["result_field"], # map subgraph output to parent key
)
```

This lets you map specific state fields to the subgraph's input/output
without exposing the full subgraph state.

---

## Nested subgraphs

Subgraphs can contain their own subgraphs. This is useful for
complex pipelines:

```
parent_graph
  └── document_pipeline (subgraph)
        └── parser (subgraph)
        └── extractor (subgraph)
```

The recursion limit applies at each level. If the parent graph's
limit is 25 and the document_pipeline is one step, the subgraph has
its own step budget.

---

## When to use `Send` vs subgraphs

| Pattern | Use | Example |
|---|---|---|
| Same logic, multiple inputs in parallel | `Send` | Analyze 10 document chunks |
| Independent workflow, reusable | Subgraph | A document processing pipeline |
| One node calling another with its own state | Subgraph | Multi-agent where each agent has its own message list |
| Map-reduce over a list | `Send` | Process each item, collect results |

---

## Common pitfalls

1. **`Send` returns a list.** If you return a single `Send`, the
   fan-out won't work correctly. Always return `list[Send]`.
2. **Subgraph state is separate.** A subgraph doesn't share the
   parent's state. Data must be explicitly passed through edges.
3. **`Command.PARENT` only works inside a subgraph.** Using it in
   a top-level graph causes an error.
4. **`Send` targets must be actual node names** in the same graph.
   You can't `Send` to a subgraph by name — the subgraph must be
   added as a node first.
5. **Recursion limit applies per graph level.** A nested subgraph
   with 10 steps counts as 1 step toward the parent's recursion
   limit, but 10 steps toward the subgraph's own limit.

---

## See also

- [[AI/langgraph/03-nodes-and-edges|03-nodes-and-edges]] — edges and conditional routing
- [[AI/langgraph/05-command-and-interrupts|05-command-and-interrupts]] — `Command` and routing changes
- [[AI/langgraph/02-state-and-reducers|02-state-and-reducers]] — custom reducers for collecting `Send` results
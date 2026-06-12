---
title: "LangGraph — Command & Interrupts"
tags:
  - AI
  - LangGraph
---

> **Part 5.** `Command` (update state and route to a different node),
> `interrupt()` (pause the graph for human-in-the-loop), and the
> resume pattern.

## `Command` — update state and change the route

`Command` from `langgraph.types` does two things at once:

1. **Updates the graph state** — applies a partial update before the
   next node runs.
2. **Changes the next node** — overrides the routing that the current
   edge would have chosen.

```python
from langgraph.types import Command

def lookup_node(state: AgentState) -> Command:
    docs = retriever.invoke(state["messages"][-1].content)
    return Command(
        goto="call_model",   # route to call_model (not the next edge)
        update={
            "messages": [
                SystemMessage(content=f"Use these documents:\n\n{docs}"),
            ],
        },
    )
```

When this node returns, the graph applies the message update and
routes to `call_model` instead of following the normal outgoing edge.

### `Command` vs returning a dict

Returning a dict only updates state. `Command` also changes routing:

```python
# Only updates state — next edge is followed normally
return {"messages": [SystemMessage(content="context")]}

# Updates state AND routes to a specific node
return Command(goto="call_model", update={"messages": [...]})
```

### `Command` with no routing change

```python
def log_node(state: AgentState) -> Command:
    log(state)
    return Command(update={"context": {"last_action": "call_model"}})
```

When `goto` is omitted, the normal edge is followed. Use this to
apply a state update before the next node runs.

---

## `interrupt()` — pause the graph

`interrupt()` from `langgraph.types` pauses the graph and returns
control to the caller. The caller can inspect state, show a UI,
ask for approval, then resume:

```python
from langgraph.types import interrupt

def call_model(state: AgentState) -> dict:
    response = llm.bind_tools(tools).invoke(state["messages"])

    # Check if any tool is destructive
    for tc in (response.tool_calls or []):
        if tc.name in ["delete_cluster", "scale_down", "terminate_instance"]:
            return Command(
                update={"messages": [response], "pending_approval": tc},
            )

    return {"messages": [response]}

def confirm_node(state: AgentState) -> dict:
    # This node only runs if we resumed with approval
    return {"messages": [AIMessage(content=f"Action approved: {state['pending_approval']}"]]}
```

When `interrupt()` is called inside a node, the graph run pauses
and returns the current state to the caller. The caller decides
whether to resume or abort.

### `interrupt()` with a value

```python
from langgraph.types import interrupt

def call_model(state: AgentState) -> dict:
    response = llm.bind_tools(tools).invoke(state["messages"])
    if response.tool_calls:
        return Command(
            update={"messages": [response]},
            goto=interrupt("pending_approval"),
        )
    return {"messages": [response]}
```

`interrupt("pending_approval")` returns a sentinel value the caller
can inspect to know why the graph paused.

---

## Resuming — `Command(resume=...)`

After an interrupt, the caller calls `graph.invoke(Command(resume=value))`:

```python
# The graph hit an interrupt — state is returned to the caller
result = graph.invoke(input_state, config=config)
# result contains the interrupted state with pending_approval

approval = ask_user(result["pending_approval"])   # show confirmation UI

if approval == "approved":
    # Resume — graph continues from where it was interrupted
    resumed = graph.invoke(
        Command(resume="approved"),
        config=config,
    )
else:
    # Abort — don't resume, just return the current state
    resumed = {"messages": [...]}   # or just return result
```

The `resume` value is available to the next node via the state:

```python
def handle_approval(state: AgentState) -> dict:
    approval = state.get("resume_value")   # "approved" or "denied"
    if approval == "approved":
        return {"messages": [AIMessage(content="Proceeding with action.")]}
    return {"messages": [AIMessage(content="Action cancelled by user.")]}
```

---

## The full human-in-the-loop pattern

```python
from langgraph.types import Command, interrupt

class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]
    pending_approval: dict | None

def call_model(state: AgentState) -> dict:
    response = llm.bind_tools(tools).invoke(state["messages"])
    if response.tool_calls:
        for tc in response.tool_calls:
            if tc.name in ["delete_cluster", "scale_down"]:
                return Command(
                    update={"messages": [response], "pending_approval": {
                        "tool": tc.name,
                        "args": tc.args,
                        "tool_call_id": tc.id,
                    }},
                    goto=interrupt("awaiting_approval"),
                )
    return {"messages": [response]}

def handle_approval(state: AgentState) -> dict:
    approval = state["configurable"].get("approval")
    pending = state["pending_approval"]
    if approval == "approved":
        # Actually execute the pending tool
        result = execute_tool(pending["tool"], pending["args"])
        return {
            "messages": [ToolMessage(
                content=str(result),
                tool_call_id=pending["tool_call_id"],
                name=pending["tool"],
            )],
            "pending_approval": None,
        }
    return {
        "messages": [AIMessage(content=f"Action cancelled: {pending['tool']} denied.")],
        "pending_approval": None,
    }

# Build graph with conditional edge for approval
def route_approval(state: AgentState) -> str:
    return "handle_approval" if state.get("pending_approval") else END

builder = StateGraph(AgentState)
builder.add_node("call_model", call_model)
builder.add_node("handle_approval", handle_approval)
builder.add_edge(START, "call_model")
builder.add_conditional_edges("call_model", route_approval)
# After handle_approval, go back to call_model to show the result
builder.add_edge("handle_approval", "call_model")
```

The key: `interrupt()` pauses and returns the state. The caller
inspects it, gets user input, then calls `graph.invoke(Command(resume=value))`
to continue.

---

## When to use `Command` vs `interrupt`

| Situation | Use | Why |
|---|---|---|
| Inject context, route to specific node | `Command(goto=...)` | No pause needed |
| Destructive action, need human approval | `interrupt()` | Must pause, cannot proceed without approval |
| Ask user a question mid-graph | `interrupt()` | User must respond before continuing |
| Modify state before next node | `Command(update=...)` | No routing change |

---

## Common pitfalls

1. **`interrupt()` inside a conditional edge routing function**
   doesn't work — `interrupt()` must be inside a node, not a routing
   function.
2. **`Command` with `goto` replaces the outgoing edge.** If you have
   `builder.add_edge("node_a", "node_b")` and return
   `Command(goto="node_c")`, the graph goes to `node_c`, not `node_b`.
3. **Resuming without calling `Command(resume=...)`** — if you just
   call `graph.invoke(...)` again, the graph restarts from the
   beginning, not from the interrupt point.
4. **`pending_approval` needs a reducer** if you want to update it
   cleanly. A plain field (no reducer) gets replaced, not merged.
5. **`interrupt()` only works in `invoke`/`ainvoke`**, not in
   streaming (`stream`/`astream`). The interrupt is surfaced as
   part of the stream, but the caller must handle it.

---

## See also

- [[AI/langgraph/01-mental-model|01-mental-model]] — the agent loop and when you'd need HITL
- [[AI/langgraph/03-nodes-and-edges|03-nodes-and-edges]] — edges and routing
- [[AI/langgraph/10-human-in-the-loop|10-human-in-the-loop]] — the full HITL patterns
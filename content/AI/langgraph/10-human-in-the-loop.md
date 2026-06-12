---
title: "LangGraph — Human-in-the-Loop"
tags:
  - AI
  - LangGraph
---

> **Part 10.** The full human-in-the-loop (HITL) pattern —
> `interrupt()` to pause, inspection UI, approval/rejection,
> and resumption with `Command(resume=...)`.

## The HITL problem

Some tool calls are destructive or irreversible:
`delete_cluster`, `scale_down`, `terminate_instance`, `drop_table`.
For these, you need a human to approve before execution.

The HITL flow:
1. Graph calls a tool
2. Before executing, the graph **pauses** and returns control
3. The human inspects the proposed action
4. The human approves or rejects
5. If approved, the graph **resumes** from where it paused
6. If rejected, the graph handles the rejection gracefully

`interrupt()` + `Command(resume=...)` give you exactly this.

---

## The full pattern

```python
from langgraph.types import Command, interrupt
from langgraph.graph import StateGraph, START, END

class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]
    pending_approval: dict | None

def call_model(state: AgentState) -> dict:
    response = llm.bind_tools(tools).invoke(state["messages"])

    # Check for destructive tools
    if response.tool_calls:
        for tc in response.tool_calls:
            if tc.name in ["delete_cluster", "scale_down"]:
                return Command(
                    update={
                        "messages": [response],
                        "pending_approval": {
                            "tool": tc.name,
                            "args": tc.args,
                            "tool_call_id": tc.id,
                        },
                    },
                    goto=interrupt("awaiting_approval"),
                )

    return {"messages": [response]}

def handle_approval(state: AgentState) -> dict:
    approval = state["configurable"].get("approval")

    if approval == "approved":
        # Execute the pending tool
        pending = state["pending_approval"]
        result = execute_tool(pending["tool"], pending["args"])
        return {
            "messages": [ToolMessage(
                content=str(result),
                tool_call_id=pending["tool_call_id"],
                name=pending["tool"],
            )],
            "pending_approval": None,
        }

    # Denied
    return {
        "messages": [AIMessage(
            content=f"Action denied: {state['pending_approval']['tool']} was rejected."
        )],
        "pending_approval": None,
    }

def should_continue(state: AgentState) -> str:
    if state.get("pending_approval"):
        return "handle_approval"
    return END

builder = StateGraph(AgentState)
builder.add_node("call_model", call_model)
builder.add_node("handle_approval", handle_approval)
builder.add_edge(START, "call_model")
builder.add_conditional_edges("call_model", should_continue)
builder.add_edge("handle_approval", "call_model")   # back to model after approval
graph = builder.compile()
```

### The API surface

The caller sees:

```python
# Step 1: initial call — pauses at interrupt
result = graph.invoke(
    {"messages": [HumanMessage(content="scale down cluster cl-001")]},
    config={"configurable": {"thread_id": "t1"}},
)
# result contains the state with pending_approval

# Step 2: human approves
approved = ask_user(result["pending_approval"])   # UI shows what will happen

result = graph.invoke(
    Command(resume={"approval": "approved"}),
    config={"configurable": {"thread_id": "t1"}},
)
# Graph resumes, executes the tool, returns the result
```

---

## What the human sees

The interrupted state contains everything needed to render an
approval UI:

```python
pending = result["pending_approval"]
# {
#     "tool": "scale_down",
#     "args": {"cluster_id": "cl-001"},
#     "tool_call_id": "call-abc123",
# }

# Render: "scale_down(cluster_id='cl-001') is about to be executed. Approve?"
```

The `tool_call_id` is available so the `ToolMessage` can be
constructed with the correct ID when resuming.

---

## Rejecting — graceful handling

When the human rejects:

```python
result = graph.invoke(
    Command(resume={"approval": "denied"}),
    config={"configurable": {"thread_id": "t1"}},
)
```

The `handle_approval` node returns an `AIMessage` explaining the
rejection. The agent loop continues — the model sees the denial
and can respond ("I've cancelled the scale-down request").

---

## When `interrupt()` is called

`interrupt()` is called inside a node's function, not in a routing
function. The routing function decides where to go; the node can
pause and return control.

```python
# RIGHT — interrupt inside a node
def call_model(state: AgentState) -> dict:
    response = llm.bind_tools(tools).invoke(state["messages"])
    if should_interrupt(response):
        return Command(
            update={"messages": [response]},
            goto=interrupt("confirm"),
        )
    return {"messages": [response]}

# WRONG — interrupt inside a routing function
def route(state: AgentState) -> str:
    if state["dangerous_action"]:
        interrupt("confirm")   # doesn't work here
    return "proceed"
```

---

## Resuming with a value

The `resume` value is available in the state when the graph resumes:

```python
def handle_approval(state: AgentState) -> dict:
    resume_value = state.get("resume_value")   # "approved" or "denied"
```

In the caller:

```python
graph.invoke(
    Command(resume="approved"),
    config=config,
)
# state["resume_value"] == "approved"
```

---

## Multiple pending actions

If the model calls multiple destructive tools at once:

```python
if response.tool_calls:
    destructive = [tc for tc in response.tool_calls if tc.name in DESTRUCTIVE]
    if destructive:
        return Command(
            update={
                "messages": [response],
                "pending_approval": destructive,   # list now
            },
            goto=interrupt("awaiting_approval"),
        )
```

The `handle_approval` node iterates over the list and either
executes or skips each.

---

## Timeouts — what happens if nobody approves

`interrupt()` pauses indefinitely. The state is saved in the
checkpointer. If you need a timeout:

```python
# Caller side
import asyncio

async def call_with_timeout(graph, input_state, config, timeout=60):
    try:
        result = await asyncio.wait_for(
            graph.ainvoke(input_state, config),
            timeout=timeout,
        )
        return result
    except asyncio.TimeoutError:
        return {"status": "timeout", "pending_approval": get_pending(config)}
```

The timeout is a caller-side concern, not a graph concern. The
graph will wait as long as the caller holds the connection.

---

## Common pitfalls

1. **`interrupt()` must be inside a node, not a routing function.**
   Routing functions can't pause — they must return a node name.
2. **`Command(resume=...)` must be called** to resume. Calling
   `graph.invoke(...)` again restarts from the beginning.
3. **`pending_approval` needs a reducer** if you want clean
   updates. Without one, it gets replaced, not merged.
4. **`tool_call_id` must be preserved** in `pending_approval` so
   the `ToolMessage` can be constructed correctly on resumption.
5. **`interrupt()` doesn't work in `stream`/`astream`** — only in
   `invoke`/`ainvoke`. The interrupt is surfaced as part of the
   stream output but must be handled by the caller.

---

## See also

- [[AI/langgraph/05-command-and-interrupts|05-command-and-interrupts]] — `Command` and `interrupt` details
- [[AI/langgraph/01-mental-model|01-mental-model]] — when HITL is needed
- [[AI/langgraph/08-checkpointers|08-checkpointers]] — how state is preserved during interrupt
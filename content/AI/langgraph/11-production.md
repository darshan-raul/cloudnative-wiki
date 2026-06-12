---
title: "LangGraph — Production"
tags:
  - AI
  - LangGraph
---

> **Part 11.** Deployment, recursion limits, error handling,
> debugging strategies, and what changes when you move to prod.

## Compilation is not free

Build the graph once at module scope, not per request:

```python
# Right — module level
agent = builder.compile(checkpointer=PostgresSaver(conn))

async def handle_message(request: Request) -> Response:
    result = await agent.ainvoke(
        {"messages": [HumanMessage(content=request.body)]},
        config={"configurable": {"thread_id": request.session_id}},
    )
    return result

# Wrong — compiles on every request
async def handle_message(request: Request) -> Response:
    agent = builder.compile()   # compiles every time!
    result = await agent.ainvoke(...)
```

`compile()` creates the internal execution engine. Doing it per
request adds latency and memory pressure.

---

## `recursion_limit` — preventing infinite loops

The default recursion limit is 25. An agent that calls tools more
than 25 times hits it and raises `GraphRecursionError`:

```python
# Raise the limit for complex agents
graph = builder.compile(recursion_limit=100)
```

Each node execution counts as one step toward the limit. A graph
with `call_model → run_tools → call_model → run_tools → ...` uses
one step per loop. After 100 steps, it stops.

**Design for termination.** If your agent can theoretically run
forever (e.g., a tool-calling loop with no exit condition), add a
step counter to the state:

```python
class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]
    step_count: int

def call_model(state: AgentState) -> dict:
    if state["step_count"] >= 50:
        return {"messages": [AIMessage(content="I've reached the maximum number of steps.")]}
    return {"messages": [llm.bind_tools(tools).invoke(state["messages"])]}
```

---

## Error handling

### `NodeInterrupt` — intentional pause

`NodeInterrupt` from `langgraph.errors` is raised by `interrupt()`.
Catch it to handle the pause:

```python
from langgraph.errors import NodeInterrupt

try:
    result = graph.invoke(input_state, config=config)
except NodeInterrupt as e:
    # Graph paused — inspect e.state and resume
    pending = e.state["pending_approval"]
    approved = ask_user(pending)
    result = graph.invoke(Command(resume={"approval": approved}), config=config)
```

### `GraphRecursionError` — recursion limit hit

```python
from langgraph.errors import GraphRecursionError

try:
    result = graph.invoke(input_state)
except GraphRecursionError:
    return {"messages": [AIMessage(content="I need more steps to complete this task.")]}
```

### Tool exceptions

`ToolNode` with `handle_tool_errors=True` (default) catches tool
exceptions and returns them as `ToolMessage` with `status="error"`.
The agent loop continues — the model sees the error and can react.

To change the error message:

```python
tool_node = ToolNode(tools, handle_tool_errors="Tool unavailable. Try again later.")
```

---

## Debugging strategies

### Inspect state with `get_state_history`

```python
history = graph.get_state_history(config={"configurable": {"thread_id": "abc"}})

for checkpoint in history:
    print(f"Step {checkpoint.metadata['step']}")
    print(f"  Last message: {checkpoint.values['messages'][-1].content[:100]}")
```

Walk the conversation backwards to find where things went wrong.

### `stream_mode="updates"` — per-node logging

```python
async for node_name, output in graph.astream(input_state, stream_mode="updates"):
    print(f"[{node_name}] returned: {list(output.keys())}")
```

Each step shows which node ran and what it returned.

### `astream_events` — full trace

```python
async for event in graph.astream_events(input_state, config=config, version="v2"):
    print(f"{event['event']}: {event.get('name', '')}")
```

The full trace — every model call, tool call, and state change.
Use this to reproduce issues locally.

---

## `update_state` — manual corrections

```python
# Correct the model's last response
graph.update_state(
    config,
    {"messages": [AIMessage(content="sorry, let me reconsider")]},
)
```

`update_state` writes to the current checkpoint. The next `invoke`
continues from the modified state. Useful for corrections without
restarting the conversation.

---

## LangGraph Platform

LangGraph Platform (the managed offering) handles:
- Deployment (Docker, Kubernetes)
- Scaling (multiple replicas)
- Persistence (built-in Postgres checkpointer)
- UI (LangGraph Studio for visualization)

If you're self-hosting, the open-source library gives you the graph
execution. You handle the deployment, scaling, and persistence
yourself.

### Self-hosting checklist

- [ ] Compile the graph once at startup, not per request
- [ ] `PostgresSaver` for the checkpointer (not `MemorySaver`)
- [ ] `PostgresStore` for cross-thread memory
- [ ] `recursion_limit` set appropriately for your agent's complexity
- [ ] `NodeInterrupt` handling for human-in-the-loop
- [ ] `GraphRecursionError` handling for runaway loops
- [ ] Health check endpoint that calls `graph.invoke` with a test input

---

## `invoke` vs `ainvoke` in FastAPI

```python
from fastapi import FastAPI, Request

app = FastAPI()

# Sync endpoint — use run_in_executor to avoid blocking
@app.post("/chat")
async def chat(request: Request):
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(
        None,
        lambda: graph.invoke({"messages": [HumanMessage(content=request.json()["message"])]}),
    )
    return result

# Or use ainvoke (fully async)
@app.post("/chat")
async def chat(request: Request):
    result = await graph.ainvoke(
        {"messages": [HumanMessage(content=request.json()["message"])]},
        config={"configurable": {"thread_id": request.session_id}},
    )
    return result
```

`ainvoke` is the cleanest for async frameworks. It releases the
event loop while waiting for the model.

---

## Common pitfalls

1. **Re-compiling on every request.** Move `builder.compile()` to
   module scope.
2. **`recursion_limit` too low.** 25 is conservative. Complex agents
   with many tool calls need 50–100.
3. **`MemorySaver` in production.** State is lost on restart.
   Use `PostgresSaver`.
4. **`interrupt()` not handled.** The caller must catch `NodeInterrupt`
   and resume. If the caller just propagates the error, the graph
   run is abandoned.
5. **`stream` in an async handler.** Blocks the event loop. Use
   `astream` instead.

---

## See also

- [[AI/langgraph/01-mental-model|01-mental-model]] — the agent loop
- [[AI/langgraph/08-checkpointers|08-checkpointers]] — `PostgresSaver` for prod
- [[AI/langgraph/07-streaming|07-streaming]] — streaming in prod
- [[AI/langgraph/12-testing|12-testing]] — testing before prod
---
title: "LangGraph — Streaming"
tags:
  - AI
  - LangGraph
---

> **Part 7.** How LangGraph streams output — `stream_mode="values"`,
> `stream_mode="messages"`, and `astream_events` for full lifecycle
> visibility.

## Streaming modes

When you call `graph.stream(input, stream_mode=...)`, LangGraph
can stream in two modes:

| Mode | What it yields | Use when |
|---|---|---|
| `"values"` (default) | Each state snapshot after a node runs | Debugging, state inspection |
| `"messages"` | Message deltas (like `AIMessageChunk`) | Building a chat UI |
| `"updates"` | Each node's partial update | Debugging, per-node progress |

For a chat UI, use `stream_mode="messages"`.

---

## `stream_mode="messages"` — message deltas

```python
async for message_chunk, metadata in graph.astream(
    {"messages": [HumanMessage(content="What's the weather?")]},
    config={"configurable": {"thread_id": "abc"}},
    stream_mode="messages",
):
    if message_chunk.content:
        print(message_chunk.content, end="", flush=True)
```

`message_chunk` is an `AIMessageChunk`. `metadata` has:

```python
{
    "agent": "call_model",        # which node emitted this
    "langgraph_node": "call_model",
    "langgraph_step": 3,
    "langgraph_path": ("call_model",),
}
```

Use `metadata["agent"]` to know which node the chunk came from —
useful for showing "agent is thinking..." while `call_model` is
running and "tool executing..." while `run_tools` is running.

---

## `stream_mode="values"` — state snapshots

```python
async for state_chunk in graph.astream(
    {"messages": [HumanMessage(content="hi")]},
    stream_mode="values",
):
    print(state_chunk["messages"][-1])
```

Each chunk is the full state after a node completes. Useful for
debugging — you can see exactly what changed after each step.

---

## `stream_mode="updates"` — per-node updates

```python
async for node_name, node_output in graph.astream(
    {"messages": [HumanMessage(content="hi")]},
    stream_mode="updates",
):
    print(f"{node_name}: {node_output}")
# call_model: {'messages': [AIMessage(...)]}
# run_tools: {'messages': [ToolMessage(...)]}
```

Each chunk is `(node_name, output)` for the node that just ran.
Useful for logging and progress indicators.

---

## `astream_events` — full lifecycle visibility

For a chat UI that needs both tokens and tool calls:

```python
async for event in graph.astream_events(
    {"messages": [HumanMessage(content="What's the weather in Tokyo?")]},
    config={"configurable": {"thread_id": "abc"}},
    version="v2",
    include_types=["chat_model", "tool"],
):
    kind = event["event"]

    if kind == "on_chat_model_stream":
        token = event["data"]["chunk"].content
        if token:
            yield {"type": "token", "content": token}

    elif kind == "on_tool_start":
        yield {
            "type": "tool_call",
            "name": event["name"],
            "args": event["data"]["input"],
        }

    elif kind == "on_tool_end":
        yield {
            "type": "tool_result",
            "name": event["name"],
            "result": event["data"]["output"],
        }

    elif kind == "on_chat_model_end":
        u = event["data"]["output"].usage_metadata or {}
        yield {
            "type": "usage",
            "input_tokens": u.get("input_tokens", 0),
            "output_tokens": u.get("output_tokens", 0),
        }
```

`astream_events` is the only API that surfaces both tokens and
tool calls simultaneously.

---

## `version="v2"` is required

Without `version="v2"`, you get the old event format. Always
include it:

```python
version="v2"
```

---

## Streaming with a checkpointer

Streaming works with checkpointers. The `thread_id` is in the
config:

```python
config = {"configurable": {"thread_id": "abc"}}

async for message_chunk, metadata in graph.astream(
    {"messages": [HumanMessage(content="What's the weather?")]},
    config=config,
    stream_mode="messages",
):
    ...
```

The checkpointer saves state after each step. Streaming and
checkpointing are orthogonal — you can use one without the other.

---

## `stream` (sync) vs `astream` (async)

| Method | When to use |
|---|---|
| `graph.stream(input)` | Sync context (not in an async handler) |
| `graph.astream(input)` | Async context (FastAPI `async def` handlers) |

Always prefer `astream` in async web frameworks. Sync `stream`
blocks the event loop.

---

## Common pitfalls

1. **`version="v2"` missing** — `astream_events` without it gives
   the old format. Always include it.
2. **`astream_events` is async** — you must `async for`. Don't mix
   sync streaming in an async function.
3. **`stream_mode="messages"` doesn't surface tool events.** Use
   `astream_events` if you need tool call visibility in your stream.
4. **Tool calls arrive over multiple chunks** — wait for
   `on_chat_model_end` before processing `tool_calls` from an
   event stream.
5. **Interrupts during streaming** — an `interrupt()` during a
   streamed run surfaces as a special event. The caller must handle
   it and decide whether to resume.

---

## See also

- [[AI/langgraph/01-mental-model|01-mental-model]] — the agent loop
- [[AI/langchain/09-streaming|../langchain/09-streaming]] — `astream_events` in depth
- [[AI/langgraph/08-checkpointers|08-checkpointers]] — checkpointers and thread IDs
---
title: "LangChain — Streaming"
tags:
  - AI
  - LangChain
  - Streaming
---

> **Part 9.** `stream`/`astream` for simple token streaming,
> `astream_events` for full lifecycle visibility, and how to
> build a streaming chat UI.

## The three streaming APIs

LangChain has three progressively more powerful streaming interfaces:

| Method | Returns | Use when |
|---|---|---|
| `stream(input)` | `Iterator[Output]` | Simple — you want the output chunks |
| `astream(input)` | `AsyncIterator[Output]` | Same, but async context |
| `astream_events(input, version="v2")` | `AsyncIterator[Event]` | You need tokens + tool calls + lifecycle |

---

## `stream` / `astream` — simple token streaming

For a chat model with `streaming=True`:

```python
from langchain_openai import ChatOpenAI

model = ChatOpenAI(model="gpt-4o-mini", streaming=True)

for chunk in model.stream([HumanMessage(content="Tell me a story")]):
    print(chunk.content, end="", flush=True)
```

`chunk` is an `AIMessageChunk`. `chunk.content` is a string delta.
For text-only responses, this is all you need.

For a chain:

```python
chain = prompt | model | parser

for chunk in chain.stream({"question": "What is Kubernetes?"}):
    print(chunk, end="", flush=True)
```

`parser` processes each chunk as it arrives. For `StrOutputParser`,
each chunk is a string delta.

### `streaming=True` must be set on the constructor

If you forget `streaming=True`, `stream()` returns the full response
in one chunk (blocking). Some providers also accept `streaming` as a
kwarg per-call; the constructor flag is the reliable default.

---

## `astream_events` — the full lifecycle API

`astream_events(version="v2")` is the only API that surfaces both
tokens and tool calls. It yields lifecycle events from every
component:

```python
async for event in graph.astream_events(input, config, version="v2"):
    print(event)
```

Each event is a dict:

```python
{
    "event": "on_chat_model_stream",
    "name": "ChatOpenAI",
    "run_id": "...",
    "parent_ids": [...],
    "tags": [...],
    "metadata": {...},
    "data": {"chunk": AIMessageChunk(...)},
    "created_at": datetime,
}
```

### Event taxonomy

| Event | Emitted by | `data` |
|---|---|---|
| `on_chat_model_start` | Model begins | `input` (the messages) |
| `on_chat_model_stream` | Token arrives | `chunk` (AIMessageChunk) |
| `on_chat_model_end` | Model done | `output` (AIMessage) |
| `on_tool_start` | Tool begins | `input` (the args) |
| `on_tool_end` | Tool completes | `output` (the result) |
| `on_chain_start/end/stream` | RunnableSequence | `input`/`output`/`chunk` |
| `on_retriever_start/end` | Retriever | `input`/`output` |
| `on_error` | Exception | `error` |

### Filtering events

The stream is loud. Filter to reduce noise:

```python
async for event in graph.astream_events(
    input,
    config,
    version="v2",
    include_types=["chat_model", "tool"],   # only these events
    exclude_types=["parser", "prompt"],     # skip these
    include_tags=["prod"],                   # only runs tagged prod
):
    ...
```

| Param | What it filters on |
|---|---|
| `include_names` | The `name` of the runnable (e.g. "call_model") |
| `include_types` | Kind: "chat_model", "tool", "chain", "retriever" |
| `include_tags` | The `tags` on the runnable |
| `exclude_*` | Same, but exclusion |

### `version="v2"` is required

Without `version="v2"`, you get the old format. `"v2"` is always
correct for new code.

---

## Building a streaming chat UI

### Token streaming with `astream`

```python
async def chat():
    model = ChatOpenAI(model="gpt-4o-mini", streaming=True)

    async for chunk in model.astream([HumanMessage(content="Tell me a story")]):
        if chunk.content:
            yield chunk.content
```

### Token + tool call tracking with `astream_events`

```python
async def chat_events(user_message: str):
    async for event in graph.astream_events(
        {"messages": [HumanMessage(content=user_message)]},
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

The frontend receives NDJSON and renders tokens as they arrive,
shows a spinner during tool execution, and displays usage at the end.

### `stream_mode="messages"` — LangGraph's built-in streaming

LangGraph's `astream` supports a `stream_mode="messages"` that
yields message deltas:

```python
async for message_chunk, metadata in graph.astream(
    {"messages": [HumanMessage(content="hi")]},
    stream_mode="messages",
):
    print(message_chunk.content, end="")
```

`metadata` includes `streamable_node` (which node emitted the chunk).
This is simpler than `astream_events` for the common case.

---

## Merging `AIMessageChunk`s into a full `AIMessage`

```python
full: AIMessage | None = None
async for chunk in model.astream([HumanMessage(content="hi")]):
    full = chunk if full is None else full + chunk

# full is now the complete AIMessage
print(full.content)
print(full.usage_metadata)
```

The `+` operator on `AIMessage` and `AIMessageChunk` merges them.
Use this when you need the final `AIMessage` after streaming.

---

## `batch` / `abatch` — bulk processing

```python
results = chain.batch([
    {"input": "question 1"},
    {"input": "question 2"},
    {"input": "question 3"},
])
# results is a list of outputs, one per input, sequential
```

For parallel bulk processing:

```python
results = await chain.abatch(
    inputs,
    config={"max_concurrency": 10},
)
```

`abatch` with `max_concurrency` is the right tool for "I have 100
questions, run at most 10 in parallel." Useful for backfilling
embeddings or batch processing documents.

`batch_as_completed` yields results as they finish:

```python
for result in chain.batch_as_completed(inputs):
    index, output = result
    print(f"Input {index} finished first")
```

---

## `stream_log` — structured execution log

`stream_log` yields `RunLogPatch` objects — more structured than
`astream_events` but more verbose. Used internally by LangSmith.
For application-level streaming, prefer `astream_events`.

```python
async for patch in chain.stream_log(input):
    print(patch)
```

---

## Common pitfalls

1. **`streaming=True` not set** — `stream()` returns everything
   in one chunk. Set it on the constructor.
2. **`version="v2"` missing** — `astream_events` without it gives
   the old format. Always include it.
3. **`astream_events` is async.** You must `async for`. Don't mix
   sync and async streaming in the same function.
4. **Tool calls arrive over multiple chunks.** Don't assume a
   `ToolCall` is complete after one `on_chat_model_stream` event.
   Wait for `on_chat_model_end` before processing `tool_calls`.
5. **`stream_mode="messages"` doesn't include tool events.** Use
   `astream_events` if you need tool call visibility.
6. **`abatch` without `max_concurrency`** runs sequentially.
   Set it if you want parallelism.

---

## See also

- [[AI/langchain/06-runnables-lcel|06-runnables-lcel]] — the `Runnable` interface and `astream_events` in depth
- [[AI/langchain/03-chat-models|03-chat-models]] — `streaming=True` on the constructor
- [[AI/langchain/10-testing|10-testing]] — testing streaming code with `FakeListChatModel`
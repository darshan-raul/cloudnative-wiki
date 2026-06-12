---
title: "LangChain — Messages"
tags:
  - AI
  - LangChain
  - Messages
---

> **Part 2.** Messages are the atom of LangChain. Every chat model
> call is "send a list of messages, get back a new message." Read
> this before anything else that calls a model.

## The five message types

Everything in LangChain is built on five message types from
`langchain_core.messages`:

```python
from langchain_core.messages import (
    SystemMessage,   # developer instructions
    HumanMessage,    # user input
    AIMessage,       # model output
    AIMessageChunk,  # streaming piece
    ToolMessage,     # tool result
    RemoveMessage,   # for trimming history
    # legacy — do not use:
    FunctionMessage,
)
```

The model sees a **list** of these. The model returns **one** of
these. Tools return values that get wrapped in one of these.

---

## SystemMessage — developer instructions

The system message is the only message you (the developer) write
freely. It shapes the model's behavior:

```python
from langchain_core.messages import SystemMessage

msg = SystemMessage(content="You are a helpful assistant that always "
                            "answers in French.")
```

What the model actually sees (after LangChain serializes it):

```json
{"role": "system", "content": "You are a helpful assistant..."}
```

The system message goes first and stays for the entire conversation.
For static behavior (persona, rules), a literal `SystemMessage` is
enough. For variable behavior (per-user context, injected docs),
use `ChatPromptTemplate` — see [[AI/langchain/05-prompts]].

**Common pattern for RAG:** inject retrieved context as a
`SystemMessage`, not a `HumanMessage`. The model treats the system
slot as instructions, not user input.

```python
messages = [
    SystemMessage(content=f"Use these documents to answer:\n\n{retrieved_docs}"),
    HumanMessage(content="What is Kubernetes?"),
]
```

---

## HumanMessage — the user's input

```python
from langchain_core.messages import HumanMessage

msg = HumanMessage(content="What is the weather in Tokyo?")
```

**The `id` field.** Every message has an `id` (a UUID by default).
You can set it explicitly:

```python
msg = HumanMessage(content="...", id="user-msg-1")
```

Set it when you're replaying a logged conversation or restoring
from a database with stable IDs.

**Multi-modal content.** The `content` field accepts a list for
image/audio input:

```python
msg = HumanMessage(content=[
    {"type": "text", "text": "What's in this screenshot?"},
    {"type": "image_url", "image_url": {"url": "https://example.com/screenshot.png"}},
])
```

This follows the OpenAI multimodal format. Most providers
(OpenAI, Anthropic via LiteLLM, Bedrock) support it.

---

## AIMessage — what the model returns

This is the big one. When you call a chat model, you get back an
`AIMessage`:

```python
from langchain_core.messages import AIMessage

response = model.invoke([HumanMessage(content="hi")])
# response is an AIMessage
```

### The three key fields

```python
response.content          # str — the model's text response (or "" if it only called tools)
response.tool_calls       # list[ToolCall] — structured tool call requests
response.usage_metadata   # dict — token counts (input, output, total)
```

Example — the model calls a tool:

```python
response = model_with_tools.invoke([HumanMessage(content="What's the weather in Tokyo?")])

print(response.content)   # "" (empty — the model only called a tool)
print(response.tool_calls)
# [ToolCall(name='get_weather', args={'city': 'Tokyo'}, id='call-abc123')]
```

Example — the model responds with text only:

```python
response = model.invoke([HumanMessage(content="Say hello")])

print(response.content)   # "Hello! How can I help you?"
print(response.tool_calls)  # []
```

Example — the model does both (some providers support this):

```python
response = model_with_tools.invoke([HumanMessage(content="Tell me about Tokyo")])

print(response.content)   # "Let me check the weather for Tokyo..."
print(response.tool_calls)  # [ToolCall(name='get_weather', ...)]
```

### The `tool_calls` field — the correlation key

`ToolCall` is a typed dict, not a `Message`. It has:

```python
ToolCall(
    name="get_weather",   # which tool to call
    args={"city": "Tokyo"},  # the arguments
    id="call-abc123",     # the correlation ID
)
```

**The `id` is critical.** When a tool returns its result, you must
wrap it in a `ToolMessage` with the **same `id`** as the `ToolCall`
that requested it. The model uses this to correlate the result with
the call:

```python
ToolMessage(
    content="The weather in Tokyo is sunny and 72°F.",
    tool_call_id="call-abc123",   # must match the ToolCall.id
)
```

If the IDs don't match, the model has no way to know which tool
call this result answers. **This is the single most common bug in
agent code.** LangGraph's `ToolNode` handles this automatically;
if you build `ToolMessage`s by hand, double-check.

### The `id` field on AIMessage

The `AIMessage.id` is the message's unique ID (a UUID by default).
It's used by checkpointers for deduplication. You usually don't
need to set it, but if you're reconstructing a conversation from
storage, you can:

```python
msg = AIMessage(content="...", id="msg-xyz-789")
```

### `usage_metadata` — token counts and cost

```python
response.usage_metadata
# {'input_tokens': 87, 'output_tokens': 12, 'total_tokens': 99}
```

Sum across a conversation to compute cost:

```python
def cost_of(response: AIMessage, rates: dict) -> float:
    u = response.usage_metadata or {}
    input_t = u.get("input_tokens", 0)
    output_t = u.get("output_tokens", 0)
    return (input_t / 1000) * rates["input"] + (output_t / 1000) * rates["output"]

rates = {"input": 0.00015, "output": 0.00060}  # $/token
cost = cost_of(response, rates)
```

### `response_metadata` — provider-specific extras

```python
response.response_metadata
# {'model_name': 'gpt-4o-mini', 'finish_reason': 'stop'}
```

Common keys: `finish_reason` (`stop`, `length`, `tool_calls`),
`system_fingerprint`, `logprobs`.

Use `finish_reason == "length"` to detect truncated responses
and retry with a higher `max_tokens`.

---

## AIMessageChunk — streaming responses

When you call a model with `streaming=True`, you get an iterator
of `AIMessageChunk` objects. Each chunk has the same shape as
`AIMessage` but carries only the **delta** for that chunk:

```python
model = ChatOpenAI(model="gpt-4o-mini", streaming=True)

for chunk in model.stream([HumanMessage(content="Tell me a story")]):
    print(chunk.content, end="", flush=True)
```

`chunk.content` is a string delta. `chunk.tool_call_chunks` is a
list of partial tool-call deltas (tool calls may arrive over
several chunks).

To reconstruct the full `AIMessage`:

```python
full: AIMessage | None = None
for chunk in model.stream([HumanMessage(content="hi")]):
    full = chunk if full is None else full + chunk

# full is now the complete AIMessage
```

The `+` operator on `AIMessage` and `AIMessageChunk` merges them.

---

## ToolMessage — the result of a tool call

A `ToolMessage` wraps a tool's result. It's appended to the messages
list so the model can see it:

```python
from langchain_core.messages import ToolMessage

tool_msg = ToolMessage(
    content="The weather in Tokyo is sunny and 72°F.",
    tool_call_id="call-abc123",   # must match the ToolCall.id from the AIMessage
)
```

### The three required fields

```python
ToolMessage(
    content="...",        # always a string — the model's only view of the result
    tool_call_id="...",   # must match an AIMessage.tool_calls[i].id
    name="get_weather",   # the tool name (for the model's benefit)
)
```

### `content` is always a string

**This is the most common bug in agent code:**

```python
# WRONG — model sees the repr of a list, not the data
ToolMessage(content=[{"id": "cl-001"}], ...)

# RIGHT — serialize explicitly
ToolMessage(content='[{"id": "cl-001"}]', ...)
```

The model's only view is `content` (a string). If your tool returns
a Pydantic model, serialize it:

```python
from pydantic import BaseModel

class Cluster(BaseModel):
    id: str
    status: str

@tool
def list_clusters() -> list[Cluster]:
    return [Cluster(id="cl-001", status="READY")]

# When the ToolMessage is built by ToolNode, it calls str() on the return.
# For a list of Pydantic models, str([...]) is not JSON.
# Serialize explicitly:
@tool
def list_clusters() -> str:   # return type is str
    clusters = [Cluster(id="cl-001", status="READY")]
    return json.dumps([c.model_dump() for c in clusters])
```

Or use `StructuredTool` with `response_format="content"` (default)
and ensure your return value serializes cleanly.

### `status` — telling the model something went wrong

```python
ToolMessage(
    content="Cluster cl-999 not found.",
    tool_call_id="call-abc123",
    name="get_cluster_status",
    status="error",   # "success" (default) or "error"
)
```

The model sees the error and can react (retry, explain, ask for
clarification). **Use this instead of raising.** Raising kills the
graph run; erroring-in-content keeps the agent loop alive.

### `artifact` — data the model shouldn't see

The model reads only `content` (a string). For data the model
shouldn't see but your code needs (a DataFrame, an image):

```python
ToolMessage(
    content="Image returned (1024x768).",
    tool_call_id="call-xyz",
    name="get_screenshot",
    artifact=PILImage.open(...),   # available to your code, not the model
)
```

### The alternation invariant

In a chat agent, messages must alternate correctly:

```
HumanMessage → AIMessage → ToolMessage → AIMessage → ToolMessage → AIMessage
```

The model never sees a `ToolMessage` without a preceding `AIMessage`
that requested it. `ToolNode` enforces this. If you build state by
hand, respect the alternation.

---

## RemoveMessage — trimming conversation history

In a stateful agent, the message list grows forever. To prune old
messages:

```python
from langgraph.graph.message import RemoveMessage

def trimmer(state):
    msgs = state["messages"]
    # keep only the last 10 messages
    return {
        "messages": [
            RemoveMessage(id=m.id) for m in msgs[:-10]
        ]
    }
```

The `add_messages` reducer honors `RemoveMessage` and deletes
matching IDs.

A simpler approach is `trim_messages` from `langchain_core.messages`:

```python
from langchain_core.messages import trim_messages

trimmed = trim_messages(
    messages,
    max_tokens=4000,
    token_counter=model,   # uses the model's tokenizer
    strategy="last",       # keep most recent, drop oldest
)
```

`strategy="last"` keeps the last N tokens. `strategy="first"` keeps
the oldest. Use `start_on="human"` to always start with a
`HumanMessage` — you never want an `AIMessage` as the first message
to a model.

---

## The complete message lifecycle

Here's the full loop from a single user message to a final response:

```python
# 1. Build the initial messages list
messages = [
    SystemMessage(content="You are a helpful assistant."),
    HumanMessage(content="What's the weather in Tokyo?"),
]

# 2. Call the model (with tools bound)
response = model_with_tools.invoke(messages)
# response is an AIMessage
# response.tool_calls = [ToolCall(name='get_weather', args={'city': 'Tokyo'}, id='call-1')]

# 3. Append the model's response to the messages list
messages.append(response)

# 4. Run the tool
tool_result = get_weather.invoke({"city": "Tokyo"})
# tool_result is a str: "The weather in Tokyo is sunny and 72°F."

# 5. Build a ToolMessage with the SAME id as the ToolCall
tool_msg = ToolMessage(
    content=tool_result,
    tool_call_id="call-1",   # must match ToolCall.id
    name="get_weather",
)
messages.append(tool_msg)

# 6. Call the model again with the updated messages
response2 = model_with_tools.invoke(messages)
# response2.content = "The weather in Tokyo is sunny and 72°F."
# response2.tool_calls = [] (no more tools to call)

messages.append(response2)
# messages is now: SystemMessage, HumanMessage, AIMessage(tool_call),
#                  ToolMessage, AIMessage(final)
```

This is the agent loop. LangGraph automates steps 2–6 and handles
the state management so you don't build the list by hand.

---

## Common pitfalls

1. **`ToolMessage.content` must be a string.** `json.dumps()` or
   `str()` your data first. A list or dict will confuse the model.
2. **Mismatched `tool_call_id`.** The `ToolMessage`'s `tool_call_id`
   must match the `AIMessage.tool_calls[i].id`. Mismatch = broken
   correlation.
3. **Mutating `messages` in place.** Don't do `messages.append(...)`
   by hand in a graph. Return a partial update `{"messages": [...]}`.
4. **`content=""` vs `content=[]` for tool-only responses.** Both
   are legal. Most providers return `""` by convention.
5. **`FunctionMessage` is legacy.** It was the pre-tool-calls way
   to return function results. Use `ToolMessage`.
6. **Sending an `AIMessage` as the first message to a model.** The
   model has no context for it. Always start with `SystemMessage`
   then `HumanMessage`.
7. **Forgetting that `content` can be a list** (for multi-modal).
   Code that does `str(msg.content)` works for both string and list
   content, but code that does `msg.content.upper()` fails on lists.

---

## See also

- [[AI/langchain/01-mental-model|01-mental-model]] — what LangChain is and why it exists
- [[AI/langchain/03-chat-models|03-chat-models]] — what `AIMessage` fields mean when the model returns
- [[AI/langchain/04-tools|04-tools]] — how tools return `ToolMessage`s
- [[AI/langchain/08-langgraph-intro|08-langgraph-intro]] — the agent loop above, automated by LangGraph
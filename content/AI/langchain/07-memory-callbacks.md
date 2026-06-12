---
title: "LangChain — Memory, Callbacks & Tracing"
tags:
  - AI
  - LangChain
  - Memory
  - Callbacks
  - Tracing
---

> **Part 7.** Caching, the `BaseCallbackHandler` interface, LangSmith
> tracing, and why LangChain's own memory classes are legacy.

## Caching chat model responses

`set_llm_cache(...)` installs a global cache. Subsequent calls with
the same `(model, messages, kwargs)` tuple return the cached result
without hitting the model.

```python
from langchain_core.globals import set_llm_cache
from langchain_core.caches import InMemoryCache

set_llm_cache(InMemoryCache())
```

Restart the process and the cache is gone. Good for dev and tests.

### The cache classes

| Class | Backend | When to use |
|---|---|---|
| `InMemoryCache` | Python dict | Dev, tests, single-process |
| `SQLiteCache` | SQLite file | Single-process, persistent |
| `RedisCache` | Redis | Multi-process, multi-host |
| `RedisSemanticCache` | Redis + embeddings | Similar but not identical queries |
| `UpstashRedisCache` | Upstash serverless Redis | Edge / serverless |

```python
# Persistent across restarts
from langchain_community.cache import SQLiteCache

set_llm_cache(SQLiteCache(database_path=".langchain.db"))

# Multi-host
from langchain_community.cache import RedisCache

set_llm_cache(RedisCache(redis_=redis.Redis.from_url("redis://...")))
```

### What is and isn't cached

The cache key is `(model, messages, kwargs)`. Two calls to the same
model with the same messages get the same result. Two calls with
different messages (even if semantically similar) miss the cache.

`RedisSemanticCache` uses embeddings to cache semantically similar
queries — useful for RAG where the same question phrased slightly
differently should hit the cache.

### `set_llm_cache` is global

It affects all chat models in the process. Reset in tests:

```python
@pytest.fixture(autouse=True)
def fresh_cache():
    from langchain_core.globals import set_llm_cache
    from langchain_core.caches import InMemoryCache
    set_llm_cache(InMemoryCache())
    yield
```

---

## `BaseCallbackHandler` — the hook system

`BaseCallbackHandler` lets you intercept events across the LangChain
stack. Every `invoke`, `stream`, `astream_events` call can carry
callbacks:

```python
from langchain_core.callbacks import BaseCallbackHandler

class MyHandler(BaseCallbackHandler):
    def on_chat_model_start(self, serialized, messages, *, run_id, **kwargs):
        print(f"Model call started: {run_id}")

    def on_chat_model_end(self, output, *, run_id, **kwargs):
        u = output.usage_metadata or {}
        print(f"Tokens: {u.get('input_tokens', 0)} in, {u.get('output_tokens', 0)} out")

    def on_tool_start(self, serialized, input, *, run_id, **kwargs):
        print(f"Tool {serialized.get('name')} called with {input}")
```

Pass callbacks via `RunnableConfig`:

```python
result = chain.invoke(
    input,
    config={"callbacks": [MyHandler()]},
)
```

Or at construction time (applies to all calls):

```python
model = ChatOpenAI(model="gpt-4o-mini").with_config(
    callbacks=[MyHandler()],
)
```

### The key hooks

| Hook | When | Common use |
|---|---|---|
| `on_chat_model_start` | Model called | Log request, add span context |
| `on_chat_model_stream` | Token arrives | Stream to frontend, accumulate |
| `on_chat_model_end` | Model done | Log tokens, record cost |
| `on_tool_start` | Tool begins | Log which tool, with what args |
| `on_tool_end` | Tool completes | Log result, duration |
| `on_chain_start/end` | RunnableSequence starts/ends | Trace pipeline sections |
| `on_error` | Exception raised | Alert, record error |
| `on_retry` | Retry about to happen | Log backoff, cancel retry |

### `on_chat_model_stream` — token accumulation

```python
class TokenAccumulator(BaseCallbackHandler):
    def __init__(self):
        self.tokens = []

    def on_chat_model_stream(self, chunk, *, run_id, **kwargs):
        if chunk.content:
            self.tokens.append(chunk.content)

accumulator = TokenAccumulator()
chain.invoke(input, config={"callbacks": [accumulator]})
print("".join(accumulator.tokens))
```

### `on_chat_model_end` — cost tracking

```python
class CostTracker(BaseCallbackHandler):
    def __init__(self):
        self.calls = []

    def on_chat_model_end(self, output, *, run_id, **kwargs):
        u = output.usage_metadata or {}
        self.calls.append({
            "run_id": str(run_id),
            "model": output.response_metadata.get("model_name"),
            "input_tokens": u.get("input_tokens", 0),
            "output_tokens": u.get("output_tokens", 0),
        })

cost_tracker = CostTracker()
result = graph.invoke(input_state, config={"callbacks": [cost_tracker]})
print(cost_tracker.calls)
```

`output` is the `AIMessage` returned by the model. `usage_metadata`
is the token counts. `response_metadata` has provider-specific fields
like `model_name`.

### Async callbacks

LangChain awaits coroutine methods if the hook is async. Don't
define both sync and async versions of the same hook — pick one.

```python
class AsyncHandler(BaseCallbackHandler):
    async def on_chat_model_end(self, output, *, run_id, **kwargs):
        await db.log_call(run_id=run_id, tokens=output.usage_metadata)
```

---

## LangSmith tracing

LangSmith is LangChain's observability product. Enable it:

```python
import os
os.environ["LANGCHAIN_TRACING_V2"] = "true"
os.environ["LANGCHAIN_API_KEY"] = "ls__..."
os.environ["LANGCHAIN_PROJECT"] = "my-project"   # defaults to "default"
```

Once enabled, every LangChain call is traced automatically. Traces
show the full chain of events — model calls, tool calls, chain
steps — with timing, tokens, and metadata.

### Tagging and filtering traces

```python
result = chain.invoke(
    input,
    config={
        "tags": ["prod", "user-facing"],
        "metadata": {"user_id": "user-42"},
    },
)
```

Filter traces in LangSmith by tag or metadata. Use `tags` for
deployment context, `metadata` for user/request context.

### `hidden` — exclude sensitive data

```python
result = chain.invoke(
    input,
    config={"tags": ["hidden"]},
)
```

Traces tagged `hidden` don't appear in LangSmith. Use for prompts
that contain PII or other sensitive data.

### `patch_langchain_environment` — test isolation

```python
from langchain_core.env import patch_langchain_environment

with patch_langchain_environment():
    # Inside this block, LANGCHAIN_TRACING_V2 is unset
    # Tests don't accidentally hit LangSmith
    ...
```

---

## Why LangChain's memory classes are legacy

The old memory classes (`ConversationBufferMemory`,
`ConversationEntityMemory`, etc.) from `langchain.memory` are
wrappers that stuff messages into a list. They were designed for
the older `LLMChain` / `AgentExecutor` pattern:

```python
# OLD — do not use
from langchain.memory import ConversationBufferMemory
from langchain.agents import AgentExecutor, ZeroShotAgent

memory = ConversationBufferMemory(memory_key="chat_history")
agentExecutor = AgentExecutor.from_agent_and_tools(
    agent=agent, tools=tools, memory=memory,
)
```

This pattern is deprecated. The modern replacement is:
- **LangGraph checkpointer** for conversation state persistence
- **Message list in the graph state** as the primary memory store

The checkpointer handles thread IDs, state serialization, and
resuming after interruption. The messages list is just a Python list
in the graph state — no special memory class needed.

See [[AI/langchain/08-langgraph-intro]] for how checkpointers work.

---

## Common pitfalls

1. **`set_llm_cache` is global** — affects all chat models in the
   process. Reset in tests to avoid cross-test pollution.
2. **`InMemoryCache` doesn't share across replicas.** Two agent-service
   pods have two caches. Use `RedisCache` for shared caching.
3. **`on_chat_model_stream` fires per token**, not per call.
   `on_chat_model_end` fires once per model call. Use the right
   hook for the right purpose.
4. **`astream_events` is not the same as `callbacks`.** They overlap
   but events is the higher-level API. For application-level
   observability, prefer `astream_events`. For per-call hooks,
   use callbacks.
5. **LangSmith traces everything** including PII in the prompt. Use
   the `hidden` tag or skip in prod.
6. **`get_openai_callback` only works for OpenAI**, not for LiteLLM
   (which presents as OpenAI but the actual call is Bedrock). Use
   `usage_metadata` instead.
7. **`on_retry` is not cancelable.** You can log it, but you can't
   stop the retry from happening.

---

## See also

- [[AI/langchain/06-runnables-lcel|06-runnables-lcel]] — how `astream_events` works
- [[AI/langchain/08-langgraph-intro|08-langgraph-intro]] — checkpointers for persistent conversation state
- [[AI/langchain/10-testing|10-testing]] — using `BaseCallbackHandler` in tests
- [LangChain callbacks docs](https://python.langchain.com/docs/concepts/callbacks/)
- [LangChain caching docs](https://python.langchain.com/docs/how_to/llm_caching/)
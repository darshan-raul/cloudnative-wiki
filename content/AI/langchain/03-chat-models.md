---
title: "LangChain — Chat Models"
tags:
  - AI
  - LangChain
  - Chat Models
---

> **Part 3.** How chat models work in LangChain — the `BaseChatModel`
> interface, `ChatOpenAI`, `bind_tools`, `with_structured_output`,
> and `with_retry`.

## The `BaseChatModel` interface

All chat models in LangChain inherit from `BaseChatModel`. They all
implement the `Runnable` interface — `invoke`, `stream`, `ainvoke`,
`astream`, `batch`, `abatch`.

The main ones:

| Class | Package | When to use |
|---|---|---|
| `ChatOpenAI` | `langchain_openai` | OpenAI, or any OpenAI-compatible endpoint (LiteLLM, vLLM, Ollama) |
| `ChatAnthropic` | `langchain_anthropic` | Direct Anthropic |
| `ChatBedrock` | `langchain_aws` | AWS Bedrock |
| `ChatOllama` | `langchain_ollama` | Local Ollama |
| `FakeListChatModel` | `langchain_core.language_models.fake_chat_models` | Tests only |

All expose `bind_tools`, `with_structured_output`, `with_retry`,
`with_fallbacks`, and `with_config`.

---

## ChatOpenAI — the workhorse

`ChatOpenAI` is the main chat model class. It wraps the OpenAI SDK
but works with any OpenAI-compatible endpoint:

```python
from langchain_openai import ChatOpenAI

# Direct to OpenAI
model = ChatOpenAI(model="gpt-4o", api_key="sk-...")

# Via a proxy (LiteLLM, vLLM, etc.)
model = ChatOpenAI(
    model="claude-3-5-haiku",          # the model's alias on the proxy
    base_url="http://localhost:4000/v1",  # must end in /v1
    api_key="...",                        # the proxy's key
)

# Local Ollama
model = ChatOpenAI(
    model="llama3",
    base_url="http://localhost:11434/v1",
    api_key="ollama",   # no auth needed for local
)
```

**`base_url` must end in `/v1`.** The OpenAI SDK appends
`/chat/completions` to whatever you pass. If you pass
`http://localhost:4000` (no `/v1`), the SDK calls
`http://localhost:4000/chat/completions` and gets a 404.

### Common constructor kwargs

| Kwarg | Default | What |
|---|---|---|
| `model` | (required) | Provider-specific model name/alias |
| `temperature` | provider default | 0 = deterministic, 1 = creative. 0.2–0.5 for most tasks |
| `max_tokens` | provider default | Cap on output tokens |
| `timeout` | provider default | HTTP timeout in seconds |
| `max_retries` | `6` | SDK retries transient errors (429, 5xx) |
| `streaming` | `False` | Whether `stream`/`astream` yield chunks |

```python
model = ChatOpenAI(
    model="gpt-4o-mini",
    temperature=0.2,
    max_tokens=2048,
    timeout=60,
    max_retries=2,
    streaming=False,
)
```

### Provider-specific kwargs via `model_kwargs`

Anything the provider supports but LangChain doesn't abstract:

```python
model = ChatOpenAI(
    model="gpt-4o-mini",
    model_kwargs={
        "top_p": 0.9,
        "presence_penalty": 0.1,
    },
)
```

For Bedrock via LiteLLM, pass provider-specific params through
`extra_body`:

```python
model_kwargs={
    "extra_body": {"anthropic_version": "bedrock"},
}
```

---

## `bind_tools` — exposing tools to the model

`bind_tools(tools)` returns a new `Runnable` that, when invoked,
can emit `AIMessage`s with `tool_calls` populated. The model decides
whether to call a tool based on the tool's name and description.

```python
from langchain_core.messages import HumanMessage
from langchain_openai import ChatOpenAI

model = ChatOpenAI(model="gpt-4o-mini")

# A tool (defined with @tool — see 04-tools)
@tool
def get_weather(city: str) -> str:
    """Get the current weather for a city.

    Use this when the user asks about the weather in a specific city.
    """
    return f"The weather in {city} is sunny and 72°F."

# Bind the tool to the model
model_with_tools = model.bind_tools([get_weather])

# Call it
response = model_with_tools.invoke([
    HumanMessage(content="What's the weather in Tokyo?")
])

print(response.tool_calls)
# [ToolCall(name='get_weather', args={'city': 'Tokyo'}, id='call-abc123')]
```

What the model sees in the API request (serialized from the tool):

```json
{
  "type": "function",
  "function": {
    "name": "get_weather",
    "description": "Get the current weather for a city. Use this when the user asks about the weather in a specific city.",
    "parameters": {
      "type": "object",
      "properties": {"city": {"type": "string"}},
      "required": ["city"]
    }
  }
}
```

### `tool_choice` — forcing or preventing tool use

```python
llm = ChatOpenAI(model="gpt-4o-mini").bind_tools(
    tools=[get_weather],
    tool_choice="auto",    # model decides (default)
)
```

| `tool_choice` | Behavior |
|---|---|
| `"auto"` | Model decides whether to call a tool. |
| `"any"` | Model must call at least one tool (any of them). |
| `"none"` | Model is not allowed to call a tool. |
| `"get_weather"` | Model must call that specific tool. |
| `{"type": "function", "function": {"name": "get_weather"}}` | Same as the string form. |

Use `"any"` when you want to force the model to commit to a tool
before proceeding (e.g., confirmation flows).

### `parallel_tool_calls` — multiple tools in one turn

```python
llm = model.bind_tools([tool_a, tool_b], parallel_tool_calls=True)
```

`True` (default) lets the model emit multiple `tool_calls` in one
`AIMessage`. For example: "list my clusters and tell me about the
oldest one" might emit `[list_clusters, get_cluster_status]`.

`False` forces one tool at a time. Easier to test and debug.

### `strict=True` — OpenAI's structured arguments

OpenAI supports a stricter mode where the model can only emit
arguments that match the schema exactly (correct types, all required
fields present, no extra keys). Passed through LiteLLM to OpenAI.
Not supported by all providers.

```python
llm = model.bind_tools([complex_tool], strict=True)
```

For most tools, the default is fine. Enable `strict` when the args
feed into a Pydantic request body where type errors would be
problematic.

---

## `with_structured_output` — force a typed response

If you don't want tool calls but want the model to return data
matching a schema:

```python
from pydantic import BaseModel
from langchain_openai import ChatOpenAI

class ClusterSummary(BaseModel):
    count: int
    oldest_region: str
    newest_region: str

model = ChatOpenAI(model="gpt-4o-mini")
structured_model = model.with_structured_output(ClusterSummary)

result = structured_model.invoke([
    HumanMessage(content="List my clusters and tell me about them.")
])

print(result.count)           # 3
print(result.oldest_region)   # us-east-1
# result is a ClusterSummary instance, not an AIMessage
```

How it works under the hood:

1. **Tool calling** — LangChain converts the schema to a tool
   definition and uses `bind_tools` internally. Then parses the
   tool call's `args` as the schema. Most reliable.
2. **JSON mode** — sends `response_format={"type": "json_object"}`
   and instructs the model via prompt. Less reliable.
3. **Provider-native structured output** — OpenAI's `strict_tools`,
   Anthropic's tool use. Highest reliability when available.

### Supported schemas

- A `TypedDict` → returns a dict
- A Pydantic `BaseModel` → returns an instance
- A JSON schema → returns a dict matching the schema
- An `Enum` → returns an enum member

### `include_raw=True` — when you need both

```python
structured_model = model.with_structured_output(
    ClusterSummary,
    include_raw=True,
)

result = structured_model.invoke([HumanMessage(content="...")])

# result is:
# {
#     "raw": AIMessage,                  # the raw response
#     "parsed": ClusterSummary | None,  # the parsed result
#     "parsing_error": Exception | None, # if parsing failed
# }
```

Use `include_raw` in tests and early development. Turn it off for
production.

---

## `with_retry` — automatic retries

```python
model = ChatOpenAI(model="gpt-4o-mini").with_retry(
    stop_after_attempt=3,
    wait_exponential_jitter=True,
    exponential_jitter_params={"initial": 1, "max": 10},
    retry_if_exception_type=(openai.APITimeoutError, openai.RateLimitError),
)
```

The retry wraps the `invoke`/`ainvoke` call. It does **not** re-run
your node; from the graph's perspective it's one call.

**When to use this vs. LiteLLM retries:**
- Use **LiteLLM retries** when you want a single place to configure
  retries for all models (recommended for most setups).
- Use **`with_retry`** when you want per-call control — e.g., one
  tool is HTTP-bound and should retry on `httpx.ConnectError`,
  another is CPU-bound and shouldn't.

---

## `with_fallbacks` — graceful degradation

```python
primary = ChatOpenAI(model="gpt-4o-mini")
fallback = ChatOpenAI(model="claude-3-5-haiku")

model = primary.with_fallbacks([fallback])
```

If `primary.invoke(...)` raises, LangChain catches and tries the
fallback. The caller doesn't see the failure unless all fallbacks
also fail.

```python
model = primary.with_fallbacks(
    [fallback1, fallback2],
    exceptions_to_handle=(openai.RateLimitError, openai.APITimeoutError),
)
```

By default, all exceptions trigger fallback. Narrow with
`exceptions_to_handle` to avoid masking real bugs.

---

## `configurable_fields` — swap the model at runtime

```python
from langchain_core.runnables import ConfigurableField

model = ChatOpenAI(model="gpt-4o-mini").configurable_fields(
    model=ConfigurableField(id="model_name"),
)

# At call time, swap the model:
result = model.with_config(
    configurable={"model_name": "claude-3-5-haiku"}
).invoke(messages)
```

`configurable_alternatives` swaps the whole model:

```python
model = ChatOpenAI(model="gpt-4o-mini").configurable_alternatives(
    ConfigurableField(id="llm"),
    default_key="gpt-4o-mini",
    haiku=ChatOpenAI(model="claude-3-5-haiku"),
    opus=ChatOpenAI(model="claude-3-opus"),
)

result = model.with_config(configurable={"llm": "haiku"}).invoke(messages)
```

The `configurable` key in the `RunnableConfig` is also how you pass
runtime values like `thread_id` to checkpointers.

---

## Streaming

```python
model = ChatOpenAI(model="gpt-4o-mini", streaming=True)

for chunk in model.stream([HumanMessage(content="Tell me a story")]):
    print(chunk.content, end="", flush=True)
```

`chunk` is an `AIMessageChunk`. `chunk.content` is a string delta.
`chunk.tool_call_chunks` is a list of partial tool-call deltas.

For full observability (tokens + tool calls + lifecycle events),
use `astream_events` — see [[AI/langchain/09-streaming]].

---

## Common pitfalls

1. **`base_url` must end in `/v1`.** Missing it = 404.
2. **`bind_tools` returns a new `Runnable`**, not a modified model.
   `model.bind_tools([...]).invoke(...)`, not `model.invoke(...)`.
3. **`tool_choice="any"`** doesn't mean "call exactly one tool" —
   it means "call at least one." Combine with `parallel_tool_calls=False`
   for exactly-one behavior.
4. **`with_structured_output` returns the parsed object**, not an
   `AIMessage`. Use `include_raw=True` when you need both.
5. **`max_retries` on the constructor** retries on SDK-level errors
   (network, 5xx). It's not the same as `with_retry` which retries
   on the application level. Don't double-count.
6. **`streaming=True` must be set on the constructor** (or passed
   per-call in some providers). Without it, `stream()` returns the
   full response in one chunk.

---

## See also

- [[AI/langchain/02-messages|02-messages]] — what the model's output (`AIMessage`) looks like
- [[AI/langchain/04-tools|04-tools]] — how `bind_tools` receives its tools
- [[AI/langchain/05-prompts|05-prompts]] — how to build the messages list with a prompt template
- [[AI/langchain/09-streaming|09-streaming]] — `stream`, `astream`, `astream_events` in depth
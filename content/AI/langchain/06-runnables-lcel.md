---
title: "LangChain — Runnables & LCEL"
tags:
  - AI
  - LangChain
  - LCEL
  - Runnables
---

> **Part 6.** The `Runnable` interface — everything in LangChain
> implements it. The `|` operator (LCEL), the composition primitives,
> `RunnableConfig`, and why you need LangGraph for agent loops.

## Everything is a `Runnable`

Every LangChain component — models, prompts, tools, parsers,
retrievers — implements `Runnable`. This means they all share the
same interface:

```python
# Sync
model.invoke(input)      # one call, full response
model.stream(input)      # one call, chunks
model.batch([inputs])    # many calls, sequential

# Async
await model.ainvoke(input)
await model.astream(input)
await model.abatch([inputs])
```

The `|` operator (pipe) chains runnables together: the output of
the left becomes the input of the right.

---

## The `|` operator — LCEL

LCEL (LangChain Expression Language) is just the `|` operator.
It builds a `RunnableSequence`:

```python
from langchain_core.prompts import ChatPromptTemplate
from langchain_openai import ChatOpenAI
from langchain_core.output_parsers import StrOutputParser

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    ("human", "{question}"),
])
model = ChatOpenAI(model="gpt-4o-mini")
parser = StrOutputParser()

chain = prompt | model | parser

result = chain.invoke({"question": "What is Kubernetes?"})
# result is a plain string
```

Each `|` adds a step to the chain. The chain is itself a `Runnable`,
so you can pipe it into another `Runnable`, bind tools to it, add
retry, add fallbacks, etc.

### What the `|` operator actually does

`prompt | model` creates a `RunnableSequence`:

```
prompt.invoke(input) → PromptValue
PromptValue → model.invoke(PromptValue) → AIMessage
```

`prompt | model | parser` continues:

```
AIMessage → parser.invoke(AIMessage) → str
```

The type of each step must match the input of the next. LangChain
validates this at construction time (or fails at invoke time if
there's a mismatch).

---

## The composition primitives

These live in `langchain_core.runnables`. They let you build
non-trivial data flow without a graph.

### `RunnableLambda` — wrap a plain function

```python
from langchain_core.runnables import RunnableLambda

def upper(x: str) -> str:
    return x.upper()

chain = prompt | model | RunnableLambda(upper)
```

Use `RunnableLambda` to shoehorn any function into the `Runnable`
system. Common uses: field extraction, dict transformation,
custom formatting.

### `RunnablePassthrough` — pass input through unchanged

```python
from langchain_core.runnables import RunnablePassthrough

chain = (
    RunnablePassthrough.assign(context=lambda x: retriever.invoke(x["question"]))
    | prompt
    | model
    | parser
)
```

`RunnablePassthrough.assign(...)` adds keys to the input dict.
`RunnablePassthrough()` alone returns the input unchanged — useful
as a no-op step.

### `RunnableParallel` — fan out

```python
from langchain_core.runnables import RunnableParallel

parallel_chain = RunnableParallel(
    summary=summarize_chain,
    details=detail_chain,
    sentiment=sentiment_chain,
)

result = parallel_chain.invoke({"text": long_article})
# result = {"summary": "...", "details": "...", "sentiment": "..."}
```

The sub-runnables run in parallel (or as parallel as the executor
allows). The output is a dict with all the keys.

Dict literal is shorthand:

```python
parallel_chain = {
    "summary": summarize_chain,
    "details": detail_chain,
}
# equivalent to RunnableParallel(summary=..., details=...)
```

### `RunnableBranch` — conditional routing

```python
from langchain_core.runnables import RunnableBranch

branch = RunnableBranch(
    (lambda x: x["type"] == "code", code_chain),
    (lambda x: x["type"] == "math", math_chain),
    default_chain,
)

result = branch.invoke({"type": "code", "input": "print('hello')"})
```

The first condition that returns `True` wins. If none match, the
default is used. If no default and no condition matches, the input
passes through unchanged.

### `RunnableWithFallbacks` — graceful degradation

```python
primary = ChatOpenAI(model="gpt-4o-mini")
fallback = ChatOpenAI(model="claude-3-5-haiku")

chain = primary.with_fallbacks([fallback])
```

If `primary.invoke(...)` raises, the fallback is tried. The caller
doesn't see the failure unless all fallbacks fail.

```python
chain = primary.with_fallbacks(
    [fallback1, fallback2],
    exceptions_to_handle=(openai.RateLimitError, openai.APITimeoutError),
)
```

By default, all exceptions trigger fallback. Narrow this to avoid
masking real bugs.

---

## `bind` vs `with_config` vs `with_retry` vs `with_fallbacks`

These all return new `Runnable` objects without mutating the
original:

| Method | What it does | Common use |
|---|---|---|
| `bind(**kwargs)` | Set per-call kwargs (model params, tools) | `stop`, `temperature`, `tools` |
| `with_config(config)` | Set `RunnableConfig` for every invocation | tags, metadata, callbacks |
| `with_retry(...)` | Wrap with retry logic | Transient errors (429, timeout) |
| `with_fallbacks([...])` | Wrap with fallback model | Provider outage, model swap |

Stack them:

```python
chain = (
    model
    .bind(stop=["\n\n"])
    .with_config(tags=["prod"])
    .with_retry(stop_after_attempt=3)
    .with_fallbacks([fallback_model])
)
```

`bind` happens first (kwargs baked in per call). `with_config`
sets the config. `with_retry` wraps the call. `with_fallbacks`
wraps the whole thing.

---

## `RunnableConfig` — the thread that ties it together

Every `invoke`/`stream`/`ainvoke` call accepts an optional
`RunnableConfig`:

```python
from langchain_core.runnables import RunnableConfig

config = RunnableConfig(
    tags=["prod", "user-facing"],
    metadata={"user_id": "user-42", "request_id": "req-123"},
    max_concurrency=10,
    recursion_limit=25,
    configurable={"thread_id": "thread-abc"},
    callbacks=[MyCallbackHandler()],
)
```

Inside a `RunnableLambda` or a tool, access the config:

```python
@RunnableLambda
def my_step(x, config: RunnableConfig):
    user_id = config.get("configurable", {}).get("user_id")
    return do_thing(x, user_id=user_id)
```

In LangGraph, the config carries `thread_id` (for checkpointer
state) and `configurable` values (for `InjectedToolArg`).

---

## `astream_events` — the full event stream

`astream_events(version="v2")` is the most powerful observability
API. It yields lifecycle events from every component:

```python
async for event in chain.astream_events(input, version="v2"):
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
    "data": {"chunk": AIMessageChunk(...)},
    "created_at": datetime,
}
```

### Event taxonomy

| Event | Emitted by | `data` content |
|---|---|---|
| `on_chat_model_start` | Chat model begins | `input` (the messages) |
| `on_chat_model_stream` | Model emits a chunk | `chunk` (AIMessageChunk) |
| `on_chat_model_end` | Model done | `output` (AIMessage) |
| `on_chain_start/end/stream` | RunnableSequence | `input`/`output`/`chunk` |
| `on_tool_start` | Tool begins | `input` (the args) |
| `on_tool_end` | Tool completes | `output` (the result) |
| `on_retriever_start/end` | Retriever | `input`/`output` |
| `on_error` | Something errored | `error` |

### Filtering events

The stream is loud. Filter with `include_names`, `include_types`,
`include_tags`, `exclude_types`:

```python
async for event in chain.astream_events(
    input,
    version="v2",
    include_types=["chat_model", "tool"],
):
    kind = event["event"]
    if kind == "on_chat_model_stream":
        yield event["data"]["chunk"].content
```

### `stream` vs `astream` vs `astream_events`

| Method | Returns | Use when |
|---|---|---|
| `stream(input)` | Iterator[Output] | You want chunks of the final output |
| `astream(input)` | AsyncIterator[Output] | Same, but async |
| `astream_events(input, version="v2")` | AsyncIterator[Event] | You want lifecycle events (tool calls, tokens, errors) |

For a chat UI that needs both tokens and tool calls, use
`astream_events`. For a simple streaming text response, use
`stream`/`astream`.

---

## Why chains are not enough — the agent loop

A chain is a linear pipeline: start → step1 → step2 → end. It can't
do this:

```
call model → tool call → tool result → call model again → tool call → ...
```

Because that requires **a loop** and **state** (the growing messages
list). You can fake it with recursive Python:

```python
def call_model(messages):
    response = model.bind_tools(tools).invoke(messages)
    if response.tool_calls:
        messages.append(response)
        for tc in response.tool_calls:
            result = tool_map[tc.name].invoke(tc.args)
            messages.append(ToolMessage(content=str(result), tool_call_id=tc.id))
        return call_model(messages)   # recursion — the loop
    return response
```

But this has no **persistence** (crash = state lost), no **human-
in-the-loop** (can't pause for approval), and no **interruption**.
For any serious agent, use LangGraph.

---

## Common pitfalls

1. **`|` requires type compatibility.** If `prompt.invoke()` returns
   a `PromptValue` and `model.invoke()` expects a `PromptValue`, it
   works. If the types don't match, LangChain raises at invoke time.
2. **`RunnableLambda` config** — the second argument to a
   `RunnableLambda` is the `config`. Don't forget to accept it if
   you need it.
3. **`astream_events(version="v2")` requires `version="v2"`.**
   Without it, you get the old format. `"v2"` is always correct.
4. **`stream` without `streaming=True`** — if the model wasn't
   constructed with `streaming=True`, `stream()` returns the full
   response in one chunk.
5. **`batch` is sequential by default.** Use `abatch` with
   `max_concurrency` for parallel execution.

---

## See also

- [[AI/langchain/01-mental-model|01-mental-model]] — chains vs agents
- [[AI/langchain/05-prompts|05-prompts]] — prompts are runnables
- [[AI/langchain/09-streaming|09-streaming]] — full streaming deep-dive
- [[AI/langchain/08-langgraph-intro|08-langgraph-intro]] — why you need LangGraph for agent loops
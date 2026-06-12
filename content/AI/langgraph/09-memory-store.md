---
title: "LangGraph — Memory Store"
tags:
  - AI
  - LangGraph
---

> **Part 9.** The memory store (`InMemoryStore`, `PostgresStore`) —
> cross-thread, long-term storage that persists across conversations.
> Different from checkpointers (which handle per-thread state).

## Checkpointers vs. Memory Stores

These are two different systems:

| | Checkpointer | Memory Store |
|---|---|---|
| Scope | Per `thread_id` | Cross-thread (global) |
| Lifetime | One conversation | Long-term (forever) |
| What it saves | Full graph state | Key-value pairs per namespace |
| Use for | Conversation history | User preferences, learned facts |

Think of checkpointers as session storage and memory stores as
long-term knowledge storage.

---

## `InMemoryStore` — dev

```python
from langgraph.store.memory import InMemoryStore

store = InMemoryStore()
graph = builder.compile(store=store)
```

RAM only. Same limitations as `MemorySaver` — restart and data is
gone. Good for dev and tests.

---

## `PostgresStore` — production

```python
from langgraph.store.postgres import PostgresStore

store = PostgresStore.from_connector(db_pool, index="chat_memory")
store.setup()   # create tables
graph = builder.compile(store=store)
```

The `index` parameter names the store (useful for multiple stores
in the same DB). `setup()` creates the tables.

---

## The store interface

### `store.put` — write a value

```python
store.put(
    namespace=("user", user_id),   # tuple of strings
    key="preferences",
    value={
        "theme": "dark",
        "language": "en",
        "timezone": "America/New_York",
    },
)
```

`namespace` is a tuple — use it to partition data. Common patterns:
`("user", user_id)`, `("session", thread_id)`, `("global", "config")`.

`value` must be JSON-serializable (dict, list, str, int, float, bool,
None). LangGraph serializes it for you.

### `store.get` — read a value

```python
result = store.get(namespace=("user", user_id), key="preferences")
# result.value == {"theme": "dark", "language": "en", ...}
# result.created_at, result.updated_at are timestamps
```

Returns `None` if the key doesn't exist.

### `store.delete` — delete a value

```python
store.delete(namespace=("user", user_id), key="preferences")
```

### `store.search` — find by prefix

```python
results = store.search(
    namespace=("user", user_id),
    prefix="pref",   # keys starting with "pref"
    limit=10,
)
```

Useful for "get all keys in this namespace" or "find all user
preferences".

---

## Using the store in a node

The store is available via `config["store"]` inside a node:

```python
def call_model(state: AgentState, config: RunnableConfig) -> dict:
    store = config["store"]

    # Look up user preferences
    prefs = store.get(namespace=("user", state["user_id"]), key="preferences")
    if prefs:
        preference_context = f"User prefers: {prefs.value}"
    else:
        preference_context = ""

    response = llm.bind_tools(tools).invoke([
        SystemMessage(content=f"You are helpful. {preference_context}"),
        *state["messages"],
    ])
    return {"messages": [response]}
```

The store is passed to the graph via `config["store"]` on compile:

```python
graph = builder.compile(store=InMemoryStore())
```

---

## Storing conversation summaries

Instead of stuffing everything into the message list, summarize
old turns and store the summary:

```python
def summarize_old_messages(state: AgentState, config: RunnableConfig) -> dict:
    store = config["store"]
    messages = state["messages"]

    if len(messages) > 10:
        # Summarize older messages
        old_messages = messages[:-5]
        summary = summarize_llm.invoke(old_messages)
        store.put(
            namespace=("user", state["user_id"]),
            key=f"summary_{len(messages)}",
            value={"summary": summary, "message_count": len(old_messages)},
        )
        return {
            "messages": [SystemMessage(content=f"Earlier summary: {summary}")]
            + messages[-5:]
        }
    return {}
```

The summary is persisted in the store. The message list stays short.
On resume, the summary is injected as a system message.

---

## Store vs. checkpointing together

```python
graph = builder.compile(
    checkpointer=PostgresSaver(conn),
    store=PostgresStore.from_connector(db_pool, index="memory"),
)
```

- `checkpointer` handles per-thread conversation state
- `store` handles cross-thread long-term knowledge

Both can be used in the same node:

```python
def call_model(state: AgentState, config: RunnableConfig) -> dict:
    checkpointer_state = config.get("configurable", {}).get("thread_id")
    store = config["store"]

    user_prefs = store.get(namespace=("user", state["user_id"]), key="prefs")
    # ...
```

---

## Common pitfalls

1. **Store and checkpointer use different backends.** You can use
   `MemorySaver` for checkpointing and `PostgresStore` for memory —
   they're independent.
2. **`namespace` must be a tuple of strings.** `("user", user_id)`
   not `["user", user_id]`.
3. **`store.put` requires JSON-serializable values.** Non-serializable
   objects fail silently (or raise at call time). Convert to dict first.
4. **`store.search` with no results** returns an empty list, not `None`.
5. **`store` is not available without `store=` in `compile()`**. If
   you try to access `config["store"]` and didn't pass a store, you
   get a `KeyError`.

---

## See also

- [[AI/langgraph/08-checkpointers|08-checkpointers]] — per-thread state persistence
- [[AI/langgraph/01-mental-model|01-mental-model]] — the persistence model
- [[AI/langchain/07-memory-callbacks|../langchain/07-memory-callbacks]] — why legacy memory classes are deprecated
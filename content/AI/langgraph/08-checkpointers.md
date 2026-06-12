---
title: "LangGraph — Checkpointers"
tags:
  - AI
  - LangGraph
---

> **Part 8.** How checkpointers save and restore graph state,
> `MemorySaver`, `SqliteSaver`, `PostgresSaver`, and how to
> configure the checkpointer on the compiled graph.

## What a checkpointer does

A checkpointer saves the graph state after each step. On the next
call with the same `thread_id`, it restores the state and resumes
from where the graph left off:

```python
from langgraph.checkpoint.memory import MemorySaver

checkpointer = MemorySaver()
graph = builder.compile(checkpointer=checkpointer)

# First call — starts fresh
config = {"configurable": {"thread_id": "thread-abc"}}
result = graph.invoke({"messages": [HumanMessage(content="hi")]}, config=config)

# Second call — resumes from saved state
result2 = graph.invoke(
    {"messages": [HumanMessage(content="What's the weather?")]},
    config=config,
)
```

The `thread_id` in `config["configurable"]` is the key. Two calls
with the same `thread_id` share the same state.

---

## Why checkpointers matter

Without a checkpointer, each `invoke` call is independent. The graph
starts from the initial state every time. Conversation history is
lost after each call.

With a checkpointer:
- **Conversation continuity** — the agent remembers what was said
  earlier in the session
- **Crash recovery** — if the server restarts mid-conversation,
  the state is recoverable
- **Human-in-the-loop** — `interrupt()` pauses the graph and the
  state is preserved while waiting for user input
- **Time travel** — inspect past states with `get_state_history`

---

## The checkpointer classes

| Class | Backend | When to use |
|---|---|---|
| `MemorySaver` | RAM | Dev, single-process |
| `SqliteSaver` | SQLite file | Single-process, persistent |
| `PostgresSaver` | PostgreSQL | Multi-host, production |

### `MemorySaver` — dev and testing

```python
from langgraph.checkpoint.memory import MemorySaver

checkpointer = MemorySaver()
graph = builder.compile(checkpointer=checkpointer)
```

RAM only — restart the process and state is gone. Good for dev and
tests. Not for production.

### `SqliteSaver` — single-host persistent

```python
from langgraph.checkpoint.sqlite import SqliteSaver

checkpointer = SqliteSaver.from_connector(connection, "my_graph")
```

Survives restarts. Good for a single-server deployment. The SQLite
file can be on a shared volume (NFS) for a single-process-per-host
setup.

### `PostgresSaver` — multi-host production

```python
from langgraph.checkpoint.postgres import PostgresSaver

checkpointer = PostgresSaver.from_connector(db_pool)
checkpointer.setup()   # create the tables if they don't exist
graph = builder.compile(checkpointer=checkpointer)
```

Shared across all agent-service replicas. The database is the
source of truth. Use a connection pool (`asyncpg` or `psycopg`).

---

## How state is serialized

The checkpointer serializes the state using the `TypedDict` field
types. `list[BaseMessage]` becomes JSON in the checkpoint. The
message IDs are preserved for deduplication by `add_messages`.

If a field contains non-serializable objects (open file handles,
DB connections), mark it with `exclude=True` in a Pydantic `Field`:

```python
class AgentState(TypedDict):
    messages: list[BaseMessage]
    db: Annotated[Session, Field(exclude=True)]   # not serialized
```

The `db` field is not saved in checkpoints. It must be provided
at invoke time via `config["configurable"]`.

---

## Time travel — `get_state_history`

```python
history = graph.get_state_history(config)

for checkpoint in history:
    print(f"Step {checkpoint.metadata['step']}: {checkpoint.values['messages'][-1]}")
```

`get_state_history` returns an iterator of checkpoints in reverse
order (most recent first). Useful for:
- Debugging — see exactly what happened at each step
- Undo — replay from an earlier checkpoint
- Audit — trace the conversation path

### Replay from a checkpoint

```python
# Get a specific checkpoint
history = list(graph.get_state_history(config))
target_checkpoint = history[2]   # step 2

# Replay from there
graph.replay(config, target_checkpoint)
```

---

## `update_state` — modify past state

```python
# Correct a wrong tool call
graph.update_state(
    config,
    {"messages": [AIMessage(content="sorry, I made a mistake")]},
)
```

`update_state` writes directly to the current checkpoint. The next
`invoke` continues from the modified state. Useful for corrections
and manual overrides.

---

## Thread ID vs configurable

```python
config = {
    "configurable": {
        "thread_id": "thread-abc",
        "user_id": "user-42",      # other runtime values
    }
}
```

`thread_id` is the checkpointer's key. Other keys in
`configurable` are available to nodes via `state["configurable"]`
— useful for passing `user_id`, `session_id`, or other runtime
context without serializing it.

---

## Checkpointer at compile time

```python
graph = builder.compile(checkpointer=MemorySaver())
```

The checkpointer is attached to the compiled graph. It cannot be
changed after compilation. Build the graph once, compile once, use
the compiled graph for all requests.

---

## Common pitfalls

1. **`thread_id` not in config** — without it, the checkpointer
   creates a new thread for every call. No continuity.
2. **Non-serializable fields without `exclude=True`** — checkpointing
   will fail on fields like open DB connections. Use `Field(exclude=True)`.
3. **`MemorySaver` doesn't survive restarts** — state is lost when
   the process restarts. Use `SqliteSaver` or `PostgresSaver` for
   persistence.
4. **`checkpointer.setup()` for Postgres** — `PostgresSaver`
   needs `setup()` called once to create the tables. `MemorySaver`
   and `SqliteSaver` don't.
5. **`get_state_history` returns a generator** — consume it
   before the next `invoke` call, or the iterator may behave
   unexpectedly.

---

## See also

- [[AI/langgraph/01-mental-model|01-mental-model]] — the agent loop and persistence
- [[AI/langgraph/07-streaming|07-streaming]] — streaming with checkpointers
- [[AI/langgraph/09-memory-store|09-memory-store]] — cross-thread memory (different from checkpointers)
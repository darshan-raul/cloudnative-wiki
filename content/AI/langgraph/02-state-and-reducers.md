---
title: "LangGraph — State & Reducers"
tags:
  - AI
  - LangGraph
---

> **Part 2.** How to define the state schema, what `add_messages`
> does, how custom reducers work, and how `MessagesState` simplifies
> the common case.

## The state schema

State is a `TypedDict`. Every field is a key that nodes read and
write:

```python
from typing import TypedDict

class AgentState(TypedDict):
    messages: list[BaseMessage]
    user_id: str
    active_form: str
```

The graph reads the type hints to know what fields exist. Each
field's Python type tells LangGraph how to serialize it for the
checkpointer.

### Adding a reducer — `Annotated[..., reducer]`

A reducer controls how a partial update merges into the current
state. Without a reducer, the field is replaced. With a reducer,
the reducer function is called:

```python
from typing import Annotated
from langgraph.graph.message import add_messages

class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]
    user_id: str
```

`add_messages` is a reducer from `langgraph.graph.message`. It
appends new messages to the list and deduplicates by message ID.

### `add_messages` — the standard reducer for messages

```python
from langgraph.graph.message import add_messages

def add_messages(left: list, right: list | BaseMessage) -> list:
    """Append right to left. If right has a message with the same id
    as one in left, replace the old one (update in place)."""
```

When a node returns `{"messages": [AIMessage(...)]}`, the framework
calls `add_messages(current_messages, [AIMessage(...)])`. The result
is the old list plus the new message appended.

**Why `add_messages` instead of a plain list?** A plain list would be
replaced on every update (wrong). With `add_messages`, updates
append, and retries/replays that return the same message ID update
in place rather than duplicate.

### `MessagesState` — the shorthand

For the common case (just messages + optional extra fields):

```python
from langgraph.graph import MessagesState

class AgentState(MessagesState):
    user_id: str       # add custom fields on top
    active_form: str
```

`MessagesState` is pre-built with `messages: Annotated[list[BaseMessage], add_messages]`.
You just add your custom fields.

---

## Custom reducers

A reducer is any callable `(current_value, update) -> new_value`:

```python
def last_write_wins(left: str, right: str) -> str:
    """Take the most recent update."""
    return right

class AgentState(TypedDict):
    value: Annotated[str, last_write_wins]
    count: Annotated[int, lambda left, right: left + right]
```

Common uses:
- **Counter:** `lambda left, right: left + right`
- **Config merge:** `lambda left, right: {**left, **right}` (deep merge)
- **Deduplication:** custom logic for a set or dict

### Reducer for a dict field

```python
from typing import TypedDict

def merge_dicts(left: dict, right: dict) -> dict:
    """Deep merge: right wins on conflict, left keys preserved."""
    result = dict(left)
    result.update(right)
    return result

class AgentState(TypedDict):
    context: Annotated[dict, merge_dicts]
    messages: Annotated[list[BaseMessage], add_messages]
```

Each node can return `{"context": {"key": "value"}}` and the dict
merges instead of replacing.

---

## What nodes return — partial updates

A node returns a **partial update**. Only the keys it wants to
change:

```python
def call_model(state: AgentState) -> dict:
    response = llm.bind_tools(tools).invoke(state["messages"])
    return {"messages": [response]}      # only messages updated

def update_context(state: AgentState) -> dict:
    return {"context": {"last_node": "call_model"}}   # only context updated
```

The graph merges the partial update into the current state using
each field's reducer.

### Returning multiple fields

```python
def call_model(state: AgentState) -> dict:
    response = llm.bind_tools(tools).invoke(state["messages"])
    return {
        "messages": [response],
        "active_form": "waiting_for_tool" if response.tool_calls else "idle",
    }
```

### Returning nothing (side-effect node)

```python
def log_to_db(state: AgentState) -> dict:
    save_to_db(state["messages"])
    return {}   # no state change — just a side effect
```

Returning an empty dict is fine. The state is unchanged.

---

## State access inside a node

Nodes are just functions. Access state by key:

```python
def call_model(state: AgentState) -> dict:
    user_id = state["user_id"]          # read
    messages = state["messages"]       # read
    ...
    return {"messages": [response]}
```

Don't mutate `state` in place. Return the update instead.

---

## Common pitfalls

1. **Forgetting the reducer on `messages`.** Without
   `Annotated[..., add_messages]`, returning `{"messages": [...]}``
   replaces the list instead of appending.
2. **Reducers must be commutative for replay to work.** If
   `merge(a, merge(b, c)) != merge(merge(a, b), c)`, checkpoint
   replay may produce different state than forward execution.
3. **`state` is immutable inside a node.** Don't do
   `state["messages"].append(...)`. Return `{"messages": [...]}``
   instead.
4. **`MessagesState` requires `messages` to be the exact field
   name.** If you name it `history` or `chat_history`, you need
   a custom state class.

---

## See also

- [[AI/langgraph/01-mental-model|01-mental-model]] — the four concepts and the agent loop
- [[AI/langgraph/03-nodes-and-edges|03-nodes-and-edges]] — adding nodes and edges to the graph
- [[AI/langgraph/08-checkpointers|08-checkpointers]] — how checkpointers use the state schema for serialization
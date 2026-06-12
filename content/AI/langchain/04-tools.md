---
title: "LangChain — Tools"
tags:
  - AI
  - LangChain
  - Tools
---

> **Part 4.** A tool is a function the model can decide to call.
> This covers `@tool`, the schema generation from type annotations,
> the docstring as the API contract, async tools, error handling,
> and `InjectedToolArg`.

## The `@tool` decorator

Turn any Python function into a LangChain tool:

```python
from langchain_core.tools import tool

@tool
def get_weather(city: str) -> str:
    """Get the current weather for a city.

    Use this when the user asks about the weather in a specific city.
    """
    return f"The weather in {city} is sunny and 72°F."
```

`@tool` returns a `StructuredTool` — a `Runnable` with a name,
description, and argument schema. The schema is derived from the
function's type annotations.

---

## The docstring is the API contract

The model decides whether to call a tool based on the tool's
**description** (the first paragraph of the docstring). This means
your docstring is the API contract between you and the model.

### Conventions for good tool descriptions

```python
@tool
def get_cluster_status(cluster_id: str) -> dict:
    """Get the current status of one EKS cluster by its id.

    Use this when the user asks for the status of a specific
    cluster, e.g. "what's the status of demo?" or "is cl-001
    ready?". Returns READY / PROVISIONING / DELETING / FAILED.

    Raises ValueError if the cluster id is not found.
    """
    ...
```

- **One-line summary first.** "Get the current status of one EKS
  cluster by its id."
- **"Use this when..." clause.** Describes intent, not mechanics.
  "Use this when the user asks about the status of a specific cluster."
- **Examples in the user voice.** The model uses these as few-shot
  hints for when to call the tool.
- **Return shape if not obvious.** "Returns READY / PROVISIONING / ..."
- **Edge cases.** "Raises ValueError if the cluster id is not found."

### `parse_docstring=True` — structured docstrings

By default, the entire docstring is the description. For long tools,
use `parse_docstring=True` to extract structured sections:

```python
@tool(parse_docstring=True)
def get_cluster_status(cluster_id: str) -> dict:
    """Get the current status of one EKS cluster by its id.

    Args:
        cluster_id: The cluster id (e.g. "cl-001").

    Returns:
        A dict with keys: id, status, last_updated, region.

    Raises:
        ValueError: if cluster_id is empty.
    """
    ...
```

LangChain splits the docstring and uses the first line as the
description, `Args`/`Returns`/`Raises` as additional structured info.

---

## The argument schema from type annotations

`@tool` reads the function's type annotations and generates a JSON
schema via Pydantic:

```python
@tool
def simple(x: str) -> str:
    """..."""
# schema: {"properties": {"x": {"type": "string"}}, "required": ["x"]}

@tool
def optional_arg(x: str, y: int = 5) -> dict:
    """..."""
# schema: {"properties": {"x": {"type": "string"}, "y": {"type": "integer", "default": 5}}, "required": ["x"]}

@tool
def with_enum(status: Literal["READY", "PROVISIONING", "FAILED"]) -> dict:
    """..."""
# schema: {"properties": {"status": {"enum": ["READY", "PROVISIONING", "FAILED"], "type": "string"}}, "required": ["status"]}
```

### Supported types

| Type | Becomes |
|---|---|
| `str`, `int`, `float`, `bool` | JSON primitive |
| `list[T]`, `dict[K, V]` | JSON array/object |
| `Optional[T]` | nullable with same rules as T |
| `Union[A, B]` | JSON `oneOf` |
| `Literal["a", "b"]` | `enum` in schema |
| `Enum` subclass | `enum` in schema |
| Pydantic `BaseModel` | nested `$ref` |
| `datetime.date`, `datetime.datetime` | ISO-8601 string |

### `args_schema` — override the schema

If the inferred schema is wrong, or you want to add descriptions
to individual parameters:

```python
from pydantic import BaseModel, Field

class GetClusterStatusArgs(BaseModel):
    cluster_id: str = Field(
        description="The EKS cluster id, e.g. 'cl-001'.",
    )

@tool("get_cluster_status", args_schema=GetClusterStatusArgs)
def get_cluster_status(cluster_id: str) -> dict:
    """Get the current status of one EKS cluster by its id."""
    return {"id": cluster_id, "status": "READY"}
```

`Field(description=...)` on each parameter adds the description
to the schema so the model knows what to pass.

---

## Async tools

If your tool is I/O-bound (HTTP calls, database queries):

```python
@tool
async def get_weather(city: str) -> str:
    """Get the current weather for a city."""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"https://api.weather.com/{city}")
        return response.json()
```

`ToolNode` awaits async tools correctly. Sync tools run in a thread
pool via `asyncio.to_thread`. Mixed lists work — async ones await,
sync ones go to the pool.

**Gotcha:** calling an `async def`-decorated tool with `.invoke(...)`
(sync) works in recent versions — LangChain handles the conversion.
But prefer `.ainvoke(...)` for async tools.

---

## Error handling — raise vs. return

`ToolNode` (from LangGraph) has `handle_tool_errors=True` by default.
It catches exceptions and returns a `ToolMessage` with `status="error"`.

```python
@tool
def get_cluster_status(cluster_id: str) -> dict:
    """Get the current status of one EKS cluster by its id."""
    if cluster_id not in KNOWN_CLUSTERS:
        raise KeyError(f"Cluster {cluster_id} not found")
    return {"id": cluster_id, "status": "READY"}
```

When the model calls this with an unknown id, `ToolNode` catches the
`KeyError` and emits:

```python
ToolMessage(
    content="Error: Cluster cl-999 not found",
    tool_call_id="call-abc123",
    name="get_cluster_status",
    status="error",
)
```

### When to raise vs. return an error string

- **Raise** — programmer errors (the model passed a value that
  broke your code). `ToolNode` wraps it, model sees the error.
- **Return error string** — business errors (the request was
  valid but the resource doesn't exist). Let the model handle it:

```python
@tool
def get_cluster_status(cluster_id: str) -> str:
    """Get the current status of one EKS cluster by its id."""
    if cluster_id not in KNOWN_CLUSTERS:
        return f"NOT_FOUND: cluster {cluster_id} does not exist"
    return json.dumps({"id": cluster_id, "status": "READY"})
```

### Custom error formatting

```python
ToolNode(
    tools,
    handle_tool_errors=lambda e: f"Tool error: {e}",
)
# or
ToolNode(tools, handle_tool_errors="The cluster service is down. Try again later.")
```

The callable form lets you format the error your way. The string
form is a static message for all errors.

---

## InjectedToolArg — args that don't come from the LLM

Sometimes a tool needs an argument the model can't supply — a
database session, a user ID, an HTTP client. Use `InjectedToolArg`:

```python
from langchain_core.tools import tool, InjectedToolArg
from typing import Annotated

@tool
def list_user_clusters(
    user_id: Annotated[str, InjectedToolArg()],
) -> list[dict]:
    """List the EKS clusters owned by the current user.

    Args:
        user_id: the authenticated user's id (injected by the runtime).
    """
    return db.query("SELECT * FROM clusters WHERE user_id = $1", user_id)
```

`InjectedToolArg` marks the parameter as hidden from the JSON schema
the model sees. The runtime provides it via `config["configurable"]`:

```python
tool.invoke(
    {},                              # no args from the LLM
    config={"configurable": {"user_id": "user-42"}},
)
```

In LangGraph, pass it in the node that calls the tool:

```python
def list_clusters_node(state):
    user_id = state["configurable"]["user_id"]
    result = list_user_clusters.invoke(
        {},
        config={"configurable": {"user_id": user_id}},
    )
    return {"cluster_list": result}
```

Also available: `InjectedToolCallId` (get the current tool call's
ID for logging).

---

## Returning a `Command` — change the graph route from a tool

In LangGraph, a tool can return a `Command` instead of a value. The
`Command` updates the graph state and changes the next node:

```python
from langgraph.types import Command
from langchain_core.messages import SystemMessage

@tool
def lookup_and_continue(query: str) -> Command:
    """Search the knowledge base for the query.

    Use this when the user asks about company policies or procedures.
    """
    docs = retriever.invoke(query)
    return Command(
        goto="call_model",
        update={
            "messages": [
                SystemMessage(content=f"Use these documents to answer:\n\n{docs}"),
            ],
        },
    )
```

This is the clean way to do "after this tool runs, inject context
and re-run the model." The model calls the tool, the tool returns
`Command`, LangGraph applies the update and routes to `call_model`.

---

## `StructuredTool.from_function` — programmatic tool creation

For runtime tool generation (e.g. one tool per cluster):

```python
from langchain_core.tools import StructuredTool

def my_get_cluster_status(cluster_id: str) -> dict:
    """Get the current status of one EKS cluster by its id."""
    return {"id": cluster_id, "status": "READY"}

tool = StructuredTool.from_function(
    func=my_get_cluster_status,
    name="get_cluster_status",
    description="Get the current status of one EKS cluster by its id.",
    return_direct=False,
    parse_docstring=False,
    infer_schema=True,
    response_format="content",   # "content" (default) or "content_and_artifact"
)
```

Use `from_function` when:
- You generate tools at runtime
- You wrap a class method as a tool
- You need to override the name without renaming the function

---

## Subclassing `BaseTool` — for complex tools

When `@tool` is too rigid (long-lived clients, complex setup):

```python
from langchain_core.tools import BaseTool
from pydantic import BaseModel, Field

class GetClusterLogsInput(BaseModel):
    cluster_id: str
    since: str = "5m"

class GetClusterLogsTool(BaseTool):
    name: str = "get_cluster_logs"
    description: str = "Fetch recent pod logs for a cluster."

    args_schema: type[BaseModel] = GetClusterLogsInput

    client: httpx.AsyncClient = Field(exclude=True)   # injected, not serialized

    def _run(self, *, cluster_id: str, since: str = "5m") -> str:
        ...

    async def _arun(self, *, cluster_id: str, since: str = "5m") -> str:
        response = await self.client.get(f"/clusters/{cluster_id}/logs?since={since}")
        return response.text
```

`Field(exclude=True)` keeps the client out of the schema. Inject
it at runtime:

```python
tool = GetClusterLogsTool()
tool.client = httpx.AsyncClient(base_url="http://localhost:8080")
```

---

## The complete tool-call round-trip

```python
from langchain_core.messages import HumanMessage, ToolMessage
from langchain_openai import ChatOpenAI

# 1. Define the tool
@tool
def get_weather(city: str) -> str:
    """Get the current weather for a city."""
    return f"The weather in {city} is sunny and 72°F."

# 2. Bind it to the model
model = ChatOpenAI(model="gpt-4o-mini")
model_with_tools = model.bind_tools([get_weather])

# 3. First call — model decides to call the tool
messages = [HumanMessage(content="What's the weather in Tokyo?")]
response = model_with_tools.invoke(messages)

# response.tool_calls = [ToolCall(name='get_weather', args={'city': 'Tokyo'}, id='call-1')]
# response.content = "" (empty — the model called a tool, not answered)

messages.append(response)

# 4. Run the tool
tool_result = get_weather.invoke(response.tool_calls[0].args)

# 5. Build ToolMessage with matching tool_call_id
tool_msg = ToolMessage(
    content=tool_result,           # must be a string
    tool_call_id=response.tool_calls[0].id,   # must match
    name="get_weather",
)
messages.append(tool_msg)

# 6. Second call — model sees the tool result and answers
response2 = model_with_tools.invoke(messages)
# response2.content = "The weather in Tokyo is sunny and 72°F."
```

Steps 3–6 are automated by LangGraph's `ToolNode`. You write the
nodes and edges; LangGraph handles the message assembly.

---

## Common pitfalls

1. **`ToolMessage.content` must be a string.** `json.dumps()` your
   dicts and lists. `str()` on a Pydantic model gives a repr, not
   JSON. Serialize explicitly.
2. **Mismatched `tool_call_id`.** The `ToolMessage`'s `tool_call_id`
   must match the `AIMessage.tool_calls[i].id`. `ToolNode` gets this
   right; if you build `ToolMessage`s by hand, double-check.
3. **Docstring is the description.** Bad docstring = wrong tool
   calls. Write one-line summary + "Use this when..." clause.
4. **`InjectedToolArg` hides the parameter from the schema.** The
   model won't try to fill it. Provide it via `config["configurable"]`
   at runtime.
5. **`async def` with `@tool` works** in recent versions. Call with
   `.ainvoke(...)` or let `ToolNode` handle it.
6. **`@tool` on a no-argument function** is fine. Schema is
   `{"properties": {}}` — the model calls it with no args.

---

## See also

- [[AI/langchain/03-chat-models|03-chat-models]] — how `bind_tools` sends the schema to the model
- [[AI/langchain/02-messages|02-messages]] — what `ToolMessage` looks like and why `tool_call_id` matters
- [[AI/langchain/05-prompts|05-prompts]] — building the messages list with templates
- [[AI/langchain/08-langgraph-intro|08-langgraph-intro]] — `ToolNode` and the agent loop
- [[AI/langchain/10-testing|10-testing]] — testing tools in isolation
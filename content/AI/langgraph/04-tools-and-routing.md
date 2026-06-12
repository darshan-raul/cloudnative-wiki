---
title: "LangGraph — Tools & Routing"
tags:
  - AI
  - LangGraph
---

> **Part 4.** `ToolNode` (how tools run), `tools_condition` (how
> routing is decided), and how to bind tools to the model so the
> agent can call them.

## `ToolNode` — the tool-execution node

`ToolNode` from `langgraph.prebuilt` is the standard way to run tools:

```python
from langgraph.prebuilt import ToolNode

tool_node = ToolNode(tools)
```

It reads `state["messages"]`, finds `AIMessage.tool_calls`, invokes
each tool, and returns `{"messages": [ToolMessage(...), ...]}`.

```python
from langchain_core.messages import HumanMessage, AIMessage, ToolCall

# Simulating what ToolNode does internally:
def tool_node_execute(state: AgentState) -> dict:
    last = state["messages"][-1]
    if not hasattr(last, "tool_calls") or not last.tool_calls:
        return {"messages": []}   # nothing to run

    tool_messages = []
    for tc in last.tool_calls:
        result = tools_by_name[tc["name"]].invoke(tc["args"])
        tool_messages.append(ToolMessage(
            content=str(result),    # must be a string
            tool_call_id=tc["id"],  # must match the ToolCall.id
            name=tc["name"],
        ))
    return {"messages": tool_messages}
```

`ToolNode` does this automatically. You just need to pass it the
list of tools.

### `ToolNode` options

```python
# All tools
tool_node = ToolNode(tools)

# Only specific tools by name (filter)
tool_node = ToolNode(["get_weather", "list_clusters"])

# With custom error handling
tool_node = ToolNode(tools, handle_tool_errors=True)
```

`handle_tool_errors=True` (default): exceptions become `ToolMessage`
with `status="error"`. The model sees the error and can react
(retry, explain, ask for clarification).

---

## `tools_condition` — the routing function

`tools_condition` from `langgraph.prebuilt` is the standard routing
function after `call_model`:

```python
from langgraph.prebuilt import tools_condition

def should_continue(state: AgentState) -> str:
    return tools_condition(state)
```

`tools_condition` does exactly this:

```python
def tools_condition(state: AgentState) -> str:
    last = state["messages"][-1]
    if hasattr(last, "tool_calls") and last.tool_calls:
        return "run_tools"    # the node name
    return END
```

You can write this yourself, but `tools_condition` is the standard.
Use it directly in `add_conditional_edges`:

```python
builder.add_conditional_edges(
    "call_model",
    tools_condition,
    {"run_tools": "run_tools", END: END},
)
```

### Writing your own routing logic

Sometimes you need more than just "tool calls or not":

```python
def route_by_intent(state: AgentState) -> str:
    last = state["messages"][-1]
    if not hasattr(last, "tool_calls") or not last.tool_calls:
        return END

    # Route based on which tool was called
    tool_name = last.tool_calls[0].name
    if tool_name in ["delete_cluster", "scale_down"]:
        return "confirm_action"   # human approval needed
    return "run_tools"

builder.add_conditional_edges("call_model", route_by_intent)
```

This is how you insert a confirmation step before destructive tools.

---

## Binding tools to the model

The tools must be bound to the model before the model can call them.
In the `call_model` node:

```python
def call_model(state: AgentState) -> dict:
    llm_with_tools = llm.bind_tools(tools)
    response = llm_with_tools.invoke(state["messages"])
    return {"messages": [response]}
```

`bind_tools` returns a new `Runnable`. The original `llm` is unchanged.
The `llm_with_tools` can emit `AIMessage`s with `tool_calls` populated.

### Binding a subset of tools

Not all nodes need all tools. For a `summarize` node that doesn't need
the full tool suite:

```python
summarize_tools = [summarize_tool, search_docs_tool]

def summarize(state: AgentState) -> dict:
    llm = llm.bind_tools(summarize_tools)
    response = llm.invoke(state["messages"])
    return {"messages": [response]}
```

---

## `ToolNode` with `handle_tool_errors`

```python
tool_node = ToolNode(tools, handle_tool_errors=True)
```

When `handle_tool_errors=True` (default), if a tool raises an
exception, `ToolNode` catches it and returns:

```python
ToolMessage(
    content=f"Error: {e}",
    tool_call_id=tc["id"],
    name=tc["name"],
    status="error",
)
```

The model sees the error and can react. This keeps the agent loop
alive instead of crashing the graph run.

### Custom error message

```python
tool_node = ToolNode(
    tools,
    handle_tool_errors="The tool call failed. Try again or ask the user to clarify.",
)
```

The string form is a static message for all errors. For dynamic
formatting, pass a callable:

```python
tool_node = ToolNode(
    tools,
    handle_tool_errors=lambda e: f"Tool error: {type(e).__name__}: {e}",
)
```

---

## Multiple `tool_calls` in one response

The model can emit multiple tool calls in one `AIMessage`:

```python
response.tool_calls
# [
#     ToolCall(name='get_weather', args={'city': 'Tokyo'}, id='call-1'),
#     ToolCall(name='get_time', args={'tz': 'JST'}, id='call-2'),
# ]
```

`ToolNode` runs them in order and returns a `ToolMessage` for each.
The messages are appended to the state in order, maintaining
alternation: `[AIMessage, ToolMessage, ToolMessage, AIMessage]`.

### `parallel_tool_calls=False` — force one at a time

If you want the model to call one tool, wait for the result, then
call the next:

```python
llm = llm.bind_tools(tools, parallel_tool_calls=False)
```

The model emits only one `tool_call` per `AIMessage`. Useful for
testing and for steps where you want to verify each call.

---

## `tool_choice` — forcing or preventing tool use

```python
llm = llm.bind_tools(tools, tool_choice="auto")    # model decides (default)
llm = llm.bind_tools(tools, tool_choice="any")     # must call at least one
llm = llm.bind_tools(tools, tool_choice="none")    # must not call any
llm = llm.bind_tools(tools, tool_choice="get_weather")  # must call this specific tool
```

Use `"any"` when you want to force the model to use a tool before
proceeding (e.g., a confirm step). Use `"none"` to get a pure text
response (e.g., for a summarization node).

---

## The complete agent loop — how it all fits together

```
START → call_model
          │
          │ AIMessage (possibly with tool_calls)
          ▼
     tools_condition → "run_tools" → ToolNode → call_model
                      → END
```

In code:

```python
builder = StateGraph(AgentState)
builder.add_node("call_model", call_model)
builder.add_node("run_tools", ToolNode(tools))
builder.add_edge(START, "call_model")
builder.add_conditional_edges(
    "call_model",
    tools_condition,
    {"run_tools": "run_tools", END: END},
)
builder.add_edge("run_tools", "call_model")
graph = builder.compile()
```

---

## Common pitfalls

1. **`tool_call_id` mismatch.** `ToolMessage`'s `tool_call_id`
   must match the `AIMessage.tool_calls[i].id`. `ToolNode` gets
   this right. If you build `ToolMessage`s by hand, double-check.
2. **`ToolMessage.content` must be a string.** `str()` or
   `json.dumps()` your return values.
3. **`parallel_tool_calls=True` (default)** means the model can
   emit multiple tool calls. Your tool node must handle a list of
   calls and return a `ToolMessage` for each.
4. **`tools_condition` checks `last.tool_calls`.** If the model
   responded with text (no tool calls), it returns `END`. If you
   have other routing logic, write your own conditional edge.
5. **`handle_tool_errors=True` on `ToolNode` doesn't catch
   system errors** (e.g., the graph itself crashing). It only
   catches tool exceptions.

---

## See also

- [[AI/langgraph/01-mental-model|01-mental-model]] — the agent loop diagram
- [[AI/langgraph/03-nodes-and-edges|03-nodes-and-edges]] — edges and routing
- [[AI/langchain/04-tools|../langchain/04-tools]] — how tools work (the `@tool` decorator)
- [[AI/langchain/02-messages|../langchain/02-messages]] — `ToolMessage` and the alternation invariant
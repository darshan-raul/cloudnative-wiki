---
title: "LangGraph — Testing"
tags:
  - AI
  - LangGraph
---

> **Part 12.** Testing LangGraph applications — `FakeListChatModel`,
> graph assertions, no-network discipline, and fixture patterns.

## The testing setup

Test the graph, not the model. Use `FakeListChatModel` to simulate
model responses without hitting the API:

```python
import pytest
from langchain_core.messages import AIMessage, HumanMessage, ToolCall

# Build graph once
@pytest.fixture
def graph():
    return builder.compile(checkpointer=MemorySaver())

# Fake model that calls a tool
@pytest.fixture
def fake_with_tool_call():
    return FakeListChatModel(responses=[
        AIMessage(content="", tool_calls=[
            ToolCall(name="get_weather", args={"city": "Tokyo"}, id="call-1"),
        ]),
        AIMessage(content="It's sunny in Tokyo."),
    ])
```

---

## Test 1: the agent calls a tool

```python
def test_calls_get_weather_tool(graph, fake_with_tool_call):
    graph = build_graph(llm=fake_with_tool_call, tools=[get_weather])

    result = graph.invoke(
        {"messages": [HumanMessage(content="What's the weather in Tokyo?")]},
        config={"configurable": {"thread_id": "test-1"}},
    )

    # Check that a tool was called
    tool_calls = [
        m.tool_calls[-1]
        for m in result["messages"]
        if hasattr(m, "tool_calls") and m.tool_calls
    ]
    assert any(tc.name == "get_weather" for tc in tool_calls)
```

---

## Test 2: the tool result is in the next model call

```python
def test_tool_result_feeds_back_to_model(graph, fake_with_tool_call):
    graph = build_graph(llm=fake_with_tool_call, tools=[get_weather])

    result = graph.invoke(
        {"messages": [HumanMessage(content="What's the weather?")]},
    )

    # ToolMessage was appended
    tool_messages = [m for m in result["messages"] if isinstance(m, ToolMessage)]
    assert len(tool_messages) == 1
    assert "Tokyo" in tool_messages[0].content
```

---

## Test 3: without tool calls, the agent finishes

```python
def test_no_tool_calls_ends(graph):
    fake = FakeListChatModel(responses=[
        AIMessage(content="The weather is sunny."),
    ])
    graph = build_graph(llm=fake, tools=[get_weather])

    result = graph.invoke(
        {"messages": [HumanMessage(content="Hello")]},
    )

    # No tool calls made
    tool_calls = [
        m.tool_calls[-1]
        for m in result["messages"]
        if hasattr(m, "tool_calls") and m.tool_calls
    ]
    assert len(tool_calls) == 0
    # Final message is the AI response
    assert isinstance(result["messages"][-1], AIMessage)
```

---

## Test 4: checkpointer persists across calls

```python
def test_checkpointer_persistence(graph):
    config = {"configurable": {"thread_id": "test-persist"}}

    # First call
    graph.invoke(
        {"messages": [HumanMessage(content="Hi")]},
        config=config,
    )

    # Second call — should resume with history
    result = graph.invoke(
        {"messages": [HumanMessage(content="What did I just say?")]},
        config=config,
    )

    # The agent saw the history
    assert len(result["messages"]) > 2
```

---

## Test 5: routing conditional edges

```python
def test_routing_to_approval(graph, fake_destructive_tool):
    graph = build_graph(llm=fake_destructive_tool, tools=DESTRUCTIVE_TOOLS)

    result = graph.invoke(
        {"messages": [HumanMessage(content="delete cluster cl-001")]},
        config={"configurable": {"thread_id": "test-route"}},
    )

    # Graph paused with pending_approval
    assert result.get("pending_approval") is not None
    assert result["pending_approval"]["tool"] == "delete_cluster"
```

---

## `FakeListChatModel` patterns

### Infinite responses (for multi-step tests)

```python
fake = FakeListChatModel(
    responses=itertools.repeat(AIMessage(content="ok")),
    cycle=True,
)
```

### `usage_metadata` on responses

```python
fake = FakeListChatModel(responses=[
    AIMessage(content="hi", usage_metadata={
        "input_tokens": 5,
        "output_tokens": 3,
        "total_tokens": 8,
    }),
])
```

### Streaming chunks

```python
for chunk in fake.stream("hi"):
    print(chunk.content, end="")
# "hi" — one chunk, the full response
```

---

## No-network discipline

```python
# conftest.py
@pytest.fixture(autouse=True)
def block_network(monkeypatch):
    import socket
    def refuse(*args, **kwargs):
        raise RuntimeError("Network call in test!")
    monkeypatch.setattr(socket, "socket", refuse)
```

Or with `pytest-socket`:

```toml
[tool.pytest.ini_options]
addopts = "--disable-socket"
```

This catches accidental LiteLLM calls before they cost money.

---

## Fixture patterns

### Reset checkpointer per test

```python
@pytest.fixture
def graph():
    return builder.compile(checkpointer=MemorySaver())
```

Each test gets a fresh in-memory checkpointer.

### Per-module graph (shared, not reset)

```python
# conftest.py
@pytest.fixture(scope="module")
def graph():
    return builder.compile()
```

Shared across tests in the module. Faster (no re-compile) but tests
must not pollute each other's state.

### `FakeListChatModel` per test

```python
@pytest.fixture
def fake_tool_call():
    return FakeListChatModel(responses=[
        AIMessage(content="", tool_calls=[
            ToolCall(name="get_weather", args={"city": "Tokyo"}, id="call-1"),
        ]),
        AIMessage(content="It's sunny."),
    ])
```

---

## Common pitfalls

1. **`FakeListChatModel` exhausted** — add `cycle=True` or enough
   responses for all the model calls in your test.
2. **`tool_call_id` mismatch** — when manually building
   `ToolMessage`s, the `tool_call_id` must match the `ToolCall.id`.
   Let `ToolNode` handle this.
3. **`block_network` doesn't catch `urllib3` direct sockets.** Use
   `pytest-socket` for more thorough blocking.
4. **`checkpointer` shared across tests** — if you share the graph
   fixture, the checkpointer accumulates state. Use `MemorySaver`
   per test or clean it between tests.
5. **`async` tests need `@pytest.mark.asyncio`.** Don't forget the
   marker for async graph calls.

---

## See also

- [[AI/langchain/10-testing|../langchain/10-testing]] — LangChain testing primitives (`FakeListChatModel`, `patch_langchain_environment`)
- [[AI/langgraph/04-tools-and-routing|04-tools-and-routing]] — `ToolNode` and routing
- [[AI/langgraph/11-production|11-production]] — error handling and recursion limits
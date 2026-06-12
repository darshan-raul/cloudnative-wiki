---
title: "LangChain — Testing"
tags:
  - AI
  - LangChain
  - Testing
---

> **Part 10.** Testing without hitting a real LLM — `FakeListChatModel`,
> `FakeMessagesListChatModel`, tool schema tests, and the no-network
> discipline.

## The testing hierarchy

Two layers, different tradeoffs:

| Layer | What | How | Speed | Cost |
|---|---|---|---|---|
| **Unit** | Graph, routing, tool schemas | `FakeListChatModel` | Fast | Free |
| **Integration** | Model calls, HTTP layer | `pytest-httpx` mocking LiteLLM | Slow | Real cost |

Unit tests cover most of your logic. Integration tests verify the
model behaves correctly with real prompts.

---

## `FakeListChatModel` — canned responses

The simplest fake model. You give it a list of `AIMessage`s; it
returns them in order on each `invoke`:

```python
from langchain_core.language_models.fake_chat_models import FakeListChatModel
from langchain_core.messages import AIMessage

fake = FakeListChatModel(responses=[
    AIMessage(content="first response"),
    AIMessage(content="second response"),
])

result = fake.invoke("hi")       # AIMessage(content="first response")
result = fake.invoke("again")    # AIMessage(content="second response")
# After the list is exhausted: IndexError
```

### Infinite repetition

```python
import itertools

fake = FakeListChatModel(responses=itertools.repeat(
    AIMessage(content="ok")
))
# Always returns "ok", no IndexError
```

### Tool calls in fake responses

```python
from langchain_core.messages import AIMessage, ToolCall

fake = FakeListChatModel(responses=[
    AIMessage(
        content="",   # empty — the model only called a tool
        tool_calls=[
            ToolCall(name="get_weather", args={"city": "Tokyo"}, id="call-1"),
        ],
    ),
    AIMessage(content="The weather in Tokyo is sunny."),  # final response
])
```

The first `AIMessage` has no content but has `tool_calls`. This
exercises the full agent loop: model calls tool → `ToolNode` runs
tool → model gets result → model answers.

### `cycle=True` — loop when exhausted

```python
fake = FakeMessagesListChatModel(
    responses=[response1, response2],
    cycle=True,   # loop back to start after exhausted
)
```

Use when your test makes more calls than you have canned responses.

---

## `FakeMessagesListChatModel` — conversation-aware fakes

Same idea but tracks conversation state. Use when you want to
return different responses based on the conversation:

```python
from langchain_core.language_models.fake_chat_models import FakeMessagesListChatModel

fake = FakeMessagesListChatModel(responses=[
    AIMessage(content="", tool_calls=[ToolCall(name="get_weather", args={}, id="call-1")]),
    AIMessage(content="The weather is sunny."),
])
```

The difference from `FakeListChatModel` shows up in streaming-aware
tests and when the response depends on prior context.

---

## Streaming with fakes

Both fakes support `stream` and return a single chunk:

```python
for chunk in fake.stream("hi"):
    print(chunk.content, end="")
# "first response"
```

The "streaming" is fake — you get the full response in one chunk.
The graph's `ToolNode` and message reducer work correctly with
these chunks.

---

## Testing the graph

### Test 1: the model calls the right tool

```python
from langchain_core.messages import HumanMessage, AIMessage, ToolCall
from langgraph.prebuilt import ToolNode

def test_model_calls_get_weather():
    fake = FakeListChatModel(responses=[
        AIMessage(content="", tool_calls=[
            ToolCall(name="get_weather", args={"city": "Tokyo"}, id="call-1"),
        ]),
        AIMessage(content="It's sunny in Tokyo."),
    ])

    # Build graph with fake model
    graph = build_graph(llm=fake)

    result = graph.invoke(
        {"messages": [HumanMessage(content="What's the weather in Tokyo?")]},
        config={"configurable": {"thread_id": "test-1"}},
    )

    # The tool was called
    tool_calls = [
        m.tool_calls[-1]
        for m in result["messages"]
        if hasattr(m, "tool_calls") and m.tool_calls
    ]
    assert any(tc.name == "get_weather" for tc in tool_calls)
```

### Test 2: the tool result feeds back to the model

```python
def test_tool_result_in_model_call():
    fake = FakeListChatModel(responses=[
        AIMessage(content="", tool_calls=[
            ToolCall(name="get_weather", args={"city": "Tokyo"}, id="call-1"),
        ]),
        AIMessage(content="It's sunny in Tokyo."),
    ])
    graph = build_graph(llm=fake)

    result = graph.invoke(
        {"messages": [HumanMessage(content="Weather in Tokyo?")]},
    )

    messages = result["messages"]
    tool_messages = [m for m in messages if isinstance(m, ToolMessage)]
    assert len(tool_messages) == 1
    assert "Tokyo" in tool_messages[0].content
```

### Test 3: without tool_calls, the agent finishes

```python
def test_no_tool_calls_ends():
    fake = FakeListChatModel(responses=[
        AIMessage(content="It's sunny in Tokyo."),
    ])
    graph = build_graph(llm=fake)

    result = graph.invoke(
        {"messages": [HumanMessage(content="Hello")]},
    )

    # No tool calls were made
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

## Testing tools in isolation

```python
def test_tool_schema():
    from my_tools import get_weather

    schema = get_weather.args_schema.model_json_schema()
    assert schema["type"] == "object"
    assert "properties" in schema
    assert "city" in schema["properties"]
    assert "required" in schema

def test_tool_returns_string():
    from my_tools import get_weather

    result = get_weather.invoke({"city": "Tokyo"})
    assert isinstance(result, str)

@pytest.mark.asyncio
async def test_async_tool():
    from my_tools import get_weather_async

    result = await get_weather_async.ainvoke({"city": "Tokyo"})
    assert isinstance(result, str)
```

---

## The no-network discipline

The test suite must never hit the network. Enforce this:

```python
# conftest.py
import socket

@pytest.fixture(autouse=True)
def block_network(monkeypatch):
    def refuse(*args, **kwargs):
        raise RuntimeError("Network call in test!")
    monkeypatch.setattr(socket, "socket", refuse)
```

Or with `pytest-socket`:

```toml
# pyproject.toml
[tool.pytest.ini_options]
addopts = "--disable-socket"
```

This catches accidental LiteLLM calls before they cost money.

---

## Mocking the LiteLLM HTTP layer

For tests that exercise the agent but not the model, mock at the
HTTP layer:

```python
import pytest

@pytest.fixture
def mock_llm_backend(httpx_mock):
    httpx_mock.add_response(
        url="http://localhost:4000/v1/chat/completions",
        json={
            "id": "chatcmpl-123",
            "object": "chat.completion",
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": "hello"},
                "finish_reason": "stop",
            }],
            "usage": {"prompt_tokens": 5, "completion_tokens": 3, "total_tokens": 8},
        },
    )
```

Reserve this for integration tests where you want to verify the
request format is correct. Unit tests use `FakeListChatModel`.

---

## Testing cost / token usage

```python
def test_usage_metadata():
    fake = FakeListChatModel(responses=[
        AIMessage(content="hi", usage_metadata={
            "input_tokens": 5,
            "output_tokens": 2,
            "total_tokens": 7,
        }),
    ])
    response = fake.invoke([])
    assert response.usage_metadata["total_tokens"] == 7
```

Use `FakeListChatModel` with `usage_metadata` to test cost-tracking
code without a real model.

---

## `patch_langchain_environment` — env isolation

```python
from langchain_core.env import patch_langchain_environment

with patch_langchain_environment():
    # LANGCHAIN_TRACING_V2 is unset inside this block
    # Tests don't accidentally hit LangSmith
    ...
```

---

## Package import gotchas

LangChain has been reorganized across versions. Import from the
right package:

| What | Import from |
|---|---|
| `Runnable`, `RunnableLambda`, `RunnableSequence` | `langchain_core.runnables` |
| Messages (`HumanMessage`, `AIMessage`, `ToolMessage`) | `langchain_core.messages` |
| `@tool` | `langchain_core.tools` |
| `FakeListChatModel`, `FakeMessagesListChatModel` | `langchain_core.language_models.fake_chat_models` |
| `ChatPromptTemplate`, `PromptTemplate` | `langchain_core.prompts` |
| `StrOutputParser`, `PydanticOutputParser` | `langchain_core.output_parsers` |
| `BaseCallbackHandler` | `langchain_core.callbacks` |
| `set_llm_cache` | `langchain_core.globals` |
| `InMemoryCache` | `langchain_core.caches` |
| `ChatOpenAI` | `langchain_openai` |
| `ChatAnthropic` | `langchain_anthropic` |

**Never use:** `from langchain.tools import tool` (legacy),
`from langchain.chat_models import ChatOpenAI` (deprecated),
`from langchain.llms import OpenAI` (legacy completion model),
`from langchain.memory import ConversationBufferMemory` (legacy).

---

## Common pitfalls

1. **`FakeListChatModel` exhausted.** Add `cycle=True` or enough
   responses for your test.
2. **`tool_call_id` mismatch in tests.** When you manually build
   `ToolMessage`s in a test, the `tool_call_id` must match the
   `ToolCall.id` from the `AIMessage`. Use the same `FakeListChatModel`
   with tool calls and let `ToolNode` handle it.
3. **`socket` monkeypatch doesn't catch `urllib3` or `httpx` direct
   sockets.** Use `pytest-socket` for more thorough network blocking.
4. **`set_llm_cache` is global.** Reset it in tests with an
   `autouse` fixture to avoid cross-test pollution.
5. **`async` test functions need `@pytest.mark.asyncio`.** Don't
   forget the marker for async tool tests.
6. **`pydantic` v1 vs v2.** Modern LangChain requires Pydantic v2.
   Don't `pip install pydantic==1.x`.

---

## See also

- [[AI/langchain/04-tools|04-tools]] — testing tool schemas
- [[AI/langchain/07-memory-callbacks|07-memory-callbacks]] — `BaseCallbackHandler` for cost tracking
- [[AI/langchain/09-streaming|09-streaming]] — testing streaming code
- [LangChain testing guide](https://python.langchain.com/docs/how_to/fake_chat_model/)
---
title: "LangChain — Mental Model"
tags:
  - AI
  - LangChain
  - LCEL
---

> **Start here.** This is the foundation. Read this first, then
> work through the files in order. Everything builds on this.

## The problem LangChain solves

When you talk to an LLM directly, you send a prompt and get a
response. That's simple. But real applications need more:

- **Multi-step reasoning** — the model needs to call tools, get
  results, and decide what to do next (an agent loop)
- **Structured inputs/outputs** — prompts with variables, responses
  that conform to a schema
- **Composition** — combine a prompt, a model, and a parser into a
  pipeline
- **Observability** — trace what happened inside the model call
- **Persistence** — remember conversation history across requests

LangChain gives you abstractions for all of these. It's not an LLM
itself — you bring your own model (OpenAI, Anthropic, Bedrock,
Ollama, anything with an OpenAI-compatible API).

---

## The four core concepts

Everything in LangChain is built from four ideas:

### 1. Messages

A chat model takes a **list of messages** and returns a **message**.
Messages are typed. The five types are:

| Type | Who writes it | What it contains |
|---|---|---|
| `SystemMessage` | you (the developer) | instructions, persona, rules |
| `HumanMessage` | the user | the user's input |
| `AIMessage` | the model | text, and optionally tool calls |
| `ToolMessage` | a tool | the result of a tool the model called |
| `AIMessageChunk` | the model (streaming) | a piece of the response |

The model's input is always `list[Message]`. Its output is always
a single `AIMessage`. Tools return `ToolMessage`s that get appended
to the list for the next model call.

This alternation — human → AI → tool → AI → tool → AI — is the
fundamental pattern of a chat agent.

### 2. Chat models

A chat model is a `Runnable` that takes messages and returns an
`AIMessage`. The main one is `ChatOpenAI`, but you can swap in any
provider:

```python
from langchain_openai import ChatOpenAI

# OpenAI direct
model = ChatOpenAI(model="gpt-4o", api_key="...")

# Any OpenAI-compatible endpoint (LiteLLM, vLLM, Ollama in OpenAI mode)
model = ChatOpenAI(
    model="claude-3-5-haiku",
    base_url="http://localhost:4000/v1",   # LiteLLM proxy
    api_key="...",
)
```

The `bind_tools` method exposes your tools to the model. The model
decides whether to call a tool based on the tool's name and
description:

```python
model_with_tools = model.bind_tools([list_clusters, get_weather])
response = model_with_tools.invoke(messages)
# response.content == "" if the model called a tool
# response.tool_calls != [] if the model called a tool
```

### 3. Tools

A tool is a function the model can call. The `@tool` decorator
turns any Python function into a tool:

```python
from langchain_core.tools import tool

@tool
def get_weather(city: str) -> str:
    """Get the current weather for a city.

    Use this when the user asks about the weather in a specific city.
    """
    return f"The weather in {city} is sunny and 72°F."
```

The **docstring is the API** — the model reads it to decide whether
to call this tool. The **type annotations** become the JSON schema
for the arguments.

A tool can be sync or async:

```python
@tool
async def get_weather_async(city: str) -> str:
    """Get the current weather for a city."""
    return await weather_api.get(city)
```

### 4. Runnables and LCEL

Everything in LangChain — models, prompts, tools, parsers — is a
`Runnable`. A `Runnable` has these methods:

```python
model.invoke(messages)         # one call, full response
model.stream(messages)        # one call, chunks
model.ainvoke(messages)       # async version
model.astream(messages)       # async chunks
```

`Runnable`s compose with the `|` operator (LCEL — LangChain
Expression Language):

```python
from langchain_core.output_parsers import StrOutputParser

chain = prompt | model | parser
# prompt: str -> PromptValue
# PromptValue -> model -> AIMessage
# AIMessage -> parser -> str
```

`chain.invoke({"question": "..."})` runs the prompt, feeds the
result to the model, feeds the model's output to the parser, and
returns the final string.

---

## The two modes: chains and agents

### Chains — linear pipelines

A chain is a `RunnableSequence`: input → step1 → step2 → output.
The `|` operator builds it. Good for one-shot tasks:

```python
from langchain_core.prompts import ChatPromptTemplate
from langchain_openai import ChatOpenAI
from langchain_core.output_parsers import StrOutputParser

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    ("human", "{question}"),
])

model = ChatOpenAI(model="gpt-4o")
parser = StrOutputParser()

chain = prompt | model | parser

result = chain.invoke({"question": "What is Kubernetes?"})
# result is a plain string
```

### Agents — loops with tool calls

A chain is linear: start → end. An agent is cyclic: the model
decides to call a tool, the tool result feeds back into the model,
the model decides again. This is the agent loop:

```
┌────────────────────────────────────────────┐
│  messages (input list)                     │
│        │                                   │
│        ▼                                   │
│  ┌─────────────┐                           │
│  │  call_model │  ← model sees messages    │
│  └──────┬──────┘                           │
│         │ AIMessage (possibly with tool_calls)
│         ▼                                   │
│  ┌─────────────┐     tool_calls?           │
│  │  run_tools  │  ← ──────────────────────┘
│  └──────┬──────┘
│         │ ToolMessage (result)
│         ▼
│  back to call_model ───────────────────────►
└────────────────────────────────────────────┘
```

LangChain chains can fake this with recursive Python, but you lose
**state** (conversation history), **durability** (resume after
crash), and **human-in-the-loop** (pause for approval). LangGraph
provides these properly.

---

## The package layout

LangChain is split across many packages. Import from the right one:

| Package | What it has |
|---|---|
| `langchain-core` | `Runnable`, messages, prompts, tools, output parsers. **Always.** |
| `langchain-openai` | `ChatOpenAI`, `OpenAIEmbeddings` |
| `langchain-anthropic` | `ChatAnthropic` |
| `langchain-ollama` | `ChatOllama` (local models) |
| `langgraph` | `StateGraph`, `ToolNode`, checkpointers (the agent framework) |
| `langsmith` | Tracing client (optional, for observability) |

**Never** `from langchain import ...` (the metapackage is mostly
empty in 0.3+/1.0+). **Never** `from langchain_community import ...`
(many things there are stale, being deprecated).

```toml
# pyproject.toml
dependencies = [
    "langchain-core>=0.3",
    "langchain-openai>=0.3",
    "langgraph>=0.2",
]
```

---

## A complete running example

Everything in one file. A simple chain with a prompt and model:

```python
# example_01.py
from langchain_core.prompts import ChatPromptTemplate
from langchain_openai import ChatOpenAI
from langchain_core.output_parsers import StrOutputParser

# 1. The prompt — a template with one variable
prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    ("human", "{question}"),
])

# 2. The model
model = ChatOpenAI(model="gpt-4o-mini")

# 3. The parser — extracts AIMessage.content as a string
parser = StrOutputParser()

# 4. Compose with |
chain = prompt | model | parser

# 5. Run it
result = chain.invoke({"question": "What is a Pod in Kubernetes?"})
print(result)
# A Pod is the smallest deployable unit in Kubernetes...
```

Now add a tool. The model decides when to call it:

```python
# example_02.py
from langchain_core.messages import HumanMessage
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI

# 1. Define a tool
@tool
def get_weather(city: str) -> str:
    """Get the current weather for a city.

    Use this when the user asks about the weather in a specific city.
    """
    return f"The weather in {city} is sunny and 72°F."

# 2. Create the model and bind the tool
model = ChatOpenAI(model="gpt-4o-mini")
model_with_tools = model.bind_tools([get_weather])

# 3. Messages list — starts with a human message
messages = [
    HumanMessage(content="What's the weather in Tokyo?"),
]

# 4. Call the model
response = model_with_tools.invoke(messages)
print(response.content)        # ""
print(response.tool_calls)     # [ToolCall(name='get_weather', args={'city': 'Tokyo'}, id='...')]

# 5. The tool call returns a ToolMessage
tool_result = get_weather.invoke(response.tool_calls[0].args)
# or, in a real agent loop, ToolNode handles this automatically
```

The model's response had `tool_calls` populated (it decided to call
`get_weather`). In a full agent, you'd:
1. Run the tool and get its result
2. Append a `ToolMessage` to the messages list
3. Call the model again with the updated list

---

## What LangChain is NOT

- **It is not an LLM.** It's a framework for talking to LLMs. The
  model is a separate service.
- **It is not an agent framework by itself.** Chains are linear.
  Agents (with loops, tools, state) need LangGraph.
- **It is not a vector store.** Qdrant, Pinecone, pgvector are
  separate. LangChain has thin adapters but you can use them directly.
- **It is not a memory system.** The legacy memory classes
  (`ConversationBufferMemory`, etc.) are wrappers over the message
  list. A LangGraph checkpointer is the modern replacement.

---

## See also

- [[AI/langchain/02-messages|02-messages]] — the five message types in detail
- [[AI/langchain/03-chat-models|03-chat-models]] — ChatOpenAI, bind_tools, with_structured_output
- [[AI/langchain/04-tools|04-tools]] — @tool, schema generation, async tools
- [[AI/langchain/05-prompts|05-prompts]] — ChatPromptTemplate and templating
- [[AI/langchain/06-runnables-lcel|06-runnables-lcel]] — the | operator and composition primitives
- [[AI/langchain/08-langgraph-intro|08-langgraph-intro]] — why you need LangGraph for agents
- [LangChain docs](https://python.langchain.com/docs/introduction/)
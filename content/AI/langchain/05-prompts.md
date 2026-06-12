---
title: "LangChain — Prompts"
tags:
  - AI
  - LangChain
  - Prompts
---

> **Part 5.** `ChatPromptTemplate` — building a messages list from
> template variables. `MessagesPlaceholder`, `partial`, the four
> slot types, and how prompts compose with `|`.

## Why templates instead of literal messages?

Literal `SystemMessage` + `HumanMessage` works for static, single-turn
cases:

```python
messages = [
    SystemMessage(content="You are a helpful assistant."),
    HumanMessage(content="What is Kubernetes?"),
]
```

But when the system message needs variables — per-user context,
retrieved docs, dynamic instructions — you need a template:

```python
prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant for {user_name} in {region}."),
    ("human", "{question}"),
])

formatted = prompt.invoke({
    "user_name": "darshan",
    "region": "us-west-2",
    "question": "How do I create a cluster?",
})
# formatted is a PromptValue — a list of messages ready to send to the model
```

---

## `ChatPromptTemplate.from_messages` — the canonical form

```python
from langchain_core.prompts import ChatPromptTemplate

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    ("human", "{question}"),
])
```

The tuple format is `("role", "content")`. The four roles:

| Tuple | Role | What goes here |
|---|---|---|
| `("system", "...")` | system | Static instructions, persona, rules. Can use `{variable}` for templating. |
| `("human", "...")` | user | Static or templated user input. |
| `("ai", "...")` | assistant | Few-shot examples of model responses. |
| `("placeholder", "{name}")` | messages | A slot for the full conversation history. |

The `("placeholder", "{messages}")` pattern is the canonical way to
build a chat prompt that carries history.

### Variable syntax

Inside message strings, `{var}` is a Python format string. Literal
braces: escape with `{{` and `}}`.

```python
prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a {persona} assistant."),
    ("human", "Question: {question}\nThink step by step."),
])

prompt.invoke({
    "persona": "helpful",
    "question": "What is 2+2?",
})
```

---

## `MessagesPlaceholder` — the explicit history slot

`("placeholder", "{messages}")` is shorthand. The explicit form:

```python
from langchain_core.prompts import MessagesPlaceholder

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    MessagesPlaceholder("history", optional=True),
    ("human", "{question}"),
])
```

Why use the explicit form:
- **`optional=True`** — the prompt works even if `history` is
  missing (the shorthand errors on missing variables).
- **Multiple placeholders** — useful if you have `messages` and
  `short_term_memory` as separate lists.
- **Controlling the message type** — `MessagesPlaceholder` adds
  `AIMessage`, `HumanMessage`, or `ToolMessage` objects; a simple
  placeholder string just interpolates whatever you pass.

---

## `partial` — pre-fill some variables

`prompt.partial(**kwargs)` returns a new prompt with some variables
already filled in. Useful when variables come from config rather
than user input:

```python
prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a copilot for {user_name} in {region}."),
    ("placeholder", "{messages}"),
])

# At module load: pre-fill the static parts
prompt = prompt.partial(user_name="darshan", region="us-west-2")

# At call time: only messages is needed
formatted = prompt.invoke({"messages": [HumanMessage(content="hi")]})
```

### `partial` with a function — dynamic values

```python
from datetime import datetime
from langchain_core.runnables import RunnableLambda

def current_date(_):
    return datetime.now().strftime("%Y-%m-%d")

prompt = prompt.partial(
    date=RunnableLambda(current_date),
)

formatted = prompt.invoke({"messages": [...]})
# prompt now has today's date baked in
```

`partial` from a `Runnable` is evaluated at invoke time, not at
partial time. Good for values that change per call.

---

## Pipeline: `prompt | model | parser`

The canonical LangChain chain:

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

What happens step by step:

```
input: {"question": "What is Kubernetes?"}
  │
  ▼
prompt.invoke(input)
  → PromptValue(list of messages)
  │
  ▼
model.invoke(PromptValue)
  → AIMessage(content="Kubernetes is...")
  │
  ▼
parser.invoke(AIMessage)
  → str("Kubernetes is...")
```

`chain.invoke(...)` takes a dict, runs it through each stage, returns
the final output.

---

## `from_template` — single-string shortcut

```python
from langchain_core.prompts import PromptTemplate

prompt = PromptTemplate.from_template(
    "Translate to French: {text}"
)
```

The result is a string, not a list of messages. Use for one-shot
completion-style tasks (legacy models, simple prompts). For chat,
use `ChatPromptTemplate.from_messages`.

---

## Few-shot examples

```python
from langchain_core.prompts import FewShotChatMessagePromptTemplate

examples = [
    {"input": "The cluster is down", "output": "Check node status first."},
    {"input": "Pods stuck in Pending", "output": "Check resource constraints."},
]

example_prompt = ChatPromptTemplate.from_messages([
    ("human", "{input}"),
    ("ai", "{output}"),
])

few_shot = FewShotChatMessagePromptTemplate(
    example_prompt=example_prompt,
    examples=examples,
)

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a Kubernetes troubleshooting assistant."),
    few_shot,
    ("human", "{problem}"),
])
```

The examples are injected between the system message and the user's
problem. The model sees them and follows the format.

### Dynamic example selection

```python
from langchain_core.example_selectors import SemanticSimilarityExampleSelector

selector = SemanticSimilarityExampleSelector.from_examples(
    examples,
    OpenAIEmbeddings(model="text-embedding-3-small"),
    Chroma,
    k=2,
)

few_shot = FewShotChatMessagePromptTemplate(
    example_prompt=example_prompt,
    example_selector=selector,
)
```

The selector picks the `k` most relevant examples based on the
input. Useful when you have many examples but only want the most
relevant few.

---

## `ChatPromptTemplate` with `with_structured_output`

The pattern for forcing a typed response via prompt:

```python
from pydantic import BaseModel

class Answer(BaseModel):
    summary: str
    citations: list[str]
    confidence: float

prompt = ChatPromptTemplate.from_messages([
    ("system", "Answer the question.\n\n{format_instructions}"),
    ("human", "{question}"),
]).partial(
    format_instructions=parser.get_format_instructions(),
)

chain = prompt | model | parser
result = chain.invoke({"question": "What is EKS?"})
# result is an Answer instance
```

`parser.get_format_instructions()` returns a string telling the model
to respond in JSON matching the schema. The parser then parses the
model's JSON output.

---

## RAG — where retrieved docs go

**Retrieved context goes in a `SystemMessage`, not a `HumanMessage`.**
The model treats the system slot as instructions; the human slot as
user input.

```python
retrieved_docs = retriever.invoke(user_question)

prompt = ChatPromptTemplate.from_messages([
    ("system",
     "Use the following documents to answer the user's question.\n\n"
     "Documents:\n{context}"),
    ("placeholder", "{messages}"),
]).partial(context=retrieved_docs)

# Later: prompt.invoke({"messages": [...]})
```

Do not inject retrieved docs as a `HumanMessage`. The model
interprets it as user input, not as instructions.

---

## Common pitfalls

1. **Forgetting `MessagesPlaceholder` for chat history.** If your
   prompt is just `("system", ...) + ("human", "...")` with no
   placeholder, the conversation history isn't passed in. The model
   sees only the latest human message.
2. **`{` in the prompt string** — escape with `{{` and `}}`.
3. **`from_template` vs `from_messages`** — `from_template` is for
   single strings and returns a `PromptTemplate` (string output).
   Use `from_messages` for multi-turn chat.
4. **`partial` is not free.** Each `partial(...)` call returns a
   new prompt object. If you do it in a hot loop, you're
   constructing prompts. Build the partially-applied prompt once
   at module scope.
5. **Putting retrieved context in the human slot** — context
   belongs in a system message.
6. **`FewShotChatMessagePromptTemplate` vs `FewShotPromptTemplate`**
   — use the chat version when the model is a chat model. The
   non-chat version generates plain strings.

---

## See also

- [[AI/langchain/01-mental-model|01-mental-model]] — what a chain is and why the `|` operator matters
- [[AI/langchain/02-messages|02-messages]] — the message types that flow through the prompt
- [[AI/langchain/03-chat-models|03-chat-models]] — what the model does with the formatted prompt
- [[AI/langchain/06-runnables-lcel|06-runnables-lcel]] — the `|` operator and composition primitives
- [[AI/langchain/04-tools|04-tools]] — tools the model calls based on the prompt context
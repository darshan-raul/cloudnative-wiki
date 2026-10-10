---
title: AI Agents
tags: [ai, agents, llm, tool-use, orchestration]
date: 2026-10-10
description: What an LLM agent is, independent of any framework — the loop, tool design, workflows versus agents, the common orchestration patterns, context and memory management, failure modes, guardrails and how to evaluate one.
---

# AI Agents

An agent is a language model running in a loop, deciding for itself which tools to call and when it is finished. That is the whole definition. Frameworks add conveniences on top, but the mechanism is small enough to hold in your head — and understanding it is what lets you debug an agent when it misbehaves.

This note is framework-independent. For a concrete implementation, see the [[AI/langgraph/README|LangGraph curriculum]] and [[AI/langchain/04-tools|LangChain tool calling]].

## The loop

```
          ┌──────────────────────────────────────────────────────────┐
          │                                                          │
 task ──► │  model sees: instructions + history + tool definitions   │
          │        │                                                 │
          │        ├── replies with text ──────────────────────────► │ ──► done
          │        │                                                 │
          │        └── requests tool call(s) ──► your code runs them │
          │                                         │                │
          │        results appended to history ◄────┘                │
          └──────────────────────────────────────────────────────────┘
```

```python
messages = [{"role": "user", "content": task}]
for _ in range(MAX_STEPS):
    reply = model(system=INSTRUCTIONS, messages=messages, tools=TOOLS)
    messages.append(reply)
    if not reply.tool_calls:
        return reply.text                      # the model decided it is finished
    for call in reply.tool_calls:
        result = run_tool(call.name, call.arguments)   # your code, your permissions
        messages.append(tool_result(call.id, result))
raise StepLimitExceeded()
```

Three things to notice:

- **The model never executes anything.** It emits a structured request; your code decides whether and how to run it. Every permission boundary lives in `run_tool`.
- **The model is stateless.** Everything it "knows" about progress is in `messages`. The context window is the agent's entire working memory.
- **Termination is the model's choice**, which is why a step limit and a budget are mandatory.

## Workflow or agent?

Not everything with an LLM in it should be an agent.

|                  | Workflow                               | Agent                                                    |
| :--------------- | :------------------------------------- | :------------------------------------------------------- |
| Control flow     | Written by you, in code                | Chosen by the model at run time                          |
| Predictability   | High                                   | Lower                                                    |
| Cost and latency | Bounded and known                      | Variable, sometimes large                                |
| Debuggability    | Like ordinary software                 | Requires traces of the model's decisions                 |
| Suits            | Tasks whose steps are known in advance | Open-ended tasks where the steps depend on what is found |

**Use the simplest thing that works.** A single well-prompted call beats a workflow; a workflow beats an agent. Reach for an agent when the path genuinely cannot be scripted — investigating a failure, researching a question, working through a codebase — and when the task is valuable enough to justify the cost and the variance.

## Common patterns

| Pattern                  | Shape                                                                        | Use when                                                      |
| :----------------------- | :--------------------------------------------------------------------------- | :------------------------------------------------------------ |
| **Prompt chaining**      | Fixed sequence of calls, each using the previous output                      | The task decomposes cleanly into stages                       |
| **Routing**              | Classify the input, send it to a specialised prompt or model                 | Distinct categories need different handling or different cost |
| **Parallelisation**      | Run independent subtasks at once, or the same task several times and vote    | Speed, or confidence through agreement                        |
| **Orchestrator–workers** | A lead model splits the task and delegates to sub-agents with fresh contexts | Large tasks that would overflow one context                   |
| **Evaluator–optimizer**  | One model produces, another critiques, repeat                                | Clear quality criteria and measurable improvement per round   |
| **Autonomous loop**      | The loop above, with tools                                                   | Open-ended problems                                           |

The first five are workflows with model calls inside them. They can be combined, and a multi-agent system is usually just orchestrator–workers. Multiple agents help mainly by **isolating context** — each sub-agent explores in its own window and returns a short summary — not because several "personalities" are smarter than one.

## Tool design is most of the work

An agent is only as good as its tools, and the model learns what a tool does solely from its name, description and parameter schema.

- **Write descriptions like documentation for a new colleague.** Say what it does, when to use it, when not to, and what it returns. Include an example for anything subtle.
- **Fewer, higher-level tools.** One `search_orders(customer, status, since)` beats exposing a raw SQL tool or thirty CRUD endpoints. Design around the tasks, not around your API.
- **Make misuse hard.** Use enums and required fields, accept forgiving formats, validate and return a helpful error.
- **Return what the model needs, and no more.** A 50,000-token JSON dump crowds out everything else. Paginate, filter and summarise; offer a "detail" tool for the full record.
- **Errors are instructions.** `"No customer with ID 123. Use find_customer(name) to look up the ID."` lets the model recover; a stack trace does not.
- **Idempotent and reversible where possible.** The model will sometimes retry or repeat.

The [[AI/mcp|Model Context Protocol]] standardises how tools are described and exposed so they can be reused across applications — see [[AI/mcp-in-production|MCP in production]].

## Context is the scarce resource

Long-running agents fail when their context fills with stale tool output. Quality degrades well before the hard limit: the model loses track of the goal and of earlier findings.

| Technique                  | What it does                                                                      |
| :------------------------- | :-------------------------------------------------------------------------------- |
| **Compaction**             | Summarise older turns and continue from the summary                               |
| **Tool-result clearing**   | Drop the bodies of old tool results, keeping a note that they happened            |
| **External notes**         | The agent writes progress, decisions and to-dos to a file and re-reads it         |
| **Sub-agents**             | Exploration happens in a separate context; only the conclusion comes back         |
| **Just-in-time retrieval** | Keep references (paths, IDs) in context and load content only when needed         |
| **Prompt caching**         | Reuse the unchanged prefix of the context between steps, cutting cost and latency |

**Memory** across sessions is a separate concern: a store the agent can write to and search — files, a database, or a vector index. Decide deliberately what is worth remembering; unfiltered memory accumulates errors. See [[AI/langgraph/09-memory-store|LangGraph memory store]] and [[AI/vector-databases|vector databases]].

## How agents fail

| Failure                  | What it looks like                                                | Mitigation                                                           |
| :----------------------- | :---------------------------------------------------------------- | :------------------------------------------------------------------- |
| **Compounding errors**   | A small early mistake is built on for twenty steps                | Verification steps; tests or checks the agent can run; shorter tasks |
| **Loops**                | The same failing call, repeated                                   | Step and budget limits; detect repetition; better error messages     |
| **Premature completion** | Declares success without finishing or checking                    | Explicit completion criteria; require evidence                       |
| **Scope creep**          | Does more than asked                                              | Clear instructions about boundaries; narrower tools                  |
| **Fabricated results**   | Reports a tool result it never obtained                           | Verify claims against the trace; structured outputs                  |
| **Context exhaustion**   | Forgets the goal or early constraints                             | Compaction, notes, sub-agents                                        |
| **Prompt injection**     | Follows instructions found in a web page, document or tool result | Treat tool output as data; least privilege; approvals — see below    |

Reliability multiplies down: a step that succeeds 95% of the time gives roughly a 36% chance of twenty steps all succeeding. Long autonomous tasks need verification built in, not just a good model.

## Guardrails

An agent with tools is software acting with your credentials. Apply ordinary security engineering.

1. **Least privilege.** Give each agent only the tools and scopes its task needs. Read-only by default.
2. **Sandbox execution.** Code and shell tools run in an isolated environment with no ambient credentials and restricted network access — see [[Kubernetes/concepts/L07-security/02-workload-sandboxing/17-runtime-sandboxing|runtime sandboxing]].
3. **Human approval for consequential actions.** Sending, paying, deleting, deploying. See [[AI/langgraph/10-human-in-the-loop|human-in-the-loop]].
4. **Treat everything a tool returns as untrusted.** A web page or an email can contain text written to hijack the agent. The dangerous combination is an agent that has access to private data, reads untrusted content, and can send data out; remove one of the three. Details in [[AI/prompt-injection|prompt injection]].
5. **Budgets and limits.** Maximum steps, tokens, spend and wall-clock time, enforced outside the model.
6. **Audit everything.** Log each model call, tool call, argument and result.

## Observability and evaluation

You cannot improve what you cannot see. Record a **trace** per run — every model call and tool call as a span, with tokens, latency and cost. The OpenTelemetry GenAI semantic conventions make these portable across tools; see [[Observability/tracing|distributed tracing]].

Evaluate at three levels:

| Level         | Question                                                                     |
| :------------ | :--------------------------------------------------------------------------- |
| Final outcome | Was the task actually accomplished? Check the end state, not the transcript. |
| Trajectory    | Did it take a sensible path, call the right tools, avoid forbidden ones?     |
| Single step   | Given this context, was the next action right?                               |

Run every task several times — agents are non-deterministic, and a pass rate is more honest than a single run. Build the test set from real failures. The method is in [[AI/evals|evaluating LLM systems]] and [[AI/langgraph/12-testing|testing LangGraph agents]].

## Related

- [[AI|AI hub]]
- [[AI/prompt-engineering/prompt-engineering-patterns|Prompt engineering patterns]] — ReAct and tool-use prompting
- [[AI/rag|Retrieval-augmented generation]] — retrieval as one of an agent's tools
- [[AI/langgraph/11-production|LangGraph in production]]
- [Building effective agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents)

## Across the wiki

- [[Architecture/solution-architecture-concepts/protocols/server-sent-events|Server-Sent Events (SSE) Architecture & LLM Streaming]] — LLM applications (Architecture)
- [[Security/application-security/README|Application Security]] — LLM applications (Security)

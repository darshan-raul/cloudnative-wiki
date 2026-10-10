---
title: MCP in Production
tags: [ai, mcp, agents, tools, security, protocol]
date: 2026-10-10
description: Running Model Context Protocol servers beyond a local demo — the protocol's shape, stdio versus Streamable HTTP, OAuth-based authorization, designing tools models can use, the security threats specific to MCP, deployment and observability.
---

# MCP in Production

The Model Context Protocol (MCP) is an open standard for connecting AI applications to tools and data. Write an integration once as an **MCP server** and any compatible **host** — a chat application, an IDE, an agent framework — can use it. It turns the M×N problem of wiring every application to every system into M+N.

[[AI/mcp|The introductory MCP note]] builds a first server. This one covers what changes when a server is shared, remote and trusted with real data.

## The shape of the protocol

```
┌──────────── host application ────────────┐
│  LLM  ◄──►  agent loop                   │
│               │                          │
│   MCP client ─┼─ MCP client ─ MCP client │      one client per server connection
└───────│───────────────│───────────│──────┘
        │ JSON-RPC 2.0  │           │
   ┌────▼────┐     ┌────▼────┐ ┌────▼────┐
   │ server  │     │ server  │ │ server  │
   │ (files) │     │ (issues)│ │ (db)    │
   └─────────┘     └─────────┘ └─────────┘
```

Messages are JSON-RPC 2.0. A connection begins with an `initialize` handshake in which both sides declare protocol version and **capabilities**.

| Server offers | What it is                                           | Controlled by                   |
| :------------ | :--------------------------------------------------- | :------------------------------ |
| **Tools**     | Functions the model can call                         | The model decides to invoke     |
| **Resources** | Data identified by URI that can be read into context | The application or user selects |
| **Prompts**   | Reusable prompt templates with arguments             | The user invokes                |

| Client offers   | What it is                                                                           |
| :-------------- | :----------------------------------------------------------------------------------- |
| **Sampling**    | The server asks the host's model to generate text, so it needs no API key of its own |
| **Roots**       | The host tells the server which directories or URIs it may operate on                |
| **Elicitation** | The server asks the user for a missing piece of information mid-operation            |

Most servers only implement tools. That is fine — tools are where nearly all the value is.

## Transports

| Transport           | How                                                                         | Use for                                                 |
| :------------------ | :-------------------------------------------------------------------------- | :------------------------------------------------------ |
| **stdio**           | The host launches the server as a child process and talks over stdin/stdout | Local tools on the user's machine; simplest; no network |
| **Streamable HTTP** | A single HTTP endpoint; responses may be plain JSON or an SSE stream        | Remote, shared, multi-user servers                      |

The earlier HTTP+SSE transport with two endpoints is deprecated in favour of Streamable HTTP. With stdio, the server inherits the launching user's environment and privileges, and anything written to stdout that is not a protocol message corrupts the stream — log to stderr.

For remote servers, prefer **stateless** request handling where possible. Sessions (`Mcp-Session-Id`) make horizontal scaling harder: they need sticky routing or a shared store.

## Authorization for remote servers

A remote MCP server is an API and needs real authentication. The specification builds on OAuth 2.1:

- The MCP server acts as an OAuth **resource server**. It does not issue tokens; it validates them.
- An unauthenticated request gets `401` with a pointer to the server's **protected resource metadata**, which names the authorization server.
- The client runs the authorization-code flow with **PKCE**, with the user's consent, and obtains an access token.
- The client includes a **resource indicator** so the token is bound to _this_ server and cannot be replayed against another.
- The server validates signature, issuer, expiry, **audience** and scopes on every request.

```
client ─► server:  request without token
server ─► client:  401 + WWW-Authenticate: resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource"
client ─► auth server: discover, authorize (PKCE, resource=https://mcp.example.com), user consents
client ─► server:  request + Authorization: Bearer <token audience=mcp.example.com>
```

Two rules that prevent the classic mistakes:

1. **Never pass the client's token through to a downstream API.** The token was issued for your server. To call another service on the user's behalf, obtain a separate token for it (token exchange or a stored grant). Passing tokens through breaks audience checks and creates a confused-deputy problem.
2. **Scope to the user.** A shared server must act with the calling user's permissions, not a powerful service account, or it becomes a way around every access control behind it.

The underlying mechanics are covered in the authentication curriculum: [[Architecture/solution-architecture-concepts/authentication/stage2/01-oauth-fundamentals|OAuth fundamentals]], [[Architecture/solution-architecture-concepts/authentication/stage2/02-auth-code-pkce|authorization code with PKCE]] and [[Architecture/solution-architecture-concepts/authentication/stage1/03-validation|token validation]].

## Designing tools a model can use

A model chooses and calls tools based only on their names, descriptions and schemas, and every tool definition consumes context in every request.

- **Design for tasks, not endpoints.** Do not mirror a REST API one-to-one. `find_and_summarise_open_incidents(service)` serves a model better than `list_incidents`, `get_incident` and `list_comments` that it must orchestrate.
- **Keep the tool count low.** Dozens of overlapping tools degrade selection accuracy and waste tokens. If a server must be large, let the host load tool definitions on demand.
- **Names and descriptions are prompt text.** State what the tool does, when to use it, and what it returns. Namespace names (`jira_search_issues`) to avoid collisions across servers.
- **Strict input schemas**: enums, required fields, formats, sensible defaults.
- **Token-efficient output.** Return the fields that matter, paginate, and truncate with a note on how to get more. Offer a concise and a detailed mode.
- **Structured output** with a declared output schema where the result will be processed further.
- **Actionable errors.** Return a tool result marked as an error, with text that tells the model how to fix the call — not a protocol-level exception.
- **Annotations.** Mark tools as read-only, destructive or idempotent so hosts can decide when to ask for confirmation. Treat annotations from servers you do not control as hints, not facts.

Then test with a real model: give it realistic tasks and read the transcripts. Where it picks the wrong tool or the wrong arguments, the description or schema is at fault. The general principles are in [[AI/agents|agents]].

## Security

MCP gives a language model the ability to act. The threats are specific and well documented.

| Threat                                | What happens                                                                           | Mitigation                                                                      |
| :------------------------------------ | :------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------ |
| **Prompt injection via tool results** | A fetched page, issue or email contains instructions the model follows                 | Treat results as untrusted data; least privilege; confirmation for side effects |
| **Tool poisoning**                    | A malicious server hides instructions in its tool _descriptions_                       | Install only trusted servers; review descriptions; show them to the user        |
| **Rug pull**                          | A server changes a tool's definition after it was approved                             | Pin versions; re-approve on change; hash tool definitions                       |
| **Tool shadowing**                    | One server's description manipulates how the model uses another server's tools         | Isolate servers; namespacing; limit which servers are active together           |
| **Confused deputy**                   | The server uses its own broad credentials on behalf of a user who lacks the permission | Per-user authorization; audience-bound tokens; no token passthrough             |
| **Data exfiltration**                 | Injected instructions make the model send private data out through another tool        | Avoid combining private data, untrusted content and outbound channels           |
| **Local server compromise**           | A stdio server runs arbitrary code with the user's privileges                          | Sandbox; restrict filesystem and network; verify the source and pin the version |

The dangerous combination is an agent that can **read private data**, **ingest untrusted content**, and **communicate externally**. Any two are manageable; all three together mean an attacker who can get text in front of the model can steal data. Design so that at least one is absent. More in [[AI/prompt-injection|prompt injection]].

Supply chain matters as much as protocol design: an MCP server is code you run or a service you send data to. Apply the same scrutiny as for any dependency — [[DevOps/devsecops/README|DevSecOps]].

## Deploying a remote server

A Streamable HTTP server is an ordinary web service:

- **Package it as a container** and run it like any other workload — [[Containers/dockerfile-best-practices|Dockerfile best practices]], [[Kubernetes/concepts/L03-workloads/03-deployments|Deployments]].
- **Terminate TLS and validate tokens at a gateway**, and validate again in the server. Validate the `Origin` header to prevent DNS-rebinding attacks against locally bound servers.
- **Configure the load balancer for streaming**: long idle timeouts, no response buffering — see [[Architecture/solution-architecture-concepts/protocols/server-sent-events|server-sent events]].
- **Rate limit per user and per tool**, and set timeouts; a model in a loop can generate a lot of calls. See [[Architecture/solution-architecture-concepts/performance/rate-limiting|rate limiting]].
- **Give the server its own narrowly scoped identity** for the systems behind it — for example [[Kubernetes/eks/security/pod-identity|Pod Identity]] on EKS.
- **Version tools carefully.** Renaming a tool or changing its schema breaks every client; add new tools rather than changing existing ones.

In larger organisations an **MCP gateway** in front of many servers provides one place for authentication, policy, audit logging and an approved catalogue.

## Observability

Log every tool call with the user, tool, arguments (redacted where sensitive), result size, latency and outcome. That audit trail answers "what did the agent do?" after an incident. Emit traces so a tool call appears as a span under the model call that triggered it — [[Observability/tracing|distributed tracing]] — and track per-tool error rate, latency and call volume. Tools that are never called should be removed; tools that fail often need better descriptions or validation.

## When not to use MCP

If one application calls a couple of functions that only it needs, define them directly as tools in that application. MCP pays off when integrations are **shared** across applications or teams, or when third parties need to plug in. For work that is easier expressed as code than as tool calls, letting an agent write and run a script against an API in a sandbox can be more efficient than many small tool round trips.

## Related

- [[AI|AI hub]]
- [[AI/mcp|MCP introduction]]
- [[AI/agents|AI agents]]
- [[AI/langchain/04-tools|LangChain tool calling]]
- [Model Context Protocol specification](https://modelcontextprotocol.io/specification)

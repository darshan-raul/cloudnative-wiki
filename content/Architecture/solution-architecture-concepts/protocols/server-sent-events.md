---
title: Server-Sent Events (SSE) Architecture & LLM Streaming
description: Server-Sent Events (SSE) deep dive — text/event-stream format, Last-Event-ID automatic reconnection, SSE vs WebSockets vs Long-Polling, and streaming generative AI LLM tokens
tags:
  - protocols
  - sse
  - streaming
  - real-time
  - llm
  - http
date: 2026-01-30
---

# Server-Sent Events (SSE) Architecture & LLM Streaming

**Server-Sent Events (SSE)** is a standardized HTTP technology (W3C / WHATWG HTML5) that allows a client to open a persistent HTTP connection and receive a real-time stream of text events pushed by the server.

Unlike WebSockets (which requires a custom protocol upgrade and bidirectional duplex frames), SSE operates over **standard HTTP/1.1 or HTTP/2**, making it the premier choice for unidirectional server-to-client real-time feeds and token-by-token LLM generation.

---

## 1. SSE vs WebSockets vs Long-Polling

| Feature                        | Server-Sent Events (SSE)                           | WebSockets                                          | HTTP Long-Polling              |
| :----------------------------- | :------------------------------------------------- | :-------------------------------------------------- | :----------------------------- |
| **Directionality**             | **Unidirectional** (Server -> Client)              | **Full Duplex** (Bidirectional)                     | Emulated Bidirectional         |
| **Protocol**                   | Standard HTTP (`text/event-stream`)                | Custom TCP protocol (`ws://`, `wss://`)             | Standard HTTP (`GET` / `POST`) |
| **HTTP/2 & HTTP/3**            | **Multiplexed over single TCP/QUIC stream**        | Separate connection per socket                      | Standard request/response      |
| **Reconnection**               | **Built-in automatic reconnection with `id`**      | Manual implementation required                      | Handled per request loop       |
| **Firewall / Proxy Traversal** | **Trivial** (Looks like standard HTTP download)    | Prone to proxy/load balancer drops                  | Trivial                        |
| **Data Format**                | UTF-8 Text / JSON                                  | Binary or Text                                      | Any                            |
| **Best Fit**                   | **LLM token streaming, live metrics, stock feeds** | **Multiplayer gaming, chat, collaborative editing** | Legacy fallback                |

---

## 2. The `text/event-stream` Wire Protocol

An SSE stream is an open-ended HTTP response with `Content-Type: text/event-stream`:

```http
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

id: 101
event: token
data: {"token": "Kubernetes", "finish_reason": null}

id: 102
event: token
data: {"token": " is", "finish_reason": null}

id: 103
event: token
data: {"token": " scalable.", "finish_reason": "stop"}

: keep-alive comment to prevent proxy timeouts
```

### Wire Fields:

- `data:` The text payload. Multiple consecutive `data:` lines are joined with newlines.
- `id:` Event identifier. If the TCP connection drops, the browser automatically sends `Last-Event-ID: 103` on reconnect, enabling the server to resume without data loss.
- `event:` Custom event name (listened to via `addEventListener('custom_name')`).
- `retry:` Milliseconds the client should wait before attempting reconnection (default ~3000ms).
- Lines starting with `:` are comments (used for periodic ping / keep-alive heartbeats).
- Two consecutive newlines (`\n\n`) terminate an individual event.

---

## 3. Production Implementation: FastAPI LLM Streamer

```python
import asyncio
from fastapi import FastAPI
from fastapi.responses import StreamingResponse

app = FastAPI()

async def event_generator():
    tokens = ["Designing", " resilient", " cloud", " native", " systems."]
    for idx, token in enumerate(tokens):
        # Format as SSE event
        yield f"id: {idx}\nevent: message\ndata: {token}\n\n"
        await asyncio.sleep(0.1)

@app.get("/stream-completion")
async def stream_completion():
    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no" # Tells Nginx to disable response buffering!
        }
    )
```

> [!IMPORTANT]
> **The Reverse Proxy Buffering Trap:** If you place Nginx, AWS CloudFront, or an Envoy gateway in front of an SSE service, you must disable response buffering (`X-Accel-Buffering: no` or `proxy_buffering off;`). Otherwise, the proxy will buffer chunks until 4KB or 8KB is collected, destroying the real-time streaming effect!

## Across the wiki

- [[AWS/serverless/api-gateway/README|Amazon API Gateway]] — API design and gateways (AWS)
- [[AWS/application-integration/appsync/README|AWS AppSync]] — API design and gateways (AWS)
- [[AI/agents|AI Agents]] — LLM applications (AI)
- [[Security/application-security/README|Application Security]] — LLM applications (Security)
- [[AI/langgraph/README|LangGraph]] — LLM applications (AI)
- [[AI/langchain/README|LangChain]] — LLM applications (AI)

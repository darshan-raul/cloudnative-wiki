---
title: OpenTelemetry Context Propagation
description: W3C Trace Context, Baggage, propagators
tags:
  - opentelemetry
  - context-propagation
  - w3c
  - baggage
date: 2025-01-01
draft: false
---

# OpenTelemetry Context Propagation

Context propagation is the mechanism that links spans across **process boundaries** (network calls, message queues, async tasks) into a single end-to-end trace.

## W3C Trace Context

The [W3C Trace Context](https://www.w3.org/TR/trace-context/) specification defines the standard format for propagating trace context across services.

### traceparent Header

The `traceparent` header encodes trace and span identity:

```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
             │  │                                │              │
             │  trace_id (32 hex chars)         │   │    │
             │                                   │   │    └── flags (2 hex chars)
             │                                   │   └─────────── span_id (16 hex chars)
             │                                   └────────────── version (2 hex chars)
             └────────────────────────────────────────────────── version prefix
```

| Field | Length | Description |
|-------|--------|-------------|
| `version` | 2 hex | Protocol version (currently `00`) |
| `trace_id` | 32 hex | 16-byte global trace ID |
| `parent_id` (span_id) | 16 hex | 8-byte span ID of the parent |
| `flags` | 2 hex | Options (bit 0 = sampled) |

### tracestate Header

The `tracestate` header carries vendor-specific or cross-cutting metadata:

```
tracestate: congo=t61rcWkgMzE,rojo=00f067aa0ba902b7
```

Format: `key=value,key=value` (max 32 pairs, 256 chars total).

### Rules

- `traceparent` is **mandatory** — must be present and valid
- `tracestate` is **optional** — can be empty or omitted
- Propagation must not modify `traceparent` (only root service sets it)
- `tracestate` is designed for multi-vendor trace correlation

## Propagators API

OTel defines a **Propagators API** — an abstraction over carriers (HTTP headers, message metadata, etc.) — with two operations:

| Operation | Direction | What it does |
|-----------|-----------|-------------|
| `Inject(ctx, carrier)` | Outgoing | Reads trace context from `ctx`, writes it into the carrier (HTTP headers, etc.) |
| `Extract(ctx, carrier)` | Incoming | Reads trace context from the carrier, returns a new `ctx` with the extracted span context |

```go
type Propagator interface {
    Inject(ctx context.Context, carrier TextMapCarrier)
    Extract(ctx context.Context, carrier TextMapCarrier) context.Context
}
```

Carriers are interface-based — any type implementing `TextMapCarrier` works: `http.Header`, `map[string]string`, Kafka headers, etc.

### Built-in Propagators

|| Propagator | `traceparent` | `tracestate` | Baggage | Notes |
||------------|---------------|--------------|---------|-------|
|| `TraceContext` | W3C standard | W3C standard | No | Default |
|| `Baggage` | No | No | W3C standard | Must be combined |
|| `CompositePropagator` | Combines multiple | | | |
|| `B3` (Zipkin) | B3 single header | N/A | Via `bkvr` | Legacy Zipkin |
|| `AWS X-Ray` | AWS format | N/A | No | AWS-specific |
|| `Jaeger` | Jaeger headers | N/A | No | Legacy Jaeger |
|| `W3C` (alias for TraceContext) | W3C standard | W3C standard | No | |

### Setting Propagators (Go)

```go
import "go.opentelemetry.io/otel/propagation"

// Register a composite propagator
otel.SetTextMapPropagator(propagation.NewCompositePropagator(
    propagation.TraceContext{},   // W3C Trace Context
    propagation.Baggage{},         // W3C Baggage
))
```

### Setting Propagators (Python)

```python
from opentelemetry import propagate
from opentelemetry.propagate import set_global_textmap
from opentelemetry.sdk.trace.propagation.tracecontext import TraceContextPropagator

set_global_textmap(TraceContextPropagator())
```

### CompositePropagator

A single service often needs to **inject and extract multiple formats** — for example, supporting both W3C trace context and a legacy Zipkin format, or combining TraceContext with Baggage. `CompositePropagator` chains multiple propagators into one.

## Propagators: ELI5 with Multi-Service Example

### The Problem

```
Service A  →  Service B  →  Service C
   │              │             │
   └── trace ─────────────────────┘
   (but they can't see each other's trace without help)
```

When Service A calls Service B over HTTP, the trace context lives in Service A's memory. Service B has **no idea** what trace it's part of — the context doesn't travel automatically.

### The Solution: Propagator = "Transporter"

A **propagator** is a translator that:
- **Outgoing** (`Inject`): Package trace context → stuff into HTTP headers
- **Incoming** (`Extract`): Read HTTP headers → unpack into memory

```
Service A                                    Service B
  │                                              │
  │  Inject: ctx → headers                        │  Extract: headers → ctx
  │  ┌─────────────────────────────────┐         │
  │  │ traceparent: 00-abc-def-123-01  │         │
  │  │ tracestate: otel.baggage=...    │──── HTTP ──→ reads headers
  │  └─────────────────────────────────┘         │
  │  Span in memory                              │  New span gets parent_id = abc
```

### The Code

```go
// Service A — OUTGOING call
func callServiceB(ctx context.Context) {
    req, _ := http.NewRequest("GET", "http://service-b/api", nil)

    // Inject: reads trace from ctx, writes to HTTP headers
    propagator.Inject(ctx, propagation.HeaderCarrier(req.Header))

    // Headers now look like:
    // traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
    // tracestate: otel.baggagegage="tenant.id=acme"

    http.DefaultClient.Do(req)  // sends headers along with request
}
```

```go
// Service B — INCOMING request
func handleRequest(w http.ResponseWriter, r *http.Request) {
    // Extract: reads traceparent from HTTP headers, returns ctx with span context
    ctx := propagator.Extract(r.Context(), propagation.HeaderCarrier(r.Header))

    // ctx now has: trace_id=0af76519..., parent_id=b7ad6b71, tracestate (tenant.id=acme)

    // Start span — parent is automatically read from ctx
    ctx, span := tracer.Start(ctx, "handle-request")
    defer span.End()

    // Service B's span now shows parent = Service A's span
    // Trace continues: Service A → Service B → (maybe) Service C
}
```

### Service B → Service C

```go
func callServiceC(ctx context.Context) {
    req, _ := http.NewRequest("GET", "http://service-c/api", nil)

    // Same Inject — ctx still has the full trace context from Service A
    propagator.Inject(ctx, propagation.HeaderCarrier(req.Header))

    http.DefaultClient.Do(req)
}
```

```
Service A span          Service B span          Service C span
  │                           │                       │
  │ traceparent (no parent)    │                       │
  │───────────────────────────│                       │
  │              parent_id=A  │                       │
  │                           │ traceparent           │
  │                           │ parent_id=A           │
  │                           │───────────────────────│
  │                           │           parent_id=B│
  │                           │                       │
  └───────────────────────────────────────────────────┘
              All three spans share the same trace_id
```

### The Propagator's Job

| Step | What happens |
|------|-------------|
| `Inject` | Take `trace_id` + `span_id` + `flags` from memory → write to headers |
| `Extract` | Read headers → put `trace_id` + `span_id` + `flags` back into memory |
| `Tracer.Start(ctx, name)` | Reads parent `span_id` from ctx → creates child span |

**That's it.** Propagator is just a courier — it takes trace context from memory, ships it in HTTP headers, and unpacks it on the other side.

## Context API (In-Process)
otel.SetTextMapPropagator(propagation.NewCompositePropagator(
    propagation.TraceContext{},   // W3C Trace Context — handles traceparent + tracestate
    propagation.Baggage{},         // W3C Baggage — handles otel.baggage in tracestate header
))
```

#### How It Works

**Inject (outgoing):** Each propagator writes to the carrier in order. All propagators in the chain write their data. No conflict — `traceparent` and `baggage` are different headers.

**Extract (incoming):** CompositePropagator tries each propagator in order and stops at the **first successful extraction**. Order matters — put the most likely format first.

```
Incoming request
  ▼
CompositePropagator.Extract()
  → Try TraceContext → traceparent found → success → return ctx
  → (Baggage never tried because TraceContext succeeded)
```

#### When to Use

| Scenario | Propagators |
|----------|-------------|
| W3C standard only | `TraceContext{}` alone |
| W3C + Baggage | `TraceContext{}` + `Baggage{}` (order: TraceContext first) |
| Migration from Zipkin | `TraceContext{}` + `B3{}` |
| Multi-vendor | `TraceContext{}` + vendor-specific propagator |

> **Rule of thumb:** For inject, order doesn't matter much. For extract, put the most specific/probable format first — extraction stops at the first match.

#### Python CompositePropagator

```python
from opentelemetry.propagate import set_global_textmap
from opentelemetry.sdk.trace.propagation.tracecontext import TraceContextPropagator
from opentelemetry.sdk.trace.propagation.b3 import B3Propagator

set_global_textmap(TraceContextPropagator())  # single propagator

# For multiple propagators (Python uses a list):
# Note: Python OTel uses a single propagator at a time;
# for composite behavior, combine via TraceContext + Baggage manually
```

```python
# Python: W3C TraceContext with Baggage
from opentelemetry import propagate

# Python's set_global_textmap takes a single propagator
# Use TraceContextPropagator which handles both traceparent and tracestate
from opentelemetry.sdk.trace.propagation.tracecontext import TraceContextPropagator
from opentelemetry.baggage.propagation import W3CBaggagePropagator

set_global_textmap(TraceContextPropagator())  # W3C includes tracestate
```

## Context API (In-Process)

Within a process, trace context lives in `context.Context` (Go) or `contextvars` (Python). The propagator's `Inject`/`Extract` read and write from this in-memory context.

### Reading the Current Span

```go
import "go.opentelemetry.io/otel"

// Get current span from context
span := otel.SpanFromContext(ctx)

// If no span is active, span.IsValid() returns false
if span.SpanContext().IsValid() {
    // we are inside a span
}
```

```python
from opentelemetry import trace

span = trace.get_current_span()
print(f"span={span}")
```

### Starting a Span from Context

`Tracer.Start(ctx, name)` reads the parent span from `ctx`:

```go
// Parent span is extracted from ctx automatically
ctx, span := tracer.Start(ctx, "operation-name")

// The span's parent is whatever span was in ctx
// If ctx has no span, this becomes a root span
```

```python
# Parent is implicit from the context
with tracer.start_as_current_span("operation-name") as span:
    # span is now the current span
    pass
```

### Context + Propagator Interaction

The full flow — inject on outgoing, extract on incoming:

```
HTTP Request (outgoing)
  │ Span from context
  ▼
Propagator.Inject(ctx, http.Header)
  → writes traceparent, tracestate, baggage into headers
  → request sent with headers

HTTP Response (incoming)
  ▼
Propagator.Extract(ctx, http.Header)
  → reads traceparent, creates new ctx with extracted SpanContext
  → ctx passed to Tracer.Start(ctx, "server-span")
  → server span has parent_id = client span
```

```go
// OUTGOING: inject context into request headers
func makeHTTPRequest(ctx context.Context, url string) (*http.Response, error) {
    req, _ := http.NewRequest("GET", url, nil)
    // Inject reads from ctx, writes to http.Header
    otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))
    return http.DefaultClient.Do(req)
}

// INCOMING: extract context from request headers
func handleHTTPRequest(w http.ResponseWriter, r *http.Request) {
    // Extract reads from http.Header, returns new ctx with SpanContext
    ctx := otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))
    // ctx now has parent span from upstream
    ctx, span := tracer.Start(ctx, "server-handler")
    defer span.End()
}
```

### Wrapping a Span's Context

To pass span context through channels, async tasks, or queues — serialize via `SpanContext` fields:

```go
sc := span.SpanContext()
fmt.Printf("trace_id=%s span_id=%s\n", sc.TraceID().String(), sc.SpanID().String())

// On the receiving end, reconstruct the SpanContext
newSc := trace.NewSpanContext(trace.SpanContextConfig{
    TraceID:    traceID,
    SpanID:     spanID,
    TraceFlags: trace.FlagsSampled,
    Remote:     true,
})
_, span := tracer.Start(ctx, "received-task", trace.WithLinks(newSc))
```

## Inject and Extract

### Manual Propagation Example (Go)

```go
// Inject: extract context from span and inject into HTTP headers
import "go.opentelemetry.io/otel/propagation"

func makeHTTPRequest(ctx context.Context, url string) (*http.Response, error) {
    req, _ := http.NewRequest("GET", url, nil)

    // Inject current trace context into request headers
    propagator := propagation.TraceContext{}
    propagator.Inject(ctx, req.Header, propagation.HeaderCarrier(req.Header))

    return http.DefaultClient.Do(req)
}

// Extract: extract trace context from incoming HTTP headers
func handleHTTPRequest(w http.ResponseWriter, r *http.Request) {
    propagator := propagation.TraceContext{}
    ctx := propagator.Extract(r.Context(), propagation.HeaderCarrier(r.Header))

    // ctx now contains extracted trace context
    // Start a span with this context as parent
    ctx, span := tracer.Start(ctx, "handler")
    defer span.End()
}
```

## Baggage

> **Note:** Baggage is **not** a signal. Traces, Metrics, and Logs are signals. Baggage is a **context propagation mechanism** — key-value metadata that flows alongside trace context across service boundaries. It doesn't produce its own telemetry.

Baggage is **key-value metadata** propagated alongside trace context. Unlike span attributes (scoped to a single span), baggage flows through the **entire trace** and across all services.

### Use Cases

- **Tenant ID** — propagate tenant context across all services
- **Feature flags** — carry experiment/flag state
- **Build info** — git SHA, CI pipeline ID
- **Customer ID** — for log correlation

### Baggage Format (W3C)

```
tracestate: otel.baggagegage="key1=value1,key2=value2"
```

Or via dedicated header (less common):

```
baggage: key1=value1, key2=value2
```

### Using Baggage (Go)

```go
import "go.opentelemetry.io/otel/baggage"

// Add baggage
b, _ := baggage.NewMember("tenant.id", "acme-corp")
m, _ := baggage.NewMember("user.role", "admin")
bag, _ := baggage.New(b, m)

ctx := baggage.ContextWithBaggage(ctx, bag)

// Read baggage anywhere in the trace
baggage := baggage.FromContext(ctx)
if val, ok := baggage.Member("tenant.id"); ok {
    span.SetAttributes(attribute.String("tenant.id", val))
}
```

### Baggage Propagation

Baggage propagates via `tracestate` **or** a dedicated header. The `tracestate` approach is preferred (forwarded by more proxies).

```go
// Baggage travels in tracestate by default
otel.SetTextMapPropagator(propagation.NewCompositePropagator(
    propagation.TraceContext{},
    propagation.Baggage{},
))
```

### Baggage Limitations

- **No cardinality limit** — high-cardinality values bloat `tracestate`
- **No encryption** — baggage is in HTTP headers, treat as non-sensitive
- **Forwarded by proxies** — not all proxies forward `tracestate`; check your ingress

## Context Across Async Boundaries

In async languages (Python, JavaScript), trace context must be explicitly passed through async task chains:

```python
import asyncio
from opentelemetry import trace

async def outer():
    async with tracer.start_as_current_span("outer") as span:
        # Tasks must receive context
        await inner(span)  # pass context explicitly

async def inner(span):
    # Extract context from the span to use as parent
    ctx = trace.set_span_in_context(span)
    async with tracer.start_as_current_span("inner", context=ctx):
        pass
```

## Context in Message Queues

When publishing to Kafka, RabbitMQ, SQS, etc., inject context into message headers. When consuming, extract context and create a linked span.

```python
# Publishing: inject trace context into message
from opentelemetry.propagate import inject

headers = {}
inject(headers)  # injects traceparent + baggage into headers
producer.send("my-topic", value=data, headers=headers)
```

```python
# Consuming: extract context from message
from opentelemetry.propagate import extract

headers = message.headers
ctx = extract(headers)
with tracer.start_as_current_span("process-message", context=ctx) as span:
    # span is linked to the producer span
    pass
```

## Trace Context and Sampling

The `traceparent` flags field carries sampling information:

| Flag | Name | Meaning |
|------|------|---------|
| `0x01` | sampled | This trace should be sampled |
| `0x02` | masked | Reserved |

```
traceparent: 00-...-...-01   ← sampled
traceparent: 00-...-...-00   ← not sampled
```

When a span is **not sampled**, the `span_id` is still set but `flags=00`. The trace ID remains — allowing you to see a "phantom" trace showing only the root entry point (useful for counting total requests).

## Multi-Vendor Trace Context

The `tracestate` header allows multiple tracing systems to coexist:

```
tracestate: congo=ucbJq3RxBfS0NYh8wotMi4zZ,rojo=00f067aa0ba902b7
```

Here `congo` is the vendor key for one system, `rojo` for another. OTel's `TraceContext` propagator only handles the W3C keys and ignores vendor-specific keys — configure your vendor-specific propagator for those.

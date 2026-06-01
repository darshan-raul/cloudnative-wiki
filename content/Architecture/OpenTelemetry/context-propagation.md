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

## Propagators

OTel defines a **Propagators API** that injects (outgoing requests) and extracts (incoming requests) context into/from carriers (HTTP headers, message metadata, etc.).

### Built-in Propagators

| Propagator | `traceparent` | `tracestate` | Baggage | Notes |
|------------|---------------|--------------|---------|-------|
| `TraceContext` | W3C standard | W3C standard | No | Default |
| `Baggage` | No | No | W3C standard | Must be combined |
| `CompositePropagator` | Combines multiple | | | |
| `B3` (Zipkin) | B3 single header | N/A | Via `bkvr` | Legacy Zipkin |
| `AWS X-Ray` | AWS format | N/A | No | AWS-specific |
| `Jaeger` | Jaeger headers | N/A | No | Legacy Jaeger |
| `W3C` (alias for TraceContext) | W3C standard | W3C standard | No | |

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

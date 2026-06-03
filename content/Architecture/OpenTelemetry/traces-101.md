---
title: OTel Traces 101
description: Core constructs for distributed tracing — TracerProvider, Tracer, Span, SpanContext, and patterns
tags:
  - opentelemetry
  - traces
  - beginner
date: 2025-01-01
draft: false
---

# OTel Traces 101

## Core Mental Model

A **Trace** is a causal chain of operations across services. Each operation is a **Span**.

```
Trace ID: abc123
│
├── Root Span: "POST /orders"           ← order-service
│     │ Span ID: span-1
│     │
│     ├── Child Span: "validate order"  ← order-service
│     │     │ Span ID: span-2
│     │     └── (work)
│     │
│     └── Child Span: "POST /invoice"   ← order-service
│           │ Span ID: span-3
│           │ (this calls invoice-service)
│           │
│           └── [ propagation via traceparent header ]
│                 │
│                 └── Linked Span: "generate_invoice"  ← invoice-service
│                       │ Span ID: span-4
│                       │ (linked from a DIFFERENT trace context on wire)
```

Context crosses process boundaries via **W3C Trace Context headers** (`traceparent`, `tracestate`).

## Core Constructs

### TracerProvider

**What it is:** The top-level factory that creates `Tracer` instances and manages the tracing pipeline.

- Usually created **once** at application startup (`main()` or init)
- Holds: sampler, span processor/batcher, resource attributes
- Alive for the entire app lifetime
- Must be set globally: `otel.SetTracerProvider(tp)`

```
App starts
  → TracerProvider created → registered globally
  → Shutdown when app exits
```

### Tracer

**What it is:** Creates spans. Scoped to a library or module.

```go
// Go
tracer := tp.Tracer("order-service")           // by name
tracer := tp.Tracer("order-service", trace.WithInstrumentationVersion("1.0.0"))
```

```python
# Python
tracer = trace.get_tracer("invoice-service")    # by name
tracer = trace.get_tracer("invoice-service", "1.0.0")
```

Naming convention: use the **service name** or **module name** as the tracer name. One tracer per logical component.

### Span

**What it is:** The fundamental unit — a named, timed operation.

| Span Field | What it stores |
|-----------|---------------|
| `name` | Human-readable operation name (`"POST /orders"`) |
| `trace_id` | 16-byte ID — identifies the entire trace |
| `span_id` | 8-byte ID — unique within the trace |
| `parent_span_id` | ID of the parent span (empty for root) |
| `start_time` / `end_time` | Wall-clock duration |
| `kind` | `server`, `client`, `producer`, `consumer`, `internal` |
| `status` | `unset`, `ok`, `error` |
| `attributes` | Key-value metadata |
| `events` | Timestamped log messages during the span |
| `links` | Links to spans from other traces |

### Span Lifecycle

```
Start span  ──────── work ────────  End span
   │                                  │
   ▼                                  ▼
span_id assigned               span recorded in trace provider
trace_id assigned             (batched → exported)
parent_span_id set
start_time set
```

## What is a Resource?

A **Resource** represents the **entity producing telemetry** — not the operation, but the *thing* doing the work. Every span is associated with a Resource.

```
Resource
├── service.name       (required)  — logical name of the service
├── service.namespace  — grouping, e.g. "payments"
├── service.version    — e.g. "1.3.0"
├── service.instance.id — unique instance, e.g. pod name
├── cloud.provider     — "aws", "gcp", "azure"
├── cloud.account.id    — cloud account
├── host.name          — hostname
├── container.name     — container name
└── k8s.namespace.name  — Kubernetes namespace
```

### Resource vs SpanAttributes

| Aspect | Resource | SpanAttributes |
|--------|----------|----------------|
| Scope | Process-wide — all spans share it | Per-span |
| Set where | `TracerProvider.WithResource()` | `span.SetAttributes()` |
| Purpose | "Who is producing this data?" | "What happened in this span?" |
| Examples | `service.name`, `cloud.region`, `host.name` | `http.status_code`, `db.operation`, `error` |

All spans from a TracerProvider inherit its Resource automatically — you set it once at startup.

### Auto-Detection

The OTel SDK can detect resource attributes from the environment:

```go
import "go.opentelemetry.io/otel/sdk/resource"

// Detect Docker, Kubernetes, AWS, cloud info automatically
res, err := resource.New(ctx,
    resource.WithAttributes(
        attribute.String("service.name", "order-service"),
    ),
    resource.WithHost(),
    resource.WithContainer(),
    resource.WithKubernetes(),
    resource.WithAWS(),
)
```

In Kubernetes, this populates `k8s.namespace.name`, `k8s.pod.name`, `container.id` automatically from downward API and cAdvisor.

### Resource in TracerProvider

```go
tp := trace.NewTracerProvider(
    trace.WithResource(resource.New(ctx,
        resource.WithAttributes(
            attribute.String("service.name", "order-service"),
            attribute.String("service.version", "1.3.0"),
        ),
    )),
)
```

All spans created via `tp.Tracer(...)` inherit this resource.

## Step-by-Step: Manual Tracing (Go)

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/sdk/trace"
    "go.opentelemetry.io/otel/sdk/resource"
)

// 1. Create Resource (who is producing telemetry?)
res := resource.New(ctx,
    resource.WithAttributes(
        attribute.String("service.name", "order-service"),
        attribute.String("service.version", "1.3.0"),
    ),
    resource.WithHost(),
    resource.WithContainer(),
)

// 2. Create TracerProvider (once at startup)
tp := trace.NewTracerProvider(
    trace.WithResource(res),
    trace.WithSampler(trace.AlwaysSample()),
)

// 2. Register globally (needed by otelhttp and auto-instrumentation)
GlobalTracerProvider = tp    // or: otel.SetTracerProvider(tp)

// 3. Get a Tracer
tracer := tp.Tracer("order-service")

// 4. Start a span
ctx, span := tracer.Start(ctx, "handleOrders")
defer span.End()                     // ← always defer

// 5. Add attributes (metadata)
span.SetAttributes(
    attribute.String("order.id", orderID),
    attribute.Float64("order.amount", amount),
    attribute.String("http.method", "POST"),
)

// 6. Add an event (a log point in time)
span.AddEvent("order validated")
span.AddEvent("invoice response received", trace.WithAttributes(
    attribute.Int("http.status_code", 201),
))

// 7. Mark error if needed
span.SetStatus(codes.Error, "failed to call invoice service")
```

## Step-by-Step: Manual Tracing (Python)

```python
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

# 1. Get the global tracer
tracer = trace.get_tracer("invoice-service")

# 2. Start a span (context manager auto-ends)
with tracer.start_as_current_span("generate_invoice") as span:
    # set attributes
    span.set_attribute("invoice.order_id", str(order_id))
    span.set_attribute("invoice.amount", amount)

    # add event
    span.add_event("invoice generation started")

    # do work
    invoice = generate_invoice(order_id, amount)

    # mark error if needed
    span.set_status(Status(StatusCode.OK))

    # or: span.set_status(Status(StatusCode.ERROR, "reason"))
```

## Key Patterns

### Pattern 1: Context Passing

The `ctx` carries the current trace context. Start a span with it — children automatically link.

```go
// Parent: creates span and embeds in ctx
ctx, span := tracer.Start(ctx, "parent-operation")
defer span.End()

// Child: inherits parent from ctx
// ctx now contains parent span_id
ctx, child := tracer.Start(ctx, "child-operation")
defer child.End()
```

### Pattern 2: HTTP Client Span (Child of Parent)

```go
// spanCtx from parent span, inject into HTTP request
ctx, span := tracer.Start(ctx, "call-downstream")
defer span.End()

req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)

// otelhttp.NewClient() auto-injects traceparent into headers
client := otelhttp.NewClient()
resp, _ := client.Do(req)
```

### Pattern 3: Linking Spans Across Services (Cross-Service Parent-Child)

```
Service A (parent)                              Service B (child)
┌─────────────────────┐                        ┌─────────────────────┐
│ tracer.Start(ctx,   │  HTTP/headers:         │ propagator.Extract()│
│   "parent")         │──traceparent:──────────▶│ tracer.start_span() │
│   span.SetAttr(...)│  00-{trace_id}-...-01   │   uses parent ctx   │
└─────────────────────┘                        └─────────────────────┘
```

Python receiving the trace:

```python
# Automatically extracts traceparent from incoming request headers
# Just pass the request context — no manual work needed

ctx = trace.get_current_span().get_span_context()  # extract from current span
with tracer.start_as_current_span("receive_invoice", context=ctx) as span:
    # span is linked as child of the Go service's "call-downstream" span
    span.set_attribute("invoice.order_id", order_id)
```

### Pattern 4: HTTP Ingress Auto-Instrumentation

Instead of manually wrapping every handler, use the auto-instrumentation library:

```go
// Instead of writing manually:
http.HandleFunc("/orders", func(w http.ResponseWriter, r *http.Request) {
    // manual span here
})

// Write this:
otelHandler := otelhttp.NewHandler(
    http.DefaultServeMux,
    "order-service",
)
// All routes now auto-create spans with HTTP attributes
http.Handle("/orders", otelHandler)
```

```python
# Python
# Auto-instrument httpx client
from opentelemetry.instrumentation.httpx import HTTPClientInstrumentor
HTTPClientInstrumentor().instrument()
# All httpx calls now auto-create spans with trace context injected
```

### Pattern 5: Marking Errors

```go
span.SetStatus(codes.Error, "database connection failed")
span.SetAttributes(attribute.Bool("error", true))
```

```python
from opentelemetry.trace import Status, StatusCode

span.set_status(Status(StatusCode.ERROR, "database connection failed"))
span.set_attribute("error", True)
```

## SpanKind Explained

| Kind | When to use | Visual |
|------|------------|--------|
| `internal` (default) | Operations inside your service with no external call | No arrow |
| `server` | Incoming request (HTTP handler, gRPC server) | `←───` |
| `client` | Outgoing call (HTTP GET, DB query) | `───▶` |
| `producer` | Message sent to queue (no reply expected) | `───▸` |
| `consumer` | Message received from queue | `▸───` |

Use `server` or `client` explicitly for clarity in service maps.

```go
_, span := tracer.Start(ctx,
    "http get",
    trace.WithSpanKind(trace.SpanKindClient),  // explicit
)
```

## Attribute Conventions

Use OTel semantic conventions for standard attribute names:

| Attribute | Value |
|-----------|-------|
| `http.method` | `"GET"`, `"POST"` |
| `http.url` | `"https://api.example.com/users"` |
| `http.status_code` | `200`, `404`, `500` |
| `db.system` | `"postgresql"`, `"redis"` |
| `db.operation` | `"SELECT"`, `"INSERT"` |
| `db.statement` | `"SELECT * FROM orders"` |
| `messaging.system` | `"kafka"`, `"rabbitmq"` |
| `error` | `true` (when span is an error) |

```go
span.SetAttributes(
    attribute.String("http.method", "POST"),
    attribute.Int("http.status_code", 201),
    attribute.String("db.system", "postgresql"),
    attribute.String("db.operation", "INSERT"),
)
```

## Sampling

Sampling decides **which spans are recorded and exported**. Without it, high-throughput services would generate millions of spans per minute and overwhelm backends and collectors.

### Head-Based vs Tail-Based

| Type | When decision is made | What it sees | Use case |
|------|---------------------|--------------|----------|
| **Head-based** | At `Span.Start()` — before work is done | Nothing (future tense) | Default SDK behavior |
| **Tail-based** | After `Span.End()` — when span is complete | Full span with status, attributes, duration | Collector pipeline |

```
HEAD-BASED (SDK — at start)
tracer.Start(ctx, "op") → Sampler.ShouldSample(ctx) → decision made → span recorded or dropped

TAIL-BASED (Collector — at end)
span.End() → span sent to collector → tail_sampling processor sees full span → policy applied
```

Head-based is **deterministic** — decision is instant, no buffering needed.
Tail-based is **selective** — you can sample based on errors, slow spans, specific routes.

### How Sampling Works

When `tracer.Start(ctx, name)` is called:

```
1. TracerProvider checks if a span is already active in ctx (parent)
   └─ If yes: ParentBased sampler inherits parent's decision
   └─ If no (root span): Sampler.ShouldSample() is called

2. ShouldSample returns:
   ├── Sampled    → span is recorded, flags=01 set in traceparent
   └── NotSampled → span object created but no data is recorded
                    (lightweight — just discards on End)

3. For sampled spans: data is batched → exporter → collector
   For not-sampled: span object is lightweight but data is dropped
```

```go
// Sampler interface
type Sampler interface {
    ShouldSample(parentSamplingContext) SamplingResult
    Description() string
}

type SamplingResult struct {
    Decision   SamplingDecision  // Sampled | NotSampled | Drop
    Tracestate Tracestate
    Attributes []Attribute
}
```

### Built-in Samplers

|| Sampler | When to use | Gotcha |
||---------|------------|--------|
| `AlwaysOn` | Dev — every span recorded | Produces huge volume |
| `AlwaysOff` | Perf testing, disabled tracing | All spans dropped |
| `TraceIdRatioBased(0.1)` | Prod head-based — sample 10% of traces | All children of sampled root are sampled |
| `ParentBased(child)` | Prod default — respect upstream decision | Child inherits parent's flags; if no parent, uses child sampler |

**ParentBased is the standard for production:**

```go
// Standard production config: respect parent's decision, fallback to 10% sampling
sampler := trace.ParentBased(
    trace.TraceIDRatioBased(0.1),  // root spans: 10%
)

tp := trace.NewTracerProvider(
    trace.WithSampler(sampler),
)
```

### TraceIdRatio: Hash Mechanics

`TraceIDRatioBased` doesn't use random numbers — it hashes the `trace_id` to ensure **consistent sampling**:

```
trace_id = "0af7651916cd43dd8448eb211c80319c"
           ↓
        SHA-256 hash (lower 8 bytes as uint64)
           ↓
        Compare against threshold (0.1 × 2^64)
           ↓
    If hash < threshold → Sampled
    If hash >= threshold → NotSampled
```

**Why hash instead of random?**
- Same trace_id always gets the same decision — no split traces
- Across multiple collectors/replicas, consistent sampling
- If 10% of trace_ids are sampled, exactly 10% of traces are sampled

### The Sampled Flag in traceparent

The `flags` byte in `traceparent` carries the sampling decision:

```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
                                                         ^^
                                                      flags (01 = sampled)
```

| Flags | Meaning |
|-------|---------|
| `01` | Sampled — all downstream services record spans |
| `00` | Not sampled — downstream SDKs record NOTsampled spans (see below) |

**Key insight:** A `flags=00` trace still has a valid `trace_id` and `span_id` — you can see it as a "phantom trace" with only the root span. This is useful for **request counting** even without full span data.

**Child span behavior with not-sampled parent:**
- `ParentBased` sampler: child follows parent → not sampled
- `TraceIDRatio` on child: child makes its own decision (not recommended — creates partial traces)

### Tail-Based Sampling (Collector)

Head-based sampling is cheap but blunt — you sample before knowing if the request failed or was slow. Tail-based sampling decides **after the span is complete** based on policies:

```yaml
processors:
  tail_sampling:
    decision_wait: 10s  # wait for spans to accumulate before making decision
    policies:
      # Sample 100% of errors
      - name: errors
        type: status_code
        status_code: {status_codes: [ERROR]}

      # Sample slow spans > 1s
      - name: slow-traces
        type: latency
        latency: {threshold_ms: 1000}

      # Sample 1% of everything (fallback)
      - name: probabilistic
        type: probabilistic
        probabilistic: {sampling_percentage: 1}

      # Always keep traces with specific service name
      - name: high-value-service
        type: string_attribute
        string_attribute: {key: service.name, values: [["payment-service", "order-service"]]}
```

```
Span.End()
   │
   ▼
BatchProcessor (queues spans)
   │
   ▼ (after batch timeout or max queue size)
tail_sampling processor
   │
   ├── status_code=ERROR?     → sample 100%
   ├── duration > 1s?         → sample 100%
   ├── service.name in list?  → sample 100%
   └── else                   → probabilistic 1%
```

**Typical prod setup:**
- Head-based: sample 10-20% at SDK (keeps costs predictable)
- Tail-based: override to 100% for errors and slow spans (preserves debugging data)

### Common Configurations

```go
// DEV: capture everything
trace.WithSampler(trace.AlwaysOn())

// PROD head-only: 10% with parent inheritance
trace.WithSampler(trace.ParentBased(trace.TraceIDRatioBased(0.1)))

// PROD head + tail: 10% at SDK, 100% for errors at collector
// SDK:
trace.WithSampler(trace.ParentBased(trace.TraceIDRatioBased(0.1)))
// Collector: tail_sampling with error/latency policies
```

## Typical Setup: Traces

**Go:**
```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

func initTracer(ctx context.Context) (func(), error) {
    exporter, err := otlptracegrpc.New(ctx)
    if err != nil {
        return nil, err
    }

    tp := trace.NewTracerProvider(
        trace.WithBatcher(exporter),            // batch spans before sending
        trace.WithResource(resource.New(ctx,
            resource.WithAttributes(
                semconv.ServiceName("order-service"),
                semconv.ServiceVersion("1.0.0"),
            ),
        )),
        trace.WithSampler(trace.AlwaysSample()), // change to ParentBased for prod
    )

    otel.SetTracerProvider(tp)
    otel.SetTextMapPropagator(propagation.NewCompositePropagator(
        propagation.TraceContext{},
        propagation.Baggage{},
    ))

    return func() { tp.Shutdown(context.Background()) }, nil
}
```

**Python:**
```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

def init_tracer():
    trace_exporter = OTLPSpanExporter(
        endpoint=os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"],
        insecure=True,
    )
    tracer_provider = TracerProvider()
    tracer_provider.add_span_processor(BatchSpanProcessor(trace_exporter))
    trace.set_tracer_provider(tracer_provider)
    return trace.get_tracer("invoice-service")
```

## SpanContext

A **SpanContext** is the minimal data required to link a span across process boundaries — it's the carrier of trace identity.

### What It Contains

```
SpanContext
├── trace_id   (16 bytes)  — the trace this span belongs to
├── span_id    (8 bytes)   — the span's own ID
├── trace_flags (1 byte)   — bit 0 = sampled flag (0x01 = sampled)
├── tracestate (optional)  — vendor-specific key-value pairs (propagator-specific)
└── remote     (bool)      — true if this context is from a remote (cross-process) peer
```

### Go: Reading SpanContext

```go
span := trace.SpanFromContext(ctx)

// Read current span context
sc := span.SpanContext()
fmt.Printf("trace_id=%s span_id=%s sampled=%t\n",
    sc.TraceID().String(),
    sc.SpanID().String(),
    sc.IsSampled(),
)
```

### Python: Reading SpanContext

```python
from opentelemetry import trace

span = trace.get_current_span()
sc = span.get_span_context()
print(f"trace_id={sc.trace_id} span_id={sc.span_id} remote={sc.is_remote}")
```

### Trace Flags and the Sampled Bit

The `trace_flags` byte carries the **sampled** flag:

| Flag | Value | Meaning |
|------|-------|---------|
| `0x00` | Not sampled | Trace exists but spans should not be recorded |
| `0x01` | Sampled | Trace is sampled — record spans |

```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-abc123456def-01
                                                         ^^
                                                      sampled flag
```

Even in a **not-sampled** trace, the `trace_id` and `span_id` are still set (you can see the trace in SigNoz as a "phantom" root with zero child spans — useful for counting total requests).

### IsRemote: Local vs Cross-Process Context

```go
sc := span.SpanContext()
if sc.IsRemote() {
    // This context arrived from another service (via propagator.Extract)
    // Don't re-export to avoid loops
}
```

When the Propagator extracts `traceparent` from HTTP headers, it sets `remote=true`. This matters when the Collector is re-exporting spans — it uses `remote` to decide whether to propagate or re-export.

### SpanContext in Proto

```protobuf
message SpanContext {
  bytes trace_id = 1;           // 16 bytes
  fixed64 span_id = 2;         // 8 bytes
  TraceFlags trace_flags = 3;  // 1 byte (sampled bit)
  string tracestate = 4;       // vendor baggage
  bool is_remote = 5;          // remote extraction (SDK internal)
}
```

## SpanStatus

Every span has a `Status`. It is **not** just for errors — it has three states:

| Status | Code | When to use |
|--------|------|-------------|
| `Unset` | `0` | Default — no status set. Treated as `Ok`. Backend typically does not display. |
| `Ok` | `1` | Span completed successfully. Set explicitly when you want to guarantee the status is visible. |
| `Error` | `2` | Span ended in a failure. Span will surface in error-focused views in SigNoz. |

### When to Set Status Explicitly

Set `Ok` for non-error cases only when you want **guaranteed status display** in backends that filter by status. Otherwise `Unset` is fine.

```go
// For a successful span — only set explicitly if you want it visible in status filters
span.SetStatus(codes.Ok, "order processed successfully")

// For an error — always set
span.SetStatus(codes.Error, "failed to connect to invoice service: connection refused")
span.SetAttributes(attribute.Bool("error", true))
```

```python
from opentelemetry.trace import Status, StatusCode

span.set_status(codes.Ok)
span.set_status(codes.Error, "connection refused")
```

### Status and Semantic Conventions

The backends use `Status` to power **error rate** calculations and alerting. A span not marked `Error` even with an exception attributes `error=true` may not appear in error dashboards.

## SpanEvents vs SpanLinks

These are often confused. They are fundamentally different constructs.

### SpanEvents

An **event** is a **log point in time** during a span. It:
- Belongs to exactly **one span**
- Has a timestamp
- Can have attributes
- Does **not** carry its own `span_id` independently — it's embedded in the parent span's record

```go
span.AddEvent("validation failed",
    trace.WithAttributes(
        attribute.String("validation.error", "amount exceeds limit"),
        attribute.Float64("amount", 50000.00),
    ),
)
```

In SigNoz: events appear as **dots on the span timeline** — useful for breadcrumbs.

### SpanLinks

A **link** connects a span to a span from a **different trace** — without establishing a parent-child relationship.
Use when:

- A async job is associated with a trace but not causally initiated by it (e.g., a background job dispatched after an order)
- An error monitoring span is linked to the trace that triggered the error
- A batch process spans multiple traces that are logically related but not causally linked

```go
import "go.opentelemetry.io/otel/trace"

// Link to a span from a different trace
linkedSc := trace.NewSpanContext(trace.SpanContextConfig{
    TraceID:    traceIDFromSomewhere,
    SpanID:     spanIDFromSomewhere,
    TraceFlags: trace.FlagsSampled,
    Remote:     true,
})

_, span := tracer.Start(ctx, "background-job",
    trace.WithLinks(linkedSc),  // ← this is the key call
)
defer span.End()
```

```python
from opentelemetry import trace

# Create a span context from a linked trace
linked_sc = trace.SpanContext(
    trace_id=trace_id_from_other_trace,
    span_id=span_id_from_other_trace,
    is_remote=True,
    trace_flags=trace.TraceFlags(0x01),
)

tracer.start_as_current_span(
    "background_job",
    links=[trace.Link(linked_sc, attributes={"job.type": "order-audit"})],
)
```

### Event vs Link Comparison

| Aspect | SpanEvent | SpanLink |
|--------|-----------|---------|
| Scope | Inside a single span | Cross-trace — no parent-child relationship |
| `trace_id` | Same as parent span | **Different** from the linking span |
| Use case | Breadcrumbs, step markers | Background jobs, error association, batch processes |
| In SigNoz | Dots on span timeline | Separate entries in the trace list for the linked trace |
| `parent_id` | Refers to the parent span | None — this is not a parent-child relationship |

## SpanAttributes vs SpanEvents

These are often confused. They serve different purposes:

| Aspect | SpanAttributes | SpanEvents |
|--------|---------------|------------|
| When set | At `Start()` or any time via `SetAttributes` | At any point via `AddEvent` |
| Cardinality | Low — one value per attribute key (deduplicated) | High — one event per call, can have many |
| Visual in backend | Shown as static span metadata fields | Shown as dots on the span timeline |
| Use for | Static metadata: `user.id`, `region`, `db.system` | Timestamps: "validation failed", "cache miss", "lock acquired" |
| Sampled | Subject to sampler — dropped entirely if span is not sampled | Same as parent span — dropped with span |
| Overhead | Negligible — just key-value pairs in the span | Higher — each event has its own timestamp and attributes |

```go
// Attributes: set once, describe the operation context
span.SetAttributes(
    attribute.String("user.id", "usr_123"),
    attribute.String("db.system", "postgresql"),
    attribute.String("db.operation", "SELECT"),
)

// Events: fired at specific points in time during the span
span.AddEvent("cache miss", trace.WithAttributes(
    attribute.String("cache.key", "product:sku:42"),
    attribute.Float64("latency_ms", 12.5),
))

span.AddEvent("validation failed", trace.WithAttributes(
    attribute.String("error", "amount exceeds limit"),
    attribute.Float64("amount", 50000.00),
))
```

**Key rule of thumb:** If the data describes the span itself, use an **attribute**. If the data marks something that happened *at a moment* during the span's lifetime, use an **event**.

## Span Recording Behavior

The OTel SDK records spans on `span.End()`. This has important implications:

### Lazy Recording (Default in OTel SDK)

Spans are recorded **lazily** — no data is sent when `tracer.Start()` is called. Data is written and batched only when `span.End()` is called (or the batch interval fires).

**Consequence:** If your process crashes between `Start()` and `End()`, the span is lost.

### Eager Recording (for Critical Operations)

For production-critical spans (e.g., payment processing), use the `otel_sdk_tracesExporter` that supports synchronous export on end. In practice, you rely on the batch processor's retry queue:

```go
tp := trace.NewTracerProvider(
    trace.WithBatcher(exporter,
        trace.WithBatchTimeout(5*time.Second),
        trace.WithMaxExportBatchSize(512),
    ),
)
```

The batch processor holds spans in a queue before exporting. If a crash loses the in-flight queue, those spans are gone — which is why some payment instrumentation uses synchronous export with `WithExportThreshold(1)` pattern.

### SpanProcessor (What Goes Between Start and Export)

The SDK talks to a `SpanProcessor` as spans end:

```go
span.End()                    // 1. Called in your code
  → SpanProcessor.OnEnd(span) // 2. SDK notifies processor
      → BatchProcessor        // 3. BatchProcessor holds until batch full or timeout
          → SpanExporter      // 4. Batch sent to OTLP
```

### SpanProcessor

The SDK calls a `SpanProcessor` when spans end, before export:

```
span.End()                    // 1. Called in your code
  → SpanProcessor.OnEnd(span) // 2. SDK notifies processor
      → BatchProcessor        // 3. BatchProcessor holds until batch full or timeout
          → SpanExporter      // 4. Batch sent to OTLP
```

**Never block `span.End()` in production** — use `BatchSpanProcessor`.

#### SpanProcessors

| Processor | Behavior | Blocking? | Use Case |
|-----------|----------|-----------|----------|
| `SimpleSpanProcessor` | Exports each span synchronously on `span.End()` | Yes | Dev, very low traffic, tests |
| `BatchSpanProcessor` | Buffers spans in queue, exports on batch size or schedule | No | **Production default** |
| `FilteredSpanProcessor` | Conditionally drops spans before batching | No | Debug filtering |

#### BatchSpanProcessor Options (Go)

| Option | Default | Description |
|--------|---------|-------------|
| `WithMaxQueueSize(n)` | 2048 | Max spans queued before forcing export |
| `WithBatchSize(n)` | 512 | Spans per batch before triggering export |
| `WithBatchTimeout(d)` | 5s | Force export after duration (even if batch not full) |
| `WithExportThreshold(n)` | 1 | Force sync export when queue reaches n (for critical spans) |

```go
// Production: non-blocking batch export
processor := trace.NewBatchSpanProcessor(exporter,
    trace.WithMaxQueueSize(2048),
    trace.WithBatchSize(512),
    trace.WithBatchTimeout(5*time.Second),
)

// Critical path: force sync export for payment spans
criticalProcessor := trace.NewBatchSpanProcessor(exporter,
    trace.WithMaxQueueSize(2048),
    trace.WithExportThreshold(1),  // export immediately if queue ≥ 1
)
```

#### BatchSpanProcessor Options (Python)

| Option | Default | Description |
|--------|---------|-------------|
| `max_queue_size` | 2048 | Max spans queued |
| `scheduled_delay_seconds` | 5s | Force export after duration |
| `max_export_batch_size` | 512 | Spans per batch |

```python
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Production default
processor = BatchSpanProcessor(
    span_exporter,
    max_queue_size=2048,
    scheduled_delay_seconds=5.0,
    max_export_batch_size=512,
)
```

#### SimpleSpanProcessor (Go + Python)

```go
// Go — blocks on every span.End(), only for dev/tests
processor := trace.NewSimpleSpanProcessor(exporter)
```

```python
# Python — blocks on every span, only for dev/tests
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
processor = SimpleSpanProcessor(span_exporter)
```

### SpanExporter

The `SpanExporter` serializes and sends completed spans to a backend.

#### Go Exporters

| Exporter | Package | Config |
|----------|---------|--------|
| **OTLP** (gRPC) | `go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc` | `WithEndpoint()`, `WithInsecure()` |
| **OTLP** (HTTP) | `go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp` | `WithEndpoint()`, `WithInsecure()` |
| **Jaeger** (Thrift) | `go.opentelemetry.io/otel/exporters/jaeger` | `WithAgentEndpoint()`, `WithEndpoint()` |
| **Zipkin** | `go.opentelemetry.io/otel/exporters/zipkin` | `WithEndpoint()` |
| **Console** | `go.opentelemetry.io/otel/exporters/stdout/stdouttrace` | (dev only) |
| **Datadog** | `gopkg.in/DataDog/dd-trace-go.v1/contrib/otel` | via Datadog exporter package |

```go
import (
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/exporters/jaeger"
    "go.opentelemetry.io/otel/exporters/zipkin"
    "go.opentelemetry.io/otel/exporters/stdout/stdouttrace"
)

// OTLP gRPC (SigNoz, Grafana Tempo, etc.)
exporter, _ := otlptracegrpc.New(ctx,
    otlptracegrpc.WithEndpoint("localhost:4317"),
    otlptracegrpc.WithInsecure(),  // no TLS for local dev
)

// Jaeger Thrift (legacy Jaeger)
exporter, _ := jaeger.New(
    jaeger.WithAgentEndpoint("localhost:6831"),
)

// Zipkin
exporter, _ := zipkin.New(
    zipkin.WithEndpoint("http://localhost:9411/api/v1/traces"),
)

// Console (stdout debug)
exporter, _ := stdouttrace.New(stdouttrace.WithPrettyPrint())
```

#### Python Exporters

| Exporter | Package | Config |
|----------|---------|--------|
| **OTLP** (gRPC/HTTP) | `opentelemetry-exporter-otlp` | `endpoint`, `insecure` |
| **Jaeger** | `opentelemetry-exporter-jaeger` | `agent_port` |
| **Zipkin** | `opentelemetry-exporter-zipkin` | `endpoint` |
| **Console** | `opentelemetry-sdk` (built-in) | (dev only) |

```python
from opentelemetry.exporter.otlp import OTLPSpanExporter
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.exporter.zipkin.thrift import ZipkinExporter
from opentelemetry.sdk.trace.export import ConsoleSpanExporter

# OTLP gRPC (SigNoz, Grafana Tempo, etc.)
exporter = OTLPSpanExporter(
    endpoint="http://localhost:4317",
    insecure=True,  # no TLS for local dev
)

# Jaeger Thrift
exporter = JaegerExporter(
    agent_host="localhost",
    agent_port=6831,
)

# Zipkin
exporter = ZipkinExporter(
    endpoint="http://localhost:9411/api/v1/traces",
)

# Console (stdout debug)
exporter = ConsoleSpanExporter()
```

#### Exporter Architecture

```
SDK SpanProcessor
      │
      ▼
SpanExporter.Export()     ← Protocol-specific serialization (OTLP, Thrift, JSON)
      │
      ▼
Network (gRPC/HTTP)       ← OTLP gRPC :4317, OTLP HTTP :4318, Jaeger Thrift :6831
      │
      ▼
Collector or Backend
```

> **Note:** The Collector receives OTLP natively on :4317 (gRPC) and :4318 (HTTP). For non-OTLP backends (Jaeger, Zipkin), your app SDK can either export directly or via the Collector as a relay.

## Construct Hierarchy

```
TracerProvider
  ├── Tracer ("order-service")
  │     ├── Span ("handleOrders")
  │     │     ├── SpanContext {trace_id, span_id, flags, remote=false}
  │     │     ├── attributes: {order.id, order.amount}
  │     │     ├── events: ["order validated", "cache miss"]
  │     │     ├── status: Ok
  │     │     └── child: Span ("POST invoice-service")
  │     │           ├── kind: client
  │     │           └── link to: [Span from different trace] (via SpanLink)
  │     │
  │     └── Span ("POST /health", parent=root)
  │           └── kind: client
  │
  └── Tracer ("invoice-service")
        └── Span ("generate_invoice", parent=linked)
              ├── trace_id: same as root (propagated)
              └── parent_span_id: matches the Go service's child span
```

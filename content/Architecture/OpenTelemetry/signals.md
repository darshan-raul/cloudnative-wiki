---
title: OpenTelemetry Signals
description: Data models for Traces, Metrics, and Logs
tags:
  - opentelemetry
  - signals
  - traces
  - metrics
  - logs
date: 2025-01-01
draft: false
---

# OpenTelemetry Signals

OpenTelemetry defines three **signals** — the fundamental types of telemetry.

## Traces

### Data Model

A **Trace** is a directed acyclic graph (DAG) of **Spans**. Each span represents a unit of work.

```
Trace
└── Span (root)
    ├── Span (child of root)
    │   ├── Span (child of Span 1.1)
    │   └── Span (child of Span 1.1)
    └── Span (child of root)
```

### Span Model

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Human-readable operation name |
| `trace_id` | 16-byte ID | Globally unique trace identifier |
| `span_id` | 8-byte ID | Unique span within the trace |
| `parent_span_id` | 8-byte ID | Parent span ID (empty for root) |
| `start_time` / `end_time` | Timestamp | Wall-clock start and end |
| `kind` | SpanKind | `server`, `client`, `producer`, `consumer`, `internal` |
| `status` | Status | `unset`, `ok`, `error` |
| `attributes` | Map[string, Value] | Key-value pairs describing the span |
| `events` | []SpanEvent | Timestamped log messages during the span |
| `links` | []SpanLink | Links to other spans (potentially from other traces) |

### SpanKind

| Kind | Meaning |
|------|---------|
| `server` | Incoming request handler |
| `client` | Outgoing request to a dependency |
| `producer` | Message sent to a queue (no immediate response) |
| `consumer` | Message received from a queue |
| `internal` | Internal operation (default) |

### Example: Creating a Span (Go)

```go
func outer(ctx context.Context) {
    // Start a span from context (parent automatically set)
    ctx, span := tracer.Start(ctx, "outer")
    defer span.End()

    span.SetAttributes(
        attribute.String("operation", "outer"),
        attribute.Int("request_id", 42),
    )

    // Child span inherits trace context
    inner(ctx)

    span.AddEvent("outer_complete")
}
```

### Example: Creating a Span (Python)

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("outer") as span:
    span.set_attribute("operation", "outer")
    with tracer.start_as_current_span("inner") as child:
        child.set_attribute("inner.detail", "value")
    span.add_event("outer_complete")
```

## Metrics

### Instruments

| Instrument | Type | Use |
|------------|------|-----|
| **Counter** | Synchronous | Additive values (requests served, bytes sent) |
| **UpDownCounter** | Synchronous | Non-additive (active connections, queue depth) |
| **Histogram** | Synchronous | Distribution of values (request latencies, payload sizes) |
| **ObservableCounter** | Async (callback) | System metrics from APIs (CPU usage) |
| **ObservableUpDownCounter** | Async | Gauge-like additive metrics |
| **ObservableGauge** | Async | Point-in-time values (temperature, queue length) |

### Temporality

Metrics have two temporality modes:

- **Cumulative** (default): Each export contains all values since program start
- **Delta**: Each export contains only the delta since last export

Delta temporality is preferred for Prometheus remote write, reducing cardinality.

### Exemplars

Exemplars are ** exemplar traces** — actual span IDs attached to histogram buckets, linking metrics back to traces for drill-down:

```
HTTP request latency p99 = 450ms
  └── Exemplar: trace_id=abc123, span_id=def456, value=447ms
```

### Example: Metrics (Go)

```go
meter := otel.Meter("my-service")

counter, _ := meter.Int64Counter(
    "http_requests_total",
    metric.WithDescription("Total HTTP requests"),
)

histogram, _ := meter.Float64Histogram(
    "http_request_duration_ms",
    metric.WithDescription("HTTP request latency in ms"),
)

counter.Add(ctx, 1,
    metric.WithAttributes(
        attribute.String("method", "GET"),
        attribute.String("path", "/api/users"),
    ),
)

histogram.Record(ctx, 127.5,
    metric.WithAttributes(
        attribute.String("method", "GET"),
        attribute.String("path", "/api/users"),
    ),
)
```

## Logs

### Log Record Model

| Field | Description |
|-------|-------------|
| `timestamp` | When the event occurred |
| `severity` | Log level (trace, debug, info, warn, error) |
| `body` | Log message |
| `resource` | Attributes of the emitting entity |
| `attributes` | Structured key-value pairs |
| `trace_id`, `span_id` | If emitted within a traced context |

### Log Signal Integration

Logs in OTel are **first-class signals**. A `LogRecord` can carry `trace_id` and `span_id`, linking logs to traces.

```
Span[span_id=abc] ←─── trace context ───→ LogRecord[span_id=abc]
```

### Log Levels

OTel defines 5 severity levels: `TRACE` (5), `DEBUG` (10), `INFO` (20), `WARN` (30), `ERROR` (40).

## Signal Relationships

```
Trace (signal)
  └── Span (signal-specific data structure)
        ├── Links to other spans
        └── Contains events (logs within a trace)

Metric (signal)
  └── DataPoints (per-instrument type: counter, histogram, gauge)

Log (signal)
  └── LogRecord (timestamped, attributed, severity-rated)
```

## Key Design Decisions

1. **Spans are the primary observability primitive** — traces give you the causal graph
2. **Metrics are point-in-time observations** — sampled separately from traces
3. **Logs carry high-fidelity detail** — but lack built-in causal linkage (solved by trace_id correlation)
4. **The three signals are designed to be correlated** — trace context flows into all three

---
title: OTel Logs 101
description: Core constructs for logging — LoggerProvider, Logger, LogRecord, Bridge patterns, and trace correlation
tags:
  - opentelemetry
  - logs
  - beginner
date: 2025-01-01
draft: false
---

# OTel Logs 101

## How OTel Logs Fit In

Before OpenTelemetry, logs were **disconnected** from traces. You could see error logs and slow traces but they didn't link together.

OTel makes logs a **first-class signal** that can be correlated to traces via `trace_id` and `span_id`.

```
Span: handleOrders
  │
  ├── Event: "order received"          ← span event (log point in trace, NOT a separate log)
  │
  └── span.AddEvent("cache miss")

  Separate LogRecord:
  logger.Info("ORDER PLACED", "order_id", "ORD-001")
      └── LogRecord has trace_id=abc, span_id=xyz
          → SigNoz correlates: click log → jump to that span
```

## Two Flavors of OTel Logs

| What | Description |
|------|-------------|
| **Span Events** | A log entry **inside a span** — has `span_id` auto-attached. Good for in-process timing breadcrumbs. |
| **Standalone Log Records** | A full log entry **outside any span** — has `trace_id` if called within a traced context. Correlates to traces cross-service. |

Span events are the simplest starting point. Standalone logs with correlation are what you want for production.

## Core Constructs

### LoggerProvider

**What it is:** Top-level factory that creates `Logger` instances and manages log export. Holds the log processor pipeline.

- Created once at startup
- Must be set globally: `otel.SetLoggerProvider(lp)`

### Logger

**What it is:** The factory for creating log records. Scoped to a service or module.

```go
// Go
logger := lp.Logger("order-service")
```

```python
# Python
logger = logger_provider.get_logger("invoice-service")
```

### LogRecord

**What it is:** A single log entry. Fields:

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | time.Time | When the event occurred |
| `severity` | SeverityNumber | `Trace=5`, `Debug=10`, `Info=20`, `Warn=30`, `Error=40` |
| `body` | string | The log message |
| `attributes` | map[string]value | Structured key-value pairs |
| `trace_id` | uint64 | Trace ID (if called within a traced context) |
| `span_id` | uint64 | Span ID (if called within a span) |
| `resource` | Resource | Service metadata (service.name, etc.) |

### LogRecord vs Span Event

```go
// Span event — attached to the current span, no separate export
span.AddEvent("order validated")
span.AddEvent("cache miss", trace.WithAttributes(
    attribute.String("cache.key", "product:SKU-123"),
))

// LogRecord — standalone log, exported separately, can have trace correlation
logger.Info("ORDER PLACED",
    attribute.String("order_id", "ORD-001"),
    attribute.Float64("amount", 149.99),
)
```

## Severity Levels

OTel uses numeric severity levels (not strings):

| Level | Number | Name | When to use |
|-------|--------|------|-------------|
| `TRACE` | 5 | Finiest granularity | Debug at function-entry level |
| `DEBUG` | 10 | Debug info | Debugging verbose details |
| `INFO` | 20 | Informational | Normal operational events |
| `WARN` | 30 | Warning | Unexpected but handled situations |
| `ERROR` | 40 | Error | Partial failure, caught exceptions |

`body` is the human-readable message. Attributes are structured data.

## Bridging stdlib Logging

You likely have existing stdlib logging. Rather than replacing all `log.Println` calls, OTel provides **bridges** that forward stdlib logs into the OTel log pipeline.

### Go: Bridge stdlog to OTel

```go
import(
    "go.opentelemetry.io/otel/sdk/log"
    "go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
)

// Create the OTel log provider
logExporter, _ := otlploggrpc.New(ctx)

lp := log.NewLoggerProvider(
    log.WithResource(res),
    log.WithProcessor(log.NewBatchProcessorProcessor(logExporter)),
    // Or for sync: log.WithProcessor(log.NewSimpleProcessorProcessor(logExporter))
)
otel.SetLoggerProvider(lp)

// Bridge stdlog
// stdlib's log.Println / log.Printf calls go to OTel
import "log"

stdlog := log.New(
    otellog.NewHandler(
        lp.Logger("order-service").Handler(),
        otellog.WithFormatter(
            // format the stdlib log.Prefix + format string
        ),
    ),
    "",
    0,
)
stdlog.Printf("ORDER PLACED: order_id=%s", orderID)
```

Alternatively, use `otel/slog` (Go 1.21+ slog support):

```go
import "log/slog"

slogHandler := otelslog.NewOTELHandler(
    lp.Logger("order-service"),
    &otelslog.HandlerOptions{...},
)
logger := slog.New(slogHandler)
logger.Info("ORDER PLACED", "order_id", "ORD-001", "amount", 149.99)
```

### Python: Bridge logging to OTel

Python's `LoggingHandler` bridges stdlib `logging` to OTel logs:

```python
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.exporter.otlp.proto.grpc.log_exporter import OTLPLogExporter

log_exporter = OTLPLogExporter(
    endpoint=f"http://{otlp_endpoint}",
    insecure=True,
)

logger_provider = LoggerProvider(resource=resource)
logger_provider.add_log_processor(
    BatchSpanProcessor(log_exporter)  # same as traces
)

# Bridge Python stdlib logging
handler = LoggingHandler(logger_provider=logger_provider)
logging.getLogger("invoice-service").addHandler(handler)
logging.getLogger("invoice-service").setLevel(logging.INFO)

# Now all standard logging calls propagate to OTel
log = logging.getLogger("invoice-service")
log.info("ORDER PLACED: order_id=%s amount=%.2f", order_id, amount)
```

## Trace Correlation

The key power of OTel logs: `LogRecord` automatically carries `trace_id` and `span_id` if recorded **within a traced context**.

### Go: Logs with Trace Context

```go
// This logger.Info call is made inside a traced request
func handleOrders(w http.ResponseWriter, r *http.Request) {
    ctx := r.Context()
    _, span := tracer.Start(ctx, "handleOrders")
    defer span.End()
    span.SetAttributes(attribute.String("order.id", orderID))

    // Logger is created with a cached handler that captures ctx
    logger.Info("ORDER RECEIVED",
        attribute.String("order_id", orderID),
        attribute.Float64("amount", amount),
        otellog.WithContext(ctx),  // ← inject context so LogRecord has trace_id
    )
}

logger.Info("no context log — trace_id will be empty")
```

### Python: Logs with Trace Context

Python's `LoggingHandler` automatically captures the current trace context:

```python
# No explicit context needed — the handler extracts it from the current span
import logging

log = logging.getLogger("invoice-service")
log.info(f"ORDER PLACED: order_id={order_id} amount={amount}")
# → LogRecord contains trace_id, span_id from the current span context
```

## Span Events (The Simple Starting Point)

Span events are the **simplest** way to get logs into traces. They're just log points in time that appear on the span timeline.

### Go

```go
_, span := tracer.Start(ctx, "handleOrders")
defer span.End()

span.AddEvent("order received")
span.AddEvent("validation passed")
span.AddEvent("invoice created",
    trace.WithAttributes(
        attribute.String("invoice_id", "INV-001"),
    ),
)
```

In SigNoz: you'll see these as events on the span timeline, plus they appear in the Logs tab linked to that span.

### Python

```python
with tracer.start_as_current_span("generate_invoice") as span:
    span.add_event("invoice generation started")
    span.add_event("invoice created", attributes={"invoice_id": f"INV-{order_id}"})
```

## OTel Log Exporter

Just like traces and metrics, logs go through an OTLP exporter:

### Go

```go
import "go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"

logExporter, err := otlploggrpc.New(ctx)
if err != nil {
    return nil, err
}

lp := log.NewLoggerProvider(
    log.WithResource(res),
    log.WithProcessor(log.NewBatchProcessor(logExporter)),  // batches logs
)
```

### Python

```python
from opentelemetry.exporter.otlp.proto.grpc.log_exporter import OTLPLogExporter
from opentelemetry.sdk._logs import LoggerProvider, BatchLogRecordProcessor

log_exporter = OTLPLogExporter(
    endpoint=f"http://{otlp_endpoint}",
    insecure=True,
)

logger_provider = LoggerProvider(resource=resource)
logger_provider.add_log_processor(
    BatchLogRecordProcessor(log_exporter)
)
```

## Full Setup: Logs (Go)

```go
func initLogger(ctx context.Context, res *resource.Resource) (*log.LoggerProvider, error) {
    logExporter, err := otlploggrpc.New(ctx)
    if err != nil {
        return nil, err
    }

    lp := log.NewLoggerProvider(
        log.WithResource(res),
        log.WithProcessor(log.NewBatchProcessor(logExporter,
            log.WithNumWorkers(2),
        )),
    )

    otel.SetLoggerProvider(lp)

    return lp, nil
}

// Usage
logger := lp.Logger("order-service")
logger.Info("order processed",
    attribute.String("order_id", "ORD-001"),
    attribute.Float64("amount", 149.99),
)
```

## Full Setup: Logs (Python)

```python
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk.resources import Resource, SERVICE_NAME
from opentelemetry.exporter.otlp.proto.grpc.log_exporter import OTLPLogExporter
import logging

resource = Resource.create({SERVICE_NAME: "invoice-service"})

log_exporter = OTLPLogExporter(
    endpoint=f"http://{otlp_endpoint}",
    insecure=True,
)
logger_provider = LoggerProvider(resource=resource)

# Bridge stdlib logger
handler = LoggingHandler(logger_provider=logger_provider)
logging.getLogger("invoice-service").addHandler(handler)
logging.getLogger("invoice-service").setLevel(logging.INFO)

log = logging.getLogger("invoice-service")
log.info("invoice generated", extra={"order_id": order_id, "amount": amount})
```

## Key Distinction: Span Events vs Standalone Logs

| Aspect | Span Events | Standalone Logs |
|--------|-----------|----------------|
| Scope | Inside a single span | Any operation |
| Export | As part of span export | Via log exporter pipeline |
| Trace ID | Inherits from parent span | Inherits if within traced context |
| Span ID | Auto-attached | Not set unless inside a span |
| Appears in | Span timeline in SigNoz | Logs tab with trace correlation |
| Use for | Breadcrumbs (step markers) | Business events, errors, lifecycle events |
| Limitations | Cannot exist independently of a span | Need bridge/otel logger for OTel pipeline |

## Structured Logging

OTel attributes are **structured key-value pairs**. Unlike plain-text logging (`"order placed"`), structured logging lets you query and filter logs in SigNoz.

### Go: Structured

```go
logger.Info("order processed",
    attribute.String("order_id", orderID),
    attribute.Float64("amount", amount),
    attribute.String("customer", customerID),
    attribute.String("currency", "USD"),
    attribute.Int("line_items", len(items)),
)
```

### Python: Structured

```python
log.info("order processed", extra={
    "order_id": orderID,
    "amount": amount,
    "customer": customerID,
    "currency": "USD",
})
```

In SigNoz Logs tab, filter: `attributes.order_id = "ORD-001"` — works without parsing string content.

## Construct Hierarchy

```
LoggerProvider
  ├── Resource (service.name, version, environment)
  ├── LogProcessor (BatchLogRecordProcessor)
  │     └── OTLP Log Exporter → Collector
  │
  └── Logger ("order-service")
        ├── LogRecord (body="order placed", severity=INFO, trace_id=abc)
        │     ├── attributes: {order_id, amount, customer}
        │     └── resource: {service.name=order-service}
        │
        └── LogRecord (body="invoice called", severity=INFO)
              └── attributes: {invoice_id, duration_ms}
```

## Common Patterns

### Pattern 1: Error Logging with Trace Context

```go
logger.Error("failed to call invoice service",
    attribute.String("error", err.Error()),
    attribute.String("order_id", orderID),
    otellog.WithContext(ctx),  // ensures trace_id is in the log
)
```

### Pattern 2: Lifecycle Events in Order Processing

```go
ordersProcessed, _ := meter.Int64Counter("orders_processed_total")
_, span := tracer.Start(ctx, "processOrder")
defer span.End()

logger.Info("order started", attribute.String("order_id", orderID))

ordersProcessed.Add(ctx, 1)
logger.Info("order recorded in DB", attribute.String("order_id", orderID))

// Call invoice service
logger.Info("calling invoice service",
    attribute.String("target", "invoice-service"),
)
```

### Pattern 3: Structured Error with Attributes

```go
if err != nil {
    span.SetStatus(codes.Error, err.Error())
    span.SetAttributes(attribute.Bool("error", true))
    span.AddEvent("error", trace.WithAttributes(
        attribute.String("error.type", reflect.TypeOf(err).String()),
        attribute.String("error.message", err.Error()),
    ))
    logger.Error("request failed",
        attribute.String("error", err.Error()),
        attribute.String("path", r.URL.Path),
        attribute.Int("status_code", 500),
        otellog.WithContext(ctx),
    )
}
}

// LogExporter

The `LogExporter` serializes and sends completed log records to a backend.

### Go Exporters

| Exporter | Package | Config |
|----------|---------|--------|
| **OTLP** (gRPC) | `go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc` | `WithEndpoint()`, `WithInsecure()` |
| **OTLP** (HTTP) | `go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp` | `WithEndpoint()`, `WithInsecure()` |
| **Console** | `go.opentelemetry.io/otel/exporters/stdout/stdoutlog` | Dev/debug |
| **Loki** | `go.opentelemetry.io/otel/exporters/otlp/otlplog` + Collector | via Collector `loki` exporter |

```go
import (
    "go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
    "go.opentelemetry.io/otel/exporters/stdout/stdoutlog"
)

// OTLP gRPC (SigNoz, Grafana with Loki, etc.)
exporter, _ := otlploggrpc.New(ctx,
    otlploggrpc.WithEndpoint("localhost:4317"),
    otlploggrpc.WithInsecure(),
)

// Console (stdout debug)
exporter, _ := stdoutlog.New(stdoutlog.WithPrettyPrint())
```

### Python Exporters

| Exporter | Package | Config |
|----------|---------|--------|
| **OTLP** (gRPC/HTTP) | `opentelemetry-exporter-otlp` | `endpoint`, `insecure` |
| **Console** | `opentelemetry-sdk` (built-in) | Dev only |

```python
from opentelemetry.exporter.otlp.proto.grpc.log_exporter import OTLPLogExporter
from opentelemetry.sdk.log import LoggerProvider
from opentelemetry.sdk.log.export import BatchLogProcessor

# OTLP gRPC
exporter = OTLPLogExporter(
    endpoint="http://localhost:4317",
    insecure=True,
)

# BatchLogProcessor in LoggerProvider
logger_provider = LoggerProvider()
logger_provider.add_log_processor(BatchLogProcessor(exporter))
```

### LogProcessor (SDK-side)

Unlike traces which use `SpanProcessor`, logs use `LogProcessor`:

| Processor | Behavior | Use |
|-----------|----------|-----|
| `SimpleLogProcessor` | Exports synchronously on `log.Record()` | Dev, tests |
| `BatchLogProcessor` | Batches logs in queue, exports on schedule | **Production default** |

```go
import "go.opentelemetry.io/otel/sdk/log"

processor := log.NewBatchLogProcessor(
    logExporter,
    log.WithBatchSize(1024),
    log.WithBatchTimeout(5*time.Second),
)
```

```python
from opentelemetry.sdk.log import LoggerProvider
from opentelemetry.sdk.log.export import BatchLogProcessor, ConsoleLogExporter

exporter = ConsoleLogExporter()
processor = BatchLogProcessor(
    exporter,
    max_batch_size=1024,
    schedule_delay_seconds=5.0,
)
```

### LogExporter Architecture

```
Logger.Record()              // call in your code
  → LogProcessor.OnEmit()    // SDK notifies processor
      → BatchLogProcessor    // batches until size or timeout
          → LogExporter      // serializes (OTLP protobuf)
              → Network      // gRPC/HTTP to Collector
                  → Backend   // SigNoz, Loki, etc.
```

## Gotchas

- **Don't use `log.Println`** — plain `fmt.Println` and `log.Println` bypass the OTel log pipeline. Use the `Logger` from the OTel SDK, or the bridging approach.
- **Cardinality in log attributes** — unlike metrics, log attribute cardinality is not enforced. But storing high-cardinality values (request IDs, user IDs) as log attributes creates large log volumes.
- **Export interval** — logs batch and export on the same interval as metrics (typically 10s). Real-time log tailing uses batch processing with shorter intervals.
- **Dropped logs** — if memory pressure exceeds `memory_limiter` settings in the Collector, logs can be dropped before export.
- **Python LoggingHandler auto-correlation** — the handler extracts whatever the current span context is at the time of the `.info()` call. If it was called from a goroutine with no active span, `trace_id` will be empty.

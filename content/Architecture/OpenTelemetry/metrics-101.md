---
title: OTel Metrics 101
description: Core constructs for metrics — MeterProvider, Meter, Instruments (Counter, Histogram, Gauge), and patterns
tags:
  - opentelemetry
  - metrics
  - beginner
date: 2025-01-01
draft: false
---

# OTel Metrics 101

## The Three Instrument Types

OTel defines 6 instruments in 3 categories:

| Instrument | Sync/Async | Use | Example |
|------------|-------------|-----|---------|
| **Counter** | Sync | Counts that only go up | `requests_total`, `orders_processed_total` |
| **UpDownCounter** | Sync | Counts up AND down | `active_connections`, `queue_size` |
| **Histogram** | Sync | Distribution of values | `request_duration_ms`, `payload_size_bytes` |
| **ObservableCounter** | Async | Same as counter but from pulled data | CPU usage from `/proc/stat` |
| **ObservableUpDownCounter** | Async | Like UpDownCounter but pulled | `memory_used_bytes` |
| **ObservableGauge** | Async | Point-in-time value | `temperature`, `queue_depth` |

**Sync** instruments: your code calls `.Add()` or `.Record()` directly.
**Async** instruments: OTel SDK calls a callback function you provide, periodically.

## Core Mental Model

```
Your Code
   │
   │  meter.Int64Counter("requests_total").Add(ctx, 1, attributes...)
   │  meter.Float64Histogram("duration_ms").Record(ctx, 127.5, attributes...)
   │  meter.Int64ObservableGauge("queue_size").Observe(42)
   │
   ▼
┌──────────────────────────────────────────┐
│  MeterProvider                           │
│  ├── Meter ("order-service")            │
│  │     ├── Int64Counter                 │
│  │     │     └── instruments/aggregation│
│  │     ├── Float64Histogram             │
│  │     │     └── instruments/aggregation│
│  │     └── ...                          │
│  │                                       │
│  └── MetricReader ←── PeriodicExportingMetricReader ←── OTLP Exporter
└──────────────────────────────────────────┘
        │
        │ 10s export interval
        │
        ▼  OTLP
   ┌─────────────┐
   │  Collector   │
   └── SigNoz     │
```

## Core Constructs

### MeterProvider

**What it is:** Top-level factory that creates `Meter` instances and manages metric reading/exporting.

- Created once at startup
- Holds one or more `MetricReader`s (who decides when to read and export)
- Must be set globally: `otel.SetMeterProvider(mp)`

### Meter

**What it is:** The factory for creating instruments. Scoped to a library or service.

```go
// Go
meter := mp.Meter(
    "order-service",
    metric.WithInstrumentationVersion("1.0.0"),
)
```

```python
# Python
meter = metrics.get_meter("invoice-service")
meter = metrics.get_meter("invoice-service", "1.0.0")
```

### Instrument (Counter, Histogram, etc.)

**What it is:** The metric metric — the thing you interact with. Created once, stored as a variable, used everywhere.

```go
// Go — create once at startup
ordersCounter, err := meter.Int64Counter(
    "orders_processed_total",
    metric.WithDescription("Total orders placed"),
    metric.WithUnit("orders"),
)
// Use anywhere in your code
ordersCounter.Add(ctx, 1, metric.WithAttributes(attribute.String("status", "accepted")))
```

```python
# Python — create once, reuse
invoices_counter = meter.create_counter(
    name="invoices_generated_total",
    description="Total invoices generated",
    unit="invoices",
)
invoices_counter.add(1, {"customer_tier": "standard"})
```

## Counters in Depth

A **Counter** only increments (monotonically). Use for things that only go up.

### Monotonic vs Non-Monotonic

| Type | Behavior | Use Case |
|------|---------|---------|
| `Int64Counter` / `Float64Counter` | Monotonic (always increases) | `requests_total`, `bytes_sent` |
| `Int64UpDownCounter` / `Float64UpDownCounter` | Non-monotonic (up or down) | `active_connections`, `queue_size` |

### Go: Counter

```go
// Create at startup
counter, err := meter.Int64Counter(
    "http_requests_total",
    metric.WithDescription("Total HTTP requests received"),
    metric.WithUnit("requests"),
)

// Record — always Add() with a positive value for counters
counter.Add(ctx, 1,
    metric.WithAttributes(
        attribute.String("method", "GET"),
        attribute.String("path", "/orders"),
        attribute.String("status", "200"),
    ),
)

// For error tracking: increment with error dimension
counter.Add(ctx, 1,
    metric.WithAttributes(
        attribute.String("status", "500"),
    ),
)
```

### Python: Counter

```python
# Create at startup
requests_counter = meter.create_counter(
    name="http_requests_total",
    description="Total HTTP requests received",
    unit="requests",
)

# Record
requests_counter.add(1, {"method": "GET", "path": "/orders", "status": "200"})
requests_counter.add(1, {"method": "POST", "path": "/orders", "status": "201"})
```

## Histograms in Depth

A **Histogram** records a distribution of values — use for latencies, sizes, durations. OTel buckets values into predefined boundaries.

### Use for:

- `request_duration_ms` — how long requests take
- `request_size_bytes` — how big requests are
- `response_size_bytes` — how big responses are
- `invoice_amount_usd` — monetary values

### Go: Histogram

```go
// Create at startup
histogram, err := meter.Float64Histogram(
    "order_processing_duration_ms",
    metric.WithDescription("Order processing time in milliseconds"),
    metric.WithUnit("ms"),
    // Optional: explicit bucket boundaries
    metric.WithExplicitBucketBoundaries(
        5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0, 10000.0,
    ),
)

// Record a measurement
histogram.Record(ctx, 127.5,
    metric.WithAttributes(
        attribute.String("method", "POST"),
        attribute.String("path", "/orders"),
    ),
)
```

### Python: Histogram

```python
# Create at startup
duration_histogram = meter.create_histogram(
    name="order_processing_duration_ms",
    description="Order processing time in milliseconds",
    unit="ms",
)

# Record
duration_histogram.record(127.5, {"method": "POST", "path": "/orders"})
```

### Histogram Visualization in SigNoz

A histogram query for p95 latency of `/orders`:

```promql
histogram_quantile(0.95,
    rate(order_processing_duration_ms_bucket{path="/orders"}[5m])
)
```

## Observables (Async) in Depth

**Observables** let OTel SDK pull metrics from your code periodically. Your callback runs every export interval.

Use for: metrics where you can't call `.Add()` manually (system metrics, hardware sensors, JVM GC stats).

### Go: ObservableGauge

```go
var currentQueueSize int64

_, err := meter.Int64ObservableGauge(
    "queue_size",
    metric.WithDescription("Current number of items in queue"),
    metric.WithCallback(func(_ context.Context, o metric.Int64Observer) error {
        o.Observe(currentQueueSize)
        return nil
    }),
)
```

### Python: ObservableGauge

```python
import psutil

process = psutil.Process()

def memory_usage_callback(options):
    return psutil.Process().memory_info().rss

meter.create_observable_gauge(
    name="process_memory_bytes",
    description="Process memory usage in bytes",
    unit="bytes",
    callbacks=[memory_usage_callback],
)
```

## Attributes (Labels)

Attributes are key-value pairs that **classify** metric recordings. They create time series dimensions without pre-declaring them.

### Go

```go
counter.Add(ctx, 1,
    metric.WithAttributes(
        attribute.String("method", "POST"),           // string
        attribute.Int("status_code", 201),           // int
        attribute.Float("cache_hit_ratio", 0.892),   // float
        attribute.Bool("is_cached", true),           // bool
    ),
)
```

### Python

```python
counter.add(1, {
    "method": "POST",
    "status_code": 201,
    "is_cached": True,
})
```

### Cardinality Warning

Every unique combination of attribute values creates a **new time series** in your backend.

```
BAD: attribute.String("request_id", unique_id)     ← every request = new time series
OK:  attribute.String("customer_tier", "premium")  ← few values = bounded cardinality
```

Rule: attribute values should have **low cardinality** (≤ 100 unique values).

## Metric Temporality

**Temporality** determines whether metrics are exported as cumulative (total since start) or delta (change since last export).

| Temporality | What it means | Use case |
|-------------|---------------|---------|
| **Cumulative** (default) | Each export includes all values since app start | General use |
| **Delta** | Each export is only the delta since last export | Prometheus remote write |

### Delta Temporality (Go)

```go
import "go.opentelemetry.io/otel/sdk/metric"

reader := metric.NewPeriodicBatchReader(
    metricExporter,
    metric.WithInterval(10 * time.Second),
    metric.WithTemporalitySelector(func(metricName string, kind metric.InstrumentKind) metric.Temporality {
        return metric.DeltaTemporality
    }),
)
```

## Exemplars

Exemplars are **trace references embedded in histogram buckets**: actual `trace_id` and `span_id` attached to a histogram recording. Enables drill-down from metric → trace.

```
order_processing_duration_ms p95 = 450ms
  └─ Exemplar: trace_id=abc123, span_id=def456, value=447ms
      ↓ click in SigNoz → jump to that specific trace
```

Exemplars are automatic when your app has a active trace context (the `.Record()` call runs inside a traced request).

## Full Setup: Metrics

### Go

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
    "go.opentelemetry.io/otel/metric"
    "go.opentelemetry.io/otel/sdk/metric"
    "go.opentelemetry.io/otel/sdk/resource"
)

func initMeter(ctx context.Context) (func(), error) {
    exporter, err := otlpmetricgrpc.New(ctx)
    if err != nil {
        return nil, err
    }

    res, err := resource.New(ctx,
        resource.WithAttributes(
            attribute.String("service.name", "order-service"),
        ),
    )
    if err != nil {
        return nil, err
    }

    reader := metric.NewPeriodicBatchReader(exporter,
        metric.WithInterval(10 * time.Second),
    )

    mp := metric.NewMeterProvider(
        metric.WithResource(res),
        metric.WithReader(reader),
    )

    otel.SetMeterProvider(mp)

    return func() { mp.Shutdown(ctx) }, nil
}
```

### Python

```python
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter

def init_meter():
    exporter = OTLPMetricExporter(
        endpoint=os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"],
        insecure=True,
    )

    reader = PeriodicExportingMetricReader(
        exporter,
        export_interval_millis=10000,
    )

    meter_provider = MeterProvider(metric_readers=[reader])
    metrics.set_meter_provider(meter_provider)

    return metrics.get_meter("invoice-service")
```

## Common Metric Patterns

### Pattern 1: Request Counter with Status

```go
counter.Add(ctx, 1,
    metric.WithAttributes(
        attribute.String("method", method),
        attribute.String("path", path),
        attribute.Int("status_code", statusCode),
    ),
)
```

In SigNoz: `sum by (status_code) (rate(orders_processed_total[5m]))`

### Pattern 2: Request Duration Histogram

```go
start := time.Now()
// ... handle request ...
histogram.Record(ctx, float64(time.Since(start).Milliseconds()),
    metric.WithAttributes(
        attribute.String("method", r.Method),
        attribute.String("path", r.URL.Path),
        attribute.Int("status_code", statusCode),
    ),
)
```

In SigNoz: `histogram_quantile(0.95, rate(order_processing_duration_ms_bucket[5m]))`

### Pattern 3: Active Connection Gauge

```go
var activeConnections int64

gauge, err := meter.Int64ObservableGauge(
    "active_connections",
    metric.WithDescription("Currently active WebSocket connections"),
    metric.WithUnit("connections"),
    metric.WithCallback(func(_ context.Context, o metric.Int64Observer) error {
        o.Observe(activeConnections)
        return nil
    }),
)
```

### Pattern 4: Business KPI Counter

```go
// Track orders by payment method
ordersCounter.Add(ctx, 1,
    metric.WithAttributes(
        attribute.String("payment_method", "credit_card"),
        attribute.String("currency", "USD"),
        attribute.String("customer_tier", "premium"),
    ),
)

ordersCounter.Add(ctx, 1,
    metric.WithAttributes(
        attribute.String("payment_method", "crypto"),
        attribute.String("currency", "BTC"),
        attribute.String("customer_tier", "standard"),
    ),
)
```

## Instrument Creation Summary

```go
// GO — All instruments
counter,     _ := meter.Int64Counter(        "name", metric.WithUnit("unit"))
upDownCnt,   _ := meter.Int64UpDownCounter(  "name", metric.WithUnit("unit"))
histogram,   _ := meter.Float64Histogram(    "name", metric.WithUnit("unit"))
obsCounter,  _ := meter.Int64ObservableCounter(  "name", metric.WithUnit("unit"), metric.WithCallback(fn))
obsUpDown,   _ := meter.Int64ObservableUpDownCounter("name", metric.WithUnit("unit"), metric.WithCallback(fn))
obsGauge,    _ := meter.Int64ObservableGauge(   "name", metric.WithUnit("unit"), metric.WithCallback(fn))
```

```python
# Python — All instruments
counter         = meter.create_counter(          "name", unit="unit")
up_down_counter = meter.create_up_down_counter(  "name", unit="unit")
histogram       = meter.create_histogram(         "name", unit="unit")
obs_counter     = meter.create_observable_counter("name", unit="unit", callbacks=[fn])
obs_updown      = meter.create_observable_up_down_counter("name", unit="unit", callbacks=[fn])
obs_gauge       = meter.create_observable_gauge( "name", unit="unit", callbacks=[fn])
```

Metrics are aggregated by instruments and read by a `MetricReader`. A `View` lets you customize aggregation and attribute handling.

## MetricReader

The `MetricReader` controls **when** metrics are read and exported. Different readers implement different push/pull patterns.

### Reader Types

| Reader | Pattern | Use Case |
|--------|---------|----------|
| `PeriodicExportingMetricReader` | **Push** — SDK pushes every interval | Most backends (SigNoz, Grafana, etc.) |
| `PeriodicBatchMetricReader` | **Push** — batches, then pushes | High throughput, reduced export calls |
| `PrometheusRemoteWriteReader` | **Push** — sends to Prometheus remote write endpoint | Prometheus, Grafana Mimir |
| `MetricReader` (base) | Custom | Building custom exporters |

### PeriodicExportingMetricReader (Go)

| Option | Default | Description |
|--------|---------|-------------|
| `WithInterval(d)` | 10s | How often to read and export |
| `WithTemporalitySelector(fn)` | Cumulative | Delta or Cumulative per instrument |

```go
import "go.opentelemetry.io/otel/sdk/metric"

reader := metric.NewPeriodicExportingMetricReader(
    metricExporter,
    metric.WithInterval(10*time.Second),
)
```

### PeriodicExportingMetricReader (Python)

```python
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader

reader = PeriodicExportingMetricReader(
    metric_exporter,
    export_interval_millis=10000,  # 10s default
)
```

### MetricReader in MeterProvider (Go)

```go
mp := metric.NewMeterProvider(
    metric.WithResource(res),
    metric.WithReader(  // one reader per MeterProvider
        metric.NewPeriodicExportingMetricReader(exporter,
            metric.WithInterval(30*time.Second),
        ),
    ),
)
```

### Multiple Readers (Go)

A MeterProvider can have multiple readers:

```go
mp := metric.NewMeterProvider(
    metric.WithResource(res),
    metric.WithReader(periodicReader),      // → SigNoz (OTLP)
    metric.WithReader(prometheusReader),     // → Prometheus scrape endpoint
)
```

This lets a single app export metrics to multiple backends simultaneously.

## MetricExporter

The `MetricExporter` serializes and sends aggregated metric data.

### Go Exporters

| Exporter | Package | Config |
|----------|---------|--------|
| **OTLP** (gRPC) | `go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc` | `WithEndpoint()`, `WithInsecure()` |
| **OTLP** (HTTP) | `go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp` | `WithEndpoint()`, `WithInsecure()` |
| **Prometheus** | `go.opentelemetry.io/otel/exporters/prometheus` | Serves `:2222`/metrics for Prometheus pull |
| **Console** | `go.opentelemetry.io/otel/exporters/stdout/stdoutmetric` | Dev/debug |

```go
import (
    "go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
    "go.opentelemetry.io/otel/exporters/prometheus"
    "go.opentelemetry.io/otel/exporters/stdout/stdoutmetric"
)

// OTLP gRPC (SigNoz, Grafana, etc.)
exporter, _ := otlpmetricgrpc.New(ctx,
    otlpmetricgrpc.WithEndpoint("localhost:4317"),
    otlpmetricgrpc.WithInsecure(),
)

// Prometheus (for Prometheus pull model)
registry := prometheus.New()  // creates a prometheus.Registry
exporter := prometheus.NewExporter(prometheus.WithRegistry(registry))
// Prometheus scrapes http://localhost:2222/metrics

// Console (stdout debug)
exporter, _ := stdoutmetric.New(stdoutmetric.WithPrettyPrint())
```

### Python Exporters

| Exporter | Package | Config |
|----------|---------|--------|
| **OTLP** (gRPC/HTTP) | `opentelemetry-exporter-otlp` | `endpoint`, `insecure` |
| **Prometheus** | `opentelemetry-exporter-prometheus` | Serves `:2222`/metrics |
| **Console** | `opentelemetry-sdk` (built-in) | Dev only |

```python
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.prometheus import PrometheusMetricReader

# OTLP gRPC
exporter = OTLPMetricExporter(
    endpoint="http://localhost:4317",
    insecure=True,
)

# Prometheus (Prometheus pulls from :2222/metrics)
from prometheus_client import start_http_server
exporter = OTLPMetricExporter()  # Prometheus reader handles /metrics
```

## View

A `View` controls **how** instruments are aggregated and which attributes are retained. Views are the customization layer between instruments and output.

Use views to:
- Rename metric instruments (e.g., `http_server_requests` → `http_requests`)
- Drop high-cardinality attributes (e.g., `user_id`, `request_id`) to reduce cardinality
- Configure histogram bucket boundaries
- Copy an instrument to multiple destinations with different aggregation

### Go: View to Drop High-Cardinality Attributes

```go
import "go.opentelemetry.io/otel/sdk/metric"

view := metric.NewView(
    metric.Instrument{
        Name: "orders_processed_total",  // match instrument name
    },
    metric.Stream{
        Name: "orders_processed_total",  // exported name
        Aggregation: metric.AggregationSum{},
        AttributeFilter: attributeFilter{
            // drop attributes with high cardinality: user_id, request_id
            Allowed: []string{"method", "status_code", "path"},
        },
    },
)

mp := metric.NewMeterProvider(
    metric.WithResource(res),
    metric.WithReader(reader),
    metric.WithView(view),
)
```

### Go: View to Configure Histogram Buckets

```go
view := metric.NewView(
    metric.Instrument{Name: "order_duration_ms"},
    metric.Stream{
        Name: "order_duration_ms",
        Aggregation: metric.AggregationHistogram{
            Boundaries: []float64{5, 10, 25, 50, 100, 250, 500, 1000},  // custom buckets
        },
    },
)
```

### Python: View

```python
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.view import View, InstrumentSelector, Stream

# View to rename and drop attributes
view = View(
    instrument_selector=InstrumentSelector(instrument_name="orders_processed_total"),
    stream=Stream(name="orders_processed", attribute_select=["method", "status_code"]),
)

mp = MeterProvider(
    metric_readers=[reader],
    views=[view],
)
```

## Construct Hierarchy

```
MeterProvider
  ├── Resource (service.name, version, etc.)
  ├── MetricReader (PeriodicExportingMetricReader)
  │     └── OTLP Exporter → Collector
  │
  └── Meter ("order-service")
        ├── Int64Counter ("orders_processed_total")
        │     └── Aggregator: Sum (monotonic)
        │
        ├── Float64Histogram ("order_duration_ms")
        │     └── Aggregator: Histogram (with explicit bucket boundaries)
        │
        └── Int64ObservableGauge ("active_connections")
              └── Aggregator: LastValue
```

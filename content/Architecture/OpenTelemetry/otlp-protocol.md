---
title: OTLP Protocol
description: OTLP gRPC and HTTP transport, delivery semantics, compression
tags:
  - opentelemetry
  - otlp
  - protocol
date: 2025-01-01
draft: false
---

# OTLP Protocol (OpenTelemetry Line Protocol)

OTLP is the **native wire protocol** for OpenTelemetry. It defines how telemetry data is encoded and transported between SDKs, the Collector, and backends.

## Protocol Versions

| Version | Status |
|---------|--------|
| OTLP v0.5 | Deprecated (gRPC only, proto3) |
| OTLP v0.7 | Stable (HTTP added, proto3) |
| OTLP v0.9 | Stable (logs signal added) |
| OTLP v0.11 | Stable (exemplars, metric metadata) |
| OTLP v0.12 | Stable (delta temporality for metrics) |
| OTLP v0.19 | Stable |
| OTLP v1.0 | Current stable (traces, metrics, logs) |

## Transport

| Transport | Port | Use |
|-----------|------|-----|
| **gRPC** | 4317 (default) | Production — binary, streaming, bidirectional |
| **HTTP/JSON** | 4318 (default) | Browser, environments without gRPC |
| **HTTP/Protobuf** | 4318 | Same as JSON but binary-encoded |

### gRPC (Production Recommended)

```
Client → Collector
  └── Uses Protocol Buffers (proto3) over HTTP/2
      Supports client-side streaming (batch exports)
```

### HTTP (Environments with Restrictions)

```
Client → Collector
  └── Uses JSON (human-readable) or protobuf (binary) over HTTP/1.1 or HTTP/2
      Single-request, no streaming
```

## Protobuf Schemas

OTLP uses Protocol Buffers v3. Three main proto files:

| Proto | Signal | Defines |
|-------|--------|---------|
| `opentelemetry/proto/trace/v1/trace.proto` | Traces | `TracesData` → `ResourceSpans` → `ScopeSpans` → `Span` |
| `opentelemetry/proto/metrics/v1/metrics.proto` | Metrics | `MetricsData` → `ResourceMetrics` → `ScopeMetrics` → `Metric` |
| `opentelemetry/proto/logs/v1/logs.proto` | Logs | `LogsData` → `ResourceLogs` → `ScopeLogs` → `LogRecord` |

### Proto Hierarchy

```
TracesData (top-level)
└── ResourceSpans (repeated)
    ├── resource (attributes)
    └── ScopeSpans (repeated)
        ├── scope (name, version)
        └── spans (repeated)
            ├── name
            ├── trace_id, span_id, parent_span_id
            ├── attributes, events, links
            └── status
```

#### Resource

The **Resource** represents the entity producing telemetry — typically your service, container, or Kubernetes pod.

| Field | Set by | Examples |
|-------|--------|---------|
| `service.name` | You / OTel SDK | `"order-service"` |
| `service.namespace` | You | `"payments"` |
| `k8s.pod.name` | Collector `k8sattributes` processor | `"order-service-7d9f4b8f9-xk2p4"` |
| `cloud.account.id` | Collector or env | `"123456789"` |

#### Instrumentation Scope

The **Instrumentation Scope** is the middle layer — it identifies **which library or module** created the telemetry.

| Field | What it is | Examples |
|-------|-----------|---------|
| `scope.name` | Library or module name | `"order-service"`, `"otelhttp"`, `"github.com/myapp/dbclient"` |
| `scope.version` | Version of that library | `"1.2.3"` — can be empty |
| `scope.attributes` | Optional KV pairs | Rarely used |

```
Service (Resource: service.name="order-service")
    │
    ├── Scope: "order-service" (version="1.0.0")
    │     └── spans[]  ← your business logic spans
    │
    ├── Scope: "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp" (version="0.46.0")
    │     └── spans[]  ← spans from auto-instrumented HTTP (wrapping your HTTP mux)
    │
    └── Scope: "github.com/myapp/dbclient" (version="2.1.0")
          └── spans[]  ← spans from your database wrapper
```

**Why it exists — before vs after:**

```
BAD (pre-OTel): All spans mixed together — filtering required parsing span attributes
  span.attributes["instrumentation_library"] = "my-db-client"

GOOD (OTel): Scope is structural, not an attribute
  The library name is in the proto message itself under ScopeSpans.scope.name
```

This enables:
- **Collector filtering without parsing body content** — filter by `scope.name` in routing rules
- **Backend grouping** — click a scope in SigNoz and see only that library's spans
- **Multiple teams** — each team owns a library → each library has its own Scope

**Scope in code — you create one implicitly:**

```go
// The string becomes the scope name on all spans this tracer creates
tracer := tp.Tracer("order-service")
//  → span.scope.name = "order-service"

// Auto-instrumentation sets its own scope automatically
otelHandler := otelhttp.NewHandler(http.DefaultServeMux, "order-service")
//  → HTTP library spans have scope.name = "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
```

**Scope vs Resource:**

| Aspect | Resource | Instrumentation Scope |
|--------|----------|----------------------|
| Represents | The entity running (service, container, host) | The code module producing the data |
| Scope | One per service/app | One per instrumented library |
| Set by | Infrastructure (K8s, env vars) | Developer (tracer name) |
| Examples | `service.name="order-service"`, `k8s.pod.name` | `"otelhttp"`, `"my-db-lib"`, `"order-service"` |

**Scope in proto:**

```protobuf
message ScopeSpans {
  opentelemetry.common.v1.InstrumentationScope scope = 1;
  repeated Span spans = 2;
}

message InstrumentationScope {
  string name = 1;
  string version = 2;
  repeated opentelemetry.common.v1.KeyValue attributes = 3;
}
```

## Endpoints

### Default Collector Receiver Ports

| Endpoint | Protocol | Signals |
|----------|----------|---------|
| `0.0.0.0:4317` | gRPC | traces, metrics, logs |
| `0.0.0.0:4318` | HTTP | traces, metrics, logs |
| `0.0.0.0:4319` | gRPC (older) | metrics |
| `0.0.0.0:55681` | HTTP (older) | legacy |

### Typical Endpoint Layout

```
POST /v1/traces      — trace signal
POST /v1/metrics     — metric signal
POST /v1/logs        — log signal
GET  /health         — health check (Collector extension)
GET  /zpages/tracez  — debug pages (Collector extension)
```

## Delivery Semantics

OTLP provides **at-least-once delivery**:

- Client retries on failure with **exponential backoff**
- Backend acknowledges with `Success` or `Failure`
- If no acknowledgment within timeout, client retries

| Guarantee | Meaning |
|-----------|---------|
| **At-least-once** | Data may be sent multiple times on retry; backends must be idempotent |
| **No exactly-once** | OTel does not provide deduplication |
| **No ordering** | Out-of-order spans/metrics are accepted |

### Retry Configuration

```yaml
exporters:
  otlp:
    endpoint: http://backend:4317
    retry_on_failure:
      enabled: true
      initial_interval: 1s
      max_interval: 30s
      max_elapsed_time: 300s
      multiplier: 1.5
    timeout: 10s
```

## Compression

| Compression | Algorithm | Benefit |
|-------------|-----------|---------|
| `gzip` | DEFLATE | Good compression, moderate CPU |
| `snappy` | Snappy | Fast, moderate compression |
| `zstd` | Zstandard | Best compression, more CPU |
| None | — | Lowest latency, highest bandwidth |

### Configuring Compression

```yaml
exporters:
  otlp:
    endpoint: http://collector:4317
    compression: gzip
```

## TLS

OTLP supports mTLS for secure transport:

```yaml
exporters:
  otlp:
    endpoint: collector.internal:4317
    tls:
      insecure: false           # Required for TLS
      cert_file: /certs/cert.pem
      key_file: /certs/key.pem
      ca_file: /certs/ca.pem
      min_version: 1.2
      max_version: 1.3
```

## Auth

Collector can authenticate exports via:

### Headers (Simple)

```yaml
exporters:
  otlp:
    endpoint: http://collector:4317
    headers:
      authorization: "Bearer ${API_KEY}"
      x-custom-header: "value"
```

### OIDC (Enterprise)

```yaml
extensions:
  oidcauth:
    issuer: https://auth.example.com
    audience: otel-collector

exporters:
  otlp:
    endpoint: collector.internal:4317
    auth:
      authenticator: oidcauth
```

## Client Configuration

### Go Client

```go
import "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"

exporter, err := otlptracegrpc.New(context.Background(),
    otlptracegrpc.WithEndpoint("collector:4317"),
    otlptracegrpc.WithDialOptions(
        grpc.WithTransportCredentials(insecure.NewCredentials()), // Use TLS in prod
    ),
    otlptracegrpc.WithCompressor("gzip"),
)
```

### Python Client

```python
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

exporter = OTLPSpanExporter(
    endpoint="collector:4317",
    insecure=True,  # Use True for localhost, configure TLS in prod
)
```

### Environment Variables

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://collector:4317
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_CERTIFICATE=/certs/cert.pem
export OTEL_EXPORTER_OTLP_HEADERS="x-api-key=${API_KEY}"
export OTEL_EXPORTER_OTLP_COMPRESSION=gzip
export OTEL_EXPORTER_OTLP_TIMEOUT=10000  # milliseconds
```

## Version Negotiation

OTLP clients and servers negotiate protocol version via proto package name:

```
type URL    = "type.googleapis.com/opentelemetry.proto.collector.trace.v1.TraceService/Export"
```

Mismatched versions return `UNIMPLEMENTED` gRPC error or HTTP 400.

## Why OTLP?

| Before OTLP | After OTLP |
|-------------|------------|
| Jaeger agent → Jaeger Collector | App → OTel SDK → OTel Collector → Any backend |
| StatsD → DogStatsD → Datadog | App → OTel SDK → OTel Collector → Datadog |
| Custom log shipper per vendor | App → OTel SDK → OTel Collector → Any backend |
| Zipkin client → Zipkin backend | App → OTel SDK → OTel Collector → Any backend |

OTLP standardizes the transport so **instrumentation is decoupled from backend**. Change backends by updating Collector config, not application code.

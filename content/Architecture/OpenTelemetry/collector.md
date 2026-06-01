---
title: OpenTelemetry Collector
description: Collector architecture, Receivers-Processors-Exporters pipeline, deployment modes
tags:
  - opentelemetry
  - collector
date: 2025-01-01
draft: false
---

# OpenTelemetry Collector

The OTel Collector is a **vendor-neutral proxy** that receives, processes, and exports telemetry. It sits between your application and your observability backends.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Collector                            │
│                                                             │
│  ┌──────────┐    ┌────────────┐    ┌───────────┐           │
│  │ Receivers│───▶│ Processors │───▶│ Exporters │           │
│  └──────────┘    └────────────┘    └───────────┘           │
│        │               │                                   │
│        ▼               ▼                                   │
│  ┌──────────┐    ┌────────────┐                           │
│  │ Extensions│   │ Connectors │                           │
│  └──────────┘    └────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

## Pipeline

### Receivers

Receivers ingest telemetry in vendor-specific formats:

| Receiver | Protocol | Signal |
|----------|----------|--------|
| `otlp` | gRPC/HTTP | traces, metrics, logs |
| `jaeger` | Thrift/gRPC | traces |
| `zipkin` | HTTP | traces |
| `prometheus` | HTTP pull | metrics |
| `prometheusremotewrite` | HTTP remote write | metrics |
| `hostmetrics` | System calls | metrics |
| `kafka` | Kafka | traces, metrics, logs |
| `filelog` | File tail | logs |
| `syslog` | Syslog | logs |

### Processors

Processors act on data mid-pipeline:

| Processor | Function |
|-----------|---------|
| `batch` | Batches spans/metrics/logs to reduce export calls |
| `memory_limiter` | Prevents OOM by rejecting data when memory is high |
| `transform` | Modify attributes using OTTL (OpenTelemetry Transformation Language) |
| `filter` | Filter spans/metrics/logs by criteria |
| `resource` | Add/modify resource attributes |
| `attributes` | Add/modify span/log attributes |
| `probabilistic_sampler` | Sample a % of traces |
| `tail_sampling` | Sample based on policies (error, latency, etc.) |
| `routing` | Route to different exporters based on criteria |
| `k8sattributes` | Inject Kubernetes metadata (pod name, namespace, etc.) |

### Exporters

Exporters send data to backends:

| Exporter | Backend |
|----------|---------|
| `otlp` | Any OTel-native backend |
| `otlphttp` | Any backend via HTTP |
| `jaeger` | Jaeger |
| `zipkin` | Zipkin |
| `prometheus` | Prometheus (pull or remote_write) |
| `prometheusremotewrite` | Prometheus via remote write |
| `loki` | Grafana Loki (logs) |
| `datadog` | Datadog |
| `awsxray` | AWS X-Ray |
| `awsemf` | AWS CloudWatch EMF (metrics) |
| `azuremonitorexporter` | Azure Monitor |
| `googlecloudmonitoring` | GCP Cloud Monitoring |
| `logging` | Stdout (debug) |
| `file` | File (debug) |

## Minimal Collector Config

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024
  memory_limiter:
    limit_mib: 512
    check_interval: 1s

exporters:
  otlp:
    endpoint: http://tempo:4317
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, memory_limiter]
      exporters: [otlp]
    metrics:
      receivers: [otlp]
      processors: [batch, memory_limiter]
      exporters: [otlp]
    logs:
      receivers: [otlp]
      processors: [batch, memory_limiter]
      exporters: [otlp]
```

## Deployment Modes

### Agent Mode (Sidecar / DaemonSet)

Collector runs as a **sidecar** or **daemonset** on each node. Applications send telemetry locally.

```
Pod → OTel Agent (localhost) → OTel Gateway → Backend
```

Use when: You want to reduce backend connections from applications, add local batching/compression.

### Gateway Mode (Central)

A single Collector **Deployment** acts as a central aggregation point.

```
App → OTel Agent → OTel Gateway → Backend
App → OTel Agent ──────────────────▶
App → OTel Agent ──────────────────▶
```

Use when: You want a single choke point for routing, filtering, sampling.

### Standalone

Collector runs as a single process doing everything (receivers + exporters directly).

Use when: Small deployments, local development.

## Extensions

Extensions are non-pipeline components (health checks, monitoring, etc.):

| Extension | Purpose |
|-----------|---------|
| `zpages` | In-process debug pages (trace stats, span names) |
| `health_check` | HTTP health endpoint at `/` |
| `pprof` | Go profiling endpoint at `localhost:1777` |
| `memory_ballast` | Allocates virtual memory to reduce GC pressure |
| `oidcauth` | Authenticate exports using OIDC tokens |

```yaml
extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  zpages:
    endpoint: 0.0.0.0:55679
  memory_ballast:
    size_mib: 64

service:
  extensions: [health_check, zpages, memory_ballast]
  pipelines:
    # ...
```

## Processors in Detail

### Batch Processor

Batches data to reduce HTTP/gRPC call overhead:

```yaml
processors:
  batch:
    timeout: 5s              # Flush after N seconds
    send_batch_size: 8192    # Or after N items
    send_batch_max_size: 8192  # Max batch size (vs send_batch_size which is target)
```

### Memory Limiter

Protects against OOM when backend is slow/unavailable:

```yaml
processors:
  memory_limiter:
    limit_mib: 512           # Hard limit
    spike_limit_mib: 128     # Spike allowance
    check_interval: 1s
```

### Tail Sampling

Sample traces **after collection** based on policies:

```yaml
processors:
  tail_sampling:
    decision_wait: 10s
    num_traces: 100000
    expected_new_traces_per_sec: 100
    policies:
      - name: errors-policy
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: slow-traces-policy
        type: latency
        latency: {threshold_ms: 1000}
      - name: probabilistic-policy
        type: probabilistic
        probabilistic: {sampling_percentage: 10}
      - name: latency-slo-policy
        type: and
        and: {and_policy_requirements:
          - policy: latency
            latency: {threshold_ms: 100}
          - policy: status_code
            status_code: {status_codes: [OK]}
        }
```

### K8s Attributes Processor

Adds Kubernetes metadata to spans:

```yaml
processors:
  k8sattributes:
    extract:
      metadata:
        - k8s.namespace.name
        - k8s.deployment.name
        - k8s.pod.name
        - k8s.pod.uid
        - k8s.pod.start_time
        - k8s.container.name
        - k8s.container.restart_count
    filter:
      node: ".*worker.*"   # Only pods on worker nodes
```

## Connectors (Beta)

Connectors join two pipelines — they act as both an exporter (for one signal) and receiver (for another), enabling **signal-to-signal routing**:

```yaml
connectors:
  spanmetrics:
    metrics_exporter: prometheus

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp, spanmetrics]  # spanmetrics connector
    metrics:
      receivers: [spanmetrics]         # receives from spanmetrics connector
      exporters: [prometheus]
```

This creates **RED metrics** (Request rate, Error rate, Duration) from traces automatically.

## Resource Attributes in Collector

The `resource` processor adds/overrides resource attributes:

```yaml
processors:
  resource:
    attributes:
      - action: upsert
        key: cloud.region
        value: us-east-1
      - action: upsert
        key: environment
        from_attribute: ENV
        # ENV env var becomes "environment" attribute
```

## Performance Notes

- **Batch processor** is essential — reduces export overhead 10-100x
- **Memory limiter** should always be on in production
- **Ballast** (extension) reduces Go GC pauses but Collector v0.91+ recommends **NOT using ballast** (changed memory management)
- **Workers** on exporters enable parallel sends:
  ```yaml
  exporters:
    otlp:
      workers: 10
  ```

## Collector Binary

The Collector has two binaries:

| Binary | Use |
|--------|-----|
| `otelcol` | Standard binary (import from `otel-contrib`) |
| `otelcol-contrib` | Community-contrib receivers/exporters |

For Kubernetes, use the **OpenTelemetry Operator** or the **Helm chart**:

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm install otel-collector open-telemetry/opentelemetry-collector \
  --set mode=daemonset \
  --set config.receivers.otlp.protocols.grpc.endpoint=0.0.0.0:4317 \
  --set config.receivers.otlp.protocols.http.endpoint=0.0.0.0:4318
```

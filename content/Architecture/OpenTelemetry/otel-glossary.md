---
title: OTel API vs SDK vs Protocol vs Exporter vs Collector
description: Clear distinction between OTel's core components
tags:
  - opentelemetry
  - glossary
date: 2025-01-01
draft: false
---

# OTel: API vs SDK vs Protocol vs Exporter vs Collector

```
Your Code
    │
    │                          ┌──────────────────────────┐
    ▼                          │     OTel Protocol        │
┌──────────────┐               │  (OTLP — wire format)     │
│  OTel API    │               │  gRPC:4317 / HTTP:4318   │
│  (interfaces)│               │  protobuf-encoded         │
└──────┬───────┘               └──────────────┬───────────┘
       │ implements                                 │
       ▼                                          │
┌──────────────┐               ┌──────────────┐  │
│  OTel SDK    │──────────────▶│   Exporter   │◀─┘
│  (impl)      │               │  (OTLP,       │
│  + sampling  │               │   Jaeger,     │
│  + batching   │               │   Prometheus) │
└──────┬───────┘               └──────┬───────┘
       │ sends                      │
       ▼ sends               ┌──────▼────────┐
┌──────────────┐            │    Collector   │
│   Exporter   │───────────▶ │  (standalone)  │
│  (in-process)│            │  Receivers →    │
└──────────────┘            │  Processors →   │
                            │  Exporters       │
                            └──────────────────┘
```

## Component Definitions

| Component | What it is | Lives in |
|-----------|-----------|----------|
| **API** | Interfaces only — `Tracer`, `Meter`, `Logger`. No-op by default. You write to this. | Your app code |
| **SDK** | Implementation of the API. Adds sampling, batching, resource attributes. When you call `NewTracerProvider()`, that's the SDK. | Your app (dependency) |
| **Protocol** (OTLP) | How data is encoded on the wire — protobuf/JSON over gRPC/HTTP. The wire format spec. | Between SDK ↔ Collector ↔ Backend |
| **Exporter** | Sends SDK data somewhere. Can be inside your app (SDK-side) or inside the Collector. | SDK process OR Collector |
| **Collector** | Standalone process. Receives → Processes → Exports. Does not run in your app process. | Separate deployment (K8s daemonset/deployment) |

## Key Distinctions

**API ≠ SDK**: You can depend on the API only (for testing, or if you don't want OTel code in your app). The SDK implements the API at runtime.

**Exporter vs Collector**: An exporter is a component (inside SDK or Collector). A Collector is the full standalone process that wires multiple exporters together with processors.

**Protocol is orthogonal**: Whether you use SDK directly → backend, or SDK → Collector → backend, the protocol between components is OTLP (or legacy Jaeger/Zipkin formats).

## Typical Flows

```
Simple:   App → OTel SDK (with built-in OTLP exporter) → Backend
          (exporter lives in your process)

With Collector:  App → OTel SDK (OTLP) → OTel Collector → Jaeger + Prometheus + Loki
                 (app just sends OTLP; Collector fans out to multiple backends)
```

The Collector is the **middleman** that lets you fan out to multiple backends, do tail-based sampling, add Kubernetes metadata, and swap backends without changing app code.

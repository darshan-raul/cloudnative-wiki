---
title: OpenTelemetry Overview
description: History, goals, and unified telemetry model
tags:
  - opentelemetry
  - overview
date: 2025-01-01
draft: false
---

# OpenTelemetry Overview

## History

OpenTelemetry emerged from the merger of two projects:

- **OpenCensus** (Google, 2017) — Metrics and tracing with vendor-neutral data collection
- **OpenTracing** (CNCF, 2016) — Distributed tracing API with no data collection mandate

In 2019, the CNCF donated both projects to the OpenTelemetry project, which absorbed their best ideas into a single unified API and SDK.

Today OTel is the **CNCF's second-largest project** after Kubernetes.

## Goals

1. **Vendor neutrality** — Own your telemetry data; route to any backend
2. **Unified signals** — Single model for traces, metrics, and logs
3. **Auto-instrumentation** — Zero-code / low-code observability
4. **Cross-cutting concerns** — Context propagation, resource attributes, semantic conventions
5. **Polyglot support** — First-class SDKs for Go, Python, Java, JavaScript, .NET, Rust, C++, PHP, Ruby

## Unified Model

```
Application Code
      │
      ▼
┌─────────────────┐
│  Auto-Instrument │ ← Libraries auto-create spans/metrics
│  + Manual API    │
└────────┬────────┘
         │ (in-process)
         ▼
┌─────────────────┐
│   OTel SDK      │ ← API implementation + sampling
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Collector     │ ← Receives, processes, exports
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Any Backend    │ ← Jaeger, Prometheus, Datadog, Tempo, etc.
└─────────────────┘
```

## Key Terms

| Term | Meaning |
|------|---------|
| **Signal** | One of the three telemetry types: trace, metric, log |
| **Span** | A named, timed operation representing a unit of work in a trace |
| **Trace** | A collection of spans sharing a root span (end-to-end request path) |
| **Context** | W3C Trace Context (traceparent + tracestate) propagated across process boundaries |
| **Baggage** | Key-value pairs propagated alongside trace context |
| **Resource** | Entity producing telemetry (service, container, host) |
| **Semantic Convention** | Standardized naming for attributes |

## Why OpenTelemetry?

Before OTel, each observability backend required its own agent/library:

```
Before OTel:
App → Jaeger Agent → Jaeger Backend
App → StatsD Exporter → StatsD → Prometheus
App → Zipkin Client → Zipkin Backend
App → Custom Logging → ELK

After OTel:
App → OTel SDK → OTel Collector → Any Backend
```

OTel decouples instrumentation from export. You instrument **once** and route telemetry to **any** backend by changing Collector config.

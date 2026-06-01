---
title: OpenTelemetry
description: OpenTelemetry (OTel) architecture, signals, SDKs, Collector, and deployment
tags:
  - observability
  - telemetry
  - opentelemetry
  - tracing
  - metrics
  - logs
date: 2025-01-01
draft: false
---

# OpenTelemetry (OTel)

Unified telemetry for cloud-native applications. Traces, metrics, and logs under one vendor-neutral standard.

## Sections

- [[Architecture/OpenTelemetry/overview|Overview]] — History, goals, unified model
- [[Architecture/OpenTelemetry/signals|Signals]] — Traces, Metrics, Logs data models
- [[Architecture/OpenTelemetry/traces-101|Traces 101]] — TracerProvider, Tracer, Span, SpanContext, patterns
- [[Architecture/OpenTelemetry/metrics-101|Metrics 101]] — MeterProvider, Meter, Counter, Histogram, Gauge
- [[Architecture/OpenTelemetry/logs-101|Logs 101]] — LoggerProvider, Logger, LogRecord, bridge patterns, trace correlation
- [[Architecture/OpenTelemetry/sdk|SDK & Language Support]] — API/SDK split, auto-instrumentation, per-language agents
- [[Architecture/OpenTelemetry/collector|Collector]] — Receivers, processors, exporters pipeline
- [[Architecture/OpenTelemetry/context-propagation|Context Propagation]] — W3C Trace Context, Baggage, propagators
- [[Architecture/OpenTelemetry/otlp-protocol|OTLP Protocol]] — gRPC/HTTP transport, delivery semantics
- [[Architecture/OpenTelemetry/semantic-conventions|Semantic Conventions]] — Resource and span attribute standards
- [[Architecture/OpenTelemetry/kubernetes|Kubernetes Deployment]] — Agent vs Gateway mode, DaemonSet, resource limits
- [[Architecture/OpenTelemetry/otel-glossary|OTel Glossary]] — API vs SDK vs Protocol vs Exporter vs Collector
- [[Architecture/OpenTelemetry/exercise-end-to-end|Exercise: End-to-End]] — Go + Python instrumented services to SigNoz

## Quick Reference

| Component | Role |
|-----------|------|
| **Signal** | Trace, Metric, or Log |
| **Span** | Single unit of work in a trace |
| **Tracer** | Creates spans |
| **Meter** | Creates metrics |
| **Collector** | Receives, processes, exports telemetry |
| **OTLP** | Protocol for telemetry transport |

## References

- [OTel Docs](https://opentelemetry.io/docs/)
- [OTel Spec](https://opentelemetry.io/docs/specs/otel/)
- [OTel GitHub](https://github.com/open-telemetry)
- [OTel Registry](https://opentelemetry.io/ecosystem/registry/)

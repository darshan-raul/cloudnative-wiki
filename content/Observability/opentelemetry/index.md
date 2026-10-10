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

- [[Observability/opentelemetry/overview|Overview]] — History, goals, unified model
- [[Observability/opentelemetry/signals|Signals]] — Traces, Metrics, Logs data models
- [[Observability/opentelemetry/traces-101|Traces 101]] — TracerProvider, Tracer, Span, SpanContext, patterns
- [[Observability/opentelemetry/metrics-101|Metrics 101]] — MeterProvider, Meter, Counter, Histogram, Gauge
- [[Observability/opentelemetry/logs-101|Logs 101]] — LoggerProvider, Logger, LogRecord, bridge patterns, trace correlation
- [[Observability/opentelemetry/sdk|SDK & Language Support]] — API/SDK split, auto-instrumentation, per-language agents
- [[Observability/opentelemetry/collector|Collector]] — Receivers, processors, exporters pipeline
- [[Observability/opentelemetry/context-propagation|Context Propagation]] — W3C Trace Context, Baggage, propagators
- [[Observability/opentelemetry/otlp-protocol|OTLP Protocol]] — gRPC/HTTP transport, delivery semantics
- [[Observability/opentelemetry/semantic-conventions|Semantic Conventions]] — Resource and span attribute standards
- [[Observability/opentelemetry/kubernetes|Kubernetes Deployment]] — Agent vs Gateway mode, DaemonSet, resource limits
- [[Observability/opentelemetry/otel-glossary|OTel Glossary]] — API vs SDK vs Protocol vs Exporter vs Collector
- [[Observability/opentelemetry/exercise-end-to-end|Exercise: End-to-End]] — Go + Python instrumented services to SigNoz

## Quick Reference

| Component     | Role                                   |
| ------------- | -------------------------------------- |
| **Signal**    | Trace, Metric, or Log                  |
| **Span**      | Single unit of work in a trace         |
| **Tracer**    | Creates spans                          |
| **Meter**     | Creates metrics                        |
| **Collector** | Receives, processes, exports telemetry |
| **OTLP**      | Protocol for telemetry transport       |

## References

- [OTel Docs](https://opentelemetry.io/docs/)
- [OTel Spec](https://opentelemetry.io/docs/specs/otel/)
- [OTel GitHub](https://github.com/open-telemetry)
- [OTel Registry](https://opentelemetry.io/ecosystem/registry/)

## Further reading

- [Open Telemetry (video)](https://youtu.be/xlWCQOlQV0M)
- [Open Telemetry (video)](https://youtu.be/hnhgXi5Sesw)
- [Open Telemetry (video)](https://www.youtube.com/watch?v=ASgosEzG4Pw)
- [Open Telemetry (video)](https://www.youtube.com/watch?v=7SccIT9rAuY)
- [Open Telemetry (video)](https://www.youtube.com/watch?v=nWDCWe5OwjQ)
- [Open Telemetry (video)](https://www.youtube.com/watch?v=2l0YXOoDmOQ)
- [Open Telemetry — betterstack.com](https://betterstack.com/community/guides/observability/what-is-opentelemetry/)
- [Open Telemetry — betterstack.com](https://betterstack.com/community/guides/observability/opentelemetry-collector/)

---
title: Observability
tags:
  [observability, monitoring, prometheus, grafana, tracing, opentelemetry, sre]
date: 2026-09-06
description: "Cloud-native observability and telemetry: OpenTelemetry (OTel), Prometheus metrics, PromQL, distributed tracing, structured logging, Grafana dashboards, and SRE alerting."
---

# Observability 📊

End-to-end observability, distributed telemetry, and site reliability engineering (SRE) for modern cloud-native systems.

---

## 1. OpenTelemetry (OTel) — The Industry Telemetry Standard

Comprehensive 13-part curriculum covering the OTel architecture and data model:

- 🏛️ **[[Architecture/OpenTelemetry/index|OpenTelemetry Overview & Architecture]]** — Core specification, SDKs, and data model
- 🧭 **[[Architecture/OpenTelemetry/signals|Signals Overview]]** — Traces, Metrics, Logs, and Baggage
- 🛰️ **[[Architecture/OpenTelemetry/collector|OTel Collector Architecture]]** — Receivers, Processors, Exporters, and Extensions
- 🌐 **[[Architecture/OpenTelemetry/otlp-protocol|OTLP Protocol]]** — Protobuf over gRPC (port 4317) & HTTP (port 4318)
- 🔀 **[[Architecture/OpenTelemetry/context-propagation|Context Propagation]]** — W3C `traceparent`, `tracestate`, and Baggage injection/extraction
- 🏷️ **[[Architecture/OpenTelemetry/semantic-conventions|Semantic Conventions]]** — Standard attributes for HTTP, DB, RPC, and Cloud
- 🔍 **[[Architecture/OpenTelemetry/traces-101|Distributed Tracing 101]]** — Spans, Tracers, SpanProcessors, and ParentBased Samplers
- 📈 **[[Architecture/OpenTelemetry/metrics-101|Metrics 101]]** — Counters, UpDownCounters, Gauges, Histograms, and Temporality
- 📜 **[[Architecture/OpenTelemetry/logs-101|Structured Logging 101]]** — LogRecord data model, OTel Bridge APIs, and correlation
- ☸️ **[[Architecture/OpenTelemetry/kubernetes|Kubernetes Observability]]** — OpenTelemetry Operator, Target Allocator, and DaemonSets
- 🛠️ **[[Architecture/OpenTelemetry/exercise-end-to-end|End-to-End Implementation Lab]]** — Hands-on multi-service instrumented lab
- 📖 **[[Architecture/OpenTelemetry/otel-glossary|OpenTelemetry Glossary]]** — Quick reference for key concepts

---

## 2. Metrics & Visualization (Prometheus & Grafana)

- **[[Resources/guides/observability/prometheus/README|Prometheus Architecture]]** — Pull-based metrics collection, TSDB engine, and scraping targets
- **[[Resources/guides/observability/prometheus/promql|PromQL Guide]]** — Query language, rate/irate calculations, and vector matching
- **[[Resources/guides/observability/grafana/README|Grafana]]** — Visualization, dashboard engineering, and alerting pipelines
- **[[Resources/guides/observability/grafana/lgtm-stack|LGTM Stack]]** — Loki, Grafana, Tempo, and Mimir unified observability

---

## 3. Distributed Tracing & eBPF

- **[[Resources/guides/observability/tracing|Distributed Tracing Architecture]]** — Trace context, critical path analysis, and latency bottleneck isolation
- **[[Resources/guides/observability/ebpf|eBPF Observability]]** — Kernel-level non-intrusive network and latency tracing (Hubble, Pixie, Beyla)
- **[[Resources/guides/observability/opentelemetry-vs-prometheus|OpenTelemetry vs Prometheus]]** — Comparative architectural evaluation and migration guide

---

## Related Topics

- ☸️ **[[Kubernetes/concepts/L08-operations/00-README|Kubernetes Operations & Observability]]** — Kubelet metrics, cAdvisor, and cluster triage
- ☁️ **[[AWS/monitoring/cloudwatch-metrics/README|AWS CloudWatch]]** — Amazon CloudWatch metrics, Container Insights, and AMP
- 🔷 **[[Azure/compute/aks/observability-monitoring|Azure Container Insights]]** — Managed Prometheus and Azure Monitor
- 🚀 **[[DevOps]]** — SRE error budgets, SLO/SLI definitions, and incident response

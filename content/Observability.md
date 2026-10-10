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

## Start here

- **[[Observability/fundamentals|Observability fundamentals]]** — The signals, what each is good for, and how they fit together
- **[[Observability/prometheus/instrumenting|Instrumenting applications]]** — What to measure (RED and USE), naming, labels and histogram buckets
- **[[Observability/alerting|Alerting]]** — Symptoms over causes, burn-rate alerts, Alertmanager routing, reducing noise

---

## 1. OpenTelemetry — the telemetry standard

Comprehensive 13-part curriculum covering the OTel architecture and data model:

- 🏛️ **[[Observability/opentelemetry/index|OpenTelemetry Overview & Architecture]]** — Core specification, SDKs, and data model
- 🧭 **[[Observability/opentelemetry/signals|Signals Overview]]** — Traces, Metrics, Logs, and Baggage
- 🛰️ **[[Observability/opentelemetry/collector|OTel Collector Architecture]]** — Receivers, Processors, Exporters, and Extensions
- 🌐 **[[Observability/opentelemetry/otlp-protocol|OTLP Protocol]]** — Protobuf over gRPC (port 4317) & HTTP (port 4318)
- 🔀 **[[Observability/opentelemetry/context-propagation|Context Propagation]]** — W3C `traceparent`, `tracestate`, and Baggage injection/extraction
- 🏷️ **[[Observability/opentelemetry/semantic-conventions|Semantic Conventions]]** — Standard attributes for HTTP, DB, RPC, and Cloud
- 🔍 **[[Observability/opentelemetry/traces-101|Distributed Tracing 101]]** — Spans, Tracers, SpanProcessors, and ParentBased Samplers
- 📈 **[[Observability/opentelemetry/metrics-101|Metrics 101]]** — Counters, UpDownCounters, Gauges, Histograms, and Temporality
- 📜 **[[Observability/opentelemetry/logs-101|Structured Logging 101]]** — LogRecord data model, OTel Bridge APIs, and correlation
- ☸️ **[[Observability/opentelemetry/kubernetes|Kubernetes Observability]]** — OpenTelemetry Operator, Target Allocator, and DaemonSets
- 🛠️ **[[Observability/opentelemetry/exercise-end-to-end|End-to-End Implementation Lab]]** — Hands-on multi-service instrumented lab
- 📖 **[[Observability/opentelemetry/otel-glossary|OpenTelemetry Glossary]]** — Quick reference for key concepts

---

## 2. Metrics

- **[[Observability/prometheus/README|Prometheus architecture]]** — Pull model, series and labels, metric types, the TSDB, scaling with remote write
- **[[Observability/prometheus/promql|PromQL]]** — Selectors, `rate`, aggregation, histograms, recording rules
- **[[Observability/prometheus/instrumenting|Instrumenting applications]]** — Client libraries in Go and Python, and the mistakes that make metrics expensive

---

## 3. Logs

- **[[Observability/logging|Logging]]** — Structured logs, levels, the collection pipeline, Loki and LogQL, cost control

---

## 4. Traces

- **[[Observability/tracing|Distributed tracing]]** — Reading a trace, context propagation, head and tail sampling, span metrics, backends

---

## 5. Platforms and visualisation

- **[[Observability/grafana|Grafana]]** — Dashboard design, variables, dashboards as code, correlating signals
- **[[Observability/lgtm-stack|The LGTM stack]]** — Loki, Grafana, Tempo and Mimir as one platform: architecture, deployment modes, run or buy
- **[[Observability/ebpf|eBPF for observability]]** — Kernel-level visibility without instrumentation, and its limits

---

## 6. Acting on it

- **[[Observability/alerting|Alerting]]** — What deserves a page
- **[[DevOps/sre/slos-and-error-budgets|SLOs and error budgets]]** — Turning telemetry into reliability targets
- **[[DevOps/sre/incident-management|Incident management]]** and **[[DevOps/sre/on-call|on-call]]**

---

## Related Topics

- ☸️ **[[Kubernetes/concepts/L08-operations/00-README|Kubernetes Operations & Observability]]** — Kubelet metrics, cAdvisor, and cluster triage
- ☸️ **[[Kubernetes/eks/observability/README|Observability on EKS]]** — Control plane logs, Fluent Bit, ADOT, Managed Prometheus, OpenSearch
- ☁️ **[[AWS/monitoring/README|AWS monitoring]]** — CloudWatch metrics, logs, alarms and dashboards
- 🔷 **[[Azure/compute/aks/observability-monitoring|Azure Container Insights]]** — Managed Prometheus and Azure Monitor
- 🐧 **[[Linux/observability/README|Linux observability]]** — journalctl, strace and host monitoring
- 🔐 **[[Security/siem/README|SIEM]]** — The security use of the same telemetry

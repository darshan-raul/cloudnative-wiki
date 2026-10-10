---
title: Prometheus Architecture
tags: [observability, prometheus, metrics, monitoring]
date: 2026-10-10
description: How Prometheus works — the pull model, the data model of series and labels, the four metric types, the TSDB, service discovery, and how it scales through federation, remote write and agent mode.
---

# Prometheus Architecture

Prometheus is a monitoring system built around one idea: every target exposes its current numbers over HTTP, and a server periodically **scrapes** them and stores the results as time series. It is the default metrics system for Kubernetes, and its exposition format and query language are what most other tools in the ecosystem speak.

## Components

```
                 service discovery (Kubernetes API, EC2, Consul, files)
                              │ target list
                              ▼
 targets  ◄── HTTP GET /metrics ──  Prometheus server ──► Alertmanager ──► pager, chat
 (apps,                              ├─ scrape manager
  exporters)                         ├─ TSDB (local disk)
                                     ├─ rule evaluator  (recording + alerting rules)
 short-lived jobs ─► Pushgateway ◄───┘ scraped like any target
                                     └─ HTTP API / PromQL ──► Grafana
                                     └─ remote write ──► long-term storage
```

| Component         | Role                                                                                             |
| :---------------- | :----------------------------------------------------------------------------------------------- |
| Prometheus server | Discovers targets, scrapes them, stores samples, evaluates rules, answers queries                |
| Exporters         | Translate something that cannot be instrumented into `/metrics` (node, database, cloud API)      |
| Client libraries  | Let your own code expose metrics — see [[Observability/prometheus/instrumenting\|instrumenting]] |
| Alertmanager      | Deduplicates, groups, silences and routes alerts — see [[Observability/alerting\|alerting]]      |
| Pushgateway       | Holds the last metrics pushed by batch jobs that die before they can be scraped                  |

## Why pull

- **Target health for free.** A failed scrape is itself a signal: the synthetic `up` series becomes `0`.
- **Central control.** Scrape interval and target selection live in one place rather than in every application.
- **Easy to debug.** `curl host:port/metrics` shows exactly what Prometheus will see.

The cost is that Prometheus must be able to reach every target and must know where they are, which is why service discovery matters, and why short-lived jobs need the Pushgateway.

## The data model

A **time series** is identified by a metric name and a set of labels. Each series is a stream of timestamped float values.

```
http_requests_total{service="checkout", method="POST", status="500"}  1027  @1760097600
└── metric name ──┘└──────────────── labels ───────────────────────┘  value  timestamp
```

Every distinct combination of label values is a separate series. This is the single most important fact about Prometheus, because **cost is proportional to the number of active series**. A label with a thousand possible values multiplies the series count by a thousand. Never put user IDs, request IDs, email addresses or unbounded paths in labels; that information belongs in [[Observability/logging|logs]] or [[Observability/tracing|traces]].

## The four metric types

| Type          | Behaviour                                            | Example                           | Query with                                      |
| :------------ | :--------------------------------------------------- | :-------------------------------- | :---------------------------------------------- |
| **Counter**   | Only goes up; resets to zero on restart              | `http_requests_total`             | `rate()` — never the raw value                  |
| **Gauge**     | Goes up and down                                     | `memory_usage_bytes`, queue depth | Directly, or `avg_over_time()`                  |
| **Histogram** | Counts observations into buckets, plus sum and count | `http_request_duration_seconds`   | `histogram_quantile()` over `rate()` of buckets |
| **Summary**   | Client-side quantiles, plus sum and count            | Legacy latency metrics            | Read the quantile directly                      |

Prefer histograms to summaries. Histogram buckets can be aggregated across instances and then turned into a percentile; pre-computed summary quantiles cannot be averaged meaningfully. **Native histograms** remove the need to choose bucket boundaries up front and are far cheaper in series; use them where your stack supports them. The statistics are explained in [[Architecture/solution-architecture-concepts/percentile|percentiles]].

## Scraping and service discovery

```yaml
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: "go_gc_duration_seconds.*"
        action: drop
```

Two relabelling stages do different jobs:

- `relabel_configs` runs **before** the scrape, on discovery metadata. It decides which targets to scrape and which labels they get.
- `metric_relabel_configs` runs **after** the scrape, on each sample. It drops or rewrites series before they are stored — the main tool for controlling cardinality.

On Kubernetes, the **Prometheus Operator** replaces hand-written scrape configs with `ServiceMonitor` and `PodMonitor` resources, so each team declares how its own service is scraped.

## Storage

The local TSDB is designed for one node and recent data:

1. Incoming samples go to an in-memory **head block** and a **write-ahead log** on disk for crash recovery.
2. Every two hours the head is cut into an immutable **block** on disk: compressed chunks plus an index.
3. Blocks are **compacted** into larger ones and deleted when older than the retention period.

Samples compress to between one and two bytes each. A rough capacity estimate:

```
disk  ≈ retention_seconds × samples_per_second × 1.5 bytes
memory grows with active series (a few kilobytes each) — this is usually the limit, not disk
```

Local storage is not replicated. A lost volume is lost history, which is why anything beyond a few weeks goes to remote storage.

## Rules

- **Recording rules** precompute expensive expressions into new series, so dashboards stay fast: `job:http_requests:rate5m`.
- **Alerting rules** evaluate an expression and fire when it has been true for a `for` duration.

Both are covered with examples in [[Observability/prometheus/promql|PromQL]] and [[Observability/alerting|alerting]].

## Scaling beyond one server

| Approach            | How                                                            | Use when                                     |
| :------------------ | :------------------------------------------------------------- | :------------------------------------------- |
| Vertical            | Bigger machine                                                 | Up to a few million active series            |
| Functional sharding | One Prometheus per team or cluster                             | Natural organisational boundaries            |
| HA pair             | Two identical servers scraping the same targets                | Alerting must survive a node loss            |
| Federation          | A global server scrapes aggregated series from others          | A small cross-cluster overview               |
| Remote write        | Ship all samples to Mimir, Thanos, Cortex or a managed service | Long retention, a global view, many clusters |
| Agent mode          | Scrape and forward only; no local queries or rules             | Edge clusters feeding a central store        |

Remote-write systems add what a single server lacks: replication, object-storage retention, and one query endpoint across all clusters. See [[Observability/lgtm-stack|the LGTM stack]] for Mimir, and [[Kubernetes/eks/observability/metrics/prometheus|Prometheus on EKS]] for the managed AWS option.

## Prometheus and OpenTelemetry

They overlap and increasingly interoperate rather than compete:

|                | Prometheus                                    | OpenTelemetry                                                |
| :------------- | :-------------------------------------------- | :----------------------------------------------------------- |
| Scope          | Metrics: collection, storage, query, alerting | Traces, metrics and logs: instrumentation and transport only |
| Transport      | Pull (scrape)                                 | Push (OTLP)                                                  |
| Storage        | Built in                                      | None — needs a backend                                       |
| Query language | PromQL                                        | None                                                         |

A common design instruments with OpenTelemetry SDKs, routes through a [[Observability/opentelemetry/collector|Collector]], and stores metrics in a Prometheus-compatible backend. Prometheus accepts OTLP directly, and the Collector can scrape Prometheus endpoints, so migration can be gradual. The metric models are compared in [[Observability/opentelemetry/metrics-101|OpenTelemetry metrics]].

## Operational advice

- Monitor Prometheus itself: `prometheus_tsdb_head_series`, scrape duration, rule evaluation failures, and a dead-man's-switch alert that always fires.
- Keep one small exporter per target rather than one large multi-target exporter; failures stay isolated and scrapes stay parallel.
- Set `sample_limit` per scrape job so one misbehaving target cannot flood the server.
- Treat label names and values as an API: changing them breaks every dashboard and alert that uses them.

## Related

- [[Observability/fundamentals|Observability fundamentals]]
- [[Observability/grafana|Grafana]]
- [[Kubernetes/concepts/L08-operations/04-metrics-sources|Kubernetes metrics sources]]
- [[Linux/observability/monitoring|Linux monitoring]]
- [[DevOps/sre/slos-and-error-budgets|SLOs and error budgets]]
- [Prometheus documentation](https://prometheus.io/docs/introduction/overview/)

## Further reading

- [Opentelemetry vs Prometheus (video)](https://www.youtube.com/live/zvPwvm7X6AY)
- [Prometheus: A complete playlist covering everuing (video playlist)](https://www.youtube.com/playlist?list=PLrMP04WSdCjrL4OBnaqXRy8X3XEd7ZrKf)
- [Prometheus: A complete playlist covering everuing — promlabs.com](https://promlabs.com/blog/2024/08/17/smaller-is-better-why-you-should-avoid-large-multi-target-exporters-in-prometheus/)

## Across the wiki

- [[Kubernetes/eks/observability/README|Observability on EKS]] — cluster observability (Kubernetes)
- [[Azure/compute/aks/observability-monitoring|AKS Observability — Container Insights, Managed Prometheus, and ContainerLogV2]] — cluster observability (Azure)
- [[GCP/compute/gke/observability-gmp|GKE Observability Architecture — Managed Prometheus (GMP), Logging, and Trace]] — cluster observability (GCP)

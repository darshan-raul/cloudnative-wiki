---
title: The LGTM Stack
tags: [observability, grafana, loki, tempo, mimir, lgtm]
date: 2026-10-10
description: Loki, Grafana, Tempo and Mimir as one observability platform — the architecture they share, how telemetry flows in, deployment modes, sizing and tenancy, and when to run it versus buying a managed service.
---

# The LGTM Stack

LGTM is Grafana Labs' open-source observability stack: **L**oki for logs, **G**rafana for visualisation, **T**empo for traces and **M**imir for metrics. Pyroscope adds continuous profiling as a fourth signal. Together they provide what commercial observability vendors sell, on your own infrastructure.

| Component   | Signal    | Query language | Roughly replaces                                           |
| :---------- | :-------- | :------------- | :--------------------------------------------------------- |
| **Mimir**   | Metrics   | PromQL         | A scaled-out, long-term Prometheus                         |
| **Loki**    | Logs      | LogQL          | Elasticsearch/OpenSearch for logs                          |
| **Tempo**   | Traces    | TraceQL        | Jaeger                                                     |
| **Grafana** | All       | —              | Kibana, vendor consoles                                    |
| Pyroscope   | Profiles  | —              | Vendor continuous profilers                                |
| Alloy       | Collector | —              | Prometheus agent, Promtail, an OTel Collector distribution |

## One architecture, three times

Mimir, Loki and Tempo descend from the same design, and understanding it once explains all three:

```
                 write path                                 read path
   agents ─► distributor ─► ingester ──flush──►  object storage  ◄── store-gateway / querier
              (validate,     (memory + WAL,      (S3, GCS, Azure Blob)        ▲
               shard by       replicated ×3)            ▲                      │
               tenant)                                  │              query-frontend
                                                   compactor           (split, cache, queue)
                                               (merge, dedupe, retention)        ▲
                                                                              Grafana
```

- **Object storage is the database.** Durable data lives in a bucket; compute is largely stateless. This is why the stack is cheap at volume: object storage costs a fraction of the replicated SSDs that index-heavy systems need.
- **Ingesters** hold recent data in memory with a write-ahead log, replicated across three instances, and flush blocks to the bucket.
- **Queriers** read recent data from ingesters and older data from the bucket; a **query frontend** splits long queries by time, runs the parts in parallel and caches results.
- **Compactors** merge blocks, deduplicate replicas and apply retention.
- **Multi-tenancy is built in.** Every request carries a tenant ID (`X-Scope-OrgID`), and limits are set per tenant.

The trade-off is the mirror image of an indexed store: writes are cheap and storage is cheap, while a query that cannot be narrowed by labels and time has to scan a lot of data.

## How telemetry gets in

```
applications ── OTLP ──►  collector (Alloy or OpenTelemetry Collector)
nodes, kubelet, exporters ◄── scrape ──┘        │
container log files ◄── tail ──────────┘        ├── metrics ─► Mimir   (remote write or OTLP)
                                                ├── logs ────► Loki    (OTLP or push API)
                                                ├── traces ──► Tempo   (OTLP)
                                                └── profiles ► Pyroscope
```

One collector tier in front of all backends is the recommended shape. Applications emit [[Observability/opentelemetry/otlp-protocol|OTLP]] and never know where data ends up; the collector adds Kubernetes metadata so that all signals share the same `cluster`, `namespace`, `pod` and `service` identifiers. That shared labelling is what makes correlation in [[Observability/grafana|Grafana]] work.

Each component is covered in its own note: [[Observability/prometheus/README|Prometheus]] for the metrics model Mimir implements, [[Observability/logging|logging]] for Loki and LogQL, and [[Observability/tracing|tracing]] for Tempo and sampling.

## Deployment modes

| Mode                | What runs                                           | Suitable for                                          |
| :------------------ | :-------------------------------------------------- | :---------------------------------------------------- |
| **Monolithic**      | One binary with every component                     | Development, small single-cluster installs            |
| **Simple scalable** | Three targets: write, read, backend                 | Loki at moderate volume                               |
| **Microservices**   | Each component as its own Deployment or StatefulSet | Production at scale; independent scaling and upgrades |

Helm charts exist for each mode. Start smaller than you think: monolithic Loki and Tempo on object storage handle a surprising amount, and moving to microservices later does not require migrating data, because the data is in the bucket.

For a quick look at the whole stack, the `grafana/otel-lgtm` container image runs all of it in one process with an OTLP endpoint — useful on a laptop, never in production.

## What it needs

| Requirement        | Detail                                                                                                         |
| :----------------- | :------------------------------------------------------------------------------------------------------------- |
| Object storage     | One bucket per component, with lifecycle rules matching retention                                              |
| Persistent volumes | For ingesters' write-ahead logs and store-gateway caches                                                       |
| Memory             | Ingesters scale with active series (Mimir) and active streams (Loki)                                           |
| Caches             | Memcached for query results, index and chunks — they make a large difference to query speed                    |
| Zones              | Spread ingesters across three zones with zone-aware replication                                                |
| Identity           | Cloud-native credentials for bucket access, e.g. [[Kubernetes/eks/security/pod-identity\|Pod Identity]] on EKS |

Sizing is driven by a few numbers: active series and samples per second for Mimir; ingested bytes per day and stream count for Loki; spans per second and retention for Tempo. Measure them from the existing system before provisioning.

## Limits protect the platform

Because tenants share infrastructure, per-tenant limits are the main operational control:

- **Mimir**: maximum active series, ingestion rate, series per query, query time range.
- **Loki**: ingestion rate, maximum streams, maximum label names per series, query lookback.
- **Tempo**: maximum bytes per trace, ingestion rate, search limits.

Set them deliberately. The classic outage is one team deploying a metric with a user-ID label and exhausting ingester memory for everyone; a series limit turns that into a rejected write for one tenant.

## Monitoring the monitoring

- Each component ships its own dashboards and alert rules ("mixins"). Install them.
- Send the stack's own telemetry somewhere else — at minimum, a small separate Prometheus and an external dead-man's-switch — so that you still have visibility when the stack is the thing that is broken.
- Watch ingester memory, rejected samples and discarded log lines, compactor lag, and object-store request errors.

## Run it or buy it

|                     | Self-managed LGTM                   | Managed (Grafana Cloud, cloud-provider services) |
| :------------------ | :---------------------------------- | :----------------------------------------------- |
| Unit cost at volume | Low                                 | Higher                                           |
| People cost         | Real: upgrades, capacity, incidents | Close to none                                    |
| Data location       | Your accounts, your controls        | The provider's, within contractual regions       |
| Time to first value | Days to weeks                       | Hours                                            |
| Flexibility         | Complete                            | Within the service's limits                      |

The honest calculation includes engineering time. Below a certain volume, managed is cheaper in total; above it, self-hosting pays for a dedicated team. A hybrid is common — for example a managed Prometheus-compatible store with self-run Loki. On AWS the pieces are [[Kubernetes/eks/observability/metrics/prometheus|Managed Prometheus]], Managed Grafana and [[AWS/monitoring/cloudwatch-logs/README|CloudWatch Logs]]; on Azure, [[Azure/compute/aks/observability-monitoring|Azure Monitor managed Prometheus]].

## Alternatives in the same space

- **Thanos** — sidecars and object storage added to existing Prometheus servers; a gentler path than Mimir if you already run many.
- **VictoriaMetrics** — a compact, efficient metrics store with its own log and trace siblings.
- **ClickHouse-based platforms** (SigNoz and others) — one columnar database for all signals, with strong ad hoc analytics.
- **Elastic / OpenSearch** — index-centric, strongest at full-text search and security analytics.

## Related

- [[Observability/fundamentals|Observability fundamentals]]
- [[Observability/alerting|Alerting]] — Mimir and Loki both include a ruler for alert rules
- [[Observability/opentelemetry/collector|OpenTelemetry Collector]]
- [[Kubernetes/eks/observability/README|Observability on EKS]]
- [[DevOps/platform-engineering/README|Platform engineering]] — observability as a platform capability

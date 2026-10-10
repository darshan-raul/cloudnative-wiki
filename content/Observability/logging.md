---
title: Logging
tags: [observability, logging, loki, structured-logging]
date: 2026-10-10
description: Logging as an engineering discipline — structured logs, levels, what to log and what never to, the collection pipeline, indexed versus label-based stores, Loki and LogQL, correlation with traces, and cost control.
---

# Logging

A log is a timestamped record of something that happened. Logs carry the most detail of the three signals and are the most expensive per byte, so the craft is recording what will be needed during an incident without paying to store noise.

Logs complement the other signals rather than replace them: [[Observability/prometheus/README|metrics]] tell you _that_ something is wrong and how much, [[Observability/tracing|traces]] tell you _where_ in a request path, and logs tell you _what exactly happened_ at that point. See [[Observability/fundamentals|observability fundamentals]].

## Structured logging

A log line written for humans has to be parsed with regular expressions before a machine can use it:

```
2026-10-10 14:03:22 ERROR Payment failed for order 8271 (user 5512): card declined after 312ms
```

A structured log is already data:

```json
{
  "ts": "2026-10-10T14:03:22.418Z",
  "level": "error",
  "msg": "payment failed",
  "service": "checkout",
  "order_id": "8271",
  "reason": "card_declined",
  "duration_ms": 312,
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7"
}
```

Every field can be filtered, aggregated and joined. Rules that make structured logs work across a fleet:

- **One JSON object per line, to stdout.** The platform collects it; the application does not manage files or shipping.
- **A constant `msg`.** Put variable data in fields, not in the message. `"payment failed"` can be counted; `"payment failed for order 8271"` is unique every time.
- **Consistent field names** across services: `service`, `trace_id`, `user_id`, `duration_ms`. Agree on them once, ideally following [[Observability/opentelemetry/semantic-conventions|semantic conventions]].
- **UTC timestamps** in RFC 3339 with milliseconds.
- **Use the language's structured logger**: `log/slog` in Go, `structlog` in Python, Logback with a JSON encoder in Java, `pino` in Node.js.

## Levels

| Level   | Use for                                                     | In production                        |
| :------ | :---------------------------------------------------------- | :----------------------------------- |
| `error` | An operation failed and someone may need to act             | On; consider counting it as a metric |
| `warn`  | Something unexpected that was handled — a retry, a fallback | On                                   |
| `info`  | Significant business or lifecycle events                    | On, but sparing                      |
| `debug` | Detail useful while developing or investigating             | Off, switchable at runtime           |

Two tests: an `error` should be something you would be unhappy to see a thousand times a day; an `info` line per request in a service doing ten thousand requests a second is not sparing. Make the level changeable without a redeploy, so debug logging can be turned on for one service during an incident.

## What to log

**Log:**

- Start-up configuration (minus secrets), version and commit.
- Each request at the edge of the system: method, route, status, duration, caller identity — once, not at every layer.
- State changes with business meaning: order placed, refund issued, role granted.
- Failures, with the error, the operation and enough identifiers to find the affected entity.
- Decisions that are hard to reconstruct: why a request was rejected, which fallback was taken.

**Never log:**

- Passwords, tokens, API keys, session cookies, full `Authorization` headers.
- Payment card numbers, government IDs, health data.
- Personal data beyond what you have a reason to keep. Logs are copied widely and retained long; treat them as a regulated data store.

Redact at the source with an allow-list of fields, and add a pipeline-level scrubber as a second line of defence. Security-relevant events — logins, permission changes, data exports — are an audit log with stricter retention and integrity needs; see [[Linux/security/auditd|auditd]] and [[Security/siem/README|SIEM]].

## The pipeline

```
application ─► stdout ─► container runtime file ─► agent (per node) ─► [buffer] ─► store ─► query UI
                                                    parse, enrich,                 index,
                                                    filter, redact                 retain
```

| Stage  | Common choices                                                            |
| :----- | :------------------------------------------------------------------------ |
| Agent  | Fluent Bit, Grafana Alloy, Vector, the OpenTelemetry Collector            |
| Buffer | Agent disk buffer; Kafka when volume or reliability demands it            |
| Store  | Loki, OpenSearch/Elasticsearch, CloudWatch Logs, ClickHouse-based systems |
| Query  | Grafana, OpenSearch Dashboards, vendor consoles                           |

The agent adds the context the application does not know — cluster, namespace, pod, node — and that enrichment is what makes logs searchable by workload. On a single host the equivalent is the systemd journal: [[Linux/observability/journalctl|journalctl]] and [[Linux/observability/log-management|log management]]. The Kubernetes mechanics are in [[Kubernetes/eks/observability/logging/pod-logging|pod logging]].

## Two kinds of store

|                                           | Full-text index (OpenSearch, Elasticsearch) | Label index (Loki)                         |
| :---------------------------------------- | :------------------------------------------ | :----------------------------------------- |
| Indexes                                   | Every word of every line                    | Only a small set of labels per stream      |
| Storage                                   | Local disks on cluster nodes                | Compressed chunks in object storage        |
| Ingestion cost                            | High (CPU and disk for indexing)            | Low                                        |
| Query for a rare string across everything | Fast                                        | Slower: selects streams, then scans        |
| Query for one service's recent logs       | Fast                                        | Fast                                       |
| Operations                                | Shards, mappings, heap tuning               | Simpler, but label discipline is essential |

Neither is better in general. Full-text indexing pays off when people search all logs for arbitrary terms daily; label indexing pays off when queries nearly always start from "this service, this time window". See [[Kubernetes/eks/observability/opensearch|OpenSearch for logs]].

## Loki and LogQL

Loki groups log lines into **streams**, each identified by a label set, exactly like Prometheus series. The same warning applies: labels must be low-cardinality. `namespace`, `app` and `level` are labels; `trace_id` and `user_id` are not — they stay in the line and are filtered at query time.

```logql
# Errors from checkout, parsed as JSON, slower than half a second
{namespace="payments", app="checkout"} | json | level="error" | duration_ms > 500

# Text search
{app="checkout"} |= "card_declined" != "test-account"

# A metric from logs: errors per second by reason
sum by (reason) (rate({app="checkout"} | json | level="error" [5m]))

# Find everything belonging to one request
{namespace="payments"} |= "4bf92f3577b34da6a3ce929d0e0e4736"
```

A query has a **stream selector** in braces, which uses the index, followed by a **pipeline** of filters and parsers, which scans. Narrow the selector and the time range first; that is what keeps Loki fast. **Structured metadata** lets high-cardinality fields such as `trace_id` be attached to lines and queried efficiently without becoming labels.

## Correlating with traces

Put the trace and span ID in every log line written while handling a request. OpenTelemetry logging bridges do this automatically. With it you can:

- jump from a slow span to the log lines emitted inside it,
- jump from an error log to the full request path,
- find all logs for one user-facing request across ten services with a single search.

This one field is the highest-value change most teams can make to their logging. See [[Observability/opentelemetry/logs-101|OpenTelemetry logs]] and [[Observability/opentelemetry/context-propagation|context propagation]].

## Cost control

Log volume grows without anyone deciding it should.

1. **Measure by source.** Find the top services by bytes per day; the distribution is always skewed.
2. **Drop at the agent**: health checks, readiness probes, debug lines, verbose third-party libraries.
3. **Sample repetitive successes**; keep every error.
4. **Do not use logs as metrics.** Counting lines to draw a graph is the costliest way to get a number — emit a counter.
5. **Tier retention**: days in the interactive store, months in cheap object storage, deleted on schedule.
6. **Set per-tenant limits** so one service's bug cannot fill the store for everyone.

## Common mistakes

| Mistake                                                | Consequence                                                |
| :----------------------------------------------------- | :--------------------------------------------------------- |
| Logging the same error at every layer as it propagates | One failure becomes six log lines and six alerts           |
| Multi-line stack traces as separate lines              | Events are split; use a JSON field or a multiline parser   |
| Catch, log and continue                                | The error is recorded and the bug stays hidden             |
| Logging inside a hot loop                              | Throughput collapses; volume explodes                      |
| Synchronous logging to a slow sink                     | The application blocks on its own logs                     |
| No retention policy                                    | Costs grow forever; old personal data is kept indefinitely |

## Related

- [[Observability/lgtm-stack|The LGTM stack]]
- [[Observability/grafana|Grafana]]
- [[Linux/concepts/08-logging|Linux logging basics]]
- [[AWS/monitoring/cloudwatch-logs/README|CloudWatch Logs]]
- [[Kubernetes/eks/observability/logging/control-plane-logs|EKS control plane logs]]

## Across the wiki

- [[AWS/monitoring/README|AWS Monitoring]] — cloud logging and monitoring (AWS)
- [[Azure/monitoring/log-analytics/README|Azure Monitor & Log Analytics Architecture, KQL, and Observability]] — cloud logging and monitoring (Azure)
- [[GCP/monitoring/cloud-logging/README|Cloud Logging Architecture, Log Router, and Log Analytics]] — cloud logging and monitoring (GCP)
- [[Linux/observability/README|Linux Observability]] — cloud logging and monitoring (Linux)

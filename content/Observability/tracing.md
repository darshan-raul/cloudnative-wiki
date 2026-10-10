---
title: Distributed Tracing
tags: [observability, tracing, opentelemetry, tempo, jaeger]
date: 2026-10-10
description: What distributed tracing is for and how to run it — spans and context, reading a trace, head and tail sampling, backends, span metrics and service graphs, rollout strategy and the common reasons traces break.
---

# Distributed Tracing

In a monolith, a slow request has a stack trace. In a system of twenty services, the same request crosses process and network boundaries, and no single service knows the whole story. A **trace** reconstructs it: one record of one request's journey, with the time spent at each step.

Tracing answers questions the other signals cannot:

- Which service in the chain is actually slow?
- Is the time spent working, or waiting on a dependency?
- Which downstream calls happen sequentially that could be parallel?
- What did this specific failed request do before it failed?

This page is about using and operating tracing. The data model and SDK details are in [[Observability/opentelemetry/traces-101|OpenTelemetry traces 101]].

## The model

```
trace 4bf92f35…                                              total 340 ms
│
├─ span: POST /checkout            [gateway]        0 ─────────────────── 340
│  ├─ span: authorize              [auth]           5 ── 30
│  ├─ span: POST /orders           [orders]        35 ──────────────── 320
│  │  ├─ span: SELECT inventory    [orders → db]   40 ─ 60
│  │  ├─ span: POST /payments      [payments]      65 ───────────── 300   ← the time is here
│  │  │  └─ span: HTTPS card API   [payments → ext] 70 ──────────── 295
│  │  └─ span: publish order.created [orders → kafka] 305 ─ 315
```

| Term           | Meaning                                                                                |
| :------------- | :------------------------------------------------------------------------------------- |
| **Trace**      | All spans sharing one trace ID                                                         |
| **Span**       | One timed operation: a name, start, duration, status, attributes, and a parent span ID |
| **Attributes** | Key-value detail on a span: `http.route`, `db.system`, `order.id`                      |
| **Events**     | Timestamped points inside a span, such as an exception                                 |
| **Links**      | References to spans in other traces — used for batch and messaging                     |
| **Context**    | Trace ID, span ID and flags, passed from caller to callee                              |

## Context propagation: where tracing succeeds or fails

A trace only connects if every hop passes the context on. For HTTP this is the W3C `traceparent` header:

```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             │  └────────── trace id ──────────┘ └── parent span ─┘ └ sampled flag
```

Instrumentation libraries inject and extract it automatically for common HTTP and gRPC clients and servers. Traces break — showing up as disconnected fragments — wherever that automation does not reach:

| Break point                                    | Fix                                                                      |
| :--------------------------------------------- | :----------------------------------------------------------------------- |
| A service with no instrumentation              | Add auto-instrumentation; even a pass-through of the header helps        |
| Work handed to a thread pool or async task     | Carry the context explicitly into the new execution                      |
| Message queues                                 | Inject context into message headers; link consumer spans to the producer |
| A proxy or gateway that strips unknown headers | Allow `traceparent` and `tracestate`                                     |
| Mixed propagation formats (B3, X-Ray, W3C)     | Configure several propagators during migration                           |

Details and code are in [[Observability/opentelemetry/context-propagation|context propagation]].

## Reading a trace

1. **Find the longest bar that is not explained by its children.** A span whose children cover its whole duration is waiting; a span with a large gap has self-time — that is where work happens.
2. **Look for staircases.** Many short sequential spans to the same dependency is the N+1 query pattern.
3. **Look for gaps between a parent's start and its first child.** Queueing, connection acquisition, garbage collection or lock contention often hide there.
4. **Check the error span, then its parents.** The deepest failed span is usually the cause; the ones above are consequences.
5. **Compare with a healthy trace** of the same operation. Trace comparison views make structural differences obvious.

## Sampling

Tracing every request is rarely affordable, and almost all traces are uninteresting. Sampling decides which to keep.

| Strategy          | Decision made                               | Strengths                                                   | Weaknesses                                                                   |
| :---------------- | :------------------------------------------ | :---------------------------------------------------------- | :--------------------------------------------------------------------------- |
| **Head sampling** | At the first span, by ratio                 | Cheap; no buffering; unsampled requests cost almost nothing | Blind: keeps 1% of errors along with 1% of everything else                   |
| **Tail sampling** | After the trace completes, in the collector | Keeps what matters: errors, slow requests, rare routes      | Must buffer whole traces; all spans of a trace must reach the same collector |

A tail-sampling policy in the [[Observability/opentelemetry/collector|OpenTelemetry Collector]]:

```yaml
processors:
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: errors
        type: status_code
        status_code: { status_codes: [ERROR] }
      - name: slow
        type: latency
        latency: { threshold_ms: 1000 }
      - name: baseline
        type: probabilistic
        probabilistic: { sampling_percentage: 2 }
```

Tail sampling at scale needs two collector tiers: a load-balancing tier that routes by trace ID, and a sampling tier behind it. Always use **parent-based** samplers in services so a downstream service honours the upstream decision rather than making its own; otherwise traces come out with holes.

## Getting metrics from traces

Sampled traces cannot be counted to produce accurate rates. Generate metrics from **all** spans before sampling instead:

- **Span metrics** — request rate, error rate and duration histograms per service and operation, derived by the collector's `spanmetrics` connector or by the backend's metrics generator.
- **Service graphs** — edges between services with call rates and error rates, built from client–server span pairs.
- **Exemplars** — trace IDs attached to histogram buckets, so a latency spike on a [[Observability/grafana|Grafana]] panel links to a real trace.

This gives RED dashboards for every service without writing metric instrumentation, and is often the fastest way to show value from tracing.

## Backends

| Backend                  | Storage                           | Notes                                                       |
| :----------------------- | :-------------------------------- | :---------------------------------------------------------- |
| Grafana Tempo            | Object storage                    | Cheap at volume; TraceQL; pairs with Loki and Mimir         |
| Jaeger                   | OpenSearch, Cassandra, ClickHouse | Mature, good UI; v2 is built on the OpenTelemetry Collector |
| AWS X-Ray                | Managed                           | Native to AWS services; accepts OTLP                        |
| SigNoz, ClickHouse-based | ClickHouse                        | Traces, metrics and logs in one columnar store              |
| Commercial APM           | Vendor                            | Least operational effort, highest unit cost                 |

All accept OTLP, so instrumenting with OpenTelemetry keeps the choice reversible. A TraceQL example:

```
{ resource.service.name = "payments" && span.http.response.status_code >= 500 && duration > 1s }
```

## Rolling it out

1. **Start with auto-instrumentation** for one request path end to end. On Kubernetes the OpenTelemetry Operator injects agents without image changes — see [[Observability/opentelemetry/kubernetes|OpenTelemetry on Kubernetes]].
2. **Send everything through a collector**, never directly from applications to a backend.
3. **Fix propagation gaps** until traces are whole. A complete trace through five services is worth more than deep spans in one.
4. **Add manual spans and attributes** where business meaning lives: order IDs, tenant, feature flags, cache hit or miss.
5. **Turn on span metrics** and build service dashboards from them.
6. **Add trace IDs to logs** — see [[Observability/logging|logging]].
7. **Introduce tail sampling** once volume makes it necessary.

## Practical cautions

- **Attributes can leak data.** Query strings, SQL statements and headers often contain personal data or secrets. Scrub them in the collector.
- **Span names must be low-cardinality**: `GET /orders/{id}`, not `GET /orders/8271`.
- **Too many spans** — one per function call — add overhead and noise. Trace boundaries and significant operations.
- **Clock skew** between hosts makes child spans appear to start before their parents; durations are still reliable.
- **Overhead** of sampled-out requests is small but not zero; measure it for latency-critical services.

## Related

- [[Observability/fundamentals|Observability fundamentals]]
- [[Observability/lgtm-stack|The LGTM stack]]
- [[Observability/opentelemetry/exercise-end-to-end|End-to-end tracing exercise]]
- [[Kubernetes/eks/observability/metrics/adot|ADOT on EKS]]
- [[Kubernetes/guides/networking/istio|Istio]] — mesh proxies generate spans but still need applications to forward headers

## Further reading

- [Tracing (video)](https://www.youtube.com/watch?v=FK0uh-7nDSg&t=931s)
- [Tracing (video)](https://youtu.be/zWJSYch26HI)

---
title: Instrumenting Applications for Prometheus
tags: [observability, prometheus, metrics, instrumentation]
date: 2026-10-10
description: How to add useful metrics to a service — what to measure with RED and USE, naming and label rules, choosing histogram buckets, Go and Python examples, and the mistakes that make metrics expensive or misleading.
---

# Instrumenting Applications for Prometheus

Infrastructure metrics tell you a container is using CPU. Only the application can tell you that checkout requests are failing. Instrumentation is the act of making a service report what it is doing, and a small number of well-chosen metrics is worth far more than hundreds of accidental ones.

How the numbers are collected and stored is covered in [[Observability/prometheus/README|Prometheus architecture]].

## What to measure

Two checklists cover almost everything.

**RED — for anything that serves requests**

| Signal       | Metric                     | Type                                    |
| :----------- | :------------------------- | :-------------------------------------- |
| **R**ate     | Requests per second        | Counter                                 |
| **E**rrors   | Failed requests per second | Counter (same metric, a `status` label) |
| **D**uration | How long requests take     | Histogram                               |

**USE — for anything that is a resource** (a pool, a queue, a disk)

| Signal          | Example                                        | Type    |
| :-------------- | :--------------------------------------------- | :------ |
| **U**tilisation | Connections in use out of the pool size        | Gauge   |
| **S**aturation  | Requests waiting for a connection; queue depth | Gauge   |
| **E**rrors      | Connection failures, timeouts                  | Counter |

Instrument at the boundaries first: every inbound request, every outbound call to a database, cache, queue or other service. Then add a few **business** metrics that say whether the system is doing its job — orders placed, payments declined, messages processed. Those are what make a dashboard meaningful to anyone outside the team. These map directly onto [[DevOps/sre/slos-and-error-budgets|SLIs]].

## Naming

Prometheus conventions are worth following exactly, because every dashboard and alert you find online assumes them.

- `snake_case`, with a prefix for the application or domain: `checkout_`, `http_`.
- **Base units**, in the name: `_seconds`, `_bytes`, never milliseconds or megabytes.
- Counters end in `_total`: `http_requests_total`.
- One metric measures one thing. Do not mix units or meanings under one name.
- A name should make sense without its labels; `sum()` over all labels must be a meaningful number.

| Avoid                                     | Use                                         |
| :---------------------------------------- | :------------------------------------------ |
| `request_latency_ms`                      | `http_request_duration_seconds`             |
| `errors`                                  | `http_requests_total{status="500"}`         |
| `checkout_success` and `checkout_failure` | `checkout_attempts_total{result="success"}` |
| `memoryMB`                                | `process_resident_memory_bytes`             |

## Labels

Labels are dimensions you can filter and aggregate by. Each new label value creates a new time series, so the rule is: **label values must come from a small, bounded set.**

| Good labels                              | Dangerous labels                    |
| :--------------------------------------- | :---------------------------------- |
| `method` (GET, POST…)                    | `user_id`, `email`, `session_id`    |
| `status` or status class (2xx, 4xx, 5xx) | `request_id`, `trace_id`            |
| `route` as a template: `/orders/{id}`    | The raw URL path: `/orders/8271653` |
| `result` (success, declined, error)      | Error message text                  |

Use the route **template** from your HTTP framework, never the concrete path. To connect a metric to a specific request, attach a trace ID as an **exemplar** on the histogram rather than as a label; Grafana can then jump from a latency spike to an example [[Observability/tracing|trace]].

Target labels such as `namespace`, `pod` and `instance` are added by Prometheus at scrape time. Do not add them yourself.

## Histogram buckets

A histogram needs bucket boundaries that surround the values you care about. If the latency objective is 300 ms, there must be a boundary at or very near 0.3, otherwise the percentile around it is an interpolation across a wide bucket and can be badly wrong.

```
default buckets:  .005 .01 .025 .05 .1 .25 .5 1 2.5 5 10
for a 300 ms SLO: .01 .025 .05 .1 .2 .3 .4 .5 .75 1 2.5 5
```

Each bucket is a series per label combination, so a histogram with 12 buckets, 5 routes, 4 methods and 3 status classes is already 720 series. Keep labels on histograms few. Native histograms avoid the trade-off entirely where supported.

## Go

```go
package main

import (
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	requests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "HTTP requests processed, by route, method and status.",
	}, []string{"route", "method", "status"})

	duration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "HTTP request latency.",
		Buckets: []float64{.01, .025, .05, .1, .2, .3, .5, 1, 2.5, 5},
	}, []string{"route", "method"})

	inFlight = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "http_requests_in_flight",
		Help: "Requests currently being served.",
	})
)

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func instrument(route string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		inFlight.Inc()
		defer inFlight.Dec()

		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		start := time.Now()
		next.ServeHTTP(rec, r)

		duration.WithLabelValues(route, r.Method).Observe(time.Since(start).Seconds())
		requests.WithLabelValues(route, r.Method, strconv.Itoa(rec.status)).Inc()
	})
}

func main() {
	http.Handle("/orders/{id}", instrument("/orders/{id}", http.HandlerFunc(getOrder)))
	http.Handle("/metrics", promhttp.Handler())
	http.ListenAndServe(":8080", nil)
}
```

The default registry also exports Go runtime and process metrics (goroutines, GC pauses, file descriptors, memory) at no extra effort. Related Go background: [[Architecture/languages/golang/context|context]] and [[Architecture/languages/golang/README|the Go section]].

## Python

```python
import time
from prometheus_client import Counter, Histogram, start_http_server

REQUESTS = Counter(
    "http_requests_total", "HTTP requests processed.", ["route", "method", "status"]
)
DURATION = Histogram(
    "http_request_duration_seconds", "HTTP request latency.", ["route", "method"],
    buckets=(.01, .025, .05, .1, .2, .3, .5, 1, 2.5, 5),
)

def handle(route, method, fn):
    start = time.perf_counter()
    status = "500"
    try:
        result = fn()
        status = "200"
        return result
    finally:
        DURATION.labels(route, method).observe(time.perf_counter() - start)
        REQUESTS.labels(route, method, status).inc()

start_http_server(9100)  # serves /metrics
```

With multi-process servers such as Gunicorn, each worker has its own counters. Enable the client's multiprocess mode, or the scrape returns whichever worker happened to answer.

## Common mistakes

| Mistake                                          | Consequence                                       | Instead                                                   |
| :----------------------------------------------- | :------------------------------------------------ | :-------------------------------------------------------- |
| A gauge for something that only increases        | `rate()` gives nonsense; restarts look like drops | A counter                                                 |
| Averaging latency                                | The mean hides the slow tail users complain about | A histogram and percentiles                               |
| A metric that appears only after the first error | `rate()` returns no data, alerts never fire       | Initialise label combinations at start-up                 |
| Separate metric names per status                 | Cannot compute an error ratio with one expression | One metric with a `status` label                          |
| Unbounded label values                           | Series explosion, memory exhaustion, a large bill | Templates and bounded sets                                |
| Measuring only successful requests               | Latency looks good while errors return instantly  | Record every request, label the outcome                   |
| Exposing `/metrics` to the internet              | Leaks internals                                   | Serve it on a separate port, restricted by network policy |

## Prometheus client or OpenTelemetry SDK

New services can instrument with the [[Observability/opentelemetry/metrics-101|OpenTelemetry metrics API]] instead and export in Prometheus format or over OTLP. Choose OpenTelemetry when you also want traces and logs from one SDK with shared context; choose the Prometheus client when metrics are all you need and you want the simplest possible setup. The naming and label rules above apply either way.

## Checklist for a new service

1. Request rate, errors and duration on every inbound endpoint.
2. The same three for every outbound dependency.
3. Pool and queue utilisation and saturation.
4. Two or three business counters.
5. A `build_info` gauge with `version` and `commit` labels, value `1`.
6. A dashboard built from these, and one alert on the error ratio.

## Related

- [[Observability/prometheus/promql|PromQL]] — querying what you just exposed
- [[Observability/alerting|Alerting]]
- [[Observability/opentelemetry/semantic-conventions|Semantic conventions]] — standard names across languages
- [[Observability/fundamentals|Observability fundamentals]]

## Further reading

- [Intrumenting: best practices — prometheus.io](https://prometheus.io/docs/practices/naming/)
- [Intrumenting: best practices — antonputra.com](https://antonputra.com/monitoring/monitor-golang-with-prometheus/#counter)
- [Intrumenting: best practices — gabrieltanner.org](https://gabrieltanner.org/blog/collecting-prometheus-metrics-in-golang/)
- [Intrumenting: best practices (video)](https://www.youtube.com/watch?v=WUBjlJzI2a0)

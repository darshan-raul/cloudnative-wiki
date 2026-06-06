---
title: Performance Testing
tags: [performance, testing, load-testing, sre]
date: 2025-05-24
description: Types of performance tests, metrics, and tooling
---

# Performance Testing

Performance testing validates that a system meets its non-functional requirements under realistic load. Do it in CI, not just before launch.

---

## Types of Performance Tests

### 1. Load Testing
Normal expected load — verify system handles peak comfortably.

```
Users: 1x baseline → 10x baseline
Metrics: response time, error rate, throughput
Goal: "Does it work at normal load?"
```

### 2. Stress Testing
Push beyond normal load to find the breaking point.

```
Users:10x baseline → 100x baseline
Metrics: throughput curve, error rate spike, recovery behavior
Goal: "Where does it break, and how does it fail?"
```

### 3. Spike Testing
Sudden, sharp increase in traffic.

```
Baseline ──▶ 50x spike ──▶ Baseline
           (seconds)
Goal: "Can the system handle sudden traffic surges?"
```

### 4. Soak Testing (Endurance Testing)
Sustained load over hours to detect memory leaks, log rotation, DB connection pool exhaustion.

```
Load: 50% capacity for 12-24 hours
Metrics: memory usage, connection count, disk usage, GC frequency
Goal: "Does it hold up over time?"
```

### 5. Chaos / Resilience Testing
Deliberately break things to validate observability and recovery.

```
Kill a pod → verify alerts fire → verify runbook executes → verify recovery
Goal: "Can we detect and recover from failures automatically?"
```

---

## Key Metrics

| Metric | What It Is | Target Example |
|--------|-----------|----------------|
| **Throughput** | Requests/sec the system handles | 1,000 req/sec |
| **Latency (p50)** | Median response time |< 50ms |
| **Latency (p95)** | 95th percentile |< 200ms |
| **Latency (p99)** | 99th percentile | < 500ms |
| **Error rate** | % of requests returning 5xx |< 0.1% |
| **Saturation** | How full are the resources? | CPU < 70%, DB connections < 80% |
| **RPS per instance** | Requests/sec per server | Profile to find limits |

---

## Latency Percentiles Explained

```
Response times for 100 requests (sorted):
[1ms, 2ms, 3ms, ... 50ms, 51ms, ... 95ms, 98ms, 100ms, 500ms, 800ms]

p50 = 50th value = ~50ms   ← "half are faster, half are slower"
p95 = 95th value = ~100ms  ← "5% of requests are slower than this"
p99 = 99th value = ~500ms  ← "1% of requests are slower than this"
```

**Why p99 and not p95?** The slowest1% of requests are where user complaints come from.

---

## Load Testing Tools

### k6 (Best for Most Teams)

```javascript
// script.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 100 },   // ramp up
    { duration: '5m', target: 100 },  // steady state
    { duration: '2m', target: 0 },    // ramp down
  ],
  thresholds: {
    http_req_duration: ['p95<500'], // p95 < 500ms
    http_req_failed: ['rate<0.01'],    // error rate < 1%
  },
};

export default function () {
  const res = http.get('https://api.example.com/health');
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
```

```bash
k6 run script.js
```

### Apache Bench (Simple)

```bash
ab -n 10000 -c 100 https://api.example.com/health
# -n: total requests
# -c: concurrent clients
```

### wrk / wrk2

```bash
wrk -t12 -c400 -d30s https://api.example.com/health
```

### Locust (Python, distributed)

```python
# locustfile.py
from locust import HttpUser, task, between

class AppUser(HttpUser):
    wait_time = between(1, 3)

    @task
    def get_order(self):
        self.client.get("/orders/123")
```

---

## Reading Load Test Results

```
Test: 1,000 concurrent users, 60 second ramp-up

Throughput:
 50k req/sec ← flat until saturation point
50k req/sec ← plateau (max throughput)
  30k req/sec ← saturation, latency spikes

Latency:
  p50: 45ms   ← normal
  p95: 120ms  ← normal
  p99: 800ms  ← some requests taking long (GC pause? DB lock?)
  p99: 5000ms ← approaching saturation

Error rate:
  0.01% ← good (only initial cold-start failures)
  5%    ← system failing under load

Conclusion: system saturates at ~50k req/sec
  → autoscale threshold: > 70% capacity
  → set SLO:99.95% availability @ 40k req/sec sustained
```

---

## Performance Testing in CI

```yaml
# GitHub Actions
- name: Load Test
  run: |
    k6 run \
 -o influxdb=http://influxdb:8086/k6 \
      k6-load-test.js
 env:
    TARGET_URL: https://staging.api.example.com
```

```javascript
// k6-load-test.js
export const options = {
  stages: [{ duration: '2m', target: 100 }],
  thresholds: {
    http_req_duration: ['p95<500'],
    http_req_failed: ['rate<0.01'],
  },
};
```

---

## Common Performance Problems

| Problem | Symptom | Fix |
|---------|---------|-----|
| DB connection pool exhaustion | Connection timeouts under load | Increase pool size, add read replica |
| N+1 queries | Latency spikes, DB CPU spike | Eager load, query optimization |
| Memory leak | Throughput drops over time | Heap profiling, restart policy |
| GC pauses | p99 latency spikes | Reduce allocations, tune GC |
| Cold start | First request very slow | Pre-warming, keep-alive |
| No connection pooling | High latency per request | Reuse connections (HTTP keep-alive) |
| Synchronous I/O in hot path | Low throughput | Async I/O, batching |

---

## Quick Checklist

```
□ Load test at10x expected peak
□ p95 and p99 latency measured and baselined
□ Error rate tracked (not just success/failure)
□ Soak test for 12+ hours before major releases
□ Performance regression in CI (k6 in GitHub Actions)
□ Profile production under real load (pprof, async_profiler)
□ SLO dashboard with error budget tracking
```

---

## Source

- [k6 Documentation](https://k6.io/docs/)
- [Grafana k6](https://grafana.com/docs/k6/latest/)
- [Locust Documentation](https://locust.io/)

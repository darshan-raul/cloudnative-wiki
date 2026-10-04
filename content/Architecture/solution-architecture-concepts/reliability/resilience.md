---
title: Resilience
tags: [architecture, reliability, fault-tolerance]
date: 2025-05-24
description: Patterns for building fault-tolerant, resilient distributed systems
---

# Resilience

Resilience = **the ability to keep serving** even when components fail. Not about preventing failures — about handling them gracefully.

---

## The Three Pillars

```
1. Prevention:   Stop failures from happening
2. Detection:    Find failures fast when they happen
3. Recovery:     Recover from failures automatically
```

Most effort goes to detection and recovery. Prevention is impossible at scale.

---

## Core Patterns

### 1. Timeouts

Every call to an external service must have a timeout. No timeouts = request hangs forever.

```python
# ❌ No timeout — request can hang indefinitely
response = requests.get("https://api.example.com/data")

# ✅ With timeout
response = requests.get("https://api.example.com/data", timeout=3)
```

**Rule:** Set timeouts at the 99th percentile of expected latency, not arbitrary values.

### 2. Circuit Breakers

```
CLOSED (normal):       requests pass through
 ↓ failure threshold
OPEN (failing):        requests rejected immediately (fallback)
  ↓ recovery timeout
HALF-OPEN (testing):  one probe request to test recovery
  ↓ success ↓ failure
CLOSED                 OPEN
```

```python
from circuitbreaker import circuit

@circuit(failure_threshold=5, recovery_timeout=30)
def call_external_service():
    return external_api.get("/data")
```

###3. Retry with Exponential Backoff

```python
import time, random

def retry_with_backoff(func, max_attempts=3, base_delay=1):
    for attempt in range(max_attempts):
        try:
            return func()
        except RetryableError as e:
            if attempt == max_attempts - 1:
                raise
            delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
            time.sleep(delay)
```

**Key:** Add **jitter** (randomization) to prevent thundering herd.

```
Without jitter:  all clients retry at t=1, t=2, t=4...
With jitter:     clients retry spread across t=1-2, t=2-4...
```

### 4. Bulkheads

Isolate failures so one component's failure doesn't cascade.

```
Traditional (shared pool):     Bulkhead (isolated pools):
┌─────────────────────┐       ┌────────┐ ┌────────┐ ┌────────┐
│      Thread Pool    │       │ Pool A │ │ Pool B │ │ Pool C │
│  (all services share)│       │ (svc A)│ │ (svc B)│ │ (svc C)│
└─────────────────────┘       └────────┘ └────────┘ └────────┘
 svc A overload ──▶ all svc fail svc A overload ──▶ only A fails
```

In K8s: separate `Deployment` per service with its own resource limits.

### 5. Graceful Degradation

When a dependency fails, serve a useful fallback instead of a hard error.

```python
def get_product_detail(product_id):
    try:
        # Primary: from recommendation engine
        return recommendation_engine.get(product_id)
    except ServiceUnavailable:
        # Fallback: from static cache
        return static_cache.get(product_id)
    except Exception:
        # Last resort: return minimal data
        return {"product_id": product_id, "name": "Default Product"}
```

### 6. Health Checks

```python
# Kubernetes-style health endpoints
@app.get("/health/live")
def liveness():
    return {"status": "ok"}  # I'm alive

@app.get("/health/ready")
def readiness():
    if not db.is_connected():
        return {"status": "not_ready", "reason": "db_disconnected"}, 503
    if not redis.is_connected():
        return {"status": "not_ready", "reason": "cache_disconnected"}, 503
    return {"status": "ready"}
```

| Check           | Purpose                | LB Removes Instance? |
| --------------- | ---------------------- | -------------------- |
| `/health/live`  | Process is alive       | No (never kill)      |
| `/health/ready` | Ready to serve traffic | Yes                  |

---

## Chaos Engineering

Test resilience by deliberately breaking things in staging.

```
Game Day: intentionally kill a service, verify alarms fire, runbook executes
```

**Principles:**

1. Blast radius: start small (1 pod,1 AZ)
2. Hypothesis: "we expect X to happen"
3. Measure: did the system behave as expected?
4. Automate: repeat in CI

### Tools

| Tool                          | What It Breaks            |
| ----------------------------- | ------------------------- |
| Chaos Monkey (Netflix)        | Random service kill       |
| Gremlin                       | CPU, memory, network, I/O |
| Litmus                        | K8s resources             |
| kube-monkey                   | K8s pod kill              |
| AWS Fault Injection Simulator | AWS resources             |

---

## Reliability vs Availability

| Property         | Definition                                   | What It Measures                 |
| ---------------- | -------------------------------------------- | -------------------------------- |
| **Reliability**  | Probability system works correctly over time | "Did we serve the right answer?" |
| **Availability** | Proportion of time system is operational     | "Is the system up?"              |

```
Reliable but not available:  wrong answers fast
Available but not reliable:  right answers slowly (or not at all)
Both:                        right answers, fast, always
```

---

## Quick Checklist

```
□ All external calls have timeouts
□ Circuit breakers on all dependencies
□ Retries with exponential backoff + jitter
□ Bulkhead isolation (separate thread pools / deployments)
□ Graceful degradation for non-critical dependencies
□ Health endpoints: /live and /ready
□ Chaos engineering in staging (game days)
□ Runbook for every failure scenario
□ Observability: latency percentiles, error rates, circuit state
```

---

## Source

- [Netflix Chaos Engineering](https://principlesofchaos.org/)
- [Martin Fowler — Circuit Breaker](https://martinfowler.com/bliki/CircuitBreaker.html)
- [AWS — Fault Injection Simulator](https://aws.amazon.com/fis/)

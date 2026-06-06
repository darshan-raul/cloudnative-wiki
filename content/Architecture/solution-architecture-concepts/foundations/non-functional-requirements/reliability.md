---
title: Reliability
---

# Reliability

Reliability is the probability that a system will function correctly under specified conditions for a specified period. A reliable system doesn't just stay up — it does the right thing, even when components fail.

The distinction that matters:

- **Availability** — "is the system up?" (are we responding?)
- **Reliability** — "is the system doing the right thing?" (are we responding correctly?)

A system can be available (responding) but unreliable (returning wrong data, processing duplicate transactions, silently dropping updates). See [[reliability-vs-availability|Reliability vs Availability]] for the full distinction.

## Failure Modes

Before designing for reliability, enumerate how things fail:

### Hardware Failures
- **Disk failure** — data loss if no RAID/replication. Mitigate: replication, backups, checksums.
- **RAM failure** — silent data corruption (bit flips). Mitigate: ECC RAM, checksums, read-replication.
- **Network hardware failure** — partition between components. Mitigate: multi-path networking, redundant switches.

### Software Failures
- **Crash loops** — process starts, fails, restarts, fails again. Mitigate: health checks, backoff delays, proper error handling.
- **Memory leaks** — gradual memory exhaustion. Mitigate: memory limits, restart policies, monitoring.
- **Deadlocks** — threads block forever waiting for each other. Mitigate: lock-free data structures, timeouts.
- **Cascading failures** — one component's failure causes others to fail. Mitigate: circuit breakers, bulkheads.

### Human Errors
- **Misconfigured deployments** — wrong environment variables, IP addresses. Mitigate: IaC, immutability, canary deployments.
- **Runaway deployments** — deploy breaks something, spreads to all instances. Mitigate: blue-green, feature flags, rollback.
- **Data corruption** — bad data writes corrupt the system. Mitigate: validation, backup before migration.

## The Reliability Hierarchy

From most to least impactful:

```
1. Redundancy          — eliminate single points of failure
2. Failure detection — know when something failed fast
3. Failover             — switch to backup automatically
4. Graceful degradation — continue partial service during failure
5. Recovery            — restore full service after failure
6. Observability       — detect failures before customers do
```

Skipping steps 1-3 leads to hero-driven recovery (a human manually fixes it). Hero-driven recovery doesn't scale and has terrible MTTR.

## Redundancy Patterns

### Replication

Keep identical copies of data/service across failure boundaries:

```
Active-Active:
 Node A ←→ Node B  (both serve traffic, sync state)

Active-Passive:
  Node A  →  Node B  (B is standby, takes over on A failure)
```

**Active-active** requires distributed consensus (see Raft in [[cluster-management/raft|raft]]) — complex but instant failover.

**Active-passive** is simpler — standby only receives state updates. Failover takes seconds to minutes.

### Erasure Coding

For storage systems: replicate data across failure domains with redundancy:

```
3 copies across 3 availability zones = tolerate 2 AZ loss
Reed-Solomon (10+4) = tolerate 4 disk failures,40% storage overhead
```

vs naive3x replication = 200% storage overhead for same durability.

### Geographic Redundancy

For disaster recovery: replicate across regions:

```
us-east-1 (primary) → us-west-2 (secondary)
 → eu-west-1 (tertiary for critical data)
```

Cross-region replication lag is measured in seconds to minutes. Synchronous cross-region writes are too slow for most applications (150-250ms round-trip).

## Fault Tolerance Patterns

### Circuit Breakers

Stop calling a failing dependency to prevent cascade:

```
Closed (normal):
  requests → dependency
 if error_rate > 50% in 10s → OPEN

Open:
  requests → fail immediately (no network call)
  after 30s → HALF-OPEN (allow test requests)

Half-Open:
  test requests → dependency
  if still failing → OPEN again
  if healthy → CLOSED
```

See [[resilience|Resilience]] for code examples.

### Bulkheads

Isolate failures so they don't spread across the system:

```
Without bulkheads:
  Service A → Service B → Service C
  If C fails → B waits → A hangs

With bulkheads:
  Service A → Pool B-1 ──→ Service C-1
            → Pool B-2 ──→ Service C-2
  If C-1 fails → B-1 pool is isolated → B-2 pool unaffected
```

Implementation: separate thread pools per dependency, separate Kubernetes namespaces per tenant/criticality.

### Timeouts

Every network call must have a timeout. No timeouts = one slow dependency takes down the entire system:

```python
# Bad: no timeout — request hangs forever
result = requests.get("https://api.example.com/data")

# Good: timeout with fallback
try:
    result = requests.get(
        "https://api.example.com/data",
        timeout=(3.0, 10.0)  # (connect_timeout, read_timeout)
    )
except requests.Timeout:
    return cached_data_or_default()
```

Default timeout guidelines:
- **Fast path (cache, in-memory):** 5-50ms
- **Synchronous API call:** 100-500ms
- **Async job dispatch:** 1-5s
- **Batch job:** no timeout, monitor progress instead

### Retry with Backoff

Transient failures (network blips, brief overload) often resolve on their own. Retry with exponential backoff:

```python
import time, random

def retry_with_backoff(fn, max_attempts=5, base_delay=1.0):
    for attempt in range(max_attempts):
        try:
            return fn()
        except TransientError as e:
            if attempt == max_attempts - 1:
                raise
            # Exponential backoff: 1s, 2s, 4s, 8s, 16s
            delay = base_delay * (2 ** attempt)
            # Jitter: prevent thundering herd
            delay += random.uniform(0, delay * 0.1)
            time.sleep(delay)
```

**Idempotency is required for retries.** If a request is retried after a timeout (response never received), the server might have processed it. See [[idempotency|Idempotency]].

## Observability for Reliability

You can't fix what you can't see. Three pillars:

### Logs
- **Structured logs** (JSON) — machine-parseable, searchable
- **Correlation IDs** — trace a request across all services
- **Log levels** — ERROR for failures, WARN for degraded, INFO for significant events

### Metrics
- **RED method** for services: Rate (RPS), Errors (error rate), Duration (latency)
- **USE method** for resources: Utilization, Saturation, Errors

### Traces
- **Distributed tracing** — trace a request across service boundaries (OpenTelemetry, Jaeger, Zipkin)
- **Span context propagation** — trace ID passed via HTTP headers or message queue metadata

## MTTR and MTBF

Two key reliability measurements:

- **MTBF (Mean Time Between Failures)** — average time between failures. Higher is better.
- **MTTR (Mean Time To Recovery)** — average time to restore service after a failure. Lower is better.

```
Reliability = MTBF / (MTBF + MTTR)
```

Design to minimize MTTR:
- **Fast detection** — health checks, alerting
- **Fast failover** — automated, not manual
- **Fast rollback** — feature flags, blue-green deployments
- **Runbooks** — documented procedures so anyone can execute them

## Reliability Anti-Patterns

- **No timeouts** — slowest dependency caps your availability
- **Synchronous everything** — one slow call blocks the entire request
- **No circuit breakers** — cascade failure from a single misbehaving dependency
- **No redundancy** — single points of failure everywhere
- **No rollback plan** — failed deployment requires manual remediation
- **No health checks** — load balancer routes to dead instances
- **Ignoring correlated failures** — two components failing simultaneously (same AZ, same dependency)

## Related

- [[reliability-vs-availability|Reliability vs Availability]] — the distinction
- [[resilience|Resilience]] — specific fault-tolerance patterns
- [[idempotency|Idempotency]] — safe retry patterns
- [[disaster-recovery|Disaster Recovery]] — recovering from major outages
- [[availability|Availability]] — uptime guarantees

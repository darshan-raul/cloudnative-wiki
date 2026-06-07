---
title: Probes — Liveness, Readiness, Startup
tags: [kubernetes, workloads, probes, liveness, readiness, startup, reliability, core-concepts]
date: 2026-06-07
description: The kubelet's three tools for knowing whether a container is alive, ready, and started. Handler types, tunables, the startup-vs-liveness pattern, why liveness must not check external dependencies, and the failure modes that make probes the #1 cause of cascading outages.
---

# Probes — Liveness, Readiness, Startup

> https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/

**Probes** are the kubelet's way of knowing whether a container is **alive**, **ready**, and **started**. They're run by the **kubelet** (not the API server, not a Service, not a sidecar), directly against the container.

Misconfigured probes are the **#1 cause of cascading failures and Pod restart loops** in production. A liveness probe that hits a downstream dependency (DB, cache) will restart every Pod when the dependency briefly hiccups, which makes the situation worse, not better.

Get probes right and your app is resilient. Get them wrong and you've built a self-DoS system that takes itself down during the first sign of trouble.

## Table of Contents

1. [The Three Probe Types](#1-the-three-probe-types)
2. [How Probes Run](#2-how-probes-run)
3. [Probe Handlers](#3-probe-handlers)
4. [Tunables — Period, Timeout, Threshold](#4-tunables--period-timeout-threshold)
5. [The Startup vs Liveness Pattern](#5-the-startup-vs-liveness-pattern)
6. [Readiness — The Under-Appreciated Probe](#6-readiness--the-under-appreciated-probe)
7. [Probe Result → Pod Lifecycle](#7-probe-result--pod-lifecycle)
8. [The Liveness-Doesn't-Check-External-Deps Rule](#8-the-liveness-doesnt-check-external-deps-rule)
9. [Endpoint Routing and Probes](#9-endpoint-routing-and-probes)
10. [Patterns and Recipes](#10-patterns-and-recipes)
11. [Operational Recipes](#11-operational-recipes)
12. [Troubleshooting](#12-troubleshooting)
13. [Anti-Patterns](#13-anti-patterns)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)
15. [Related Notes](#15-related-notes)

---

## 1. The Three Probe Types

### The summary

| Probe | Question | If it fails | When to use |
|---|---|---|---|
| `startupProbe` | "Has the app finished starting?" | Disables other probes; container is killed if it never succeeds | Slow-starting apps (JVM warmup, big data loads) |
| `livenessProbe` | "Is the container still alive?" | Container is killed and restarted | Detect deadlocks, unrecoverable errors |
| `readinessProbe` | "Can the container serve traffic?" | Pod IP removed from Service endpoints (not restarted) | "Draining" or "warming up" or "not yet ready" |

### The mental model

```
App lifecycle:        Startup  ──────── Running ──────── Shutting down
                         │                  │                  │
Probe status:      startupProbe        livenessProbe        (no probe)
                   running             running              (container exits)
                         │                  │
                         │                  │
Probe result:    "not started yet"   "alive" / "dead"
                         │                  │
Action:          disable other       restart if dead /
                 probes; kill        remove from
                 if never           endpoints if
                 succeeds           readiness fails
```

### Why three probes

Each probe answers a different question, and conflating them is the source of most probe bugs:

- **Startup** is binary: the app has either finished starting or it hasn't. During startup, liveness and readiness are disabled.
- **Liveness** is binary: the app is either still working correctly or it's hung. Liveness failures trigger restarts.
- **Readiness** is fluid: the app might be ready for some traffic but not other. Readiness failures remove the Pod from Service routing (no restart).

A slow-starting JVM needs `startupProbe`. A long-running API that should always be available needs `livenessProbe`. A web app that needs to warm caches before serving traffic needs `readinessProbe`. Most production apps need all three.

### What each probe does NOT do

| Probe | Does NOT do |
|---|---|
| `startupProbe` | Does not check if the app is "correct" — only if it's started. After it succeeds, the kubelet runs liveness/readiness. |
| `livenessProbe` | Does not stop traffic — it restarts the container. Use readiness for traffic management. |
| `readinessProbe` | Does not restart the container — it just removes the Pod from Service endpoints. |

---

## 2. How Probes Run

### The kubelet, not the API server

Probes are run by the **kubelet** on the **node** where the Pod is scheduled. The kubelet:

1. Watches the Pod's container spec for probe definitions
2. Runs the probe handler (HTTP, TCP, exec, gRPC) at the configured `periodSeconds`
3. Compares the result to the `failureThreshold` and `successThreshold`
4. Updates the container's state in the Pod's status
5. Takes the configured action (kill container, remove from endpoints, etc.)

The kubelet does this **directly against the container's network namespace**. It does not go through the Service, through kube-proxy, or through any sidecar. It hits the container's IP on the configured port.

### The probe reaches the container, not the Pod

A common misconception: "the probe goes through the Service." It doesn't. The kubelet hits the container's network directly. This means:

- The probe is not affected by Service routing rules
- The probe is not affected by NetworkPolicy (wait, it kind of is — see below)
- The probe can reach the container even if no Service is defined

Wait, what about NetworkPolicy? NetworkPolicy is enforced by the CNI on the **Pod's network namespace**. The kubelet is on the **node's network namespace** (mostly). When the kubelet hits a container's port, the traffic is **inside the node**, not crossing a CNI datapath. So NetworkPolicy **does not** block probes.

This is by design — you don't want NetworkPolicy to accidentally make probes fail.

### The probe timing model

```
periodSeconds: how often the kubelet runs the probe
timeoutSeconds: how long the probe can take before it counts as a failure
failureThreshold: how many consecutive failures before action
successThreshold: how many consecutive successes before "ready"
```

Default values:

| Field | Default |
|---|---|
| `periodSeconds` | 10 |
| `timeoutSeconds` | 1 |
| `failureThreshold` | 3 |
| `successThreshold` | 1 (must be 1 for liveness/startup) |
| `initialDelaySeconds` | 0 (deprecated for slow apps — use `startupProbe`) |

For a default liveness probe:
- Runs every 10 seconds
- Times out after 1 second
- After 3 consecutive failures, the container is killed

So a hung container is restarted within ~30 seconds (3 × 10s period).

### When the probe starts

| Probe | When it starts |
|---|---|
| `startupProbe` | When the container starts |
| `livenessProbe` | After `startupProbe` succeeds (or immediately if no `startupProbe`) |
| `readinessProbe` | When the container starts, and continues throughout its life |

`initialDelaySeconds` is the wait time before the first probe. It applies to all three probe types, but it's deprecated for slow-starting apps. Use `startupProbe` instead.

---

## 3. Probe Handlers

Four handlers, each with a different way of checking the container's health.

### `httpGet` — HTTP request

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
    httpHeaders:
    - name: X-Probe
      value: kubelet
    scheme: HTTP         # default; HTTPS is also valid
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 1
  failureThreshold: 3
```

The kubelet sends a GET request to `http://<container-ip>:<port>/<path>`. The probe is **successful** if:

- The response status code is in the 200-399 range
- The response is received within `timeoutSeconds`

Anything outside 200-399 is a failure. This includes:

- 404 (handler not found)
- 500 (app error)
- Connection refused (app not listening)
- Timeout (app too slow)

#### Named ports

`port` can be a number (8080) or a name (http). If you use a name, the kubelet resolves it from the container's `ports` field:

```yaml
ports:
- name: http
  containerPort: 8080
livenessProbe:
  httpGet:
    path: /healthz
    port: http         # resolves to 8080
```

Named ports make probe configs survive container port changes.

#### Custom headers

```yaml
httpGet:
  path: /healthz
  port: 8080
  httpHeaders:
  - name: X-Health-Check
    value: kubelet
  - name: User-Agent
    value: kube-probe/1.30
```

Useful for:
- Differentiating probe traffic from real user traffic (in metrics/logs)
- Routing probes to a different code path in your app

### `tcpSocket` — TCP connect

```yaml
livenessProbe:
  tcpSocket:
    port: 3306
  initialDelaySeconds: 15
  periodSeconds: 10
```

The kubelet opens a TCP connection to `<container-ip>:<port>`. The probe is **successful** if the connection is established within `timeoutSeconds`.

A TCP probe verifies that **something is listening** on the port. It does **not** verify that the listener is healthy (e.g., a database that's accepting connections but failing every query).

**Use cases:**
- Databases (MySQL, PostgreSQL, Redis) — TCP confirms the server is up
- Apps that don't expose an HTTP endpoint
- Quick liveness checks where HTTP is overkill

**Don't use for:**
- Apps that need a deeper health check (use `httpGet` or `exec`)

### `exec` — Run a command

```yaml
livenessProbe:
  exec:
    command:
    - sh
    - -c
    - "cat /tmp/healthy | grep -q OK"
  initialDelaySeconds: 10
  periodSeconds: 5
```

The kubelet runs the command **inside the container's namespace**. The probe is **successful** if the command exits with status 0.

**Use cases:**
- Apps that don't expose HTTP or TCP
- Custom health checks that need to inspect files, env vars, or run scripts
- Apps with complex state (e.g., a queue consumer that's processing but not yet "ready")

**Caveats:**
- The command is run by the kubelet, **not** by your app. It runs in the container's namespace, but the kubelet determines success/failure.
- The command should be **fast** and **idempotent**. A long-running exec probe will time out.
- The command is **synchronous** in the kubelet. A probe that hangs will block subsequent probes.

### `gRPC` — gRPC health check (k8s 1.24+)

```yaml
livenessProbe:
  grpc:
    port: 9090
    service: my-service     # optional, defaults to the empty string
```

The kubelet uses the gRPC Health Checking Protocol to query the service. The probe is **successful** if the service responds with `SERVING`.

**Use cases:**
- gRPC services that implement the standard health check protocol
- Avoiding the overhead of HTTP probes on gRPC services

**Requirements:**
- The container must implement the gRPC Health Checking Protocol (most modern gRPC frameworks do)
- The kubelet's gRPC client must be able to reach the container (port must be open)

**Caveats:**
- TLS is not yet supported (k8s 1.30+ may add this)
- HTTP/2 must be supported by the container

---

## 4. Tunables — Period, Timeout, Threshold

### The full reference

| Field | Default | Meaning | Notes |
|---|---|---|---|
| `initialDelaySeconds` | 0 | Wait this long before the first probe | Deprecated for slow apps — use `startupProbe` |
| `periodSeconds` | 10 | How often the kubelet runs the probe | Higher = less load, slower detection |
| `timeoutSeconds` | 1 | Probe timeout | Raise for slow apps |
| `successThreshold` | 1 | Consecutive successes for "ready" | **Must be 1 for liveness/startup** |
| `failureThreshold` | 3 | Consecutive failures before action | Higher = more tolerant of blips |
| `terminationGracePeriodSeconds` | 30 | Time to wait for container to exit after liveness failure | Separate from the Pod's grace period |

### The math

For a default probe:
- Period: 10s
- Failure threshold: 3
- Detection time: up to 30s (3 × 10s) after the probe starts failing

For a tighter probe (e.g., critical service):
- Period: 2s
- Failure threshold: 3
- Detection time: up to 6s

For a more tolerant probe (e.g., background worker):
- Period: 30s
- Failure threshold: 3
- Detection time: up to 90s

### The trade-offs

| Tighter probes | Looser probes |
|---|---|
| Faster failure detection | Slower failure detection |
| More load on the kubelet | Less load on the kubelet |
| More sensitive to transient blips | More tolerant of transient blips |
| More risk of false positives | More risk of prolonged outages |
| Good for: critical, latency-sensitive | Good for: batch jobs, background workers |

### `successThreshold: 1` is enforced for liveness and startup

You can only fail your way out of being healthy for liveness and startup. You can't succeed your way out of being unhealthy. The API server enforces `successThreshold: 1` for these two probe types.

For readiness, `successThreshold: 1` is the default, but you can set it higher. For example, `successThreshold: 2` for readiness means the app needs to succeed twice in a row before being added back to Service endpoints. This can be useful for preventing flapping (Pod keeps getting added/removed).

---

## 5. The Startup vs Liveness Pattern

The most important probe pattern: **use `startupProbe` for anything that takes >30 seconds to start.**

### The problem with `initialDelaySeconds`

The legacy pattern was:

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 60   # wait 60 seconds before starting liveness
  periodSeconds: 10
  failureThreshold: 3
```

This has a fundamental problem: while the app is starting, the liveness probe is **not running**. If the app takes 90 seconds to start, the liveness probe starts at 60s. If the app is hung, the liveness probe might not catch it.

Also, `initialDelaySeconds` is a single fixed value. If the app sometimes starts in 30s and sometimes in 90s, you have to pick the worst case.

### The startup pattern

The modern pattern:

```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30
  periodSeconds: 10    # 30 × 10 = 300s (5 minutes) to start
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  periodSeconds: 10
  failureThreshold: 3
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  periodSeconds: 5
  failureThreshold: 2
```

The flow:
1. Container starts. `startupProbe` runs.
2. While `startupProbe` is failing, `livenessProbe` and `readinessProbe` are **disabled**.
3. If `startupProbe` succeeds, the kubelet starts running `livenessProbe` and `readinessProbe`.
4. If `startupProbe` never succeeds within `failureThreshold × periodSeconds`, the container is killed.

This gives slow-starting apps (JVMs, big data loads) up to 5 minutes to start, without false-positive liveness failures.

### The math for `startupProbe`

`failureThreshold × periodSeconds = max startup time`

| Use case | failureThreshold | periodSeconds | Total |
|---|---|---|---|
| Fast app (Node, Go) | 12 | 5 | 60s |
| Medium app (Python) | 30 | 10 | 300s (5 min) |
| Slow app (JVM with warmup) | 60 | 10 | 600s (10 min) |

Tune to your app's actual startup time. A fast app doesn't need 5 minutes; a slow JVM might need 10.

### The startup + readiness interaction

While `startupProbe` is running:
- The Pod is **not Ready** (`Ready: False`)
- The Pod is **not in Service endpoints** (traffic is not routed)
- The Pod is "starting"

This is correct behavior. You don't want traffic routed to a Pod that's still initializing. Once `startupProbe` succeeds, `readinessProbe` takes over, and the Pod is added to Service endpoints when `readinessProbe` succeeds.

### The startup + liveness interaction

While `startupProbe` is running:
- `livenessProbe` is **disabled**
- The container is not killed (even if the liveness probe would fail)
- Only `startupProbe` runs

After `startupProbe` succeeds:
- `livenessProbe` starts running
- If `livenessProbe` fails, the container is killed

This is by design. You don't want a slow-starting app to be killed by the liveness probe before it has a chance to start.

---

## 6. Readiness — The Under-Appreciated Probe

Most teams set `livenessProbe` and skip `readinessProbe`. This is a mistake. Readiness is the most operationally useful probe.

### What readiness does

When a readiness probe fails:
- The Pod IP is **removed from the Service endpoints** (no traffic routed to it)
- The Pod is **not restarted**
- The Pod is still "alive" (liveness can succeed or fail independently)
- The Pod is still in the cluster (you can `kubectl exec` into it)

When a readiness probe succeeds again:
- The Pod IP is **added back to the Service endpoints**
- Traffic is routed again

This is the right tool for:

- **"Not yet ready" during startup** — the app is starting but not yet serving traffic
- **"Draining" during shutdown** — return 503 from `/ready` on SIGTERM to stop accepting new traffic while finishing in-flight requests
- **"Cascading dependencies"** — a pod that depends on a cache returns "not ready" until the cache is warm
- **"Maintenance mode"** — temporarily take a Pod out of rotation for debugging

### The minimum viable readiness probe

If you do nothing else with probes, **at minimum set a readinessProbe**. Without it:

```yaml
# A Pod without readinessProbe
# The Pod is added to Service endpoints the moment the container accepts a TCP connection
# This can be 10+ seconds before the app is actually serving requests
# Result: 500 errors for users during the gap
```

With a minimal readiness probe:

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  periodSeconds: 5
  failureThreshold: 2    # be quick to mark unready
```

The app defines `/ready` to return 200 only when it's truly ready to serve traffic. The kubelet polls this; until it returns 200, the Pod is not in the Service endpoints.

### Readiness for graceful shutdown

The classic pattern for graceful shutdown:

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  periodSeconds: 5
  failureThreshold: 1
terminationGracePeriodSeconds: 60
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 10"]
```

The flow:
1. Pod is marked for deletion (e.g., during a rolling update)
2. **As soon as the deletion is requested, the Pod's `Ready` condition becomes `False`** (the kubelet does this for terminating Pods)
3. The Service endpoints controller removes the Pod from the Service
4. The kubelet sends SIGTERM after `preStop` sleep
5. The app has `terminationGracePeriodSeconds` to finish in-flight requests

Wait, step 2 isn't quite right. Let me correct it:

Actually, when a Pod is marked for deletion, the endpoints controller removes the Pod from the Service endpoints. The Pod is removed from the Service **before** SIGTERM is sent. But there's a race: in-flight requests can still arrive at the Pod for a few seconds.

To handle this race, the app should:
- Have a `preStop` hook that sleeps (giving the endpoint removal time to propagate)
- AND/OR return 503 from `/ready` on SIGTERM (so any new requests get rejected)

Most modern apps just use the `preStop` sleep, which is sufficient in most cases.

### Readiness for warm-up

A cache layer that needs to load data before serving traffic:

```python
# App initialization
def warm_cache():
    for key in critical_keys:
        cache.set(key, fetch_from_db(key))
    app.route('/ready')(lambda: 'OK')   # /ready returns 200 only after warmup
    app.route('/healthz')(lambda: 'OK')  # /healthz is independent of warmup

warm_cache()
app.run(port=8080)
```

The liveness probe (`/healthz`) returns 200 as soon as the app is running, even if the cache isn't warm. The readiness probe (`/ready`) returns 200 only after the cache is loaded. The Pod is not in Service endpoints until the cache is warm.

### Readiness and rolling updates

During a rolling update, the old Pods are kept until the new Pods are ready. The Deployment waits for the new Pod's `Ready: True` before marking the old Pod for deletion.

If the new Pod's readiness probe fails (e.g., the app takes 30s to warm up), the rolling update stalls. The Deployment's `progressDeadlineSeconds` (default 600s) bounds how long it will wait.

---

## 7. Probe Result → Pod Lifecycle

### The state machine

```
                  ┌──────────────────────────────┐
                  │                                │
                  ▼                                │
        ┌──────────────────┐                      │
        │ Container Waiting │  (image pull, etc.)  │
        └─────────┬────────┘                      │
                  │                               │
                  │ main process starts           │
                  ▼                               │
        ┌──────────────────┐                      │
        │ startupProbe     │                      │
        │ running          │                      │
        │ liveness:        │                      │
        │   disabled       │                      │
        │ readiness:       │                      │
        │   running, not   │                      │
        │   ready          │                      │
        └─────────┬────────┘                      │
                  │                               │
                  │ startupProbe succeeds         │
                  ▼                               │
        ┌──────────────────┐                      │
        │ livenessProbe    │                      │
        │ + readinessProbe │                      │
        │ running          │                      │
        └─────────┬────────┘                      │
                  │                               │
       ┌──────────┼──────────┐                    │
       │          │          │                    │
       ▼          ▼          ▼                    │
   liveness   readiness  lifecycle                │
   fails:     fails:     event                    │
   restart    no         (sigterm)                │
   container  traffic                            │
       │          │          │                    │
       └──────────┴──────────┘                    │
                  │                               │
                  ▼                               │
        ┌──────────────────┐                      │
        │ Container        │                      │
        │ Terminated       │──────────────────────┘
        └──────────────────┘
```

### The three failure modes

| Probe failure | Action | Reversible? |
|---|---|---|
| `startupProbe` fails | Container is killed (after `failureThreshold × periodSeconds`) | No (Pod restarts) |
| `livenessProbe` fails | Container is killed and restarted (after `failureThreshold × periodSeconds`) | No (Pod restarts) |
| `readinessProbe` fails | Pod IP is removed from Service endpoints (no restart) | Yes (Pod can become ready again) |

### Container restart vs Pod restart

Important distinction:

- **Container restart**: the same Pod, same UID, same IP. Just the container is killed and restarted.
- **Pod restart**: a new Pod is created (e.g., by a Deployment, ReplicaSet). New UID, new IP.

A liveness failure causes a **container restart** (not a Pod restart). The Pod stays around. The kubelet kills the container and starts a new one in the same Pod.

A Pod failure (e.g., the node dies) causes a **Pod restart** — a new Pod is created by the controller.

### Restart count and backoff

The kubelet tracks the number of container restarts. If a container keeps crashing:

- The kubelet applies exponential backoff: 10s, 20s, 40s, ..., 300s
- The Pod's `status.containerStatuses[].restartCount` increases
- After the Pod's `backoffLimit` (which applies to the kubelet, default 6), the Pod is marked Failed

For Pods in a Deployment, the Deployment controller sees the Failed Pod and creates a new one. The new Pod starts fresh (no backoff state from the old Pod).

---

## 8. The Liveness-Doesn't-Check-External-Deps Rule

This is the most important rule in the probes note. Repeat it:

> **Liveness probes must check internal health only. They must NOT check external dependencies (DB, cache, downstream APIs).**

### The anti-pattern

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  # The /healthz handler does:
  #   1. Check app is alive
  #   2. Query the database
  #   3. Check the cache
  #   4. Return 200 if all OK
```

When the database hiccups:
1. `/healthz` returns 500 (because step 2 failed)
2. The kubelet marks the Pod as unhealthy
3. The kubelet kills the container
4. The Deployment creates a new Pod
5. The new Pod's `/healthz` also returns 500 (DB is still down)
6. The new Pod is also killed
7. All Pods are restarted in a tight loop
8. **The service is now completely down** because every Pod is restarting

The DB hiccup caused a **cascading failure**. The liveness probe turned a partial outage into a total outage.

### The fix

Liveness should check **internal** state only:

```python
# /healthz — checks internal state only
@app.route('/healthz')
def healthz():
    # Is the process alive? Is the event loop responsive?
    # Is the GC healthy? Is the HTTP server accepting connections?
    return 'OK', 200
```

Readiness should check **external** dependencies:

```python
# /ready — checks external dependencies
@app.route('/ready')
def ready():
    if not db.is_reachable():
        return 'DB not reachable', 503
    if not cache.is_warm():
        return 'Cache not warm', 503
    return 'OK', 200
```

When the DB hiccups:
1. `/ready` returns 503
2. The Pod is removed from Service endpoints
3. No new traffic is routed to the Pod
4. The Pod is **not restarted** (liveness is still OK)
5. When the DB recovers, `/ready` returns 200
6. The Pod is added back to Service endpoints

The DB hiccup caused a **graceful degradation**, not a cascading failure. Some Pods are temporarily out of rotation, but the service stays up.

### The summary

| Probe | Checks | Why |
|---|---|---|
| `livenessProbe` | Internal state only | Restarting on external failure makes the failure worse |
| `readinessProbe` | Internal state + external dependencies | Removing from rotation is the right action for "can't serve traffic" |
| `startupProbe` | "Has the app started?" | Anything else is wrong |

### The exception

There's one case where liveness might check an external dep: a **critical local resource** that the app absolutely cannot function without. For example, a local socket or a tmpfs mount. If that resource is missing, the app is permanently broken, and a restart won't help.

But for **most** external dependencies (DB, cache, downstream services), use readiness, not liveness.

---

## 9. Endpoint Routing and Probes

### The kubelet, not the Service

Probes are run by the kubelet directly against the container. They do **not** go through the Service.

This means:
- A Service with no endpoints is fine — the probe still works
- A Service with a different port mapping doesn't affect the probe
- A NetworkPolicy that denies Service traffic doesn't affect the probe

### The endpoints controller

The Service endpoints controller watches Pods. When a Pod's `Ready: True`, the controller adds the Pod IP to the Service's endpoints. When `Ready: False`, the controller removes it.

The Pod's `Ready` condition is the AND of:
- All containers are `Ready` (i.e., their readiness probes are succeeding)
- The Pod is not being deleted

So a failing readiness probe → `Ready: False` → endpoints controller removes the Pod from the Service → no traffic.

This is a **pull-based** system. The kubelet doesn't push readiness state to the Service; the endpoints controller pulls it from the Pod's status.

### The timing

There's a small lag between the readiness probe failing and the Pod being removed from the Service. The lag is the time for the endpoints controller to observe the change and update the Service. In practice, this is a few seconds.

During this lag, traffic can still arrive at the Pod. If the readiness probe is failing because the app is "not yet ready," the app should be able to handle the incoming traffic (or return 503).

For faster removal, you can lower the `readinessProbe.periodSeconds` and `failureThreshold`. The endpoints controller polls the Pod's status every 10 seconds by default, so even with a 1-second probe period, the lag is at least 10 seconds.

### The `publishNotReadyAddresses` Service flag

By default, a Service's endpoints list only contains Pods that are `Ready: True`. To include all Pods regardless of readiness, set:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  publishNotReadyAddresses: true
  selector:
    app: my-app
  ports:
  - port: 8080
    targetPort: 8080
```

This is useful for:
- Stateful applications (e.g., a database cluster) where the "ready" Pod is the leader and the "not ready" Pods are replicas
- Applications where the client handles routing (e.g., a custom load balancer that knows about all Pods)

For most cases, leave this `false`.

---

## 10. Patterns and Recipes

### Pattern 1: Standard web app (startup + liveness + readiness)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  template:
    spec:
      containers:
      - name: app
        image: myorg/web:2.1
        ports:
        - containerPort: 8080
        startupProbe:
          httpGet:
            path: /healthz
            port: 8080
          failureThreshold: 30
          periodSeconds: 5       # 30 × 5 = 150s to start
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          periodSeconds: 10
          failureThreshold: 3    # 30s detection time
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          periodSeconds: 5
          failureThreshold: 2    # 10s detection time
        lifecycle:
          preStop:
            exec:
              command: ["sh", "-c", "sleep 10"]
      terminationGracePeriodSeconds: 60
```

### Pattern 2: Slow-starting JVM

```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 60
  periodSeconds: 10    # 60 × 10 = 600s (10 min) to start
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  periodSeconds: 10
  failureThreshold: 3
```

The startup probe gives the JVM up to 10 minutes to warm up. After that, liveness takes over.

### Pattern 3: Database with TCP probe

```yaml
startupProbe:
  tcpSocket:
    port: 5432
  failureThreshold: 30
  periodSeconds: 5     # 150s to start
livenessProbe:
  tcpSocket:
    port: 5432
  periodSeconds: 30
  timeoutSeconds: 5
  failureThreshold: 3
readinessProbe:
  exec:
    command: ["pg_isready", "-U", "postgres"]
  periodSeconds: 10
  failureThreshold: 3
```

For a database:
- Liveness: TCP probe (something is listening on the port)
- Readiness: `pg_isready` (the database is actually accepting connections)
- Startup: TCP probe with longer threshold

### Pattern 4: Worker with exec probe

```yaml
livenessProbe:
  exec:
    command:
    - sh
    - -c
    - "test -f /tmp/worker-alive"
  periodSeconds: 30
  failureThreshold: 3
```

The worker writes a heartbeat file every 10 seconds. If the file is missing for 90 seconds, the worker is restarted. This catches deadlocks where the worker process is alive but stuck.

### Pattern 5: gRPC service

```yaml
startupProbe:
  grpc:
    port: 9090
    service: my-service
  failureThreshold: 30
  periodSeconds: 5
livenessProbe:
  grpc:
    port: 9090
    service: my-service
  periodSeconds: 10
  failureThreshold: 3
readinessProbe:
  grpc:
    port: 9090
    service: my-service
  periodSeconds: 5
  failureThreshold: 2
```

Requires the gRPC service to implement the gRPC Health Checking Protocol.

### Pattern 6: Zero-downtime deployment with graceful shutdown

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  periodSeconds: 5
  failureThreshold: 1
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 10"]    # let endpoints removal propagate
terminationGracePeriodSeconds: 60
```

The `preStop` sleep + readiness probe + grace period combine to ensure in-flight requests are completed before the container is killed.

---

## 11. Operational Recipes

### Recipe 1: Test a probe locally

```bash
# Get the Pod IP
POD_IP=$(kubectl get pod <pod> -o jsonpath='{.status.podIP}')

# Test the probe (port-forward first, or use the Pod IP)
kubectl port-forward <pod> 8080:8080 &
sleep 1
curl -i http://localhost:8080/healthz
```

If `/healthz` returns 200, the kubelet will mark the probe as successful. If 500 or timeout, the probe fails.

### Recipe 2: Check probe status

```bash
# Get the Pod's full status
kubectl describe pod <pod>
# Look at "Conditions" and "Containers" sections

# Get just the probe status
kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[].ready}'
# Returns: true / false

# Last probe time
kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[].lastProbeTime}'
```

### Recipe 3: Manually fail a readiness probe

To test the readiness flow, you can override the probe at runtime... actually you can't. The probe is defined in the Pod spec. To test, you need to:

- Make the app's `/ready` endpoint return 503 (e.g., set a config flag)
- Or temporarily edit the probe (e.g., point it to a non-existent endpoint) and apply

For a non-destructive test, use a sidecar container with a custom health endpoint. Or just deploy a test Pod with a probe pointing to a known-failing endpoint.

### Recipe 4: Disable a probe temporarily

You can't disable a probe in the spec. You can:

- Set `failureThreshold` very high (so the probe effectively never fails)
- Change the probe handler to a no-op (e.g., `exec: ["true"]` for liveness, which always succeeds)
- Set the `periodSeconds` very high (so the probe runs rarely)

To apply, edit the Deployment:

```bash
kubectl edit deployment <name>
# Change periodSeconds: 86400 (1 day) to effectively disable
```

### Recipe 5: See why a Pod was restarted

```bash
kubectl describe pod <pod>
# Look at "Last State" of the container
# It will show:
#   Terminated
#   Reason: Completed / Error / OOMKilled
#   Exit Code: 0 / 1 / 137
#   Started: <time>
#   Finished: <time>
```

For liveness-restarted containers, the reason is usually `Error` with exit code 1 (or whatever the app exits with on shutdown).

### Recipe 6: See probe events

```bash
kubectl get events --field-selector involvedObject.name=<pod>
# Look for events about the probe
```

The kubelet doesn't always emit events for probe failures. For a more detailed view, use the kubelet logs (if you have access).

---

## 12. Troubleshooting

### Symptom: Pod keeps restarting

```bash
kubectl describe pod <pod>
# Look at "Last State" and "Restart Count"
```

Common causes:

- **Liveness probe failing** — the app returns 500 from `/healthz` (or the probe times out)
- **App crashes on startup** — exit code 1, no probe
- **App uses too much memory** — OOMKilled
- **Init container fails** — see [[Kubernetes/concepts/L03-workloads/08-init-containers|08 — Init Containers]]

For probe-related restarts, check:
- The `/healthz` endpoint exists and returns 200
- The probe's `periodSeconds` and `timeoutSeconds` are appropriate
- The probe's `failureThreshold` isn't too tight

### Symptom: Pod is Running but not Ready

```bash
kubectl describe pod <pod>
# Look at "Conditions" — the "Ready" condition should be False
```

Common causes:

- **Readiness probe failing** — the app returns 503 from `/ready`
- **Container is still starting** — startupProbe is still running
- **A dependency is down** — DB, cache, etc.

For readiness issues, check the same things as liveness. Readiness failures don't restart the container, so the Pod stays Running.

### Symptom: Rolling update is stuck

```bash
kubectl rollout status deployment/<name>
# Shows "Waiting for deployment rollout to finish: N out of M new replicas updated"
```

Common causes:

- **New Pods' readiness probes are failing** — the new version is not ready
- **New Pods' startup probes are slow** — the new version takes longer to start
- **`progressDeadlineSeconds` exceeded** — the Deployment has been waiting too long

Check the new Pods:

```bash
kubectl get pods -l app=<name>
# Look for new replicas in Pending or CrashLoopBackOff
```

### Symptom: Service endpoints are empty

```bash
kubectl get endpoints <service-name>
# Shows the list of Pod IPs
```

If empty:
- No Pods match the Service selector
- All matching Pods have `Ready: False` (readiness failing)

Check the Pods:

```bash
kubectl get pods -l app=<name>
kubectl describe pod <pod>
# Look at the readiness probe status
```

### Symptom: Probe timing is too tight

A probe that's too sensitive:
- `periodSeconds: 1` + `failureThreshold: 1` = a single missed probe kills the container
- `timeoutSeconds: 1` with a slow `/healthz` = the probe times out

Fix:
- Raise `periodSeconds` and `failureThreshold`
- Raise `timeoutSeconds` if the app's `/healthz` is slow
- Make the `/healthz` endpoint faster (no DB queries, no heavy work)

### Symptom: Probe is too slow to detect failures

A probe that takes too long to detect failure:
- `periodSeconds: 60` + `failureThreshold: 3` = 3 minutes to detect a failure
- This might be fine for batch workers, but bad for user-facing services

Fix:
- Lower `periodSeconds` (e.g., 5-10s)
- Lower `failureThreshold` (e.g., 2-3)
- Optimize the probe handler (e.g., use TCP instead of HTTP for simple liveness)

### Symptom: Memory grows when probes are added

If adding probes makes the app's memory grow, the probe handler itself is heavy. For example, `/healthz` does a database query or a complex computation. The probe runs every 10s, so the app is doing this work 6 times per minute.

Fix:
- Make the probe handler lightweight
- Use TCP for liveness instead of HTTP (just check the port is open)
- Cache the result of expensive health checks

---

## 13. Anti-Patterns

### Anti-pattern 1: Liveness probe that hits the database

```yaml
# ❌ WRONG
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  # /healthz queries the database and returns 200 only if DB is reachable
```

When the DB hiccups, every Pod's liveness probe fails, every Pod restarts, the service is completely down. **Don't do this.**

Use readiness for DB-dependent health.

### Anti-pattern 2: `failureThreshold: 1` with `periodSeconds: 1`

```yaml
# ❌ WRONG
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  periodSeconds: 1
  failureThreshold: 1
```

A single missed probe kills the container. Way too aggressive for production. A transient blip (network, GC pause, slow disk) causes a restart.

Use at least `failureThreshold: 3` and `periodSeconds: 10` (default) for most apps.

### Anti-pattern 3: Probe that does heavy work

```python
# ❌ WRONG
@app.route('/healthz')
def healthz():
    # Queries the database
    db.execute("SELECT 1")
    # Loads a config file
    config = load_config_from_disk()
    # Runs a complex computation
    return 'OK' if everything_ok() else 'FAIL', 200 if everything_ok() else 500
```

The probe runs every 10s. If `everything_ok()` is slow, the probe times out, and the container is restarted.

Keep probe handlers **lightweight**. A simple "is the process alive" check is enough.

### Anti-pattern 4: Probe that returns success unconditionally

```python
# ❌ WRONG
@app.route('/healthz')
def healthz():
    return 'OK', 200     # always 200
```

The probe is a no-op. The container is never restarted, even if the app is hung. This is worse than no probe at all.

If you don't want a probe to do anything, don't set one. The kubelet will fall back to the container's process state.

### Anti-pattern 5: Slow probe on a fast-changing app

```yaml
# ❌ WRONG (for a critical API)
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  periodSeconds: 60
  failureThreshold: 5
# Detection time: 5 minutes
```

For a critical API, 5 minutes of detection is too slow. The service is down for 5 minutes before anything is restarted.

Use `periodSeconds: 5-10` and `failureThreshold: 2-3` for most production apps.

### Anti-pattern 6: Skipping readinessProbe

```yaml
# ❌ WRONG
# Pod has livenessProbe but no readinessProbe
```

Without readiness, the Pod is in Service endpoints the moment it accepts a TCP connection. This can be seconds before the app is actually serving traffic. Result: 500 errors for users.

Always set at least a minimal readinessProbe.

### Anti-pattern 7: Readiness probe that never succeeds

```python
# ❌ WRONG
@app.route('/ready')
def ready():
    if not external_service_healthy():
        return 'NOT READY', 503
    # external_service_healthy() always returns False in dev
    return 'READY', 200
```

The Pod is never added to Service endpoints. No traffic ever reaches it.

If you want to take a Pod out of rotation temporarily, return 503 from `/ready` and the Pod is removed. But to put it back, return 200.

### Anti-pattern 8: Probes that depend on the app's main thread

```python
# ❌ WRONG
# A single-threaded app where /healthz is handled by the same thread that processes requests
@app.route('/healthz')
def healthz():
    return 'OK', 200

@app.route('/process')
def process():
    # Long-running task
    do_heavy_work()
    return 'Done', 200
```

The probe can't run while the app is processing a long request. The probe times out, the kubelet restarts the container mid-request.

Use a multi-threaded app server (Gunicorn, uvicorn workers, etc.) so probes can run on a separate thread.

### Anti-pattern 9: Different ports for the app and probes

```yaml
# ❌ Confusing
ports:
- containerPort: 8080     # main app
livenessProbe:
  httpGet:
    port: 9090             # probe on a different port
```

The probe must match the app's port. If the app listens on 8080, the probe should hit 8080. If you want a separate "management" port for probes, document it clearly.

### Anti-pattern 10: `successThreshold > 1` for liveness or startup

The API server rejects this. You can only fail your way out of being healthy for liveness and startup.

For readiness, `successThreshold > 1` is allowed but rarely useful. The default of 1 is fine for most cases.

---

## 14. Gotchas and Common Mistakes

### Probe semantic gotchas

- **Liveness probe = restart, not "remove from service."** Use readiness for "remove from service."
- **Readiness probe = remove from service, not "restart."** Use liveness for "restart."
- **Startup probe = "still starting", not "liveness while starting."** Use it to give slow apps time.
- **Probes run from the kubelet, not the API server or Service.** The probe hits the container's IP directly.

### Timing gotchas

- **Detection time = `periodSeconds × failureThreshold`.** Default 30s. Tune based on the app's criticality.
- **`timeoutSeconds: 1` is too tight for many apps.** The probe might time out due to GC pauses, network blips, or slow disks. Raise it to 2-5s for safety.
- **A probe that times out counts as a failure.** The handler doesn't have to return a non-200 status; a network timeout is also a failure.

### Configuration gotchas

- **`initialDelaySeconds` is deprecated for slow apps.** Use `startupProbe`.
- **`successThreshold` must be 1 for liveness and startup.** The API server enforces this.
- **`failureThreshold: 1` is too aggressive.** A single blip kills the container.
- **Probes are not inherited from another container.** Each container has its own probes.

### Lifecycle gotchas

- **The kubelet, not your app, decides when a probe is "failing."** The app's `/healthz` returning 500 is interpreted as a failure, even if the app is doing what it's supposed to (returning 500 to indicate a problem).
- **A failing readiness probe doesn't terminate in-flight requests.** It just stops new ones. Use `preStop` for in-flight request draining.
- **The endpoints controller polls the Pod's status every 10 seconds by default.** There's a small lag between readiness failure and the Pod being removed from the Service.

### Resource gotchas

- **Probes add load to the kubelet.** 1000 Pods with `periodSeconds: 1` = 1000 probes/second on the kubelet. Use reasonable `periodSeconds`.
- **Probes hit the container's IP, not the Service IP.** This is faster (no kube-proxy) but bypasses some routing logic.
- **Heavy probe handlers can cause CPU spikes.** If the probe does work (e.g., a DB query), the work happens every `periodSeconds`.

### Multi-container gotchas

- **Each container has its own probes.** The Pod is Ready only when **all** containers are Ready.
- **A native sidecar (k8s 1.29+) can have probes.** The sidecar's probes don't affect the main container's probes.
- **An init container has no probes.** Init must exit 0; there's no "ready" state.

### The "probe was added and now the app restarts constantly" gotcha

A team adds a liveness probe that returns 200 for "ok" and 500 for "not ok." The app's `/healthz` returns 500 when the DB is down. The liveness probe fails, the container restarts, the new container's `/healthz` also returns 500, the new container is also killed, etc.

This is the most common probe misconfiguration. **Liveness must check internal state only.**

### The "probe was added and now traffic is intermittent" gotcha

A team adds a readiness probe that returns 503 when the app is "warming up" (e.g., loading config from a remote service). The probe runs every 5s. If the remote service is slow, the readiness probe fails intermittently, and the Pod is repeatedly added/removed from the Service.

Fix: make the readiness check lightweight and don't depend on external services for "is the Pod ready to serve traffic."

### The "probe times out and the app is fine" gotcha

The probe times out, the container is killed, but the app is actually fine. The probe handler is slow (heavy work, slow DB, complex computation). Fix the probe handler.

Or: the probe's `timeoutSeconds` is too low. Raise it.

### The "probe is HTTP but the app is gRPC" gotcha

The probe is configured for HTTP (`httpGet`), but the app is gRPC. The HTTP probe hits `/healthz` on port 8080, but the gRPC app doesn't have an HTTP endpoint. The probe always fails.

For gRPC apps, use the `grpc` probe handler (k8s 1.24+) or add an HTTP shim that returns 200.

### The "readiness probe is too strict" gotcha

The readiness probe checks "all dependencies reachable, all caches warm, all configs loaded." The Pod is "not ready" for the first 30 seconds of its life. During a rolling update, the old Pod is taken down before the new Pod is ready, causing downtime.

Fix: make the readiness probe more lenient. "Is the HTTP server up and the app responsive?" is enough. Defer deeper checks to liveness or background.

---

## 15. Related Notes

| Topic | Note |
|---|---|
| Pods (probes are a container field) | [[Kubernetes/concepts/L03-workloads/01-pods\|01 — Pods]] |
| Lifecycle hooks (preStop) | [[Kubernetes/concepts/L03-workloads/01-pods\|01 — Pods]] (Section 6) |
| Deployments (rolling updates) | [[Kubernetes/concepts/L03-workloads/03-deployments\|03 — Deployments]] |
| Init containers (no probes) | [[Kubernetes/concepts/L03-workloads/08-init-containers\|08 — Init Containers]] |
| Multi-container Pods (probes per container) | [[Kubernetes/concepts/L03-workloads/09-multi-container-pods\|09 — Multi-Container Pods]] |
| Services and Endpoints (readiness drives routing) | [[Kubernetes/concepts/L04-services-networking/02-services\|L04 — Services]] |
| Resource requests and limits | [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|L06 — Resource Requests and Limits]] |
| PDBs (voluntary disruption) | [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling\|L06 — Scaling]] |

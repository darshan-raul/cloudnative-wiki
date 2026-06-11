---
title: Multi-Container Pods — Sidecar, Ambassador, Adapter
tags: [kubernetes, workloads, multi-container, sidecar, ambassador, adapter, core-concepts]
date: 2026-06-07
description: The three patterns for putting multiple containers in one Pod. Network and IPC sharing, when to use each pattern, native sidecars (k8s 1.29+), and when NOT to use multiple containers.
---

# Multi-Container Pods — Sidecar, Ambassador, Adapter

> https://kubernetes.io/docs/concepts/workloads/pods/#workload-resources-for-managing-pods

A **multi-container Pod** is a Pod that runs more than one container. All containers in the Pod share the **same network namespace**, **IPC namespace**, **volumes**, and **lifecycle**, and they are scheduled onto the **same node**.

The Kubernetes docs recognize three standard patterns for multi-container Pods: **sidecar**, **ambassador**, and **adapter**. Knowing them by name helps you describe a design without a 5-minute explanation.

The most common pattern in production is the **sidecar** — a helper container that extends or enhances the main app. Service mesh sidecars (Envoy, Linkerd), log shippers, metrics exporters, and Dapr all use this pattern.

## Table of Contents

1. [Why Multi-Container Pods Exist](#1-why-multi-container-pods-exist)
2. [What Containers in a Pod Share](#2-what-containers-in-a-pod-share)
3. [The Three Patterns](#3-the-three-patterns)
4. [Pattern 1: Sidecar](#4-pattern-1-sidecar)
5. [Pattern 2: Ambassador](#5-pattern-2-ambassador)
6. [Pattern 3: Adapter](#6-pattern-3-adapter)
7. [Native Sidecars (k8s 1.29+)](#7-native-sidecars-k8s-129)
8. [Inter-Container Communication](#8-inter-container-communication)
9. [Lifecycle and Ordering](#9-lifecycle-and-ordering)
10. [Resource and Security Considerations](#10-resource-and-security-considerations)
11. [When NOT to Use Multiple Containers](#11-when-not-to-use-multiple-containers)
12. [Operational Recipes](#12-operational-recipes)
13. [Troubleshooting](#13-troubleshooting)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)
15. [Related Notes](#15-related-notes)

---

## 1. Why Multi-Container Pods Exist

### The problem

Some workloads need two things running together: the main app, and a helper. The helper is not a separate service; it lives with the app.

A few examples:

- A web app that writes structured logs to a file. A log shipper (Fluent Bit) reads the file and forwards to a central backend.
- An app that makes outbound HTTP calls. A service mesh proxy (Envoy) handles mTLS, retries, and observability for those calls.
- A legacy app that talks to `localhost:8080`. An ambassador container intercepts on `localhost:8080` and forwards to the real backend (which may be in-cluster or external).
- An app that emits logs in a custom format. An adapter container reads the logs and rewrites them in JSON / OTLP.

In all four cases, the helper must run **with the app**, on the same node, in the same network namespace, sharing the same lifecycle. A separate Deployment won't work — the helper wouldn't see the app's files, network, or lifecycle.

### Why not just one container

Some teams try to put everything in one container. This breaks down quickly:

- **The helper has different dependencies.** A log shipper might need `fluent-bit`; the app might need a JVM. Combining them in one image is ugly.
- **The helper has different security requirements.** A proxy might need `NET_ADMIN`; the app should run as non-root.
- **The helper has a different release cadence.** You want to update the log shipper without rebuilding the app image.
- **The helper is shared infrastructure.** A service mesh sidecar is injected by the mesh, not part of the app.

Multi-container Pods handle all four cleanly.

### Why not separate Deployments

Some teams try to put the helper in a separate Deployment. This also breaks down:

- **The helper needs the app's local files.** Two Deployments on the same node don't share volumes by default.
- **The helper needs the app's network namespace.** Two Pods have different IPs.
- **The helper needs to start with the app and die with the app.** Two Deployments have independent lifecycles.
- **The helper is per-app-instance.** Sidecars are 1:1 with the app, not "one per cluster."

A multi-container Pod enforces all four: same node, same network ns, same volumes, same lifecycle.

---

## 2. What Containers in a Pod Share

### The shared-namespace model

```
┌────────────────────────────────────────────────────────────┐
│ Pod                                                          │
│                                                              │
│  Network namespace  (one IP, one set of ports)               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   app        │  │   sidecar    │  │   adapter    │       │
│  │              │  │              │  │              │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                              │
│  IPC namespace  (System V IPC, POSIX shared memory)          │
│                                                              │
│  UTS namespace  (one hostname)                               │
│                                                              │
│  PID namespace  (optionally shared, see below)              │
│                                                              │
│  Volumes  (mounted into containers at their mountPaths)     │
│                                                              │
│  Cgroup  (resource accounting is per-container)              │
│                                                              │
│  Lifecycle  (started together, terminated together)          │
│                                                              │
│  Node  (always scheduled onto the same node)                │
└────────────────────────────────────────────────────────────┘
```

### What's shared

| Resource | Shared | Notes |
|---|---|---|
| **Network namespace** | ✅ | Same IP, same `localhost`, same ports (conflict!) |
| **IPC namespace** | ✅ | System V IPC, POSIX shared memory |
| **UTS namespace** | ✅ | Same hostname (the Pod's name) |
| **Volumes** | ✅ | Mounts at any path in any container |
| **Lifecycle** | ✅ | Started together, terminated together |
| **Node** | ✅ | Always on the same node |
| **CPU/memory cgroup** | ❌ | Each container has its own cgroup |
| **PID namespace** | ⚠️ | Optional — see `shareProcessNamespace` |
| **Security context** | ❌ | Each container has its own |

### The `shareProcessNamespace` flag

By default, containers in a Pod do **not** see each other's processes. The `app` container can't `ps aux` and see the `sidecar`. To share the PID namespace:

```yaml
spec:
  shareProcessNamespace: true
  containers:
  - name: app
    # ...
  - name: sidecar
    # ...
```

With this flag, both containers see the same process list. Use it for:

- A sidecar that needs to signal the main process (e.g., `kill -USR1 <pid>` for log rotation)
- A debug sidecar that monitors the main process

For most cases, leave it `false` to keep containers isolated.

### The port conflict gotcha

Containers in a Pod share the network namespace, which means they share the same port space. If `app` binds `:8080` and `sidecar` tries to bind `:8080`, the second one gets "address already in use."

This is sometimes useful (both containers intentionally use the same port), sometimes a bug (typo or forgotten overlap). Be explicit about ports in each container's `ports:` field.

---

## 3. The Three Patterns

The official k8s docs define three standard patterns. They're not types — there's no `kind: Sidecar`. They're patterns you implement by writing a Pod with multiple containers.

```
┌──────────────────────────────────────────┐
│ Pod                                       │
│  ┌──────────┐    ┌──────────────────┐   │
│  │   app    │    │   helper          │   │
│  │          │    │                   │   │
│  │  main    │◀──▶│  extends,         │   │
│  │  work    │    │  proxies,         │   │
│  │          │    │  or normalizes    │   │
│  └──────────┘    └──────────────────┘   │
│                                           │
│  What is the helper's role?               │
│                                           │
│  Extends the app  ──▶ Sidecar             │
│  Proxies for the app ──▶ Ambassador       │
│  Normalizes the app ──▶ Adapter           │
└──────────────────────────────────────────┘
```

### Pattern summary

| Pattern | Helper's role | Direction | Examples |
|---|---|---|---|
| **Sidecar** | Extends or enhances the main app | Both directions, often pull (e.g., reads logs) | Log shipper, metrics exporter, service mesh proxy |
| **Ambassador** | Proxies network traffic for the main app | Egress (app → ambassador → real destination) | Legacy migration, broker abstraction |
| **Adapter** | Normalizes the main app's output | Ingress (app emits → adapter reads and rewrites) | Log format conversion, metrics normalization |

The same container can fit multiple patterns. A Fluent Bit log shipper is both a sidecar (extends the app's observability) and an adapter (converts logs to a standard format). The categorization is about the helper's primary role.

---

## 4. Pattern 1: Sidecar

The most common pattern. A helper container that extends or enhances the main app container.

### Mental model

```
┌──────────────────────────────────────────┐
│ Pod                                       │
│  ┌──────────┐    ┌──────────────────┐   │
│  │   app    │    │    sidecar        │   │
│  │          │    │  (helper)         │   │
│  │  writes  │───▶│  reads /          │   │
│  │  logs    │    │  processes /      │   │
│  │  metrics │    │  forwards         │   │
│  └──────────┘    └──────────────────┘   │
│                                           │
│  The sidecar "helps" the app.            │
│  Without the app, the sidecar is useless.│
└──────────────────────────────────────────┘
```

### Common examples

| Sidecar | What it does |
|---|---|
| **Fluent Bit / Promtail / Vector** | Reads the app's logs (stdout or shared volume) and ships to a central backend |
| **Istio / Linkerd / Consul Connect proxy** | Service mesh sidecar; handles mTLS, retries, observability for the app's traffic |
| **node-exporter / Datadog agent** | (Usually a DaemonSet, not a sidecar, but can be a sidecar for per-app metrics) |
| **Dapr sidecar** | Provides service invocation, state management, pub/sub, etc. for the app |
| **OpenTelemetry collector** | Receives traces/metrics from the app and exports to a backend |
| **Vault agent** | Fetches and rotates secrets, mounts them as files in the app |
| **cert-manager's csi-driver-spiffe** | Mounts SPIFFE identities as files in the app |
| **AWS LB controller pod webhook** | Registers Pods with an external load balancer on startup |

### Example: log shipper sidecar

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-sidecar
spec:
  containers:
  - name: app
    image: myorg/app:2.1
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
    - name: shared-config
      mountPath: /etc/app
      readOnly: true
  - name: log-shipper
    image: fluent/fluent-bit:3.0
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
      readOnly: true
    - name: shared-config
      mountPath: /etc/fluent-bit
      readOnly: true
  volumes:
  - name: logs
    emptyDir: {}
  - name: shared-config
    configMap:
      name: app-and-shipper-config
```

The app writes logs to `/var/log/app/`. The log shipper reads from the same path (read-only) and forwards to the central backend. The shared `emptyDir` is the channel between them.

### Example: service mesh sidecar (Istio)

Istio injects an Envoy sidecar automatically. The injection is done by a mutating webhook at admission time, so the Pod spec is augmented before the Pod is created.

The injected Pod looks like:

```yaml
spec:
  containers:
  - name: app
    image: myorg/app:2.1
    # ... app config ...
  - name: istio-proxy
    image: docker.io/istio/proxyv2:1.20
    args:
    - proxy
    - sidecar
    - --domain
    - $(POD_NAMESPACE).svc.cluster.local
    - --proxyLogLevel=warning
    - --proxyComponentLogLevel=misc:error
    - --log_output_level=default:info
    env:
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: POD_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
    securityContext:
      capabilities:
        drop:
        - ALL
      runAsNonRoot: false
      privileged: false
      readOnlyRootFilesystem: true
    # ... a lot more config ...
```

The Istio sidecar handles all of the app's inbound and outbound traffic, applying mTLS, retries, circuit breaking, and observability. The app is unaware of the sidecar — it just sees network traffic flowing.

### Why sidecars are so common

Sidecars are the **standard way to add cross-cutting concerns** to a Pod without modifying the app:

- **Observability** (logs, metrics, traces) — most apps don't have a perfect observability story out of the box. A sidecar adds it.
- **Security** (mTLS, secrets, identity) — a sidecar handles the cryptographic work so the app doesn't have to.
- **Resilience** (retries, circuit breaking, rate limiting) — a sidecar applies policies consistently.
- **Traffic management** (routing, load balancing, canaries) — a sidecar implements these without app changes.

---

## 5. Pattern 2: Ambassador

A container that **proxies network traffic** for the main app, abstracting the outside world.

### Mental model

```
┌──────────────────────────────────────────────────┐
│ Pod                                                │
│  ┌──────────┐         ┌──────────────────┐       │
│  │   app    │────────▶│   ambassador      │       │
│  │          │  local  │  (proxy)          │       │
│  │ talks to │  host   │                   │       │
│  │ localhost│         │  forwards to:     │       │
│  │          │         │  - in-cluster svc │       │
│  │          │         │  - external URL   │       │
│  │          │         │  - decision based │       │
│  │          │         │    on env / config│       │
│  └──────────┘         └──────────────────┘       │
│                                                     │
│  The ambassador "represents" the outside world     │
│  to the app.                                        │
└──────────────────────────────────────────────────┘
```

The app talks to `localhost:8080`. The ambassador decides where to forward that traffic. The app doesn't need to know if the destination is local, in-cluster, or external.

### When to use

The ambassador pattern is most useful for:

1. **Legacy migration** — the app code is hard to change, but you want to move from an old backend to a new one. The ambassador abstracts the change.
2. **Environment abstraction** — dev vs. prod, on-prem vs. cloud. The ambassador picks the right destination based on environment variables.
3. **Multi-cloud / failover** — the ambassador chooses between backends in different clouds.

### Example: Kafka ambassador

The app wants to publish events. It talks to `localhost:9092`. The ambassador forwards to a real Kafka broker, chosen at startup based on a config.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-ambassador
spec:
  containers:
  - name: app
    image: myorg/app:2.1
    command: ["./app", "--broker=localhost:9092"]
  - name: kafka-ambassador
    image: myorg/kafka-ambassador:1.0
    command: ["./ambassador", "--listen=localhost:9092", "--target=$(BROKER_URL)"]
    env:
    - name: BROKER_URL
      value: kafka-prod.internal:9092
```

If you want to change the broker, edit the ambassador's `BROKER_URL` env var, not the app's code.

### Example: dynamic backend selection

The ambassador picks the destination based on a label or annotation:

```yaml
- name: db-ambassador
  image: myorg/db-ambassador:1.0
  command: ["./ambassador", "--listen=localhost:5432"]
  # Reads the target from a label on the Pod or a ConfigMap
  # The app stays the same; the ambassador routes
```

### Why ambassadors are less common than sidecars

Modern apps usually use **Service discovery** (DNS, Service Mesh, etc.) to find backends. The ambassador pattern is useful when the app's code can't easily be changed to use service discovery. In greenfield code, prefer:

- Configure the app with a real Service name (e.g., `db.prod.svc.cluster.local:5432`)
- Or use a service mesh to abstract the destination

---

## 6. Pattern 3: Adapter

A container that **normalizes the main app's output**. The app emits logs / metrics / events in some format; the adapter reads them and rewrites in a standard format.

### Mental model

```
┌──────────────────────────────────────────────────┐
│ Pod                                                │
│  ┌──────────┐         ┌──────────────────┐       │
│  │   app    │────────▶│   adapter         │       │
│  │          │         │  (normalizer)     │       │
│  │  emits   │ stdout  │  reads stdout /   │       │
│  │  custom  │ ──────▶ │  shared volume /  │       │
│  │  format  │         │  / shared stdout  │       │
│  │          │         │                   │       │
│  │          │         │  emits JSON, OTLP │       │
│  └──────────┘         └──────────────────┘       │
│                                                     │
│  The adapter "translates" the app's output          │
│  into a standard format.                            │
└──────────────────────────────────────────────────┘
```

### When to use

The adapter pattern is most useful for:

1. **Legacy apps with non-standard output** — the app writes logs in a custom format; the adapter converts to JSON.
2. **Heterogeneous apps in a single observability backend** — different apps emit different formats; the adapter normalizes.
3. **Tracing** — the app emits spans in a custom format; the adapter converts to OTLP.

### Example: log format adapter

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-adapter
spec:
  containers:
  - name: app
    image: myorg/legacy-app:1.0     # writes "INFO: started" format logs
  - name: log-adapter
    image: fluent/fluent-bit:3.0
    # Reads the app's stdout (via shared volume or tail)
    # Converts to JSON
    # Forwards to Loki
```

The app's logs go to a shared `emptyDir` volume. The adapter tails the log file, parses the custom format, and emits JSON.

### Sharing stdout

The default `kubectl logs` shows the app container's stdout. A sidecar (or adapter) that wants to see the app's stdout has a few options:

1. **Shared `emptyDir` volume** — the app writes to `/var/log/app/`, the adapter reads from there. The adapter doesn't see the actual stdout stream.

2. **Streaming from `/proc/<pid>/fd/1`** — the adapter reads the app's stdout file descriptor. This requires `shareProcessNamespace: true` and the right permissions. Complex.

3. **Sidecar pattern with `kubectl logs --all-containers`** — both containers log to stdout; you use `--all-containers` to see all of them. The sidecar is just another log source.

For most cases, option 1 (shared volume) is the simplest.

### Why adapters are less common in cloud-native

Modern apps usually emit JSON logs directly. The adapter pattern is useful for:

- Legacy apps you can't change
- Apps with custom log formats that need normalization
- Apps that emit in a non-standard protocol (e.g., StatsD, custom binary)

If you're writing a new app, emit JSON / OTLP / structured logs from the start. No adapter needed.

---

## 7. Native Sidecars (k8s 1.29+)

In k8s 1.29, a new feature was added: **native sidecars** via `restartPolicy: Always` on a regular container.

### The old way

```yaml
spec:
  initContainers:
  - name: log-shipper
    image: fluent/fluent-bit:3.0
    # The container exits when the work is "done"
    # But you want it to keep running
    # Workaround: tail -f /dev/null
    command: ["sh", "-c", "fluent-bit -c /etc/fluent-bit.conf & sleep infinity"]
```

This works but has problems:
- The init shows as `Terminated` (because it "completed")
- The kubelet doesn't know if the sidecar is healthy
- No probes, no proper lifecycle

### The new way (k8s 1.29+)

```yaml
spec:
  containers:
  - name: app
    image: myorg/app:2.1
    # ... main app ...
  - name: log-shipper
    image: fluent/fluent-bit:3.0
    restartPolicy: Always    # native sidecar primitive
    command: ["fluent-bit", "-c", "/etc/fluent-bit.conf"]
```

### What a native sidecar gets

1. **Ordered start**: the sidecar starts **before** the main app containers
2. **Ordered stop**: the sidecar stops **after** the main app containers, ensuring in-flight logs are flushed
3. **Proper status reporting**: the sidecar is treated like a regular container, with normal `Running` / `Waiting` / `Terminated` states
4. **Probes work**: `livenessProbe`, `readinessProbe`, `startupProbe` are all supported

### The migration path

If you have an init container that does `sleep infinity` after starting the actual sidecar, convert it to a native sidecar:

```yaml
# Before
initContainers:
- name: log-shipper
  image: fluent/fluent-bit:3.0
  command: ["sh", "-c", "fluent-bit -c /etc/fluent-bit.conf & sleep infinity"]

# After (k8s 1.29+)
containers:
- name: log-shipper
  image: fluent/fluent-bit:3.0
  restartPolicy: Always
  command: ["fluent-bit", "-c", "/etc/fluent-bit.conf"]
```

For more on init containers and the relationship to native sidecars, see [[Kubernetes/concepts/L03-workloads/08-init-containers|08 — Init Containers]].

---

## 8. Inter-Container Communication

### `localhost` (network)

Since containers share a network namespace, they reach each other on `localhost`:

```yaml
containers:
- name: app
  image: myorg/app:2.1
  ports:
  - containerPort: 8080
- name: cache-warmup
  image: myorg/warmer:1.0
  command: ["sh", "-c", "curl -fs http://localhost:8080/warmup"]
```

The cache-warmup talks to the app on `localhost:8080`. No DNS lookup, no Service routing. Direct.

### Shared volumes

```yaml
containers:
- name: writer
  image: myorg/writer:1.0
  volumeMounts:
  - name: shared
    mountPath: /shared
  command: ["sh", "-c", "while true; do echo $(date) >> /shared/log; sleep 1; done"]
- name: reader
  image: myorg/reader:1.0
  volumeMounts:
  - name: shared
    mountPath: /shared
    readOnly: true
  command: ["sh", "-c", "tail -f /shared/log"]
volumes:
- name: shared
  emptyDir: {}
```

The writer appends to `/shared/log`; the reader tails it. Both see the same file because they share the volume.

### IPC

Containers share System V IPC and POSIX shared memory:

```python
# Container A: creates a shared memory segment
import sysv_ipc
shm = sysv_ipc.SharedMemory(key=42, size=1024, flags=sysv_ipc.IPC_CREAT)

# Container B: reads the same segment
import sysv_ipc
shm = sysv_ipc.SharedMemory(key=42)
```

This is rarely used in practice (modern apps use files, sockets, or shared databases instead), but it's available.

### Signals (with `shareProcessNamespace`)

With `shareProcessNamespace: true`, one container can signal another:

```yaml
spec:
  shareProcessNamespace: true
  containers:
  - name: app
    # ...
  - name: reloader
    image: myorg/reloader:1.0
    command: ["sh", "-c", "while true; do sleep 60; kill -USR1 1; done"]
    # Periodically sends SIGUSR1 to PID 1 (the app's main process)
```

This is a niche pattern. Most apps use HTTP endpoints (e.g., POST `/reload`) for cross-container signaling, which doesn't require PID sharing.

---

## 9. Lifecycle and Ordering

### The start order

Containers start in **declared order** in the manifest:

```yaml
containers:
- name: app                # starts first
- name: log-shipper        # starts second
- name: metrics-exporter   # starts third
```

But "starts" doesn't mean "is ready." The kubelet starts them in order, but each one takes time to initialize. The next container may start before the previous is fully ready.

To enforce strict ordering, use:

1. **Native sidecars (k8s 1.29+)** — guaranteed ordered start/stop
2. **Readiness probes** — wait for the previous container to be `Ready` before considering the Pod `Ready`
3. **App's own retry logic** — the app waits for the sidecar to be reachable

For most use cases, "containers start in declared order, no strict waiting" is fine.

### The stop order

Containers stop in **reverse declared order**:

```yaml
containers:
- name: app                # stopped last
- name: log-shipper        # stopped second-to-last
- name: metrics-exporter   # stopped first
```

This is generally good: the helper sidecars are stopped first, after which the app can finish its work (flush logs, drain connections). But it's also **not guaranteed** — the kubelet sends SIGTERM to all containers in parallel, then waits for the grace period.

For strict stop order, use **native sidecars (k8s 1.29+)**, which guarantee ordered stop.

### Pre-stop and graceful shutdown

Each container can have its own `preStop` hook:

```yaml
containers:
- name: app
  lifecycle:
    preStop:
      exec:
        command: ["sh", "-c", "sleep 5"]   # drain traffic
- name: log-shipper
  lifecycle:
    preStop:
      exec:
        command: ["sh", "-c", "fluent-bit -c /etc/fluent-bit.conf --quit"]  # flush
```

The order of `preStop` execution is the same as the order of container start: app first, then log shipper. But the kubelet doesn't wait between them — they run in parallel.

For a clean shutdown, the app's `preStop` should drain traffic, and the log shipper's `preStop` should flush its buffers. Both should complete within the Pod's `terminationGracePeriodSeconds`.

---

## 10. Resource and Security Considerations

### Per-container resources

Each container has its own resource requests and limits. They are summed for the Pod's effective request:

```yaml
containers:
- name: app
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
- name: log-shipper
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
```

Effective Pod `requests`: 250m CPU, 320Mi memory. The Pod is scheduled onto a node that has at least that much available.

For full coverage, see [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|L06 — Resource Requests and Limits]].

### The shared cgroup, independent limits

Containers in a Pod share the **node's cgroup hierarchy** (Linux control groups) but each has its own cgroup slice. The kubelet enforces each container's limits separately:

- If `app` exceeds its memory limit, `app` is OOMKilled. The log-shipper is unaffected.
- If `app` exceeds its CPU limit, `app` is throttled. The log-shipper is unaffected.

The kernel's OOM killer picks the container with the highest memory usage when the Pod is under pressure. This is usually `app` (which is the heavy one), but it could be the sidecar if the sidecar is the leaky one.

### Per-container security contexts

Each container can have its own `securityContext`:

```yaml
initContainers: []   # no init
containers:
- name: app
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
- name: log-shipper
  securityContext:
    runAsNonRoot: false           # fluent-bit needs root to read /var/log
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
      add: ["DAC_READ_SEARCH"]    # needed to read arbitrary files
```

The app runs as non-root; the log shipper can run as root (because it needs to read `/var/log`). The Pod has a mix of security postures, and that's fine.

For full coverage, see [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context|L07 — Security Context]].

### The shared security context gotcha

A multi-container Pod has **one** Pod-level `securityContext`, but each container can override it. The "effective" security context for a container is the merge of the Pod-level and the container-level. Container-level takes precedence.

A compromised sidecar can affect the main app. They're in the same network namespace, same volumes, same node. Don't put a sidecar you don't trust in the same Pod as your app.

---

## 11. When NOT to Use Multiple Containers

### The cost of multi-container

Multi-container Pods share the same node, network, and lifecycle. This is a **tight coupling**. Use it only when the helper truly belongs with the app.

### When to use a separate Deployment

| Need | Why NOT multi-container |
|---|---|
| Helper scales independently | Two Deployments, two HPA configs |
| Helper has different security profile | Two Pods, different ServiceAccounts, different NetworkPolicies |
| Helper has different release cadence | Two Deployments, independent rollouts |
| Helper is shared across many apps | A separate Deployment, possibly a DaemonSet |

### The "sidecar sprawl" anti-pattern

A Pod with 5+ sidecars is a code smell. Each sidecar adds:

- Resource overhead (CPU, memory, network)
- Security surface (each sidecar can be compromised)
- Startup time
- Complexity (which sidecar does what?)

If your Pod has 5 sidecars, ask: do they all really need to be sidecars? Could some be a separate Deployment? Could the app integrate the functionality directly?

### When to use a DaemonSet instead

A helper that's needed on **every node** (e.g., node-exporter, log shipper for node-level logs) is a DaemonSet, not a sidecar. The sidecar pattern is for per-app helpers, not per-node helpers.

### When to use a Service

A helper that's a shared service (e.g., a central API, a database) is a Service + Deployment, not a sidecar. The sidecar pattern is for helpers that are 1:1 with the app.

### Decision tree

```
Need a helper for an app?
│
├── Helper is 1:1 with the app instance (logs, metrics, mesh)?
│   └── Yes ──▶ Sidecar (or native sidecar k8s 1.29+)
│
├── Helper is a network proxy for the app (legacy, dynamic backend)?
│   └── Yes ──▶ Ambassador
│
├── Helper normalizes the app's output (custom format → standard)?
│   └── Yes ──▶ Adapter
│
├── Helper is 1:1 with the node (node metrics, log shipping)?
│   └── Yes ──▶ DaemonSet
│
├── Helper is a shared service (DB, cache, broker)?
│   └── Yes ──▶ Separate Deployment + Service
│
└── Helper scales independently / has different lifecycle?
    └── Yes ──▶ Separate Deployment
```

---

## 12. Operational Recipes

### Recipe 1: Log shipper sidecar

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-log-shipper
spec:
  containers:
  - name: app
    image: myorg/app:2.1
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  - name: fluentbit
    image: fluent/fluent-bit:3.0
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
      readOnly: true
    - name: fb-config
      mountPath: /fluent-bit/etc
      readOnly: true
  volumes:
  - name: logs
    emptyDir: {}
  - name: fb-config
    configMap:
      name: fluent-bit-config
```

### Recipe 2: Service mesh sidecar (Istio)

Istio uses a mutating webhook to inject the sidecar automatically. To opt a namespace in:

```bash
kubectl label namespace my-namespace istio-injection=enabled
```

Then every Pod created in `my-namespace` has the Istio sidecar injected. You don't write the sidecar config yourself.

### Recipe 3: OpenTelemetry sidecar

```yaml
containers:
- name: app
  image: myorg/app:2.1
  env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: http://localhost:4318
- name: otel-collector
  image: otel/opentelemetry-collector-contrib:0.95.0
  args: ["--config=/etc/otel/config.yaml"]
  ports:
  - containerPort: 4318    # OTLP HTTP
  - containerPort: 4317    # OTLP gRPC
  volumeMounts:
  - name: otel-config
    mountPath: /etc/otel
volumes:
- name: otel-config
  configMap:
    name: otel-collector-config
```

The app exports telemetry to `localhost:4318`; the sidecar receives, batches, and exports to the backend.

### Recipe 4: Native sidecar (k8s 1.29+)

```yaml
spec:
  containers:
  - name: app
    image: myorg/app:2.1
  - name: log-shipper
    image: fluent/fluent-bit:3.0
    restartPolicy: Always    # native sidecar primitive
    lifecycle:
      preStop:
        exec:
          command: ["sh", "-c", "fluent-bit -c /etc/fluent-bit.conf --quit"]
```

### Recipe 5: Dapr sidecar

Dapr uses the same multi-container pattern but is typically managed by the Dapr control plane:

```yaml
containers:
- name: app
  image: myorg/app:2.1
- name: daprd
  image: docker.io/daprio/daprd:1.12
  args:
  - --app-id=my-app
  - --app-port=8080
  - --dapr-http-port=3500
  - --dapr-grpc-port=50001
  - --components-path=/components
  - --log-level=info
```

The app talks to Dapr on `localhost:3500` (HTTP) or `localhost:50001` (gRPC). Dapr handles service invocation, state, pub/sub, secrets, etc.

### Recipe 6: Vault agent sidecar (secrets as files)

```yaml
containers:
- name: app
  image: myorg/app:2.1
  volumeMounts:
  - name: vault-secrets
    mountPath: /etc/secrets
    readOnly: true
- name: vault-agent
  image: hashicorp/vault:1.15
  args:
  - agent
  - -config=/etc/vault/config.hcl
  volumeMounts:
  - name: vault-config
    mountPath: /etc/vault
  - name: vault-secrets
    mountPath: /etc/secrets
volumes:
- name: vault-secrets
  emptyDir:
    medium: Memory    # secrets in tmpfs, not disk
  - name: vault-config
    configMap:
      name: vault-agent-config
```

Vault Agent authenticates to Vault, fetches secrets, and writes them to `/etc/secrets/`. The app reads them as files. The secrets are in memory (`medium: Memory`), not on disk.

---

## 13. Troubleshooting

### Symptom: Sidecar won't start

```bash
kubectl describe pod <pod>
# Look at the sidecar's status
```

Common causes:

- **Image pull error** — bad image tag, registry auth
- **CrashLoopBackOff** — the sidecar's process is crashing (check logs)
- **Volume mount error** — the sidecar is waiting for a volume that doesn't exist

### Symptom: App can't reach the sidecar

The app tries to connect to `localhost:<port>` but fails.

Common causes:

- **The sidecar isn't listening on that port** — check the sidecar's config
- **The port is bound by the app** — port conflict
- **The app is starting before the sidecar** — add a wait/retry in the app
- **NetworkPolicy blocks the connection** — localhost traffic usually isn't filtered, but check

```bash
# From inside the Pod, check what ports are listening
kubectl exec <pod> -c app -- netstat -tlnp
kubectl exec <pod> -c app -- ss -tlnp
```

### Symptom: Sidecar logs are missing

```bash
# Get logs from a specific container
kubectl logs <pod> -c <sidecar-name>

# Get logs from all containers
kubectl logs <pod> --all-containers=true

# Previous instance (if it restarted)
kubectl logs <pod> -c <sidecar-name> --previous
```

### Symptom: Sidecar uses too much memory

The sidecar's memory usage is high. Check:

- Is the sidecar leaking? (Memory grows over time → bug)
- Is the sidecar under-provisioned? (Check `resources.limits`)
- Is the sidecar processing too much data? (Rate-limit, batch, or split)

```bash
# Memory usage per container
kubectl top pod <pod> --containers
```

### Symptom: Sidecar blocks Pod shutdown

The Pod takes a long time to terminate because the sidecar is slow to stop.

Fix:

- Add a `preStop` hook that flushes the sidecar
- Reduce `terminationGracePeriodSeconds` (but be careful not to kill the app mid-shutdown)
- Use native sidecars (k8s 1.29+) for guaranteed ordered stop

### Symptom: Init container instead of sidecar

You wrote a sidecar as an init container:

```yaml
initContainers:
- name: log-shipper
  command: ["sh", "-c", "fluent-bit -c /etc/fluent-bit.conf & sleep infinity"]
```

This works but the sidecar shows as `Terminated` (the init "completed"). If you're on k8s 1.29+, convert to a native sidecar. Otherwise, accept the workaround.

### Symptom: Sidecar was injected unexpectedly

A mutating webhook (e.g., Istio, Linkerd, Vault Agent Injector) injected a sidecar. To see what was injected:

```bash
kubectl get pod <pod> -o yaml | less
# Look for containers that aren't in your manifest
```

To opt out:

- **Istio**: don't label the namespace with `istio-injection=enabled`
- **Linkerd**: don't annotate the workload with `linkerd.io/inject: enabled`
- **Vault Agent**: don't annotate the workload with `vault.hashicorp.com/agent-inject: true`

---

## 14. Gotchas and Common Mistakes

### Lifecycle gotchas

- **Containers start in declared order, but no waiting is enforced.** The next container may start before the previous is ready.
- **Containers stop in reverse declared order, but no waiting is enforced.** The kubelet sends SIGTERM to all in parallel.
- **The `sleep infinity` workaround for sidecars-as-init is fragile.** Use native sidecars (k8s 1.29+) if possible.

### Port gotchas

- **Port conflicts are silent.** If two containers try to bind the same port, the second one fails to start. Check `kubectl describe pod` for events.
- **`containerPort` is informational.** Declaring a `containerPort` doesn't actually publish the port. The port is published when something binds to it.

### Resource gotchas

- **Each container's resources are summed for scheduling.** A 2-container Pod with 1 CPU each = 2 CPU reserved. Plan accordingly.
- **A leaky sidecar OOMKills the entire Pod.** Memory leaks in sidecars are particularly nasty because they take down the app too.
- **Per-container limits are enforced independently.** A sidecar that exceeds its memory limit is OOMKilled. The app is unaffected.

### Security gotchas

- **A compromised sidecar has access to the app's network and volumes.** Sidecar = trusted code. Don't put untrusted code in a sidecar.
- **`shareProcessNamespace: true` exposes process info.** Use it only when necessary.
- **`hostNetwork: true` and multi-container Pods are a high-risk combination.** The Pod's traffic bypasses NetworkPolicy.

### Performance gotchas

- **Sidecar startup adds to the Pod's startup time.** A Pod with 3 sidecars takes 3x the time to be Ready.
- **A sidecar that does heavy work (e.g., compression, encryption) adds latency** to the app's network calls.
- **Sidecars with persistent connections (e.g., mesh proxies) hold sockets.** Restarting the app doesn't tear them down; the sidecar does.

### Ordering gotchas

- **There's no "wait for sidecar to be ready" in the Pod spec.** The app's own readiness logic must include this.
- **Init containers are sequential, sidecars are parallel.** Use init containers for ordered setup, sidecars for parallel helpers.
- **Native sidecars (k8s 1.29+) get ordered start/stop.** Regular sidecars don't.

### "All the patterns at once" gotcha

Some Pods have:
- 2 init containers
- 3 main containers
- 1 native sidecar
- 1 ambassador
- 1 adapter

This is too much. Refactor:
- Init containers for setup (one is usually enough)
- Sidecars for the cross-cutting concerns (logs, metrics, mesh)
- Drop the ambassador and adapter if they're not strictly needed
- Move shared helpers to a DaemonSet

### "Sidecar with the wrong image" gotcha

A sidecar uses a different image than the app, with different OS libraries, different update cadence. Pin the image with a tag, not `:latest`. Use a specific version (e.g., `fluent/fluent-bit:3.0.1`) to avoid surprise upgrades.

### "The sidecar fails and the app keeps running" gotcha

By default, the Pod's restart policy is `Always`. If the sidecar crashes, the Pod is restarted (all containers). The app is also restarted, even though it was running fine. This is usually what you want, but it can be surprising.

If you want only the sidecar to restart (not the app), set the sidecar's `restartPolicy` differently. But this requires the sidecar to be a native sidecar (k8s 1.29+) or a regular container with custom logic. Not common.

### "The shared volume is a race condition" gotcha

Two containers writing to the same file in a shared volume can corrupt the file. If both containers append, you need a write-append protocol that the kernel's `O_APPEND` flag provides (each write is atomic up to a certain size).

For most use cases, use separate files per container. Don't share a single file for writes.

### "init container as a sidecar" anti-pattern

The classic mistake:

```yaml
initContainers:
- name: log-shipper
  command: ["sh", "-c", "fluent-bit -c /etc/fluent-bit.conf & sleep infinity"]
```

This works, but:
- The init shows as `Terminated` (not `Running`)
- The kubelet doesn't know if the sidecar is healthy
- No probes
- `kubectl logs -c log-shipper` works, but `kubectl get pod` doesn't show it as "Running"

If you're on k8s 1.29+, use a native sidecar. Otherwise, accept the workaround or upgrade.

---

## 15. Related Notes

| Topic | Note |
|---|---|
| Pods (multi-container is a Pod field) | [[Kubernetes/concepts/L03-workloads/01-pods\|01 — Pods]] |
| Init containers (run before app) | [[Kubernetes/concepts/L03-workloads/08-init-containers\|08 — Init Containers]] |
| Probes (liveness, readiness) | [[Kubernetes/concepts/L03-workloads/10-probes\|10 — Probes]] |
| DaemonSet (per-node helpers) | [[Kubernetes/concepts/L03-workloads/05-daemonset\|05 — DaemonSet]] |
| Resource requests and limits | [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|L06 — Resource Requests and Limits]] |
| Security context | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context\|L07 — Security Context]] |
| Service mesh (Istio/Linkerd) | [[Kubernetes/guides/networking/service-mesh/README\|Guides — Service Mesh]] |
| Pod networking (CNI, Pod IPs) | [[Kubernetes/concepts/L04-services-networking/01-networking\|L04 — Networking]] |

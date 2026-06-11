---
title: Init Containers — Ordered Setup Before the App
tags: [kubernetes, workloads, init-containers, pods, core-concepts]
date: 2026-06-07
description: The specialized containers that run before app containers. Ordering, failure semantics, resource interaction, native sidecars (k8s 1.29+), and the patterns that make init containers the right answer for setup, gating, and migration.
---

# Init Containers — Ordered Setup Before the App

> https://kubernetes.io/docs/concepts/workloads/pods/init-containers/

**Init containers** are specialized containers that run **before the app containers** in a Pod. They run **one at a time**, in declared order, and must **succeed** before the next one starts. After all init containers have completed, the app containers start.

Init containers are the right answer for setup, waiting, and gating tasks that need to happen **once**, **before** the main workload. They're simpler than sidecars (which run alongside the app for the Pod's lifetime) and more powerful than a "wait for X" script in the app itself.

## Table of Contents

1. [The Init Container Mental Model](#1-the-init-container-mental-model)
2. [How Init Containers Run](#2-how-init-containers-run)
3. [Manifest Anatomy](#3-manifest-anatomy)
4. [Common Patterns](#4-common-patterns)
5. [Init Containers vs Sidecars](#5-init-containers-vs-sidecars)
6. [Init Containers vs the App's Own Setup](#6-init-containers-vs-the-apps-own-setup)
7. [Resource Interaction](#7-resource-interaction)
8. [Failure Semantics and Restart](#8-failure-semantics-and-restart)
9. [Native Sidecars (k8s 1.29+)](#9-native-sidecars-k8s-129)
10. [Operational Recipes](#10-operational-recipes)
11. [Troubleshooting](#11-troubleshooting)
12. [Gotchas and Common Mistakes](#12-gotchas-and-common-mistakes)
13. [Related Notes](#13-related-notes)

---

## 1. The Init Container Mental Model

### The contract

> "Before the app starts, run these containers in order. Each must succeed. If any fails, the Pod is not Ready until the issue is resolved."

Init containers are **declarative setup**. You specify the setup steps as a list, and Kubernetes runs them in order. If you change the init container spec (e.g., new image), the Pod is recreated and the init containers run again.

```
┌──────────────────────────────────────────────────────────┐
│ Pod lifecycle                                             │
│                                                            │
│  ┌─────────────────┐                                       │
│  │ Init container 1│  wait for DB                          │
│  │   (must exit 0) │──┐                                    │
│  └─────────────────┘  │                                   │
│                       ▼                                    │
│  ┌─────────────────┐                                       │
│  │ Init container 2│  run migrations                      │
│  │   (must exit 0) │──┐                                    │
│  └─────────────────┘  │                                   │
│                       ▼                                    │
│  ┌─────────────────┐                                       │
│  │ Init container 3│  fetch config from S3                │
│  │   (must exit 0) │──┐                                    │
│  └─────────────────┘  │                                   │
│                       ▼                                    │
│  ┌─────────────────┐  ┌─────────────────┐                │
│  │ App container 1 │  │ App container 2 │ (sidecar, etc.) │
│  │   (main)        │  │                 │                 │
│  └─────────────────┘  └─────────────────┘                 │
│                                                            │
│  ── Pod lifecycle (one of these can fail and restart) ── │
└──────────────────────────────────────────────────────────┘
```

### Why init containers exist

Some setup work has to happen before the app starts but doesn't fit cleanly into the app's own initialization:

- **The setup is a different image** (e.g., `busybox` for `nc -z` waiting, but the app is a JVM)
- **The setup has different security constraints** (e.g., needs `NET_ADMIN` to manipulate iptables, but the app should not)
- **The setup should not run inside the app's restart cycle** (a flaky wait shouldn't keep restarting the app)
- **The setup is reusable** across many apps (e.g., a generic "wait for DB" pattern)

Init containers handle all four cleanly.

### What init containers are NOT

- Not for long-running helpers (use a sidecar)
- Not for app initialization (do that in the app)
- Not for one-off setup that the user can do manually (e.g., `kubectl exec` to run a setup script)
- Not a substitute for proper application design (don't use init containers to paper over a broken startup)

---

## 2. How Init Containers Run

### The execution model

```
1. Pod is created (or recreated due to spec change)
2. kubelet starts the Pod sandbox (the network namespace, volumes, etc.)
3. kubelet runs init containers in declared order, one at a time:
   - init[0] starts, must exit 0
   - init[1] starts (only after init[0] succeeded), must exit 0
   - ...
4. After all init containers have exited 0:
   - App containers start in parallel
5. App containers run for the Pod's lifetime
6. On Pod deletion, all containers (init + app) are terminated
```

### State during init

The Pod is **not Ready** while init containers are running. The `Initialized` condition is `False` until all init containers complete. The Service endpoints controller does not add the Pod to any Service until `Initialized: True`.

### Restarting init containers

Init containers use the Pod's `restartPolicy`:

- `restartPolicy: Always` (the default) — failed init container is restarted in place
- `restartPolicy: OnFailure` — same
- `restartPolicy: Never` — failed init container is left in a non-running state, the Pod is not Ready

For most production workloads, `Always` is the right choice for the Pod (and therefore for the init containers). If the init container is failing transiently, the kubelet will restart it.

---

## 3. Manifest Anatomy

A Pod with init containers:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  initContainers:
  - name: wait-for-db
    image: busybox:1.36
    command: ['sh', '-c', 'until nc -z db 5432; do echo waiting; sleep 2; done']
  - name: migrate
    image: myorg/app:2.1
    command: ['./manage', 'migrate']
  - name: fetch-config
    image: myorg/config-fetcher:1.0
    command: ['./fetch', '--output=/config/app.yaml']
    volumeMounts:
    - name: config
      mountPath: /config
  containers:
  - name: app
    image: myorg/app:2.1
    command: ['./serve']
    volumeMounts:
    - name: config
      mountPath: /etc/app
      readOnly: true
    readinessProbe:
      exec:
        command: ['/bin/sh', '-c', 'cat /tmp/ready']
      initialDelaySeconds: 5
      periodSeconds: 5
  volumes:
  - name: config
    emptyDir: {}
```

Full field reference for an init container (it's a regular container spec, with some restrictions):

```yaml
initContainers:
- name: my-init
  image: myorg/init:1.0
  imagePullPolicy: IfNotPresent
  command: ["./init.sh"]
  args: ["--config=/etc/config"]
  workingDir: /app
  env:
  - name: LOG_LEVEL
    value: debug
  envFrom:
  - configMapRef:
      name: app-config
  resources:                     # independent budget
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  volumeMounts:
  - name: shared
    mountPath: /shared
  securityContext:               # independent of app container's
    runAsNonRoot: true
    capabilities:
      add: ["NET_ADMIN"]         # init needs this; app shouldn't have it
  lifecycle:                     # postStart/preStop are NOT supported on init containers
    # postStart: ❌ ignored
    # preStop:  ❌ ignored
  livenessProbe:                 # NOT supported on init containers
    # ❌ ignored
  readinessProbe:                # NOT supported on init containers
    # ❌ ignored
  startupProbe:                  # NOT supported on init containers
    # ❌ ignored
```

### What init containers support

| Field | Supported | Notes |
|---|---|---|
| `image` | ✅ | |
| `command`, `args` | ✅ | |
| `env`, `envFrom` | ✅ | |
| `resources` | ✅ | Independent budget |
| `volumeMounts` | ✅ | Shares Pod's volumes |
| `securityContext` | ✅ | Independent of app container's |
| `workingDir` | ✅ | |
| `imagePullPolicy` | ✅ | |
| `lifecycle.postStart` | ❌ | Init must exit; no post-start needed |
| `lifecycle.preStop` | ❌ | Init must exit; no pre-stop needed |
| `livenessProbe` | ❌ | Init must exit; no liveness check |
| `readinessProbe` | ❌ | Init is binary (running or done) |
| `startupProbe` | ❌ | Same reason |
| `stdin`, `tty` | ✅ | Unusual but valid |
| `ports` | ⚠️ | Allowed but unusual; init shouldn't be a server |

### Why probes and lifecycle hooks are not supported

Init containers are **run-to-completion** tasks. They exit 0 (success) or non-zero (failure). There's no concept of "still starting up" or "drain gracefully" — the init either completes or it doesn't. Lifecycle hooks and probes would imply a longer-lived state that init containers don't have.

If you need a long-lived setup helper, use a **sidecar** (regular container in the same Pod) or, in k8s 1.29+, a **native sidecar** (see section 9).

---

## 4. Common Patterns

### Pattern 1: Wait for a dependency

The most common pattern. The app needs a database (or cache, message broker, etc.) to be reachable, but you don't want to bake retry logic into the app.

```yaml
initContainers:
- name: wait-for-db
  image: busybox:1.36
  command:
  - sh
  - -c
  - |
    until nc -z db 5432; do
      echo "waiting for db..."
      sleep 2
    done
```

Variations:

```yaml
# Wait for a TCP port
until nc -z db 5432; do sleep 2; done

# Wait for an HTTP endpoint
until wget -q --spider http://cache:6379/ping; do sleep 2; done

# Wait for a DNS name to resolve
until nslookup api.svc.cluster.local; do sleep 2; done

# Wait for a file (mounted via a shared volume)
until [ -f /shared/ready ]; do sleep 2; done
```

This pattern is so common that tools like `dockerize` and `wait-for-it` exist to wrap it. But `busybox + nc` is often enough.

### Pattern 2: Schema / data migration

Run a migration before the app starts. The migration is part of the app's image (same binary, different command).

```yaml
initContainers:
- name: migrate
  image: myorg/app:2.1
  command: ['./manage', 'migrate']
  env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: url
```

Critical: the migration must be **idempotent** (running it twice should be safe) or you must be sure it only runs once per app version. Otherwise a Pod restart will re-run the migration and may corrupt the database.

A safer pattern: a separate `Job` that runs the migration, gated by a CI step:

```bash
# CI: run the migration Job first
kubectl apply -f migration-job.yaml
kubectl wait --for=condition=Complete --timeout=600s job/migration

# Then deploy the new app version
kubectl apply -f app-deployment-v2.yaml
```

This decouples the migration from the app startup.

### Pattern 3: Git clone / config fetch

Pull configs from a remote source. Useful for environments where ConfigMaps are not the right abstraction (e.g., per-Pod config that varies).

```yaml
initContainers:
- name: fetch-config
  image: myorg/config-fetcher:1.0
  command: ['./fetch', '--url=https://config.internal/app.yaml', '--output=/config/app.yaml']
  env:
  - name: CONFIG_TOKEN
    valueFrom:
      secretKeyRef:
        name: config-fetcher-token
        key: token
  volumeMounts:
  - name: config
    mountPath: /config
containers:
- name: app
  volumeMounts:
  - name: config
    mountPath: /etc/app
    readOnly: true
volumes:
- name: config
  emptyDir: {}
```

The fetched config is written to a shared `emptyDir` volume. The app reads it as a read-only mount.

### Pattern 4: Permissions setup

Prepare a volume with the right ownership, generate certs, or populate a directory before the app reads it.

```yaml
initContainers:
- name: setup-data
  image: busybox:1.36
  command:
  - sh
  - -c
  - |
    mkdir -p /data
    chown 1000:1000 /data
    # Generate a self-signed cert
    openssl req -x509 -newkey rsa:4096 -nodes \
      -keyout /data/tls.key -out /data/tls.crt \
      -days 365 -subj "/CN=app"
  volumeMounts:
  - name: data
    mountPath: /data
containers:
- name: app
  volumeMounts:
  - name: data
    mountPath: /var/lib/app
volumes:
- name: data
  emptyDir: {}
```

The init container can run as root (or with elevated capabilities) to do privileged setup, while the app runs as a non-root user. The fsGroup ensures the data is owned correctly.

### Pattern 5: Registration / deregistration with an external system

Register the Pod with Consul, an external load balancer, or a service registry on startup. The init container does the registration; the app starts.

```yaml
initContainers:
- name: register
  image: myorg/registrar:1.0
  command: ['./register', '--service=my-app', '--host=$(POD_IP)', '--port=8080']
  env:
  - name: POD_IP
    valueFrom:
      fieldRef:
        fieldPath: status.podIP
  - name: CONSUL_HTTP_TOKEN
    valueFrom:
      secretKeyRef:
        name: consul-token
        key: token
```

This is an anti-pattern in modern k8s. Use Services and Endpoints instead. But for legacy systems that require explicit registration, it works.

### Pattern 6: Database seeding (development)

For dev environments, seed the database with test data on first startup.

```yaml
initContainers:
- name: seed
  image: myorg/seed:1.0
  command: ['./seed', '--if-empty']
  env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: url
```

The `--if-empty` flag makes the seed script a no-op if the database is already populated. Combined with `restartPolicy: OnFailure`, the init won't re-seed on every restart.

---

## 5. Init Containers vs Sidecars

The choice between an init container and a sidecar comes down to **lifetime**:

| Aspect | Init container | Sidecar |
|---|---|---|
| Lifetime | Until success (run-to-completion) | Same as the app (long-lived) |
| Started when | Before app containers | Alongside app containers |
| Restarted when | Failed (per Pod's restartPolicy) | Per Pod's restartPolicy |
| Resources | Independent budget | Independent budget |
| Network namespace | Shared with Pod | Shared with Pod |
| Volumes | Shared with Pod | Shared with Pod |
| Probes | ❌ | ✅ |
| Lifecycle hooks | ❌ | ✅ |

### Decision rule

```
Need a helper that runs ONCE before the app starts?
│
├── Yes ──▶ Init container
│
└── Need a helper that runs ALONGSIDE the app for the Pod's lifetime?
    │
    ├── Yes, and I need ordered start/stop ──▶ Native sidecar (k8s 1.29+, restartPolicy: Always on a regular container)
    │
    └── Yes, and ordered start/stop is OK to be approximate ──▶ Regular sidecar container
```

### The "what about a sidecar that's actually a setup helper?"

Some teams use a sidecar for "setup" because they need ordered start (sidecar starts before app) and ordered stop (sidecar stops after app). In k8s 1.29+, this is what **native sidecars** are for. Before 1.29, you can use a regular sidecar with a `postStart` hook in the app that waits for the sidecar to be ready.

---

## 6. Init Containers vs the App's Own Setup

When should you put setup logic in an init container vs in the app itself?

### Use the app's own setup when

- The setup is fast (sub-second)
- The setup doesn't need a different image or different security context
- The setup is part of the app's domain (e.g., a Spring Boot app's bean initialization)
- The setup should retry transparently on every app start (e.g., connecting to a DB)

Example: a Java app that connects to a DB on startup. The app handles retries, timeout, logging. No init container needed.

### Use an init container when

- The setup needs a different image (e.g., `busybox` for `nc`, `curl` for HTTP probes, a config fetcher for S3)
- The setup needs different security (e.g., needs `NET_ADMIN` or root to manipulate iptables)
- The setup should not be part of the app's restart cycle (a flaky init shouldn't restart the app)
- The setup is shared across many apps (a generic "wait for DB" step)
- The setup creates a file the app reads (better separation of concerns)

Example: a Node.js app that needs a TLS cert from a secrets manager. The init container fetches the cert to a shared volume; the app reads it on startup.

### The "always use init for waiting" rule

A common best practice: **use an init container for any "wait for X" step**, not the app's own logic. Reasons:

- The app's startup is faster (no retry logic in the app)
- The wait can be standardized (a `wait-for-it` image for the whole org)
- The Pod's `Initialized` condition is `False` until the wait completes (no traffic before then)
- Failures are visible in `kubectl describe pod` (init container status is shown)

---

## 7. Resource Interaction

### Init container resources are independent

Each init container has its own `resources` block. They are **not** summed with the app containers for runtime enforcement, but they **are** considered for scheduling.

```yaml
initContainers:
- name: migrate
  image: myorg/app:2.1
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 1Gi
containers:
- name: app
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

The Pod's effective `requests` for scheduling:

```
effective.cpu.request = max(sum of init containers, sum of app containers)
                      = max(500m, 100m) = 500m
effective.memory.request = max(sum of init containers, sum of app containers)
                          = max(512Mi, 128Mi) = 512Mi
```

So the scheduler reserves 500m / 512Mi for this Pod on the node.

At runtime, the init container is allowed to use up to 1 CPU and 1Gi (its own limits). The app is allowed up to 200m / 256Mi. They don't share.

### Why this design

The init container might do heavy work (e.g., a database migration that loads 1 GB into memory). The app's steady-state needs are much lower. By having independent limits, the init can use what it needs without constraining the app, and vice versa.

### The QoS class

The QoS class is determined by the **largest** resource combination:

- If any init container has `requests == limits` (Guaranteed) and all app containers are also Guaranteed → Guaranteed
- If any init container has limits but not equal to requests, or any container is Burstable → Burstable
- If no init container and no app container has any requests or limits → BestEffort

In practice, init containers often have requests but no limits (Burstable), which makes the whole Pod Burstable.

### When init resources don't matter

For very fast init containers (the typical "wait for DB" pattern), the resources don't matter much — the init runs for seconds, not minutes. The scheduler doesn't reserve resources for it beyond the request.

But for heavy migrations (e.g., loading 1 GB of data into a database), the init's resources matter. Set them explicitly so the scheduler can place the Pod correctly.

---

## 8. Failure Semantics and Restart

### What happens when an init container fails

```
1. Init container exits non-zero
2. kubelet restarts it (per Pod's restartPolicy)
3. kubelet applies the exponential backoff:
   - First failure: restart after 10s
   - Second: 20s
   - Third: 40s
   - ...
   - Capped at 300s (5 min)
4. The Pod is in Init:CrashLoopBackOff state
5. The Pod is NOT Ready
6. After backoffLimit (Pod-level, default 6), the Pod is marked Failed
   (for non-Job Pods; for Jobs, the Job's backoffLimit applies)
```

### Backoff for init containers

The init container uses the **same backoff** as a regular container. The first restart is 10s after failure, then 20s, 40s, etc. There's no "infinite retry" by default — after the Pod's `backoffLimit` (which is set on the Pod, not the init container), the kubelet gives up.

For Pods in Deployments, the controller will see the failed Pod and create a new one. The init runs again. If the init is consistently failing, you have a problem (bad image, bad config, missing dependency).

### Diagnosing init failures

```bash
# Show all containers in a Pod, including init
kubectl get pod <pod> -o jsonpath='{.status.initContainerStatuses}'
# Or
kubectl describe pod <pod>
# Look at the "Init Containers:" section
```

The init container's status shows the same fields as a regular container (`state`, `lastState`, `restartCount`, etc.).

```bash
# Logs from a specific init container
kubectl logs <pod> -c <init-container-name>
```

### Modifying an init container

If you change the init container's image or command, the Pod is recreated (the Pod template changed). The new init runs from scratch.

If you change a non-init field (e.g., the app's image), the init containers are **not re-run** — the existing init's state is preserved (the volumes they wrote are still there).

This is important for the **migrations** pattern. If you change only the app's image, the init doesn't re-run, so a previously-completed migration doesn't re-run. But if you change the init's image, the init runs again from scratch.

---

## 9. Native Sidecars (k8s 1.29+)

In k8s 1.29, a new feature was added: **native sidecars** via `restartPolicy: Always` on a regular container.

```yaml
spec:
  initContainers:
  - name: log-shipper                  # ❌ old way: init container
    image: fluent/fluent-bit:3.0
    # The container exits when the work is "done" — but you want it to keep running
    # Workaround: tail -f /dev/null
    command: ["sh", "-c", "fluent-bit -c /etc/fluent-bit.conf & sleep infinity"]
  # vs.
  containers:
  - name: log-shipper                  # ✅ new way: native sidecar
    image: fluent/fluent-bit:3.0
    restartPolicy: Always             # k8s 1.29+ sidecar primitive
    command: ["fluent-bit", "-c", "/etc/fluent-bit.conf"]
```

### What a native sidecar gets

1. **Ordered start**: the sidecar starts **before** the main app containers, similar to an init container
2. **Ordered stop**: the sidecar stops **after** the main app containers, ensuring in-flight logs are flushed
3. **Proper status reporting**: the sidecar is treated like a regular container, with normal `Running` / `Waiting` / `Terminated` states
4. **No more `sleep infinity` hacks**

### The old way vs the new way

| Aspect | Init container with `sleep infinity` | Native sidecar (k8s 1.29+) |
|---|---|---|
| Ordered start | ✅ | ✅ |
| Ordered stop | ❌ (init exits immediately, sidecar is "done") | ✅ |
| Status reporting | ❌ (init shows as `Terminated`) | ✅ (regular `Running` state) |
| Probes | ❌ | ✅ |
| Resources | Independent | Independent |
| Restart on failure | Per Pod's restartPolicy | Per Pod's restartPolicy |

### The migration

If you have:

```yaml
initContainers:
- name: log-shipper
  image: fluent/fluent-bit:3.0
  command: ["sh", "-c", "fluent-bit -c /etc/fluent-bit.conf & sleep infinity"]
```

Change to:

```yaml
initContainers: []   # remove the init container
containers:
- name: app
  # ... main app
- name: log-shipper
  image: fluent/fluent-bit:3.0
  restartPolicy: Always    # this makes it a native sidecar
  command: ["fluent-bit", "-c", "/etc/fluent-bit.conf"]
```

The behavior is the same, but the sidecar is now a first-class container with proper lifecycle.

### Why this matters

The `sleep infinity` pattern is a workaround. Native sidecars are the right answer. If you're on k8s 1.29+, use them.

For multi-container Pod patterns in general, see [[Kubernetes/concepts/L03-workloads/09-multi-container-pods|09 — Multi-Container Pods]].

---

## 10. Operational Recipes

### Recipe 1: Wait for a database (the most common pattern)

```yaml
initContainers:
- name: wait-for-db
  image: busybox:1.36
  command:
  - sh
  - -c
  - |
    until nc -z db 5432; do
      echo "waiting for db at db:5432..."
      sleep 2
    done
```

### Recipe 2: Wait for multiple dependencies

```yaml
initContainers:
- name: wait-for-db
  image: busybox:1.36
  command: ['sh', '-c', 'until nc -z db 5432; do sleep 2; done']
- name: wait-for-cache
  image: busybox:1.36
  command: ['sh', '-c', 'until nc -z cache 6379; do sleep 2; done']
- name: wait-for-broker
  image: busybox:1.36
  command: ['sh', '-c', 'until nc -z broker 9092; do sleep 2; done']
```

Init containers run sequentially, so the Pod waits for all three.

### Recipe 3: Run migrations then start app

```yaml
initContainers:
- name: migrate
  image: myorg/app:2.1
  command: ['./manage', 'migrate']
  env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: url
  resources:
    requests:
      memory: 512Mi
      cpu: 500m
containers:
- name: app
  image: myorg/app:2.1
  command: ['./serve']
```

### Recipe 4: Generate TLS cert

```yaml
initContainers:
- name: generate-cert
  image: alpine:3.19
  command:
  - sh
  - -c
  - |
    apk add --no-cache openssl
    openssl req -x509 -newkey rsa:4096 -nodes \
      -keyout /certs/tls.key -out /certs/tls.crt \
      -days 365 -subj "/CN=$(POD_NAME)"
  env:
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  volumeMounts:
  - name: certs
    mountPath: /certs
containers:
- name: app
  volumeMounts:
  - name: certs
    mountPath: /etc/app/certs
    readOnly: true
volumes:
- name: certs
  emptyDir: {}
```

### Recipe 5: Permission setup with different security contexts

```yaml
initContainers:
- name: setup-data
  image: busybox:1.36
  command: ['sh', '-c', 'mkdir -p /data && chown 1000:1000 /data && touch /data/ready']
  securityContext:
    runAsUser: 0      # needs root to chown
  volumeMounts:
  - name: data
    mountPath: /data
containers:
- name: app
  image: myorg/app:2.1
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  volumeMounts:
  - name: data
    mountPath: /var/lib/app
volumes:
- name: data
  emptyDir: {}
```

The init container runs as root to chown the volume; the app runs as non-root.

### Recipe 6: Fetch config from S3

```yaml
initContainers:
- name: fetch-config
  image: amazon/aws-cli:2.15.0
  command:
  - sh
  - -c
  - |
    aws s3 cp s3://my-config-bucket/app.yaml /config/app.yaml
  env:
  - name: AWS_REGION
    value: us-east-1
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: aws-creds
        key: access-key
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: aws-creds
        key: secret-key
  volumeMounts:
  - name: config
    mountPath: /config
containers:
- name: app
  image: myorg/app:2.1
  volumeMounts:
  - name: config
    mountPath: /etc/app
    readOnly: true
volumes:
- name: config
  emptyDir: {}
```

### Recipe 7: Native sidecar (k8s 1.29+)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      containers:
      - name: app
        image: myorg/app:2.1
        # ... main app ...
      - name: log-shipper
        image: fluent/fluent-bit:3.0
        restartPolicy: Always        # native sidecar primitive
        command: ["fluent-bit", "-c", "/etc/fluent-bit.conf"]
        volumeMounts:
        - name: logs
          mountPath: /var/log/app
          readOnly: true
      - name: app
        volumeMounts:
        - name: logs
          mountPath: /var/log/app
      volumes:
      - name: logs
        emptyDir: {}
```

---

## 11. Troubleshooting

### Symptom: Pod stuck in `Init:0/2` or `Init:CrashLoopBackOff`

The Pod has 2 init containers; 0 have completed; one is in CrashLoopBackOff.

```bash
kubectl describe pod <pod>
# Look at "Init Containers:" section
# Each init container has its own status block
```

Common causes:

- **Init image is bad** (`ImagePullBackOff`, `ErrImagePull`)
- **Init command exits non-zero** — check the script's logic
- **Init is waiting for something that doesn't exist** — e.g., `nc -z db 5432` where `db` is not a resolvable Service
- **Init is timing out** — e.g., a `wget` that hangs

```bash
# Logs from a specific init container
kubectl logs <pod> -c <init-name>
# Previous instance (if it restarted)
kubectl logs <pod> -c <init-name> --previous
```

### Symptom: Init succeeds but app fails

The init container ran successfully, but the app fails to start. Common causes:

- **The init didn't write what the app expected** — check the volume, check the file path
- **The app can't read the file** — permissions, path mismatch
- **The init set up a different env var** than the app reads

```bash
# Compare what the init wrote vs what the app expects
kubectl exec <pod> -c <init-name> -- ls -la /config/
# vs.
kubectl exec <pod> -c <app-name> -- ls -la /etc/app/
```

### Symptom: Init runs again on every Pod restart

This happens when the init's success state is not preserved across restarts. Examples:

- The init writes to a non-shared volume (won't work)
- The init registers with an external system, but the system forgets on Pod restart
- The init relies on the network, and the network was reconfigured

For most patterns (waiting for DB, writing to a shared volume), the init's work is preserved. For others (registering with a system), you may need a different design.

### Symptom: Init container resources are causing the Pod to be unschedulable

```bash
kubectl describe pod <pod>
# Look for "FailedScheduling" events
```

The init container is requesting more resources than any node can satisfy. Either:

- Reduce the init's `requests` (if possible)
- Move heavy work out of the init (e.g., do migrations in a separate Job)
- Add more nodes

### Symptom: Init container timeouts

You have `command: ['sh', '-c', 'until ... do sleep 2; done']` but the Pod is in `Init:0/1` for too long.

Add a timeout to the init:

```yaml
initContainers:
- name: wait-for-db
  image: busybox:1.36
  command:
  - sh
  - -c
  - |
    end=$((SECONDS+60))
    until nc -z db 5432; do
      if [ $SECONDS -ge $end ]; then
        echo "timed out waiting for db"
        exit 1
      fi
      sleep 2
    done
```

This makes the init fail after 60 seconds instead of waiting forever.

### Symptom: Init container has been "running" for a long time

Some init containers legitimately run for minutes (e.g., large migrations). To verify:

```bash
# Check the init's status
kubectl get pod <pod> -o jsonpath='{.status.initContainerStatuses[0]}'
```

Look at the `state.running.startedAt` — if it's been hours, something is wrong. If minutes, it might be normal.

---

## 12. Gotchas and Common Mistakes

### Init container gotchas

- **Probes and lifecycle hooks are not supported.** Don't try to add them — they're silently ignored.
- **Init container restart counts are separate from app container restart counts.** A flaky init doesn't trigger an app restart.
- **Init container resources are independent of app resources.** Set them explicitly, especially for heavy migrations.
- **Init containers run sequentially.** If you have 5 init containers, the Pod waits for all 5 in order. Plan the total time.
- **The `Initialized` Pod condition is `False` until all init containers complete.** No traffic, no Service endpoints.
- **Init containers share the Pod's network namespace.** `localhost:5432` from an init container is the same as `localhost:5432` from the app.
- **Init containers share the Pod's volumes.** Writing to a shared volume in the init is visible to the app.
- **Init containers have separate `securityContext`.** Use this to give the init more permissions than the app.

### The "init doesn't re-run on spec change" gotcha

If you change **only** the app's image (not the init's), the init is **not re-run**. This is correct behavior — the init's work is preserved.

If you change the init's image, the Pod is recreated, and the init runs from scratch.

For migrations, this means:
- App image bump → migration doesn't re-run (good, idempotent)
- Migration image bump → migration re-runs (potentially dangerous if not idempotent)

### The "init has a typo" gotcha

A typo in the init's command is hard to debug. The init exits non-zero, the Pod restarts it, and the loop continues. The error message might be cryptic.

Always test the init's command locally before deploying. Use `kubectl run --rm -it --image=<init-image> -- <command>` to verify.

### The "init needs root" gotcha

Some init containers need root to do their work (e.g., `chown`, generating certs in `/etc`). Make sure the init's `securityContext` allows this, but the app's `securityContext` does **not**:

```yaml
initContainers:
- name: setup
  securityContext:
    runAsUser: 0      # needs root
containers:
- name: app
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
```

This is a valid pattern, but audit the init's permissions carefully. A compromised init container with root can do anything in the Pod.

### The "infinite wait" gotcha

```yaml
initContainers:
- name: wait-for-db
  command: ['sh', '-c', 'until nc -z db 5432; do sleep 2; done']
```

If `db` is not resolvable, this loops forever. The Pod is in `Init:0/1` until the kubelet gives up. Add a timeout:

```yaml
command: ['sh', '-c', 'timeout 300 sh -c "until nc -z db 5432; do sleep 2; done"']
```

Or use a custom timeout in the script.

### The "init runs on every restart" gotcha (for migrations)

A migration init container runs on every Pod creation. If the migration is not idempotent, the second run will fail.

Mitigations:
- Use a separate Job for migrations (gated by CI)
- Make the migration script idempotent (`CREATE TABLE IF NOT EXISTS`, `IF NOT EXISTS` clauses)
- Use a flag file (write `/shared/migrated` after success; skip if exists)

### The "init image is huge" gotcha

Init containers that use the same image as the app (e.g., for migrations) are fine. But if you use a separate image (e.g., a custom config fetcher), make sure it's small. A 1 GB init image for a "wait for X" step is wasteful.

Use `busybox`, `alpine`, or `distroless` for small init containers.

### The "Pod's restartPolicy applies to init" gotcha

Init containers use the **Pod's** `restartPolicy`. If the Pod's restartPolicy is `Never`, the init is not restarted on failure. This can lead to a Pod that is permanently stuck in `Init:Error` state.

For most use cases, `Always` (the default) is correct. Set `Never` only if you want the Pod to be Failed and not retried.

### The "init in a Job" gotcha

A Job uses init containers the same way, but the **Job's** `backoffLimit` applies. If the init is failing, the Job retries, creating a new Pod each time. After `backoffLimit` retries, the Job is Failed.

For migrations, prefer a separate Job (not an init container in a Deployment's Pod) so the migration is decoupled from the app.

---

## 13. Related Notes

| Topic | Note |
|---|---|
| Pods (init containers are a Pod field) | [[Kubernetes/concepts/L03-workloads/01-pods\|01 — Pods]] |
| Multi-container Pods (sidecars) | [[Kubernetes/concepts/L03-workloads/09-multi-container-pods\|09 — Multi-Container Pods]] |
| Probes (not supported on init) | [[Kubernetes/concepts/L03-workloads/10-probes\|10 — Probes]] |
| Jobs (run-to-completion) | [[Kubernetes/concepts/L03-workloads/06-job\|06 — Job]] |
| Resource requests and limits | [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|L06 — Resource Requests and Limits]] |
| Security context | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context\|L07 — Security Context]] |
| Volumes (shared with init) | [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim\|L05 — PersistentVolumeClaim]] |

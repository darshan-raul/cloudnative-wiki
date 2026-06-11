---
title: Pods — The Foundation of Kubernetes Workloads
tags: [kubernetes, workloads, pods, core-concepts]
date: 2026-06-07
description: The smallest deployable unit in Kubernetes. Container grouping, networking, lifecycle, scheduling, security context, and the deep internals that every controller builds on.
---

# Pods — The Foundation of Kubernetes Workloads

> https://kubernetes.io/docs/concepts/workloads/pods/

A **Pod** is the **smallest deployable unit** in Kubernetes. It is **not** a single container. It is a wrapper around one or more containers that share a network namespace, volumes, and a lifecycle, and that are always scheduled onto the **same node**.

If you only learn one Kubernetes concept deeply, it should be this one. Every controller in L03 — ReplicaSet, Deployment, StatefulSet, DaemonSet, Job — is a strategy for managing Pods. Every L04 networking primitive operates on Pods. Every L07 security control targets Pods. Get Pods wrong and everything else collapses.

## Table of Contents

1. [Why Pods Exist — The Container Colocation Problem](#1-why-pods-exist--the-container-colocation-problem)
2. [What a Pod Is (and Isn't)](#2-what-a-pod-is-and-isnt)
3. [The Pod Manifest — Anatomy](#3-the-pod-manifest--anatomy)
4. [Pod Networking Deep Dive](#4-pod-networking-deep-dive)
5. [Pod Lifecycle — From Pending to Termination](#5-pod-lifecycle--from-pending-to-termination)
6. [Container Lifecycle Hooks](#6-container-lifecycle-hooks)
7. [Init Containers — Ordered Setup Before the App](#7-init-containers--ordered-setup-before-the-app)
8. [Multi-Container Pods — Sidecar / Ambassador / Adapter](#8-multi-container-pods--sidecar--ambassador--adapter)
9. [Probes — Liveness, Readiness, Startup](#9-probes--liveness-readiness-startup)
10. [Resource Requests and Limits](#10-resource-requests-and-limits)
11. [Security Context — Per-Container Hardening](#11-security-context--per-container-hardening)
12. [Volumes and Storage in Pods](#12-volumes-and-storage-in-pods)
13. [Pod Scheduling — How the Scheduler Sees a Pod](#13-pod-scheduling--how-the-scheduler-sees-a-pod)
14. [Pod Disruption — How Pods Get Killed](#14-pod-disruption--how-pods-get-killed)
15. [Pod QoS Classes](#15-pod-qos-classes)
16. [Static Pods — The Outlier](#16-static-pods--the-outlier)
17. [Why You Almost Never Write a Bare Pod](#17-why-you-almost-never-write-a-bare-pod)
18. [Operational Recipes](#18-operational-recipes)
19. [Gotchas and Common Mistakes](#19-gotchas-and-common-mistakes)
20. [Related Notes](#20-related-notes)

---

## 1. Why Pods Exist — The Container Colocation Problem

Before Pods, the question was simple: "Can I run containers in Kubernetes?" The answer turned out to be: "Yes, but you almost always want to run **groups** of containers together." And the abstraction k8s settled on is the Pod.

### The two-container case

Imagine a web app that writes structured logs to a file, plus a log shipper that reads that file and forwards to a central backend. You need:

- Both containers on the **same node** (so the log file is local)
- Both to share the **same volume** (so the shipper can read the app's log file)
- Both to share a **network namespace** (so the app can call the shipper on `localhost`, no DNS needed)
- Both to **start together and die together**

You could run two separate containers on the same node and try to enforce all of that yourself. Or you could let the scheduler know "these two belong together" and have the kubelet start them as a unit. That unit is the Pod.

```
┌──────────────────────────────────────────────────┐
│ Pod                                               │
│  ┌────────────────┐  ┌────────────────────────┐  │
│  │  app           │  │  log-shipper            │  │
│  │  /var/log/app  │──▶│  reads /var/log/app/*   │  │
│  │  (writes)      │  │  forwards to backend    │  │
│  └────────────────┘  └────────────────────────┘  │
│         shared volume (emptyDir)                  │
│         shared network namespace                  │
│         same node, same lifecycle                 │
└──────────────────────────────────────────────────┘
```

The pattern generalizes. Service mesh sidecars (Envoy, Linkerd proxies), Dapr sidecars, metrics exporters, debug sidecars — all are variations on "helper container that lives with the main app."

### Why not just deploy containers directly?

Three reasons:

1. **No native way to group containers.** Docker Compose has `depends_on`, but Kubernetes has no equivalent at the container level — only at the Pod level.
2. **Networking across containers on the same node is awkward.** Without a shared network namespace, container A would have to know container B's IP, which only exists after B is scheduled.
3. **Lifecycles are coupled but managed separately.** Two "loose" containers with separate lifecycles break the "start together, die together" guarantee.

The Pod is the unit the scheduler schedules, the kubelet starts, the Service targets, the network policy selects, and the controller reconciles. **Everything in k8s is a Pod.** Containers are an implementation detail of a Pod.

---

## 2. What a Pod Is (and Isn't)

### The mental model

```
┌──────────────────────────────────────────┐
│ Pod                                       │
│                                           │
│  Network namespace (one IP, one hostname)│
│  ┌──────────┐  ┌──────────┐  ┌────────┐  │
│  │ container│  │ container│  │ ...    │  │
│  │   A      │  │   B      │  │        │  │
│  └──────────┘  └──────────┘  └────────┘  │
│                                           │
│  Volumes (shared mounts)                  │
│  IPC namespace (shared)                   │
│  PID namespace (optionally shared)        │
│  UTS namespace (shared hostname)         │
│  Cgroup (shared)                          │
└──────────────────────────────────────────┘
```

### What a Pod is

| Property | Value |
|---|---|
| **Smallest deployable unit** | Yes — you cannot deploy a container without a Pod |
| **One or more containers** | Always at least one |
| **One network namespace** | All containers share the same IP and `localhost` |
| **One IPC namespace** | Shared System V IPC + POSIX shared memory |
| **One UTS namespace** | All containers see the same hostname (the Pod's name) |
| **One PID namespace** | Optionally shared (`shareProcessNamespace: true`) |
| **Scheduled as a unit** | All containers land on the same node |
| **Started as a unit** | kubelet starts them in declared order |
| **Terminated as a unit** | kubelet sends SIGTERM to all, then SIGKILL after grace period |
| **Has a unique UID** | Generated by the API server, changes on every recreation |
| **Has a stable name within its lifetime** | DNS A record: `<pod-ip>.<namespace>.pod.cluster.local` |

### What a Pod is NOT

| Misconception | Reality |
|---|---|
| A Pod is a container | A Pod is a wrapper. It can hold one or more. |
| A Pod is a VM | A Pod is not a VM. It doesn't have its own kernel, doesn't virtualize hardware. |
| A Pod's IP is stable | A Pod's IP is stable **for the lifetime of the Pod**. Recreate the Pod, get a new IP. |
| A Pod is a security boundary | A Pod is a weak security boundary. Containers in a Pod share kernel namespaces. For real isolation, use separate Pods (or separate Nodes). |
| A Pod is the right place to put cross-cutting concerns | Sometimes — but more often, a sidecar container (still inside a Pod) is the right abstraction. |
| A Pod is restarted when its node dies | **No.** A new Pod is created, with a new UID, possibly on a different node. The original Pod is gone. |

---

## 3. The Pod Manifest — Anatomy

The full shape of a Pod spec, in field order:

```yaml
apiVersion: v1                   # always v1 for Pod
kind: Pod
metadata:
  name: nginx                    # DNS-compatible name (lowercase, ≤63 chars)
  namespace: default             # every Pod lives in exactly one namespace
  labels:                        # used by selectors, Service routing, NetworkPolicy
    app: nginx
    tier: frontend
  annotations:                   # non-identifying metadata, used by tools
    prometheus.io/scrape: "true"
spec:                            # desired state
  containers:                    # one or more
  - name: nginx                  # required, unique within Pod
    image: nginx:1.27            # image:tag — pin the tag
    imagePullPolicy: IfNotPresent
    ports:                       # informational — does not actually publish
    - name: http                 # named port for use elsewhere (probes, NetPol)
      containerPort: 80
      protocol: TCP
    env:                         # environment variables
    - name: LOG_LEVEL
      value: info
    envFrom:                     # bulk load from ConfigMap/Secret
    - configMapRef:
        name: app-config
    resources:                   # see section 10
      requests:
        cpu: 100m                # 0.1 CPU
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
    volumeMounts:                # see section 12
    - name: data
      mountPath: /var/www/html
    livenessProbe:               # see probes note
      httpGet:
        path: /healthz
        port: http
    readinessProbe:
      httpGet:
        path: /ready
        port: http
    startupProbe:
      httpGet:
        path: /healthz
        port: http
      failureThreshold: 30
      periodSeconds: 5
    lifecycle:                   # see section 6
      preStop:
        exec:
          command: ["sh", "-c", "nginx -s quit"]
      postStart:
        exec:
          command: ["/bin/sh", "-c", "echo started > /tmp/started"]
    securityContext:             # see section 11
      runAsNonRoot: true
      runAsUser: 101
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
  initContainers:                # see section 7 — run before main containers
  - name: wait-for-db
    image: busybox:1.36
    command: ['sh', '-c', 'until nc -z db 5432; do sleep 2; done']
  volumes:                       # see section 12
  - name: data
    emptyDir: {}
  - name: config
    configMap:
      name: app-config
  restartPolicy: Always          # Always | OnFailure | Never
  nodeSelector:                  # constraint: which nodes
    node-role.kubernetes.io/worker: ""
  affinity:                      # richer constraints — see L06
  tolerations:                   # tolerate taints
  serviceAccountName: my-sa      # identity for API calls
  hostNetwork: false             # share node network? usually false
  dnsPolicy: ClusterFirst        # see L04
  priorityClassName: normal      # see L06
  schedulingGates: []            # see L06
  overhead:                      # resource overhead for scheduling
    pod:
      cpu: 100m
  terminationGracePeriodSeconds: 30  # see section 14
  activeDeadlineSeconds: 3600    # Job-only; see Job note
  hostname: my-pod               # sets the UTS hostname
  subdomain: db                  # forms a headless Service DNS name
  hostAliases:                   # /etc/hosts entries
  - ip: 1.2.3.4
    hostnames: ["db.local"]
status:                          # current state, written by kubelet
  phase: Running
  conditions: []
  containerStatuses: []
  podIP: 10.244.1.5
  hostIP: 10.0.0.12
  startTime: "2025-05-24T10:00:00Z"
```

That looks enormous. Most of the fields are optional. A minimum-viable Pod is just `apiVersion`, `kind`, `metadata.name`, and `spec.containers[].image`. Everything else exists to handle real-world constraints (probes, security, resources, networking).

### Required fields

| Field | Required | Why |
|---|---|---|
| `apiVersion` | yes | Schema version — always `v1` for Pod |
| `kind` | yes | Must be `Pod` |
| `metadata.name` | yes | DNS-1123 label: lowercase, ≤63 chars, no leading/trailing `-` |
| `spec.containers[].name` | yes | Unique within Pod |
| `spec.containers[].image` | yes | Image reference (registry/repo:tag) |
| `spec.containers[].ports[].name` | no, but recommended | Makes ports referenceable by name in probes and NetworkPolicy |

### Container name rules

Container names must be **unique within a Pod** and be valid DNS-1123 labels. Use names that describe the role, not the image:

```yaml
containers:
- name: api          # ✅ role-based
  image: ghcr.io/myorg/api:v2.3.1
- name: proxy        # ✅ role-based
  image: envoyproxy/envoy:v1.30
```

Avoid:

```yaml
containers:
- name: myorg-api-v2-3-1   # ❌ couples name to image
```

---

## 4. Pod Networking Deep Dive

Pod networking is its own layer of complexity. It's covered in detail in [[Kubernetes/concepts/L04-services-networking/01-networking|L04 — Networking]], but here's the 60-second version you need before reading the rest of L03.

### The flat network: every Pod gets a routable IP

In a Kubernetes cluster, **every Pod gets a real IP** (no NAT, no port translation, no overlay if you use a CNI that supports it). A Pod can reach any other Pod by IP. From a Pod's perspective:

```
Pod A                            Pod B
10.244.1.5                       10.244.2.7
   │                                ▲
   │  curl 10.244.2.7:8080          │
   └───────────────────────────────▶┘
        (no NAT, no proxy)
```

This is enforced by the CNI plugin (Calico, Cilium, Flannel, Weave, etc.). The CNI provisions a virtual network on every node and wires up the routes so Pod IPs are reachable cluster-wide.

### One IP, one namespace, one localhost

All containers in a Pod share a **single network namespace**:

```yaml
# Pod with two containers — they reach each other on localhost
containers:
- name: api
  ports:
  - containerPort: 8080
- name: cache-warmup
  image: mywarmer:1.0
  command: ["sh", "-c", "curl -s http://localhost:8080/warmup"]
  # The warmer talks to api on localhost:8080
  # Same Pod IP, same localhost, no DNS lookup needed
```

Two containers in the same Pod **cannot** bind to the same port. If container A binds `:8080`, container B trying to bind `:8080` will get an "address already in use" error.

### Pod DNS

Every Pod gets a DNS A record of the form:

```
<pod-ip-with-dashes>.<namespace>.pod.cluster.local
```

For example, a Pod with IP `10.244.1.5` in namespace `production` is resolvable as:

```
10-244-1-5.production.pod.cluster.local
```

(This is mostly used by Service discovery from outside the Pod — for in-Pod communication, `localhost` is enough.)

### hostNetwork — escape the Pod network

Setting `hostNetwork: true` makes the Pod share the **node's** network namespace. The Pod is reachable on the node's IP and can bind to privileged ports. This is occasionally needed for CNI components, kube-proxy, and Ingress controllers, but it's almost always wrong for application Pods:

```yaml
# ❌ Avoid this for application Pods
spec:
  hostNetwork: true
  containers:
  - name: app
    image: myapp:1.0
```

Why avoid it: it bypasses NetworkPolicy, it removes the Pod's natural isolation, and it requires the host's port range to be available cluster-wide.

### `localhost` traffic in NetworkPolicy

When a Pod talks to itself (`localhost`), the traffic **does not leave the Pod's network namespace**, so NetworkPolicy does **not** see it. This is sometimes surprising — "why can my Pod still reach itself after I locked down egress?" — and the answer is: that traffic never hit the CNI datapath.

---

## 5. Pod Lifecycle — From Pending to Termination

A Pod moves through a state machine. Understanding the states is critical for debugging.

### The state machine

```
                    ┌────────────────────────────────────────┐
                    │                                         │
                    ▼                                         │
              ┌──────────┐                                   │
              │ Pending  │                                   │
              └─────┬────┘                                   │
                    │                                       │
                    │ (image pulled, scheduled, started)     │
                    ▼                                       │
              ┌──────────┐                                   │
              │ Running  │──────────────────────────────────▶│ (node lost)
              └─────┬────┘                                   │
                    │                                       │
   ┌────────────────┼────────────────┐                       │
   ▼                ▼                ▼                       │
┌────────┐   ┌──────────┐   ┌──────────┐                    │
│Succeed │   │ Failed   │   │ Unknown  │                    │
│ ed     │   │          │   │          │                    │
└────────┘   └──────────┘   └──────────┘                    │
                                                         ▼
                                                  (new Pod created
                                                   by controller)
```

### Phase meanings

| Phase | Meaning | Action |
|---|---|---|
| **Pending** | Accepted by API server, but not yet running. Could be: scheduling, image pull, init container running, volume mounting | Check `kubectl describe pod` for `Events`. |
| **Running** | Bound to a node, at least one container is running | Normal state. |
| **Succeeded** | All containers terminated with exit code 0, won't be restarted | Typical of Jobs. |
| **Failed** | At least one container terminated with non-zero, won't be restarted | Typical of failed Jobs. |
| **Unknown** | State can't be obtained (usually node communication lost) | Check the node. |

### Conditions (more granular than phase)

The `status.conditions` array is the **truthful** state. Phase is a coarse summary; conditions are precise.

| Condition | True means |
|---|---|
| `PodScheduled` | Pod has been assigned to a node |
| `PodReadyToStartContainers` (k8s 1.28+) | Sandbox (and volumes, etc.) is ready |
| `ContainersReady` | All containers in the Pod are ready |
| `Initialized` | All init containers completed successfully |
| `Ready` | Pod is ready to serve traffic (the AND of `ContainersReady` and being routable) |
| `DisruptionTarget` | Pod is being deleted (PDB-aware eviction) |

A Pod can be `Phase: Running` with `Ready: False` (e.g., during a rolling update, or when readiness probe fails). That's normal — it just means it's not in the Service endpoint list yet.

### Container states (separate from Pod phase)

Each container has its own state:

| Container state | Meaning |
|---|---|
| `Waiting` | Not running yet. `reason: ContainerCreating`, `CrashLoopBackOff`, `ImagePullBackOff`, `ErrImagePull` |
| `Running` | Process is up |
| `Terminated` | Exited. `reason: Completed`, `Error`, `OOMKilled` |

`CrashLoopBackOff` is the state you'll see most often during debugging. It means: the container started, crashed, and the kubelet is backing off before retrying. The backoff is 10s, 20s, 40s, 80s, 160s, 300s (cap).

---

## 6. Container Lifecycle Hooks

Two hooks per container: `postStart` and `preStop`.

### postStart

Runs **after** the container's main process has started, but the engine doesn't guarantee ordering with the entrypoint:

```yaml
lifecycle:
  postStart:
    exec:
      command: ["/bin/sh", "-c", "echo started > /tmp/started"]
```

Critical: postStart runs **in parallel** with the container's main process. Don't depend on it having completed before your app is ready. For "wait until X" gating, use a readiness probe or init container.

### preStop

Runs **before** the container is sent SIGTERM:

```yaml
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "nginx -s quit"]   # graceful shutdown
```

This is the right place to:
- Drain in-flight HTTP connections (`nginx -s quit`, `kill -SIGTERM <pid>`)
- Flush buffers to a sidecar
- Deregister from a load balancer (e.g., the AWS Load Balancer Controller)
- Wait for a sleep to let the readiness probe flip to "not ready" (so the Service stops routing traffic)

**The preStop sleep pattern:**

```yaml
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 10"]   # give kube-proxy / iptables time to propagate
```

The reason: when a Pod is deleted, the Endpoints controller removes the Pod from the Service **in parallel** with sending SIGTERM. There's a race: traffic can still arrive at the Pod for a few seconds after SIGTERM. Sleeping in preStop gives the endpoint-removal time to propagate. This is a known k8s gotcha and the sleep is a common workaround.

### The graceful shutdown flow

```
1. Pod deletion requested (kubectl delete / scale down / node drain)
2. Pod enters "Terminating" state
3. Endpoints controller removes the Pod from Service endpoints
4. kubelet sends SIGTERM to containers
5. preStop hook runs
6. Container has terminationGracePeriodSeconds (default 30) to exit
7. kubelet sends SIGKILL if still running
8. Pod object is deleted from etcd
```

The 30-second grace period is the global default. Override per-Pod:

```yaml
spec:
  terminationGracePeriodSeconds: 60
```

---

## 7. Init Containers — Ordered Setup Before the App

Init containers are specialized containers that **run before the main app containers**, in declared order, and must succeed before the next one starts.

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
    image: app:1.0
    command: ['./migrate', 'up']
  containers:
  - name: app
    image: app:1.0
    command: ['./serve']
```

Init container rules:

| Rule | Detail |
|---|---|
| **Order** | Declared order, started one at a time |
| **Success required** | Must exit 0 for the next one to start |
| **Run to completion** | No restart, no long-running |
| **Separate images** | Often a different image (e.g., `busybox` for waiting) |
| **Separate resources** | Init container resources are NOT added to the main container's |
| **No probes** | Can't use liveness/readiness/startup on init containers |
| **No lifecycle hooks** | preStop/postStart don't apply to init containers |
| **Restart policy** | Follows Pod's `restartPolicy` (typically `Always`) |

### Common patterns

1. **Wait for a dependency** — DB, cache, message broker. Simpler than a sidecar.
2. **Schema migration** — run once before the app boots.
3. **Git clone / config fetch** — pull secrets from a remote source.
4. **Permissions setup** — `chown` a volume, generate certs.
5. **Registration** — register the Pod with an external system (e.g., Consul, an LB).

### Init container resources

Init container resources are **independent** of the main containers. The scheduler treats the larger of (sum of init containers) or (sum of app containers) as the effective request, but the runtime enforces them separately:

```yaml
initContainers:
- name: migrate
  image: app:1.0
  resources:
    requests:
      memory: 512Mi      # big, for migration
      cpu: 500m
containers:
- name: app
  resources:
    requests:
      memory: 128Mi      # small, for steady state
      cpu: 100m
```

The Pod's `effective.memory.request = max(sum of init, sum of app)`.

For full coverage, see [[Kubernetes/concepts/L03-workloads/08-init-containers|08 — Init Containers]].

---

## 8. Multi-Container Pods — Sidecar / Ambassador / Adapter

A Pod can have multiple containers. The three recognized patterns (from the official k8s docs):

### 1. Sidecar

The most common. A helper that extends or enhances the main container.

```
┌──────────────────────────────────────┐
│ Pod                                   │
│  ┌──────────┐    ┌────────────────┐  │
│  │   app    │    │    sidecar      │  │
│  │          │    │ (log shipper,   │  │
│  │          │    │  metrics, mesh) │  │
│  └──────────┘    └────────────────┘  │
│   same network ns, shared volumes     │
└──────────────────────────────────────┘
```

Examples: Fluent Bit, Istio envoy, Linkerd proxy, Dapr sidecar, metrics exporter, secrets refresher.

### 2. Ambassador

Proxies network traffic for the main app. The app talks to `localhost`, the ambassador figures out the real destination.

```
┌──────────────────────────────────────┐
│ Pod                                   │
│  ┌──────────┐    ┌────────────────┐  │
│  │   app    │───▶│  ambassador     │  │
│  │          │    │  (forwards to   │  │
│  │          │    │   real broker)  │  │
│  └──────────┘    └────────────────┘  │
└──────────────────────────────────────┘
   localhost:9092 → remote broker
```

Used in legacy migrations: app code stays the same, ambassador handles the new topology.

### 3. Adapter

Normalizes the main app's output. App emits a custom log format, adapter rewrites to a standard one.

```
┌──────────────────────────────────────┐
│ Pod                                   │
│  ┌──────────┐    ┌────────────────┐  │
│  │   app    │───▶│    adapter      │  │
│  │ (custom  │    │  (converts to   │  │
│  │  logs)   │    │   JSON/OTLP)    │  │
│  └──────────┘    └────────────────┘  │
└──────────────────────────────────────┘
```

For full coverage, see [[Kubernetes/concepts/L03-workloads/09-multi-container-pods|09 — Multi-Container Pods]].

---

## 9. Probes — Liveness, Readiness, Startup

Three probe types, all run by the **kubelet** (not the API server, not a sidecar, not a Service):

| Probe | Question it answers | If it fails | Use it for |
|---|---|---|---|
| `startupProbe` | "Has the app finished starting?" | Container is killed if it never succeeds | Slow-starting apps (JVM, big data loads) |
| `livenessProbe` | "Is the container still alive?" | Container is killed and restarted | Detect deadlocks, unrecoverable errors |
| `readinessProbe` | "Can the container serve traffic?" | Pod removed from Service endpoints | Signal "draining" or "warming up" |

Probe handlers: `httpGet`, `tcpSocket`, `exec`, `gRPC`.

Critical gotcha: **liveness probes must check internal health only.** A liveness probe that hits a downstream dependency (DB, cache) will restart the Pod when the dependency is briefly unavailable — making the situation worse, not better. Use readiness for downstream checks.

For the full reference, see [[Kubernetes/concepts/L03-workloads/10-probes|10 — Probes]].

---

## 10. Resource Requests and Limits

Resources are the **scheduler's contract** with the kubelet. They control both **scheduling decisions** and **runtime enforcement**.

```yaml
spec:
  containers:
  - name: app
    image: app:1.0
    resources:
      requests:
        cpu: 100m           # 0.1 vCPU core
        memory: 128Mi       # 128 mebibytes
      limits:
        cpu: 200m
        memory: 256Mi
```

### What each value means

| Field | Used at | If not set |
|---|---|---|
| `requests.cpu` | Scheduling — guarantees this much CPU | Pod may be scheduled onto a fully-utilized node and get throttled |
| `requests.memory` | Scheduling — guarantees this much memory | Pod may be scheduled onto a node with no free memory and OOMKilled |
| `limits.cpu` | Runtime — throttles above this | Container can use all available CPU |
| `limits.memory` | Runtime — OOMKills above this | Container can use all available memory |

### The difference between CPU and memory enforcement

- **CPU** is compressible. The kernel throttles — the process gets less CPU but keeps running.
- **Memory** is incompressible. The kernel OOMKills the process. There is no "throttle memory" — if you're over your limit, you die.

This is why memory limits are scarier than CPU limits, and why most production workloads set memory `requests == limits` (Guaranteed QoS) for critical Pods.

### Default behavior

If you don't set requests or limits, the Pod is **BestEffort** QoS. The scheduler can place it on any node, and it has no guaranteed resources. This is almost always wrong for production.

For full coverage, see [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|L06 — Resource Requests and Limits]].

---

## 11. Security Context — Per-Container Hardening

`securityContext` lets you apply security constraints at the Pod or container level. In production, every container should have at least these:

```yaml
spec:
  securityContext:                          # pod-level
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault                  # default seccomp, not unconfined
  containers:
  - name: app
    image: app:1.0
    securityContext:                        # container-level
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
```

### What each field does

| Field | Effect |
|---|---|
| `runAsNonRoot: true` | Container refuses to start if the image has USER 0 |
| `runAsUser: <uid>` | Forces the container's main process to run as that UID |
| `runAsGroup: <gid>` | Same, for primary GID |
| `fsGroup: <gid>` | Group ownership of any volumes mounted into the Pod |
| `readOnlyRootFilesystem: true` | Container's root FS is read-only. App must write to a mounted volume. |
| `allowPrivilegeEscalation: false` | Disables setuid binaries and capability escalation |
| `capabilities.drop: ["ALL"]` | Drops all Linux capabilities; opt back in if needed |
| `seccompProfile.type: RuntimeDefault` | Use the runtime's default seccomp filter (much better than unconfined) |

For full coverage, see [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context|L07 — Security Context]].

---

## 12. Volumes and Storage in Pods

Containers in a Pod share **volumes**. A volume is mounted into one or more containers at a path, and the contents are visible to all of them.

```yaml
spec:
  volumes:
  - name: data
    emptyDir: {}                  # ephemeral, lives with the Pod
  - name: config
    configMap:
      name: app-config
  - name: secret
    secret:
      secretName: app-secret
  - name: persistent
    persistentVolumeClaim:
      claimName: app-data
  containers:
  - name: app
    volumeMounts:
    - name: data
      mountPath: /var/lib/app
    - name: config
      mountPath: /etc/app
      readOnly: true
    - name: secret
      mountPath: /etc/app-secrets
      readOnly: true
    - name: persistent
      mountPath: /var/lib/app/db
```

### Volume types

| Type | Lifetime | Use case |
|---|---|---|
| `emptyDir` | Pod lifetime | Scratch space, sidecar-shared data |
| `configMap` | Until ConfigMap changes | App config |
| `secret` | Until Secret changes | Credentials, tokens |
| `hostPath` | Node lifetime (data lives on the node) | node-level agents reading /var/log |
| `persistentVolumeClaim` | Independent of Pod | Databases, durable state |
| `ephemeral` (k8s 1.19+) | Per-Pod, dynamic provisioning | Per-Pod scratch that survives container restarts |
| `gitRepo` (deprecated → `initContainer` clone) | n/a | Don't use this; use an init container |
| `nfs`, `iscsi`, `csi` | Various | External storage backends |

### The emptyDir caveat

`emptyDir` is **lost when the Pod is deleted**. It is not durable. It is for scratch space, shared between containers in a Pod, or for ephemeral data that doesn't need to survive a restart.

For full coverage, see [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim|L05 — PersistentVolumeClaim]].

---

## 13. Pod Scheduling — How the Scheduler Sees a Pod

The scheduler sees a Pod, not the containers inside it. It places the Pod on a node based on:

1. **Resource requests** — the sum of all containers' requests
2. **Node selectors** — `nodeSelector` and `nodeName`
3. **Affinity / anti-affinity** — soft or hard constraints
4. **Taints and tolerations** — "this node repels Pods unless they tolerate the taint"
5. **Topology spread constraints** — spread Pods across zones / nodes
6. **Priority** — `priorityClassName`
7. **Scheduling gates** — `schedulingGates` (k8s 1.27+, defer scheduling)

If the scheduler can't place the Pod, it stays in `Pending` and emits a `FailedScheduling` event:

```
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  12s   default-scheduler  0/5 nodes are available: 3 Insufficient memory, 2 Insufficient cpu.
```

For full coverage, see [[Kubernetes/concepts/L06-scheduling-scaling|L06 — Scheduling and Scaling]].

---

## 14. Pod Disruption — How Pods Get Killed

Pods get killed in three ways:

### 1. Voluntary disruption (you control it)

- `kubectl delete pod`
- Scaling a Deployment down
- Rolling update replacing the Pod
- `kubectl drain <node>` (node maintenance)

For voluntary disruption, a **PodDisruptionBudget** (PDB) sets a floor:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app
spec:
  minAvailable: 2     # always keep at least 2 Pods
  selector:
    matchLabels:
      app: myapp
```

### 2. Involuntary disruption (you don't control it)

- Node failure (hardware, OOM)
- Cluster autoscaler removing a node
- Cloud provider evicting the instance
- Kernel panic

PDBs do **not** protect against involuntary disruption.

### 3. The deletion flow

When a Pod is deleted (voluntary), the order is:

```
1. API server marks Pod for deletion (deletionTimestamp set)
2. PodDisruptionBudget controller counts current disruptions
3. Endpoints controller removes the Pod from Service endpoints
4. kube-proxy / CNI update iptables / routing
5. kubelet sends SIGTERM to all containers (in reverse declaration order)
6. preStop hooks run
7. terminationGracePeriodSeconds elapses
8. SIGKILL if still running
9. Pod object is deleted from etcd
```

The 30-second default grace period is configurable per-Pod. If your app needs longer to drain (e.g., long-polling connections, in-flight uploads), raise it:

```yaml
spec:
  terminationGracePeriodSeconds: 120
```

### The endpoint-removal race

There's a subtle race: the kubelet can send SIGTERM **before** the kube-proxy update propagates, meaning traffic can still hit the dying Pod. The common workaround is the preStop sleep:

```yaml
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 10"]   # let endpoint removal propagate
```

The exact sleep time depends on your cluster size and CNI. AWS Load Balancer Controller docs recommend 5-10 seconds. Bigger clusters may need more.

---

## 15. Pod QoS Classes

Kubernetes assigns every Pod to one of three **Quality of Service** classes based on its resource requests and limits:

| Class | Rule | Treatment |
|---|---|---|
| **Guaranteed** | Every container has `requests == limits` for both CPU and memory | Last to be evicted |
| **Burstable** | At least one container has `requests` set, but not Guaranteed | Evicted after BestEffort, before Guaranteed |
| **BestEffort** | No container has any requests or limits | Evicted first |

### Why it matters

When a node runs out of resources, the kubelet evicts Pods in this order: **BestEffort first, then Burstable, then Guaranteed**. Setting Guaranteed QoS is the most reliable way to ensure your Pod stays up under node pressure.

### The full set of QoS rules

| Container config | QoS |
|---|---|
| `resources: {}` (no requests, no limits) for all containers | **BestEffort** |
| Some requests/limits set, but not equal on all containers | **Burstable** |
| All containers have `requests == limits` for both CPU and memory | **Guaranteed** |

Mixed cases:
- One container with `requests == limits`, another with no requests → **Burstable**
- All containers with `requests == limits` for CPU, but memory not set → **Burstable**

Guaranteed requires **all** containers, **both** resources.

---

## 16. Static Pods — The Outlier

A **Static Pod** is managed directly by the **kubelet** on a specific node, not by the API server. The kubelet reads them from a local manifest directory (default `/etc/kubernetes/manifests/`) and starts them. The API server reflects them as read-only mirrors.

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml on the master
apiVersion: v1
kind: Pod
metadata:
  name: kube-apiserver
spec:
  containers:
  - name: kube-apiserver
    image: registry.k8s.io/kube-apiserver:v1.30
```

Static Pods are how the **control plane itself runs**. `kube-apiserver`, `etcd`, `kube-controller-manager`, `kube-scheduler` are typically static Pods on the control plane nodes. They are also used for node-level agents (like a custom CNI or monitoring agent) that you want to run before the API server is up.

Key properties:

| Property | Detail |
|---|---|
| **Managed by** | kubelet (not a controller) |
| **Stored in** | Local file on a node (not etcd) |
| **API server view** | Mirror, read-only, with `mirror` annotation |
| **Survives** | API server outage. As long as the kubelet is up, the static Pod runs. |
| **Restarted by** | kubelet watches the file. If the file changes, the Pod is recreated. |
| **No controller** | ReplicaSet, Deployment, etc. don't see static Pods. |

For full coverage, see [[Kubernetes/concepts/L03-workloads/11-static-pods|11 — Static Pods]].

---

## 17. Why You Almost Never Write a Bare Pod

In production, a bare `kind: Pod` is a bug:

- **No self-healing** — if the node dies, the Pod stays dead
- **No rolling updates** — you have to delete and recreate by hand
- **No scaling** — you can't scale a single Pod
- **No selector semantics** — Services can't target it predictably

Always use a **controller** (Deployment, StatefulSet, DaemonSet, Job) so something is responsible for keeping the desired number of Pods alive.

### When you DO write a bare Pod

- `kubectl run --rm -it <image> -- <cmd>` — one-off debugging
- `kubectl debug node/<node> -it --image=<img>` — node-level debugging
- Static Pods for control plane components
- Custom controllers that manage their own Pods

The rule of thumb: if a human is going to write the Pod manifest, it should be inside a controller.

---

## 18. Operational Recipes

### Recipe 1: A web app with a log shipper sidecar

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-with-sidecar
  labels:
    app: web
spec:
  containers:
  - name: app
    image: myorg/web:2.1
    ports:
    - name: http
      containerPort: 8080
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 256Mi
    readinessProbe:
      httpGet:
        path: /ready
        port: http
      periodSeconds: 5
    livenessProbe:
      httpGet:
        path: /healthz
        port: http
      periodSeconds: 10
    securityContext:
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  - name: log-shipper
    image: fluent/fluent-bit:3.0
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
      readOnly: true
  volumes:
  - name: logs
    emptyDir: {}
```

### Recipe 2: A Pod that waits for a database, then runs migrations

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
  containers:
  - name: app
    image: myorg/app:2.1
    command: ['./serve']
    readinessProbe:
      exec:
        command: ['/bin/sh', '-c', 'curl -fs http://localhost:8080/healthz']
      initialDelaySeconds: 5
      periodSeconds: 5
```

### Recipe 3: A Pod with a graceful-shutdown sleep

```yaml
spec:
  terminationGracePeriodSeconds: 60
  containers:
  - name: app
    image: myorg/app:2.1
    lifecycle:
      preStop:
        exec:
          command: ["sh", "-c", "sleep 10"]   # let endpoint removal propagate
```

### Recipe 4: A Pod with hard memory limits (Guaranteed QoS)

```yaml
spec:
  containers:
  - name: app
    image: myorg/app:2.1
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 200m
        memory: 256Mi
```

`requests == limits` → Guaranteed QoS → last to be evicted under node pressure.

---

## 19. Gotchas and Common Mistakes

### Pod identity

- **A Pod's UID is not stable across recreations.** Never store it. If the Pod restarts, it gets a new UID, new name (if its name had a hash suffix), and new IP.
- **A Pod's IP is not stable across recreations.** Same reason. Reach Pods through Services, not by IP.
- **Two Pods cannot live on the same node with the same UID** — UID is globally unique.

### Networking

- **Containers in a Pod share the network namespace but not the port space.** Two containers trying to bind `:8080` will conflict.
- **`localhost` traffic never leaves the Pod's namespace.** NetworkPolicy doesn't see it. If you've locked down egress and `localhost` still works, that's why.
- **`hostNetwork: true` bypasses NetworkPolicy entirely.** Avoid for application Pods.

### Resources

- **No requests = BestEffort = first to be killed under pressure.** Always set at least `requests`.
- **Memory limit == death.** A container that exceeds its memory limit is OOMKilled, no warning. Set limits carefully, and monitor `container_memory_failures_total` for OOM events.
- **CPU is throttled, not killed.** A container that exceeds its CPU limit slows down but keeps running. CPU throttling can hurt latency-sensitive apps; raise the limit or fix the app.

### Lifecycle

- **`postStart` runs in parallel with the main process.** Don't depend on it having completed.
- **`preStop` sleep is sometimes necessary** to let endpoint removal propagate. Tune the sleep based on your cluster size.
- **The 30-second termination grace is a default, not a guarantee.** If your app needs longer to drain, set `terminationGracePeriodSeconds`.

### Probes

- **Liveness probes must check internal health only.** A liveness probe that hits a downstream DB will restart the Pod when the DB hiccups. Use readiness for external deps.
- **`failureThreshold: 1` with `periodSeconds: 1` is too aggressive** for production. A single blip kills the container.

### Scheduling

- **A `Pending` Pod is normal only briefly.** If it stays Pending for more than a few minutes, check `kubectl describe pod` for `FailedScheduling` events.
- **The scheduler sees the Pod, not the containers.** Don't try to "balance" containers across nodes — it doesn't work that way.

### Security

- **`runAsNonRoot: true` is a guardrail, not a fix.** It refuses to start the container if the image has USER 0. It doesn't fix the image.
- **`readOnlyRootFilesystem: true` breaks apps that write to `/tmp` or `/var/log`.** Mount writable emptyDir volumes at those paths.

---

## 20. Related Notes

| Topic | Note |
|---|---|
| ReplicaSet (manages Pods) | [[Kubernetes/concepts/L03-workloads/02-replicaset\|02 — ReplicaSet]] |
| Deployment (manages ReplicaSets) | [[Kubernetes/concepts/L03-workloads/03-deployments\|03 — Deployments]] |
| StatefulSet (stable network IDs) | [[Kubernetes/concepts/L03-workloads/04-statefulsets\|04 — StatefulSets]] |
| DaemonSet (one per node) | [[Kubernetes/concepts/L03-workloads/05-daemonset\|05 — DaemonSet]] |
| Job (run to completion) | [[Kubernetes/concepts/L03-workloads/06-job\|06 — Job]] |
| CronJob (scheduled Jobs) | [[Kubernetes/concepts/L03-workloads/07-cronjob\|07 — CronJob]] |
| Init Containers | [[Kubernetes/concepts/L03-workloads/08-init-containers\|08 — Init Containers]] |
| Multi-Container Pods (sidecar/ambassador/adapter) | [[Kubernetes/concepts/L03-workloads/09-multi-container-pods\|09 — Multi-Container Pods]] |
| Probes (liveness/readiness/startup) | [[Kubernetes/concepts/L03-workloads/10-probes\|10 — Probes]] |
| Static Pods | [[Kubernetes/concepts/L03-workloads/11-static-pods\|11 — Static Pods]] |
| Resource requests and limits | [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|L06 — Resource Requests and Limits]] |
| Security context (per-container hardening) | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context\|L07 — Security Context]] |
| Pod networking (CNI, Pod IPs) | [[Kubernetes/concepts/L04-services-networking/01-networking\|L04 — Networking]] |
| Persistent storage (PV/PVC) | [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim\|L05 — PersistentVolumeClaim]] |

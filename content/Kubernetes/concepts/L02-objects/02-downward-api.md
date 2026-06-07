# Downward API

*"https://kubernetes.io/docs/concepts/workloads/pods/downward-api/"*

The Downward API is a way for a **container to read its own metadata** (Pod name, namespace, labels, annotations, resource limits, etc.) at runtime, **without** having to call the Kubernetes API.

It's "downward" because the **control plane pushes data down to the container**, instead of the container pulling from the API.

## Why it exists

Most apps need to know *something* about their own environment:

* "What's my Pod name?" (for logging, for registration with a service registry)
* "What namespace am I in?" (to look up other services in the same namespace)
* "What labels / annotations do I have?" (to know if I'm a canary, what tier I am, etc.)
* "What are my resource limits?" (for sizing a thread pool, cache, etc.)

The "naive" answer is to call the Kubernetes API:

```bash
curl -k https://kubernetes.default.svc/api/v1/namespaces/$POD_NAMESPACE/pods/$POD_NAME \
  -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
```

This works, but it has problems:

* **The container needs API access** (and a ServiceAccount token)
* **It needs to know the API server URL** (well, it can guess `kubernetes.default.svc`)
* **It needs to handle failures, retries, RBAC denials**
* **It's an extra network call** for every piece of metadata
* **It ties the app to k8s** (not great for testing outside k8s)

The Downward API solves all of this by **injecting the data as environment variables or files** at Pod start time.

## Two ways to consume

### 1. Environment variables

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: downward-env
  labels:
    app: web
    tier: frontend
    version: "1.4"
spec:
  containers:
  - name: app
    image: app:1.0
    env:
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: POD_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: NODE_NAME
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
    - name: APP_TIER
      valueFrom:
        fieldRef:
          fieldPath: metadata.labels['tier']
    - name: APP_VERSION
      valueFrom:
        fieldRef:
          fieldPath: metadata.labels['version']
    - name: MEM_LIMIT
      valueFrom:
        resourceFieldRef:
          containerName: app
          resource: limits.memory
          divisor: "1Mi"
    - name: CPU_REQUEST
      valueFrom:
        resourceFieldRef:
          containerName: app
          resource: requests.cpu
          divisor: "1"
```

Inside the container:

```bash
echo $POD_NAME        # downward-env
echo $POD_NAMESPACE   # default
echo $POD_IP          # 10.0.0.42
echo $NODE_NAME       # ip-10-0-1-23
echo $APP_TIER        # frontend
echo $APP_VERSION     # 1.4
echo $MEM_LIMIT       # 256 (in Mi, because divisor was 1Mi)
echo $CPU_REQUEST     # 0.1 (1 = 1 core, 0.1 = 100m)
```

### 2. Files (downwardAPI volume)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: downward-vol
  labels:
    app: web
    tier: frontend
spec:
  containers:
  - name: app
    image: app:1.0
    volumeMounts:
    - name: podinfo
      mountPath: /etc/podinfo
      readOnly: true
  volumes:
  - name: podinfo
    downwardAPI:
      items:
      - path: "labels"
        fieldRef:
          fieldPath: metadata.labels
      - path: "annotations"
        fieldRef:
          fieldPath: metadata.annotations
      - path: "pod-name"
        fieldRef:
          fieldPath: metadata.name
      - path: "pod-namespace"
        fieldRef:
          fieldPath: metadata.namespace
      - path: "memory-limit"
        resourceFieldRef:
          containerName: app
          resource: limits.memory
          divisor: "1Mi"
```

Inside the container:

```bash
ls /etc/podinfo
# annotations  labels  pod-name  pod-namespace  memory-limit

cat /etc/podinfo/labels
# app="web"
# tier="frontend"

cat /etc/podinfo/pod-name
# downward-vol

cat /etc/podinfo/memory-limit
# 256
```

The volume is a **real volume** — updates are reflected if the labels change (subject to the `subPath` caveat — see below). Each file's content is updated when the source field changes.

## What fields you can read

### `fieldRef` (Pod-level fields)

`fieldPath` accepts these paths:

| Path | Value | Notes |
|---|---|---|
| `metadata.name` | Pod name | |
| `metadata.namespace` | Namespace | |
| `metadata.uid` | Pod UID | |
| `metadata.labels['<key>']` | Label value | |
| `metadata.annotations['<key>']` | Annotation value | |
| `metadata.labels` | All labels | File mode only |
| `metadata.annotations` | All annotations | File mode only |
| `spec.nodeName` | Node name | After scheduling |
| `spec.serviceAccountName` | SA name | |
| `spec.priorityClassName` | PriorityClass name | |
| `status.podIP` | Pod IP | After scheduling |
| `status.podIPs` | All Pod IPs (dual-stack) | |
| `status.hostIP` | Node IP | |
| `status.phase` | Pod phase | |
| `status.qosClass` | QoS class | |

You can also traverse containers:

| Path | Value |
|---|---|
| `spec.containers{name}.image` | Image |
| `spec.containers{name}.ports{name}.containerPort` | Port |

### `resourceFieldRef` (resource limits/requests)

| Resource | Value |
|---|---|
| `limits.cpu` | CPU limit |
| `limits.memory` | Memory limit |
| `limits.ephemeral-storage` | Ephemeral storage limit |
| `requests.cpu` | CPU request |
| `requests.memory` | Memory request |
| `requests.ephemeral-storage` | Ephemeral storage request |

With a `divisor` to scale the value:

```yaml
- name: CPU_LIMIT
  valueFrom:
    resourceFieldRef:
      containerName: app
      resource: limits.cpu
      divisor: "1"           # 1 = 1 core; "100m" = millicores
```

Common divisors:

* `"1"` for CPU (yields cores; "1" = 1 core, "100m" = 0.1 core)
* `"1Mi"`, `"1Gi"` for memory
* `"1"` for memory (yields bytes)

## Practical patterns

### Logging: include Pod name in every log line

```yaml
env:
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
```

In your app:

```python
log = logging.getLogger(__name__)
log.info("starting", extra={"pod": os.environ["POD_NAME"]})
```

### Service registration: register with the Pod's identity

```yaml
env:
- name: POD_NAME
  valueFrom: { fieldRef: { fieldPath: metadata.name } }
- name: POD_IP
  valueFrom: { fieldRef: { fieldPath: status.podIP } }
```

The app registers itself with a service registry (Consul, Eureka, etcd, your custom one) using its Pod name and IP.

### Sizing JVM heap from memory limit

```yaml
env:
- name: MEM_LIMIT_BYTES
  valueFrom:
    resourceFieldRef:
      containerName: app
      resource: limits.memory
      divisor: "1"
```

In the JVM args:

```bash
java -XX:MaxRAMPercentage=70.0 -XshowSettings:vm
# the JVM's ergonomics will use the cgroup limit, not MEM_LIMIT_BYTES
```

The JVM is cgroup-aware, so it auto-detects. For non-Java apps, you might do:

```python
import os
mem_bytes = int(os.environ["MEM_LIMIT_BYTES"])
pool_size = mem_bytes // (1024 * 1024 * 100)   # 100 MiB per worker
```

### Canary deployments: read a "version" or "track" label

```yaml
env:
- name: DEPLOY_TRACK
  valueFrom:
    fieldRef:
      fieldPath: metadata.labels['track']
```

The app branches behavior based on whether `DEPLOY_TRACK` is `stable`, `canary`, `experimental`, etc.

### Health check endpoint that exposes metadata

```python
@app.get("/healthz")
def health():
    return {
        "status": "ok",
        "pod": os.environ.get("POD_NAME"),
        "node": os.environ.get("NODE_NAME"),
        "mem_limit": os.environ.get("MEM_LIMIT"),
    }
```

## Gotchas

* **The Downward API does NOT update env vars after Pod start.** Environment variables are set at Pod start and are **static** for the Pod's lifetime. If you want live updates, use the **file** (volume) form.
* **Volume updates propagate, but with a delay.** Files are updated by the kubelet when it sees the field change. There's a small lag (caching, sync period). Don't expect real-time.
* **`subPath` on a downwardAPI volume breaks updates.** Same gotcha as ConfigMap volumes. If you mount a subPath of a downwardAPI volume, the file is static.
* **`fieldRef` paths are case-sensitive** and **must be exact.** `metadata.name` works, `Metadata.Name` doesn't. `status.podIP` works, `status.pod_ip` doesn't. Read the docs carefully.
* **For label / annotation keys with special characters** (dots, dashes, etc.), use the bracket notation: `metadata.labels['my-label']`. Bare `metadata.labels.my-label` doesn't work.
* **`resourceFieldRef` reads the LIMIT, not the actual usage.** A Pod with `limits.memory: 1Gi` always sees `MEM_LIMIT=1073741824`, regardless of how much memory it's actually using. To get actual usage, use the cgroup files directly or a metrics exporter.
* **CPU `resourceFieldRef` returns cores as a decimal.** With `divisor: "1"`, you get `0.1` for 100m, `1.0` for 1 core, `2.0` for 2 cores. Apps that expect integer cores get surprised.
* **The Downward API is for Pod metadata, not arbitrary ConfigMap / Secret values.** For those, use ConfigMap and Secret env vars directly.
* **`metadata.labels` (all labels) only works in the file form, not as an env var.** Same for annotations.
* **The Downward API can't read custom data.** It can only read fields that exist on the Pod / Container spec or status.
* **You can't reference fields that don't exist on the Pod.** For example, you can't read the Pod's `ownerReferences` or `finalizers` via the Downward API. (Use the API server for those.)

## When NOT to use the Downward API

* **Reading data that's not Pod metadata.** ConfigMap / Secret values are easier with `valueFrom: configMapKeyRef` or `secretKeyRef`.
* **Reading arbitrary CRD fields.** Use the API server (or a controller).
* **Reading other Pods' metadata.** Same — use the API server.
* **Real-time data.** The Downward API is at most eventually consistent for the volume form, and never updated for the env-var form. Use a watcher or polling if you need real-time.

## When TO use the Downward API

* **The app needs its own identity** (Pod name, namespace, IP) and you don't want to call the API server
* **The app needs to know its resource limits** (for sizing pools, caches, GC tuning)
* **The app needs to branch behavior on labels / annotations** (track, tier, canary)
* **You want to avoid giving the Pod API access** (security posture)

## Downward API vs ConfigMap

These can look similar, but they're different:

| | Downward API | ConfigMap |
|---|---|---|
| Source of data | Pod's own metadata | A ConfigMap object |
| Updates | Some fields update (file mode only) | Updates propagate (with the `subPath` caveat) |
| Visibility | Pod's own data | Shared across consumers |
| Use case | "Tell me about myself" | "Tell me about external config" |

A common pattern: **the Downward API gives the app its identity; a ConfigMap gives the app its config.**

## See also

* [[Kubernetes/concepts/L03-workloads/01-pods|Pods]] — the Downward API is a Pod-level concept
* [[Kubernetes/concepts/L05-config-storage/01-config-maps|ConfigMaps]] — for non-Pod data
* [[Kubernetes/concepts/L05-config-storage/02-secrets|Secrets]] — for sensitive data
* [[Kubernetes/concepts/L07-security/02-service-accounts|ServiceAccounts]] — when the app does need to call the API

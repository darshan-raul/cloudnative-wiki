# Multi-Container Pods

*"https://kubernetes.io/docs/concepts/workloads/pods/#workload-resources-for-managing-pods"*

A Pod can have **more than one container**. They share:

* Network namespace (same IP, same `localhost`)
* IPC namespace
* Volumes
* Lifecycle (started together, terminated together)

They are scheduled on the **same node**.

## The three patterns

The official k8s docs recognize three standard multi-container patterns. Knowing them by name helps you describe a design without a 5-minute explanation.

### 1. Sidecar

The sidecar is the **most common** pattern. A helper container that extends or enhances the main app container.

```
┌──────────────────────────────┐
│           Pod                │
│  ┌──────────┐  ┌──────────┐  │
│  │   app    │  │ sidecar  │  │
│  │          │  │ (log     │  │
│  │          │  │ shipper) │  │
│  └──────────┘  └──────────┘  │
└──────────────────────────────┘
```

Examples:
* Log shipper (Fluent Bit) reading the app's stdout / shared log volume
* Service mesh proxy (Istio envoy, Linkerd)
* Metrics exporter
* Dapr sidecar

### 2. Ambassador

A container that **proxies network traffic** for the main app, abstracting the outside world.

* The app talks to `localhost:8080` (the ambassador)
* The ambassador figures out where to forward (local broker? remote service? in-cluster?)
* Used in legacy migration: app code is unchanged, ambassador handles the move

### 3. Adapter

A container that **normalizes output** from the main app.

* App emits a custom log format
* Adapter reads the logs and rewrites them in a standard format (JSON, OTLP)
* Used to standardize heterogeneous apps into a single observability backend

## How containers in a Pod communicate

Since they share a network namespace:

* **localhost** — `app` and `sidecar` reach each other on `localhost:8080`
* **Shared volumes** — write to `/shared`, the other reads it
* **IPC** — `System V IPC` and POSIX shared memory

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-sidecar
spec:
  containers:
  - name: app
    image: app:1.0
    volumeMounts:
    - name: shared
      mountPath: /var/log/app
  - name: log-shipper
    image: fluent/fluent-bit:2.2
    volumeMounts:
    - name: shared
      mountPath: /var/log/app
      readOnly: true
  volumes:
  - name: shared
    emptyDir: {}
```

## When NOT to use multiple containers

* **They scale independently** — use two Deployments
* **They have different security profiles** — putting them in the same Pod shares a security context
* **They're on different release cadences** — they shouldn't be coupled at the Pod level

## Gotchas

* **Containers in a Pod share resources.** If one container has a memory leak, the kernel OOM-kills the whole Pod, not just the leaky container. Use `resources.limits` carefully.
* **All containers in a Pod are equal to the scheduler.** The scheduler sees a Pod, not its containers.
* **Sidecars must be in the same manifest as the main app.** Some teams use a sidecar-injector (e.g. Istio, Linkerd) to inject them at admission time.
* **Ordering across containers is the developer's responsibility** in the manifest. The kubelet starts them in declared order. If a sidecar needs to be up before the app, declare it first.
* **Native sidecars** (k8s 1.29+ via `restartPolicy: Always`) get proper ordered start/stop — see [[Kubernetes/concepts/L03-workloads/08-init-containers|init-containers]].

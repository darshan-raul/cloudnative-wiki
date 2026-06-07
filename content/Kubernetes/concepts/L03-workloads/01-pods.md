# Pods

*"https://kubernetes.io/docs/concepts/workloads/pods/"*

A Pod is the **smallest deployable unit** in Kubernetes — not a single container, but a group of one or more containers that:

* Share a **network namespace** (same IP, same `localhost`)
* Share the same **lifecycle** (started together, stopped together)
* Share **volumes** mounted into them
* Live on the **same node**

Pods are ephemeral. They are designed to be replaced, not repaired. A Pod IP is only stable for the lifetime of the Pod.

## The Pod manifest

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
```

In practice you almost never write a bare `kind: Pod` — you wrap it in a controller (Deployment, StatefulSet, etc.) so something is responsible for keeping it alive. Bare Pods are useful for one-off debugging (`kubectl run --rm -it ...`).

## Pod lifecycle phases

```
Pending → Running → Succeeded / Failed / Unknown
```

* **Pending** — accepted by the API server, but one or more containers haven't started (image pull, scheduling, etc.)
* **Running** — at least one container is running
* **Succeeded** — all containers exited with status 0, will not be restarted
* **Failed** — at least one container exited non-zero
* **Unknown** — state can't be obtained (usually a node communication problem)

## Container probes

Three types, all defined under `spec.containers[].livenessProbe` / `readinessProbe` / `startupProbe`:

* **startupProbe** — slow-starting apps. Disables liveness/readiness checks until it succeeds. Use for legacy JVM apps, etc.
* **livenessProbe** — "is this container dead?" If it fails, kubelet restarts the container.
* **readinessProbe** — "is this container ready to serve traffic?" If it fails, the Pod is removed from Service endpoints (but not restarted).

Probe handlers:

```yaml
livenessProbe:
  httpGet:        # HTTP request
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3
# or
exec:
  command: ["cat", "/tmp/healthy"]
# or
tcpSocket:
  port: 3306
```

## Pod lifecycle hooks

```yaml
spec:
  containers:
  - name: app
    image: app:1.0
    lifecycle:
      preStop:
        exec:
          command: ["sh", "-c", "sleep 10"]   # drain in-flight requests
      postStart:
        exec:
          command: ["sh", "-c", "touch /tmp/started"]
```

`preStop` runs before the container is sent SIGTERM — use it to drain connections gracefully.

## Gotchas

* **Two Pods cannot live on the same node with the same UID**, but a Pod's UID changes every time it is recreated. Never store Pod UIDs anywhere.
* **Pods share network but not port conflicts** — if container A binds port 8080 and container B in the same Pod tries to, you'll get an error.
* **Don't add public IPs to Pods** — they're not stable. Reach them via a Service (see L04).
* **A Pod is not restarted when its node dies** — the replacement Pod is a new Pod with a new UID, possibly on a different node.
* **Resource `requests` are used for scheduling, `limits` are enforced at runtime.** See [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|resource-requests-limits]].
* **`kubectl get pod` shows the Pod, not the container.** Use `-c <container>` or `kubectl describe pod` to see per-container status.
* **Static Pods** are managed by kubelet directly, not the API server — see [[Kubernetes/concepts/L03-workloads/11-static-pods|static-pods]].

## Related

* [[Kubernetes/concepts/L03-workloads/03-deployments|Deployments]] — the controller that manages Pods in production
* [[Kubernetes/concepts/L03-workloads/02-replicaset|ReplicaSet]] — the lower-level controller
* [[Kubernetes/concepts/L03-workloads/08-init-containers|init-containers]] — run before app containers start
* [[Kubernetes/concepts/L03-workloads/09-multi-container-pods|multi-container-pods]] — sidecar / ambassador / adapter patterns
* [[Kubernetes/concepts/L03-workloads/10-probes|probes]] — liveness / readiness / startup in depth

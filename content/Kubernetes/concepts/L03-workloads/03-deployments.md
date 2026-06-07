# Deployments

*"https://kubernetes.io/docs/concepts/workloads/controllers/deployment/"*

A Deployment is a **controller that manages a replicated set of Pods**, with **rolling updates**, **rollbacks**, **pauses**, and **scaling**. It owns one or more ReplicaSets; each ReplicaSet owns a set of Pods. This is the **default way to deploy a stateless service** in Kubernetes.

## The Deployment → ReplicaSet → Pod chain

```
Deployment (the user-facing object)
  │
  │ owns
  ▼
ReplicaSet (manages the replicas)
  │
  │ owns
  ▼
Pods (the actual running containers)
```

When you change a Deployment's Pod template:

1. The Deployment controller creates a **new ReplicaSet** with the new template
2. The new RS scales up (replicas move from old to new)
3. The old RS scales down to 0
4. At any point during the rollout, both RSes may have replicas (controlled by `maxSurge` / `maxUnavailable`)

You can see this with:

```bash
# show the RSes owned by a Deployment
kubectl get rs -l app=web
# NAME             DESIRED   CURRENT   READY   AGE
# web-abc          0         0         0       10m
# web-def          3         3         3       2m
```

The old RS (`web-abc`) is kept at 0 replicas, not deleted. This is so you can **roll back** to it.

## Basic example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels:
    app: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%              # can have 25% over desired during update
      maxUnavailable: 25%        # can have 25% under desired during update
  template:
    metadata:
      labels:
        app: web
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
            cpu: 500m
            memory: 256Mi
        readinessProbe:
          httpGet:
            path: /
            port: 80
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 80
          periodSeconds: 30
```

This is the typical "web service" Deployment.

## The key fields

### `spec.replicas`

The desired number of Pods. The Deployment controller ensures the actual count matches.

```bash
kubectl scale deployment web --replicas=10
# or
kubectl patch deployment web -p '{"spec":{"replicas":10}}'
```

HPA (if present) also writes to this field.

### `spec.selector`

**Required, immutable.** Matches the Pods the Deployment owns. Must be unique within a namespace.

If you change the selector, you can't update the Deployment — you have to delete and recreate it.

### `spec.strategy`

How the Deployment rolls out changes:

```yaml
strategy:
  type: RollingUpdate    # or "Recreate"
  rollingUpdate:
    maxSurge: 25%        # how many Pods above replicas can exist during update
    maxUnavailable: 25%  # how many Pods below replicas can be unavailable
```

**`RollingUpdate`** (default):

* Old Pods are killed and replaced one at a time (controlled by `maxSurge` / `maxUnavailable`)
* Zero downtime (assuming `maxUnavailable: 0` is not set)
* Two RSes exist during the rollout

**`Recreate`**:

* All old Pods are killed at once
* New Pods are created
* **Causes downtime** but ensures no two versions run simultaneously
* Useful for stateful apps that can't have two versions running

### `spec.template`

The Pod template. **Any change here triggers a rollout.** The Deployment controller sees the change, creates a new RS with the new template, and rolls out.

```yaml
template:
  spec:
    containers:
    - name: nginx
      image: nginx:1.28   # changed from 1.27 — triggers rollout
```

The change is detected by comparing the template to the **last-applied** template. If anything differs, a rollout starts.

### `spec.minReadySeconds`

How long a Pod must be Ready before the Deployment considers it "successfully rolled out". Default 0.

```yaml
spec:
  minReadySeconds: 30
```

Useful to ensure a Pod stays Ready for a bit before the Deployment moves on (avoids flapping).

### `spec.revisionHistoryLimit`

How many old ReplicaSets to keep around for rollback. Default 10.

```yaml
spec:
  revisionHistoryLimit: 5
```

Each RS uses a small amount of etcd storage. For most apps, 10 is fine. If you have huge RS specs, you might lower it.

### `spec.progressDeadlineSeconds`

How long the Deployment will wait for a rollout to make progress before considering it failed. Default 600s (10 min).

```yaml
spec:
  progressDeadlineSeconds: 300
```

If the rollout doesn't make progress in 5 min, the Deployment is marked as `ProgressDeadlineExceeded`. The rollout continues, but the Deployment is in a "stuck" state.

## Rolling update in detail

Given a Deployment with 3 replicas and a new template:

```
1. The Deployment controller sees the new template
2. It creates a new ReplicaSet ("web-def") with replicas=0
3. It starts scaling up the new RS:
   - maxSurge: 25% of 3 = 0.75, round up = 1
   - So 1 new Pod is created
4. It starts scaling down the old RS ("web-abc"):
   - maxUnavailable: 25% of 3 = 0.75, round up = 1
   - So 1 old Pod is killed
5. Repeat:
   - Old RS: 2 replicas
   - New RS: 1 replica
   Total Pods: 3
6. New RS: 2, Old RS: 1
7. New RS: 3, Old RS: 0
8. Rollout complete
```

The total Pod count is **between 75% and 125%** of the desired count (3 in this case, so 2-4 Pods) at any time.

`maxSurge: 0, maxUnavailable: 1` would mean no extra Pods, but 1 can be down at a time (so 2-3 Pods total).

`maxSurge: 1, maxUnavailable: 0` would mean always exactly 3 Pods, no downtime, but no slack.

## Rollouts and rollbacks

### Triggering a rollout

```bash
# change anything in spec.template
kubectl edit deployment web
# or
kubectl set image deployment/web nginx=nginx:1.28
# or
kubectl patch deployment web -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","image":"nginx:1.28"}]}}}}'
```

The Deployment sees the change and starts a rollout.

### Watching a rollout

```bash
kubectl rollout status deployment/web
# Waiting for deployment "web" rollout to finish: 1 out of 3 new replicas updated...
# Waiting for deployment "web" rollout to finish: 2 out of 3 new replicas updated...
# deployment "web" successfully rolled out
```

### Pausing a rollout

```bash
kubectl rollout pause deployment/web
# make changes (e.g. via patching, which won't trigger rollouts while paused)
# then resume
kubectl rollout resume deployment/web
```

Pausing is useful when you want to make multiple changes and roll them out together.

### Rolling back

```bash
# see the rollout history
kubectl rollout history deployment/web
# REVISION  CHANGE-CAUSE
# 1         <none>
# 2         <none>
# 3         <none>

# see a specific revision's details
kubectl rollout history deployment/web --revision=2

# rollback to the previous revision
kubectl rollout undo deployment/web
# or to a specific revision
kubectl rollout undo deployment/web --to-revision=2
```

The undo creates a new revision (e.g. 4) with the old template. The old RS is still around, so the rollback is fast.

## Update strategies in depth

### `RollingUpdate` — `maxSurge` and `maxUnavailable`

Both are **percentages or absolute numbers**:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 25%             # or "1" (absolute)
    maxUnavailable: 0         # or "0" — zero downtime
```

The math:

```
upperBound = replicas + maxSurge (if percent, ceiling)
lowerBound = replicas - maxUnavailable (if percent, floor)
```

At any time during the rollout:

* Total available Pods ≥ `lowerBound`
* Total ready Pods (old + new) ≤ `upperBound`

For a zero-downtime rollout:

```yaml
rollingUpdate:
  maxSurge: 25%        # can have some extra during the rollout
  maxUnavailable: 0     # but never fewer than desired
```

This is the **safest** for production. It can take longer (more cautious), but no requests fail.

For faster rollouts (accepting brief unavailability):

```yaml
rollingUpdate:
  maxSurge: 1
  maxUnavailable: 1
```

This batches the rollout — kills one old, creates one new at a time, but allows temporary under-replication.

### `Recreate`

```yaml
strategy:
  type: Recreate
```

Kills all old Pods before creating new ones. **Downtime = Pod startup time.**

Useful for:

* Apps that can't have two versions running (e.g. schema migrations)
* Apps with shared state that conflicts during a rollout

Most apps should use `RollingUpdate`.

## Probes and Deployments

Deployments use **probes** to decide if a Pod is "rolled out":

* `readinessProbe` — Pod is "Ready" when this passes
* `livenessProbe` — Pod is restarted when this fails
* `startupProbe` — Pod is "started" when this passes (disables liveness/readiness until then)

A Deployment considers a rollout complete when:

* All new Pods are Ready (or have passed startup + readiness)
* Old Pods are deleted
- `minReadySeconds` has passed since the last new Pod became Ready

**Without a readiness probe, the Deployment has no way to know if the new Pod is actually serving traffic.** It considers the Pod Ready as soon as the container starts. This is usually wrong.

## HPA + Deployments

HPA writes to `spec.replicas`:

```yaml
# HPA
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 2
  maxReplicas: 10
```

HPA's controller and the Deployment's controller both write to `replicas`. HPA wins (it has a controller ref, the Deployment doesn't fight back).

**Don't manually set `replicas` when HPA is enabled.** HPA will overwrite it.

## Pause + multiple changes

The pause + edit pattern is for batched changes:

```bash
kubectl rollout pause deployment/web

# multiple changes
kubectl set image deployment/web nginx=nginx:1.28
kubectl set resources deployment/web -c=nginx --limits=cpu=1,memory=512Mi
kubectl patch deployment web -p '{"spec":{"template":{"spec":{"nodeSelector":{"gpu":"true"}}}}}'

# when done
kubectl rollout resume deployment/web
# ONE rollout starts, applying all changes
```

## The Deployment controller's behavior

The Deployment controller is in `kube-controller-manager`. It:

1. Watches Deployments, ReplicaSets, Pods
2. For each Deployment:
   * Reconciles the current ReplicaSet(s) toward the desired state
   * On template change: creates a new RS, scales it up, scales the old one down
   * On deletion: deletes the owned ReplicaSets (which deletes the Pods)
3. Manages `status.conditions`:
   * `Available` — Deployment has minimum availability
   * `Progressing` — Deployment is making progress (or stuck)
   * `ReplicaSetUpdated` — the latest rollout completed

```bash
kubectl get deployment web -o yaml | grep -A 20 status
# status:
#   availableReplicas: 3
#   conditions:
#   - type: Available
#     status: "True"
#   - type: Progressing
#     status: "True"
#     reason: NewReplicaSetAvailable
#   observedGeneration: 5
#   readyReplicas: 3
#   replicas: 3
#   updatedReplicas: 3
```

## Common patterns

### Blue/Green

Two Deployments, one Service, switch the Service's selector.

```yaml
# blue (current)
apiVersion: apps/v1
kind: Deployment
metadata: { name: web-blue }
spec:
  replicas: 3
  selector: { matchLabels: { app: web, track: blue } }
  template:
    metadata: { labels: { app: web, track: blue } }
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
---
# green (new)
apiVersion: apps/v1
kind: Deployment
metadata: { name: web-green }
spec:
  replicas: 3
  selector: { matchLabels: { app: web, track: green } }
  template:
    metadata: { labels: { app: web, track: green } }
    spec:
      containers:
      - name: nginx
        image: nginx:1.28
---
# Service routes to blue
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  selector: { app: web, track: blue }
  ports:
  - port: 80
```

To switch:

```bash
# green is running, blue is still up (old version)
# switch the Service
kubectl patch service web -p '{"spec":{"selector":{"track":"green"}}}'
# green is now serving
# (blue is still running, in case you need to roll back)

# when confident
kubectl delete deployment web-blue
```

Blue/green gives you **instant rollback** (just switch the Service back) and **zero-downtime deploys** (the new version is fully ready before traffic is shifted).

### Canary

Run a small percentage of new-version traffic.

```yaml
# main: 9 replicas of v1
apiVersion: apps/v1
kind: Deployment
metadata: { name: web-v1 }
spec:
  replicas: 9
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web, version: v1 } }
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
---
# canary: 1 replica of v2
apiVersion: apps/v1
kind: Deployment
metadata: { name: web-v2 }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web, version: v2 } }
    spec:
      containers:
      - name: nginx
        image: nginx:1.28
```

Both Deployments have selectors that match the Service. The Service round-robins to all matching Pods. With 9 v1 + 1 v2, ~10% of traffic goes to v2.

To increase canary traffic, scale up `web-v2` and down `web-v1`. To roll back, delete `web-v2`.

For finer-grained canary (e.g. 5%, 10%, 25% traffic splits), use a service mesh (Istio, Linkerd) or a Gateway API implementation.

### Init containers before the app

```yaml
spec:
  template:
    spec:
      initContainers:
      - name: migrate
        image: migrate:1.0
        command: ['./migrate.sh']
      containers:
      - name: app
        image: app:1.0
```

The init container runs to completion before the app starts. If you have a one-shot migration to run on each rollout, this is where it goes.

## Gotchas

* **The Deployment's selector is immutable.** You can't change it. If you need a different selector, create a new Deployment.
* **Two Deployments can't have overlapping selectors.** This is enforced by the apiserver. If `web-v1` and `web-v2` both match `app: web`, the second `apply` will fail.
* **A Deployment with no Pods is valid.** `replicas: 0` is fine. The Deployment is "scaled to zero".
* **A Deployment with no `selector`** doesn't work. The selector is required.
* **A Deployment's `replicas` is a hint.** The actual count is the sum of its RSes' replicas. Don't be surprised if you see the count differ briefly during a rollout.
* **Pausing a Deployment does not pause the existing rollout.** It only prevents new rollouts from starting. The current one finishes.
* **`maxSurge: 0` is a hard no-no** in most cases. You can't create new Pods before killing old ones, which means you can't deploy. Use `maxSurge: 25%` or similar.
* **The Deployment controller is rate-limited.** With many Deployments, rollouts can be slow. Tune `--deployment-controller-sync-period` on the controller-manager.
* **The `availableReplicas` field in status** is the count of Pods that are **Ready for at least `minReadySeconds`**. It's what you should alert on.
* **`kubectl rollout restart` is the cleanest way to do a "no-change" restart** (e.g. to pick up a new image with the same tag, or to refresh Pods after a secret rotation).
* **The `RollingUpdate` strategy assumes your app handles graceful shutdown.** If it doesn't, you have connection-during-rolling-update issues. Add a `preStop` hook and a `terminationGracePeriodSeconds`.
* **HPA + manual scaling conflicts.** HPA overwrites `replicas` periodically. If you set `replicas: 5` manually with HPA enabled, the HPA will set it back to whatever the metric dictates.
* **Deployments don't do "scale to zero on idle"** natively. Use HPA with `minReplicas: 0` or KEDA.
* **A Deployment that owns a `HostPort`** can't have more replicas than nodes (the port is node-scoped). Use a Service or Ingress instead.
* **The Deployment controller and the StatefulSet controller are similar but separate.** Mixing up which one to use leads to subtle bugs (e.g. PVCs not getting created with a Deployment, or no rolling update with a StatefulSet).

## When to use a Deployment

* **Stateless services** — the default
* **Stateful services that can use a ReplicaSet pattern** — some databases (with careful management)
* **Anything that needs rolling updates and rollbacks** — basically everything

## When NOT to use a Deployment

* **Stable network identity required** — use a StatefulSet
* **One Pod per node** — use a DaemonSet
* **Run-to-completion tasks** — use a Job
* **Scheduled tasks** — use a CronJob
* **Truly stateful with persistent volume per replica** — use a StatefulSet

## See also

* [[Kubernetes/concepts/L03-workloads/02-replicaset|ReplicaSet]] — the lower-level controller
* [[Kubernetes/concepts/L03-workloads/04-statefulsets|StatefulSets]] — when you need stable identity
* [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] — automated scaling
* [[Kubernetes/concepts/L08-operations/01-troubleshooting|Troubleshooting]] — when a Deployment is acting up

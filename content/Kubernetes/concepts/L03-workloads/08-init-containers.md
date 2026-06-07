# Init Containers

*"https://kubernetes.io/docs/concepts/workloads/pods/init-containers/"*

Init containers are **specialized containers that run before app containers** in a Pod. They're used for setup, waiting, and gating — not for the main workload.

## What they do

* Run **one at a time**, in declared order, and **must succeed** before the next one starts
* Run to completion (don't stay running alongside the app)
* Have separate images from the app containers
* Can use different security contexts (e.g. different capabilities)

## Example: wait for a database, then start the app

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

Init containers:

1. Wait for the DB to be reachable
2. Run migrations
3. Then the app container starts

## Common patterns

* **Wait for a dependency** — DB, cache, message broker. Simpler than a sidecar and doesn't keep running.
* **Schema / data migration** — run once before the app boots
* **Git clone / config fetch** — pull configs from a remote source before the app starts
* **Permissions setup** — change ownership of a volume, generate certs
* **Registration / "I'm alive" call** — register the Pod with an external system

## Init containers vs sidecars

| | Init container | Sidecar |
|---|---|---|
| Runs | Once, before app | Alongside app, for the Pod's lifetime |
| Use case | Setup, migration, gating | Logging agent, proxy, metrics shipper |
| Restarted | No (must succeed) | Yes (part of the Pod) |
| Lifetime | Until success | Until Pod terminates |

A sidecar is just a regular container in the Pod manifest. There's no `kind: Sidecar` — it's a pattern, not a primitive.

## Gotchas

* **Init container restart counts separately from app containers.** A flaky init container with a bad `backoffLimit` (or none, in a Pod with no controller) will loop forever — there is no default backoff.
* **Init containers share the Pod's volumes.** Useful for "prepare a volume, app reads it".
* **Init containers don't support `livenessProbe` / `readinessProbe` / `lifecycle`** in the same way. They must exit 0.
* **In a Deployment, init container changes do trigger a rolling update** if their image or command changes.
* **Init container `resources` are NOT shared with the app containers.** They're independent budgets.

## Native sidecars (k8s 1.29+)

As of k8s 1.29, you can declare a sidecar natively with `restartPolicy: Always` on a regular container. This is the right way to run a long-lived sidecar today — it gets ordered lifecycle (sidecar starts before, stops after) without the old "guaranteed to be terminated first" hacks.

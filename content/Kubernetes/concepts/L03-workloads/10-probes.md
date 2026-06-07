# Probes (Liveness, Readiness, Startup)

*"https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/"*

Probes are kubelet's way of knowing whether a container is **alive, ready, and started**. Misconfigured probes are the most common cause of cascading failures and Pod restart loops.

## Three probe types

| Probe | Question it answers | If it fails | When to use |
|---|---|---|---|
| `startupProbe` | "Has the app finished starting?" | Disables other probes; container is killed if it never succeeds | Slow-starting apps (JVM warmup, big data loads) |
| `livenessProbe` | "Is the container still alive?" | Container is killed and restarted | Detect deadlocks, unrecoverable errors |
| `readinessProbe` | "Can the container serve traffic?" | Pod IP removed from Service endpoints (container is not restarted) | Signal "draining" or "warming up"; "not yet ready" |

## Probe handlers

```yaml
livenessProbe:
  httpGet:           # HTTP GET
    path: /healthz
    port: 8080
    httpHeaders:
    - name: X-Probe
      value: kubelet
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 1
  successThreshold: 1
  failureThreshold: 3
```

The other handlers:

```yaml
exec:                  # run a command
  command: ["cat", "/tmp/healthy"]
tcpSocket:             # TCP connect
  port: 3306
gRPC:                  # gRPC health check (k8s 1.24+)
  port: 9090
  service: my-service
```

## Tunables

* `initialDelaySeconds` — wait this long before the first probe (deprecated in favor of `startupProbe`)
* `periodSeconds` — how often to probe (default 10)
* `timeoutSeconds` — probe timeout (default 1, raise for slow apps)
* `successThreshold` — consecutive successes to be considered healthy (default 1, **must be 1 for liveness/startup**)
* `failureThreshold` — consecutive failures before action (default 3)

## Startup vs liveness — when to use which

**Use `startupProbe` for anything that takes >30s to start.** This is the modern recommendation.

```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30
  periodSeconds: 10    # 30 * 10 = 300s to start
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  periodSeconds: 10
  failureThreshold: 3
```

While the startup probe is failing, the kubelet **does not run the liveness probe**. So a slow-starting app gets up to 5 minutes to come up without the kubelet killing it.

## Readiness — the under-appreciated probe

Readiness failure doesn't restart the container. It just **removes the Pod from Service endpoints**. This is the right tool for:

* **Draining traffic during shutdown** — return 503 from `/ready` on SIGTERM
* **Marking "not yet ready" during config reloads**
* **Cascading dependencies** — a pod that depends on a cache returns "not ready" until the cache is warm

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  periodSeconds: 5
  failureThreshold: 2    # be quick to mark unready
```

If you do nothing else with probes, **at minimum set a readinessProbe**. Without it, traffic gets sent to a Pod the moment it accepts a TCP connection — which can be 10+ seconds before the app is actually serving requests.

## Gotchas

* **Liveness probe loops are the #1 cause of cascading failures.** A liveness probe that hits an external dependency (DB, cache) will restart the container when the dependency is briefly down, which makes the situation worse. Liveness must check **internal health only** — readiness is for external dependencies.
* **Don't use `initialDelaySeconds` for slow apps anymore.** Use `startupProbe`. Mixing `initialDelaySeconds` with `periodSeconds` doesn't compose well.
* **A probe handler that takes longer than `timeoutSeconds` counts as a failure.** If your `/healthz` does heavy work, raise the timeout or split it into a lightweight check.
* **`successThreshold` must be 1 for liveness and startup.** You can only fail your way out of being healthy, you can't succeed your way out of being unhealthy.
* **A failing readiness probe doesn't terminate connections** — it just stops new ones. The kubelet does not "drain" in-flight requests; you need `preStop` for that.
* **Probes run from the kubelet, not from a sidecar.** They hit the Pod's IP directly, not via the Service.

## Anti-patterns

* Liveness probe that hits the DB → if the DB hiccups, every Pod restarts at once → service goes down. Use readiness for downstream deps.
* `failureThreshold: 1` with `periodSeconds: 1` → a single missed probe kills the container. Way too aggressive for production.
* Health endpoint that does heavy work → causes CPU spikes under load.
* Probes that return success unconditionally → defeats the purpose.

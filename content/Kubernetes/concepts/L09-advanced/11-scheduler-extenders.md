# Scheduler Extenders

*"https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/"*

A scheduler extender is a **webhook the scheduler calls** to influence scheduling decisions. Out-of-process — you run a service, the kube-scheduler queries it.

This is the right tool when built-in scheduling primitives (taints, affinity, topology spread) can't express your constraint.

## What extenders can do

Three hooks:

* **Filter** — "drop nodes that can't run this Pod" (analogous to Filter in the built-in scheduler)
* **Prioritize (Score)** — "rank the remaining nodes"
* **Preempt** — "evict other Pods to make room"

Most extenders implement filter + prioritize. Preempt is rare and dangerous.

## Webhook protocol

The scheduler sends a JSON payload:

```json
{
  "apiVersion": "v1",
  "kind": "Pod",
  // full Pod spec
}
```

For **filter**:

```json
{
  "apiVersion": "v1",
  "kind": "Nodes",
  "nodes": [
    {"name": "node-1"},
    {"name": "node-2"}
  ]
}
```

For **prioritize**:

```json
{
  "Nodes": {
    "items": [
      {"name": "node-1", "score": 80},
      {"name": "node-2", "score": 30}
    ]
  }
}
```

The scheduler merges the extender's nodes with its own, then scores them. The highest-scoring node wins.

## Configuration

```yaml
# scheduler-config.yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: default-scheduler
  plugins:
    preFilter:
      enabled:
      - name: NodeResourcesFit
    filter:
      enabled:
      - name: NodeResourcesFit
    score:
      enabled:
      - name: NodeResourcesFit
  extenderConfig:
  - urlPrefix: "https://my-extender.svc:8443"
    filterVerb: "filter"
    prioritizeVerb: "prioritize"
    preemptVerb: "preempt"
    weight: 5                    # relative weight of the extender's score
    enableHttps: true
    tlsConfig:
      insecure: false
      certFile: /etc/scheduler/cert.pem
      keyFile: /etc/scheduler/key.pem
      trustedCaFile: /etc/scheduler/ca.pem
    managedResources:
    - name: "example.com/gpu"
      ignoredByScheduler: true     # the scheduler ignores this resource; the extender handles it
    ignorable: false              # if true, the extender failure doesn't block scheduling
```

Then pass `--config=/etc/kubernetes/scheduler-config.yaml` to the kube-scheduler.

## When you'd actually use one

* **Hardware-specific scheduling** — FPGAs, custom accelerators with no built-in support
* **Cloud-cost optimization** — schedule to the cheapest available instance
* **Cluster federation** — pick a node based on cross-cluster state
* **License-aware scheduling** — only schedule to nodes that have an available license
* **Custom hardware health** — a node might be "Ready" to the kubelet but actually degraded in a way only your hardware knows

## Extenders vs custom scheduler

A scheduler extender is **additive** to the default scheduler. The default scheduler still does its thing (filter, score, bind); the extender just influences the decision.

The alternative is a **custom scheduler** — a complete replacement. Much more work; you reimplement everything. **Reach for extenders first.**

## Extenders vs node labels / taints

For most cases, **labels + taints + affinity are enough**. The built-in primitives can express a lot. Only reach for an extender when:

* The decision depends on data the scheduler can't see (license servers, cost APIs, external hardware state)
* The decision is too complex for the label-based model
* You need a numeric score that varies (cost, latency) — affinity is binary

## Gotchas

* **Extenders are on the scheduling hot path.** A slow extender blocks every Pod from scheduling. Same caveats as admission webhooks — small, fast, replicated.
* **`enableHttps: true` and a proper `tlsConfig` are required for production.** Don't run over plain HTTP — the scheduler is sending Pod specs (often with sensitive data).
* **`weight: 5`** is the relative weight of the extender's score vs the default scorers. Tune this to make the extender more or less influential.
* **`managedResources`** is a way to tell the scheduler "don't try to schedule this resource type, the extender handles it". Useful for custom hardware resources.
* **`ignorable: false`** means a failed extender call aborts scheduling. `true` means the scheduler proceeds without the extender's input. Default is `false`; most teams want `true` for resilience.
* **Extenders can't add new node conditions** — they only see the node name and the Pod spec. If you need richer node state, the extender has to fetch it itself (from the API, from a CMDB, etc.).
* **Scheduling Framework plugins (k8s 1.19+)** are the modern alternative. They run in-process (no HTTP) and are Go-native. Higher performance, lower operational burden — but you have to write Go. For most teams, the built-in primitives are enough; for the few that aren't, an extender is fine.
* **Multiple extenders** can be configured. The scheduler calls them in order, then merges. They can interact unpredictably — test carefully.

## Modern alternative: Scheduling Framework

Since k8s 1.19, the **Scheduling Framework** lets you write plugins in Go that run in-process. Plugins are faster (no HTTP), have richer access to the scheduler's state, and are first-class. The down side is you need a custom scheduler build or a scheduler fork.

The trade-off:

* **Extender** — easier, write in any language, hot-path but bearable
* **Framework plugin** — harder, write in Go, much faster, much more powerful

For 95% of use cases, **extenders are enough**. For the remaining 5% (large fleets, custom hardware, performance-critical), the framework is the right answer.

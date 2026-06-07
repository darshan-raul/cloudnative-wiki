# Scheduling (Taints, Tolerations, Affinity, Topology)

*"https://kubernetes.io/docs/concepts/scheduling-eviction/"*

The kube-scheduler decides **which node a Pod runs on**. By default, it picks anything with enough resources. When you need to constrain that — keep Pods off certain nodes, group them together, spread them out — you use the scheduling primitives below.

## The scheduling flow

For every Pod, the scheduler:

1. **Filtering** — drops nodes that can't run the Pod (insufficient resources, taints, affinity mismatch, etc.)
2. **Scoring** — ranks the remaining nodes by how well they match the Pod's preferences
3. **Binding** — assigns the Pod to the highest-scoring node

If the result is zero nodes, the Pod stays `Pending`.

## Node selection primitives

### nodeSelector (simple)

Match nodes by label.

```yaml
spec:
  nodeSelector:
    disktype: ssd
  # pod only schedules on nodes labeled disktype=ssd
```

The `kubernetes.io/os: linux` and similar built-in labels are the most common selectors. You label nodes with `kubectl label node <name> disktype=ssd`.

### Affinity / anti-affinity (richer)

```yaml
spec:
  affinity:
    nodeAffinity:                  # which nodes
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values: ["us-east-1a", "us-east-1b"]
      preferredDuringSchedulingIgnoredDuringExecution:   # soft preference
      - weight: 80
        preference:
          matchExpressions:
          - key: gpu
            operator: Exists

    podAffinity:                   # which other pods
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: cache
        topologyKey: kubernetes.io/hostname
    podAntiAffinity:                # spread pods apart
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: web
        topologyKey: kubernetes.io/hostname
```

* **nodeAffinity** — "run me on a node with these characteristics"
* **podAffinity** — "run me on a node where a Pod matching these labels is already running"
* **podAntiAffinity** — "run me on a node where NO Pod matching these labels is running"

The `IgnoredDuringExecution` suffix is a sore point — these are **scheduling-time** constraints, not steady-state constraints. If you change labels after a Pod is running, the Pod won't be evicted to satisfy the new rules.

### Taints and tolerations (keep pods off nodes)

A taint on a **node** says "repel Pods". A toleration on a **Pod** says "I can tolerate that taint".

```bash
# taint a node
kubectl taint nodes node1 special=true:NoSchedule
```

```yaml
# Pod tolerates the taint
spec:
  tolerations:
  - key: special
    operator: Equal
    value: "true"
    effect: NoSchedule
```

Three effects:

* **`NoSchedule`** — Pods without the toleration won't be scheduled. Existing Pods unaffected.
* **`PreferNoSchedule`** — soft version of `NoSchedule`. Scheduler tries to avoid, but will schedule if necessary.
* **`NoExecute`** — Pods without the toleration are evicted.

Common uses:

* **Reserve nodes for system Pods** — taint control-plane nodes `node-role.kubernetes.io/control-plane:NoSchedule`, only system Pods tolerate it
* **Dedicated GPU nodes** — taint `nvidia.com/gpu=present:NoSchedule`, GPU Pods tolerate it
* **Drain a node gracefully** — add a `NoExecute` taint with a tolerationSeconds so existing Pods get evicted but have time to finish

### Topology spread constraints

Distribute Pods across failure domains.

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: web
```

* **`maxSkew: 1`** — at most 1 more Pod in any zone than the average
* **`topologyKey`** — what counts as a "domain" (zone, region, hostname)
* **`whenUnsatisfiable: DoNotSchedule`** — hard constraint, vs `ScheduleAnyway` (soft)

This is the modern replacement for "spread evenly across zones" — use it instead of multiple `podAntiAffinity` rules.

## Scheduler configuration

The scheduler's behavior is configurable via a `KubeSchedulerConfiguration` object. Two notable customizations:

* **Profiles** — different scheduling behaviors for different Pods (e.g. a "system" profile that packs tightly, vs a "user" profile that spreads)
* **Plugins** — the scheduler is a set of plugins; you can disable / reorder them. For most users this is overkill; the defaults are fine.

## Gotchas

* **`nodeSelector` and `nodeAffinity` are not mutually exclusive** — a Pod can require both.
* **Taints are how you protect nodes, not labels.** A node with no taint will accept any Pod. Taint = "no Pods unless they tolerate".
* **Pod affinity / anti-affinity scale poorly.** With 1000+ nodes and many Pods, the scheduler gets slow. Topology spread constraints are more efficient.
* **Affinity on hostname is the same as "node anti-affinity with the same Pod".** If you want a Pod to NOT land on the same node as another, use `podAntiAffinity` with `topologyKey: kubernetes.io/hostname`.
* **The scheduler is reactive, not proactive.** It only runs when there's something to schedule. There's no constant rebalancing.
* **A `Pending` Pod with no events is usually a scheduling failure** — `kubectl describe pod` will show why.
* **Don't over-constrain.** The more affinity rules, the more likely Pods will be `Pending` and nothing gets scheduled. Defaults are sane.

## When you'd actually change scheduling

* **Multi-tenant cluster** — use taints to dedicate nodes to teams / priority classes
* **High availability** — topology spread constraints across zones
* **Special hardware** — nodeAffinity for GPU / ARM / special storage
* **Performance** — nodeAffinity to keep a Pod's cache hot by staying on the same node (anti-affinity to the same Pod)

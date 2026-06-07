# PodDisruptionBudget (PDB)

*"https://kubernetes.io/docs/concepts/workloads/pods/disruptions/"*

A PodDisruptionBudget **limits how many Pods in a set can be simultaneously unavailable** during voluntary disruption. Voluntary = initiated by a person or a controller (not a node failure, not an OOM).

## What it protects against

* `kubectl drain` (node maintenance, upgrade)
* Cluster autoscaler removing a node
* Operator removing Pods for a rollout
* Admin deleting a Deployment to "see what happens"

What it does NOT protect against:

* Node failure (involuntary)
* Pod OOM / crash
* Cluster-wide outage

The `eviction API` (used by drain / autoscaler) **respects PDBs**. The kubelet does not — a node failure will take down Pods regardless.

## Basic example

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web
spec:
  minAvailable: 2           # or
  # maxUnavailable: 1      # pick one
  selector:
    matchLabels:
      app: web
```

* `minAvailable: 2` — at least 2 Pods must be available at all times during disruption
* `maxUnavailable: 1` — at most 1 Pod can be unavailable at a time
* Use `minAvailable` for "I always need N available" services, `maxUnavailable` for "I can tolerate some being gone"

You can use **percentages** too:

```yaml
spec:
  minAvailable: 75%        # round up
  # maxUnavailable: 25%
```

## The math

PDB + replicas = what's actually safe:

| replicas | minAvailable | maxUnavailable | What happens during a drain |
|---|---|---|---|
| 3 | 2 | 1 | 1 Pod evicted at a time |
| 3 | 1 | 2 | Up to 2 evicted simultaneously |
| 3 | (unset) | (unset) | All 3 can be evicted at once (no protection) |
| 1 | 1 | 0 | The Pod can never be evicted voluntarily — drain won't proceed |

## Gotchas

* **PDB requires a matching Pod selector.** If your selector doesn't match any Pods, the PDB has no effect.
* **PDB is enforced by the eviction API, not by the scheduler.** If you set `maxUnavailable: 0` and the cluster autoscaler wants to scale down a node, it will fail to evict. The autoscaler will retry — but if your PDB is unworkable, the autoscaler gives up.
* **`maxUnavailable: 0` and `minAvailable: replicas` are the same thing** and equally dangerous. The node is unevictable; the autoscaler will leave the node behind.
* **PDB is not a substitute for HPA.** PDB is about availability during planned disruption, not about handling load. You can have 100% availability during a drain and still get killed by traffic spikes.
* **PDB does not block voluntary disruption completely.** It controls the *rate*, not the possibility. A `kubectl delete pod` still works — it just makes the next drain fail.
* **PDB status is reflected in the PDB object itself** — `kubectl get pdb` shows `ALLOWED DISRUPTIONS`. If that's 0, the next drain will block.
* **Eviction API is what drain / autoscaler call.** A forced Pod deletion via `kubectl delete pod --force --grace-period=0` **bypasses the PDB**. Use with caution.

## When to use

* Stateful workloads (databases, queues) — `maxUnavailable: 0` is too strict, but `minAvailable: N-1` makes sense
* Stateless services with HA — `minAvailable: 50%` to keep majority available during drains
* Critical singletons — `minAvailable: 1` with `replicas: 1` means the Pod can't be drained

## When NOT to use

* The Pod has no replicas (replicas=1) and you want it to be drainable — don't set a PDB
* Batch / Job workloads — PDB doesn't really apply
* DaemonSets — PDB is calculated for the DS's Pods, but in practice DSes are designed to live on nodes; just drain and let the DS controller recreate

## What a node drain looks like with PDB

```bash
kubectl drain node-1 --ignore-daemonsets
```

The drain:

1. Cordons the node (no new Pods)
2. Evicts each Pod one at a time
3. For each eviction, checks the PDB — if it would violate, retries with backoff
4. After `--timeout`, gives up and leaves the node with some Pods

Use `--disable-eviction=false` (default true) to allow force-delete after timeout.

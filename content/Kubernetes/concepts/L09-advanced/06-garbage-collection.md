# Garbage Collection

*"https://kubernetes.io/docs/concepts/architecture/garbage-collection/"*

Garbage collection is how Kubernetes **automatically deletes objects** when their owners are deleted, when labels no longer match, or when they've outlived their TTL. It's the cleanup mechanism that keeps etcd from filling up with orphaned resources.

## Three kinds of garbage collection

1. **Owner-reference based** (cascading deletion) — when an owner is deleted, its dependents go too
2. **Label-based** — periodically delete objects whose labels match a selector (used by old controllers)
3. **TTL-based** — delete finished Jobs (and other resources) after a time-to-live

Most "GC" in k8s context means cascading deletion via owner references.

## Owner references

Every object can have an `ownerReferences` field that points to a parent. When the parent is deleted, the children are deleted too.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-abc
  ownerReferences:
  - apiVersion: apps/v1
    kind: ReplicaSet
    name: web
    uid: a1b2c3-d4e5f6-...
    controller: true          # exactly one owner can be "the controller"
    blockOwnerDeletion: true  # (optional) prevent the owner from being deleted while children exist
```

A Pod owned by a ReplicaSet. When the ReplicaSet is deleted, the Pod is deleted automatically.

### `controller: true`

**Only one owner can be the controller.** This is the "primary" owner. The relationship is used to:

* Determine the **controllerRef** in `kubectl get pod -o yaml` (the field that points to the "managing" object)
* Determine which object to scale when you `kubectl scale rs` (the RS is the controller of its Pods)

Other owners in `ownerReferences` are still part of the cascade, just not the "controller".

### `blockOwnerDeletion: true`

If set on a child, the apiserver **prevents the parent from being deleted** until the child is removed. This is a safety mechanism to avoid orphaned dependents.

```bash
# if you have a Pod with blockOwnerDeletion: true, you can't delete the ReplicaSet:
kubectl delete rs web
# Error from server (Forbidden):
#   cannot delete replicasets.apps "web" because it has 3 owning objects
#   (use --cascade=orphan to delete the RS but orphan the Pods)
```

## Cascading deletion

When you delete a parent, the **default behavior** is to delete its dependents too:

```
kubectl delete deployment web
# 1. Deployment "web" is marked for deletion
# 2. ReplicaSets owned by "web" are deleted
# 3. Pods owned by those ReplicaSets are deleted
# 4. PVCs / Services / ConfigMaps owned by the Deployment are deleted
# 5. The Deployment object is removed from etcd
```

You can control this with the `--cascade` flag:

```bash
# default: cascade delete (delete dependents too)
kubectl delete deployment web
kubectl delete deployment web --cascade=true

# orphan: delete the parent but keep the dependents
kubectl delete deployment web --cascade=orphan
# the Deployment is gone, but the RS and Pods remain
```

`--cascade=orphan` is useful for "promoting" a child to standalone (e.g. deleting a ReplicaSet but keeping its Pods).

## The two deletion modes

For cascading deletion, k8s has two modes (set on the parent before deletion):

### Foreground

```yaml
metadata:
  finalizers:
  - foregroundDeletion
```

The parent is marked for deletion but **stays in the API** until all dependents are deleted. The dependents are deleted first, then the parent.

```
1. Parent: deletionTimestamp set, stays visible
2. Dependents: deleted (sequentially or in parallel)
3. Parent: removed from the API
```

Foreground is used by **StatefulSets** and other controllers that need the parent to "stay around" until cleanup is done. Without it, the parent disappears, and any finalizer logic in dependents that wants to look at the parent fails.

### Background (default)

The parent is removed from the API immediately, and dependents are deleted in the background.

```
1. Parent: removed from the API
2. Dependents: deleted in the background (concurrent)
```

Background is faster but loses the ability for dependents to "see" the parent during cleanup.

## Finalizers and GC

Finalizers are **how controllers prevent their objects from being deleted** until the controller does cleanup.

```yaml
apiVersion: v1
kind: Pod
metadata:
  finalizers:
  - example.com/cleanup
```

When you `kubectl delete pod web-abc`:

1. The apiserver sees the finalizer
2. Sets `deletionTimestamp`
3. **Does NOT delete the object yet** — the finalizer must be removed first
4. The controller sees `deletionTimestamp` is set, runs cleanup
5. The controller removes the finalizer
6. The apiserver finally deletes the object

If the controller is broken and the finalizer never gets removed, **the object is stuck**. You can force-delete it (see below).

## Force deletion

If a finalizer is stuck, the apiserver has a way to skip the wait:

```bash
# the delete will complete even if finalizers aren't removed
kubectl delete pod web-abc --force --grace-period=0
```

This sets a special annotation that tells the apiserver to remove the finalizers and delete. **The controller's cleanup logic doesn't run.** Use with caution.

You can also do it via the API:

```bash
# create a tmp patch
kubectl proxy &
curl -X PATCH localhost:8001/api/v1/namespaces/default/pods/web-abc \
  -H "Content-Type: application/merge-patch+json" \
  -d '{"metadata":{"finalizers":null}}'
```

This wipes all finalizers.

## TTL-based GC

The `ttl-after-finished` controller (built into kube-controller-manager) deletes **Jobs** (and CronJobs, ExecutingJobs) after they've been "Finished" for a TTL.

```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: my-job }
spec:
  ttlSecondsAfterFinished: 600      # 10 minutes after completion, delete
  template: ...
```

`Finished` means the Job's Pods have terminated (succeeded or failed). After the TTL, the Job and its Pods are deleted.

This is the **modern, simple alternative** to `successfulJobsHistoryLimit` / `failedJobsHistoryLimit` on CronJobs. Use it for ad-hoc Jobs.

## Label-based GC (mostly historical)

The **old** way to do GC: label-based selectors on controllers that periodically delete objects.

Most of this is gone. **Owner references replaced it** in nearly all cases. The only remaining user-facing label-based GC is the **node-lease** system, but that's internal.

If you're tempted to add a label-based GC, use owner references instead.

## Node GC

The **node controller** (in kube-controller-manager) GC's Nodes that have been unreachable for `--node-monitor-grace-period` (default 40s). Pods on those Nodes are evicted (with `--pod-eviction-timeout`, default 5m).

```bash
# how long before a NotReady Node is considered gone
--node-monitor-grace-period=40s

# how long before Pods on a NotReady Node are evicted
--pod-eviction-timeout=5m
```

This is **involuntary disruption** — Pods are killed without respecting PodDisruptionBudgets. It's the "the node is gone, what do we do" cleanup.

## The "orphaned Pod" gotcha

If a Deployment is deleted with `--cascade=orphan`, its Pods are left running:

```bash
kubectl delete deployment web --cascade=orphan
# Pods are now "orphaned" — no controller, but still running
kubectl get pods -l app=web
# NAME         READY   STATUS    RESTARTS   AGE
# web-abc      1/1     Running   0          30s
# web-def      1/1     Running   0          30s
```

The Pods continue to run, get traffic from their Service, etc. — until something kills them. **This is rarely what you want.** Use `--cascade=orphan` only when you specifically need to detach the children.

## The "stuck finalizer" troubleshooting

A Pod with a stuck finalizer:

```bash
kubectl get pod web-abc -o yaml
# metadata:
#   finalizers:
#   - example.com/cleanup
#   deletionTimestamp: 2024-01-15T12:00:00Z

kubectl describe pod web-abc
# events will show the controller trying to clean up
```

Solutions:

1. **Fix the controller.** If the controller is the broken party, restart it or fix the bug.
2. **Force delete** with `--force --grace-period=0`.
3. **Manually remove the finalizer** (see the curl example above).

The "stuck finalizer" is the #1 cause of "I deleted it but it's still there" issues.

## When to use which deletion mode

| Scenario | Mode | Why |
|---|---|---|
| Deleting a Deployment (default) | Background | Fast, dependents cleaned up automatically |
| Deleting a StatefulSet | Foreground | Pods need to be deleted in order, with stable identity |
| Deleting a CR with custom finalizer | Foreground | The controller needs to see the parent during cleanup |
| Promoting a child to standalone | Orphan (no cascade) | Keep the Pods running, lose the controller |
| Cleaning up after a failed rollout | Orphan (then delete Pods) | Sometimes useful in disaster recovery |

## The interaction with owner references and admission

When a controller creates a child, the **admission chain** checks that the parent exists and the controller has permission to set the owner. If the parent is being deleted (has a `deletionTimestamp`), setting an owner reference to it may be rejected.

Most controllers handle this by checking `deletionTimestamp` before creating the child.

## Gotchas

* **The default for `kubectl delete` is background cascade.** If you want to ensure dependents are deleted before the parent is gone, use foreground (`--cascade=foreground`).
* **Orphaned resources are invisible to their old controller.** A Pod with no owner references doesn't get reconciled by anything. If you want it managed, create a new controller (e.g. a new Deployment with the same selector).
* **Re-creation is slow.** Even with `--cascade=orphan`, the new controller takes time to notice and create new Pods. Have a buffer.
* **Finalizers are not auto-cleaned.** A broken finalizer blocks deletion forever. Add monitoring on `deletionTimestamp + finalizers` to catch this.
* **`blockOwnerDeletion: true` requires the parent to wait for the child.** This can cause unexpected "cannot delete" errors.
* **Cross-namespace owners don't work.** A Pod in `default` can't be owned by a Deployment in `kube-system`. The apiserver rejects it.
* **An owner reference must point to an object that exists.** Pointing to a non-existent UID causes the apiserver to silently drop the owner reference (since k8s 1.20).
* **A namespace's deletion also GCs everything in it.** Deleting a namespace cascades to every namespaced object in it.
* **The default StorageClass's `reclaimPolicy: Delete`** means deleting a PVC deletes the underlying volume. If the PV is owned by a higher-level object (e.g. a StatefulSet's volumeClaimTemplate), the deletion cascade is more complex.
* **The `foregroundDeletion` finalizer is special** — it's added by the apiserver when you set `propagationPolicy: Foreground` on a delete.

## See also

* [[Kubernetes/concepts/L09-advanced/05-finalizers|Finalizers]] — the cleanup hook
* [[Kubernetes/concepts/L09-advanced/02-custom-controllers|Custom Controllers]] — who manages cleanup
* [[Kubernetes/concepts/L03-workloads/04-statefulsets|StatefulSets]] — they need ordered deletion

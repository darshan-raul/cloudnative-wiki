# ReplicaSet

*"https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/"*

A ReplicaSet (RS) is a controller that **maintains a stable set of replica Pods** running at any given time. It's the lower-level controller that a [[Kubernetes/concepts/L03-workloads/03-deployments|Deployment]] manages.

## What it does

* Watches a set of Pods matching a label selector
* Reconciles the actual count toward the desired `replicas` value
* Creates / deletes Pods to match

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: web
        image: nginx:1.27
```

## ReplicaSet vs Deployment

You almost never write a ReplicaSet directly. **Use a Deployment.**

| | ReplicaSet | Deployment |
|---|---|---|
| Self-heal pods | ✓ | ✓ (via the RS it owns) |
| Rolling updates | ✗ | ✓ |
| Rollback | ✗ | ✓ |
| Scaling | ✓ | ✓ (updates the RS) |
| Pause / resume | ✗ | ✓ |

A Deployment owns a ReplicaSet; the RS owns the Pods. Rolling updates work by creating a **new** RS with the new template and scaling the old one down — you can see this with `kubectl get rs`.

## Gotchas

* **`spec.selector` is immutable.** If you need to change it, you must replace the RS (Deployment does this for you automatically).
* **ReplicaSets only work over labels.** A Pod not matching the selector is invisible to the RS.
* **A ReplicaSet can own Pods not created by its `template`** — if a matching Pod already exists, the RS adopts it (it does **not** delete orphans when scaling down). Be careful with selector overlap.
* **You can't use a Deployment-style update strategy on a bare RS.** That's the whole point of Deployment.

## When you'd actually use a bare ReplicaSet

Almost never. The only legitimate uses are:

* Custom controllers that need a fixed number of identical Pods but don't need rolling updates
* Historical artifacts (ReplicationController was the older API; RS replaced it)

For everything else, use a Deployment.

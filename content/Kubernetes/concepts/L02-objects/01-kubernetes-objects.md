# Kubernetes Objects

*"https://kubernetes.io/docs/concepts/overview/working-with-objects/kubernetes-objects/"*

A Kubernetes object is a **persistent entity in the cluster** — a Pod, Deployment, Service, ConfigMap, etc. It's a "record of intent": you declare the desired state, and the cluster's controllers work to make it so.

## The desired-state model

Kubernetes follows a **desired-state controller** pattern:

```
You (or a controller) write desired state to the API
                         │
                         ▼
              ┌─────────────────────┐
              │  kube-apiserver     │
              │  (stores in etcd)   │
              └──────────┬──────────┘
                         │ watches
                         ▼
              ┌─────────────────────┐
              │  controller         │
              │  (reconcile loop)   │
              │                     │
              │  observed state ────┼──── what's actually running
              │  desired state ─────┤──── what you wrote
              │  diff               │
              │  action             │
              └─────────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │  actual cluster     │
              │  (moves toward      │
              │   desired state)    │
              └─────────────────────┘
```

The controller keeps running, watching, diffing, acting. If something drifts from desired state (a Pod dies, a node goes down), the controller notices and fixes it.

## Every object has this structure

```yaml
apiVersion: apps/v1           # which API group and version
kind: Deployment              # what kind of object
metadata:                     # who this object is
  name: web
  namespace: default
  uid: a1b2c3d4-e5f6-7890-abcd-ef1234567890
  resourceVersion: "12345"    # changes on every update (optimistic concurrency)
  generation: 1               # increments on spec change
  labels:
    app: web
  annotations:
    description: "Production web server"
spec:                         # DESIRED state — what you want
  replicas: 3
  selector:
    matchLabels:
      app: web
status:                       # CURRENT state — what the cluster reports
  availableReplicas: 3
  readyReplicas: 3
  replicas: 3
  conditions:
  - type: Available
    status: "True"
```

### `apiVersion`

The API group + version. Kubernetes uses API groups to organize objects:

* `v1` — core objects (Pod, Service, Namespace, Node, PersistentVolume, etc.)
* `apps/v1` — apps objects (Deployment, ReplicaSet, StatefulSet, DaemonSet)
* `batch/v1` — batch (Job, CronJob)
* `networking.k8s.io/v1` — networking (Ingress, NetworkPolicy)
* `rbac.authorization.k8s.io/v1` — RBAC (Role, ClusterRole, RoleBinding)
* `policy/v1` — PodDisruptionBudget
* `storage.k8s.io/v1` — StorageClass
* Custom groups: `mycompany.com/v1`, `metrics.k8s.io/v1beta1`, etc.

### `kind`

The object type. Examples: Pod, Deployment, Service, ConfigMap, Secret, Ingress, Role, ServiceAccount, etc.

### `metadata`

**Identity and bookkeeping:**

* `name` — unique within a namespace (or cluster-wide for cluster-scoped objects)
* `namespace` — for namespaced objects; ignored for cluster-scoped objects
* `uid` — globally unique, assigned by the API server; survives across updates
* `resourceVersion` — the version of the object in etcd; used for optimistic concurrency (if you try to PATCH an old version, you get a conflict)
* `generation` — increments when the `spec` changes; `status.observedGeneration` shows which generation the controller has processed
* `labels` — key-value pairs for organizing and selecting objects
* `annotations` — non-identifying key-value pairs for tooling and metadata (not used by selectors)
* `creationTimestamp` — when the object was created
* `deletionTimestamp` — set when deletion starts (if a finalizer is present)
* `finalizers` — a list of strings that must be removed before deletion completes
* `ownerReferences` — references to parent objects (for cascading deletion and GC)

### `spec`

The **desired state** — what you want. The format is different for every `kind`. The apiserver validates it against the CRD's schema.

The `spec` is what you write. It's what you control.

### `status`

The **current state** — what the cluster reports. You don't write this; controllers update it. The apiserver stores it; you read it.

The `status` is read-only from the user's perspective. You can read it with `kubectl get`, but you don't usually write it directly (except for a few objects like Pod status, which is written by the kubelet).

## Labels and selectors

Labels are key-value pairs attached to objects:

```yaml
metadata:
  labels:
    app: web
    tier: frontend
    environment: production
    version: v1.2.3
```

Selectors filter objects by labels:

```bash
# filter Pods by label
kubectl get pods -l app=web,tier=frontend
kubectl get pods -l 'app in (web, api)'
kubectl get pods -l 'app notin (web)'

# filter Deployments
kubectl get deployment -l environment=production
```

Labels are how Services find the Pods they route to:

```yaml
spec:
  selector:
    app: web          # routes to Pods with label app=web
```

Labels are how Deployments find the Pods they manage:

```yaml
spec:
  selector:
    matchLabels:
      app: web        # owns Pods with label app=web
```

### Label format rules

* Keys: alphanumeric, optionally with a prefix + `/` (e.g. `app.kubernetes.io/name`)
* Values: max 63 chars, alphanumeric, `-`, `_`, `.`
* Prefixes are optional; if omitted, the label is considered private to the user
* Reserved prefixes: `kubernetes.io/`, `k8s.io/`

## Annotations

Annotations are like labels but **not used for selection**:

```yaml
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"kind":"Deployment","apiVersion":"apps/v1",...}
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
    description: "Frontend web server for the production site"
```

Typical uses:

* **Last-applied configuration** — set by `kubectl apply` to compute diffs
* **Tooling metadata** — Prometheus scrape configs, Git commit SHAs, CI pipeline IDs
* **Human-readable descriptions** — for documentation in `kubectl describe`

The difference: **labels are for selection**, **annotations are for everything else**.

## Namespaces

Namespaces partition the cluster into virtual clusters:

```bash
kubectl get namespaces
# NAME              STATUS   AGE
# default           Active   300d
# kube-node-lease   Active   300d
# kube-public       Active   300d
# kube-system       Active   300d
# monitoring        Active   100d
# production        Active   50d
```

Most objects are namespaced (Pod, Deployment, Service, etc.). Some are cluster-scoped (Node, PersistentVolume, ClusterRole, etc.).

```bash
# list namespaced objects
kubectl api-resources --namespaced=true

# list cluster-scoped objects
kubectl api-resources --namespaced=false
```

Namespaces provide:

* **Scope** — `name` only needs to be unique within a namespace
* **RBAC** — RoleBindings are namespace-scoped; ClusterRoles are cluster-scoped
* **Resource quotas** — limit CPU/memory per namespace
* **NetworkPolicy** — scope of a NetworkPolicy
* **DNS** — Services in a namespace get short DNS names; cross-namespace needs the full FQDN

## How to create objects

### Imperative (fast, for exploration)

```bash
kubectl run web --image=nginx --replicas=3
kubectl expose deployment web --port=80
kubectl create namespace production
kubectl label namespace production environment=production
```

### Declarative (preferred, for production)

Write YAML and apply it:

```yaml
# web.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  ...
```

```bash
kubectl apply -f web.yaml          # create or update
kubectl diff -f web.yaml           # see what would change
kubectl replace -f web.yaml        # replace (fails if changed since you read it)
kubectl delete -f web.yaml         # delete
```

`apply` is idempotent — running it twice doesn't break anything. It's the basis of GitOps.

### Dry-run

```bash
# validate the YAML without creating anything
kubectl apply -f web.yaml --dry-run=server

# see what would be created (client-side)
kubectl apply -f web.yaml --dry-run=client

# dry-run output the object
kubectl apply -f web.yaml --dry-run=client -o yaml
```

## How to read objects

```bash
# get in YAML
kubectl get pod web -o yaml

# get in JSON
kubectl get pod web -o json

# get just the status
kubectl get pod web -o jsonpath='{.status}'

# get all fields
kubectl get pod web -o wide

# describe (human-friendly)
kubectl describe pod web

# get in a specific namespace
kubectl get pod -n kube-system

# get all namespaces
kubectl get pod -A

# watch (live updates)
kubectl get pods -w

# get with custom columns
kubectl get pods -o custom-columns=NAME:.metadata.name,READY:.status.conditions[?(@.type=='Ready')].status,NODE:.spec.nodeName
```

## Object deletion

```bash
kubectl delete deployment web
kubectl delete -f web.yaml
kubectl delete pods --all           # delete all Pods (careful!)
kubectl delete pods -l app=web      # delete Pods matching label
```

Deletion is cascading by default (the Deployment's Pods are deleted too). Use `--cascade=orphan` to keep the Pods.

## Garbage collection

When an owner object is deleted, its dependent objects are deleted too (unless `--cascade=orphan`):

```bash
kubectl delete deployment web --cascade=orphan   # keep the Pods
kubectl delete deployment web                    # delete the Deployment AND its Pods
```

The "owner" is determined by `ownerReferences` on the dependent. Controllers set this automatically.

## Common field errors

### `field is immutable`

```bash
# Error: field is immutable
# spec.selector is immutable after creation
```

The selector on a Deployment (or Job, etc.) can't be changed after creation. Recreate the object.

### `object has been modified`

```bash
# Error: Apply failed with Conflict: 2 errors occurred:
# * object has been modified; please apply your changes to the latest version
```

Someone else changed the object since you last read it. Re-read and re-apply.

### `invalid type`

```yaml
# Error: spec.replicas in body must be of type integer
spec:
  replicas: "3"    # wrong: string
  # replicas: 3    # correct: integer
```

YAML distinguishes strings from integers. `replicas` must be an integer.

## The object life cycle

```
1. You write YAML, run kubectl apply
   │
2. kubectl POSTs to apiserver (or PUT/PATCH)
   │
3. apiserver validates, stores in etcd
   │
4. controller notices the new object (via watch)
   │
5. controller creates dependent resources (e.g. Pods from a Deployment)
   │
6. controller updates .status
   │
7. Pods are scheduled, containers start
   │
8. controller updates .status.conditions (Ready, etc.)
   │
9. if you update the YAML and re-apply:
   │
10. controller notices the change
    │
11. controller reconciles toward new desired state
    │
12. on delete: finalizers run (if any), then object is removed
```

## See also

* [[Kubernetes/concepts/L03-workloads/01-pods|Pods]] — the fundamental workload unit
* [[Kubernetes/concepts/L03-workloads/03-deployments|Deployments]] — managing replicated Pods
* [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — networking Pods
* [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CRDs]] — extending the object model
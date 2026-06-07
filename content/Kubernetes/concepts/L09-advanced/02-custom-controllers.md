# Custom Controllers

*"https://kubernetes.io/docs/concepts/architecture/controller/"*

A custom controller is a **control loop** that watches the state of the cluster and makes changes to move the actual state toward the desired state. Every useful thing in k8s is a controller — Deployments, ReplicaSets, StatefulSets, DaemonSets, Jobs, the cloud-controller-manager. Custom controllers are how you add your own.

## The control loop in one sentence

```
Observe → Diff → Act → Repeat
```

The controller:

1. **Observes** the current state of the cluster (via the apiserver's watch API)
2. **Diffs** it against the desired state (in a Spec somewhere — a Deployment, a CR, etc.)
3. **Acts** to make the actual state match the desired (create / update / delete resources)
4. **Repeats**, usually with a small delay between iterations

This is a **reconciliation loop**. The controller "reconciles" the actual state toward the desired state.

## The pattern, step by step

```
┌──────────────────────────────────────────────────────┐
│  desired state: Deployment with replicas=3           │
└────────────────────────┬─────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  Watch Deployments   │  ← controller subscribes
              │  via the apiserver   │
              └──────────┬───────────┘
                         │ event: deployment "web" updated
                         ▼
              ┌──────────────────────┐
              │  Enqueue work item   │
              │  (workqueue)         │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  Worker picks up     │
              │  the work item       │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  Reconcile()         │
              │                      │
              │  1. Get current      │
              │  2. Diff vs desired  │
              │  3. Create/update/   │
              │     delete           │
              │  4. Update status    │
              │  5. Requeue          │
              └──────────┬───────────┘
                         │
                         ▼
                    (repeat)
```

The **Reconcile** function is the heart. It should be **idempotent** — calling it multiple times with the same desired state should produce the same result.

## What every custom controller has

Whether you use kubebuilder, operator-sdk, or write one from scratch, the pieces are:

### 1. Informer

An **informer** watches a resource type and maintains a **local cache** of the current state. It also emits events (add, update, delete) for changes.

```go
// pseudo-code
informer := factory.Apps().V1().Deployments().Informer()
informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
    AddFunc:    func(obj interface{}) { enqueue(obj) },
    UpdateFunc: func(old, new interface{}) { enqueue(new) },
    DeleteFunc: func(obj interface{}) { enqueue(obj) },
})
```

The informer's local cache means the controller doesn't hammer the apiserver for every reconcile. It reads from the cache; writes go through the apiserver.

### 2. Workqueue

A **rate-limited FIFO queue** of work items (object keys like "namespace/name") to be reconciled. The controller has one or more workers pulling items off the queue.

```go
queue := workqueue.NewRateLimitingQueue(workqueue.DefaultControllerRateLimiter())
// workers
for i := 0; i < workers; i++ {
    go func() {
        for {
            key, _ := queue.Get()
            process(key)
            queue.Done(key)
        }
    }()
}
```

If a work item fails, it's requeued with **exponential backoff**. This prevents a flapping resource from drowning the controller.

### 3. Reconciler

The `Reconcile(ctx, req)` function. Given a request (an object key), it does the work.

```go
func (r *MyReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. Fetch the object
    obj := &myv1.MyResource{}
    if err := r.Get(ctx, req.NamespacedName, obj); err != nil {
        if apierrors.IsNotFound(err) {
            return ctrl.Result{}, nil   // gone, nothing to do
        }
        return ctrl.Result{}, err
    }

    // 2. Reconcile owned resources
    if err := r.reconcileDeployment(ctx, obj); err != nil {
        return ctrl.Result{}, err
    }
    if err := r.reconcileService(ctx, obj); err != nil {
        return ctrl.Result{}, err
    }

    // 3. Update status
    obj.Status.Ready = true
    if err := r.Status().Update(ctx, obj); err != nil {
        return ctrl.Result{}, err
    }

    // 4. Requeue if periodic reconciliation is needed
    return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}
```

The **return values** are important:

* `ctrl.Result{}` — done, don't requeue
* `ctrl.Result{Requeue: true}` — done, requeue immediately
* `ctrl.Result{RequeueAfter: 30 * time.Second}` — done, requeue in 30s
* `(result, err)` with `err != nil` — failed, requeue with backoff

### 4. Owner references

When the controller creates sub-resources (Deployments, Services, etc.), it sets **`metadata.ownerReferences`** to the parent CR. This makes garbage collection work:

* When the parent CR is deleted, the sub-resources are deleted automatically
* The controller's finalizer logic runs before deletion (see below)

```go
dep := &appsv1.Deployment{...}
if err := ctrl.SetControllerReference(parent, dep, r.Scheme); err != nil {
    return err
}
if err := r.Create(ctx, dep); err != nil {
    return err
}
```

### 5. Finalizers

When a CR is deleted, the apiserver doesn't immediately remove it — it waits for the controller to do cleanup. **Finalizers** are the mechanism.

```go
const myFinalizer = "mycontroller.example.com/finalizer"

func (r *MyReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    obj := &myv1.MyResource{}
    if err := r.Get(ctx, req.NamespacedName, obj); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // If being deleted, run finalizer logic
    if !obj.DeletionTimestamp.IsZero() {
        if containsString(obj.Finalizers, myFinalizer) {
            // Run cleanup
            if err := r.cleanup(ctx, obj); err != nil {
                return ctrl.Result{}, err
            }
            // Remove our finalizer
            obj.Finalizers = removeString(obj.Finalizers, myFinalizer)
            if err := r.Update(ctx, obj); err != nil {
                return ctrl.Result{}, err
            }
        }
        return ctrl.Result{}, nil
    }

    // Add finalizer if not present
    if !containsString(obj.Finalizers, myFinalizer) {
        obj.Finalizers = append(obj.Finalizers, myFinalizer)
        if err := r.Update(ctx, obj); err != nil {
            return ctrl.Result{}, err
        }
        // requeue to do the actual reconciliation
        return ctrl.Result{Requeue: true}, nil
    }

    // ... normal reconciliation
}
```

The flow:

1. User deletes the CR
2. Apiserver sees `deletionTimestamp` is set, but a finalizer is present
3. The CR stays in `Terminating` state
4. The controller sees the deletion, runs cleanup
5. The controller removes the finalizer
6. The apiserver deletes the CR

Without finalizers, deletion happens immediately and the controller's cleanup never runs. **Always add a finalizer if you have external resources to clean up.**

### 6. Leader election

A controller can run as multiple replicas for HA, but only one is **active** at a time. **Leader election** is the mechanism.

```go
mgr, err := ctrl.NewManager(cfg, ctrl.Options{
    LeaderElection:          true,
    LeaderElectionID:        "my-controller-leader",
    LeaderElectionNamespace: "kube-system",
})
```

If the active leader dies, another replica takes over. The transition takes a few seconds (lease TTL).

### 7. RBAC

The controller needs permission to read the CRs it watches and create / update the resources it manages. You declare this in a `ClusterRole` and bind it to the controller's ServiceAccount.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: my-controller }
rules:
- apiGroups: [mygroup.example.com]
  resources: [myresources, myresources/status]
  verbs: [get, list, watch, update, patch]
- apiGroups: [apps]
  resources: [deployments]
  verbs: [get, list, watch, create, update, patch, delete]
- apiGroups: [""]
  resources: [services, configmaps, secrets]
  verbs: [get, list, watch, create, update, patch, delete]
- apiGroups: [coordination.k8s.io]
  resources: [leases]
  verbs: [get, list, watch, create, update, patch, delete]  # for leader election
```

The blast radius of a controller is its RBAC. Keep it minimal.

## The simplest possible controller (in Python with kopf)

```python
import kopf

@kopf.on.create('example.com', 'v1', 'foos')
def create_fn(spec, name, namespace, **kwargs):
    # create a Deployment for this Foo
    deploy = client.AppsV1Api().create_namespaced_deployment(
        namespace=namespace,
        body={
            'metadata': {'name': f'{name}-deploy'},
            'spec': {
                'replicas': spec.get('replicas', 1),
                'selector': {'matchLabels': {'app': name}},
                'template': {
                    'metadata': {'labels': {'app': name}},
                    'spec': {
                        'containers': [{
                            'name': 'foo',
                            'image': spec['image'],
                        }],
                    },
                },
            },
        },
    )
    return {'deployment': deploy.metadata.name}

@kopf.on.update('example.com', 'v1', 'foos')
def update_fn(spec, status, name, namespace, **kwargs):
    # update the Deployment
    patch = {'spec': {'replicas': spec.get('replicas', 1)}}
    client.AppsV1Api().patch_namespaced_deployment(
        name=f'{name}-deploy', namespace=namespace, body=patch,
    )

@kopf.on.delete('example.com', 'v1', 'foos')
def delete_fn(spec, name, namespace, **kwargs):
    # cleanup (if needed)
    pass
```

`kopf` (Kubernetes Operator Pythonic Framework) is the easiest entry point for Python controllers.

## The simplest possible controller (in Go with kubebuilder)

Kubebuilder generates the boilerplate. You write the Reconcile:

```go
func (r *FooReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    foo := &examplev1.Foo{}
    if err := r.Get(ctx, req.NamespacedName, foo); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // your logic here

    return ctrl.Result{}, nil
}

func (r *FooReconciler) SetupWithManager(mgr ctrl.Manager) error {
    return ctrl.NewControllerManagedBy(mgr).
        For(&examplev1.Foo{}).
        Owns(&appsv1.Deployment{}).
        Complete(r)
}
```

`For` is the primary watch; `Owns` is a secondary watch for resources we own.

## Status subresource

A CRD can have a separate `.status` field (the "status subresource"):

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
spec:
  versions:
  - name: v1
    subresources:
      status: {}      # <-- this enables the subresource
```

With this:

* Users PUT to `.spec` (to change the desired state)
* The controller PUTs to `.status` (to report the actual state)
* They're separate operations, so a user updating `.spec` doesn't accidentally clobber `.status`

## Generation and observed generation

The apiserver maintains a `metadata.generation` field that increments on every spec change. The controller reads `.status.observedGeneration` to know which spec it last reconciled.

```go
if foo.Status.ObservedGeneration != foo.Generation {
    // spec has changed since we last reconciled
    // re-reconcile
}
```

This is a simple way to detect "the user changed something, I need to re-process".

## Conditions

A `status.conditions` array is the standard way to report per-aspect health:

```go
foo.Status.Conditions = []metav1.Condition{
    {
        Type: "Ready",
        Status: metav1.ConditionTrue,
        Reason: "AllReplicasReady",
        Message: "3/3 replicas are ready",
        LastTransitionTime: metav1.Now(),
    },
    {
        Type: "Progressing",
        Status: metav1.ConditionTrue,
        Reason: "Reconciling",
        Message: "Scaling up to 5 replicas",
        LastTransitionTime: metav1.Now(),
    },
}
```

Tools like `kubectl get foo foo-1 -o yaml` show this. `kubectl wait --for=condition=Ready` can wait on it.

## Event recording

Controllers should record **Events** for important things ("scaled up from 3 to 5", "failed to create Service"):

```go
r.Recorder.Event(foo, corev1.EventTypeNormal, "Scaled", "Scaled up from 3 to 5 replicas")
r.Recorder.Eventf(foo, corev1.EventTypeWarning, "Failed", "Could not create Service: %v", err)
```

`kubectl describe foo foo-1` shows the events. They're also shipped to log aggregators.

## Metrics

Controllers should expose Prometheus metrics. The most common:

* `controller_runtime_reconcile_total` — total reconciles by result (success / error)
* `controller_runtime_reconcile_errors_total` — errors
* `controller_runtime_reconcile_time_seconds` — histogram of reconcile duration
* `workqueue_depth` — current workqueue depth
* `workqueue_latency_seconds` — time in workqueue

These are the basics; a custom controller can add more (e.g. `foo_replicas_desired`, `foo_replicas_ready`).

## The full controller stack

A real production controller has all of this:

```
┌─────────────────────────────────────────────────┐
│  Deployment (controller-manager)                │
│  ├─ pod: my-controller-abc                      │
│  │                                             │
│  │  my-controller process                      │
│  │  ├─ Manager (controller-runtime)             │
│  │  │  ├─ Leader election                      │
│  │  │  ├─ Metrics server (Prometheus)          │
│  │  │  ├─ Health probe                         │
│  │  │  ├─ Cache (informers)                    │
│  │  │  └─ Reconciler(s)                        │
│  │  │     ├─ Informer for primary CR            │
│  │  │     ├─ Informer for owned resources       │
│  │  │     ├─ Workqueue                          │
│  │  │     ├─ Reconcile loop                     │
│  │  │     ├─ Event recorder                     │
│  │  │     └─ Status updater                     │
│  │  │                                          │
│  │  └─ /metrics endpoint                        │
│  │  └─ /healthz endpoint                       │
│  │                                             │
│  ServiceAccount: my-controller                  │
│  ClusterRole + ClusterRoleBinding:              │
│    - read CRs                                   │
│    - create / update owned resources            │
│    - leases (for leader election)               │
│    - events (for recording)                     │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Common controller mistakes

### 1. Not setting owner references

```go
// WRONG — the sub-resource has no owner
r.Create(ctx, deployment)

// RIGHT — set the owner so GC works
ctrl.SetControllerReference(parent, deployment, r.Scheme)
r.Create(ctx, deployment)
```

### 2. Not using finalizers

If the controller creates external resources (e.g. a cloud DB instance), and doesn't add a finalizer, deleting the CR leaves the cloud resource orphaned.

### 3. Reconciling the wrong object

Reconciling on every update is wasteful. Reconcile on the **object you care about** (the CR), not on every dependent.

### 4. Forgetting `RequeueAfter`

If your controller needs periodic reconciliation (e.g. to check health), return `RequeueAfter`. Otherwise it only runs when something changes.

### 5. Long-running reconciliations

A Reconcile that takes 10 minutes blocks the workqueue. Move long operations to a separate goroutine or use Jobs.

### 6. Reading directly from the apiserver

Use the **local cache** (informers). Reading from the apiserver in every reconcile is slow and adds load.

### 7. Tight requeue loops

If you requeue with no delay, the controller loops fast. Use `RequeueAfter` to slow down.

### 8. No status updates

If `.status` never updates, users can't tell if the controller is working. Update it.

## When to write a controller

* **You have a custom resource that needs to do something** — write a controller
* **You're managing an application's lifecycle** — write a controller
* **You want to extend k8s with new behavior** — write a controller
* **You have automation that runs in CI** — it can be a controller, but it might not need to be

## When NOT to write a controller

* **You can do it with a CronJob + kubectl** — don't write a controller
* **You can do it with an admission webhook** — admission is sync, controllers are async
* **The upstream project provides one** — use it
* **You don't have Go / Python / Java skills on the team** — find an operator that does what you need

## See also

* [[Kubernetes/concepts/L09-advanced/01-operators|Operators]] — when controllers encode operational knowledge
* [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CRDs]] — the API extension
* [[Kubernetes/concepts/L09-advanced/05-finalizers|Finalizers]] — for cleanup
* [[Kubernetes/concepts/L09-advanced/06-garbage-collection|Garbage Collection]] — owner references

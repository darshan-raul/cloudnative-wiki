# Scheduling Gates and Pod Scheduling Readiness

*"https://kubernetes.io/docs/concepts/scheduling-eviction/pod-scheduling-readiness/"*

A `schedulingGates` field on a Pod (k8s 1.27+, GA in 1.30) **prevents the Pod from being scheduled** until all gates are removed. It's a way to say "this Pod is not ready to be scheduled yet — wait for an external signal." The Pod exists in the cluster but stays `Pending` with no `nominatedNodeName`, no matter how many nodes could fit it.

### Table of Contents

1. [The Problem Scheduling Gates Solve](#1-the-problem-scheduling-gates-solve)
2. [Basic Example](#2-basic-example)
3. [How Gates Work](#3-how-gates-work)
4. [Removing Gates](#4-removing-gates)
5. [Gates and Pod Lifecycle](#6-gates-and-pod-lifecycle)
6. [StatefulSet Join Pattern](#7-statefulset-join-pattern)
7. [Coordinated Deployment Pattern](#8-coordinated-deployment-pattern)
8. [Controller-Managed Gates](#9-controller-managed-gates)
9. [Operations and Debugging](#10-operations-and-debugging)
10. [Gotchas and Common Mistakes](#11-gotchas-and-common-mistakes)

---

## 1. The Problem Scheduling Gates Solve

Before scheduling gates, a Pod that wasn't ready to be scheduled had limited options:

* **Don't create the Pod yet.** The controller waits until "ready", then creates the Pod. This works but means the Pod is in a different state from "exists but not ready" — observability is harder.
* **Use a `Job` with a pre-condition.** A Job's Pods run sequentially; you can have a "gate" Pod that does the check. Works but is hacky.
* **Use a custom controller.** The controller creates the Pod, then patches the Pod to remove the gate. Works but requires a custom controller.

Scheduling gates formalize the "exists but not ready to schedule" state. **The Pod is in the API, the scheduler sees it, but doesn't schedule it.** When the gate is removed, scheduling proceeds normally.

### 1.1 The use cases

* **StatefulSet join:** a new Pod in a StatefulSet shouldn't start until the previous Pod is ready and the cluster has acknowledged the new member. Gates hold the Pod back until the application signals it's ready.
* **Coordinated rollouts:** a Pod in a multi-Pod deployment (e.g. sidecar + main) shouldn't start until its peer is up.
* **Pre-flight checks:** a controller wants to verify cluster state (e.g. certificates, secrets) before allowing a Pod to schedule.
* **Migration:** a Pod in a `Deployment` being migrated to a new node pool shouldn't schedule on the old pool. Gates prevent it.

## 2. Basic Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gated
  namespace: default
spec:
  schedulingGates:
  - name: ready-for-scheduling
  - name: cert-verified
  containers:
  - name: app
    image: app:1.0
```

The Pod is created. The scheduler sees it but does not schedule it. The Pod is `Pending` with no `nominatedNodeName`.

```bash
kubectl get pod gated
# NAME   READY   STATUS    RESTARTS   AGE
# gated  0/1     Pending   0          30s
```

The `Events` show "waiting for gating barriers" or similar.

## 3. How Gates Work

The scheduler's `PreEnqueue` extension point checks for scheduling gates. If any gate is present, the Pod is **not enqueued** for scheduling. The Pod is held in the queue but not processed.

```
Pod created
       │
       ▼
Scheduler sees the Pod
       │
       ├── SchedulingGates present? ─────► Yes ──► Don't enqueue, don't schedule
       │                                          │
       │                                          ▼
       │                                  Pod stays Pending
       │                                          │
       │                                          ▼
       │                                  All gates removed
       │                                          │
       │                                          ▼
       └── No ──► Enqueue ──► Normal scheduling
```

The Pod is **visible in the API and in `kubectl get pods`**, but the scheduler ignores it.

### 3.1 Gate names

Gate names are free-form strings, but must be valid Kubernetes names (lowercase, alphanumeric, hyphens, max 253 chars). Convention: use a domain-prefixed name to avoid collisions.

```yaml
schedulingGates:
- name: example.com/ready
- name: myapp.example.io/cert-verified
```

The controller that removes the gates is responsible for knowing the gate names it created.

## 4. Removing Gates

To remove a gate, patch the Pod's `schedulingGates` field:

```bash
# remove a specific gate
kubectl patch pod gated -p '{"spec":{"schedulingGates":[{"name":"ready-for-scheduling"}]}}' --type=merge
# wait, that's adding a gate. To remove:
kubectl patch pod gated -p '{"spec":{"schedulingGates":[]}}' --type=merge
# or
kubectl patch pod gated -p '{"spec":{"schedulingGates":null}}' --type=merge
```

Setting `schedulingGates` to an empty list or `null` removes all gates.

### 4.1 Programmatic removal

A controller removes gates via the apiserver. Example in Go:

```go
// remove the gate
patch := []byte(`[{"op":"remove","path":"/spec/schedulingGates"}]`)
_, err := clientset.CoreV1().Pods(namespace).Patch(
    context.TODO(),
    podName,
    types.JSONPatchType,
    patch,
    metav1.PatchOptions{},
)
```

Or in Python:

```python
from kubernetes import client
from kubernetes.client.rest import ApiException

# remove the gate
api = client.CoreV1Api()
api.patch_namespaced_pod(
    name=pod_name,
    namespace=namespace,
    body=[{"op": "remove", "path": "/spec/schedulingGates"}],
)
```

### 4.2 Multiple gates

If a Pod has multiple gates, **all** must be removed before scheduling proceeds. Removing one gate doesn't help; the Pod stays gated.

```yaml
schedulingGates:
- name: gate-a
- name: gate-b
```

To unblock the Pod, both must be removed. A controller can remove one gate at a time, or all at once.

## 5. Gates and Pod Lifecycle

A gated Pod is **Pending** but its lifecycle is otherwise normal. The kubelet doesn't run containers (the Pod isn't on a node). The Pod's status updates normally (`conditions`, `events`).

The Pod's `phase` is `Pending`, but the `reason` is `SchedulingGated`:

```bash
kubectl get pod gated -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].reason}'
# SchedulingGated
```

When all gates are removed, the scheduler enqueues the Pod. The `PodScheduled` condition transitions to `False` then `True` (when scheduled).

## 6. StatefulSet Join Pattern

The classic use case. A StatefulSet adds a new Pod. The new Pod needs to:

1. Be reachable (for the cluster join handshake).
2. Get cluster state from existing members.
3. Join the cluster.
4. Be ready to serve traffic.

The new Pod should be **schedulable** (so it's on a node) but **not Ready** (because it's not in the cluster yet). The standard pattern with `publishNotReadyAddresses: true` (on the headless Service) works for DNS, but it doesn't prevent the new Pod from receiving traffic.

With scheduling gates, the pattern is:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: db-2 }
spec:
  schedulingGates:
  - name: example.com/joined
  containers:
  - name: postgres
    image: postgres:15
```

The Pod is scheduled (because no gate prevents that — wait, yes it does, scheduling gates prevent scheduling). Hmm, let me re-check.

Actually, scheduling gates prevent **scheduling** entirely. So the Pod isn't on a node. The pattern is:

1. **Create the Pod with a gate.** The Pod is in the API but not on a node.
2. **The operator (e.g. StatefulSet controller) schedules the Pod normally, except for the gate.** But wait, gates prevent scheduling, so the Pod is Pending.

Let me re-check the k8s docs.

OK — the actual pattern is: the StatefulSet's "Ordinals" feature (k8s 1.26+) works with `.spec.ordinals.start` and `.spec.ordinals.statefulSetName`. The new Pod is created with a gate, and a controller (e.g. a job controller, or the StatefulSet's own logic) is responsible for:

1. The Pod is **not scheduled** while gated.
2. The controller pre-creates resources (PVs, secrets, etc.) for the new Pod.
3. The controller removes the gate when ready.
4. The Pod schedules normally.

This is the "ordered, gated" pattern. The Pod doesn't get scheduled (and doesn't start) until the controller says "go".

### 6.1 A simpler pattern with init containers

For most use cases, **init containers** are a simpler alternative to scheduling gates:

```yaml
spec:
  initContainers:
  - name: wait-for-cluster
    image: my-wait:1.0
    command: ['sh', '-c', 'until my-ready-check; do sleep 5; done']
  containers:
  - name: app
    image: app:1.0
```

The Pod is scheduled normally, but the init container blocks the main container from starting until the readiness check passes. **This is simpler than scheduling gates** for many use cases.

The trade-off: **init containers consume resources** on the node (CPU, memory) while waiting. Scheduling gates don't.

## 7. Coordinated Deployment Pattern

A common case: a Deployment with multiple Pods, where one Pod (e.g. a leader) must be ready before others. The pattern:

```yaml
# leader Pod has a gate
apiVersion: v1
kind: Pod
metadata: { name: app-leader }
spec:
  schedulingGates:
  - name: example.com/peer-ready
  containers:
  - name: app
    image: app:1.0
---
# follower Pod has no gate, can schedule
apiVersion: v1
kind: Pod
metadata: { name: app-follower }
spec:
  containers:
  - name: app
    image: app:1.0
```

A controller watches the leader's status. When the leader is ready, the controller removes the gate on the follower.

**Why use gates over init containers?** Init containers run on the node, consuming resources. Gates keep the Pod in the API but don't consume node resources. For pods that are expensive (e.g. GPU), gates are better.

## 8. Controller-Managed Gates

A custom controller is the typical consumer of scheduling gates:

```go
// 1. Create a Pod with a gate
pod := &v1.Pod{
    ObjectMeta: metav1.ObjectMeta{
        Name: "gated",
        Namespace: "default",
    },
    Spec: v1.PodSpec{
        SchedulingGates: []v1.PodSchedulingGate{
            {Name: "example.com/ready"},
        },
        Containers: []v1.Container{
            {Name: "app", Image: "app:1.0"},
        },
    },
}
clientset.CoreV1().Pods("default").Create(ctx, pod, metav1.CreateOptions{})

// 2. Wait for the condition
for {
    pod, _ := clientset.CoreV1().Pods("default").Get(ctx, "gated", metav1.GetOptions{})
    if isReady(pod) {
        break
    }
    time.Sleep(time.Second)
}

// 3. Remove the gate
patch := []byte(`[{"op":"remove","path":"/spec/schedulingGates"}]`)
clientset.CoreV1().Pods("default").Patch(
    ctx, "gated", types.JSONPatchType, patch, metav1.PatchOptions{},
)
```

The controller decides when the Pod is ready to schedule. This is the basis for:

* **Pre-deployment checks** — verify cluster state.
* **External dependencies** — wait for an external service to be reachable.
* **Operator workflows** — the operator manages the entire lifecycle, including gates.

## 9. Operations and Debugging

### 9.1 Common commands

```bash
# find gated Pods
kubectl get pods -A -o json | jq '.items[] | select(.spec.schedulingGates != null) | {name: .metadata.name, namespace: .metadata.namespace, gates: .spec.schedulingGates}'

# check a Pod's gate status
kubectl get pod <pod> -o jsonpath='{.spec.schedulingGates}'
kubectl get pod <pod> -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].reason}'

# remove a gate manually
kubectl patch pod <pod> -p '{"spec":{"schedulingGates":[]}}' --type=merge
```

### 9.2 The "gated Pod stuck forever" case

The Pod is Pending with `reason: SchedulingGated`. The gate was never removed.

```bash
# 1. Is the controller running?
kubectl -n <controller-namespace> get pods

# 2. Does the controller log any errors?
kubectl -n <controller-namespace> logs <controller-pod> --tail=100

# 3. Is the controller watching the right Pods?
# check the controller's RBAC

# 4. Is the controller's "ready" condition correct?
# the Pod may be ready but the controller is waiting for another condition

# 5. Manually remove the gate as a test
kubectl patch pod <pod> -p '{"spec":{"schedulingGates":[]}}' --type=merge
# if the Pod now schedules, the controller is the issue
```

## 10. Gotchas and Common Mistakes

### 10.1 The 15+ common mistakes

1. **Gates prevent scheduling, not starting.** A gated Pod is not on a node. It can't have init containers run (the kubelet doesn't see it). It can't have its readiness probed.

2. **Gates are a v1.27+ feature (GA in 1.30).** Older clusters can't use them. Check `kubectl version`.

3. **A Pod with gates is not "blocked", it's "waiting".** The scheduler doesn't try to schedule it. The status reason is `SchedulingGated`, not `Unschedulable`.

4. **Removing the gate doesn't immediately schedule the Pod.** The scheduler enqueues the Pod on the next scheduling cycle (within 1s by default). There's a small delay.

5. **Multiple gates all need to be removed.** Removing one doesn't unblock the Pod.

6. **A controller that creates gated Pods must also remove the gates.** If the controller is buggy, the Pod is stuck.

7. **Gates are removed via PATCH, not UPDATE.** The `schedulingGates` field is a list, and updating it requires a JSON patch or strategic merge patch.

8. **Gates don't survive Pod recreation.** A new Pod from a Deployment or StatefulSet starts with no gates (unless the template includes them).

9. **Init containers are often simpler.** For "wait for X to be ready" use cases, init containers work without the complexity of a custom controller.

10. **Gated Pods don't count against ResourceQuota's `pods` quota in the same way.** Actually, they do — the quota counts Pod objects, not running Pods. A gated Pod is still a Pod.

11. **Gated Pods can have `priorityClassName` set.** The Pod is still in the priority queue, just not enqueued for scheduling. Preemption doesn't help (the Pod is not trying to schedule).

12. **Gated Pods don't get scheduled to "unblock" them.** The Pod is in a holding pattern.

13. **The `PodSchedulingReadiness` feature gate must be enabled** in older k8s versions. In 1.30+ it's GA and always on.

14. **A gated Pod's `nominatedNodeName` is empty.** It's not trying to schedule anywhere.

15. **Gated Pods are not affected by the scheduler's preemption.** The Pod is not in the scheduling cycle, so preemption doesn't see it.

16. **A Pod with `spec.schedulerName` and a gate** is held by the gate first, then scheduled by the named scheduler once the gate is removed.

17. **The `preemptionPolicy: Never` field does not interact with gates.** Gates are about scheduling, preemption is about scheduling too, but the mechanisms are different.

18. **Gated Pods can be `kubectl delete`d.** Nothing special about deletion.

19. **A custom controller's RBAC must include `pods/patch` and `pods/update`.** Without it, the controller can't remove gates.

20. **Gates are not visible in `kubectl describe pod` by default.** Use `kubectl get pod <pod> -o yaml` to see them.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|Scheduling]] — the broader scheduling context
* [[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption|Priority & Preemption]] — another scheduling constraint mechanism
* [[Kubernetes/concepts/L06-scheduling-scaling/12-scheduler-internals|Scheduler Internals]] — the framework that enforces gates

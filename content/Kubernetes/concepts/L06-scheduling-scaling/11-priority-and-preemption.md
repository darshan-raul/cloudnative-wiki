# PriorityClass and Preemption

*"https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/"*

PriorityClass is the k8s mechanism for **ranking Pods by importance**. When the cluster is out of resources, the scheduler **preempts** (evicts) lower-priority Pods to make room for higher-priority ones. This is how you say "my critical monitoring Pod is more important than my batch workload" — and have the system enforce it.

### Table of Contents

1. [What Priority Solves](#1-what-priority-solves)
2. [PriorityClass Resource](#2-priorityclass-resource)
3. [How Preemption Works](#3-how-preemption-works)
4. [The Preemption Algorithm](#4-the-preemption-algorithm)
5. [Pod Priority vs QoS — Different Things](#5-pod-priority-vs-qos--different-things)
6. [System and User Priority Classes](#6-system-and-user-priority-classes)
7. [Critical Pods and the cluster-critical Marker](#7-critical-pods-and-the-cluster-critical-marker)
8. [Preemption in Practice](#8-preemption-in-practice)
9. [Interaction with PDBs and Eviction](#9-interaction-with-pdbs-and-eviction)
10. [The PodSchedulingReadiness Gate](#10-the-podschedulingreadiness-gate)
11. [Operations and Debugging](#11-operations-and-debugging)
12. [Gotchas and Common Mistakes](#12-gotchas-and-common-mistakes)

---

## 1. What Priority Solves

When the cluster is full, **which Pod gets scheduled first?** The default answer is "whichever the scheduler evaluates first" (FIFO within a queue). Priority changes this.

```
Without priority:
   Pod A (Request: "give me 4 cores")
   Pod B (Request: "give me 4 cores")
   Pod C (Request: "give me 4 cores")
   
   Cluster has 4 cores free.
   → Scheduler picks one, runs it. The other two stay Pending.
   → Which one? FIFO. Order of submission. Not "importance".

With priority:
   Pod A — priority 1000 (critical monitoring)
   Pod B — priority 100 (normal app)
   Pod C — priority 0 (batch)
   
   Cluster has 4 cores free, but Pod B wants 4.
   → Pod B runs.
   → Pod A arrives, also wants 4 cores. Cluster is full.
   → Scheduler preempts... nothing? Or Pod B?
   → Pod A preempts Pod B because 1000 > 100. Pod B is evicted.
   → Pod A runs. Pod B is Pending (or re-scheduled on another node).
```

**Priority is the only signal the scheduler uses to decide "evict one of these to make room for the new one".** Without it, all Pods are equal.

### 1.1 The real use case

You have a heterogeneous cluster with:

* **Critical system Pods** (Prometheus, ingress controller, cert-manager) — must run.
* **Production app Pods** (your main service) — should run.
* **Dev / batch Pods** (CI jobs, dev environments) — run if there's room.

When a node is full and a critical Pod needs to land, dev / batch Pods are preempted. The critical Pod runs. When load drops, the dev Pods are rescheduled.

This is **the alternative to a separate cluster for critical workloads** — Priority + overprovisioning lets you share a cluster safely.

## 2. PriorityClass Resource

A `PriorityClass` is a **cluster-scoped resource** that assigns a numeric value to a named priority:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000              # higher = more important
globalDefault: false        # if true, this is the default for Pods without priorityClassName
description: "Production critical services"
```

The `value` is an **int32** (can be negative). Higher = more important. The highest possible value is `1000000000` (1 billion), the lowest is `-1000000000`. **Don't use those extremes** — leave headroom.

### 2.1 The default PriorityClass

If a Pod has no `priorityClassName`, it gets the value of the `globalDefault: true` PriorityClass. If no class is global-default, the Pod has a value of `0`.

Most clusters ship with a `system-cluster-critical` and `system-node-critical` class for system Pods, but no `globalDefault`. **Pod without a priorityClassName has priority 0.**

### 2.2 Pod priority

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: critical-app
spec:
  priorityClassName: high-priority
  containers:
  - name: app
    image: app:1.0
```

The Pod's priority is the value of the `high-priority` PriorityClass. The scheduler uses this for both queue ordering and preemption.

## 3. How Preemption Works

When a Pod is Pending and can't be scheduled (no node has enough resources), the scheduler:

1. **Tries to schedule** on every node. Fails (no node has the resources).
2. **Looks for a node** where it could fit if some other Pods were removed.
3. **Finds candidates** — Pods on that node with lower priority.
4. **Picks the set of candidates** to evict to make room.
5. **Marks the candidates for deletion** (sets `nominatedNodeName` and `deletionTimestamp`).
6. **The new Pod is scheduled** on the freed space.
7. **The evicted Pods** are re-scheduled by their controllers (or stay Pending if no other node fits).

The evicted Pods are NOT gracefully shut down — they're **killed** (similar to a node failure). Their `terminationGracePeriodSeconds` is honored, but preemption is **involuntary disruption**.

### 3.1 Preemption is the eviction API in disguise

Preempted Pods go through the **eviction API** — the same one that `kubectl drain` and Cluster Autoscaler use. This means:

* **PDBs are respected** — preemption can't violate a PDB for the evicted Pods. (Or rather, it tries to; see section 9.)
* **Graceful shutdown** is honored — the evicted Pod's `terminationGracePeriodSeconds` is used.
* **Pod events are emitted** — the preempted Pod gets a "Preempted" event with the reason.

### 3.2 Preemption is best-effort

The scheduler doesn't guarantee a higher-priority Pod always gets scheduled. It only attempts preemption. If preemption fails (e.g. all candidates are protected by PDBs), the high-priority Pod stays Pending.

## 4. The Preemption Algorithm

```
For a high-priority Pod P that can't be scheduled:
  1. For each node N:
     a. Compute the "free space" on N if all lower-priority Pods were removed.
     b. If P can fit in that free space, N is a preemption candidate.
  2. From the candidates, pick the node where the **least** number of lower-priority Pods would be preempted.
  3. On that node, pick the set of Pods whose removal frees the most space per Pod.
  4. Mark them for deletion.
  5. Schedule P on the freed space.
```

The algorithm minimizes the **number of preempted Pods** (and thus the disruption).

### 4.1 The `nominatedNodeName` field

When a Pod is preempting, the scheduler sets `status.nominatedNodeName` on the preempting Pod:

```bash
kubectl get pod <high-priority-pod> -o jsonpath='{.status.nominatedNodeName}'
# node-2
```

This is a hint: "if preemption succeeds, this Pod will land on node-2." The nominated node's Pods are marked for deletion.

### 4.2 Grace period for preempted Pods

The preempted Pods are given a **2-second grace period** by default. The scheduler waits 2 seconds for the Pods to actually be removed before scheduling the high-priority Pod. This is to ensure the space is free when the new Pod lands.

You can change this with `--preemption-evaluation-timeout` on kube-scheduler.

## 5. Pod Priority vs QoS — Different Things

**Priority and QoS are completely different concepts.**

| | Priority | QoS |
|---|---|---|
| **Determines** | Preemption order | Eviction order under node pressure |
| **Set by** | `priorityClassName` (Pod spec) | `requests` and `limits` (Pod spec) |
| **Triggers** | Preemption (PENDING Pod, scheduler evicts others) | Eviction (node is full, kubelet kills Pods) |
| **When applied** | Scheduling time | Runtime, when node is under pressure |
| **Number of classes** | Arbitrary (you define them) | 3 (Guaranteed, Burstable, BestEffort) |
| **Resources needed** | A PriorityClass | Nothing (computed from resources) |

A Pod can be:

* **High priority + Guaranteed** — preempted last, evicted last.
* **High priority + BestEffort** — preempted last, evicted first.
* **Low priority + Guaranteed** — preempted first, evicted last.
* **Low priority + BestEffort** — preempted first, evicted first.

**Priority is about "what gets scheduled when resources are tight".** **QoS is about "what gets killed when the node runs out of memory".**

## 6. System and User Priority Classes

### 6.1 The built-in system classes

k8s ships with two built-in PriorityClasses for system use:

* `system-cluster-critical` (value: 2000000000) — for cluster-level critical Pods.
* `system-node-critical` (value: 3000000000 / 2000000000 in older versions) — for node-level critical Pods.

These are **reserved for system components** (kube-proxy, CNI, etc.). Don't assign them to user Pods.

### 6.2 User-defined classes

A typical setup:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: production-critical
value: 1000000
globalDefault: false
description: "Production critical services (auth, payments, etc.)"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: production-standard
value: 100000
globalDefault: false
description: "Standard production services"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: batch-low
value: 10000
globalDefault: false
description: "Batch / non-production workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: best-effort
value: -100000
globalDefault: true
description: "Default for Pods without explicit priority"
```

The `globalDefault: true` on `best-effort` means Pods without `priorityClassName` get priority -100000. They're preempted first.

**Avoid making a class with very high value the global default.** Pods with default priority should be preemptable, not preemptors.

### 6.3 Naming convention

The k8s convention:

* `system-*` — reserved for system Pods.
* `cluster-critical`, `node-critical` — same, reserved.
* Everything else — your own classes.

A common pattern:

* `tier-0-critical` (or `production-critical`)
* `tier-1-standard` (or `production-standard`)
* `tier-2-batch`
* `tier-3-dev` (or `batch-low`)
* `tier-4-best-effort` (globalDefault)

## 7. Critical Pods and the cluster-critical Marker

Some Pods are **critical to the cluster's operation** — the kubelet, the CNI, the kube-apiserver, etc. If these are preempted, the cluster breaks. They have a special marker:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-proxy
  namespace: kube-system
spec:
  priorityClassName: system-node-critical
  # ...
```

The scheduler treats these as **never-evict**. Even if preemption would otherwise target them, they're skipped. This is why system Pods don't get preempted when user Pods come in.

**Don't assign system critical classes to user Pods.** The scheduler's preemption algorithm skips them, which means high-priority user Pods can't preempt them either. The result is high-priority Pods Pending indefinitely.

## 8. Preemption in Practice

### 8.1 The "high-priority Pod is Pending" case

A high-priority Pod is Pending. The cluster has capacity, but it's all on nodes with low-priority Pods. The scheduler preempts them.

```
$ kubectl get pods -A -o wide
NAMESPACE   NAME              PRIORITY   NODE      STATUS
prod        critical-app      1000000    <none>    Pending
dev         dev-app-1         10000      node-1    Running
dev         dev-app-2         10000      node-1    Running
dev         dev-app-3         10000      node-1    Running

Events:
  Type     Reason       Age    From               Message
  ----     ------       ----   ----               -------
  Warning  FailedScheduling  30s   default-scheduler   0/3 nodes are available: 3 Insufficient cpu.
  Normal   Preempted     25s    default-scheduler   Preempted dev-app-1, dev-app-2 on node node-1
  Normal   Scheduled     25s    default-scheduler   Successfully assigned prod/critical-app to node-1
```

The preemption events are visible on the **preempted Pods**, not the preempting one (in some versions). Check `kubectl get events --field-selector reason=Preempted`.

### 8.2 The "preemption is too aggressive" case

A common scenario: dev Pods keep getting preempted. Solution: lower their priority.

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: dev-low }
value: 1000
```

Now production (value 100000) preempting dev (value 1000) is fine. Dev can still run when there's room.

### 8.3 The "priority inversion" case

A low-priority Pod is running. A medium-priority Pod comes in. The scheduler doesn't preempt the low one (no need). A high-priority Pod comes in. The scheduler preempts the low one. **But what if there are also medium-priority Pods on the node?** Preemption only removes the **lowest-priority** Pods. The medium ones stay. The high-priority Pod runs alongside medium ones.

This is correct behavior. Preemption is **targeted at the lowest** to minimize disruption.

## 9. Interaction with PDBs and Eviction

Preemption **respects PDBs** — it tries not to violate them. But "tries" is the operative word:

* If a node has 3 Pods, all `minAvailable: 2`, and a high-priority Pod needs 1 of those evicted, **preemption skips the node**. The high-priority Pod stays Pending.
* If the only preemptable candidates are protected by PDBs, **preemption fails**. The high-priority Pod stays Pending.

The preemption algorithm prefers nodes where the **fewest PDBs are violated**. If no node can be preempted without violating a PDB, the high-priority Pod doesn't get scheduled.

**This is a common deadlock** — high-priority Pods are Pending because all candidates are protected by tight PDBs.

## 10. The PodSchedulingReadiness Gate

*(See [[Kubernetes/concepts/L06-scheduling-scaling/13-scheduling-gates|Scheduling Gates]] for the deep dive.)*

A `schedulingGates` field on a Pod holds it back from scheduling until explicitly removed. This is the "Pod scheduling readiness" feature (k8s 1.27+).

```yaml
apiVersion: v1
kind: Pod
metadata: { name: gated }
spec:
  schedulingGates:
  - name: ready-for-scheduling
  containers:
  - name: app
    image: app:1.0
```

The Pod is created but not scheduled until the gate is removed:

```bash
# remove the gate via the API
kubectl patch pod gated -p '{"spec":{"schedulingGates":[]}}' --type=merge
# or
kubectl patch pod gated -p '{"spec":{"schedulingGates":null}}' --type=merge
# either removes all gates
```

This is useful for:

* StatefulSet joins — wait for the previous Pod to be ready.
* Coordinated deployments — wait for a signal before allowing scheduling.
* Pre-deployment checks — verify cluster state before allowing the Pod to run.

## 11. Operations and Debugging

### 11.1 Common commands

```bash
# list PriorityClasses
kubectl get priorityclass
# shows NAME, VALUE, GLOBAL-DEFAULT, AGE

# describe
kubectl describe priorityclass <name>

# check a Pod's priority
kubectl get pod <pod> -o jsonpath='{.spec.priorityClassName}'
kubectl get pod <pod> -o jsonpath='{.spec.priority}'

# find preempted Pods
kubectl get events --field-selector reason=Preempted -A
kubectl get events --field-selector reason=Preempted -A --sort-by='.lastTimestamp'

# find Pods on a specific node
kubectl get pods -A --field-selector spec.nodeName=<node>
```

### 11.2 The "high-priority Pod stuck Pending" checklist

```bash
# 1. Is the priority class defined?
kubectl get priorityclass
# if not, the Pod's priorityClassName is invalid

# 2. Are there lower-priority Pods on the candidate nodes?
kubectl get pods -A -o custom-columns='NAME:.metadata.name,PRIORITY:.spec.priority,NODE:.spec.nodeName'

# 3. Are the candidate Pods protected by PDBs?
kubectl get pdb -A

# 4. Is the cluster out of capacity entirely?
# check the resource usage
kubectl top nodes
kubectl describe node <node> | grep Allocatable

# 5. Are the system Pods taking all the resources?
# the scheduler treats system-cluster-critical and system-node-critical as untouchable
```

### 11.3 The "preemption happens too often" case

If preemption is happening too frequently:

* **Too many high-priority Pods.** Lower their priority.
* **Not enough capacity.** Add nodes (CA / Karpenter).
* **The high-priority Pods have high resource requests.** Lower them.
* **PDBs are too tight.** Loosen the PDBs to allow eviction of low-priority Pods.

## 12. Gotchas and Common Mistakes

### 12.1 The 25+ common mistakes

1. **Pod priority and QoS class are different things.** Conflating them is the #1 mistake. Priority = scheduling/preemption. QoS = runtime eviction.

2. **Preemption is best-effort.** A high-priority Pod doesn't always get scheduled. PDBs and system classes can block it.

3. **The default priority is 0.** Without a PriorityClass with `globalDefault: true`, all unnamed Pods are equal at priority 0.

4. **High-priority Pods don't preempt system classes.** `system-cluster-critical` and `system-node-critical` are off-limits.

5. **Preemption is involuntary disruption.** It's similar to a node failure for the preempted Pods. Use it for "I really need this" cases, not "I'd like this".

6. **Preemption respects PDBs.** Tight PDBs on low-priority Pods can prevent the high-priority Pod from being scheduled.

7. **`preemption-evaluation-timeout` is the wait time** for preempted Pods to be removed. Default 2s. If preempted Pods are slow to die, this can cause race conditions.

8. **The scheduler doesn't run constantly.** A high-priority Pod is evaluated when the scheduler next runs (every `--scheduler-interval`, default 1s).

9. **A Pending high-priority Pod is queued.** It doesn't pre-emptively search for victims until the scheduler runs.

10. **Preemption costs scheduler time.** With 1000+ nodes and many Pods, the algorithm is O(n) per high-priority Pod. Don't make every Pod high-priority.

11. **PriorityClass is cluster-scoped.** A `PriorityClass` is available to all namespaces. You can't have a private one.

12. **You can't change a Pod's `priorityClassName` after creation.** You'd have to delete and recreate the Pod.

13. **You can have a Pod with `priority: 0` and a Pod with `priorityClassName: default` (value 0) and they're treated equally.** The actual numeric value matters, not the name.

14. **Negative priorities are valid.** A `PriorityClass` with `value: -1000` makes Pods preemptable by everyone.

15. **The scheduler doesn't guarantee a Pod's nominated node is where it lands.** `nominatedNodeName` is a hint. The Pod might be scheduled on a different node if it becomes available.

16. **Preempted Pods are killed, not gracefully shut down by default.** The Pod's `terminationGracePeriodSeconds` is honored, but the application is forcibly terminated.

17. **Preemption doesn't help with memory pressure.** If a node is OOM-killing Pods, priority doesn't change that. (QoS class matters here, not priority.)

18. **A node's kubelet doesn't know about preemption priority.** The kubelet kills Pods based on QoS class and memory pressure, not priority.

19. **A high-priority Pod that's been Pending for a while may be preempted by an even higher-priority one.** Priority is a continuum, not a binary.

20. **The `non-preempting` PolicyField** (alpha in 1.27+) lets a high-priority Pod opt out of preempting. Useful for "I want to wait, not preempt".

21. **The `preemptionPolicy: Never` field on a Pod** is the same as the alpha feature. A high-priority Pod with `preemptionPolicy: Never` waits in the queue.

22. **PriorityClass names with `system-` prefix are reserved.** The scheduler / API server will reject user PriorityClasses with that prefix.

23. **The maximum PriorityClass value is 1000000000.** Don't go higher — there's no benefit, and you may break assumptions.

24. **The minimum PriorityClass value is -1000000000.** Use negative values for "preemptable" Pods (e.g. dev environments, batch).

25. **Preemption is cluster-wide, not per-node.** A high-priority Pod can preempt Pods on any node, not just the one it's targeting.

26. **The scheduler doesn't keep a global view of "free" capacity.** It tries nodes one at a time, and preemption is per-node.

27. **Preemption is disabled by default for Pods that are themselves being preempted.** A Pod being preempted doesn't preempt others in the same cycle. (Cascade protection.)

28. **A `priorityClassName` on a Job / CronJob is inherited by the Pods it creates.** A high-priority Job creates high-priority Pods.

29. **A `priorityClassName` on a Deployment is inherited by the Pods in its ReplicaSet.** A high-priority Deployment creates high-priority Pods.

30. **Preemption in `kube-scheduler` v1.x is a "soft" preemption** — the preempted Pods may not actually be removed before the high-priority Pod is scheduled. This is a known race condition.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|Scheduling]] — the broader scheduling context
* [[Kubernetes/concepts/L06-scheduling-scaling/12-scheduler-internals|Scheduler Internals]] — the actual scheduling algorithm
* [[Kubernetes/concepts/L06-scheduling-scaling/13-scheduling-gates|Scheduling Gates]] — holding Pods back from scheduling
* [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PDB]] — how PDBs interact with preemption

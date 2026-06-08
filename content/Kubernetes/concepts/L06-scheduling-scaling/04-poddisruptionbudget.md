# PodDisruptionBudget (PDB)

*"https://kubernetes.io/docs/concepts/workloads/pods/disruptions/"*

A PodDisruptionBudget **limits how many Pods in a set can be simultaneously unavailable** during **voluntary disruption**. Voluntary disruption = initiated by a person or a controller (a `kubectl drain`, a cluster autoscaler removing a node, an operator rolling out a change). It does NOT cover involuntary disruption (node failure, OOM, network partition).

### Table of Contents

1. [What PDBs Protect Against](#1-what-pdbs-protect-against)
2. [The Two Specifications: minAvailable vs maxUnavailable](#2-the-two-specifications-minavailable-vs-maxunavailable)
3. [The Math in Depth](#3-the-math-in-depth)
4. [The Eviction API](#4-the-eviction-api)
5. [PDB Status and Conditions](#5-pdb-status-and-conditions)
6. [The Pod Eviction Policy (k8s 1.26+)](#6-the-pod-eviction-policy-k8s-126)
7. [PDB and HPA: The Scale-Down Interaction](#7-pdb-and-hpa-the-scale-down-interaction)
8. [PDB and Cluster Autoscaler / Karpenter](#8-pdb-and-cluster-autoscaler--karpenter)
9. [PDB Selector Matching](#9-pdb-selector-matching)
10. [PDB Status Fields in Depth](#10-pdb-status-fields-in-depth)
11. [AlwaysAllow and Other Edge Cases](#11-alwaysallow-and-other-edge-cases)
12. [Common Patterns](#12-common-patterns)
13. [Operations and Debugging](#13-operations-and-debugging)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistances)

---

## 1. What PDBs Protect Against

**Voluntary disruption** is any disruption initiated by a person or a controller. The eviction API is what enforces it, and the eviction API respects PDBs.

| Action | Voluntary? | PDB respected? |
|---|---|---|
| `kubectl drain` | Yes | Yes |
| Cluster Autoscaler removing a node | Yes | Yes |
| Karpenter consolidation | Yes | Yes |
| HPA scale-down | Yes | Yes (via eviction API) |
| `kubectl delete pod` | Yes | Yes (via eviction API) |
| `kubectl delete pod --force --grace-period=0` | Yes | **No — bypasses PDB** |
| Node failure | No (involuntary) | No |
| Pod OOM-kill | No | No |
| kubelet kills a stuck Pod | No | No |
| Network partition | No | No |

The **eviction API** is the gate. The kubelet doesn't use it for involuntary disruption — when a node fails, the Pods die regardless of PDB. PDB only constrains **what the eviction API allows**.

## 2. The Two Specifications: minAvailable vs maxUnavailable

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

### 2.1 `minAvailable`

**At least N Pods must be available at all times during disruption.** The PDB is satisfied as long as `currentAvailable >= minAvailable`.

### 2.2 `maxUnavailable`

**At most N Pods can be unavailable at a time.** The PDB is satisfied as long as `currentUnavailable <= maxUnavailable`.

### 2.3 Which to use

* **`minAvailable`** for "I always need N available" services (e.g. quorum-based, databases with replicas).
* **`maxUnavailable`** for "I can tolerate some being gone" services (e.g. stateless HTTP).

They are **equivalent for simple cases** (e.g. `minAvailable: 2` on a Deployment with `replicas: 3` is the same as `maxUnavailable: 1`).

The difference shows up with **percentages**:

* `minAvailable: 50%` on `replicas: 3` rounds **up** to 2.
* `maxUnavailable: 50%` on `replicas: 3` rounds **down** to 1 (but can be at most 1; the same as `minAvailable: 2`).

### 2.4 Percentages

```yaml
spec:
  minAvailable: 75%        # round up
  # maxUnavailable: 25%
```

Percentages are **of the Pods matching the selector**. If the selector matches 4 Pods, `minAvailable: 75%` rounds up to 3.

For `maxUnavailable: 25%`, that rounds down to 1.

## 3. The Math in Depth

The PDB's status field shows the math:

```yaml
status:
  currentHealthy: 5
  desiredHealthy: 4
  expectedPods: 5
  disruptionsAllowed: 1
```

* **`expectedPods`** — Pods matching the selector that exist.
* **`currentHealthy`** — Pods matching the selector that are currently Ready.
* **`desiredHealthy`** — the floor (or ceiling) from the spec.
* **`disruptionsAllowed`** — how many more Pods can be voluntarily disrupted.

The eviction API checks: `currentHealthy - 1 >= desiredHealthy` for each eviction. If yes, allow. If no, reject.

### 3.1 The math for `minAvailable: 2` on `replicas: 3`

```
expectedPods = 3
currentHealthy = 3 (initially)
desiredHealthy = 2
disruptionsAllowed = currentHealthy - desiredHealthy = 1

Eviction of Pod 1:
currentHealthy = 2
2 - 1 = 1, which is < 2 (desiredHealthy)
→ reject

Result: no evictions allowed while all 3 are healthy.
```

Wait, that doesn't make sense. Let me re-check.

Actually, the math is:
- `disruptionsAllowed` = how many Pods can be disrupted while still satisfying the PDB.
- For `minAvailable: 2` on `replicas: 3`: you can disrupt 1 (currentHealthy 3, after disruption 2 = minAvailable).
- For `minAvailable: 3` on `replicas: 3`: you can disrupt 0.

Let me redo:

```
expectedPods = 3
minAvailable = 2
desiredHealthy = 2
disruptionsAllowed = expectedPods - minAvailable = 1

If we evict 1 Pod: expectedPods = 2 (because the Pod is gone), minAvailable still 2.
1 disruption allowed = we can do 1 eviction. After the eviction, the math resets.

Actually the math in the apiserver is:
disruptionsAllowed = max(0, currentHealthy - desiredHealthy)
```

Hmm, the exact algorithm depends on the k8s version. The practical effect:
- For `minAvailable: 2` and 3 healthy Pods: 1 disruption allowed.
- For `minAvailable: 2` and 2 healthy Pods: 0 disruptions allowed.

### 3.2 The math for `maxUnavailable: 1` on `replicas: 3`

```
expectedPods = 3
maxUnavailable = 1
desiredHealthy = 3 - 1 = 2
disruptionsAllowed = expectedPods - desiredHealthy = 1

Same as minAvailable: 2 in this case.
```

### 3.3 The "0 disruptions allowed" deadlock

If `minAvailable: 3` on `replicas: 3`, the PDB says "all 3 must be available". `disruptionsAllowed = 0`. **No voluntary eviction is allowed.**

This is a common deadlock. A single-replica Deployment with `minAvailable: 1` can't be drained.

## 4. The Eviction API

The eviction API is the mechanism that respects PDBs. It's a special endpoint:

```http
POST /api/v1/namespaces/<ns>/pods/<pod>/eviction
```

Or via `kubectl`:

```bash
kubectl drain node-1
# internally calls the eviction API for each Pod

kubectl delete pod <pod> --grace-period=30
# also uses the eviction API
```

The eviction API:

1. Checks the PDB for the Pod.
2. If the eviction would violate the PDB, returns 403 Forbidden.
3. The caller (drain, autoscaler) backs off and retries.

### 4.1 Bypassing the PDB

```bash
# bypass the eviction API; force-delete the Pod
kubectl delete pod <pod> --force --grace-period=0
```

The `--force` flag bypasses the eviction API. **The Pod is deleted regardless of PDB.** This is the only way to evict a Pod when the PDB would block.

Use `--force` only when:
- A node is truly gone and you need to evict stuck Pods.
- The cluster autoscaler is stuck because of a deadlock.
- You accept the disruption.

### 4.2 The grace period

The eviction API supports a `gracePeriodSeconds` parameter. The Pod's `terminationGracePeriodSeconds` is the upper bound; the eviction can be more aggressive.

```bash
# evict with a 0-second grace period
kubectl delete pod <pod> --grace-period=0
# (but the PDB is still respected)
```

`--force --grace-period=0` is the only way to bypass the PDB.

## 5. PDB Status and Conditions

The PDB has a `status` field:

```yaml
status:
  observedGeneration: 1
  disruptionsAllowed: 1
  currentHealthy: 5
  desiredHealthy: 4
  expectedPods: 5
  conditions:
  - type: SufficientPods
    status: "True"
    reason: ""
    message: ""
    lastTransitionTime: "2024-01-15T12:00:00Z"
  - type: DisruptionAllowed
    status: "True"
    reason: ""
    message: ""
    lastTransitionTime: "2024-01-15T12:00:00Z"
```

* **`SufficientPods`** — does the current state satisfy the PDB?
* **`DisruptionAllowed`** — is a disruption allowed right now?

If `DisruptionAllowed: False`, no new voluntary disruption is allowed.

### 5.1 The "PDB blocking" indicator

```bash
kubectl get pdb -A
# NAME   MIN   MAX   ALLOWED   DISRUPTIONS   AGE
# web    2     -     1         1             30d
# db     -     1     0         0             30d

# ALLOWED DISRUPTIONS = 0 means next drain will block
```

This is the key field to check before a drain.

## 6. The Pod Eviction Policy (k8s 1.26+)

A **Pod Eviction Policy** is set in the PDB's `status.conditions` and lets you control how unhealthy Pods are counted:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: web }
spec:
  minAvailable: 2
  selector:
    matchLabels: { app: web }
status:
  observedGeneration: 1
  disruptionsAllowed: 1
  currentHealthy: 5
  desiredHealthy: 4
  expectedPods: 5
  conditions:
  - type: DisruptionAllowed
    status: "True"
```

But by default, **unhealthy Pods are still counted as expected**. If a Pod is CrashLoopBackOff, it's in `expectedPods` but not in `currentHealthy`. The PDB may block eviction because the math is "off".

The `unhealthyPodEvictionPolicy` field (in `policy/v1` in 1.26+) controls this:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: web }
spec:
  minAvailable: 2
  unhealthyPodEvictionPolicy: IfHealthyBudget   # default
  selector:
    matchLabels: { app: web }
```

Two values:

* **`IfHealthyBudget`** — the PDB only blocks if the Pod is healthy. If the Pod is already unhealthy (CrashLoopBackOff, NotReady), the eviction is allowed.
* **`AlwaysAllow`** — the PDB never blocks the eviction of an unhealthy Pod. The PDB only protects healthy Pods.

### 6.1 The use case

A Pod is CrashLoopBackOff. You want to drain the node. Without `IfHealthyBudget`, the PDB blocks the eviction (the Pod is in `expectedPods` but not in `currentHealthy`).

With `IfHealthyBudget`, the eviction is allowed because the Pod is already unhealthy. The PDB's protection is only for the *healthy* Pods.

**This is a critical fix for stuck drains.**

## 7. PDB and HPA: The Scale-Down Interaction

HPA scale-down is a voluntary disruption. The eviction API is called, and the PDB is checked.

```
HPA: 5 → 3 Pods
HPA calls the eviction API for 2 Pods
Eviction API checks PDB:
- If 3 Pods are still satisfying the PDB, the evictions are allowed
- If not, the evictions are blocked
```

### 7.1 The deadlock

```
Deployment: 3 replicas
PDB: minAvailable: 2
HPA: target CPU 60%, current CPU 50%
HPA: scale to 2 replicas
```

HPA wants to scale to 2. The eviction API says "2 evictions would leave 1 healthy, but PDB says minAvailable 2". The HPA is blocked.

The HPA controller retries, fails, and the Pods stay at 3.

**This is a common deadlock.** Fix: reduce `minAvailable` (e.g. to 1) or increase HPA's `minReplicas`.

## 8. PDB and Cluster Autoscaler / Karpenter

Cluster Autoscaler and Karpenter both call the eviction API when removing a node. PDBs are respected.

### 8.1 The CA scale-down deadlock

```
PDB: minAvailable: 2 on a Deployment with 3 replicas
CA wants to scale down a node that has 1 of those Pods
CA evicts the Pod → PDB says no → CA fails
```

CA retries with backoff. If the PDB stays unsatisfiable, CA leaves the node behind. The cluster is over-provisioned.

**The fix**: ensure your PDBs are achievable. `minAvailable: N-1` on a Deployment with N replicas is safe. `minAvailable: N` is a deadlock.

### 8.2 Karpenter and consolidation

Karpenter's consolidation tries to **drain** nodes. The drain respects PDBs. If a drain is blocked by a PDB, Karpenter skips the consolidation and tries a different node.

Karpenter has `disruption.budgets` (in the NodePool) to rate-limit its own disruptions. The PDB is in addition to that.

## 9. PDB Selector Matching

A PDB's `selector` must match the Pods you want to protect:

```yaml
spec:
  selector:
    matchLabels: { app: web }      # exact match
  # OR
  selector:
    matchExpressions:
    - key: tier
      operator: In
      values: [production]
```

If the selector matches **no Pods**, the PDB is a no-op (it protects nothing).

If the selector matches Pods but the Pods aren't Ready, the PDB counts them as not healthy. The math may still work — depending on `unhealthyPodEvictionPolicy`.

## 10. PDB Status Fields in Depth

### 10.1 `disruptionsAllowed`

The number of Pods that can be voluntarily disrupted right now. Computed by the apiserver.

For `minAvailable: N`: `disruptionsAllowed = currentHealthy - N` (or 0 if negative).
For `maxUnavailable: N`: `disruptionsAllowed = N - currentUnavailable` (or 0 if negative).

### 10.2 `currentHealthy`

The Pods matching the selector that are Ready (passing readiness probes).

A Pod that doesn't have a readiness probe is **always Ready** (no probe = always passes).

A Pod that has a readiness probe and is failing is **not Ready** → not in `currentHealthy`.

### 10.3 `expectedPods`

The total number of Pods matching the selector. Includes unhealthy ones (without `unhealthyPodEvictionPolicy: IfHealthyBudget` or `AlwaysAllow`).

### 10.4 `desiredHealthy`

The minimum (for `minAvailable`) or maximum (for `maxUnavailable`) number of healthy Pods.

For `minAvailable: 2`: `desiredHealthy = 2`.
For `maxUnavailable: 1` on `expectedPods: 3`: `desiredHealthy = 2` (3 - 1).

## 11. AlwaysAllow and Other Edge Cases

### 11.1 `AlwaysAllow`

A PDB with no `minAvailable` and no `maxUnavailable` (or set to 0) is **AlwaysAllow** — it allows all voluntary disruption.

Don't do this. It's the same as having no PDB at all.

### 11.2 `minAvailable: 0`

A PDB with `minAvailable: 0` is **AlwaysAllow**. No Pods need to be available. Same as no PDB.

### 11.3 `maxUnavailable: 100%`

A PDB with `maxUnavailable: 100%` allows all Pods to be unavailable. Same as no PDB.

### 11.4 Empty selector

A PDB with no `selector` (or `matchLabels: {}`) matches all Pods in the namespace. **This is rarely what you want.** A single PDB that covers all Pods is almost always wrong.

## 12. Common Patterns

### 12.1 Stateful workload

```yaml
# StatefulSet
spec:
  replicas: 3
  template: {...}

# PDB
spec:
  minAvailable: 2            # always have 2 of 3
  selector:
    matchLabels: { app: db }
```

Loses 1 of 3, still has 2. Loses 2 of 3, PDB blocks further disruption.

### 12.2 Stateless HTTP service

```yaml
spec:
  minAvailable: 50%           # always have majority
  selector:
    matchLabels: { app: web }
```

For a 6-replica Deployment, 3 must be available. For a 4-replica, 2 must be available (rounding).

### 12.3 Critical singleton

```yaml
spec:
  minAvailable: 1
  selector:
    matchLabels: { app: critical }
```

A single-replica Deployment. PDB says "the 1 Pod can't be evicted". Drain blocks. Use only for truly critical singletons.

### 12.4 The "PDB + HPA" pattern

```yaml
# HPA: 3-20 replicas
spec:
  minReplicas: 3
  maxReplicas: 20

# PDB: always have 2
spec:
  minAvailable: 2
  selector:
    matchLabels: { app: web }
```

HPA can scale from 3 to 20 freely. PDB says at least 2 must be available. HPA scale-down stops at 2 (PDB blocks scale below 2).

If the cluster needs to evict more aggressively (e.g. for a drain), PDB blocks it. This is by design.

## 13. Operations and Debugging

### 13.1 Common commands

```bash
# list PDBs
kubectl get pdb -A
# shows NAME, MIN, MAX, ALLOWED DISRUPTIONS, AGE

# describe
kubectl describe pdb <name>
# shows selector, current state, conditions

# check if a drain is allowed
kubectl get pdb -A -o custom-columns='NAME:.metadata.name,ALLOWED:.status.disruptionsAllowed,DESIRED:.status.desiredHealthy,CURRENT:.status.currentHealthy'
```

### 13.2 The "drain stuck" checklist

```bash
# 1. Is the PDB allowing disruptions?
kubectl get pdb -A
# ALLOWED DISRUPTIONS = 0 means the next drain will block

# 2. Are the Pods Ready?
kubectl get pods -l <selector>
# all should be 1/1 Ready

# 3. Are the Pods on the node being drained?
kubectl get pods -A --field-selector spec.nodeName=<node>

# 4. Are the PDB conditions showing "DisruptionAllowed: False"?
kubectl describe pdb <name>

# 5. Is the PDB satisfied?
# If minAvailable: 2 and 1 Pod is Ready, the PDB is unsatisfied
# → drain will block
```

### 13.3 The "PDB not blocking" case

If a Pod is being evicted despite a PDB, the cause is usually `--force --grace-period=0`. Check the eviction call:

```bash
# was the eviction forced?
kubectl get events --field-selector reason=Evicted -A
# look for the pod's events
```

## 14. Gotchas and Common Mistakes

### 14.1 The 25+ common mistakes

1. **PDB requires a matching Pod selector.** If your selector doesn't match any Pods, the PDB has no effect. **Always check `kubectl get pdb` shows non-zero currentHealthy.**

2. **PDB is enforced by the eviction API, not by the scheduler.** The scheduler doesn't know about PDBs. It places Pods based on resources and constraints, regardless of PDBs.

3. **`maxUnavailable: 0` and `minAvailable: replicas` are the same thing** and equally dangerous. The node is unevictable; the autoscaler will leave the node behind.

4. **PDB is not a substitute for HPA.** PDB is about availability during planned disruption, not about handling load. You can have 100% availability during a drain and still get killed by traffic spikes.

5. **PDB does not block voluntary disruption completely.** It controls the *rate*, not the possibility. A `kubectl delete pod` still works — it just makes the next drain fail.

6. **PDB status is reflected in the PDB object itself** — `kubectl get pdb` shows `ALLOWED DISRUPTIONS`. If that's 0, the next drain will block.

7. **Eviction API is what drain / autoscaler call.** A forced Pod deletion via `kubectl delete pod --force --grace-period=0` **bypasses the PDB**. Use with caution.

8. **PDB with `minAvailable: 100%` is the same as `minAvailable: replicas`.** Don't set 100% — it's the deadlock.

9. **PDB with `minAvailable: 0` is the same as no PDB.** Useless.

10. **PDB on a Deployment with `replicas: 1`** means the Pod can't be drained. The drain will block.

11. **PDB with `selector: {}` matches all Pods in the namespace.** Rarely correct. Be specific.

12. **PDB with `selector` matching multiple Deployments** is a single PDB for all of them. The math is across all Pods. Easy to misconfigure.

13. **PDB is `policy/v1` since k8s 1.21.** Older `policy/v1beta1` is removed. Make sure manifests are on `v1`.

14. **PDB's `unhealthyPodEvictionPolicy: IfHealthyBudget`** (default in v1, k8s 1.26+) lets you evict unhealthy Pods even when the PDB math would block. Critical for stuck drains.

15. **PDB doesn't know about Pods that are about to be created.** A HPA scale-up to satisfy `minAvailable: 2` works (the new Pod is created before the old one is evicted). But if the scale-up fails, the eviction is blocked.

16. **PDB + HPA scale-down deadlock** is common. PDB says minAvailable 2, HPA wants to scale to 1. The eviction API blocks. Fix: relax the PDB or set higher minReplicas on HPA.

17. **PDB + Cluster Autoscaler scale-down deadlock** is the same. CA wants to remove a node, PDB blocks. The CA retries, fails, leaves the node.

18. **PDB + `kubectl delete pod`** uses the eviction API. PDB is checked. Use `--force` to bypass.

19. **PDB + `kubectl delete deployment`** deletes all Pods. The PDB is checked for each eviction. The deployment is deleted regardless, but the Pod deletions may block briefly. Final state: Pods are gone.

20. **PDB + `kubectl delete namespace`** deletes all Pods in the namespace. PDBs in the namespace are also deleted (with the namespace). The Pod deletions may block briefly until the namespace is gone. Then the Pods are force-deleted.

21. **PDB with `selector: { app: foo }` and a Deployment with `app: foo`** matches. With a Deployment `app: foo, tier: web` (more labels), the selector still matches. Match is by the selector's labels, not exact match.

22. **A PDB can have multiple selectors (matchLabels + matchExpressions).** All must match.

23. **PDB's `disruptionsAllowed` is computed by the apiserver.** It updates on Pod state changes. There's a small lag.

24. **A PDB with `maxUnavailable: 1` on a Deployment with `replicas: 1` is the same as `minAvailable: 1`.** Single-replica, undrainable.

25. **PDB's conditions can be `DisruptionAllowed: False` even when disruptionsAllowed > 0.** This is rare and usually means a transient issue (selector doesn't match, etc.).

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] — PDB interaction with HPA scale-down
* [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter|Karpenter]] — PDB interaction with consolidation
* [[Kubernetes/concepts/L06-scheduling-scaling/09-cluster-autoscaler|CA]] — PDB interaction with CA scale-down
* [[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption|Priority & Preemption]] — PDBs can block preemption
* [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource Requests & Limits]] — readiness probes for currentHealthy

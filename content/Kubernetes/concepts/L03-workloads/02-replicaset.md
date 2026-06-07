---
title: ReplicaSet — The Pod-Replica Controller
tags: [kubernetes, workloads, replicaset, controllers, core-concepts]
date: 2026-06-07
description: The lower-level controller that maintains a stable set of Pod replicas. Reconciler model, selector mechanics, adoption behavior, and why you almost always use a Deployment instead.
---

# ReplicaSet — The Pod-Replica Controller

> https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/

A **ReplicaSet** (RS) is a controller whose only job is to maintain a **stable set of replica Pods** running at any given time. You tell it "I want 3 of these," and the ReplicaSet controller does whatever it takes to make that true — creating Pods when there are too few, deleting them when there are too many, and replacing them when they die.

In modern Kubernetes, you almost never write a ReplicaSet directly. A [[Kubernetes/concepts/L03-workloads/03-deployments|Deployment]] owns a ReplicaSet and adds rolling-update, rollback, and pause/resume on top. But understanding the ReplicaSet is essential, because:

1. **Deployments manage ReplicaSets.** When you update a Deployment, it creates a new ReplicaSet — you'll see this in `kubectl get rs`.
2. **The ReplicaSet is the actual Pod-reconciler.** The Deployment is a ReplicaSet manager.
3. **Some operators (e.g., older Operator SDK versions) generate ReplicaSets directly.**
4. **`kubectl scale rs/<name>` works on ReplicaSets, not Deployments.** When you scale a Deployment, the Deployment scales its ReplicaSet.

## Table of Contents

1. [The ReplicaSet Mental Model](#1-the-replicaset-mental-model)
2. [Manifest Anatomy](#2-manifest-anatomy)
3. [The Selector System — The Most Important Field](#3-the-selector-system--the-most-important-field)
4. [Pod Adoption — How an RS "Claims" Existing Pods](#4-pod-adoption--how-an-rs-claims-existing-pods)
5. [The Reconciler Loop](#5-the-reconciler-loop)
6. [ReplicaSet and Deployments — The Relationship](#6-replicaset-and-deployments--the-relationship)
7. [Rolling Updates, ReplicaSet-Style](#7-rolling-updates-replicaset-style)
8. [When You'd Actually Use a Bare ReplicaSet](#8-when-youd-actually-use-a-bare-replicaset)
9. [Operational Recipes](#9-operational-recipes)
10. [Troubleshooting](#10-troubleshooting)
11. [Gotchas and Common Mistakes](#11-gotchas-and-common-mistakes)
12. [Related Notes](#12-related-notes)

---

## 1. The ReplicaSet Mental Model

### The job

> "Maintain N Pods matching this selector, at all times."

Three numbers tell the whole story:

| Field | Meaning |
|---|---|
| `spec.replicas` | Desired number of Pods |
| `status.replicas` | Actual number of Pods currently managed by this RS |
| `status.readyReplicas` | Pods that are also `Ready: True` |

The controller's job is to make `replicas == readyReplicas` by reconciling the spec to the observed state.

### The watch-and-reconcile pattern

The ReplicaSet controller doesn't actively poll. It uses the **shared informer** pattern: it watches Pod events and reacts when the count of matching Pods diverges from `replicas`. The same pattern is used by every controller in Kubernetes.

```
┌──────────────────┐
│ ReplicaSet Spec  │
│ replicas: 3      │
└────────┬─────────┘
         │ (informer cache)
         ▼
┌──────────────────────────┐    too few     ┌─────────────┐
│  ReplicaSet controller   │───Pod create──▶│ API server  │
│  (per RS)                │                │  (creates)  │
│                          │                └─────────────┘
│  count of matching Pods  │
│       = 3?  keep watching│    too many    ┌─────────────┐
│       < 3?  create       │───Pod delete──▶│  API server │
│       > 3?  delete       │                │  (deletes)  │
└──────────────────────────┘                └─────────────┘
```

The controller never "checks" anything periodically. It reacts to events. That's the entire mental model.

### What a ReplicaSet does NOT do

| Capability | ReplicaSet | Deployment |
|---|---|---|
| Self-heal Pods | ✅ | ✅ (via the RS) |
| Maintain a fixed count | ✅ | ✅ (via the RS) |
| Rolling updates | ❌ | ✅ |
| Rollback to previous version | ❌ | ✅ |
| Pause / resume updates | ❌ | ✅ |
| Scale by changing a field | ✅ (edit `replicas`) | ✅ (transparently updates the RS) |

A ReplicaSet is "Pods of this template, exactly N of them, always." A Deployment is "rolling-update these Pods to a new template, while keeping the app available."

---

## 2. Manifest Anatomy

The minimum-viable ReplicaSet:

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  replicas: 3                    # desired count
  selector:                      # CRITICAL — see section 3
    matchLabels:
      app: frontend
  template:                      # Pod template (used to create new Pods)
    metadata:
      labels:
        app: frontend            # MUST match selector
    spec:
      containers:
      - name: web
        image: nginx:1.27
        ports:
        - containerPort: 80
```

Full anatomy, in field order:

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: frontend
  namespace: production
  labels:
    app: frontend
    tier: web
spec:
  replicas: 3                          # desired count (default 1)
  minReadySeconds: 0                   # min time a Pod must be Ready before counted as ready
  selector:                            # which Pods this RS owns
    matchLabels:                       # OR matchExpressions
      app: frontend
    matchExpressions:                  # same as Pod spec selectors
    - key: tier
      operator: In
      values: ["web", "api"]
  template:                            # Pod spec
    metadata:
      labels:
        app: frontend                  # MUST intersect with selector
    spec:
      containers:
      - name: web
        image: nginx:1.27
        # ... full Pod spec ...
status:
  replicas: 3
  fullyLabeledReplicas: 3
  readyReplicas: 3
  availableReplicas: 3
  observedGeneration: 1
  conditions: []
```

### Required fields

| Field | Required | Why |
|---|---|---|
| `apiVersion` | yes | Always `apps/v1` |
| `kind` | yes | Must be `ReplicaSet` |
| `metadata.name` | yes | DNS-1123 label |
| `spec.selector` | yes | Determines which Pods this RS owns |
| `spec.template` | yes | Pod template for new Pods |
| `spec.replicas` | no (default 1) | Desired count |

### The `template` vs `selector` constraint

`spec.template.metadata.labels` must **intersect** with `spec.selector`. That is, the labels on the template must include the selector's match. If they don't, the API server rejects the ReplicaSet with a clear error.

```yaml
# ❌ This will be rejected
selector:
  matchLabels:
    app: web
template:
  metadata:
    labels:
      app: api        # doesn't match selector
```

This constraint exists to prevent an infinite-creation loop: if the template didn't match the selector, the Pods an RS creates would never be selected by its own selector, and the controller would keep creating more.

---

## 3. The Selector System — The Most Important Field

The selector is the **most important field** in a ReplicaSet. Get it wrong and the controller's behavior is undefined in subtle ways.

### `matchLabels` — exact match

```yaml
selector:
  matchLabels:
    app: frontend
    tier: web
```

Matches Pods with **both** `app: frontend` AND `tier: web`. AND across keys, exact match on values.

### `matchExpressions` — richer matching

```yaml
selector:
  matchExpressions:
  - key: app
    operator: In
    values: [frontend, mobile]
  - key: env
    operator: NotIn
    values: [deprecated]
```

Supported operators:

| Operator | Behavior |
|---|---|
| `In` | Key's value is in the listed values |
| `NotIn` | Key's value is NOT in the listed values |
| `Exists` | Key exists (any value) |
| `DoesNotExist` | Key does not exist |

`In` and `NotIn` require `values`. `Exists` and `DoesNotExist` must NOT have `values` (the API server rejects otherwise).

### Combining matchLabels and matchExpressions

Both fields are AND'd together. All matchLabels conditions AND all matchExpressions conditions must be true.

### Why the selector is immutable

You **cannot change** `spec.selector` after the ReplicaSet is created. The API server rejects any patch that tries to. This is by design — if you change the selector, the RS would no longer select the Pods it owns, and the controller would create duplicates.

To change a selector, you must **delete the old RS and create a new one**. This is one of the reasons Deployments use ReplicaSets under the hood — when the Deployment's selector changes, it creates a new RS rather than mutating the old one.

---

## 4. Pod Adoption — How an RS "Claims" Existing Pods

Here's a subtle behavior that catches people: **a ReplicaSet can own Pods that it did not create.** If a Pod already exists with labels matching the RS's selector, the RS adopts it.

```yaml
# Existing Pod — not created by any controller
apiVersion: v1
kind: Pod
metadata:
  name: web-orphan
  labels:
    app: web          # matches the RS's selector
spec:
  containers:
  - name: web
    image: nginx:1.27
---
# RS that selects that Pod
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: web-rs
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginx:1.27
```

When `web-rs` is created, the controller sees: "I want 2 Pods. There's already 1 matching Pod (`web-orphan`). I need to create only 1 more." The orphan Pod is **adopted** — it becomes part of the ReplicaSet's count, gets the RS's owner reference, and is treated like any other replica.

### Adoption details

| Behavior | Detail |
|---|---|
| **Triggered by** | ReplicaSet creation or scale-up, with selector matching an existing orphan |
| **Owner reference** | Added to the adopted Pod. The Pod is now an "owner reference" of the RS. |
| **Deletion** | Scaling the RS down **can delete the adopted Pod** if it's "extra" |
| **Adopted Pods get no template updates** | Even if you change the RS template, the existing Pod is not updated |
| **What about scale-down** | The RS picks which Pods to delete; orphaned Pods are not protected |

### Why this matters

- **Don't name selectors too broadly.** If you create an RS with `selector: { app: web }` and there are already Pods in the cluster with that label (e.g., from a previous experiment), the RS adopts them. The new RS now has a mixed population of old and new Pods.
- **Selector overlap between two RSs is undefined behavior.** If two ReplicaSets select the same Pod, both will try to manage it. The result depends on which one's `replicas` count is higher. **Avoid this.**
- **The `fullyLabeledReplicas` status field** tells you how many Pods match the selector and have the full label set. Pods that match the selector but lack some labels are "partial" and may be deleted on scale-down.

### The fullyLabeledReplicas status

```yaml
status:
  replicas: 5             # total Pods matching selector
  fullyLabeledReplicas: 3 # Pods matching selector AND having all template labels
```

If `replicas > fullyLabeledReplicas`, you have **partially-labeled Pods** that the RS adopted but that don't carry the full template label set. These are candidates for deletion on scale-down. If you see this, suspect a label typo or a stray manual Pod.

---

## 5. The Reconciler Loop

The ReplicaSet controller runs a continuous reconciliation loop. It does the following on every relevant event:

```
1. List all Pods in the namespace
2. Filter by selector (matchLabels + matchExpressions)
3. Count: how many match?
4. If count < replicas:
     For each missing replica:
       Create a Pod from spec.template
       Set owner reference (so the Pod is garbage-collected when RS is deleted)
5. If count > replicas:
     For each extra Pod:
       Delete the extra Pod
       (Choose the most "disposable" first: failed > succeeded > running)
6. Update status (replicas, readyReplicas, availableReplicas)
7. Wait for next event
```

This loop runs **asynchronously** in response to events. The controller doesn't poll; it watches.

### What "wait for next event" means

If nothing changes — the right number of Pods are running, healthy, and matching — the controller is **idle**. No CPU, no API calls. It only acts when:

- A Pod is created (count might be too high)
- A Pod is deleted (count might be too low)
- A Pod changes labels (selector might no longer match)
- The RS spec is updated (replicas or template changed)
- The informer cache is resynced (every ~10 minutes by default)

### Race conditions in reconciliation

The reconciler is eventually consistent. There can be a small window where:

- A Pod is being scheduled → counted as 0
- The previous Pod is being deleted → counted as 1
- Total: 1, but spec is 2 → controller creates another

In steady state, this resolves within a few seconds. But under high churn, you may see `replicas` briefly diverge from `readyReplicas` — that's normal.

---

## 6. ReplicaSet and Deployments — The Relationship

A Deployment doesn't manage Pods directly. It manages **ReplicaSets**, and the ReplicaSets manage Pods. This is the layered-controller pattern, and it's how rolling updates work.

```
                    Deployment
                    │  (strategy, history)
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
   ReplicaSet "old"         ReplicaSet "new"
   replicas: 0              replicas: 3
   template: v1             template: v2
        │                       │
   ┌────┴────┐             ┌────┴────┐
   ▼         ▼             ▼         ▼
 Pod       Pod           Pod       Pod
 (v1)      (v1)          (v2)      (v2)
```

When you update a Deployment:

1. Deployment creates a **new ReplicaSet** with the new template
2. New RS scales up (one Pod at a time, or `maxSurge`)
3. Old RS scales down (one Pod at a time, or `maxUnavailable`)
4. When transition is complete, the old RS has `replicas: 0` but is **not deleted** (it's kept for rollback)
5. `kubectl get rs` shows you both: the old one (with 0 Pods) and the new one (with N)

### What the Deployment adds on top of a ReplicaSet

| Capability | ReplicaSet | Deployment |
|---|---|---|
| Maintain N replicas | ✅ | ✅ |
| Rolling update (gradual) | ❌ | ✅ |
| Rollback to previous revision | ❌ | ✅ |
| Pause / resume updates | ❌ | ✅ |
| Multiple update strategies | ❌ | ✅ (Recreate, RollingUpdate) |
| Revision history (with `kubectl rollout undo`) | ❌ | ✅ (default 10) |
| Progress deadline (timeout) | ❌ | ✅ (`progressDeadlineSeconds`) |

So when would you ever write a bare ReplicaSet? Section 8.

### How a Deployment "scales" a ReplicaSet

When you run `kubectl scale deployment/web --replicas=5`, the Deployment:

1. Sees the request
2. Identifies its active ReplicaSet (the one with non-zero replicas)
3. Patches that RS's `spec.replicas` to 5
4. The RS controller creates 2 more Pods

You can verify this with `kubectl get rs` — the active RS shows the new count, and the old (zero-replica) RS is unchanged.

---

## 7. Rolling Updates, ReplicaSet-Style

A bare ReplicaSet **cannot** do rolling updates. The template is mutable, but changing the template does **not** update existing Pods. It only changes the template used for new Pods (e.g., when the RS scales up after a Pod dies).

```yaml
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginx:1.27   # ← change this to 1.28
```

If you change this image to `nginx:1.28` and apply it:

- Existing 3 Pods (running 1.27) are **not** updated
- A new Pod, if created, would use 1.28
- This is **not** a rolling update — it's a template change for future Pods only

This is exactly the limitation that Deployments fix. A Deployment creates a new ReplicaSet with the new template and orchestrates the transition.

**Rule of thumb: never mutate a bare ReplicaSet's template in production.** Use a Deployment.

### What about a scale event — does that update Pods?

No. Scaling up creates new Pods from the **current** template. Scaling down deletes Pods (typically the newest first, but the choice is implementation-specific). Neither updates existing Pods to a new template.

---

## 8. When You'd Actually Use a Bare ReplicaSet

Honest list:

1. **Custom controllers (operator pattern)** — an Operator that needs a fixed number of identical Pods and manages its own update strategy. The Operator generates a ReplicaSet directly.

2. **The Deployment's underlying primitive** — you're writing a controller that IS to a ReplicaSet what a Deployment is to a ReplicaSet. Use a ReplicaSet as your foundation.

3. **One-off batch workloads without a Job's bookkeeping** — though `Job` is almost always better.

4. **Historical/legacy** — ReplicationController was the older API; ReplicaSet replaced it. If you see a `kind: ReplicationController` in old code, you should migrate to a Deployment with a ReplicaSet.

5. **Testing and demos** — when you want to demonstrate the reconciler pattern without the Deployment layer in the way.

For everything else, **use a Deployment**.

### Decision tree

```
Need to run Pods?
│
├── Need a fixed count + rolling update? ──▶ Deployment (owns a ReplicaSet)
│
├── Need a fixed count, no rolling update? ──▶ Bare ReplicaSet
│   (rare — custom controllers, demos)
│
├── Need run-to-completion? ──▶ Job
│
├── Need a schedule? ──▶ CronJob
│
├── Need one per node? ──▶ DaemonSet
│
├── Need stable network IDs and ordered deployment? ──▶ StatefulSet
│
└── Need direct control? ──▶ Bare Pod (debugging only)
```

---

## 9. Operational Recipes

### Recipe 1: Quick scale up

```bash
# Scale a Deployment's underlying RS
kubectl scale rs frontend-<hash> --replicas=10

# Better: scale the Deployment (which scales the RS)
kubectl scale deployment frontend --replicas=10
```

### Recipe 2: Force a particular image via the RS

```bash
# Get the current template
kubectl get rs frontend -o jsonpath='{.spec.template.spec.containers[0].image}'

# Patch the RS template
kubectl patch rs frontend -p '{"spec":{"template":{"spec":{"containers":[{"name":"web","image":"nginx:1.28"}]}}}}'
```

Note: this changes the template for future Pods only. Existing Pods are not updated. **Use a Deployment patch instead.**

### Recipe 3: Identify which RS owns a Pod

```bash
kubectl get pod <pod-name> -o jsonpath='{.metadata.ownerReferences[0].name}'
# Output: frontend-7c8d9b4f7
```

Or:

```bash
kubectl get pod <pod-name> -o jsonpath='{.metadata.ownerReferences}' | jq
```

### Recipe 4: Find the Deployment that owns an RS

```bash
kubectl get rs <rs-name> -o jsonpath='{.metadata.ownerReferences[0].name}'
# Output: frontend
```

The RS is owned by the Deployment; the Deployment is the higher-level controller.

### Recipe 5: Diagnose "too many Pods" or "too few Pods"

```bash
# Count Pods that match the selector
kubectl get pods -l app=frontend --no-headers | wc -l

# Compare to the RS's replicas
kubectl get rs frontend -o jsonpath='{.spec.replicas}'

# If they differ, look for:
# - Orphan Pods with the matching label
# - Other RSs selecting the same label
# - Manual Pod creations with the matching label
```

### Recipe 6: Delete a stuck Pod from a ReplicaSet

```bash
# Standard delete (kubelet will recreate it)
kubectl delete pod <pod-name>

# For a stuck Pod that won't terminate
kubectl delete pod <pod-name> --grace-period=0 --force
```

---

## 10. Troubleshooting

### Symptom: ReplicaSet has `replicas: 3` but only 1 Pod is running

**Check 1: Are the missing Pods Pending?**

```bash
kubectl get pods -l app=frontend
```

If you see `0/2 Pending`, look for `FailedScheduling` events:

```bash
kubectl describe rs frontend
# Look at the events section
```

Common causes:
- Insufficient node resources
- Node selector doesn't match any nodes
- Persistent volume can't be bound
- Taints without tolerations

**Check 2: Are the Pods CrashLoopBackOff?**

```bash
kubectl get pods -l app=frontend
# If status is CrashLoopBackOff, the Pod is restarting, not failing to schedule
```

Common causes:
- Bad image (ErrImagePull)
- Bad command/args
- Probe failing immediately
- Missing config/secret

**Check 3: Are Pods being deleted by something else?**

Check the Pod's events for `Killing`:

```bash
kubectl get pod <pod> -o yaml | grep -A 5 "lastState"
```

If you see frequent kills, suspect:
- A DaemonSet's `exclude` annotation
- An eviction (node pressure)
- A custom controller with overlapping selector

### Symptom: ReplicaSet has too many Pods

`status.replicas > spec.replicas` should not happen. If you see it:

- There are **adopted Pods** (created manually, with matching labels)
- There are **other ReplicaSets** with the same selector
- The controller is in the middle of a scale-up

```bash
# Find all Pods with the label
kubectl get pods -l app=frontend --show-labels

# Check for owner references
kubectl get pods -l app=frontend -o json | jq '.items[].metadata.ownerReferences'
```

If multiple owners appear, fix the selector overlap.

### Symptom: Pods not being deleted when scaling down

`spec.replicas: 1` but 3 Pods still running. Check:

```bash
kubectl describe pod <pod> | grep -A 5 "Conditions"
```

If you see `DisruptionTarget: True` and the Pod won't die, suspect a **PodDisruptionBudget** blocking the deletion. PDBs only apply to **voluntary** disruptions, but if the budget is set tight and the controller is trying a slow drain, it can stall.

```bash
# Look for PDBs
kubectl get pdb -A

# See the budget's current state
kubectl get pdb <name> -o yaml
```

### Symptom: `kubectl get rs` shows old ReplicaSets

After a Deployment update, you have:

```
NAME                  DESIRED   CURRENT   READY   AGE
frontend              3         3         3       5m
frontend-7c8d9b4f7    0         0         0       10m
```

The old RS (`frontend-7c8d9b4f7`) is kept for **rollback**. It's not a bug. To clean it up, you'd delete the Deployment (which cascades to the RS, which cascades to the Pods) — but this also loses the rollback history.

If you want to keep the Deployment but garbage-collect old RSs, lower `spec.revisionHistoryLimit` on the Deployment (default 10, can be set to 0 to keep none).

### Symptom: `selector is immutable` error

```
The ReplicaSet "frontend" is invalid: spec.selector: Forbidden: selector is immutable
```

You tried to change the RS's selector. The API server forbids it. To change a selector, you must:

1. Delete the old RS
2. Create a new RS with the new selector
3. Let the new RS adopt (or not adopt) the existing Pods

**This is why Deployments exist** — they create a new RS when needed rather than mutating the old one.

---

## 11. Gotchas and Common Mistakes

### Selector gotchas

- **`spec.selector` is immutable.** Cannot be changed after creation. To change, delete and recreate.
- **The template's labels must intersect with the selector.** If they don't, the API server rejects the RS.
- **Two ReplicaSets with the same selector is a bug.** They'll fight over the Pods.
- **Overly broad selectors adopt existing Pods.** If you have `selector: { app: web }` and there are old Pods with that label from a previous experiment, the new RS adopts them.

### Adoption gotchas

- **Adopted Pods are not updated** when you change the template. They keep their old spec.
- **Adopted Pods can be deleted on scale-down** if they're "extra." They're not protected.
- **`fullyLabeledReplicas < replicas`** indicates partially-labeled Pods. Investigate.

### Replica count gotchas

- **`spec.replicas: 0` is a valid scale-to-zero.** The RS will delete all its Pods. Useful for dev environments.
- **You can scale a ReplicaSet that's owned by a Deployment**, but the Deployment will fight you. Use the Deployment's `replicas` field instead.
- **`replicas` and `status.replicas` may briefly diverge** during reconciliation. This is normal.

### Template mutation gotchas

- **Changing `spec.template` does not update existing Pods.** It only changes the template for new Pods (e.g., when the RS scales up after a Pod dies).
- **Never mutate a bare ReplicaSet's template in production.** Use a Deployment.

### Controller interaction gotchas

- **A Deployment owns its ReplicaSets.** Don't manually delete a ReplicaSet that's owned by a Deployment; the Deployment will recreate it.
- **A ReplicaSet owns its Pods.** Don't manually delete a Pod that has an owner reference; the RS will recreate it (unless the controller is shutting down).
- **Owner references create cascading deletes.** Deleting an RS deletes all its Pods. Deleting a Deployment deletes all its RSs and all their Pods.

### Other gotchas

- **`minReadySeconds` is per-Pod, not per-RS.** A Pod must be `Ready` for this many seconds before it's counted as ready. Default 0.
- **The ReplicaSet name is used in the Pod's owner reference chain.** If you change the RS name, the chain breaks (for old Pods).
- **ReplicaSets don't run on a schedule.** For scheduled workloads, use a CronJob.
- **ReplicaSets don't provide stable network IDs.** For that, use a StatefulSet.

---

## 12. Related Notes

| Topic | Note |
|---|---|
| Pods (what an RS manages) | [[Kubernetes/concepts/L03-workloads/01-pods\|01 — Pods]] |
| Deployments (manage ReplicaSets) | [[Kubernetes/concepts/L03-workloads/03-deployments\|03 — Deployments]] |
| StatefulSets (stable IDs, ordered) | [[Kubernetes/concepts/L03-workloads/04-statefulsets\|04 — StatefulSets]] |
| DaemonSet (one per node) | [[Kubernetes/concepts/L03-workloads/05-daemonset\|05 — DaemonSet]] |
| Labels and selectors (in depth) | [[Kubernetes/concepts/L02-objects/01-kubernetes-objects\|L02 — Kubernetes Objects]] |
| PodDisruptionBudgets | [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling\|L06 — Scaling]] |

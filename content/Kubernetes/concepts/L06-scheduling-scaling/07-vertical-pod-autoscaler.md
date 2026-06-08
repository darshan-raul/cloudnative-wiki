# Vertical Pod Autoscaler (VPA)

*"https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler"*

The Vertical Pod Autoscaler (VPA) **adjusts the CPU and memory `requests` and `limits` of containers** in a Deployment, StatefulSet, ReplicaSet, DaemonSet, or Job, based on observed historical usage. It solves the "you have no idea what to set" problem — most teams either over-provision (wasting money) or under-provision (OOM-kills). VPA in `recommend` mode watches and tells you; in `Auto` mode it acts.

### Table of Contents

1. [What VPA Solves](#1-what-vpa-solves)
2. [VPA Modes](#2-vpa-modes)
3. [VPA Components](#3-vpa-components)
4. [Basic Example](#4-basic-example)
5. [The Three Recommenders in Detail](#5-the-three-recommenders-in-detail)
6. [Container Policies and Constraints](#6-container-policies-and-constraints)
7. [How VPA Resizes a Pod](#7-how-vpa-resizes-a-pod)
8. [VPA + HPA — The Coexistence Rules](#8-vpa--hpa--the-coexistence-rules)
9. [OOM and the "VPA Saved My Life" Pattern](#9-oom-and-the-vpa-saved-my-life-pattern)
10. [Limitations and Gotchas](#10-limitations-and-gotchas)
11. [VPA and Stateful Workloads](#11-vpa-and-stateful-workloads)
12. [Operations and Debugging](#12-operations-and-debugging)
13. [When to Use VPA](#13-when-to-use-vpa)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)

---

## 1. What VPA Solves

Setting resource requests is one of the hardest things in k8s. Three failure modes are common:

* **No requests at all** — BestEffort Pods. First to be evicted under pressure. Can't HPA on resource metrics. Most common rookie mistake.
* **Wildly over-provisioned requests** — "I'll set 4 cores and 8 GB to be safe." Wastes money, packs fewer Pods per node, makes the cluster feel expensive.
* **Wildly under-provisioned requests** — "I'll set 50m and 64Mi." OOM-kills in production. The app actually needs 1 core and 1 GB.

VPA observes real usage over a window and **computes the right value**. You can either take the recommendation (mode `Off`) or have it act on it (`Auto`, `Initial`).

```
                ┌────────────────────────────────────┐
                │  VPA recommender (VPA Controller)  │
                │                                    │
   Pod A ──────►│  1. observe:                        │
   Pod B ──────►│     - last 8 days of CPU, memory    │
   Pod C ──────►│     - 95th percentile usage        │
                │  2. recommend:                      │
                │     - lower bound, target, upper    │
                │  3. apply (Auto mode) or report:   │
                │     - write to VPA.status          │
                │     - or evict + recreate Pod      │
                └────────────────────────────────────┘
```

## 2. VPA Modes

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: web
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  updatePolicy:
    updateMode: Auto     # Off | Initial | Auto
```

### 2.1 `Off` — Recommend only

VPA computes recommendations and writes them to the VPA object's `status.recommendation` field. **It does NOT change any Pods.** This is the safe default for getting started.

```yaml
status:
  recommendation:
    containerRecommendations:
    - containerName: app
      lowerBound:
        cpu: 100m
        memory: 256Mi
      target:
        cpu: 250m
        memory: 512Mi
      upperBound:
        cpu: 500m
        memory: 1Gi
```

Three numbers per resource:

* **`lowerBound`** — minimum safe value. If the app uses less, it's wasteful.
* **`target`** — what VPA thinks the app actually needs (95th percentile of usage).
* **`upperBound`** — maximum VPA will ever set. Above this, the app is probably broken (memory leak, runaway CPU).

### 2.2 `Initial` — Set at creation only

VPA sets the right requests/limits at Pod **creation** time. Live Pods are not changed. This is a good compromise for stateful workloads that need right-sized requests but don't want VPA restarting their Pods.

```yaml
spec:
  updatePolicy:
    updateMode: Initial
```

When a new Pod is created, the VPA admission controller sets its `requests` to the recommendation. If the Pod's `requests` is already set in the manifest, VPA **overrides** it.

### 2.3 `Auto` — Set at creation AND resize live

VPA sets the right requests at creation AND evicts + recreates live Pods to apply new recommendations.

```yaml
spec:
  updatePolicy:
    updateMode: Auto
```

This is the most aggressive mode. The eviction happens via the eviction API (respects PDBs), then the Pod is recreated with new requests.

**VPA in Auto mode restarts Pods.** For stateful workloads, this is usually a no-go unless the app handles graceful restart well.

## 3. VPA Components

VPA has three components, each a separate Deployment:

```
┌─────────────────────────────────────────────────────────────┐
│  recommender (VPA Controller)                                │
│  - Watches Pods, computes recommendations                   │
│  - Writes to VPA.status.recommendation                      │
│  - One Deployment, scales horizontally                      │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  updater (VPA Updater)                                       │
│  - Watches VPA objects with updateMode: Auto                │
│  - Evicts Pods whose requests don't match the recommendation│
│  - Respects PDBs                                             │
│  - One Deployment, singleton (or 2 for HA)                  │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  admission-controller (VPA Admission Webhook)               │
│  - Mutating webhook on Pod creation                         │
│  - Sets requests from VPA's recommendation                  │
│  - Required for Initial and Auto modes                      │
│  - HA: 2+ replicas                                          │
└─────────────────────────────────────────────────────────────┘
```

All three must be running for VPA to work end-to-end. If the admission webhook is down, Pods may fail to create (the webhook is on the critical path).

## 4. Basic Example

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: web
  namespace: prod
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  updatePolicy:
    updateMode: Auto
  resourcePolicy:
    containerPolicies:
    - containerName: '*'           # applies to all containers
      minAllowed:
        cpu: 50m
        memory: 64Mi
      maxAllowed:
        cpu: "2"
        memory: 4Gi
      controlledResources:
      - cpu
      - memory
      - ephemeral-storage           # optional, off by default
    - containerName: 'sidecar'     # overrides for a specific container
      mode: "Off"                  # don't manage this container
```

This tells VPA:

* Watch the `web` Deployment.
* For all containers (`*`): keep CPU between 50m and 2, memory between 64Mi and 4Gi. Set both.
* For the `sidecar` container: don't manage it (e.g. it's a logging sidecar with a known fixed size).

## 5. The Three Recommenders in Detail

The recommender's job is to pick `lowerBound`, `target`, `upperBound` for each resource. It does this by analyzing the last **8 days** of usage data (configurable).

### 5.1 How the target is computed

The default target is the **95th percentile of usage** over the window. Why 95th and not mean?

* The mean is dragged down by idle periods. Setting requests to the mean means OOM during the 5% of busy moments.
* The 99th percentile is conservative — wastes capacity.
* The 95th is the standard compromise.

The computation is per-container, per-resource. If a container has had 3 replicas over the window, VPA pools their data.

### 5.2 The lower bound

The lower bound is the **minimum value that would have avoided OOM** during the window. If the container OOM-killed at 200Mi, the lower bound is 200Mi or higher. This is the safety net.

### 5.3 The upper bound

The upper bound is the **maximum VPA will ever set**. It's typically the highest observed value, with some headroom. Above this, VPA assumes the app has a memory leak or runaway CPU and won't try to "fix" it by giving it more.

### 5.4 Confidence

VPA also computes a **confidence** metric for each recommendation:

* **High** — plenty of data, recommendation is reliable.
* **Low** — sparse data, recommendation may be off.

The confidence is reflected in the VPA's `status.conditions`. **In Low confidence, VPA may skip resizing** (in Auto mode) to avoid bad recommendations.

## 6. Container Policies and Constraints

```yaml
spec:
  resourcePolicy:
    containerPolicies:
    - containerName: '*'
      minAllowed:
        cpu: 50m
        memory: 64Mi
      maxAllowed:
        cpu: "2"
        memory: 4Gi
      controlledResources:
      - cpu
      - memory
      mode: Auto
    - containerName: 'sidecar'
      mode: "Off"                    # don't touch this container
    - containerName: 'gpu-worker'
      minAllowed:
        nvidia.com/gpu: 1            # extended resources
      maxAllowed:
        nvidia.com/gpu: 1
      controlledResources: []        # no CPU/memory, only GPU
```

### 6.1 `minAllowed` and `maxAllowed`

Hard limits on VPA's recommendations. VPA will never set a request below `minAllowed` or above `maxAllowed`. This is your safety net — you can say "VPA, you can tune this, but never go below 100m CPU because the JVM warmup needs at least that."

### 6.2 `controlledResources`

Which resources VPA manages. Default: CPU and memory. Add `ephemeral-storage` to manage container writable layer + logs.

```yaml
controlledResources:
- cpu
- memory
- ephemeral-storage
```

### 6.3 `mode: "Off"` per-container

Useful for sidecars (logging, metrics, mesh) that have a known fixed size. VPA doesn't touch them.

```yaml
- containerName: 'istio-proxy'
  mode: "Off"
```

## 7. How VPA Resizes a Pod

In `Auto` mode, the VPA updater watches for Pods whose `requests` don't match the recommendation. When a mismatch is found:

1. **Evict the Pod** via the eviction API (respects PDBs).
2. **The Pod's controller** (Deployment, StatefulSet, etc.) creates a replacement.
3. **The VPA admission webhook** (on creation) sets the new Pod's `requests` to the recommendation.
4. The new Pod starts with the right size.

The cycle is: **observe → recommend → evict → recreate with new requests**.

The eviction is gentle (respects `terminationGracePeriodSeconds`). The Pod's container restarts happen via the normal k8s lifecycle, not a hard kill.

### 7.1 Timing

* The recommender updates recommendations every **1 minute** (configurable).
* The updater checks for mismatched Pods every **1 minute** (configurable).
* The admission webhook sets requests on every Pod creation.

So the latency from "metric spike" to "Pod resized" is **2-5 minutes** typically. **VPA is not real-time.** It's a slow, conservative resizer.

### 7.2 Pod startup race

If the recommender computes a new target at T=0, the updater evicts the Pod at T=1min, and the new Pod starts at T=1.5min — but the admission webhook is the one that sets the new `requests`. **If the webhook is down, the new Pod has its old (manually-set) `requests`, not VPA's recommendation.**

This is one of the most common VPA outages.

## 8. VPA + HPA — The Coexistence Rules

This is the most-asked question about VPA. **The answer: don't use both on the same metric.**

### 8.1 Why not

* **HPA on CPU** scales replicas based on `cpu_utilization = actual_cpu / requests_cpu`.
* **VPA on CPU** changes `requests_cpu`.
* If both are running, HPA sees `actual_cpu / new_requests_cpu` go down (because VPA raised requests), thinks it scaled too much, scales down. VPA sees fewer replicas, recomputes, etc. The two fight.

### 8.2 The safe patterns

**Pattern 1: VPA only on memory, HPA only on CPU.**

```yaml
# HPA: scale on CPU
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: web }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: web }
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
---
# VPA: tune memory only
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata: { name: web }
spec:
  targetRef: { apiVersion: apps/v1, kind: Deployment, name: web }
  updatePolicy: { updateMode: Auto }
  resourcePolicy:
    containerPolicies:
    - containerName: '*'
      controlledResources:
      - memory                  # only memory, leave CPU alone
      minAllowed: { memory: 256Mi }
      maxAllowed: { memory: 4Gi }
```

**Pattern 2: VPA in `Initial` mode, HPA on custom metric.**

```yaml
# VPA: set requests at creation, don't touch live Pods
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata: { name: web }
spec:
  targetRef: { apiVersion: apps/v1, kind: Deployment, name: web }
  updatePolicy: { updateMode: Initial }
  resourcePolicy:
    containerPolicies:
    - containerName: '*'
      controlledResources: [cpu, memory]
---
# HPA: scale on a custom metric (e.g. queue depth)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: web }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: web }
  minReplicas: 2
  maxReplicas: 100
  metrics:
  - type: Pods
    pods:
      metric: { name: queue_depth }
      target:
        type: AverageValue
        averageValue: "10"
```

HPA scales on a metric VPA doesn't touch. **No conflict.**

### 8.3 The "VPA on the same metric" footgun

If you set HPA on CPU and VPA on CPU+memory (with CPU included), they fight. The HPA controller emits an event:

```
HPA web was unable to compute the desired replica count:
  failed to get cpu utilization: missing request for cpu in container app
```

And/or the VPA emits:

```
VPA web: recommendation conflict with HPA scaling
```

Some HPA versions have a feature gate (`HPAScaleToZero`) and some HPA controllers ignore Pods with no `requests` — but VPA managing the same metric is the bigger problem.

## 9. OOM and the "VPA Saved My Life" Pattern

The most common use of VPA in production is **OOM-kill prevention in `recommend` mode**:

1. VPA computes `lowerBound: { memory: 800Mi }` (the value that would have avoided OOM yesterday).
2. You look at the recommendation.
3. You bump the Pod's `requests.memory` to 800Mi manually.
4. Tomorrow, the OOM is gone.

VPA in `recommend` mode is **observability** — it tells you the right value. The team decides when to apply it. This is the safe, low-risk adoption path.

**The pattern that fails:** set VPA in `Auto` mode on a stateful workload with a memory leak. VPA will keep raising `requests.memory` as the leak grows. The Pod keeps restarting. The leak gets worse. Eventually you hit `maxAllowed` and the OOM comes back.

## 10. Limitations and Gotchas

### 10.1 The fundamental limitation

**VPA can only set `requests` and `limits` that the Pod was already designed to accept.** If a Pod has no `resources` field at all, VPA can add it (in `Initial` or `Auto` mode). If it has `requests` but no `limits`, VPA can add `limits`. If it has both, VPA can change them.

**VPA cannot tell a container to use less** if the app is fundamentally hungry. It can only set the box bigger.

### 10.2 Cold start

VPA needs historical data to recommend. **A new Deployment has no data.** VPA returns a "no recommendation" until it has at least a few minutes of data (depending on the config).

For brand-new Deployments, you have two options:

* Set `requests` manually based on app docs.
* Use `updateMode: Initial` — VPA sets the request on the first Pod from limited data.

### 10.3 Vertical scaling and QoS

VPA changing `requests` may change the Pod's QoS class:

* `requests == limits` (Guaranteed) before, `requests != limits` (Burstable) after.
* The reverse can also happen.

QoS affects eviction order under node pressure. **VPA can move a Pod from "Guaranteed, last to evict" to "Burstable, evict before BestEffort" without warning.** This is a real footgun.

### 10.4 VPA and HPA controllers' resource usage

VPA's components (recommender, updater, admission controller) consume cluster resources. The recommender caches the last 8 days of metrics in memory — for a busy cluster, this can be hundreds of MB.

A reasonable starting point: 1-2 cores, 1-2 GB of memory for the recommender. Scale up for clusters with thousands of Pods.

### 10.5 VPA and PodDisruptionBudgets

VPA's evictions respect PDBs. If the PDB says `minAvailable: 1` and there's only 1 Pod, VPA can't evict it. The Pod stays at the old size until the PDB allows eviction.

This is correct behavior, but it means VPA resizes can be **delayed by PDBs**. In tight scenarios, VPA never catches up.

## 11. VPA and Stateful Workloads

The classic question: "Can I use VPA on my database StatefulSet?"

**Answer: only in `Off` or `Initial` mode, never in `Auto` mode.**

Why:

* StatefulSets have stable identities. Restarting a Pod to apply a new memory limit can disrupt a database that's mid-transaction.
* StatefulSet PVCs are tied to Pod identities. If the Pod is recreated with different requests, the new Pod binds to the same PVC, but the resize happens during restart.
* Database apps (Postgres, MySQL) have warmup phases. Restarting them is expensive.

The pattern:

1. Run VPA in `Off` mode.
2. VPA writes recommendations to `status.recommendation`.
3. Operator reviews recommendations.
4. Operator manually updates the StatefulSet's `template.spec.containers[].resources` if the change is meaningful.
5. Roll the StatefulSet with `kubectl rollout restart statefulset`.

**Don't put VPA in `Auto` on a StatefulSet.** The result is endless Pod restarts that can corrupt data.

## 12. Operations and Debugging

### 12.1 Common commands

```bash
# list VPAs
kubectl get vpa -A
# shows NAME, MODE, CPU, MEM, PROVIDED, AGE

# get recommendations
kubectl describe vpa <name>
# look at the Recommendation section

# check the controller
kubectl -n kube-system get pods -l app=vpa-recommender
kubectl -n kube-system logs -l app=vpa-recommender --tail=100
```

### 12.2 The "VPA not recommending" cases

| Symptom | Cause | Fix |
|---|---|---|
| `status.recommendation: <none>` | No data yet (new Deployment) | Wait, or set initial requests manually |
| `status.recommendation` frozen | Recommender down | Check recommender logs |
| Recommendation has no `lowerBound` | `minAllowed` blocked it | Adjust `minAllowed` |
| Recommendation hits `maxAllowed` | App is using more than `maxAllowed` | App probably has a leak; investigate before raising max |

### 12.3 The "VPA not resizing" cases (Auto mode)

| Symptom | Cause | Fix |
|---|---|---|
| Pods have old requests after a day | Updater is down | Check updater logs |
| Pods resize but restart constantly | App can't handle restart | Use `Off` or `Initial` |
| Pods not resizing because of PDB | PDB blocks eviction | Adjust PDB or replicas |

### 12.4 The webhook outage

If the VPA admission webhook is down, Pods that VPA manages fail to create. The error:

```
Error from server (InternalError):
  failed calling webhook "vpa.k8s.io":
  failed to call webhook: Post "https://vpa-webhook.kube-system.svc:443/...":
  dial tcp ...: i/o timeout
```

Fix: restart the webhook, or temporarily set `updateMode: Off` on the affected VPA.

## 13. When to Use VPA

### 13.1 The right time to use VPA

* **You don't know the right requests.** New service, no profiling, no historical data. Run VPA in `Off` mode, get recommendations, apply them.
* **You have a memory leak you're hunting.** VPA's `lowerBound` tells you the value that would have avoided OOM. Compare to actual usage — if there's a big gap, you have a leak.
* **You have a heterogeneous workload.** Different microservices with different needs. VPA per-Deployment.
* **You're over-provisioned and want to right-size.** VPA can save 30-50% on memory by tightening requests.

### 13.2 The right mode

| Mode | Use when |
|---|---|
| `Off` | You want recommendations but no automation. The safe starting point. |
| `Initial` | You want right-sized requests for new Pods, but no restart risk for live ones. Good for stateful. |
| `Auto` | Stateless services where restarts are cheap and the app handles them gracefully. Most common in production. |

### 13.3 The right metric set

| Set | Use when |
|---|---|
| `cpu, memory` | Default. Most apps. |
| `cpu` only | App has a known fixed memory footprint (JVM with `-Xmx`, native binary). |
| `memory` only | CPU is bursty / uninteresting; only memory matters (some batch jobs). |
| `cpu, memory, ephemeral-storage` | App writes a lot to disk (logs, caches). |

## 14. Gotchas and Common Mistakes

### 14.1 The 25+ common mistakes

1. **VPA in `Auto` on a stateful workload.** Causes endless Pod restarts. Use `Off` or `Initial` for StatefulSets.

2. **VPA on the same metric as HPA.** They fight. Use HPA on one metric, VPA on another.

3. **The admission webhook is on the critical path.** If it's down, Pods that VPA manages fail to create. Monitor it.

4. **VPA is in beta.** It's been "beta" since k8s 1.9. Works, but has rough edges. Don't trust it blindly.

5. **`maxAllowed` is a hard cap.** VPA will never exceed it. Set it based on what makes sense for the app, not what the cluster can do.

6. **`minAllowed` blocks VPA from being too aggressive.** Without it, VPA could recommend 10Mi of memory, which is dangerous.

7. **VPA's eviction respects PDBs.** A tight PDB can prevent VPA from ever resizing. Set PDBs with VPA in mind.

8. **VPA doesn't manage init containers' resources.** Only the main containers.

9. **VPA's recommendations lag by ~8 days.** A new traffic pattern takes a week to show up in recommendations.

10. **VPA doesn't work on `replicas: 0` Deployments.** The recommender has no data.

11. **VPA doesn't manage extended resources (GPU, etc.) by default.** Add them to `controlledResources` if you want VPA to manage them. Note: GPU is usually a fixed `1`, not a tunable value.

12. **VPA's `mode: "Off"` is per-container.** Useful for sidecars but easy to typo.

13. **VPA's recommender caches 8 days of data in memory.** For 10,000+ Pods, this is significant memory.

14. **VPA can change a Pod's QoS class.** Guaranteed → Burstable if `requests != limits` after resize. Affects eviction order.

15. **VPA's admission controller overrides user-set `requests`.** If you set `requests.cpu: 200m` in the Pod and VPA recommends 500m, the VPA wins. The `requests` in the manifest is ignored.

16. **VPA's status field is computed by the recommender.** It doesn't update in real-time. Check the `lastUpdateTime` to see when it was last computed.

17. **VPA in `Auto` doesn't work on Pods that have `priorityClassName: system-cluster-critical` or higher.** The eviction is blocked by the priority class.

18. **VPA components are cluster-wide.** A misbehaving recommender affects all VPAs in the cluster.

19. **VPA's `updatePolicy.updateMode` field is not validated against the VPA's `targetRef.kind`.** Setting it on a `DaemonSet` works but the eviction is unusual (DS Pods are recreated by the DS controller).

20. **VPA doesn't restart a Pod if the recommendation hasn't changed.** Eviction is only on a real change.

21. **VPA doesn't have a "dry run" mode at the API level.** You can simulate by running VPA in `Off` mode and reading the recommendations.

22. **VPA + `LimitRange` interaction is subtle.** LimitRange's `default` may set initial values that VPA then overrides.

23. **VPA + `ResourceQuota` interaction.** The quota is on `requests`, so as VPA raises `requests`, the namespace's quota fills up. Watch for "exceeded quota" errors.

24. **VPA's recommender doesn't know about HPA scale-down events.** A Pod that's been scaled up by HPA is still in the recommender's data.

25. **VPA doesn't tell you *why* a recommendation is what it is.** You get a number, not an explanation. For "why is memory spiking on Mondays", you need separate observability.

26. **VPA + PDB + `minReplicas: 1` HPA is a deadlock.** HPA keeps the Deployment at 1 Pod. PDB says minAvailable: 1. VPA can't evict. The Pod never resizes.

27. **VPA in `Auto` mode + immediate rollout is risky.** VPA evicts a Pod mid-deploy. The new Pod from the rollout comes up, VPA evicts it for being wrong-sized, the rollout completes, VPA evicts again. Storms of restarts.

28. **The `controlledResources` field defaults to `cpu` and `memory` only.** Add `ephemeral-storage` if you want to manage it.

29. **VPA's `lowerBound`, `target`, `upperBound` are independent per resource.** A container could have `cpu.lowerBound: 50m` and `memory.lowerBound: 200Mi`. They're not linked.

30. **VPA's eviction doesn't trigger a `kubectl rollout restart`.** It's a separate Pod deletion. The controller (Deployment, etc.) sees the deletion and creates a replacement.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource Requests & Limits]] — what VPA tunes
* [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] — the horizontal counterpart
* [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling|Scaling]] — L06 overview
* [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter|Karpenter]] — node autoscaling
* [[Kubernetes/concepts/L05-config-storage/08-resource-quota|ResourceQuota]] — namespace-level constraints VPA interacts with

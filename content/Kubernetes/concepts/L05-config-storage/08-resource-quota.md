# ResourceQuota and LimitRange

*"https://kubernetes.io/docs/concepts/policy/resource-quotas/"*

ResourceQuota and LimitRange are the two **namespace-level policy objects** that constrain what a namespace can use. They're how a cluster admin or platform team enforces "this namespace gets at most 100 GB of storage and 50 cores" or "Pods in this namespace can request at most 8 GB of memory each".

This note covers:

* **ResourceQuota** — aggregate limits for a namespace (total CPU, total memory, total storage, object counts, etc.).
* **LimitRange** — per-object limits and defaults (e.g. "every container in this namespace gets a default 100m CPU request if not specified").

These are **complementary** — ResourceQuota is the ceiling, LimitRange is the floor and per-object constraint.

### Table of Contents

1. [The Two-Policy Model](#1-the-two-policy-model)
2. [ResourceQuota — Aggregate Namespace Limits](#2-resourcequota--aggregate-namespace-limits)
3. [ResourceQuota Specification in Detail](#3-resourcequota-specification-in-detail)
4. [Compute Quotas (CPU / Memory / Ephemeral Storage)](#4-compute-quotas-cpu--memory--ephemeral-storage)
5. [Storage Quotas](#5-storage-quotas)
6. [Object Count Quotas](#6-object-count-quotas)
7. [Extended Resources (GPU, etc.)](#7-extended-resources-gpu-etc)
8. [LimitRange — Per-Object Defaults and Constraints](#8-limitrange--per-object-defaults-and-constraints)
9. [LimitRange Specification in Detail](#9-limitrange-specification-in-detail)
10. [The Pod's View: How Quotas Affect Scheduling](#10-the-pods-view-how-quotas-affect-scheduling)
11. [Operations and Debugging](#11-operations-and-debugging)
12. [Gotchas and Common Mistakes](#12-gotchas-and-common-mistakes)

---

## 1. The Two-Policy Model

```
                  Namespace
                      │
        ┌─────────────┴─────────────┐
        │                           │
        ▼                           ▼
   ResourceQuota                 LimitRange
   (aggregate ceiling)          (per-object floor / ceiling)
        │                           │
        │  - total CPU: 50         │  - default request per container
        │  - total memory: 200Gi   │  - max request per Pod
        │  - total storage: 1Ti    │  - max storage per PVC
        │  - max Pods: 100         │  - default storage request
        │  - max ConfigMaps: 200   │  - min storage request
        │                           │
        ▼                           ▼
   "Can't create more             "Every Pod/Container/PVC in this
   because quota exceeded"        namespace has these constraints"
```

### 1.1 Why two objects

* **ResourceQuota** is about the **namespace as a whole** — how much total resource consumption is allowed.
* **LimitRange** is about **individual objects** — what each Pod, Container, or PVC can request or limit.

A team might set:

* `ResourceQuota`: "this namespace gets at most 100 cores and 500 GB of memory"
* `LimitRange`: "every container in this namespace must request at least 100m CPU, can't request more than 8 cores"

The ResourceQuota says "the namespace is full, you can't add more Pods". The LimitRange says "this individual Pod is too big, you need to shrink it".

### 1.2 Are they required?

**No.** A namespace without a ResourceQuota and without a LimitRange has no constraints. Pods can request any amount, the namespace can have any number of objects.

Most production namespaces have at least one of these. Best practice is **both** — a ResourceQuota for the namespace ceiling, a LimitRange for per-Pod safety.

## 2. ResourceQuota — Aggregate Namespace Limits

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: prod
spec:
  hard:
    requests.cpu: "50"
    requests.memory: 200Gi
    limits.cpu: "100"
    limits.memory: 400Gi
    persistentvolumeclaims: "20"
    requests.storage: 1Ti
    requests.ephemeral-storage: 100Gi
    limits.ephemeral-storage: 200Gi
    pods: "100"
    configmaps: "200"
    secrets: "100"
    services: "50"
    services.loadbalancers: "5"
    services.nodeports: "5"
    count/jobs.batch: "10"
    count/cronjobs.batch: "20"
```

This says: "the `prod` namespace can have at most 50 cores of CPU requested, 200 GB of memory requested, 100 cores of CPU limited, etc."

### 2.1 What happens when quota is exceeded

When you try to create a Pod (or PVC, etc.) that would exceed the quota:

```
$ kubectl run test --image=busybox --requests='cpu=1' --restart=Never
Error from server (Forbidden):
  pods "test" is forbidden:
    exceeded quota: compute-quota,
    requested: requests.cpu=1,
    used: requests.cpu=50, limited: requests.cpu=50
```

The resource isn't created. The error tells you which quota and what's over.

For PVCs:

```
$ kubectl apply -f big-pvc.yaml
Error from server (Forbidden):
  persistentvolumeclaims "big-pvc" is forbidden:
    exceeded quota: storage-quota,
    requested: requests.storage=2Ti,
    used: requests.storage=1Ti, limited: requests.storage=1Ti
```

### 2.2 Quota is namespace-scoped

ResourceQuota lives in a namespace and applies to that namespace only. Different namespaces can have different quotas.

```yaml
metadata:
  namespace: prod       # this quota applies to the prod namespace
```

Cross-namespace quotas are not a thing. To limit the entire cluster, you'd need a controller that aggregates per-namespace quotas.

### 2.3 Quota is enforced at admission

The ResourceQuota is enforced by the **admission controller** in the apiserver. When you create a Pod:

1. The apiserver receives the request.
2. The ResourceQuota admission plugin checks: "would creating this Pod exceed any quota in the namespace?"
3. If yes, the request is rejected.
4. If no, the request proceeds.

**The Pod's resource requests are what count, not its actual usage.** A Pod that requests 1 CPU but uses 10 millicores still counts as 1 CPU against the quota.

### 2.4 Quota is observed

The apiserver updates the ResourceQuota's `status.used` field as resources are allocated. You can see the current usage:

```bash
kubectl describe resourcequota <name> -n <namespace>
# shows the hard limits, the used, and the difference
```

## 3. ResourceQuota Specification in Detail

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: full-quota
  namespace: prod
spec:
  hard:
    # compute
    requests.cpu: "50"
    requests.memory: 200Gi
    limits.cpu: "100"
    limits.memory: 400Gi
    requests.ephemeral-storage: 100Gi
    limits.ephemeral-storage: 200Gi
    # storage
    requests.storage: 1Ti
    persistentvolumeclaims: "20"
    # object counts
    pods: "100"
    configmaps: "200"
    secrets: "100"
    services: "50"
    services.loadbalancers: "5"
    services.nodeports: "5"
    replicationcontrollers: "20"
    resourcequotas: "5"               # max number of ResourceQuotas in the namespace
    # typed object counts
    count/jobs.batch: "10"
    count/cronjobs.batch: "20"
    count/deployments.apps: "50"
    count/statefulsets.apps: "10"
    # extended resources
    requests.nvidia.com/gpu: "8"
    limits.nvidia.com/gpu: "8"
  scopes:
  - NotTerminating                  # only count non-terminal Pods
  # OR
  scopes:
  - BestEffort                       # only count BestEffort Pods
  # OR
  scopes:
  - Terminating                      # only count terminating Pods
```

### 3.1 The `scopes` field

By default, the quota counts **all** Pods (BestEffort, Burstable, Guaranteed, and Terminating). You can scope the quota to a subset:

| Scope | Applies to |
|---|---|
| `Terminating` | Pods with `activeDeadlineSeconds` set, or Jobs |
| `NotTerminating` | All other Pods (the default) |
| `BestEffort` | Pods with no resource requests/limits set |
| `NotBestEffort` | Pods with at least one resource request/limit set |

**Example:** you want to limit Burstable / Guaranteed Pods but not BestEffort:

```yaml
spec:
  scopes:
  - NotBestEffort
  hard:
    requests.cpu: "50"
    requests.memory: 200Gi
```

BestEffort Pods (no requests) are unlimited; Burstable / Guaranteed are constrained.

**Example:** you want to limit Jobs separately from long-running Pods:

```yaml
# quota for long-running Pods
apiVersion: v1
kind: ResourceQuota
metadata:
  name: long-running
spec:
  scopes:
  - NotTerminating
  hard:
    pods: "50"
    requests.cpu: "30"
---
# quota for Jobs
apiVersion: v1
kind: ResourceQuota
metadata:
  name: jobs
spec:
  scopes:
  - Terminating
  hard:
    requests.cpu: "100"
    count/jobs.batch: "20"
```

Now you can have at most 50 long-running Pods and at most 20 Jobs, with separate CPU ceilings.

## 4. Compute Quotas (CPU / Memory / Ephemeral Storage)

```yaml
spec:
  hard:
    requests.cpu: "50"          # total CPU requested by all Pods
    requests.memory: 200Gi      # total memory requested by all Pods
    limits.cpu: "100"           # total CPU limits across all Pods
    limits.memory: 400Gi        # total memory limits across all Pods
    requests.ephemeral-storage: 100Gi   # total ephemeral storage requested
    limits.ephemeral-storage: 200Gi     # total ephemeral storage limits
```

### 4.1 Requests vs limits

A Pod can have both `requests` and `limits`. The quota can constrain each separately.

* **`requests.cpu` and `requests.memory`** — the **sum of all Pods' requests** must not exceed this. The scheduler uses this for placement.
* **`limits.cpu` and `limits.memory`** — the **sum of all Pods' limits** must not exceed this. The kubelet enforces this at runtime.

**Why have both?** A common pattern is:

* `requests.cpu: 50` — at most 50 cores of "guaranteed" capacity.
* `limits.cpu: 100` — Pods can burst up to 100 cores (overcommit).

This lets you overcommit, with the scheduler placing based on requests and the kubelet throttling based on limits.

### 4.2 The "Burstable QoS" implication

A Pod with `requests: {cpu: 100m}` and `limits: {cpu: 1}` is Burstable. It uses 100m against the request quota and 1 against the limit quota. **Both numbers count.**

A Pod with `requests: {cpu: 1}` and no limit is also Burstable (no limit = node capacity, but quota-wise the limit is the same as the request).

A Pod with `requests == limits` for both CPU and memory is Guaranteed. The numbers are the same.

### 4.3 Overcommitment math

If you have 10 nodes, each with 16 cores = 160 cores of cluster capacity.

* `requests.cpu: 80` — at most 80 cores of guaranteed capacity (50% overcommit).
* `limits.cpu: 160` — Pods can use up to 100% of cluster capacity.

This is a common setup. The scheduler uses the request for placement (so we don't overcommit placement), the kubelet uses the limit for throttling (so we don't OOM the node).

## 5. Storage Quotas

```yaml
spec:
  hard:
    requests.storage: 1Ti              # total storage requested by all PVCs
    persistentvolumeclaims: "20"       # max number of PVCs
    requests.ephemeral-storage: 100Gi  # total ephemeral storage requested (emptyDir, etc.)
    limits.ephemeral-storage: 200Gi    # total ephemeral storage limits
```

### 5.1 `requests.storage` vs `persistentvolumeclaims`

* **`requests.storage`** — the sum of all PVCs' `spec.resources.requests.storage`.
* **`persistentvolumeclaims`** — the count of PVCs.

A single namespace can have:

* 20 PVCs, each 50 GiB = 1 TiB total (`requests.storage: 1Ti`).
* 5 PVCs, each 200 GiB = 1 TiB total.
* 100 PVCs, each 10 GiB = 1 TiB total (but `persistentvolumeclaims: 20` would block the 21st).

The two constraints are **independent**. You can have 20 PVCs totaling 10 TiB if you only set `persistentvolumeclaims: 20`.

### 5.2 Storage class-specific quotas

```yaml
spec:
  hard:
    requests.storage: 1Ti                          # total across all classes
    gold.storageclass.requests.storage: 500Gi      # total for the gold class
    silver.storageclass.requests.storage: 500Gi    # total for the silver class
```

This constrains the total storage for each StorageClass. Useful for:

* **Tiered storage** — limit how much high-perf storage a namespace can use.
* **Cost control** — gp3 vs io2 vs sc1 have very different costs.

### 5.3 PVC count vs total storage

You can have:

```yaml
spec:
  hard:
    persistentvolumeclaims: "20"
    requests.storage: 1Ti
```

A namespace with 20 PVCs of 50 GiB each is at the limit. A namespace with 20 PVCs of 100 GiB each is **over** the storage quota but at the count limit.

**Both constraints must be satisfied.** Either can block a new PVC.

## 6. Object Count Quotas

```yaml
spec:
  hard:
    pods: "100"
    configmaps: "200"
    secrets: "100"
    services: "50"
    services.loadbalancers: "5"
    services.nodeports: "5"
    replicationcontrollers: "20"
    resourcequotas: "5"
```

These count **objects of the given type** in the namespace. Some examples:

* **`pods: 100`** — at most 100 Pods in the namespace (regardless of resource requests).
* **`services: 50`** — at most 50 Services.
* **`services.loadbalancers: 5`** — at most 5 LoadBalancer Services (a subset of `services`).
* **`services.nodeports: 5`** — at most 5 NodePort Services.

### 6.1 Typed object counts

```yaml
spec:
  hard:
    count/jobs.batch: "10"
    count/cronjobs.batch: "20"
    count/deployments.apps: "50"
    count/statefulsets.apps: "10"
    count/daemonsets.apps: "20"
```

The format is `count/<resource>.<api-group>`. The api-group is the part after the slash in the apiVersion (`apps/v1` → `apps`).

This is useful for:

* **Restricting who can create what** — only 10 StatefulSets, but unlimited Deployments.
* **Cost control** — LoadBalancer Services cost money; limit them.

## 7. Extended Resources (GPU, etc.)

```yaml
spec:
  hard:
    requests.nvidia.com/gpu: "8"
    limits.nvidia.com/gpu: "8"
```

Extended resources are **opaque to k8s** — they're reported by nodes (via the kubelet's `--node-labels` or the device plugin) and consumed by Pods. The most common is GPU:

```yaml
containers:
- name: ml
  image: tensorflow/tensorflow:latest-gpu
  resources:
    requests:
      nvidia.com/gpu: 1
    limits:
      nvidia.com/gpu: 1
```

The ResourceQuota can constrain how many GPUs a namespace can request.

**Other extended resources:**

* `nvidia.com/gpu` — NVIDIA GPUs
* `amd.com/gpu` — AMD GPUs
* `intel.com/sgx` — Intel SGX enclaves
* Custom resources from device plugins (FPGAs, InfiniBand, etc.)

The quota format is `requests/<resource-domain>/<resource-name>` and `limits/<resource-domain>/<resource-name>`.

## 8. LimitRange — Per-Object Defaults and Constraints

A LimitRange sets **per-object defaults and constraints** in a namespace. It's the "floor" and "ceiling" for individual objects.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: prod
spec:
  limits:
  - type: Container
    default:                  # applied if not set in the Pod
      cpu: 500m
      memory: 512Mi
    defaultRequest:           # applied if not set in the Pod
      cpu: 200m
      memory: 256Mi
    max:                      # max allowed per container
      cpu: "2"
      memory: 4Gi
    min:                      # min allowed per container
      cpu: 100m
      memory: 128Mi
    maxLimitRequestRatio:     # max ratio of limit:request
      cpu: 4
      memory: 2
  - type: Pod
    max:                      # max total per Pod (sum of all containers)
      cpu: "8"
      memory: 16Gi
  - type: PersistentVolumeClaim
    max:
      storage: 100Gi
    min:
      storage: 1Gi
  - type: PersistentVolumeClaim
    max:
      storage: 1Ti
    min:
      storage: 10Gi
    default:
      storage: 100Gi
    defaultRequest:
      storage: 50Gi
```

This is per-Pod, per-Container, and per-PVC constraints and defaults. **The defaults are applied automatically** to Pods / PVCs that don't specify the field.

### 8.1 The four types

| Type | Applies to | What it can do |
|---|---|---|
| `Container` | Each container in a Pod | default, defaultRequest, max, min, maxLimitRequestRatio |
| `Pod` | Each Pod (sum of all containers) | max (only) |
| `PersistentVolumeClaim` | Each PVC | default, defaultRequest, max, min |
| `PersistentVolume` | Each PV (cluster-wide) | max, min (rarely used) |

### 8.2 The `default` and `defaultRequest` fields

These are the **defaults applied to objects that don't specify the field**.

* `default.cpu: 500m` — if a Container doesn't specify `limits.cpu`, set it to 500m.
* `defaultRequest.cpu: 200m` — if a Container doesn't specify `requests.cpu`, set it to 200m.

The default is what the user gets if they don't say. The defaultRequest is the same for requests. The defaults can be overridden by the Pod's spec, but the **max** and **min** are hard constraints.

### 8.3 The `max` and `min` fields

Hard constraints on individual values:

* `max.cpu: 2` — no Container can request more than 2 cores.
* `min.memory: 128Mi` — no Container can request less than 128 MiB.

A Pod that violates a `max` or `min` is **rejected at admission**.

### 8.4 The `maxLimitRequestRatio`

The **maximum allowed ratio** of `limit:request` for a single resource:

```yaml
maxLimitRequestRatio:
  cpu: 4        # limit can be at most 4x the request
  memory: 2     # limit can be at most 2x the request
```

If a Pod sets `requests.cpu: 500m, limits.cpu: 1`, the ratio is 1/0.5 = 2, which is ≤ 4. Allowed.

If a Pod sets `requests.cpu: 500m, limits.cpu: 4`, the ratio is 4/0.5 = 8, which is > 4. Rejected.

**This is a "don't overcommit too much" guard.** It prevents Pods from setting tiny requests but huge limits (which would be a free-for-all).

## 9. LimitRange Specification in Detail

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: container-limits
  namespace: prod
spec:
  limits:
  - type: Container
    default:
      cpu: 500m
      memory: 512Mi
      ephemeral-storage: 1Gi
    defaultRequest:
      cpu: 200m
      memory: 256Mi
      ephemeral-storage: 100Mi
    max:
      cpu: "2"
      memory: 4Gi
      ephemeral-storage: 10Gi
    min:
      cpu: 100m
      memory: 128Mi
      ephemeral-storage: 10Mi
    maxLimitRequestRatio:
      cpu: 4
      memory: 2
      ephemeral-storage: 10
  - type: Pod
    max:
      cpu: "8"
      memory: 16Gi
      ephemeral-storage: 50Gi
  - type: PersistentVolumeClaim
    max:
      storage: 1Ti
    min:
      storage: 1Gi
    default:
      storage: 100Gi
    defaultRequest:
      storage: 10Gi
```

### 9.1 How defaults are applied

When a Pod is created in the namespace:

1. If the Pod has no `containers[].resources.requests.cpu`, the LimitRange's `defaultRequest.cpu` is applied.
2. If the Pod has no `containers[].resources.limits.cpu`, the LimitRange's `default.cpu` is applied.
3. The Pod's effective resources are checked against `max` and `min`.
4. If violations, the Pod is rejected.

**Defaults don't change the Pod's spec** — they only apply at admission. The Pod's spec remains as the user wrote it. (You can see the defaults via `kubectl describe pod` or by querying the apiserver with `?includeUninitialized=...`.)

### 9.2 The "BestEffort" trap

A Pod with **no** requests or limits is `BestEffort` QoS. The LimitRange's `defaultRequest` doesn't apply (it requires a request to be defaulted). BestEffort Pods are unlimited.

**To prevent BestEffort Pods, use a ResourceQuota with the `BestEffort` scope negation:**

```yaml
# Allow only Burstable / Guaranteed Pods
apiVersion: v1
kind: ResourceQuota
metadata:
  name: no-besteffort
spec:
  scopes:
  - NotBestEffort
  hard:
    pods: "100"
```

This counts Burstable and Guaranteed Pods only. **BestEffort Pods aren't counted by this quota** (they're unlimited by it), but they aren't blocked either. **To block BestEffort Pods, use a NetworkPolicy or a custom admission webhook.**

## 10. The Pod's View: How Quotas Affect Scheduling

A Pod's resource **requests** are what count against the quota. The scheduler uses the requests for placement.

### 10.1 The flow

```
User creates Pod (requests.cpu=1, requests.memory=1Gi)
       │
       ▼
admission: check ResourceQuota
       │
       ├── quota OK → Pod is created
       │
       └── quota exceeded → Pod is rejected with 403 Forbidden
```

### 10.2 Quota and the scheduler

The scheduler places Pods based on the node's available resources (sum of node capacity minus sum of Pods' requests). The ResourceQuota is a **separate, additional constraint** — it limits the namespace, not the cluster.

```
Cluster capacity: 160 cores
Namespace quota: requests.cpu: 50

Total requests in namespace: 50 cores
Total requests on nodes: 40 cores

A new Pod requests 2 cores.
- Scheduler: 40 + 2 = 42 < 160. Plenty of cluster capacity. OK.
- Quota: 50 + 2 = 52 > 50. Quota exceeded. Reject.
```

The Pod is rejected even though the cluster has plenty of capacity. **The namespace is full.**

### 10.3 The "quota exceeded" 403

When the quota blocks a Pod, the error is:

```
Error from server (Forbidden):
  pods "my-pod" is forbidden:
    exceeded quota: compute-quota,
    requested: requests.cpu=2,requests.memory=1Gi,
    used: requests.cpu=50,requests.memory=200Gi,
    limited: requests.cpu=50,requests.memory=200Gi
```

The error tells you which quota, what you requested, what's used, and what's the limit. **The Pod is not created.** `kubectl describe pod` will show the same error in events.

For PVCs:

```
Error from server (Forbidden):
  persistentvolumeclaims "my-pvc" is forbidden:
    exceeded quota: storage-quota,
    requested: requests.storage=1Ti,
    used: requests.storage=1Ti,
    limited: requests.storage=1Ti
```

### 10.4 What quota doesn't do

* **Quota doesn't move existing Pods to a different node.** It only blocks new creations / updates.
* **Quota doesn't evict Pods.** A Pod that's already running is fine, even if the namespace is now over quota (rare, but possible if the quota was reduced).
* **Quota doesn't care about actual usage.** A Pod that requests 1 CPU but uses 10 millicores still counts as 1 CPU.

## 11. Operations and Debugging

### 11.1 Common commands

```bash
# list ResourceQuotas
kubectl get resourcequota -A
# or
kubectl get quota -A

# describe
kubectl describe resourcequota <name> -n <namespace>
# shows hard limits, used, and the difference

# the same for LimitRange
kubectl get limitrange -A
kubectl describe limitrange <name> -n <namespace>

# check the current usage
kubectl describe resourcequota <name> -n <namespace> | grep -A 20 "Used"

# check why a Pod was rejected
kubectl describe pod <pod> -n <namespace>
# look for "exceeded quota" in events
```

### 11.2 The "Pod is forbidden" debugging

```
$ kubectl create -f pod.yaml
Error from server (Forbidden): ...
```

1. **Read the error message.** It tells you which quota, what's used, what's requested, what's the limit.
2. **Check the quota's current state:** `kubectl describe resourcequota <name> -n <namespace>`.
3. **Options:**
   * Increase the quota (`kubectl edit resourcequota`).
   * Reduce the Pod's requests.
   * Delete unused resources in the namespace.
   * Move the Pod to a different namespace.

### 11.3 The "PVC is forbidden" debugging

Same as Pod, but for PVCs. The error message tells you which storage quota is exceeded.

### 11.4 The "my Pod has no resource requests but should"

This is a LimitRange issue. The LimitRange has `defaultRequest` for the namespace, but the Pod has no requests — which means the Pod is BestEffort (unbounded).

**Fix:** either set the Pod's requests explicitly, or make the LimitRange's `defaultRequest` apply (it only applies to Pods with at least one resource set, not entirely empty Pods).

Actually, re-reading the docs: the LimitRange's `defaultRequest` IS applied to Pods that don't have requests. So a LimitRange with `defaultRequest: {cpu: 200m, memory: 256Mi}` would set those for a Pod with no requests.

**Verify with:**

```bash
kubectl get pod <pod> -o yaml
# look at spec.containers[].resources
# should have the defaults applied
```

## 12. Gotchas and Common Mistakes

### 12.1 The 25+ common mistakes

1. **A namespace without a ResourceQuota and LimitRange is unbounded.** A user can request 1000 cores and 1 PB of memory, and the apiserver accepts it.

2. **ResourceQuota is enforced at admission, not at runtime.** A Pod that already exists is not evicted if the quota is reduced. New Pods are blocked.

3. **A Pod's resource REQUESTS are what count, not its actual usage.** A Pod that requests 1 CPU but uses 10 millicores counts as 1 CPU against the quota.

4. **The `requests.cpu` and `limits.cpu` quotas are independent.** A Pod's request counts against `requests.cpu`, its limit counts against `limits.cpu`. Set both.

5. **BestEffort Pods are not counted by the `NotBestEffort` quota scope.** They have no requests, so they don't count. To limit them, use a separate quota or a NetworkPolicy / custom admission webhook.

6. **LimitRange's `defaultRequest` is applied at admission.** It doesn't change the Pod's spec, but the effective request is what the scheduler sees. `kubectl describe pod` shows the default.

7. **The `maxLimitRequestRatio` is a per-resource setting.** Set it for each resource individually (`cpu: 4, memory: 2`), not as a single value.

8. **The `Pod` type's `max` is the sum of all containers in the Pod.** A Pod with 2 containers, each requesting 2 cores, violates a `Pod.max.cpu: 2` (even if each container is below the Container `max`).

9. **The `PersistentVolumeClaim` type's `max` is per-PVC, not aggregate.** A quota of `max.storage: 100Gi` means each PVC can be at most 100 GiB. The aggregate is constrained by the ResourceQuota's `requests.storage`.

10. **A namespace can have multiple ResourceQuotas.** They all apply. A new resource must satisfy all of them.

11. **A namespace can have multiple LimitRanges.** They all apply. A new object must satisfy all of them.

12. **The `services.loadbalancers` quota is a subset of `services`.** If you set `services: 10` and `services.loadbalancers: 2`, you can have at most 10 Services, of which at most 2 are LoadBalancer.

13. **The `resourcequotas` quota limits the number of ResourceQuotas in a namespace.** Useful to prevent admin sprawl. Set it to 1 or 5.

14. **The default StorageClass is used by PVCs without `storageClassName`.** The default class isn't constrained by the per-class storage quota unless you set one. A PVC using the default class counts against the namespace's `requests.storage`, not the per-class quota.

15. **Per-storage-class quotas require the StorageClass to be installed.** A quota like `gp3.storageclass.requests.storage: 500Gi` only works if the `gp3` StorageClass is installed. Otherwise, no PVC can use it.

16. **The `count/<resource>.<api-group>` format is case-sensitive.** `count/deployments.apps` is correct. `count/Deployments.Apps` is not.

17. **The `requests.ephemeral-storage` and `limits.ephemeral-storage` are for emptyDir, container overlay, etc.** Not for PVCs.

18. **LimitRange's `default` for PersistentVolumeClaim is the `limits` equivalent.** It applies to the PVC's `spec.resources.limits.storage` (if set). Wait, actually it applies to the request... let me re-check.

Actually, for PVCs, `default` and `defaultRequest` are both supported. The behavior is similar to Container:

* `defaultRequest.storage` is applied if `spec.resources.requests.storage` is not set.
* `default.storage` is applied if `spec.resources.limits.storage` is not set.

But for PVCs, the standard is to use `requests` (the limit is the same as the request). So `default` and `defaultRequest` are usually the same.

19. **A LimitRange with `max: 0` blocks all creations.** Useful for "freeze" scenarios.

20. **A LimitRange with no `min` and no `max` is just defaults.** It's not a hard constraint; it just sets the values for objects that don't specify them.

21. **Quota doesn't apply to completed Jobs.** Once a Job is done, it's in `Complete` or `Failed` state. It may or may not be counted depending on the GC.

22. **Quota doesn't apply to Pods in the `Succeeded` or `Failed` phase.** Only `Running` and `Pending` Pods count.

23. **The `Terminating` scope counts Pods that are in the process of being deleted** (have `deletionTimestamp` set). Use `NotTerminating` to exclude them.

24. **The `BestEffort` scope only counts BestEffort Pods.** Use `NotBestEffort` to count the others.

25. **The `scopes` field is a list.** You can have multiple scopes (e.g. `NotTerminating` AND `NotBestEffort`). All must match for the quota to apply.

26. **The `pods` quota counts Pods regardless of state.** A namespace with `pods: 100` can have 100 Pods in any phase. To count only Running / Pending, use a custom controller.

27. **Quota doesn't account for nodes' overhead.** Each node reserves some CPU and memory for the kubelet, system processes, etc. The quota is on the Pod's resources, not the node's.

28. **The ResourceQuota admission controller is built into the apiserver.** It can't be disabled per-namespace; you have to delete the ResourceQuota.

29. **The LimitRange admission controller is also built into the apiserver.** Same — delete the LimitRange to disable.

30. **A namespace can have a `default` LimitRange that applies to all objects.** Set this up as a default for all new namespaces via an admission webhook or a controller.

## See also

* [[Kubernetes/concepts/L05-config-storage/04-persistentvolume|PersistentVolume]] — the cluster-scoped storage object
* [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim|PersistentVolumeClaim]] — the user-facing storage API
* [[Kubernetes/concepts/L05-config-storage/06-storageclass|StorageClass]] — dynamic provisioning
* [[Kubernetes/concepts/L06-scheduling-scaling/02-resource-requests-limits|Resource Requests and Limits]] — the per-Pod view
* [[Kubernetes/concepts/L05-config-storage/07-storage|Storage]] — the L05 mental model

---
title: DaemonSet — One Pod Per Node
tags: [kubernetes, workloads, daemonset, controllers, node-level, core-concepts]
date: 2026-06-07
description: The controller that runs exactly one Pod on every selected node. Update strategies, node selection, taints and tolerations, and the ops patterns that make DaemonSets the right answer for node-level agents.
---

# DaemonSet — One Pod Per Node

> https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/

A **DaemonSet** (DS) is a controller that ensures **one copy of a Pod runs on every (selected) node** in the cluster. When you add a node, the DS Pod is automatically scheduled onto it. When you remove a node, the Pod is garbage-collected. When a node becomes NotReady, the Pod is rescheduled elsewhere.

DaemonSets are the right answer for **node-level agents** — anything that needs to be on every machine by definition. Think log shippers, metrics exporters, CNI components, storage daemons, security agents. You don't say "how many" — you say "every node that matches this criteria," and the controller does the rest.

## Table of Contents

1. [The DaemonSet Mental Model](#1-the-daemonset-mental-model)
2. [When to Use a DaemonSet (and When NOT To)](#2-when-to-use-a-daemonset-and-when-not-to)
3. [Manifest Anatomy](#3-manifest-anatomy)
4. [Node Selection — Restricting Where the DS Runs](#4-node-selection--restricting-where-the-ds-runs)
5. [Taints, Tolerations, and the DS Scheduler](#5-taints-tolerations-and-the-ds-scheduler)
6. [Update Strategies](#6-update-strategies)
7. [Rolling Updates in Detail](#7-rolling-updates-in-detail)
8. [DaemonSet and the Host](#8-daemonset-and-the-host)
9. [Resource Budgets — A Hidden Cost](#9-resource-budgets--a-hidden-cost)
10. [DaemonSet Lifecycle (Add Node, Drain Node, Delete)](#10-daemonset-lifecycle-add-node-drain-node-delete)
11. [Operational Recipes](#11-operational-recipes)
12. [Troubleshooting](#12-troubleshooting)
13. [Gotchas and Common Mistakes](#13-gotchas-and-common-mistakes)
14. [Related Notes](#14-related-notes)

---

## 1. The DaemonSet Mental Model

### The contract

> "For every node matching this criteria, ensure exactly one Pod is running."

Unlike a Deployment (where you specify a count) or a StatefulSet (where you also specify a count), a DaemonSet's "count" is implicit — it's the size of the matching node set.

```
┌─────────────────────────────────────────────────────────────┐
│ Cluster: 4 nodes (2 workers, 2 control-plane)             │
│                                                               │
│ DaemonSet: log-shipper                                      │
│ Selector: role=worker                                       │
│                                                               │
│ Result:                                                      │
│   worker-1  ───▶  log-shipper Pod  ✓                         │
│   worker-2  ───▶  log-shipper Pod  ✓                         │
│   cp-1      ───▶  (no Pod)            (doesn't match)        │
│   cp-2      ───▶  (no Pod)            (doesn't match)        │
└─────────────────────────────────────────────────────────────┘
```

If you add a new worker node, the DaemonSet controller notices (via the node informer) and creates a Pod on it. If you delete a worker, the Pod is garbage-collected.

### What runs the DaemonSet controller

The DaemonSet controller runs in **kube-controller-manager** (not as a separate component). It watches:

- DaemonSet objects (for spec changes)
- Node objects (for membership changes)
- Pod objects (to track which DaemonSet Pods are running where)

When a node appears, the controller computes "which DaemonSets should run a Pod on this node?" and creates the Pod, bypassing the regular scheduler. **DaemonSet Pods are not scheduled by the normal scheduler** — they're placed by the DS controller.

### Why the DS controller, not the scheduler

The scheduler is designed to optimize placement (spread, binpack, affinity, etc.). The DS controller is doing something simpler: "one per node." Routing this through the scheduler would add overhead and introduce scheduling semantics that don't apply. The DS controller:

1. Computes the set of "matching" nodes
2. For each DS, creates a Pod on each matching node, with `spec.nodeName` pre-set
3. The kubelet on that node picks up the Pod and starts it

This bypasses the normal scheduler but respects taints, tolerations, and node selectors (see section 5).

---

## 2. When to Use a DaemonSet (and When NOT To)

### The right use cases

A DaemonSet is the right answer when your workload has the property **"there must be one of me on every node"** (or every node matching a criteria).

| Use case | Why DS |
|---|---|
| **Node-level log shippers** (Fluent Bit, Filebeat, Promtail, Vector) | Each node has unique local logs to read |
| **Node-level metrics agents** (node-exporter, Datadog agent, Dynatrace OneAgent) | Each node has unique metrics to emit |
| **Cluster networking components** (CNI agents like Calico, Cilium; kube-proxy replacements) | The CNI needs to be on every node to function |
| **Storage daemons** (CSI drivers like Glusterd, Ceph, local-path-provisioner) | The storage backend has a per-node agent |
| **Node-level security agents** (Falco, Tracee, Wazuh agent) | Each node has unique kernel events to monitor |
| **GPU drivers / device plugins** | Some hardware needs a per-node agent |
| **Node-level debug tools** (e.g., a privileged toolbox Pod that's always there for SSH-style debugging) | A "break glass" Pod available on every node |

### The wrong use cases

A DaemonSet is the **wrong** answer when:

| Use case | Why NOT DS |
|---|---|
| **You want a fixed count of replicas** | Use a Deployment |
| **You want stable network IDs and ordered deployment** | Use a StatefulSet |
| **You want run-to-completion** | Use a Job |
| **You want a scheduled workload** | Use a CronJob |
| **You want a "per-customer" or "per-tenant" Pod** | The "per-X" unit isn't a node |
| **The workload scales with traffic, not with nodes** | Use a Deployment with HPA |

### The decision tree

```
Need to run Pods on every node? (or every node matching X)
│
├── Yes ──▶ DaemonSet
│
├── Need a fixed count?
│   └── Yes ──▶ Deployment
│
├── Need run-to-completion?
│   └── Yes ──▶ Job / CronJob
│
├── Need stable network IDs?
│   └── Yes ──▶ StatefulSet
│
└── Need direct control / debugging only?
    └── Bare Pod (kubectl run)
```

### Real-world example: a full observability stack

```
┌────────────────────────────────────────────────────┐
│ Cluster (3 nodes)                                  │
│                                                     │
│  node-1                          node-2            │
│  ┌─────────────────────┐        ┌──────────────┐  │
│  │  app Pod            │        │ app Pod      │  │
│  │  (Deployment)       │        │ (Deployment) │  │
│  └─────────────────────┘        └──────────────┘  │
│  ┌─────────────────────┐        ┌──────────────┐  │
│  │  log-shipper (DS)   │        │ log-shipper  │  │
│  │  reads /var/log     │        │ (DS)         │  │
│  └─────────────────────┘        └──────────────┘  │
│  ┌─────────────────────┐        ┌──────────────┐  │
│  │  node-exporter (DS) │        │ node-exp (DS)│  │
│  │  exports metrics    │        │              │  │
│  └─────────────────────┘        └──────────────┘  │
│  ┌─────────────────────┐        ┌──────────────┐  │
│  │  promtail (DS)      │        │ promtail (DS)│  │
│  │  ships to Loki      │        │              │  │
│  └─────────────────────┘        └──────────────┘  │
└────────────────────────────────────────────────────┘
```

Three DaemonSets, each on every node, each doing one job. This is the canonical observability pattern.

---

## 3. Manifest Anatomy

A minimum-viable DaemonSet:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentbit
  namespace: logging
spec:
  selector:                              # CRITICAL — like ReplicaSet
    matchLabels:
      app: fluentbit
  template:                              # Pod template
    metadata:
      labels:
        app: fluentbit
    spec:
      containers:
      - name: fluentbit
        image: fluent/fluent-bit:3.0
        volumeMounts:
        - name: varlog
          mountPath: /var/log
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
          type: Directory
```

Full anatomy:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: monitoring
  labels:
    app: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  updateStrategy:                        # see section 6
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  minReadySeconds: 0                     # min time a Pod must be Ready before considered ready
  revisionHistoryLimit: 10               # how many old ReplicaSets to keep
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      # Pod scheduling
      nodeSelector:                      # restrict to nodes with this label
        node-role.kubernetes.io/worker: ""
      affinity:                          # richer constraints
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values: ["linux"]
      tolerations:                       # tolerate node taints
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      priorityClassName: system-node-critical  # high priority for system DS
      # Pod spec
      serviceAccountName: node-exporter
      hostNetwork: true                  # use node's network (often true for DS)
      hostPID: false
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.7.0
        args:
        - --path.procfs=/host/proc
        - --path.sysfs=/host/sys
        - --path.rootfs=/host/root
        - --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)
        ports:
        - name: metrics
          containerPort: 9100
          hostPort: 9100                  # expose on the node's IP
        resources:
          requests:
            cpu: 100m
            memory: 30Mi
          limits:
            cpu: 200m
            memory: 50Mi
        readinessProbe:
          httpGet:
            path: /
            port: metrics
          periodSeconds: 10
        securityContext:
          runAsNonRoot: false             # node-exporter needs root for /proc, /sys
          hostPID: true                   # see /host/proc
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
        - name: root
          mountPath: /host/root
          readOnly: true
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
      - name: root
        hostPath:
          path: /
status:
  desiredNumberScheduled: 5
  currentNumberScheduled: 5
  numberReady: 5
  updatedNumberScheduled: 5
  numberMisscheduled: 0
  numberUnavailable: 0
  observedGeneration: 1
  conditions: []
```

### Required fields

| Field | Required | Why |
|---|---|---|
| `apiVersion` | yes | Always `apps/v1` |
| `kind` | yes | Must be `DaemonSet` |
| `metadata.name` | yes | DNS-1123 label |
| `spec.selector` | yes | Determines which Pods the DS owns |
| `spec.template` | yes | Pod template |
| `spec.updateStrategy` | no (default `RollingUpdate`) | How the DS updates its Pods |
| `spec.template.spec.nodeSelector` | no | Restrict which nodes the DS runs on |

### The selector constraint

Like a ReplicaSet, the template's labels must **intersect** with the selector. The API server validates this on creation and update.

---

## 4. Node Selection — Restricting Where the DS Runs

By default, a DaemonSet runs on **every node in the cluster**. To restrict, use one of:

### `nodeSelector` — simple key-value

```yaml
spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/worker: ""    # only nodes with this label
```

You can also use `kubernetes.io/os: linux` to exclude Windows nodes, or `kubernetes.io/arch: amd64` to exclude ARM nodes.

### `nodeAffinity` — richer rules

```yaml
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: disktype
                operator: In
                values: ["ssd"]
              - key: kubernetes.io/hostname
                operator: NotIn
                values: ["legacy-1", "legacy-2"]
```

`nodeAffinity` supports AND, OR, In, NotIn, Exists, DoesNotExist — the full Pod-affinity expression language. See [[Kubernetes/concepts/L06-scheduling-scaling|L06 — Scheduling and Scaling]] for details.

### Per-node exclusion

You can mark a node as **excluded from all DaemonSets** by adding this taint:

```bash
kubectl taint nodes <node-name> node.kubernetes.io/exclude-daemonsets=true:NoSchedule
```

This is the standard way to say "this node is for special workloads, don't run DS Pods on it." Use it for:

- Nodes reserved for batch jobs
- Nodes that run control-plane components only
- Nodes that are in maintenance

The taint is **additive** — DS Pods that have a toleration for it will still run. The taint just opts a node out of the default.

### Taints with the legacy `schedulingDisabled` annotation

The old way (pre-1.6) was the annotation `scheduler.alpha.kubernetes.io/ignore-daemonsets`. This is **deprecated and ignored** in modern clusters. Use the taint.

---

## 5. Taints, Tolerations, and the DS Scheduler

A critical mental model: **DaemonSet Pods bypass the normal scheduler**, but the **DS controller still respects taints and tolerations**. If a node has a taint that the Pod template doesn't tolerate, the DS Pod will not run on that node.

### The default taint situation

In most clusters, control-plane nodes have a taint:

```
node-role.kubernetes.io/control-plane:NoSchedule
```

This taint **rejects all Pods** that don't tolerate it. To run a DaemonSet on control-plane nodes (e.g., for a CNI), you must add a toleration:

```yaml
spec:
  template:
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/master     # older clusters
        operator: Exists
        effect: NoSchedule
```

The result: the DS runs on every node, including control-plane. If you don't add the toleration, the DS runs only on worker nodes.

### Unschedulable taints and DS

A node marked `node-role.kubernetes.io/control-plane:NoSchedule` (the same one we just tolerationed) does **not** receive DS Pods unless the Pod's tolerations list that taint. This is correct behavior — control-plane nodes are unschedulable for normal Pods, but DS Pods that tolerate the taint can still run.

A node that is **cordoned** (`kubectl cordon`) is different. Cordon adds a taint that makes the node unschedulable for normal Pods, but DaemonSets that don't tolerate the taint are also blocked. DaemonSets that tolerate it still run.

A node that is **drained** (`kubectl drain`) is cordoned plus Pods are evicted. DaemonSet Pods are **also evicted** during drain — unless they tolerate the `node.kubernetes.io/unschedulable` taint (see below).

### The drain escape hatch

Some DaemonSets (e.g., a debug agent, a security scanner) need to survive a `kubectl drain`. The taint added during drain can be tolerated:

```yaml
tolerations:
- key: node.kubernetes.io/unschedulable
  operator: Exists
  effect: NoSchedule
```

This is appropriate for system-critical DS like CNI plugins, but not for general-purpose agents.

### `unschedulable` field (deprecated)

The legacy `spec.unschedulable` on a node (set by `kubectl cordon`) used to be a separate boolean. In modern clusters, this is implemented as the `node.kubernetes.io/unschedulable` taint. The boolean is still accepted for backward compatibility but should not be used directly.

---

## 6. Update Strategies

A DaemonSet has two update strategies, configured via `spec.updateStrategy`:

### RollingUpdate (default)

Old Pods are killed and replaced, one at a time (or `maxUnavailable` at a time).

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1         # at most 1 Pod down at a time
```

`maxSurge` is supported as of k8s 1.22, but only when your cluster supports it. With `maxSurge: 1`, a new Pod is created before the old one is killed, ensuring no gap in coverage.

**Without `maxSurge` (default in older clusters):**

```
node-1: old Pod killed, new Pod scheduled, old Pod terminating
        (briefly: no log shipper on node-1 — gap in observability)
node-2: still running old Pod
node-3: still running old Pod
```

**With `maxSurge: 1` (k8s 1.22+):**

```
node-1: new Pod starts (maxSurge), then old Pod is killed
        (no gap)
```

`maxSurge` requires a CNI that supports additional IP allocation. If yours doesn't, omit it.

### OnDelete

Old Pods are kept until you manually delete them.

```yaml
spec:
  updateStrategy:
    type: OnDelete
```

Use this when:

- **GPU drivers** — only one driver version can run at a time
- **Kernel modules** — loading/unloading has ordering constraints
- **Databases with local state** — you need to drain traffic before restart
- **Custom controllers** — you want full manual control over the update order

With `OnDelete`, the workflow is:

1. Update the DS template (e.g., new image)
2. Manually `kubectl delete pod` on each node's Pod, one at a time
3. The DS controller creates the new Pod on the same node (because of the selector)
4. Repeat for the next node

This gives you complete control over the rollout order and timing.

### Choosing a strategy

| Need | Strategy |
|---|---|
| Standard log/metrics shippers, low impact | RollingUpdate with `maxUnavailable: 1` |
| Critical: zero gap in coverage | RollingUpdate with `maxSurge: 1` (k8s 1.22+) |
| GPU drivers, kernel modules, ordered updates | OnDelete |
| Canary / staged rollout | OnDelete + manual deletion per node |

---

## 7. Rolling Updates in Detail

When you change a DaemonSet's template (e.g., new image), the DS controller does the following:

### Rolling update flow

```
1. User edits the DS spec (kubectl edit ds, or via Deployment-style patch)
2. DS controller sees the change
3. Controller computes: which nodes have old Pods, which have new Pods
4. For each old Pod (one at a time, up to maxUnavailable):
   a. Pick a node (round-robin or oldest-first)
   b. Mark the Pod for deletion
   c. Wait for the new Pod to be Ready
   d. Move to the next node
5. When all old Pods are replaced, update is complete
```

You can monitor progress with:

```bash
kubectl rollout status ds/<name>
kubectl get ds <name> -o jsonpath='{.status}'
```

### The status fields

```yaml
status:
  desiredNumberScheduled: 5     # total nodes that should have a Pod
  currentNumberScheduled: 5     # Pods scheduled
  numberReady: 5                # Pods that are Ready
  updatedNumberScheduled: 5     # Pods running the new template
  numberUnavailable: 0          # Pods not Ready
  numberMisscheduled: 0         # Pods on nodes that no longer match the DS
  observedGeneration: 2         # last DS spec generation seen
```

If `numberReady == desiredNumberScheduled` and `updatedNumberScheduled == desiredNumberScheduled`, the rollout is complete.

### Rolling back

DaemonSets do not have built-in rollback. To roll back:

1. Edit the DS spec to the old image
2. The DS controller does a rolling update to the old image

Or, more cleanly:

```bash
# View the rollout history
kubectl rollout history ds/<name>

# Roll back (uses the previous revision)
kubectl rollout undo ds/<name>

# Roll back to a specific revision
kubectl rollout undo ds/<name> --to-revision=3
```

This requires `spec.revisionHistoryLimit > 0` (default 10) so old templates are kept.

### Pausing a rollout

If a rolling update is mid-flight and you want to stop:

```bash
kubectl rollout pause ds/<name>
```

Resume with:

```bash
kubectl rollout resume ds/<name>
```

This is the same mechanism as Deployment pause/resume, applied to the DS's rolling update.

---

## 8. DaemonSet and the Host

DaemonSet Pods typically need access to the **host** (the node itself). This is the source of most "is the DS doing weird things" complaints.

### `hostNetwork: true`

The Pod shares the node's network namespace. The Pod's port is the node's port.

```yaml
spec:
  template:
    spec:
      hostNetwork: true
      containers:
      - name: node-exporter
        ports:
        - containerPort: 9100
          hostPort: 9100
```

Why use it:

- The Pod is reachable on the node's IP, not just the Pod IP
- No NAT, no port translation
- Useful for service-discovery and Prometheus scraping

Why avoid it (for non-DS workloads):

- Bypasses NetworkPolicy (no Pod-level traffic filtering)
- Bypasses the cluster DNS
- Increases the blast radius of a compromised Pod

For DaemonSets, `hostNetwork: true` is **acceptable and common** for node-level agents.

### `hostPath` volumes

The Pod mounts a directory from the node's filesystem.

```yaml
volumes:
- name: varlog
  hostPath:
    path: /var/log
    type: DirectoryOrCreate
```

The Pod sees the node's `/var/log` as if it were its own. This is how log shippers read local logs.

`type` controls behavior on the node:

| Type | Behavior |
|---|---|
| `DirectoryOrCreate` | Use existing dir, or create empty dir (default if omitted) |
| `Directory` | Must exist, fail if missing |
| `FileOrCreate` | Use existing file, or create empty file |
| `File` | Must exist, fail if missing |
| `Socket` | Must be a Unix socket |
| `CharDevice` | Must be a char device |
| `BlockDevice` | Must be a block device |

The `DirectoryOrCreate` default can mask configuration mistakes. Use `Directory` if you need to ensure the host path exists.

### `hostPID: true` and `hostIPC: true`

The Pod shares the node's PID or IPC namespace.

```yaml
spec:
  hostPID: true              # Pod can see all host processes (ps aux shows host PIDs)
  hostIPC: true              # Pod shares SysV IPC with the host
```

`hostPID: true` is needed for agents that watch host processes (e.g., node-exporter, security tools). It's a **significant security risk** — a compromised Pod can inspect every process on the node. Use it only for trusted, security-reviewed DS Pods.

### Security implications

DaemonSet Pods that touch the host (hostNetwork, hostPath, hostPID) are a **major attack surface**. A compromised DS Pod can:

- Read all node logs (hostPath /var/log)
- Read /proc for every process (hostPID)
- Bind to any port (hostNetwork)
- Read /etc/shadow or other host files (hostPath)

Mitigations:

- **Run DS as non-root where possible** (`runAsNonRoot: true`)
- **Use read-only mounts** (`readOnly: true` on volumeMounts)
- **Drop Linux capabilities** (`capabilities.drop: ["ALL"]`)
- **Use `priorityClassName: system-node-critical`** so the kubelet prefers to keep them running
- **Apply Pod Security Standards** to the namespace (`pod-security.kubernetes.io/enforce: restricted`)
- **Audit DS manifests regularly** — any DS with `hostPID: true` deserves review

---

## 9. Resource Budgets — A Hidden Cost

DaemonSet Pods run on **every node**. Their resource requests are summed across the entire cluster.

### The math

| DS requests | Cluster size | Total reserved |
|---|---|---|
| 100m CPU, 128Mi memory | 10 nodes | 1 CPU, 1.28Gi |
| 200m CPU, 256Mi memory | 100 nodes | 20 CPU, 25.6Gi |
| 500m CPU, 512Mi memory | 1000 nodes | 500 CPU, 512Gi |

A "small" DS that asks for 500m CPU and you have 100 nodes = **50 cores reserved cluster-wide**, just for that one DS.

### The cost on cluster sizing

If your node is 4 CPU and 16Gi memory, and you have 5 DaemonSets each requesting 200m CPU and 256Mi memory, you've already burned:

```
5 DS × 200m CPU = 1.0 CPU
5 DS × 256Mi memory = 1.25Gi
```

That's 25% of your node's CPU and 8% of its memory — gone before any application Pods run.

### How to estimate

For each DS, compute: `requests × number_of_matching_nodes`. Sum across all DS. Subtract from node capacity. What's left is what your application Pods can use.

```bash
# Sum of CPU requests across all DS
kubectl get ds -A -o json | jq '[.items[] | {
  name: .metadata.name,
  cpu: (.spec.template.spec.containers[].resources.requests.cpu // "0" | tonumber? // 0)
}] | map(.cpu) | add'

# Or with kubectl and a label selector:
kubectl get pods -A -l app=node-exporter -o json | jq '[.items[].spec.containers[].resources.requests.cpu] | map(tonumber? // 0) | add'
```

### Tips for keeping DS budgets low

- **Set `requests`, not `limits`, for most DS Pods.** Limits throttle or kill the Pod; DS Pods should run reliably.
- **Right-size requests.** Don't ask for 1 CPU if the agent uses 50m. Profile under realistic load.
- **Use `Burstable` QoS, not `Guaranteed`, for most DS.** Saves memory headroom.
- **For purely "fire and forget" agents**, consider BestEffort (no requests). Acceptable if the agent can restart.
- **Consider `system-node-critical` PriorityClass** for system DS so they're not evicted under pressure.

---

## 10. DaemonSet Lifecycle (Add Node, Drain Node, Delete)

### New node joins the cluster

```
1. Node is registered with the API server
2. DaemonSet controller notices (via node informer)
3. For each DS, check: should this node have a Pod?
4. If yes, create the Pod with spec.nodeName set to the new node
5. Kubelet on the new node picks up the Pod and starts it
```

Latency: typically 5-10 seconds from node registration to Pod start.

### Node becomes NotReady

```
1. Node stops heartbeating to the API server
2. After node-monitor-grace-period (default 40s), node is marked NotReady
3. Pods on the node are still running (kubelet is still alive)
4. The Pods are still counted in the DS status
5. After pod-eviction-timeout (default 5m), the API server force-deletes the Pods
6. The DS controller sees the missing Pod and creates a new one elsewhere
```

If the original node recovers within 5 minutes, its Pods are still there (the force-delete was a no-op). If the node is gone for longer, replacement Pods are scheduled on other nodes.

### `kubectl drain <node>`

Drain is a maintenance operation. It:

1. Cordons the node (adds the unschedulable taint)
2. Evicts all Pods that can be evicted (respecting PDBs)
3. **DaemonSet Pods ARE evicted by default**, unless they tolerate the unschedulable taint

The DS controller sees the evicted Pod and immediately tries to recreate it on the same node — but the cordoned node rejects it. So drain effectively moves DS Pods off the node. If the DS has a `minReadySeconds: 30` or uses a slow-starting image, this can leave a temporary gap in coverage on the drained node.

To keep a DS running during drain, add:

```yaml
tolerations:
- key: node.kubernetes.io/unschedulable
  operator: Exists
  effect: NoSchedule
```

This is appropriate for system-critical DS like CNI, kube-proxy replacements, and core security agents.

### Deleting the DaemonSet

```bash
kubectl delete ds <name>
```

This:

1. Marks the DS for deletion
2. Cascades: deletes all Pods owned by the DS
3. Removes the DS object from etcd
4. Pods are terminated per the normal Pod deletion flow (preStop, SIGTERM, grace period, SIGKILL)

There's no `kubectl delete` flag to "drain DS Pods first." If you need a graceful shutdown, use `kubectl rollout pause` + manual Pod deletion, or set a long `terminationGracePeriodSeconds` on the Pod template.

---

## 11. Operational Recipes

### Recipe 1: Node-exporter (the canonical DS)

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: monitoring
  labels:
    app: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      serviceAccountName: node-exporter
      hostNetwork: true
      hostPID: true
      nodeSelector:
        kubernetes.io/os: linux
      tolerations:
      - operator: Exists
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.7.0
        args:
        - --path.procfs=/host/proc
        - --path.sysfs=/host/sys
        - --path.rootfs=/host/root
        - --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)
        ports:
        - name: metrics
          containerPort: 9100
          hostPort: 9100
        resources:
          requests:
            cpu: 100m
            memory: 30Mi
          limits:
            cpu: 200m
            memory: 50Mi
        securityContext:
          runAsNonRoot: false     # node-exporter needs root for /proc, /sys
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
        - name: root
          mountPath: /host/root
          readOnly: true
      volumes:
      - name: proc
        hostPath: { path: /proc }
      - name: sys
        hostPath: { path: /sys }
      - name: root
        hostPath: { path: / }
```

### Recipe 2: Fluent Bit log shipper

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentbit
  namespace: logging
  labels:
    app: fluentbit
spec:
  selector:
    matchLabels:
      app: fluentbit
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: fluentbit
    spec:
      serviceAccountName: fluentbit
      tolerations:
      - operator: Exists
      containers:
      - name: fluentbit
        image: fluent/fluent-bit:3.0
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: fluentbit-config
          mountPath: /fluent-bit/etc/
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: fluentbit-config
        configMap:
          name: fluentbit-config
```

### Recipe 3: Calico CNI (production)

The Calico CNI runs as a DaemonSet. Excerpt of the key fields:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: calico-node
  namespace: calico-system
spec:
  selector:
    matchLabels:
      k8s-app: calico-node
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        k8s-app: calico-node
    spec:
      priorityClassName: system-node-critical
      hostNetwork: true
      tolerations:
      - effect: NoSchedule
        operator: Exists
      - key: CriticalAddonsOnly
        operator: Exists
      containers:
      - name: calico-node
        image: docker.io/calico/node:v3.27.0
        env:
        - name: DATASTORE_TYPE
          value: kubernetes
        - name: WAIT_FOR_DATASTORE
          value: "true"
        securityContext:
          privileged: true        # CNI needs to manipulate iptables, routes
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
```

Note `privileged: true` — this is the exception, not the rule. The CNI Pod needs raw network access to set up routing on the node.

### Recipe 4: Exclude a node from all DaemonSets

```bash
kubectl taint nodes <node-name> node.kubernetes.io/exclude-daemonsets=true:NoSchedule
```

Now no DS runs on this node unless the Pod explicitly tolerates the taint.

### Recipe 5: Roll out a DS change to one node at a time

```bash
# Update the DS image
kubectl set image ds/fluentbit fluentbit=fluent/fluent-bit:3.1

# Watch the rollout
kubectl rollout status ds/fluentbit

# If you need to pause and check
kubectl rollout pause ds/fluentbit
kubectl rollout resume ds/fluentbit
```

### Recipe 6: Get the list of nodes a DS is running on

```bash
# All DS Pods and their nodes
kubectl get pods -l app=node-exporter -A -o wide

# Just the node names
kubectl get pods -l app=node-exporter -A -o jsonpath='{.items[*].spec.nodeName}'
```

---

## 12. Troubleshooting

### Symptom: DS is supposed to be on N nodes but only M are running

**Check 1: Are some nodes cordoned or tainted?**

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

If a node has `node.kubernetes.io/unschedulable:NoSchedule` and your DS doesn't tolerate it, that node won't get a Pod.

**Check 2: Are there unschedulable nodes due to other taints?**

Look for any taint on a missing node and check if the DS template has a matching toleration.

**Check 3: Is the DS selector too restrictive?**

```bash
kubectl get ds <name> -o jsonpath='{.spec.selector}'
kubectl get ds <name> -o jsonpath='{.spec.template.metadata.labels}'
```

If the template's labels don't include the selector, the API server should have rejected the DS. If they do include the selector but you still see fewer Pods, the issue is on the node side.

**Check 4: Are the Pods in a different namespace?**

DaemonSets are namespace-scoped. If you created a DS in `monitoring` but expected Pods in `kube-system`, they won't be there.

### Symptom: DS Pods are Pending

```bash
kubectl get pods -l app=node-exporter
# Shows 0/N Pending
kubectl describe pod <name>
```

Common causes:

- **Image pull error** — bad image tag, registry auth issue
- **Resource pressure** — node has no room for the requests
- **Volume mount failure** — hostPath doesn't exist, PVC can't bind
- **Taint without toleration** — the node is tainted, the Pod doesn't tolerate

### Symptom: DS Pods are CrashLoopBackOff

The Pod is starting, crashing, and the kubelet is backing off. Check the logs:

```bash
kubectl logs <pod> --previous
```

Common causes:

- Bad config in a mounted ConfigMap
- Missing service account token
- Permission errors on a hostPath
- The agent requires capabilities it doesn't have (e.g., needs `NET_ADMIN`)

### Symptom: `numberMisscheduled > 0`

`numberMisscheduled` is the count of DS Pods running on nodes that **no longer match** the DS criteria. This usually means:

- You changed the DS's `nodeSelector` to be more restrictive
- A node was relabeled and no longer matches

```bash
kubectl get pods -l app=node-exporter -A -o wide
# Check which nodes they're on
```

These Pods are still running but are not what the DS controller wants. They will be deleted on the next reconciliation cycle (the controller deletes them as "extra").

### Symptom: Rolling update stuck

The DS is mid-update and some Pods are old, some are new. The rollout isn't completing.

**Check 1: Are the new Pods failing to start?**

```bash
kubectl get pods -l app=node-exporter -A
# Look for CrashLoopBackOff, ImagePullBackOff
```

**Check 2: Is `maxUnavailable: 0` blocking?**

If you set `maxUnavailable: 0` and the new Pod is failing to start, the rollout is stuck. Either:

- Fix the new Pod's failure
- Bump `maxUnavailable` to allow the old Pod to be killed

**Check 3: Is there a PDB blocking?**

```bash
kubectl get pdb -A
```

PDBs don't typically apply to DaemonSets, but if you've set one for the DS Pods' labels, it could slow the rollout.

### Symptom: Memory pressure from DS

`kubectl top nodes` shows high memory usage. Investigate the DS Pods:

```bash
kubectl top pods -A --sort-by=memory | head
```

If a DS Pod is using more than its `requests`, the kubelet might evict it under pressure. Consider:

- Raising the `requests` and `limits`
- Profiling the agent to reduce memory usage
- Using a different agent (e.g., node-exporter is lighter than Datadog agent)

### Symptom: DS Pods survive node drain

You ran `kubectl drain <node>` but the DS Pods are still there. This means the DS tolerates the unschedulable taint (or the drain didn't evict it for another reason). To make the DS evictable, remove the toleration:

```bash
kubectl edit ds <name>
# Remove the node.kubernetes.io/unschedulable toleration
```

Or, in the original manifest, omit the toleration.

---

## 13. Gotchas and Common Mistakes

### Selector and template gotchas

- **Template labels must intersect with the selector.** If they don't, the API server rejects the DS.
- **Two DSs with overlapping selectors is a bug.** They'll fight over the same Pods.
- **Adopting Pods**: an existing Pod with the matching label is adopted by the DS. Be careful with selector overlap.

### Node selection gotchas

- **`nodeSelector` is exact match.** A node must have all listed labels to match.
- **Control-plane taints are not auto-tolerated.** A DS that wants to run on control-plane nodes must explicitly tolerate the taint.
- **`kubectl cordon` blocks DS Pods** that don't tolerate the unschedulable taint. This is correct behavior but surprises people.
- **`kubectl drain` evicts DS Pods** by default. They get recreated on other nodes, but there's a brief gap. Plan for it.

### Update strategy gotchas

- **`maxSurge` requires a CNI that supports additional IPs.** If yours doesn't, omit it.
- **`maxUnavailable: 0` is fragile.** If a new Pod fails to start, the rollout stalls. Prefer `maxUnavailable: 1`.
- **`OnDelete` requires manual orchestration.** You must `kubectl delete pod` each node's Pod yourself. Easy to forget a node.
- **No automatic rollback on failure.** The DS controller doesn't detect "the new image is broken" — it just keeps trying to start the new Pod. Use readiness probes to gate.

### Host access gotchas

- **`hostPID: true` is a major security risk.** A compromised Pod can see all host processes. Use only for trusted, security-reviewed agents.
- **`hostNetwork: true` bypasses NetworkPolicy.** The Pod's traffic is not filtered.
- **`hostPath: /` is dangerous.** It mounts the node's entire root filesystem. Use the narrowest path possible.
- **`privileged: true`** is needed for CNI but should be avoided for general DS. Justify it explicitly in the manifest comment.

### Resource gotchas

- **DS resources are summed cluster-wide.** A "small" DS can reserve gigabytes of memory across a large cluster.
- **No requests = BestEffort QoS = first to be evicted.** Always set at least `requests`.
- **CPU limits throttle the agent.** A log shipper throttled to 100m CPU may not be able to keep up under load. Set realistic limits.

### Lifecycle gotchas

- **DS Pods are not restarted when the node dies** — the controller creates a new Pod on a different node, with a new UID.
- **DS Pods do count toward the cluster's pod CIDR budget.** A node with 254 IPs can host at most ~250 Pods (with CNI overhead). If you have 20 DSs, you've used 20 of that budget on every node.
- **DS Pods do not respect `priorityClassName: system-cluster-critical` by default.** Use `system-node-critical` for system DS.

### The "DS is for everything" anti-pattern

A common mistake is using a DS for workloads that don't need to be on every node. Example:

```yaml
# ❌ Anti-pattern: an "API gateway" DS
# The API gateway doesn't need to be on every node
# It needs a fixed count with load balancing
spec:
  kind: DaemonSet
  # ... this is wrong, use a Deployment
```

Rule: if the answer to "why per-node?" is "well, it's not really, but it's convenient," use a Deployment with the appropriate scheduler rules.

---

## 14. Related Notes

| Topic | Note |
|---|---|
| Pods (what a DS manages) | [[Kubernetes/concepts/L03-workloads/01-pods\|01 — Pods]] |
| Deployment (fixed-count workloads) | [[Kubernetes/concepts/L03-workloads/03-deployments\|03 — Deployments]] |
| StatefulSet (stable network IDs) | [[Kubernetes/concepts/L03-workloads/04-statefulsets\|04 — StatefulSets]] |
| Job (run-to-completion) | [[Kubernetes/concepts/L03-workloads/06-job\|06 — Job]] |
| CronJob (scheduled jobs) | [[Kubernetes/concepts/L03-workloads/07-cronjob\|07 — CronJob]] |
| Taints and tolerations | [[Kubernetes/concepts/L06-scheduling-scaling\|L06 — Scheduling and Scaling]] |
| Resource requests and limits | [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|L06 — Resource Requests and Limits]] |
| Security context | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context\|L07 — Security Context]] |
| Host network (CNI, kube-proxy) | [[Kubernetes/concepts/L04-services-networking/01-networking\|L04 — Networking]] |
| Static Pods (kubelet-managed) | [[Kubernetes/concepts/L03-workloads/11-static-pods\|11 — Static Pods]] |

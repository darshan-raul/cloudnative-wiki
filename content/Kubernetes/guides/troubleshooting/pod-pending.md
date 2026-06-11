---
title: Pod Pending
tags:
  - Kubernetes
  - Troubleshooting
  - Scheduling
---

A pod that's stuck in `Pending` hasn't even started yet. The scheduler hasn't placed it on a node, or it can't be placed. This is **scheduling**, not container-level issues.

## Symptoms

```bash
$ kubectl get pods
NAME          READY   STATUS    RESTARTS   AGE
web-1         0/1     Pending   0          10m
api-2         0/1     Pending   0          5m
worker-3      0/1     Pending   0          30s
```

`RESTARTS = 0` is the giveaway — the container has never started. Compare to CrashLoopBackOff (container started and crashed) or ImagePullBackOff (image is the problem).

## The 30-second diagnosis

```bash
# 1. describe — events will tell you why
kubectl describe pod web-1 | tail -30

# 2. scheduler events
kubectl get events --field-selector involvedObject.name=web-1,reason=FailedScheduling

# 3. node list — are there any eligible nodes?
kubectl get nodes

# 4. node capacity vs pod requirements
kubectl describe nodes | grep -A 5 "Allocated resources"

# 5. PVCs referenced by the pod
kubectl get pvc -n my-ns
```

## The taxonomy of Pending causes

```
┌──────────────────────────────────────────────────────────────┐
│                       Pod Pending                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Insufficient resources   (CPU, memory, ephemeral-storage)│
│  2. Node selectors / taints  (no node matches affinity)      │
│  3. PVC not bound            (waiting on storage provision)  │
│  4. Pod scheduling gates      (newer feature, gate not met)  │
│  5. Topology spread           (SpreadConstraint unsatisfiable)│
│  6. Scheduler queue jam       (one bad pod blocks many)      │
│  7. Runtime class missing     (no node has the runtime)      │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

Each is a different category with a different fix.

## 1. Insufficient resources

The most common. The pod asks for more CPU/memory/ephemeral-storage than any node has free.

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -10
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  10m   default-scheduler  0/3 nodes are available:
    3 Insufficient cpu, 3 Insufficient memory.
```

The message is literal — every node has been checked, none has the resources.

**Diagnosis:**

```bash
# 1. What does the pod request?
kubectl get pod web-1 -o jsonpath='{.spec.containers[0].resources}' | jq .

# 2. What's free on the nodes?
kubectl describe nodes | grep -E "Name:|Allocated resources:|Capacity:|^\s+cpu|memory" | head -40

# 3. Total cluster capacity
kubectl get nodes -o json | jq '[.items[] | {
  name: .metadata.name,
  cpu_allocatable: .status.allocatable.cpu,
  mem_allocatable: .status.allocatable.memory
}]'

# 4. Top consumers (find the heavy pod)
kubectl top pods -A --sort-by=memory | head
```

**Common sub-causes:**

1. **Pod requests are too high.** Someone set `requests: { cpu: 64, memory: 256Gi }` and the cluster doesn't have that much.
   ```yaml
   resources:
     requests:
       cpu: "64"          # 64 cores
       memory: "256Gi"    # 256 GB
   ```
   Fix: lower the requests, or add nodes.

2. **Node capacity is too low for the workload.** Small nodes (4 CPU, 8GB) running pods that ask for 2 CPU / 4GB.
   Fix: larger nodes, more nodes, or smaller pod requests.

3. **No headroom for system pods.** kube-proxy, CNI, kubelet, OS daemons all consume resources. If you set `capacity = allocatable - system-reserved`, requests are calculated against `allocatable`. But if you've asked for `100% of allocatable`, there's no room for the actual workload.
   ```bash
   # check what the kubelet reserves
   kubectl describe node node-1 | grep -A 5 "System Info"
   # and compare to:
   kubectl describe node node-1 | grep "Allocated resources"
   ```

4. **Ephemeral storage full.** The pod's working directory, container layers, logs all use ephemeral storage. If `/var/lib/kubelet` is full on all nodes, pods can't schedule.
   ```bash
   $ kubectl describe pod web-1 | tail -5
   Warning  FailedScheduling  5m  default-scheduler  0/3 nodes are available:
     3 Insufficient ephemeral-storage.
   ```
   Fix: clean up `/var/lib/kubelet`, add disk, or lower `ephemeral-storage` requests.

5. **Hugepages.** If your pod requests hugepages and the nodes don't have them, pod can't schedule.
   ```yaml
   resources:
     requests:
       hugepages-1Gi: 1Gi
   ```
   Fix: configure hugepages on the node, or remove the request.

## 2. Node selectors, affinity, taints

The pod's selectors don't match any node, or every matching node has a taint the pod doesn't tolerate.

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -10
Warning  FailedScheduling  5m  default-scheduler  0/3 nodes are available:
  3 node(s) didn't match Pod's node affinity/selector.
```

```bash
$ kubectl describe pod web-1 | tail -10
Warning  FailedScheduling  5m  default-scheduler  0/3 nodes are available:
  3 node(s) had taints that the pod didn't tolerate.
```

**Diagnosis:**

```bash
# 1. What selectors / affinity does the pod have?
kubectl get pod web-1 -o jsonpath='{.spec}' | jq '{nodeSelector, affinity, tolerations}'

# 2. What labels do nodes have?
kubectl get nodes --show-labels

# 3. What taints do nodes have?
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, taints: .spec.taints}'

# 4. Does any node match?
kubectl get nodes -l workload=batch    # if pod has nodeSelector: { workload: batch }
```

**Common sub-causes:**

1. **Typo in nodeSelector.**
   ```yaml
   spec:
     nodeSelector:
       workload: gpu    # but nodes have workload: GPU
   ```
   Fix: spell it right.

2. **Node has taint, pod has no toleration.** Most managed clusters taint control plane nodes.
   ```bash
   $ kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, taints: .spec.taints}'
   {
     "name": "control-plane-1",
     "taints": [{"key": "node-role.kubernetes.io/control-plane", "effect": "NoSchedule"}]
   }
   ```
   Pods need to tolerate this taint, or they won't schedule on the control plane.

3. **Required affinity is impossible.** Pod requires `topology.kubernetes.io/zone in (us-east-1a) AND (us-east-1c)`. No single node is in both.
   ```yaml
   affinity:
     nodeAffinity:
       requiredDuringSchedulingIgnoredDuringExecution:
         nodeSelectorTerms:
         - matchExpressions:
           - key: topology.kubernetes.io/zone
             operator: In
             values: ["us-east-1a", "us-east-1c"]   # impossible
   ```
   Fix: review the affinity, make it possible.

4. **DaemonSet pods.** If a node has a taint, even DaemonSet pods need tolerations. Forgetting this is a common gotcha.

5. **nodeName pinning.** If `spec.nodeName: node-1` and node-1 is gone, the pod stays pending.
   ```bash
   $ kubectl get pod web-1 -o jsonpath='{.spec.nodeName}'
   node-1
   $ kubectl get node node-1
   NAME     STATUS        ROLES                  AGE
   node-1   NotReady      <none>                 5m
   ```
   Fix: remove `nodeName` or fix the node.

## 3. PVC not bound

The pod asks for a PVC that isn't bound. Usually because the PVC is `Pending` (waiting for the storage provisioner).

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -10
Warning  FailedScheduling  5m  default-scheduler
  persistentvolumeclaim "data" not found
```

or

```bash
Warning  FailedScheduling  5m  default-scheduler
  0/3 nodes are available: 3 persistentvolumeclaim "data" bound to unexpected node.
```

or

```bash
Warning  FailedScheduling  5m  default-scheduler
  0/3 nodes are available: 3 node(s) didn't find available persistent volumes
    to bind.
```

**Diagnosis:**

```bash
# 1. PVC status
kubectl get pvc -n my-ns
# NAME    STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# data    Pending                                      gp3            5m

# 2. Why is the PVC pending?
kubectl describe pvc data -n my-ns | tail -10
# Events:
#   Warning  ProvisioningFailed  45s  external-provisioner
#     failed to provision volume: AccessDenied: ...

# 3. StorageClass exists?
kubectl get sc

# 4. Provisioner is running?
kubectl get pods -n kube-system -l app=csi-aws-ebs-csi-driver
```

**Common sub-causes:**

1. **StorageClass doesn't exist.** `spec.storageClassName: gp3-encrypted` but the cluster has no such SC.
   Fix: create the SC, or use one that exists.

2. **StorageClass provisioner is broken.** CSI driver pod is down, IAM permissions missing, zone out of capacity.
   ```bash
   $ kubectl logs -n kube-system -l app=ebs-csi-controller
   failed to create volume: ... AccessDenied
   ```
   Fix: fix the IAM policy, restart the provisioner, free up quota.

3. **No available PV (static provisioning).** PVC asks for 100Gi, only 50Gi PVs exist.
   ```bash
   kubectl get pv | grep Available
   ```
   Fix: create more PVs, or switch to dynamic provisioning.

4. **Access mode mismatch.** PVC asks for `ReadWriteMany`, but the SC only provisions `ReadWriteOnce`.
   ```yaml
   spec:
     accessModes: [ReadWriteMany]
     storageClassName: gp3   # gp3 is RWO
   ```
   Fix: use a SC that supports RWX (e.g., EFS, NFS, CephFS).

5. **Volume binding mode = WaitForFirstConsumer.** The PVC won't provision until a pod using it is scheduled. If the pod can't be scheduled, the PVC stays pending.
   ```yaml
   apiVersion: storage.k8s.io/v1
   kind: StorageClass
   metadata:
     name: gp3
   provisioner: ebs.csi.aws.com
   volumeBindingMode: WaitForFirstConsumer
   ```
   This is a chicken-and-egg situation. Fix by making sure the pod can schedule.

## 4. Pod scheduling gates

A newer feature (k8s 1.27+, GA in 1.30+). Pods can be **gated** — the scheduler waits for a gate to be removed before scheduling.

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -10
Status:
  ...
  Pod Scheduling Gates:
    <gate-name>: <reason>
```

```bash
$ kubectl get pod web-1 -o json | jq '.spec.schedulingGates'
[
  {"name": "gated-by-foo"}
]
```

**Diagnosis:**

```bash
# 1. What gates are set?
kubectl get pod web-1 -o jsonpath='{.spec.schedulingGates}' | jq .

# 2. Why was the gate set?
#    (this is application logic — usually set by an operator that needs the
#    pod to wait for some external event, like a config to be ready)
```

**Common sub-causes:**

1. **Gates set by an admission webhook.** Some operators (DRA, leader-election) set gates.
   Fix: wait for the operator to clear the gate, or fix the operator.

2. **Stuck gate from a bug.** Operator that sets the gate never clears it.
   Fix: file a bug. Workaround: `kubectl patch pod web-1 --type=json -p '[{"op":"remove","path":"/spec/schedulingGates"}]'`.

## 5. Topology spread constraints

You asked for pods spread across zones, but the cluster doesn't have enough zones (or nodes) to satisfy the spread.

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -10
Warning  FailedScheduling  5m  default-scheduler
  0/5 nodes are available: 2 node(s) didn't match pod topology spread constraints,
  3 node(s) had taints that the pod didn't tolerate.
```

```bash
$ kubectl describe pod web-1 | tail -10
Warning  FailedScheduling  5m  default-scheduler
  0/3 nodes are available: 3 node(s) didn't match pod topology spread constraints.
```

**Diagnosis:**

```bash
# 1. Spread constraints
kubectl get pod web-1 -o jsonpath='{.spec.topologySpreadConstraints}' | jq .

# 2. Where are the existing replicas?
kubectl get pods -l app=web -o wide
# are they all in one zone? (then you have no spread)

# 3. What zones are nodes in?
kubectl get nodes -o json | jq '[.items[] |
  {name: .metadata.name, zone: .metadata.labels["topology.kubernetes.io/zone"]}]'
```

**Common sub-causes:**

1. **`maxSkew: 1` with `whenUnsatisfiable: DoNotSchedule`.** Even one node imbalance fails the constraint.
   ```yaml
   topologySpreadConstraints:
   - maxSkew: 1
     topologyKey: topology.kubernetes.io/zone
     whenUnsatisfiable: DoNotSchedule
   ```
   Fix: switch to `ScheduleAnyway` to allow the imbalance, or add nodes to balance the spread.

2. **All existing pods in one zone.** New pods can't spread if every existing one is in the same zone and `maxSkew: 0` (with DoNotSchedule).
   ```bash
   $ kubectl get pods -l app=web -o jsonpath='{.items[*].spec.nodeName}'
   node-1 node-2 node-3
   $ kubectl get nodes -o jsonpath='{.items[*].metadata.labels.topology\.kubernetes\.io/zone}'
   us-east-1a us-east-1a us-east-1a   # all same zone
   ```
   Fix: add nodes in other zones, or relax the constraint.

## 6. Scheduler queue jam

The scheduler has a queue. Pending pods are processed in order. If a pod at the front of the queue can't schedule (e.g., it's looking for a non-existent node), it can **block the queue**.

In large clusters, this rarely happens because of preemption and backoff, but in smaller clusters, a single misconfigured pod can delay many others.

**Signatures:**

```bash
# Many pods pending, all with the same age
$ kubectl get pods -A | grep Pending | head
ns1    web-1     0/1   Pending   0   30m
ns1    web-2     0/1   Pending   0   30m
ns1    web-3     0/1   Pending   0   30m
```

**Diagnosis:**

```bash
# 1. Pending pod count by age
kubectl get pods -A --no-headers | awk '$3=="Pending"{print $6, $2}' | sort -n | tail

# 2. Scheduler logs
kubectl logs -n kube-system -l component=kube-scheduler --tail=100

# 3. Specific pod's events
kubectl describe pod <oldest-pending-pod> | tail
```

**Common sub-causes:**

1. **Head-of-line blocking.** A pod that can't be scheduled is at the front of the queue. Subsequent pods wait.
   Fix: fix the head pod, or set pod priority so others skip the queue.

2. **Scheduler crashloop.** The scheduler is restarting, queue doesn't drain.
   ```bash
   $ kubectl get pods -n kube-system -l component=kube-scheduler
   NAME                              READY   STATUS             RESTARTS
   kube-scheduler-control-plane      0/1     CrashLoopBackOff   5
   ```
   Fix: see [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] for the scheduler.

## 7. Runtime class missing

The pod specifies a `runtimeClassName` (e.g., `gvisor`, `kata`, `wasm`) and no node has the corresponding runtime configured.

**Signatures:**

```bash
$ kubectl describe pod web-1 | tail -10
Warning  FailedScheduling  5m  default-scheduler
  0/3 nodes are available: 3 node(s) didn't match Pod's runtimeClass.
```

```bash
$ kubectl get runtimeclass
# empty
```

**Diagnosis:**

```bash
# 1. RuntimeClass on the pod
kubectl get pod web-1 -o jsonpath='{.spec.runtimeClassName}'

# 2. Available RuntimeClasses
kubectl get runtimeclass

# 3. CRI runtime on the node
kubectl get nodes -o json | jq '.items[].status.nodeInfo.containerRuntimeVersion'
```

**Common sub-causes:**

1. **RuntimeClass doesn't exist.** `runtimeClassName: gvisor` but no `gvisor` RuntimeClass in the cluster.
   Fix: install the RuntimeClass.

2. **No node has the runtime installed.** `gvisor` RuntimeClass exists, but the actual runsc binary isn't on any node.
   Fix: install the runtime on the node.

## The fix menu

For each cause, the typical fix:

| Cause | Fix |
|-------|-----|
| Insufficient CPU/memory | Lower requests, add nodes, scale cluster |
| Node selectors / affinity | Check labels, fix selectors, add tolerations |
| PVC not bound | Create the PVC, fix the storage class, fix provisioner |
| Topology spread | Add nodes in the missing topology, relax constraint |
| Runtime class | Install the runtime, create the RuntimeClass |
| Scheduling gates | Wait for the operator, or remove the gate |
| Scheduler jam | Fix the head pod, restart scheduler |

## The fast triage script

```bash
#!/bin/bash
# triage-pending.sh - find why a pod is pending
POD=${1:-$(kubectl get pods -A --no-headers | awk '$3=="Pending"' | head -1 | awk '{print $2, $1}')}

if [ -z "$POD" ]; then
  echo "No pending pods"
  exit 0
fi

read -r NAME NS <<<"$POD"
echo "=== Triage for $NS/$NAME ==="

echo ""
echo "1. Pod spec (resources, selectors, affinity)"
kubectl get pod -n "$NS" "$NAME" -o jsonpath='{.spec}' | \
  jq '{nodeName, nodeSelector, affinity, tolerations, runtimeClassName,
       schedulingGates, topologySpreadConstraints,
       resources: .containers[0].resources}'

echo ""
echo "2. Recent events"
kubectl get events -n "$NS" --field-selector involvedObject.name="$NAME" \
  --sort-by='.lastTimestamp' | tail -10

echo ""
echo "3. PVCs (if any)"
kubectl get pvc -n "$NS"

echo ""
echo "4. Node status"
kubectl get nodes --no-headers

echo ""
echo "5. Cluster resource pressure"
kubectl describe nodes | grep -A 5 "Allocated resources" | head -20
```

Save this as `triage-pending.sh`, run it, get a comprehensive view.

## When to use a PriorityClass

If you have many pending pods and need to enforce ordering, use PriorityClasses:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000
globalDefault: false
description: "Production traffic — preempt lower-priority pods"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: -100
globalDefault: true
description: "Batch jobs — get scheduled last"
```

The scheduler will **preempt** (evict) low-priority pods to make room for high-priority ones when the cluster is full.

## Common gotchas

* **"0/N nodes are available" with N = number of nodes** — read the message. It tells you *why*. Every reason is listed.
* **Pending pods are not failures** — they're waiting. The kubelet doesn't restart them. The controller might (e.g., Deployment's controller will eventually create a new pod if one is stuck for too long, depending on `progressDeadlineSeconds`).
* **Progress deadline.** Deployments have a `progressDeadlineSeconds` (default 600s). If a Deployment is stuck pending past this, the controller marks it as `ProgressDeadlineExceeded`.
  ```bash
  $ kubectl get deploy web
  NAME   READY   UP-TO-DATE   AVAILABLE   AGE
  web    0/3     0            0           12m
  $ kubectl describe deploy web | tail
  Conditions:
    Type: ProgressDeadlineExceeded
  ```
* **`kubectl describe` is the only place you'll see the reason.** `kubectl get pods` shows the status; `describe` shows the events. Always `describe`.
* **Re-applying a manifest can re-trigger scheduling** — but only if the scheduler decides it's a new pod (different labels, different nodeName, etc.).
* **"Pending" doesn't always mean "won't schedule"** — the scheduler might be about to schedule it. Run `kubectl get pods -w` to watch.
* **Node autoscaling takes minutes.** If you're using cluster-autoscaler or Karpenter, scaling out to satisfy pending pods isn't instant. Pending pods are the trigger; you have to wait for the new node to come up.
* **A pod in `Pending` doesn't consume resources on any node** — but the scheduler still has it in memory. If you have tens of thousands of pending pods, scheduler performance degrades.
* **Don't set `nodeName` in production specs.** It pins the pod to a specific node. If the node is down, the pod stays pending forever. Use nodeSelector + taints/tolerations, or topology spread, instead.

## See also

* [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] — when the container is the problem
* [[Kubernetes/guides/troubleshooting/node-not-ready|node-not-ready]] — when the node is the problem
* [[Kubernetes/guides/troubleshooting/pvc-stuck|pvc-stuck]] — when storage is the problem
* [[Kubernetes/concepts/L06-scheduling-scaling|scheduling & scaling]] — how scheduling works

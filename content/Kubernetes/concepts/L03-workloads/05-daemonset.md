# DaemonSet

*"https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/"*

A DaemonSet ensures that **one Pod runs on every (selected) node** (or as many as fit). When you add a node, the DS Pod is scheduled onto it. When you remove a node, the Pod is garbage-collected.

## When you'd use one

* **Node-level log shippers** — Fluent Bit, Filebeat, Promtail (one per node to read node-local logs)
* **Node-level metrics agents** — node-exporter, Datadog agent
* **Cluster networking components** — CNI agents (Calico, Cilium), kube-proxy
* **Storage daemons** — CSI drivers that need to run on every node (Glusterd, Ceph)
* **Anything that needs to be on every machine by definition**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentbit
spec:
  selector:
    matchLabels:
      app: fluentbit
  template:
    metadata:
      labels:
        app: fluentbit
    spec:
      containers:
      - name: fluentbit
        image: fluent/fluent-bit:2.2
        volumeMounts:
        - name: varlog
          mountPath: /var/log
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
```

## Update strategy

* **RollingUpdate** (default) — old Pods are killed and replaced, one at a time (or `maxUnavailable` at a time). Use `maxSurge` only when supported (k8s 1.22+ for DS).
* **OnDelete** — old Pods are kept until you manually delete them. Use when you need precise control (e.g. GPU drivers).

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
```

## Node selection

By default a DS runs on **every node**. To restrict it:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/worker: ""     # only workers
      tolerations:                              # tolerate control-plane taints
      - key: node-role.kubernetes.io/control-plane
        effect: NoSchedule
```

Or use `nodeAffinity` for richer rules. A Pod can be excluded from a DS by setting the **taint** `node.kubernetes.io/exclude-daemonsets` on the node.

## Gotchas

* **DS Pods are scheduled by the DS controller, not the normal scheduler** — they bypass `nodeSelector` and other constraints of normal pods in the same template unless you add them back. (The DS controller **does** respect taints/tolerations in the template.)
* **A node with the `unschedulable` taint still gets DS Pods** unless you also tolerate the right taints.
* **DS Pods count toward your resource budget** — if you have 100 nodes and a DS with `requests.cpu: 500m`, you've already burned 50 cores.
* **DS doesn't run on a node until the node is ready** — a NotReady node is skipped.

## DaemonSet vs Deployment

| | DaemonSet | Deployment |
|---|---|---|
| Replicas | One per selected node | Fixed count (`replicas`) |
| Use case | Node-level agents | Stateless apps |
| Spreads by | Node membership | Scheduler decisions |

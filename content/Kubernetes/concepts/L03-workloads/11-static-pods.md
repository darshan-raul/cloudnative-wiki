# Static Pods

*"https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/"*

A static Pod is a Pod **managed directly by the kubelet** on a specific node, **not by the API server**. The kubelet watches a directory (or a remote URL, or an HTTP endpoint) for Pod manifest files and runs each one as a Pod on its node.

## The basic idea

Instead of the usual flow (you `kubectl apply` → apiserver → etcd → scheduler → kubelet), the kubelet **reads files from a local directory and starts the Pods directly**, without any API server involvement.

```bash
# configure the kubelet to read from /etc/k8s/manifests
# (in /var/lib/kubelet/config.yaml)
staticPodPath: /etc/k8s/manifests

# or via kubelet flag
--pod-manifest-path=/etc/k8s/manifests
```

Drop a Pod manifest in that directory:

```yaml
# /etc/k8s/manifests/web.yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels:
    app: web
spec:
  containers:
  - name: nginx
    image: nginx:1.27
```

The kubelet on that node picks it up and starts the Pod. No scheduler, no API server, no etcd — just the kubelet and the container runtime.

## How the kubelet manages them

The kubelet has a goroutine that:

```
loop {
  files = read(staticPodPath)
  for each file:
    if content changed: reconcile
  for each running static Pod:
    if file is gone: delete the Pod
}
```

When you change a file, the kubelet **reconciles**: deletes the old Pod, starts a new one with the new spec. There is no rolling update, no graceful drain, no in-place update — same as a bare Pod, but managed by the kubelet.

If you delete the file, the kubelet **stops the Pod** (sends SIGTERM, waits `terminationGracePeriodSeconds`, then SIGKILL).

## Mirror Pods

The kubelet also creates a **mirror Pod** on the API server for each static Pod. This lets `kubectl get pods` see them, but they have an annotation that marks them as mirrors:

```bash
kubectl get pods -A
# NAMESPACE   NAME    READY   STATUS    RESTARTS   AGE
# kube-system web-abcde   1/1     Running   0          5m

kubectl get pod web-abcde -n kube-system -o yaml | grep -A 5 annotations
# annotations:
#   kubelet.kubernetes.io/observed-generation: "1"
#   kubernetes.io/created-by: ...  # mirror Pod identity
#   kubernetes.io/config.source: file
#   ...
```

The mirror Pod is **read-only** from the API server's perspective. You can't `kubectl edit` it or `kubectl delete` it. Changes only happen by editing the file on the node.

If the API server is down, the static Pods keep running. **The mirror is a courtesy, not a requirement.**

## Why static Pods exist

### 1. The chicken-and-egg of the control plane

The control plane itself is a set of Pods (etcd, kube-apiserver, kube-controller-manager, kube-scheduler). Those Pods need to run before the API server is up. Static Pods are how this works on kubeadm clusters — the apiserver Pod is a static Pod on the first control-plane node, and **that node is the only one that needs to be up for the apiserver to start**.

```bash
# on a kubeadm control-plane node
ls /etc/kubernetes/manifests/
# etcd.yaml
# kube-apiserver.yaml
# kube-controller-manager.yaml
# kube-scheduler.yaml
```

Those four YAML files are static Pods. They run on this node, regardless of the API server's state.

### 2. Node-level agents

Sometimes you want a Pod to run on a specific node and only that node, with no possibility of rescheduling elsewhere. Static Pods guarantee this.

Examples:

* A log shipper that must run on every node
* A node-specific monitoring agent
* A debug tool that should be present but only on a particular node

You'd use a DaemonSet for most of these, but static Pods guarantee the Pod is on the node **even if the API server is unavailable**. In some edge cases, that matters.

### 3. Bootstrap of self-managed clusters

Before the API server exists, you need *something* to run Pods. Static Pods are the only way to start a cluster from scratch without an API server. `kubeadm` uses them for this.

## Static Pods in practice

### How kubeadm uses them

```bash
# on a kubeadm control-plane node
ls /etc/kubernetes/manifests/
# etcd.yaml
# kube-apiserver.yaml
# kube-controller-manager.yaml
# kube-scheduler.yaml
```

The kubelet on this node has `staticPodPath: /etc/kubernetes/manifests` configured. It runs these four Pods.

To upgrade the control plane, you edit the manifest file:

```bash
sudo vim /etc/kubernetes/manifests/kube-apiserver.yaml
# change the image tag from v1.29.0 to v1.30.0
# save the file
# kubelet sees the change, deletes the old Pod, starts a new one
# the apiserver restarts with the new version
```

This is the **only** way to upgrade the control plane on a kubeadm cluster.

### Webhook delivery

Instead of files, the kubelet can be configured to **poll a URL** for manifests:

```yaml
# in /var/lib/kubelet/config.yaml
staticPodURL: https://my-server/manifests/
```

The kubelet fetches the URL periodically and runs whatever manifests it returns. Useful for:

* **Air-gapped clusters** — central server pushes Pod manifests
* **Multi-node coordination** — a third-party system manages which Pods run on which nodes
* **Cluster bootstrap** — a tool like `bootkube` or `talos` runs the control plane as static Pods via URL

### HTTP endpoint

The kubelet also exposes the **running static Pods** as an HTTP endpoint:

```bash
# the kubelet's serving port (10250 by default)
curl -k --cert /etc/kubernetes/ssl/kubelet-client.crt \
     --key /etc/kubernetes/ssl/kubelet-client.key \
     https://<node-ip>:10250/pods
```

This is what some higher-level tools use to discover what static Pods are running on a node.

## Differences from regular Pods

| | Static Pod | Regular Pod |
|---|---|---|
| Managed by | kubelet | API server (via controller) |
| Stored in etcd | No (mirror is, but it can't be edited) | Yes |
| Scheduled | No (always on the kubelet's node) | Yes (by scheduler) |
| Rescheduled on node failure | No | Yes (if controller is around) |
| Survives API server outage | Yes | No |
| Editable via `kubectl edit` | No | Yes |
| Has a controller (Deployment, etc.) | No | Optional |
| Has a `controllerRef` | No | Usually yes |

## Gotchas

* **Static Pods can't be rescheduled.** If the node dies, the static Pod is gone. Use a DaemonSet if you want resilience.
* **Static Pods are bound to the kubelet that started them.** If you move the manifest to a different node's directory, the old node stops the Pod, the new node starts it. The Pod's UID changes.
* **Mirror Pods have the kubelet's node in their name.** A static Pod running on `node-1` shows up as `<name>-<node-1>` in `kubectl get`. The exact suffix is the node name.
* **You can't update a static Pod in place.** You change the file; the kubelet deletes the old Pod and starts a new one. Same UID loses its identity; any references (logs, metrics tagged by Pod UID) get a new UID.
* **Static Pods bypass the scheduler entirely.** They always run on the kubelet's node. If that node is full, the Pod will sit `Pending` or fail to start.
* **Static Pods are not subject to admission control.** They can have `privileged: true` and `hostNetwork: true` without admission review. The kubelet trusts whatever's in the file.
* **Mirror Pods can be GC'd.** The kubelet's `--node-lease-duration` and similar settings can affect mirror Pods. If you see mirror Pods disappearing, check the kubelet logs.
* **Updates require the kubelet to be running and the file to be readable.** If the kubelet is down, your changes don't take effect until it restarts.
* **Static Pods don't get the `kubernetes.io/created-for` annotation that regular Pods do.** They have `kubernetes.io/config.source` instead.
* **The kubelet's static Pod path needs read access for the kubelet's user.** If `/etc/kubernetes/manifests` is owned by root and the kubelet runs as a non-root user, you have a problem.

## When to use static Pods

* **You're running a kubeadm-based cluster** — already in use for the control plane
* **You're bootstrapping a cluster without an API server** — `talos`, `bootkube`, etc.
* **You need a Pod to survive API server outages** — niche but real
* **You need a Pod on a specific node and don't want anyone else to be able to delete it** — though RBAC can do this for normal Pods too

## When NOT to use static Pods

* **Anything that needs to be on every node** — use a DaemonSet
* **Anything that needs HA** — use a Deployment / StatefulSet
* **Anything that needs rolling updates** — use a Deployment
* **Most things** — for 99% of use cases, the API-server-driven model is the right answer

## How to make a Pod "static" in modern k8s

The modern equivalent of static Pods is the **kubelet's static Pod path** plus **control plane Pods as static Pods**. Most clusters use this via `kubeadm`.

For non-control-plane workloads, **don't use static Pods**. Use a DaemonSet (for node-level agents) or a Deployment (for everything else).

## See also

* [[Kubernetes/concepts/L01-architecture/01-setting-up-cluster|Setting up a Cluster]] — kubeadm uses static Pods for the control plane
* [[Kubernetes/concepts/L01-architecture/06-what-happens-when|What Happens When…]] — how regular Pods are created, for contrast
* [[Kubernetes/concepts/L09-advanced/09-pause-container|Pause Container]] — every Pod, including static ones, has one

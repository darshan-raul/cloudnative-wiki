# Troubleshooting (L08 Overview)

*"https://kubernetes.io/docs/tasks/debug/"*

A high-level overview of the **troubleshooting flow** in Kubernetes. Use this as a quick reference for "where do I look when something is broken". The deeper notes are linked below.

## The first question

When something doesn't work, the first question is always:

> **Is the Pod actually running?**

Because:

* If the Pod is `Pending`, the problem is scheduling (resources, affinity, volumes, etc.)
* If the Pod is `ContainerCreating`, the problem is image pull / volume mount / secret mount
* If the Pod is `CrashLoopBackOff`, the problem is the app or its config
* If the Pod is `Running` but the app is broken, the problem is the app, the network, or the Service

Knowing which **phase** the Pod is in is half the diagnosis.

## The decision tree

```
Pod is Pending
  ├── Insufficient resources (CPU, memory)
  ├── Unschedulable taint (no Pod tolerates)
  ├── Affinity / anti-affinity can't be satisfied
  ├── NodeSelector doesn't match any node
  ├── PVC is Pending (storage provision failed)
  ├── RuntimeClass not available
  └── Scheduler can't keep up
Pod is ContainerCreating
  ├── Image pull error
  ├── Volume mount error
  ├── Secret / ConfigMap not found
  ├── Init container stuck
  └── CNI not ready
Pod is CrashLoopBackOff
  ├── App exits with error
  ├── App OOM-killed
  ├── Liveness probe kills the app
  ├── Config / secret missing
  └── Dependency not available
Pod is Running but not in Service endpoints
  ├── Readiness probe failing
  ├── Selector mismatch
  └── Port mismatch
Pod is Running, in Service, but requests fail
  ├── App returns 5xx
  ├── App returns 4xx (config issue)
  ├── NetworkPolicy blocking
  ├── DNS not resolving
  └── Service is in a different namespace
```

## The "kubectl describe" reflex

The single most useful command for troubleshooting:

```bash
kubectl describe pod <pod-name>
```

Output sections, in order:

1. **Name, Namespace, Node, Labels, Annotations** — basic metadata
2. **Status** — phase (Pending / Running / etc.) and conditions
3. **Conditions** — PodScheduled, Initialized, ContainersReady, Ready (each with True/False/Unknown)
4. **Containers** — image, state, ready, restart count, last state
5. **Volumes** — what's mounted, source
6. **Events** — at the bottom, chronological, often the only useful part

When asking for help with a Pod, paste the full `kubectl describe` output. It has everything needed to diagnose most issues.

## The "kubectl logs" reflex

The second most useful command:

```bash
# current container
kubectl logs <pod>

# all containers
kubectl logs <pod> --all-containers

# previous instance (if the container restarted)
kubectl logs <pod> --previous

# with timestamps
kubectl logs <pod> --timestamps

# follow
kubectl logs -f <pod>
```

The container's stdout/stderr is in here. **If the app doesn't write to stdout, you won't see anything.** That's an app problem, not a k8s problem — but common.

## The "kubectl get events" reflex

For cluster-wide issues, the events stream is invaluable:

```bash
# all events, sorted
kubectl get events -A --sort-by=.lastTimestamp

# events for a specific object
kubectl get events --field-selector involvedObject.name=<pod>

# only warnings
kubectl get events -A --field-selector type=Warning
```

Events have a **1-hour TTL** by default. If you need history, ship events to a log aggregator.

## The four useful commands

These four commands cover 90% of troubleshooting:

```bash
# what is it doing?
kubectl describe pod <pod>

# what is it saying?
kubectl logs <pod> --previous

# what does the cluster think?
kubectl get events --field-selector involvedObject.name=<pod>

# can I reach it?
kubectl exec <pod> -- curl -v <service>.<ns>:<port>
```

## When the problem is at the cluster level

```bash
# are the nodes OK?
kubectl get nodes
kubectl describe node <node>

# are the system Pods OK?
kubectl get pods -n kube-system

# is the API server responding?
kubectl get --raw='/healthz'

# is the CNI working?
kubectl get pods -n kube-system -l k8s-app=<cni>
```

For etcd health:

```bash
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

## The "I have no idea" checklist

When you have no clue, go through this list:

1. **Look at `kubectl describe pod <pod>`.** Read the whole output, especially Events.
2. **Look at `kubectl logs <pod> --previous`.** If it's crashlooping, the previous instance's logs are gold.
3. **Look at events for the namespace.** `kubectl get events -n <ns> --sort-by=.lastTimestamp`.
4. **Check the node.** `kubectl describe node <node>`. Look for MemoryPressure, DiskPressure, PIDPressure, NotReady.
5. **Check the system Pods.** `kubectl get pods -n kube-system`. If any are broken, the cluster is broken.
6. **Check the CNI.** `kubectl get pods -n kube-system -l k8s-app=<cni>`. If these are down, nothing has networking.
7. **Check DNS.** `kubectl run -it --rm debug --image=busybox -- nslookup kubernetes.default`. If this fails, CoreDNS is broken.
8. **Increase kubectl verbosity.** `kubectl -v=8 describe pod ...`. Shows the raw API calls — useful for authn/authz issues.

## The "kubectl debug" toolbox

Modern k8s has `kubectl debug`, which creates ephemeral debug containers:

```bash
# run a debug container in a Pod's namespace
kubectl debug -it <pod> --image=busybox --target=<container>

# create a copy of a Pod with a debug container
kubectl debug <pod> --image=ubuntu --copy-to=<new-pod> --share-processes

# debug a node
kubectl debug node/<node> -it --image=ubuntu
# the Pod is <node>-debug; /host is the node's root filesystem
```

These don't require the Pod to have a shell, an image with shell tools, or any modification.

## The "kubectl auth" toolbox

For RBAC issues:

```bash
# can I do this?
kubectl auth can-i create deployments

# can a SA do this?
kubectl auth can-i list pods --as=system:serviceaccount:default:app

# what can this user do?
kubectl auth can-i --list --as=alice@example.com -n production
```

If a request is failing with `403 Forbidden`, this is the first place to look.

## Common issues and quick fixes

### ImagePullBackOff

```bash
kubectl describe pod <pod>
# Events:
#   Failed to pull image "registry.example.com/myapp:1.0":
#     rpc error: code = Unknown desc = Error response from daemon:
#     pull access denied for registry.example.com/myapp,
#     repository does not exist or may require 'docker login'
```

Causes:

* Wrong image name / tag
* Image doesn't exist
* No credentials for the registry
* Network policy / firewall blocking the registry

Fixes:

* Verify the image: `docker pull <image>` (locally, for dev)
* Add `imagePullSecrets`
* Allow egress to the registry in NetworkPolicy

### CrashLoopBackOff

```bash
kubectl logs <pod> --previous
# (whatever the app logged before dying)
kubectl describe pod <pod>
# Last State: Terminated, Reason: Error, Exit Code: 1
```

Causes:

* App error (config bad, code bug)
* OOM-killed (exit code 137)
* Liveness probe too aggressive
* Missing config / secret / dependency

Fixes:

* Read the logs
* Check `resources.limits.memory` if exit 137
* Disable liveness probe temporarily to confirm

### Pending

```bash
kubectl describe pod <pod>
# Events:
#   0/3 nodes are available: 3 Insufficient memory.
```

Causes:

* Not enough cluster capacity
* Node taints not tolerated
* Affinity / anti-affinity can't be satisfied
* PVC can't be bound (storage class issues)

Fixes:

* Add nodes (CA / Karpenter)
* Add tolerations
* Relax affinity
* Check the PVC

### Service has no endpoints

```bash
kubectl describe svc <service>
# Endpoints: <none>
kubectl get pods -l app=<service-selector>
# (all in CrashLoopBackOff or ImagePullBackOff)
```

The Service has no Pods matching its selector that are ready. Check:

* Selector matches the Pod labels
* Pods are `Ready` (readiness probe passing)
* Port matches

### DNS not resolving

```bash
kubectl run -it --rm debug --image=busybox -- nslookup kubernetes.default
# Server:    10.96.0.10
# Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
# nslookup: can't resolve 'kubernetes.default'
```

Causes:

* CoreDNS Pods aren't running
* NetworkPolicy blocks DNS egress
* `dnsPolicy: Default` in the Pod (uses node's resolv.conf, not cluster DNS)

Fixes:

* Restart CoreDNS
* Allow UDP/TCP port 53 to `kube-system` in NetworkPolicy
* Set `dnsPolicy: ClusterFirst`

## The notes in this level

→ [[Kubernetes/concepts/L08-operations/02-kubectl-debug|kubectl Debug Toolkit]] — the commands you reach for
→ [[Kubernetes/concepts/L08-operations/03-common-failure-modes|Common Failure Modes]] — the full triage guide
→ [[Kubernetes/concepts/L08-operations/04-metrics-sources|Metrics Sources]] — where observability data comes from

## See also

* [[Kubernetes/concepts/L03-workloads/10-probes|Probes]] — a common source of restart loops
* [[Kubernetes/concepts/L04-services-networking/03-dns|DNS]] — when DNS is the problem
* [[Kubernetes/concepts/L09-advanced/10-etcd|etcd]] — when the cluster itself is broken

# Common Failure Modes

A decision tree for **"my Pod isn't working"**. The first question is always: *is the Pod actually running?* If no, why not? If yes, what's the symptom?

## Table of Contents

1. [Stage 1: is the Pod scheduled?](#1-stage-1-is-the-pod-scheduled)
2. [Stage 2: the Pod is Running, but the app isn't](#2-stage-2-the-pod-is-running-but-the-app-isnt)
3. [Stage 3: container is crashing](#3-stage-3-container-is-crashing)
4. [Stage 4: deployment / rollout issues](#4-stage-4-deployment--rollout-issues)
5. [Stage 5: node issues](#5-stage-5-node-issues)
6. [Stage 6: everything is broken](#6-stage-6-everything-is-broken)
7. [The "kubectl describe" habit](#7-the-kubectl-describe-habit)
8. [Exit code reference](#8-exit-code-reference)
9. [The "I have no idea" checklist](#9-the-i-have-no-idea-checklist)
10. [Escalation checklist](#10-escalation-checklist)
11. [Quick reference tables](#11-quick-reference-tables)
12. [Common error strings and what they mean](#12-common-error-strings-and-what-they-mean)
13. [Gotchas](#13-gotchas)

---

### 1. Stage 1: is the Pod scheduled?

```bash
kubectl get pod <pod> -n <namespace>
kubectl describe pod <pod> | grep -A 20 "^Events"
```

| Status | What it means | Next step |
|--------|---------------|-----------|
| `Pending` | Scheduler hasn't placed it yet | Read Events — usually resources, affinity, PVC |
| `ContainerCreating` | Scheduled, preparing containers | Read Events — image pull, volume, CNI |
| `Running` | Container started | Go to Stage 2 |
| `CrashLoopBackOff` | Container keeps dying | Go to Stage 3 |
| `ImagePullBackOff` | Can't pull the image | Registry / auth / network issue |
| `Error` | Container exited with non-zero code | Go to Stage 3 |
| `Terminating` | Graceful shutdown in progress | Wait or check finalizers |
| `Unknown` | Node unreachable by API server | Check node (Stage 5) |

#### Pending: the full decision tree

```
Pending
├── Insufficient CPU / memory
│   └── Events: "0/3 nodes are available: 1 Insufficient CPU, 2 Insufficient memory"
│       └── Fix: raise limits, add nodes, adjust QoS
├── Taint not tolerated
│   └── Events: "node(s) had taints that the pod didn't tolerate"
│       └── Fix: add toleration to Pod, or remove taint from node
├── Node selector / affinity unsatisfied
│   └── Events: "node(s) didn't match pod affinity/selector"
│       └── Fix: adjust nodeSelector, affinity, or topology spread
├── No nodes match Labels / Topology
│   └── Events: "0/1 nodes are available: 1 node(s) didn't match topology"
│       └── Fix: check topologyKey, topologySpreadConstraints
├── PVC Pending (storage)
│   └── Events: "persistentvolumeclaim/... not found" or "waiting for first consumer"
│       └── Fix: check PVC exists, StorageClass, provisioner
├── Pod has Unsizeable resource requests
│   └── Events: "failed to admit pod: resource requests exceed allowed"
│       └── Fix: adjust requests to fit node allocatable
└── Scheduler not responding (rare)
    └── Check: kubectl get componentstatuses (legacy)
```

#### ContainerCreating: the full decision tree

```
ContainerCreating
├── Image pull failing
│   ├── "ImagePullBackOff" — wrong name, missing auth
│   │   └── Fix: imagePullSecrets, correct image name
│   ├── "ErrImagePull" — network issue to registry
│   │   └── Fix: check egress, DNS, registry reachability
│   └── "unauthorized: authentication required"
│       └── Fix: imagePullSecrets for the registry
├── Volume mount failing
│   ├── "Unable to attach or mount volumes"
│   │   └── Fix: check PVC exists, bound, CSI driver healthy
│   └── "no such file or directory" (for hostPath)
│       └── Fix: the path doesn't exist on the node
├── Secret / ConfigMap not found
│   └── Events: "secret/... not found" or "configmap/... not found"
│       └── Fix: create the Secret/ConfigMap in the same namespace
├── Init container stuck
│   └── Events: "init container ... has restart count > 0"
│       └── Fix: kubectl logs <pod> --previous (init container logs)
└── CNI not ready
    └── Events: "networkPlugin cni failed to set up pod network"
        └── Fix: check CNI DaemonSet pods in kube-system
```

---

### 2. Stage 2: the Pod is Running, but the app isn't

| Symptom | Likely cause | Check |
|---------|-------------|-------|
| Service has no endpoints | Readiness probe failing, selector mismatch | `kubectl get endpoints <svc>` |
| DNS resolves but connection refused | Wrong port, app not listening | `kubectl exec` → `ss -tlnp` |
| DNS works but 5xx from app | App error, wrong targetPort | `kubectl logs`, check Service `targetPort` |
| DNS works but 9xx / timeout | NetworkPolicy blocking | `kubectl get networkpolicy -A` |
| Slow responses | CPU throttling, OOM in progress | `kubectl top pod`, resource limits |
| 403 / RBAC error | RBAC missing for ServiceAccount | `kubectl auth can-i` |
| Requests routed to wrong Pod | Session affinity + backend flap | check endpoint stability |

#### The "Service has no endpoints" checklist

```bash
# 1. Does the Service have any endpoints at all?
kubectl get endpoints <service> -n <namespace>
# If empty: go to step 2

# 2. Which Pods does the selector match?
kubectl get pods -n <namespace> -l app=<selector-value>
# If no pods: selector mismatch — check labels on Pods vs svc.spec.selector

# 3. Are the Pods Ready?
kubectl get pods -n <namespace> -l app=<selector-value>
# If not Ready: readiness probe failing — check probe config

# 4. Are the pods in the Service's namespace?
kubectl get pods -n <namespace> -l app=<selector-value> --show-labels
# Cross-namespace Services are NOT supported (selector must match pods in same ns)

# 5. Check the targetPort
kubectl describe svc <service> | grep -A 3 "Port:"
# Is the container actually listening on that port?
kubectl exec <pod> -- ss -tlnp | grep <port>
```

#### Cross-namespace Service access

Services are **namespaced**. `default/my-svc` can only route to Pods in `default`. To expose a Service across namespaces, use:

- `ExternalName` Service (CNAME)
- A Ingress/Gateway
- A federated Service (rare)

---

### 3. Stage 3: container is crashing

```bash
kubectl logs <pod> --previous           # logs from the crashed instance
kubectl describe pod <pod>              # Last State, Exit Code, Restart Count
kubectl logs <pod> --all-containers    # all containers at once
```

#### Exit code reference

| Exit code | Name | What happened |
|-----------|------|--------------|
| 0 | Success | Container exited normally. Normal for Jobs; for Deployments, Kubernetes restarts it |
| 1 | Application error | Your code exited with non-zero. Check logs |
| 127 | Command not found | Entrypoint / CMD references a non-existent binary |
| 137 | SIGKILL (128 + 9) | OOM-killed (memory limit exceeded) OR `kill -9` |
| 139 | SIGSEGV (128 + 11) | Segmentation fault — memory corruption, bad pointer |
| 143 | SIGTERM (128 + 15) | Graceful termination (`kill -15`). Expected during Pod shutdown |
| 255 | Exit code out of range | Something went very wrong before the entrypoint ran |

#### CrashLoopBackOff: the decision tree

```
CrashLoopBackOff
├── App exits immediately with error
│   ├── Config file missing / unreadable
│   │   └── kubectl logs --previous | grep "no such file"
│   ├── Wrong entrypoint / missing binary
│   │   └── kubectl describe pod | grep "cannot find"
│   └── Dependency not reachable (DB, cache, API)
│       └── kubectl logs --previous | grep "connection refused"
├── OOM-killed (exit 137)
│   ├── Memory limit exceeded
│   │   └── kubectl describe pod | grep "OOMKilled"
│   │       Fix: raise memory limit, find the leak
│   └── Memory request too high for node
│       └── Events: "node didn't have Pod fixed"
│       Fix: lower request, add memory to node
├── Liveness probe kills app
│   ├── Probe fires before app is ready
│   │   └── increase `initialDelaySeconds`
│   ├── App becomes unhealthy under load
│   │   └── fix the app, or make probe less aggressive
│   └── Probe port wrong
│       └── check `livenessProbe.port` vs actual listening port
├── Permission denied
│   ├── readOnlyRootFilesystem: true but app needs to write
│   │   └── Events: "permission denied" on /some/path
│   │       Fix: set readOnlyRootFilesystem: false, or mount tmpfs
│   ├── runAsNonRoot: true but image runs as root
│   │   └── Events: "container has runAsNonRoot and image will run as root"
│   │       Fix: set `securityContext.runAsNonRoot: true` + runAsUser > 0
│   └── fsGroup doesn't match volume permissions
│       └── check volume gid vs fsGroup in securityContext
└── Init container failing (init container error → CrashLoopBackOff on main)
    └── kubectl logs <pod> --previous --container=<init-container>
```

#### OOM-killed deep dive

```bash
# Check if OOMKilled
kubectl describe pod <pod> | grep -A 5 "Last State"
# Last State: Terminated
#   Reason: OOMKilled
#   Exit Code: 137

# Check memory limits and usage
kubectl top pod <pod>

# Is the limit too low for the app?
# Is the request (not limit) causing the Pod to land on a memory-pressured node?
kubectl describe node <node> | grep -A 10 "Allocated resources"
# Memory: 8Gi requested, 16Gi allocatable — very tight

# Tune oomScoreAdj (default: pod's OOM score based on priority/limits)
# Higher oomScoreAdj = more likely to be OOM-killed under pressure
# Lower = less likely (system pods want lower = survive longer)
kubectl patch pod <pod> -p '{"spec":{" Containers":[{
# This won't work for existing pods — it's set at admission
# Configure via spec.priorityClassName or spec.containers[].resources
```

---

### 4. Stage 4: deployment / rollout issues

```bash
kubectl rollout status deployment/<name> -n <namespace>
kubectl rollout history deployment/<name>
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20
```

| Symptom | Cause | Fix |
|---------|-------|-----|
| Rollout stuck | New Pods failing readiness, old ones not terminating | `kubectl rollout undo` |
| Rollout succeeded but traffic broken | Probes too lax | Tighten probes, canary |
| `ProgressDeadlineExceeded` | No progress in 10 min (configurable) | Investigate scheduling/image issues |
| Pods Pending after rollout | New replicas can't be scheduled | Resources, affinity, taints |
| Revision mismatch | Rollback went wrong | `kubectl rollout history`, check revision |
| Pods CrashLoopBackOff after rollout | New version broken | `kubectl rollout undo` |

#### Rollback commands

```bash
# Rollback to previous version
kubectl rollout undo deployment/<name>

# Rollback to specific revision
kubectl rollout undo deployment/<name> --to-revision=3

# Pause a rollout (useful for CI/CD)
kubectl rollout pause deployment/<name>
kubectl rollout resume deployment/<name>

# Restart without a new image (re-create pods)
kubectl rollout restart deployment/<name>
```

#### Why probes were "too lax"

A probe that's too lax passes even when the app is broken:

```yaml
# Bad: startup probe passes immediately, liveness probe too generous
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 0   # passes immediately, even if app is starting
  periodSeconds: 10         # waits 10s before declaring dead
  failureThreshold: 3       # waits 30s before killing
# If app needs 60s to start, it gets killed before it boots
```

---

### 5. Stage 5: node issues

```bash
kubectl get nodes
kubectl describe node <node>
kubectl top node <node>
```

| Condition | Meaning | Pods affected |
|-----------|---------|---------------|
| `Ready` | Normal | None |
| `MemoryPressure` | Node is low on memory | New Pods with BestEffort QoS rejected |
| `DiskPressure` | Node is low on disk | New Pods rejected |
| `PIDPressure` | Node is out of PIDs | New Pods rejected |
| `NetworkUnavailable` | CNI has not configured pod network | Pods on this node can't communicate |
| `NotReady` | kubelet can't reach API server, or node overwhelmed | All Pods on this node are treated as terminating |

#### Node NotReady: what to check

```bash
# On the node (ssh in):
systemctl status kubelet
journalctl -u kubelet -n 50 --no-pager
# Look for: "failed to start kubelet", "node not found", TLS errors

# Check if kubelet can talk to the API server
curl -k https://<api-server>:6443/healthz

# Check if the node's cert is still valid
openssl x509 -in /var/lib/kubelet/pki/kubelet.crt -noout -dates

# Check if the node's lease in etcd is still alive
kubectl get node <node> -o jsonpath='{.status.conditions[?(@.type=="Ready")]}' | jq

# Check for resource pressure
df -h           # disk
free -h         # memory
cat /proc/loadavg  # CPU load
```

#### Kubelet not starting: common causes

```bash
# 1. TLS cert rotation failed
# kubelet logs: "unable to load client CA file"
# Fix: re-bootstrap kubelet credentials
kubeadm init phase kubelet --bootstrap

# 2. Kubeconfig missing
# Fix:
kubeadm init phase kubeconfig kubelet --kubeconfig-dir=/var/lib/kubelet

# 3. CSI driver failure (causes NetworkUnavailable on node)
kubectl get pods -n kube-system -l k8s-app=csi-driver
kubectl logs <csi-driver-pod> -n kube-system

# 4. etcd unreachable (for stacked control plane nodes)
# kubelet logs: "server timeout"
```

---

### 6. Stage 6: everything is broken

When the cluster itself is in trouble:

```bash
# Are the control-plane components healthy?
kubectl get pods -n kube-system
# All should be Running, not Restarting or Pending

# Is the API server responding?
kubectl get --raw '/healthz'
# Returns: "ok"

# Is etcd healthy?
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Cluster-wide events
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# API server logs (if you have access)
# Usually at: /var/log/pods/kube-system/kube-apiserver-*/kube-apiserver/*.log
# or via journalctl on the control plane node

# Component status (legacy but still works)
kubectl get componentstatuses
# NAME                      STATUS    MESSAGE              ERROR
# scheduler                 Healthy   ok
# controller-manager       Healthy   ok
# etcd-0                    Healthy   ok
```

#### What to check for each control-plane component

```
kube-apiserver (API server)
├── Is the pod running?
│   └── kubectl get pods -n kube-system kube-apiserver-<node>
├── Is it listening?
│   └── ss -tlnp | grep 6443
├── Can it reach etcd?
│   └── etcdctl endpoint health
├── Logs: TLS errors, authentication errors, RBAC denials
│   └── kubectl logs -n kube-system kube-apiserver-<node> --previous | grep -i error
└── /healthz endpoint: "etcdserver: leader is unknown" — etcd cluster issue

kube-controller-manager
├── Pod running?
├── Controller loop errors (Deployment, ReplicaSet stuck?)
│   └── kubectl get events | grep "controller"
└── Cloud provider issues (CCR, CLB controllers on cloud)

kube-scheduler
├── Pod running?
├── "waiting for pod" events (scheduler not placing pods)
│   └── kubectl get events | grep "unschedulable"
└── Schedulerextender failures (if custom scheduler)

etcd
├── Pod running and healthy?
├── Disk latency: "fsync took too long"
├── Leader elections: "raft: leader changed"
└── Out of space: "database space exceeded"
```

---

### 7. The "kubectl describe" habit

`kubectl describe pod` is the single most informative command for pod issues. Read it **top to bottom**:

```bash
kubectl describe pod <pod-name> -n <namespace>
```

What to look for in each section:

```
Name:             my-app-7d8f9c6b5-abcde
Namespace:        production
Priority:         0
Node:             node-2/10.0.1.2
Start Time:       Thu, 11 Jun 2026 10:00:00 +0000
Labels:           app=my-app version=v2
Annotations:      <none>
Status:           Running                                          ← check here
Conditions:
  Type             Status
  PodScheduled     True
  Initialized      True
  ContainersReady  True
  Ready            True                                          ← should all be True
Volumes:
  config:      ConfigMap (r/o) name=my-config
  credentials: Secret (r/o) name=db-creds
QoS Class:        Burstable                                        ← Guaranteed/Burstable/BestEffort
Tolerations:      node.kubernetes.io/not-ready:NoExecute for 300s  ← check taints

Init Containers:
  init-db    Running (healthcheck)    0/1                    ← init container running

Containers:
  my-app:
    Container ID:   docker://abc123...
    Image:          my-registry.com/my-app:v2
    Image ID:       docker-pullable://...
    Port:           8080/TCP
    State:          Running                                     ← Running/Waiting/Terminated
      Reason:      ContainerCreating (if not Running)
    Last State:     Terminated (Exit Code: 137, Reason: OOMKilled)  ← CRITICAL if non-zero
    Ready:          True
    Restart Count:  3                                           ← if high, something keeps crashing
    Limits:         cpu: 500m, memory: 256Mi
    Requests:       cpu: 100m, memory: 64Mi
    Environment:    from secret db-creds, from configmap my-config
    Mounts:         /etc/config from config (rw)

Events:                                                         ← MOST USEFUL SECTION
  Type     Reason                  Age   From             Message
  ────     ──────                  ──   ───             ───────
  Normal   Scheduled                2m   default-scheduler  Successfully scheduled
  Normal   Pulling                  1m   kubelet           Pulling image "my-registry.com/my-app:v2"
  Normal   Pulled                   1m   kubelet           Successfully pulled image "..."
  Normal   Created                  1m   kubelet           Created container my-app
  Normal   Started                  1m   kubelet           Started container my-app
  Warning  Unhealthy               30s   kubelet           Liveness probe failed
```

---

### 8. Exit code reference

| Code | Signal | Meaning | Action |
|------|--------|---------|--------|
| 0 | — | Exited normally | Jobs: expected. Deployments: will restart |
| 1 | SIGKILL (128+1) | Application error | Check logs |
| 127 | — | Command not found | Entrypoint typo, wrong image base |
| 137 | SIGKILL (128+9) | OOM-killed OR `kill -9` | Increase limit or find leak |
| 139 | SIGSEGV (128+11) | Segfault — memory corruption | App bug, check core dump |
| 143 | SIGTERM (128+15) | Graceful termination | Normal during shutdown |
| 255 | — | Entrypoint failed before exec | Entrypoint script error |

---

### 9. The "I have no idea" checklist

When you've tried everything and nothing makes sense:

```bash
# 1. Full pod describe (including Events — always)
kubectl describe pod <pod> -n <namespace>

# 2. Previous container logs (if crashlooping)
kubectl logs <pod> --previous --all-containers

# 3. Namespace events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# 4. Node status and resource pressure
kubectl describe node <node-name>
kubectl top node <node-name>

# 5. System pods in kube-system
kubectl get pods -n kube-system
# Are DNS, CNI, API server all healthy?

# 6. CNI check
kubectl get pods -n kube-system -l k8s-app=...   # CNI daemonset
# Are CNI pods running on ALL nodes?

# 7. DNS check
kubectl run -it --rm debug --image=busybox -- nslookup kubernetes.default
# If this fails: CoreDNS is broken

# 8. API server health
kubectl get --raw '/healthz'
# Should return "ok"

# 9. Etcd health (if you have access)
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=... --cert=... --key=...

# 10. Increase kubectl verbosity
kubectl -v=8 describe pod <pod>     # shows raw API calls
kubectl -v=8 get pod <pod>          # TLS/auth issues show here
```

---

### 10. Escalation checklist

If you've spent 15 minutes and don't have a lead:

```bash
# Level 1: Basic state
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Level 2: Resource exhaustion
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"
# Are nodes out of CPU/memory/PIDs?

# Level 3: Network
kubectl get networkpolicies -A
# Is a NetworkPolicy blocking your traffic?
kubectl exec <pod> -- nslookup kubernetes.default
# Is DNS working?

# Level 4: Storage
kubectl get pvc -A
kubectl describe pvc <pvc>
# Is storage provisioned? Is the PVC bound?

# Level 5: Control plane
kubectl get componentstatuses
# Any unhealthy components?
# Check disk/memory on control plane nodes
```

---

### 11. Quick reference tables

#### ImagePullBackOff causes

| Error message | Cause | Fix |
|---------------|-------|-----|
| `ImagePullBackOff` + `ErrImagePull` | Wrong image name / tag | Verify image exists, correct name |
| `ImagePullBackOff` + `unauthorized` | No registry credentials | Add `imagePullSecrets` |
| `ImagePullBackOff` + `denied` | Image is private / org policy | `imagePullSecrets`, registry policy |
| `ImagePullBackOff` + `tcp timeout` | Network to registry blocked | Firewall rules, egress allowed |
| `ImagePullBackOff` + `manifest unknown` | Tag doesn't exist | Use correct tag / digest |

#### Pending pod causes

| Event | Cause | Fix |
|-------|-------|-----|
| `0/3 nodes available: 1 Insufficient cpu` | No CPU headroom | Add nodes, lower requests |
| `0/3 nodes available: 1 Insufficient memory` | No memory headroom | Add nodes, lower requests |
| `node(s) had taints` | Taints not tolerated | Add toleration to Pod |
| `didn't match Pod affinity` | Affinity rule unsatisfiable | Relax affinity |
| `pvc not found` | PVC doesn't exist | Create PVC |
| `waiting for first consumer` | StorageClass delay | Wait or check provisioner |
| `unexpected unresolved PodSchedulingGate` | Pod has scheduling gates | Remove `schedulingGates` |

---

### 12. Common error strings and what they mean

```bash
# "pod has unbound immediate PersistentVolumeClaims"
kubectl get pvc -n <namespace>
# PVC exists but no StorageClass set, or provisioner is down

# "kubernetes endpoint not found"
# CoreDNS / kube-proxy issue:
kubectl get endpoints kube-dns -n kube-system
kubectl get pods -n kube-system -l k8s-app=kube-dns

# "connection refused" to Service ClusterIP
# kube-proxy not working or IPVS/iptables issue:
ipvsadm -L -n 2>/dev/null || iptables -L KUBE-SERVICES -n | head

# "no route to host"
# CNI issue, network policy, or firewall:
ping <pod-ip>
kubectl exec debug -- ping <target-ip>

# "dial tcp: lookup my-svc.my-ns on 10.96.0.10:53"
# DNS issue:
kubectl exec debug -- nslookup my-svc.my-ns
# CoreDNS not working or NetworkPolicy blocking port 53

# "node(s) exceeded memory pressure"
kubectl top nodes
# Pod eviction in progress or imminent

# "node(s) out of pids"
# PID limit exceeded:
cat /proc/sys/kernel/pid_max
# Increase node's pid.max or reduce pod density
```

---

### 13. Gotchas

* **"Pending" can mean many things.** The Events section is the only way to know which.
* **A "Running" Pod is not necessarily a working Pod.** The container is up; the app may not be.
* **The same error can have many causes.** "CrashLoopBackOff" tells you it's crashing, not why.
* **Restart count in `kubectl get pod` is cumulative across the Pod's life.** A Pod running 30 days with 3 restarts is fine. One running 30 seconds with 3 restarts is a problem.
* **`kubectl rollout undo` is a real rollback.** It changes the Deployment's template to the previous revision. Safer than editing YAML.
* **A node can be "Ready" but still have problems.** Disk full, kernel deadlock, kubelet hang — none of these immediately flip the Ready condition.
* **The "CrashLoopBackOff" timing is exponential.** First restart 10s, then 20s, 40s ... up to 5 minutes. A Pod in CLB may be slow to recover.
* **`kubectl get events` has a 1-hour TTL.** If the event is old, it's gone. Ship events to a log aggregator for cluster-wide history.
* **"No endpoints" means the Service selector found no Ready Pods.** It does NOT mean the Pods don't exist — check readiness and selector.
* **Cross-namespace Services don't work.** The Service selector can only match Pods in the same namespace.
* **`kubectl rollout restart` doesn't change the image tag.** It just deletes/recreates the pods. Use `kubectl set image` for an actual update.
* **`kubectl describe pod` shows `Last State: Terminated`** — this is the state of the previous (crashed) container, not the current one.

---

## See also

* [[Kubernetes/concepts/L08-operations/02-kubectl-debug|kubectl Debug Toolkit]] — the commands to use during this flow
* [[Kubernetes/concepts/L08-operations/01-troubleshooting|Troubleshooting]] — the quick-reference version
* [[Kubernetes/concepts/L08-operations/04-metrics-sources|Metrics Sources]] — where observability data comes from
* [[Kubernetes/concepts/L03-workloads/10-probes|Probes]] — liveness/readiness probes are a common crash cause
* [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource Requests & Limits]] — OOM and CPU throttling
* [[Kubernetes/concepts/L09-advanced/10-etcd|etcd]] — when the cluster itself is broken

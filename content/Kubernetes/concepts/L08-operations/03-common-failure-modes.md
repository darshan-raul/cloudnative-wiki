# Common Failure Modes

A decision tree for **"my Pod isn't working"**. The first question is always: *is the Pod actually running?* If no, why not? If yes, what's the symptom?

## Stage 1: is the Pod scheduled?

```bash
kubectl get pod <pod>
kubectl describe pod <pod> | tail -20      # Events at the bottom
```

| Status | What it means | Next step |
|---|---|---|
| `Pending` | Scheduler hasn't placed it | Read events — usually insufficient resources, unsatisfiable affinity, or unsatisfiable PVC |
| `ContainerCreating` | Scheduled, image / volume being prepared | Read events — image pull, volume mount, secret mount issues |
| `Running` | Container(s) started | Stage 2 |
| `CrashLoopBackOff` | Container keeps exiting | Stage 3 |
| `ImagePullBackOff` | Can't pull the image | Image / registry / secret issue |
| `Error` | Container exited with error | Stage 3 |

## Stage 2: the Pod is Running, but the app isn't

| Symptom | Likely cause | Check |
|---|---|---|
| Service has no endpoints | Readiness probe failing | `kubectl describe pod` → conditions → Ready |
| Service routes but 5xx | App error, or wrong port | `kubectl logs`, check `targetPort` in Service |
| DNS works but no response | NetworkPolicy blocking | `kubectl get networkpolicy -A` |
| Slow responses | CPU throttle, OOM in progress | `kubectl top pod`, resource limits |
| Connection refused | Wrong port or app not listening | `kubectl exec` → `ss -tlnp` |

### The "Service has no endpoints" checklist

1. Readiness probe is failing — fix the probe or make the app respond healthy
2. Selector mismatch — `kubectl get endpoints <service>` will be empty
3. Container is listening on a different port than the Service's `targetPort`
4. Pod is on a node the Service can't reach (shouldn't happen with normal k8s, but possible with weird CNI configs)

## Stage 3: container is crashing

```bash
kubectl logs <pod> --previous     # logs from the previous (crashed) container
kubectl describe pod <pod>        # Last State, Exit Code
```

| Exit code | Meaning |
|---|---|
| 0 | Normal exit (Jobs only; for Deployments, this triggers a restart) |
| 1 | Application error — your code is exiting |
| 137 | SIGKILL (OOM-killed or evicted) |
| 139 | SIGSEGV — segfault |
| 143 | SIGTERM (graceful shutdown) |

### CrashLoopBackOff common causes

* **Bad config** — the app can't read its config, exits with an error
* **Missing dependency** — the app tries to talk to a DB that's not there
* **Bad image** — entrypoint doesn't exist or fails immediately
* **Liveness probe too aggressive** — the app starts but gets killed by the probe before it's ready
* **Permission denied** — readOnlyRootFilesystem, runAsNonRoot, fsGroup mismatch

### OOM-killed (exit 137)

The container used more memory than its `limit`. Either:

* Raise the limit (and the request)
* Find the leak
* Add `oomScoreAdj` if the workload is critical and the OOM-killer is too aggressive

```bash
kubectl describe pod <pod> | grep -A 5 "Last State"
# Reason: OOMKilled
# Exit Code: 137
```

## Stage 4: deployment / rollout issues

```bash
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
```

| Symptom | Cause |
|---|---|
| Rollout stuck | New Pods failing readiness, old ones not terminated |
| Rollout succeeded but traffic broken | The new version is broken; the probes were too lax |
| `ProgressDeadlineExceeded` | Rollout didn't make progress in 10 minutes |
| Pods Pending after rollout | New replicas can't be scheduled (resources, affinity) |

## Stage 5: node issues

```bash
kubectl get nodes
kubectl describe node <node>
```

| Symptom | Cause |
|---|---|
| `NotReady` | kubelet can't reach the API server, or the node is overwhelmed |
| `MemoryPressure` | Node is low on memory; Pods will be evicted (BestEffort first) |
| `DiskPressure` | Node is low on disk; Pods will be evicted |
| `PIDPressure` | Node is out of PIDs |
| `NetworkUnavailable` | CNI is broken on this node |

If a node is `NotReady`, the Pods are rescheduled (after the controller's tolerationSeconds — default 5 minutes for most controllers). **Don't panic; investigate.**

## Stage 6: "everything is broken"

When the cluster itself is in trouble:

```bash
# are the control-plane components healthy?
kubectl get componentstatuses        # legacy, but still works
kubectl get pods -n kube-system       # are the system Pods running?
kubectl get events -A --sort-by=.lastTimestamp | head -20

# is the API server responding?
kubectl get --raw='/healthz'

# is etcd healthy? (you need access to etcd)
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

## The "kubectl describe" habit

Most pod issues are visible in `kubectl describe pod` if you read the whole output:

1. **Status** — Pending / Running / etc.
2. **Conditions** — PodScheduled, Initialized, ContainersReady, Ready
3. **Container statuses** — State, Ready, Restart Count, Image
4. **Events** — at the bottom. The most useful part. `kubectl get events` shows them cluster-wide.

When asking for help, always include:

* `kubectl describe pod <pod>` (full)
* `kubectl logs <pod> --previous` (if it's crashlooping)
* The output of `kubectl get events --field-selector involvedObject.name=<pod>`

## Gotchas

* **"Pending" can mean many things.** The Events section is the only way to know which.
* **A "Running" Pod is not necessarily a working Pod.** The container is up; the app may not be.
* **The same error can have many causes.** "CrashLoopBackOff" tells you it's crashing, not why.
* **Restart counts in `kubectl get pod` are cumulative across the Pod's life.** A Pod that's been running for 30 days with 3 restarts is not the same as one that's been running for 30 seconds with 3 restarts.
* **`kubectl rollout undo` is a real rollback.** It changes the Deployment's template back to the previous one. Safer than editing YAML by hand.
* **A node can be "Ready" but still have problems.** Disk full, kernel deadlock, kubelet hang — none of these immediately flip the Ready condition.
* **The "CrashLoopBackOff" timing is exponential.** First restart 10s, then 20s, 40s, ... up to 5 minutes. A Pod in CLB may be slow to recover.

## Escalation checklist

If you've spent 15 minutes and don't have a lead:

1. Are the **nodes** healthy? (`kubectl get nodes`)
2. Are the **system Pods** in `kube-system` healthy? (`kubectl get pods -n kube-system`)
3. Are there **cluster-wide events**? (`kubectl get events -A --sort-by=.lastTimestamp | head -30`)
4. Is the **CNI** healthy? (look for CNI Pods / DaemonSets)
5. Is the **DNS** working? (`kubectl run -it --rm debug --image=busybox -- nslookup kubernetes.default`)
6. **Increase verbosity**: `kubectl -v=8 describe ...` shows the raw API calls; can reveal auth / TLS issues

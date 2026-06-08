# Restart Policy

*"https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#restart-policy"*

A Pod's `restartPolicy` determines how the kubelet behaves when a container terminates. The three values are `Always` (default), `OnFailure`, and `Never` — each applies to a different kind of workload. The restart policy is set at the **Pod** level and applies to all containers in the Pod (init containers excluded — they always run to completion).

### Table of Contents

1. [The Three Restart Policies](#1-the-three-restart-policies)
2. [Restart Policy and Workload Type](#2-restart-policy-and-workload-type)
3. [The Restart Backoff Algorithm](#3-the-restart-backoff-algorithm)
4. [Exit Codes and What They Mean](#4-exit-codes-and-what-they-mean)
5. [Init Containers and Restart Policy](#5-init-containers-and-restart-policy)
6. [The kubelet's Restart Loop](#6-the-kubelets-restart-loop)
7. [Container Restart vs Pod Restart](#7-container-restart-vs-pod-restart)
8. [terminationGracePeriodSeconds and Restart](#8-terminationgraceperiodseconds-and-restart)
9. [livenessProbe and Restart](#9-livenessprobe-and-restart)
10. [Job's restartPolicy and backoffLimit](#10-jobs-restartpolicy-and-backofflimit)
11. [StatefulSet and DaemonSet Restart Policy](#11-statefulset-and-daemonset-restart-policy)
12. [Common Pitfalls](#12-common-pitfalls)
13. [Operations and Debugging](#13-operations-and-debugging)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)

---

## 1. The Three Restart Policies

```yaml
apiVersion: v1
kind: Pod
metadata: { name: app }
spec:
  restartPolicy: Always       # default
  containers:
  - name: app
    image: app:1.0
```

### 1.1 `Always` (default)

The kubelet **always restarts** the container, regardless of exit code. This is the default for any Pod without an explicit `restartPolicy`.

```yaml
spec:
  restartPolicy: Always
```

**Use for:** long-running services (web servers, API servers, daemons).

The container is restarted on:
- Normal exit (0).
- Error exit (non-zero).
- Crash (signal, segfault).
- OOM-kill.
- Liveness probe failure.

The kubelet restarts indefinitely. **There is no limit on restarts.** Use `maxRetries` on a Job, or rely on the backoff algorithm to space out the restarts.

### 1.2 `OnFailure`

The kubelet restarts the container **only if it exits with a non-zero status**. A successful exit (code 0) leaves the container stopped.

```yaml
spec:
  restartPolicy: OnFailure
```

**Use for:** batch jobs, one-shot tasks that should retry on failure. (This is the default for Jobs.)

The container is restarted on:
- Non-zero exit code.
- Crash.
- OOM-kill.
- Liveness probe failure.

The container is **NOT** restarted on:
- Exit code 0.
- The Pod being deleted.

### 1.3 `Never`

The kubelet **never** restarts the container after it terminates.

```yaml
spec:
  restartPolicy: Never
```

**Use for:** one-shot tasks that should not retry. Less common — usually `OnFailure` is preferred so the task retries on transient failures.

The container is **not** restarted for any reason. Once it exits, the kubelet records the exit and moves on. The Pod's status reflects the final state.

## 2. Restart Policy and Workload Type

The `restartPolicy` should match the workload:

| Workload | Typical restartPolicy | Why |
|---|---|---|
| Deployment (web server) | `Always` (default) | Long-running, must stay up |
| StatefulSet (DB) | `Always` (default) | Long-running, must stay up |
| DaemonSet (node agent) | `Always` (default) | Long-running, must stay up |
| Job (batch task) | `OnFailure` | Should retry on failure, but not on success |
| CronJob (scheduled task) | `OnFailure` (via Job) | Same as Job |
| One-shot Pod | `Never` | Should not retry |
| Init container | (n/a) | Init containers always run to completion |

The `restartPolicy` is set by the **controller** (Deployment, Job, etc.) when it creates the Pod. You can override it in the Pod template, but you usually shouldn't.

### 2.1 What each controller sets

| Controller | Default restartPolicy | Override possible? |
|---|---|---|
| Deployment | `Always` | Yes, but rare |
| StatefulSet | `Always` | Yes, but rare |
| DaemonSet | `Always` | Yes, but rare |
| Job | `OnFailure` | Yes, also `Never` |
| CronJob | `OnFailure` (via Job) | Yes |
| Bare Pod | `Always` | Yes |

## 3. The Restart Backoff Algorithm

When a container is restarted, the kubelet **waits an increasing amount of time** between restarts. This is the **exponential backoff** algorithm.

```
Restart 1: wait 10s
Restart 2: wait 20s
Restart 3: wait 40s
Restart 4: wait 80s
Restart 5: wait 160s
Restart 6: wait 300s (5 min)  ← cap
Restart 7+: wait 300s
```

The backoff starts at 10s, doubles each time, and **caps at 5 minutes**. Once the cap is hit, all subsequent restarts are 5 min apart.

The backoff **resets** after 10 minutes of successful running. A container that runs for 10 min without restarting has its backoff reset.

### 3.1 The CrashLoopBackOff

A container that crashes repeatedly enters **CrashLoopBackOff**. The kubelet:

1. Restarts the container.
2. Waits the backoff time.
3. Container crashes again.
4. Backoff doubles (up to 5 min).
5. Repeat.

The Pod is `Running` (the kubelet is actively managing it), but the container keeps crashing. The `kubectl get pod` shows `CrashLoopBackOff` in the STATUS column.

### 3.2 The kubelet's flags

The backoff is configurable on the kubelet:

```bash
# kubelet flags
--node-status-update-frequency=10s
--node-monitor-grace-period=40s
```

But the backoff algorithm itself (10s → 300s, doubling) is built-in. You can only change the cap (via `--node-monitor-grace-period` indirectly) or override the wait per-container via the `restartPolicy` itself.

## 4. Exit Codes and What They Mean

The container's **exit code** is what determines whether the kubelet restarts (under `OnFailure` or `Always`).

| Exit code | Meaning | When |
|---|---|---|
| 0 | Success | App explicitly exited 0 |
| 1 | General error | App's error path |
| 2 | Misuse of shell builtins | Shell script bug |
| 126 | Command cannot execute | Permissions |
| 127 | Command not found | Typo |
| 128 + N | Killed by signal N | Signal (e.g. 137 = SIGKILL, 143 = SIGTERM) |
| 137 | SIGKILL (9) | OOM-kill, `kubectl delete pod --force` |
| 139 | SIGSEGV (11) | Segfault |
| 143 | SIGTERM (15) | `kubectl delete pod`, normal termination |

### 4.1 Common exit codes you'll see

* **0** — clean shutdown. `OnFailure` doesn't restart. `Always` does restart.
* **137** — OOM-killed or force-killed. `OnFailure` restarts. **The container that OOM-killed will probably OOM-kill again.**
* **139** — segfault. `OnFailure` restarts. The app has a bug.
* **143** — graceful termination. The container handled SIGTERM and exited. `OnFailure` doesn't restart on 0... wait, 143 is 128 + 15, which is signal 15 (SIGTERM), so it's a non-zero status. `OnFailure` does restart.

Actually, the rule is: **exit code 0 = success, anything else = failure.** Even 143 (terminated by signal) is "non-zero" and triggers `OnFailure` restart.

### 4.2 The signal exit code formula

```
exit_code = 128 + signal_number
```

So:
- 137 = 128 + 9 (SIGKILL)
- 143 = 128 + 15 (SIGTERM)
- 139 = 128 + 11 (SIGSEGV)

If the container was killed by a signal, the exit code is `128 + signal_number`.

### 4.3 The special case: `successThreshold` and readiness

For `livenessProbe`, the kubelet considers the container **healthy** only after `successThreshold` consecutive successes. For `readinessProbe`, the same.

**A liveness probe failure is a kill.** The kubelet kills the container (with SIGKILL, exit code 137) and restarts it.

**A readiness probe failure is not a kill.** The kubelet removes the Pod from the Service's endpoints. The container keeps running.

## 5. Init Containers and Restart Policy

Init containers have a **different** restart policy from regular containers — they always run to completion. If an init container fails, the Pod's regular containers don't start, and the init container is **not** restarted (the Pod is restarted by the kubelet under the Pod's `restartPolicy`).

```
Pod lifecycle:
  1. Init container 1 starts
  2. Init container 1 fails
  3. Pod is restarted (per Pod's restartPolicy)
  4. Init container 1 starts again
  5. ... (repeat until init succeeds or Pod is deleted)
```

Init containers don't have their own `restartPolicy` — they always run to completion. The Pod's `restartPolicy` controls what happens to the **Pod** when an init container fails.

A Job with init containers: if the init fails, the Job retries (per `backoffLimit`).

## 6. The kubelet's Restart Loop

The kubelet runs a loop per container:

```
1. Start the container
2. Wait for it to exit
3. If restartPolicy says restart:
   a. Apply backoff
   b. Go to step 1
4. If restartPolicy says don't restart:
   a. Mark the container as terminated
   b. Exit the loop
```

The loop runs **forever** for `Always`. For `OnFailure`, it runs until the container exits with 0. For `Never`, it runs only once.

The kubelet's restart is at the **container** level, not the Pod level. The Pod stays `Running`; the container is restarted. **The Pod's IP doesn't change on container restart.** The container's filesystem is also preserved (depending on the volume config).

## 7. Container Restart vs Pod Restart

A container restart is **not** the same as a Pod restart:

* **Container restart** — the kubelet restarts the container in place. The Pod's IP is the same. The container's filesystem is preserved. **No external disruption** (the Pod's Service routing is unaffected, but the brief moment during restart is "down").

* **Pod restart** — the Pod is deleted and a new one is created. The new Pod has a new IP. The container starts fresh. The Service routing updates.

A container restart is **involuntary** (the kubelet does it). A Pod restart is **voluntary** (you do it, or a controller does).

`kubectl rollout restart` triggers a **Pod restart** (rolls the Deployment). `kubectl delete pod` triggers a Pod restart. Container restarts happen automatically.

## 8. terminationGracePeriodSeconds and Restart

`terminationGracePeriodSeconds` is the time the kubelet gives a container to **shut down gracefully** after SIGTERM.

```yaml
spec:
  terminationGracePeriodSeconds: 30
  containers:
  - name: app
    image: app:1.0
    lifecycle:
      preStop:
        exec:
          command: ["/bin/sh", "-c", "sleep 5"]
```

When the kubelet wants to stop a container (for restart, eviction, etc.):

1. Sends SIGTERM.
2. Waits up to `terminationGracePeriodSeconds` (default 30s).
3. Sends SIGKILL if the container hasn't exited.

The container's `preStop` hook (if any) runs before SIGTERM. The app should handle SIGTERM by closing connections, finishing in-flight work, and exiting.

### 8.1 The interaction with restart

For container restart:
- `terminationGracePeriodSeconds` is the time the kubelet waits for graceful shutdown.
- The container gets SIGTERM, has 30s to exit, then SIGKILL.
- If the container exits within 30s, the kubelet starts the new container immediately.
- If not, the kubelet SIGKILLs the old container and starts the new one.

For Pod deletion (e.g. `kubectl delete pod`):
- Same as above. The Pod's `terminationGracePeriodSeconds` applies.

## 9. livenessProbe and Restart

The `livenessProbe` is the kubelet's check for "is this container still working". If the probe fails repeatedly, the kubelet **kills and restarts** the container.

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3
```

If the probe fails 3 times in a row (over 30s), the kubelet kills the container (SIGKILL, exit 137) and restarts it.

### 9.1 livenessProbe vs readinessProbe

* **livenessProbe** — "is the container alive?" If no, restart. **Restart-on-failure.**
* **readinessProbe** — "is the container ready to serve traffic?" If no, remove from Service. **Don't restart.**

Common pattern: a slow app takes a while to start. Use `initialDelaySeconds` to give it time. The liveness probe shouldn't fire during startup.

### 9.2 The liveness probe trap

A liveness probe that's too strict will restart the container unnecessarily. A liveness probe that checks downstream dependencies (e.g. "is the database reachable?") will restart the container when the DB has a hiccup — which doesn't fix the DB issue, just thrashes the Pod.

**Liveness probes should check "am I still functional"**, not "are my dependencies up". For dependency checks, use readiness probes.

## 10. Job's restartPolicy and backoffLimit

A Job's Pods use `restartPolicy: OnFailure` (or `Never`) by default. The Job also has a `backoffLimit`:

```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: my-job }
spec:
  backoffLimit: 6       # retry the Pod up to 6 times
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: worker
        image: worker:1.0
```

The Job controller:
1. Creates a Pod.
2. The Pod runs. If it fails, the kubelet restarts the container (per `OnFailure`).
3. If the Pod's container keeps failing, the kubelet gives up (per the backoff algorithm).
4. The Job controller counts the failure, increments the retry counter.
5. If the retry counter exceeds `backoffLimit`, the Job is marked as `Failed`. The Pod is left in a failed state.

### 10.1 The Pod failure policy (k8s 1.26+)

For more granular control:

```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: my-job }
spec:
  backoffLimit: 6
  podFailurePolicy:
    rules:
    - action: FailJob
      onExitCodes:
        containerName: worker
        operator: In
        values: [42]               # exit 42 = fail the Job
    - action: Ignore
      onExitCodes:
        containerName: worker
        operator: In
        values: [137]              # exit 137 = ignore (OOM is normal in our app)
    - action: Count
      onExitCodes:
        containerName: worker
        operator: In
        values: [1]                # exit 1 = count toward backoffLimit
```

This lets you distinguish "intentional failure" (exit 42 = fail) from "OOM" (exit 137 = ignore) from "transient error" (exit 1 = retry).

## 11. StatefulSet and DaemonSet Restart Policy

### 11.1 StatefulSet

A StatefulSet's Pods use `restartPolicy: Always` (the default). The StatefulSet controller creates Pods with stable identities. When a Pod is restarted (container restart), the Pod's identity is preserved.

If the Pod is **deleted and recreated** (Pod restart, not container restart), the StatefulSet controller creates a new Pod with the same ordinal. The PVC is bound to the new Pod.

### 11.2 DaemonSet

A DaemonSet's Pods use `restartPolicy: Always`. The DS controller ensures one Pod per node. When a node dies, the DS Pod is gone; when the node returns, the DS Pod is recreated.

The DS controller also handles **rolling updates** — when the DS template changes, the controller rolls the Pods one at a time, respecting `maxUnavailable` and `maxSurge`.

## 12. Common Pitfalls

### 12.1 The "container keeps restarting" loop

A container that crashes immediately on every restart is in **CrashLoopBackOff**. The Pod is `Running` but the container isn't.

Common causes:
- Bad config (missing env vars, wrong image, etc.)
- App startup error (database not reachable, port in use, etc.)
- Liveness probe failure (probe checks something that fails on startup)

Fix: `kubectl logs <pod> --previous` to see the previous container's logs. The crash usually leaves a stack trace.

### 12.2 The "livenessProbe too strict" trap

A liveness probe that returns 503 during normal operation restarts the container unnecessarily. **Liveness probes should be a stable check**, not a "is everything perfect" check.

```yaml
# too strict
livenessProbe:
  httpGet:
    path: /health/full        # checks all dependencies

# better
livenessProbe:
  httpGet:
    path: /health/live        # checks only "am I running"

readinessProbe:
  httpGet:
    path: /health/ready       # checks "am I ready for traffic"
```

### 12.3 The "OnFailure" + exit 0 trap

A container that exits 0 under `OnFailure` is **not restarted**. The Pod's status is `Succeeded`. The container is stopped.

If the app accidentally exits 0 when it shouldn't, the Pod is "succeeded" but not actually working. **Use a liveness probe or a startup script that exits non-zero on failure.**

### 12.4 The "Always" + Job trap

A Job's Pod uses `OnFailure` by default. If you set `restartPolicy: Always`, the Pod will restart on success (exit 0), which means the Job never completes.

**Don't use `Always` for Jobs.**

## 13. Operations and Debugging

### 13.1 Common commands

```bash
# check a Pod's restart count
kubectl get pod <pod>
# RESTARTS column shows the count

# check the previous container's logs
kubectl logs <pod> --previous

# check the events
kubectl describe pod <pod>
# look at the restart history in "Events"

# check the container's last state
kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[*].lastState}'
# shows terminated: { reason: OOMKilled | Error | Completed, exitCode: 137 }
```

### 13.2 The "container restart loop" checklist

```bash
# 1. Why did the container exit?
kubectl logs <pod> --previous
# look for error messages, stack traces

# 2. Is the liveness probe killing it?
kubectl describe pod <pod>
# look at recent events: "Liveness probe failed"

# 3. Is the container OOM-killing?
kubectl describe pod <pod>
# look at "Last State": reason: OOMKilled

# 4. Is the restart count growing?
kubectl get pod <pod>
# RESTARTS column
# if it's growing, the container is in a restart loop
```

### 13.3 The "container won't restart" case

A container exited and isn't restarting. This happens with `OnFailure` and exit code 0, or with `Never`.

```bash
# check the Pod's phase
kubectl get pod <pod> -o jsonpath='{.status.phase}'
# Succeeded = exited 0, not restarted (OnFailure)
# Failed = exited non-zero, not restarted (Never)
# Running = still running
```

## 14. Gotchas and Common Mistakes

### 14.1 The 25+ common mistakes

1. **`Always` is the default for any Pod without explicit `restartPolicy`.** Even bare Pods use it. Job's Pods override to `OnFailure`.

2. **Init containers always run to completion.** They don't have a `restartPolicy`. The Pod's `restartPolicy` controls what happens when an init container fails.

3. **`OnFailure` restarts on any non-zero exit code.** Including 137 (OOM) and 143 (SIGTERM). If you don't want to restart on OOM, use `Never` and handle restarts elsewhere.

4. **`OnFailure` does NOT restart on exit 0.** The container is "succeeded" and the Pod's phase is `Succeeded`. The Pod stays in the cluster (until the controller deletes it).

5. **`Never` does not retry.** A single failure = Pod Failed. No automatic retry.

6. **The restart backoff caps at 5 min.** A container in CrashLoopBackOff will restart every 5 min after the cap. **Use this to your advantage** — if you have a flaky app, the backoff prevents a tight restart loop.

7. **The backoff resets after 10 min of successful running.** A container that runs for 10 min has its backoff cleared. The next crash starts a new backoff cycle.

8. **Container restart is not a Pod restart.** The Pod's IP is the same. The container's filesystem may be preserved (depending on volumes). External disruption is minimal.

9. **The kubelet is the only thing that restarts containers.** The apiserver doesn't. Other controllers don't. The kubelet watches the container and restarts it locally.

10. **The kubelet's restart is at the container level, not the Pod.** For Pod-level restart, the controller (Deployment, etc.) creates a new Pod.

11. **The liveness probe failure is treated as a kill.** The kubelet kills the container (SIGKILL, exit 137) and restarts it. The container's `preStop` hook does **not** run on liveness failure.

12. **The readiness probe failure is not a kill.** The kubelet removes the Pod from the Service's endpoints. The container keeps running.

13. **A liveness probe that's too strict causes restarts.** Use a stable check, not a "is everything perfect" check.

14. **The `preStop` hook has its own `terminationGracePeriodSeconds` semantics.** The preStop runs, then the kubelet sends SIGTERM, then waits for graceful exit.

15. **The container's `terminationMessagePath` captures the last log lines.** If the container crashed, the last few lines of output are in `/dev/termination-log` (or similar). The kubelet reads them and shows them in `kubectl describe pod`.

16. **A Job with `restartPolicy: Always` will never complete.** Because it restarts on success (exit 0). Always use `OnFailure` or `Never` for Jobs.

17. **A Pod with `restartPolicy: Never` and an init container that fails** will be in a permanent fail state. The init container is not retried. Delete the Pod to retry.

18. **A `DaemonSet`'s Pods use `Always`.** When a node dies, the DS Pod dies. When the node returns, the DS Pod is recreated. The DS controller handles the recreation, not the kubelet's restart.

19. **The kubelet's restart is per-container.** A multi-container Pod's containers restart independently. If one container is in CrashLoopBackOff, the others can be running fine.

20. **The kubelet doesn't restart containers that were killed by the user** (e.g. `kubectl exec ... kill 1`). The kubelet treats user-initiated kills as intentional.

21. **A liveness probe with `initialDelaySeconds: 0` and `failureThreshold: 1` is very aggressive.** A slow-starting app will fail the probe immediately on startup, get killed, restart, fail again. The backoff helps, but the right fix is to give the app time to start.

22. **A Job's `backoffLimit` is on the Pod, not the container.** The Job counts Pod failures. A Pod that restarts its container 100 times is 1 Pod failure.

23. **A CronJob's `successfulJobsHistoryLimit` and `failedJobsHistoryLimit`** cap the number of old Jobs kept. Default 3 and 1. Set higher if you want history.

24. **The container's `image` is immutable** — it can't be changed without recreating the Pod. The `restartPolicy` doesn't help here.

25. **The `restartPolicy` is set at Pod creation.** You can't change it on a running Pod. You have to delete and recreate the Pod.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource Requests & Limits]] — OOM-kill is a major cause of restarts
* [[Kubernetes/concepts/L03-workloads/01-pods|Pods]] — what restart policy applies to
* [[Kubernetes/concepts/L03-workloads/02-replicasets|ReplicaSets]] — the controllers that create Pods
* [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — readiness probes affect Service routing

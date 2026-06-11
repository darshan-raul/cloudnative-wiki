---
title: CrashLoopBackOff
tags:
  - Kubernetes
  - Troubleshooting
  - Pods
---

The most common pod failure mode. A container starts, exits with an error, the kubelet restarts it (per `restartPolicy`), it exits again, and after a few cycles the kubelet gives up for a while before retrying. The pod's status reads `CrashLoopBackOff`.

## Symptoms

```bash
$ kubectl get pods
NAME          READY   STATUS             RESTARTS   AGE
web-1         0/1     CrashLoopBackOff   8          5m
api-2         0/1     CrashLoopBackOff   12         10m
worker-3      0/1     CrashLoopBackOff   3          2m
```

The `RESTARTS` column is your first signal — anything > 0 means the container has been restarted at least once. The longer the pod has been alive, the more worrying a high restart count is.

```bash
$ kubectl get pods -o wide
NAME     READY   STATUS             RESTARTS   AGE   NODE       NOMINATED
web-1    0/1     CrashLoopBackOff   8          5m    node-2     <none>
```

## The 30-second diagnosis

```bash
# 1. describe — events and reason
kubectl describe pod web-1 | tail -30

# 2. current logs
kubectl logs web-1

# 3. previous container logs (after a crash, the previous instance's logs are kept)
kubectl logs web-1 --previous

# 4. all containers (multi-container pods)
kubectl logs web-1 --all-containers --previous

# 5. events
kubectl get events --field-selector involvedObject.name=web-1
```

**`kubectl logs --previous`** is the killer command. The first thing to check on any CrashLoopBackOff.

## The backoff schedule

The kubelet doesn't restart immediately. It uses **exponential backoff**:

```
Restart #1: 10s after start
Restart #2: 20s
Restart #3: 40s
Restart #4: 80s
Restart #5: 160s
Restart #6: 320s
Cap: 5 minutes between restarts
```

This is why a pod in CrashLoopBackOff often sits for a while between restarts — it's the kubelet backing off. **If you see `RESTARTS=8` and `AGE=5m`, something has been crashing for 5 minutes.**

You can force a fresh restart attempt by deleting the pod (the controller will recreate it):

```bash
kubectl delete pod web-1     # forces an immediate re-attempt
```

Useful when you've fixed the issue and don't want to wait for the backoff timer.

## The taxonomy of causes

CrashLoopBackOff has six root cause categories:

```
┌──────────────────────────────────────────────────────────────┐
│                   CrashLoopBackOff                           │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. App error           (your code, your config)             │
│  2. Bad image           (corrupt, missing entrypoint)        │
│  3. Missing config      (env var, secret, ConfigMap not set) │
│  4. Resource limits     (OOMKilled, CPU throttled to death)  │
│  5. Volume issues       (PVC not bound, mount path conflict) │
│  6. Liveness probe      (probe is too aggressive, app is     │
│                          slow to start)                      │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

Each has a distinct signature. The sections below walk through all six.

## 1. App error

The most common. The container starts, runs your code, hits an unhandled exception or `os.Exit(1)`.

**Signatures:**

```bash
$ kubectl logs web-1
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x...]
goroutine 1 [running]:
main.main()
    /app/main.go:42 +0x...
```

```bash
$ kubectl logs web-1
Traceback (most recent call last):
  File "/app/server.py", line 12, in <module>
    from config import load
ModuleNotFoundError: No module named 'config'
```

```bash
$ kubectl logs web-1
Exception in thread "main" java.lang.NullPointerException
    at com.example.App.run(App.java:42)
```

**The exit code matters.** A non-zero exit code triggered the crash. Look at the container's exit code:

```bash
$ kubectl describe pod web-1 | grep -A 5 "Last State"
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Mon, 15 Jan 2024 10:00:00
      Finished:     Mon, 15 Jan 2024 10:00:02
```

Common exit codes:
- `1` — generic application error
- `2` — misuse of shell builtins (often: missing argument, bad flag)
- `126` — command found but not executable (file permission issue)
- `127` — command not found (missing binary, wrong entrypoint)
- `137` — `128 + 9` (SIGKILL) — usually OOMKill
- `139` — `128 + 11` (SIGSEGV) — segfault
- `143` — `128 + 15` (SIGTERM) — graceful shutdown signal received

**Diagnosis:** Read the logs. The error is almost always in there.

**Fix:** Fix the code or the config that caused the error.

**Most common sub-causes:**

1. **Missing environment variable** — your app reads `DATABASE_URL` from env, env isn't set, app fails.
   ```bash
   $ kubectl logs web-1
   KeyError: 'DATABASE_URL'
   ```
   Fix: set the env var in the spec, or in a ConfigMap/Secret that's mounted.

2. **Bad config** — `config.yaml` has a typo, or points to a non-existent endpoint.
   ```bash
   $ kubectl logs web-1
   failed to load config: open /etc/web/config.yaml: no such file or directory
   ```
   Fix: check the ConfigMap, check the volume mount path.

3. **Missing dependency** — app expects a sidecar (Redis, postgres) that isn't there.
   ```bash
   $ kubectl logs web-1
   dial tcp 10.96.0.42:5432: connect: connection refused
   ```
   Fix: add the dependency, or wait for it (init container, init script).

4. **Code bug** — unhandled edge case, race condition, panic.
   ```bash
   $ kubectl logs web-1
   IndexOutOfRangeException at line 42
   ```
   Fix: fix the code.

## 2. Bad image

The container image itself is broken — wrong entrypoint, missing binary, wrong architecture.

**Signatures:**

```bash
$ kubectl describe pod web-1 | grep -A 3 "Events:"
Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Normal   Pulled     30s   kubelet            Successfully pulled image "myorg/web:v2"
  Normal   Created    30s   kubelet            Created container web
  Normal   Started    30s   kubelet            Started container web
  Warning  BackOff    10s   kubelet            Back-off restarting failed container
```

```bash
$ kubectl logs web-1
exec /app/server: exec format error
```

`exec format error` means you built the image for the wrong CPU architecture. e.g., you built on ARM (M1 Mac) and deployed to AMD64 nodes.

```bash
$ kubectl logs web-1
/app/entrypoint.sh: line 5: /app/server: not found
```

`not found` (with exit 127) means the entrypoint points to a binary that isn't in the image.

**Diagnosis:**

```bash
# inspect the image locally
docker run --rm -it myorg/web:v2 /bin/sh    # can you shell in?
docker inspect myorg/web:v2 | jq '.[0].Config.Entrypoint, .[0].Config.Cmd'
docker inspect myorg/web:v2 | jq '.[0].Architecture'    # should be amd64 or arm64
```

**Common sub-causes:**

1. **Wrong entrypoint** — Dockerfile's `ENTRYPOINT` doesn't exist in the image.
   ```dockerfile
   # bad
   COPY server /app/server
   ENTRYPOINT ["/app/server"]
   # but you forgot the COPY
   ```

2. **Wrong architecture** — built on M1 Mac (arm64), deploying to Linux x86 cluster.
   ```bash
   # rebuild with explicit platform
   docker buildx build --platform linux/amd64 -t myorg/web:v2 .
   # or in the multi-arch build
   docker buildx build --platform linux/amd64,linux/arm64 -t myorg/web:v2 .
   ```

3. **Wrong base image** — `FROM alpine:3.20` doesn't have `glibc` and your Go binary needs it.
   ```bash
   $ kubectl logs web-1
   /app/server: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.34' not found
   ```
   Fix: use `FROM ubuntu:22.04` or a static binary.

4. **Shell script not executable** — `ENTRYPOINT ["./run.sh"]` but the file isn't `chmod +x`'d.
   ```bash
   $ kubectl logs web-1
   exec ./run.sh: permission denied
   ```
   Fix: `RUN chmod +x run.sh` in Dockerfile, or invoke via `ENTRYPOINT ["sh", "./run.sh"]`.

## 3. Missing config

The container starts, but can't find config it needs at runtime. Similar to "App error" but the issue is at the **infra** layer — ConfigMap/Secret isn't there, or volume mount is wrong.

**Signatures:**

```bash
$ kubectl describe pod web-1
Events:
  Warning  FailedMount  30s  kubelet  Unable to attach or mount volumes: unmounted volumes=[config], unattached volumes=[config]: timed out waiting for the condition
```

```bash
$ kubectl describe pod web-1
Events:
  Warning  FailedScheduling  30s  default-scheduler  persistentvolumeclaim "data" not found
```

```bash
$ kubectl logs web-1
Error: could not read config file /etc/web/config.yaml: open /etc/web/config.yaml: no such file or directory
```

**Diagnosis:**

```bash
# 1. Check what ConfigMaps/Secrets exist in the namespace
kubectl get cm,secret -n my-ns

# 2. Check what the pod expects
kubectl get pod web-1 -o yaml | grep -A 5 "volumes:"

# 3. Check if a referenced ConfigMap actually has the key
kubectl get cm web-config -o jsonpath='{.data}' | jq .

# 4. Check events for FailedMount, FailedBinding
kubectl describe pod web-1 | grep -A 3 "Warning"
```

**Common sub-causes:**

1. **ConfigMap doesn't exist** — typo in `configMapRef.name`.
   ```yaml
   volumes:
   - name: config
     configMap:
       name: web-config   # if this doesn't exist, pod hangs at "ContainerCreating"
   ```

2. **Key doesn't exist in ConfigMap** — `configMapRef.items[].key` references a key that's not in the ConfigMap.
   ```yaml
   volumes:
   - name: config
     configMap:
       name: web-config
       items:
       - key: config.yaml    # if this key isn't in web-config, mount fails
         path: config.yaml
   ```

3. **Secret decryption failed** — encrypted Secret (Sealed Secrets, ESO, KMS) failed to decrypt.
   ```bash
   $ kubectl describe pod web-1
   Warning  FailedMount  30s  kubelet  MountVolume.SetUp failed for volume "secret-vol" :
   secret "db-credentials" not found
   ```

4. **Permission denied on volume** — `defaultMode` doesn't allow the app's UID to read.
   ```bash
   $ kubectl exec -it web-1 -- ls -la /etc/web
   -r--------  1 root root  1234 Jan 15 10:00 config.yaml
   # but the app runs as UID 1000 and can't read root-owned 0600
   ```
   Fix: set `defaultMode: 0644` on the volume, or run as root, or set the file's group to the app's GID.

## 4. Resource limits

The container starts, runs, gets killed because it exceeded a limit. **OOMKilled** is the most common form of CrashLoopBackOff.

**Signatures:**

```bash
$ kubectl describe pod web-1 | grep -A 5 "Last State"
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Mon, 15 Jan 2024 10:00:00
      Finished:     Mon, 15 Jan 2024 10:00:30
```

```bash
$ kubectl describe pod web-1 | grep -A 5 "Last State"
    Last State:     Terminated
      Reason:       Error
      Exit Code:    137
```

Exit code `137` = `128 + 9` = SIGKILL. Could be OOMKilled, could be evicted by the kubelet, could be `kubectl delete pod` from somewhere.

**Confirm OOM by checking the OOM events on the node:**

```bash
# on the node where the pod ran
sudo dmesg | grep -i "killed process" | tail
# or
sudo journalctl -k | grep -i "out of memory" | tail
```

**Or look at metrics-server:**

```bash
kubectl top pods
# NAME    CPU(cores)   MEMORY(bytes)
# web-1   50m          900Mi
# but your limit is 512Mi → OOMKill
```

**Diagnosis:**

```bash
# 1. What are the limits?
kubectl get pod web-1 -o jsonpath='{.spec.containers[0].resources}' | jq .

# 2. What was the actual usage right before crash?
# (if you have Prometheus, check container_memory_working_set_bytes)
# (otherwise, increase the limit and watch)

# 3. JVM-specific: -Xmx must fit inside the memory limit
#    if you set memory limit = 512Mi and the JVM starts with -Xmx4g, you OOM
```

**Common sub-causes:**

1. **Memory limit too low.** App legitimately needs more.
   ```yaml
   resources:
     limits:
       memory: 256Mi   # too low
   ```
   Fix: increase the limit (or fix the leak).

2. **JVM heap not configured for the limit.** JVMs default to 1/4 of host memory for `-Xmx`. If your container limit is 1Gi, the JVM may try to use 1/4 of node memory (e.g. 16Gi on a 64Gi node), exceeding the cgroup limit → OOMKill.
   ```bash
   # fix: set -Xmx explicitly to a value below the limit
   env:
   - name: JAVA_OPTS
     value: "-Xmx400m"   # less than 512Mi limit, leave headroom for non-heap
   ```

3. **Memory leak.** App allocates more and more over time, eventually hits the limit.
   ```bash
   # watch memory grow
   watch -n 1 'kubectl top pod web-1'
   ```
   Fix: profile the app, find the leak.

4. **CPU throttling.** Not a crash, but can look like one. App becomes so slow it can't respond to liveness probes.
   ```bash
   # check throttling (Prometheus)
   rate(container_cpu_cfs_throttled_seconds_total[5m])
   ```
   Fix: raise the CPU limit (or remove the limit entirely if you have node-level isolation).

5. **Ephemeral storage limit.** Container writes to `/tmp` or its working dir until it hits the limit.
   ```bash
   $ kubectl describe pod web-1
   Reason:   Error
   Exit Code: 137
   Message:  container exceeded its ephemeral storage limit
   ```
   Fix: set `ephemeral-storage` limit, or clean up `/tmp`.

## 5. Volume issues

The pod can't start because volumes aren't binding, or mounts are misconfigured.

**Signatures:**

```bash
$ kubectl describe pod web-1
Events:
  Warning  FailedScheduling  30s  default-scheduler  persistentvolumeclaim "data" not found
```

```bash
$ kubectl describe pod web-1
Events:
  Warning  FailedMount  30s  kubelet  Unable to attach or mount volumes: unmounted volumes=[data], unattached volumes=[data]: timed out waiting for the condition
```

```bash
$ kubectl describe pod web-1
Events:
  Warning  FailedBinding  30s  default-scheduler  persistentvolumeclaim "data" pending
```

The pod sits in `ContainerCreating` indefinitely, then the kubelet may eventually mark it as failed and CrashLoopBackOff kicks in.

**Diagnosis:**

```bash
# 1. Check the PVC
kubectl get pvc -n my-ns
# NAME    STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# data    Pending                                      gp3            5m

# 2. Why is the PVC pending?
kubectl describe pvc data -n my-ns
# Events:
#   Warning  ProvisioningFailed  45s  external-provisioner  failed to provision volume: ...
```

**Common sub-causes:**

1. **StorageClass doesn't exist.** `spec.storageClassName: gp3-encrypted` but the cluster only has `gp2`.
   ```bash
   kubectl get sc
   # NAME            PROVISIONER
   # gp2             kubernetes.io/aws-ebs
   # no gp3-encrypted
   ```

2. **No matching PV (for static provisioning).** PVC asks for 100Gi, only 50Gi PVs available.
   ```bash
   kubectl get pv
   # NAME     CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS
   # pv-001   50Gi       RWO            Delete           Available
   ```

3. **ReadWriteOnce on a multi-node deployment.** RWX volumes required for multi-pod, but you asked for RWO.
   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   spec:
     accessModes:
     - ReadWriteOnce    # but the Deployment has 3 replicas
   ```

4. **Volume mount path is read-only.** You mount a ConfigMap to `/etc/config`, and the app tries to write to it.
   ```bash
   $ kubectl logs web-1
   failed to write /etc/config/state.json: read-only file system
   ```

5. **subPath collision.** Two containers mount different things to the same path, or you mount to `/` and the container has its own content there.
   ```yaml
   volumeMounts:
   - name: config
     mountPath: /app/config.yaml
     subPath: config.yaml    # good — single file mount
   # vs
   - name: config
     mountPath: /app        # bad — overwrites everything in /app
   ```

## 6. Liveness probe

Your liveness probe is too aggressive. The app is slow to start, the probe fails, the kubelet kills the container, the cycle continues.

**Signatures:**

```bash
$ kubectl describe pod web-1 | grep -A 10 "Events:"
Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Normal   Pulled     30s   kubelet            Successfully pulled image
  Normal   Created    30s   kubelet            Created container
  Normal   Started    30s   kubelet            Started container
  Warning  Unhealthy  25s   kubelet            Liveness probe failed: HTTP 503
  Warning  Killing    25s   kubelet            Killing container
  Warning  BackOff    20s   kubelet            Back-off restarting failed container
```

The `Unhealthy` event is the smoking gun. The kubelet killed the container because the liveness probe returned non-success.

**Diagnosis:**

```bash
# 1. What does the liveness probe check?
kubectl get pod web-1 -o jsonpath='{.spec.containers[0].livenessProbe}' | jq .

# 2. What does the app say when the probe fires?
kubectl logs web-1 --previous
# look for messages around the time the probe fired

# 3. Test the probe manually
kubectl exec -it web-1 -- curl -s http://localhost:8080/health
# (assuming your probe hits /health on port 8080)
```

**Common sub-causes:**

1. **`initialDelaySeconds` is too low.** App takes 30s to start; probe checks at 10s.
   ```yaml
   livenessProbe:
     initialDelaySeconds: 10    # too low for slow-starting apps
     periodSeconds: 10
   ```
   Fix: increase `initialDelaySeconds`, **or** use a `startupProbe` to give the app a window to start.

2. **Probe checks a too-strict endpoint.** App returns 200 on `/health` only when fully ready; probe checks `/health` during startup when it returns 503.
   ```yaml
   livenessProbe:
     httpGet:
       path: /health    # too strict — try /ready vs /health
       port: 8080
   ```
   Fix: have a dedicated `/alive` endpoint that's permissive; `/ready` for readiness.

3. **`failureThreshold` is too low.** One failure kills the pod. Network blip → probe fails → pod killed.
   ```yaml
   livenessProbe:
     failureThreshold: 1   # one failure = death
     periodSeconds: 10
   ```
   Fix: `failureThreshold: 3` (3 consecutive failures).

4. **Probe is too slow.** Probe itself takes longer than `timeoutSeconds`, always times out.
   ```yaml
   livenessProbe:
     timeoutSeconds: 1   # probe takes 5s
   ```
   Fix: increase `timeoutSeconds` or speed up the probe.

5. **App is genuinely unhealthy.** Probe correctly reports the app is broken.
   - This is the "liveness probe doing its job" case. Fix the app.

**Use `startupProbe` for slow-starting apps:**

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8080
  periodSeconds: 5
  failureThreshold: 30    # 30 * 5s = 150s for the app to start
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  periodSeconds: 10
  failureThreshold: 3     # after startup, kill after 3 failures
```

`startupProbe` gives the app a generous window to start, then liveness takes over. The kubelet only checks liveness once `startupProbe` succeeds.

## Force a re-attempt

If you've fixed the issue (or just want to retry without waiting for backoff):

```bash
# delete the pod (the controller will recreate it)
kubectl delete pod web-1

# restart a Deployment (rolls out all pods)
kubectl rollout restart deployment/web

# scale to zero and back
kubectl scale deployment/web --replicas=0
kubectl scale deployment/web --replicas=3
```

`kubectl rollout restart` is the right tool for `Deployment`s. It increments the `pod-template-hash` annotation, triggering a new ReplicaSet.

## The "is it OOM or is it the app?" test

Hard to tell from exit code 137 alone. Three reliable tests:

```bash
# 1. Check events on the node
kubectl get events -A --field-selector reason=OOMKilling | head
# or, on the node:
sudo dmesg | grep -i "killed process" | tail

# 2. Check cgroup memory.max vs actual usage
#    (if you can get a shell into the node)
CONTAINER_ID=$(crictl ps --name web -q)
cat /sys/fs/cgroup/memory/kubepods/.../$CONTAINER_ID/memory.peak
cat /sys/fs/cgroup/memory/kubepods/.../$CONTAINER_ID/memory.max

# 3. Watch memory grow
kubectl exec web-1 -- cat /proc/meminfo | grep -i available
# (inside the pod, repeatedly)
```

## The "is it the image?" test

Strip the app to a minimal container and see if the same pod spec works:

```bash
# override the image with a known-good one (e.g., busybox, alpine)
kubectl edit pod web-1
# change image: myorg/web:v2
# to:          busybox:latest
# change command: ["/bin/sh", "-c", "sleep 3600"]
# save
```

If the busybox pod stays up, the problem is in the original image. If it also fails, the problem is in the pod spec (volume, config, etc.).

You can do this for Deployments too, but you'll fight the controller. Easiest with a one-off Pod.

## The "is it the node?" test

Schedule the pod on a specific node (or exclude a suspect node):

```bash
# force to a specific node
kubectl edit pod web-1
# add to spec:
#   nodeName: node-2

# exclude a node
kubectl cordon node-1
# now no new pods schedule on node-1
```

If the pod runs on node-2 but not node-1, the issue is node-1 (kernel, disk, network).

## Common gotchas

* **`kubectl logs` is empty.** The container wrote to stderr, or never started. Try `kubectl logs --previous`. If still empty, it's an image problem (image didn't start, no logs to read).
* **The error is in the application, not k8s.** CrashLoopBackOff is just a state. The actual error is in the app. Logs are the only place to find it.
* **Restart policy is `Never`.** For `Job`s and `Pod`s with `restartPolicy: Never`, the pod won't restart — it just shows `Error`. CrashLoopBackOff is a `restartPolicy: Always` thing.
* **Init containers fail separately.** A pod with init containers that fail shows `Init:Error` or `Init:CrashLoopBackOff`, not the regular `CrashLoopBackOff`. The diagnosis is the same; the location is different.
* **The probe is fine; the app is the problem.** Don't keep tweaking the probe to make the symptoms go away. Fix the app.
* **`initContainers` are the silent killer.** A failing init container makes the pod sit in `Init:Error`. Use `kubectl describe pod` to see the init container's status.
* **Sidecar containers (k8s 1.28+)** have a different lifecycle — they restart independently. A failing sidecar can be a `CrashLoopBackOff` even if the main container is fine.
* **Container `restartCount` is the truth.** The `RESTARTS` column in `kubectl get pods` is the container's restart count. If it's climbing, the container is being killed. If it's stable, the pod is in a non-restart state.
* **Don't set `restartPolicy: Always` on a `Job`.** Jobs use `restartPolicy: OnFailure` or `Never`. Using `Always` makes the Job controller treat the pod as a long-running workload, breaking the Job.

## A worked example

```bash
$ kubectl get pods
NAME    READY   STATUS             RESTARTS   AGE
web-1   0/1     CrashLoopBackOff   5          3m

$ kubectl describe pod web-1 | tail -20
Events:
  Type     Reason   Age                From     Message
  ----     ------   ----               ----     -------
  Normal   Pulled   3m                 kubelet  Successfully pulled image "myorg/web:v2"
  Normal   Created  3m                 kubelet  Created container web
  Normal   Started  3m                 kubelet  Started container web
  Warning  BackOff  30s (x4 over 3m)   kubelet  Back-off restarting failed container

$ kubectl logs web-1 --previous
2024-01-15 10:00:00 [INFO] web server starting on :8080
2024-01-15 10:00:01 [INFO] connecting to database at postgres:5432
2024-01-15 10:00:02 [ERROR] failed to connect: dial tcp 10.96.0.42:5432: connect: connection refused
2024-01-15 10:00:02 [FATAL] exiting

$ kubectl get svc -n my-ns
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)
postgres   ClusterIP   10.96.0.42   <none>        5432/TCP

$ kubectl get pods -n my-ns -l app=postgres
NAME                       READY   STATUS    RESTARTS   AGE
postgres-1                 1/1     Running   0          4h
postgres-2                 0/1     Pending   0          5m   <-- this one

$ kubectl describe pod postgres-2 -n my-ns
Events:
  Warning  FailedScheduling  5m  default-scheduler  0/3 nodes are available:
    insufficient cpu, insufficient memory, 1 node(s) had taint {node.kubernetes.io/disk-pressure: }

# Aha! Postgres can't schedule, so web can't connect to it.
```

The web pod was "crashing" but the root cause was upstream — postgres wasn't running, and the web app's retry logic exited after 3 attempts.

## See also

* [[Kubernetes/guides/tools/kubectl|kubectl]] — the commands you need
* [[Kubernetes/guides/tools/k9s|k9s]] — fast visual diagnosis
* [[Kubernetes/guides/troubleshooting/pod-pending|pod-pending]] — pods that won't schedule
* [[Kubernetes/guides/troubleshooting/image-pull|image-pull]] — image pull failures
* [[Kubernetes/guides/troubleshooting/service-unreachable|service-unreachable]] — networking issues
* [[Kubernetes/guides/troubleshooting/dns-resolution|dns-resolution]] — name resolution failures

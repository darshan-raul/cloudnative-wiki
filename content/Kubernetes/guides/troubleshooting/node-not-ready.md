---
title: Node Not Ready
tags:
  - Kubernetes
  - Troubleshooting
  - Nodes
---

A `NotReady` node can't run new pods, and the pods on it can become unreachable. This is a **node-level** problem — the kubelet can't communicate with the control plane, or the node has a critical condition.

## Symptoms

```bash
$ kubectl get nodes
NAME      STATUS     ROLES                  AGE   VERSION
node-1    Ready      <none>                 30d   v1.29.0
node-2    NotReady   <none>                 30d   v1.29.0
node-3    Ready      <none>                 30d   v1.29.0
```

```bash
$ kubectl describe node node-2 | tail -30
Conditions:
  Type             Status    Reason               Message
  ----             ------    ------               -------
  Ready            False     KubeletNotReady      [KUBERNETES] PLEG is not healthy
  MemoryPressure   False
  DiskPressure     False
  PIDPressure      False
  NetworkUnavailable False
```

Pods on `node-2`:
- Still running, but new pods won't schedule there
- Service endpoints for those pods may be removed if their readiness probes fail
- Pods that try to reach out may fail if networking is broken

## The 30-second diagnosis

```bash
# 1. what's the node's status?
kubectl get node node-2 -o yaml | grep -A 20 "conditions:"

# 2. can the kubelet reach the apiserver?
#    (this is checked implicitly — if the node is NotReady, often it can't)

# 3. is the kubelet running on the node?
ssh node-2
$ systemctl status kubelet
$ journalctl -u kubelet --tail=100

# 4. what are the node's conditions?
kubectl describe node node-2 | grep -A 5 "Conditions:"

# 5. resource pressure?
kubectl describe node node-2 | grep -A 2 "Allocated resources:"
```

## The taxonomy of NotReady

```
┌──────────────────────────────────────────────────────────────┐
│                     Node NotReady                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Kubelet not running       (process dead, not starting)   │
│  2. Kubelet can't reach apiserver (network, TLS, RBAC)       │
│  3. PLEG (Pod Lifecycle Event Generator) unhealthy           │
│  4. Disk pressure             (out of disk)                  │
│  5. Memory pressure           (under memory cgroup)         │
│  6. PID pressure              (too many processes)           │
│  7. Network unavailable       (CNI not running on node)      │
│  8. Clock skew                (cert validation fails)         │
│  9. Node-controller timeout    (over 5min of no heartbeats)   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 1. Kubelet not running

The kubelet process is dead, restarting, or not installed. Without it, the node can't run pods.

**Signatures:**

```bash
$ kubectl describe node node-2 | tail -5
Conditions:
  Type    Status  Reason             Message
  Ready   False   KubeletNotReady    container runtime is not running
```

```bash
# on the node
$ systemctl status kubelet
● kubelet.service - kubelet: The Kubernetes Node Agent
   Loaded: loaded (/lib/systemd/system/kubelet.service; enabled)
   Active: activating (auto-restart) (Result: exit-code) since Mon 2024-01-15 10:00:00
  Process: 12345 ExecStart=/usr/bin/kubelet (code=exited, status=1/FAILURE)
```

**Diagnosis:**

```bash
# 1. kubelet logs
ssh node-2
$ journalctl -u kubelet --tail=200
$ sudo journalctl -xe

# 2. kubelet config
$ cat /var/lib/kubelet/config.yaml
$ cat /etc/kubernetes/kubelet.conf  (bootstrap kubeconfig)
$ cat /var/lib/kubelet/kubeconfig  (real kubeconfig)

# 3. is the binary even there?
$ which kubelet
$ /usr/bin/kubelet --version
```

**Common sub-causes:**

1. **kubelet can't read its config.**
   ```bash
   $ journalctl -u kubelet --tail=50
   failed to load kubelet config file /var/lib/kubelet/config.yaml:
     open /var/lib/kubelet/config.yaml: permission denied
   ```
   Fix: `chown` the file, or run as the right user.

2. **kubelet config has a typo.**
   ```bash
   failed to parse kubelet flags: invalid value "127.0.0.1" for flag -port:
     port must be a number between 1 and 65535
   ```

3. **Container runtime is dead.** kubelet needs containerd/CRI-O. If that's dead, kubelet can't run pods.
   ```bash
   $ systemctl status containerd
   ● containerd.service - containerd container runtime
      Active: inactive (dead)
   ```

4. **The kubelet service is disabled.** After a reboot, the kubelet doesn't auto-start.
   ```bash
   $ systemctl is-enabled kubelet
   disabled
   ```
   Fix: `systemctl enable kubelet`.

5. **kubelet version mismatch with apiserver.** If kubelet is on v1.28 and apiserver is on v1.30, you can get a skew violation.
   ```bash
   failed to register node: ... node version v1.28.0 is not supported
   ```

**Fix:** restart kubelet, fix the config, fix the runtime.

```bash
ssh node-2
$ sudo systemctl restart kubelet
$ sudo journalctl -u kubelet --tail
```

## 2. Kubelet can't reach the apiserver

The kubelet is running, but it can't talk to the apiserver. Without that, it can't register or send heartbeats.

**Signatures:**

```bash
$ kubectl describe node node-2 | tail
Conditions:
  Type    Status  Reason             Message
  Ready   False   KubeletNotReady    failed to contact API server
```

```bash
# on the node
$ journalctl -u kubelet --tail=100
E0115 10:00:00.000    12345 kubelet.go:2342] "Error getting node" err="... client: etcd cluster is unavailable or misconfigured"
```

**Diagnosis:**

```bash
# 1. can the node reach the apiserver?
ssh node-2
$ curl -k https://<apiserver-endpoint>:6443/healthz
# should return "ok"

# 2. check the kubelet's bootstrap kubeconfig
$ cat /var/lib/kubelet/kubeconfig
# server, certificate-authority-data, token

# 3. is the apiserver reachable from the node?
$ nc -zv <apiserver-ip> 6443
$ traceroute <apiserver-ip>
```

**Common sub-causes:**

1. **TLS cert expired.** The kubelet's client cert is good for 1 year. After that, it can't auth.
   ```bash
   $ journalctl -u kubelet | grep -i "x509"
   x509: certificate has expired or is not yet valid
   ```
   Fix: re-issue the cert. With managed clusters (EKS, GKE, AKS), the cloud handles this. With kubeadm, run `kubeadm cert renew`.

2. **Network partition.** Node can't reach the apiserver due to firewall, security group, or routing.
   ```bash
   $ nc -zv <apiserver> 6443
   nc: connect to <apiserver> port 6443 (tcp) timed out
   ```

3. **Wrong apiserver endpoint.** The kubelet was bootstrapped with the wrong `--kubeconfig` or `--api-servers` flag.
   ```yaml
   # /var/lib/kubelet/config.yaml
   apiVersion: kubelet.config.k8s.io/v1beta1
   kind: KubeletConfiguration
   ...
   # the apiServer endpoint is implicit, derived from the kubeconfig
   ```

4. **DNS broken on the node.** The apiserver endpoint is a DNS name, and the node can't resolve it.
   ```bash
   $ nslookup <apiserver-dns-name>
   # fails
   ```

5. **Proxy required but not configured.** The node is behind a corporate proxy, and the kubelet doesn't have `HTTPS_PROXY` set.
   ```bash
   $ journalctl -u kubelet | grep -i "proxy"
   ```

**Fix:** depending on the cause, renew certs, fix networking, or fix the kubeconfig.

## 3. PLEG unhealthy

PLEG (Pod Lifecycle Event Generator) is the kubelet's component that watches containers. If PLEG is unhealthy, the kubelet doesn't know the state of pods, marks itself NotReady.

**Signatures:**

```bash
$ kubectl describe node node-2 | tail
Conditions:
  Type    Status  Reason             Message
  Ready   False   KubeletNotReady    PLEG is not healthy
```

```bash
# on the node
$ journalctl -u kubelet | tail
PLEG: ... relist time exceeded 3m0s
```

**Diagnosis:**

```bash
# 1. check the relist time on the node
ssh node-2
$ journalctl -u kubelet | grep "relist time"

# 2. check container runtime
$ crictl ps
# if this hangs, the runtime is stuck
```

**Common sub-causes:**

1. **Container runtime is slow or stuck.** PLEG relies on the CRI to list containers. If CRI is slow (high load, kernel issues), PLEG can't keep up.
   ```bash
   $ time crictl ps
   real    4m30s   <-- should be milliseconds
   ```

2. **Too many containers on the node.** PLEG relists all containers; with 1000+ containers, it can take longer than the relist period (default 1m for PLEG, 10s for relist).
   ```bash
   $ crictl ps | wc -l
   1500
   ```
   Fix: reduce pods per node (kubelet's `--max-pods`).

3. **Syscall issues.** PLEG uses inotify; if the inotify limits are hit, PLEG fails.
   ```bash
   $ cat /proc/sys/fs/inotify/max_user_watches
   8192   <-- too low for many pods
   ```
   Fix: increase `fs.inotify.max_user_watches` in `/etc/sysctl.d/`.

4. **Kernel bugs.** Rare, but specific kernel versions have PLEG issues. Check the kernel logs.

**Fix:** restart the kubelet, fix the runtime, increase inotify limits.

## 4. Disk pressure

Node is out of disk (or projected to be). The kubelet evicts pods to free up space and marks itself NotReady.

**Signatures:**

```bash
$ kubectl describe node node-2 | tail
Conditions:
  Type             Status  Reason              Message
  Ready            False   KubeletNotReady     (also)
  DiskPressure     True    FreeDiskSpaceFailed node has disk pressure
```

```bash
# on the node
$ df -h /
$ df -h /var/lib/kubelet
$ du -sh /var/lib/containerd
$ du -sh /var/log
```

**Diagnosis:**

```bash
# 1. what's using disk?
ssh node-2
$ du -sh /var/lib/* 2>/dev/null | sort -h | tail

# 2. container image cache
$ crictl images | head
$ du -sh /var/lib/containerd

# 3. logs
$ du -sh /var/log
$ journalctl --disk-usage
```

**Common sub-causes:**

1. **Container images filling up.** Every image ever pulled is still on disk (until garbage collected).
   ```bash
   $ crictl images | wc -l
   500
   ```
   Fix: `crictl rmi --prune` to clean unused images.

2. **Container logs filling up.** A pod with verbose logging will fill the disk fast.
   ```bash
   $ du -sh /var/log/pods/
   50G
   ```
   Fix: set log rotation, reduce log verbosity.

3. **Ephemeral storage used by pods.** If pods write to `/tmp` or their working dir, that uses node disk.
   ```bash
   $ du -sh /var/lib/kubelet/pods/
   ```
   Fix: set `ephemeral-storage` limits on pods.

4. **Logs not rotated.** kubelet doesn't rotate system logs automatically.
   Fix: configure `logrotate` for `/var/log/`.

5. **The node's root disk is too small.** Some cloud defaults are 20GB; that's not enough for a busy node.
   Fix: bigger disk, or move `/var/lib/containerd` to a separate volume.

**Fix:** clean up, increase disk.

## 5. Memory pressure

Node is under memory pressure. The kubelet starts evicting pods.

**Signatures:**

```bash
$ kubectl describe node node-2 | tail
Conditions:
  Type             Status  Reason              Message
  Ready            False   KubeletNotReady
  MemoryPressure   True    FreeMemoryFailed
```

```bash
# on the node
$ free -h
$ cat /proc/meminfo | head
```

**Diagnosis:**

```bash
# 1. what's using memory?
ssh node-2
$ ps aux --sort=-%mem | head

# 2. cgroup usage
$ cat /sys/fs/cgroup/memory/memory.usage_in_bytes
$ cat /sys/fs/cgroup/memory/memory.limit_in_bytes

# 3. who is the heaviest?
$ kubectl top pods -A --sort-by=memory | head
```

**Common sub-causes:**

1. **Pods using more memory than they requested.** Even if requests match, the actual usage can spike.
   ```bash
   $ kubectl describe pod <name> | grep -A 3 "Limits"
   Limits:
     memory: 512Mi
   # but the pod is using 2Gi
   ```
   Fix: increase the limit (or fix the leak).

2. **System daemons using memory.** kubelet, kube-proxy, CNI agent, OS daemons.
   ```bash
   $ ps aux --sort=-%mem | grep -E "kubelet|kube-proxy|cilium|calico"
   ```
   Fix: increase node size, or reduce system reserved.

3. **Kernel cache pressure.** Linux uses free memory for page cache. If memory is tight, the kernel can reclaim page cache, but if there's hard pressure, it OOMs.
   ```bash
   $ cat /proc/meminfo | grep -E "MemAvailable|SwapCached"
   # MemAvailable near 0 = pressure
   ```

4. **A pod was OOMKilled and the kernel is now in a bad state.** Sometimes the kernel OOM killer goes on a spree.

**Fix:** evict pods, scale down workloads, add memory.

## 6. PID pressure

Too many processes on the node. The kubelet can't fork more.

**Signatures:**

```bash
$ kubectl describe node node-2 | tail
Conditions:
  Type             Status  Reason              Message
  Ready            False   KubeletNotReady
  PIDPressure      True    TooManyProcesses
```

```bash
# on the node
$ ps aux | wc -l
# 100000
```

**Common sub-causes:**

1. **Many pods, each with a process tree.** Each pod is a container; each container has at least one process. 200 pods = 200+ processes minimum.
2. **Fork bombs in user code.** A buggy app that forks continuously.
3. **Forking servers.** Apache, nginx prefork models.

**Fix:** reduce pods per node, fix the buggy app, raise `pid.max`.

## 7. Network unavailable

The CNI plugin isn't fully working on the node. The kubelet marks the node NetworkUnavailable.

**Signatures:**

```bash
$ kubectl describe node node-2 | tail
Conditions:
  Type                 Status  Reason              Message
  NetworkUnavailable   True    NoRouteCreated      node has no routes
```

**Diagnosis:**

```bash
# 1. CNI status
ssh node-2
$ ls /etc/cni/net.d/
$ cat /etc/cni/net.d/10-cilium.conflist

# 2. CNI pod status
kubectl get pods -n kube-system -l k8s-app=cilium -o wide | grep node-2

# 3. routes
$ ip route
$ ip link
```

**Common sub-causes:**

1. **CNI pod not running on the node.** Cilium/calico/whatever crashed.
   ```bash
   $ kubectl get pods -n kube-system -l k8s-app=cilium -o wide
   cilium-1    1/1   Running   0   ...   node-1
   cilium-2    0/1   CrashLoopBackOff   5   ...   node-2   <-- this one
   ```

2. **CNI not installed.** The CNI binaries aren't on the node.

3. **AWS VPC CNI — out of IPs in the subnet.** The pod's ENI can't be assigned.
   ```bash
   $ kubectl describe node node-2 | tail
   NetworkUnavailable   True   IPAssignFailed
   ```
   Fix: free up ENIs, add subnets, or use prefix delegation.

## 8. Clock skew

Node's clock is more than a few minutes off. TLS cert validation fails, kubelet can't auth.

**Signatures:**

```bash
# on the node
$ date
# the time is way off
```

```bash
# in kubelet logs
x509: certificate has expired or is not yet valid
```

**Diagnosis:**

```bash
# 1. compare node time to a known good source
ssh node-2
$ date
$ curl -sI http://worldtimeapi.org/api/timezone/Etc/UTC | head

# 2. is NTP/chrony running?
$ systemctl status chrony
$ chronyc tracking
```

**Fix:**

```bash
# 1. restart time sync
$ sudo systemctl restart chrony

# 2. force a sync
$ sudo chronyc makestep

# 3. or set the time manually (in emergencies)
$ sudo ntpdate pool.ntp.org
```

## 9. Node controller timeout

The node-controller in the control plane marks a node NotReady if it doesn't get heartbeats for 5 minutes (default `node-monitor-grace-period`).

This is downstream of the actual problem — if the kubelet can't heartbeat, this is the symptom.

**Diagnosis:**

```bash
# 1. how long has the node been NotReady?
kubectl get node node-2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}'

# 2. check the node-controller logs
kubectl logs -n kube-system kube-controller-manager-<master> | grep node-2
```

**Fix:** the node-controller will evict pods after `--pod-eviction-timeout` (default 5min). To bring the node back:

1. Fix the actual cause (kubelet, network, etc.)
2. Once the kubelet heartbeats again, the node-controller marks it Ready

If the node is gone for good, `kubectl delete node node-2` to clean up.

## The fix menu

| Symptom | First action |
|---------|--------------|
| `KubeletNotReady` | SSH to node, `systemctl status kubelet`, `journalctl -u kubelet` |
| `PLEG is not healthy` | Check container runtime, `crictl ps` |
| `DiskPressure` | `df -h`, clean up images and logs |
| `MemoryPressure` | `free -h`, `kubectl top pods` |
| `NetworkUnavailable` | Check CNI pod, `ip route` |
| Cert expired | `kubeadm cert renew` (or cloud-managed) |
| Clock skew | Restart NTP/chrony |

## Common gotchas

* **The node-controller evicts pods 5 minutes after the node goes NotReady.** You have a 5-minute window to fix the issue before pods get rescheduled.
* **Pods on a NotReady node still consume resources** (CPU, memory on the node). But they're not in the Service endpoints if readiness fails, so no traffic.
* **A node marked NotReady is still "there"** — the kubelet might be running but unable to communicate. Don't immediately delete the node; investigate.
* **Some node conditions are normal during startup.** A new node might briefly show `DiskPressure=True` while images are being pulled. Wait a minute and re-check.
* **Draining a node before maintenance is the right pattern** — `kubectl drain` marks it unschedulable and evicts pods gracefully. Don't just `kubectl delete node`.
* **NotReady != unschedulable.** A NotReady node is unhealthy. An unschedulable (cordoned) node is healthy but excluded. `kubectl uncordon` only works on the latter.
* **The kubelet can be running but the kubeconfig can be wrong.** The process is up, the socket is listening, but it can't register with the apiserver. Check the kubelet logs, not just the process status.
* **Custom node conditions** — operators can set custom conditions (e.g., GPU operator sets a `GPUHealthy` condition). These can mark a node NotReady if their custom logic fails.
* **`kubectl get nodes` shows the apiserver's view, not the kubelet's view.** If the node can run pods but can't reach the apiserver, it looks NotReady even though it's fine.
* **Restarting kubelet is usually safe but disruptive.** The kubelet restarts the container runtime connection, which can cause brief pod disruption. Don't do it during peak traffic.

## A worked example

```bash
$ kubectl get nodes
NAME      STATUS     ROLES                  AGE    VERSION
node-2    NotReady   <none>                 30d    v1.29.0

$ kubectl describe node node-2 | tail -10
Conditions:
  Type             Status  Reason              Message
  ----             ------  ------              -------
  Ready            False   KubeletNotReady     PLEG is not healthy
  MemoryPressure   False
  DiskPressure     True    FreeDiskSpaceFailed
  PIDPressure      False
```

Two conditions: PLEG and DiskPressure. Let me check the node.

```bash
$ ssh node-2
$ df -h /
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p1   20G   19G  1.0G  95%  /

# 95% full. Containerd has 8GB of old images
$ du -sh /var/lib/containerd
8.5G

$ crictl images | wc -l
450
```

The disk is full of old container images. The kubelet can't relist (PLEG), because PLEG uses cgroup and containerd state, and containerd is bogged down.

```bash
# clean up old images
$ sudo crictl rmi --prune

# remove unused images
$ sudo crictl images | awk '{print $3}' | xargs -I {} sudo crictl rmi {} 2>/dev/null

# restart kubelet to clear the PLEG issue
$ sudo systemctl restart kubelet
```

Wait a minute, the node should re-register:

```bash
$ kubectl get nodes
NAME      STATUS   ROLES                  AGE    VERSION
node-2    Ready    <none>                 30d    v1.29.0
```

## See also

* [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] — when pods are the problem
* [[Kubernetes/guides/troubleshooting/pod-pending|pod-pending]] — when pods can't schedule
* [[Kubernetes/guides/non-functional/high-availability|high-availability]] — preventing node failures

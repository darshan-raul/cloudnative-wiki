# Need for swapoff

*"https://kubernetes.io/docs/concepts/architecture/nodes/"*

A node with swap enabled **cannot join a Kubernetes cluster** by default. The kubelet refuses to start with `--fail-swap-on=true` (the default since k8s 1.8). This is a deliberate design choice with a long, slightly controversial history. This note explains the why, the how, and the recent changes.

## The short version

```bash
# disable swap (Linux)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# verify
free -h
#                total        used        free      shared  buff/cache   available
# Mem:           15Gi       1.5Gi        12Gi       0.0Ki       1.2Gi        13Gi
# Swap:          0B          0B          0B
```

If you skip this, `kubelet` will fail to start with an error like:

```
journalctl -u kubelet
# ...
# "Swap is enabled; production deployments should disable swap or set --fail-swap-on=false"
# "running with swap on is not supported, please disable swap"
```

## Why kubelet refuses swap

The reason is **quality of service** — specifically, the kubelet's ability to enforce memory limits.

### How memory limits work

When you set `resources.limits.memory: 256Mi` on a container:

1. The container is given a **cgroup** with a memory limit of 256 MiB
2. If the container's memory usage approaches the limit, the kernel's **memory OOM-killer** activates
3. The kubelet may also **evict the Pod** if the node is under memory pressure

### What swap breaks

The cgroup memory limit is enforced at the cgroup level, but **swap is global** — when the cgroup is at its limit, the kernel can still swap out pages of that cgroup to swap, defeating the limit. The cgroup-v1 memory controller didn't account for swap usage in the limit. (cgroup-v2 has `memory.swap.max` which fixes this, but k8s historically didn't use it.)

Without accurate memory accounting:

* **Liveness probes** can't reliably detect OOM situations
* **Resource limits** become best-effort
* **The scheduler** can no longer guarantee that a node has enough "real" memory for a Pod's requests
* **Node-level OOMs** become unpredictable — the kernel kills whatever, not the right thing

The Kubernetes SIG-Node decision was: **swap is dangerous for k8s's memory model, refuse to run with it.** Better to fail loudly than to silently misbehave.

## The history of the debate

The "no swap" rule has been controversial:

* **OS people** (especially on smaller devices) think swap is essential. A Raspberry Pi with 1GB RAM benefits hugely from 2GB swap.
* **k8s people** want predictable memory accounting.
* **Container runtime people** (containerd, CRI-O) wanted to support both.

### k8s 1.22 — NodeSwap status Beta

In k8s 1.22, support for swap was added **as a beta feature**. The kubelet gained:

* `--feature-gates=NodeSwap=on` (default off, became default off in 1.28)
* `--fail-swap-on` (default true) — when false, kubelet starts even with swap enabled
* Memory accounting that takes swap into account

### k8s 1.28 — `NodeSwap` graduates to beta, default ON

Starting in k8s 1.28, `NodeSwap` is enabled by default but **only on cgroup-v2 systems** (which most modern Linux distros use). The kubelet now:

* Detects swap
* Accounts for swap in memory cgroup limits
* Allows Pods to use swap when configured

This means **on a modern Linux with cgroup-v2, the kubelet does not refuse to start with swap enabled.** It still does on cgroup-v1 systems.

The gotcha: even with k8s 1.28+, the cgroup accounting assumes that **swap usage of a cgroup counts against its memory limit**. So `limits.memory: 256Mi` means "256 MiB of RAM + swap combined". Which is what you want for hard limits, but is a behavior change from "256 MiB of RAM, period".

```yaml
# In k8s 1.28+ with NodeSwap enabled:
spec:
  containers:
  - name: app
    resources:
      limits:
        memory: 256Mi    # 256 MiB of RAM + swap combined
      requests:
        memory: 128Mi
```

## So what do I do today?

### If you control the node and can disable swap (most cases)

**Disable swap.** It's the simplest, most predictable setup. Cloud images from AWS / GCP / Azure don't enable swap by default, so this is usually already done.

```bash
# disable for this session
sudo swapoff -a

# disable permanently
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

### If you're on a constrained device (Raspberry Pi, edge)

You have two options:

**Option A: disable swap anyway, give Pods what they need**

```yaml
# In production, you size requests to fit. On a Pi with 1GB RAM, run lightweight
# workloads with small requests.
spec:
  containers:
  - name: app
    resources:
      requests:
        memory: 64Mi
      limits:
        memory: 128Mi
```

**Option B: enable swap and use k8s 1.28+ NodeSwap**

Requires:
* cgroup-v2 (modern Linux)
* k8s 1.28+
* `memory.swap.max` set in the cgroup to limit swap usage
* Understanding that `limits.memory` now includes swap

This is the right answer for edge / IoT but requires care.

### If you're on a shared VM with swap (some cloud VMs)

Most cloud images disable swap. If yours has it on, disable it. Don't try to work around it.

## The kubelet flags

If you must run with swap on an older k8s:

```bash
# /etc/default/kubelet
KUBELET_EXTRA_ARGS="--fail-swap-on=false"
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

This is a workaround. The kubelet will start, but you'll have **unpredictable behavior under memory pressure**. Use only for dev, never for production.

## How to check

```bash
# is swap enabled?
free -h
# swapon -s

# is the kubelet configured to fail on swap?
cat /var/lib/kubelet/config.yaml | grep fail-swap-on

# what cgroup version?
stat -fc %T /sys/fs/cgroup/
# 0  → cgroup-v1 (legacy)
# 1  → cgroup-v2 (modern, unified hierarchy)
```

## What about Swap on AWS EKS, GKE, AKS?

Managed clusters run on nodes that don't have swap enabled by default. The cloud-optimized AMIs/images disable swap. You usually don't need to think about this.

If you're bringing your own AMI with swap enabled, you'll hit the "kubelet won't start" error. Disable swap on the image.

## What about k3s?

k3s has historically been more permissive. By default, k3s runs without enforcing `--fail-swap-on`. The CNI is more lightweight, the memory model is the same, but k3s is positioned for edge / IoT where swap is useful.

If you're running k3s on a Pi with swap, you can either disable swap (recommended) or leave it on (k3s tolerates it). The k8s upstream behavior is stricter.

## Gotchas

* **`free -h` shows 0 swap but the kubelet still complains.** The kernel is still configured to allow swap; just no swap file is in use. `swapoff -a` plus a `sed` of `/etc/fstab` is the proper fix.
* **The cgroup v1 vs v2 distinction matters.** On cgroup-v1 systems, swap accounting is broken. On cgroup-v2, it's not. Modern distros (Ubuntu 22.04+, RHEL 9+, Debian 12+) default to cgroup-v2. Older distros need configuration.
* **Cloud VMs sometimes have swap on a separate volume.** Disabling it requires editing `/etc/fstab` and unmounting the swap volume, not just `swapoff -a`.
* **Minikube in a VM doesn't have swap.** minikube's default VM doesn't enable swap. No problem.
* **Docker Desktop's k8s doesn't have swap.** Same deal.
* **K3s on a Raspberry Pi often has swap on by default.** Raspbian enables a swap file. If you want to run "real k8s" on a Pi, disable the swap file. If you want k3s to tolerate it, fine.
* **The `--fail-swap-on=false` workaround causes silent OOMs.** A Pod that exceeds its limit may swap instead of being killed, masking the issue until the system is so swapped that everything slows to a crawl. Not a free lunch.

## What to remember

* **Production nodes have swap disabled.** Period. Don't argue.
* **k8s 1.28+ supports swap on cgroup-v2** as a beta feature, but it's still opt-in for most operators.
* **Edge / IoT with constrained memory** is the legitimate use case for swap-on-k8s.
* **If your kubelet won't start, check swap first.** It's the most common cause of the "kubelet fails to start" error in a fresh install.

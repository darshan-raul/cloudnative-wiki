---
title: Cgroups v2
description: Linux cgroups v2 — unified hierarchy, controllers, /sys/fs/cgroup, resource control for processes and containers
tags:
  - linux
  - cgroups
  - kernel
---

# Cgroups v2

Control groups (cgroups) are the Linux kernel mechanism for **limiting, accounting, and isolating** the resource usage of groups of processes — CPU time, memory, I/O, PID count. Cgroups v2 is the modern revision (kernel 5.0+), replacing the older v1 with a unified hierarchy.

## Architecture

```
cgroups v2 hierarchy (single tree)
└── /sys/fs/cgroup/
    └── system/
        ├── slice_1/
        │   ├── cgroup.procs      ← processes in this group
        │   ├── cgroup.controllers ← controllers available here
        │   ├── cgroup.subtree_control ← child controllers enabled
        │   ├── cgroup.events      ← cgroup.populated, cgroup.events
        │   ├── cpu.max            ← cpu controller
        │   ├── memory.max        ← memory controller
        │   ├── io.max            ← I/O controller
        │   └── pids.max          ← pids controller
        └── slice_2/
```

Each controller (cpu, memory, io, pids) adds its own interface files to every cgroup. Unlike cgroups v1's per-controller hierarchies, v2 has **one unified tree** and controllers can be enabled per subtree.

## Key Differences: v1 vs v2

| Feature              | v1                              | v2                                      |
|----------------------|----------------------------------|----------------------------------------|
| Hierarchy            | One per controller               | Single unified tree                    |
| Controller trees     | Independent per controller       | Unified tree with subtree_control      |
| Thread grouping      | Processes only                   | Threads (PIDs) can be in separate cgroups |
| `cpu.rt_runtime`    | Per-cgroup                       | No (moved to cpu controller)           |
| Default hierarchy    | `/cgroup.controllers/`           | `/sys/fs/cgroup/` (unified)            |
| `notify_on_release`  | Per-cgroup                       | Replaced by `cgroup.events`           |

## Controllers

### CPU Controller

```
# Set max CPU time: max 50% of one CPU, period 100000µs
echo "50000 100000" > cpu.max

# Unlimited (default)
echo "max" > cpu.max

# Show current usage
cat cpu.stat
```

`cpu.max` format: `max_quota period` in microseconds. With 50% quota and 100000µs period, a process gets 50000µs every 100000µs window.

```
# Shares-based (relative weight, default 1024)
echo "2048" > cpu.weight.nice   # relative to siblings
```

### Memory Controller

```
# Hard limit: kill processes that exceed this
echo "536870912" > memory.max   # 512 MiB in bytes

# Soft limit: reclaim when below this, unless under pressure
echo "256870912" > memory.low   # 256 MiB

# Swap limit (v2 adds this)
echo "107374182" > memory.swap.max   # allow 1 GiB swap

# Default: "max" = unlimited
echo "max" > memory.max

# Current usage
cat memory.current
```

**OOM behavior in v2:** When `memory.max` is exceeded, the kernel sends SIGKILL to a process in the cgroup. The `memory.oom.group` flag controls whether the entire cgroup is killed or just the exceeding process.

```
# Kill entire cgroup on OOM (default 0 = process only)
echo "1" > memory.oom.group
```

### I/O Controller (blkio)

```
# Set device throttles: major:minor rbps wbps
echo "8:0 104857600" > io.max      # 100 MiB/s read
echo "8:0 max max" > io.max        # remove limit

# Weight-based (relative, 1-10000, default 100)
echo "weight 500" > io.weight
```

v2 blkio is called `io` (not `blkio` like in v1). Throttle (upper bound) uses `io.max`, weight-based uses `io.weight`.

### PIDs Controller

```
# Max number of processes in this cgroup
echo "1024" > pids.max

# Current count
cat pids.current
```

## Creating a Cgroup

```bash
# Create a new cgroup
mkdir -p /sys/fs/cgroup/system/myapp.slice

# Add a process
echo $$ > /sys/fs/cgroup/system/myapp.slice/cgroup.procs

# Set limits
echo "200000 100000" > /sys/fs/cgroup/system/myapp.slice/cpu.max
echo "1073741824" > /sys/fs/cgroup/system/myapp.slice/memory.max

# Verify
cat /sys/fs/cgroup/system/myapp.slice/cgroup.procs
cat /sys/fs/cgroup/system/myapp.slice/memory.max
```

`$$` is the shell's own PID. The current shell (and any children it spawns) are now in the cgroup.

## Enabling Controllers in Subtrees

Child cgroups don't automatically inherit controller limits. You must explicitly enable them:

```bash
# Enable CPU controller for children of this cgroup
echo "+cpu" > /sys/fs/cgroup/system/myapp.slice/cgroup.subtree_control

# Now child cgroups can set cpu.max
mkdir /sys/fs/cgroup/system/myapp.slice/worker
echo "100000 100000" > /sys/fs/cgroup/system/myapp.slice/worker/cpu.max
```

`-cpu` removes the controller. `+memory` enables memory, etc.

## `cgroup.procs` vs `cgroup.threads` (cgroup v2 Threads)

| File           | What it contains           | Granularity |
|----------------|---------------------------|-------------|
| `cgroup.procs` | Thread-group leaders only  | Process-level |
| `cgroup.threads` | All threads (PIDs)      | Thread-level |

`cgroup.procs` only accepts the *thread group leader* (PID = TGID). To place individual threads in different cgroups (useful for web servers where each thread handles a request), use `cgroup.threads`.

## systemd Integration

systemd manages cgroups automatically via slice units:

```bash
# Default slices:
systemd-cgls                 # show cgroup tree
systemctl set-property --system usage=cpu,memory slice_name  # persistent limits

# Create a transient slice (session-scoped)
systemd-run --scope -p MemoryMax=512M -- curl https://example.com
```

systemd creates `/sys/fs/cgroup/system.slice/`, `/sys/fs/cgroup/user.slice/`, etc. automatically.

## Container Runtime Integration

Container runtimes (containerd, runc) use cgroups v2 to enforce resource limits. In Kubernetes:

```yaml
# Kubernetes pod QoS maps to cgroup:
# Guaranteed   → cpuset.cpus + memory.min/memory.max
# Burstable   → memory.min + memory.high (best-effort reclaim)
# BestEffort  → no guarantees, gets reclaimed first
```

**Key insight:** When you set `resources.limits.memory: 512Mi` in a K8s pod, kubelet writes `536870912` to `memory.max` in the container's cgroup. The kernel enforces it.

## Inspecting cgroups

```bash
# What cgroup is this process in?
cat /proc/self/cgroup

# cgroup v2 shows a single unified path:
# 0::/system.slice/containerd.service

# Show all cgroups and their controllers
lssubsys -m                     # v1

# v2: just look at the tree
tree /sys/fs/cgroup/

# PID 1's cgroup (root)
cat /proc/1/cgroup
```

## Common Mistakes

- **Writing to wrong level:** Limits must be set on the *leaf* cgroup where processes live. Setting on a parent doesn't retroactively apply.
- **Forgetting subtree_control:** Parent won't pass controller to children without it.
- **Bytes vs percentages:** `memory.max` takes bytes, not percentages. `536870912` = 512 MiB.
- **Confusing v1 and v2 paths:** v1 = `/cgroup/cpu/`, v2 = `/sys/fs/cgroup/system.slice/`
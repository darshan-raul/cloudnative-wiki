---
title: Mount Namespaces
description: Linux mount namespaces — mount(2), mount propagation, pivot_root, shared/subordinate mounts
tags:
  - linux
  - namespaces
  - containers
  - filesystem
---

# Mount Namespaces

Mount namespaces isolate the set of filesystem mount points visible to a group of processes. What `/` means, what `/proc` means, what `/dev` means — all of these can differ between mount namespaces. This is the foundation of container filesystem isolation.

## The Core Concept

In Linux, every process has a root filesystem (`/`). By default, all processes share the same mount table — when one process mounts something, everyone sees it (unless the mount is private).

Mount namespaces let processes have **independent mount tables**:

```
Host mount namespace:
  /           → /dev/sda1 (ext4)
  /home       → /dev/sda2 (xfs)
  /var/lib/mysql → /dev/sdb (volume)

Container mount namespace (isolated):
  /           → /dev/sda1 (ext4)          ← same underlying disk
  /home       → /dev/sda2 (xfs)
  /var/lib/mysql → overlayfs (container's own layers)  ← DIFFERENT
```

## Creating a Mount Namespace

```bash
# Create a new mount namespace (unshare defaults to --mount if not specified)
unshare --mount bash

# Inside: mounts are private to this namespace
mount -t tmpfs tmpfs /mytmp
df -h /mytmp              # shows tmpfs
# In another terminal (host): df -h /mytmp → nothing (not visible)
```

## `pivot_root` vs `chroot`

Both change the root filesystem, but they work differently:

### chroot (older, simpler)
```
chroot /new/root bash
```
Changes where `/` points to. The old `/` is still accessible as the parent directory of the new root. Poor isolation — escape is possible via `chdir("..")`.

### pivot_root (what containers use)
```c
// The pivot_root syscall
pivot_root(new_root, put_old);
```

Moves the current root to `put_old` and makes `new_root` the new root. The old root is hidden under `put_old` and is no longer reachable from the new namespace.

```bash
# Typical container init sequence:
mkdir -p /newroot /oldroot
mount --bind /overlay /newroot
pivot_root /newroot /newroot/oldroot
# Now /oldroot holds what was previously /
umount /oldroot   # clean up
```

The key difference: with `pivot_root`, processes cannot escape back to the old root because the old root is mounted *inside* the new root's namespace and gets hidden.

## Mount Propagation

When you mount something inside a container, does it propagate to the host? Mount propagation controls this.

### Mount Types

| Type         | Propagation                           | Container default |
|-------------|--------------------------------------|------------------|
| `private`   | No propagation in either direction   | What containers use |
| `shared`    | Bidirectional propagation             | Rarely used      |
| `slave`     | Host → container (not reverse)        | Rarely used      |
| `unbindable`| Cannot be bind-mounted               | For /                 |

```bash
# Default: containers use private mounts
mount --make-private /var/lib/container

# Check current propagation type
findmnt -o PROPAGATION

# Docker uses private by default for container filesystem mounts
# Kubernetes pods: pod's volumes use private
```

### Why Private Matters

```
Host mounts /dev/sda1 at /
Container has /dev/sda1 at / (same)
Container mounts overlay at /var/lib/mysql

With private:   container sees overlay, host sees /dev/sda1 (independent)
With shared:    container's overlay would appear on host (BAD)
```

## Overlay Filesystem

Overlay is the standard container image filesystem. It **layers multiple directories** into one merged view:

```
overlay on /var/lib/docker/overlay2/... mounted at /

Layers (lowerdir) — read-only:
  /var/lib/docker/overlay2/l/XXXX   ← image layer 1 (base OS)
  /var/lib/docker/overlay2/l/YYYY   ← image layer 2 (tools)
  /var/lib/docker/overlay2/l/ZZZZ   ← image layer 3 (app code)

Merged view (upperdir + lowerdir):
  /                                 ← everything merged

Writable layer (upperdir) — copy-up on write:
  /var/lib/docker/overlay2/XXXX/diff ← container's changes
```

### Overlay Mount Syntax

```bash
mount -t overlay overlay \
  -o lowerdir=/lower1:/lower2:/lower3,\
      upperdir=/upper,\
      workdir=/work \
  /merged
```

- `lowerdir`: read-only layers, colon-separated (first = topmost layer)
- `upperdir`: writable layer (container's changes go here)
- `workdir`: empty directory needed by overlay for atomic rename ops

### Copy-on-Write

When a process writes to a file in `lowerdir`, overlay **copies it to `upperdir` first** (copy-up). The lowerdir file is never modified. This is the CoW mechanism that makes image layers shareable.

```bash
# Image layer has /bin/bash (read-only)
# Container writes to /bin/bash (e.g., patches it)
# → /upper/bin/bash is created (copy-up)
# → lowerdir's /bin/bash untouched (shared across containers)
```

## Mount Namespaces and `/proc`

Container runtimes must also mount `/proc` specially inside containers:

```bash
# /proc inside a container needs its own mount namespace
# Otherwise ps/top would show host PIDs

# Typical container /proc mount:
mount -t proc proc /proc

# This creates a private /proc visible only inside the namespace
# containing only processes in that namespace (ps shows only container PIDs)
```

Docker does this automatically. In Kubernetes, the kubelet ensures each pod gets its own mount namespace via the container runtime.

## Key Insight: Mount Namespace ≠ Container

Containers need **multiple namespaces together**:
- Mount NS: which filesystems are visible
- PID NS: which processes are visible
- Network NS: which network interfaces exist
- UTS NS: which hostname/domainname
- User NS: which UIDs/GIDs are visible

No single namespace is enough — they compose to form a container.

## Viewing Mounts in a Namespace

```bash
# Inside a namespace:
findmnt              # show all mounts (namespaced view)

# From host, see mounts for a specific PID's namespace:
nsenter --target $PID --mount findmnt

# /proc/$PID/mounts always shows the host view
# /proc/$PID/mountinfo shows namespace-specific mounts
cat /proc/self/mountinfo | head -20
# 36 31 0:32 / /sys/fs/cgroup/memory ...
#   ↑ mount_id parent_id major:minor root mount_point options super_options
```
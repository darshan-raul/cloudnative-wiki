---
title: User Namespaces
description: Linux user namespaces — UID/GID mapping, uid_map, gid_map, subuid/subgid, rootless containers, SECBIT_NO_NEW_PRIVS
tags:
  - linux
  - namespaces
  - security
  - containers
---

# User Namespaces

User namespaces isolate the UID/GID mappings between host and container. Inside a user namespace, processes can have **root privileges** (UID 0) that are actually an unprivileged UID on the host. This is the cornerstone of **rootless containers**.

## The Core Problem

Without user namespaces, a container running as UID 0 inside the container IS UID 0 on the host. That's a security risk — a container escape could mean host root.

With user namespaces:
- Inside the container: UID 0 (root)
- On the host: UID 100000 (or whatever the mapping says)

A compromise of the container gives the attacker a non-root account on the host.

## How UID Mapping Works

Each user namespace has two files that define the mapping:

```bash
# Files defining the mapping (one per PID namespace level)
```

A user namespace is created and then mapped:

```bash
# Create a new user namespace
unshare --user

# Inside, map UID 0 (root) in namespace to UID 100000 on host
echo "0 100000 1" > /proc/self/uid_map    # host UID 100000 = namespace UID 0

# Same for GID (requires CAP_SETGID in parent namespace)
echo "0 100000 1" > /proc/self/gid_map
```

Format of `uid_map` and `gid_map`:
```
ID-inside-namespace   ID-on-host   count
```

```bash
# Example: map 1000 container UIDs to host UIDs 100000-100999
echo "0 100000 1000" > /proc/self/uid_map

# This means:
# container UID 0      → host UID 100000
# container UID 1      → host UID 100001
# ...
# container UID 999    → host UID 100999
```

## `/etc/subuid` and `/etc/subgid`

When you run a rootless container, the container runtime reads these files to know what UID ranges are available for mapping:

```bash
# /etc/subuid — host UIDs that can be mapped to a user
# Format: username:start:count
cat /etc/subuid
# darshan:100000:65536
# root:100000:65536

cat /etc/subgid
# darshan:100000:65536
# root:100000:65536
```

The value `65536` means this user can map 65536 host UIDs (100000-165535) into user namespaces.

## The Full Rootless Container Setup

```bash
# Check if your user can use user namespaces
cat /proc/sys/kernel/unprivileged_userns_clone
# 1 = allowed, 0 = only root

# Or check the mappings you're allowed to use:
grep $(whoami) /etc/subuid
# darshan:100000:65536

# Run a rootless container (Podman does this by default)
podman run -d nginx

# Inside container:
#   UID 0 (root)      → UID 199999 on host (not root!)
#   UID 1 (daemon)    → UID 200000 on host
```

## Why Rootless Containers Matter

**Without user namespaces:** If a container process escapes, it has root on the host.
**With user namespaces:** If a container process escapes, it has the mapped unprivileged UID.

```bash
# A rootless container running as host UID 100000
# Even with full container breakout:
# - Can't modify /etc/passwd (requires host UID 0)
# - Can't bind to privileged ports < 1024 (requires host UID 0)
# - Can't load kernel modules (requires CAP_SYS_MODULE on host = not granted)
```

## Nested Namespaces and Mapping

User namespaces can be nested. Each level maps UIDs independently:

```
Level 1 (host)        UID 0 (root)         → UID 0 on host
Level 2 (user NS)     UID 0 (root)         → UID 100000 on host
Level 3 (container)   UID 0 (root)         → UID 200000 on host (mapped through level 2)
```

The mapping is **per-namespace-level**, not global. Container UID 0 maps through all namespace levels to reach the host UID.

## CAP_SETUID and CAP_SETGID

To create a user namespace and set mappings, the process needs:
- `CAP_SETUID` — to set uid_map
- `CAP_SETGID` — to set gid_map

On a rootless unprivileged user namespace, these capabilities are granted within the namespace (container root can remap its own UIDs), but they don't grant host privileges.

## `SECBIT_NO_NEW_PRIVS`

The `no_new_privs` bit (`SECBIT_NO_NEW_PRIVS`) prevents a process and its children from gaining new privileges. It's important for rootless containers because it stops `setuid` binaries from elevating to root:

```bash
# Check if setuid binaries can still work (they won't if no_new_privs is set)
cat /proc/self/status | grep NoNewPrivs
# 0 = can gain privileges (normal)
# 1 = cannot gain new privileges (secure)

# Set it:
prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);

# Or via shell:
setpriv --no-new-privs curl https://example.com
```

## Rootless Docker vs Rootless Podman

| Feature              | Rootless Docker           | Rootless Podman            |
|---------------------|--------------------------|----------------------------|
| User namespace      | Requires setup (newuidmap) | Automatic by default        |
| daemon              | dockerd still runs as root | daemonless (no daemon)    |
| Network namespace   | Still needs root for some  | Uses slirp4netns/netns    |
| Storage             | fuse-overlayfs recommended | fuse-overlayfs automatic  |

Podman is designed rootless-first. Docker rootless requires more manual configuration.

## Security Considerations

User namespaces reduce but don't eliminate container escape risk:
- A namespace UID 0 is still mapped to a real UID — that UID might have **some** capabilities
- The mapped UID range in `/etc/subuid` should be **dedicated** (not overlapping with real users)
- Some syscalls are still restricted even in a user namespace (`mount`, `sys_admin`)

```bash
# The host kernel capabilities for the mapped UID:
# If uid 100000 has no capabilities on host → minimal risk
# If uid 0 on host somehow → MAXIMUM risk
```

## Practical: Inspecting Namespace Mappings

```bash
# See what UID you appear as inside a user namespace
cat /proc/self/uid_map
#          0          100000              1

# GID mapping
cat /proc/self/gid_map
#          0          100000              1

# From host: see all user namespaces
ls -la /proc/self/ns/user

# Enter a user namespace
nsenter --target $PID --user bash
```
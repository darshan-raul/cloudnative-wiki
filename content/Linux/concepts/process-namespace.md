---
title: Process Namespaces
description: Linux PID namespaces — process isolation, clone, PID1, pid_ns, the namespace hierarchy
tags:
  - linux
  - namespaces
  - containers
---

# Process Namespaces

Linux namespaces are a kernel feature that **partition kernel resources** so that processes in one namespace can't see or modify resources in another. The PID namespace isolates process IDs — processes in different PID namespaces can have the same PID, and PID namespace nesting creates a hierarchy.

## The Core Concept

Without namespaces, the whole system shares one PID tree. PID 1 is always init.

With PID namespaces:

```
Host namespace (PID namespace 0)
└── Container namespace (PID namespace 1)
    ├── PID 1 (inside container = PID 256 on host)
    ├── PID 2 (nginx = PID 257 on host)
    └── PID 3 (bash = PID 258 on host)
```

Inside the container, processes see PIDs 1, 2, 3 as normal. On the host, they have different PIDs in a completely separate namespace.

## Creating a PID Namespace

The `unshare` command creates a new namespace:

```bash
# Create a new PID namespace and run a shell in it
unshare --pid --fork --map-root-user bash

# Inside the new namespace:
echo $$                     # shows PID 1
ps aux                     # only sees processes in this namespace
```

Or via `nsenter` to enter an existing namespace:

```bash
# Find a process's PID namespace
ls -la /proc/$$/ns/pid

# Enter it
nsenter --target 1234 --pid bash
```

## How PID Namespaces Work

### The `clone(2)` syscall

```
clone(CLONE_NEWPID | CLONE_NEWNS | CLONE_NEWNET, stack, flags);
```

`CLONE_NEWPID` tells the kernel: create a new PID namespace. The child starts with PID 1 inside the new namespace.

### The Namespace Hierarchy

Namespaces are nested. When you create a PID namespace inside another:

```
/proc/[pid]/ns/pid_for_children    ← created when this process has children
/proc/[pid]/ns/pid                 ← this process's namespace
```

The first process in a new PID namespace has its own "init" role: it reaps orphaned children (Zombies). If it exits, the namespace is destroyed and all remaining processes in it are killed.

### PID 1 Inside the Namespace

Inside a new PID namespace, the first process has a special role:

```c
// Simplified: what the kernel does when CLONE_NEWPID is set
if (child_pid == 0) {
    // This is PID 1 inside the new namespace
    disable_SIGCHLD_handler();  // or handle it specially
    become_reaper_of_orphans();
}
```

PID 1 inside a namespace:
- Reaps zombie processes (calls `wait()` on exited children)
- Receives signals with no handler (SIGTERM, SIGKILL) and terminates children
- Its death causes all descendants to die (namespace destruction)

## The `/proc` Interface

```bash
# Show which namespaces a process belongs to
ls -la /proc/$$/ns/
# lrwxrwxrwx 1 root root 0 Jun  6 /proc/self/ns/cgroup -> 'cgroup:[4026531835]'
# lrwxrwxrwx 1 root root 0 Jun  6 /proc/self/ns/ipc' -> 'ipc:[4026531839]'
# lrwxrwxrwx 1 root root 0 Jun  6 /proc/self/ns/mnt' -> 'mnt:[4026531840]'
# lrwxrwxrwx 1 root  root 0 Jun  6 /proc/self/ns/net' -> 'net:[4026531841]'
# lrwxrwxrwx 1 root root 0 Jun  6 /proc/self/ns/pid' -> 'pid:[4026531836]'
# lrwxrwxrwx 1 root root 0 Jun  6 /proc/self/ns/pid_for_children' -> 'pid:[4026531836]'
# lrwxrwx 1 root root 0 Jun  6 /proc/self/ns/time' -> 'time:[4026531834]'
# lrwxrwxrwx 1 root root 0 Jun  6 /proc/self/ns/user' -> 'user:[4026531837]'
# lrwxrwxrwx 1 root root 0 Jun  6 /proc/self/ns/uts' -> 'uts:[4026531838]'

# All processes sharing the same namespace have the same inode
stat /proc/$$/ns/pid
```

## Nesting: The pid_for_children Link

```
pid_for_children    ← points to the namespace that CHILDREN of this process will use
pid                 ← points to the namespace THIS process is in
```

This allows a process to create children in a new namespace without affecting itself:

```bash
# Parent remains in host namespace, children go into new one
unshare --pid --fork
```

The `--fork` flag ensures the `unshare` call itself is the first process in the new namespace (becoming PID 1 to its children).

## Practical: Container Runtime Use

Container runtimes use PID namespaces to isolate processes:

```
containerd-shim (host)
└── runc (host, parent of container processes)
    └── container init (PID 1 in container = high PID on host)
        ├── nginx worker (PID 2 in container)
        └── nginx worker (PID 3 in container)
```

The **pause container** (in K8s) is a process in a separate PID namespace whose only job is to be PID 1 and reap zombies. It stays alive as long as the pod runs.

## Viewing Namespace Relationships

```bash
# Show PID namespace hierarchy
nsenter --target 1 --pid readlink /proc/self/ns/pid

# With bcc-tools / linux-tool
execsnoop          # trace process creation
nslist             # list namespace membership

# Manual: find all processes in a namespace
for pid in /proc/[0-9]*; do
  if [ "$(readlink $pid/ns/pid)" = "pid:[4026531836]" ]; then
    echo $(basename $pid): $(cat $pid/comm)
  fi
done
```

## Key Insight for Containers

PID namespace isolation means:
- `ps` inside a container only shows container processes (not host)
- Signal routing: SIGTERM sent to PID 1 inside container terminates the container's PID 1
- `/proc/PID` on the host shows the host PID; inside the container it shows the container PID
- `kill -9 1` inside the container kills the container's init, not the host's
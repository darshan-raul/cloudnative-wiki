---
title: Container Runtimes
description: Linux container runtimes — runc, containerd, OCI spec, containerd shim, runtime hierarchy
tags:
  - linux
  - containers
  - runc
  - containerd
---

# Container Runtimes

Container runtimes are the software that creates and runs containers. There's a layered stack — low-level OCI runtime that does the actual container creation, and a higher-level runtime that manages images, networking, and orchestration.

## The Runtime Stack

```
┌──────────────────────────────────────┐
│  High-level runtime (containerd, CRI-O)│
│  - Pulls images                      │
│  - Manages network                   │
│  - Creates containers                │
└────────────────┬─────────────────────┘
                 │  CRI (Container Runtime Interface)
┌────────────────▼─────────────────────┐
│  Low-level runtime (runc)             │
│  - Creates namespaces                 │
│  - Applies cgroups                    │
│  - Runs the container process          │
└────────────────┬─────────────────────┘
                 │  exec()s
┌────────────────▼─────────────────────┐
│  containerd-shim (runc-v2 shim)       │
│  - Keeps container running if runtime │
│    restarts                           │
│  - Reaps zombie runc processes        │
└────────────────┬─────────────────────┘
                 │  wait()s
┌────────────────▼─────────────────────┐
│  runc (OCI runtime)                   │
│  - Implements OCI runtime spec         │
│  - create, start, kill, delete        │
└──────────────────────────────────────┘
```

## OCI Runtime Spec

The Open Container Initiative defines a spec (`config.json`) that all OCI runtimes implement. It describes what a container looks like:

```json
{
  "ociVersion": "1.0.2",
  "process": {
    "terminal": true,
    "user": { "uid": 0, "gid": 0 },
    "args": ["/bin/bash"],
    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/bin"],
    "cwd": "/"
  },
  "root": {
    "path": "rootfs",
    "readonly": true
  },
  "hostname": "container",
  "mounts": [
    { "destination": "/proc", "type": "proc", "source": "proc" },
    { "destination": "/dev", "type": "tmpfs", "source": "tmpfs" }
  ],
  "linux": {
    "namespaces": [
      { "type": "pid" },
      { "type": "network" },
      { "type": "mount" },
      { "type": "uts" },
      { "type": "ipc" },
      { "type": "user" }
    ],
    "cgroupsPath": "system.slice/container-test",
    "resources": {
      "memory": { "limit": 536870912 }
    },
    "seccomp": { ... }
  }
}
```

The OCI bundle is a directory containing this `config.json` plus a `rootfs/` directory.

## runc

`runc` is the reference OCI runtime. It takes a bundle directory and runs the container:

```bash
# Create a container from an OCI bundle
runc create mycontainer

# Start it
runc start mycontainer

# List containers
runc list

# Get container state
runc state mycontainer

# Kill (SIGKILL)
runc kill mycontainer

# Delete (cleanup)
runc delete mycontainer

# Run interactively
runc run -it mycontainer

# Execute a command inside a running container
runc exec mycontainer ps aux
```

`runc` doesn't pull images — it expects the rootfs to already be on disk. It creates namespaces, applies cgroups, sets up seccomp, and execs the container process.

## containerd

`containerd` is the high-level runtime. It runs as a daemon and exposes an API (CRI = Container Runtime Interface) that kubelet talks to:

```
kubelet
  └── containerd (daemon)
        ├── Image management (pull, unpack to snapshots/)
        ├── Container lifecycle (create, start, stop)
        └── snapshotter (overlayfs, devicemapper)
              └── runc (per-container process)
```

```bash
# containerd runs as a systemd service
systemctl status containerd

# ctr is the containerd CLI (for debugging)
ctr images pull docker.io/library/nginx:latest
ctr images list
ctr containers list
ctr run docker.io/library/nginx:latest mynginx
```

containerd doesn't just run containers — it manages the whole lifecycle including image pulling, snapshot management, and networking setup.

## The containerd-shim (runc-v2 shim)

The shim exists for **lifecycle isolation**:

```
Without shim:
  containerd → runc → container-process
  If containerd restarts:
    runc dies → container-process dies (orphaned or killed)

With shim:
  containerd → runc → shim → container-process
  If containerd restarts:
    shim stays alive → container-process stays alive
```

The shim:
- Is the parent of the container process (wait()s on it)
- Stays alive even if containerd dies
- Exposes a FD-based API for containerd to talk to the running container
- Allows containerd to be upgraded without restarting containers

This is why containers survive containerd restarts in Kubernetes.

## Docker's Full Stack

Docker historically included its own runtime. Modern Docker uses containerd internally:

```
docker CLI (dockerd API)
  └── containerd
        └── containerd-shim
              └── runc
                    └── container process
```

```bash
# Docker info shows the runtime
docker info | grep -i runtime
# Runtime: containerd
# Default Runtime: runc

# containerd socket (what kubelet uses)
docker://unix:///var/run/dockershim.sock

# containerd CRI socket (what kubelet uses in newer setups)
containerd://unix:///run/containerd/containerd.sock
```

## CRI: Container Runtime Interface

Kubernetes doesn't talk directly to containerd — it uses the CRI gRPC API:

```
kubelet (CRI client)
  └── CRI gRPC (Unix socket /run/containerd/containerd.sock)
        └── containerd (CRI server)
              └── containerd-shim
                    └── runc
                          └── container
```

The CRI defines `RuntimeService` and `ImageService` RPCs: `ListContainers`, `CreateContainer`, `StartContainer`, `StopContainer`, `PullImage`, etc.

CRI-O is a CRI implementation that's specifically for Kubernetes — it uses runc (not the full containerd) directly.

## Practical: Inspecting Runtime Components

```bash
# See runc processes (container processes)
ps aux | grep runc

# See containerd-shim processes
ps aux | grep "containerd-shim"

# See containerd PID
systemctl show containerd | grep MainPID

# What cgroup a container is in
cat /proc/<pid>/cgroup | grep memory

# Find container's overlay path
ls /sys/fs/cgroup/memory/system.slice/docker-<container-id>.scope/

# Run a minimal container manually
mkdir -p /tmp/bundle/rootfs
docker export $(docker create busybox) | tar -C /tmp/bundle/rootfs -xf -
cd /tmp/bundle
runc run mybox
```
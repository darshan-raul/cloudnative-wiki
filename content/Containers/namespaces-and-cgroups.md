---
title: Namespaces and cgroups — What a Container Really Is
tags: [containers, linux, namespaces, cgroups, isolation]
date: 2026-10-10
description: A container is an ordinary Linux process with a restricted view of the system and a resource budget. This note builds one by hand, maps each kernel feature to what it isolates, and draws the consequences for debugging and security.
---

# Namespaces and cgroups — What a Container Really Is

There is no "container" object in the Linux kernel. A container is an ordinary process, started with a particular combination of kernel features:

- **namespaces** change what the process can _see_,
- **cgroups** limit what it can _use_,
- **capabilities, seccomp and LSMs** restrict what it can _do_,
- a **root filesystem** from an image gives it its own files.

Everything a container engine does is setting those up and then calling `exec()` on your program. The proof is on any host running containers:

```bash
ps -ef | grep nginx          # the "containerised" nginx is right there in the host's process list
ls -l /proc/<pid>/ns/        # …and these symlinks show which namespaces it lives in
cat /proc/<pid>/cgroup       # …and this shows its cgroup
```

## Namespaces: what the process can see

| Namespace | Isolates                                  | Inside the container                                | Deep dive                                                     |
| :-------- | :---------------------------------------- | :-------------------------------------------------- | :------------------------------------------------------------ |
| `pid`     | Process IDs                               | Your process is PID 1 and sees only its descendants | [[Linux/concepts/process-namespace\|Process namespace]]       |
| `mnt`     | Mount points                              | A private filesystem tree rooted at the image       | [[Linux/virtualization/mount-namespace\|Mount namespace]]     |
| `net`     | Interfaces, routes, firewall rules, ports | Its own `eth0` and `lo`; port 80 is free            | [[Linux/virtualization/network-namespace\|Network namespace]] |
| `uts`     | Hostname                                  | Its own hostname                                    |                                                               |
| `ipc`     | Shared memory, semaphores, message queues | Cannot see the host's IPC objects                   |                                                               |
| `user`    | UID and GID mappings                      | Can be root inside while unprivileged outside       | [[Linux/virtualization/user-namespace\|User namespace]]       |
| `cgroup`  | The view of the cgroup hierarchy          | Sees its own cgroup as the root                     |                                                               |
| `time`    | Boot and monotonic clocks                 | Rarely used                                         |                                                               |

Namespaces are independent, and a process can share some and not others. That is exactly what a Kubernetes [[Kubernetes/concepts/L03-workloads/01-pods|pod]] is: several containers sharing one network and IPC namespace — held open by the [[Kubernetes/concepts/L09-advanced/09-pause-container|pause container]] — while keeping separate mount namespaces. `hostNetwork: true` simply means "do not create a network namespace".

## Build a container by hand

```bash
# 1. A root filesystem — borrow one from an image
mkdir rootfs && docker export $(docker create alpine) | tar -C rootfs -xf -

# 2. A new set of namespaces, with a shell inside
sudo unshare --pid --mount --uts --ipc --net --fork \
  chroot rootfs /bin/sh -c 'mount -t proc proc /proc && hostname box && exec /bin/sh'

# inside:
ps aux        # only the shell and ps — PID 1 is your shell
ip addr       # only a loopback interface, and it is down
hostname      # box
```

That is most of a container in two commands. A real runtime uses `pivot_root` instead of `chroot` (which is escapable), adds networking, drops privileges and applies limits — but nothing conceptually different.

To enter an existing container's namespaces from the host, without any container tooling:

```bash
sudo nsenter --target <pid> --net --pid --mount   # all of them
sudo nsenter --target <pid> --net ss -tlnp        # just the network namespace, with the HOST's tools
```

The second form is the trick for debugging minimal images that contain no shell and no tools: you borrow the container's network view and use binaries from the host. `kubectl debug` does the same thing with an ephemeral container — see [[Kubernetes/concepts/L08-operations/02-kubectl-debug|kubectl debug]].

## cgroups: what the process can use

Control groups organise processes into a tree and attach resource controllers to it. With cgroup v2 — the default on current distributions and what Kubernetes expects — the tree is a filesystem under `/sys/fs/cgroup`:

```bash
sudo mkdir /sys/fs/cgroup/demo
echo "50000 100000" | sudo tee /sys/fs/cgroup/demo/cpu.max     # 50 ms per 100 ms = half a CPU
echo "256M"         | sudo tee /sys/fs/cgroup/demo/memory.max
echo "100"          | sudo tee /sys/fs/cgroup/demo/pids.max
echo $$             | sudo tee /sys/fs/cgroup/demo/cgroup.procs # move this shell into it
```

| File                        | Effect                                                                | Kubernetes field          |
| :-------------------------- | :-------------------------------------------------------------------- | :------------------------ |
| `cpu.max`                   | Hard ceiling: throttled when the quota is used up within the period   | `resources.limits.cpu`    |
| `cpu.weight`                | Relative share when CPUs are contended                                | `resources.requests.cpu`  |
| `memory.max`                | Hard ceiling: exceeding it triggers the OOM killer **in this cgroup** | `resources.limits.memory` |
| `memory.min` / `memory.low` | Protected memory under pressure                                       | Memory QoS                |
| `pids.max`                  | Maximum number of processes — stops fork bombs                        | kubelet `podPidsLimit`    |
| `io.max`                    | Per-device throughput and IOPS limits                                 |                           |

Two behaviours explain a great many production mysteries:

- **CPU limits throttle, memory limits kill.** A container at its CPU limit gets slower. A container at its memory limit has a process killed with `OOMKilled` (exit code 137). There is no graceful degradation for memory.
- **Throttling happens per period.** A multi-threaded process can burn its whole quota in the first few milliseconds of each 100 ms period and then sit idle, which shows up as latency spikes at low average CPU. Check `cpu.stat` for `nr_throttled`.

More in [[Linux/kernel/cgroups|cgroups]] and [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|resource requests and limits]].

## A caution about what the process sees

Namespaces do not virtualise everything. `/proc/meminfo` and `/proc/cpuinfo` show the **host's** memory and CPUs, not the cgroup's limits. Older runtimes and tools that size heaps or thread pools from those files oversize themselves and are then throttled or killed. Modern JVMs, Go (with `GOMEMLIMIT` / automatic `GOMAXPROCS` awareness in recent releases), .NET and Node.js read the cgroup files; verify for anything else.

## Restricting what the process can do

Isolation of _view_ is not enough when the process is root.

| Mechanism                                       | Effect                                                                |
| :---------------------------------------------- | :-------------------------------------------------------------------- |
| [[Linux/security/capabilities\|Capabilities]]   | Root's privileges split into ~40 units; runtimes drop most by default |
| [[Linux/security/seccomp\|seccomp]]             | Blocks dangerous system calls (`mount`, `reboot`, `kexec_load`, …)    |
| [[Linux/security/apparmor\|AppArmor]] / SELinux | Mandatory access control on files and operations                      |
| `no_new_privs`                                  | Prevents gaining privileges through setuid binaries                   |
| Read-only root filesystem                       | The process cannot modify its own image                               |
| User namespaces                                 | Container root maps to an unprivileged host UID                       |

`--privileged` (or `privileged: true`) turns essentially all of this off: every capability, no seccomp, access to host devices. A privileged container is root on the node.

## The boundary, stated honestly

All containers on a host **share one kernel**. The isolation is a set of checks inside that kernel, and a kernel vulnerability can break all of them at once. That is the difference from a virtual machine, where the guest has its own kernel and the boundary is the much narrower hypervisor interface — see [[Linux/virtualization/hypervisors|hypervisors]].

For untrusted or multi-tenant code, add a stronger boundary: gVisor intercepts system calls in user space, Kata Containers and Firecracker give each pod its own lightweight VM. See [[Kubernetes/concepts/L07-security/02-workload-sandboxing/17-runtime-sandboxing|runtime sandboxing]] and [[Linux/security/container-security|container security]].

## Related

- [[Containers|Containers hub]]
- [[Containers/runtimes|Container runtimes]] — the software that performs these steps
- [[Containers/images-and-layers|Images and layers]] — where the root filesystem comes from
- [[Linux/kernel/process-management|Process management]] and [[Linux/kernel/signals|signals]] — why PID 1 behaves differently

## Across the wiki

- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/16-seccomp-apparmor|Seccomp and AppArmor]] — kernel sandboxing (Kubernetes)
- [[Security/kubernetes-security/pod-security/README|Pod Security]] — kernel sandboxing (Security)
- [[Linux/concepts/ulimit|ulimit]] — resource limits (Linux)
- [[Kubernetes/concepts/L05-config-storage/08-resource-quota|ResourceQuota and LimitRange]] — resource limits (Kubernetes)

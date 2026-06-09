# Runtime Sandboxing (gVisor, Kata Containers)

*"https://gvisor.dev/ | https://katacontainers.io/"*

By default, a container runs as a regular Linux process with kernel-level isolation (namespaces, cgroups, capabilities). For **multi-tenant** or **untrusted workloads**, this isn't enough — a kernel exploit in the container can compromise the host. **Runtime sandboxing** (gVisor, Kata Containers) is a stronger isolation layer: the container runs in a **user-space kernel** (gVisor) or a **hardware-virtualized microVM** (Kata). The container thinks it has a kernel, but the actual kernel is a layer removed. This is the **strongest workload isolation** available in k8s.

### Table of Contents

1. [The Threat Runtime Sandboxing Solves](#1-the-threat-runtime-sandboxing-solves)
2. [The Default Container Runtime (runc)](#2-the-default-container-runtime-runc)
3. [gVisor — the User-Space Kernel](#3-gvisor--the-user-space-kernel)
4. [Kata Containers — the Hardware Virtualization](#4-kata-containers--the-hardware-virtualization)
5. [The RuntimeClass Resource](#5-the-runtimeclass-resource)
6. [Choosing a Sandbox Runtime](#6-choosing-a-sandbox-runtime)
7. [The Performance Tradeoff](#7-the-performance-tradeoff)
8. [The Compatibility Tradeoff](#8-the-compatibility-tradeoff)
9. [Networking in Sandboxes](#9-networking-in-sandboxes)
10. [Resource Overhead](#10-resource-overhead)
11. [Common Patterns](#11-common-patterns)
12. [Operations and Debugging](#12-operations-and-debugging)
13. [Gotchas and Common Mistakes](#13-gotchas-and-common-mistakes)

---

## 1. The Threat Runtime Sandboxing Solves

The default container runtime is `runc` (or `crun`). The container is a process on the host's kernel. The kernel's namespaces, cgroups, capabilities, seccomp, AppArmor are the only isolation.

A kernel exploit — a vulnerability in a syscall handler, a race condition in the kernel, a misconfigured capability — **escapes the container and compromises the host**. The blast radius: every Pod on the node.

For **multi-tenant clusters** (you don't trust the workload) or **untrusted code** (third-party code, customer workloads), this is unacceptable. You need **a kernel between the workload and the host**.

Runtime sandboxing provides that:

* **gVisor** — a user-space kernel. The workload's syscalls are intercepted and re-implemented in user space. The host kernel sees the gVisor process, not the workload.
* **Kata Containers** — a microVM (QEMU / Cloud Hypervisor). The workload runs in a separate VM. The host kernel is the hypervisor, not the workload's kernel.

In both cases, **a kernel exploit in the workload compromises the sandbox, not the host**.

### 1.1 The threat model

The "kernel exploit" threat model:

* The workload is untrusted (or treated as such).
* The workload has a vulnerability that allows kernel-level code execution.
* The default container runtime (runc) executes the kernel code, which compromises the host.

With runtime sandboxing:

* The workload has the same vulnerability.
* The sandbox intercepts the kernel code before it reaches the host kernel.
* The exploit is contained within the sandbox.

This is **the strongest practical defense** against kernel exploits. It does NOT protect against:

* **Application-level exploits** — the app's own bugs.
* **Network-level exploits** — the workload can still make network calls.
* **Side-channel attacks** — Spectre / Meltdown style.

## 2. The Default Container Runtime (runc)

`runc` is the OCI reference implementation. The container is a process:

```
┌─────────────────────────────┐
│  Host Linux Kernel          │
│  ┌─────────────────────┐    │
│  │  runc               │    │
│  │  ┌──────────────┐  │    │
│  │  │  container    │  │    │
│  │  │  process      │  │    │
│  │  └──────────────┘  │    │
│  └─────────────────────┘    │
└─────────────────────────────┘
```

The container's process makes syscalls directly to the host kernel. The kernel's isolation (namespaces, cgroups, seccomp, capabilities) is the only barrier.

`runc` is the standard. containerd and CRI-O use it (or `crun`, a faster alternative). It's lightweight (no extra layer), well-understood, and supported everywhere.

The downside: **no defense against kernel exploits**. A container escape is a host compromise.

## 3. gVisor — the User-Space Kernel

*"https://gvisor.dev/"*

**gVisor** (from Google) is a **user-space kernel** written in Go. The container's process makes syscalls, but they go to **gVisor**, not the host kernel. gVisor re-implements the syscalls in user space, then makes a small set of calls to the host kernel (the "actual" syscalls are a curated subset).

```
┌──────────────────────────────┐
│  Host Linux Kernel           │
│  ┌────────────────────────┐  │
│  │  runsc (gVisor)         │  │
│  │  ┌───────────────────┐  │  │
│  │  │  Sentry           │  │  │
│  │  │  (user-space      │  │  │
│  │  │   kernel)         │  │  │
│  │  │  ┌─────────────┐ │  │  │
│  │  │  │  container   │ │  │  │
│  │  │  │  process     │ │  │  │
│  │  │  └─────────────┘ │  │  │
│  │  └───────────────────┘  │  │
│  └────────────────────────┘  │
└──────────────────────────────┘
```

The Sentry is gVisor's user-space kernel. It re-implements ~250 syscalls. The host kernel sees only a small set of syscalls (the "platform" calls) from gVisor.

### 3.1 gVisor's components

* **`runsc`** — the OCI runtime. Replaces `runc` in containerd / CRI-O.
* **`Sentry`** — the user-space kernel. Re-implements syscalls.
* **`Gofer`** — the file system proxy. The container's filesystem operations go through Gofer to the host.

The container is unaware. It sees a Linux environment, with a kernel, with a filesystem. The actual kernel and filesystem are gVisor's, on top of the host.

### 3.2 The interception

When the container calls `open("/etc/passwd", ...)`:

1. **Container process** makes the syscall.
2. **gVisor (Sentry)** intercepts it (via seccomp / ptrace).
3. **Sentry** looks up `/etc/passwd` in its VFS.
4. **Sentry** calls `Gofer` to fetch the file contents from the host.
5. **Sentry** returns the file data to the container.

The host kernel sees only the `Gofer`'s syscalls. The container's `open` doesn't reach the host kernel.

### 3.3 The performance

gVisor is **slower** than runc for syscall-heavy workloads:

* **CPU-intensive** — small overhead (~5-10%).
* **Syscall-heavy** (DB, network servers) — 1.5x-2x slower.
* **I/O-heavy** (file ops) — 2x-3x slower.

The gVisor team has been optimizing. The `runsc` runtime is now quite fast, but it's still a layer.

For **multi-tenant** workloads, the slowdown is acceptable (security > performance). For **latency-sensitive** workloads (search, ML serving), it's a concern.

## 4. Kata Containers — the Hardware Virtualization

*"https://katacontainers.io/"*

**Kata Containers** (merger of Intel Clear Containers and Hyper runV) is a **microVM-based** runtime. The container runs in a **separate VM** with its own kernel. The host sees a QEMU / Cloud Hypervisor process.

```
┌────────────────────────────────┐
│  Host Linux Kernel             │
│  ┌──────────────────────────┐  │
│  │  kata-runtime             │  │
│  │  ┌────────────────────┐  │  │
│  │  │  QEMU / CloudHv    │  │  │
│  │  │  ┌──────────────┐  │  │  │
│  │  │  │  container's  │  │  │  │
│  │  │  │  own kernel   │  │  │  │
│  │  │  │  ┌─────────┐  │  │  │  │
│  │  │  │  │  app     │  │  │  │  │
│  │  │  │  └─────────┘  │  │  │  │
│  │  │  └──────────────┘  │  │  │
│  │  └────────────────────┘  │  │
│  └──────────────────────────┘  │
└────────────────────────────────┘
```

The container has its own kernel. The host kernel is the hypervisor. A kernel exploit in the container compromises the guest kernel, not the host.

### 4.1 The microVM

A "microVM" is a VM with a minimal footprint:

* **Fast startup** — ~100ms (vs. seconds for traditional VMs).
* **Small memory** — ~50 MB minimum.
* **Minimal kernel** — the guest kernel is small and focused.

The hypervisor (QEMU or Cloud Hypervisor) is what runs the microVM. Cloud Hypervisor (from Intel) is the modern choice; it has less overhead than QEMU.

### 4.2 The agent

Inside the guest, the **kata-agent** is the equivalent of kubelet for the microVM. It starts the container, sets up networking, etc. The agent talks to the host's kata-runtime over a virtio channel.

### 4.3 The performance

Kata is **slower than runc** but **faster than gVisor** for some workloads:

* **CPU-intensive** — small overhead (~5-10%, similar to gVisor).
* **Syscall-heavy** — small overhead (the guest kernel is real, not user-space). Faster than gVisor.
* **I/O-heavy** — virtio overhead, similar to gVisor.

Kata is **closer to native** than gVisor for most workloads. The trade-off is **memory overhead** (each container has its own guest kernel + memory).

## 5. The RuntimeClass Resource

To use gVisor or Kata, you create a `RuntimeClass`:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: { name: gvisor }
spec:
  runtimeHandler: runsc
  scheduling:
    nodeSelector:
      sandbox-runtime: gvisor
```

The `runtimeHandler` matches what the CRI plugin (containerd, CRI-O) registers. For gVisor, it's `runsc`. For Kata, it's `kata` (or `kata-qemu`, `kata-clh`).

The `scheduling.nodeSelector` ensures the Pod only lands on nodes that have the runtime installed. Without this, a Pod asking for gVisor might land on a node without gVisor, and the kubelet will fail to start it.

Pods use the RuntimeClass via `spec.runtimeClassName`:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: myapp }
spec:
  runtimeClassName: gvisor
  containers:
  - name: app
    image: myapp:1.0
```

The kubelet sees `runtimeClassName: gvisor`, looks up the RuntimeClass, gets `runsc`, and asks containerd to start the container with `runsc` (instead of `runc`).

## 6. Choosing a Sandbox Runtime

| | runc (default) | gVisor | Kata |
|---|---|---|---|
| **Isolation** | Linux primitives (namespaces, cgroups, capabilities, seccomp) | User-space kernel | Hardware virtualization (microVM) |
| **Strength** | Default, well-understood | Strong against kernel exploits | Strongest (full kernel separation) |
| **Weakness** | Kernel exploits are node-compromising | Slow for syscall-heavy workloads | Memory overhead per container |
| **Performance** | Native | 1.5-2x slower for syscall-heavy | 1.1-1.3x slower for most |
| **Memory overhead** | None | Small (~10-50 MB) | Larger (~50-200 MB per microVM) |
| **Boot time** | <1s | ~1s | ~100-500ms |
| **Compatibility** | All Linux apps | Most (some syscalls not implemented) | All (full kernel) |
| **Use case** | Trusted workloads | Multi-tenant, untrusted | Highest isolation needs |

The decision:

* **runc** for trusted workloads (most production clusters).
* **gVisor** for multi-tenant or untrusted code, where the performance hit is acceptable.
* **Kata** for the highest isolation needs (e.g. running untrusted code that needs near-native performance).

## 7. The Performance Tradeoff

Both gVisor and Kata add overhead. The cost:

### 7.1 gVisor overhead

* **Syscall-heavy workloads** — 1.5-2x slower. Network servers, databases, language runtimes with frequent syscalls.
* **I/O-heavy** — 2-3x slower. File servers, build systems.
* **CPU-heavy** — small (~5%) overhead. The Sentry's syscall interception is cheap.
* **Memory** — small (~10-50 MB per container) for the Sentry and Gofer.

### 7.2 Kata overhead

* **Syscall-heavy** — small (~5-10%) overhead. The guest kernel is real; the host kernel sees only the hypervisor's calls.
* **I/O-heavy** — virtio overhead. Slower than runc, comparable to gVisor.
* **Memory** — larger (~50-200 MB per microVM) for the guest kernel and minimal userspace.
* **Boot time** — ~100-500ms per microVM. Not a concern for long-running, but noticeable for short-lived.

### 7.3 The benchmark reality

For most production workloads, the overhead is **manageable**. The exceptions:

* **High-RPS services** (>10k RPS) — the syscall overhead is per-request. 1.5x slowdown is 1.5x more nodes.
* **DB servers** — Postgres, MySQL have high syscall rates. 1.5x slowdown is real.
* **Real-time apps** — sub-millisecond latency is hard with an extra layer.

For **most other workloads** (web apps, batch jobs, async workers), the overhead is small.

## 8. The Compatibility Tradeoff

### 8.1 gVisor

gVisor re-implements ~250 syscalls. The gaps:

* **No `ioctl`** with arbitrary commands. gVisor implements a subset.
* **No raw sockets** (some networking apps).
* **No `bpf()`** (eBPF programs from inside the container).
* **Limited `ptrace`** (debugging tools that use ptrace may not work).
* **No `/proc/<pid>/mem`** reads from outside the container (used by some debuggers).

Most apps work. Some specialized apps (eBPF, debuggers, certain language runtimes) may not.

### 8.2 Kata

Kata has a **full kernel** in the guest. Most apps work. The exceptions:

* **Kernel modules** — the guest kernel is minimal; no loading of modules.
* **Direct hardware access** — the guest sees virtio devices, not real hardware.
* **Nested virtualization** — running a VM inside the container doesn't work.

For **most app containers** (web apps, services, batch), Kata works.

## 9. Networking in Sandboxes

The networking model in sandboxed runtimes is **the same as runc** from the cluster's perspective. The Pod gets an IP, the Service routes to it.

The difference is **inside the sandbox**:

* **gVisor** — networking is via a TAP device. The container's network stack is the host's (gVisor uses the host's TCP/IP). The Sentry handles the application-level protocols.
* **Kata** — networking is via a virtio-net device. The guest has its own network stack; the host is a bridge.

For the application, **networking is transparent**. The Pod has an IP, traffic flows in and out.

For advanced networking (eBPF, host networking, custom CNI), there are caveats:

* **gVisor + Cilium** — works (Cilium's eBPF is on the host; gVisor uses the host's network stack).
* **Kata + eBPF** — works (eBPF is on the host; Kata uses virtio-net).
* **gVisor + hostNetwork** — the container shares the host's network namespace. gVisor's interception is bypassed (syscalls go directly to the host).

## 10. Resource Overhead

Sandbox runtimes add resource overhead:

### 10.1 gVisor

* **Memory** — ~10-50 MB per container (Sentry + Gofer).
* **CPU** — small overhead per syscall.
* **Disk** — small (the gVisor binary itself).

### 10.2 Kata

* **Memory** — ~50-200 MB per microVM (guest kernel + minimal userspace).
* **CPU** — small overhead per virtio call.
* **Disk** — small (the kata-agent + qemu binary + guest kernel image).

For a 100-Pod cluster:
* **gVisor** — 1-5 GB overhead total.
* **Kata** — 5-20 GB overhead total.

This is **per-container overhead**. For high-density clusters (many small Pods), Kata's overhead is significant. gVisor's is more reasonable.

## 11. Common Patterns

### 11.1 Multi-tenant cluster (gVisor)

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: { name: gvisor }
spec:
  runtimeHandler: runsc
  scheduling:
    nodeSelector:
      sandbox-runtime: gvisor
  overhead:
    podFixed:
      memory: "120Mi"
      cpu: "250m"
```

The `overhead` field tells the scheduler that gVisor Pods have an extra overhead (the Sentry + Gofer). Without it, the scheduler places Pods as if they had no overhead, and the node runs out of memory.

### 11.2 High-isolation workloads (Kata)

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: { name: kata }
spec:
  runtimeHandler: kata
  scheduling:
    nodeSelector:
      sandbox-runtime: kata
  overhead:
    podFixed:
      memory: "200Mi"
      cpu: "250m"
```

The `overhead` for Kata is larger. The Pod's effective resources = container resources + overhead.

### 11.3 Per-namespace enforcement

To enforce gVisor for all Pods in a namespace, use an admission policy:

```yaml
# Kyverno or OPA Gatekeeper policy
# mutate: set spec.runtimeClassName: gvisor
# match: namespaces: ["untrusted"]
```

The Pods are forced to use gVisor. The user can't override (or you can use `validate` to reject Pods that don't have it).

## 12. Operations and Debugging

### 12.1 Common commands

```bash
# list RuntimeClasses
kubectl get runtimeclass

# describe
kubectl describe runtimeclass gvisor

# check a Pod's runtimeClassName
kubectl get pod <pod> -o jsonpath='{.spec.runtimeClassName}'

# on the node, check the container's runtime
crictl inspect <container-id> | grep runtime
# "runtimeType": "io.containerd.runsc.v2" (for gVisor)

# check the gVisor logs
# (the Sentry and Gofer log to a file, location depends on the runtime)
```

### 12.2 The "Pod stuck Pending" case (gVisor not installed)

A Pod with `runtimeClassName: gvisor` is Pending.

```bash
# 1. Is the RuntimeClass defined?
kubectl get runtimeclass gvisor
# if not, the Pod can't be scheduled

# 2. Does the node have the runtime?
# (on the node)
which runsc
# if not installed, the node can't run gVisor Pods

# 3. Does the nodeSelector match?
kubectl describe runtimeclass gvisor
# look at spec.scheduling.nodeSelector
kubectl get nodes --show-labels | grep sandbox-runtime
```

### 12.3 The "container fails to start" case (incompatible syscall)

A gVisor container starts, then crashes. The logs show `bad system call` or similar.

```bash
# 1. Check the container's logs
kubectl logs <pod>
# or
crictl logs <container-id>

# 2. Check gVisor's compatibility
# gVisor has a list of unsupported syscalls:
# https://gvisor.dev/docs/user_guide/compatibility/

# 3. Use Kata instead (if compatibility is the issue)
# Kata has a full kernel; most apps work
```

## 13. Gotchas and Common Mistakes

### 13.1 The 25+ common mistakes

1. **Runtime sandboxing is not a silver bullet.** It protects against kernel exploits. It doesn't protect against application-level exploits or network-level attacks.

2. **gVisor is slower for syscall-heavy workloads.** DB servers, high-RPS services, certain language runtimes. Benchmark before deploying.

3. **Kata has per-container memory overhead.** 50-200 MB per microVM. For high-density clusters, this is significant.

4. **The `RuntimeClass` must match the node's runtime.** A Pod asking for `gvisor` on a node without `runsc` installed fails to start.

5. **The `nodeSelector` in the RuntimeClass is critical.** Without it, the scheduler may place the Pod on a node that doesn't have the runtime.

6. **The `overhead` field is for the scheduler.** Without it, the scheduler under-counts the Pod's resources. The node runs out of memory / CPU.

7. **gVisor doesn't support all syscalls.** Apps that use `ioctl` with custom commands, raw sockets, or `bpf()` may not work.

8. **Kata doesn't support nested virtualization.** Running a VM inside a Kata container doesn't work.

9. **gVisor uses the host's TCP/IP stack.** The container's network behavior is the host's. There's no separate network namespace in the Sentry.

10. **Kata's guest kernel is small.** Some kernel modules are not available. The container's view of the kernel is limited.

11. **The container's `/proc` is sandboxed.** In gVisor, `/proc` is the Sentry's. In Kata, it's the guest's. Some debugging tools (`ps`, `top`) may show different info.

12. **The `runtimeHandler` value is the CRI plugin's name.** For gVisor, it's `runsc` (or `io.containerd.runsc.v2`). For Kata, it's `kata`, `kata-qemu`, or `kata-clh`. The exact value depends on the runtime's config.

13. **A RuntimeClass is cluster-wide.** A Pod in any namespace can use it (subject to RBAC).

14. **The kubelet doesn't validate the runtimeClassName.** A typo in the Pod's `runtimeClassName` means the Pod is Pending (no RuntimeClass matches).

15. **gVisor's Sentry is a single process per container.** If the Sentry crashes, the container crashes. The kubelet restarts it.

16. **Kata's microVM is a separate process.** The QEMU / Cloud Hypervisor process is the VM. The container's process is inside the VM.

17. **gVisor's `runsc` binary is OCI-compatible.** It works with any OCI-compliant container runtime (containerd, CRI-O).

18. **Kata's `kata-runtime` binary is OCI-compatible.** Same.

19. **gVisor's network performance** depends on the runtime's network mode (`runsc-bridge`, `runsc-ptp`, etc.). The default is `runsc-bridge`; check the cluster's config.

20. **Kata's virtio performance** depends on the virtio transport (`virtio-1`, `virtio-mmio`). The default is `virtio-1`; check the cluster's config.

21. **The seccomp / AppArmor layers still apply** to sandboxed runtimes. The Sentry or guest kernel is subject to the same kernel-level restrictions as the host.

22. **gVisor's `io_uring` support is limited.** Apps that use `io_uring` heavily may see lower performance.

23. **Kata's startup time is ~100-500ms.** This adds to Pod scheduling latency. For latency-sensitive apps, the cold start penalty is real.

24. **The `overhead` in RuntimeClass is per-Pod, not per-container.** A Pod with 3 containers has the overhead applied once (not 3x).

25. **gVisor doesn't support the `CAP_SYS_PTRACE` capability.** Apps that need ptrace (debuggers like `strace` from inside the container) don't work.

26. **Kata's guest kernel is fixed** (configured at install time). To upgrade, you update the guest kernel image and re-create Pods.

27. **gVisor's `runsc` has flags for the Sentry's behavior.** `--network=host` shares the host's network namespace; `--network=sandbox` uses a separate netns. Default is `sandbox`.

28. **Kata's `kata-runtime` has flags for the hypervisor.** `--vm-type=qemu` or `--vm-type=cloud-hypervisor`. The default is qemu; cloud-hypervisor is faster.

29. **gVisor's `gofer` is the file system proxy.** It's a separate process. The container's filesystem operations go through it.

30. **A sandbox runtime doesn't protect against a misconfigured Pod.** If the Pod has `privileged: true` and `hostNetwork: true`, the sandbox's isolation is bypassed (the container is on the host).

## See also

* [[Kubernetes/concepts/L07-security/05-security-context|SecurityContext]] — the standard hardening
* [[Kubernetes/concepts/L07-security/16-seccomp-apparmor|Seccomp / AppArmor]] — the kernel-level filters
* [[Kubernetes/concepts/L07-security/17-runtime-detection|Runtime Detection]] — detecting exploits even in sandboxes
* [[Kubernetes/concepts/L07-security/19-image-hardening|Image Hardening]] — reduce the attack surface before runtime

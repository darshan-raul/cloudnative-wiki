# Seccomp and AppArmor

*"https://kubernetes.io/docs/tutorials/security/seccomp/ | https://kubernetes.io/docs/tutorials/security/apparmor/"*

Seccomp and AppArmor are **Linux kernel security modules** that restrict what a process can do at the syscall / file level. They are the **last line of defense** in the container sandbox: PSS / SecurityContext restrict what a container is allowed to request, but seccomp and AppArmor restrict what the kernel will do for the process inside. This is defense-in-depth — even if an attacker exploits the app, the kernel's restrictions limit the blast radius.

### Table of Contents

1. [The Kernel Sandbox Layers](#1-the-kernel-sandbox-layers)
2. [Seccomp — the Syscall Filter](#2-seccomp--the-syscall-filter)
3. [The Seccomp Profile](#3-the-seccomp-profile)
4. [Seccomp in k8s](#4-seccomp-in-k8s)
5. [The RuntimeDefault Profile](#5-the-runtimedefault-profile)
6. [The Localhost Profile (Custom)](#6-the-localhost-profile-custom)
7. [Seccomp Profile Generation](#7-seccomp-profile-generation)
8. [AppArmor — the File + Capability Filter](#8-apparmor--the-file--capability-filter)
9. [The AppArmor Profile](#9-the-apparmor-profile)
10. [AppArmor in k8s](#10-apparmor-in-k8s)
11. [Seccomp vs AppArmor — When to Use Which](#11-seccomp-vs-apparmor--when-to-use-which)
12. [Common Patterns](#12-common-patterns)
13. [Operations and Debugging](#13-operations-and-debugging)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)

---

## 1. The Kernel Sandbox Layers

A container is a process. The kernel's sandboxing primitives limit what the process can do:

| Layer | What it restricts | Where it lives |
|---|---|---|
| **Linux capabilities** | Privileged operations (mount, raw socket, etc.) | `security.capability` |
| **Seccomp** | Syscalls (`open`, `read`, `write`, `clone`, ...) | `seccomp` |
| **AppArmor** | File paths, capabilities, network, mount | LSM (Linux Security Module) |
| **SELinux** | File paths, network, capabilities (more granular than AppArmor) | LSM |
| **Namespaces** | What the process can see (PIDs, network, mount) | `clone()` flags |
| **cgroups** | Resource limits (CPU, memory, disk) | cgroup fs |

Seccomp restricts **syscalls** — the process can only call a specific set. AppArmor restricts **file paths, capabilities, and network** — the process can only access a specific set of resources.

Both are **LSMs (Linux Security Modules)** — plug-ins to the kernel's security framework. They sit between the syscall interface and the kernel's actual operations.

## 2. Seccomp — the Syscall Filter

**Seccomp (Secure Computing Mode)** restricts the syscalls a process can make. The kernel evaluates each syscall: "is this syscall in the allow list? If yes, run it. If no, kill the process (with `SIGSYS`)."

The seccomp filter is a **BPF program** (the same BPF as eBPF / Cilium / Falco). It's loaded into the kernel via `prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ...)` or `seccomp(SECCOMP_SET_MODE_FILTER, ...)`.

The BPF program returns one of:

* `SECCOMP_RET_ALLOW` — the syscall runs.
* `SECCOMP_RET_ERRNO` — the syscall returns an error (with a specific errno).
* `SECCOMP_RET_TRAP` — the process is killed with `SIGSYS`.
* `SECCOMP_RET_LOG` — the syscall is allowed, but the action is logged.
* `SECCOMP_RET_KILL_PROCESS` — the process (and all threads) are killed.

The default in most kernels is `Unconfined` — all syscalls allowed. With seccomp, you narrow the set.

## 3. The Seccomp Profile

A seccomp profile is a JSON file that describes the allowed syscalls:

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_AARCH64"],
  "syscalls": [
    {
      "names": ["read", "write", "open", "close", "stat", "fstat", "mmap", "mprotect", "munmap", "brk", "rt_sigaction", "rt_sigprocmask", "rt_sigreturn", "ioctl", "nanosleep", "select", "mmap2", "madvise", "exit_group", "exit"],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

The structure:

* **`defaultAction`** — what to do for syscalls not explicitly listed. `SCMP_ACT_ERRNO` returns an error; `SCMP_ACT_KILL` kills the process.
* **`architectures`** — which CPU architectures the profile applies to.
* **`syscalls`** — list of rules. Each rule has syscall names and an action.

A **whitelist** profile has `defaultAction: SCMP_ACT_ERRNO` and explicit `SCMP_ACT_ALLOW` rules for allowed syscalls. A **blacklist** profile has `defaultAction: SCMP_ACT_ALLOW` and explicit `SCMP_ACT_ERRNO` rules for denied syscalls.

Whitelist is the standard for production. Blacklist is rarely correct.

## 4. Seccomp in k8s

In k8s, a seccomp profile is set via `securityContext.seccompProfile`:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: myapp }
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault        # or Localhost or Unconfined
  containers:
  - name: app
    image: myapp:1.0
    securityContext:
      seccompProfile:
        type: RuntimeDefault
```

Three values for `type`:

* **`Unconfined`** — no seccomp (the default). All syscalls allowed.
* **`RuntimeDefault`** — use the container runtime's default seccomp profile. This is a **safe superset** of syscalls the runtime considers safe.
* **`Localhost`** — use a custom profile loaded from the node (in `/var/lib/kubelet/seccomp/<name>.json`).

PSS `restricted` requires `seccompProfile.type: RuntimeDefault` or `Localhost` (no `Unconfined`).

## 5. The RuntimeDefault Profile

The container runtime (containerd, CRI-O) has a **default seccomp profile** that's safe for most workloads. It's a whitelist of syscalls that are commonly needed (read, write, mmap, etc.) and excludes dangerous ones (raw socket manipulation, kernel module loading, etc.).

`RuntimeDefault` is the **default for PSS `restricted`**. It applies a curated, safe profile without you having to write one.

The profile is in the runtime's source:

* **containerd's default** — a JSON file in the containerd repo.
* **CRI-O's default** — a JSON file in the CRI-O repo.

These profiles are **very similar** (whitelist of ~50 syscalls). They allow the common syscalls and deny the rest.

## 6. The Localhost Profile (Custom)

For workloads that need a custom seccomp profile (e.g. an app that uses a syscall not in the default):

1. **Write the profile** — a JSON file like the one above.
2. **Place it on every node** — at `/var/lib/kubelet/seccomp/<name>.json`.
3. **Reference it from the Pod**:

```yaml
seccompProfile:
  type: Localhost
  localhostProfile: profiles/my-profile.json
```

The `localhostProfile` is a **relative path** under `/var/lib/kubelet/seccomp/`. The kubelet reads the file and loads the profile.

The downside: **the profile is on every node**. With managed clusters (EKS, GKE), you can't add files to nodes. You'd use a DaemonSet that mounts the profile, or use the k8s-native seccomp profile (next section).

## 7. Seccomp Profile Generation

Writing a seccomp profile by hand is tedious. Tools:

* **bashica** (spd-tx) — generates from a process's actual syscalls. Run the app, capture the syscalls, generate a profile.
* **kubectl-debug** (Bhojwani) — runs in a pod, captures syscalls, generates a profile.
* **Kubernetes Security Profile Operator (SPO)** — generates and manages seccomp profiles as k8s objects.

The SPO is the **k8s-native way** to manage seccomp profiles. It:

1. Lets you create `SeccompProfile` CRDs.
2. Auto-generates profiles by recording an app's syscalls.
3. Distributes the profile to nodes (via a DaemonSet or a CSI driver).

```yaml
apiVersion: security-profiles-operator.x-k8s.io/v1beta1
kind: SeccompProfile
metadata: { name: my-app }
spec:
  defaultAction: SCMP_ACT_ERRNO
  syscalls:
  - names: [read, write, open, ...]
    action: SCMP_ACT_ALLOW
```

The SPO controller makes the profile available to all nodes. The Pod references it:

```yaml
seccompProfile:
  type: Localhost
  localhostProfile: my-app.json    # matches the SPO's name
```

## 8. AppArmor — the File + Capability Filter

**AppArmor** is a Linux Security Module that restricts:

* **File access** — which files the process can read / write / execute.
* **Capabilities** — which Linux capabilities the process has.
* **Network** — which network operations the process can do.
* **Mount** — which mount operations are allowed.

AppArmor is **path-based** — rules are tied to file paths. SELinux (the alternative) is **label-based** — rules are tied to inode labels. AppArmor is simpler; SELinux is more granular.

AppArmor is mostly used on **Debian / Ubuntu**. On RHEL / CentOS, the equivalent is SELinux.

## 9. The AppArmor Profile

An AppArmor profile is a text file (typically in `/etc/apparmor.d/`):

```
#include <tunables/global>

profile myapp flags=(attach_disconnected) {
  #include <abstractions/base>

  # Allow reading the app's data
  /var/lib/myapp/** r,
  /etc/myapp/** r,

  # Allow writing to its temp dir
  /tmp/** rw,

  # Deny writing to /etc
  deny /etc/** w,

  # Allow network
  network inet tcp,
  network inet6 tcp,

  # Deny raw socket
  deny network raw,

  # Allow capabilities
  capability dac_read_search,
  deny capability sys_admin,
}
```

The structure:

* **`profile myapp flags=(attach_disconnected)`** — the profile name and flags. `attach_disconnected` applies the profile to threads that don't have one.
* **`#include <abstractions/base>`** — common rules (read /lib, etc.).
* **Path rules** — `path permission,` (r = read, w = write, x = execute, etc.).
* **`deny`** — explicit denials.
* **`network`** — network rules.
* **`capability`** — Linux capabilities.

A profile is loaded into the kernel with `apparmor_parser`. Once loaded, the profile is in `/sys/kernel/security/apparmor/profiles`.

## 10. AppArmor in k8s

In k8s, an AppArmor profile is set via an **annotation**:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
  annotations:
    container.apparmor.security.beta.kubernetes.io/app: runtime/default
spec:
  containers:
  - name: app
    image: myapp:1.0
```

The annotation key is `container.apparmor.security.beta.kubernetes.io/<container-name>`. The value is:

* **`runtime/default`** — use the runtime's default profile.
* **`localhost/<profile-name>`** — use a profile loaded on the node (in `/etc/apparmor.d/<name>`).
* **`unconfined`** — no AppArmor.

The profile is **loaded on the node** (not in the Pod spec). The kubelet sets the profile via the container runtime.

### 10.1 Loading profiles

AppArmor profiles are loaded on each node:

1. **Write the profile** to `/etc/apparmor.d/<name>`.
2. **Parse it** with `apparmor_parser -r /etc/apparmor.d/<name>`.
3. **Reference it** from the Pod annotation.

For k8s-native management:

* **AppArmor profiles as a DaemonSet** — a DaemonSet that loads profiles on each node.
* **Security Profiles Operator (SPO)** — k8s-native AppArmor + seccomp management.

## 11. Seccomp vs AppArmor — When to Use Which

| | Seccomp | AppArmor |
|---|---|---|
| **Restricts** | Syscalls | Files, capabilities, network, mount |
| **Granularity** | Per-syscall | Per-path |
| **Profile format** | JSON | Text |
| **Common in k8s** | Very (PSS `restricted` requires it) | Less (annotation-based, OS-dependent) |
| **OS support** | All Linux | Debian / Ubuntu primarily |
| **Equivalent on RHEL** | (seccomp itself) | SELinux (different syntax) |

The decision:

* **Use seccomp** as a baseline. It's supported everywhere and is the PSS `restricted` requirement.
* **Use AppArmor** for additional path-based restrictions on Debian / Ubuntu. SELinux on RHEL.
* **Use both** for defense-in-depth (a syscall that bypasses seccomp is still caught by AppArmor, and vice versa).

For most clusters, **seccomp `RuntimeDefault` is enough**. AppArmor is added when there's a specific threat (e.g. "the app should never read /etc/shadow").

## 12. Common Patterns

### 12.1 PSS `restricted` baseline

```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop: ["ALL"]
  runAsNonRoot: true
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
```

This is the **safe default** for application containers. Seccomp narrows the syscalls; capabilities are dropped; no root; no privilege escalation; read-only root.

### 12.2 Custom seccomp for a specific app

```yaml
securityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: my-app-profile.json
```

The profile is on every node (via SPO or manual). The app gets its custom seccomp filter.

### 12.3 AppArmor for a privileged workload

```yaml
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/app: localhost/myapp
```

The profile is on the node. The workload's container gets the AppArmor filter.

### 12.4 The "deny all, allow specific" pattern

A seccomp profile that denies everything except a small whitelist:

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "syscalls": [
    {"names": ["read", "write", "exit", "exit_group"], "action": "SCMP_ACT_ALLOW"}
  ]
}
```

This is **the strictest seccomp profile**. The process can read, write, and exit — and nothing else. The process can't even open files (no `open` / `openat`).

For most apps, this is too restrictive (you need `open`, `mmap`, etc.). For some (e.g. a tight network-only app), it works.

## 13. Operations and Debugging

### 13.1 Common commands

```bash
# check the seccomp status of a Pod
kubectl get pod <pod> -o jsonpath='{.spec.securityContext.seccompProfile}'

# check the seccomp profile applied (on the node)
# find the container's cgroup
cat /proc/<pid>/status | grep Seccomp
# Seccomp: 0 = disabled, 1 = strict, 2 = filter
# 2 = filter (a profile is loaded)

# check the AppArmor profile (on the node)
cat /proc/<pid>/attr/current
# shows the current AppArmor profile

# list loaded AppArmor profiles
sudo aa-status
```

### 13.2 The "container is killed by seccomp" case

The container is `CrashLoopBackOff`. The logs show `Bad system call` (signal 31 / `SIGSYS`).

```bash
# 1. Check the seccomp profile
kubectl get pod <pod> -o jsonpath='{.spec.securityContext.seccompProfile}'

# 2. Check the container's syscalls
# (on the node, get the container's PID)
crictl inspect <container-id> | grep pid
# then strace the process
strace -p <pid> -e trace=all 2>&1 | tail
# shows the syscall that triggered the kill

# 3. If the profile is too strict, switch to Localhost with a custom profile
# (or remove the seccomp entirely as a test)
```

### 13.3 The "AppArmor denies access" case

The container can't read a file. The logs show permission denied (from AppArmor, not the FS).

```bash
# 1. Check the AppArmor profile
kubectl get pod <pod> -o jsonpath='{.metadata.annotations.container\.apparmor\.security\.beta\.kubernetes\.io\/<container>}'

# 2. Check the kernel audit
dmesg | grep -i apparmor
# shows "audit: type=1400 audit=... apparmor=\"DENIED\""

# 3. Update the profile
# add the path with the right permissions
```

## 14. Gotchas and Common Mistakes

### 14.1 The 25+ common mistakes

1. **`Unconfined` is the default.** Without explicit `seccompProfile.type: RuntimeDefault`, the container is unconfined. PSS `restricted` requires it.

2. **A seccomp profile that's too strict kills the container.** The container may need syscalls not in the default. Use `Localhost` for custom profiles.

3. **Seccomp is per-syscall, not per-app.** The filter applies to the process, regardless of the app. The process can't call `open` if `open` is not in the allow list.

4. **AppArmor is path-based.** A rule like `/var/lib/myapp/** r` allows reading the path. **But not following symlinks** (the path traversal is the access check, not the symlink target).

5. **AppArmor profiles must be loaded on the node.** A Pod can't reference a profile that's not on the node.

6. **The annotation is `container.apparmor.security.beta.kubernetes.io/<container-name>`.** Not `apparmor.security.beta.kubernetes.io`. The container name matters.

7. **`runtime/default` is the runtime's default AppArmor profile.** It may be very permissive (or non-existent). Don't assume it.

8. **Seccomp and AppArmor are not the same.** They restrict different things. Use both for defense-in-depth.

9. **SELinux is the RHEL equivalent of AppArmor.** On RHEL, the container runtime enables SELinux by default. The default SELinux policy is `container_t`.

10. **The kubelet doesn't validate the seccomp profile.** A `Localhost` reference to a non-existent file is silently ignored (the container runs unconfined).

11. **The kubelet doesn't validate the AppArmor profile either.** A `localhost/<name>` reference to a non-existent profile is silently ignored.

12. **A seccomp filter that returns `SCMP_ACT_LOG` is for debugging.** The syscall is allowed, but the action is logged. Use this to generate profiles.

13. **The seccomp profile is loaded by the container runtime, not k8s.** The runtime (containerd, CRI-O) reads the profile and configures the container's seccomp filter.

14. **The `RuntimeDefault` profile is the runtime's, not k8s's.** Containerd and CRI-O have different defaults (slightly). The PSS `restricted` requirement is "RuntimeDefault or Localhost", and either is fine.

15. **Seccomp is for syscalls only.** File access is not blocked by seccomp — the kernel's VFS handles that. AppArmor or SELinux is needed for file restrictions.

16. **A seccomp filter that returns `SCMP_ACT_KILL` is irreversible.** The process is killed. Use `SCMP_ACT_ERRNO` for tests (the syscall fails with a specific error, the process can handle it).

17. **A seccomp filter is inherited by child processes.** Forking a process inherits the filter. The child can't call syscalls not in the parent's filter.

18. **The seccomp BPF program runs in the kernel.** It's fast (~100ns per syscall). The overhead is negligible.

19. **AppArmor doesn't replace SELinux on systems that have both.** On Ubuntu, AppArmor is loaded; SELinux is not. On RHEL, SELinux is loaded; AppArmor is not. They don't conflict, but only one is active.

20. **The kubelet's `--seccomp-profile-root` flag controls where to look for `Localhost` profiles.** Default `/var/lib/kubelet/seccomp/`. If you change it, your profiles need to be there.

21. **The kubelet's `--allowed-unsafe-sysctls` and `--seccomp-default` flags control defaults.** With `--seccomp-default=true`, the kubelet sets `RuntimeDefault` for all containers that don't have a profile. This is a hardening default.

22. **A seccomp profile is per-container, not per-Pod.** A multi-container Pod can have different profiles for each container.

23. **The seccomp filter is a BPF program, not a JSON file in the kernel.** The kubelet / runtime parses the JSON and compiles it to BPF. The BPF is loaded into the kernel.

24. **A seccomp filter can have multiple actions per syscall.** You can have `SCMP_ACT_LOG` for one syscall and `SCMP_ACT_ALLOW` for another. The first matching rule wins.

25. **The seccomp profile name in `localhostProfile` is a relative path.** The kubelet appends it to `--seccomp-profile-root`. So `localhostProfile: profiles/my.json` resolves to `/var/lib/kubelet/seccomp/profiles/my.json`.

26. **An AppArmor profile is loaded once, not per-container.** The profile is in the kernel; containers reference it by name.

27. **The `unconfined` annotation value disables AppArmor.** Don't use it for production.

28. **Seccomp doesn't restrict the `ioctl` syscall fully.** A seccomp filter can allow / deny `ioctl`, but the arguments (which device) are not filterable. For device-level restrictions, use AppArmor or SELinux.

29. **A `seccompProfile.type: Localhost` without the file present is silently ignored.** The container runs unconfined. Check the kubelet's log for warnings.

30. **The Seccomp and AppArmor layers are independent.** A container can have `seccompProfile: RuntimeDefault` and `container.apparmor.security.beta.kubernetes.io/app: runtime/default` simultaneously. Both apply.

## See also

* [[Kubernetes/concepts/L07-security/05-security-context|SecurityContext]] — where seccomp / AppArmor are set
* [[Kubernetes/concepts/L07-security/06-pod-security-standards|PSS]] — requires `RuntimeDefault` seccomp for `restricted`
* [[Kubernetes/concepts/L07-security/17-runtime-sandboxing|Runtime Sandboxing]] — gVisor / Kata as stronger alternatives
* [[Kubernetes/concepts/L07-security/19-runtime-detection|Runtime Detection]] — Falco / Tetragon detect syscall anomalies

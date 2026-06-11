# SecurityContext

*"https://kubernetes.io/docs/tasks/configure-pod-container/security-context/"*

A `SecurityContext` defines **privilege and access control settings** for a Pod or Container. It runs from "do almost nothing" (default) to "do everything" (`privileged: true`). Most production clusters should be **far from privileged** — the `restricted` PSS profile (covered in [[Kubernetes/concepts/L07-security/02-workload-sandboxing/06-pod-security-standards|PSS]]) is the safe default. This note covers every field, the layered defense model, and the real recipes for hardening.

### Table of Contents

1. [The Two Scopes (Pod vs Container)](#1-the-two-scopes-pod-vs-container)
2. [The Field Reference](#2-the-field-reference)
3. [The User / Group Fields](#3-the-user--group-fields)
4. [The Filesystem Fields](#4-the-filesystem-fields)
5. [The Privilege Fields](#5-the-privilege-fields)
6. [The Capability Fields](#6-the-capability-fields)
7. [The Seccomp and AppArmor Fields](#7-the-seccomp-and-apparmor-fields)
8. [The Sysctl Fields](#8-the-sysctl-fields)
9. [The SELinux Fields](#9-the-selinux-fields)
10. [The "restricted" PSS Baseline in Depth](#10-the-restricted-pss-baseline-in-depth)
11. [The fsGroup Mechanics](#11-the-fsgroup-mechanics)
12. [The runAsNonRoot Mechanics](#12-the-runasnonroot-mechanics)
13. [The readOnlyRootFilesystem Caveats](#13-the-readonlyrootfilesystem-caveats)
14. [The Capabilities Allow List](#14-the-capabilities-allow-list)
15. [The "Drop ALL" Pattern](#15-the-drop-all-pattern)
16. [Common Real-World Recipes](#16-common-real-world-recipes)
17. [Operations and Debugging](#17-operations-and-debugging)
18. [Gotchas and Common Mistakes](#18-gotchas-and-common-mistakes)

---

## 1. The Two Scopes (Pod vs Container)

A `SecurityContext` can be set at **two levels**:

* **Pod-level** (`spec.securityContext`) — applies to all containers in the Pod.
* **Container-level** (`spec.containers[].securityContext`) — applies to that container.

For fields that are both Pod-level and Container-level (e.g. `runAsUser`), the **container-level value overrides the Pod-level value**.

```yaml
apiVersion: v1
kind: Pod
metadata: { name: app }
spec:
  securityContext:                  # Pod-level
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    fsGroupChangePolicy: OnRootMismatch
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: app:1.0
    securityContext:                # Container-level (overrides Pod-level for shared fields)
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      capabilities:
        drop: ["ALL"]
        add: ["NET_BIND_SERVICE"]   # only if you need to bind < 1024
      seccompProfile:
        type: RuntimeDefault
  - name: sidecar
    image: sidecar:1.0
    # inherits Pod-level securityContext, but no container-level overrides
```

Pod-level fields:

* `runAsUser`, `runAsGroup`, `runAsNonRoot`
* `fsGroup`, `fsGroupChangePolicy`
* `seccompProfile`, `appArmorProfile` (via annotation)
* `sysctls` (deprecated; use `securityContext.sysctls` on the container)
* `supplementalGroups`
* `fsGroupChangePolicy`

Container-level fields (additional):

* `allowPrivilegeEscalation`
* `readOnlyRootFilesystem`
* `privileged`
* `capabilities` (add / drop)
* `seccompProfile` (overrides Pod-level)
* `procMount`

## 2. The Field Reference

| Field | Scope | Default | What it does |
|---|---|---|---|
| `runAsUser` | Pod / Container | (image's USER) | UID for the container process |
| `runAsGroup` | Pod / Container | (image's GROUP) | GID for the container process |
| `runAsNonRoot` | Pod / Container | false | Reject if the container would run as root (UID 0) |
| `fsGroup` | Pod | (none) | GID for volume ownership — group-writable volumes |
| `fsGroupChangePolicy` | Pod | Always | When to chown the volume |
| `supplementalGroups` | Pod | (none) | Additional GIDs the user is in |
| `readOnlyRootFilesystem` | Container | false | Mount the root filesystem read-only |
| `allowPrivilegeEscalation` | Container | true | Allow setuid binaries and capabilities to gain privileges |
| `privileged` | Container | false | Run as effectively root on the host (almost never) |
| `capabilities.add` | Container | (none) | Linux capabilities to add |
| `capabilities.drop` | Container | (none) | Linux capabilities to drop |
| `seccompProfile.type` | Pod / Container | Unconfined | Seccomp filter (RuntimeDefault, Localhost, Unconfined) |
| `seccompProfile localhostProfile` | Pod / Container | (none) | Local seccomp profile (if type=Localhost) |
| `appArmorProfile.type` | (via annotation) | RuntimeDefault | AppArmor profile (RuntimeDefault, Localhost, Unconfined) |
| `procMount` | Container | Default | /proc mount type (Default, Unmasked) |
| `sysctls` | Pod / Container | (none) | Allowed kernel tunables |

## 3. The User / Group Fields

### 3.1 `runAsUser`

```yaml
securityContext:
  runAsUser: 1000
```

Sets the **UID** of the container process. The container's process runs as this UID inside the container's namespace. (On the host, with user namespaces, the UID is remapped.)

The image's `USER` directive is overridden. If the image expects to run as a specific UID, setting `runAsUser` may break it.

### 3.2 `runAsGroup`

```yaml
securityContext:
  runAsGroup: 3000
```

Sets the **GID** of the container process. The process is in this group (and any `supplementalGroups`).

### 3.3 `runAsNonRoot`

```yaml
securityContext:
  runAsNonRoot: true
```

**Rejects the Pod** if the container would run as root (UID 0). The admission controller checks:

* `runAsUser` is not 0.
* The image's `USER` is not 0 (or not set, in which case the default is root, so the Pod is rejected).

`runAsNonRoot: true` is a **hard guarantee**. If the image's `USER` is `0` (root) and you don't set `runAsUser`, the Pod is rejected.

### 3.4 `supplementalGroups`

```yaml
securityContext:
  supplementalGroups: [1234, 5678]
```

Additional GIDs the user is in (besides the primary GID). Useful for accessing group-owned volumes.

## 4. The Filesystem Fields

### 4.1 `fsGroup`

```yaml
securityContext:
  fsGroup: 2000
```

The **GID for volume ownership**. When a volume is mounted, the kubelet:

1. `chown`s the volume to this GID.
2. Adds this GID to the container's groups.
3. The container's process can read / write group-owned files.

This applies to **all volumes** the Pod mounts, including `emptyDir`, `hostPath`, `configMap`, `secret`, `persistentVolumeClaim`.

### 4.2 `fsGroupChangePolicy`

```yaml
securityContext:
  fsGroup: 2000
  fsGroupChangePolicy: OnRootMismatch   # or "Always"
```

Controls when the `chown` happens:

* **`Always`** (default) — `chown` the volume's root and all files. **Slow for large volumes** (e.g. a PVC with 100 GB).
* **`OnRootMismatch`** — `chown` only if the volume's root is not already owned by the `fsGroup`. **Fast for large volumes**.

For `configMap`, `secret`, `downwardAPI`, `projected`: the kubelet always uses `OnRootMismatch` (these are read-only).

For `emptyDir`, `hostPath`, `nfs`, `persistentVolumeClaim`: the policy is respected.

### 4.3 `readOnlyRootFilesystem`

```yaml
securityContext:
  readOnlyRootFilesystem: true
```

Mounts the container's **root filesystem as read-only**. The container can't write to `/`, `/usr`, `/etc`, etc. (whatever's in the image).

To write anywhere, mount a writable `emptyDir` or `persistentVolumeClaim` at the write path.

```yaml
volumes:
- name: scratch
  emptyDir: {}
volumeMounts:
- name: scratch
  mountPath: /tmp
- name: scratch
  mountPath: /var/cache
```

`readOnlyRootFilesystem: true` is part of the `restricted` PSS profile. It prevents:

* The app from modifying the image's files (e.g. writing to `/etc/nginx`).
* An attacker from modifying the image's files (e.g. replacing a binary).

Most apps work with `readOnlyRootFilesystem: true` if you mount writable volumes for the write paths.

### 4.4 The `procMount` field

```yaml
securityContext:
  procMount: Unmasked
```

Controls the `/proc` mount type:

* **`Default`** — the standard `/proc` (with some restrictions).
* **`Unmasked`** — the full `/proc` (like a regular host).

`Unmasked` is rare; most apps work with `Default`. PSS `restricted` requires `Default`.

## 5. The Privilege Fields

### 5.1 `allowPrivilegeEscalation`

```yaml
securityContext:
  allowPrivilegeEscalation: false
```

Controls whether the container can **gain privileges** via `setuid` binaries, file capabilities, or other mechanisms.

* **`true`** (default) — the container can use `setuid` to escalate. The app can call `setuid(0)` to become root.
* **`false`** — the container can't escalate. The `no_new_privs` flag is set, preventing privilege escalation.

`allowPrivilegeEscalation: false` is part of the `restricted` PSS profile. It prevents:

* `setuid 0` calls.
* File capability-based escalation.
* Other no-new-privileges mechanisms.

Some apps need setuid (e.g. installers, package managers). For most app containers, this is fine.

### 5.2 `privileged`

```yaml
securityContext:
  privileged: true
```

**Disables almost all isolation**. The container can:

* See all host devices.
* Mount filesystems.
* Modify kernel parameters.
* Do anything the host's root can do.

`privileged: true` is for:

* **CNI plugins** (Calico, Cilium, etc.) — they need to manipulate the network.
* **Storage daemons** (some CSI drivers).
* **GPU drivers** (NVIDIA device plugin).
* **System Pods** (kube-proxy in some configs).

**For application code, `privileged: true` is a near-universal red flag.** If an app claims to need it, find out what capability it actually needs and grant that explicitly.

PSS `baseline` blocks `privileged: true` for application namespaces.

## 6. The Capability Fields

*"https://man7.org/linux/man-pages/man7/capabilities.7.html"*

Linux **capabilities** are fine-grained privileges. A process can have a subset of root's powers (e.g. `CAP_NET_BIND_SERVICE` to bind port 80, but not `CAP_SYS_ADMIN`).

The full list has ~40 capabilities. The default set for a container is the **same as root** (because the container's UID is 0 by default, or runs as a user with all capabilities).

`capabilities.drop` and `capabilities.add` are the tools to narrow the set:

```yaml
securityContext:
  capabilities:
    drop: ["ALL"]
    add: ["NET_BIND_SERVICE"]   # only if you need to bind < 1024
```

`drop: ["ALL"]` removes every capability. `add: [...]` adds specific ones. **The "drop ALL" pattern is the standard.**

### 6.1 The capabilities you might need

| Capability | Purpose | When you need it |
|---|---|---|
| `NET_BIND_SERVICE` | Bind port < 1024 | Apps binding port 80/443 without root |
| `NET_RAW` | Use raw sockets (ping, etc.) | Network diagnostic tools |
| `SYS_PTRACE` | ptrace other processes | Debuggers (strace, gdb) |
| `SYS_ADMIN` | Many admin operations | **Almost never for app containers** |
| `SYS_RESOURCE` | Override resource limits | Resource-intensive tools |
| `DAC_OVERRIDE` | Bypass file permission checks | Apps reading arbitrary files |
| `CHOWN` | Change file ownership | Apps that need to chown |
| `FOWNER` | Bypass owner checks | Apps modifying files regardless of owner |
| `SETUID`, `SETGID` | Change UID/GID | Apps that change user |

`SYS_ADMIN` is the **most dangerous**. It includes mount, swapon, setns, and many other admin operations. PSS `baseline` blocks it for app namespaces.

## 7. The Seccomp and AppArmor Fields

See [[Kubernetes/concepts/L07-security/02-workload-sandboxing/16-seccomp-apparmor|Seccomp / AppArmor]] for the full treatment. The fields:

```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault   # or Localhost, Unconfined
    localhostProfile: profiles/my-app.json   # if type=Localhost
```

PSS `restricted` requires `RuntimeDefault` or `Localhost`. The default is `Unconfined` (no seccomp).

## 8. The Sysctl Fields

```yaml
securityContext:
  sysctls:
  - name: net.core.somaxconn
    value: "1024"
```

Pod can set safe sysctls. With `protectKernelDefaults: true` on the kubelet, only **safe** sysctls are allowed. Unsafe sysctls require an admission policy to allow.

See [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/21-node-hardening|Node Hardening]] for the full sysctl list.

## 9. The SELinux Fields

```yaml
securityContext:
  seLinuxOptions:
    user: "system_u"
    role: "system_r"
    type: "container_t"
    level: "s0"
```

For SELinux-enabled systems (RHEL). The `type` is the SELinux type. `container_t` is the default for containers.

PSS `baseline` requires the default SELinux options (no custom user/role/type/level).

## 10. The "restricted" PSS Baseline in Depth

The PSS `restricted` profile is the **safe default** for untrusted workloads. It requires:

```yaml
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop: ["ALL"]
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
```

Plus:

* No `privileged: true`.
* No `hostNetwork`, `hostPID`, `hostIPC`.
* No `hostPath` volumes.
* No dangerous capabilities.
* The image's `USER` is non-root (or set `runAsUser`).

A Pod that meets `restricted` is generally safe to run as a default workload.

## 11. The fsGroup Mechanics

The `fsGroup` field has subtle mechanics.

### 11.1 What gets chowned

The kubelet chowns the **root** of the volume to the `fsGroup` GID. For a `persistentVolumeClaim`, the root is the mount point. For an `emptyDir`, the root is the directory.

Files **inside** the volume are not recursively chowned by default. With `fsGroupChangePolicy: OnRootMismatch`, only the root is chowned. With `Always`, all files are chowned (slow).

### 11.2 The runtime chown

Some runtimes (containerd 1.5+) support **lazy fsGroup chown**. The chown is done when the volume is first accessed, not on mount. This is much faster for large volumes.

### 11.3 The group permission

After `fsGroup: 2000`, the volume's files have `group: 2000`. The container's process is in group 2000. So the process can read / write group-owned files.

If the image's app writes to a file with mode 0644 (no group write), the `fsGroup` doesn't help. The app needs to set group-write permissions (e.g. `chmod g+w`).

## 12. The runAsNonRoot Mechanics

`runAsNonRoot: true` is enforced at admission. The check:

1. If `runAsUser` is set, it must be != 0.
2. If `runAsUser` is not set, the image's `USER` must be != 0.
3. If neither is set, the Pod is rejected.

The check is done by the `SecurityContextDeny` admission plugin (deprecated) and the `PodSecurity` admission plugin (modern).

A common issue: the image runs as root (many do), and the user sets `runAsNonRoot: true` without `runAsUser`. The Pod is rejected with `CreateContainerConfigError`.

**Fix**: set `runAsUser` explicitly, or build a non-root image.

## 13. The readOnlyRootFilesystem Caveats

`readOnlyRootFilesystem: true` is great for security but breaks apps that write to the root filesystem. The common write paths:

* `/tmp` — temp files.
* `/var/cache` — cached data.
* `/var/log` — logs.
* `/var/run` — runtime data.
* `/home/<user>/.cache` — user cache.

The fix: mount `emptyDir` at each write path.

```yaml
volumes:
- name: tmp
  emptyDir: { medium: Memory }    # in-memory for security (no disk)
- name: cache
  emptyDir: {}
volumeMounts:
- name: tmp
  mountPath: /tmp
- name: cache
  mountPath: /var/cache
```

For app-specific write paths, check the app's documentation. Most apps have a config option to change the write path.

## 14. The Capabilities Allow List

The k8s-recommended capability allow list for `restricted`:

```yaml
capabilities:
  drop: ["ALL"]
  add: []    # no additions
```

This is the **strictest**. The container has no capabilities beyond the default user. To bind port 80, you'd need to run as root (with `runAsUser: 0`) or add `NET_BIND_SERVICE`.

For apps that need specific capabilities:

```yaml
capabilities:
  drop: ["ALL"]
  add: ["NET_BIND_SERVICE"]
```

PSS `restricted` allows `NET_BIND_SERVICE` (and a few others) in addition. For everything else, the Pod is rejected at admission.

## 15. The "Drop ALL" Pattern

The "drop ALL" pattern is the standard:

```yaml
securityContext:
  capabilities:
    drop: ["ALL"]
```

This removes every capability. The container has no special privileges. To add back specific ones, use `add: [...]`.

The pattern is:

1. Drop all.
2. Add only what you need.

This is the **principle of least privilege** at the capability level.

## 16. Common Real-World Recipes

### 16.1 A stateless web app

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop: ["ALL"]
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
```

### 16.2 A workload binding port 80

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  capabilities:
    drop: ["ALL"]
    add: ["NET_BIND_SERVICE"]
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
seccompProfile:
  type: RuntimeDefault
```

### 16.3 A workload that needs writable `/tmp`

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
  # mount emptyDir for /tmp
volumes:
- name: tmp
  emptyDir: { medium: Memory }   # in-memory
volumeMounts:
- name: tmp
  mountPath: /tmp
```

### 16.4 A workload that needs to chown files

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop: ["ALL"]
    add: ["CHOWN", "FOWNER"]
```

### 16.5 A workload that uses Docker-in-Docker (CI runner)

```yaml
securityContext:
  privileged: true    # required for DinD
  # OR use a sidecar with sysctls
```

DinD is one of the few legitimate uses of `privileged: true`. The standard alternative is **sysbox** (a nested container runtime).

## 17. Operations and Debugging

### 17.1 Common commands

```bash
# check a Pod's securityContext
kubectl get pod <pod> -o jsonpath='{.spec.securityContext}'
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].securityContext}'

# check the running process's UID/GID
kubectl exec <pod> -- id
# uid=1000 gid=3000 groups=3000

# check the running process's capabilities
kubectl exec <pod> -- cat /proc/1/status | grep Cap

# check the container's effective capabilities
kubectl exec <pod> -- grep CapEff /proc/self/status
```

### 17.2 The "Pod rejected with CreateContainerConfigError" case

The Pod is rejected because the securityContext can't be satisfied.

```bash
# 1. Check the events
kubectl describe pod <pod>
# look for: "container has runAsNonRoot and image will run as root"

# 2. Check the image's USER
docker inspect <image> | jq '.[0].Config.User'

# 3. Set runAsUser explicitly
kubectl edit pod <pod>
# add: runAsUser: 1000
```

### 17.3 The "Pod is CrashLoopBackOff" case

The container starts and immediately crashes, often because of a capability or seccomp issue.

```bash
# 1. Check the logs
kubectl logs <pod> --previous
# look for: "operation not permitted", "permission denied", "no_new_privs"

# 2. Check the container's runtime constraints
# (on the node)
crictl inspect <container-id> | grep -i 'seccomp\|capabilit'
```

## 18. Gotchas and Common Mistakes

### 18.1 The 30+ common mistakes

1. **`runAsNonRoot: true` rejects images that run as root by default.** Many base images do. Set `runAsUser` explicitly, or build a non-root image.

2. **`readOnlyRootFilesystem: true` breaks apps that write to the image.** Mount `emptyDir` at the write paths.

3. **`allowPrivilegeEscalation: false` blocks setuid binaries.** Some installers need setuid. For most app containers, this is fine.

4. **`fsGroup` only applies to volumes mounted after the Pod starts.** Pre-populated volumes (ConfigMap, downwardAPI, projected) don't get the chown unless you use `fsGroupChangePolicy: OnRootMismatch`.

5. **`fsGroup: 0` is the same as not setting `fsGroup`.** The default GID is 0.

6. **`capabilities.drop: ["ALL"]` removes the default capabilities.** Without `add: [...]`, the container has no special privileges. To bind port 80, add `NET_BIND_SERVICE`.

7. **`capabilities.add` doesn't whitelist capabilities.** It adds to the default set. If you don't `drop: ["ALL"]` first, the container has all capabilities.

8. **`seccompProfile.type: Unconfined` is the default.** PSS `restricted` requires `RuntimeDefault` or `Localhost`.

9. **`seccompProfile.type: Localhost` requires the profile to be on the node.** A reference to a non-existent profile is silently ignored.

10. **`privileged: true` is a near-universal red flag** for application code. Only system Pods (CNI, GPU, etc.) need it.

11. **`hostNetwork: true` bypasses NetworkPolicy.** The Pod is on the host's network namespace, not the Pod network. Use `hostAlias` for limited /etc/hosts changes instead.

12. **`hostPID: true` and `hostIPC: true` are dangerous.** PSS `baseline` blocks them.

13. **`procMount: Unmasked` is for tools that need full /proc.** Rare for app containers. PSS `restricted` requires `Default`.

14. **`seLinuxOptions` for SELinux-enabled systems.** The default is fine for most apps.

15. **`supplementalGroups` is for additional GIDs.** Use it for accessing group-owned volumes.

16. **`runAsUser` overrides the image's USER.** If the image expects to run as a specific UID, this may break.

17. **`runAsGroup` overrides the image's GROUP.** Same.

18. **`runAsNonRoot` is enforced at admission.** Once the Pod is running, the check is gone. The kubelet doesn't kill a Pod if it tries to switch to root.

19. **`readOnlyRootFilesystem` and `subPath` interact subtly.** A `subPath` mount can write to a read-only root if the subPath is on a writable volume.

20. **`emptyDir.medium: Memory` is in tmpfs (RAM).** Faster but uses memory. Don't use for large data.

21. **`securityContext` is per-Pod, not per-Container.** Some fields (e.g. `fsGroup`) are only at the Pod level. Setting them at the Container level is ignored.

22. **The container-level `securityContext` overrides the Pod-level for shared fields.** The non-shared fields (e.g. `fsGroup` at the Pod level, `capabilities` at the Container level) don't override.

23. **The `setuid` binary can escalate** unless `allowPrivilegeEscalation: false`. The `no_new_privs` flag is what prevents it.

24. **`/proc/<pid>/status` shows the container's effective capabilities.** `grep Cap` to see.

25. **The capabilities are the **container's**, not the host's.** They're set via the `AmbientCapabilities` and the container's `BoundingSet` / `EffectiveSet`.

26. **The `runAsUser: 0` and `allowPrivilegeEscalation: false` is contradictory.** UID 0 with no-new-privs. The app runs as root but can't escalate. Rare.

27. **A `readOnlyRootFilesystem: true` Pod with `hostPath` is a leak.** The hostPath is read-only too, but the host's files are exposed.

28. **`hostAliases` is the safe way to add /etc/hosts entries.** `hostNetwork: true` is for when you need the host's network namespace.

29. **`shareProcessNamespace: true` shares PID namespace between containers.** Useful for sidecar patterns. Not a security issue per se.

30. **`automountServiceAccountToken: false` for Pods that don't need apiserver access.** The default SA token is auto-mounted. Disabling saves a mount and reduces attack surface.

## See also

* [[Kubernetes/concepts/L07-security/02-workload-sandboxing/06-pod-security-standards|PSS]] — the namespace-level enforcement
* [[Kubernetes/concepts/L07-security/02-workload-sandboxing/16-seccomp-apparmor|Seccomp / AppArmor]] — the kernel-level restrictions
* [[Kubernetes/concepts/L07-security/02-workload-sandboxing/17-runtime-sandboxing|Runtime Sandboxing]] — gVisor / Kata for stronger isolation
* [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image Hardening]] — build non-root images
* [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/20-cluster-hardening|Cluster Hardening]] — the apiserver flags

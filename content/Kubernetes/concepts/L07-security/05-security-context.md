# SecurityContext

*"https://kubernetes.io/docs/tasks/configure-pod-container/security-context/"*

A SecurityContext defines **privilege and access control settings** for a Pod or Container. It runs from "do almost nothing" (default) to "do everything" (privileged). Most production clusters should be **far from privileged**.

## Two scopes

* **Pod-level `securityContext`** — applies to all containers in the Pod
* **Container-level `securityContext`** — applies to that container only (overrides Pod-level for fields they share)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
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
    securityContext:                # Container-level
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      capabilities:
        drop: ["ALL"]
        add: ["NET_BIND_SERVICE"]   # only if you need to bind < 1024
      seccompProfile:
        type: RuntimeDefault
```

## The fields

| Field | Default | What it does |
|---|---|---|
| `runAsUser` | (image's USER) | UID for the container process |
| `runAsGroup` | (image's GROUP) | GID for the container process |
| `runAsNonRoot` | false | Refuse to start the container if it'd run as root (UID 0) |
| `fsGroup` | (none) | GID for volume ownership — group-writable volumes |
| `fsGroupChangePolicy` | Always | When to chown the volume (`Always` / `OnRootMismatch`) |
| `readOnlyRootFilesystem` | false | Mount the root filesystem read-only |
| `allowPrivilegeEscalation` | true | Allow setuid binaries and capabilities to gain privileges |
| `privileged` | false | Run as effectively root on the host (almost never) |
| `capabilities.add/drop` | full set | Linux capabilities the container keeps |
| `seccompProfile` | Unconfined | Which seccomp filter applies |

## A hardened baseline (the "restricted" PSS profile)

This is what [[Kubernetes/concepts/L07-security/06-pod-security-standards|Pod Security Standards]] calls `restricted` — the safe default for untrusted workloads:

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

Plus a writable volume for any scratch space:

```yaml
volumes:
- name: scratch
  emptyDir: {}
volumeMounts:
- name: scratch
  mountPath: /tmp
```

## Common patterns

### A web app

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
```

### A workload that needs to bind port 80 (low port)

```yaml
securityContext:
  capabilities:
    drop: ["ALL"]
    add: ["NET_BIND_SERVICE"]
```

### A workload that needs to write to a specific path

```yaml
securityContext:
  readOnlyRootFilesystem: true
  # mount a writable volume at the write path
```

### A workload that needs to run as a specific user (matches image's USER)

```yaml
securityContext:
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
```

## Gotchas

* **`privileged: true` is a near-universal red flag.** It disables almost all isolation. The container can see host devices, mount filesystems, etc. It exists for legitimate use cases (some CNI plugins, some storage daemons, GPU drivers) but never for application code.
* **`runAsNonRoot: true` rejects images that don't declare a non-root USER.** If your image runs as root by default (many do!), the Pod will be `CreateContainerConfigError`.
* **`readOnlyRootFilesystem: true` will break apps that write anywhere except volumes.** Make sure you mount writable `emptyDir`s at all write paths (`/tmp`, `/var/cache`, `/var/log`, etc.).
* **`allowPrivilegeEscalation: false` blocks setuid binaries.** Some installers / package managers need setuid. If you run such a workload, you have to allow it.
* **`fsGroup` only applies to volumes mounted after the Pod starts.** Pre-populated volumes (ConfigMap, downwardAPI, projected) don't get the chown unless you use `fsGroupChangePolicy: OnRootMismatch`.
* **`seccompProfile.type: RuntimeDefault` requires a runtime that supports it** (containerd 1.5+, CRI-O). It applies the runtime's default seccomp filter — usually a safe superset of allowed syscalls.
* **Capabilities are added on top of the default set, not as a whitelist.** `drop: [ALL]` then `add: [NET_BIND_SERVICE]` works. `drop: [NET_RAW]` only doesn't restrict what the container can do — it just removes that one capability.
* **The Pod's `securityContext` is a hard requirement for admission**, not a hint. The Pod either has it or it doesn't.

## Why not just set everything to true?

The defaults (root, privileged, all capabilities) are a **terrible** security posture. They're set that way for backwards compatibility with the pre-PSS world. Always harden.

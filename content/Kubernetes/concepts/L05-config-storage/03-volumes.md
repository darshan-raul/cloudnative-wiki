# Volume Types

*"https://kubernetes.io/docs/concepts/storage/volumes/"*

A Pod's `volumes` array declares what storage is available. Each volume type is a different source — local disk, network filesystem, cloud disk, ConfigMap, etc. The type you pick determines the lifetime, contents, and operational characteristics of the volume.

### Table of Contents

1. [The Volume Abstraction](#1-the-volume-abstraction)
2. [emptyDir — Pod-Lifetime Scratch](#2-emptydir--pod-lifetime-scratch)
3. [hostPath — The Node's Filesystem](#3-hostpath--the-nodes-filesystem)
4. [nfs — Legacy Network Filesystem](#4-nfs--legacy-network-filesystem)
5. [CSI — The Modern Way](#5-csi--the-modern-way)
6. [persistentVolumeClaim — The Standard Pattern](#6-persistentvolumeclaim--the-standard-pattern)
7. [configMap and secret — Config as Volumes](#7-configmap-and-secret--config-as-volumes)
8. [projected — Combine Multiple Sources](#8-projected--combine-multiple-sources)
9. [downwardAPI — Pod Metadata as Files](#9-downwardapi--pod-metadata-as-files)
10. [ephemeral — Inline PVC per Pod](#10-ephemeral--inline-pvc-per-pod)
11. [gitRepo — Deprecated, but Worth Knowing](#11-gitrepo--deprecated-but-worth-knowing)
12. [Mount Options — subPath, subPathExpr, mountPropagation](#12-mount-options--subpath-subpathexpr-mountpropagation)
13. [Operations and Debugging](#13-operations-and-debugging)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)

---

## 1. The Volume Abstraction

A volume is a directory mounted into a container's filesystem. The directory's contents come from somewhere — a node's disk, a network share, a ConfigMap, etc. The kubelet mounts the volume into the container's filesystem at the path you specify in `volumeMounts`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
  - name: app
    image: app:1.0
    volumeMounts:
    - name: cache
      mountPath: /var/cache
  volumes:
  - name: cache
    emptyDir: {}        # <-- the volume type
```

The volume's name (`cache`) is the link between `volumes` and `volumeMounts`. The same volume can be mounted at multiple paths (and even in multiple containers in the same Pod).

### 1.1 Volume lifetime vs Pod lifetime

| Type | Lifetime | Survives Pod restart? | Survives node restart? |
|---|---|---|---|
| `emptyDir` | Pod | ❌ (deleted with Pod) | ❌ |
| `hostPath` | Node | ✅ (on the same node) | ✅ |
| `nfs` | NFS share | ✅ (data is on NFS) | ✅ |
| `persistentVolumeClaim` | PV's lifetime | ✅ | ✅ |
| `configMap` / `secret` | The source resource | ✅ (until the resource is deleted) | ✅ |
| `projected` | Depends on sources | Depends | Depends |
| `downwardAPI` | Pod | ❌ | ❌ |
| `ephemeral` | Pod (with a PVC) | ❌ | ✅ (if backed by remote storage) |
| `gitRepo` | Pod | ❌ | ❌ |

### 1.2 The volume vs the mount

The `volumes` array declares **what** storage is available. The `volumeMounts` array (per-container) declares **where** it goes. The same volume can be mounted at multiple paths:

```yaml
volumeMounts:
- name: data
  mountPath: /var/lib/data
- name: data
  mountPath: /var/log/app     # same volume, different path
  readOnly: true
- name: data
  mountPath: /cache
  subPath: my-cache           # only the subpath is mounted
```

Or in multiple containers of the same Pod (they share the volume by default).

## 2. emptyDir — Pod-Lifetime Scratch

A directory that **lives for the lifetime of the Pod**. Created on the node when the Pod is scheduled, deleted when the Pod is removed. Shared by all containers in the Pod.

```yaml
volumes:
- name: cache
  emptyDir:
    sizeLimit: 1Gi             # k8s 1.22+, evict if exceeded
    medium: Memory             # or "" (default, node disk) or "HugePages"
```

### 2.1 The three media

| Medium | Storage | Use case |
|---|---|---|
| `""` (default) | Node's disk | Scratch space, caches, intermediate data |
| `Memory` | tmpfs (RAM) | Fast scratch, but counts against Pod's memory limit |
| `HugePages` | Huge pages | High-performance apps (databases, scientific computing) |

**`medium: Memory` uses tmpfs** — the kernel allocates RAM. The data is gone when the Pod is deleted. **Be careful:** tmpfs counts against the Pod's memory limit. A 1Gi tmpfs + 512Mi request = the Pod is constrained to ~512Mi total (request-based, not limit-based).

### 2.2 sizeLimit eviction (k8s 1.22+)

```yaml
emptyDir:
  sizeLimit: 1Gi
```

If the emptyDir exceeds the sizeLimit, the kubelet evicts the Pod (or the container, depending on the policy). The eviction is fast and noisy — the Pod's logs will show `FailedMount` or `Evicted`.

This is useful for:

* **Caches that should be bounded** — preventing a runaway cache from filling the node's disk.
* **Build scratch** — preventing a build from filling /tmp.
* **Logging buffers** — preventing log buffers from eating all the disk.

**Watch out:** the sizeLimit is **enforced by the kubelet**, not the emptyDir itself. On `medium: ""` (node disk), the sizeLimit corresponds to a quota on the node's filesystem. On `medium: Memory`, it corresponds to a memory limit on the tmpfs.

### 2.3 Use cases

* **Scratch space** for the app's working data.
* **Cache for build steps** in a CI runner.
* **Sidecar reading app's logs** (shared `/var/log/app`).
* **Shared memory between containers in the same Pod** (with `medium: Memory`).
* **Tmpfs for fast data** (image processing, encryption keys, etc.).

### 2.4 What it's NOT for

* **Anything that needs to survive the Pod** — emptyDir is deleted with the Pod.
* **Multi-Pod shared storage** — emptyDir is per-Pod, not shared between Pods.
* **Durable data** — see `persistentVolumeClaim`.

## 3. hostPath — The Node's Filesystem

Mounts a **file or directory from the host node's filesystem** into the Pod.

```yaml
volumes:
- name: host-fs
  hostPath:
    path: /data
    type: DirectoryOrCreate
```

### 3.1 The `type` field

| Type | Behavior |
|---|---|
| `DirectoryOrCreate` | Mount the directory; create it on the host with root ownership if it doesn't exist (0755) |
| `Directory` | Mount the directory; must exist, otherwise mount fails |
| `FileOrCreate` | Mount a file; create it on the host with root ownership if it doesn't exist (0644) |
| `File` | Mount a file; must exist, otherwise mount fails |
| `CharDevice` | Mount a character device |
| `BlockDevice` | Mount a block device |
| `Socket` | Mount a unix socket |

**`DirectoryOrCreate` is the dangerous one.** It creates the directory on the host as root, with default permissions. If the host's `/data` doesn't exist, the kubelet creates it. This is a common path for privilege escalation and unintended host access.

**Prefer `Directory` (must exist)** for tighter control. The kubelet doesn't create anything, the operator has set up the directory explicitly.

### 3.2 Use cases

* **DaemonSets that need to read host logs/metrics** — Prometheus node-exporter, Fluent Bit, Filebeat.
* **Single-node clusters** — kind, minikube, k3d. Dev/test only.
* **Custom CNIs, storage plugins, or network plugins** that need raw host access.
* **Accessing the node's Docker socket** (`/var/run/docker.sock`) — for sidecars that interact with the container runtime.

### 3.3 What it's NOT for

* **Portable workloads** — if the Pod reschedules to a different node, the data isn't there.
* **Production stateful apps** — hostPath survives only as long as the node does. If the node is replaced, the data is gone.
* **Multi-Pod shared storage** — hostPath is per-node. Pods on different nodes see different files.

### 3.4 The security implications

hostPath is one of the **most dangerous volume types** in k8s. A Pod with a hostPath mount can:

* Read host files (`/etc`, `/var`, `/proc`, etc.)
* Write to host files (corrupting the node's OS)
* Mount `/` and get full host access (the most extreme form)

This is why **Pod Security Standards** restrict hostPath. In `baseline` and `restricted` profiles, hostPath is either disallowed or restricted to specific paths.

Always use `readOnly: true` if possible, and prefer the most specific path you can.

## 4. nfs — Legacy Network Filesystem

Mounts an NFS share. Requires an NFS server reachable from the cluster.

```yaml
volumes:
- name: nfs-vol
  nfs:
    server: nfs.example.com
    path: /exports/data
    readOnly: false
```

### 4.1 The in-tree NFS driver is deprecated

Since k8s 1.20, the in-tree `nfs` volume type is **deprecated**. The recommended replacement is the **NFS CSI driver** (`csi.driver.nfs` from the Kubernetes CSI project, or vendor-specific).

```yaml
# New way: NFS CSI
volumes:
- name: nfs-vol
  csi:
    driver: nfs.csi.k8s.io
    readOnly: false
    volumeAttributes:
      server: nfs.example.com
      share: /exports/data
```

The CSI driver provides the same functionality but follows the standard CSI model (out-of-tree, with dynamic provisioning, snapshots, etc.).

### 4.2 Use cases

* **Legacy NFS-based storage** — migrating from a pre-CSI setup.
* **Read-only data shared across many Pods** — content, ML models, static assets.
* **Hybrid setups** — on-prem + NFS for cross-cluster data sharing.

### 4.3 What it's NOT for

* **Cloud-native setups** — use EFS, Filestore, or a CSI driver instead. They're more reliable, scalable, and integrated with the cloud.
* **High-performance workloads** — NFS has known perf issues for high-IO workloads.
* **Cross-AZ setups** — NFS is typically single-AZ. Cross-AZ NFS is slow.

## 5. CSI — The Modern Way

The **Container Storage Interface (CSI)** is the abstraction layer for all cloud / third-party storage. The actual driver is a separate project (EBS CSI, EFS CSI, Ceph CSI, GKE PD CSI, etc.). Once installed, you use it via a `PersistentVolume` / `PVC` — the volume is referenced as a normal PV, not directly in the Pod spec.

```yaml
volumes:
- name: data
  persistentVolumeClaim:
    claimName: my-pvc
```

This is the right way to use EBS, EFS, Azure Disk/Files, GCP PD, Ceph, NetApp, Pure, etc. The PV is provisioned (statically or dynamically via a StorageClass) and the Pod just claims it.

### 5.1 The CSI architecture

A CSI driver typically has three components:

```
┌────────────────────────────────────────────────────────┐
│  Control plane (controller)                            │
│  - Runs in Deployment, scales horizontally            │
│  - Watches PVCs / PVs / VolumeAttachments              │
│  - Creates / deletes the underlying storage           │
│  - Calls cloud APIs (CreateVolume, DeleteVolume, etc.)│
└────────────────┬───────────────────────────────────────┘
                 │
┌────────────────▼───────────────────────────────────────┐
│  Data plane (node plugin)                             │
│  - Runs as DaemonSet on every node                    │
│  - Mounts / unmounts the volume on the node           │
│  - Talks to the local kubelet                         │
└────────────────┬───────────────────────────────────────┘
                 │
┌────────────────▼───────────────────────────────────────┐
│  Sidecar containers (per-Pod)                         │
│  - driver-registrar: registers with kubelet           │
│  - livenessprobe: reports health                       │
│  - external-provisioner, external-snapshotter, etc.   │
│  - Inject as sidecars to the CSI driver Pods          │
└────────────────────────────────────────────────────────┘
```

### 5.2 Why CSI

* **Out-of-tree** — drivers don't need to be in the kubelet binary. They can be installed, upgraded, and managed independently.
* **Standardized** — every CSI driver exposes the same interface (CreateVolume, DeleteVolume, CreateSnapshot, etc.). Cluster admins don't need to learn vendor-specific APIs.
* **Decoupled from k8s release** — vendors release drivers on their own schedule. No more waiting for a k8s release to get a new feature.

### 5.3 The in-tree → CSI migration

Older k8s versions had **in-tree volume plugins** for major providers (AWS EBS, GCE PD, etc.). These have been **removed in k8s 1.26+** (or marked for removal). All storage now goes through CSI.

If you're upgrading from a cluster with in-tree volumes, you need to:

1. Install the CSI driver.
2. Migrate any in-tree PVs to CSI PVs (use the `migrator` sidecar that does this automatically).
3. Update your StorageClasses to use the CSI provisioner.

Most CSI drivers provide migration tools. The migration is usually transparent — your existing PVCs keep working, and new ones are provisioned by the CSI driver.

## 6. persistentVolumeClaim — The Standard Pattern

The volume type you'll use most often. References a PVC by name.

```yaml
volumes:
- name: data
  persistentVolumeClaim:
    claimName: my-pvc
```

The PVC must be in the same namespace as the Pod. The PV behind the PVC is provisioned (statically or dynamically). **This is the only way to use a PVC from a Pod.**

See `04-persistentvolume.md` and `05-persistentvolumeclaim.md` for full details.

## 7. configMap and secret — Config as Volumes

Mount a ConfigMap or Secret as a directory of files. Each key becomes a file.

```yaml
volumes:
- name: config
  configMap:
    name: app-config
    items:
    - key: app.properties
      path: app.properties
    - key: log4j.xml
      path: logging/log4j.xml
    defaultMode: 0400
```

The keys become files at the volume's mount path. The `items` field lets you pick which keys to mount and where. `defaultMode` sets the file mode (default 0644).

```yaml
volumes:
- name: secrets
  secret:
    secretName: app-secrets
    defaultMode: 0400
```

Same pattern for Secrets.

### 7.1 Hot reload

Mounted ConfigMaps and Secrets are **updated automatically** when the source is updated. The kubelet uses inotify to watch the file and updates the Pod's volume in place. **Updates can take 30-60 seconds to propagate** (default sync period).

**Note:** `subPath` mounts do NOT hot-reload. If you need hot reload, don't use subPath — mount the whole volume and use `subPathExpr` or symlinks.

### 7.2 The "ConfigMap doesn't exist" gotcha

If the ConfigMap doesn't exist when the Pod starts, the Pod fails to start. The error is `MountVolume.SetUp failed for volume "config"`. Fix: create the ConfigMap first, then the Pod.

**The Pod does NOT wait for the ConfigMap to appear.** This is different from `default` ConfigMaps (created by the namespace admin), which do wait.

## 8. projected — Combine Multiple Sources

A `projected` volume combines multiple sources into a single volume. Each source becomes a subdirectory.

```yaml
volumes:
- name: all-config
  projected:
    sources:
    - configMap:
        name: app-config
    - secret:
        name: app-secrets
    - downwardAPI:
        items:
        - path: "labels"
          fieldRef:
            fieldPath: metadata.labels
        - path: "cpu-limit"
          resourceFieldRef:
            containerName: app
            resource: limits.cpu
    - serviceAccountToken:
        path: token
        audience: api.example.com
        expirationSeconds: 3600
```

The Pod sees:

```
/etc/all-config/
├── (from app-config)
│   ├── app.properties
│   └── log4j.xml
├── (from app-secrets)
│   ├── db-password
│   └── api-key
├── labels        (from downwardAPI)
├── cpu-limit     (from downwardAPI)
└── token         (from serviceAccountToken)
```

Use cases:

* **Consolidating config** — one volume for the app's complete config, instead of mounting five separate volumes.
* **Workload identity** — the `serviceAccountToken` source projects a token for an external service (e.g. AWS IAM, Vault, GCP IAM).
* **One source of truth** — the app reads one directory instead of five.

## 9. downwardAPI — Pod Metadata as Files

Expose Pod metadata as files in the volume. Useful for apps that need to know their own name, namespace, labels, etc.

```yaml
volumes:
- name: podinfo
  downwardAPI:
    items:
    - path: "name"
      fieldRef:
        fieldPath: metadata.name
    - path: "namespace"
      fieldRef:
        fieldPath: metadata.namespace
    - path: "labels"
      fieldRef:
        fieldPath: metadata.labels
    - path: "annotations"
      fieldRef:
        fieldPath: metadata.annotations
    - path: "cpu-limit"
      resourceFieldRef:
        containerName: app
        resource: limits.cpu
        divisor: "1m"
```

Available fields:

* `metadata.name` — Pod name
* `metadata.namespace` — namespace
* `metadata.uid` — Pod UID
* `metadata.labels` — all labels, as a key=value file
* `metadata.annotations` — all annotations, as a key=value file
* `status.podIP` — Pod IP
* `status.hostIP` — node IP
* `spec.serviceAccountName` — ServiceAccount
* `spec.nodeName` — node name

For container resources:

* `limits.cpu`, `limits.memory`, `limits.ephemeral-storage`
* `requests.cpu`, `requests.memory`, `requests.ephemeral-storage`

`divisor` is the unit. `1m` = millicores, `1` = bytes, `1Mi` = mebibytes, etc.

**downwardAPI values are written at Pod start and not updated dynamically.** If the Pod's labels change, the file isn't updated. This is a known limitation.

## 10. ephemeral — Inline PVC per Pod

A newer volume type (k8s 1.19+) that creates an **inline PVC per Pod**. The Pod has a volume with a `volumeClaimTemplate`, and a PVC is created automatically when the Pod starts.

```yaml
volumes:
- name: scratch
  ephemeral:
    volumeClaimTemplate:
      metadata:
        labels:
          type: scratch
      spec:
        accessModes: [ "ReadWriteOnce" ]
        storageClassName: "scratch-storage"
        resources:
          requests:
            storage: 1Gi
```

The PVC:

* Is created when the Pod is created
* Has the labels specified in `volumeClaimTemplate.metadata.labels`
* Uses the StorageClass specified
* Is **deleted when the Pod is deleted**

This is the **inline alternative to** a separate PVC + Pod. Useful for:

* **Batch jobs** that need scratch storage
* **Per-Pod temp space** without managing PVCs
* **Stateless apps with a writeable scratch directory** (test runners, build containers)

The PVC's lifecycle is tied to the Pod. **Don't use ephemeral for stateful data** — the PVC is deleted with the Pod.

## 11. gitRepo — Deprecated, but Worth Knowing

The `gitRepo` volume type mounts a git repository into the Pod. **Deprecated since k8s 1.22** — the kubelet no longer ships git, and the volume type is non-functional on most modern clusters.

If you need a git repo in a Pod:

```yaml
# Use an init container
initContainers:
- name: git-clone
  image: alpine/git
  command: ['git', 'clone', 'https://github.com/my-org/my-repo', '/data']
  volumeMounts:
- name: data
  mountPath: /data
containers:
- name: app
  image: app:1.0
  volumeMounts:
- name: data
  mountPath: /var/lib/app
volumes:
- name: data
  emptyDir: {}
```

This is the modern equivalent. The init container clones the repo into an emptyDir, and the main container reads from it.

## 12. Mount Options — subPath, subPathExpr, mountPropagation

### 12.1 `subPath`

```yaml
volumeMounts:
- name: config
  mountPath: /etc/app/app.properties
  subPath: app.properties       # mount just this file, not the whole volume
```

`subPath` lets you mount a single file (or a subdirectory) instead of the whole volume. Useful when:

* The volume is a ConfigMap and you want one file at a specific path.
* The volume is a PVC and you want a subdirectory.
* You need to avoid symlink-related issues with hot reload.

**The hot-reload gotcha:** `subPath` mounts **do NOT track updates** to the source. A ConfigMap updated after Pod start won't be reflected in the subPath mount. This is the #1 subPath gotcha.

### 12.2 `subPathExpr` (k8s 1.27+)

A templated alternative to subPath:

```yaml
volumeMounts:
- name: data
  mountPath: /var/lib/data/$(POD_NAME)
  subPathExpr: $(POD_NAME)
```

`subPathExpr` supports downward API variables. Use it for per-Pod directories in shared volumes.

```yaml
volumeMounts:
- name: data
  mountPath: /cache/$(POD_NAME)
  subPathExpr: $(POD_NAME)
```

The value comes from the Pod's environment (or downward API). The expression is evaluated at Pod start, not dynamically.

### 12.3 `mountPropagation`

Controls how mounts made inside the container propagate to the host and other containers.

| Value | Behavior |
|---|---|
| `None` (default) | Mounts inside the container stay inside the container |
| `HostToContainer` | Mounts on the host propagate to the container |
| `Bidirectional` | Mounts in either direction propagate |

**`Bidirectional` is dangerous.** It lets the container mount volumes onto the host (and have them propagate back). This is required for some CSI drivers (e.g. some networked storage systems), but should be a rare, deliberate choice.

**Most apps should use the default (`None`)** and never set mountPropagation. If a CSI driver requires `Bidirectional`, document why.

### 12.4 `readOnly`

```yaml
volumeMounts:
- name: data
  mountPath: /data
  readOnly: true
```

Mount the volume read-only. The container can't write to it. Useful for:

* **ConfigMaps and Secrets** — they're already read-only, but explicit is better.
* **Shared data** — prevent one container from corrupting another's data.
* **Defense in depth** — even if the app is compromised, it can't write to the volume.

### 12.5 `mountPath` and the bind mount

The `mountPath` is the path inside the container where the volume is mounted. If the directory doesn't exist, kubelet creates it. If it exists and has content, that content is **hidden** when the volume is mounted (the volume's contents take over).

**This is a common gotcha:** if you `mountPath: /var/log` and the container has logs in `/var/log` from a previous run, those logs are hidden by the mount. Use a different path or initialize the directory before mounting.

## 13. Operations and Debugging

### 13.1 Common commands

```bash
# list volumes in a Pod
kubectl get pod <pod> -o jsonpath='{.spec.volumes[*].name}'
kubectl get pod <pod> -o yaml

# check volume mounts in a container
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].volumeMounts}'
kubectl get pod <pod> -o jsonpath='{.spec.initContainers[*].volumeMounts}'

# check Pod events for volume issues
kubectl describe pod <pod>
# look for "FailedMount", "FailedAttachVolume", "MountVolume.SetUp failed"

# exec into the Pod to check the mount
kubectl exec -it <pod> -- df -h
kubectl exec -it <pod> -- mount | grep <volume-name>
kubectl exec -it <pod> -- ls -la <mount-path>

# check the node's view
# (on the node)
mount | grep <pod-uid>
```

### 13.2 The "volume won't mount" checklist

```bash
# 1. Is the source available?
kubectl get configmap <name>
kubectl get secret <name>
kubectl get pvc <name>

# 2. Is the PVC bound?
kubectl get pvc <name>
# STATUS should be Bound

# 3. Is the CSI driver running?
kubectl -n kube-system get pods -l <csi-driver-label>

# 4. Check the kubelet logs on the node
journalctl -u kubelet --since "5 minutes ago" | grep -i mount
# look for "MountVolume.SetUp failed", "timed out", "forbidden"

# 5. Check the CSI driver logs
kubectl -n kube-system logs -l <csi-driver-label> --tail=100

# 6. Try mounting manually on the node
# (advanced, for debugging only)
mount -t nfs <server>:<path> /mnt/test
```

### 13.3 The "PVC Pending" case

A Pod's `persistentVolumeClaim` volume can't mount if the PVC is `Pending`. See `05-persistentvolumeclaim.md` for the full debugging flow.

## 14. Gotchas and Common Mistakes

### 14.1 The 25+ common mistakes

1. **`subPath` blocks hot-reload.** The most common subPath gotcha. If the ConfigMap is updated, the subPath mount still has the old value. **Don't use subPath with ConfigMaps / Secrets you want to hot-reload.**

2. **`subPathExpr` syntax is `$(VAR)`, not `$VAR` or `${VAR}`.** The leading `$(` is required.

3. **`mountPath: /var/log` hides existing container files.** If the container has logs at `/var/log/myapp.log` from the image, mounting a volume at `/var/log` hides them. Use a subdirectory.

4. **`emptyDir` with `medium: Memory` counts against the Pod's memory limit.** A 1Gi tmpfs + 512Mi memory limit = the Pod can be OOM-killed for using too much tmpfs.

5. **`emptyDir` is deleted with the Pod.** Don't put anything in emptyDir that needs to survive.

6. **`hostPath: DirectoryOrCreate` creates directories as root.** This is a security risk — the host's directory is owned by root, the container may not be able to write to it.

7. **`hostPath` is restricted by Pod Security Standards.** In `baseline` and `restricted` profiles, hostPath is disallowed (or restricted to specific paths). If you can't use hostPath, check your PSS configuration.

8. **The `nfs` in-tree volume type is deprecated.** Use the NFS CSI driver instead. The in-tree one is gone in 1.26+.

9. **In-tree volume types for major providers are removed in 1.26+.** AWS EBS, GCE PD, Azure Disk, etc. all go through CSI now. Use `ebs.csi.aws.com`, not `kubernetes.io/aws-ebs`.

10. **`configMap` / `secret` volumes don't hot-reload if the source is deleted.** If the ConfigMap is deleted, the files in the volume stay. The kubelet doesn't unmount on delete.

11. **A `configMap` volume is read-only by default.** You can't write to it from the container. (It's a mount of the ConfigMap, not a directory you can modify.)

12. **`projected` volumes combine sources, but each source has its own limits.** A projected secret + configMap + downwardAPI is fine. A projected volume with 10 sources may have permission issues.

13. **`downwardAPI` doesn't update dynamically.** Pod name, labels, etc. are written at Pod start. If the labels change, the file doesn't.

14. **`ephemeral` volume's PVC is deleted with the Pod.** Don't use it for data that needs to survive the Pod.

15. **`ephemeral` requires the StorageClass to support `WaitForFirstConsumer` or have a default mode.** If the StorageClass can't provision, the Pod fails to start.

16. **A single Pod can have up to ~250 volumes in practice.** Kernel limits, file descriptor limits, kubelet's `max-volumes-per-pod` flag (default 256). StatefulSets with `volumeClaimTemplates` can hit this.

17. **The `defaultMode` for ConfigMap / Secret volumes is 0644.** For Secrets, this means the keys are world-readable inside the container. Set `defaultMode: 0400` to be safer.

18. **`items` in a ConfigMap / Secret volume lets you pick keys, but the keys must exist.** A typo in `items[].key` causes `MountVolume.SetUp failed`.

19. **`serviceAccountToken` projection (in projected volumes) is for external service identity** (Vault, AWS IAM, GCP IAM, etc.). It's NOT for talking to the apiserver — that's automatic via the Pod's projected SA token (mounted at `/var/run/secrets/kubernetes.io/serviceaccount`).

20. **The volume name in `volumes[]` and `volumeMounts[]` must match exactly.** Typo → `MountVolume.SetUp failed`.

21. **You can't mount a volume to a read-only filesystem root.** If the container's root filesystem is read-only (some security-hardened images), the mount fails. Use `securityContext.readOnlyRootFilesystem: false` if you need to mount.

22. **`mountPropagation: Bidirectional` is required for some CSI drivers** (CephFS, some GlusterFS setups). Check the driver's docs. If you set it on the wrong driver, you get weird propagation issues.

23. **`gitRepo` is deprecated.** Use an init container instead.

24. **A `hostPath` volume to `/var/run/docker.sock`** lets the container interact with the host's Docker daemon. This is a major security risk — a compromised container could create privileged containers on the host. **Don't do this in production.**

25. **Mounting `/proc`, `/sys`, or `/dev` from the host is also a major security risk.** Don't do it.

26. **A `hostPath` of a `FileSocket` (like `/var/run/docker.sock`) uses the socket file directly.** Not the file's contents. Be careful with what permissions the container has.

27. **An `emptyDir` on `medium: HugePages` requires the Pod's `resources.requests.hugepages-2Mi` or similar to be set.** Without it, the kubelet can't allocate the huge pages.

28. **The `csi` volume type is a low-level escape hatch.** Most apps shouldn't reference a CSI driver directly — they should use a PVC backed by the driver. Direct CSI references bypass the PV/PVC abstraction.

29. **`subPath` and `subPathExpr` cannot both be set on the same volumeMount.** Pick one.

30. **The Pod's `volumes[]` is a flat list.** You can't nest volumes or have a volume be the "parent" of another. Each volume is independent.

## See also

* [[Kubernetes/concepts/L05-config-storage/01-config-maps|ConfigMaps]] — one of the volume types
* [[Kubernetes/concepts/L05-config-storage/02-secrets|Secrets]] — the secret volume type
* [[Kubernetes/concepts/L05-config-storage/04-persistentvolume|PersistentVolume]] — the standard persistent storage
* [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim|PersistentVolumeClaim]] — the user-facing API for storage
* [[Kubernetes/concepts/L05-config-storage/06-storageclass|StorageClass]] — dynamic provisioning
* [[Kubernetes/concepts/L05-config-storage/07-storage|Storage]] — the L05 mental model

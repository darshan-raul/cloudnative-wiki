# Volume Types

*"https://kubernetes.io/docs/concepts/storage/volumes/"*

A Pod's `volumes` array declares what storage is available. Each volume type is a different source. The four you'll actually use:

## emptyDir

A directory that **lives for the lifetime of the Pod**. Created on the node when the Pod is scheduled, deleted when the Pod is removed. Shared by all containers in the Pod.

```yaml
volumes:
- name: cache
  emptyDir:
    sizeLimit: 1Gi             # k8s 1.22+, evict if exceeded
      medium: Memory           # or "" (default, disk) or "HugePages"
```

**Use cases:**

* Scratch space for the app
* Cache for build steps
* Sidecar reading app's logs (shared `/var/log/app`)

**Not for**: anything that needs to survive the Pod.

## hostPath

Mounts a **file or directory from the host node's filesystem** into the Pod.

```yaml
volumes:
- name: host-fs
  hostPath:
    path: /data
    type: DirectoryOrCreate
```

**Use cases:**

* DaemonSets that need to read host logs/metrics (Prometheus node-exporter, Fluent Bit)
* Testing storage on a single-node cluster

**Not for**: portable workloads. If the Pod reschedules to a different node, the data isn't there.

**Gotchas:** `type: DirectoryOrCreate` will create `/data` on the host with root ownership — security implications. Prefer `type: Directory` (must exist) or `type: File` for tighter control.

## nfs

Mounts an NFS share. Requires an NFS server reachable from the cluster.

```yaml
volumes:
- name: nfs-vol
  nfs:
    server: nfs.example.com
    path: /exports/data
    readOnly: false
```

**Use cases:**

* Legacy NFS-based storage
* Read-only data shared across many Pods

**Not for**: cloud-native setups (use EFS, Filestore, or a CSI driver instead).

**Gotchas:** NFS in-tree driver is deprecated; use the CSI driver (`nfs.csi.k8s.io`).

## CSI (the modern way)

The **Container Storage Interface** is the abstraction layer for all cloud / third-party storage. The actual driver is a separate project (EBS CSI, EFS CSI, Ceph CSI, GKE PD CSI, etc.). Once installed, you use it via a `PersistentVolume` / `PVC` — the volume is referenced as a normal PV, not directly in the Pod spec.

```yaml
volumes:
- name: data
  persistentVolumeClaim:
    claimName: my-pvc
```

This is the right way to use EBS, EFS, Azure Disk/Files, GCP PD, Ceph, NetApp, Pure, etc. The PV is provisioned (statically or dynamically via a StorageClass) and the Pod just claims it.

## Less common but worth knowing

* **gitRepo** — deprecated since 1.22 (use a sidecar or init container)
* **configMap / secret** — covered separately; appear as a volume type
* **projected** — combine multiple sources (ConfigMap + Secret + downward API) into one volume
* **downwardAPI** — expose Pod metadata as files in the volume
* **ephemeral** (k8s 1.19+) — inline volume definition that auto-creates a PVC per Pod

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

Ephemeral volumes are scoped to the Pod and deleted with it. Great for batch jobs and per-Pod scratch without managing PVCs explicitly.

## Mount options

```yaml
volumes:
- name: data
  persistentVolumeClaim:
    claimName: data
  # or directly on a volume
  emptyDir:
    medium: Memory
  # mountOptions is per-container on the volumeMount, NOT on the volume
```

```yaml
volumeMounts:
- name: data
  mountPath: /data
  mountPropagation: Bidirectional   # for mount-in-mount scenarios
  readOnly: true
  subPath: foo                       # mount a subpath, not the whole volume
  subPathExpr: $(POD_NAME)            # templated subPath (k8s 1.27+)
```

## Gotchas

* **`subPath` bypasses volume updates.** A subPath mount doesn't track updates to the source. Also breaks `subPath` and ConfigMap/Secret update propagation.
* **`subPathExpr` is the modern templated alternative** — supported for downward-API and env-var values.
* **`mountPropagation: Bidirectional` is dangerous.** It lets the container mount volumes onto the host, and those mounts propagate back. Required for some CSI drivers; not for most apps.
* **emptyDir on `medium: Memory` uses tmpfs** — fast, but counts against the Pod's memory limit.
* **A single Pod can have up to ~250 volumes** in practice (kernel limits, file descriptor limits). StatefulSets with `volumeClaimTemplates` are the usual offender.
* **CSI drivers run as DaemonSets** (in-cluster) or as sidecars in the control plane (in-tree replacement). The Pod uses the volume via the API; the actual driver is elsewhere.

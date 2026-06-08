# PersistentVolumeClaim (PVC)

*"https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims"*

A PersistentVolumeClaim is a **request for storage** by a user / Pod. It's the namespaced object that the cluster binds to a PersistentVolume. Pods use PVCs the way they use ConfigMaps or Secrets — declared in the spec, mounted as a volume.

### Table of Contents

1. [The Basic Idea](#1-the-basic-idea)
2. [PVC Specification in Detail](#2-pvc-specification-in-detail)
3. [Access Modes in Detail](#3-access-modes-in-detail)
4. [Storage Class Selection](#4-storage-class-selection)
5. [The Binding Lifecycle](#5-the-binding-lifecycle)
6. [Capacity and Expansion](#6-capacity-and-expansion)
7. [Volume Modes: Filesystem vs Block](#7-volume-modes-filesystem-vs-block)
8. [DataSource: Cloning and Restoring](#8-datasource-cloning-and-restoring)
9. [Volume Populators](#9-volume-populators)
10. [PVC Selectors and Matchmaking](#10-pvc-selectors-and-matchmaking)
11. [The Pod's View: How It Mounts](#11-the-pods-view-how-it-mounts)
12. [Operations and Debugging](#12-operations-and-debugging)
13. [Gotchas and Common Mistakes](#13-gotchas-and-common-mistakes)

---

## 1. The Basic Idea

A PVC is a **namespaced request for storage**. The user says "I need 50 GiB of RWO storage from the `gp3` class", and the system figures out the rest.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
  namespace: prod
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 50Gi
```

The claim says: "I need 50 GiB of `ReadWriteOnce` storage from the `gp3` class." k8s binds it to a matching PV (existing or newly provisioned).

A Pod then references the PVC:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: prod
spec:
  containers:
  - name: app
    image: app:1.0
    volumeMounts:
    - name: data
      mountPath: /var/lib/data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data
```

The Pod references the PVC by name (in the same namespace), the volume is mounted at `/var/lib/data`. The contents of the PV appear at that path.

### 1.1 The flow

```
User / Controller                apiserver                  StorageClass / Provisioner
       │                              │                              │
       │  kubectl apply -f pvc.yaml   │                              │
       │ ───────────────────────────► │                              │
       │                              │  create PVC (status: Pending)│
       │                              │ ──────────────────────────► │
       │                              │                              │  CreateVolume()
       │                              │                              │  (cloud API)
       │                              │                              │
       │                              │  ◄─────────────────────────  │
       │                              │  PV created, PVC bound       │
       │                              │ ──────────────────────────► │
       │                              │                              │
       │  kubectl apply -f pod.yaml   │                              │
       │ ───────────────────────────► │                              │
       │                              │  Pod sees bound PVC          │
       │                              │  (status: Bound)             │
       │                              │  mounts the volume           │
       │                              │ ──────────────────────────► │
       │                              │                              │  NodePublishVolume()
       │                              │  (CSI mounts on the node)    │
```

## 2. PVC Specification in Detail

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
  namespace: prod
  labels:
    app: myapp
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 50Gi
  volumeMode: Filesystem           # or Block
  selector:                        # optional: bind to specific PVs
    matchLabels:
      tier: gold
  dataSource:                      # k8s 1.20+: clone or restore
    apiGroup: snapshot.storage.k8s.io
    kind: VolumeSnapshot
    name: my-snapshot
  dataSourceRef:                   # k8s 1.22+: typed version of dataSource
    apiGroup: snapshot.storage.k8s.io
    kind: VolumeSnapshot
    name: my-snapshot
status:
  phase: Bound                     # Pending | Bound | Lost
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: 50Gi
  conditions:
  - type: Ready
    status: "True"
    reason: ""
    message: ""
```

### 2.1 The `spec.resources.requests.storage`

The **minimum capacity** the PVC needs. The system tries to provide at least this much.

This is a **request**, not a hard limit. Some backends may provide more (e.g. EBS rounds up to the next GB). The actual capacity is in `status.capacity.storage`.

### 2.2 The `volumeMode` field

`Filesystem` (default) or `Block`. See section 7 for details.

### 2.3 The `selector` field

Binds the PVC to a specific PV (in static provisioning) or restricts the StorageClass to creating PVs with specific labels.

```yaml
spec:
  selector:
    matchLabels:
      tier: gold
    matchExpressions:
    - key: environment
      operator: In
      values: [production]
```

The `selector` is mostly used in static provisioning. In dynamic provisioning, the labels are usually set in the StorageClass's `volumeBindingMode` and topology constraints.

## 3. Access Modes in Detail

| Mode | Meaning | Use case |
|---|---|---|
| `ReadWriteOnce` (RWO) | Mounted read-write by a single node | Databases, single-instance stateful apps |
| `ReadOnlyMany` (ROX) | Mounted read-only by many nodes | Shared content, models, static assets |
| `ReadWriteMany` (RWX) | Mounted read-write by many nodes | Multi-writer filesystems, cluster-aware apps |
| `ReadWriteOncePod` (RWOP) | Mounted read-write by a single Pod | Single-writer volumes, strict ownership |

### 3.1 Matching PVC to PV access modes

The PV must support **at least** the access modes the PVC requests. The matching rules:

| PVC requests | PV supports |
|---|---|
| RWO | RWO or RWX (anything that includes RWO) |
| ROX | RWO, ROX, or RWX (anything that can be mounted read-only) |
| RWX | RWX only |
| RWOP | RWOP only |

**Common mistake:** a PVC requesting RWO can bind to a RWX PV, but a PVC requesting RWX cannot bind to a RWO PV. **The PVC can never get a less-capable PV than it asks for.**

### 3.2 The "RWO is one node" detail

A RWO volume is mounted read-write by a single node. Multiple Pods on the same node can mount it. **This is what most databases need** — Postgres, MySQL, MongoDB. They run on one node.

For a **database cluster** (Postgres with replicas, Cassandra) on multiple nodes, you need RWX or RWOP.

## 4. Storage Class Selection

```yaml
spec:
  storageClassName: gp3
```

### 4.1 The three cases

| Value | Behavior |
|---|---|
| `gp3` (or any name) | Bind to a PV with that storageClassName, or dynamically provision via that StorageClass |
| `""` (empty string) | Opt out of dynamic provisioning. Bind to a pre-existing PV with `storageClassName: ""` |
| omitted | Use the cluster's default StorageClass |

### 4.2 The default StorageClass

Most managed clusters (EKS, GKE, AKS) have a default StorageClass. A PVC without `storageClassName` uses it.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
```

**Best practice:** always set `storageClassName` explicitly in production. The "default" can change between clusters, and a default PVC in a namespace that doesn't have access to the default class will stay `Pending`.

### 4.3 Opting out of dynamic provisioning

Set `storageClassName: ""` to bind to a pre-existing PV only. If no matching PV exists, the PVC stays `Pending`.

```yaml
spec:
  storageClassName: ""     # opt out of dynamic
  selector:
    matchLabels:
      tier: gold
  resources:
    requests:
      storage: 50Gi
```

This is useful for:

* Legacy on-prem storage that's pre-allocated
* Custom storage pools with specific labels
* Testing without consuming cloud resources

## 5. The Binding Lifecycle

The PVC's `status.phase` reflects the binding state:

| Phase | Meaning |
|---|---|
| `Pending` | No PV bound yet, waiting for one to be found or provisioned |
| `Bound` | A PV is bound to this claim |
| `Lost` | The bound PV has been lost (deleted or otherwise inaccessible) |

### 5.1 Pending → Bound

The transition happens when:

* A matching PV exists (static).
* The StorageClass's provisioner creates one (dynamic).
* The bind is allowed by the StorageClass's `volumeBindingMode` (Immediate vs WaitForFirstConsumer).

**Common reasons for staying Pending:**

* No matching PV (storage class mismatch, capacity mismatch, access mode mismatch).
* The provisioner can't reach the cloud API (auth issue, network).
* The StorageClass has `WaitForFirstConsumer` and no Pod is using the PVC yet.
* A namespace ResourceQuota is blocking the storage request (see 8-resource-quota.md).
* The provisioner is misconfigured (wrong region, missing permissions).

### 5.2 The WaitForFirstConsumer dance

With `volumeBindingMode: WaitForFirstConsumer`, the bind is delayed:

1. PVC created → `Pending`.
2. Pod referencing the PVC is scheduled to a node.
3. The provisioner creates a PV in the same zone / topology as the node.
4. PVC binds to the PV → `Bound`.
5. The Pod's kubelet mounts the volume.

The Pod has to wait for the volume. **This can add 5-30 seconds to Pod startup** (depending on the provisioner).

**Why it's the default for cloud storage:** for zone-specific storage (EBS, GCE PD), provisioning the volume before knowing the Pod's zone can mean the Pod is scheduled to a different zone and can't mount. WaitForFirstConsumer ensures correctness.

### 5.3 Lost

The PV has been lost — typically deleted out from under the PVC. The Pod using the PVC will start getting I/O errors on the mount. **This is a data loss scenario.** The PVC stays in `Lost` until manual intervention.

```bash
# check why
kubectl describe pvc <name>
# events will show the underlying volume is gone
```

To recover, you need to either restore the underlying volume or accept the loss and delete the PVC.

## 6. Capacity and Expansion

### 6.1 The request

```yaml
spec:
  resources:
    requests:
      storage: 50Gi
```

This is the **minimum** capacity. The actual capacity is in `status.capacity.storage`.

### 6.2 Online expansion (k8s 1.11+)

You can expand a PVC without deleting it:

```bash
kubectl edit pvc data
# change spec.resources.requests.storage from 50Gi to 100Gi
```

```yaml
spec:
  resources:
    requests:
      storage: 100Gi   # was 50Gi
```

The PV's `capacity` is updated, and the underlying volume is resized by the CSI driver. **Not all backends support online expansion** — check the CSI driver's docs.

### 6.3 The expansion flow

```
User edits PVC (50Gi → 100Gi)
       │
       ▼
StorageClass has allowVolumeExpansion: true?
       ├── No → PVC stays at 50Gi, the resize is silently rejected
       │        (kubectl edit succeeds but the actual size doesn't change)
       │
       └── Yes → PVC enters "Resizing" condition
                       │
                       ▼
              CSI driver supports expansion?
                       ├── No → expansion fails, error in events
                       │
                       └── Yes → CSI driver resizes the volume
                                       │
                                       ▼
                              Pod's filesystem is resized (CSI driver signals kubelet)
                                       │
                                       ▼
                              PVC status.capacity = 100Gi
```

For the filesystem to be resized (not just the underlying volume), the CSI driver supports **`ControllerExpandVolume`** and **`NodeExpandVolume`**. Most do.

### 6.4 Shrinking

You **cannot shrink a PVC**. Once expanded, you can't go back. This is intentional — shrinking risks data loss.

If you need a smaller volume, create a new one and migrate data.

### 6.5 Capacity constraints

* The expansion is **online** if the volume is in use and the driver supports it. Otherwise, the Pod may need to be restarted (driver-dependent).
* Some drivers don't allow expansion of volumes in use (e.g. older EBS CSI versions). Check the docs.
* The expanded capacity must be **larger** than the current. Shrinking is rejected.
* Expanding across storage classes is not allowed.

## 7. Volume Modes: Filesystem vs Block

```yaml
spec:
  volumeMode: Filesystem   # default
  # or
  volumeMode: Block
```

### 7.1 Filesystem mode

The volume is **formatted with a filesystem** (ext4, xfs, etc.) by the CSI driver. The Pod mounts it as a directory.

```yaml
volumeMounts:
- name: data
  mountPath: /var/lib/data
```

The CSI driver:

1. Creates the volume.
2. Formats it (if not already formatted).
3. Mounts it on the node.
4. The kubelet bind-mounts it into the container.

### 7.2 Block mode

The volume is exposed as a **raw block device** (`/dev/xvda` or similar). The Pod sees a device, not a directory.

```yaml
volumeDevices:
- name: data
  devicePath: /dev/xvda
```

The container reads/writes the device directly. **Used for apps that manage their own filesystem** — databases, ZFS, raw block apps.

**Block mode constraints:**

* `volumeMode` must match between PVC and PV.
* `accessModes` must be compatible (RWO or RWOP, typically).
* The container must be able to use the device path (no `volumeMounts`, use `volumeDevices`).
* `fsType` is irrelevant in block mode (the device is unformatted).

## 8. DataSource: Cloning and Restoring

A PVC can be created from a **VolumeSnapshot** or another **PVC** (cloning). This is how you do point-in-time backups and restores.

### 8.1 Restoring from a snapshot

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-restored
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 50Gi
  dataSource:
    apiGroup: snapshot.storage.k8s.io
    kind: VolumeSnapshot
    name: my-snapshot
```

The cluster:

1. Creates a new volume.
2. Copies the data from the snapshot into the new volume.
3. Binds the PVC to the new PV.

The new PVC is a **copy of the snapshot at the time the snapshot was taken**. Subsequent writes to the original PVC don't affect the restored PVC.

### 8.2 Cloning a PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-clone
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 50Gi
  dataSource:
    kind: PersistentVolumeClaim
    name: data-original
```

The cluster:

1. Creates a new volume.
2. Copies the data from the source PVC.
3. Binds the new PVC to the new PV.

Cloning is useful for:

* **Testing** — copy a production DB to a dev environment.
* **Branching data** — fork the data for an experiment.
* **Migrations** — copy data from one cluster to another.

### 8.3 The dataSourceRef (k8s 1.22+)

`dataSourceRef` is a typed version of `dataSource`:

```yaml
dataSourceRef:
  apiGroup: snapshot.storage.k8s.io
  kind: VolumeSnapshot
  name: my-snapshot
```

It's almost identical to `dataSource` but with stricter validation. **Prefer `dataSourceRef` over `dataSource`** for new code.

## 9. Volume Populators

A **volume populator** is a controller that handles a custom `dataSourceRef.kind`. The default Kubernetes installation supports `VolumeSnapshot` and `PersistentVolumeClaim`. Custom populators can be installed for:

* **Database snapshots** — restore from a database-aware snapshot (Postgres WAL position, etc.).
* **S3-backed volumes** — populate a CSI volume with S3 data.
* **Custom workflows** — anything that can be expressed as "create a volume with these contents".

The populator registers itself with the apiserver, and the kube-controller-manager defers to it when it sees the custom `kind`.

## 10. PVC Selectors and Matchmaking

In **static provisioning**, a PVC can use a `selector` to bind to a specific PV:

```yaml
spec:
  storageClassName: ""        # opt out of dynamic
  selector:
    matchLabels:
      tier: gold
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
```

This binds to a PV that has `tier: gold` and `storageClassName: ""`.

### 10.1 Match semantics

* The PV's labels must satisfy both `matchLabels` and `matchExpressions`.
* The PV's `accessModes`, `storageClassName`, and `volumeMode` must match the PVC's.
* The PV's `capacity` must be **at least** the PVC's request.

If no matching PV exists, the PVC stays `Pending`. **There is no error, just silence.** This is a common source of confusion.

### 10.2 Empty selector

```yaml
spec:
  selector: {}     # matches all PVs
```

This binds to any PV that satisfies the other constraints. **Use with care** — it can match unintended PVs.

## 11. The Pod's View: How It Mounts

A Pod mounts a PVC via a `volumes[]` entry of type `persistentVolumeClaim`:

```yaml
volumes:
- name: data
  persistentVolumeClaim:
    claimName: data     # the PVC's name, in the Pod's namespace
```

### 11.1 The mount flow

1. Pod is scheduled to a node.
2. The kubelet on the node sees the PVC reference.
3. If the PVC is `Pending`, the Pod waits (or fails to start, depending on the bind mode).
4. If the PVC is `Bound`, the kubelet calls the CSI driver's `NodeStageVolume` and `NodePublishVolume` to mount the volume on the node.
5. The kubelet bind-mounts the node's mount point into the container.
6. The container's `volumeMounts[].mountPath` (or `volumeDevices[].devicePath`) sees the volume.

### 11.2 Same-namespace rule

The PVC and the Pod must be in the **same namespace**. A Pod in `default` can't mount a PVC in `prod`.

Cross-namespace mounting requires:

* **A second PVC in the same namespace** that references the same PV (via a `dataSource` of kind `PersistentVolumeClaim`).
* **Read-only mounting** from a different namespace — the Pod can use a PVC in its own namespace that was created from a snapshot of the original.

There is **no direct cross-namespace PVC mount**.

### 11.3 subPath and subPathExpr

Like other volume types, a PVC-backed volume can be mounted with `subPath` or `subPathExpr`:

```yaml
volumeMounts:
- name: data
  mountPath: /var/lib/data/$(POD_NAME)
  subPathExpr: $(POD_NAME)
```

**`subPath` bypasses volume updates.** A subPath mount of a PVC doesn't track updates to the volume. Don't use subPath with PVCs you expect to be expanded (or that have hot-updated data).

**`subPathExpr` is the templated alternative.** Use it for per-Pod directories in shared volumes.

## 12. Operations and Debugging

### 12.1 Common commands

```bash
# list PVCs
kubectl get pvc -A
# shows NAME, STATUS, VOLUME, CAPACITY, ACCESS MODES, STORAGECLASS, AGE

# describe
kubectl describe pvc <name>
# shows spec, status, events, the bound PV

# check the bound PV
kubectl get pv <volume-name>
# shows the underlying volume (EBS volume ID, EFS file system ID, etc.)

# check the Pod's view
kubectl describe pod <pod>
# look for "MountVolume.SetUp failed" or similar events

# check the CSI driver
kubectl -n kube-system get pods -l <csi-driver-label>
kubectl -n kube-system logs -l <csi-driver-label> --tail=100
```

### 12.2 The "PVC Pending" checklist

```bash
# 1. Is there a matching PV?
kubectl get pv
# look for an Available PV with matching accessModes, capacity, storageClassName

# 2. Is the StorageClass installed?
kubectl get storageclass

# 3. Is the provisioner running?
kubectl -n kube-system get pods -l <csi-driver-label>
# the pod for your provisioner (e.g. ebs-csi-controller)

# 4. Is the provisioner authenticated to the cloud?
kubectl -n kube-system logs -l <csi-driver-label> --tail=100
# look for "failed to create volume", "AccessDenied", "AuthFailure", etc.

# 5. Is the StorageClass configured correctly?
kubectl describe storageclass <name>
# check provisioner, parameters, volumeBindingMode

# 6. Is there a ResourceQuota blocking?
kubectl get resourcequota -A
# storage quota can block PVC creation

# 7. Is the requested capacity too large for the underlying volume type?
# EBS has discrete GB sizes, gp3 has min/max IOPS, etc.

# 8. Zone mismatch (multi-AZ clusters)
# with WaitForFirstConsumer, the PV should be in the same zone as the Pod
# without it, the PV may be in a different zone
kubectl describe node <name>
kubectl get pv -o custom-columns=NAME:.metadata.name,ZONE:.spec.nodeAffinity
# (zone information may be in different fields for different drivers)
```

### 12.3 The "Pod can't mount PVC" cases

```bash
# Pod events
kubectl describe pod <pod>
# look for:
#   - "MountVolume.SetUp failed for volume"
#   - "FailedMount"
#   - "Unable to attach or mount volumes"
#   - "Volume is already exclusively attached"

# Check the volume is in the right zone
# (for cloud disks)
aws ec2 describe-volumes --volume-ids <volume-id> --query 'Volumes[0].AvailabilityZone'
kubectl get node <pod-node> -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}'

# Check the PVC is in the right namespace
kubectl get pvc <name> -n <pod-namespace>
# if it's in a different namespace, the Pod can't see it

# Check the PVC is bound
kubectl get pvc <name> -o jsonpath='{.status.phase}'
# should be "Bound"
```

### 12.4 The "I/O error on the mount" case

If the Pod is running but the mount has I/O errors, the underlying volume is gone (or unreachable):

```bash
# exec into the Pod
kubectl exec -it <pod> -- df -h
# I/O error = volume is gone

# check the bound PV
kubectl get pv -o yaml | grep -A 5 "csi:"
# look for the volumeHandle (cloud volume ID)
# verify it still exists in the cloud
```

Recovery:

* If the cloud volume was deleted accidentally, restore from a snapshot.
* If the volume is in a different zone, the Pod can't reach it.
* If the CSI driver has lost its connection to the cloud, the volume is effectively gone.

## 13. Gotchas and Common Mistakes

### 13.1 The 25+ common mistakes

1. **PVCs are namespaced.** A PVC in `ns-a` cannot be used by a Pod in `ns-b`. The Pod can only see PVCs in its own namespace.

2. **Bound PVs are immutable in `accessModes`, `storageClassName`, `volumeMode`.** To change them, you'd need a new PVC.

3. **A PVC stuck in `Pending` is the most common storage issue.** Run `kubectl describe pvc` and read the events. Usually: no matching PV, no dynamic provisioner, wrong zone, or no quota.

4. **Deleting a PVC destroys the data** if the PV's `persistentVolumeReclaimPolicy` is `Delete`. Be careful. Use `Retain` for databases.

5. **A StatefulSet creates a PVC per replica automatically.** The PVC template is in the StatefulSet spec, not a separate YAML. See `03-statefulsets.md` (in the L03 folder).

6. **`subPath` on a PVC-backed volume mount means the volume is mounted at a subpath, but all subPaths share the same volume.** Don't expect isolation.

7. **Block mode PVCs cannot be mounted as filesystem.** They're for raw block access (databases that want to manage the filesystem themselves).

8. **Empty selector (`{}`) matches all PVs.** This can bind to unintended PVs. Use specific labels.

9. **The PVC's `storageClassName: ""` (empty string) is different from unset.** Set both explicitly. Mismatch = no bind.

10. **`WaitForFirstConsumer` delays binding until a Pod uses the PVC.** The Pod can't start until the PV is provisioned. Add this to your deployment scripts.

11. **CSI drivers can be slow.** A new PV can take 5-30 seconds to provision. Don't expect instant.

12. **The PVC's `resources.requests.storage` is a minimum, not a maximum.** Some backends may provide more. The actual capacity is in `status.capacity.storage`.

13. **Shrinking is not allowed.** Expanding is, but you can't go back. Create a new PVC if you need a smaller volume.

14. **Online expansion depends on the CSI driver.** Older drivers don't support it. The Pod may need to be restarted.

15. **`dataSource` vs `dataSourceRef`:** `dataSourceRef` is the typed, validated version. Use it for new code.

16. **A PVC with `dataSource` and `dataSourceRef` both set is invalid.** Pick one.

17. **Cross-namespace PVCs don't work directly.** You can't have a Pod in `default` mount a PVC in `prod`. Create a second PVC in `default` (via snapshot clone).

18. **A PVC with no `accessModes` defaults to an empty list.** The apiserver may reject this. Set at least one mode.

19. **The PVC's `status.phase` is `Pending` until bound.** Check `kubectl describe pvc` for events to see why.

20. **A PVC with `Lost` status has lost its underlying volume.** This is a data loss scenario. Recover from snapshot or accept loss.

21. **The `selector` field is only useful in static provisioning.** In dynamic provisioning, the StorageClass determines the PV.

22. **The `dataSource.kind: PersistentVolumeClaim` is for cloning, not for cross-namespace mounting.** A PVC in `prod` can't be referenced by a Pod in `default` directly.

23. **A PVC created from a snapshot is a copy, not a reference.** Subsequent writes to the source don't affect the clone. Cloning is a point-in-time operation.

24. **CSI drivers may not support all features.** Snapshots, expansion, clones, RWX — check the driver docs. `reclaimPolicy: Delete` and `allowVolumeExpansion: true` are honored only if the driver supports them.

25. **The Pod's `volumes[].persistentVolumeClaim.claimName` must match exactly.** Typo → `PVC not found`.

26. **A Pod can be scheduled to a node where the volume isn't available.** The kubelet will then fail to mount. The Pod stays in `ContainerCreating` until the issue is resolved.

27. **The PVC's `metadata.labels` are propagated to the dynamically-created PV.** Use them to identify which PVC owns which PV (the PV gets `pv.kubernetes.io/bound-by-controller: "yes"` and other labels).

28. **A PVC with `volumeMode: Block` needs `volumeDevices[].devicePath` in the Pod, not `volumeMounts[].mountPath`.** A block volume can't be mounted as a directory.

29. **`WaitForFirstConsumer` interacts badly with `kubectl create -f` workflows.** The Pod has to be created and scheduled before the PV is provisioned. If you're scripting, the Pod may not start for 30+ seconds.

30. **The `selector.matchLabels` field requires the PV to have those labels.** If the PV's labels were set by the admin and the PVC's selector asks for a different label, no bind.

## See also

* [[Kubernetes/concepts/L05-config-storage/03-volumes|Volume Types]] — the volume types, including PVCs
* [[Kubernetes/concepts/L05-config-storage/04-persistentvolume|PersistentVolume]] — the cluster-scoped storage object
* [[Kubernetes/concepts/L05-config-storage/06-storageclass|StorageClass]] — dynamic provisioning
* [[Kubernetes/concepts/L05-config-storage/07-storage|Storage]] — the L05 mental model
* [[Kubernetes/concepts/L03-workloads/04-statefulsets|StatefulSets]] — primary consumer of PVCs

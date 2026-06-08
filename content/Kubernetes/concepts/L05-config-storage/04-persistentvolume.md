# PersistentVolume (PV)

*"https://kubernetes.io/docs/concepts/storage/persistent-volumes/"*

A PersistentVolume (PV) is a **piece of storage in the cluster** that has been provisioned by an administrator or dynamically by a StorageClass. It's a cluster-level resource (not namespaced) — like a node, it represents physical or virtual infrastructure.

### Table of Contents

1. [The Two-Step Model: PV and PVC](#1-the-two-step-model-pv-and-pvc)
2. [The PV Lifecycle](#2-the-pv-lifecycle)
3. [PV Specification in Detail](#3-pv-specification-in-detail)
4. [Access Modes in Detail](#4-access-modes-in-detail)
5. [Reclaim Policies in Detail](#5-reclaim-policies-in-detail)
6. [Static Provisioning](#6-static-provisioning)
7. [Dynamic Provisioning](#7-dynamic-provisioning)
8. [Volume Modes: Filesystem vs Block](#8-volume-modes-filesystem-vs-block)
9. [Capacity, Limits, and What They Mean](#9-capacity-limits-and-what-they-mean)
10. [Binding Lifecycle and Phases](#10-binding-lifecycle-and-phases)
11. [In-Use PVs: Modifying and Protecting](#11-in-use-pvs-modifying-and-protecting)
12. [PV Selectors and Matchmaking](#12-pv-selectors-and-matchmaking)
13. [Operations and Debugging](#13-operations-and-debugging)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)

---

## 1. The Two-Step Model: PV and PVC

The k8s storage model has **two** objects for a reason: to separate "how storage is provided" (PV) from "how it's consumed" (PVC). This separation lets:

* **Admins** define storage offerings (PVs from a pool, or StorageClasses that create them on demand).
* **Users** request storage (PVCs) without knowing the details.
* **The system** match requests to offerings (binding).

```
┌────────────┐         ┌────────────┐         ┌────────────┐
│  Storage   │  →→→   │     PV     │  ←←←   │    PVC     │
│  backend   │         │  (cluster) │         │(namespaced)│
│ (NFS, EBS, │         │            │         │            │
│  iSCSI,    │         │            │         │            │
│  Ceph, …)  │         │            │         │            │
└────────────┘         └────────────┘         └────────────┘
                                                       ↑
                                                  claimed by
                                                       Pod
```

A Pod doesn't bind to a PV directly. The Pod (or the controller managing the Pod) creates a **PersistentVolumeClaim**, and the claim is bound to a PV that matches.

### 1.1 Why two objects?

* **Decoupling** — the admin doesn't know which Pods will use the storage. The user doesn't know which backend it ends up on.
* **Reuse** — a PV can be reused across PVCs (with reclaim).
* **Abstraction** — the user requests "50 GiB of RWO storage from the gp3 class". The system figures out the rest.
* **Namespacing** — PVCs are namespaced, PVs are cluster-scoped. This matches the ownership model: storage is a cluster resource, claims are per-namespace.

### 1.2 The two provisioning models

| | Static | Dynamic |
|---|---|---|
| Who creates the PV | Admin | StorageClass + provisioner |
| When the PV is created | Before the PVC | When the PVC is created |
| How the user requests | PVC matches a pre-existing PV | PVC with `storageClassName` |
| Production use | Legacy / on-prem | **The default in modern clusters** |

In static provisioning, the admin pre-creates PVs (often by hand, often from a fixed pool). In dynamic provisioning, the cluster creates PVs on demand via a StorageClass.

## 2. The PV Lifecycle

A PV goes through these states:

```
                  ┌─→ Available
                  │     │
   (static)       │     │ (PVC matches)
   admin creates  │     ▼
   PV             │   Bound
                  │     │
                  │     │ (PVC deleted)
                  │     ▼
                  │   Released
                  │     │
                  │     │ (depending on reclaim policy)
                  │     │
                  │     ├── Retain → stays in Released, admin cleans up
                  │     ├── Delete → underlying volume deleted, PV removed
                  │     └── Recycle → deprecated, do not use
                  │
                  └─→ Failed
```

### 2.1 Available

The PV is free, not bound to a PVC. Available for new claims.

### 2.2 Bound

The PV is bound to a PVC. The PVC's status `accessModes`, `volumeMode`, and `storageClassName` match. The underlying storage has been mounted (or is ready to be mounted) on a node.

Bound PVs are **immutable in certain fields** (see section 11).

### 2.3 Released

The PVC has been deleted, but the PV has not been reused or deleted. The PV's `persistentVolumeReclaimPolicy` determines what happens next:

* **`Retain`** — the PV stays in `Released`. The admin must manually clean up the underlying storage and either reuse the PV (by deleting and recreating the claim) or remove it.
* **`Delete`** — the underlying storage is deleted by the CSI driver. The PV object is also deleted.

### 2.4 Failed

The PV has failed to be provisioned or released. The PV object exists but the underlying storage didn't materialize (or is gone). Manual intervention required.

### 2.5 Phase transitions

```
           ┌─────────────────────────────────┐
           ▼                                 │
       Available ──── (claim created) ────► Bound ──── (claim deleted) ────► Released
           │                                                                   │
           │                                                                   │
           │                                                                   │
           └────────────────────── (manually) ─────────────── (manually) ◄────┘
                                                       (Released → Available)
```

The transition from `Released` to `Available` requires **manual intervention** for `Retain`. For `Delete`, the PV is removed entirely.

## 3. PV Specification in Detail

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-1
  labels:
    tier: gold              # used for PV selector matching
  annotations:
    pv.kubernetes.io/provisioned-by: ebs.csi.aws.com   # set by dynamic provisioner
spec:
  capacity:
    storage: 100Gi
  volumeMode: Filesystem   # or "Block"
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: gold
  mountOptions:
  - debug
  # one of: (CSI / NFS / hostPath / iSCSI / ... — see 3.1)
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: vol-0123456789abcdef0
    fsType: ext4
    volumeAttributes:
      storage.kubernetes.io/csiProvisionerIdentity: ebs.csi.aws.com
  # OR for static NFS:
  # nfs:
  #   server: nfs.example.com
  #   path: /exports/data
  #   readOnly: false
  # OR for static hostPath (dev only):
  # hostPath:
  #   path: /data/pv-1
  #   type: Directory
  claimRef:                  # set by the system when bound
    apiVersion: v1
    kind: PersistentVolumeClaim
    name: my-claim
    namespace: prod
    uid: ...
```

### 3.1 Volume source types

The PV can be backed by:

* `csi` — Container Storage Interface (most common in production)
* `nfs` — legacy, deprecated
* `hostPath` — dev only
* `iscsi` — iSCSI target
* `fc` — Fibre Channel
* `glusterfs` — GlusterFS
* `rbd` — Ceph RBD
* `cephfs` — CephFS
* `azureFile`, `azureDisk` — Azure storage (in-tree, removed in 1.26+)
* `awsElasticBlockStore` — AWS EBS (in-tree, removed in 1.26+)
* `gcePersistentDisk` — GCE PD (in-tree, removed in 1.26+)
* `local` — local node storage (different model, see below)
* `flexVolume` — deprecated, removed in 1.26+

### 3.2 The `claimRef` field

Set automatically by the system when a PVC binds to the PV. Prevents the PV from being bound to a different PVC, even if the new PVC's selector matches. **Don't set this by hand** unless you know what you're doing.

## 4. Access Modes in Detail

| Mode | Abbreviation | Description |
|---|---|---|
| `ReadWriteOnce` | RWO | Mounted read-write by a single node |
| `ReadOnlyMany` | ROX | Mounted read-only by many nodes |
| `ReadWriteMany` | RWX | Mounted read-write by many nodes |
| `ReadWriteOncePod` | RWOP | Mounted read-write by a single Pod (k8s 1.22+) |

### 4.1 ReadWriteOnce (RWO)

The most restrictive. **One node can mount the volume read-write.** Multiple Pods on the same node can mount it.

This works for most databases (Postgres, MySQL, MongoDB) — the database runs on a single node. It also works for StatefulSets with `volumeClaimTemplates` — each Pod has its own PV.

**The "one node" detail matters.** A RWO PV can be mounted by multiple Pods on the same node, but not by Pods on different nodes. For a single-instance database, this is fine. For a database cluster with replicas on different nodes, you need RWX or RWOP.

### 4.2 ReadOnlyMany (ROX)

Many nodes can mount the volume read-only. Used for:

* **Shared content** — read-only data that all Pods need (configs, models, static assets).
* **Multi-replica reads** — when all replicas should see the same data.

### 4.3 ReadWriteMany (RWX)

Many nodes can mount the volume read-write. The hardest mode to support. Backends:

* **NFS** — the original RWX backend.
* **AWS EFS** — RWX, AWS's managed NFS-like service.
* **Azure Files** — RWX.
* **CephFS** — RWX.
* **GlusterFS** — RWX.
* **Some CSI drivers** (NetApp, Pure, etc.) — RWX.

**EBS does NOT support RWX.** This is a frequent mistake. If you need RWX on AWS, use EFS (or a third-party driver).

### 4.4 ReadWriteOncePod (RWOP)

The most restrictive. **Only one Pod can mount the volume, on any node.** k8s 1.22+.

Use case: **single-writer volumes where the writer is a Pod, not a node.** For example, a database that insists on being the only writer. RWO would allow multiple Pods on the same node to mount; RWOP prevents that.

Backends: EFS (1.27+), some CSI drivers, and a few cloud disks that support it.

### 4.5 The PVC-to-PV access mode matching

A PVC can request a specific access mode, and it binds to a PV that supports **at least** that mode. The reverse is also true: a PVC requesting RWO can bind to a PV with RWO only. A PVC requesting RWX needs a PV that supports RWX.

The exact matching rules:

| PVC requests | PV supports | Match? |
|---|---|---|
| RWO | RWO | ✅ |
| RWO | ROX | ❌ (ROX is read-only) |
| RWO | RWX | ✅ (PV supports more than PVC needs) |
| RWX | RWO | ❌ (PV doesn't support RWX) |
| RWX | RWX | ✅ |
| ROX | ROX | ✅ |
| ROX | RWO | ✅ (ROX is a subset of RWO) |

Wait, the last row is correct: RWO is more permissive than ROX (RWO is read-write, which can be used as read-only). A RWO PV can satisfy a ROX request.

**The full matrix:**

| PVC \ PV | RWO | ROX | RWX | RWOP |
|---|---|---|---|---|
| RWO | ✅ | ❌ | ✅ | ❌ |
| ROX | ✅ | ✅ | ✅ | ❌ |
| RWX | ❌ | ❌ | ✅ | ❌ |
| RWOP | ❌ | ❌ | ❌ | ✅ |

Wait, that's not quite right. Let me redo it more carefully. The rule is: the PV's accessModes must be a **superset** of the PVC's request.

| PVC \ PV | RWO | ROX | RWX | RWOP |
|---|---|---|---|---|
| RWO | ✅ | ❌ | ✅ | ❌ |
| ROX | ✅ | ✅ | ✅ | ❌ |
| RWX | ❌ | ❌ | ✅ | ❌ |
| RWOP | ❌ | ❌ | ❌ | ✅ |

Yes, that's right. RWO PV matches RWO or ROX PVC. RWX PV matches RWO, ROX, or RWX PVC. RWOP PV only matches RWOP PVC.

**Practical:** when defining a StorageClass or PV, the access modes you list are what it supports. A PVC requesting RWO binds to a PV that lists `[RWO]` (or `[RWO, RWX]`). A PVC requesting RWX needs a PV that lists `[RWX]`.

## 5. Reclaim Policies in Detail

| Policy | Default for | Behavior |
|---|---|---|
| `Retain` | Manually-created PVs | Keep the data, leave the PV in `Released` state. Admin cleans up manually. |
| `Delete` | Dynamically-provisioned PVs | Delete the underlying storage asset AND the PV object. |
| `Recycle` | n/a | **Deprecated.** Do not use. |

### 5.1 Retain

The PV survives the PVC. The underlying storage asset survives. The PV is in `Released` state, and an admin must:

1. Verify the underlying storage is no longer needed (or back it up).
2. Delete the PV (so it can be reused) or clean up the storage (so the PV is truly gone).
3. If you want to **rebind** the PV, you have to remove its `claimRef` first.

**Use case:** databases, anything with persistent data that you don't want to lose on a PVC delete.

### 5.2 Delete

The PV is **deleted when the PVC is deleted**. The CSI driver is asked to delete the underlying storage asset (e.g. the EBS volume), and the PV object is removed from etcd.

**Use case:** ephemeral storage, caches, build scratch — anything where losing the data on PVC delete is fine.

### 5.3 Recycle

Runs `rm -rf /*` on the volume. **Deprecated since k8s 1.15.** Don't use it. If you need to clean a volume, use a CSI driver's snapshot / restore flow, or just delete the volume.

### 5.4 Setting reclaim policy

On the PV:

```yaml
spec:
  persistentVolumeReclaimPolicy: Retain
```

On the StorageClass (for dynamic PVs):

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gold
provisioner: ebs.csi.aws.com
reclaimPolicy: Delete    # default for dynamic PVs
parameters:
  type: io2
  iopsPerGB: "50"
```

The PV's reclaim policy is set at creation. To change it:

```bash
kubectl patch pv <name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

**This is allowed only for PVs that are not yet bound.** Once bound, you can't change the reclaim policy until the PVC is deleted.

## 6. Static Provisioning

You create the PV yourself, then create a PVC that matches.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-1
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: gold
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: vol-0123456789abcdef0
    fsType: ext4
```

The PVC then matches it:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-claim
  namespace: prod
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: gold
  resources:
    requests:
      storage: 100Gi
```

The system binds them automatically. **Static provisioning is useful for legacy storage that you can't have a StorageClass create on demand** (e.g. an on-prem SAN with pre-allocated LUNs).

## 7. Dynamic Provisioning

You don't create the PV at all. You create a PVC that references a StorageClass, and k8s (via the storage provisioner) creates the PV for you. **This is the only sane way to run in production.**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-claim
  namespace: prod
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 100Gi
```

→ k8s calls the `gp3` provisioner → provisioner creates the EBS volume + PV → PVC binds to PV → Pod mounts the claim.

The PV that gets created looks something like:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pvc-a1b2c3d4-...
  annotations:
    pv.kubernetes.io/provisioned-by: ebs.csi.aws.com
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: gp3
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: vol-0987654321fedcba0
    fsType: ext4
  claimRef:
    apiVersion: v1
    kind: PersistentVolumeClaim
    name: my-claim
    namespace: prod
    uid: ...
```

You can `kubectl get pv` to see all the dynamically-provisioned PVs, but you rarely need to interact with them.

## 8. Volume Modes: Filesystem vs Block

```yaml
spec:
  volumeMode: Filesystem   # default
  # or
  volumeMode: Block
```

### 8.1 Filesystem (default)

The volume is **formatted with a filesystem** (ext4, xfs, etc.) and mounted as a directory. The Pod sees files.

This is what most apps want. The CSI driver handles the formatting.

### 8.2 Block

The volume is **exposed as a raw block device** (`/dev/sdb` or similar). The Pod sees a block device, not a directory.

**Use case:** apps that manage their own filesystem — databases that want to format the device with their preferred filesystem (Postgres, MySQL, ZFS), or apps that use raw block for performance.

```yaml
volumeMounts:
- name: data
  devicePath: /dev/xvda   # not mountPath — it's a device
```

**Block volumes can't be mounted as filesystems** (and vice versa). The PVC and the volume mount must match.

## 9. Capacity, Limits, and What They Mean

```yaml
spec:
  capacity:
    storage: 100Gi
```

This is the **requested capacity**. The system tries to provide at least this much.

**Important:** the PV's `capacity` is **not always enforced at the storage level** (in many backends). A 10Gi PV on a 100Gi EBS volume just records "10Gi requested" — the actual EBS volume is 100Gi, and the PV's `capacity` is more of a label than a hard limit.

For backed-by-disk volumes (EBS, GCE PD, etc.), the PV's `capacity` should match the actual volume size. The CSI driver usually sets it correctly.

For **block-mode** volumes, the `capacity` is the device size.

### 9.1 Capacity expansion (k8s 1.11+)

A PVC's storage can be expanded:

```bash
kubectl edit pvc my-claim
# change spec.resources.requests.storage from 50Gi to 100Gi
```

The PV's `capacity` is updated, and the underlying volume is resized by the CSI driver. **Not all backends support online expansion** — check the CSI driver's docs.

Conditions for online expansion:

* The StorageClass has `allowVolumeExpansion: true`.
* The CSI driver supports expansion.
* The volume is in a state that allows expansion (not in use, or the driver supports in-use expansion).

### 9.2 Capacity limits

The `capacity` is a **minimum**, not a maximum. Some backends let you provision less than the underlying volume size. The CSI driver usually rounds up to the closest supported size (e.g. EBS has discrete GB sizes).

## 10. Binding Lifecycle and Phases

When you create a PVC, it goes through:

```
Pending ──── (PV matched) ────► Bound
```

The PVC stays `Pending` until:

* A matching PV is found (static).
* The StorageClass's provisioner creates one (dynamic).
* The bind is delayed for some reason (WaitForFirstConsumer).

### 10.1 WaitForFirstConsumer

If the StorageClass has `volumeBindingMode: WaitForFirstConsumer`, the PV is **not provisioned until a Pod that uses the PVC is scheduled**. The provisioner then creates the volume in the same zone / topology as the Pod.

**Why:** for cloud storage that's zone-specific (EBS, GCE PD), provisioning the volume in the wrong zone means the Pod can't mount it. WaitForFirstConsumer ensures the volume is in the right place.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
```

The Pod sees the PVC as `Pending` until it's scheduled and the volume is provisioned. This can add a few seconds to Pod startup.

### 10.2 Binding a PVC to a specific PV

You can force a PVC to bind to a specific PV using the PV's selector:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-claim
spec:
  storageClassName: ""     # opt out of dynamic provisioning
  selector:
    matchLabels:
      tier: gold
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
```

This binds to a PV with the label `tier: gold`, if one exists. If no matching PV exists, the PVC stays `Pending`.

## 11. In-Use PVs: Modifying and Protecting

Once a PV is bound, certain fields are **immutable**:

* `accessModes`
* `storageClassName`
* `volumeMode`

The reason: changing these would mean re-mounting the volume on every node, which is risky for a running app. To change them, you'd need to:

1. Drain the Pods using the PVC.
2. Delete the PVC.
3. Create a new PVC with the new settings.

The PV itself can usually be modified to:

* `persistentVolumeReclaimPolicy` (with restrictions — see 5.4)
* `capacity` (via expansion)
* `mountOptions` (with restrictions)
* `labels` / `annotations`

### 11.1 The `claimRef` protection

The PV's `claimRef` field is set when the PVC binds. If a new PVC is created with the same selector, it **won't** bind to this PV — the `claimRef` points to a different (or no longer existing) claim. **To rebind a Released PV**, you have to remove the `claimRef`:

```bash
kubectl patch pv <name> --type=json \
  -p='[{"op":"remove","path":"/spec/claimRef"}]'
```

This is intentional — it prevents accidental rebinding to the wrong claim.

## 12. PV Selectors and Matchmaking

PVs have labels (set by the admin or the provisioner). PVCs can use a `selector` to match specific PVs:

```yaml
# PV with labels
metadata:
  labels:
    tier: gold
    environment: production
---
# PVC with selector
spec:
  selector:
    matchLabels:
      tier: gold
    matchExpressions:
    - key: environment
      operator: In
      values: [production, staging]
```

The PVC binds to a PV whose labels match **both** `matchLabels` and `matchExpressions`.

`matchLabels` is exact match on key=value pairs.
`matchExpressions` allows set-based selectors (In, NotIn, Exists, DoesNotExist).

**Selectors are only used in static provisioning.** In dynamic provisioning, the StorageClass (not the PV's labels) determines which volume gets created. The PV is created with the labels specified in the PVC's `selector` field via `volumeClaimTemplate.metadata.labels`.

### 12.1 The "PVC's storageClassName must match the PV's" rule

For a PVC to bind to a PV, their `storageClassName` fields must match. Both empty string = match. Both set to the same name = match. Mismatch = no bind.

A common mistake: setting `storageClassName: ""` on a PVC hoping to bind to a PV with no storageClassName set. This works, but the empty string must be **explicit** in both the PV and the PVC.

```yaml
# PV with no storageClassName
spec:
  storageClassName: ""     # empty string
---
# PVC with no storageClassName
spec:
  storageClassName: ""     # empty string
```

If the PV has `storageClassName: ""` and the PVC has no `storageClassName` field at all, they don't match (one is empty string, the other is unset). **Set both explicitly.**

## 13. Operations and Debugging

### 13.1 Common commands

```bash
# list PVs
kubectl get pv
# shows NAME, CAPACITY, ACCESS MODES, RECLAIM POLICY, STATUS, CLAIM, STORAGECLASS, REASON, AGE

# describe
kubectl describe pv <name>
# shows spec, status, events

# check the bound claim
kubectl get pv <name> -o jsonpath='{.spec.claimRef}'
# shows the PVC that the PV is bound to

# check the underlying volume
# (for EBS)
aws ec2 describe-volumes --volume-ids <volume-handle>

# check the CSI driver
kubectl -n kube-system get pods -l <csi-driver-label>
kubectl -n kube-system logs -l <csi-driver-label> --tail=100
```

### 13.2 The "PV stuck" cases

| Status | Cause | Fix |
|---|---|---|
| `Available` forever | No matching PVC | Create a PVC with matching accessModes, storageClassName, and capacity |
| `Bound` (good) | Working | — |
| `Released` | PVC deleted, PV not yet reused | Depends on reclaim policy. Retain: manual cleanup. Delete: PV will be removed. |
| `Failed` | Provisioning or release failed | Check CSI driver logs. Usually a permission / capacity issue. |
| `Pending` (PVC) | No matching PV, no provisioner, wrong zone, quota | See "PVC stuck" checklist |

### 13.3 The "rebind a Released PV" flow

```bash
# 1. find the Released PV
kubectl get pv
# NAME     CAPACITY   STATUS     ...
# pv-old   100Gi      Released   ...

# 2. clear the claimRef
kubectl patch pv pv-old --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'

# 3. now create a new PVC that matches
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rebound-claim
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gold
  resources:
    requests:
      storage: 100Gi
EOF
```

This binds the existing PV to the new PVC. Useful for recovering data from a Released PV.

## 14. Gotchas and Common Mistakes

### 14.1 The 25+ common mistakes

1. **PVs are cluster-scoped.** Don't try to make them namespaced. The PV lives in the cluster, the PVC lives in a namespace.

2. **A PVC can only bind to one PV.** A PV can only bind to one PVC. **One-to-one.** Once bound, the PV is "owned" by that PVC.

3. **Bound PVs are immutable in `accessModes`, `storageClassName`, `volumeMode`.** Change them only by deleting and recreating the PVC.

4. **The PV's `capacity` is not always the underlying volume size.** Some backends report capacity = request. The actual volume may be larger. Don't assume `100Gi` means exactly 100Gi.

5. **`ReadWriteOnce` means "one node", not "one Pod".** Multiple Pods on the same node can mount the same RWO volume. For "one Pod only", use `ReadWriteOncePod` (k8s 1.22+).

6. **`ReadWriteMany` is rare.** EBS, the most common cloud disk, doesn't support RWX. Use EFS, NFS, or a third-party driver for RWX on AWS.

7. **`persistentVolumeReclaimPolicy: Retain` is required for production databases.** A `Delete` policy means `kubectl delete pvc` destroys the volume. **Disaster for stateful workloads.**

8. **`Recycle` is deprecated.** Don't use it. Use `Retain` or `Delete`.

9. **The PV's `claimRef` blocks rebinding.** A Released PV can't be rebound to a new PVC without clearing the `claimRef`. Do this carefully.

10. **Dynamic PVs default to `Delete` reclaim.** The StorageClass sets this. If you want Retain for a database, set it in the StorageClass or after creation (`kubectl patch pv`).

11. **PV labels aren't enforced for binding in dynamic provisioning.** The StorageClass determines the volume, not the labels.

12. **`mountOptions` are backend-specific.** A bad `mountOptions` (e.g. `noatime` for a backend that doesn't support it) can cause mount failures.

13. **Block volumes can't be mounted as filesystems.** A `volumeMode: Block` PV needs a `volumeMounts[].devicePath`, not `mountPath`.

14. **`WaitForFirstConsumer` delays the bind.** The PVC is `Pending` until a Pod that uses it is scheduled. Add this delay to your deployment scripts.

15. **CSI drivers can be slow.** A new PV can take 5-30 seconds to provision. Don't expect instant.

16. **The `fsType` field in CSI matters.** `ext4`, `xfs`, `btrfs` — the CSI driver formats the volume with the requested filesystem. Wrong fsType = mount failure.

17. **A PV with `claimRef` to a non-existent PVC is stuck.** The PV is "bound" to a phantom claim. You have to remove the `claimRef` manually.

18. **The PV's `storageClassName: ""` (empty string) is different from unset.** Set both explicitly. Mismatch = no bind.

19. **`kubectl delete pv` on a Bound PV is rejected.** You have to delete the PVC first. This is to prevent accidental data loss.

20. **`kubectl delete pv` on a Released PV (Retain) deletes the PV object** but leaves the underlying storage. The admin must clean up the storage.

21. **The PV name doesn't have to be meaningful.** It's just an identifier. Most dynamic PVs have auto-generated names like `pvc-abc123-...`.

22. **PVs in `Failed` state need manual intervention.** They don't auto-recover. Look at the events and the CSI driver logs.

23. **The PV's `volumeMode` must match between PV and PVC.** A `Filesystem` PV can't bind to a `Block` PVC.

24. **Snapshotting requires the CSI driver to support it.** Not all do. Check the driver docs.

25. **The PV's `spec.csi.volumeHandle` is opaque.** It's whatever the driver uses to identify the volume (EBS volume ID, EFS file system ID, etc.). Don't try to parse it.

26. **CSI migration:** in k8s 1.26+, all in-tree volume types are removed. You must use CSI. If you have old manifests with `awsElasticBlockStore` or `gcePersistentDisk`, they fail to create.

27. **Some CSI drivers don't support snapshots or expansion.** Check the driver docs. The `reclaimPolicy: Delete` and `allowVolumeExpansion: true` flags are honored only if the driver supports them.

28. **The PV's `spec.csi` field is set by the provisioner for dynamic PVs.** For static PVs, you set it yourself with the right `volumeHandle` (the cloud's volume ID).

29. **`hostPath` PVs in production are an antipattern.** They survive only as long as the node does. A node replacement = data loss.

30. **The PV's `persistentVolumeReclaimPolicy` cannot be changed while the PV is bound.** Wait for the PVC to be deleted, or `kubectl patch` after the PV is Released.

## See also

* [[Kubernetes/concepts/L05-config-storage/03-volumes|Volume Types]] — the volume types, including PVCs
* [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim|PersistentVolumeClaim]] — the user-facing API
* [[Kubernetes/concepts/L05-config-storage/06-storageclass|StorageClass]] — dynamic provisioning
* [[Kubernetes/concepts/L05-config-storage/07-storage|Storage]] — the L05 mental model

# StorageClass

*"https://kubernetes.io/docs/concepts/storage/storage-classes/"*

A StorageClass is a **way to describe "types" of storage** you can dynamically provision. It maps a name (like `gp3` or `ssd`) to a provisioner and a set of parameters. Without StorageClasses, you'd hand-create PVs for every workload — a nightmare at scale.

### Table of Contents

1. [Why StorageClasses Exist](#1-why-storageclasses-exist)
2. [Basic Example](#2-basic-example)
3. [StorageClass Specification in Detail](#3-storageclass-specification-in-detail)
4. [Volume Binding Modes — Immediate vs WaitForFirstConsumer](#4-volume-binding-modes--immediate-vs-waitforfirstconsumer)
5. [Reclaim Policy on the StorageClass](#5-reclaim-policy-on-the-storageclass)
6. [The Default StorageClass](#6-the-default-storageclass)
7. [Common Provisioners](#7-common-provisioners)
8. [Provisioner-Specific Parameters](#8-provisioner-specific-parameters)
9. [allowedTopologies and Multi-Zone Clusters](#9-allowedtopologies-and-multi-zone-clusters)
10. [Mount Options](#10-mount-options)
11. [Volume Expansion](#11-volume-expansion)
12. [Snapshots and Clones](#12-snapshots-and-clones)
13. [Multiple StorageClasses — Performance Tiers](#13-multiple-storage-classes--performance-tiers)
14. [Operations and Debugging](#14-operations-and-debugging)
15. [Gotchas and Common Mistakes](#15-gotchas-and-common-mistakes)

---

## 1. Why StorageClasses Exist

Before StorageClasses (k8s 1.4+), an admin had to hand-create PVs for every workload. With StorageClasses, a user just requests "give me 100Gi of `gp3`" and the cluster creates the volume on-demand.

```
Without StorageClass:                      With StorageClass:

User requests storage                       User requests storage
       │                                          │
       ▼                                          ▼
Admin creates PV                          PVC created with storageClassName: gp3
       │                                          │
       ▼                                          ▼
Admin creates PVC                         StorageClass triggers provisioner
       │                                          │
       ▼                                          ▼
PVC binds to PV                           Provisioner creates PV
       │                                          │
       ▼                                          ▼
Pod mounts                                PVC binds to PV
                                                  │
                                                  ▼
                                            Pod mounts
```

**StorageClasses turn storage from a manual, ticket-driven process into an automated, declarative one.** The user doesn't need to know the backend; the admin defines "tiers" and the system picks the right one.

## 2. Basic Example

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com       # the CSI driver
parameters:
  type: gp3
  fsType: ext4
  iopsPerGB: "3000"
reclaimPolicy: Delete              # what happens to the PV when PVC is deleted
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
mountOptions:
  - debug
```

Now any PVC that sets `storageClassName: gp3` will trigger the `ebs.csi.aws.com` provisioner to create an EBS volume matching the request.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 100Gi
```

→ k8s calls the `gp3` provisioner → provisioner creates the EBS volume + PV → PVC binds to PV → Pod mounts the claim.

## 3. StorageClass Specification in Detail

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gold
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"  # marks this as default
provisioner: ebs.csi.aws.com
parameters:
  type: io2
  iopsPerGB: "50"
  fsType: ext4
  encrypted: "true"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
allowedTopologies:
- matchLabelExpressions:
  - key: topology.kubernetes.io/zone
    values: ["us-east-1a", "us-east-1b"]
mountOptions:
- noatime
- debug
```

### 3.1 The `provisioner` field

The driver to call. Three kinds:

* **CSI driver** — `ebs.csi.aws.com`, `disk.csi.azure.com`, `pd.csi.storage.gke.io`, etc. **The standard.**
* **In-tree provisioner** — `kubernetes.io/aws-ebs`, `kubernetes.io/gce-pd`, etc. **Removed in k8s 1.26+.**
* **Local provisioner** — `kubernetes.io/no-provisioner`. Used with `local` PVs (the user creates the PV manually, no cloud volume).

The provisioner name is **opaque to k8s** — it's just a string the driver registers itself as. The driver watches for PVCs with a matching `storageClassName.provisioner` and creates volumes.

### 3.2 The `parameters` field

Provisioner-specific configuration. Each driver has its own parameter set:

* **EBS CSI**: `type`, `iopsPerGB`, `fsType`, `encrypted`, `kmsKeyId`
* **EBS CSI (v1.30+)**: `blockSize`, `inodeSize`, `throughput`
* **GCE PD CSI**: `type` (pd-standard, pd-balanced, pd-ssd), `replication-type`
* **Azure Disk CSI**: `skuName` (Premium_LRS, StandardSSD_LRS, etc.)
* **Azure File CSI**: `skuName`, `protocol`
* **Ceph RBD CSI**: `pool`, `clusterID`, `imageFeatures`

Always check the driver's docs. **Parameters are case-sensitive and validated by the driver**, not the apiserver.

### 3.3 The `reclaimPolicy` field

What happens to the PV when the PVC is deleted. See `04-persistentvolume.md` for the full discussion. The two useful values:

* `Delete` (default for dynamic) — the underlying volume is deleted.
* `Retain` — the underlying volume is kept, the PV goes to `Released` state.

```yaml
reclaimPolicy: Delete    # default
reclaimPolicy: Retain    # for databases, anything that should survive PVC delete
```

### 3.4 The `volumeBindingMode` field

When the PV is created and bound:

* `Immediate` (default) — as soon as the PVC is created.
* `WaitForFirstConsumer` — when a Pod using the PVC is scheduled.

See section 4 for the full discussion. **For cloud storage, use `WaitForFirstConsumer`.**

### 3.5 The `allowVolumeExpansion` field

If `true`, PVCs using this class can be expanded. Most modern CSI drivers support expansion.

```yaml
allowVolumeExpansion: true
```

This only sets the cluster's intent. The CSI driver must also support expansion for it to actually work. If the driver doesn't support it, expansion requests fail.

### 3.6 The `mountOptions` field

Mount options passed to the kubelet when the volume is mounted. **Driver-specific** — a bad mount option can cause mount failures.

Common safe options:

* `noatime` — don't update access times. Speeds up reads.
* `nodiratime` — same, for directories.
* `ro` — read-only.
* `debug` — extra logging.

Dangerous options:

* `noexec` — some apps need to execute binaries from the mount.
* `nosuid`, `nodev` — can break some apps.
* `sync` vs `async` — affects consistency.

Always test mountOptions in a non-prod environment first. **A bad mountOption can prevent the Pod from starting.**

### 3.7 The `allowedTopologies` field

Restrict the topology the volume can be provisioned in. Used for multi-zone clusters to ensure the volume is in the same zone as the Pod.

```yaml
allowedTopologies:
- matchLabelExpressions:
  - key: topology.kubernetes.io/zone
    values: ["us-east-1a", "us-east-1b"]
- matchLabelExpressions:
  - key: topology.kubernetes.io/region
    values: ["us-east-1"]
```

The provisioner creates the volume in a topology that matches one of the entries. If no entry matches, the volume can't be created.

**Most clusters don't need this** — `WaitForFirstConsumer` handles zone-affinity for cloud storage. Use `allowedTopologies` when you need to restrict the zone (e.g. only certain zones have the right type of storage available).

## 4. Volume Binding Modes — Immediate vs WaitForFirstConsumer

### 4.1 `Immediate` (default)

The PV is created as soon as the PVC is. The PV's location is decided without knowing where the Pod will run.

**Problem:** for cloud storage that's zone-specific (EBS, GCE PD), the PV may be in a different zone than the Pod. The Pod then fails to mount the volume.

```
Pod scheduled in us-east-1a
        │
        ▼
PVC created, bound to PV in us-east-1b
        │
        ▼
Pod tries to mount the volume
        │
        ▼
"MountVolume.SetUp failed: volume is in zone us-east-1b, node is in us-east-1a"
```

### 4.2 `WaitForFirstConsumer` (recommended for cloud)

The PV is **not created until a Pod that uses the PVC is scheduled**. The provisioner creates the volume in the same zone / topology as the Pod.

```
Pod scheduled in us-east-1a
        │
        ▼
PVC created, status: Pending
        │
        ▼
kube-scheduler picks a node for the Pod (e.g. us-east-1a)
        │
        ▼
External-provisioner sees the PVC is in use, creates the PV in us-east-1a
        │
        ▼
PVC binds, Pod mounts successfully
```

**The cost:** the Pod can't start until the PV is provisioned. This adds 5-30 seconds to Pod startup.

**This is the right default for any cloud storage that's zone-specific.** Set it on every StorageClass for cloud disks.

### 4.3 When to use `Immediate`

* **Storage that's not zone-specific** — NFS, hostPath, some CephFS setups.
* **When you control the placement** — single-zone clusters.
* **When the bind needs to happen before the Pod is scheduled** — unusual, but some controllers may want this.

## 5. Reclaim Policy on the StorageClass

```yaml
reclaimPolicy: Delete
```

This sets the **default** reclaim policy for PVs created via this StorageClass. The PV's actual `persistentVolumeReclaimPolicy` is set when it's provisioned.

You can change the reclaim policy on an individual PV after creation:

```bash
kubectl patch pv <name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

But it's easier to set it correctly on the StorageClass.

**Best practice:**

* `Delete` for ephemeral workloads (caches, build scratch).
* `Retain` for databases, anything with persistent data.
* Have **two StorageClasses** with different reclaim policies for different tiers.

## 6. The Default StorageClass

If a PVC doesn't specify `storageClassName`, it gets the **default** StorageClass. Most managed clusters (EKS, GKE, AKS) have one.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
```

You can mark a class as default with the annotation. **Only one class can be default at a time.** Setting two with the annotation makes the admission reject both.

### 6.1 The default dangers

* **The default can change between clusters.** A PVC that worked in dev may get a different volume in prod.
* **The default class may not be available in every namespace.** Some setups restrict the default class to certain namespaces (e.g. via a default policy).
* **The default class is not enforced to be production-grade.** Some teams' "default" is a low-tier class that shouldn't be used for prod databases.

**Best practice:** always set `storageClassName` explicitly in production. To explicitly opt out of the default (for static provisioning), set `storageClassName: ""`.

```yaml
spec:
  storageClassName: ""     # empty string = opt out of dynamic
```

### 6.2 Changing the default

```bash
# remove the annotation from the old default
kubectl annotate storageclass gp2 storageclass.kubernetes.io/is-default-class-

# add the annotation to the new default
kubectl annotate storageclass gp3 storageclass.kubernetes.io/is-default-class=true
```

**Do this carefully** — existing PVCs that used the old default are unaffected (they're bound to specific PVs), but any new PVCs without a `storageClassName` will use the new default.

## 7. Common Provisioners

| Provisioner | Backend | Notes |
|---|---|---|
| `ebs.csi.aws.com` | AWS EBS | gp2, gp3, io1, io2, st1, sc1. **Default on EKS.** |
| `efs.csi.aws.com` | AWS EFS | RWX support. Slower than EBS but cross-node. |
| `fsx.csi.aws.com` | AWS FSx | Lustre, ONTAP, OpenZFS. HPC use cases. |
| `disk.csi.azure.com` | Azure Disk | Premium_LRS, StandardSSD_LRS, etc. **Default on AKS.** |
| `file.csi.azure.com` | Azure Files | SMB / NFS. RWX. |
| `blob.csi.azure.com` | Azure Blob | Object storage as filesystem. |
| `pd.csi.storage.gke.io` | GCP Persistent Disk | pd-standard, pd-balanced, pd-ssd. **Default on GKE.** |
| `filestore.csi.storage.gke.io` | GCP Filestore | NFS. RWX. |
| `nfs.csi.k8s.io` | NFS | External NFS server. RWX. |
| `rook-ceph.rbd.csi.ceph.com` | Ceph RBD | Block storage. |
| `rook-ceph.cephfs.csi.ceph.com` | CephFS | Filesystem. RWX. |
| `csi.trident.netapp.io` | NetApp | OnTap, SolidFire, etc. |
| `csi-pure-csi.k8s.io` | Pure Storage | FlashArray, FlashBlade. |
| `kubernetes.io/no-provisioner` | Local PV | User creates the PV manually. |

### 7.1 In-tree provisioners — removed in 1.26+

In older k8s, you could use in-tree provisioners like `kubernetes.io/aws-ebs`. These are **removed in k8s 1.26+** — you must use the CSI provisioner.

If you have old manifests with in-tree provisioners, they fail to create. Migrate to CSI.

## 8. Provisioner-Specific Parameters

### 8.1 AWS EBS CSI

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-encrypted
provisioner: ebs.csi.aws.com
parameters:
  type: gp3               # gp2, gp3, io1, io2, st1, sc1
  fsType: ext4             # ext4, xfs, ext3
  iopsPerGB: "3000"        # gp3: 3000-16000, io1/io2: per-IOP
  throughput: "125"        # gp3: 125-1000 MiB/s
  encrypted: "true"        # encrypt with the default KMS key
  # kmsKeyId: "arn:aws:kms:..."  # use a specific KMS key
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
```

For `io1` / `io2` (high-performance), specify IOPS explicitly:

```yaml
parameters:
  type: io2
  iops: "10000"            # total IOPS, not per-GB
```

### 8.2 Azure Disk CSI

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-premium
provisioner: disk.csi.azure.com
parameters:
  skuName: Premium_LRS     # Standard_LRS, StandardSSD_LRS, Premium_LRS, UltraSSD_LRS
  # kind: Shared     # for maxShares > 1
  # diskEncryptionSetID: /subscriptions/.../diskEncryptionSets/...
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
```

### 8.3 GCE PD CSI

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gce-pd-balanced
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-balanced        # pd-standard, pd-balanced, pd-ssd, pd-extreme
  replication-type: none   # or regional-pd for HA
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
```

For `pd-extreme`, specify IOPS:

```yaml
parameters:
  type: pd-extreme
  provision-iops-on-create: "10000"
```

## 9. allowedTopologies and Multi-Zone Clusters

For multi-zone clusters where storage is zone-specific, you may need to restrict which zones the StorageClass can use.

```yaml
allowedTopologies:
- matchLabelExpressions:
  - key: topology.kubernetes.io/zone
    values: ["us-east-1a", "us-east-1b", "us-east-1c"]
```

The provisioner will only create volumes in zones that match one of the entries. If the Pod is scheduled to a zone that's not in the list, the volume can't be created (and the Pod stays in `Pending`).

**In practice, `WaitForFirstConsumer` handles this automatically** — the volume is created in the same zone as the Pod. `allowedTopologies` is for when you need to restrict the zones (e.g. some zones don't have the right storage tier, or licensing restrictions).

## 10. Mount Options

```yaml
mountOptions:
- noatime
- nodiratime
- debug
```

These are passed to the kubelet, which passes them to `mount` when mounting the volume. **Driver-specific** — some options may not be supported.

**Common gotchas:**

* `noexec` — the volume can't be used to run binaries. Some apps need this.
* `nosuid` — setuid binaries don't work. May break some apps.
* `ro` — read-only. The Pod can't write to the volume. Set this on the Pod's `volumeMounts.readOnly: true` instead, so the StorageClass is reusable.
* `sync` — synchronous I/O. Slower but more consistent. Don't set this on SSDs.

**Test before applying** — a bad mountOption can prevent the Pod from starting, and the error message may not be obvious.

## 11. Volume Expansion

```yaml
allowVolumeExpansion: true
```

This sets the cluster's intent. The CSI driver must also support expansion.

Expansion flow (covered in `05-persistentvolumeclaim.md`):

1. User edits PVC, increases `resources.requests.storage`.
2. The PVC's status enters `Resizing`.
3. The external-resizer (a sidecar in the CSI driver Deployment) calls the driver's `ControllerExpandVolume`.
4. The driver resizes the underlying volume.
5. The kubelet on the node is told to resize the filesystem.
6. The PVC's `status.capacity` reflects the new size.

**Most modern CSI drivers support online expansion** — the Pod doesn't need to be restarted. Some older drivers only support offline expansion (Pod must be stopped).

**Not all storage backends support shrinking.** Expansion is one-way.

## 12. Snapshots and Clones

Snapshots and clones are **not** properties of the StorageClass — they're separate APIs.

### 12.1 VolumeSnapshotClass

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-aws-vsc
driver: ebs.csi.aws.com
deletionPolicy: Delete
parameters:
  tagSpecification_1: "tag1=value1,tag2=value2"
```

A `VolumeSnapshotClass` is the snapshot equivalent of a StorageClass. It tells the CSI driver how to create snapshots.

### 12.2 Creating a snapshot

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: my-snap
spec:
  volumeSnapshotClassName: csi-aws-vsc
  source:
    persistentVolumeClaimName: data
```

The CSI driver creates a snapshot of the underlying volume. The snapshot is then available for restore or clone.

### 12.3 Restoring from a snapshot

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-restored
spec:
  storageClassName: gp3
  dataSource:
    apiGroup: snapshot.storage.k8s.io
    kind: VolumeSnapshot
    name: my-snap
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 50Gi
```

Creates a new PVC that's a copy of the snapshot at the time the snapshot was taken.

## 13. Multiple StorageClasses — Performance Tiers

A common pattern: multiple StorageClasses for different tiers.

```yaml
# Cheap, for caches
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cheap
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iopsPerGB: "3000"
  throughput: "125"
reclaimPolicy: Delete
---
# Balanced, for general workloads
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iopsPerGB: "3000"
  throughput: "500"
reclaimPolicy: Delete
---
# High-perf, for databases
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: high-perf
provisioner: ebs.csi.aws.com
parameters:
  type: io2
  iops: "10000"
reclaimPolicy: Retain        # DB volumes should survive PVC delete
---
# Cold, for archives
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cold
provisioner: ebs.csi.aws.com
parameters:
  type: sc1                  # cold HDD
reclaimPolicy: Delete
```

Users pick the tier by setting `storageClassName` on the PVC. The cluster creates the right volume.

**The cost calculus:** io2 is ~10x more expensive than gp3. sc1 is ~10x cheaper than gp3 but with much higher latency. Match the tier to the workload.

## 14. Operations and Debugging

### 14.1 Common commands

```bash
# list StorageClasses
kubectl get storageclass
# shows NAME, PROVISIONER, RECLAIMPOLICY, VOLUMEBINDINGMODE, ALLOWVOLUMEEXPANSION, AGE

# describe
kubectl describe storageclass <name>
# shows parameters, mount options, allowed topologies

# the default
kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'

# check the provisioner
kubectl -n kube-system get pods -l <csi-driver-label>
kubectl -n kube-system logs -l <csi-driver-label> --tail=100
```

### 14.2 The "PVC Pending" checklist

The most common PVC issue is Pending, usually due to StorageClass problems:

```bash
# 1. Is the StorageClass installed?
kubectl get storageclass
# if not, the PVC's storageClassName points to nothing

# 2. Is the provisioner running?
kubectl -n kube-system get pods -l <csi-driver-label>
# the external-provisioner sidecar

# 3. Is the provisioner authenticated?
kubectl -n kube-system logs -l <csi-driver-label> --tail=100
# look for "failed to create volume", "AccessDenied", etc.

# 4. Are the parameters valid?
# check the driver's docs. A typo in parameters may be silently ignored or cause errors.

# 5. Is the zone compatible?
kubectl describe storageclass <name>
# look for allowedTopologies

# 6. Is the WaitForFirstConsumer waiting for a Pod?
# the PVC is Pending until a Pod is created and scheduled
```

### 14.3 The "wrong volume created" cases

If the volume was created but with the wrong parameters (e.g. wrong type, wrong size):

* The provisioner is honoring the StorageClass, but the parameters were wrong when the PV was created. You can't change a bound PV's parameters — create a new PVC.
* The PVC's `storageClassName` is right, but the StorageClass's parameters are wrong. Edit the StorageClass — but new PVs will use the new parameters, existing PVs are unchanged.

## 15. Gotchas and Common Mistakes

### 15.1 The 25+ common mistakes

1. **A StorageClass is not a "type" of disk — it's a recipe for creating one.** `gp3` and `io2` are different StorageClasses backed by different EBS volume types, but both are EBS volumes.

2. **Default StorageClass is dangerous to assume.** A PVC in a namespace that doesn't have access to the default class will stay Pending. Always set `storageClassName` explicitly in production.

3. **StorageClasses are cluster-scoped, not namespaced.** A StorageClass is available to all namespaces.

4. **`WaitForFirstConsumer` matters.** If you have a multi-AZ cluster and the StorageClass doesn't use it, a PVC bound in `us-east-1a` might get scheduled to a Pod in `us-east-1b` and fail to mount.

5. **Volume expansion is CSI-driver specific.** Even if `allowVolumeExpansion: true`, the driver must support it. Older drivers don't.

6. **Deleting a StorageClass does not delete the PVs that were provisioned by it.** Existing PVs keep working; new PVCs that reference the class will fail.

7. **`reclaimPolicy: Delete` is the safe default for ephemeral workloads, dangerous for databases.** A `Retain` policy on a database StorageClass means the EBS volume survives the PVC — important for `kubectl delete pvc` accidents.

8. **You can have many StorageClasses in one cluster** — different performance tiers, different regions, different backends. A common setup: `gp3-default`, `gp3-replicated`, `io2-high-perf`, `cold-archive`.

9. **`mountOptions` are passed to `mount` as-is.** A typo can cause the mount to fail. Test in a non-prod environment.

10. **`mountOptions` is shared across all volumes in the class.** You can't set different options for different PVCs in the same class. Either use a separate class or set `readOnly` on the volumeMount.

11. **In-tree provisioners are removed in 1.26+.** `kubernetes.io/aws-ebs` doesn't work. Use `ebs.csi.aws.com`.

12. **The provisioner name is case-sensitive.** `ebs.csi.aws.com` and `EBS.CSI.AWS.COM` are different.

13. **The provisioner registers itself, but k8s doesn't verify it exists.** A StorageClass can reference a non-existent provisioner. PVCs will sit Pending until the provisioner is installed.

14. **`allowedTopologies` is a hard constraint.** If the Pod is scheduled to a zone not in the list, the volume can't be created.

15. **The `reclaimPolicy` on the StorageClass is the default for new PVs.** Existing PVs are unchanged.

16. **A StorageClass can have a `reclaimPolicy: Delete` but the PV can be patched to `Retain`.** The StorageClass sets the default, but the PV is authoritative once created.

17. **EBS CSI's `type` parameter is required.** Forgetting it causes the provisioner to fail. Other drivers have similar requirements.

18. **The default class annotation is `storageclass.kubernetes.io/is-default-class: "true"`.** Not `isDefaultClass`, not `default-class`. The exact spelling matters.

19. **At most one StorageClass can be the default.** Setting two with the annotation makes admission reject both. **The error is sometimes confusing** — it says "default class already set" but doesn't tell you which one.

20. **The `parameters` field is opaque to k8s.** A typo isn't caught at admission. The provisioner either ignores the bad parameter or fails to create the volume.

21. **`volumeBindingMode: WaitForFirstConsumer` requires the Pod to be created before the PV is provisioned.** This adds latency to Pod startup. For workloads that need fast startup, this can be a problem.

22. **For multi-zone clusters, you may need separate StorageClasses per zone.** If `allowedTopologies` is set, a PVC in zone A can't be bound to a PV in zone B. The user has to pick the right class.

23. **The `fsType` parameter is for the filesystem, not the volume type.** A `fsType: ext4` StorageClass formats new volumes with ext4. The `type: gp3` (or similar) is the volume type.

24. **A StorageClass with `allowVolumeExpansion: true` doesn't mean all volumes can be expanded.** The driver must support expansion. Some drivers only support expansion for certain volume types.

25. **`mountOptions` is the kubelet's mount options, not the cloud volume's.** They apply when the volume is mounted on the node, not when the volume is created in the cloud.

26. **Some CSI drivers have parameters that conflict.** For example, EBS CSI's `iopsPerGB` and `iops` are mutually exclusive. The driver rejects conflicting parameters.

27. **The StorageClass's `parameters` are strings.** `iopsPerGB: "3000"` is a string, not a number. The driver parses it. Don't use `iopsPerGB: 3000` (no quotes).

28. **A StorageClass can be deleted while PVCs use it.** The PVCs keep working (they're bound to specific PVs). New PVCs that reference the deleted class will fail.

29. **The default StorageClass can be set by RBAC.** Some setups use RBAC to restrict who can mark a class as default. This prevents accidental default-class changes.

30. **`reclaimPolicy` on a `Retain` StorageClass with no admin is a footgun.** The PVs are kept, but no one cleans them up. Over time, orphaned volumes accumulate.

## See also

* [[Kubernetes/concepts/L05-config-storage/03-volumes|Volume Types]] — the volume types, including PVCs
* [[Kubernetes/concepts/L05-config-storage/04-persistentvolume|PersistentVolume]] — the cluster-scoped storage object
* [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim|PersistentVolumeClaim]] — the user-facing API
* [[Kubernetes/concepts/L05-config-storage/07-storage|Storage]] — the L05 mental model
* [[Kubernetes/concepts/L05-config-storage/08-resource-quota|ResourceQuota]] — namespace-level storage quotas

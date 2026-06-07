# Storage (L05 Overview)

*"https://kubernetes.io/docs/concepts/storage/"*

A high-level overview of the **storage model** in Kubernetes — the 30-page version of how PVs, PVCs, StorageClasses, and volumes fit together. Use this as a quick reference; the deeper notes are linked below.

## The four object types

There are four kinds of objects in the storage model:

1. **Volume** — not an object, but a field in a Pod spec. A "thing mounted into a container."
2. **PersistentVolume (PV)** — a piece of storage in the cluster. Cluster-scoped.
3. **PersistentVolumeClaim (PVC)** — a request for storage. Namespaced.
4. **StorageClass** — a "type" of storage with a provisioner. Cluster-scoped.

The flow:

```
        ┌────────────────┐
        │ StorageClass   │  gp3, gp2, io2, efs-standard, ...
        │ (cluster)      │  defines provisioner + parameters
        └────────┬───────┘
                 │ provisioner creates
                 ▼
        ┌────────────────┐
        │  PV            │  one piece of storage
        │  (cluster)     │  cluster-scoped, exists independently
        └────────▲───────┘
                 │ bound to
                 │
        ┌────────┴───────┐
        │  PVC           │  "I need 50 GiB of ReadWriteOnce"
        │  (namespaced)  │  namespaced, lives in user's ns
        └────────▲───────┘
                 │ consumed by
                 │
        ┌────────┴───────┐
        │  Pod           │  mounts the PVC as a volume
        └────────────────┘
```

A Pod **never** references a PV directly. Always through a PVC.

## The two provisioning modes

### Static

The admin creates PVs by hand. The user creates a PVC that matches. Used for:

* Special-purpose storage (high-perf NVMe, encrypted volumes)
* Pre-provisioned hardware
* Legacy setups

```yaml
# admin creates
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-nfs-01
spec:
  capacity: { storage: 1Ti }
  accessModes: [ReadWriteMany]
  nfs: { server: nfs.example.com, path: /exports/data }
---
# user creates
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: [ReadWriteMany]
  resources: { requests: { storage: 1Ti } }
# the system binds the PVC to pv-nfs-01
```

### Dynamic

The user creates a PVC. The StorageClass's provisioner creates the PV (and the underlying storage asset) on demand. **This is how 99% of clusters work today.**

```yaml
apiVersion: v1
kind: StorageClass
metadata: { name: gp3 }
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  storageClassName: gp3
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 50Gi } }
# the StorageClass's provisioner creates a 50GiB EBS volume + a PV
# the PVC is bound to the PV
```

## Access modes

| Mode | Abbreviation | Meaning | What supports it |
|---|---|---|---|
| ReadWriteOnce | RWO | Mounted read-write by a single node | Almost everything (EBS, hostPath, ...) |
| ReadOnlyMany | ROX | Mounted read-only by many nodes | NFS, EFS, some CSI |
| ReadWriteMany | RWX | Mounted read-write by many nodes | NFS, EFS, CephFS, some CSI |
| ReadWriteOncePod | RWOP | Mounted read-write by a single Pod | CSI drivers that support it (k8s 1.22+) |

The mode you can use is **constrained by the backend** — EBS only supports RWO, not RWX. If you need RWX, use EFS, NFS, or a CSI that supports it.

## Reclaim policies

What happens to the PV when the PVC is deleted:

* **`Retain`** — PV stays; admin cleans up manually. Default for static PVs. Use for databases and anything important.
* **`Delete`** — PV and the underlying storage asset are deleted. Default for dynamic PVs.
* **`Recycle`** — deprecated, do not use.

## Volume binding modes

* **`Immediate`** — PV is created as soon as the PVC is. The volume's location is chosen without knowing where the Pod will run. **Bad for zonal storage** — the Pod might end up in a different zone.
* **`WaitForFirstConsumer`** — PV is created only when a Pod using the PVC is scheduled. The provisioner creates the volume in the same zone / topology as the Pod. **The right default for cloud storage.**

## The volume types

In a Pod spec, `volumes` can be:

* `emptyDir` — a directory that lives for the Pod's lifetime. Shared by all containers. Used for scratch, caches, sidecar log mounts.
* `hostPath` — a path on the host node's filesystem. Used by DaemonSets, single-node clusters. **Not portable.**
* `nfs` — an NFS share. Requires an NFS server.
* `gitRepo` — **deprecated** in k8s 1.22. Use an init container or sidecar.
* `configMap` / `secret` — mount a ConfigMap or Secret as a volume. For config injection.
* `persistentVolumeClaim` — the standard way to use storage.
* `ephemeral` — inline PVC, lives and dies with the Pod. k8s 1.19+.
* `downwardAPI` — expose Pod metadata as files in a volume.
* `projected` — combine multiple sources into one volume.
* `csi` — direct CSI driver reference. Rare; usually wrapped in a PVC.

## The lifecycle of a volume claim

```
1. User creates PVC
   ↓
2. StorageClass provisioner sees it (WaitForFirstConsumer: wait for Pod)
   ↓
3. Pod is created with the PVC
   ↓
4. Pod is scheduled to a node
   ↓
5. Provisioner creates the storage asset in the right topology
   ↓
6. Provisioner creates a PV
   ↓
7. PVC binds to the PV
   ↓
8. kubelet on the node mounts the volume into the Pod
   ↓
9. Container starts with the volume at the mount path
   ↓
... time passes ...
   ↓
10. User deletes the PVC
   ↓
11. Reclaim policy runs:
    - Delete: storage asset deleted
    - Retain: PV stays, admin cleans up
```

## What's in the deeper notes

* **[[Kubernetes/concepts/L05-config-storage/01-config-maps|ConfigMaps]]** — non-sensitive config, the model for all config injection
* **[[Kubernetes/concepts/L05-config-storage/02-secrets|Secrets]]** — sensitive config, the same model with extra protections
* **[[Kubernetes/concepts/L05-config-storage/03-volumes|Volume Types]]** — every type of volume in a Pod spec
* **[[Kubernetes/concepts/L05-config-storage/04-persistentvolume|PersistentVolume]]** — the cluster-scoped storage object, in depth
* **[[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim|PersistentVolumeClaim]]** — the namespaced storage request, in depth
* **[[Kubernetes/concepts/L05-config-storage/06-storageclass|StorageClass]]** — the dynamic provisioning model, in depth
* **[[Kubernetes/concepts/L05-config-storage/07-storage|Storage]]** — this note
* **[[Kubernetes/concepts/L05-config-storage/08-resource-quota|Resource Quota]]** — how to put limits on what namespaces can do

## The four most important things to remember

1. **Always use a StorageClass.** Don't rely on the default. The default is implementation-defined; setting it explicitly makes your manifests portable.
2. **Use `WaitForFirstConsumer` for cloud storage.** Avoids cross-zone Pod-to-volume mismatches.
3. **Reclaim policy matters.** `Delete` for ephemeral, `Retain` for anything important.
4. **Pods never see PVs directly.** They see PVCs. If you find yourself writing `volumes: [persistentVolume: ...]` in a Pod spec, you've done something wrong.

## Cross-cutting gotchas

* **Storage is a separate failure mode from compute.** A node can run 100 Pods but only have 10 EBS volumes attached (EBS's per-instance limit). Storage and compute aren't fungible.
* **A StorageClass is not the same as a volume type.** `gp3` is a StorageClass, but the underlying volume is still an EBS `gp3` volume. The StorageClass is the recipe; the volume is the result.
* **Mount propagation matters for some apps.** Tools that need to mount volumes from inside a container (NFS, CSI) need `mountPropagation: HostToContainer` or `Bidirectional`. Default is `None`, which can break them.
* **PVs are not namespaced, but the storage backend often is.** AWS EBS volumes live in a specific region. A PV's storage class might say `us-east-1`, but the cluster could span regions. Watch for this with multi-region clusters.
* **The PV's `capacity` is recorded, not enforced.** A 10Gi PV on a 100Gi volume just records "10Gi was requested". The actual volume is the volume.
* **A PVC can only be bound to one PV. A PV can only be bound to one PVC.** This is one-to-one. (Some drivers fake multi-binding with `ReadOnlyMany` + multiple PVCs, but the underlying volume is still one asset.)
* **CSI drivers are updated separately from k8s.** A k8s upgrade doesn't automatically upgrade EBS CSI. Manage them as their own thing.
* **The 1.5 MB object size limit on etcd applies to PVs.** A PV's spec is JSON, capped at 1.5 MB. Don't put huge parameters in a StorageClass.

## See also

* [[Kubernetes/concepts/L05-config-storage/04-persistentvolume|PersistentVolume]] — the cluster-scoped object
* [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim|PersistentVolumeClaim]] — the request
* [[Kubernetes/concepts/L05-config-storage/06-storageclass|StorageClass]] — dynamic provisioning
* [[Kubernetes/concepts/eks/storage/README|EKS Storage]] — AWS-specific details for EKS

# PersistentVolume (PV)

*"https://kubernetes.io/docs/concepts/storage/persistent-volumes/"*

A PersistentVolume (PV) is a **piece of storage in the cluster** that has been provisioned by an administrator or dynamically by a StorageClass. It's a cluster-level resource (not namespaced) — like a node, it represents physical or virtual infrastructure.

## The two-step model: PV and PVC

The k8s storage model has **two** objects for a reason: to separate "how storage is provided" (PV) from "how it's consumed" (PVC).

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

## Lifecycle

```
Available → Bound → Released → (recycled / deleted / retained)
```

* **Available** — free, not yet claimed
* **Bound** — claimed by a PVC
* **Released** — PVC deleted, PV not yet reused
* **Available** again — depending on the `persistentVolumeReclaimPolicy`

## Reclaim policy

What happens to the PV when the PVC is deleted:

* **Retain** (default for manually-created PVs) — keep the data, leave the PV in `Released` state. Admin has to manually clean up.
* **Delete** (default for dynamically-provisioned PVs) — delete the underlying storage asset (e.g. the EBS volume) AND the PV object.
* **Recycle** — deprecated, do not use. (Runs `rm -rf` on the volume.)

## Access modes

| Mode | Abbreviation | Description |
|---|---|---|
| `ReadWriteOnce` | RWO | Mounted read-write by a single node |
| `ReadOnlyMany` | ROX | Mounted read-only by many nodes |
| `ReadWriteMany` | RWX | Mounted read-write by many nodes |
| `ReadWriteOncePod` | RWOP | Mounted read-write by a single Pod (k8s 1.22+) |

Not all backends support all modes. EBS only supports RWO. EFS, NFS, CephFS support RWX. The mode you need constrains the backend.

## Static vs dynamic provisioning

### Static

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
  storageClassName: manual
  hostPath:                  # for dev only
    path: /data/pv-1
```

You create the PV yourself, then create a PVC that matches its `storageClassName`, `accessModes`, and capacity.

### Dynamic

You don't create the PV at all. You create a PVC that references a StorageClass, and k8s (via the storage provisioner) creates the PV for you. **This is the only sane way to run in production.**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-claim
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 100Gi
```

→ k8s calls the `gp3` provisioner → provisioner creates the EBS volume + PV → PVC binds to PV → Pod mounts the claim.

## Gotchas

* **PVs are cluster-scoped (not namespaced).** PVCs are namespaced. The Pod sees only the PVC.
* **A PVC can only be bound to one PV.** A PV can only be bound to one PVC. (One-to-one.)
* **Bound PVs cannot be deleted** while a PVC references them. You have to delete the PVC first.
* **`persistentVolumeReclaimPolicy: Retain`** means data survives the PVC — useful for databases, but you must clean up manually.
* **PV capacity is not enforced at the storage level** (in many backends). A 10Gi PV on a 100Gi volume just records "10Gi requested" — the volume is the volume.
* **`ReadWriteOnce` means "one node", not "one Pod".** Multiple Pods on the same node can mount the same RWO volume.
* **ReadWriteMany is the hardest mode to support** — only certain backends do it (NFS, EFS, CephFS, some CSI drivers).
* **A Pod cannot mount a PV directly** — it always goes through a PVC.
* **Static PVs with `hostPath` are not for production.** They survive only as long as the node does.

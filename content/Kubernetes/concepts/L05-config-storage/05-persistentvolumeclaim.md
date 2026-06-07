# PersistentVolumeClaim (PVC)

*"https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims"*

A PersistentVolumeClaim is a **request for storage** by a user / Pod. It's the namespaced object that the cluster binds to a PersistentVolume. Pods use PVCs the way they use ConfigMaps or Secrets — declared in the spec, mounted as a volume.

## Basic example

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
      storage: 50Gi
```

The claim says: "I need 50 GiB of `ReadWriteOnce` storage from the `gp3` class." k8s binds it to a matching PV (existing or newly provisioned).

## How a Pod uses a PVC

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
    - name: data
      mountPath: /var/lib/data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data
```

The Pod references the PVC by name, the volume is mounted at `/var/lib/data`. The contents of the PV appear at that path.

## What a PVC actually specifies

| Field | Meaning |
|---|---|
| `accessModes` | RWO / ROX / RWX / RWOP — see [[Kubernetes/concepts/L05-config-storage/04-persistentvolume\|persistentvolume]] |
| `storageClassName` | Which class to use (drives dynamic provisioning) |
| `resources.requests.storage` | Minimum capacity required |
| `volumeMode` (optional) | `Filesystem` (default) or `Block` (raw block device) |
| `selector` (optional) | Match only PVs with these labels |
| `dataSource` (k8s 1.20+) | Clone an existing PVC or snapshot a volume |

## Binding behavior

By default, a PVC binds **immediately** if a matching PV exists. If no PV exists and dynamic provisioning is configured, a PV is created.

If neither is true, the PVC stays `Pending` until something changes.

`spec.waitForFirstConsumer` on a StorageClass delays binding until a Pod actually uses the claim — useful when the choice of storage backend depends on the Pod's scheduling constraints (e.g. zone-affine storage).

## Capacity expansion

A PVC's storage can be expanded (k8s 1.11+) if the underlying backend supports it:

```bash
kubectl edit pvc data
# change spec.resources.requests.storage to 100Gi
```

```yaml
spec:
  resources:
    requests:
      storage: 100Gi    # was 50Gi
```

The PV's `capacity` is updated, and the underlying volume is resized by the CSI driver. **Not all backends support online expansion** — check the CSI driver's docs.

## Snapshot / restore (k8s 1.20+)

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: data-snap
spec:
  volumeSnapshotClassName: csi-aws-vsc
  source:
    persistentVolumeClaimName: data
```

Creates a snapshot. To restore, create a new PVC that points at the snapshot via `dataSource`.

## Gotchas

* **PVCs are namespaced.** A PVC in `ns-a` cannot be used by a Pod in `ns-b`.
* **Bound PVs are immutable in `accessModes`, `storageClassName`, and `volumeMode`.** To change them, you'd need a new PVC.
* **A PVC stuck in `Pending` is the most common storage issue.** Run `kubectl describe pvc` and read the events. Usually: no matching PV, no dynamic provisioner, wrong zone, or no quota.
* **Deleting a PVC destroys the data** if the PV's `persistentVolumeReclaimPolicy` is `Delete`. Be careful.
* **A StatefulSet creates a PVC per replica** automatically. The PVC template is in the StatefulSet spec.
* **`subPath` on a PVC-backed volume mount** means the volume is mounted at a subpath, but all subPaths share the same volume. Don't expect isolation.
* **Block mode PVCs cannot be mounted as filesystem.** They're for raw block access (databases that want to manage the filesystem themselves).

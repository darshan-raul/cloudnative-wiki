# StorageClass

*"https://kubernetes.io/docs/concepts/storage/storage-classes/"*

A StorageClass is a **way to describe "types" of storage** you can dynamically provision. It maps a name (like `gp3` or `ssd`) to a provisioner and a set of parameters.

## Why they exist

Before StorageClasses, an admin had to hand-create PVs for every workload. With StorageClasses, a user just requests "give me 100Gi of `gp3`" and the cluster creates the volume on-demand.

## Basic example

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

## Key fields

| Field | Purpose |
|---|---|
| `provisioner` | The driver to call (CSI driver name, in-tree name, or local) |
| `parameters` | Provisioner-specific config (e.g. AWS `type: gp3`) |
| `reclaimPolicy` | `Delete` (default) or `Retain` — what happens to PV when PVC is gone |
| `volumeBindingMode` | `Immediate` (default) or `WaitForFirstConsumer` |
| `allowVolumeExpansion` | If true, PVCs can be expanded after creation |
| `mountOptions` | Mount options passed to kubelet |
| `allowedTopologies` | Restrict the topology the volume can be provisioned in (e.g. specific zones) |

## Volume binding modes

* **`Immediate`** — the PV is created as soon as the PVC is. The PV's location is decided without knowing where the Pod will run. **Can cause issues** if your storage is zone-specific and the Pod is scheduled to a different zone.
* **`WaitForFirstConsumer`** — the PV is not created until a Pod that uses the PVC is scheduled. The provisioner creates the volume in the same zone / topology as the Pod. **This is the safe default for cloud storage.**

## Default StorageClass

If a PVC doesn't specify `storageClassName`, it gets the **default** StorageClass. Most managed clusters have one (e.g. EKS sets `gp2` as default).

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
```

You can mark a class as default with the annotation. **Only one class can be default at a time.** Some teams explicitly set `storageClassName: ""` (empty string) on PVCs to opt out of the default.

## Common provisioners

| Provisioner | Backend |
|---|---|
| `ebs.csi.aws.com` | AWS EBS |
| `efs.csi.aws.com` | AWS EFS |
| `disk.csi.azure.com` | Azure Disk |
| `file.csi.azure.com` | Azure Files |
| `pd.csi.storage.gke.io` | GCP Persistent Disk |
| `nfs.csi.k8s.io` | NFS |
| `rook-ceph.rbd.csi.ceph.com` | Ceph RBD |
| `kubernetes.io/no-provisioner` | Local PV |

## Gotchas

* **A StorageClass is not a "type" of disk — it's a recipe for creating one.** `gp3` and `io2` are different StorageClasses backed by different EBS volume types, but both are EBS volumes.
* **Default StorageClass is dangerous to assume.** A PVC in a namespace that doesn't have access to the default class will stay Pending. Always set `storageClassName` explicitly in production.
* **StorageClasses are cluster-scoped, not namespaced.**
* **`WaitForFirstConsumer` matters.** If you have a multi-AZ cluster and the StorageClass doesn't use it, a PVC bound in `us-east-1a` might get scheduled to a Pod in `us-east-1b` and fail to mount.
* **Volume expansion is CSI-driver specific.** Even if `allowVolumeExpansion: true`, the driver must support it.
* **Deleting a StorageClass does not delete the PVs that were provisioned by it.** Existing PVs keep working; new PVCs that reference the class will fail.
* **`reclaimPolicy: Delete` is the safe default for ephemeral workloads, dangerous for databases.** A `Retain` policy on a database StorageClass means the EBS volume survives the PVC — important for `kubectl delete pvc` accidents.
* **You can have many StorageClasses in one cluster** — different performance tiers, different regions, different backends. A common setup: `gp3-default`, `gp3-replicated`, `io2-high-perf`, `cold-archive`.

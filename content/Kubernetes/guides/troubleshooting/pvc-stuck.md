---
title: PVC Stuck
tags:
  - Kubernetes
  - Troubleshooting
  - Storage
  - PVC
---

A `PersistentVolumeClaim` that's stuck in `Pending` is waiting for a volume to be provisioned or bound. The pod that uses it can't schedule. This is a **storage** problem.

## Symptoms

```bash
$ kubectl get pvc
NAME    STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
data    Pending                                      gp3            5m
```

```bash
$ kubectl get pods
NAME    READY   STATUS    RESTARTS   AGE
web-1   0/1     Pending   0          5m
```

The pod is Pending because the PVC is Pending. Cascade.

```bash
$ kubectl describe pvc data
Events:
  Type     Reason              Age   From                         Message
  ----     ------              ----  ----                         -------
  Warning  ProvisioningFailed  4m   external-provisioner         failed to provision volume: ... AccessDenied
```

## The 30-second diagnosis

```bash
# 1. PVC status and events
kubectl describe pvc data

# 2. storage class
kubectl get sc

# 3. is the provisioner running?
kubectl get pods -n kube-system | grep -E "csi|provisioner"

# 4. PVs available?
kubectl get pv

# 5. quota exceeded?
kubectl describe quota -n my-ns
```

## How PVC provisioning works

```
┌──────────────────────────────────────────────────────────────┐
│  Pod requests PVC                                            │
│       ↓                                                      │
│  PVC created (Status: Pending)                               │
│       ↓                                                      │
│  Provisioner watches for unbound PVCs                        │
│       ↓                                                      │
│  Provisioner calls the storage API to create a volume        │
│  (EBS, EFS, NFS, Ceph, etc.)                                 │
│       ↓                                                      │
│  Provisioner creates a PV and binds it to the PVC            │
│       ↓                                                      │
│  PVC Status: Bound                                           │
│       ↓                                                      │
│  Pod can now mount the volume                                │
└──────────────────────────────────────────────────────────────┘
```

PVC binding is **one-shot**. If the provisioner fails, the PVC stays Pending until you fix the cause. Re-applying the PVC doesn't help unless the underlying issue is resolved.

## The taxonomy of PVC issues

```
┌──────────────────────────────────────────────────────────────┐
│                      PVC Pending                              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. StorageClass doesn't exist                                │
│  2. Provisioner is broken          (CSI driver, IAM, etc.)   │
│  3. Provisioner can't satisfy      (zone, capacity, etc.)    │
│  4. VolumeBindingMode: WaitForFirstConsumer + scheduling jam  │
│  5. Access mode mismatch           (PVC asks RWX, SC has RWO)│
│  6. Insufficient quota             (resource quota, EBS PIops)│
│  7. Static PV doesn't exist        (static provisioning)     │
│  8. PV access mode wrong           (RWO, RWX, ROX)            │
│  9. Node affinity conflict         (zone constraints)         │
│ 10. Volume expansion hit limit     (only some CSI drivers)    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 1. StorageClass doesn't exist

The PVC references a StorageClass by name, but that SC isn't in the cluster.

**Signatures:**

```bash
$ kubectl describe pvc data
Events:
  Type     Reason              Age   From               Message
  ----     ------              ----  ----               -------
  Warning  ProvisioningFailed  1m   external-provisioner  storageclass.in.storage.k8s.io "gp3-encrypted" not found
```

```bash
$ kubectl get sc
NAME            PROVISIONER
gp2             kubernetes.io/aws-ebs
# no gp3-encrypted
```

**Fix:** create the StorageClass, or change the PVC to use an existing one.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-encrypted
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
```

## 2. Provisioner is broken

The CSI driver is unhealthy, has wrong IAM, can't reach the cloud API.

**Signatures:**

```bash
$ kubectl describe pvc data
Events:
  Warning  ProvisioningFailed  1m   external-provisioner
    failed to provision volume: ... AccessDenied: User ... is not authorized to perform: ec2:CreateVolume
```

```bash
$ kubectl get pods -n kube-system -l app=ebs-csi-controller
NAME                                  READY   STATUS    RESTARTS
ebs-csi-controller-7d8b8b7c9d-abcd    0/1     Error     3
```

**Diagnosis:**

```bash
# 1. CSI controller pod logs
kubectl logs -n kube-system ebs-csi-controller-7d8b8b7c9d-abcd --tail=50

# 2. CSI node pod (per-node)
kubectl logs -n kube-system ebs-csi-node-xxx --tail=50

# 3. CSIDriver and CSINode objects
kubectl get csidriver
kubectl get csinode

# 4. cloud IAM
aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole
# or whatever role the driver uses
```

**Common sub-causes:**

1. **IAM role missing permissions.** AWS EKS, IRSA setup incomplete.
   ```bash
   $ kubectl logs -n kube-system ebs-csi-controller-xxx
   failed to create volume: ... AccessDenied
   ```
   Fix: ensure the IRSA service account has `arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy` (or equivalent).

2. **CSI driver not installed.** Some distributions need explicit installation (e.g., kOps, kind, kubeadm).
   ```bash
   $ kubectl get csidriver
   # empty
   ```
   Fix: install the driver (Helm, manifests, etc.).

3. **CSI driver version incompatible with k8s.** Old CSI drivers don't work on new k8s.
   Fix: upgrade the CSI driver.

4. **Cloud API rate limit.** Especially during cluster boot or large deployments.
   ```bash
   $ kubectl logs -n kube-system ebs-csi-controller-xxx
   failed to create volume: ... RequestLimitExceeded
   ```
   Fix: back off, retry. Or use a different region.

5. **Network unreachable to the cloud API.** Node can't reach `ec2.amazonaws.com` or the metadata service.
   ```bash
   $ curl -sS https://ec2.amazonaws.com/
   # timeout
   ```

## 3. Provisioner can't satisfy

The provisioner is running, but can't create a volume that matches the request.

**Signatures:**

```bash
$ kubectl describe pvc data
Events:
  Warning  ProvisioningFailed  1m   external-provisioner
    failed to provision volume: InvalidParameter: The volume size 100Gi is smaller than the minimum size 1Ti
```

```bash
Events:
  Warning  ProvisioningFailed  1m   external-provisioner
    failed to provision volume: InsufficientInstanceCapacity: Not enough capacity in zone us-east-1a
```

```bash
Events:
  Warning  ProvisioningFailed  1m   external-provisioner
    failed to provision volume: Unsupported: EBS volume type io2 not supported in this region
```

**Common sub-causes:**

1. **Capacity too small or too large for the volume type.** Each cloud has min/max sizes per volume type.
   - EBS gp3: 1Gi - 64Ti
   - EBS io1/io2: 4Gi - 64Ti
   - EFS: 0 bytes (pay per use)
   - GCE PD: 10GB - 64TB

2. **AWS region out of capacity for the volume type.** Rare, but possible during spikes.

3. **Unsupported volume type in region.** Some volume types (e.g., io2 Block Express) aren't in all regions.

4. **Encryption requested, but KMS key not accessible.**
   ```bash
   failed to provision volume: InvalidParameter: ... KMS key not found or access denied
   ```

## 4. WaitForFirstConsumer scheduling jam

`volumeBindingMode: WaitForFirstConsumer` means the PVC won't provision until a pod using it is scheduled. If the pod can't be scheduled (resource pressure, affinity), the PVC stays Pending.

**Signatures:**

```bash
$ kubectl get pvc
NAME    STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
data    Pending                                      gp3            5m
```

```bash
$ kubectl describe pvc data
Events: <none>     <-- no provisioner events at all
```

The provisioner is silent because it hasn't been triggered. The pod that uses this PVC is also Pending.

**Diagnosis:**

```bash
# 1. is the pod pending?
kubectl get pod -l app=web

# 2. why is the pod pending?
kubectl describe pod -l app=web | tail
# likely: insufficient resources, affinity, taints

# 3. PVC has the right StorageClass?
kubectl get pvc data -o jsonpath='{.spec.storageClassName}'
```

**Fix:** fix the pod's scheduling issue. The PVC will provision once the pod is placed.

For more control, change to `Immediate` binding (the PVC provisions without waiting for a pod). Useful when:
- You want to pre-provision volumes
- You don't have node-specific storage requirements
- The pod can move between nodes without volume migration

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-immediate
provisioner: ebs.csi.aws.com
volumeBindingMode: Immediate
```

## 5. Access mode mismatch

The PVC asks for an access mode the SC doesn't support.

**Signatures:**

```bash
$ kubectl describe pvc data
Events:
  Warning  ProvisioningFailed  1m   external-provisioner
    failed to provision volume: ... AccessMode not supported
```

**Diagnosis:**

```bash
# 1. what does the PVC want?
kubectl get pvc data -o jsonpath='{.spec.accessModes}' | jq .
# ["ReadWriteMany"]

# 2. what does the SC support?
kubectl get sc gp3 -o yaml | grep -A 3 "volumeBindingMode\|parameters"
# gp3 only supports ReadWriteOnce (RWO)
```

**Common access modes:**

| Mode | Meaning | Backed by |
|------|---------|-----------|
| `ReadWriteOnce` (RWO) | One node can mount read-write | EBS, GCE PD, most block storage |
| `ReadOnlyMany` (ROX) | Multiple nodes can mount read-only | Same as above |
| `ReadWriteMany` (RWX) | Multiple nodes can mount read-write | EFS, NFS, CephFS, GlusterFS |
| `ReadWriteOncePod` (RWOP) | One pod can mount read-write | CSI 1.0+ drivers |

**Fix:** use an SC that supports the access mode you need. For RWX, common options:
- AWS: EFS (NFS-based)
- GCP: Filestore (NFS)
- Azure: Azure Files (SMB)
- On-prem: NFS, CephFS, Rook

## 6. Insufficient quota

Resource quotas in the namespace limit the total storage that can be requested.

**Signatures:**

```bash
$ kubectl describe pvc data
Events:
  Warning  ProvisioningFailed  1m   external-provisioner
    exceeded quota: pvc-count, requested: 1, used: 10, limited: 10
```

```bash
$ kubectl describe resourcequota -n my-ns
Name:            storage-quota
Resource         Used   Hard
--------         ----   ----
persistentvolumeclaims  10    10
requests.storage       1Ti   2Ti
```

**Fix:** increase the quota, or clean up unused PVCs.

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storage-quota
  namespace: my-ns
spec:
  hard:
    persistentvolumeclaims: "50"     # up from 10
    requests.storage: "10Ti"          # up from 2Ti
    # AWS-specific
    requests.ephemeral-storage: "1Ti"
```

For cloud-specific quotas (EBS volumes per node, IOPS limits), the issue might be at the cloud level, not k8s. AWS limits:
- Default: 28 EBS volumes per node (with the AWS VPC CNI)
- Max IOPS per volume: 64,000 for io2, 16,000 for gp3
- Max throughput: 1,000 MiB/s for gp3

## 7. Static PV doesn't exist

Static provisioning: you've pre-created PVs, and the PVC binds to a matching one. If no PV matches, the PVC stays Pending.

**Signatures:**

```bash
$ kubectl describe pvc data
Events: <none>
```

```bash
$ kubectl get pv
NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS
# (empty)
```

**Diagnosis:**

```bash
# 1. PVs available?
kubectl get pv

# 2. what does the PVC want?
kubectl get pvc data -o jsonpath='{.spec}' | jq .
# {
#   "accessModes": ["ReadWriteOnce"],
#   "resources": {"requests": {"storage": "100Gi"}},
#   "storageClassName": "manual"   # important for static
# }
```

**For static provisioning to work:**
- The PV and PVC must match on `storageClassName`
- The PV's capacity must be >= PVC's request
- The PV's access modes must include the PVC's requested access mode
- The PV's `claimRef` should not point to another PVC (or be unset)

**Fix:** create a matching PV:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-001
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual     # matches the PVC's storageClassName
  hostPath:
    path: /mnt/data            # or nfs, iscsi, etc.
```

## 8. PV access mode wrong

The PV is provisioned, but the access mode doesn't match what the PVC wants.

**Signatures:**

```bash
$ kubectl get pv,pvc
NAME                      CAPACITY   ACCESS MODES   STATUS   CLAIM
persistentvolume/pv-001   100Gi      RWO            Available

NAME                      STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
persistentvolumeclaim/data Pending                      gp3            5m
# PVC is Pending even though there's an Available PV
```

**Diagnosis:**

```bash
# 1. PVC's access mode
kubectl get pvc data -o jsonpath='{.spec.accessModes}' | jq .
# ["ReadWriteMany"]   <-- wants RWX

# 2. PV's access mode
kubectl get pv pv-001 -o jsonpath='{.spec.accessModes}' | jq .
# ["ReadWriteOnce"]   <-- RWO only, no match
```

**Fix:** create a PV with the right access mode, or change the PVC.

## 9. Node affinity conflict

The pod using the PVC is on a node that the volume can't be attached to (zone mismatch, regional storage).

**Signatures:**

```bash
$ kubectl describe pod -l app=web
Events:
  Warning  FailedScheduling  1m  default-scheduler
    0/3 nodes are available: 1 node(s) didn't match Pod's node affinity/selector,
    2 node(s) had volume node affinity conflict.
```

**Common sub-causes:**

1. **Pod is in zone us-east-1a, volume is in us-east-1b.** EBS volumes are zone-bound.
   ```bash
   $ kubectl describe pod web-1
   Events:
     Warning  FailedScheduling  ...  volume "pv-001" affinity rules conflict with node "node-1"
   ```
   Fix: schedule the pod in the same zone as the volume, or use a multi-zone storage (EFS).

2. **Pod has `nodeSelector: topology.kubernetes.io/zone: us-east-1a` and the only available zones are different.**
   Fix: relax the selector.

3. **Cluster autoscaling didn't add a node in the right zone.** The cluster autoscaler picks the cheapest zone, which may not match the volume.
   Fix: configure cluster autoscaler to balance zones.

## 10. Volume expansion hit limit

You tried to expand a PVC, but the underlying storage hit a limit.

**Signatures:**

```bash
$ kubectl describe pvc data
Events:
  Warning  VolumeResizeFailed  1m  external-resizer
    failed to expand volume: ... max volume size exceeded
```

```bash
Events:
  Warning  VolumeResizeFailed  1m  external-resizer
    failed to expand volume: ... volume modification is in progress
```

**Common sub-causes:**

1. **EBS volume at 64Ti max.** Try to expand beyond, fails.
2. **A previous expansion is still in progress.** EBS allows one modification at a time. Wait for the previous one to complete.
3. **StorageClass has `allowVolumeExpansion: false`.**
   ```bash
   $ kubectl get sc gp3 -o jsonpath='{.allowVolumeExpansion}'
   # false
   ```
   Fix: set to `true` (some volume types can't be expanded).

## Useful commands

```bash
# 1. what's the PVC bound to?
kubectl get pvc data -o jsonpath='{.spec.volumeName}' | xargs -I {} kubectl get pv {} -o yaml

# 2. which pod is using this PVC?
kubectl get pods -A -o json | jq '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == "data") | .metadata.name'

# 3. which PVC is this pod using?
kubectl get pod web-1 -o jsonpath='{.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}'

# 4. is the volume actually attached to the node?
kubectl describe pod web-1 | grep -A 5 "Volumes:"

# 5. resize in progress?
kubectl get events -n my-ns --field-selector reason=VolumeResize

# 6. raw CSI events
kubectl get events -n my-ns | grep -i "csi\|provision\|resize"
```

## The "is it the provisioner or the pod?" test

```bash
# 1. is the provisioner healthy?
kubectl get pods -n kube-system | grep -E "csi|provisioner"

# 2. provisioner logs
kubectl logs -n kube-system ebs-csi-controller-xxx --tail=50

# 3. is the pod using the PVC schedulable?
kubectl get pod -l app=web

# 4. can you create a test PVC?
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
  storageClassName: gp3
EOF

kubectl get pvc test-pvc -w
# if THIS also stays Pending, the issue is the provisioner / SC
# if THIS binds, the issue is specific to the original PVC's parameters
```

## The "is it the cloud quota?" test

```bash
# AWS: list EBS volumes in the region
aws ec2 describe-volumes --region us-east-1 \
  --filters "Name=status,Values=creating,available" \
  | jq '.Volumes | length'
# if 0, the volumes aren't being created at all (IAM or SC issue)

# AWS: are we hitting per-region volume count?
aws ec2 describe-account-attributes \
  --attribute-names max-ebs-volumes-per-region
# 5000 default

# AWS: are we hitting per-instance volume count?
aws ec2 describe-account-attributes \
  --attribute-names max-ebs-volumes-per-instance
# 28 default for some instance types
```

## Common gotchas

* **Re-applying the PVC doesn't help.** PVC binding is one-shot. The provisioner will try again only if you delete and recreate the PVC.
* **WaitForFirstConsumer is the default for many cloud SCs.** It's usually the right setting, but it can confuse diagnosis (no provisioner events = pod is the problem).
* **ReadWriteMany is rare on block storage.** EBS is RWO only. If you need RWX, use EFS or NFS.
* **EBS volumes are zone-bound.** A pod in zone A can't attach a volume in zone B. Use topology constraints to schedule in the same zone.
* **`storageClassName: ""` means default.** The cluster's default SC. If you want a specific SC, set it explicitly.
* **Some CSI drivers don't support expansion.** AWS EBS supports it, but only when `allowVolumeExpansion: true` in the SC.
* **Snapshot-based restore creates new volumes.** If you restore from a snapshot, you get a new PV with a new volume handle. The PVC's existing pod is unaffected.
* **Volume finalizers.** A PVC with a finalizer (e.g., `kubernetes.io/pvc-protection`) doesn't get deleted until the finalizer is removed. If the deletion hangs, check the finalizer.
* **Long-term stuck PVCs.** A PVC that's been Pending for hours won't be re-evaluated. `kubectl delete pvc data` and recreate (after fixing the cause).
* **The volume "exists" in the cloud but isn't a PV yet.** AWS shows a volume, but k8s doesn't know about it. The provisioner needs to create the PV object. If the provisioner is broken, the volume is orphaned in the cloud.

## A worked example

```bash
$ kubectl get pvc
NAME    STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
data    Pending                                      gp3-encrypted   10m

$ kubectl describe pvc data | tail -10
Events:
  Type     Reason              Age   From               Message
  ----     ------              ----  ----               -------
  Warning  ProvisioningFailed  10m  external-provisioner
    storageclass.in.storage.k8s.io "gp3-encrypted" not found
```

The StorageClass `gp3-encrypted` doesn't exist. Let me check.

```bash
$ kubectl get sc
NAME            PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE
gp2             kubernetes.io/aws-ebs      Delete          WaitForFirstConsumer
gp3             ebs.csi.aws.com            Delete          WaitForFirstConsumer
# no gp3-encrypted
```

Two options: create the SC, or use the existing `gp3`.

If I have a different SC that's similar:

```bash
# patch the PVC to use gp3 instead
kubectl patch pvc data -p '{"spec":{"storageClassName":"gp3"}}'
# this won't actually work — PVC's storageClassName is immutable
# need to delete and recreate
```

So:

```bash
# option 1: create the missing SC
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-encrypted
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF

# the provisioner should now pick it up
kubectl get pvc data -w
# NAME   STATUS   VOLUME   CAPACITY   ...
# data   Bound    pvc-xxx  100Gi      ...
```

Or:

```bash
# option 2: change the PVC to use the existing SC
kubectl delete pvc data
# recreate with the right SC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Gi
  storageClassName: gp3   # changed from gp3-encrypted
EOF
```

## See also

* [[Kubernetes/guides/troubleshooting/pod-pending|pod-pending]] — when the pod is the symptom, PVC is the cause
* [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] — when the pod fails after PVC binds
* [[Kubernetes/concepts/L05-config-storage/05-persistent-volumes|persistent-volumes]] — how storage works
* [[Kubernetes/concepts/L05-config-storage/06-storage-classes|storage-classes]] — how SCs work

---
title: "Runbook: EBS Volume Stuck Attaching (Multi-Attach, AZ Conflict, Attach Limits)"
description: "A Pod with an EBS-backed PVC stays ContainerCreating or Pending with Multi-Attach, FailedAttachVolume or volume node affinity errors. Find who still holds the volume and release it without risking data."
tags:
  [kubernetes/eks/operator-runbook, eks, runbook, ebs, storage, csi, incident]
date: 2026-10-20
aliases: [EKS Multi-Attach error runbook, EBS CSI FailedAttachVolume]
---

# Runbook: EBS Volume Stuck Attaching (Multi-Attach, AZ Conflict, Attach Limits)

**Applies to:** PVCs provisioned by the EBS CSI driver (`ebs.csi.aws.com`) on EC2 nodes, including the managed `aws-ebs-csi-driver` add-on and Auto Mode's built-in block storage (`ebs.csi.eks.amazonaws.com`).
**Typical severity:** Sev 2. Usually one stateful workload is down, often a database replica or a single-instance service.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

```text
Warning  FailedAttachVolume  attachdetach-controller  Multi-Attach error for volume "pvc-3f2a..." Volume is already
         exclusively attached to one node and can't be attached to another
Warning  FailedAttachVolume  attachdetach-controller  AttachVolume.Attach failed for volume "pvc-3f2a..." :
         rpc error: code = DeadlineExceeded desc = context deadline exceeded
Warning  FailedMount         kubelet                  MountVolume.MountDevice failed for volume "pvc-3f2a..." ...
Warning  FailedScheduling    default-scheduler        0/9 nodes are available: 3 node(s) had volume node affinity conflict, ...
```

## Impact

An EBS volume attaches to **one instance in one AZ** (`ReadWriteOnce`), apart from io1/io2 Multi-Attach, which needs a cluster-aware filesystem. The safety rule is to **never let two writers mount it**. Every fix below respects that; skipping it corrupts data.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1 NS=<namespace> POD=<stuck pod> PVC=<claim name>
export PV=$(kubectl get pvc "$PVC" -n "$NS" -o jsonpath='{.spec.volumeName}')
export VOL=$(kubectl get pv "$PV" -o jsonpath='{.spec.csi.volumeHandle}')
```

## Triage

**1. Read the events and identify the kind of failure.**

```bash
kubectl describe pod "$POD" -n "$NS" | sed -n '/Events:/,$p'
```

- `Multi-Attach error` → still attached to another node (cause A or B).
- `volume node affinity conflict` → no schedulable node in the volume's AZ (cause C).
- `AttachVolume.Attach failed` / `DeadlineExceeded` → CSI or EC2 attach failure (cause D or E).
- `FailedMount` after a successful attach → filesystem or permission step (cause F).

**2. Where is the volume, according to AWS and to Kubernetes?**

```bash
aws ec2 describe-volumes --region "$REGION" --volume-ids "$VOL" \
  --query 'Volumes[].{state:State,az:AvailabilityZone,type:VolumeType,attachments:Attachments[].[InstanceId,State]}'
kubectl get pv "$PV" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions}{"\n"}'
kubectl get volumeattachments -o custom-columns=NAME:.metadata.name,PV:.spec.source.persistentVolumeName,NODE:.spec.nodeName,ATTACHED:.status.attached \
  | grep -E "NAME|$PV"
```

**3. Is anyone still using it?**

```bash
kubectl get pods -A -o json | jq -r --arg c "$PVC" --arg ns "$NS" '.items[] |
  select(.metadata.namespace==$ns and any(.spec.volumes[]?; .persistentVolumeClaim.claimName==$c)) |
  "\(.metadata.name)\t\(.spec.nodeName)\t\(.status.phase)\t\(.metadata.deletionTimestamp // "")"'
```

- **Two Pods** (old and new) reference the claim → cause A.
- **One old Pod, `Terminating`,** on a node that's `NotReady` → cause B.

**4. CSI driver logs:**

```bash
kubectl logs -n kube-system deploy/ebs-csi-controller -c ebs-plugin --tail=100 | grep -iE "$VOL|error" | tail -20
kubectl logs -n kube-system deploy/ebs-csi-controller -c csi-attacher --tail=50 | grep -i "$PV" | tail
```

## Diagnosis

| Signal                                                             | Cause                                              | Fix      |
| ------------------------------------------------------------------ | -------------------------------------------------- | -------- |
| Multi-Attach; old Pod still running on a healthy node              | A. Rolling update on a ReadWriteOnce volume        | Fix A    |
| Multi-Attach; old Pod `Terminating` on a NotReady node             | B. Old node unreachable, volume not released       | Fix B    |
| `volume node affinity conflict`                                    | C. No capacity in the volume's AZ                  | Fix C    |
| `UnauthorizedOperation`, or KMS `AccessDenied`, in the CSI logs    | D. CSI driver IAM or KMS permission                | Fix D    |
| Attach timeout; node has many volumes attached                     | E. Node attachment limit reached                   | Fix E    |
| Volume `attaching` or `detaching` in EC2 for more than ~10 minutes | E2. Stuck on the EC2 side                          | Escalate |
| `FailedMount` after attach; very slow start on large volumes       | F. Mount step: filesystem check or `fsGroup` chown | Fix F    |

## Fix

### A. Rolling update on a ReadWriteOnce volume

A Deployment with the default `RollingUpdate` strategy starts the new Pod **before** stopping the old one. With an RWO volume, the new Pod can't attach until the old one is gone. If they're on different nodes, the rollout deadlocks.

- **Now:** scale down or delete the **old** Pod (it's healthy, and stops cleanly). The new Pod then attaches.
- **Permanently:** use `strategy: {type: Recreate}` for single-writer Deployments, or move the workload to a StatefulSet.

### B. Old node unreachable

Kubernetes won't release the volume while the old Pod might still be writing. Follow [[Kubernetes/eks/operator-runbook/runbooks/node-not-ready|Node NotReady]] Fix step 4:

1. Confirm the old instance is `stopped` or `terminated`. If it's running but partitioned, stop it: `aws ec2 stop-instances --force --instance-ids <id>`.
2. Taint the node out of service: `kubectl taint node <old-node> node.kubernetes.io/out-of-service=nodeshutdown:NoExecute`. Kubernetes deletes the Pod and the CSI driver detaches the volume.
3. Watch `describe-volumes` move to `available`, then `in-use` on the new instance.

**⚠ Destructive, last resort:** `aws ec2 detach-volume --force --volume-id "$VOL"`. Use it only if the instance is confirmed stopped and the normal detach is stuck. A force detach skips filesystem flushing; run the application's integrity checks afterwards.

### C. No capacity in the volume's AZ

The volume lives in one AZ, so the Pod can only run there. **Don't delete and recreate the PVC to "move" it.** With `reclaimPolicy: Delete`, that destroys the data.

- **Karpenter:** check that the NodePool's `topology.kubernetes.io/zone` requirement and the EC2NodeClass subnets include that AZ.
- **Managed node groups:** make sure a group with subnets in that AZ has room to scale (cluster-autoscaler's `--balance-similar-node-groups` helps).
- **To move the data to another AZ deliberately:** snapshot, then create a PVC from the snapshot with a `VolumeSnapshot` dataSource in the target AZ. Plan it; don't do it mid-incident.

### D. CSI driver IAM or KMS permission

The driver's controller role needs `AmazonEBSCSIDriverPolicy`. For volumes encrypted with a customer-managed KMS key, it also needs `kms:CreateGrant`, `kms:Decrypt`, `kms:GenerateDataKeyWithoutPlaintext` and `kms:DescribeKey` on that key, allowed by the key policy too.

```bash
aws eks describe-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name aws-ebs-csi-driver \
  --query 'addon.{role:serviceAccountRoleArn,status:status,issues:health.issues}'
```

### E. Node attachment limit reached

Many Nitro instance types share one attachment limit across EBS volumes, ENIs and NVMe instance-store devices, so a node with many ENIs fits fewer volumes. The CSI driver reports what's left for the scheduler:

```bash
kubectl get csinode <node> -o jsonpath='{.spec.drivers[?(@.name=="ebs.csi.aws.com")].allocatable.count}{"\n"}'
kubectl get volumeattachments -o custom-columns=NODE:.spec.nodeName --no-headers | sort | uniq -c | sort -rn | head
```

Spread stateful Pods across nodes (topology spread or anti-affinity), or use instance types with higher limits. If the reported count is wrong for your instances, set the driver's `volumeAttachLimit` (`node.volumeAttachLimit` in the add-on or Helm configuration).

### F. Mount step slow or failing

- **`fsGroup` chown:** on volumes with millions of files, Kubernetes recursively changes ownership at every mount. That can take longer than the mount timeout. Set `securityContext.fsGroupChangePolicy: OnRootMismatch`.
- **Filesystem errors** (`wrong fs type`, `structure needs cleaning`): the volume needs `fsck`. Attach it to a utility instance, check it there, and restore from snapshot if it's damaged.

## Verify recovery

```bash
kubectl get pod "$POD" -n "$NS" -o wide        # Running, on a node in the volume's AZ
aws ec2 describe-volumes --region "$REGION" --volume-ids "$VOL" --query 'Volumes[].Attachments[].[InstanceId,State]'
```

Confirm at the **application** level: the database starts without recovery errors, a replica rejoins and catches up, or a read and write round-trip succeeds. A Running Pod alone doesn't prove the data is good.

## Escalate

Open an AWS Support case if a volume stays `attaching` or `detaching` for more than ~10 minutes with the instance healthy, or `describe-volumes` reports `impaired` I/O status (`aws ec2 describe-volume-status`). Attach the volume ID, instance ID, the UTC window and the CSI controller log excerpts.

## Prevent

- Use `Recreate` (or StatefulSets) for every single-writer workload with an RWO volume.
- StorageClasses with `volumeBindingMode: WaitForFirstConsumer`, so volumes are created in the AZ where the Pod lands.
- Make sure every AZ that holds volumes can always get capacity, through NodePool zones and node group subnets.
- Take scheduled snapshots (`VolumeSnapshot`, AWS Backup or Data Lifecycle Manager) and test a restore.
- Alert on `FailedAttachVolume` and `FailedMount` events lasting more than 5 minutes.

## Background

- [[Kubernetes/eks/storage/ebs-csi|EBS CSI driver on EKS]]
- [[Kubernetes/guides/troubleshooting/pvc-stuck|Troubleshooting stuck PVCs]]
- [[AWS/storage/ebs/README|Amazon EBS]]
- [Non-graceful node shutdown](https://kubernetes.io/docs/concepts/cluster-administration/node-shutdown/#non-graceful-node-shutdown)
- [Amazon EC2 instance volume limits](https://docs.aws.amazon.com/ec2/latest/instancetypes/volume_limits.html)

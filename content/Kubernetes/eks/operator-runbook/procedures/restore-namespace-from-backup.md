---
title: "Procedure: Restore a Namespace from a Velero Backup"
description: "Restore Kubernetes objects and EBS-backed volumes for one namespace with Velero: test into a scratch namespace first, then restore in place, and verify at the application level."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    procedure,
    backup,
    velero,
    disaster-recovery,
  ]
date: 2026-10-20
aliases: [EKS Velero restore, EKS namespace restore]
---

# Procedure: Restore a Namespace from a Velero Backup

**Applies to:** clusters backed up with Velero (AWS plugin, objects in S3) with volume data from CSI snapshots (EBS) or file-system backup. The same flow applies to other backup tools: test restore first, then the real restore, then application checks.
**Duration:** minutes for objects; volumes depend on size (snapshot restore is lazy, so first reads are slower).
**Risk:** high for in-place restores, which overwrite or recreate live objects. Low for restores into a new namespace.
**Tested:** not run on a live cluster; commands checked for syntax.

## When to use

- A namespace, or objects in it, were deleted or corrupted.
- Application data in a PVC must go back to a point in time.
- For a scheduled restore drill, do the test restore only (steps 1–3).

For whole-cluster loss, the same flow applies, but first build a new cluster with the same add-ons, CRDs and storage classes.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export NS=<namespace to restore>
export RESTORE_NS=$NS-restore-$(date +%m%d%H%M)
```

## Pre-checks

**1. Velero is healthy and sees the backups.**

```bash
velero version
velero backup-location get                        # PHASE Available
velero backup get | grep -E "NAME|$NS"            # or: velero backup get --selector ...
export BACKUP=<backup name>
velero backup describe "$BACKUP" --details | sed -n '1,60p'
```

- **Expect:** backup `Phase: Completed`. `PartiallyFailed` means some items or volumes are missing; read `velero backup logs "$BACKUP"` before relying on it.
- Check the backup includes the namespace and its PVCs, and note its timestamp. That's your data recovery point.

**2. Target dependencies exist:** the CRDs used by objects in the backup, the StorageClasses and the `VolumeSnapshotClass`, the IAM roles referenced by service accounts, and the external secrets the namespace depends on.

**3. Decide what happens to the live namespace.** Velero doesn't overwrite existing objects by default; it skips them and warns. For an in-place restore of objects that still exist, either delete them first, or use `--existing-resource-policy update`, which doesn't apply to everything. Read the Velero documentation for your version.

## Steps

**1. Test restore into a new namespace.** This touches nothing live:

```bash
velero restore create "test-$RESTORE_NS" --from-backup "$BACKUP" \
  --include-namespaces "$NS" --namespace-mappings "$NS:$RESTORE_NS"
velero restore describe "test-$RESTORE_NS" --details
velero restore logs "test-$RESTORE_NS" | grep -iE 'error|warn' | head -40
```

**2. Check the test restore.**

```bash
kubectl get all,pvc -n "$RESTORE_NS"
kubectl get pvc -n "$RESTORE_NS" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
```

- **Checkpoint:** PVCs are `Bound`, and Pods are Running. Some will fail on purpose; for example Ingresses or Services that clash with live ones, or workloads that connect to live databases. Scale those down in the test namespace.
- Restored EBS volumes are created in the same AZ as the original snapshot's volume. Pods need nodes in that AZ; see [[Kubernetes/eks/operator-runbook/runbooks/ebs-volume-stuck-attaching|EBS stuck attaching]] cause C.

**3. Verify the data** at the application level: row counts, the latest record timestamp, checksums or a read-only smoke test against the restored copy. This step tells you whether the backup is good.

**4. Restore in place** (only if the test passed and the incident owner agrees).

**⚠ Destructive:** deleting the broken namespace removes its PVCs. With `reclaimPolicy: Delete`, that also deletes the volumes. If any data in them might still be needed, snapshot first, or set the PVs to `Retain`:

```bash
for pv in $(kubectl get pvc -n "$NS" -o jsonpath='{.items[*].spec.volumeName}'); do
  kubectl patch pv "$pv" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
done
kubectl delete namespace "$NS"
kubectl get namespace "$NS"      # wait until NotFound
velero restore create "restore-$NS-$(date +%m%d%H%M)" --from-backup "$BACKUP" --include-namespaces "$NS"
```

To restore a subset instead of the whole namespace, use `--include-resources` or `--selector`, without deleting the namespace.

**5. Watch it complete.**

```bash
velero restore get | head
velero restore describe <restore-name> --details
kubectl get pods,pvc -n "$NS"
```

## Abort criteria and rollback

- If the test restore fails, or its data is wrong, **don't** restore in place. Try an older backup, or escalate to the application owner.
- If the in-place restore fails midway, the retained PVs from step 4 still hold the pre-restore data. Bind them to new PVCs to get it back.

## Post-checks

- Application checks (as in step 3) pass against the live namespace.
- GitOps shows the namespace in sync. If it doesn't, decide whether Git or the restored state is right before syncing.
- Ingresses and Services have load balancers again (the controller recreates them; their DNS names may change).

## Clean-up

```bash
kubectl delete namespace "$RESTORE_NS"
velero restore delete "test-$RESTORE_NS" --confirm
```

Release retained PVs from step 4 once they're no longer needed. Record the backup used, the recovery point and the time to restore. That's your measured RPO and RTO.

## Background

- [[Kubernetes/guides/non-functional/backup-restore|Backup and restore]]
- [[Kubernetes/eks/storage/ebs-csi|EBS CSI driver]]
- [Velero restore reference](https://velero.io/docs/main/restore-reference/)

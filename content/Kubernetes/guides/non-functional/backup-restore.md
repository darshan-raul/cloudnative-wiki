---
title: Backup & Restore
tags:
  - Kubernetes
  - Non-Functional
  - Backup
  - Restore
  - DR
  - Velero
  - etcd
---

How to actually back up and restore a k8s cluster, day to day. This is the "**when things break, here's how you fix it**" guide. The patterns work for self-managed and cloud-managed clusters (with adjustments for who manages etcd).

## What to back up

```
┌────────────────────────────────────────────────────────────┐
│  Cluster data                                              │
│  ├── etcd (the source of truth for k8s API objects)       │
│  ├── Persistent volumes (PVC contents)                    │
│  ├── Application configs (in git — usually)                │
│  └── Secrets (in etcd, but also external stores)            │
│                                                            │
│  Add-on state                                              │
│  ├── Cert-manager certificates                            │
│  ├── Argo CD / Flux state (in git, plus Redis/Postgres)   │
│  ├── Cluster autoscaler state                            │
│  └── Custom operator state (Datadog, etc.)                │
│                                                            │
│  Application state                                         │
│  ├── Database contents (managed separately, usually)      │
│  ├── Object storage (S3, GCS)                              │
│  └── Queues / caches (Redis, Kafka)                        │
└────────────────────────────────────────────────────────────┘
```

**For a k8s cluster backup:** etcd + PVs. The rest is in git or external systems.

## etcd backup

etcd is the **database** for the k8s API. Backing it up is the most important thing.

### For self-managed (kubeadm)

```bash
# 1. find the etcd endpoints
kubectl -n kube-system get pods -l component=etcd -o wide
# NAME                             READY   STATUS    RESTARTS   AGE   IP            NODE
# etcd-master-1                    1/1     Running   0          30d   10.0.0.1     master-1
# etcd-master-2                    1/1     Running   0          30d   10.0.0.2     master-2
# etcd-master-3                    1/1     Running   0          30d   10.0.0.3     master-3

# 2. find the certs
ls /etc/kubernetes/pki/etcd/
# ca.crt  ca.key  server.crt  server.key

# 3. take a snapshot
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%Y%m%d-%H%M).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

### For cloud-managed (EKS, GKE, AKS)

The cloud manages etcd. You don't back it up. The cloud does (and restores it for you if you ask).

**If you need cluster-state backup in cloud-managed:** use **Velero** to back up the k8s API objects (which are in etcd). That's what the cloud doesn't manage.

### Automating etcd backups

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: etcd-backup
  namespace: kube-system
spec:
  schedule: "0 2 * * *"   # daily at 2am
  successfulJobsHistoryLimit: 7
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: etcd-backup-sa
          containers:
          - name: etcd-backup
            image: k8s.gcr.io/etcd:3.5.7
            command:
            - /bin/sh
            - -c
            - |
              set -e
              ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%Y%m%d-%H%M).db \
                --endpoints=https://127.0.0.1:2379 \
                --cacert=/etc/kubernetes/pki/etcd/ca.crt \
                --cert=/etc/kubernetes/pki/etcd/server.crt \
                --key=/etc/kubernetes/pki/etcd/server.key
              # upload to S3
              aws s3 cp /backup/etcd-$(date +%Y%m%d-%H%M).db s3://my-etcd-backups/
              # cleanup local
              rm -f /backup/etcd-$(date +%Y%m%d-%H%M).db
            volumeMounts:
            - name: etcd-certs
              mountPath: /etc/kubernetes/pki/etcd
              readOnly: true
            - name: backup
              mountPath: /backup
          restartPolicy: OnFailure
          volumes:
          - name: etcd-certs
            hostPath:
              path: /etc/kubernetes/pki/etcd
              type: Directory
          - name: backup
            hostPath:
              path: /var/backups/etcd
              type: DirectoryOrCreate
```

**Important:** schedule backups when the cluster is quiet (early morning).

### etcd backup gotchas

* **etcd v3 vs v2.** Use `ETCDCTL_API=3` always. v2 is deprecated.
* **The etcd pod's filesystem** has the data dir. You can't just `cp` it; you need a consistent snapshot.
* **Encryption at rest.** etcd can encrypt data, but the key must be backed up separately.
* **Cross-region etcd** (3 nodes in 3 AZs) — back up from any one of them.
* **Backup size.** etcd snapshots are small (KBs-MBs for most clusters).
* **Backup duration.** A snapshot is fast (seconds), even for large etcds.
* **Backup verification.** A snapshot that can't be restored is useless. Verify with `etcdctl snapshot status`.

### Verify an etcd snapshot

```bash
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot.db \
  --write-out=table
```

```
+----------+----------+--------------+------------+
|  HASH    | REVISION | TOTAL KEYS   | TOTAL SIZE |
+----------+----------+--------------+------------+
| 1a2b3c4d | 12345    | 1234         | 4.2 MB     |
+----------+----------+--------------+------------+
```

If the snapshot is corrupt, this fails.

## Velero (the standard k8s backup tool)

Velero backs up k8s API objects and PVs. It's the right tool for most clusters.

### Install Velero

```bash
# for AWS
velero install \
  --provider aws \
  --bucket my-velero-backups \
  --prefix velero \
  --secret-file ./credentials-velero \
  --use-restic \
  --backup-location-config region=us-east-1 \
  --snapshot-location-config region=us-east-1

# for GCP
velero install \
  --provider gcp \
  --bucket my-velero-backups \
  --prefix velero \
  --secret-file ./credentials-gcp \
  --use-restic

# for Azure
velero install \
  --provider azure \
  --bucket my-velero-backups \
  --prefix velero \
  --secret-file ./credentials-azure \
  --use-restic

# backup PVCs with restic (filesystem-based)
# or use CSI snapshots if your CSI driver supports them
```

### Schedule daily backups

```bash
velero schedule create daily-full \
  --schedule="0 2 * * *" \
  --include-namespaces '*' \
  --ttl 720h   # 30 days
```

### On-demand backup

```bash
# back up a single namespace
velero backup create pre-upgrade-myapp \
  --include-namespaces myapp

# back up specific resources
velero backup create config-backup \
  --include-resources configmaps,secrets \
  --include-namespaces myapp

# back up everything
velero backup create full-cluster \
  --include-namespaces '*'
```

### List and inspect backups

```bash
velero backup get
# NAME              STATUS      CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
# daily-full-2024... Completed   2024-01-15 02:00:00 +0000 UTC  29d       default            <none>
# pre-upgrade-...   Completed   2024-01-15 14:00:00 +0000 UTC  29d       default            <none>

velero backup describe daily-full-2024-01-15-020000
# details: namespaces, resources, hooks, errors

velero backup logs daily-full-2024-01-15-020000
# step-by-step log
```

### Restore

```bash
# restore from a backup
velero restore create --from-backup daily-full-2024-01-15-020000

# restore to a different namespace
velero restore create --from-backup daily-full-2024-01-15-020000 \
  --namespace-mappings myapp:myapp-restore

# restore specific resources
velero restore create --from-backup daily-full-2024-01-15-020000 \
  --include-resources deployments,services
```

### Velero gotchas

* **CSI snapshots vs Restic.** Restic does file-level, slower for big PVs. CSI snapshots are block-level, faster, but require CSI driver support.
* **CRDs are backed up** by default, but **not the operators/controllers that manage them.** Restoring a CRD without its operator leaves the CRD in a "stuck" state.
* **Velero restores to a specific namespace by default.** Use `--include-namespaces '*'` to restore all.
* **PVs are restored with the same StorageClass.** If the StorageClass doesn't exist in the target cluster, restore fails.
* **Velero doesn't back up application data** in external systems (RDS, S3, etc.). Those are separate.
* **Velero's metadata is in etcd** (Backup, Restore objects). If you restore etcd, the Velero CRDs come back too.

## PV backups

### Cloud-native snapshots (CSI)

Most cloud CSI drivers support snapshots:

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: my-pv-snapshot
spec:
  volumeSnapshotClassName: csi-aws-vsc
  source:
    persistentVolumeClaimName: my-pvc
```

Then restore:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc-restored
spec:
  dataSource:
    name: my-pv-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Gi
```

**Pros:** fast, consistent, supported by most CSI drivers.

**Cons:** snapshot lives in the cloud, not portable. Need a corresponding restore target.

### Velero with CSI snapshots

```bash
# install with CSI snapshot support
velero install \
  --provider aws \
  --bucket my-velero-backups \
  --secret-file ./credentials-velero \
  --features=EnableCSI
```

```yaml
# backup with CSI snapshots
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: myapp-with-csi
spec:
  includedNamespaces: [myapp]
  snapshotMoveData: false   # if CSI snapshots are supported
  csiSnapshotTimeout: 10m
```

### Restic (filesystem backup)

For PVs that can't use CSI snapshots:

```bash
velero install \
  --provider aws \
  --bucket my-velero-backups \
  --secret-file ./credentials-velero \
  --use-restic
```

Restic reads files from the PV's filesystem and uploads them. Slower than CSI snapshots but works for any PV.

**For large PVs:** Restic is slow. Use CSI snapshots if you can.

## What Velero doesn't back up

Velero covers k8s API objects and PVs. It does **not** back up:

- **Application data in external systems** (RDS, DynamoDB, S3, etc.) — back those up separately
- **In-cluster caches** (Redis, Memcached) — design for these to be disposable
- **Caches inside apps** (LRU caches, in-memory state) — design for these to be rebuildable
- **Logs stored in cluster** (if using in-cluster Loki, etc.) — back those up separately
- **Metrics** (Prometheus TSDB) — not critical, can be rebuilt
- **Custom controller state** (operators) — usually in etcd, so it's covered, but some have external state

## A complete backup strategy

```
1. etcd backup (self-managed clusters)
   - Daily, 30-day retention
   - Encrypted, cross-region S3
   - Test restore quarterly

2. Velero (cluster state)
   - Daily, 30-day retention
   - Encrypted, cross-region S3
   - Test restore monthly

3. PV snapshots (stateful workloads)
   - Daily for critical data
   - Hourly for very critical
   - 7-day retention
   - Cross-region replication

4. Database backups (managed)
   - Use the cloud's built-in
   - Daily full + WAL/transaction logs
   - 30-day retention
   - Cross-region

5. Object storage (S3)
   - Versioning enabled
   - Cross-region replication
   - Lifecycle policies

6. Git
   - Source of truth
   - Multiple remotes (mirror to GitHub, GitLab, etc.)
```

## Restoring a cluster

### Scenario 1: lost a single resource

```bash
# Velero restore
velero restore create --from-backup <backup> --include-resources deployments,services
```

### Scenario 2: lost a namespace

```bash
velero restore create --from-backup <backup> --include-namespaces myapp
```

### Scenario 3: lost a node

For a lost node, just remove it from the cluster and let the cluster reschedule pods:

```bash
kubectl delete node <lost-node>
# pods on that node will be rescheduled
```

### Scenario 4: lost a control plane node (self-managed)

```bash
# 1. SSH to a surviving control plane
ssh master-2

# 2. use etcdctl to remove the dead member
etcdctl member list
etcdctl member remove <dead-member-id>

# 3. if no survivors, restore from snapshot
# (see etcd restore below)
```

### Scenario 5: lost the entire cluster

For self-managed:
1. **Re-provision the cluster** (kubeadm init)
2. **Restore etcd** from snapshot
3. **Reinstall add-ons** (CNI, ingress, cert-manager, etc.)
4. **Velero restore** for namespace contents
5. **Verify** everything

For cloud-managed:
1. **Re-create the cluster** (terraform, eksctl, gcloud, etc.)
2. **Velero restore** for namespace contents
3. **Reinstall add-ons**
4. **Verify**

## The etcd restore (kubeadm)

```bash
# 1. stop the apiserver (only on the control plane you're restoring)
sudo systemctl stop kube-apiserver

# 2. move the existing data dir
sudo mv /var/lib/etcd /var/lib/etcd-old

# 3. restore the snapshot
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd

# 4. update etcd.yaml to point to the new dir
sudo vim /etc/kubernetes/manifests/etcd.yaml
# update --data-dir=/var/lib/etcd
# (or change the hostPath for the etcd-data volume)

# 5. the apiserver will pick up the change automatically
# (kubelet watches /etc/kubernetes/manifests/)

# 6. verify
kubectl get nodes
# should show all nodes
```

**For multi-node etcd:** restore to one node, then have the others rejoin.

## Backup verification

The most important step. **An unverified backup is just a wish.**

### Test the etcd snapshot

```bash
# 1. create a test cluster
kind create cluster --name backup-test

# 2. copy snapshot to a test node
docker cp /backup/etcd-snapshot.db backup-test-control-plane:/tmp/

# 3. restore in the test cluster
docker exec backup-test-control-plane bash -c "
  ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-snapshot.db \
    --data-dir=/tmp/etcd-test
"

# 4. verify the data
docker exec backup-test-control-plane etcdctl --endpoints=:2379 get /registry --prefix --keys-only | head
```

### Test Velero

```bash
# 1. create a test cluster
kind create cluster --name velero-test

# 2. install Velero in the test cluster
velero install ...

# 3. point at the same S3 bucket
velero backup-location set --bucket my-velero-backups

# 4. restore
velero restore create --from-backup <backup>

# 5. verify
kubectl get all -A
# should match the original cluster
```

## The "I lost everything" runbook

1. **Don't panic.** The cloud or backup has it.
2. **Identify what's lost.** Cluster? Namespace? Specific resource?
3. **Re-create infrastructure.** New cluster (cloud-managed) or restore etcd (self-managed).
4. **Restore from backup.** Velero for k8s objects, snapshots for PVs.
5. **Verify.** Check critical workloads are running.
6. **Re-point DNS** if cluster endpoint changed.
7. **Communicate.** Internal: status. Customer: ETA.
8. **Post-mortem.** Within a week, what failed, what worked, what to change.

## Common gotchas

* **Velero doesn't back up CRDs that are in-cluster but defined by operators.** If you uninstall the operator and reinstall, the CRDs are gone.
* **etcd snapshot doesn't include the encryption key.** Back up the key separately.
* **Restic backups are slow for large PVs.** A 1TB PV can take hours.
* **CSI snapshots are bound to the cloud.** Can't restore to on-prem without conversion.
* **Restoring to a different k8s version** can break things. Test compatibility.
* **Velero's `Backup` objects are in etcd.** If you restore etcd, they come back. Useful, but can clutter.
* **The backup process is a workload.** It needs resources, scheduling, monitoring. Not "set and forget."
* **A snapshot during heavy write load can be slow or inconsistent.** Schedule for off-peak.
* **The restore target cluster needs the same IAM/cloud permissions.** Velero can't snapshot PVs without the right IAM.
* **Schedule backup retention policies** with care. Some teams lose data because lifecycle policies deleted backups.

## See also

* [[Kubernetes/guides/non-functional/disaster-recovery|disaster-recovery]] — the bigger picture
* [[Kubernetes/guides/non-functional/upgrade-strategy|upgrade-strategy]] — backup before upgrade
* [[Kubernetes/guides/non-functional/security-baseline|security-baseline]] — encrypting backups
* [[Kubernetes/guides/non-functional/multi-tenancy|multi-tenancy]] — per-tenant restore

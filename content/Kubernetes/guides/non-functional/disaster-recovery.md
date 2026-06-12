---
title: Disaster Recovery
tags:
  - Kubernetes
  - Non-Functional
  - Disaster-Recovery
  - Backup
  - DR
---

DR is the answer to "what if the cluster is gone?" The cluster doesn't fail often, but when it does — region outage, ransomware, accidental deletion, infra-as-code gone wrong — the only thing that saves you is the backup you took earlier.

## RPO and RTO

Two numbers define your DR plan:

- **RPO (Recovery Point Objective)** — how much data can you afford to lose? Measured in time. RPO of 1 hour means: if disaster strikes, you can lose at most 1 hour of data.
- **RTO (Recovery Time Objective)** — how long until you're back online? Measured in time. RTO of 4 hours means: from disaster to fully restored, 4 hours max.

| Tier | RPO | RTO | Cost | Example |
|------|-----|-----|------|---------|
| Tier 1 (best) | seconds | seconds | very high | Active-active multi-region |
| Tier 2 | minutes | minutes | high | Active-passive with hot standby |
| Tier 3 | 1 hour | hours | medium | Backup + restore |
| Tier 4 (lowest) | 24 hours | 24+ hours | low | Offsite backups only |

**For most k8s workloads, Tier 2-3 is appropriate.**

## What needs backing up

K8s has two main things to back up:

1. **Cluster state** — etcd, which holds all API objects
2. **Application data** — PersistentVolumes, which hold user data

```
┌──────────────────────────────────────────────────────────────┐
│  Cluster state (etcd)                                        │
│  ├─ Deployments, Services, ConfigMaps, Secrets, CRDs         │
│  ├─ RBAC, NetworkPolicy, PodSecurityStandards                │
│  └─ All custom resources                                     │
├──────────────────────────────────────────────────────────────┤
│  Application data (PVs)                                      │
│  ├─ Database files (postgres, mysql, mongo data dir)         │
│  ├─ User uploads (S3, NFS, gluster)                          │
│  └─ Caches that need to persist (Redis snapshots)            │
└──────────────────────────────────────────────────────────────┘
```

Backing up cluster state without application data is useless. Both are needed.

## etcd backup

etcd snapshots contain the entire cluster state. Restore from snapshot = entire cluster restored.

**Cloud-managed clusters:** the cloud handles etcd backup (EKS, GKE, AKS). You don't get direct access but you can ask for restoration.

**Self-managed (kubeadm, kOps, etc.):** you handle etcd.

```bash
# etcd snapshot
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key

# verify
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot.db

# restore (DANGEROUS — replaces cluster state)
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restore
```

**For managed clusters, "restore" means contacting the cloud.** EKS: AWS Support can restore. GKE: gcloud `container clusters restore`. AKS: portal/Az CLI.

**Recovery time:** etcd restore is fast (minutes), but the cluster is unavailable during restore. Pods are recreated from the snapshot state, including their prior scheduling decisions.

## Application data backup

For data in PVs, you need **application-aware** or **filesystem-level** backup.

### Application-aware (best)

The application quiesces itself, takes a consistent snapshot, then resumes.

- **postgres** — `pg_dump`, `pg_basebackup`
- **mysql** — `mysqldump`, Percona XtraBackup
- **mongodb** — `mongodump`, MongoDB Atlas backup
- **redis** — `BGSAVE`
- **Elasticsearch** — `_snapshot` API

These are consistent at the application level, even if the underlying storage isn't.

### Filesystem-level (good)

Tools that snapshot the filesystem while the app is running. May not be application-consistent (e.g., postgres might be mid-transaction).

- **Velero** — k8s-native, supports PV snapshots via CSI
- **Restic/Kopia** — file-level backup
- **ZFS/Btrfs snapshots** — if your storage backend supports them
- **EBS snapshots** — AWS volume snapshots, can be triggered from k8s

### Cloud-native

- **AWS Backup** — manages EBS snapshots, RDS backups, etc., across accounts
- **Azure Backup** — similar for Azure
- **GCP Persistent Disk Snapshots** — for GCE PD

## Velero — the k8s-native backup tool

Velero backs up:
- Cluster state (all API objects)
- Persistent volumes (via CSI snapshots, Restic, or Kopia)

### Install

```bash
# Add the Helm repo
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero \
  --namespace velero --create-namespace \
  --set configuration.backupStorageLocation[0].name=default \
  --set configuration.backupStorageLocation[0].provider=aws \
  --set configuration.backupStorageLocation[0].bucket=my-backups \
  --set configuration.backupStorageLocation[0].config.region=us-east-1 \
  --set credentials.existingSecret=velero-credentials \
  --set deployRestic=true   # file-level backup
```

### Backup

```bash
# backup all namespaces
velero backup create full-cluster-$(date +%Y%m%d) \
  --default-volumes-to-restic   # or use CSI snapshots

# backup specific namespace
velero backup create web-$(date +%Y%m%d) \
  --include-namespaces web

# schedule: daily at 2am
velero schedule create daily-full \
  --schedule="0 2 * * *" \
  --ttl 720h   # keep for 30 days
```

### Restore

```bash
# full restore
velero restore create --from-backup full-cluster-20240115

# restore specific namespace
velero restore create --from-backup web-20240115 \
  --include-namespaces web

# verify
velero restore describe --name restore-xxx
velero restore logs --name restore-xxx
```

### What Velero doesn't do well

- **Application consistency.** Velero takes CSI snapshots or restic copies. The app is still running, may have in-flight transactions.
- **Cross-cluster restore requires some setup.** Different clouds, different CSI drivers.
- **Restore to a different k8s version.** Works, but be aware of API version drift.

**For app-consistent backups:** use the operator or the app's own backup mechanism. Velero is great for cluster state and "good enough" PV backup.

## RTO/RPO targets in practice

For a 4-hour RTO, 1-hour RPO:

```
Every 15 minutes:
  - Application-level backup (pg_basebackup, mongodump, etc.) to S3
  - 15-min RPO achieved

Daily:
  - Velero backup of cluster state to S3
  - This gives 1-day RPO for cluster state, but it's mostly for "oops I deleted something"
  - not for "data loss" — that's covered by app-level

Every 5 minutes:
  - Cross-region replication of S3 bucket
  - So if us-east-1 is gone, us-west-2 has the data
```

**RTO calculation:**

- 15 min: detect outage
- 5 min: declare DR, start failover
- 30 min: spin up new cluster (Cluster API, kOps, etc.)
- 30 min: install operators, GitOps reconcilers
- 1 hour: restore cluster state (Velero)
- 1 hour: restore data (Velero + app backups)
- 1 hour: verify, test, route traffic
- **Total: 4-5 hours** — within target

## Cluster recreation

The hardest part isn't the data — it's getting the cluster back up. **GitOps is essential here.**

If your cluster was provisioned with:
- **kOps / Cluster API** — declarative, can re-provision
- **Terraform / Pulumi** — declarative, can re-apply
- **EKS / GKE / AKS** — declarative, can recreate
- **Hand-built** — disaster

**Best practice:** cluster lifecycle is in git, with a "create new cluster" pipeline that works from scratch. Test it quarterly.

## Multi-region DR patterns

### Backup-and-restore (lowest cost, highest RTO)

- One region active, another has only backups
- RTO: hours (re-provision cluster, restore data)
- RPO: depends on backup frequency

### Pilot light (medium cost, medium RTO)

- Primary region: full production
- Secondary region: minimum infra running (etcd, control plane), no app pods
- On disaster: scale up secondary, restore data, route traffic
- RTO: 30-60 min
- RPO: minutes (data continuously replicated)

### Warm standby (higher cost, lower RTO)

- Primary: full production
- Secondary: full infra, minimum app pods (1-2 replicas per service)
- On disaster: scale up, route traffic
- RTO: 10-30 min
- RPO: seconds to minutes

### Active-active (highest cost, lowest RTO)

- Both regions serve traffic
- Data replicated synchronously (or near-sync)
- On disaster: route all traffic to surviving region
- RTO: seconds (DNS update or LB failover)
- RPO: seconds (or zero, with synchronous replication)

| Pattern | RTO | RPO | Cost | When to use |
|---------|-----|-----|------|-------------|
| Backup-and-restore | 4+ hours | 1+ hour | $ | Compliance, not customer-facing |
| Pilot light | 30-60 min | minutes | $$ | Most production |
| Warm standby | 10-30 min | seconds | $$$ | Critical services |
| Active-active | seconds | zero | $$$$ | Telco, finance, payments |

## The DR plan

A written, tested DR plan. Not a wiki page nobody reads — a real document with:

1. **Roles and responsibilities** — who's on-call, who calls the shots
2. **Decision criteria** — when to invoke DR, who has the authority
3. **Communication plan** — internal, customer, executive
4. **Step-by-step procedures** — "run this command, then this"
5. **Verification** — how to confirm DR worked
6. **Rollback** — what if DR fails partway
7. **Post-mortem** — after the incident

**Test the plan.** Quarterly minimum. Real exercises, not tabletop.

## Tools

| Tool | What it backs up | When to use |
|------|------------------|-------------|
| **Velero** | Cluster state + PVs (CSI/restic) | Most clusters |
| **etcdctl snapshot** | etcd directly | Self-managed clusters |
| **Restic** | File-level backup | When CSI snapshots aren't available |
| **Kopia** | File-level backup with dedup | Modern restic alternative |
| **Cloud-native snapshots** (EBS, GCE PD) | Volume snapshots | When you control the storage |
| **App-level tools** (pg_basebackup, mongodump) | App-consistent data | Critical data stores |
| **Cloud backup services** (AWS Backup, Azure Backup) | Cross-service backup | Multi-service DR |

## Testing backups

**Untested backups aren't backups.** Three things to test:

1. **Restore actually works.** Pick a backup, restore to a test cluster, verify.
2. **Restore is fast enough.** Time it. If RTO is 4 hours, you have 4 hours to restore.
3. **Restore is complete.** All PVs restored, all ConfigMaps present, all RBAC intact. Easy to miss something.

**Test procedure:**

```bash
# 1. create a test cluster (or use a dev cluster)
kind create cluster --name dr-test
# or
eksctl create cluster --name dr-test

# 2. install Velero
velero install ...

# 3. restore
velero restore create --from-backup latest-prod-backup

# 4. verify
kubectl get all -A
kubectl get pvc -A
# (compare with what you expect)

# 5. test applications
# are the apps actually working? do they have data?
```

**Quarterly minimum.** After any major change (new app, new storage, new region), test again.

## Recovery time vs recovery point

The two numbers are independent. You can have:

- **Low RTO, high RPO** — fast failover but lose data (e.g., async replication)
- **High RTO, low RPO** — slow failover but no data loss (e.g., sync replication, slow restore)
- **Low RTO, low RPO** — best of both, expensive (active-active sync)
- **High RTO, high RPO** — cheap, but you lose customers

The cost goes up exponentially as you push both down. **Match the targets to the workload:**

- **Payments** — low RPO (data loss = money loss)
- **User-facing API** — low RTO (downtime = revenue loss)
- **Internal tools** — moderate RTO/RPO
- **Dev/staging** — high RTO/RPO acceptable

## Common gotchas

* **etcd snapshots contain secrets in plaintext.** Encrypt the backup at rest.
* **Velero backups aren't app-consistent.** For databases, use the app's own backup mechanism.
* **RPO of 0 is hard.** Even sync replication has a few ms of lag.
* **RTO of 0 is impossible.** At least DNS propagation takes seconds.
* **Cloud-managed control plane is HA, but data plane is yours.** EKS recovers the control plane. Your workloads, your problem.
* **Backup encryption key is not the same as cluster encryption key.** If you lose the cluster, you still have the key (in a separate vault).
* **Cross-region replication is not a substitute for proper backup.** Replicated data with corruption = corruption in both regions. Have a real backup.
* **Ransomware doesn't care about replication.** If your cluster is encrypted by attackers, replicated data is too. Have an offline/air-gapped backup.
* **GitOps and DR work together.** Git is the source of truth. If the cluster is gone, `kubectl apply` from git rebuilds.
* **Testing DR takes the cluster offline.** Use a non-prod cluster or a test environment.
* **DNS failover isn't instant.** TTLs matter. Set them appropriately.
* **The 3am call:** you need people who know the DR plan. Document it. Train them.

## A worked example

**Company:** SaaS product, 1000 customers, hosted on EKS.
**RTO target:** 1 hour.
**RPO target:** 15 minutes.

**Architecture:**

```
us-east-1 (primary)                    us-west-2 (DR)
  ┌──────────────────┐                  ┌──────────────────┐
  │  EKS cluster     │                  │  EKS cluster     │
  │  (full prod)     │                  │  (pilot light)   │
  │                  │                  │  - control plane │
  │  App pods        │  ─── route53 ──> │  - 0 app pods    │
  │  RDS postgres    │                  │  - read replica  │
  │  ElastiCache     │                  │    of RDS        │
  └──────────────────┘                  └──────────────────┘
         │                                     ▲
         │           ┌──────────┐              │
         └────S3────>│  backups │<─────────────┘
                     │  bucket  │
                     │  +Velero │
                     └──────────┘
```

**Backups:**

- **RDS:** automated snapshots every 5 min, cross-region replica
- **EBS:** daily snapshots, copy to us-west-2
- **Cluster state:** Velero, every 6 hours, to S3 with cross-region replication
- **Object storage:** S3 cross-region replication, 15-min lag

**Failover procedure:**

1. **Detect** (0-5 min) — Route53 health check fails
2. **Confirm** (5-10 min) — on-call confirms outage
3. **Promote** (10-15 min) — promote RDS read replica, update Route53 to us-west-2
4. **Scale up** (15-30 min) — Karpenter adds nodes in us-west-2, GitOps pulls manifests
5. **Verify** (30-45 min) — smoke tests pass
6. **Communicate** — internal Slack, customer status page
7. **Total:** 45 min, within 1-hour target

**Data loss:** up to 15 minutes (RDS replication lag, S3 lag, Velero window).

**Test:** every 3 months, do a real failover. Game day with engineering observing.

## The "day 0" backup hygiene

Set up backups before you need them. The first 90 days of any new cluster should include:

- [ ] etcd snapshot automation (or trust cloud-managed)
- [ ] Velero installed and a daily schedule running
- [ ] S3 (or equivalent) bucket with versioning + cross-region replication
- [ ] Restore test in a sandbox cluster
- [ ] Runbook for restore (with the actual commands)
- [ ] On-call knows where the backups are and how to use them

## Backup the backup's backup

**The 3-2-1 rule:**
- 3 copies of data
- 2 different storage types
- 1 offsite (different region, different cloud, or air-gapped)

```
Production cluster
    ↓
Velero backup → S3 (region 1)
                       ↓
                  Cross-region replication → S3 (region 2)
                                              ↓
                                          Cold storage (Glacier)
```

**For ransomware:** air-gapped backups. A copy that can't be reached from the network. AWS S3 Object Lock, Azure Blob immutable storage, GCP locked buckets.

## Application-level backup patterns

Different apps need different backup approaches.

### Relational databases (Postgres, MySQL)

```bash
# postgres — logical backup
pg_dump -U user -h db.example.com dbname > backup-$(date +%Y%m%d).sql

# postgres — physical backup (faster, larger)
pg_basebackup -U user -h db.example.com -D /backup/base-$(date +%Y%m%d) -Ft -z -P

# restore
pg_restore -U user -h db.example.com -d dbname backup.dump
```

**For cloud-managed:** use the cloud's built-in. RDS automated backups, point-in-time recovery, cross-region replicas.

### NoSQL (MongoDB, Cassandra)

```bash
# mongodb
mongodump --uri="mongodb://user:pass@host:27017/dbname" --out=/backup/mongo-$(date +%Y%m%d)

# mongodb — replica set backup (oplog-based for point-in-time)
mongodump --uri="mongodb://..." --oplog

# restore
mongorestore --uri="mongodb://user:pass@host:27017" /backup/mongo-20240115
```

### Object storage (S3, GCS, Azure Blob)

```bash
# aws
aws s3 sync s3://my-bucket s3://my-backup-bucket --delete

# or
aws s3api put-bucket-replication --bucket my-bucket --replication-configuration file://replication.json
```

**For 1PB+ datasets:** use AWS Snowball, Azure Data Box, or GCP Transfer Appliance. Or set up cross-region replication with versioning.

### Message queues (Kafka, RabbitMQ)

```bash
# kafka
kafka-backup --bootstrap-server kafka:9092 --topics orders --output /backup/kafka-orders

# or use MirrorMaker2 for cross-region replication
```

### Caches (Redis, Memcached)

Caches are typically **not backed up** — they're disposable. But:

```bash
# redis
redis-cli BGSAVE    # background snapshot
# or
redis-cli --rdb /backup/redis-$(date +%Y%m%d).rdb
```

If your cache contains critical data, you have a design problem. Move it to a database.

### Kubernetes resources (CRDs, etcd)

Velero, etcd snapshots.

### Configurations (Terraform, Helm, manifests)

These should be in **git**, not in backups. But for the cluster state, Velero.

## Backup verification

The most important part of backups: **verifying they work.**

```bash
# 1. restore a recent backup to a test cluster
kind create cluster --name backup-test
velero install ...
velero restore create --from-backup latest-prod
# (or just etcd restore)

# 2. verify the data
kubectl get all -A
# (compare with expected)
psql -U user -h <restored-db> -c "SELECT count(*) FROM orders"
# (compare with expected count)

# 3. time the restore
time velero restore create --from-backup latest-prod
# is it within RTO?

# 4. test data integrity
# - row counts match?
# - indexes are there?
# - foreign keys are intact?
# - the app can read/write the data?
```

**Quarterly restore tests.** After any major change (new app, new storage, new region), test again.

## Backup encryption

Backups contain secrets. Encrypt them.

**At rest:**

```bash
# s3 default encryption
aws s3api put-bucket-encryption \
  --bucket my-backups \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# cross-region replication with encryption
aws s3api put-bucket-replication ...
```

**In transit:**

```bash
# s3 enforces HTTPS by default
# but if you're using custom endpoints, verify TLS
```

**With your own key (KMS):**

```bash
# encrypt with a specific KMS key
aws s3 cp backup.tar.gz s3://my-backups/ \
  --sse aws:kms \
  --sse-kms-key-id arn:aws:kms:us-east-1:xxx:key/yyy
```

**For the worst case (key compromised):** the backup is still encrypted. If you lose the key, the backup is unreadable. So:

- **Rotate KMS keys regularly** (auto-rotation, 1 year)
- **Keep old keys enabled** for decryption of historical data
- **Test key rotation** — old backups must still be readable

## Backup retention policies

How long do you keep backups?

| Tier | Daily | Weekly | Monthly | Yearly |
|------|-------|--------|---------|--------|
| **Tier 0** (critical) | 7 days | 4 weeks | 12 months | 7 years |
| **Tier 1** (production) | 7 days | 4 weeks | 6 months | 2 years |
| **Tier 2** (internal) | 3 days | 2 weeks | 3 months | None |
| **Tier 3** (dev) | 1 day | None | None | None |

**Compliance mandates** may require specific retention (HIPAA: 6 years, PCI-DSS: 1 year, SOX: 7 years).

## Common gotchas (deep)

* **The "primary" bucket isn't backed up if it's encrypted with a key that you lose.** Multiple encryption paths.
* **Cross-region replication has eventual consistency.** A write to us-east-1 may not be in us-west-2 for seconds. Test the lag.
* **S3 Glacier is cheap but slow to restore.** Hours to days. Don't use it for active DR.
* **Air-gapped backups are the only true ransomware protection.** Replicated data is also encrypted by the attacker.
* **The restore runbook should be in a different place from the cluster.** If the cluster is gone, you still need the runbook. (git is fine.)
* **Restoring from cold storage is slow.** Plan for hours.
* **Velero's restic integration is slow for large PVs.** Use CSI snapshots where possible.
* **Application-level backup requires app cooperation.** If the app is down, you can't back it up.
* **Database backups during heavy load are slow.** Schedule for off-peak.
* **Network bandwidth for backup/restore is finite.** Don't run full backups during business hours.
* **The restore target cluster must have the same CRDs.** If you restore a workload with a CRD that's not installed, the restore "succeeds" but the resource is broken.
* **Backup retention doesn't survive "delete before X" policies.** Test your lifecycle policies.
* **Encrypted backups need their encryption key.** If the key is in the cluster, restoring the cluster is hard. Move keys to a separate store.
* **A full restore is not the same as an upgrade.** Restoring an old backup to a new cluster may need version migrations.

## The decision matrix

**For a small cluster (1-5 nodes, 50 namespaces):**

- Cloud-managed etcd (or daily etcdctl snapshot)
- Velero, daily schedule, 30-day retention
- S3 with cross-region replication
- S3 Glacier for monthly backups, 1-year retention
- Quarterly restore test

**For a large cluster (50+ nodes, 500+ namespaces):**

- Cloud-managed etcd + Velero, hourly
- Per-app backup for critical data stores
- Multi-region active-passive
- DR runbook, tested quarterly
- Dedicated backup operator

**For mission-critical (regulated, $1B+ revenue):**

- Active-active multi-region
- App-level backups for everything
- Air-gapped backup tier
- Continuous data replication (RPO seconds)
- 24/7 incident response team
- DR tested monthly

## Incident response playbook

When disaster strikes:

1. **Detect** (0-15 min) — alerts fire, users complain, monitoring goes red
2. **Confirm** (15-30 min) — on-call confirms outage is real, not a false alarm
3. **Declare DR** (30-45 min) — incident commander, comms channel
4. **Decide** (45-60 min) — invoke DR or try to fix in place
5. **Execute** (1-4 hours) — follow the runbook
6. **Verify** (after restore) — smoke tests, data integrity checks
7. **Communicate** — internal, customer, executive
8. **Post-mortem** — within 1 week

**The 30-minute decision point:** if you can't fix in 30 min, invoke DR. Don't try to fix for 4 hours, then discover you needed DR.

## See also

* [[Kubernetes/guides/non-functional/backup-restore|backup-restore]] — day-to-day backup tooling
* [[Kubernetes/guides/non-functional/high-availability|high-availability]] — preventing disasters
* [[Kubernetes/guides/non-functional/chaos-engineering|chaos-engineering]] — testing the plan
* [[Kubernetes/guides/non-functional/cost-optimization|cost-optimization]] — DR has a cost

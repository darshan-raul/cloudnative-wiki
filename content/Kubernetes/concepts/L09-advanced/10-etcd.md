# etcd

>*"https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/"*

etcd is the **distributed key-value store that backs Kubernetes**. Every object you create — Pod, ConfigMap, Secret, CRD — lives in etcd. The API server is the only thing that talks to it; the kubelet and controllers talk to the API server, which talks to etcd.

## Table of Contents

1. [What etcd actually is](#1-what-etcd-actually-is)
2. [The architecture diagram](#2-the-architecture-diagram)
3. [How Kubernetes uses etcd](#3-how-kubernetes-uses-etcd)
4. [Key structure and the registry layout](#4-key-structure-and-the-registry-layout)
5. [Member management](#5-member-management)
6. [Quorum and availability](#6-quorum-and-availability)
7. [Health checks and diagnostics](#7-health-checks-and-diagnostics)
8. [Backups: snapshot save and restore](#8-backups-snapshot-save-and-restore)
9. [Defragmentation](#9-defragmentation)
10. [Compaction and history retention](#10-compaction-and-history-retention)
11. [Authentication and RBAC](#11-authentication-and-rbac)
12. [TLS setup](#12-tls-setup)
13. [Snapshots and the WAL](#13-snapshots-and-the-wal)
14. [Performance tuning](#14-performance-tuning)
15. [Object size limits](#15-object-size-limits)
16. [Encryption at rest](#16-encryption-at-rest)
17. [Monitoring etcd](#17-monitoring-etcd)
18. [Disaster recovery](#18-disaster-recovery)
19. [Common failure modes](#19-common-failure-modes)
20. [etcd in different deployment modes](#20-etcd-in-different-deployment-modes)
21. [When etcd is the bottleneck](#21-when-etcd-is-the-bottleneck)
22. [Gotchas](#22-gotchas)

---

### 1. What etcd actually is

etcd is a **distributed, consistent, strongly consistent key-value store** based on the Raft consensus algorithm.

Key properties:
- **Consistent**: reads are linearizable (all clients see the same data at the same time)
- **Fault-tolerant**: can tolerate N member failures in a 2N+1 cluster
- **Strongly consistent**: writes are only acknowledged after quorum agrees
- **Ordered**: writes have a total order — you can reconstruct history
- **Versioned**: every key change creates a new generation/version

This is not a general-purpose database. It's a control plane store — and that constraint shapes everything about how Kubernetes uses it.

---

### 2. The architecture diagram

```
┌──────────────────────────────────────────────────────────┐
│                     etcd cluster                        │
│                    (3 or 5 members)                    │
│                                                          │
│   ┌──────────┐   ┌──────────┐   ┌──────────┐           │
│   │ Member 1 │◄─►│ Member 2 │◄─►│ Member 3 │           │
│   │ (Leader) │   │          │   │          │           │
│   └────┬─────┘   └────┬─────┘   └──────────┘           │
│        │              │    Raft consensus (WAL)        │
└────────┼──────────────┼────────────────────────────────┘
         │              │
         ▼              ▼
┌─────────────────────────────────────────────────────┐
│                   kube-apiserver                     │
│              (the only thing that talks to etcd)      │
│              (except etcd backup/restore tools)       │
└─────────────────────┬───────────────────────────────┘
                      │
        ┌─────────────┼─────────────────┐
        ▼             ▼                  ▼
    kubelet      controllers       kubelet
    (node 1)     (in-cluster)      (node 2)
```

The kube-apiserver is a **single Raft client**. It connects to the etcd cluster as one logical client. etcd handles the distribution, consensus, and replication.

---

### 3. How Kubernetes uses etcd

Kubernetes uses etcd as a **dumb store with rich objects**:

```
kubectl apply -f deployment.yaml
  ↓
kube-apiserver serializes Deployment to JSON
  ↓
kube-apiserver issues a gRPC call to etcd:
  - key: /registry/deployments/default/my-app
  - value: <JSON bytes>
  - version: (auto-assigned by etcd)
  - lease: (for TTL'd keys)
  ↓
etcd writes to WAL, replicates to quorum, returns
```

All reads go through the API server too (except some read-only watch requests). etcd never sees "kubectl get pods" — it sees range requests for `/registry/pods/...`.

---

### 4. Key structure and the registry layout

Keys are hierarchical and include the API group, namespace, and resource name:

```
/registry/deployments/default/my-app
/registry/configmaps/kube-system/coredns
/registry/secrets/default/db-credentials
/registry/statefulsets.apps/production/postgres
/registry/customresourcedefinitions/apiextensions.k8s.io/cronjobs.stable.example.com
/registry/persistentvolumes/pv-001
/registry/namespaces/production
/registry/clusterrolebindings.rbac.authorization.k8s.io/cluster-admin
```

The **value** is a protobuf-encoded Kubernetes object (not JSON by default, though gRPC-gateway can return JSON).

```bash
# Get the raw value (requires etcdctl with proto validation off)
ETCDCTL_API=3 etcdctl get /registry/deployments/default/my-app \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt

# With hex output to see the protobuf framing
ETCDCTL_API=3 etcdctl get /registry/deployments/default/my-app -w=hex
```

---

### 5. Member management

```bash
# List members
ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# ID        Status   Name       Peer Addresses            Client Addresses
# abc123    running  etcd-1    https://10.0.0.1:2380    https://10.0.0.1:2379
# def456    running  etcd-2    https://10.0.0.2:2380    https://10.0.0.2:2379
# ghi789    running  etcd-3    https://10.0.0.3:2380    https://10.0.0.3:2379

# Add a new member
ETCDCTL_API=3 etcdctl member add etcd-4 \
  --peer-urls=https://10.0.0.4:2380 \
  --endpoints=https://127.0.0.1:2379

# Returns the command to run on the new node:
# ETCDCTL_API=3 etcdctl member add abc123 --peer-urls=...
# Then start etcd on the new node with that member ID

# Remove a member
ETCDCTL_API=3 etcdctl member remove abc123 \
  --endpoints=https://127.0.0.1:2379

# Promote a learner to voting member (etcd 3.5+)
ETCDCTL_API=3 etcdctl member promote abc123 \
  --endpoints=https://127.0.0.1:2379
```

---

### 6. Quorum and availability

| Cluster size | Tolerated failures | Quorum (needs) |
|-------------|-------------------|----------------|
| 1 | 0 | 1 |
| 3 | 1 | 2 |
| 5 | 2 | 3 |
| 7 | 3 | 4 |

**Always use odd numbers.** A 3-member and 4-member cluster have the same write quorum (2/3 and 3/4 ≈ 2/3), but 4 has more failure points.

```
Loss of quorum:
  - Writes STOP (cluster becomes read-only or rejects all writes)
  - Reads continue (from any healthy member)
  - Raft commits nothing until quorum restored
```

The default in kubeadm is **3 stacked** (etcd runs on same nodes as kube-apiserver) for dev, and **3 external** for prod.

---

### 7. Health checks and diagnostics

```bash
# Basic health check
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# endpoint is healthy: true
# endpoint is active: true
# endpoint is available: true

# Check all members
ETCDCTL_API=3 etcdctl --endpoints=$ENDPOINTS endpoint status -w table

# Status output shows:
# +------------------+------------------+---------+---------+
# |     ENDPOINT     |        ID        | STATUS  | LEADER  |
# +------------------+------------------+---------+---------+
# | 10.0.0.1:2379    | abc123           | started | true    |
# | 10.0.0.2:2379    | def456           | started | false   |
# +------------------+------------------+---------+---------+

# Check disk performance
ETCDCTL_API=3 etcdctl check perf \
  --endpoints=https://127.0.0.1:2379

# Check disk latency (should be < 10ms for good perf)
# FAIL: slow disk (25.532ms) — etcd requires fast disks

# View etcd logs (when running as static pod)
kubectl logs -n kube-system etcd-<node-name>
```

---

### 8. Backups: snapshot save and restore

```bash
# Take a snapshot (online, all members can do it)
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snap-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Check snapshot status
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snap-20240611.db -w table

# Restore from snapshot (stops etcd first, creates a new data-dir)
# Used for disaster recovery or cluster migration
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snap-20240611.db \
  --name etcd-1 \
  --initial-cluster etcd-1=https://10.0.0.1:2380,etcd-2=https://10.0.0.2:2380,etcd-3=https://10.0.0.3:2380 \
  --initial-advertise-peer-urls https://10.0.0.1:2380 \
  --initial-cluster-token etcd-cluster \
  --data-dir /var/lib/etcd-restored

# Start etcd with the restored data dir
# Then rejoin other members to the restored cluster
```

**Backup schedule best practice:**
```bash
# Cron job: daily backup + upload to S3
0 3 * * * ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-daily.db \
  --endpoints=$ETCD_ENDPOINTS ... && \
  aws s3 cp /backup/etcd-daily.db s3://my-bucket/etcd/$(date +%Y%m%d).db
```

---

### 9. Defragmentation

Over time, etcd accumulates **free space** from deleted/replaced keys, but the physical file size doesn't shrink. Defragmentation reclaims physical space:

```bash
# Check physical space usage
# ls -lh /var/lib/etcd/member/snap/db
# (the .db file size)

# Defrag a member
ETCDCTL_API=3 etcdctl defrag \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=... --cert=... --key=...

# Defrag all endpoints
ETCDCTL_API=3 etcdctl defrag \
  --endpoints=etcd-1:2379,etcd-2:2379,etcd-3:2379 \
  --cacert=... --cert=... --key=...

# Check space after defrag
# The physical .db file should be smaller (or the same if no fragmentation)
```

Defragmentation is **I/O heavy** — do it during low-traffic windows. It requires briefly pausing writes on that member (but not the full cluster if done member-by-member).

etcd 3.5+ has **automatic defragmentation** enabled by default, but manual defrag is still good practice for very large clusters.

---

### 10. Compaction and history retention

etcd keeps the full history of key changes (for MVCC/linearizable reads). This grows disk usage over time:

```bash
# Check current revision
ETCDCTL_API=3 etcdctl get /registry --endpoints=$ENDPOINT \
  --cacert=... --cert=... --key=... \
  -w json | jq '.header.revision'
# 125000

# Compact to revision 124000 (remove history before r124000)
ETCDCTL_API=3 etcdctl compact 124000 \
  --endpoints=$ENDPOINT --cacert=... --cert=... --key=...

# After compacting, defrag to reclaim the physical space
ETCDCTL_API=3 etcdctl defrag --endpoints=$ENDPOINT ...
```

Kubernetes etcd usually has compaction and defrag handled by the kube-apiserver's etcd quota (default: 2GB), which triggers automatic compaction. But for very large clusters, manual compaction is useful.

---

### 11. Authentication and RBAC

etcd has its own user/role system, but in Kubernetes the kube-apiserver handles all authnz. etcd just needs:

```bash
# In practice, Kubernetes uses certificates for etcd auth:
# kube-apiserver: --etcd-certfile, --etcd-keyfile, --etcd-cafile
# etcd: client certificates on the server side

# If you want etcd-native auth (rare for k8s):
etcdctl user add root
etcdctl user grant-role root root
etcdctl role add my-role
etcdctl role grant-permission my-role readwrite /registry/deployments/
etcdctl auth enable
```

Most Kubernetes clusters **don't enable etcd auth** — they rely on kube-apiserver's TLS cert + network-level access control (etcd port 2379 is not exposed outside the control plane nodes).

---

### 12. TLS setup

In a kubeadm cluster:

```
/etc/kubernetes/pki/etcd/
  ca.crt          — CA for etcd peer and client certs
  server.crt      — server cert for etcd (CN=etcd-hostname)
  server.key
  peer.crt        — cert for etcd peer communication
  peer.key
  healthcheck-client.crt  — for kube-apiserver's etcd health checks
  healthcheck-client.key
```

kube-apiserver connects to etcd with:
```bash
kube-apiserver \
  --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt \
  --etcd-certfile=/etc/kubernetes/pki/etcd/server.crt \
  --etcd-keyfile=/etc/kubernetes/pki/etcd/server.key \
  --etcd-servers=https://10.0.0.1:2379,https://10.0.0.2:2379,https://10.0.0.3:2379
```

etcd members talk to each other with peer certs (separate from client certs).

---

### 13. Snapshots and the WAL

etcd has two key storage concepts:

| | WAL | Snapshot |
|---|---|---|
| **What** | Write-Ahead Log — append-only log of all operations | Point-in-time snapshot of the DB |
| **Purpose** | Durability — survive crashes and replay | Faster recovery, compaction |
| **Location** | `/var/lib/etcd/member/wal/` | `/var/lib/etcd/member/snap/` |
| **Size** | Grows indefinitely (compacted by etcd) | Periodically created |
| **Crash recovery** | Replays WAL on top of last snapshot | |

On a crash, etcd replays the WAL on the last snapshot to reconstruct state. This is why etcd needs fast disk (fsync on every write).

```
Write: WAL append → replicate to quorum → respond → (async) snapshot
Read:  serve from current state (snapshot + WAL replay)
```

---

### 14. Performance tuning

The bottleneck is almost always **disk I/O**. etcd writes are fsynced before acknowledgment.

```bash
# Recommended sysctls for etcd nodes (add to /etc/sysctl.d/99-etcd.conf)

# Increase file descriptor limit
fs.file-max = 16384

# etcd uses a lot of mmap — increase map count
vm.max_map_count = 655300

# Disable swap (etcd MUST NOT swap)
vm.swappiness = 0

# Disk I/O scheduler (for spinning disks — use 'none' for NVMe/SSD)
# echo "none" > /sys/block/sda/queue/scheduler

# Increase read-ahead for etcd disk
blockdev --setra 4096 /dev/sda

# Network: etcd is latency-sensitive, keep it on a low-latency network segment
```

**Storage requirements:**
- SSD/NVMe required for production (IOPS: 5,000+ for a busy cluster)
- Spinning disks will cause write stalls and leader elections
- RAID 0 for capacity/speed (not for availability — etcd handles replication)

---

### 15. Object size limits

| Limit | Default | Applied where |
|-------|---------|---------------|
| Max object size | 1.5 MB | etcd — any single object |
| Max value size | 1.5 MB | etcd key value |
| Max key length | 16 KB | etcd |
| Max WAL entry size | Unlimited | WAL can have huge entries (don't) |

**ConfigMaps and Secrets are subject to the 1.5MB limit.** Large ConfigMaps (>1MB) will cause API server slowness. For large data, use a PV or external storage.

---

### 16. Encryption at rest

By default, Secrets in etcd are **base64-encoded, not encrypted**. Anyone with etcd access can read them.

```bash
# Enable encryption at rest
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    - configmaps
    providers:
    - aescbc:
        keys:
        - name: key1
          # 32-byte key, base64-encoded
          secret: <base64-32-byte-secret>
    - identity: {}   # passthrough for already-encrypted data
```

```bash
# kube-apiserver flag
--encryption-provider-config=/etc/kubernetes/encryption-config.yaml
```

Then restart kube-apiserver. **Existing secrets are not automatically encrypted** — you need to run a re-encryption:

```bash
# Force all secrets to be re-written with encryption
kubectl get secrets --all-namespaces -o json | \
  kubectl replace -f -
```

Encryption at rest **does not protect data in transit** — that's TLS.

---

### 17. Monitoring etcd

Key metrics (exposed at `https://<etcd>:2379/metrics`):

| Metric | What it tells you |
|--------|------------------|
| `etcd_server_leader_changes_total` | Leader elections — should be near zero |
| `etcd_mvcc_db_total_size_in_bytes` | Physical DB size |
| `etcd_mvcc_db_total_size_in_bytes_in_use` | Actual data size (after defrag) |
| `etcd_mvcc_db_compaction_keys_total` | Compaction operations |
| `etcd_disk_wal_fsync_duration_seconds` | WAL fsync latency — should be <10ms |
| `etcd_disk_backend_commit_duration_seconds` | BoltDB commit latency |
| `etcd_network_peer_round_trip_time_seconds` | Peer latency — high = network issue |
| `etcd_server_has_failed_requests_total` | Failed requests — indicates issues |

Prometheus scrape config for etcd:
```yaml
- job_name: etcd
  static_configs:
    - targets: ['10.0.0.1:2379']
  scheme: https
  tls_config:
    ca_file: /etc/kubernetes/pki/etcd/ca.crt
    cert_file: /etc/kubernetes/pki/etcd/healthcheck-client.crt
    key_file: /etc/kubernetes/pki/etcd/healthcheck-client.key
```

---

### 18. Disaster recovery

**Scenario: losing one member in a 3-node cluster**

```bash
# 1. Identify the failed member
ETCDCTL_API=3 etcdctl member list

# 2. Remove the failed member
ETCDCTL_API=3 etcdctl member remove <failed-member-id> \
  --endpoints=<working-member>:2379

# 3. Add a new member
ETCDCTL_API=3 etcdctl member add etcd-new \
  --peer-urls=https://10.0.0.4:2380 \
  --endpoints=<working-member>:2379

# 4. On the new node, start etcd with the new member info
# The etcd static pod will pick up the new config via kubeadm
```

**Scenario: losing quorum (2 of 3 members down)**

1. Stop kube-apiserver on all nodes (prevent writes)
2. Identify the most up-to-date member (latest revision)
3. Use `snapshot restore` on the most up-to-date member's data
4. Start a new single-node cluster
5. Add back remaining members

This is why backups matter — and why quorum is critical.

---

### 19. Common failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `etcd cluster is unavailable` | Lost quorum | Restore from snapshot |
| Write timeouts | Disk too slow (HDD, fsync lag) | Switch to SSD, tune disk |
| `etcd: request is too large` | ConfigMap/Secret > 1.5MB | Split the data |
| High `etcd_server_leader_changes_total` | Network issues between nodes | Check network, reduce load |
| Member shows `unstarted` | Peer TLS misconfigured | Verify certs, restart etcd |
| `mvcc: database space exceeded` | DB quota hit (default 2GB) | Defrag, increase quota |
| Snapshot restore fails | Snapshot corrupted or wrong version | Use `etcdctl snapshot status` to verify |
| `etcd: invalid credentials` | Cert expired or misconfigured | Renew certs (12 months typical) |

```bash
# Space exceeded: check quota
ETCDCTL_API=3 etcdctl endpoint status \
  --endpoints=$ENDPOINT \
  -w json | jq '.[0].Status.dbSize'
# vs
ETCDCTL_API=3 etcdctl endpoint status \
  --endpoints=$ENDPOINT \
  -w json | jq '.[0].Status.dbSizeInUse'

# Increase quota (in bytes, default 2GB = 2*1024*1024*1024)
ETCDCTL_API=3 etcdctl quota increase 8589934592 \
  --endpoints=$ENDPOINT

# Or via API server flag (if managed):
# --etcd-quota-backend-bytes=8589934592
```

---

### 20. etcd in different deployment modes

| Mode | Description | Where |
|------|-------------|-------|
| **Stacked** | etcd runs as static pod on same nodes as control plane | kubeadm default for dev |
| **External** | etcd on dedicated nodes | Production kubeadm |
| **Managed** | Cloud provider runs etcd (EKS, GKE, AKS) | EKS/GKE/AKS |
| **Stretched** | etcd across availability zones | HA across AZs |

For managed Kubernetes (EKS, GKE, AKS), you **never touch etcd** — the cloud provider manages it. For self-managed (kubeadm, kops), you're responsible.

---

### 21. When etcd is the bottleneck

Signs etcd is slowing down the API server:

```bash
# API server logs: "etcd: request is taking too long"
# kubectl get pods: operations taking 5+ seconds
# etcd metrics: high disk fsync latency

# Check etcd latency
# Should be < 10ms for 99th percentile
curl -s https://<etcd>:2379/metrics | grep etcd_disk_backend_commit_duration_seconds
```

Solutions:
1. **Fast disk (NVMe SSD)** — the single biggest improvement
2. **Defragment** — reclaim physical space after deletions
3. **Reduce object count** — fewer ConfigMaps/Secrets helps
4. **Increase quota** — if the 2GB default is too small
5. **Read replicas** — etcd 3.3+ supports read-only replicas (not for write scaling)
6. **Upgrade etcd** — newer versions have performance improvements

---

### 22. Gotchas

* **etcd is the cluster.** Lose all members = lose all cluster state. Back up regularly.
* **SSD/NVMe is mandatory for production.** A spinning disk cannot handle etcd's fsync requirements.
* **`snapshot restore` creates a new data dir** — never use the old data dir after restoring.
* **The 1.5MB object limit is enforced by etcd**, not the API server. Big ConfigMaps hit the etcd error before the API server can reject them.
* **Encryption at rest is opt-in.** Secrets are base64-encoded plaintext in etcd by default.
* **Changing encryption keys requires a re-encryption procedure** — it's not automatic.
* **Defragmentation is necessary** even though etcd has automatic compaction. Check physical DB size vs actual data size.
* **The WAL is append-only** and can grow large if the cluster is write-heavy and compaction is delayed.
* **etcd defrag is member-by-member** — you can defrag one member without affecting the cluster.
* **Cross-cluster etcd is not supported.** Don't try to share etcd between clusters.
* **The API server is a single Raft client.** etcd sees one client regardless of how many API server replicas you have.
* **etcd 3.5 auto-defrags**, but the compaction happens at the revision level, not the space level — manual defrag after bulk deletes is still useful.
* **`etcdctl endpoint health`** checks connectivity, not data integrity. For integrity, use `etcdctl endpoint status`.

---

## See also

* [[Kubernetes/concepts/L09-advanced/09-pause-container|Pause Container]] — the infra container in every Pod
* [[Kubernetes/concepts/L01-architecture/02-high-availability|HA Topology]] — where etcd fits in an HA cluster
* [[Kubernetes/concepts/L04-services-networking/03-dns|DNS]] — how Pods find each other via Services

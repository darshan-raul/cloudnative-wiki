# etcd

*"https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/"*

etcd is the **distributed key-value store that backs the Kubernetes API**. Every object you create — Pod, ConfigMap, Secret, CRD — lives in etcd. The API server is the only thing that talks to it (in normal operation); the kubelet and controllers talk to the API server, which talks to etcd.

## What it actually is

* A **distributed, consistent key-value store** based on the Raft consensus algorithm
* Stores all cluster state
* **The single source of truth** — if etcd is gone, the cluster is gone
* Highly available (3 or 5 members) in production; single member for dev

```
                ┌──────────┐
                │  etcd    │  ← the truth
                │  cluster │     (3 or 5 members, Raft)
                └────┬─────┘
                     │
                ┌────┴─────┐
                │  kube-   │  ← the only thing that talks to etcd
                │ apiserver│
                └────┬─────┘
                     │
       ┌─────────────┼─────────────┐
       │             │             │
   kubelet       controllers    your code
```

## How objects are stored

Keys look like:

```
/registry/pods/default/my-pod
/registry/configmaps/kube-system/coredns
/registry/customresourcedefinitions/apiextensions.k8s.io/...
```

The value is a serialized protobuf-encoded object. `kubectl get` parses this back into YAML/JSON for you.

## Operations

### Health check

```bash
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

### List members

```bash
ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=... --cert=... --key=...
```

### Backup

```bash
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snap.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=... --cert=... --key=...
```

The snapshot is a single file you can store anywhere (S3, etc.) and use to restore the cluster. **Back up etcd regularly** — it's the cluster.

### Restore

```bash
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snap.db \
  --name m1 \
  --initial-cluster m1=https://10.0.0.1:2380,m2=https://10.0.0.2:2380,m3=https://10.0.0.3:2380 \
  --initial-advertise-peer-urls https://10.0.0.1:2380 \
  --data-dir /var/lib/etcd-restored
```

This produces a data dir; you'd then point etcd at it (or use it in a fresh cluster).

### Wipe a namespace (manual cleanup)

```bash
# In an emergency: delete all keys for a namespace
ETCDCTL_API=3 etcdctl del --prefix /registry/pods/default
```

This is destructive. Don't do it casually.

## Quorum and availability

* **3 members** — can survive 1 failure (2 of 3 needed for quorum)
* **5 members** — can survive 2 failures (3 of 5 needed for quorum)
* **Always use odd numbers.** 4 members have the same quorum as 3 (3 of 4) but more failure modes.

If etcd loses quorum, **the cluster stops accepting writes** but reads continue. This is by design — Raft prioritizes consistency over availability. The API server returns 503s.

## etcd in different deployments

* **Self-managed (kubeadm, k8s-the-hard-way)** — you run etcd as a separate set of pods (in `kube-system` as `etcd-<member>`), or as systemd units
* **Managed (EKS, GKE, AKS)** — etcd is hidden; you don't manage it. The cloud provider runs it.
* **Stacked control plane** — etcd runs on the same nodes as the kube-apiserver (kubeadm default)
* **External etcd** — etcd runs on separate nodes from the control plane (more HA, more ops)

EKS, GKE, AKS all run external etcd. You never touch it.

## Performance characteristics

* **Slow on large values.** Single object size limit is 1.5 MB by default. ConfigMaps and Secrets can't exceed that. **Don't put big blobs in ConfigMaps.**
* **Slow on many keys.** ~10,000 keys per second per member is realistic. Past that, you're bottlenecked.
* **Watches are cheap** — this is why k8s controllers can watch the API efficiently.
* **Disk is the bottleneck** — etcd writes are fsynced. **NVMe SSDs are basically required** for production.

## Encryption at rest

By default, Secrets in etcd are **base64-encoded, not encrypted**. Anyone with etcd access can read them.

Enable encryption:

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
        - name: key1
          secret: <base64-32-byte-key>
    - identity: {}
```

Then pass `--encryption-provider-config` to the kube-apiserver. This encrypts Secret data at rest. **It does not protect data in flight** — that's TLS to the apiserver.

## Gotchas

* **etcd is the cluster.** If you lose all etcd members, you lose the cluster. **Back it up.**
* **Don't run etcd on a spinning disk.** SSDs are required. Fsync latency directly affects API server write latency.
* **etcdctl is the only direct way to talk to etcd.** The API server is what everyone else uses. Don't try to share etcd between two API servers.
* **The `1.5 MB` object size limit is real.** Hit it with a big ConfigMap or a large Secret, and you'll get an "object too large" error. Move big data to a PV or external store.
* **etcd defragments over time.** Long-running clusters should be defragmented periodically (`etcdctl defrag`) — but it requires brief downtime of one member at a time.
* **The encryption-at-rest config is read at startup.** Changing the key file doesn't rotate keys; you have to follow a re-encryption procedure.
* **Cross-cluster etcd operations are unsupported.** Don't try to share etcd between clusters.
* **etcd logs are useful for forensics.** When something weird happens, etcd's log often tells you which object changed when.
* **Don't use etcd as a general-purpose DB.** It's a control plane store. Even if the API allows it (via CRDs), don't put millions of rows there.

## When you'd actually touch etcd

* You're running kubeadm or self-managed
* You're taking backups (you should, always)
* You're investigating "the cluster forgot this object" — start at etcd, not the apiserver
* You're migrating / restoring a cluster
* You're debugging performance (the bottleneck is almost always etcd disk)

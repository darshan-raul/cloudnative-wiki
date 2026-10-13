---
title: "Lab CKA-05 — etcd Backup & Restore"
tags: [kubernetes, labs, cka, etcd, backup, restore, etcdctl, etcdutl]
date: 2026-10-13
description: "Take an etcd snapshot with etcdctl, restore it with etcdutl into a new data directory, and repoint the etcd static Pod at it."
---

# Lab CKA-05 — etcd Backup & Restore

Take a snapshot of etcd, change the cluster, then roll the whole cluster state back to the snapshot. Theory is in [[Kubernetes/concepts/L09-advanced/10-etcd|etcd in Kubernetes]] and [[Kubernetes/guides/non-functional/backup-restore|Backup and Restore]].

Tested 2026-10-13 on kind v0.33.0 with Kubernetes v1.37.0 (etcd 3.7.0), sections 1 to 5. Section 6 was run earlier on v1.35.0.

Verified on `kind` v0.31 with Kubernetes v1.35.0 and etcd 3.6.6.

> [!warning] etcd 3.6 moved restore to etcdutl
> Older guides restore with `etcdctl snapshot restore`. From etcd 3.6, `etcdctl` only keeps `snapshot save`. `snapshot restore` and `snapshot status` live in `etcdutl`. Know both tools.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**.
- A shell on the control plane node. In the exam this is `ssh`; on `kind` it is:

```bash
docker exec -it k8s-lab-control-plane bash
```

Commands marked **node** run in that shell. Commands marked **host** run where your `kubectl` is.

### Put the etcd tools on the node

Exam nodes have `etcdctl` and `etcdutl` installed. A `kind` node does not, but both binaries are in the etcd image already unpacked on disk:

```bash
# node
cp "$(find /var/lib/containerd -name etcdctl -type f | head -1)" /usr/local/bin/
cp "$(find /var/lib/containerd -name etcdutl -type f | head -1)" /usr/local/bin/
etcdctl version
etcdutl version
```

```
etcdctl version: 3.7.0
API version: 3.7
etcdutl version: 3.7.0
API version: 3.7
```

Kubernetes 1.37 ships etcd 3.7; 1.35 and 1.36 ship 3.6. The commands in this lab are the same on both. `etcdctl` talks to a running server over the network; `etcdutl` works on files and needs no server.

---

## 2. Find the Connection Details

Never guess certificate paths. Read them from the etcd static Pod manifest:

```bash
# node
grep -E 'listen-client-urls|cert-file|key-file|trusted-ca-file|data-dir' /etc/kubernetes/manifests/etcd.yaml
```

| etcd flag              | `etcdctl` flag | Value on a kubeadm cluster            |
| :--------------------- | :------------- | :------------------------------------ |
| `--listen-client-urls` | `--endpoints`  | `https://127.0.0.1:2379`              |
| `--trusted-ca-file`    | `--cacert`     | `/etc/kubernetes/pki/etcd/ca.crt`     |
| `--cert-file`          | `--cert`       | `/etc/kubernetes/pki/etcd/server.crt` |
| `--key-file`           | `--key`        | `/etc/kubernetes/pki/etcd/server.key` |
| `--data-dir`           | none           | `/var/lib/etcd`                       |

Save typing for the rest of the lab:

```bash
# node
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key

etcdctl endpoint health
etcdctl member list -w table
```

In the exam, pass the four flags explicitly if the task gives different paths.

---

## 3. Take a Snapshot

Create something to prove the backup contains it:

```bash
# host
kubectl create namespace etcd-lab
kubectl -n etcd-lab create configmap keep-me --from-literal=state=saved
```

```bash
# node
etcdctl snapshot save /opt/etcd-snapshot.db
etcdutl snapshot status /opt/etcd-snapshot.db -w table
```

```
Snapshot saved at /opt/etcd-snapshot.db
+----------+----------+------------+------------+---------+
|   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE | VERSION |
+----------+----------+------------+------------+---------+
| f6aa7726 |     7077 |        708 |     7.9 MB |   3.7.0 |
+----------+----------+------------+------------+---------+
```

The status table shows a hash, the revision, the key count and the size. A snapshot that reports zero keys is not a backup. `etcdctl snapshot status` and `etcdctl snapshot restore` no longer exist (removed in etcd 3.6); use `etcdutl` for both.

Now make a change that the restore should undo:

```bash
# host
kubectl -n etcd-lab create configmap lose-me --from-literal=state=after-snapshot
kubectl -n etcd-lab get configmap
```

---

## 4. Restore

### Step 1: Stop the control plane

The kubelet runs whatever is in the static Pod directory. Moving the manifests out stops the components cleanly:

```bash
# node
mkdir -p /root/manifests-off
mv /etc/kubernetes/manifests/*.yaml /root/manifests-off/
until [ -z "$(crictl ps -q --name 'etcd|kube-apiserver')" ]; do sleep 2; done
crictl ps --name 'etcd|kube-apiserver'
```

The loop returns when both containers have stopped, and the last command prints only a header.

### Step 2: Restore into a new directory

```bash
# node
etcdutl snapshot restore /opt/etcd-snapshot.db --data-dir /var/lib/etcd-restore \
  --bump-revision 1000000000 --mark-compacted
ls /var/lib/etcd-restore
```

Restore always writes to a **new, empty** directory. It does not touch the running data directory, which is why step 3 exists.

> [!note] Why the revision is bumped
> Every Kubernetes object carries a `resourceVersion`, which is an etcd revision. Restoring a snapshot moves etcd **back** to an older revision, but controllers, operators and kubelets that kept running still hold caches at the newer one. They can then miss changes or act on objects that no longer exist. `--bump-revision` moves the restored store's revision far ahead of anything a client has seen, and `--mark-compacted` (required with it) makes every older watch fail and re-list. The etcd project recommends this pair whenever a restore serves Kubernetes. A plain `etcdutl snapshot restore <file> --data-dir <dir>` also restores the data and is what an exam task usually asks for; add the two flags if the task or the documentation says to.

> [!note] One member here, several in production
> This cluster has a single etcd member, so the defaults are enough. For a multi-member cluster you restore the **same snapshot once per member**, each into its own data directory with that member's `--name`, `--initial-cluster`, `--initial-cluster-token` and `--initial-advertise-peer-urls`, and start them together as a new cluster. Restoring only one member of a running cluster does not work.

### Step 3: Point etcd at the restored data

In `/root/manifests-off/etcd.yaml`, change the `hostPath` of the `etcd-data` volume. Leave the `--data-dir` flag and the `volumeMounts` alone; they are paths inside the container.

```yaml
volumes:
  - hostPath:
      path: /var/lib/etcd-restore # was /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
```

```bash
# node
sed -i 's#path: /var/lib/etcd$#path: /var/lib/etcd-restore#' /root/manifests-off/etcd.yaml
```

### Step 4: Start the control plane

```bash
# node
mv /root/manifests-off/*.yaml /etc/kubernetes/manifests/
```

---

## 5. Verification

```bash
# host
until kubectl get nodes >/dev/null 2>&1; do sleep 5; done
kubectl get nodes
kubectl -n etcd-lab get configmap
kubectl -n etcd-lab create configmap after-restore --from-literal=a=b -o jsonpath='{.metadata.resourceVersion}{"\n"}'
```

```
NAME               DATA   AGE
keep-me            1      75s
kube-root-ca.crt   1      75s
1000007110
```

`keep-me` is present and `lose-me` is gone: the data is back at the snapshot. The new object's `resourceVersion` is above one billion, which is the revision bump at work.

Check the rest of the cluster too, not only the object you were watching:

```bash
# host
kubectl get pods -A | grep -v Running
```

The controller manager or scheduler may show restarts or `CrashLoopBackOff` for a few minutes, because they lost the API server while it was down; in the test run they recovered without any. They recover on their own, and `systemctl restart kubelet` on the node speeds it up. Components **outside** the control plane node (operators, admission webhooks, a GitOps controller) are not restarted by this procedure. The revision bump makes them re-list; without it, restart them.

---

## 6. Controlled Failure Scenario: Restore Without Restarting the API Server

Repeat the lab with a shortcut: skip step 1, restore into `/var/lib/etcd-restore-2`, and edit `/etc/kubernetes/manifests/etcd.yaml` in place. The kubelet restarts etcd on its own when the manifest changes.

```bash
# host
kubectl -n etcd-lab get configmap
```

In the earlier test run of this shortcut, objects created after the snapshot were **still listed**, even though etcd no longer had them. Whether you see it depends on timing and on whether the API server happens to restart, so treat it as a failure that can occur, not one that always does. Prove it from the node:

```bash
# node
etcdctl get /registry/configmaps/etcd-lab --prefix --keys-only
```

The API server was never restarted, so it keeps answering from its watch cache, which still describes the old data. Restart it and the stale objects disappear:

```bash
# node
crictl stop $(crictl ps -q --name kube-apiserver)
```

This is why the reliable procedure stops the whole control plane first.

---

## 7. Cleanup

```bash
# host
kubectl delete namespace etcd-lab
```

The restored directory is now the live data directory. Leave it in place, or recreate the cluster with `kind delete cluster --name k8s-lab` and Lab CKAD-01.

---

## Further reading

- [Operating etcd clusters for Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
- [etcd disaster recovery](https://etcd.io/docs/v3.6/op-guide/recovery/), including [restoring with a revision bump](https://etcd.io/docs/v3.6/op-guide/recovery/#restoring-with-revision-bump)

## Next Lab

Proceed to **[[Kubernetes/labs/cka/06-users-and-certificate-requests|Lab CKA-06 — Users & Certificate Requests]]**, or return to the [[Kubernetes/certifications/cka|CKA Track]].

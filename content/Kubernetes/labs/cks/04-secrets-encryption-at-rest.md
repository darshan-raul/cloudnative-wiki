---
title: "Lab CKS-04 — Secrets Encryption at Rest"
tags: [kubernetes, labs, cks, secrets, encryption, etcd]
date: 2026-10-13
description: "Read a Secret in plaintext straight from etcd, enable an EncryptionConfiguration on the API server, re-encrypt existing Secrets and prove the result."
---

# Lab CKS-04 — Secrets Encryption at Rest

By default a Secret is stored in etcd unencrypted. The base64 you see in `kubectl get secret -o yaml` is only how the API represents binary data; in etcd the value sits in the stored object as readable bytes. Anyone who can read the etcd data directory or a backup of it can read every Secret. This lab shows that, then fixes it.

Concepts: [[Kubernetes/concepts/L07-security/03-encryption-identity/14-secret-encryption|Secret Encryption]] and [[Kubernetes/concepts/L07-security/03-encryption-identity/13-etcd-encryption|etcd Encryption]].

Tested on kind v0.31 with Kubernetes v1.35.0 (the version the CKS exam used on 2026-10-13). Not re-run on v1.37; expect small differences in output there.

Verified on `kind` v0.31 with Kubernetes v1.35.0 and etcd 3.6.6.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**.
- A control plane node shell with `etcdctl`, set up exactly as in **[[Kubernetes/labs/cka/05-etcd-backup-restore|Lab CKA-05]]**:

```bash
docker exec -it k8s-lab-control-plane bash
# node
cp "$(find /var/lib/containerd -name etcdctl -type f | head -1)" /usr/local/bin/
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key
mkdir -p /root/backup/cks-04 && cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/backup/cks-04/
```

---

## 2. Read a Secret from etcd

```bash
# host
kubectl create namespace enc-lab
kubectl -n enc-lab create secret generic before --from-literal=password=plain-before
```

Secrets are stored under `/registry/secrets/<namespace>/<name>`:

```bash
# node
etcdctl get /registry/secrets/enc-lab/before --print-value-only | tr -c '[:print:]' '.'; echo
```

The output starts with `k8s`, followed by the object's metadata, and ends with `password..plain-before`. The value is sitting there in clear text. This is what an attacker with an etcd snapshot sees.

---

## 3. Write the EncryptionConfiguration

```bash
# node
mkdir -p /etc/kubernetes/enc

cat > /etc/kubernetes/enc/enc.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: $(head -c 32 /dev/urandom | base64)
      - identity: {}
EOF
chmod 600 /etc/kubernetes/enc/enc.yaml
```

Provider order is the whole point of this file:

- The **first** provider encrypts every new write.
- **All** providers are tried, in order, when reading.

So `aescbc` first means new Secrets are encrypted, and `identity` second means the existing plaintext Secrets can still be read. Reversing the two would leave everything in plaintext.

| Provider    | Use                                                |
| :---------- | :------------------------------------------------- |
| `identity`  | No encryption                                      |
| `aescbc`    | Local key, 32 bytes, the usual exam answer         |
| `aesgcm`    | Local key, faster, needs frequent rotation         |
| `secretbox` | Local key, modern cipher                           |
| `kms` v2    | Key held in an external KMS, the production choice |

---

## 4. Enable It on the API Server

Edit `/etc/kubernetes/manifests/kube-apiserver.yaml`.

**Flag:**

```yaml
- --encryption-provider-config=/etc/kubernetes/enc/enc.yaml
```

**Volume mount:**

```yaml
- name: enc
  mountPath: /etc/kubernetes/enc
  readOnly: true
```

**Volume:**

```yaml
- name: enc
  hostPath:
    path: /etc/kubernetes/enc
    type: Directory
```

```bash
# node
watch crictl ps --name kube-apiserver
```

---

## 5. Verification

A new Secret is encrypted:

```bash
# host
kubectl -n enc-lab create secret generic after --from-literal=password=plain-after
```

```bash
# node
etcdctl get /registry/secrets/enc-lab/after --print-value-only | head -c 60 | tr -c '[:print:]' '.'; echo
```

```text
k8s:enc:aescbc:v1:key1:;-..+..c.9...V>..`.X.A.......3}.FBz.>
```

The prefix names the provider and the key, and the rest is ciphertext. The API still returns the value, because the API server decrypts on read:

```bash
# host
kubectl -n enc-lab get secret after -o jsonpath='{.data.password}' | base64 -d
```

The older Secret is **still plaintext** in etcd. Enabling encryption does not touch existing data:

```bash
# node
etcdctl get /registry/secrets/enc-lab/before --print-value-only | tr -c '[:print:]' '.'; echo
```

### Re-encrypt existing Secrets

Rewrite every Secret so it passes through the first provider:

```bash
# host
kubectl get secrets -A -o json | kubectl replace -f -
```

```bash
# node
etcdctl get /registry/secrets/enc-lab/before --print-value-only | head -c 60 | tr -c '[:print:]' '.'; echo
```

It now starts with `k8s:enc:aescbc:v1:key1:` too. A task that says "ensure all existing Secrets are encrypted" is asking for this step.

---

## 6. Controlled Failure Scenario: Losing the Key

Replace the key with a different one, as if the configuration file had been regenerated:

```bash
# node
cp /etc/kubernetes/enc/enc.yaml /root/backup/cks-04/enc.yaml
sed -i "s#secret: .*#secret: $(head -c 32 /dev/urandom | base64)#" /etc/kubernetes/enc/enc.yaml
crictl stop $(crictl ps -q --name kube-apiserver)
```

```bash
# host
kubectl -n enc-lab get secret after
kubectl get secrets -A
```

Reading a Secret encrypted with the old key fails with `Internal error occurred: invalid padding on input`, and listing Secrets fails for the whole cluster with `unable to transform key`. The data is intact in etcd but unreadable. Restore the key:

```bash
# node
cp /root/backup/cks-04/enc.yaml /etc/kubernetes/enc/enc.yaml
crictl stop $(crictl ps -q --name kube-apiserver)
```

Two lessons follow. The encryption key must be backed up separately from etcd, since a backup without the key is useless and a backup stored with the key is not protected. And rotating a key is a sequence, not an edit:

1. Add the new key as the **second** entry and restart the API server.
2. Move the new key to the **first** position and restart.
3. Re-encrypt everything with `kubectl replace`.
4. Remove the old key and restart.

---

## 7. Cleanup

```bash
# host
kubectl delete namespace enc-lab
```

To turn encryption off, first make `identity` the first provider, restart the API server and run the `kubectl replace` command so that every Secret is plaintext again. Only then remove the flag. Removing the flag while Secrets are still encrypted makes them unreadable.

---

## Further reading

- [Encrypting confidential data at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [Using a KMS provider for data encryption](https://kubernetes.io/docs/tasks/administer-cluster/kms-provider/)

## Next Lab

Proceed to **[[Kubernetes/labs/cks/05-seccomp-apparmor-and-immutability|Lab CKS-05 — Seccomp, AppArmor & Immutability]]**, or return to the [[Kubernetes/certifications/cks|CKS Track]].

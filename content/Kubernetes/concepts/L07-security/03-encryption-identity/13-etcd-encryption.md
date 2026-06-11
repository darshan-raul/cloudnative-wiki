# etcd Encryption

*"https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/"*

By default, **k8s Secrets are stored in etcd as base64-encoded plaintext** (not encrypted at rest). Anyone with `etcdctl` access can read them. **etcd encryption** is the mechanism that lets you encrypt data at rest in etcd, using an `EncryptionConfiguration`. The encryption is **envelope encryption** — the keys are in an external KMS, and etcd encrypts / decrypts on the fly. Without etcd encryption, your secrets are one etcd backup away from being public.

### Table of Contents

1. [What etcd Encryption Solves](#1-what-etcd-encryption-solves)
2. [The EncryptionConfiguration Resource](#2-the-encryptionconfiguration-resource)
3. [The Identity Provider (no encryption)](#3-the-identity-provider-no-encryption)
4. [The aescbc Provider (local keys)](#4-the-aescbc-provider-local-keys)
5. [The secretbox Provider (XSalsa20-Poly1305)](#5-the-secretbox-provider-xsalsa20-poly1305)
6. [The KMS Providers (AWS / GCP / Azure / Vault)](#6-the-kms-providers-aws--gcp--azure--vault)
7. [Envelope Encryption in Depth](#7-envelope-encryption-in-depth)
8. [Key Rotation](#8-key-rotation)
9. [The Read / Write Flow](#9-the-read--write-flow)
10. [Backups and Encryption](#10-backups-and-encryption)
11. [Performance and Storage Overhead](#11-performance-and-storage-overhead)
12. [Operations and Debugging](#12-operations-and-debugging)
13. [Gotchas and Common Mistakes](#13-gotchas-and-common-mistakes)

---

## 1. What etcd Encryption Solves

etcd encryption protects against:

* **etcd backup exposure** — an attacker who steals an etcd backup sees ciphertext.
* **Insider threat** — a cluster operator with etcd access can't read secrets.
* **Storage compromise** — if etcd's disk is stolen, secrets are encrypted.

It does **not** protect against:

* **Compromised apiserver** — the apiserver has the keys; it decrypts on the fly.
* **Compromised workload** — the workload has the secret in memory; etcd encryption doesn't help.
* **Compromised RBAC** — anyone with `get` on Secrets can read them in plaintext (the apiserver decrypts for them).

The threat model: **protect data at rest, not data in use**. Encryption at rest + RBAC + audit logs = layered defense.

### 1.1 What gets encrypted

The `EncryptionConfiguration` controls encryption of:

* **Secrets** — by default.
* **ConfigMaps** — optional.
* **Anything else** — ConfigMap can be added; other resources typically aren't.

**Pods, Deployments, etc. are NOT encrypted** by default. The `EncryptionConfiguration` only encrypts what's listed in the `resources` section. If you want Pods encrypted, you add them to the config.

## 2. The EncryptionConfiguration Resource

The `EncryptionConfiguration` is a file on the apiserver's node. It's not a k8s resource — it's a static file that the apiserver reads on startup.

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - kms:
      name: aws-kms-provider
      endpoint: unix:///var/run/kmsplugin/socket.sock
      cachesize: 1000
      timeout: 3s
  - aescbc:
      keys:
      - name: key1
        secret: <base64-encoded-32-byte-key>
  - identity: {}
```

The structure:

* **`resources`** — list of resources to encrypt.
* **`providers`** — list of encryption providers, in priority order. The **first** provider is used for encryption. All providers are tried for decryption (so old keys still work).

The file is passed to the apiserver via `--encryption-provider-config`:

```bash
# in the kube-apiserver static pod manifest
- --encryption-provider-config=/etc/kubernetes/encryption-config.yaml
```

The apiserver reads the file on startup. Changes to the file require an apiserver restart.

## 3. The Identity Provider (no encryption)

```yaml
- identity: {}
```

The `identity` provider is a no-op — data is stored as-is. It's used:

* As a placeholder (the file must have at least one provider).
* To **decrypt** data encrypted by a previous provider (after rotation, the new provider is the first; the old provider is below it; if decryption with the new fails, it falls through).

When you rotate keys, you add the new key at the top, keep the old key below it, then re-encrypt the data, then remove the old key.

## 4. The aescbc Provider (local keys)

```yaml
- aescbc:
    keys:
    - name: key1
      secret: <base64-encoded-32-byte-key>
```

The `aescbc` provider is **AES-CBC with PKCS#7 padding**. The key is a 32-byte key (AES-256), base64-encoded.

This is **local key management** — the key is in the same file as the config. The file should be on a separate volume, not in a generic ConfigMap.

### 4.1 Generating a key

```bash
# generate a 32-byte key
head -c 32 /dev/urandom | base64
# outputs: kZd2f9z+8x... (base64)

# use as the 'secret' field
```

**`aescbc` is the weakest option.** It encrypts at rest, but the key is local. If the apiserver's host is compromised, the key is in the file. Use `aescbc` only for **testing or low-value data**.

For production, use **KMS** (the next sections).

## 5. The secretbox Provider (XSalsa20-Poly1305)

```yaml
- secretbox:
    keys:
    - name: key1
      secret: <base64-encoded-32-byte-key>
```

The `secretbox` provider uses **XSalsa20-Poly1305** (a NaCl crypto primitive). It's similar to `aescbc` but uses a different cipher.

`secretbox` is slightly faster than `aescbc` for small data (Secrets are small). For Secrets specifically, `secretbox` is the recommended local option.

**Both `aescbc` and `secretbox` are local-key.** Use KMS in production.

## 6. The KMS Providers (AWS / GCP / Azure / Vault)

KMS providers call out to a **KMS plugin** that runs as a separate process on the apiserver's node. The plugin talks to the actual KMS (AWS KMS, GCP KMS, Azure Key Vault, HashiCorp Vault).

### 6.1 AWS KMS

```yaml
- kms:
    name: aws-kms-provider
    endpoint: unix:///var/run/kmsplugin/socket.sock
    cachesize: 1000
    timeout: 3s
    apiVersion: v2
```

The apiserver talks to the AWS KMS plugin over a Unix socket. The plugin talks to AWS KMS. The plugin is the **aws-encryption-Provider** (or a similar tool).

The plugin is a separate Deployment (or process). The apiserver's static pod manifest must include the plugin's pod.

### 6.2 GCP KMS

```yaml
- kms:
    name: gcp-kms-provider
    endpoint: unix:///var/run/kmsplugin/socket.sock
    cachesize: 1000
    timeout: 3s
```

Similar to AWS, with a GCP-specific plugin.

### 6.3 Azure Key Vault

```yaml
- kms:
    name: azure-kv-provider
    endpoint: unix:///var/run/kmsplugin/socket.sock
    cachesize: 1000
    timeout: 3s
```

The Azure plugin calls Azure Key Vault.

### 6.4 HashiCorp Vault

```yaml
- kms:
    name: vault-kms-provider
    endpoint: unix:///var/run/kmsplugin/socket.sock
    cachesize: 1000
    timeout: 3s
```

The Vault plugin calls Vault's transit engine. The plugin handles auth, renews tokens, etc.

### 6.5 The KMS plugin

The KMS plugin is **not built into k8s**. It's a separate binary you deploy. The most common:

* **aws-encryption-provider** (Kubernetes SIG) — for AWS KMS.
* **gcp-kms-provider** — for GCP KMS.
* **azure-keyvault-provider** — for Azure.
* **vault-kms-plugin** — for HashiCorp Vault.

The plugin is a long-running process that exposes a gRPC API over a Unix socket. The apiserver calls the plugin for every encrypt / decrypt operation.

## 7. Envelope Encryption in Depth

The KMS providers use **envelope encryption**:

```
Write a Secret:
  1. apiserver generates a random Data Encryption Key (DEK)
  2. apiserver encrypts the Secret with the DEK (AES-256-GCM)
  3. apiserver sends the DEK to the KMS plugin
  4. KMS plugin sends the DEK to the actual KMS (e.g. AWS KMS)
  5. KMS encrypts the DEK with the Key Encryption Key (KEK)
  6. KMS plugin returns the encrypted DEK (EDEK)
  7. apiserver stores: { EDEK, encrypted_data } in etcd

Read a Secret:
  1. apiserver reads { EDEK, encrypted_data } from etcd
  2. apiserver sends EDEK to the KMS plugin
  3. KMS plugin sends EDEK to KMS
  4. KMS decrypts EDEK → DEK
  5. KMS plugin returns DEK
  6. apiserver decrypts the data with DEK
  7. apiserver returns the plaintext Secret
```

The **DEK** is per-Secret. The **KEK** is the master key in KMS. The DEK is encrypted with the KEK before being stored. **The KEK never leaves the KMS.**

This is the standard pattern for cloud-native encryption. It allows:

* **Encryption without round-trips to KMS for every read** — the DEK is cached (with TTL).
* **Rotation** — rotate the KEK; new DEKs are encrypted with the new KEK; old DEKs are still encrypted with the old KEK; the apiserver tries both.
* **KMS-side audit** — every DEK decrypt is logged in the KMS (e.g. CloudTrail).

### 7.1 The cache

The apiserver caches the DEKs. The `cachesize` and `timeout` fields control the cache:

* `cachesize: 1000` — cache up to 1000 DEKs.
* `timeout: 3s` — DEK is valid for 3s after decryption (to limit the time a stolen DEK is useful).

The cache is in-memory. Restart the apiserver, the cache is empty.

## 8. Key Rotation

Key rotation is **read-friendly** but requires careful steps.

### 8.1 The rotation flow

```
Initial state:
  providers:
  - kms: { ... key1 ... }       # encrypts
  - aescbc: { ... oldkey ... }  # decrypts old data
  - identity: {}

Phase 1: add new key
  providers:
  - kms: { ... key2 ... }       # new key
  - kms: { ... key1 ... }       # old key, still used for decryption
  - aescbc: { ... oldkey ... }
  - identity: {}

Phase 2: re-encrypt all data
  (use `kubectl get secrets -A -o json | kubectl apply -f -` to force a re-write)

Phase 3: remove old key
  providers:
  - kms: { ... key2 ... }       # new key only
  - identity: {}
```

The "re-encrypt all data" step is important. After Phase 1, new data is encrypted with key2, but old data is still encrypted with key1. The apiserver can read both (it tries the new first, falls back to the old), but to ensure all data is encrypted with key2, you must re-write it.

`kubectl get secrets -A -o json | kubectl apply -f -` is the trick — it reads all secrets (which decrypts them via key1) and re-writes them (which encrypts with key2). The apply is a no-op for the Secret's data (same data), but the encryption is new.

### 8.2 The KMS rotation

If you're using KMS, the KEK is rotated in the KMS itself. AWS KMS, for example, has automatic key rotation (yearly) or you can do it manually.

When the KEK rotates:
* New DEKs are encrypted with the new KEK.
* Old DEKs are still encrypted with the old KEK.
* The KMS plugin handles decryption with both.

The apiserver's KMS provider config doesn't change (it still points to the same KMS key ID). The rotation is in the KMS, transparent to the apiserver.

## 9. The Read / Write Flow

```
Write (CREATE / UPDATE a Secret):
  1. Client sends Secret to apiserver
  2. apiserver validates, authorizes, admits
  3. apiserver generates DEK (random)
  4. apiserver encrypts Secret with DEK (AES-256-GCM)
  5. apiserver sends DEK to KMS plugin
  6. KMS plugin sends DEK to KMS
  7. KMS encrypts DEK with KEK, returns EDEK
  8. apiserver writes { EDEK, encrypted_data } to etcd

Read (GET a Secret):
  1. Client sends GET request
  2. apiserver authorizes
  3. apiserver reads { EDEK, encrypted_data } from etcd
  4. apiserver checks DEK cache
     - If hit: use cached DEK
     - If miss: send EDEK to KMS plugin, decrypt to DEK
  5. apiserver decrypts data with DEK
  6. apiserver returns plaintext Secret to client
```

The read path can be slow on the **first read of a Secret** (cold cache), but subsequent reads are fast (cache hit).

### 9.1 The cache invalidation

The DEK cache is per-apiserver-pod. With multiple apiservers (HA), each has its own cache. A Secret read for the first time by apiserver A takes a KMS round-trip; the next read is a cache hit. A Secret read for the first time by apiserver B also takes a round-trip.

The cache size is small (1000-10000 DEKs is typical). For a cluster with millions of Secrets, the cache thrashes.

## 10. Backups and Encryption

etcd backups (`etcdctl snapshot save`) **include the encrypted data**, not the plaintext. A stolen backup is still encrypted.

But:

* The **EncryptionConfiguration** is needed to decrypt. Without it (or the KMS access), the backup is useless.
* The **DEK cache** doesn't help with backups — it's in the apiserver, not the backup.
* The **KMS access** is needed to decrypt DEKs. If the KMS is gone (or the keys are revoked), the backup is unreadable.

**Disaster recovery implications:**

* Back up the **EncryptionConfiguration** alongside the etcd backup.
* Back up the **KMS credentials** (or store them in a separate KMS).
* Test the **decryption** periodically — `etcdctl snapshot restore` + `etcdctl get` to verify the data is readable.

## 11. Performance and Storage Overhead

### 11.1 The overhead

Encryption adds:

* **CPU** — AES-256-GCM is fast (~1 GB/s on modern CPUs with AES-NI). KMS round-trips are slower (10-100ms over the network).
* **Latency** — first read of a Secret is ~10-100ms slower (KMS round-trip). Cached reads are fast.
* **Storage** — the EDEK is small (~200 bytes for a 32-byte DEK). The encrypted Secret is the same size as the plaintext (AES is a stream cipher for this purpose, with the IV prepended).

### 11.2 The cache

The `cachesize` is critical for performance. With 1000-10000 entries, the cache covers most Secrets. The `timeout` (3-10s) limits the time a cached DEK is valid.

For high-throughput clusters, increase `cachesize`. For low-latency clusters, decrease `timeout` (more KMS round-trips, but shorter window for stolen DEKs).

## 12. Operations and Debugging

### 12.1 Common commands

```bash
# check the apiserver's encryption config
cat /etc/kubernetes/encryption-config.yaml

# check the apiserver logs for encryption errors
kubectl -n kube-system logs kube-apiserver-<node> | grep -i encrypt

# read a Secret's actual storage
ETCDCTL_API=3 etcdctl get /registry/secrets/default/my-secret \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ca.crt \
  --cert=/etc/ssl/etcd/peer.crt \
  --key=/etc/ssl/etcd/peer.key | strings | head
# if encryption is on, you'll see "k8s:enc:aescbc:v1:key1" or similar
# if encryption is off, you'll see the base64 plaintext

# force re-encryption of all Secrets
kubectl get secrets -A -o json | kubectl apply -f -
```

### 12.2 The "encryption not working" case

```bash
# 1. Is the EncryptionConfiguration passed to the apiserver?
kubectl -n kube-system get pod kube-apiserver-<node> -o yaml | grep encryption-provider-config

# 2. Are the providers correct?
cat /etc/kubernetes/encryption-config.yaml

# 3. Is the KMS plugin running?
# (for KMS providers)
ps aux | grep kmsplugin

# 4. Read a Secret and check the actual storage
ETCDCTL_API=3 etcdctl get /registry/secrets/default/my-secret ...
# should be encrypted, not plaintext
```

### 12.3 The "decryption failing" case

A Secret read returns an error (e.g. "Failed to decrypt"):

```bash
# 1. Is the EncryptionConfiguration on the apiserver?
cat /etc/kubernetes/encryption-config.yaml

# 2. Is the KMS plugin reachable?
# (for KMS)
ls -la /var/run/kmsplugin/socket.sock

# 3. Is the KMS key still valid?
# (check the KMS console)

# 4. Restart the apiserver after fixing
```

## 13. Gotchas and Common Mistakes

### 13.1 The 25+ common mistakes

1. **The `EncryptionConfiguration` is read on startup.** Changing the file requires an apiserver restart.

2. **The first provider in the list is the encryption provider.** All providers are tried for decryption. Order matters.

3. **`aescbc` and `secretbox` are local keys.** The key is in the file. If the file is exposed, the encryption is broken.

4. **The base64 key in the config is the actual encryption key.** Anyone with the file can decrypt the data. The file should be on a separate volume with restricted access.

5. **KMS providers require a separate plugin process.** The plugin is not built into k8s. You need to deploy it.

6. **The KMS plugin's Unix socket must be accessible by the apiserver.** If the socket is in a different path, the apiserver can't reach it.

7. **The DEK cache is in-memory per apiserver.** With HA, each apiserver has its own cache. Restart the apiserver, the cache is cold.

8. **The DEK timeout (3-10s) is the time a decrypted DEK is cached.** A stolen DEK is usable for that long. Tune based on your threat model.

9. **Re-encryption requires rewriting all data.** The `kubectl get secrets -A -o json | kubectl apply -f -` trick works but is heavy.

10. **KMS round-trips are slow.** First read of a Secret: 10-100ms. Subsequent reads: fast (cache). High-throughput clusters need large caches.

11. **etcd backups include the encrypted data, not the plaintext.** A stolen backup is encrypted. But you need the EncryptionConfiguration + KMS access to decrypt.

12. **The EncryptionConfiguration file must be on the apiserver's node.** It's not a k8s resource.

13. **`identity` is a no-op provider.** It's used to "decrypt" data that was never encrypted (during migration).

14. **Mixing providers can be confusing.** If you change from `aescbc` to `kms`, the old data is still encrypted with `aescbc`. Keep the old provider in the list until re-encryption is complete.

15. **`resources` is a list.** You can encrypt Secrets and ConfigMaps. Don't encrypt Pods (the apiserver can't mutate them during admission).

16. **ConfigMap encryption is rare.** It adds CPU and storage for little gain. Most clusters only encrypt Secrets.

17. **KMS key rotation in the KMS is transparent to the apiserver.** The provider config doesn't change.

18. **The `cachesize` is per-provider.** With 3 providers, you have 3 caches (each with its own DEKs).

19. **A KMS plugin that goes down** blocks all reads. The apiserver can't decrypt without the plugin. Mitigate with `failurePolicy` (in `EncryptionConfiguration`, the `kms` provider can have a `failurePolicy` — `Fail` or `Ignore`).

20. **`aescbc` keys are 32 bytes (AES-256).** `secretbox` keys are 32 bytes (XSalsa20). `kms` keys are in the KMS, not the file.

21. **The EncryptionConfiguration is not encrypted itself.** It's a YAML file with keys (for local providers). Protect it like a secret.

22. **Adding a new provider while the apiserver is running requires a restart.** The config is read on startup.

23. **A Secret that was created before encryption was enabled** is in plaintext in etcd. To encrypt it, read it (via apiserver) and write it back.

24. **The "encrypted with k8s:enc:aescbc:v1:key1" prefix in the etcd value** indicates the encryption provider. If you see "k8s:enc:aescbc:v1:key1", the data is encrypted. If you see base64 (e.g. "eyJ..."), it's plaintext.

25. **The apiserver's static pod manifest must include the `--encryption-provider-config` flag.** Without it, the apiserver uses identity (no encryption).

26. **The KMS plugin's logs are critical for debugging.** The plugin logs every encrypt / decrypt request. Watch the logs for errors.

27. **A KMS provider with `cachesize: 0`** has no cache. Every read is a round-trip. Don't set 0.

28. **A failed KMS round-trip is cached as a failure** (depending on the plugin). The next request retries. Tune the plugin's retry policy.

29. **The `kms` provider's `apiVersion` is `v1` or `v2`.** v2 adds more features (key naming, etc.). Use the latest.

30. **A `ClusterRole` to read Secrets in etcd directly is a security smell.** Use the apiserver, which handles decryption. Direct etcd access bypasses the encryption.

## See also

* [[Kubernetes/concepts/L07-security/03-encryption-identity/14-secret-encryption|Secret Encryption]] — the higher-level view
* [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/15-audit-logging|Audit Logging]] — what gets logged for encryption events
* [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/20-cluster-hardening|Cluster Hardening]] — etcd access control

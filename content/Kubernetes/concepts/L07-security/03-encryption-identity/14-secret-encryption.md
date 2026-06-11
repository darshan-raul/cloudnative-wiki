# Secret Encryption

*"https://kubernetes.io/docs/concepts/configuration/secret/"*

Kubernetes Secrets are **base64-encoded plaintext** by default — encoded, not encrypted. Anyone with etcd access can read them as plaintext. **Secret encryption** is the practice of encrypting Secrets at rest, in transit, and in use, using layered defenses. This note covers the encryption-at-rest side (etcd encryption), but also walks through the broader "Secrets lifecycle" — when encryption matters, what to encrypt, and the operational patterns.

### Table of Contents

1. [Why Secrets Need Encryption](#1-why-secrets-need-encryption)
2. [The Three States of a Secret](#2-the-three-states-of-a-secret)
3. [The Base64 Misconception](#3-the-base64-misconception)
4. [Encryption at Rest: etcd EncryptionConfiguration](#4-encryption-at-rest-etcd-encryptionconfiguration)
5. [Encryption in Transit: TLS and mTLS](#5-encryption-in-transit-tls-and-mtls)
6. [Encryption in Use: Application-Level](#6-encryption-in-use-application-level)
7. [The Secret Lifecycle](#7-the-secret-lifecycle)
8. [External Secret Managers](#8-external-secret-managers)
9. [The Secret Store CSI Driver](#9-the-secret-store-csi-driver)
10. [Sealed Secrets, SOPS, and GitOps](#10-sealed-secrets-sops-and-gitops)
11. [RBAC for Secrets](#11-rbac-for-secrets)
12. [Secret Rotation](#12-secret-rotation)
13. [Secret Sprawl](#13-secret-sprawl)
14. [Operations and Debugging](#14-operations-and-debugging)
15. [Gotchas and Common Mistakes](#15-gotchas-and-common-mistakes)

---

## 1. Why Secrets Need Encryption

Secrets in k8s are the **highest-value target** in a cluster. They contain:

* Database credentials.
* API tokens.
* TLS private keys.
* OAuth client secrets.
* Encryption keys.
* Cloud provider credentials (via IRSA / Pod Identity).

A leaked secret is a **direct path to other systems**. A database password gives the attacker DB access. A cloud credential gives them the entire cloud account. A TLS private key lets them impersonate the service.

The threat model:

* **Compromised etcd** — the attacker can read all data. Encryption at rest mitigates.
* **Compromised apiserver backup** — the backup contains all data. Encryption at rest mitigates.
* **Compromised workload** — the workload has the secret in memory. Encryption at rest doesn't help; need runtime controls.
* **Compromised RBAC** — a user with `get` on Secrets can read them. RBAC mitigation.
* **Compromised Git repo** — if Secrets are in git, they're exposed. Need external secret store.

The defenses are **layered**: encryption at rest, RBAC, external secret managers, runtime controls (NetworkPolicy, etc.).

## 2. The Three States of a Secret

A Secret's data is in one of three states:

* **At rest** — stored in etcd (or in an external system).
* **In transit** — moving between the apiserver and the client, or between the apiserver and etcd.
* **In use** — in the memory of a workload.

Each state needs its own defense:

| State | Defense | Default in k8s |
|---|---|---|
| At rest (etcd) | etcd encryption, KMS | ❌ plaintext (base64) |
| In transit (apiserver ↔ client) | TLS | ✅ TLS 1.2+ |
| In transit (apiserver ↔ etcd) | TLS, mTLS | ✅ mTLS |
| In transit (workload ↔ apiserver) | TLS | ✅ TLS |
| In use (workload memory) | Runtime controls | ❌ no protection |
| In transit (workload ↔ DB) | App-level mTLS | ❌ not by default |

The most important gap: **at rest** (by default, no encryption) and **in use** (no protection beyond the workload's own controls).

## 3. The Base64 Misconception

A common misconception: "Secrets are encrypted because they're base64-encoded." **No.** Base64 is an **encoding**, not encryption. It's a way to represent binary data as text. The encoded form decodes back to the original.

```
Secret data:   "my-secret-password"
Base64:        "bXktc2VjcmV0LXBhc3N3b3Jk"
Decode:        "my-secret-password"
```

Anyone with `base64 --decode` can read a base64-encoded Secret. The encoding is just a transport format (Secrets in YAML can't have raw binary).

**The only "encryption" base64 provides is the obvious: the value isn't directly visible in `kubectl get secret -o yaml`.** With `kubectl get secret -o jsonpath='{.data.password}' | base64 -d`, it's plaintext.

## 4. Encryption at Rest: etcd EncryptionConfiguration

See [[Kubernetes/concepts/L07-security/03-encryption-identity/13-etcd-encryption|etcd Encryption]] for the full deep-dive. The summary:

* An `EncryptionConfiguration` file on the apiserver's node configures encryption.
* Local providers (`aescbc`, `secretbox`) use keys in the file.
* KMS providers (`kms`) call out to AWS KMS, GCP KMS, Azure Key Vault, etc.
* Envelope encryption: per-Secret DEK encrypted with KMS KEK.
* The apiserver handles encryption / decryption transparently.
* etcd stores ciphertext; the apiserver decrypts for clients.

The trade-off:

* **Local providers** — simple, no external dependencies, but the key is in the file.
* **KMS providers** — production-grade, key in the cloud KMS, but adds a network dependency.

For production: **use KMS**. The performance cost is small (with caching); the security gain is large (the key never leaves the cloud's HSM).

## 5. Encryption in Transit: TLS and mTLS

See [[Kubernetes/concepts/L07-security/03-encryption-identity/08-tls-mtls|TLS / mTLS]] for the full deep-dive. The summary:

* **apiserver ↔ client** — TLS by default (port 6443). mTLS optional.
* **apiserver ↔ etcd** — mTLS by default.
* **apiserver ↔ kubelet** — mTLS by default.
* **Pod ↔ Pod** — plaintext by default. mTLS via service mesh.
* **Pod ↔ apiserver** — TLS via the SA token.

**The control plane is mTLS.** **The data plane needs work** (NetworkPolicy + service mesh or app-level mTLS).

## 6. Encryption in Use: Application-Level

There's no k8s-level encryption for secrets in a workload's memory. The Secret is **decrypted by the apiserver, sent to the workload over TLS, and held in the workload's memory as plaintext.**

Mitigations:

* **Don't put secrets in environment variables.** Env vars are visible in `/proc/<pid>/environ` and in `kubectl describe pod`. Use **files** (mounted as volumes).
* **Use memory-only filesystems** (`tmpfs` for `/tmp`) to limit swap.
* **Don't log secrets.** Configure the app to redact.
* **Use runtime detection** (Falco, Tetragon) to alert on secret file reads.
* **Use mTLS in the app** to limit network exposure of the secret (e.g. the DB password is in a TLS handshake, not a network packet).
* **Use secret rotation** to limit the window of a leaked secret.

For most apps, the **memory protection is the OS's job** (process isolation). The k8s layer doesn't have visibility into process memory.

## 7. The Secret Lifecycle

A Secret's full lifecycle:

```
1. Creation
   - created via kubectl, manifest, controller
   - stored in etcd (encrypted if EncryptionConfiguration is on)
   - logged in audit log

2. Distribution
   - mounted as file (volume mount) or env var
   - the workload sees the value

3. Use
   - the app uses the value (auth, DB connection, etc.)
   - the value is in memory

4. Rotation
   - the value is changed (new Secret, or update existing)
   - the workload picks up the new value (depends on refresh)

5. Deletion
   - the Secret is deleted
   - the value is gone from etcd
   - the value may still be in the workload's memory
```

Each step has a defense. The weakest link determines the overall security.

### 7.1 Secret refresh

A Secret's value is mounted as a file. The file is **updated atomically** when the Secret is updated (the kubelet uses a symlink + file replace pattern). The workload sees the new value within a few seconds (the kubelet's sync period).

For env vars, the workload must be **restarted** to pick up the new value. Env var Secret injection happens at container start.

For a smooth rotation:

* Use **files** (volume mount) for secrets that rotate.
* Use **env vars** for secrets that don't rotate (e.g. cluster config).
* The workload must **reload the file** when it changes (inotify or a refresh task).

## 8. External Secret Managers

The recommended pattern: **Secrets live in an external manager** (Vault, AWS Secrets Manager, etc.) and are **synchronized into k8s** (or mounted as files).

The "External Secrets" pattern:

```
   Vault / AWS Secrets Manager / Azure Key Vault
        │
        │ (sync)
        │
   k8s Secret (or mounted file)
        │
        │ (volume mount)
        │
   workload
```

The sync can be:

* **External Secrets Operator** (ESO) — a k8s controller that syncs from external stores.
* **Vault Agent Injector** — Vault's sidecar that fetches and mounts.
* **Secrets Store CSI Driver** — a CSI driver that mounts secrets as volumes (see below).

The external store is the **source of truth**. The k8s Secret is a **cache**.

### 8.1 Why external is better

* **Centralized rotation** — the secret manager rotates, all k8s workloads pick it up.
* **Audit trail** — the secret manager logs who accessed what.
* **Granular access control** — the secret manager has its own RBAC.
* **No plaintext in git** — secrets are not in the cluster's source of truth.
* **Better key management** — the secret manager has HSM-backed keys, audit logs, etc.

### 8.2 The secret-zero problem

The first secret you need: the credential to the secret manager itself. This is the **secret-zero problem**. Solutions:

* **IAM roles for service accounts** (IRSA) on EKS — the pod's identity is in the IAM role, not in a Secret.
* **Workload Identity** on GKE — similar.
* **Pod Identity** on AKS — similar.

These give the pod a cloud identity that can access the secret manager. No Secret holds the credential.

## 9. The Secret Store CSI Driver

*"https://secrets-store-csi-driver.sigs.k8s.io/"*

The **Secret Store CSI Driver** is a CSI driver that mounts secrets from an external store as a volume. The pod's filesystem contains the secret; the secret is fetched on demand.

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata: { name: vault-secrets }
spec:
  provider: vault
  parameters:
    vaultAddress: "https://vault.example.com"
    roleName: "my-app"
    objects: |
      - objectName: "secret/data/db/password"
        secretPath: "db-password"
```

A pod mounts the CSI volume:

```yaml
volumes:
- name: secrets
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: vault-secrets
volumeMounts:
- name: secrets
  mountPath: /mnt/secrets
  readOnly: true
```

The pod's `/mnt/secrets/db-password` contains the secret. The pod can read it like a regular file.

### 9.1 The CSI driver modes

* **CSI volume** — mounted as a tmpfs (in-memory) volume. The secret is in memory, not on disk.
* **CSI inline** — the secret is also written to a k8s Secret (sync'd from the external store).

The "CSI inline" mode is the bridge to existing patterns (where the app reads from a k8s Secret).

## 10. Sealed Secrets, SOPS, and GitOps

For GitOps workflows where Secrets are in git (encrypted), there are two main tools:

### 10.1 Sealed Secrets (Bitnami)

*"https://github.com/bitnami-labs/sealed-secrets"*

A `SealedSecret` is a custom resource that contains an encrypted Secret. Only the **Sealed Secrets controller** in the cluster can decrypt it.

```bash
# install the controller
helm install sealed-secrets sealed-secrets/sealed-secrets

# seal a secret
kubectl create secret generic my-secret --from-literal=password=foo --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets -o yaml > sealed-secret.yaml
```

The `sealed-secret.yaml` is safe to commit. The controller decrypts and creates the k8s Secret.

### 10.2 SOPS (Mozilla)

*"https://github.com/getsops/sops"*

SOPS encrypts specific fields in a YAML / JSON / ENV file. The encrypted file is committed to git; the decryption key is in the cloud (KMS) or locally.

```bash
# encrypt a Secret
sops --encrypt --kms arn:aws:kms:us-east-1:1234:key/abcd secret.yaml > secret.enc.yaml

# decrypt
sops --decrypt secret.enc.yaml | kubectl apply -f -
```

The encrypted file looks like:

```yaml
data:
  password: ENC[AES256_GCM,data:abc...,tag:xyz,iv:...]
```

The `ENC[...]` blocks are the encrypted fields. SOPS knows which fields to encrypt (based on the `sops:` metadata).

### 10.3 Sealed Secrets vs SOPS

* **Sealed Secrets** — k8s-specific, requires the controller in the cluster. The encryption key is in the controller.
* **SOPS** — generic, works for any YAML / JSON / ENV. The encryption key is in KMS (or PGP, age, etc.).

For pure k8s GitOps: **Sealed Secrets**. For multi-system (k8s + Terraform + Ansible): **SOPS**.

## 11. RBAC for Secrets

RBAC controls **who can read** Secrets. The standard is "least privilege":

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: secret-reader, namespace: default }
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["my-secret"]   # only this Secret
  verbs: ["get"]
```

With `resourceNames`, the Role is limited to a specific Secret. The bound subject can read only that one.

The standard anti-pattern: a ClusterRole with `resources: ["secrets"], verbs: ["get", "list", "watch"]` and no `resourceNames`. This lets the subject read every Secret in every namespace.

For production:

* Default: **no role grants access to Secrets** (the default ServiceAccount has no RoleBindings).
* App: a Role that grants access to **specific Secrets** by name.
* Admin: a ClusterRole for emergency access (e.g. cluster-admin).

## 12. Secret Rotation

Secrets should be **rotated regularly**. The rotation flow:

1. **Generate a new secret value** (in the secret manager).
2. **Update the k8s Secret** (or wait for the external sync).
3. **Workloads pick up the new value** (file refresh or env var restart).
4. **Old value is invalidated** (in the secret manager).

For **zero-downtime rotation**:

* The Secret has two values (e.g. `password` and `previousPassword`).
* The app tries `password` first; if auth fails, it tries `previousPassword`.
* The old value is removed after all clients are using the new one.

For **DB credentials**:

* The DB has two users (or one user with two passwords).
* The app's first attempt is the new password; the fallback is the old.
* Once all clients are on the new password, the old is removed.

For **TLS certs**:

* The cert has a validity period (90 days is typical).
* The new cert is issued and stored as a new Secret.
* The app (or ingress controller) reloads the new cert.
* The old cert expires naturally.

## 13. Secret Sprawl

A common anti-pattern: **Secrets are scattered** across ConfigMaps, env vars, files, git repos, and external stores. No single place to know "where is this secret used".

The "single source of truth" pattern:

* All Secrets live in **one external manager** (Vault, AWS Secrets Manager, etc.).
* A controller syncs them to k8s Secrets (or mounts them as files).
* The app reads from the k8s Secret (or the mounted file).
* GitOps doesn't have Secrets — only references to the Secret's name.

The "Secret" is a **handle**, not a value. The value lives in the external manager. The handle is in git.

## 14. Operations and Debugging

### 14.1 Common commands

```bash
# list Secrets
kubectl get secrets -A
# NAME              TYPE     DATA   AGE
# my-secret         Opaque   1      30d

# see a Secret's data (base64)
kubectl get secret my-secret -o yaml

# decode a Secret value
kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d

# see who's accessing Secrets (RBAC)
kubectl auth can-i get secrets --as=system:serviceaccount:default:my-app -n default

# check encryption at rest
ETCDCTL_API=3 etcdctl get /registry/secrets/default/my-secret \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ca.crt \
  --cert=/etc/ssl/etcd/peer.crt \
  --key=/etc/ssl/etcd/peer.key | head
# if encrypted, you'll see "k8s:enc:aescbc:v1:key1" or similar
```

### 14.2 The "Secret rotation failed" case

A new Secret value is in the external manager, but the workload is using the old value.

```bash
# 1. Is the sync working?
# check the external secrets operator
kubectl -n external-secrets get externalsecret
# or the Vault agent
kubectl logs <pod> -c vault-agent

# 2. Is the workload picking up the new value?
kubectl exec <pod> -- cat /path/to/secret
# should show the new value

# 3. Is the kubelet refreshing the file?
# the kubelet refreshes the Secret volume every sync period (default 1m)
```

### 14.3 The "Secret not encrypted" case

A Secret is in etcd in plaintext (not encrypted):

```bash
# 1. Is the EncryptionConfiguration on the apiserver?
kubectl -n kube-system get pod kube-apiserver-<node> -o yaml | grep encryption-provider-config

# 2. Was the Secret created before encryption was enabled?
# if so, re-encrypt:
kubectl get secrets -A -o json | kubectl apply -f -

# 3. Check the etcd storage
ETCDCTL_API=3 etcdctl get /registry/secrets/default/my-secret ...
# should show encrypted prefix
```

## 15. Gotchas and Common Mistakes

### 15.1 The 30+ common mistakes

1. **Base64 is not encryption.** Anyone with the base64 value can decode it. The Secret is "encoded, not encrypted" by default.

2. **The default ServiceAccount can read no Secrets** (without explicit RoleBindings). Don't grant it access.

3. **A ClusterRoleBinding that grants `get secrets` to a group is dangerous.** Anyone in the group can read all Secrets cluster-wide.

4. **The `resourceNames` field is the right way to limit Secret access.** A Role that lists a specific Secret by name, with `get` verb, is what you want.

5. **etcd encryption requires the EncryptionConfiguration on every apiserver.** With HA, all apiservers must have the config. Otherwise, requests hitting an apiserver without the config return plaintext.

6. **Re-encrypting all data after enabling encryption is a heavy operation.** For a cluster with millions of Secrets, this can take hours.

7. **Env vars don't refresh.** A Secret mounted as an env var is set at container start. To pick up a new value, restart the container.

8. **File mounts refresh, but the app may cache the old value.** The app's logic must re-read the file (or use a library that does).

9. **`/proc/<pid>/environ` shows env vars.** Any process in the same PID namespace can see them. Use files instead.

10. **The audit log doesn't log Secret content.** It logs the request (the user, the resource, the operation), but not the Secret's value.

11. **The EncryptionConfiguration file has the keys (for local providers).** It's a sensitive file. Restrict access.

12. **A KMS provider's plugin must be running on every apiserver.** If the plugin is down, the apiserver can't decrypt.

13. **The secret-zero problem is real.** The first secret is the credential to the secret manager. Solve with IRSA, Workload Identity, Pod Identity.

14. **External Secrets Operator is a controller, not a sidecar.** It runs in its own Deployment. The synced Secrets are visible to all subjects with the right RBAC.

15. **Sealed Secrets are sealed with the cluster's controller key.** A SealedSecret can only be decrypted by the cluster that sealed it. Migrating a SealedSecret to a new cluster requires re-sealing.

16. **SOPS with KMS requires IAM access.** The CI / operator that decrypts must have the IAM role.

17. **`kubectl create secret --from-literal` puts the value in the shell history.** Use `--from-file` or read from a file.

18. **A Secret in a ConfigMap is not a Secret.** ConfigMaps are not encrypted by default. If the data is sensitive, use a Secret.

19. **A `docker exec` into a running container can read the Secret's file.** Anyone with `kubectl exec` permission can read the mounted Secret.

20. **A Secret that's also a ServiceAccount token (mountPath `/var/run/secrets/...`) is auto-mounted.** The default ServiceAccount's token is in every pod. Disable the automount if not needed.

21. **The `--from-env-file` flag for `kubectl create secret` reads env vars from a file.** Useful for bulk creation.

22. **A Secret's `data` field is base64; the `stringData` field is plaintext.** `stringData` is converted to `data` on create.

23. **A Secret of type `kubernetes.io/dockerconfigjson` holds a Docker registry credential.** The data is a base64-encoded JSON.

24. **A Secret of type `kubernetes.io/tls` holds a cert + key.** The data has `tls.crt` and `tls.key`.

25. **A Secret of type `kubernetes.io/service-account-token` is the legacy SA token type.** Now deprecated in favor of bound tokens.

26. **A `bootstrap.kubernetes.io/token` Secret is the bootstrap token for `kubeadm join`.** It's in `kube-system`, has a specific format.

27. **The encryption-at-rest prefix in etcd is `k8s:enc:<provider>:v<version>:<key>`.** This is what tells the apiserver how to decrypt.

28. **The audit log has a `metadata.creationTimestamp` but not the Secret value.** Audit the access, not the content.

29. **A Secret with `type: Opaque` is the default.** It has no schema; the data is whatever you put in.

30. **The `immutable: true` field on a Secret (k8s 1.21+) prevents updates.** Useful for performance (the kubelet doesn't watch for changes) and security (the value can't be modified).

## See also

* [[Kubernetes/concepts/L07-security/03-encryption-identity/13-etcd-encryption|etcd Encryption]] — the at-rest encryption deep-dive
* [[Kubernetes/concepts/L07-security/03-encryption-identity/08-tls-mtls|TLS / mTLS]] — the in-transit story
* [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]] — controlling who can read Secrets
* [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/20-cluster-hardening|Cluster Hardening]] — apiserver flags for encryption

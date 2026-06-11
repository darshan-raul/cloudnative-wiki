# Secrets

*"https://kubernetes.io/docs/concepts/configuration/secret/"*

A Secret is a k8s object that holds **sensitive data** — passwords, OAuth tokens, SSH keys, TLS certs, etc. Conceptually the same as a ConfigMap, but with extra fields that mark it sensitive and (optionally) protections at the storage layer.

## The four Secret types

k8s has four built-in types, each for a specific use case:

| Type | Use case | Required keys |
|---|---|---|
| `Opaque` | Arbitrary user-defined data | none (free-form) |
| `kubernetes.io/tls` | TLS cert + key | `tls.crt`, `tls.key` |
| `kubernetes.io/dockerconfigjson` | Image pull secret for a private registry | `.dockerconfigjson` |
| `kubernetes.io/basic-auth` | Basic auth credentials | `username`, `password` |
| `kubernetes.io/ssh-auth` | SSH credentials | `ssh-privatekey` |
| `kubernetes.io/service-account-token` | Legacy SA token (k8s 1.21+ uses bound tokens instead) | token data |

`Opaque` is the most common. Use the more specific types when they apply — tools know what to do with them.

## The basic example

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
stringData:                  # stringData lets you use plain text
  username: admin
  password: hunter2          # written as base64 in `data` field
```

`kubectl get secret db-credentials -o yaml` shows:

```yaml
data:
  password: aHVudGVyMg==        # base64 of "hunter2"
  username: YWRtaW4=            # base64 of "admin"
type: Opaque
```

**Base64 is NOT encryption.** Anyone with `kubectl get secret` access can read the data. Real protection comes from:

* **RBAC** — restrict who can `get`, `list`, `watch` secrets
* **Encryption at rest** — see below
* **External secret managers** — HashiCorp Vault, AWS Secrets Manager, etc.

## Two ways to use a Secret

### Environment variables

```yaml
apiVersion: v1
kind: Pod
metadata: { name: app }
spec:
  containers:
  - name: app
    image: app:1.0
    env:
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: username
    - name: DB_PASS
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
```

The app sees `DB_USER=admin` and `DB_PASS=hunter2` as plain env vars.

### Mounted as a file

```yaml
apiVersion: v1
kind: Pod
metadata: { name: app }
spec:
  containers:
  - name: app
    image: app:1.0
    volumeMounts:
    - name: secrets
      mountPath: /etc/secrets
      readOnly: true
  volumes:
  - name: secrets
    secret:
      secretName: db-credentials
```

The container sees:

```bash
ls /etc/secrets
# password  username

cat /etc/secrets/password
# hunter2
```

**Updates propagate** to the mounted files (with the kubelet's sync period, typically 60-90s). Env vars, by contrast, are **static** — they're set at Pod start and don't change.

**Gotcha:** env vars from Secrets are visible in `/proc/<pid>/environ` of any process in the container. Files are only readable by the container's UID. If you have multiple UIDs or a sidecar that can read `/proc`, prefer files.

## The `imagePullSecrets` pattern

To pull from a private registry, the kubelet needs credentials. The `imagePullSecrets` field on a Pod / ServiceAccount tells it which Secret to use:

```bash
# create a dockerconfigjson Secret
kubectl create secret docker-registry my-registry \
  --docker-server=registry.example.com \
  --docker-username=alice \
  --docker-password=s3cret \
  --docker-email=alice@example.com
```

```yaml
spec:
  imagePullSecrets:
  - name: my-registry
  containers:
  - name: app
    image: registry.example.com/myapp:1.0
```

Or attach to a ServiceAccount (k8s 1.22+ has a cleaner API for this):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: app }
imagePullSecrets:
- name: my-registry
```

Any Pod using this SA inherits the pull secret.

## TLS Secrets

```bash
kubectl create secret tls my-tls \
  --cert=./tls.crt \
  --key=./tls.key
```

```yaml
apiVersion: v1
kind: Secret
metadata: { name: my-tls }
type: kubernetes.io/tls
data:
  tls.crt: <base64>
  tls.key: <base64>
```

The `tls.crt` may be a chain (server cert + intermediate certs). The `tls.key` is the private key.

Used by:

* **Ingress** for TLS termination
* **cert-manager** to track issued certs
* **Custom apps** for mTLS

## The "image pull secret" gotcha

If a Pod has an `imagePullSecrets` and the kubelet can't pull the image, the Pod sits in `ImagePullBackOff`. Common causes:

* Wrong secret name
* Wrong credentials (expired, rotated)
* Wrong registry URL (e.g. `https://` prefix not expected)
* Network policy blocking egress to the registry

```bash
# debug
kubectl describe pod <pod>
# events will show the image pull error
kubectl get events --field-selector reason=Failed
```

## Encryption at rest (the real protection)

By default, Secrets in etcd are **base64-encoded, not encrypted**. Anyone with etcd access can read them. The mitigation:

### 1. Encryption at rest in the apiserver

Configure the apiserver with an `EncryptionConfiguration`:

```yaml
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
          secret: c2VjcmV0IGVuY3J5cHRpb24ga2V5Cg==
    - identity: {}              # identity is the fallback (no encryption)
```

Then pass `--encryption-provider-config=/etc/kubernetes/encryption-config.yaml` to the kube-apiserver.

This **encrypts Secrets in etcd at rest**. They remain plaintext over the wire (TLS handles that) and plaintext in the kubelet (which needs to use them).

**Rotating keys** is a separate procedure — the apiserver re-encrypts Secrets on the next read. To force re-encryption, `kubectl get secrets -o yaml --watch` until all are re-encrypted.

### 2. Restrict etcd access

Etcd should be reachable only by the apiserver. No shell access, no debugging tools, no etcdctl from random places. If someone has etcd access, they can read the (now-encrypted) data, but if they have the encryption key, encryption-at-rest doesn't help.

### 3. Use an external secret manager

Vault, AWS Secrets Manager, Azure Key Vault, GCP Secret Manager. The pattern:

1. App uses a sidecar or init container to fetch secrets from the external manager
2. The fetched secrets are mounted as files (or env vars) into the app
3. The k8s Secret is not used; the source of truth is the external manager

Operators for this:

* **Vault Agent Injector** (HashiCorp Vault)
* **External Secrets Operator** (cloud-agnostic, supports AWS / GCP / Azure / Vault)
* **Sealed Secrets** (one-way encryption, useful for GitOps)
* **AWS Secrets Manager CSI Driver** (mounts secrets as files)

The trade-off: extra components, but better security.

## The "everyone can read secrets" anti-pattern

By default, **any user with `get secrets` RBAC can read any Secret**. This is by design — the apiserver doesn't try to enforce "only the app can read its own Secret". If you give a ServiceAccount `get secrets` cluster-wide, you've given it the keys to the kingdom.

The right pattern:

```yaml
# RBAC: only the "app" SA can read "app-secrets"
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: app-secrets-reader, namespace: default }
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["app-secrets"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: app-secrets-reader, namespace: default }
subjects:
- kind: ServiceAccount
  name: app
  namespace: default
roleRef:
  kind: Role
  name: app-secrets-reader
  apiGroup: rbac.authorization.k8s.io
```

This limits `app` to read only `app-secrets` in `default`.

## Bound ServiceAccount tokens (the modern way)

k8s 1.21+ introduced **bound tokens** — short-lived, audience-scoped ServiceAccount tokens. The old long-lived tokens still exist for backward compatibility, but for new code:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: app, namespace: default }
# projected SA token, valid for 1h, audience "vault"
```

The Pod mounts this token as a file. The token:

* Is **valid for a short time** (default 1h, configurable)
* Is **scoped to an audience** — only the right consumer (e.g. Vault) accepts it
* Is **bound to the Pod** — even if leaked, it's tied to one Pod's lifetime

Tools like Vault Agent, External Secrets Operator, IRSA, and Pod Identity all use bound tokens.

## Secrets in Git (the GitOps question)

If you GitOps your manifests, **plaintext Secrets in git are a bad idea**. Options:

* **Sealed Secrets** (Bitnami) — encrypt a Secret with a cluster-specific key, commit the encrypted form. Controller decrypts on apply.
* **External Secrets Operator** — pull from a secret manager at apply time, not stored in git.
* **SOPS** (Mozilla) — encrypt values in YAML, decrypt at apply time with a key from the cluster.
* **Don't store the Secret in git at all** — use a controller or operator to create it on the cluster, and let GitOps only deploy the controller.

## The Secret-vs-ConfigMap question

What's the difference? **Functionally, nothing.** A ConfigMap and a Secret are both key-value bags. The differences are:

* **Type metadata** — Secrets have a `type` field
* **Default RBAC** — list/watch on Secrets is often more restricted
* **Encryption at rest** — Secrets can be encrypted in etcd (ConfigMaps can too, with the same config)
* **Tooling** — some tools treat Secrets specially (e.g. `kubectl create secret`)

In practice:

* If the data is sensitive, use a Secret
* If the data is just config, use a ConfigMap
* Don't put non-sensitive data in a Secret (clutters the audit log, makes RBAC harder)
* Don't put sensitive data in a ConfigMap (it's not protected)

## Gotchas

* **`stringData` is plain text, `data` is base64.** Use `stringData` for readability. Both end up the same in etcd.
* **The Secret data is **fetched by the kubelet at Pod start and held in memory.** Compromised kubelet = compromised secrets. Treat the kubelet as a sensitive component.
* **Updating a Secret updates the mounted files (eventually).** The kubelet syncs every 60-90s. The Pod doesn't restart.
* **Updating a Secret does NOT update env vars.** The env vars are set at Pod start; they don't change. Restart the Pod to pick up new env values.
* **`imagePullSecrets` are not validated at apply time.** A typo'd secret name doesn't fail the apply; it fails the image pull, much later.
* **The `kubernetes.io/service-account-token` type is legacy.** Don't use it for new SAs. Use the bound token API.
* **Secrets in `/proc/<pid>/environ` are visible to anyone with read access to /proc.** Don't run untrusted code in a Pod that has Secrets in env vars.
* **A Secret with no `type` defaults to `Opaque`.** Explicit is better.
* **`kubectl get secret -o yaml` is `get`, which requires RBAC.** Without it, you get a "forbidden" error. With it, you can dump every Secret in the cluster.
* **The `data` field size limit is 1 MiB** (etcd's per-object limit). If your Secret is bigger, you can't store it as one Secret — split it, or use a different mechanism (an external store mounted as a volume).
* **TLS Secrets need both `tls.crt` and `tls.key`.** If you omit either, k8s refuses to create it. cert-manager has a `Certificate` CR that creates them for you.
* **The "image pull secret" referenced by a Pod must exist in the same namespace** as the Pod, or the kubelet can't find it.
* **Secret encryption at rest is opt-in.** The default is identity (no encryption). Always configure it for production.

## See also

* [[Kubernetes/concepts/L05-config-storage/01-config-maps|ConfigMaps]] — the non-sensitive cousin
* [[Kubernetes/concepts/L07-security/01-api-access/02-service-accounts|ServiceAccounts]] — bound tokens, the modern way
* [[Kubernetes/concepts/L05-config-storage/03-volumes|Volume Types]] — for mounted-as-a-file Secrets
* [[Kubernetes/eks/security/secrets-management|EKS Secrets Management]] — AWS-specific
* [[Kubernetes/guides/security/secrets-management-README|Secrets Management Guide]] — practical patterns

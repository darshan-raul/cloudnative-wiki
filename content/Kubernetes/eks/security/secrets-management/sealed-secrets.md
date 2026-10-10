---
title: Sealed Secrets
tags: [eks, security, secrets, sealed-secrets, gitops]
date: 2026-05-17
description: Storing encrypted Kubernetes secrets in Git with Bitnami Sealed Secrets — how the asymmetric scheme works, scopes, the kubeseal workflow, key rotation and backup, disaster recovery and its limits compared with external secret stores.
---

# Sealed Secrets

GitOps wants everything in Git, and a Kubernetes Secret is only base64-encoded — it cannot go there. Sealed Secrets solves that with public-key encryption: you encrypt a secret into a `SealedSecret` resource that is safe to commit, and a controller in the cluster decrypts it into an ordinary Secret.

It is the simplest way to keep secrets in a Git workflow with no external service.

## How it works

```
developer                         Git                       cluster
plain Secret ──kubeseal──► SealedSecret ──commit──► GitOps applies it
            (public key)    (ciphertext)                     │
                                                 sealed-secrets controller
                                                 (holds the private key)
                                                             ▼
                                                    ordinary Secret
```

- The controller generates an RSA key pair at install. The **private key** never leaves the cluster.
- `kubeseal` encrypts each value with the **public key**. Anyone may encrypt; only the controller can decrypt.
- The controller watches `SealedSecret` objects and creates or updates the matching Secret. Deleting the `SealedSecret` deletes the Secret.

## Install

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set fullnameOverride=sealed-secrets-controller
```

Install the `kubeseal` CLI on workstations and CI. Publish the public certificate so that sealing works offline, without cluster access:

```bash
kubeseal --fetch-cert > pub-cert.pem      # commit this; it is public
```

## Sealing a secret

```bash
kubectl create secret generic db-credentials \
  --namespace payments \
  --from-literal=username=app \
  --from-literal=password='S3cr3t!' \
  --dry-run=client -o yaml \
| kubeseal --cert pub-cert.pem --format yaml > db-credentials.sealed.yaml
```

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-credentials
  namespace: payments
spec:
  encryptedData:
    username: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq...
    password: AgCtrfV9dTP1Yx0mN3...
  template:
    metadata:
      labels: { app: payments-api }
```

Commit the sealed file and never the plain one. Avoid leaving the plaintext in shell history: read values from a file or a password manager.

## Scopes

A sealed value is bound to where it may be unsealed, so that a ciphertext copied elsewhere is useless:

| Scope              | Bound to                    | Use                                                                |
| :----------------- | :-------------------------- | :----------------------------------------------------------------- |
| `strict` (default) | This name **and** namespace | Normal case                                                        |
| `namespace-wide`   | The namespace; any name     | Secrets that are renamed or templated                              |
| `cluster-wide`     | Nothing                     | Rarely justified — anyone who can create it anywhere can unseal it |

The default matters for multi-tenancy: a tenant cannot take another team's `SealedSecret` from Git and unseal it in their own namespace.

## Updating and rotating

**Changing a value** means sealing a new file and committing it; the controller updates the Secret. `kubeseal --merge-into` updates a single key without re-sealing the rest. Pods do not restart on their own — use a tool such as Reloader, or a checksum annotation in the pod template.

**The sealing key renews every 30 days** by default. The controller creates a new key and uses it for new seals, but **keeps all old keys**, so existing `SealedSecret` objects keep working. Renewal therefore does not re-encrypt anything already in Git.

That has an important implication. If a sealing private key leaks, every secret ever sealed with it is exposed, and rotating the sealing key does not help. The fix is to **rotate the underlying secrets themselves**. Key renewal limits future exposure; it is not a substitute for rotating credentials.

To re-encrypt existing files with the newest key (hygiene, and required before retiring old keys):

```bash
kubeseal --re-encrypt < db-credentials.sealed.yaml > tmp.yaml && mv tmp.yaml db-credentials.sealed.yaml
```

## Back up the keys

The private keys exist only as Secrets in the controller's namespace. Lose the cluster without a backup and **every sealed secret in Git becomes undecryptable**.

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealing-keys.yaml
```

Store that backup somewhere at least as protected as the secrets themselves — for example [[AWS/security/secrets-manager/README|Secrets Manager]] or an encrypted, access-controlled [[AWS/storage/s3/README|S3]] bucket — and refresh it after each renewal. To restore, apply the key Secrets to the new cluster before installing or restarting the controller.

For several clusters, either seal separately per cluster (strongest isolation, more files) or install the same key pair everywhere (simpler, one key to protect). Decide deliberately; it is part of your [[Kubernetes/guides/non-functional/disaster-recovery|disaster recovery]] plan.

## Limits

| Limitation                                 | Consequence                                                                                                                            |
| :----------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------- |
| The result is a normal Kubernetes Secret   | Readable by anyone with `get secrets` in the namespace; restrict with [[Kubernetes/concepts/L07-security/01-api-access/03-rbac\|RBAC]] |
| No automatic rotation of the secret values | A human or pipeline must re-seal                                                                                                       |
| No central audit of who read a secret      | Only Kubernetes audit logs                                                                                                             |
| Cluster-specific ciphertext                | The same secret is sealed once per cluster                                                                                             |
| The controller is a single point of trust  | Protect its namespace and its keys                                                                                                     |

## Sealed Secrets or an external store

|                            | Sealed Secrets                    | [[Kubernetes/eks/security/secrets-management/secrets-manager\|Secrets Manager + CSI driver or ESO]] | SOPS with KMS                    |
| :------------------------- | :-------------------------------- | :-------------------------------------------------------------------------------------------------- | :------------------------------- |
| Source of truth            | Git (encrypted)                   | AWS                                                                                                 | Git (encrypted)                  |
| External dependency        | None                              | AWS API                                                                                             | [[AWS/security/kms/README\|KMS]] |
| Rotation                   | Manual                            | Built in                                                                                            | Manual                           |
| Access control and audit   | Cluster RBAC                      | IAM and CloudTrail                                                                                  | Key policy and CloudTrail        |
| Key management             | You back up the controller's keys | AWS-managed                                                                                         | AWS-managed                      |
| Works without cloud access | Yes                               | No                                                                                                  | No                               |

Sealed Secrets suits small teams, on-premises or multi-cloud clusters, and anything that must work without a cloud API. On EKS with compliance requirements, an AWS-backed approach usually wins on rotation and audit. SOPS with KMS (built into [[Kubernetes/eks/automation/gitops/flux|Flux]]) is the middle path: secrets in Git, no key backups to manage.

## Related

- [[Kubernetes/eks/security/secrets-management/README|Secrets management on EKS]]
- [[Kubernetes/concepts/L05-config-storage/02-secrets|Secrets (concepts)]]
- [[Kubernetes/guides/delivery/gitops/basics|GitOps basics]]
- [[DevOps/devsecops/stage1-code/06-secrets-detection|Secrets detection]] — catching plaintext before it is committed
- [Sealed Secrets on GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [EKS Workshop: Sealed Secrets](https://www.eksworkshop.com/docs/security/secrets-management/sealed-secrets/)

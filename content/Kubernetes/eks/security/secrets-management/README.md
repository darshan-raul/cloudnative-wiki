---
title: Secrets Management on EKS
tags: [eks, security, secrets, secrets-manager, kms]
date: 2026-05-17
description: The options for handling secrets on EKS — what a Kubernetes Secret does and does not protect, envelope encryption with KMS, external stores versus encrypted-in-Git, a comparison of the tools, and guidance on choosing.
---

# Secrets Management on EKS

A Kubernetes Secret is a delivery mechanism, not a vault. Its values are base64-encoded, stored in etcd, and readable by anyone with `get` on Secrets in the namespace — and by anyone who can create a pod there. Secrets management on EKS is about deciding where the **source of truth** lives and how values reach pods with the least exposure.

The fundamentals are in [[Kubernetes/concepts/L05-config-storage/02-secrets|Secrets (concepts)]] and [[Kubernetes/concepts/L07-security/03-encryption-identity/14-secret-encryption|secret encryption]].

## Notes in this section

- [[Kubernetes/eks/security/secrets-management/secrets-manager|AWS Secrets Manager]] — the Secrets Store CSI Driver with the AWS provider, External Secrets Operator, rotation, and what syncing to a Kubernetes Secret gives up.
- [[Kubernetes/eks/security/secrets-management/sealed-secrets|Sealed Secrets]] — encrypted secrets in Git, decrypted by a controller in the cluster; scopes, key rotation and backup.

## What EKS does by default

- **Encryption at rest.** EKS encrypts etcd volumes, and newer clusters apply envelope encryption to all Kubernetes API data by default. You can supply your own [[AWS/security/kms/README|KMS]] key for Secrets, which adds key-policy control and an audit trail of decryptions in [[AWS/security/cloudtrail/README|CloudTrail]].
- **Encryption in transit.** All API traffic is TLS.

Neither protects against someone who is _authorised_ to read the Secret through the API. That is what [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]] and the choices below are for.

## The approaches

| Approach                            | Source of truth       | Reaches the pod as         | Stored in etcd | Rotation  |
| :---------------------------------- | :-------------------- | :------------------------- | :------------- | :-------- |
| Plain Kubernetes Secrets            | The cluster           | Env vars or files          | Yes            | Manual    |
| **Secrets Store CSI Driver + ASCP** | Secrets Manager / SSM | Files on a tmpfs volume    | No (optional)  | Built in  |
| **External Secrets Operator**       | Secrets Manager / SSM | A synced Kubernetes Secret | Yes            | Built in  |
| **Sealed Secrets**                  | Git (encrypted)       | A Kubernetes Secret        | Yes            | Manual    |
| **SOPS with KMS**                   | Git (encrypted)       | A Kubernetes Secret        | Yes            | Manual    |
| **No secret at all**                | IAM                   | Temporary credentials      | No             | Automatic |

The last row is the most important. Most "secrets" on EKS are AWS credentials, and those should not exist: give the pod an IAM role through [[Kubernetes/eks/security/pod-identity|Pod Identity]] or [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]] and let the SDK fetch short-lived credentials. The same goes for databases that support IAM authentication. **The best-managed secret is the one you eliminated.**

## Choosing

| Situation                                                     | Recommendation                                                            |
| :------------------------------------------------------------ | :------------------------------------------------------------------------ |
| The pod needs to call AWS APIs                                | Pod Identity — no secret                                                  |
| Compliance requires that secrets never rest in etcd           | CSI driver with mounted files, no sync                                    |
| Applications expect environment variables or ordinary Secrets | External Secrets Operator                                                 |
| Automatic rotation and a central audit trail matter           | Secrets Manager with either tool                                          |
| Everything must live in Git; no dependency on a cloud API     | Sealed Secrets                                                            |
| Secrets in Git, with AWS managing the keys                    | SOPS with KMS (native in [[Kubernetes/eks/automation/gitops/flux\|Flux]]) |
| Fargate-only workloads                                        | External Secrets Operator (the CSI driver needs a DaemonSet)              |

Mixing is normal: Pod Identity for AWS access, Secrets Manager for third-party API keys and database passwords, and nothing sensitive in Git in plain text.

## Practices that apply whichever tool you choose

1. **Least privilege on both sides.** Narrow IAM permissions to specific secret paths, and narrow Kubernetes RBAC on `secrets` — `list` and `watch` reveal values just as `get` does.
2. **Prefer mounted files to environment variables.** Environment variables leak into crash dumps, debug output and child processes, and never update in a running process.
3. **Rotate, and make applications tolerate it**: re-read the file, or restart on change.
4. **Separate by namespace and by environment.** One service account, one role, one set of secrets.
5. **Keep secrets out of images, manifests, logs and CI output** — scan for them: [[DevOps/devsecops/stage1-code/06-secrets-detection|secrets detection]].
6. **Audit access.** CloudTrail for Secrets Manager and KMS; Kubernetes [[Kubernetes/eks/observability/logging/control-plane-logs|audit logs]] for Secret reads.
7. **Plan recovery.** Know how secrets are restored after a cluster loss — especially the sealing keys for Sealed Secrets.

## Related

- [[Kubernetes/eks/security/README|EKS security overview]]
- [[AWS/security/secrets-manager/README|AWS Secrets Manager]]
- [[Security/kubernetes-security/secrets/README|Kubernetes Secrets Management]]
- [[DevOps/devsecops/stage4-runtime/16-secret-management|M16: Runtime Secret Management]]
- [[Azure/compute/aks/security-key-vault-csi|AKS Secrets Management — Azure Key Vault Provider for Secrets Store CSI Driver]]
- [EKS best practices: data encryption and secrets management](https://docs.aws.amazon.com/eks/latest/best-practices/data-encryption-and-secrets-management.html)

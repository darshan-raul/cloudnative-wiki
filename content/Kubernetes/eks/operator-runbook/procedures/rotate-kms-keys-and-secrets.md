---
title: "Procedure: Rotate KMS Keys and Application Secrets"
description: "Rotate the KMS key that encrypts EKS Secrets without breaking the cluster, rotate application secrets in Secrets Manager so consumers follow, and respond to a leaked credential."
tags: [kubernetes/eks/operator-runbook, eks, procedure, kms, secrets, rotation]
date: 2026-10-20
aliases: [EKS KMS key rotation, EKS secrets rotation procedure]
---

# Procedure: Rotate KMS Keys and Application Secrets

**Applies to:** clusters using a customer-managed KMS key for Kubernetes Secrets encryption (`encryptionConfig`), and application secrets in AWS Secrets Manager consumed through External Secrets or the Secrets Store CSI driver.
**Duration:** minutes for KMS rotation; per-secret rotation depends on consumers.
**Risk:** low for KMS key material rotation. **Critical** if the key is disabled, deleted, or its policy is broken: that can make the cluster's Secrets unreadable for good.
**Tested:** not run on a live cluster; commands checked for syntax.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1
export KMS_KEY_ARN=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.encryptionConfig[0].provider.keyArn' --output text)
echo "$KMS_KEY_ARN"
```

`None` means the cluster doesn't use a customer-managed key for Secrets encryption. Then only Part B applies.

## Part A: Rotate the cluster's KMS key

### What you can and can't do

- **You can** rotate the key's **material**, automatically or on demand. The key ID and ARN stay the same; KMS keeps old material to decrypt old data, so EKS needs no change.
- **You can't** switch the cluster to a different KMS key, or turn encryption off, after it's enabled. A new key means a new cluster.
- **Never** disable the key, schedule it for deletion, or remove EKS's permissions from its key policy. The API server then can't decrypt Secrets, and a deleted key can't be recovered.

### Pre-checks

```bash
aws kms describe-key --key-id "$KMS_KEY_ARN" --region "$REGION" --query 'KeyMetadata.[KeyState,KeyManager,Origin]'
aws kms get-key-rotation-status --key-id "$KMS_KEY_ARN" --region "$REGION"
```

- **Expect:** `Enabled`, `CUSTOMER`, `AWS_KMS`. Keys with imported material (`EXTERNAL`) or in a custom key store can't use automatic rotation; rotate them by your key-management process.

### Steps

**1. Turn on automatic rotation** (the period can be 90 to 2,560 days):

```bash
aws kms enable-key-rotation --key-id "$KMS_KEY_ARN" --region "$REGION" --rotation-period-in-days 365
```

**2. Rotate now**, if policy or an incident requires it:

```bash
aws kms rotate-key-on-demand --key-id "$KMS_KEY_ARN" --region "$REGION"
aws kms list-key-rotations --key-id "$KMS_KEY_ARN" --region "$REGION" --query 'Rotations[-1]'
```

**3. Optionally re-encrypt existing Secrets** under the newest material, by rewriting them. Rotation doesn't require this, and it touches every Secret, so do it in a quiet window:

```bash
kubectl get secrets -A -o json | kubectl replace -f -
```

### Verify

```bash
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query 'cluster.[status,health.issues]'
kubectl get secret -n kube-system --no-headers | head -3        # Secrets still readable
kubectl create secret generic kms-check -n default --from-literal=x=y && kubectl delete secret kms-check -n default
```

### Protect the key

- Make the key policy deny `kms:DisableKey` and `kms:ScheduleKeyDeletion` to everyone except a tightly held key-admin role.
- Alert on CloudTrail `DisableKey`, `ScheduleKeyDeletion` and `PutKeyPolicy` for this key.
- If a key is scheduled for deletion by mistake, cancel it immediately: `aws kms cancel-key-deletion --key-id "$KMS_KEY_ARN"`, then `aws kms enable-key`.

## Part B: Rotate an application secret in Secrets Manager

**Pre-checks:**

- You know every consumer: which namespaces sync this secret, and how each Pod consumes it (file or env var); see the delivery table in [[Kubernetes/eks/operator-runbook/runbooks/secrets-not-syncing|Secrets not syncing]].
- Consumers that read it only at startup have a restart plan.
- For database credentials, rotation uses a Lambda rotation function, and the old password stops working once rotation completes. Use the alternating-users strategy if consumers can't switch instantly.

**Steps:**

```bash
export AWS_SECRET_ID=<secret>
aws secretsmanager rotate-secret --region "$REGION" --secret-id "$AWS_SECRET_ID"
aws secretsmanager describe-secret --region "$REGION" --secret-id "$AWS_SECRET_ID" \
  --query '{rotated:LastRotatedDate,stages:VersionIdsToStages}'
```

Then force the Kubernetes sync (`kubectl annotate externalsecret <name> -n <ns> force-sync="$(date +%s)" --overwrite`), and restart the consumers that don't reload: `kubectl rollout restart deploy/<name> -n <ns>`.

**Verify:** the application logs successful connections with the new credential, and no authentication errors appear over the next refresh interval.

**Rollback:** Secrets Manager keeps the previous version under the `AWSPREVIOUS` stage. For a non-database secret, move `AWSCURRENT` back with `aws secretsmanager update-secret-version-stage`. For a rotated database password, the old one may already be invalid, so fix forward.

## Part C: A credential has leaked

1. **Revoke first, then investigate.** Rotate the secret (Part B), or, for IAM access keys, deactivate them (`aws iam update-access-key --status Inactive`).
2. Restart consumers so nothing keeps using the leaked value.
3. Search CloudTrail and the application logs for use of the leaked credential since the exposure.
4. If it was a Kubernetes service account token, delete the token Secret (for legacy long-lived tokens), or the service account. Bound tokens expire on their own (one hour by default on EKS, extended for older clients).
5. Remove the leaked value from wherever it was exposed (repository history, logs, tickets).

## Background

- [[AWS/security/kms/README|AWS KMS]]
- [[Kubernetes/concepts/L07-security/03-encryption-identity/14-secret-encryption|Secret encryption]]
- [[Kubernetes/eks/security/secrets-management/secrets-manager|Secrets Manager with EKS]]
- [Encrypt Kubernetes secrets with KMS on existing clusters](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html)
- [Rotating AWS KMS keys](https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html)

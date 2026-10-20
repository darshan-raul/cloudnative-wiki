---
title: "Runbook: Secrets Not Syncing from AWS (External Secrets, Secrets Store CSI)"
description: "A rotated or new secret in Secrets Manager or Parameter Store doesn't reach the Pod. Find whether the sync failed, the Kubernetes Secret is current but the Pod hasn't reloaded, or the mount itself fails."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    secrets,
    secrets-manager,
    incident,
  ]
date: 2026-10-20
aliases: [External Secrets not syncing, Secrets Store CSI driver mount failure]
---

# Runbook: Secrets Not Syncing from AWS (External Secrets, Secrets Store CSI)

**Applies to:** the External Secrets Operator (ESO) and the Secrets Store CSI Driver with the AWS provider (ASCP), reading from AWS Secrets Manager or SSM Parameter Store. Sealed Secrets are covered briefly at the end.
**Typical severity:** Sev 2 when a rotation breaks a database or API connection; Sev 3 when a new secret doesn't appear.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

- After a rotation, applications fail authentication with the **old** credential.
- `ExternalSecret` shows `READY False` with `SecretSyncedError`.
- Pods stay `ContainerCreating` with `FailedMount ... failed to mount secrets store objects for pod`.

## Find the broken link

A secret goes through up to three hops. Find which one is stale:

```text
AWS secret  --(1) sync-->  Kubernetes Secret  --(2) delivery-->  Pod (env var or file)  --(3) reload-->  application
```

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export REGION=us-east-1 NS=<namespace> SECRET=<kubernetes secret name> AWS_SECRET_ID=<secret name or ARN>
```

## Triage

**1. Compare versions at each hop.** Compare the AWS value's version and timestamp, not the value itself; don't print secret values into terminals or tickets:

```bash
aws secretsmanager describe-secret --region "$REGION" --secret-id "$AWS_SECRET_ID" \
  --query '{changed:LastChangedDate,rotated:LastRotatedDate,versions:VersionIdsToStages}'
kubectl get secret "$SECRET" -n "$NS" -o jsonpath='{.metadata.creationTimestamp}{"  "}{.metadata.resourceVersion}{"  "}{.metadata.annotations}{"\n"}'
# Short hash of each key's value, so you can compare without printing secrets
kubectl get secret "$SECRET" -n "$NS" -o json | jq -r '.data | to_entries[] | "\(.key)\t\(.value)"' \
  | while IFS=$'\t' read -r k v; do printf '%s %s\n' "$k" "$(printf %s "$v" | base64 -d | sha256sum | cut -c1-12)"; done
```

To compare with AWS without showing the value, hash it the same way: `printf %s "$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$AWS_SECRET_ID" --query SecretString --output text)" | sha256sum | cut -c1-12`. That only works for a whole-string secret mapped to one key. For JSON secrets mapped per key, compare the timestamps instead.

- **If** the Kubernetes Secret is older than the AWS change → hop 1, sync (cause A or B).
- **If** the Kubernetes Secret is current but Pods use the old value → hop 2 or 3, delivery or reload (cause C).

**2. External Secrets Operator status:**

```bash
kubectl get externalsecrets -n "$NS"
kubectl describe externalsecret <name> -n "$NS" | sed -n '/Status:/,$p'
kubectl get secretstores,clustersecretstores -A
kubectl logs -n external-secrets deploy/external-secrets --tail=100 | grep -iE 'error|denied' | tail
```

**3. Secrets Store CSI:**

```bash
kubectl describe pod <pod> -n "$NS" | grep -A5 FailedMount
kubectl get secretproviderclass -n "$NS"
kubectl logs -n kube-system -l app=csi-secrets-store-provider-aws --tail=50
kubectl logs -n kube-system -l app=secrets-store-csi-driver -c secrets-store --tail=50
```

## Diagnosis

| Signal                                                                                       | Cause                                              | Fix   |
| -------------------------------------------------------------------------------------------- | -------------------------------------------------- | ----- |
| `AccessDeniedException` (`secretsmanager:GetSecretValue`, `ssm:GetParameter`, `kms:Decrypt`) | A. IAM or KMS permission                           | Fix A |
| `ResourceNotFoundException`; wrong name, ARN or region; SecretStore not `Valid`              | B. Reference or store configuration                | Fix B |
| Kubernetes Secret current; Pod still uses the old value                                      | C. Delivery or reload                              | Fix C |
| Sync succeeds but only every hour                                                            | D. Refresh interval longer than the rotation needs | Fix D |

## Fix

### A. IAM or KMS permission

The identity that reads the secret depends on the tool:

- **ESO:** the role of the `SecretStore` (`auth.jwt.serviceAccountRef`) or of the operator's own service account (Pod Identity or IRSA).
- **ASCP:** the **application Pod's** service account (IRSA, or Pod Identity with `usePodIdentity: "true"` in the SecretProviderClass).

The role needs `secretsmanager:GetSecretValue` and `DescribeSecret` (or `ssm:GetParameter(s)`) on the secret ARN, and `kms:Decrypt` on the key if it's a customer-managed key. Check the secret's resource policy too. For Pod Identity or IRSA wiring problems, see [[Kubernetes/eks/operator-runbook/runbooks/workload-aws-access-denied|workload AccessDenied]].

### B. Reference or store configuration

Fix the `remoteRef.key` (ESO) or `objectName` (ASCP) to the right name or ARN, in the right region. A `SecretStore` that isn't `Valid` names its problem in `status.conditions`, typically a wrong region or auth block.

**Force an ESO sync** once fixed, instead of waiting for the refresh interval:

```bash
kubectl annotate externalsecret <name> -n "$NS" force-sync="$(date +%s)" --overwrite
```

### C. Delivery or reload

How the Pod consumes the Secret decides whether it ever sees the change:

| Consumption                             | Picks up changes?                                                                              |
| --------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Environment variable (`env`, `envFrom`) | **Never**, until the Pod restarts                                                              |
| Secret volume                           | Yes, after the kubelet's sync (typically within a minute or two)                               |
| Secret volume with `subPath`            | **Never**, until the Pod restarts                                                              |
| ASCP CSI volume                         | Only with rotation enabled on the driver (`enableSecretRotation=true`, `rotationPollInterval`) |

Then the **application** has to re-read the file. Many read credentials once at startup.

- **Now:** restart the consumers: `kubectl rollout restart deploy/<name> -n "$NS"`.
- **Permanently:** mount as a volume without `subPath` and have the app re-read it, or use a reloader controller (for example Stakater Reloader) that restarts Deployments when their Secret changes.

For database credentials rotated by Secrets Manager, the **old** version (`AWSPREVIOUS`) stops working when rotation completes. Consumers must pick up the new one within that window, or use the alternating-users rotation strategy.

### D. Refresh interval

ESO's `refreshInterval` (often `1h`) is the maximum delay between AWS and Kubernetes. Shorten it for secrets that rotate. Each refresh is an AWS API call per ExternalSecret, so keep it reasonable (minutes, not seconds) on large clusters.

## Sealed Secrets

`no key could decrypt secret` after a cluster rebuild or controller reinstall means the controller's private key changed. Restore the old key Secret (`sealedsecrets.bitnami.com/sealed-secrets-key` labelled Secrets in the controller namespace) from backup, and restart the controller, or re-seal every secret with the new key. Back up those keys.

## Verify recovery

- `kubectl get externalsecrets -n "$NS"` shows `READY True` with a recent sync time.
- The hashes or timestamps from Triage step 1 match at every hop.
- The application authenticates with the new credential; check its logs, not just Pod status.

## Escalate

Escalate to the secret's owner (the team or pipeline that rotates it) if the AWS side is wrong. AWS Support is needed only if Secrets Manager or SSM APIs fail with server errors.

## Prevent

- Alert on `ExternalSecret` `Ready=False`, and on ESO sync error metrics.
- Test rotation in staging end to end, including the application reload.
- Consume secrets as files, not environment variables, for anything that rotates.
- Back up the Sealed Secrets controller keys.

## Background

- [[Kubernetes/eks/security/secrets-management/README|Secrets management on EKS]]
- [[Kubernetes/eks/security/secrets-management/secrets-manager|AWS Secrets Manager with EKS]]
- [[Kubernetes/eks/security/secrets-management/sealed-secrets|Sealed Secrets]]
- [External Secrets Operator: AWS Secrets Manager provider](https://external-secrets.io/latest/provider/aws-secrets-manager/)

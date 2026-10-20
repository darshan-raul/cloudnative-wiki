---
title: "Procedure: Upgrade an EKS Managed Add-on"
description: "Choose a compatible version, carry configuration over safely, update with PRESERVE, verify, and know what to do when the update degrades the add-on."
tags: [kubernetes/eks/operator-runbook, eks, procedure, add-ons, upgrades]
date: 2026-10-20
aliases: [EKS add-on update procedure]
---

# Procedure: Upgrade an EKS Managed Add-on

**Applies to:** EKS managed add-ons such as `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`, `eks-pod-identity-agent` and `amazon-cloudwatch-observability`.
**Duration:** 5–15 minutes per add-on. DaemonSet add-ons roll node by node.
**Risk:** medium for `vpc-cni`, `coredns` and `kube-proxy` (cluster networking); low for most others.
**Tested:** not run on a live cluster; commands checked for syntax.

## When to use

- As part of a [[Kubernetes/eks/operator-runbook/procedures/control-plane-upgrade|control-plane upgrade]].
- For a fix or feature in a newer add-on version.
- When EKS insights or health issues flag the installed version.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1 ADDON=<add-on name>
export K8S=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.version --output text)
```

## Pre-checks

**1. Record the current state.** This is your only rollback reference.

```bash
aws eks describe-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name "$ADDON" \
  | tee "$EVIDENCE_DIR/addon-$ADDON-before.json" \
  | jq '.addon | {addonVersion, status, serviceAccountRoleArn, configurationValues, podIdentityAssociations, health}'
```

- **Expect:** `status: ACTIVE`. Don't upgrade an add-on that's already `DEGRADED` until you know why.

**2. Choose the target version.** Use the default for your cluster version unless you need something newer:

```bash
aws eks describe-addon-versions --addon-name "$ADDON" --kubernetes-version "$K8S" --region "$REGION" \
  --query 'addons[].addonVersions[].[addonVersion,compatibilities[0].defaultVersion]' --output table
export NEW_VERSION=<chosen version>
```

Read the add-on's release notes (for `vpc-cni`, its GitHub releases) for the versions between current and target. For `vpc-cni`, AWS recommends moving **one minor version at a time**.

**3. Check the configuration schema still accepts your values.**

```bash
aws eks describe-addon-configuration --addon-name "$ADDON" --addon-version "$NEW_VERSION" --region "$REGION" \
  --query configurationSchema --output text | jq '.properties | keys'
```

Every top-level key in your current `configurationValues` must still exist.

**4. Look for manual drift.** If someone edited the add-on's objects by hand (for example `kubectl set env` on `aws-node`), those values aren't in `configurationValues`. Compare:

```bash
kubectl get ds aws-node -n kube-system -o json | jq '.spec.template.spec.containers[] | {name, env}'   # vpc-cni example
```

Move wanted manual settings into `configurationValues` before the upgrade. `PRESERVE` keeps conflicting fields this time, but they stay invisible to IaC.

## Steps

**1. Update.**

```bash
UPDATE_ID=$(aws eks update-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name "$ADDON" \
  --addon-version "$NEW_VERSION" --resolve-conflicts PRESERVE \
  --query update.id --output text)
aws eks describe-update --name "$CLUSTER" --region "$REGION" --addon-name "$ADDON" --update-id "$UPDATE_ID" \
  --query 'update.[status,errors]'
```

To change configuration in the same step, add `--configuration-values file://values.json`. Values you pass replace the whole configuration, so include every key you want to keep.

`--resolve-conflicts` options: `PRESERVE` keeps fields changed outside EKS; `OVERWRITE` resets them to EKS defaults. Use `OVERWRITE` only when you've confirmed nothing manual is needed.

**2. Watch the rollout.**

```bash
kubectl rollout status ds/aws-node -n kube-system --timeout=15m        # vpc-cni
kubectl rollout status ds/kube-proxy -n kube-system --timeout=15m      # kube-proxy
kubectl rollout status deploy/coredns -n kube-system --timeout=5m      # coredns
aws eks describe-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name "$ADDON" \
  --query 'addon.[addonVersion,status,health.issues]'
```

- **Checkpoint:** `ACTIVE`, no health issues, and all Pods of the add-on Ready.

## Smoke tests

- **vpc-cni:** create a Pod on a few different nodes, and check that it gets an IP and can reach a Pod on another node and the internet.
- **coredns:** run the DNS loop from [[Kubernetes/eks/operator-runbook/runbooks/dns-timeouts-coredns|DNS timeouts]] Triage step 1.
- **kube-proxy:** a ClusterIP Service answers from another node.
- **aws-ebs-csi-driver:** create and delete a small PVC with a test Pod.

## Abort criteria and rollback

Stop if new add-on Pods crash-loop, Pods can't get IPs, DNS fails, or error rates rise.

Test add-on upgrades in staging first. If an upgrade breaks things:

1. Read the new Pods' logs: `kubectl logs -n kube-system <pod> --previous`. A configuration-schema change, or a missing IAM permission for the new version, are the usual causes. Fix forward with a corrected `--configuration-values`, or an IAM policy update.
2. If the add-on must go back to the old version, update it to that version. `update-addon` accepts an earlier version from `describe-addon-versions` for your cluster's Kubernetes version:

   ```bash
   aws eks update-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name "$ADDON" \
     --addon-version <previous version from the pre-check record> --resolve-conflicts PRESERVE
   ```

   Pass the previous `configurationValues` too if you changed them in the upgrade. If the old version doesn't run with the new configuration schema, fix the configuration first.

## If the add-on is DEGRADED or the update failed

```bash
aws eks describe-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name "$ADDON" \
  --query 'addon.{status:status,version:addonVersion,issues:health.issues}'
aws eks describe-update --name "$CLUSTER" --region "$REGION" --addon-name "$ADDON" --update-id "$UPDATE_ID" \
  --query 'update.errors'
```

| Health issue code              | Meaning and fix                                                                                                                                                                                                                                                            |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ConfigurationConflict`        | Fields the add-on manages were changed by someone else (`kubectl edit`, Helm, GitOps). Move the wanted values into `--configuration-values`, then update with `PRESERVE`, or `OVERWRITE` once nothing manual is needed. Stop any other tool from managing the same objects |
| `InsufficientNumberOfReplicas` | Add-on Pods aren't Ready. Read their events and logs: Pending (capacity, taints), crash-looping (configuration or IAM), or image pull failures                                                                                                                             |
| `AccessDenied`                 | The add-on's IAM role (`serviceAccountRoleArn` or its Pod Identity association) lacks permissions the new version needs. Compare with the add-on's documented policy                                                                                                       |
| `AdmissionRequestDenied`       | An admission webhook or policy (Kyverno, Gatekeeper, Pod Security) rejected the add-on's objects. Add a scoped exception for the add-on, rather than weakening the policy for everything                                                                                   |
| `UnsupportedAddonModification` | A change to the add-on's objects isn't allowed. Revert it, and make the change through `--configuration-values` if the schema supports it                                                                                                                                  |
| `ClusterUnreachable`           | EKS can't reach the API server to apply the add-on. Check the cluster's status and endpoint access settings                                                                                                                                                                |

An update that failed leaves the previous version running in most cases. Once the cause is fixed, run the same `update-addon` again.

## Post-checks and clean-up

- Update IaC (Terraform, CDK, eksctl config) to the new version and configuration, so the next apply doesn't revert it.
- Record the old and new versions in the change log.

## Background

- [Amazon EKS add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- [[Kubernetes/eks/networking/vpc-cni/configuration-reference|VPC CNI configuration reference]]
- [[Kubernetes/eks/operator-runbook/reference/command-conventions|Command conventions]]

---
title: "Procedure: Migrate from aws-auth to EKS Access Entries"
description: "Move every aws-auth mapping to access entries with no loss of access for people, pipelines or nodes, then switch the cluster to API-only authentication."
tags: [kubernetes/eks/operator-runbook, eks, procedure, access, iam, rbac]
date: 2026-10-20
aliases: [aws-auth migration, EKS access entries migration]
---

# Procedure: Migrate from aws-auth to EKS Access Entries

**Applies to:** clusters in `CONFIG_MAP` or `API_AND_CONFIG_MAP` authentication mode.
**Duration:** about an hour for a typical cluster, plus a soak period before the final switch.
**Risk:** high if rushed: a missed mapping locks out a person, a pipeline or the nodes. Each step below is reversible except the mode changes, which only move forward.
**Tested:** not run on a live cluster; commands checked for syntax.

## Why

`aws-auth` is a single ConfigMap. One bad edit, or one wrong overwrite by a tool, can lock out everyone including the nodes, and fixing it needs Kubernetes access. Access entries live in the EKS API, are managed with IAM permissions, are audited in CloudTrail, and can be fixed even when nobody can reach Kubernetes.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1
```

## Pre-checks

**1. Record the current mode and mappings.**

```bash
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.accessConfig
kubectl get configmap aws-auth -n kube-system -o yaml | tee "$EVIDENCE_DIR/aws-auth-before.yaml"
aws eks list-access-entries --cluster-name "$CLUSTER" --region "$REGION"
```

**2. Inventory each mapping.** For every `mapRoles` and `mapUsers` entry, note the ARN, the username and the groups, and work out the replacement:

| aws-auth mapping                                           | Access entry                                                                                                               |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Node role, groups `system:bootstrappers`, `system:nodes`   | `--type EC2_LINUX` (or `EC2_WINDOWS`). No groups or policies needed                                                        |
| Fargate pod execution role                                 | `--type FARGATE_LINUX`                                                                                                     |
| Role in `system:masters`                                   | Standard entry plus `AmazonEKSClusterAdminPolicy` with cluster scope. **`system:masters` can't be set on an access entry** |
| Role in custom groups (e.g. `dev-team`) bound by your RBAC | Standard entry with `--kubernetes-groups dev-team`. Your existing RoleBindings keep working                                |
| Role needing a common built-in level (view, edit, admin)   | Standard entry plus `AmazonEKSViewPolicy`, `EditPolicy` or `AdminPolicy`, scoped by namespace where possible               |

A role ARN in `aws-auth` has its path stripped. The access entry needs the **full** ARN, including any path (`arn:aws:iam::<acct>:role/teams/dev/Dev`); get it with `aws iam get-role --role-name Dev --query Role.Arn`.

**3. Make sure you have a working break-glass path:** a role with `eks:CreateAccessEntry` and `eks:AssociateAccessPolicy`. With it you can recover access through the EKS API whatever happens. If you don't have one, set it up first with [[Kubernetes/eks/operator-runbook/procedures/break-glass-access-setup|Break-glass access setup]].

## Steps

**1. Enable access entries alongside the ConfigMap** (skip if already `API_AND_CONFIG_MAP`). This is **one-way**: you can't return to `CONFIG_MAP`. It doesn't change existing access.

```bash
aws eks update-cluster-config --name "$CLUSTER" --region "$REGION" \
  --access-config authenticationMode=API_AND_CONFIG_MAP
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.status   # wait for ACTIVE
```

**2. Create the entries**, through IaC if possible. CLI examples:

```bash
# Node role
aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION" \
  --principal-arn arn:aws:iam::111122223333:role/eks-node-role --type EC2_LINUX

# Admin role (was system:masters)
aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION" \
  --principal-arn arn:aws:iam::111122223333:role/PlatformAdmin
aws eks associate-access-policy --cluster-name "$CLUSTER" --region "$REGION" \
  --principal-arn arn:aws:iam::111122223333:role/PlatformAdmin \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster

# Team role mapped to an RBAC group
aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION" \
  --principal-arn arn:aws:iam::111122223333:role/teams/dev/Dev --kubernetes-groups dev-team
```

Managed node groups and Fargate profiles created while access entries are enabled get their entries automatically; check `list-access-entries` for each node role anyway.

**3. Verify each principal through access entries.** When an access entry exists for a principal, EKS uses it instead of `aws-auth`, so each test proves the new path:

```bash
kubectl auth whoami                     # run as each migrated role
kubectl auth can-i --list -n <namespace>
```

Check every pipeline and GitOps identity by running a real deploy, not just `whoami`.

- **Checkpoint:** every mapping from pre-check 2 has an entry, and each works. Compare the two lists:

```bash
aws eks list-access-entries --cluster-name "$CLUSTER" --region "$REGION" --query 'accessEntries[]' --output text | tr '\t' '\n' | sort
```

**4. Soak.** Leave `aws-auth` in place for a few days, so anything missed shows up while the old path still works. In the audit log, search for requests whose identity has no access entry. Authenticator logs show which mapping source was used.

**5. Switch to API-only** (also one-way). From here on, `aws-auth` is ignored:

```bash
aws eks update-cluster-config --name "$CLUSTER" --region "$REGION" --access-config authenticationMode=API
```

**6. After another check of nodes and pipelines**, delete the ConfigMap, and remove it from IaC and from tools that write it (older eksctl configs, Terraform modules):

```bash
kubectl get nodes          # all Ready
kubectl delete configmap aws-auth -n kube-system
```

## Abort criteria and rollback

- **Before step 5:** if a principal loses access, recreate or fix its access entry, or delete the faulty entry so EKS falls back to its `aws-auth` mapping.
- **After step 5:** there's no fallback. Recover any principal with the break-glass role (`create-access-entry`); see [[Kubernetes/eks/operator-runbook/runbooks/kubectl-unauthorized-or-forbidden|kubectl Unauthorized]] Fix C.
- **Nodes going NotReady** at any point means the node role entry is missing. Create it with `--type EC2_LINUX`; nodes recover within a minute.

## Post-checks and clean-up

- `aws eks describe-cluster --query cluster.accessConfig` shows `API`.
- Every node is Ready, and every pipeline deploys.
- Remove any temporary break-glass entry. Document the standing one, and alert on its use.

## Background

- [[Kubernetes/eks/security/access/cluster-access-management|Cluster access management]]
- [[Kubernetes/eks/security/access/aws-auth-legacy|aws-auth (legacy)]]
- [Migrating existing aws-auth ConfigMap entries to access entries](https://docs.aws.amazon.com/eks/latest/userguide/migrating-access-entries.html)

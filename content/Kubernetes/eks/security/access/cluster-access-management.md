---
title: EKS Cluster Access Management
tags: [eks, security, access, iam, rbac]
date: 2026-05-17
description: Granting IAM principals access to an EKS cluster with access entries and access policies — authentication modes, policy scopes, mapping to Kubernetes RBAC and migrating off aws-auth.
---

# EKS Cluster Access Management

Cluster access management is the EKS API for answering "which [[AWS/security/iam/README|IAM]] principals may use this cluster, and as what?". It replaces the `aws-auth` ConfigMap with two AWS-side objects:

- an **access entry** — binds one IAM role or user to the cluster, optionally with a Kubernetes username and groups;
- an **access policy** — an AWS-managed permission set attached to an entry, scoped to the cluster or to specific namespaces.

Because both live in the EKS API rather than inside the cluster, access can be granted with CloudFormation or Terraform before the cluster has a single node, every change is recorded in [[AWS/security/cloudtrail/README|CloudTrail]], and a typo cannot lock everyone out the way a malformed ConfigMap could.

## Authentication happens in two steps

1. **Authentication.** `kubectl` presents a token that is a pre-signed STS `GetCallerIdentity` request. The EKS control plane verifies it and learns the caller's IAM ARN. For an assumed role, the _role_ ARN is used, not the session.
2. **Authorization.** EKS looks up the access entry for that ARN. Permissions then come from attached access policies, from Kubernetes [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]] bindings on the entry's groups, or both.

More background: [[Kubernetes/eks/security/access/authentication-patterns|authentication patterns]] and [[Kubernetes/concepts/L07-security/01-api-access/01-authentication-authorization|authentication and authorization]].

## Authentication mode

| Mode                 | Sources consulted               | When                                               |
| :------------------- | :------------------------------ | :------------------------------------------------- |
| `CONFIG_MAP`         | `aws-auth` only                 | Legacy clusters                                    |
| `API_AND_CONFIG_MAP` | Access entries, then `aws-auth` | Migration period                                   |
| `API`                | Access entries only             | The target state, and the default for new clusters |

The mode can only move forward: `CONFIG_MAP` → `API_AND_CONFIG_MAP` → `API`. There is no way back.

```bash
aws eks update-cluster-config --name my-cluster \
  --access-config authenticationMode=API_AND_CONFIG_MAP
```

## Granting access

```bash
# 1. Register the principal
aws eks create-access-entry \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::111122223333:role/platform-admin

# 2a. Cluster-wide admin
aws eks associate-access-policy \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::111122223333:role/platform-admin \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster

# 2b. Or edit rights in two namespaces only
aws eks associate-access-policy \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::111122223333:role/team-payments \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
  --access-scope type=namespace,namespaces=payments,payments-staging
```

## Access policies

| Policy                        | Roughly equivalent to          | Typical holder                     |
| :---------------------------- | :----------------------------- | :--------------------------------- |
| `AmazonEKSClusterAdminPolicy` | `cluster-admin`                | Platform team, break-glass role    |
| `AmazonEKSAdminPolicy`        | `admin` (namespace-scoped use) | Team leads within their namespaces |
| `AmazonEKSEditPolicy`         | `edit`                         | Developers, CI deploy roles        |
| `AmazonEKSViewPolicy`         | `view`                         | Read-only users, dashboards        |
| `AmazonEKSAdminViewPolicy`    | View including Secrets         | Auditors, support                  |

Access policies are AWS-managed and cannot be customised. They are not IAM policies, despite the ARN.

## When you need custom permissions

Give the entry Kubernetes groups and bind them yourself:

```bash
aws eks create-access-entry \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::111122223333:role/log-reader \
  --kubernetes-groups log-readers
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: log-readers
subjects:
  - kind: Group
    name: log-readers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: pod-log-reader
  apiGroup: rbac.authorization.k8s.io
```

Group names starting with `system:` are reserved, so an access entry cannot place a principal in `system:masters`. That is deliberate: `system:masters` bypasses RBAC and cannot be audited or revoked by policy.

## Entry types

| Type                       | For                                                                                          |
| :------------------------- | :------------------------------------------------------------------------------------------- |
| `STANDARD`                 | Humans and automation                                                                        |
| `EC2_LINUX`, `EC2_WINDOWS` | Node roles for self-managed nodes and [[Kubernetes/eks/compute/karpenter/README\|Karpenter]] |
| `FARGATE_LINUX`            | Fargate pod execution roles                                                                  |
| `EC2`, `HYBRID_LINUX`      | Auto Mode node roles and hybrid nodes                                                        |

Managed node groups and Fargate profiles create their entries automatically.

## The cluster creator

Historically the principal that created a cluster was a hidden, permanent admin that appeared nowhere. With access entries it becomes a visible entry you can remove. For new clusters, set `bootstrapClusterCreatorAdminPermissions=false` and grant admin explicitly to a role, so that access does not depend on whichever pipeline or person ran the create call.

## Migrating from aws-auth

1. Switch to `API_AND_CONFIG_MAP`.
2. Create an access entry for each `mapRoles` / `mapUsers` item. `eksctl utils migrate-to-access-entry` automates this.
3. Verify with `kubectl auth can-i --list --as-group=…` and by exercising real roles.
4. Remove the ConfigMap entries, then switch to `API`.

Details of the old mechanism are in [[Kubernetes/eks/security/access/aws-auth-legacy|aws-auth (legacy)]].

## Good practice

- Grant access to **roles**, not users, and federate humans through IAM Identity Center.
- Prefer namespace-scoped policies; keep cluster admin for a small break-glass role with alerting on its use.
- Manage entries as code alongside the cluster definition.
- Pair with a locked-down API endpoint — [[Kubernetes/eks/security/access/endpoint-access|endpoint access]].

## Related

- [[Kubernetes/eks/security/access/README|EKS access overview]]
- [[Kubernetes/eks/security/pod-identity|Pod Identity]] — the workload-side counterpart
- [[AWS/security/iam/various-types-of-roles|Types of IAM roles]]
- [Access entries user guide](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)

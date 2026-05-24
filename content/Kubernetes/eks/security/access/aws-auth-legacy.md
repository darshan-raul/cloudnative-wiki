---
title: Legacy aws-auth ConfigMap
tags: [eks, security, access, aws-auth, legacy]
date: 2026-05-17
description: Legacy aws-auth ConfigMap for EKS cluster access - history and migration
---

# Legacy aws-auth ConfigMap

## Overview

The `aws-auth` ConfigMap in `kube-system` namespace was the **original mechanism** for granting IAM principals access to EKS clusters. It maps IAM roles and users to Kubernetes RBAC groups.

**Status:** Legacy - replaced by [[Kubernetes/eks/security/access/cluster-access-management|Cluster Access API]] (2019)

## ConfigMap Structure

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: arn:aws:iam::123456789:role/NodeRole
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
  mapUsers: |
    - userarn: arn:aws:iam::123456789:user/admin
      username: admin
      groups:
        - system:masters
```

## mapRoles - Node Access

Required for self-managed nodes to join the cluster:

```yaml
mapRoles: |
  - rolearn: arn:aws:iam::123456789:role/NodeInstanceRole
    username: system:node:{{EC2PrivateDNSName}}
    groups:
      - system:bootstrappers
      - system:nodes
```

| Group | Purpose |
|-------|---------|
| `system:bootstrappers` | Required for kubelet to bootstrap |
| `system:nodes` | Required for node registration |

### Template Variable

| Variable | Resolves To |
|----------|-------------|
| `{{EC2PrivateDNSName}}` | Node's private DNS name |

## mapUsers - Human Access

```yaml
mapUsers: |
  - userarn: arn:aws:iam::123456789:user/developer
    username: developer
    groups:
      - system:masters
  - userarn: arn:aws:iam::123456789:user/readonly
    username: readonly
    groups:
      - view  # Built-in read-only role
```

| Built-in RBAC Role | Access Level |
|--------------------|--------------|
| `system:masters` | Full cluster access (superuser) |
| `system:node` | Node-specific operations |
| `view` | Read-only to all resources (except secrets) |
| `edit` | Read/write to most resources (except role bindings) |
| `admin` | Read/write plus ability to create roles/bindings |

## Why Cluster Access API is Preferred

| Aspect | aws-auth ConfigMap | Cluster Access API |
|--------|-------------------|---------------------|
| Management | Manual kubectl edit | AWS API/Console |
| Audit trail | None | CloudTrail logging |
| Validation | None (silent failures) | AWS validates inputs |
| Lifecycle | Manual | Managed with cluster |
| Migration | N/A | Clean separation |
| Deletion | kubectl delete | AWS API call |

### Audit Trail Comparison

**aws-auth:** No audit trail for ConfigMap changes

**Cluster Access API:**
```bash
# CloudTrail logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssociateAccessPolicy
```

## Migration Path

### Step 1: Create Access Entries (New Way)

```bash
# Create access entry for IAM user
aws eks create-access-entry \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789:user/admin \
  --username admin

# Associate policy
aws eks associate-access-policy \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789:user/admin \
  --policy-arn arn:aws:eks::aws:cluster-access-policy:AmazonEKSClusterAdmin

# Create access entry for IAM role
aws eks create-access-entry \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789:role/developer
```

### Step 2: Verify New Access Works

```bash
# Test as the user/role
aws eks update-kubeconfig --name my-cluster
kubectl auth can-i "*" "*"  # Should show permissions
```

### Step 3: Remove from aws-auth (Optional)

After verifying all entries work via Cluster Access API:

```bash
# Edit configmap
kubectl edit configmap aws-auth -n kube-system

# Remove entries from mapUsers/mapRoles
# Keep NodeInstanceRole entry if using self-managed nodes
```

### Coexistence

**aws-auth entries and Cluster Access API entries coexist.** EKS evaluates both.

## When You Might Still See aws-auth

### 1. Self-Managed Node Groups

The `mapRoles` entry for node instance roles is often kept:

```yaml
mapRoles: |
  - rolearn: arn:aws:iam::123456789:role/NodeInstanceRole
    username: system:node:{{EC2PrivateDNSName}}
    groups:
      - system:bootstrappers
      - system:nodes
```

### 2. Existing Clusters (Pre-2019)

Clusters created before Cluster Access API may have all access via aws-auth.

### 3. Manual kubectl Edits

Some teams still use aws-auth for quick access grants, though this is not recommended.

## Generating mapRoles Entry

For managed node groups, eksctl generates this automatically:

```bash
# Get node instance role
aws iam get-role --role-name eksNodeRole

# The role ARN goes into mapRoles
```

For managed node groups, EKS can auto-manage the node entry:

```bash
# Enable EKS management of node IAM role
aws eks update-cluster-config \
  --name my-cluster \
  --access-config accessConfigauthenticationMode=API_AND_CONFIG_MAP
```

With this enabled, EKS automatically adds node entries and you don't need to manage them manually.

## Security Considerations

| Risk | Mitigation |
|------|-----------|
| No audit trail | Use Cluster Access API for new grants |
| Manual errors | Cluster Access API validates inputs |
| Overly broad access | Follow least-privilege in RBAC groups |
| Deleted users still in ConfigMap | Regular audit of aws-auth entries |

## Viewing Current Configuration

```bash
# View current aws-auth
kubectl get configmap aws-auth -n kube-system -o yaml

# Check what Cluster Access API knows
aws eks list-access-entries --cluster-name my-cluster

# Describe specific access
aws eks describe-access-entry \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789:user/admin
```

## Common ConfigMap Patterns

### Grant Namespace-Only Access

```yaml
# Create Role and RoleBinding first
# Then in aws-auth mapUsers:
mapUsers: |
  - userarn: arn:aws:iam::123456789:user/developer
    username: developer
    groups:
      - namespace-developers
```

### Multiple Roles

```yaml
mapRoles: |
  - rolearn: arn:aws:iam::123456789:role/infra-role
    username: infra
    groups:
      - system:masters
  - rolearn: arn:aws:iam::123456789:role/app-role
    username: app
    groups:
      - app-namespace-admins
```

## References

- [Grant IAM users and roles access to Kubernetes APIs](https://docs.aws.amazon.com/eks/latest/userguide/grant-k8s-access.html)
- [Cluster Access API](https://docs.aws.amazon.com/eks/latest/userguide/cluster-access.html)
- [EKS Best Practices - Identity](https://aws.github.io/aws-eks-best-practices/security/docs/iam/)
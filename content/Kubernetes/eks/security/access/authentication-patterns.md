---
title: Authentication Patterns
tags: [eks, security, access, authentication]
date: 2026-05-17
description: Comparison of EKS authentication patterns - IRSA, Pod Identity, node roles, instance profiles
---

# Authentication Patterns on EKS

## Overview

EKS uses two-layer authentication:

1. **Authentication (AuthN)** - Who are you?
2. **Authorization (AuthZ)** - What can you do?

```
┌─────────────────────────────────────────────────────────────┐
│                    EKS Access Model                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Request comes in                                           │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────┐                                            │
│  │     IAM     │ ──── AuthN: Verify IAM identity           │
│  └─────────────┘                                            │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────┐                                            │
│  │    RBAC     │ ──── AuthZ: Check Kubernetes permissions  │
│  └─────────────┘                                            │
│       │                                                     │
│       ▼                                                     │
│  Allow or Deny                                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Authentication Methods

### For Humans (kubectl)

| Method | AuthN | Use Case |
|--------|-------|----------|
| AWS CLI (IAM user/role) | IAM | Local development, CI/CD |
| AWS Console | IAM | Web UI |
| Bastion host | IAM + network | Private clusters |
| CloudShell | IAM | Quick operations, private clusters |
| Cloud9 | IAM + VPC | Development environment |

### For Workloads (Pods)

| Method | AuthN | Use Case |
|--------|-------|----------|
| [[Kubernetes/eks/security/pod-identity|Pod Identity]] | IAM role | AWS SDK access |
| [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]] | IAM role via OIDC | AWS SDK access |
| Node IAM role | Instance profile | Fallback (not recommended) |

## Pod Authentication Deep-Dive

### Available Methods

| Method | Pros | Cons |
|--------|------|------|
| **Pod Identity** | Simple, no OIDC, cross-cluster | Agent required, EKS-only |
| **IRSA** | Mature, OIDC-based | OIDC setup, per-cluster config |
| **Instance Profile** | No setup | All pods share permissions, no isolation |

### Credential Isolation Comparison

```
┌─────────────────────────────────────────────────────────────┐
│              Credential Access by Method                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Method: Instance Profile (on node)                         │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Node Instance Role                                 │    │
│  │    │                                                │    │
│  │    ├──► Pod A (can access if knows role)           │    │
│  │    ├──► Pod B (can access if knows role)           │    │
│  │    └──► Pod C (can access if knows role)           │    │
│  └─────────────────────────────────────────────────────┘    │
│  Problem: All pods on node can potentially access creds     │
│                                                             │
│  Method: Pod Identity / IRSA                                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Pod A ──► Own Role (read-s3)                       │    │
│  │  Pod B ──► Own Role (write-dynamo)                  │    │
│  │  Pod C ──► Own Role (admin-eks)                    │    │
│  └─────────────────────────────────────────────────────┘    │
│  Benefit: Each pod has only its own permissions            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Node IMDS Consideration

| IMDS Configuration | Pod can access node role? | Pod can use IRSA/Pod Identity? |
|-------------------|---------------------------|------------------------------|
| IMDSv2 required | No | Yes |
| IMDSv1 allowed | Potentially | Yes |
| Unrestricted | Yes | SDK prefers IRSA |

**Recommendation:** Always require IMDSv2:

```bash
# On all nodes
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxx \
  --http-tokens required \
  --http-put-response-hop-limit 1
```

## IRSA vs Pod Identity Quick Reference

| Aspect | IRSA | Pod Identity |
|--------|------|--------------|
| Setup | Create OIDC provider + trust policy | Create EKS association |
| OIDC provider | Must create and manage | Not needed |
| Trust policy | `oidc.eks.region.../id/CLUSTER_ID:sub=...` | `Service: pods.eks.amazonaws.com` |
| Per-cluster config | Yes, separate trust policy | No, same role works everywhere |
| Cross-cluster | Requires separate roles | Single role works |
| SDK calls | Each pod calls STS | Cached at node level |
| Key rotation | 7 days | Managed by EKS |
| Agent | None | DaemonSet required |
| Limits | None | 5,000 associations/cluster |
| Fargate | Not supported | Not supported |

### Decision Tree

```
                    Do you need AWS SDK access from pods?
                                    │
                                    Yes
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
            Multi-cluster?                    Single cluster?
                    │                               │
                    │                               │
            Use Pod Identity              ┌───────────┴───────────┐
            (same role works                 │                   │
            everywhere)                      │                   │
                                              │                   │
                              Simpler setup?              Complex OIDC needed?
                                    │                         │
                                    │                         │
                            Use Pod Identity          Use IRSA
```

## Node Authentication

### Node IAM Role

Required for nodes to join the cluster:

```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:DescribeInstances",
    "ec2:DescribeTags",
    "ec2:DescribeVolumes",
    "eks:DescribeCluster"
  ],
  "Resource": "*"
}
```

### Node Authorization (NodeAuthorizer)

Kubernetes uses NodeAuthorizer to authorize kubelet requests:

```yaml
# Nodes get these groups via aws-auth or Cluster Access API
groups:
  - system:bootstrappers  # Allows node registration
  - system:nodes          # Allows kubelet to operate
```

### Instance Profile vs IRSA for Nodes

| Purpose | Instance Profile | IRSA for kubelet |
|---------|-----------------|------------------|
| Node registration | Yes | No (different flow) |
| Node to API server | Yes | Yes |
| Pod AWS access | Shared | Per-pod via IRSA/PodIdentity |

**Note:** Nodes still need instance profile/role for:
- Node registration
- Pulling ECR images
- CloudWatch logging
- Other AWS service access from node level

## Cluster Access Methods Summary

### For Cluster Management (kubectl)

| Method | Configuration | Best For |
|--------|---------------|----------|
| **Cluster Access API** | `aws eks create-access-entry` | All new access grants |
| **aws-auth ConfigMap** | `kubectl edit configmap` | Legacy, node access only |

### Access Entry Policies

| Policy ARN | Permission |
|-----------|------------|
| `arn:aws:eks::aws:cluster-access-policy:AmazonEKSClusterAdmin` | Superuser (full cluster) |
| `arn:aws:eks::aws:cluster-access-policy:AmazonEKSAdminView` | Read-only cluster |
| `arn:aws:eks::aws:cluster-access-policy:AmazonEKSEdit` | Read/write workloads |
| `arn:aws:eks::aws:cluster-access-policy:AmazonEKSView` | Read-only namespaces |

### RBAC Mapping

Access entries grant IAM principals access, but RBAC controls what they can do:

```
IAM Principal (via Cluster Access API)
    │
    ▼
RBAC Role/ClusterRoleBinding
    │
    ▼
Kubernetes Permissions
```

## Security Best Practices

### 1. Use IRSA or Pod Identity for All Pods

```bash
# Check for pods WITHOUT IRSA/Pod Identity
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.serviceAccountName}{"\n"}{end}' | \
  while read ns sa; do
    if ! kubectl get sa $sa -n $ns -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null | grep -q .; then
      echo "No IRSA: $ns/$sa"
    fi
  done
```

### 2. Restrict IMDS Access

```bash
# Require IMDSv2 on all instances
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxx \
  --http-tokens required \
  --http-put-response-hop-limit 1
```

### 3. Use Least-Privilege IAM Policies

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ],
    "Resource": "arn:aws:s3:::my-specific-bucket/my-specific-path/*"
  }]
}
```

### 4. Prefer Cluster Access API over aws-auth

```bash
# Grant access via Cluster Access API
aws eks create-access-entry \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789:user/developer

aws eks associate-access-policy \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789:user/developer \
  --policy-arn arn:aws:eks::aws:cluster-access-policy:AmazonEKSEdit
```

### 5. Use Separate Service Accounts

```yaml
# Bad: Same SA for multiple apps with different permissions
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: shared-sa  # Used by app A, B, C
---
# Good: Separate SAs per app
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-a-sa  # Only for app A
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-b-sa  # Only for app B
```

## Common Patterns

### Pattern 1: App with S3 Access

```bash
# 1. Create role with S3 policy
aws iam create-role --role-name app-s3-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

# 2. Create Pod Identity association
aws eks create-pod-identity-association \
  --cluster-name my-cluster \
  --namespace production \
  --service-account my-app \
  --role-arn arn:aws:iam::123456789:role/app-s3-role

# 3. Use in deployment
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: production
---
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      serviceAccountName: my-app
EOF
```

### Pattern 2: App with DynamoDB Access

```bash
# Role with DynamoDB policy
aws iam create-role --role-name app-dynamo-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

aws iam attach-role-policy --role-name app-dynamo-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess

# Association
aws eks create-pod-identity-association \
  --cluster-name my-cluster \
  --namespace backend \
  --service-account api-service \
  --role-arn arn:aws:iam::123456789:role/app-dynamo-role
```

### Pattern 3: Database App with Secrets Manager

```bash
# Role for Secrets Manager + RDS
aws iam create-role --role-name db-app-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

# Attach policies
aws iam attach-role-policy --role-name db-app-role \
  --policy-arn arn:aws:iam::aws:policy/secretsmanager:ReadWrite

aws iam attach-role-policy --role-name db-app-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess
```

## Anti-Patterns to Avoid

### 1. Using Node Role for Application Workloads

```yaml
# DON'T: Pod accessing AWS resources using node role
# (via IMDS if not restricted)

# DO: Use IRSA or Pod Identity instead
```

### 2. Overly Broad Trust Policies

```json
// DON'T: Allow any service account in any cluster
{
  "Principal": {"Federated": "*"},
  "Condition": {"StringLike": {"*:sub": "system:serviceaccount:*:*"}}
}

// DO: Be specific
{
  "Condition": {
    "StringEquals": {
      "oidc.eks.us-west-2.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:production:my-app"
    }
  }
}
```

### 3. Using Long-Lived AWS Credentials in Code

```dockerfile
# DON'T: Embed credentials in image
RUN aws configure set aws_access_key_id xxx

# DO: Use IRSA/Pod Identity at runtime
```

### 4. Sharing Service Accounts Across Applications

```yaml
# DON'T: App A and App B share same SA but have different permission needs

# DO: Separate SAs with appropriate permissions for each app
```

## Reference: Environment Variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `AWS_ROLE_ARN` | IRSA annotation or Pod Identity | Role being assumed |
| `AWS_WEB_IDENTITY_TOKEN_FILE` | IRSA mount | JWT for STS AssumeRoleWithWebIdentity |
| `AWS_CONTAINER_CREDENTIALS_FULL_URI` | Pod Identity agent | Local HTTP endpoint for creds |
| `AWS_DEFAULT_REGION` | User/instance | Default region |
| `AWS_REGION` | User/instance | Preferred region |

## References

- [EKS Authentication](https://docs.aws.amazon.com/eks/latest/userguide/managing-access.html)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [EKS Best Practices - IAM](https://aws.github.io/aws-eks-best-practices/security/docs/iam/)
---
title: IAM Roles for Service Accounts (IRSA)
tags: [eks, security, iam, irsa]
date: 2026-05-17
description: IRSA deep-dive - OIDC trust chain, token details, security, multi-cluster patterns
---

# IAM Roles for Service Accounts (IRSA)

## Overview

IRSA allows pods to authenticate as IAM roles, enabling fine-grained access to AWS resources without sharing IAM credentials. It's the original EKS-native solution for pod-level IAM permissions.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    IRSA Authentication Flow                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Pod uses ServiceAccount with eks.amazonaws.com/role-arn │
│                                                             │
│  2. kubelet mounts ProjectedServiceAccountToken             │
│     Path: /var/run/secrets/eks.amazonaws.com/serviceaccount│
│                                                             │
│  3. AWS SDK automatically uses token via:                  │
│     - AWS_ROLE_ARN                                          │
│     - AWS_WEB_IDENTITY_TOKEN_FILE                           │
│     - AWS_SESSION_TOKEN (if using GetSessionToken)          │
│                                                             │
│  4. SDK calls STS AssumeRoleWithWebIdentity:               │
│     POST https://sts.amazonaws.com/                         │
│     RoleArn=<role-arn>                                      │
│     WebIdentityToken=<JWT from service account>             │
│                                                             │
│  5. IAM validates token:                                    │
│     - Signature verification (OIDC public keys)            │
│     - Claims validation (sub, aud, exp)                    │
│     - Trust policy conditions                              │
│                                                             │
│  6. STS returns temporary credentials                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## OIDC Trust Chain Deep-Dive

### Components

| Component | URL |
|-----------|-----|
| OIDC Provider URL | `https://oidc.eks.<region>.amazonaws.com/id/<CLUSTER_ID>` |
| Discovery Document | `/.well-known/openid-configuration` |
| JWKS (Public Keys) | `/.well-known/jwks.json` |

### Trust Policy Structure

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E:sub": "system:serviceaccount:default:my-app",
          "oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

### Condition Keys

| Key | Description | Example Value |
|-----|-------------|---------------|
| `sub` | Service account identity | `system:serviceaccount:default:my-app` |
| `aud` | Intended audience | `sts.amazonaws.com` |
| `namespace` | (Prefix) SA namespace | `default:my-app` |
| `svcacct` | (Prefix) SA name | `default:my-app` |

### Conditions Syntax Examples

```json
// Specific service account only
"Condition": {
  "StringEquals": {
    "oidc.eks.region.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:default:my-app"
  }
}

// All service accounts in a namespace
"Condition": {
  "StringLike": {
    "oidc.eks.region.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:default:*"
  }
}

// Multiple namespaces (OR logic via multiple statements)
"Condition": {
  "StringLike": {
    "oidc.eks.region.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:(production|monitoring):*"
  }
}
```

## ProjectedServiceAccountToken Details

### Token Contents

```json
{
  "iss": "oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E",
  "sub": "system:serviceaccount:default:my-app",
  "aud": ["sts.amazonaws.com"],
  "exp": 1699999999,
  "iat": 1699996399,
  "jti": "abcd1234-xxxx-xxxx-xxxx-123456789abc"
}
```

### Token Characteristics

| Property | Value |
|----------|-------|
| Issuer | EKS OIDC provider URL |
| Subject | `system:serviceaccount:<namespace>:<name>` |
| Audience | `sts.amazonaws.com` |
| Expiration | Token-based, configurable (default 1 day) |
| Rotation | Managed by kubelet |

### Token Mount in Pod

```bash
# In container, token is available at:
/var/run/secrets/eks.amazonaws.com/serviceaccount/token

# Environment variables set automatically:
echo $AWS_ROLE_ARN
# arn:aws:iam::123456789:role/my-app-role

echo $AWS_WEB_IDENTITY_TOKEN_FILE
# /var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

## Setup - Complete Walkthrough

### Step 1: Create OIDC Provider

```bash
# Using eksctl (recommended)
eksctl utils associate-iam-oidc-provider \
  --cluster my-cluster \
  --region us-west-2 \
  --approve

# Verify it was created
aws iam list-open-id-connect-providers \
  --query 'OpenIDConnectProviderList[*].Arn'
```

### Step 2: Create IAM Role

```bash
# Get OIDC provider ARN
OIDC_PROVIDER=$(aws eks describe-cluster \
  --name my-cluster \
  --region us-west-2 \
  --query 'cluster.identity.oidc.issuer' \
  --output text | sed 's|https://||')

# Create trust policy file
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:default:my-app"
        }
      }
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name my-app-role \
  --assume-role-policy-document file://trust-policy.json

# Attach permissions
aws iam attach-role-policy \
  --role-name my-app-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

### Step 3: Create ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/my-app-role
```

```bash
kubectl apply -f serviceaccount.yaml
```

### Step 4: Use in Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  serviceAccountName: my-app
  containers:
  - name: app
    image: my-app:latest
    # No need to set env vars - SDK auto-detects
```

### Verify IRSA is Working

```bash
# Check token is mounted
kubectl exec -it my-app -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | head -c 200

# Check env vars
kubectl exec -it my-app -- env | grep AWS

# Test AWS CLI (requires AWS SDK)
kubectl exec -it my-app -- aws sts get-caller-identity
# Should return role ARN, not instance profile
```

## Key Rotation

| Rotation | Frequency | Details |
|----------|-----------|---------|
| OIDC signing keys | Every 7 days | EKS rotates private key |
| Service account token | 1 day (default) | kubelet manages |

### External Client Key Refresh

If you have external OIDC clients (not AWS SDK), refresh keys before expiration:

```bash
# Fetch signing keys
curl https://oidc.eks.us-west-2.amazonaws.com/id/CLUSTER_ID/.well-known/jwks.json
```

### SDK Behavior

AWS SDKs handle key refresh automatically - no external action needed.

## Security Considerations

### IMDS Access

| Node Configuration | IMDS Access | IRSA Override |
|-------------------|-------------|---------------|
| IMDSv2 required | Blocked | SDK uses IRSA creds |
| IMDSv1 + IMDSv2 | Available | SDK prefers IRSA creds |
| No restriction | Available | SDK uses first available |

**Best Practice:** Require IMDSv2 on all nodes:
```bash
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxx \
  --http-tokens required \
  --http-put-response-hop-limit 1
```

### hostNetwork Pods

Pods using `hostNetwork: true` always have IMDS access, but SDK still uses IRSA when configured.

### Containers Not a Security Boundary

```bash
# From a Pod, you can potentially access:
# - Node root filesystem (via hostPath)
# - Other Pods on same node
# - Node IAM role credentials (if IMDS unrestricted)
```

**Implication:** IRSA limits damage from container compromise but doesn't prevent node-level attacks.

### Credential Isolation

```
Pod A (app)           Pod B (app)
    │                     │
    ▼                     ▼
IRSA: read-s3        IRSA: write-s3
    │                     │
    └─────────┬───────────┘
              │
         Node (shared kernel)
```

Pods on the same node share:
- Kernel namespaces (if not isolated)
- Node credentials (if IMDS accessible)

## Multi-Cluster Patterns

### Cross-Cluster Reuse (Same Account)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Federated": "*"},
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "oidc.eks.*.amazonaws.com/id/*:sub": "system:serviceaccount:production:my-app"
        }
      }
    }
  ]
}
```

**Risk:** Allows any EKS cluster in the account to use this role. Use with caution.

### Per-Cluster Roles (Recommended)

```json
// Role for cluster-1 only
{
  "Condition": {
    "StringEquals": {
      "oidc.eks.us-west-2.amazonaws.com/id/CLUSTER_ID_1:sub": "system:serviceaccount:default:my-app"
    }
  }
}
```

### Cross-Account Access

```json
// In target account
{
  "Principal": {
    "AWS": "arn:aws:iam::ACCOUNT_B:role/RoleInAccountB"
  }
}
```

Then in account B, assume into role with IRSA trust.

## CloudTrail Audit

### AssumeRoleWithWebIdentity Events

```json
{
  "eventVersion": "1.08",
  "userIdentity": {
    "type": "WebIdentityUser",
    "principalId": "SYSTEM:SERVICEACCOUNT:DEFAULT:MY-APP",
    "roleSessionName": "system:serviceaccount:default:my-app"
  },
  "eventSource": "sts.amazonaws.com",
  "eventName": "AssumeRoleWithWebIdentity",
  "awsRegion": "us-west-2",
  "sourceIPAddress": "node.ip.address",
  "userAgent": "aws-sdk-go-v2/1.2.3",
  "requestParameters": {
    "roleArn": "arn:aws:iam::123456789:role/my-app-role",
    "roleSessionName": "system:serviceaccount:default:my-app"
  },
  "responseElements": {
    "credentials": {
      "accessKeyId": "ASIA...",
      "expiration": "2024-01-01T12:00:00Z"
    }
  }
}
```

### Filtering CloudTrail

```bash
# Find all IRSA assume events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time 2024-01-01T00:00:00Z

# Filter by role
aws logs insights-query \
  --log-group-name AWSLogs/123456789/CloudTrail \
  --start-time 2024-01-01T00:00:00Z \
  --query-string 'fields @timestamp, userIdentity.roleSessionName | filter eventName = "AssumeRoleWithWebIdentity" | filter roleSessionName like "my-app"'
```

## Troubleshooting

### AccessDenied when calling AssumeRoleWithWebIdentity

| Cause | Fix |
|-------|-----|
| Trust policy missing | Add OIDC provider to principals |
| Condition mismatch | Verify `sub` matches SA exactly |
| Wrong OIDC provider | Check cluster's OIDC provider URL |

### InvalidIdentityToken

```
Error: InvalidIdentityToken: Couldn't retrieve verification key from ...
```

| Cause | Fix |
|-------|-----|
| Can't reach OIDC endpoint | Check VPC routing, NAT Gateway |
| Wrong audience | Ensure `aud: sts.amazonaws.com` in trust policy |
| Token expired | kubelet should auto-renew |

### Token Not Mounted

```bash
# Check if projected volume is mounted
kubectl describe pod my-app | grep -A5 Volumes

# Expected output:
# Volumes:
#   aws-iam-token:
#     Type:                    Projected
#     ServiceAccountToken:    projection.config.oath.com
```

### SDK Not Using IRSA Creds

```bash
# Check env vars are set
kubectl exec -it my-app -- env | grep AWS

# If not set, check service account has annotation
kubectl get sa my-app -o yaml | grep annotations

# If annotation exists but env vars missing, restart pod
kubectl delete pod my-app
```

### DescribeCluster Fails from Pod

```bash
# Check if VPC has endpoint for eks
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=*eks*"

# If missing, this is expected - EKS uses gateway endpoints for S3
# Cluster API calls go through public endpoint or private endpoint
```

## Comparison with Pod Identity

| Aspect | IRSA | Pod Identity |
|--------|------|--------------|
| Setup | OIDC provider + trust policy | EKS API association |
| Per-cluster config | Separate trust policy | Same role works everywhere |
| SDK calls | Each pod calls STS | One call per node, cached |
| Key management | 7-day rotation | Managed by EKS |
| Cross-account | Via trust relationships | Via role delegation |
| Audit trail | CloudTrail STS events | CloudTrail + EKS API |

## References

- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [EKS Workshop - IRSA](https://www.eksworkshop.com/docs/security/iam-roles-for-service-accounts/)
- [OIDC Background](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html#irsa-oid)
- [Best Practices](https://aws.github.io/aws-eks-best-practices/security/docs/iam/)
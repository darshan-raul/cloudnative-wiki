---
title: EKS Pod Identity
tags: [eks, security, iam, pod-identity]
date: 2026-05-17
description: EKS Pod Identity deep-dive - agent architecture, configuration, migration from IRSA
---

# EKS Pod Identity

## Overview

EKS Pod Identity provides a simpler alternative to IRSA for assigning IAM permissions to pods. It eliminates the need for OIDC provider setup while providing the same credential isolation benefits.

**Key Benefit:** No OIDC provider management - EKS handles the trust relationship.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                  EKS Pod Identity Flow                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Create Pod Identity Association (via EKS API)         │
│     - Maps IAM role → ServiceAccount (namespace/name)       │
│     - Stored in EKS control plane                           │
│                                                             │
│  2. Pod uses ServiceAccount with association               │
│                                                             │
│  3. EKS Pod Identity Agent (DaemonSet) responds:            │
│     - Listens on port 80, 2703 (link-local 169.254.170.23)  │
│     - One agent per node, serves all pods on that node       │
│                                                             │
│  4. Pod's AWS SDK makes credential request:                 │
│     - To: http://169.254.170.23/latest/meta-data/iam/security-credentials/  │
│     - Or: http://169.254.170.23/latest/api/token           │
│                                                             │
│  5. Agent forwards to EKS Auth service                     │
│     - Service: pods.eks.amazonaws.com                       │
│     - EKS Auth validates association and returns creds     │
│                                                             │
│  6. Agent returns credentials to SDK                       │
│     - Via: AWS_CONTAINER_CREDENTIALS_FULL_URI env var       │
│     - Or: AWS_ROLE_ARN + AWS_WEB_IDENTITY_TOKEN             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## EKS Pod Identity Agent Architecture

### Agent Details

| Property | Value |
|----------|-------|
| Deployment type | DaemonSet (one per node) |
| Listen address | `169.254.170.23` (IPv4), `[fd00:ec2::23]` (IPv6) |
| Ports | 80, 2703 |
| Memory | ~50MB |
| CPU | Low (background) |

### Port Usage

| Port | Purpose |
|------|---------|
| 80 | HTTP server for credential requests |
| 2703 | gRPC for internal communication |

### IPv6 Configuration

If your cluster has IPv6 disabled, disable IPv6 for the agent:

```bash
# Check current state
kubectl get daemonset pod-identity-agent -n kube-system -o jsonpath='{.spec.template.spec.containers[*].env}'

# Disable IPv6 if cluster is IPv4-only
# Agent respects cluster IP family settings
```

### Agent Logs

```bash
# View agent logs
kubectl logs -n kube-system -l app=pod-identity-agent --tail=100

# Check for association lookups
kubectl logs -n kube-system -l app=pod-identity-agent | grep -i association
```

## Setup - Complete Walkthrough

### Prerequisites

- EKS cluster with platform version eks.4 or later
- Kubernetes 1.28+ (or eks.4 platform for older k8s)
- Linux EC2 nodes (not Fargate, not Windows)

### Step 1: Install Pod Identity Agent

```bash
# Via eksctl (recommended)
eksctl create podidentityassociation \
  --cluster my-cluster \
  --namespace default \
  --serviceaccount my-app \
  --role-name my-app-role \
  --region us-west-2

# Or via AWS CLI (creates association and installs agent if needed)
aws eks create-pod-identity-association \
  --cluster-name my-cluster \
  --namespace default \
  --service-account my-app \
  --role-arn arn:aws:iam::123456789:role/my-app-role \
  --region us-west-2
```

### Step 2: Create IAM Role with Pod Identity Trust

```bash
# Create role with Pod Identity trust policy
aws iam create-role \
  --role-name my-app-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "pods.eks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'

# Attach permissions
aws iam attach-role-policy \
  --role-name my-app-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

**Key Difference from IRSA:** No OIDC provider reference. Trust policy uses `pods.eks.amazonaws.com` as principal.

### Step 3: Create ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: default
  # No annotations needed for Pod Identity!
  # Association is external to the cluster
```

```bash
kubectl apply -f serviceaccount.yaml
```

### Step 4: Deploy Pod

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: my-app
      containers:
      - name: app
        image: my-app:latest
```

### Environment Variables Set by Agent

| Variable | Value |
|----------|-------|
| `AWS_ROLE_ARN` | The role ARN from association |
| `AWS_WEB_IDENTITY_TOKEN_FILE` | Path to token (if supported) |
| `AWS_CONTAINER_CREDENTIALS_FULL_URI` | `http://169.254.170.23/latest/meta-data/...` |

**Note:** The agent sets these in the container, not the service account.

## Verifying Pod Identity Works

```bash
# Check agent is running
kubectl get daemonset pod-identity-agent -n kube-system

# Check pod has credentials
kubectl exec -it deployment/my-app -- env | grep AWS

# Test AWS CLI
kubectl exec -it deployment/my-app -- aws sts get-caller-identity
# Should return:
# {
#     "UserId": "AROA...:botocore-session-...",
#     "Account": "123456789",
#     "Arn": "arn:aws:sts::123456789:assumed-role/my-app-role/..."
# }
```

## Associations Management

### List Associations

```bash
aws eks list-pod-identity-associations \
  --cluster-name my-cluster \
  --region us-west-2
```

### Describe Association

```bash
aws eks describe-pod-identity-association \
  --cluster-name my-cluster \
  --association-id us-west-2:xxxxx-xxxx-xxxx-xxxx-xxxxxxxxx
```

### Update Association

```bash
# Change the role
aws eks update-pod-identity-association \
  --cluster-name my-cluster \
  --association-id us-west-2:xxxxx-xxxx-xxxx-xxxx-xxxxxxxxx \
  --role-arn arn:aws:iam::123456789:role/new-role
```

### Delete Association

```bash
aws eks delete-pod-identity-association \
  --cluster-name my-cluster \
  --association-id us-west-2:xxxxx-xxxx-xxxx-xxxx-xxxxxxxxx
```

## Limits

| Resource | Limit |
|----------|-------|
| Associations per cluster | 5,000 |
| Service accounts per association | 1 |
| Roles per association | 1 |
| Regions | All EKS regions |

## Eventual Consistency

Pod Identity associations are **eventually consistent**:

| Operation | Propagation Time |
|-----------|------------------|
| Create | Seconds to minutes |
| Update | Seconds to minutes |
| Delete | Seconds to minutes |

**Implication:** Avoid creating/updating associations in high-availability code paths.

## Proxy Considerations

If pods use an HTTP proxy, exclude the Pod Identity Agent:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-proxy-config
data:
  HTTP_PROXY: "http://proxy.example.com:8080"
  NO_PROXY: "169.254.170.23,localhost,127.0.0.1,.cluster.local"
  # For IPv6:
  # NO_PROXY: "[fd00:ec2::23],localhost,127.0.0.1"
```

### Why Exclude the Agent?

```
┌─────────────────────────────────────────────────────────────┐
│                        Proxy Flow                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Pod SDK                                                    │
│     │                                                       │
│     ├─── Request to 169.254.170.23 (Pod Identity Agent)    │
│     │      Should BYPASS proxy                              │
│     │                                                       │
│     └─── Request to S3 (AWS API)                           │
│            Should USE proxy                                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Security Groups for Pods with Pod Identity

When using Security Groups for Pods with Pod Identity:

```bash
# Ensure required flags are set on aws-node
kubectl set env daemonset/aws-node -n kube-system \
  ENABLE_POD_ENI=true \
  POD_SECURITY_GROUP_ENFORCING_MODE=standard
```

## Comparison with IRSA

| Aspect | IRSA | Pod Identity |
|--------|------|--------------|
| **Setup Complexity** | Higher (OIDC provider) | Lower (EKS API only) |
| **OIDC Provider** | Required | Not needed |
| **Trust Policy** | Per-cluster OIDC principal | `pods.eks.amazonaws.com` |
| **Cross-cluster reuse** | Separate IAM roles | Same role works everywhere |
| **Credential flow** | Each SDK calls STS | One call per node, cached |
| **Key rotation** | 7-day (EKS managed) | Managed by EKS |
| **CloudTrail events** | STS AssumeRoleWithWebIdentity | STS AssumeRole (EKS Auth) |
| **Agent required** | No | Yes (DaemonSet) |
| **Region availability** | All EKS regions | All EKS regions |
| **Limits** | None specific | 5,000 associations/cluster |

### Trust Policy Comparison

**IRSA:**
```json
{
  "Principal": {
    "Federated": "arn:aws:iam::123456789:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/CLUSTER_ID"
  },
  "Condition": {
    "StringEquals": {
      "oidc.eks...:sub": "system:serviceaccount:namespace:name"
    }
  }
}
```

**Pod Identity:**
```json
{
  "Principal": {
    "Service": "pods.eks.amazonaws.com"
  }
}
```

### SDK Call Comparison

**IRSA (per-pod):**
```
Pod A: SDK → STS AssumeRoleWithWebIdentity → IAM → Temp Creds
Pod B: SDK → STS AssumeRoleWithWebIdentity → IAM → Temp Creds
Pod C: SDK → STS AssumeRoleWithWebIdentity → IAM → Temp Creds
```

**Pod Identity (per-node):**
```
Node 1 (Pod A, Pod B): SDK → Pod Identity Agent → EKS Auth → Temp Creds (cached)
Node 2 (Pod C): SDK → Pod Identity Agent → EKS Auth → Temp Creds (cached)
```

## Migration from IRSA to Pod Identity

### Prerequisites

- Cluster running Kubernetes 1.28+ or platform version eks.4+
- Linux EC2 nodes (not Fargate)

### Step 1: Create Pod Identity Association

```bash
aws eks create-pod-identity-association \
  --cluster-name my-cluster \
  --namespace default \
  --service-account my-app \
  --role-arn arn:aws:iam::123456789:role/my-app-role
```

### Step 2: Remove IRSA Annotation

```bash
# Remove from service account
kubectl annotate sa my-app eks.amazonaws.com/role-arn-
```

### Step 3: Update IAM Trust Policy

**IRSA trust (can be removed after migration):**
```json
{
  "Condition": {
    "StringEquals": {
      "oidc.eks...:sub": "system:serviceaccount:default:my-app"
    }
  }
}
```

**Pod Identity trust (add):**
```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "pods.eks.amazonaws.com"
  },
  "Action": "sts:AssumeRole"
}
```

### Step 4: Redeploy Pods

```bash
# Restart pods to pick up new credentials
kubectl rollout restart deployment my-app

# Or delete pods individually
kubectl delete pod my-app-xxxxx
```

### Step 5: Verify

```bash
# Should show role from Pod Identity
kubectl exec -it my-app-xxxxx -- aws sts get-caller-identity

# Verify no IRSA env vars (should not see AWS_WEB_IDENTITY_TOKEN_FILE pointing to eks.amazonaws.com)
kubectl exec -it my-app-xxxxx -- env | grep AWS
```

### Rollback

If issues occur:

```bash
# Re-add IRSA annotation
kubectl annotate sa my-app eks.amazonaws.com/role-arn=arn:aws:iam::123456789:role/my-app-role

# Remove Pod Identity association
aws eks delete-pod-identity-association \
  --cluster-name my-cluster \
  --association-id us-west-2:xxxxx

# Restart pods
kubectl rollout restart deployment my-app
```

## Troubleshooting

### Pod Not Getting Credentials

```bash
# 1. Check agent is running
kubectl get daemonset pod-identity-agent -n kube-system

# 2. Check association exists
aws eks list-pod-identity-associations --cluster-name my-cluster

# 3. Check environment variables in pod
kubectl exec -it my-app-xxxxx -- env | grep AWS
# Should see AWS_CONTAINER_CREDENTIALS_FULL_URI or AWS_ROLE_ARN

# 4. Test connectivity to agent
kubectl exec -it my-app-xxxxx -- wget -O- 169.254.170.23/latest/meta-data/
```

### Access Denied Errors

```bash
# Check IAM role permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789:role/my-app-role \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::my-bucket/*

# Check CloudTrail for assume errors
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole
```

### Association Not Taking Effect

```bash
# Describe association for details
aws eks describe-pod-identity-association \
  --cluster-name my-cluster \
  --association-id us-west-2:xxxxx

# Check association status
# "ASSOCIATING" = in progress
# "ASSOCIATED" = ready
# "DISASSOCIATING" = removing
```

### Agent Not Starting

```bash
# Check agent pods
kubectl get pods -n kube-system -l app=pod-identity-agent

# Check events
kubectl describe daemonset pod-identity-agent -n kube-system

# Common issues:
# - Port 80 conflict (another pod using port 80)
# - IPv6 disabled but agent trying IPv6
```

### SDK Using Wrong Credentials

```bash
# Check credential provider chain
kubectl exec -it my-app -- aws configure list

# Verify credential source
# Should show: EKS Pod Identity (pod-identity)
```

## When to Choose Pod Identity over IRSA

| Scenario | Recommended |
|----------|-------------|
| New project | Pod Identity |
| Multi-cluster with same permissions | Pod Identity |
| Simple AWS access needs | Pod Identity |
| Complex OIDC requirements | IRSA |
| External OIDC client (non-AWS SDK) | IRSA |
| Existing IRSA working well | Keep IRSA |

## References

- [Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [EKS Workshop - Pod Identity](https://www.eksworkshop.com/docs/security/amazon-eks-pod-identity/)
- [Pod Identity Agent Setup](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html)
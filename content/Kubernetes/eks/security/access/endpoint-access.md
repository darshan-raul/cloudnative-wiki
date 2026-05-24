---
title: Cluster Endpoint Access
tags: [eks, security, access, networking, endpoint]
date: 2026-05-17
description: EKS cluster endpoint configuration - public/private access, bastion hosts, security groups
---

# Cluster Endpoint Access

## Endpoint Overview

When you create an EKS cluster, two endpoints are created:

| Endpoint | Purpose | Default State |
|----------|---------|---------------|
| **Public endpoint** | Kubernetes API from internet | Enabled |
| **Private endpoint** | Kubernetes API from within VPC | Disabled by default |

Both endpoints resolve to the same API server. You can use one or both depending on your security requirements.

## Endpoint Configurations

### Configuration Matrix

| Public Access | Private Access | Behavior |
|---------------|----------------|----------|
| Enabled | Disabled | API server reachable from internet only |
| Enabled | Enabled | API server reachable from internet AND VPC (recommended) |
| Disabled | Enabled | API server reachable from VPC only (most secure) |

### Configuration via AWS CLI

```bash
# Create cluster with both endpoints enabled
aws eks create-cluster \
  --name my-cluster \
  --role-arn arn:aws:iam::123456789:role/eks-cluster-role \
  --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true \
  --kubernetes-version 1.30

# Update existing cluster
aws eks update-cluster-config \
  --name my-cluster \
  --region us-west-2 \
  --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs="10.0.0.0/16"
```

## Private Endpoint Deep-Dive

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                   Private Endpoint Architecture               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  VPC with EKS Cluster                                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Route53 Private Hosted Zone                        │   │
│  │  (managed by EKS, not visible in your Route53)     │   │
│  │  Resolves: my-cluster.oidc.eks.us-west-2.amazonaws.com  │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Private Subnets                                   │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐         │   │
│  │  │ Node 1   │  │ Node 2   │  │ Pod      │         │   │
│  │  └──────────┘  └──────────┘  └──────────┘         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Requirements

| Requirement | Description |
|-------------|-------------|
| `enableDnsHostnames` | VPC must have DNS hostnames enabled |
| `enableDnsSupport` | VPC must have DNS support enabled |
| DHCP options | Must include `AmazonProvidedDNS` in domain name servers |

Check with:
```bash
aws ec2 describe-vpc-attribute \
  --vpc-id vpc-xxxx \
  --attribute enableDnsHostnames

aws ec2 describe-vpc-attribute \
  --vpc-id vpc-xxxx \
  --attribute enableDnsSupport
```

### Important Notes

- The private endpoint is **not** a VPC endpoint service (PrivateLink)
- It doesn't appear in the Amazon VPC console under "Endpoints"
- EKS manages the Route53 private hosted zone internally
- DNS resolution only works from within the VPC

## Accessing Private Clusters

When public access is disabled, you need to access the API server from within the VPC or a connected network.

### Method 1: VPN or Direct Connect

```
Corporate Network ──► AWS Transit Gateway ──► VPC ──► API Server
                      (or Direct Connect)         │
                                                   │
                           ┌───────────────────────┘
                           │
                      kubectl/bastion
```

**Requirements:**
- Transit Gateway or Direct Connect connected to VPC
- Security group rule allowing port 443 from connected network
- Network path allows traffic to EKS control plane

### Method 2: EC2 Bastion Host

```bash
# 1. Launch bastion in public subnet
aws ec2 run-instances \
  --image-id ami-xxxx \
  --instance-type t3.medium \
  --subnet-id subnet-public \
  --security-group-ids sg-bastion

# 2. From bastion, configure kubectl with cluster credentials
aws eks update-kubeconfig --name my-cluster

# 3. Ensure IAM principal has cluster access (via Cluster Access API or aws-auth)
```

**Bastion Security Group Rules:**
```json
{
  "InboundRules": [
    {
      "FromPort": 443,
      "ToPort": 443,
      "CidrBlocks": ["10.0.0.0/16"],
      "Description": "EKS API access from VPC"
    }
  ],
  "OutboundRules": [
    {
      "IpProtocol": "-1",
      "CidrBlocks": ["0.0.0.0/0"]
    }
  ]
}
```

### Method 3: AWS CloudShell

CloudShell can automatically launch in a VPC context for private clusters:

1. Go to EKS Console
2. Click **Connect** on the cluster
3. CloudShell launches with VPC context
4. `kubectl` commands work immediately

**Limitation:** CloudShell sessions are temporary; credentials aren't persisted.

### Method 4: AWS Cloud9 IDE

```bash
# Create Cloud9 environment in cluster's VPC
# Configure IAM role with access to cluster
aws cloud9 create-environment-ec2 \
  --name eks-dev \
  --instance-type t3.medium \
  --subnet-id subnet-private \
  --automatic-stop-time-minutes 60

# In Cloud9, configure kubectl
aws eks update-kubeconfig --name my-cluster
```

**Benefits:**
- Persistent credentials
- VPC-based access to private clusters
- Full IDE with debugging capabilities

## Cluster Security Group

The cluster security group controls access to the kubelet API and private endpoint.

### What It Controls

| Traffic Type | Ports | Commands Affected |
|-------------|-------|-------------------|
| Kubelet API | 10250 | `kubectl exec`, `logs`, `cp`, `attach`, `port-forward` |
| Private endpoint | 443 | All kubectl operations from within VPC |

### What It Does NOT Control

- Public endpoint access (controlled by public access CIDRs)
- Access from nodes to API server (handled by node security group)

### Default Rules (Managed by EKS)

| Rule Type | Effect | Description |
|-----------|--------|-------------|
| Inbound | Allow | All traffic from node security group |
| Outbound | Allow | All traffic |

### Customizing for Private-Only Access

If you disable public access, ensure your cluster security group allows access from your access points:

```bash
# Get cluster security group
aws eks describe-cluster \
  --name my-cluster \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId'

# Add ingress rule for bastion access
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxx \
  --protocol tcp \
  --port 443 \
  --cidr 10.0.0.0/24  # Your network CIDR
```

## Public Endpoint CIDR Restrictions

Limit which IP addresses can access the public endpoint.

### Configuration

```bash
# Restrict to specific CIDRs
aws eks update-cluster-config \
  --name my-cluster \
  --resources-vpc-config publicAccessCidrs="1.2.3.4/32,10.0.0.0/8"

# Allow from anywhere (default)
aws eks update-cluster-config \
  --name my-cluster \
  --resources-vpc-config publicAccessCidrs="0.0.0.0/0"
```

### IPv4 vs IPv6 Considerations

| Cluster Type | CIDR Types Allowed |
|-------------|-------------------|
| IPv4 cluster | IPv4 CIDRs only |
| IPv6 cluster (post-Oct 2024) | Both IPv4 and IPv6 CIDRs |
| IPv6 cluster (pre-Oct 2024) | IPv4 CIDRs only |

**New IPv6 clusters** (post-Oct 2024) have dual-stack endpoints and can mix CIDR types.

### Common Patterns

```bash
# Corporate IP only
publicAccessCidrs="203.0.113.0/24"

# Office + VPN
publicAccessCidrs="203.0.113.0/24,10.0.0.0/8"

# Block all public (when using private endpoint)
publicAccessCidrs="0.0.0.0/32"
```

## kubectl Configuration

### Standard Configuration

```bash
# Generate kubeconfig (uses public endpoint by default)
aws eks update-kubeconfig --name my-cluster

# Test connectivity
kubectl get nodes
```

### Force Private Endpoint

```bash
# Update kubeconfig with private endpoint URL
aws eks update-kubeconfig \
  --name my-cluster \
  --endpoint https://my-cluster.privatelink.eks.us-west-2.amazonaws.com

# Or manually add to kubeconfig:
apiVersion: v1
clusters:
- cluster:
    server: https://my-cluster.oidc.eks.us-west-2.amazonaws.com
    # For private endpoint, use the privatelink URL
```

### Verify Endpoint in Use

```bash
# Check current context
kubectl config current-context

# View cluster server URL
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
```

## VPC Endpoint for EKS (PrivateLink)

EKS uses managed VPC endpoints for the API server. These are **not** customer-created endpoints.

### EKS Managed Endpoints

| Service | Endpoint Type |
|---------|---------------|
| eks.amazonaws.com | Interface (PrivateLink) |
| eks.us-west-2.amazonaws.com | Gateway (S3) |

### When You Might Need Additional Endpoints

For certain AWS services accessed from within the VPC:

```bash
# If EKS VPC endpoint exists (for describe-cluster calls)
# Not typically needed for cluster operations
```

### Common Misconception

**Myth:** "I need to create a PrivateLink endpoint to access my private cluster."

**Reality:** No. EKS manages the private endpoint automatically. You only need network access (VPN, Direct Connect, or bastion) to reach it.

## Security Best Practices

1. **Use both public and private endpoints** - Allows internal access without bastion while still enabling public access for CI/CD

2. **Restrict public endpoint CIDRs** - Limit to known IP ranges (office, CI/CD runners)

3. **Disable public endpoint for highest security** - Requires VPN/Direct Connect but provides maximum isolation

4. **Configure cluster security group correctly** - Allow only necessary traffic

5. **Use IMDSv2 on nodes** - Prevents metadata service attacks
   ```bash
   aws ec2 modify-instance-metadata-options \
     --instance-id i-xxxx \
     --http-tokens required \
     --http-put-response-hop-limit 1
   ```

6. **Prefer IRSA/Pod Identity over node IAM roles** - Limits credential exposure

## Troubleshooting Access Issues

### Cannot reach cluster from internet

```bash
# Check endpoint configuration
aws eks describe-cluster \
  --name my-cluster \
  --query 'cluster.resourcesVpcConfig'

# Check public access CIDRs
# Verify your IP is within allowed CIDRs
curl ifconfig.me
```

### Cannot reach private endpoint from VPC

```bash
# Check VPC DNS settings
aws ec2 describe-vpcs \
  --vpc-ids vpc-xxxx \
  --query 'Vpcs[0].[VpcId,EnableDnsHostnames,EnableDnsSupport]'

# Test DNS resolution
nslookup my-cluster.oidc.eks.us-west-2.amazonaws.com

# Check route tables for private hosted zone
# (Note: hosted zone is managed by EKS, not visible in your Route53)
```

### kubectl exec/logs failing

```bash
# Check security group rules allow port 10250
aws ec2 describe-security-groups \
  --group-ids sg-cluster-xxxx

# Verify node has security group with cluster access
kubectl get nodes -o wide

# Test kubelet port connectivity
nc -zv node-ip 10250
```

## References

- [EKS Cluster Endpoint](https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html)
- [EKS Security Group Requirements](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html)
- [Linux Bastion Hosts on AWS](https://aws.amazon.com/quickstart/architecture/linux-bastion/)
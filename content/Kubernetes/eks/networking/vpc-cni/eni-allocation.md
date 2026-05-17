---
title: ENI and IP Allocation
tags: [eks, networking, vpc-cni, eni, ipam]
date: 2026-05-17
description: Deep dive into ENI and IP allocation mechanics, warm pools, and WARM target settings
---

# ENI and IP Allocation

## Overview

VPC CNI manages Elastic Network Interfaces (ENIs) and IP addresses to provide each pod with a native VPC IP. Understanding the allocation mechanics helps optimize pod density and reduce EC2 API throttling.

## ENI Basics

Each EC2 instance type has limits:

| Property | Description |
|----------|-------------|
| Max ENIs | Maximum network interfaces per instance |
| IPs per ENI | Secondary IPs per interface (primary + secondaries) |
| Max Pods | Calculated: `(ENIs × (IPs_per_ENI - 1)) + 2` |

### Max Pods Formula

```
Max Pods = (Max ENIs × (IPs per ENI - 1)) + 2

Example for m5.xlarge:
  Max ENIs = 4
  IPs per ENI = 15
  Max Pods = (4 × (15 - 1)) + 2 = 58
```

The `-1` accounts for the primary IP (used by the node itself). The `+2` provides a small buffer for the node's kubelet and kube-proxy.

## Default Warm Pool Behavior

By default, ipamd maintains **1 extra ENI** as a warm pool to reduce pod launch latency.

### Default Allocation Scheme

```
Pod Count    ENIs Allocated    Warm Pool    Purpose
─────────────────────────────────────────────────────
0-29         1 (primary only)    0         Node baseline
30-58        2                   1         First ENI exhausted
59-87        3                   1         Second ENI exhausted
```

### Why 30?

Each ENI (except the primary) can have up to 30 IPs. When pods exceed the available IPs on existing ENIs, ipamd allocates a new ENI.

## Warm Pool Configuration Options

### WARM_ENI_TARGET (Default: 1)

```bash
# Keep specified number of ENIs warm (with all their IPs)
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_WARM_ENI_TARGET=2
```

| Setting | Behavior |
|---------|----------|
| `1` (default) | Keep 1 extra ENI with all IPs ready |
| `0` | No warm pool, allocate only when needed (slower pod launches) |
| `2` | Keep 2 extra ENIs warm |

**Trade-off**: Higher WARM_ENI_TARGET = faster pod launches but more IP addresses allocated (potential waste).

### WARM_IP_TARGET

```bash
# Keep specified number of free IP addresses available
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_WARM_IP_TARGET=5
```

| Setting | Behavior |
|---------|----------|
| `0` or unset | Use WARM_ENI_TARGET behavior |
| `5` | Keep 5 free IPs ready at all times |

**When to use**: When you know exactly how many IPs you need available.

**Important**: Can cause EC2 API throttling in large clusters. Combine with `MINIMUM_IP_TARGET`.

### MINIMUM_IP_TARGET

```bash
# Pre-allocate minimum number of IPs regardless of current usage
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_MINIMUM_IP_TARGET=30
```

**Purpose**: Pre-scale IP allocation for known pod density without wasting IPs during scale-down.

| WARM_IP_TARGET | MINIMUM_IP_TARGET | Behavior |
|----------------|-------------------|----------|
| Not set | 30 | Pre-allocate 30 IPs, deallocate when pod count drops |
| 3 | 30 | Keep at least 30 IPs, plus 3 free IPs warm |

**Example**: If 30 pods are expected per node, set `MINIMUM_IP_TARGET=30` to pre-allocate, with `WARM_IP_TARGET=2` for burst.

### Combining WARM_IP_TARGET and MINIMUM_IP_TARGET

```bash
# Pre-allocate 30 IPs, keep 5 free for scaling
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_MINIMUM_IP_TARGET=30 \
  AWS_VPC_K8S_CNI_WARM_IP_TARGET=5
```

| Pod Count | IPs Allocated | Free IPs | Notes |
|-----------|---------------|----------|-------|
| 0 | 30 | 30 | MINIMUM_IP_TARGET ensures 30 allocated |
| 25 | 30 | 5 | WARM_IP_TARGET met |
| 30 | 30 | 0 | All allocated |
| 35 | 35 | 0 | +5 IPs allocated for new pods |

### WARM_PREFIX_TARGET (Prefix Delegation Mode)

```bash
# Keep specified number of /28 prefixes warm
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_WARM_PREFIX_TARGET=1
```

**Used only when `ENABLE_PREFIX_DELEGATION=true`**. Each prefix is a /28 (16 IPs).

## Allocation Decision Tree

```
                    Start
                      │
                      ▼
        ┌─────────────────────────┐
        │ ENABLE_PREFIX_DELEGATION│
        └─────────┬───────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
     true                false
        │                   │
        ▼                   ▼
   WARM_PREFIX_TARGET   WARM_IP_TARGET
        │                   │
        │         ┌─────────┴─────────┐
        │         │                   │
        │      set                 not set
        │         │                   │
        │         ▼                   ▼
        │   WARM_IP_TARGET       WARM_ENI_TARGET
        │         │                   │
        │         └─────────┬─────────┘
        │                   │
        └─────────┬─────────┘
                  │
                  ▼
           EC2 API Call
         (Allocate ENI or IPs)
```

## Practical Configuration Examples

### Scenario 1: Standard Workload (Default)

```yaml
# Use defaults - 1 warm ENI
# Good for: Consistent pod counts, no rapid scaling
env:
- name: AWS_VPC_K8S_CNI_WARM_ENI_TARGET
  value: "1"
```

### Scenario 2: Pre-scaled for Known Density

```yaml
# Pre-allocate for 30 pods, small warm pool for headroom
env:
- name: AWS_VPC_K8S_CNI_MINIMUM_IP_TARGET
  value: "30"
- name: AWS_VPC_K8S_CNI_WARM_IP_TARGET
  value: "5"
# Good for: Known workload with occasional burst
```

### Scenario 3: High Density with Prefix Delegation

```yaml
# Use prefix delegation with 1 warm prefix
env:
- name: AWS_VPC_K8S_CNI_ENABLE_PREFIX_DELEGATION
  value: "true"
- name: AWS_VPC_K8S_CNI_WARM_PREFIX_TARGET
  value: "1"
# Good for: Dense clusters, many pods per node
```

### Scenario 4: Cost Optimization (Small Warm Pool)

```yaml
# Minimize wasted IPs, slower pod launches
env:
- name: AWS_VPC_K8S_CNI_WARM_IP_TARGET
  value: "1"
# Good for: Cost-sensitive, infrequent pod creation
```

## EC2 API Rate Limiting

### Impact of Settings

| Setting | EC2 API Calls | Throttle Risk |
|---------|---------------|---------------|
| High WARM_ENI_TARGET | Fewer (ENI-level) | Lower |
| High WARM_IP_TARGET | More (IP-level) | Higher |
| Low targets | More frequent | Higher |

### Reducing Throttling

```bash
# Use MINIMUM_IP_TARGET instead of WARM_IP_TARGET alone
# Pre-allocates in bulk rather than incremental

# Enable subnet discovery (reduces DescribeSubnets calls)
# Enabled by default in v1.18+

# Consider MAX_ENI to cap ENIs
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_MAX_ENI=5
```

## Monitoring Allocation

### Check Current Allocation

```bash
# View ENIs and IPs on a node
kubectl exec -n kube-system aws-node-xxxx -- \
  aws ec2 describe-network-interfaces \
  --filters "Name=tag:Name,Values=*-eni-*" \
  --query 'NetworkInterfaces[*].[Attachment.InstanceId,PrivateIpAddress,Status,InterfaceType]'

# View ipamd state
kubectl exec -n kube-system aws-node-xxxx -- \
  cat /var/run/aws-node/ipam.json | jq .
```

### Metrics to Watch

| Metric | Description | Alert If |
|--------|-------------|----------|
| `aws_vpc_ipamd_eni_allocated` | ENIs allocated | At capacity |
| `aws_vpc_ipamd_prefix_assigned` | Prefixes assigned | Low free |
| EC2 API throttle % | Throttling rate | >5% |

### CloudWatch Insights Query for IP Exhaustion

```bash
# Find nodes approaching IP limits
aws logs insights-query \
  --log-group-name /aws/eks/my-cluster/cluster/api \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --query-string 'fields @timestamp, @message | filter @message like "failed to allocate" | limit 20'
```

## Common Allocation Issues

### Issue: Pods stuck in Pending despite available IPs

**Cause**: IP addresses are assigned to pods but not freed properly, or ENI limit reached.

```bash
# Check ENI count
kubectl exec -n kube-system aws-node-xxxx -- \
  aws ec2 describe-network-interfaces \
  --filters "Name=attachment.instance-id,Values=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

# Check ipamd state
kubectl exec -n kube-system aws-node-xxxx -- cat /var/run/aws-node/ipam.json
```

**Solution**: Increase instance size or use prefix delegation.

### Issue: EC2 API Throttling

**Cause**: Too many IP allocation calls due to low WARM_IP_TARGET.

```bash
# Check CloudWatch for throttle events
aws logs filter-log-events \
  --log-group-name /aws/eks/my-cluster/cluster/api \
  --filter-pattern "ThrottlingException"
```

**Solution**: Increase WARM_IP_TARGET or use MINIMUM_IP_TARGET for pre-allocation.

### Issue: IP Exhaustion in Subnet

**Cause**: All IPs in subnet CIDR are allocated.

```bash
# Check subnet IP usage
aws ec2 describe-subnets \
  --subnet-ids subnet-xxxxxxxx \
  --query 'Subnets[0].[SubnetId,AvailableIpAddressCount,CidrBlock]'
```

**Solution**: Use custom networking to use a different subnet, or expand VPC CIDR.

## References

- [WARM_ENI_TARGET, WARM_IP_TARGET, MINIMUM_IP_TARGET](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/eni-and-ip-target.md)
- [EC2 ENI Limits](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)
- [IP Address Per Instance Type](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html)
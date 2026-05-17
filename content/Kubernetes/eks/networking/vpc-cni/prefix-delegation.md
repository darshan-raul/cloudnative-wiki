---
title: Prefix Delegation
tags: [eks, networking, vpc-cni, prefix-delegation]
date: 2026-05-17
description: Increase pod density with IP prefix delegation - /28 prefixes instead of individual IPs
---

# Prefix Delegation

## Overview

Prefix delegation increases the number of pods per node by assigning IP **prefixes** (/28 blocks of 16 IPs) instead of individual secondary IP addresses. This dramatically increases pod capacity on Nitro-based instances.

## Why Prefix Delegation?

### Standard Mode (No Prefix Delegation)

| Component | Limit |
|-----------|-------|
| ENIs per instance | Instance-dependent (e.g., m5.xlarge = 4) |
| IPs per ENI | 15 secondary IPs |
| Usable IPs per ENI | 15 (one is primary for node) |
| **Max pods formula** | `(ENIs × 14) + 2 = (4 × 14) + 2 = 58` |

### Prefix Delegation Mode

| Component | Limit |
|-----------|-------|
| ENIs per instance | Instance-dependent |
| Prefixes per ENI | 15 prefixes |
| IPs per prefix | 16 IPs |
| Usable IPs per ENI | 15 × 16 = 240 |
| **Max pods formula** | `(ENIs × 15 × 16) + 2` |

### Pod Capacity Comparison

| Instance Type | Standard Mode | With Prefix Delegation | Increase |
|---------------|---------------|------------------------|----------|
| t3.medium | 17 | ~110 | 6.5× |
| t3.large | 35 | ~234 | 6.7× |
| m5.xlarge | 58 | ~722 | 12.4× |
| m5.2xlarge | 118 | ~1474 | 12.5× |
| c5.4xlarge | 234 | ~2922 | 12.5× |

**Note**: Exact numbers vary by instance generation and ENI attachments for other purposes.

## How It Works

### Without Prefix Delegation

```
ENI (eth0)
├── Primary IP: 10.0.1.10/32 (node)
├── Secondary IP: 10.0.1.11/32 → Pod A
├── Secondary IP: 10.0.1.12/32 → Pod B
├── Secondary IP: 10.0.1.13/32 → Pod C
... (max 15 secondary IPs)
```

### With Prefix Delegation

```
ENI (eth0)
├── Primary IP: 10.0.1.10/32 (node)
├── /28 Prefix: 10.0.1.16/28
│   ├── 10.0.1.16/32 → Pod A
│   ├── 10.0.1.17/32 → Pod B
│   ├── 10.0.1.18/32 → Pod C
│   ... (16 IPs per prefix)
├── /28 Prefix: 10.0.1.32/28
│   ├── 10.0.1.32/32 → Pod D
│   ├── 10.0.1.33/32 → Pod E
│   ... (16 more pods)
... (15 prefixes per ENI = 240 pods per ENI)
```

## Prerequisites

- Nitro-based instance types (not T2/T3 burst, not older generations)
- VPC CNI v1.9.0 or later
- Kubernetes 1.18 or later (for best support)

## Instance Type Support

Prefix delegation works on most Nitro-based instances:

```bash
# Check if instance supports prefix delegation
aws ec2 describe-instance-types \
  --instance-types t3.medium t3.large m5.xlarge m5.2xlarge c5.xlarge c5.4xlarge \
  --query 'InstanceTypes[*].[InstanceType,NetworkInfo.MaximumNetworkInterfaces,NetworkInfo.Ipv4AddressesPerInterface]'
```

### Unsupported

- T2/T3 burst instances (not Nitro)
- Some older non-Nitro instance types
- Windows nodes

## Configuration

### Enable Prefix Delegation

```bash
# Via kubectl
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_ENABLE_PREFIX_DELEGATION=true
```

### Complete DaemonSet Environment

```yaml
env:
- name: AWS_VPC_K8S_CNI_ENABLE_PREFIX_DELEGATION
  value: "true"
- name: AWS_VPC_K8S_CNI_WARM_PREFIX_TARGET
  value: "1"
- name: AWS_VPC_K8S_CNI_MINIMUM_IP_TARGET
  value: "16"
- name: AWS_VPC_K8S_CNI_WARM_IP_TARGET
  value: "16"
```

### Verify Configuration

```bash
# Check if prefix delegation is enabled
kubectl exec -n kube-system aws-node-xxxx -- \
  ip rule show

# View allocated prefixes
kubectl exec -n kube-system aws-node-xxxx -- \
  aws ec2 describe-network-interfaces \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Ipv4Prefixes]'

# Check ipamd for prefix info
kubectl exec -n kube-system aws-node-xxxx -- \
  cat /var/run/aws-node/ipam.json | jq '.ipv4prefix'
```

## Transitioning from Standard to Prefix Delegation

### Critical: Do Not Rolling Replace Nodes

**Important**: When transitioning from standard mode (secondary IPs) to prefix delegation mode, create new node groups with prefix delegation enabled. Do not attempt to enable prefix delegation on existing nodes via rolling replacement.

### Recommended Transition Process

1. **Create new node group with prefix delegation enabled**

```yaml
# new-nodegroup-prefix.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
  region: us-west-2
managedNodeGroups:
  - name: ng-prefix
    instanceType: m5.xlarge
    desiredCapacity: 3
    labels:
      ip-mode: prefix
    preBootstrapCommands:
      - echo "AWS_VPC_K8S_CNI_ENABLE_PREFIX_DELEGATION=true" >> /etc/eks/aws.conf
```

2. **Cordon old nodes**

```bash
kubectl cordon <old-node-name>
```

3. **Drain old nodes**

```bash
kubectl drain <old-node-name> --ignore-daemonsets
```

4. **Delete old node group**

```bash
eksctl delete nodegroup --cluster my-cluster --name <old-ng-name>
```

### Why Rolling Replace Doesn't Work

When a node joins the cluster:
1. Node gets ENIs attached
2. ipamd starts with existing ENIs (secondary IPs, not prefixes)
3. Transitioning to prefix mode would require full ENI detachment/reattachment
4. This causes pod disruption and potential networking issues

## WARM Prefix Target vs WARM IP Target

### WARM_PREFIX_TARGET (Prefix Delegation Mode)

```bash
# Keep specified number of /28 prefixes warm
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_WARM_PREFIX_TARGET=1
```

| Value | Behavior |
|-------|----------|
| `0` | Allocate prefixes only when needed |
| `1` (default) | Keep 1 prefix (16 IPs) warm |
| `2` | Keep 2 prefixes (32 IPs) warm |

### Interaction with WARM_IP_TARGET

When `ENABLE_PREFIX_DELEGATION=true`:
- `WARM_IP_TARGET` overrides `WARM_PREFIX_TARGET`
- If `WARM_IP_TARGET=16` and `WARM_PREFIX_TARGET=1`, the behavior follows `WARM_IP_TARGET`

```bash
# WARM_IP_TARGET takes precedence
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_ENABLE_PREFIX_DELEGATION=true \
  AWS_VPC_K8S_CNI_WARM_IP_TARGET=32 \
  AWS_VPC_K8S_CNI_MINIMUM_IP_TARGET=64
```

| Scenario | WARM_IP_TARGET | WARM_PREFIX_TARGET | Result |
|----------|----------------|-------------------|--------|
| A | 16 | 1 | 16 IPs warm (via prefixes) |
| B | 32 | 1 | 32 IPs warm (2 prefixes needed) |
| C | not set | 1 | 16 IPs warm (1 prefix) |

## Using with Security Groups for Pods

Prefix delegation works with Security Groups for Pods (SGP):

```yaml
# Both can be enabled together
env:
- name: AWS_VPC_K8S_CNI_ENABLE_PREFIX_DELEGATION
  value: "true"
- name: AWS_VPC_K8S_CNI_ENABLE_POD_ENI
  value: "true"
- name: POD_SECURITY_GROUP_ENFORCING_MODE
  value: "standard"
```

### Branch ENI Behavior with Prefix Delegation

| Feature | Standard Mode | With Prefix Delegation |
|---------|---------------|------------------------|
| Branch ENIs per instance | Instance limit | Same instance limit |
| IPs per branch ENI | 1 (primary only) | 1 (primary only) |
| Prefix delegation effect | N/A | Does not affect branch ENI pods |

Branch ENI pods (with SGP) still get a single primary IP from their dedicated ENI - prefix delegation affects only standard pods.

## Verifying Prefix Delegation is Working

### Check Pod Network Interface

```bash
# On the node, check pod interface
ip addr show eth0

# You should see /28 addresses assigned
# Example output (truncated):
# inet 10.0.1.17/32 scope global eth0
# inet 10.0.1.18/32 scope global eth0
# inet 10.0.1.19/32 scope global eth0
```

### Check CNI Logs for Prefix Allocation

```bash
# Look for prefix-related logs
kubectl logs -n kube-system -l k8s-app=aws-node --tail=100 | grep -i prefix
```

Expected log entries:
```
level=debug msg="Creating/deleting ENI"
level=debug msg="Allocating prefix" ipv4Prefix=10.0.1.16/28
level=info msg="ishi: isPrimaryDevice: true, getDeviceNumber: 0
```

### Check ENI Prefixes

```bash
kubectl exec -n kube-system aws-node-xxxx -- \
  aws ec2 describe-network-interfaces \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Ipv4Prefixes]'
```

Example output:
```
[
    ["eni-abc123", [{"Ipv4Prefix": "10.0.1.16/28"}, {"Ipv4Prefix": "10.0.1.32/28"}]],
    ["eni-def456", [{"Ipv4Prefix": "10.0.1.48/28"}]]
]
```

## Limitations

1. **Linux only** - Prefix delegation not supported on Windows nodes
2. **Nitro instances only** - Not available on T2/T3 burst instances
3. **Cannot downgrade below v1.9.0** - Once enabled, cannot downgrade without new nodes
4. **Mixed mode limitations** - Pods on a node should all use same mode
5. **External SNAT behavior** - With `POD_SECURITY_GROUP_ENFORCING_MODE=standard` and `externalSNAT=false`, pod traffic outside VPC uses node's security groups

## Performance Considerations

### Pod Launch Latency

- First pod on a new ENI may have slightly higher latency (prefix assignment)
- Warm prefix pool eliminates this for most cases

### Memory Usage

ipamd memory usage increases slightly with prefix delegation (tracking more IPs):
- Standard: ~100MB typical
- Prefix Delegation: ~120MB typical (20% increase)

## Common Issues

### Issue: Pods stuck in Pending after enabling prefix delegation

**Diagnosis**:
```bash
# Check if prefix delegation is actually enabled
kubectl exec -n kube-system aws-node-xxxx -- \
  env | grep PREFIX

# Check ipamd logs
kubectl logs -n kube-system aws-node-xxxx -c aws-node --tail=50 | grep -i prefix
```

**Solution**: Nodes may need to be recycled to pick up the configuration. Create new nodes with prefix delegation enabled.

### Issue: "Insufficient IP address capacity" error

**Cause**: Transitioning nodes but old allocation mode still active on some nodes.

**Solution**: Complete the node transition - all nodes should use prefix delegation.

## IPv6 Prefix Delegation

Prefix delegation for IPv6 uses /80 prefixes:

```bash
# Enable IPv6 mode (requires prefix delegation)
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_ENABLE_IPv6=true \
  AWS_VPC_K8S_CNI_ENABLE_PREFIX_DELEGATION=true
```

IPv6 prefix delegation follows same principles but uses larger prefixes (/80 for IPv6).

## References

- [Prefix Delegation AWS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html)
- [Prefix Mode Best Practices](https://docs.aws.amazon.com/eks/latest/best-practices/prefix-mode-linux.html)
- [VPC CNI GitHub - Prefix Delegation](https://github.com/aws/amazon-vpc-cni-k8s#vpc-cni-feature-matrix)
- [EKS Workshop - Prefix Delegation](https://www.eksworkshop.com/docs/networking/vpc-cni/prefix/)
---
title: VPC CNI Configuration Reference
tags: [eks, networking, vpc-cni, configuration]
date: 2026-05-17
description: Complete configuration reference for VPC CNI - all environment variables and their valid values
---

# VPC CNI Configuration Reference

## Configuration Methods

| Installation Type | Configuration Method |
|------------------|----------------------|
| EKS Addon (Managed) | AWS API / Console / Terraform |
| Self-managed (Helm) | Helm values or ConfigMap |
| Self-managed (YAML) | ConfigMap only |

## Environment Variables

All VPC CNI configuration is via environment variables on the `aws-node` DaemonSet.

### Quick Reference Table

| Variable | Default | Valid Values | Since |
|----------|---------|--------------|-------|
| `AWS_VPC_K8S_CNI_LOGLEVEL` | DEBUG | DEBUG, INFO, WARN, ERROR, FATAL | v1.0 |
| `AWS_VPC_K8S_CNI_EXTERNALSNAT` | false | true, false | v1.0 |
| `AWS_VPC_K8S_CNI_RANDOMIZESNAT` | prng | hashrandom, prng, none | v1.0 |
| `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG` | false | true, false | v1.1 |
| `AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS` | empty | Comma-separated CIDRs | v1.6 |
| `AWS_VPC_ENI_MTU` | 9001 | 576-9001 (IPv4), 1280-9001 (IPv6) | v1.6 |
| `POD_MTU` | 9001 | 576-9001 (IPv4), 1280-9001 (IPv6) | v1.16.4 |
| `WARM_ENI_TARGET` | 1 | Integer >= 0 | v1.0 |
| `WARM_IP_TARGET` | (none) | Integer >= 0 | v1.2 |
| `MINIMUM_IP_TARGET` | (none) | Integer >= 0 | v1.6 |
| `MAX_ENI` | (none) | Integer >= 0 | v1.3 |
| `ENABLE_PREFIX_DELEGATION` | false | true, false | v1.9 |
| `WARM_PREFIX_TARGET` | (none) | Integer >= 0 | v1.9 |
| `ENABLE_POD_ENI` | false | true, false | v1.7 |
| `POD_SECURITY_GROUP_ENFORCING_MODE` | strict | strict, standard | v1.11 |
| `ENABLE_IPv4` | true | true, false | v1.10 |
| `ENABLE_IPv6` | false | true, false | v1.10 |
| `ENABLE_NFTABLES` | false | true, false | v1.12.1 (deprecated v1.13.2) |
| `CLUSTER_NAME` | (none) | String | v1.6 |
| `CLUSTER_ENDPOINT` | (none) | String (API server endpoint) | v1.12.1 |
| `DISABLE_INTROSPECTION` | false | true, false | v1.4 |
| `DISABLE_METRICS` | false | true, false | v1.4 |
| `AWS_MANAGE_ENIS_NON_SCHEDULABLE` | false | true, false | v1.12.6 |
| `DISABLE_LEAKED_ENI_CLEANUP` | false | true, false | v1.13.0 |
| `ENABLE_SUBNET_DISCOVERY` | true | true, false | v1.18.0 |
| `ENABLE_V6_EGRESS` | false | true, false | v1.13.0 |
| `ENABLE_BANDWIDTH_PLUGIN` | false | true, false | v1.10.0 |
| `ADDITIONAL_ENI_TAGS` | {} | JSON object | v1.6 |

## Detailed Reference

### Networking Configuration

#### AWS_VPC_K8S_CNI_LOGLEVEL

Controls logging verbosity for ipamd and cni-metric-helper.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_LOGLEVEL=DEBUG
```

| Value | Use Case |
|-------|----------|
| DEBUG | Troubleshooting, development |
| INFO | Default for most deployments |
| WARN | Production when reducing log volume |
| ERROR | Minimal logging |

#### AWS_VPC_K8S_CNI_LOG_FILE

Redirect logging to file instead of stdout.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_LOG_FILE=/var/log/aws-routed-eni/ipamd.log
```

#### AWS_VPC_K8S_PLUGIN_LOG_FILE

CNI plugin logging output.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_PLUGIN_LOG_FILE=/var/log/aws-routed-eni/plugin.log
```

#### AWS_VPC_ENI_MTU

Set MTU for all ENIs attached to the node.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_ENI_MTU=9001
```

| MTU Value | Notes |
|-----------|-------|
| 9001 | Standard for jumbo frames in AWS |
| 1500 | Standard Ethernet |
| 576 | Minimum for IPv4 |

#### POD_MTU

MTU for pod virtual interfaces. Should typically match AWS_VPC_ENI_MTU.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  POD_MTU=9001
```

#### AWS_VPC_K8S_CNI_VETHPREFIX

Prefix for veth device names on host side.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_VETHPREFIX=eni
```

**Reserved prefixes**: `eth`, `vlan`, `lo` - cannot be used.

### SNAT Configuration

#### AWS_VPC_K8S_CNI_EXTERNALSNAT

Control Source Network Address Translation for pod egress.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_EXTERNALSNAT=false
```

| Value | Behavior |
|-------|----------|
| `false` (default) | Pod egress to outside VPC is SNATed to node's primary IP |
| `true` | Pod keeps its pod IP as source (no SNAT) |

**When to use true**: VPN, Direct Connect, or pod needs direct routing without NAT.

#### AWS_VPC_K8S_CNI_RANDOMIZESNAT

Randomize source ports for SNAT connections.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_RANDOMIZESNAT=prng
```

| Value | Behavior |
|-------|----------|
| `prng` (default) | Use `--random-fully` for better port randomization |
| `hashrandom` | Legacy random mode |
| `none` | Sequential port allocation (for NACL compatibility) |

#### AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS

CIDRs to exclude from SNAT.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS="10.0.0.0/8,172.16.0.0/12"
```

**Use case**: Exclude RFC 1918 private ranges when using external SNAT to prevent hairpin routing.

### IP Allocation Settings

#### WARM_ENI_TARGET

Number of warm ENIs to maintain.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_WARM_ENI_TARGET=1
```

**Ignored when**: `WARM_IP_TARGET` or `MINIMUM_IP_TARGET` is set.

#### WARM_IP_TARGET

Number of free IP addresses to maintain warm.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_WARM_IP_TARGET=5
```

**Warning**: Can cause EC2 API throttling in large clusters. Use with `MINIMUM_IP_TARGET`.

#### MINIMUM_IP_TARGET

Minimum total IP addresses to pre-allocate.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_MINIMUM_IP_TARGET=30
```

**Use with**: `WARM_IP_TARGET=2-3` for burst headroom.

#### MAX_ENI

Maximum ENIs to attach regardless of instance type limits.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_MAX_ENI=5
```

**Use when**: You need to limit resource usage for cost or compliance.

### Prefix Delegation Settings

#### ENABLE_PREFIX_DELEGATION

Enable assigning /28 prefixes instead of individual IPs.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_ENABLE_PREFIX_DELEGATION=true
```

#### WARM_PREFIX_TARGET

Number of warm /28 prefixes.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_WARM_PREFIX_TARGET=1
```

**Only applies when**: `ENABLE_PREFIX_DELEGATION=true`.

### Security Groups for Pods Settings

#### ENABLE_POD_ENI

Enable Security Groups for Pods feature.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_ENABLE_POD_ENI=true
```

**Requires**: EKS 1.17+ and Nitro-based instances.

#### POD_SECURITY_GROUP_ENFORCING_MODE

How security groups are enforced.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  POD_SECURITY_GROUP_ENFORCING_MODE=strict
```

| Mode | Behavior |
|------|----------|
| `strict` (default) | Pod SG rules apply to all traffic |
| `standard` | Relaxed - traffic to/from same host uses node SG |

### Custom Networking Settings

#### AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG

Enable custom networking (pods in different subnet than nodes).

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
```

**Requires**: `ENIConfig` custom resources and node annotations/labels.

#### ENI_CONFIG_ANNOTATION_DEF

Annotation key for ENIConfig selection.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  ENI_CONFIG_ANNOTATION_DEF=k8s.amazonaws.com/eniConfig
```

#### ENI_CONFIG_LABEL_DEF

Label key for ENIConfig selection.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  ENI_CONFIG_LABEL_DEF=k8s.amazonaws.com/eniConfig
```

**Set to `topology.kubernetes.io/zone`** for AZ-based ENIConfig selection.

### IPv4/IPv6 Configuration

#### ENABLE_IPv4

Enable IPv4 mode.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_ENABLE_IPv4=true
```

| Value | Notes |
|-------|-------|
| `true` (default) | IPv4 pod IPs |
| `false` | Disable IPv4 |

#### ENABLE_IPv6

Enable IPv6 mode.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_ENABLE_IPv6=true
```

**Requires**: `ENABLE_PREFIX_DELEGATION=true` for IPv6 mode.

**Note**: Dual-stack not yet supported.

### Observability Settings

#### DISABLE_INTROSPECTION

Disable the debugging introspection endpoint.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_DISABLE_INTROSPECTION=false
```

#### DISABLE_METRICS

Disable Prometheus metrics endpoint.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_DISABLE_METRICS=false
```

**Metrics endpoint**: Port 61678 on `/metrics`

#### INTROSPECTION_BIND_ADDRESS

Address for introspection endpoint.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  INTROSPECTION_BIND_ADDRESS=127.0.0.1:61679
```

### Cluster Configuration

#### CLUSTER_NAME

Cluster name for tagging ENIs.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  CLUSTER_NAME=my-cluster
```

#### CLUSTER_ENDPOINT

API server endpoint for direct CNI-to-API-server communication.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  CLUSTER_ENDPOINT=https://ABCD1234.gr7.us-west-2.eks.amazonaws.com
```

**Benefit**: Reduces pod initialization time by bypassing kube-proxy for API server communication.

### Advanced Settings

#### AWS_MANAGE_ENIS_NON_SCHEDULABLE

Allow ipamd to manage ENIs on nodes marked as unschedulable.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_MANAGE_ENIS_NON_SCHEDULABLE=false
```

#### DISABLE_LEAKED_ENI_CLEANUP

Disable hourly cleanup of leaked ENIs.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  DISABLE_LEAKED_ENI_CLEANUP=false
```

#### ENABLE_SUBNET_DISCOVERY

Auto-discover subnets with `kubernetes.io/role/cni` tag.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_ENABLE_SUBNET_DISCOVERY=true
```

#### ADDITIONAL_ENI_TAGS

Add custom tags to all ENIs.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  ADDITIONAL_ENI_TAGS='{"Environment":"production","Team":"platform"}'
```

**Note**: Tags with `k8s.amazonaws.com` prefix are ignored.

#### ENABLE_BANDWIDTH_PLUGIN

Enable CNI bandwidth plugin for traffic shaping.

```bash
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_ENABLE_BANDWIDTH_PLUGIN=true
```

**Warning**: Not compatible with VPC CNI network policies (eBPF).

## Complete Example Configuration

```yaml
# Complete VPC CNI configuration
env:
# Networking
- name: AWS_VPC_K8S_CNI_LOGLEVEL
  value: "DEBUG"
- name: AWS_VPC_ENI_MTU
  value: "9001"
- name: AWS_VPC_K8S_CNI_EXTERNALSNAT
  value: "false"
- name: AWS_VPC_K8S_CNI_RANDOMIZESNAT
  value: "prng"

# IP Allocation
- name: AWS_VPC_K8S_CNI_MINIMUM_IP_TARGET
  value: "30"
- name: AWS_VPC_K8S_CNI_WARM_IP_TARGET
  value: "5"

# Prefix Delegation (uncomment if using)
# - name: AWS_VPC_K8S_CNI_ENABLE_PREFIX_DELEGATION
#   value: "true"
# - name: AWS_VPC_K8S_CNI_WARM_PREFIX_TARGET
#   value: "1"

# Security Groups for Pods (uncomment if using)
# - name: AWS_VPC_K8S_CNI_ENABLE_POD_ENI
#   value: "true"
# - name: POD_SECURITY_GROUP_ENFORCING_MODE
#   value: "strict"

# Custom Networking (uncomment if using)
# - name: AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG
#   value: "true"

# Cluster
- name: CLUSTER_NAME
  value: "my-cluster"
- name: CLUSTER_ENDPOINT
  value: "https://ABCD1234.gr7.us-west-2.eks.amazonaws.com"

# Tags
- name: ADDITIONAL_ENI_TAGS
  value: '{"Environment":"production"}'
```

## Applying Configuration

### Via kubectl

```bash
# Set single variable
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_WARM_IP_TARGET=5

# Set multiple variables
kubectl set env daemonset/aws-node -n kube-system \
  AWS_VPC_K8S_CNI_MINIMUM_IP_TARGET=30 \
  AWS_VPC_K8S_CNI_WARM_IP_TARGET=5
```

### Via Helm

```bash
helm upgrade aws-vpc-cni aws-eks/aws-vpc-cni \
  --namespace kube-system \
  --reuse-values \
  --set enableNetworkPolicy=true \
  --set env.WARM_IP_TARGET=5 \
  --set env.MINIMUM_IP_TARGET=30
```

### Via EKS Addon

```bash
aws eks update-addon \
  --cluster-name my-cluster \
  --addon-name vpc-cni \
  --addon-version latest \
  --configuration-values '{
    "env": {
      "WARM_IP_TARGET": "5",
      "MINIMUM_IP_TARGET": "30"
    }
  }'
```

## References

- [VPC CNI GitHub README](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/README.md)
- [Helm Chart Configuration](https://github.com/aws/eks-charts/tree/master/stable/aws-vpc-cni)
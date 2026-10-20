---
title: "Reference: EKS Limits, Defaults and Formulas"
description: "The numbers operators need during incidents and planning: max-pods formulas, address and attachment limits, timeouts, disruption defaults, service quotas and version support windows."
tags: [kubernetes/eks/operator-runbook, eks, reference, limits, capacity]
date: 2026-10-20
aliases: [EKS limits cheat sheet, EKS max pods formula]
---

# Reference: EKS Limits, Defaults and Formulas

Values are defaults at the time of writing for the wiki's Kubernetes baseline (1.37). Where a value depends on instance type or account, the command that returns it is given. Check service quotas in your own account (`aws service-quotas list-service-quotas --service-code eks`).

## Pod density (VPC CNI)

| Mode                   | Max Pods per node                                                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------------------ |
| Secondary IP (default) | **ENIs × (IPv4 addresses per ENI − 1) + 2**                                                                  |
| Prefix delegation      | ENIs × (IPv4 addresses per ENI − 1) × 16 + 2, capped by EKS at **110** (instances with < 30 vCPU) or **250** |
| Custom networking      | As secondary IP, but with **ENIs − 1** (the primary ENI isn't used for Pods)                                 |
| Fargate                | 1 Pod per node                                                                                               |

The `+ 2` is for host-network Pods (`aws-node`, `kube-proxy`). Get the inputs, or the full calculation:

```bash
aws ec2 describe-instance-types --instance-types m5.large \
  --query 'InstanceTypes[].NetworkInfo.[MaximumNetworkInterfaces,Ipv4AddressesPerInterface]' --output text
curl -sO https://raw.githubusercontent.com/awslabs/amazon-eks-ami/main/templates/al2/runtime/max-pods-calculator.sh
bash max-pods-calculator.sh --instance-type m5.large --cni-version 1.19.0 [--cni-prefix-delegation-enabled]
```

| Instance     | ENIs × IPs | Max Pods (secondary IP) |
| ------------ | ---------- | ----------------------- |
| `t3.medium`  | 3 × 6      | 17                      |
| `m5.large`   | 3 × 10     | 29                      |
| `m5.xlarge`  | 4 × 15     | 58                      |
| `m5.2xlarge` | 4 × 15     | 58                      |
| `m5.4xlarge` | 8 × 30     | 234                     |

**Warm pool defaults:** `WARM_ENI_TARGET=1` (one spare ENI per node), `WARM_IP_TARGET` and `MINIMUM_IP_TARGET` unset, `WARM_PREFIX_TARGET=1` in prefix mode.

## Address planning

- **Subnet size for Pods:** max nodes × (max Pods per node + warm addresses per node), plus room for a full node-group rotation, which briefly doubles nodes.
- **Cluster subnets:** EKS needs **up to 5 free IP addresses** in the cluster's subnets for control-plane upgrades and ENI moves.
- **AWS reserves 5 addresses** in every subnet (first four and last).
- **Service CIDR:** `10.100.0.0/16`, or `172.20.0.0/16` if the VPC uses `10.x`. It's fixed at creation. `kube-dns` is the `.10` address.

## Networking limits

| Limit                               | Value                                                                                              |
| ----------------------------------- | -------------------------------------------------------------------------------------------------- |
| VPC DNS resolver                    | **1,024 packets per second per ENI**; drops show as `linklocal_allowance_exceeded` in `ethtool -S` |
| IMDSv2 hop limit                    | 1 blocks non-host-network Pods from IMDS; 2 allows them                                            |
| ALB idle timeout                    | 60 s                                                                                               |
| ALB/NLB target deregistration delay | 300 s                                                                                              |
| Security groups per ENI             | 5 (adjustable quota)                                                                               |
| Rules per security group            | 60 inbound + 60 outbound (adjustable quota)                                                        |

## Storage

| Item                                   | Value                                                                                                                                                                                                                       |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EBS attachment                         | One instance, one AZ (io1/io2 Multi-Attach excepted)                                                                                                                                                                        |
| Attachment slots                       | Per instance type. Many Nitro types share one limit across EBS volumes, ENIs and NVMe instance store. Check with `kubectl get csinode <node> -o jsonpath='{.spec.drivers[?(@.name=="ebs.csi.aws.com")].allocatable.count}'` |
| gp3 baseline                           | 3,000 IOPS and 125 MiB/s regardless of size; more is provisioned separately                                                                                                                                                 |
| Force-detach wait on an unhealthy node | ~6 minutes (attach/detach controller), unless the node is tainted `out-of-service`                                                                                                                                          |

## Pod and node lifecycle

| Item                                          | Default                                                                                 |
| --------------------------------------------- | --------------------------------------------------------------------------------------- |
| `terminationGracePeriodSeconds`               | 30 s                                                                                    |
| Eviction after node unreachable or not-ready  | 300 s (`tolerationSeconds` added by DefaultTolerationSeconds)                           |
| Admission webhook `timeoutSeconds`            | 10 s default, 30 s maximum                                                              |
| Managed node group update `maxUnavailable`    | 1 node                                                                                  |
| Managed node group eviction failure           | Fails with `PodEvictionFailure` after **15 min** of blocked evictions, unless `--force` |
| Karpenter NodeClaim registration              | Deleted and retried if the node hasn't registered in **15 min**                         |
| Karpenter default disruption budget           | `nodes: 10%` per NodePool                                                               |
| kubelet `imageGCHighThresholdPercent` / `Low` | 85 / 80                                                                                 |
| kubelet hard eviction (EKS AMIs)              | `memory.available<100Mi`, `nodefs.available<10%`, `nodefs.inodesFree<5%`                |

## Version skew and support

| Rule                       | Value                                                                                                        |
| -------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Control-plane upgrade step | One minor version at a time                                                                                  |
| kubelet vs API server      | kubelet may be up to **3 minors older**, never newer                                                         |
| kube-proxy                 | Same skew as kubelet. EKS recommends matching the node's kubelet minor                                       |
| `kubectl`                  | Within ±1 minor of the API server                                                                            |
| EKS standard support       | **14 months** from EKS release of a version                                                                  |
| EKS extended support       | A further **12 months**, at a higher per-cluster hourly fee ($0.60 vs $0.10 per hour at the time of writing) |

```bash
aws eks describe-cluster-versions --region "$REGION" \
  --query 'clusterVersions[].[clusterVersion,versionStatus,endOfStandardSupportDate,endOfExtendedSupportDate]' --output table
```

## Control plane

| Item                             | Value                                                                                                    |
| -------------------------------- | -------------------------------------------------------------------------------------------------------- |
| etcd database size               | Provisioned at **8 GiB**, the upstream maximum. Watch `apiserver_storage_size_bytes`                     |
| Control-plane version rollback   | One minor version back, within **7 days** of an in-place upgrade, gated by `ROLLBACK_READINESS` insights |
| Cluster insights refresh         | Every 24 hours, or on demand with `aws eks start-insights-refresh`                                       |
| Deprecated API usage in insights | Last 30 days of requests                                                                                 |

## EKS service quotas (defaults, adjustable)

| Quota                           | Default |
| ------------------------------- | ------- |
| Clusters per region             | 100     |
| Managed node groups per cluster | 30      |
| Nodes per managed node group    | 450     |
| Fargate profiles per cluster    | 10      |
| Selectors per Fargate profile   | 5       |

## Across the wiki

- [[Kubernetes/eks/networking/vpc-cni/eni-allocation|ENI and IP allocation]]
- [[Kubernetes/eks/networking/vpc-cni/prefix-delegation|Prefix delegation]]
- [[Kubernetes/eks/operator-runbook/reference/command-conventions|Command conventions]]
- [Amazon EKS service quotas](https://docs.aws.amazon.com/eks/latest/userguide/service-quotas.html)

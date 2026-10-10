---
title: Advanced EKS Networking
tags: [eks, networking, advanced, ipv6, vpc]
date: 2026-05-17
description: A decision guide to the hard networking problems on EKS — IP exhaustion, IPv6 clusters, fully private clusters, overlapping CIDRs, multi-cluster connectivity and egress control.
---

# Advanced EKS Networking

The [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]] gives every pod a real [[AWS/networking/vpc/README|VPC]] IP address. That one design choice makes pod networking simple and fast — no overlay, native security groups and flow logs — and it is also the root of most advanced networking problems on EKS, because pods consume VPC address space and VPC limits.

This page maps each problem to the feature that solves it. Start from the symptom.

## Problem 1: running out of IP addresses

Pods fail with `failed to assign an IP address to container`, or nodes join but schedule fewer pods than expected.

| Option                                                                                 | What it does                                                                          | Cost                                                      |
| :------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------ | :-------------------------------------------------------- |
| [[Kubernetes/eks/networking/vpc-cni/prefix-delegation\|Prefix delegation]]             | Assigns /28 prefixes to ENIs: far more pods per node, faster pod start                | Needs contiguous free /28 blocks; fragmented subnets fail |
| [[Kubernetes/eks/networking/vpc-cni/custom-networking\|Custom networking]]             | Puts pods in different subnets from nodes, typically a secondary `100.64.0.0/10` CIDR | One ENI per node is lost to the node itself; more config  |
| Tune warm pools ([[Kubernetes/eks/networking/vpc-cni/eni-allocation\|ENI allocation]]) | Stops nodes hoarding unused IPs with `WARM_IP_TARGET` / `MINIMUM_IP_TARGET`           | More EC2 API calls; slower bursts                         |
| IPv6 cluster                                                                           | Removes the constraint entirely                                                       | A new cluster; see below                                  |

The usual order: tune warm pools first (free), add a secondary CIDR with custom networking when the VPC itself is too small, and enable prefix delegation when pod density per node is the limit. They can be combined.

## Problem 2: IPv6

An IPv6 cluster gives each node a /80 prefix and every pod a globally unique IPv6 address. Address exhaustion disappears.

- The IP family is chosen at cluster creation and **cannot be changed**.
- Pods and Services are IPv6-only. Nodes are dual-stack.
- Pods can still reach IPv4 endpoints: the CNI assigns a host-local IPv4 address and NATs through the node. Inbound IPv4 arrives through a dual-stack load balancer.
- Check every dependency for IPv6 support before committing: service meshes, observability agents, on-premises firewalls and partner allow-lists are the usual blockers.

## Problem 3: no internet access at all

A fully private cluster has no NAT gateway and no internet gateway. Everything the nodes need must be reachable inside the VPC:

| Need                                  | VPC endpoint                                                              |
| :------------------------------------ | :------------------------------------------------------------------------ |
| Pull images                           | `ecr.api`, `ecr.dkr`, and the **S3 gateway** endpoint (layers live in S3) |
| Node bootstrap and credentials        | `ec2`, `sts`, `eks`, `eks-auth` (Pod Identity)                            |
| Logs and metrics                      | `logs`, `monitoring`                                                      |
| Load balancer controller, autoscaling | `elasticloadbalancing`, `autoscaling`                                     |
| Session Manager access to nodes       | `ssm`, `ssmmessages`, `ec2messages`                                       |

Images from public registries must be mirrored into ECR, for example with pull-through cache rules. Set the cluster API to private access and reach it through VPN, Direct Connect or a bastion — see [[Kubernetes/eks/security/access/endpoint-access|endpoint access]]. Each interface endpoint is billed per hour per zone, so this design trades NAT data charges for endpoint charges: [[AWS/cost-management/network-cost-optimization|network cost optimization]].

## Problem 4: overlapping CIDRs

Two clusters, or a cluster and an on-premises network, use the same address range and need to talk.

- **Keep pod ranges non-routable.** Put pods in `100.64.0.0/10` with custom networking and SNAT at the node. Only node subnets are advertised to the rest of the network.
- **Private NAT gateway** translates between overlapping ranges at the VPC boundary.
- **[[Kubernetes/eks/networking/vpc-lattice/README|VPC Lattice]]** or **PrivateLink** connects services without any IP routing between the networks, so overlap stops mattering.

Related background: [[AWS/networking/vpc/transit-gateway|Transit Gateway]], [[AWS/networking/vpc/vpc-peering|VPC peering]] and [[Architecture/solution-architecture-concepts/networking/nat|NAT]].

## Problem 5: connecting services across clusters

| Approach                                                                                                                      | Works at | Good for                                                      |
| :---------------------------------------------------------------------------------------------------------------------------- | :------- | :------------------------------------------------------------ |
| Flat routing (peering or Transit Gateway)                                                                                     | L3       | Few clusters, non-overlapping CIDRs, simple needs             |
| VPC Lattice with the Gateway API controller                                                                                   | L7       | Cross-account and cross-VPC service calls with IAM auth       |
| Service mesh multi-cluster ([[Kubernetes/guides/networking/istio\|Istio]], [[Kubernetes/guides/networking/linkerd\|Linkerd]]) | L7       | mTLS identity, traffic shifting and failover between clusters |
| Internal load balancer per service                                                                                            | L4       | Occasional, coarse-grained integration                        |

See [[AWS/concepts/app-mesh-vs-vpc-lattice|App Mesh vs VPC Lattice]] and [[Kubernetes/guides/tools/multi-cluster|multi-cluster tooling]].

## Problem 6: controlling egress

By default a pod can reach anything its node can.

1. **Inside the cluster**, restrict with egress [[Kubernetes/eks/networking/vpc-cni/network-policies|network policies]].
2. **Per workload at the VPC layer**, attach a dedicated security group with [[Kubernetes/eks/networking/vpc-cni/security-groups-for-pods|security groups for pods]].
3. **At the VPC edge**, route outbound traffic through AWS Network Firewall or a proxy for domain-based allow-lists and logging.
4. **Fixed source IP** for partner allow-lists: send the workload's traffic through a NAT gateway with an Elastic IP. With pods in dedicated subnets (custom networking), route only those subnets through it.

A related surprise: pods on nodes in public subnets have their traffic SNATed to the node's IP by default. Set `AWS_VPC_K8S_CNI_EXTERNALSNAT=true` when traffic already goes through a NAT gateway or must preserve the pod IP across peering.

## Problem 7: pods that need more than one interface

Telecom and some network-appliance workloads need extra interfaces on specific subnets. **Multus** is supported on EKS as a meta-CNI: the VPC CNI provides the primary interface, and Multus attaches additional ENIs with the `ipvlan` or `host-device` plugins. Reserve it for workloads that truly need it; it bypasses most of the tooling built around the single-interface model.

## Debugging at this level

When a problem spans pods, nodes and the VPC, work outward one layer at a time:

1. In the pod: resolve DNS, then connect — [[Kubernetes/guides/troubleshooting/dns-resolution|DNS troubleshooting]].
2. On the node: routes, rules and conntrack — [[Linux/networking/routing|Linux routing]], [[Linux/networking/ip-command|the `ip` command]], [[Linux/virtualization/network-namespace|network namespaces]].
3. In the VPC: security groups, [[AWS/networking/vpc/network-acls|network ACLs]], route tables, and VPC Flow Logs for `REJECT` records.
4. With VPC Reachability Analyzer for paths between ENIs.

The packet-level path is described in [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|Kubernetes networking deep dive]] and [[Kubernetes/eks/networking/vpc-cni/architecture|VPC CNI architecture]].

## Related

- [[Kubernetes/eks/networking/README|EKS networking overview]]
- [[Kubernetes/eks/networking/vpc-cni/configuration-reference|VPC CNI configuration reference]]
- [[Kubernetes/eks/advanced/README|Advanced EKS topics]]
- [EKS best practices: networking](https://docs.aws.amazon.com/eks/latest/best-practices/networking.html)

## Across the wiki

- [[Azure/compute/aks/fleet-manager-multicluster|Azure Kubernetes Fleet Manager — Multi-Cluster Governance, Staged Upgrades, and Multi-Cluster Services (MCS)]] — multi-cluster (Azure)
- [[GCP/compute/gke/fleets-and-anthos|GKE Fleets, Cloud Service Mesh (formerly ASM), and Policy Controller Governance]] — multi-cluster (GCP)
- [[GCP/compute/gke/multi-cluster-services|GKE Multi-Cluster Services (MCS) and Multi-Cluster Ingress (MCI) Architecture]] — multi-cluster (GCP)

---
title: EKS Networking
tags: [eks, networking, vpc-cni, load-balancing]
date: 2026-05-17
description: How networking works on EKS — pods with real VPC addresses, the VPC CNI and its modes, how traffic gets in and out, the security layers, IP planning, and an index of the detailed notes.
---

# EKS Networking

EKS networking rests on one design decision: **every pod gets a real IP address from your VPC**. There is no overlay. A pod is a first-class citizen of the [[AWS/networking/vpc/README|VPC]], reachable by anything that can route to its subnet, and visible in VPC Flow Logs.

That makes pod networking fast and simple to reason about. It also means pods consume VPC address space and are bounded by EC2 limits — which is the source of most EKS networking work.

The Kubernetes model this implements is in [[Kubernetes/concepts/L04-services-networking/00-README|L04 — Services & Networking]]; the Linux mechanics are in [[Containers/container-networking|container networking]].

## The moving parts

| Component                        | Role                                                            |
| :------------------------------- | :-------------------------------------------------------------- |
| **VPC CNI** (`aws-node`)         | Attaches ENIs to nodes and assigns their addresses to pods      |
| **kube-proxy**                   | Implements Service virtual IPs on each node                     |
| **CoreDNS**                      | Cluster DNS for Services and pods                               |
| **AWS Load Balancer Controller** | Creates ALBs and NLBs from Ingress, Gateway and Service objects |
| **Network policy agent**         | Enforces NetworkPolicy with eBPF, when enabled                  |
| **VPC resource controller**      | Manages trunk and branch ENIs for per-pod security groups       |

On [[Kubernetes/eks/compute/eks-auto-mode/README|Auto Mode]] these are built into the nodes and managed by AWS.

## Notes

### [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]]

The plugin itself: architecture, ENI and IP allocation, and its configuration.

- [[Kubernetes/eks/networking/vpc-cni/prefix-delegation|Prefix Delegation]] — assign /28 prefixes for far more pods per node and faster pod start-up.
- [[Kubernetes/eks/networking/vpc-cni/custom-networking|Custom Networking]] — put pods in different subnets from their nodes, typically a secondary CIDR, to escape IP exhaustion.
- [[Kubernetes/eks/networking/vpc-cni/security-groups-for-pods|Security Groups for Pods]] — give selected pods their own security groups for access to VPC resources.
- [[Kubernetes/eks/networking/vpc-cni/network-policies|Network Policies]] — pod-to-pod segmentation enforced natively.

### [[Kubernetes/eks/networking/vpc-lattice/README|VPC Lattice]]

Service-to-service connectivity across clusters, VPCs and accounts through the Gateway API, without IP routing between networks.

## How traffic flows

| Path                              | Mechanism                                                              |
| :-------------------------------- | :--------------------------------------------------------------------- |
| Pod to pod                        | Routed natively in the VPC; no encapsulation, no NAT                   |
| Pod to Service                    | `kube-proxy` rewrites the Service IP to a pod IP on the node           |
| Internet to pod                   | ALB or NLB with **IP targets** sends straight to pod addresses         |
| Pod to internet                   | Source-NAT to the node's address, then a NAT gateway (private subnets) |
| Pod to AWS services               | Through the NAT gateway, or privately through VPC endpoints            |
| Pod to another VPC or on-premises | Normal VPC routing: peering, Transit Gateway, VPN, Direct Connect      |

## Security layers

Traffic has to be allowed by every layer it crosses:

| Layer                                                                    | Scope                | Identifies peers by      |
| :----------------------------------------------------------------------- | :------------------- | :----------------------- |
| [[AWS/networking/vpc/network-acls\|Network ACLs]]                        | Subnet               | CIDR                     |
| [[AWS/networking/vpc/security-groups\|Security groups]] on nodes         | All pods on the node | Security group or CIDR   |
| Security groups for pods                                                 | Individual pods      | Security group or CIDR   |
| Network policies                                                         | Pod to pod           | Labels and namespaces    |
| A service mesh ([[Kubernetes/guides/networking/service-mesh\|overview]]) | Service to service   | Workload identity (mTLS) |

Use network policies for segmentation inside the cluster, and security groups for the boundary to AWS resources such as databases.

## IP address planning

Because pods use VPC addresses, plan for them up front:

- Size subnets for **pods and nodes combined**, with room to grow. A /24 is small for a production cluster.
- Each instance type has a maximum number of ENIs and addresses, which caps pods per node.
- Nodes keep a **warm pool** of unused addresses for fast pod start-up; on a tight subnet that pool can strand a large share of the space.
- When addresses run short, the options in order are: tune warm targets, enable prefix delegation, add a secondary CIDR with custom networking, or build an IPv6 cluster.

The decision guide for these, plus private clusters, overlapping CIDRs and egress control, is in [[Kubernetes/eks/advanced/advanced-networking|advanced EKS networking]].

## When something is wrong

Start with [[Kubernetes/eks/networking/vpc-cni/troubleshooting|VPC CNI troubleshooting]] for IP and ENI problems, [[Kubernetes/guides/troubleshooting/dns-resolution|DNS resolution]] for name lookups, and [[Kubernetes/guides/troubleshooting/service-unreachable|Service unreachable]] for connectivity. Alert on free addresses per subnet before pods start failing.

## Related

- [[Kubernetes/eks/README|EKS implementation track]]
- [[Kubernetes/concepts/L04-services-networking/06-cni|CNI (concepts)]] and [[Kubernetes/concepts/L04-services-networking/09-gateway-api|Gateway API]]
- [[AWS/networking/load-balancing/README|Elastic Load Balancing]]
- [[Azure/compute/aks/networking-cni|AKS networking]] and [[GCP/compute/gke/networking|GKE networking]] — the same problems on other clouds
- [EKS best practices: networking](https://docs.aws.amazon.com/eks/latest/best-practices/networking.html)

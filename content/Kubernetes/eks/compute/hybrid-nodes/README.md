---
title: EKS Hybrid Nodes
tags: [eks, compute, hybrid, on-premises, edge]
date: 2026-05-17
description: Running on-premises and edge machines as nodes of an EKS cluster — what Hybrid Nodes is, the networking it depends on, how nodes authenticate and join, what you operate yourself, limits and how it compares with EKS Anywhere and Outposts.
---

# EKS Hybrid Nodes

EKS Hybrid Nodes lets machines in your own data centre or at an edge site join an EKS cluster as worker nodes. The control plane stays in AWS, fully managed; the nodes are your hardware or virtual machines, running your operating system, wherever they are.

It gives one cluster API and one set of tooling across cloud and on-premises capacity, without you running a Kubernetes control plane on-premises.

## When it is the right tool

| Situation                                                     | Why Hybrid Nodes                                            |
| :------------------------------------------------------------ | :---------------------------------------------------------- |
| Data that must stay on-premises for residency or regulation   | Workloads run where the data is                             |
| Low latency to factory, hospital, retail or telecom equipment | Compute sits next to the equipment                          |
| Existing hardware, including GPUs, that is already paid for   | Use it from the same cluster as cloud capacity              |
| Gradual migration to AWS                                      | Move workloads between node types without changing clusters |
| Ending a self-managed on-premises Kubernetes                  | No more control plane, etcd or upgrades to operate          |

It is **not** for sites that must keep working when the link to AWS is down for long periods. The control plane is in the region; without it, running pods continue but nothing can be scheduled, scaled or healed.

## Architecture

```
AWS region                                            your site
┌──────────────────────────────┐   private link   ┌────────────────────────────────┐
│ EKS control plane (managed)  │◄────────────────►│ hybrid nodes (your OS, your HW) │
│ VPC with cluster ENIs        │  Direct Connect  │  kubelet, containerd, kube-proxy│
│ cloud nodes (optional)       │  or Site-to-Site │  CNI: Cilium or Calico          │
└──────────────────────────────┘       VPN        │  pods with on-premises IPs      │
                                                  └────────────────────────────────┘
```

Two address ranges must be declared when the cluster is created, as its **remote network configuration**:

- the **remote node network** — where the machines live;
- the **remote pod network** — the range the CNI assigns to pods on those machines.

Neither may overlap the VPC CIDR or the Kubernetes service CIDR.

## Networking requirements

This is where most of the effort goes.

| Requirement               | Detail                                                                                                                          |
| :------------------------ | :------------------------------------------------------------------------------------------------------------------------------ |
| Private connectivity      | [[AWS/networking/hybrid/README\|Direct Connect]] or [[AWS/networking/vpc/vpn\|Site-to-Site VPN]] between the site and the VPC   |
| Routes in both directions | The VPC must route the remote node and pod CIDRs to the gateway; the site must route the VPC CIDR back                          |
| Control plane to nodes    | The API server must reach the kubelet (10250) for logs, exec and metrics                                                        |
| Control plane to **pods** | Required for admission webhooks running on hybrid nodes — so the pod CIDR must be routable, or webhooks must run on cloud nodes |
| Firewalls                 | Allow the node-to-API (443) and API-to-node ports, plus the CNI's own ports between nodes                                       |
| Bandwidth and latency     | A stable link; AWS guidance is at least 100 Mbps and under 200 ms round trip                                                    |

Making pod addresses routable usually means advertising the pod CIDR from the nodes with BGP, which Cilium and Calico both support. The mechanics are in [[Linux/networking/routing|Linux routing]] and [[Kubernetes/eks/advanced/advanced-networking|advanced EKS networking]].

The Amazon [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]] does **not** run on hybrid nodes. Use **Cilium** or **Calico**; the AWS load balancer and EBS integrations likewise do not apply on-premises, so bring your own load balancing (for example Cilium's BGP or L2 announcement, or MetalLB) and storage (a CSI driver for your storage system).

## How nodes authenticate and join

A machine outside AWS has no instance profile, so it obtains temporary [[AWS/security/iam/README|IAM]] credentials another way:

| Method                     | How                                                                | Suits                              |
| :------------------------- | :----------------------------------------------------------------- | :--------------------------------- |
| **SSM hybrid activations** | Register the machine with Systems Manager using an activation code | Simplest to start with             |
| **IAM Roles Anywhere**     | The machine presents an X.509 certificate from your own CA         | Organisations with an existing PKI |

Then:

1. Create a **Hybrid Nodes IAM role** and an [[Kubernetes/eks/security/access/cluster-access-management|access entry]] of type `HYBRID_LINUX` for it.
2. Install the node components with the `nodeadm` CLI: `nodeadm install <version> --credential-provider ssm`.
3. Write a `NodeConfig` with the cluster name, region and credentials, and run `nodeadm init`.
4. Install the CNI; the node becomes `Ready`.

Nodes are labelled `eks.amazonaws.com/compute-type=hybrid`, which you use to steer workloads.

## What you operate

| AWS                                          | You                                                                              |
| :------------------------------------------- | :------------------------------------------------------------------------------- |
| Control plane, its availability and upgrades | Hardware, virtualisation, power, physical network                                |
| EKS add-ons that support hybrid nodes        | Operating system and its patching (AL2023, Ubuntu, RHEL, Bottlerocket on VMware) |
| `nodeadm` and the node artifacts             | Running `nodeadm upgrade` on each node; the CNI, ingress and storage             |
| Cluster API, access entries, Pod Identity    | Capacity planning — there is no autoscaling of physical machines                 |

Node upgrades are manual or scripted, typically with [[DevOps/infrastructure-as-code/ansible|Ansible]], and follow the usual [[Kubernetes/eks/cluster-upgrades/upgrade-process|version-skew rules]]. Hardening is yours: [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/21-node-hardening|node hardening]].

## Running mixed clusters

- Use node selectors or affinity on `eks.amazonaws.com/compute-type` and a zone-style topology label per site so workloads land in the right place.
- Keep **CoreDNS replicas on both sides** so that a link blip does not take down name resolution on-premises.
- Keep **admission webhooks on cloud nodes** unless on-premises pod IPs are routable from the control plane.
- Mind **data transfer**: chatty traffic between on-premises pods and cloud pods crosses the private link and is billed and latency-bound.
- Spread replicas so that losing the link, or losing the site, does not remove a whole service.

## Limits

| Limit                          | Detail                                                                                              |
| :----------------------------- | :-------------------------------------------------------------------------------------------------- |
| Disconnected operation         | Not designed for it; long disconnections lead to nodes marked `NotReady` and pods evicted elsewhere |
| VPC CNI, EBS, ALB integrations | Not available on hybrid nodes                                                                       |
| Autoscaling                    | No Karpenter or Cluster Autoscaler for physical capacity                                            |
| Pricing                        | Charged per vCPU-hour of hybrid nodes, on top of the cluster fee                                    |
| Architecture and OS            | x86 and Arm, on a supported OS list                                                                 |

## Alternatives

| Option                 | Control plane location   | Hardware                 | Works disconnected         | Choose when                                          |
| :--------------------- | :----------------------- | :----------------------- | :------------------------- | :--------------------------------------------------- |
| **EKS Hybrid Nodes**   | AWS region               | Yours                    | No                         | Reliable link; you want no on-premises control plane |
| **EKS Anywhere**       | On-premises, you operate | Yours                    | Yes                        | Air-gapped or unreliable connectivity                |
| **EKS on Outposts**    | Region or on the Outpost | AWS-supplied racks       | Partially (local clusters) | You want AWS hardware and APIs on-site               |
| **EKS on Local Zones** | AWS region               | AWS, in a metro location | No                         | Low latency to a city, with no hardware of your own  |

## Related

- [[Kubernetes/eks/compute/README|Compute options on EKS]]
- [[Kubernetes/concepts/L04-services-networking/06-cni|CNI plugins]]
- [[AWS/solutions-architect-professional/domain-1/1.1-network-connectivity|Hybrid network connectivity]]
- [[Kubernetes/guides/tools/multi-cluster|Multi-cluster tooling]]
- [EKS Hybrid Nodes overview](https://docs.aws.amazon.com/eks/latest/userguide/hybrid-nodes-overview.html)
- [EKS Workshop: Hybrid Nodes](https://www.eksworkshop.com/docs/networking/eks-hybrid-nodes/)

## Across the wiki

- [[GCP/networking/hybrid/README|GCP Cloud Interconnect & HA VPN]] — hybrid connectivity (GCP)

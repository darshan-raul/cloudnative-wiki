---
title: "Global network services"
description: "Choose IPAM, Cloud WAN, Network Manager or Global Accelerator by the boundary each manages."
tags:
  - cloud/aws/networking
date: 2026-10-12
---

# Global network services

These services address different layers. Start with [[AWS/networking/vpc/README|VPC]] and [[AWS/networking/vpc/transit-gateway|TGW]].

## Choose the problem

| Service            | Boundary                                                        | Not a substitute for                        |
| ------------------ | --------------------------------------------------------------- | ------------------------------------------- |
| VPC IPAM           | Address allocation, visibility and overlap management           | Routing or application authorization        |
| Cloud WAN          | Policy-driven global network connectivity/segmentation          | Every per-VPC SG or workload configuration  |
| Network Manager    | Network topology/operational visibility for supported resources | A packet inspection firewall                |
| Global Accelerator | Supported endpoint traffic over AWS global network entry points | CloudFront content caching or DNS ownership |

Design address pools for growth, environment isolation and hybrid overlap. Segments and routing attachments need explicit policy; simply adding a network service does not enforce every workload boundary.

Global Accelerator endpoint health/traffic dials affect traffic routing. It does not cache your objects and does not turn an unavailable backend into a healthy one. Confirm supported endpoint types/address-family configuration and pricing before deployment.

## Design exercise

A company has two Regions, twenty VPCs and an acquired network overlapping 10.0.0.0/16. Specify address-allocation ownership, whether networks must communicate, segmentation requirements and global application latency targets.

Choose which service addresses each requirement, and explain why a CDN or DNS record cannot solve IP overlap. Define attachment/policy rollback and a test that proves forbidden segments cannot reach each other.

Read-only drill: inspect existing sandbox CIDRs and routing attachments, map them into an IPAM plan, and compare it with an approved allocation policy. Do not create global paid attachments just to draw a topology.

## References

- [IPAM](https://docs.aws.amazon.com/vpc/latest/ipam/what-it-is-ipam.html).
- [Cloud WAN](https://docs.aws.amazon.com/network-manager/latest/cloudwan/what-is-cloudwan.html).
- [Network Manager](https://docs.aws.amazon.com/network-manager/latest/tgwnm/what-is-network-manager.html).
- [Global Accelerator](https://docs.aws.amazon.com/global-accelerator/latest/dg/what-is-global-accelerator.html).

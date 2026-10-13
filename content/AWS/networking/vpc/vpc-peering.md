---
title: "VPC peering"
description: "Configure bidirectional private routes, understand non-transitivity/DNS limits and compare transfer-aware costs."
tags:
  - cloud/aws/networking
date: 2026-10-12
---

# VPC peering

Peering connects two compatible VPCs through private routing. It can span supported accounts/Regions, but overlapping CIDRs and non-transitive routing constrain the design. Start with [[AWS/networking/vpc/README|VPC routes]].

## What peering does not do

A→B and B→C connections do not let A reach C through B. Peering does not grant application permission, share every DNS namespace or make B's NAT/IGW a universal egress path for A.

Acceptance and bidirectional routes are separate steps. Add the destination CIDR in each relevant subnet route table and review SG/NACL rules. Supported same-Region SG references have conditions; inter-Region behavior differs.

Peering DNS resolution options affect supported public hostnames resolving to private addresses; they do not automatically associate all private hosted zones or forward arbitrary on-premises names. Use [[AWS/networking/private-access-and-hybrid-dns|Resolver/zone design]] when that is the requirement.

## Two-VPC sandbox exercise

Prerequisites: two non-overlapping sandbox VPCs, one private test client/server and management access that does not depend on the new peering path.

1. Request/accept a dedicated connection and record its ID.
2. Add each remote CIDR to the relevant route table with the peering ID.
3. Permit only the intended application port/client source.
4. Test the remote private IP, then the intended DNS name; diagnose routing and naming separately.
5. Remove one return route in the sandbox and observe failure; restore it and prove recovery.
6. Delete dedicated routes before removing the connection. Restore groups and remove disposable client/server resources.

Expected evidence: both effective route tables, accepted connection, allowed/denied flow test and documented DNS behavior.

## Cost and scale

There is no peering attachment-hour fee, but **same-Region is not universally free transfer**: AZ placement and direction matter. Inter-Region transfer has its own tariff. Compare the actual path/GB with [[AWS/networking/vpc/transit-gateway|TGW]] processing/attachment dimensions.

A mesh grows connections and route-management effort quickly; “three VPCs use peering, ten use TGW” is a heuristic, not a hard threshold. Inspect current active/pending connection and route quotas before scaling.

## Peering versus hub routing

| Requirement                          | Peering                                    | Transit Gateway                                        |
| ------------------------------------ | ------------------------------------------ | ------------------------------------------------------ |
| Direct private path between two VPCs | Good starting point                        | Works with additional hub controls/cost                |
| A→B→C transit                        | Unsupported through peering                | Supported when route tables/attachments permit         |
| Many accounts and route domains      | Pairwise connection/route management grows | Central tables and sharing, with additional operations |
| Billing                              | No attachment-hour; transfer still applies | Attachment-hours and eligible processing/transfer      |

```text
VPC A subnet → route(B CIDR, pcx) → peering → VPC B subnet
VPC B subnet → route(A CIDR, pcx) → peering → VPC A subnet
```

The connection must be active and both sides need routes. Use non-overlapping ranges, then test a private IP before debugging DNS. A Route 53 private hosted zone needs its own association/Resolver design; the peering DNS option is narrower. For an access denial, inspect source SG or CIDR support, target SG, both NACL directions and guest firewall rather than adding a third peering connection.

## References

- [Peering guide](https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html).
- [Unsupported peering configurations](https://docs.aws.amazon.com/vpc/latest/peering/invalid-peering-configurations.html).
- [Peering DNS](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-dns.html).
- [VPC pricing](https://aws.amazon.com/vpc/pricing/).

## Across the wiki

- [[Azure/networking/private-link/README|Azure Private Link, Private Endpoints, and Private DNS Architecture]] — private connectivity (Azure)
- [[GCP/networking/private-service-connect/README|GCP Private Service Connect (PSC)]] — private connectivity (GCP)
- [[Kubernetes/eks/networking/vpc-lattice/README|Amazon VPC Lattice]] — private connectivity (Kubernetes)
- [[Azure/networking/virtual-wan/README|Azure Virtual WAN (vWAN) Architecture & Global Transit Routing]] — private connectivity (Azure)

---
title: AWS Transit Gateway
description: Design association, propagation, return paths and cross-account sharing for a regional routing hub.
tags:
  - cloud/aws/networking
date: 2026-10-12
---

# AWS Transit Gateway

TGW is a regional routing hub for supported VPC, VPN, Direct Connect/Connect and peering paths. It reduces mesh administration but does not automatically make every attachment mutually reachable.

## Association versus propagation

An attachment's associated TGW route table determines its ingress route lookup. Propagation adds supported learned routes to selected tables. These are separate operations; association alone does not enable propagation.

Routing uses longest-prefix matching with documented route priorities. Static aggregate routes are supported where appropriate; “TGW cannot summarize routes” is false. Overlapping attached VPC CIDRs have restrictions and must not be used as an illustration of guaranteed propagation.

Configure VPC subnet routes to TGW and the destination return path. A VPC attachment enables selected AZs through attachment subnets; traffic originating in an AZ without an enabled attachment subnet has documented reachability constraints. Sharing a route table does not override missing routes or SG/NACL restrictions.

## Hybrid and sharing

TGW VPN supports static or dynamic BGP routing. Device capabilities and failover requirements determine the choice; lack of BGP does not force a VPN per VPC.

Share supported TGW resources with RAM. With Organizations sharing enabled, eligible organization recipients can access shares without invitations; external sharing has different invitation/acceptance behavior. Resource sharing, attachment acceptance, association and route propagation are independent controls.

TGW is regional; inter-Region TGW peering is a separate attachment design. Do not attach a remote Region's VPC as though the hub were global.

## Segmentation exercise

Prerequisites: a disposable TGW/test attachments, non-overlapping VPCs, management access and an attachment/data budget.

1. Create two TGW route tables for approved isolation boundaries.
2. Associate each source attachment deliberately and propagate only the intended destination routes.
3. Add VPC-side and return routes, then allow the specific test traffic.
4. Verify permitted source→destination access and denied cross-segment access.
5. Remove one sandbox propagation/return route and explain the failure from effective route tables.
6. Restore configuration, then remove lab routes/associations/attachments before deleting the dedicated hub. Preserve shared attachments.

Use actual returned identifiers and check both source AZs; one successful test does not prove all zonal paths work.

## Capacity and cost

The documented attachment quota is 5,000, and the 10,000-route quota is combined across TGW route tables—not ten thousand per table. Check current scope/adjustability and your account allocation before deployment.

For a hypothetical us-east-1 study dated 2026-10-12, assume VPC-attachment inputs of \$0.05/hour and \$0.02 per eligible processed GB. Ten attachments over 730 hours plus 500 GB cost 10 × 730 × \$0.05 + 500 × \$0.02 = \$375. Add applicable transfer, VPN, DX and inspection charges; attachment types are not interchangeable tariff units.

## Route-table example

```text
VPC A attachment ─ associate → TGW table A
                  └ propagate → TGW table B (if allowed)
VPC B attachment ─ associate → TGW table B
                  └ propagate → TGW table A (if allowed)

VPC A subnet route: B CIDR → TGW
TGW table A:       B CIDR → B attachment
VPC B return route:A CIDR → TGW
TGW table B:       A CIDR → A attachment
```

This two-VPC path requires four route decisions and workload security controls. Route-table association chooses the table used by traffic _entering_ TGW from an attachment; propagation makes routes available in selected tables. To isolate production from test, maintain separate associated tables and deliberately omit the prohibited attachment routes. Test both directions from the AZs containing attachment subnets; a green TGW attachment state does not prove the VPC-side path.

Peering can be simpler for a few stable pairwise links, whereas TGW centralizes a changing multi-VPC/hybrid topology and adds attachment/processing costs. Neither is the right substitute for a private service API when consumers should not receive broad IP-level routes; compare [[AWS/concepts/vpc-lattice|VPC Lattice]] or [[AWS/networking/private-access-and-hybrid-dns|PrivateLink]] where applicable.

## References

- [TGW operation, AZs and route selection](https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html).
- [VPN attachments](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-vpn-attachments.html).
- [Quotas](https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-quotas.html).
- [RAM invitations and organization sharing](https://docs.aws.amazon.com/ram/latest/userguide/working-with-shared-invitations.html).
- [Pricing](https://aws.amazon.com/transit-gateway/pricing/).
- Compare [[AWS/networking/vpc/vpc-peering|peering]] and [[AWS/networking/private-access-and-hybrid-dns|private service access]].

## Across the wiki

- [[Azure/networking/private-link/README|Azure Private Link, Private Endpoints, and Private DNS Architecture]] — private connectivity (Azure)
- [[GCP/networking/private-service-connect/README|GCP Private Service Connect (PSC)]] — private connectivity (GCP)
- [[Kubernetes/eks/networking/vpc-lattice/README|Amazon VPC Lattice]] — private connectivity (Kubernetes)
- [[Azure/networking/virtual-wan/README|Azure Virtual WAN (vWAN) Architecture & Global Transit Routing]] — private connectivity (Azure)

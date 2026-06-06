---
title: VPC Peering
description: VPC Peering — private IP connectivity between two VPCs. Peering configuration, route tables, security group rules, and limitations compared to Transit Gateway.
tags:
  - aws
  - networking
  - vpc-peering
---

# VPC Peering

VPC Peering creates a private connection between two VPCs so instances in either VPC can communicate using private IP addresses. No gateways, no NAT, no Transit Gateway needed.

## How It Works

```
VPC-A (10.0.0.0/16) ←→ VPC Peering ←→ VPC-B (10.1.0.0/16)
```
Traffic flows directly between VPCs over the AWS backbone, not the public internet. Latency is lower than internet-based communication.

## Key Constraints

- **No transitive peering:** VPC-A can talk to VPC-B, and VPC-B can talk to VPC-C. But VPC-A cannot talk to VPC-C through VPC-B. Each pair needs a direct peering connection.
- **No overlapping CIDRs:** The CIDR blocks of the two VPCs must not overlap. This is the most common reason peering requests fail.
- **Region-bound by default:** Peering connections are between VPCs in the same region. Cross-region peering is supported but adds latency and cost.
- **Account-bound by default:** Peering between VPCs in different AWS accounts requires acceptance from both accounts.

## Setup Steps

1. **Requester creates peering connection** — From VPC-A, create a peering connection request to VPC-B
2. **Accepter accepts** — VPC-B (or the other account) accepts the request
3. **Update route tables** — Add a route in VPC-A's route table pointing to the peering connection for VPC-B's CIDR, and vice versa
4. **Update security groups** — Security groups in VPC-A need rules allowing traffic from VPC-B's CIDR (or the peering SG)

## Route Table Configuration

```
VPC-A Route Table:
Destination: 10.0.0.0/16    → Target: local
Destination: 10.1.0.0/16    → Target: pcx-xxxxx (peering connection)

VPC-B Route Table:
Destination: 10.1.0.0/16    → Target: local
Destination: 10.0.0.0/16    → Target: pcx-xxxxx (peering connection)
```

## DNS Resolution Between VPCs

If you want instances in VPC-B to resolve DNS names in VPC-A, enable **DNS resolution for the peering connection** in the peering connection settings. By default, DNS resolution is disabled for new peering connections.

## Use Cases

- **Two-tier architecture:** VPC-A for application, VPC-B for database — direct private communication without Transit Gateway
- **Shared services VPC:** A central services VPC (logging, monitoring) peered with all application VPCs
- **Migration:** Peering a new VPC with an old VPC during migration to allow direct communication without re-IPing

## Limits

| Resource | Limit |
|----------|-------|
| Active peering connections per VPC | 50 (can request increase) |
| Pending peering connections per VPC | 50 |
| VPCs per region (default) | 5 |

## Comparison: Peering vs Transit Gateway

| | VPC Peering | Transit Gateway |
|--|--|--|
| Transitive routing | No | Yes |
| Scales to100s of VPCs | No (mesh complexity) | Yes (hub-and-spoke) |
| Cross-account | Yes | Yes (with AWS Organizations) |
| Route management | Per-VPC route tables | Centralized route tables |
| Cost | Free (same region) | Per-hour + per-GB data transfer |
| Use when | 2-3 VPCs, simple topology | 10+ VPCs, hub-and-spoke |

## References

- **Homepage:** https://aws.amazon.com/vpc/
- **Documentation:** https://docs.aws.amazon.com/vpc/latest/peering/
- **Pricing:** https://aws.amazon.com/vpc/pricing/ (same-region peering is free)

## Pricing Examples

**Scenario 1:** Same-region VPC Peering between two VPCs (10.0.0.0/16 and 10.1.0.0/16) — free. Traffic between them traverses the AWS backbone at no cost. A1GB/month data transfer between VPCs costs $0.

**Scenario 2:** Cross-region VPC Peering between us-east-1 and eu-west-1. Data transfer: $0.02/GB from us-east-1 to eu-west-1. If you transfer 500GB/month, that's $10/month. Compare to Transit Gateway cross-region: $0.02/GB + $0.007/Transit Gateway hour. For this volume, Transit Gateway adds ~$0.50/hr ×720hr = $360/month minimum, making peering36x cheaper for this use case.

## Nuggets & Gotchas

- **Peering connections don't inherit from the default security group:** When you peer two VPCs, instances in VPC-A can only reach instances in VPC-B if the security group in VPC-B explicitly allows traffic from VPC-A's CIDR. This catches many people off guard.
- ==**VPC CIDR overlap is a hard constraint==:** If your VPCs use 10.0.0.0/8 and 10.0.0.0/16, they overlap and peering fails. This is common in organizations that used the same CIDR in multiple environments. Use non-overlapping RFC 1918 ranges.
- **Peering doesn't support IPv6 by default:** IPv6 traffic requires the VPC to have an IPv6 CIDR block and the peering connection to be configured for IPv6. Not all use cases need this, but it's a gotcha for IPv6 workloads.
- **Security groups referencing peer VPC SGs require the SG to exist in both accounts:** If Account A has sg-123 and it references sg-456 in Account B's VPC, sg-456 must exist and be assigned to instances in Account B's VPC. This cross-account SG reference is valid only when the peering connection is active.
- **DNS resolution for peering must be explicitly enabled:** By default, instances in VPC-B cannot resolve DNS names in VPC-A (or vice versa). ==You must enable "DNS resolution" on the peering connection.== This is a common cause of mysterious "can't resolve hostname" issues after setting up peering.

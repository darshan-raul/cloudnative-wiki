---
title: Transit Gateway
description: AWS Transit Gateway — hub-and-spoke router for multi-VPC and hybrid connectivity. Centralized routing, cross-account sharing, and site-to-site VPN integration.
tags:
  - aws
  - networking
  - transit-gateway
---

# AWS Transit Gateway

A Transit Gateway (TGW) is a regional hub that connects VPCs and on-premises networks in a hub-and-spoke topology. Instead of managing peering connections between every pair of VPCs (mesh), all VPCs connect to the TGW, and the TGW routes traffic between them.

## Why Transit Gateway instead of VPC Peering

```
VPC Peering (mesh): 10 VPCs → 45 peering connections (n(n-1)/2)
Transit Gateway: 10 VPCs → 10 attachments to one TGW
```

As VPC count grows, peering becomes unmanageable. TGW provides transitive routing without individual peering connections.

## Core Concepts

### Attachments

A TGW connects to:
- **VPC** — One attachment per VPC (you attach a VPC, not individual subnets — the TGW can route to any subnet with a route table entry)
- **Site-to-Site VPN** — Your on-premises network via IPsec VPN
- **Direct Connect** — Your on-premises via AWS Direct Connect
- **Transit Gateway Connect** — GRE tunnels for BGP routing (for SD-WAN appliances)

### Route Tables

Each TGW has one or more route tables. Route tables control which attachments can reach which other attachments:

```
TGW Route Table (default):
─────────────────────────────
Destination → Target
10.0.0.0/16       → Attachment: VPC-A
10.1.0.0/16       → Attachment: VPC-B
10.2.0.0/16       → Attachment: VPC-C
172.16.0.0/12     → Attachment: VPN (on-prem)
```

**Propagation:** Routes from VPC attachments are automatically propagated to the TGW route table if associated with the VPC. VPN routes propagate via BGP.

### Associations

Each attachment is associated with exactly one TGW route table. An attachment can only use routes in its associated route table.

### Cross-Account Sharing (AWS Organizations)

Transit Gateway can be shared with other AWS accounts via AWS Resource Access Manager (RAM). The owner account creates the TGW, shares it with the Organization, and member accounts can attach their VPCs.

## Architecture: Multi-Account with TGW

```
Account: Network (Owner)
└── Transit Gateway (tgw-xxxxx)
    ├── Route Table: Prod
    │   ├── VPC-Prod (Account B) ← attachment
    │   └── VPN (on-prem)
    └── Route Table: Dev
        ├── VPC-Dev (Account C) ← attachment
        └── (no VPN for dev)

Account B (Prod):
└── VPC-Prod (10.0.0.0/16)
    └── Route Table: TGW route → tgw-xxxxx (for 10.1.0.0/16, 172.16.0.0/12)
```

## Site-to-Site VPN via Transit Gateway

When you attach a VPN to a TGW, you create a Transit Gateway VPN attachment. The on-premises router establishes BGP with the TGW, and routes propagate automatically.

Benefits over direct VPN to VPC:
- One VPN connection from on-prem connects to all VPCs attached to the TGW
- Centralized egress for all VPC traffic (for inspection)
- VPN failover without changing on-prem router config

## Shared VPC with Transit Gateway

```
Central Network Account
└── Transit Gateway
    ├── VPC-Prod (shared)
    ├── VPC-Dev (shared)
    └── On-prem (VPN)

All attachments use the same TGW route table
→ All VPCs can reach each other and on-prem
→ Network team manages TGW, app teams manage their VPCs
```

## Limits

| Resource | Limit |
|----------|-------|
| Transit Gateways per region | 5 |
| Attachments per Transit Gateway | 50 |
| VPCs per Transit Gateway | 50 |
| Routes per Transit Gateway route table | 10,000 |
| Cross-region attachments | Not supported (TGW is regional) |

## Cost

Transit Gateway is charged per hour per attachment + per GB of data processed:

- $0.02/Transit Gateway attachment-hour
- $0.007/GB data transfer

At scale: 10 VPCs, 500GB/month cross-VPC traffic = $0.20/hr × 720hr + $3.50 = ~$147/month.

## References

- **Homepage:** https://aws.amazon.com/transit-gateway/
- **Documentation:** https://docs.aws.amazon.com/vpc/latest/tgw/
- **Pricing:** https://aws.amazon.com/transit-gateway/pricing/

## Pricing Examples

**Scenario 1:** A multi-account setup with 5 VPCs (production, staging, dev, shared-services, logging) connected via Transit Gateway.5 attachments × $0.02/hr × 720hr = $72/month. Cross-account data transfer: 200GB/month × $0.007 = $1.40/month. Total: ~$73/month. Compare to individual VPC peering connections (same-region, free) but 10 peering connections for 5 VPCs is a mesh — hard to manage.

**Scenario 2:** A hybrid cloud setup:3 VPCs (prod, dev, shared-services) + on-premises via Direct Connect + VPN backup. Transit Gateway with 4 attachments (3 VPCs + 1 VPN). Monthly: 4 × $0.02 × 720hr = $57.60 +1TB cross-VPC/data transfer (300GB between VPCs + 700GB from on-prem) =1TB × $0.007 = $7. Total: ~$65/month. Without TGW, you'd need 3 separate VPN connections to each VPC.

## Nuggets & Gotchas

- **Transit Gateway is regional — cross-region requires inter-region TGW peering:** You can't attach a VPC in us-east-1 to a TGW in eu-west-1. For multi-region architectures, you need inter-region TGW peering (which has its own latency and cost implications).
- **TGW route tables don't support summarization:** If VPC-A uses 10.0.0.0/8 and VPC-B uses 10.1.0.0/16, you can't add one route 10.0.0.0/8 → VPC-A and expect VPC-B's 10.1.0.0/16 to be reachable from on-prem via VPN. TGW doesn't summarize routes — you need explicit routes for each VPC CIDR.
- **VPN attachment to TGW uses BGP for route propagation:** Unlike VPC attachments (static routes), VPN attachments learn routes via BGP. If your on-premises router doesn't support BGP, you can't use TGW VPN attachment — you'd need direct VPN to each VPC.
- **TGW attachments inherit routing behavior based on their associated route table:** A VPC attachment can only send traffic to destinations listed in its associated TGW route table. If the route table doesn't have a route to on-prem, the VPC can't reach on-prem even if the VPN attachment can.
- **Shared TGW from AWS Organizations requires RAM:** If you share a TGW with member accounts via AWS Organizations, those accounts need RAM invitations accepted. If RAM sharing is disabled in the Organization, cross-account TGW sharing doesn't work.

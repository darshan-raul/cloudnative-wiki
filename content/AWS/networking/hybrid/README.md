---
title: AWS Hybrid Connectivity
description: AWS hybrid networking — Direct Connect for dedicated private connections (1Gbps/100Gbps), Site-to-Site VPN for encrypted IPsec tunnels over internet, and when to use each.
tags:
  - aws
  - networking
  - direct-connect
  - vpn
  - hybrid
---

# AWS Hybrid Connectivity

AWS provides two primary methods for connecting on-premises infrastructure to AWS VPCs: Direct Connect (dedicated private connection) and Site-to-Site VPN (encrypted tunnel over internet).

## Direct Connect vs VPN

| | Direct Connect | Site-to-Site VPN |
|--|--|--|
| Connection type | Dedicated physical fiber | Encrypted IPsec tunnel over internet |
| Bandwidth | 1Gbps, 10Gbps, 100Gbps | Limited by internet bandwidth |
| Latency | Low, consistent | Variable (internet-dependent) |
| Reliability | 99.9% SLA | Best-effort (depends on ISP) |
| Cost | $0.03/GB (data transfer) + port hours | $0.05/hr per VPN tunnel |
| Setup time | Weeks (physical setup) | Minutes (IPsec is software) |
| Use when | High-throughput, low-latency, consistent workloads | Quick setup, low-volume, DR |
| BGP required | Yes | Yes |

## AWS Direct Connect

Direct Connect provides a dedicated, private fiber connection from your on-premises network to an AWS Direct Connect location.

### How It Works

```
On-premises Router → Direct Connect Location (Customer Cage)
                           ↓
                    AWS Direct Connect Router
                           ↓
                    AWS Region (via private VIF)
                           ↓
                    VPC (private subnet)
```

### Components

**Dedicated Connection:** A physical 1Gbps or 10Gbps fiber port in an AWS Direct Connect location. You provision this port with an AWS partner (for 1Gbps) or AWS directly (for 10Gbps+).

**Virtual Interface (VIF):** A virtual interface on top of the dedicated connection. Three types:
- **Private VIF:** Routes to VPC private IP addresses (for connecting to EC2, RDS, etc.)
- **Public VIF:** Routes to AWS public services (S3, DynamoDB, CloudWatch) over AWS backbone
- **Transit VIF:** Connects to Transit Gateway

**Direct Connect Gateway:** Regional aggregation point for connecting to VPCs in different regions. Enables multi-VPC and multi-region access from a single Direct Connect connection.

### Connection Process

1. **Order a connection** via AWS Console or API — creates a dedicated port in a DX location
2. **Create a virtual interface** (private for VPC access)
3. **Configure BGP** on your router — exchange routes with AWS
4. **Update VPC route tables** — add the on-premises CIDR as a target via the Virtual Gateway or Transit Gateway

### Direct Connect Gateway (Multi-Region)

```
Direct Connect Gateway (regional)
  ├── Private VIF → VPC-A (us-east-1)
  ├── Private VIF → VPC-B (eu-west-1) ← cross-region
  └── Transit VIF → Transit Gateway (us-east-1)
```

Without a DX Gateway, each private VIF can only reach VPCs in the same region.

### AWS Direct Connect Partners

AWS doesn't run fiber to every customer building. You use an AWS Direct Connect Partner who has cage space in DX locations and can provision cross-connects:

- **Equinix, Digital Realty, CyrusOne** — major DX partners with cage space in most DX locations
- **Lumen (formerly CenturyLink), AT&T** — direct DX partners for enterprise

### Direct Connect + VPN (Private VIF + VPN Backup)

Direct Connect has no SLA for availability (it's physical infrastructure). A common pattern is running Direct Connect for primary traffic and an IPsec VPN as a failover:

```
Primary: On-prem → Direct Connect → VPC (low latency, high throughput)
Failover: On-prem → Internet VPN → VPC (higher latency, lower throughput)
  BGP routes: Primary path has lower MED/AS-Path preference
```

### Site-to-Site VPN

Site-to-Site VPN creates an encrypted IPsec tunnel from your on-premises router to your VPC.

```
On-premises Router
  ↓ (IPsec tunnel)
Customer Gateway (CGW) ← AWS-managed
  ↓
Virtual Private Gateway (VGW) ← attached to VPC
  ↓
VPC route table (add on-prem CIDR)
```

### VPN Components

**Customer Gateway:** Your on-premises router (or software VPN endpoint). You provide its public IP and BGP ASN.

**Virtual Private Gateway:** AWS side of the VPN. Attached to the VPC and provides the second endpoint of the IPsec tunnel.

**Site-to-Site VPN Connection:** The VPN connection itself.

### VPN as Transit Gateway Attachment

You can attach a VPN to a Transit Gateway instead of a Virtual Private Gateway. This enables:
- One VPN connection to reach all VPCs attached to the Transit Gateway
- Centralized routing through the Transit Gateway
- BGP peering with the Transit Gateway

### BGP Configuration

Both Direct Connect and VPN require BGP for route exchange. BGP ASN (Autonomous System Number) is required:
- AWS default ASN: `64512`
- Your ASN: Any private ASN (64512-65534) or your public ASN

```
On-prem router: ASN 65001
AWS: ASN 64512
BGP session: Establishes peer, exchanges routes
```

### Transit Gateway VPN Attachment vs VGW

| | VGW (Virtual Private Gateway) | TGW VPN Attachment |
|--|--|--|
| VPCs per connection | 1 VPC | All VPCs attached to TGW |
| Routing | Static routes or BGP | BGP only |
| Cross-region | No | No (TGW is regional) |
| HA | Two tunnels per VPN | Two tunnels per VPN |
| Use when | Single VPC, simple | Multi-VPC, hub-and-spoke |

## Architecture: Hybrid with Direct Connect + TGW

```
On-premises Data Center
  ↓ Direct Connect (1Gbps)
Direct Connect Location
  ↓ Private VIF
Direct Connect Gateway (us-east-1)
  ├── Transit VIF → Transit Gateway (us-east-1)
  │                   ├── VPC-Prod (10.0.0.0/16)
  │                   ├── VPC-Dev (10.1.0.0/16)
  │                   └── VPC-Shared (10.2.0.0/16)
  │
  └── (Cross-region via DX Gateway): VPC in eu-west-1

VPN (failover):
  On-prem → Internet VPN → Transit Gateway (backup)
```

## Limits

| Resource | Limit |
|----------|-------|
| Direct Connect connections per region | 10 |
| Virtual interfaces per connection | 50 |
| BGP prefixes per connection | 100 (default, can request up to 1,000) |
| VPN connections per VGW | 10 |
| VPN connections per TGW | 30 (can request increase) |

## Cost Comparison

| Scenario | Direct Connect | VPN |
|----------|---------------|-----|
| 100GB/month | $0.03 × 100 = $3/month + port | $0.05 × 720hr = $36/month |
| 1TB/month | $0.03 × 1024 = $30/month + port | $0.05 × 720hr = $36/month |
| 10TB/month | $0.02 × 10240 = $200/month + port | $0.05 × 720hr = $36/month |

Direct Connect becomes cheaper than VPN at higher data transfer volumes. VPN has a flat hourly cost regardless of usage.

## References

- **Homepage:** https://aws.amazon.com/directconnect/
- **Documentation:** https://docs.aws.amazon.com/directconnect/
- **Pricing:** https://aws.amazon.com/directconnect/pricing/

## Pricing Examples

**Scenario 1:** A development team with an on-premises office (50 users) needing to access AWS dev VPC. VPN: $0.05/hr × 720hr = $36/month. Data transfer: 5GB/month × $0.05/GB = $0.25/month. Total: ~$36/month for occasional access. VPN is appropriate for this use case.

**Scenario 2:** A production data center moving 10TB/month to AWS via Direct Connect. Dedicated connection (1Gbps, 1000BASE-LX optics): $0.30/hr × 720hr = $216/month for the port. Data transfer: 10TB × $0.02/GB (10TB+ tier) = $200/month. Total: ~$416/month. Equivalent VPN: $0.05/hr × 720hr = $36/month. Direct Connect is 11x more expensive but offers 20x the bandwidth and consistent <1ms latency.

## Nuggets & Gotchas

- **Direct Connect doesn't provide built-in redundancy:** A single Direct Connect connection is a single point of failure. For production, provision connections from different DX locations (if available) or use a second DX connection + VPN as failover.
- **VPN tunnels on VGW are AWS-managed and can flap:** The VGW is stateless during failover. For production HA, use two VPN tunnels (automatically created) and configure your router to use both. For Transit Gateway VPN attachments, always use two tunnels for HA.
- **Direct Connect MACSec encryption is per-hop:** Direct Connect offers MACsec (Layer 2 encryption) at the physical layer, but once traffic leaves the DX location, it's on the AWS backbone (which is encrypted at Layer 3). You still need TLS/HTTPS for end-to-end encryption of application data.
- **BGP prefix limits apply:** By default, Direct Connect and VPN allow 100 BGP prefixes. If you're running full BGP table routing (140K+ prefixes from the internet), you need to request an increase or use route summarization on your router.
- **VPN connections via VGW cannot use BGP route propagation to VPC route tables:** When using a VGW, VPN routes are propagated to VPC route tables via BGP. But you cannot control the routing policy (e.g., prefer DX over VPN) using BGP attributes. Use Transit Gateway for advanced routing policies.

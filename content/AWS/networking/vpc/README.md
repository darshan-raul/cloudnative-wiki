---
title: Amazon VPC
description: Amazon VPC — isolated virtual network with subnets, route tables, internet gateways, NAT gateways, VPC endpoints, and VPC Flow Logs
tags:
  - aws
  - networking
  - vpc
---

# Amazon VPC

A VPC is an isolated virtual network in AWS. You define the IP address range (CIDR block), subdivide it into subnets, and control how traffic flows between subnets, the internet, and your on-premises network.

## Core Concepts

### CIDR Blocks

Every VPC has one or more IPv4 CIDR blocks. AWS reserves5 IPs per subnet:
- Network address (first IP)
- VPC router (second IP — used for the subnet's default gateway)
- DNS (third IP)
- Future use (fourth IP)
- Broadcast (last IP — not used in AWS but reserved)

| CIDR Size | Usable IPs per Subnet |
|-----------|----------------------|
| /28 | 11 |
| /27 | 27 |
| /26 | 59 |
| /25 | 123 |
| /24 | 251 |

A /24 subnet in us-east-1 gives you 251 usable instances — enough for most application tiers.

### Subnet Types

```
Public Subnet — Has a route to the Internet Gateway via the main route table
Private Subnet   — No direct route to IGW. Outbound via NAT Gateway or egress-only IGW
VPN-only Subnet  — Route to Virtual Private Gateway (site-to-site VPN)
```

### Route Tables

Each subnet has exactly one route table. Routes determine where traffic is directed:

```
Destination: 10.0.0.0/16        → Target: local (all subnets in VPC)
Destination: 0.0.0.0/0          → Target: igw-xxxx           (public subnet)
Destination: 0.0.0.0/0          → Target: nat-xxxx           (private subnet via NAT GW)
Destination: 10.1.0.0/16 → Target: tgw-xxxx           (via Transit Gateway)
Destination: 10.1.0.0/16         → Target: pcx-xxxx           (VPC Peering)
```

### Internet Gateway

An IGW is a horizontally scaled, redundant component attached to your VPC. It performs NAT between private IPs and your VPC's public IP.

Traffic flow: Instance (private IP) → IGW (attaches Elastic IP) → Internet

The IGW is free and handles unlimited bandwidth. Your instance's bandwidth is limited by the ENI's instance type limits.

### NAT Gateway

A NAT Gateway enables instances in private subnets to initiate outbound traffic to the internet (for OS updates, API calls, etc.) while preventing inbound connections from the internet.

Key properties:
- Deployed in a **public subnet** (one per AZ for HA)
- Managed by AWS — no patching, no maintenance
- One Elastic IP attached
- Supports TCP, UDP, and ICMP
- **Stateful in the outbound direction only** — inbound-initiated connections are blocked

NAT Gateway hourly cost + per-GB processing cost. In high-traffic private subnets, a NAT Gateway can be expensive. Consider a NAT Instance (EC2 with `SourceDestCheck` disabled) for lower cost at scale, or use a proxy service (VPC Endpoints for AWS API calls).

### VPC Endpoints

VPC Endpoints allow private connectivity to AWS services without going through the internet. Two types:

**Interface Endpoints** — An ENI with a private IP in your subnet (powered by AWS PrivateLink)
- S3, DynamoDB, SQS, SNS, Lambda, KMS, CloudWatch, Secrets Manager, and 100+ services
- Hourly cost per endpoint per AZ
- Security group controls access

**Gateway Endpoints** — A target in your route table for S3 and DynamoDB
- Free to use
- Only supports S3 and DynamoDB
- Uses prefix lists in route tables
- Most cost-effective for high-volume S3/DynamoDB access from private subnets

### VPC Flow Logs

Flow Logs capture traffic information for your VPC, subnet, or ENI. Not real-time — typically 10-15 minute delay before logs appear in CloudWatch Logs or S3.

Log format: `version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes action log-status`

Actions:
- `ACCEPT` — Traffic allowed by security group/NACL
- `REJECT` — Traffic blocked by security group/NACL
- `REJECT` — Traffic blocked by implicit VPC deny (no matching rule)

Use cases:
- Security monitoring (identify unauthorized access attempts)
- Troubleshooting connectivity (which security group rule is blocking?)
- Forensic analysis (what IPs were involved in an incident)
- Compliance (log all traffic for audit)

### Egress-Only Internet Gateway

IPv6 only. Allows outbound traffic from instances (via their IPv6 address) while preventing inbound IPv6 connections. Unlike an IGW, it doesn't support IPv4.

## Architecture: Three-Tier Web Application

```
Internet
  ↓
Internet Gateway
  ↓
Public Subnet (ALB)
  ↓
Private Subnet (EC2 App Tier) 10.0.11.0/24
  ↓
Private Subnet (RDS)10.0.21.0/24

Route Tables:
Public: 0.0.0.0/0 → IGW
Private: 0.0.0.0/0 → NAT Gateway (in public subnet)
RDS:10.0.0.0/16 → local
```

## VPC Sharing (AWS Organizations)

VPC sharing allows an account to share subnets with other accounts in the same AWS Organization. The sharing account owns the VPC; member accounts launch resources into shared subnets.

Benefits:
- Members don't need VPC CIDR planning
- Single VPC, multi-account usage
- Shared infrastructure (NAT GW, Transit Gateway) managed centrally

Limitations:
- Cannot share subnets with accounts outside the Organization
- All participants must be in the same Region

## VPC Reachability Analyzer

AReachability Analyzer helps you understand and debug network connectivity. You specify a source and destination, and AWS simulates the traffic path to identify where it's blocked.

Use when:
- A security group rule should allow traffic but connections still fail
- You want to audit connectivity before a production deployment
- Troubleshooting cross-account VPC Peering or Transit Gateway issues

## Limits

| Resource | Default Limit |
|----------|-------------|
| VPCs per region | 5 |
| Subnets per VPC | 200 |
| IPv4 CIDR blocks per VPC | 5 (max 16) |
| IPv6 CIDR blocks per VPC | 1 (/56 default) |
| Route tables per VPC | 200 |
| Elastic IPs | 5 per account |
| Security groups per VPC | 500 |
| Rules per security group | 60 inbound + 60 outbound |
| NACL rules per subnet | 20 inbound + 20 outbound |
| VPC Peering connections per VPC | 50 (can request increase) |
| NAT Gateways per AZ | 5 |

## Operational Best Practices

```
□ Use /16 VPC with /24 subnets per AZ — simplifies IP management
□ Always use at least 2 AZs — single-AZ is a single point of failure
□ Place NAT Gateways in the same AZ as the instances they serve — avoids cross-AZ NAT costs
□ Tag NAT Gateways with their AZ — helps identify which one to replace if an AZ fails
□ Use Gateway Endpoints for S3/DynamoDB from private subnets — free vs $0.007/endpoint-hour for Interface Endpoints
□ Enable VPC Flow Logs for all subnets — security monitoring and forensics
□ Use Security Groups as the primary firewall — NACLs as explicit deny for specific IPs/subnets only
□ Place ALB in public subnets, EC2/ECS in private subnets — never expose compute directly to the internet
□ Use VPC endpoints for AWS API calls from private subnets — avoids NAT Gateway costs and internet exposure
□ Set up a dedicated inspection VPC for perimeter security — Transit Gateway routes all traffic through it
```

## References

- **Homepage:** https://aws.amazon.com/vpc/
- **Documentation:** https://docs.aws.amazon.com/vpc/
- **Pricing:** https://aws.amazon.com/vpc/pricing/

## Pricing Examples

**Scenario 1:** A three-tier web application in us-east-1 with 6 subnets (2 AZs × 3 tiers). NAT Gateway in each AZ ($0.045/hr × 2 = $0.09/hr = $64.80/month) + VPC Flow Logs (100GB/month × $0.01/GB = $1/month) + 2 Interface Endpoints for Secrets Manager and KMS ($0.007/endpoint-hour × 2 × 720hr = $10.08/month). Total: ~$76/month for networking infrastructure.

**Scenario 2:** A startup with 50 EC2 instances in a private subnet making AWS API calls via a NAT Gateway.500GB/month outbound through NAT Gateway ($0.045/hr + $0.045/GB = $22.50 + $22.50 = $45/month for NAT data transfer). Using a Gateway Endpoint for S3 (free) instead of NAT Gateway for S3 calls saves $0.045/GB ×200GB = $9/month. VPC endpoints for AWS services: ~$10/month total. Total: ~$55/month.

## Nuggets & Gotchas

- **NAT Gateway has no Multi-AZ automatic failover:** If the AZ hosting your NAT Gateway goes down, instances in private subnets in other AZs that use that NAT Gateway lose internet access. Deploy one NAT Gateway per AZ, and route each AZ's private subnet traffic to its own NAT Gateway.
- **Gateway Endpoints are route table entries, not resources:** There's no "Gateway Endpoint" resource to manage in the console — it's just a prefix list route in your route table. This makes them invisible in most tooling but free.
- **Interface Endpoints cost $0.007/endpoint-hour per AZ:** In a 3-AZ VPC with 5 interface endpoints, that's 15 endpoint-hour charges per hour ($0.105/hr = $75/month). Minimize the number of AZs for interface endpoints or use PrivateLink endpoints in a single AZ.
- **VPC Flow Logs don't capture DNS traffic from the VPC DNS resolver (resolver VPC IP):** If an instance queries the VPC DNS (at the VPC router IP), that DNS query won't appear in Flow Logs. This makes troubleshooting DNS issues from Flow Logs impossible.
- **S3 VPC Endpoint policy is separate from the S3 bucket policy:** The VPC Endpoint can have its own access policy restricting which buckets are accessible from it. A bucket policy denying public access won't be overridden by a permissive VPC Endpoint policy — both must allow.

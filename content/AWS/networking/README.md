---
title: AWS Networking
description: AWS networking services — VPC for isolated cloud networking, Route 53 for DNS, ELB for load balancing, CloudFront for CDN, Direct Connect for hybrid connectivity, and VPC security services.
tags:
  - aws
  - networking
---

# AWS Networking

AWS networking is split into two layers: the foundational IP networking inside your VPC, and the edge services that connect users and on-premises infrastructure to your VPC.

## Service Map

| Service | What It Does | When to Use |
|---------|-------------|-------------|
| [[vpc/README|VPC]] | Isolated virtual network with subnets, route tables, gateways | Every AWS workload — foundational |
| [[vpc/security-groups|Security Groups]] | Stateful instance-level firewall | Per-instance/per-ENI inbound/outbound rules |
| [[vpc/network-acls|Network ACLs]] | Stateless subnet-level firewall |Subnet-level deny rules, explicit allow/deny |
| [[vpc/vpc-peering|VPC Peering]] | Private connection between two VPCs | Two VPCs needing direct private communication |
| [[vpc/transit-gateway|Transit Gateway]] | Hub-and-spoke router for 100s of VPCs | Multi-VPC architectures, cross-account routing |
| [[load-balancing/README|ELB]] | Distributes traffic across targets | Always — for any service with more than one target |
| [[dns/README|Route 53]] | Managed DNS and domain registration | Every production workload — DNS + health checks |
| [[cdn/README|CloudFront]] | Global CDN with edge caching | Static assets, API acceleration, geo-restriction |
| [[hybrid/README|Direct Connect]] | Dedicated private connection from on-prem | Hybrid workloads, consistent high-bandwidth needs |
| [[hybrid/README|VPN]] | Encrypted tunnel over internet | Quick hybrid setup, low-volume traffic |
| [[networking-security/README|API Gateway]] | Managed API proxy with auth and throttling | HTTP/REST APIs, microservices communication |

## How Services Relate

```
Internet → CloudFront → ALB → Services in VPC (EC2/ECS/Lambda in private subnets)
 ↓
         Route 53 (DNS resolution, health checks)
                ↓
         VPC (isolated network, subnets, route tables, NAT Gateway)
                ↓
         Direct Connect / VPN → On-premises
```

CloudFront sits at the edge, terminating user traffic before it hits your VPC. Route 53 resolves domain names and performs health checks to route around failures. Inside the VPC, security groups and NACLs enforce traffic rules, and the ELB distributes load across your compute fleet.

## Subnet Architecture Pattern

```
VPC (10.0.0.0/16)
├── Subnet-A (AZ-1)          10.0.1.0/24  — Public-facing (NLB/ALB, NAT Gateway)
├── Subnet-B (AZ-2)          10.0.2.0/24  — Public-facing
├── Subnet-C (AZ-1)          10.0.11.0/24 — Private (application servers)
├── Subnet-D (AZ-2)          10.0.12.0/24 — Private (application servers)
├── Subnet-E (AZ-1)          10.0.21.0/24 — Private (databases)
└── Subnet-F (AZ-2)          10.0.22.0/24 — Private (databases)
```

## Common Architecture Patterns

### Internet-Facing Web Service
```
Users → CloudFront → ALB (public subnet) → EC2/ECS (private subnets)
                        ↓
              RDS (database, private subnet)
```

### Hybrid with Private API
```
On-premises → Direct Connect → VPC Private subnet → API Gateway → Lambda/EC2
                                       ↓
                              Route 53 (private hosted zone)
```

### Multi-Account VPC
```
Transit Gateway (Account A)
 ├── VPC-Prod (Account B)
  ├── VPC-Dev  (Account C)
  └── VPC-OnPrem (Direct Connect)
```

## AWS Services Organized by Category

**Core Networking**
- [[vpc/README|VPC]] — Isolated network, subnets, route tables, IGW, NAT GW
- [[vpc/vpc-peering|VPC Peering]] — Two-VPC private connectivity
- [[vpc/transit-gateway|Transit Gateway]] — Multi-VPC hub router
- [[vpc/vpn|VPN]] — Site-to-Site VPN over internet

**Load Balancing**
- [[load-balancing/README|ALB]] — Layer 7 HTTP/S load balancer with rule-based routing
- [[load-balancing/README|NLB]] — Layer 4 TCP/UDP load balancer for high-throughput
- [[load-balancing/README|CLB]] — Legacy layer 4/7 load balancer (avoid for new deployments)

**DNS**
- [[dns/README|Route 53]] — Managed DNS, domain registration, health checks, routing policies

**CDN & Edge**
- [[cdn/README|CloudFront]] — Global CDN, SSL termination, edge functions

**Hybrid Connectivity**
- [[hybrid/README|Direct Connect]] — Dedicated 1Gbps/100Gbps private connection
- [[hybrid/README|VPN]] — Encrypted IPsec tunnel over internet

**Security & Filtering**
- [[networking-security/README|WAF]] — Web application firewall, rule-based filtering
- [[networking-security/README|Shield]] — DDoS protection (Standard vs Advanced)
- [[networking-security/README|Network Firewall]] — Managed VPC intrusion detection/prevention

## References

- **Homepage:** https://aws.amazon.com/networking/
- **Documentation:** https://docs.aws.amazon.com/vpc/
- **Pricing:** https://aws.amazon.com/vpc/pricing/

## Nuggets & Gotchas

- **Every VPC CIDR must be unique across your organization:** Overlapping CIDRs between VPCs prevent VPC Peering and Transit Gateway peering. Use RFC 1918 ranges and plan the IP space before creating VPCs.
- **Security groups are stateful; NACLs are stateless:** A return traffic rule in a security group is automatic (stateful). NACLs require explicit bidirectional rules for return traffic.
- **Cross-AZ traffic has a per-GB data transfer cost:** Traffic between AZs costs $0.01/GB (us-east-1). Traffic within the same AZ is free. Architect to minimize cross-AZ traffic for high-volume flows.
- **Internet Gateway is horizontally scalable and free:** It handles unlimited bandwidth. You don't need to provision or pay for IGW capacity. The bottleneck is your instance ENI bandwidth or NAT Gateway throughput.
- **VPC CIDR cannot be changed after creation:** You can't expand or shrink a VPC's CIDR. If you need more IP space, you must create a new VPC and migrate resources. Plan CIDR sizes generously (a /16 is common for a production VPC).

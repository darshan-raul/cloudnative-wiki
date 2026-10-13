---
title: "Amazon VPC"
description: "Build the routing and security mental model for public/private subnets, endpoints, egress and reachability tests."
tags:
  - cloud/aws/networking
date: 2026-10-12
---

# Amazon VPC

A VPC is a regional virtual network; each subnet belongs to one AZ. A “public subnet” has an Internet Gateway route, but that alone does not make an instance internet-reachable: addressing, SG/NACL and workload configuration still matter.

## Trace the path

Route tables use destination-prefix matching. The local route connects supported VPC ranges; additional routes can target gateways, peering, endpoints or TGW. Associate the intended table with each subnet rather than assuming every subnet uses the main table.

IPv4 private egress can use NAT where appropriate; supported IPv6 egress uses different controls. A zonal NAT design creates an AZ dependency; evaluate current supported gateway modes and routing rather than generalizing one topology. NAT instances add operating, scaling and availability responsibilities.

Use [[AWS/networking/vpc/security-groups|SGs]] for stateful ENI access and [[AWS/networking/vpc/network-acls|NACLs]] for subnet rules. Both forward and return paths must work.

## Private access and visibility

[[AWS/networking/private-access-and-hybrid-dns|Gateway/interface endpoints]] provide different private paths. Gateway endpoints are real resources with IDs/policies/routes. Interface endpoints add per-AZ network interfaces and applicable hourly/processing fees.

Flow Logs provide traffic metadata with documented exclusions. REJECT can reflect SG/NACL denial, including implicit denial; no log record does not prove a successful packet. Reachability Analyzer analyzes supported configurations, not live packet capture or application behavior.

VPC sharing/RAM changes ownership and allowed operations. It does not mean every participant can mutate every subnet route/resource; review shared-VPC responsibilities.

## Three-tier exercise

Prerequisites: approved sandbox CIDRs, two AZs, temporary credentials, budget and an independent administration path.

1. Design public ingress subnets, private application subnets and database subnets.
2. Draw each route table and the forward/return path for HTTPS, health checks, database access and required AWS API calls.
3. Deploy a disposable client/server through approved tooling; create only the necessary routes and rules.
4. Verify the intended application connection and denial from an excluded source.
5. Introduce one missing return route/rule in the sandbox. Use configuration analysis and logs to locate it, then restore access.
6. Inventory/delete dedicated gateways/endpoints, interfaces, workloads and logs before deleting subnets/VPC. Preserve shared resources.

A production pattern needs availability, capacity, DNS, deployment and recovery requirements; it is not a mandatory prescription to deploy a NAT/LB/database for every workload.

## Cost and quotas

Price NAT hours/processed GB, interface-endpoint AZ-hours/GB, transfer direction/AZ boundaries, public addresses and telemetry separately. Gateway endpoints do not have the same tariff as interface endpoints. Logs bill their own ingested/retained bytes, not network bytes multiplied by an invented log rate.

For a hypothetical us-east-1 study dated 2026-10-12, two zonal NAT gateways at an assumed \$0.045/hour over 730 hours cost 2 × 730 × \$0.045 = \$65.70 before processed data/other charges. Current Region/mode tariff and availability requirements determine the real comparison.

Inspect actual service quotas for CIDRs, subnets, routes, endpoints and security rules; classify adjustable/account/Region/resource scope.

## Addressing, route tables and shared VPCs

A subnet's IPv4 usable count is its CIDR size minus five reserved addresses. For example, a /24 has 256 total addresses and 251 usable; a /28 has 16 total and 11 usable. Plan capacity for ENIs, pods, load balancers and future growth, not just present EC2 instances. Every subnet is in one AZ and associated with one route table; a main route table applies when there is no explicit association.

| Example destination               | Route target     | Typical purpose                           |
| --------------------------------- | ---------------- | ----------------------------------------- |
| VPC CIDR                          | local            | Intra-VPC path                            |
| `0.0.0.0/0` in a public subnet    | Internet Gateway | Public IPv4 egress for eligible addresses |
| `0.0.0.0/0` in a private subnet   | NAT gateway      | Outbound IPv4 when required               |
| Remote VPC CIDR                   | Peering or TGW   | Approved cross-VPC route                  |
| Supported S3/DynamoDB prefix list | Gateway endpoint | Private service access                    |

The longest matching destination prefix wins among applicable routes. An IGW route does not itself make an instance public; public IPv4/EIP, SG/NACL permissions and a listening service still matter. A gateway endpoint has an endpoint ID, policy and route entries. An interface endpoint has ENIs and SGs; inspect private DNS and its supported service/Region contract.

For IPv6, an egress-only internet gateway supports outbound-initiated traffic without accepting new internet-initiated connections; it is not an IPv4 NAT gateway. Design IPv6 SG/NACL rules, address assignment and DNS deliberately. A VPC Flow Log can help explain accepted/rejected flows but has exclusions and delivery delay; a missing record does not prove the packet never arrived.

For shared VPCs, distinguish the VPC owner from participant accounts. Participants may launch supported resources in shared subnets but do not receive blanket authority over owner routes and gateways. Reachability Analyzer can identify supported configuration blocks; it cannot prove an application listener or credentials work. Use Flow Logs and an application probe alongside it.

## Lessons and references

- [[AWS/networking/vpc/vpc-peering|Peering]], [[AWS/networking/vpc/transit-gateway|TGW]], [[AWS/networking/vpc/vpn|VPN]].
- [VPC concepts](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html).
- [Subnet routing](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-route-tables.html).
- [VPC quotas](https://docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html).
- [Flow Logs](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html).
- [Pricing](https://aws.amazon.com/vpc/pricing/).

## Across the wiki

- [[Azure/networking/vnet|Azure Virtual Network (VNet) & Hybrid Routing]] — virtual networks (Azure)
- [[GCP/networking/vpc|GCP Virtual Private Cloud (VPC) & Networking]] — virtual networks (GCP)
- [[Architecture/solution-architecture-concepts/networking/README|Cloud-Native Networking Architecture Guide]] — virtual networks (Architecture)
- [[Linux/networking/README|Linux Networking]] — virtual networks (Linux)

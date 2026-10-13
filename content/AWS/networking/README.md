---
title: AWS networking
description: Follow routing, security, naming and service-access lessons in a dependency-aware learning order.
tags:
  - cloud/aws/networking
date: 2026-10-12
---

# AWS networking

Begin with packet paths, then add service discovery, ingress, hybrid/private access and inspection. A product association is not proof of connectivity or authorization.

## Learning route

1. [[AWS/networking/vpc/README|VPC routes/subnets]], [[AWS/networking/vpc/security-groups|SGs]] and [[AWS/networking/vpc/network-acls|NACL return traffic]].
2. [[AWS/networking/load-balancing/README|ALB/NLB/GWLB health and ingress]], [[AWS/networking/dns/README|Route 53]] and [[AWS/networking/cdn/README|CloudFront cache/origin security]].
3. [[AWS/networking/vpc/vpc-peering|Peering]] versus [[AWS/networking/vpc/transit-gateway|TGW]].
4. [[AWS/networking/hybrid/README|Direct Connect/VPN]], [[AWS/networking/vpc/vpn|client/site VPN]] and [[AWS/networking/private-access-and-hybrid-dns|PrivateLink/endpoints/Resolver]].
5. [[AWS/networking/networking-security/README|Network-security boundaries]] → [[AWS/networking/protection-and-inspection|staged WAF/inspection tests]].
6. [[AWS/networking/global-network-services|IPAM/Cloud WAN/Network Manager/Global Accelerator]] and [[AWS/concepts/vpc-lattice|Lattice]] for the requirements they actually address.

[[AWS/serverless/api-gateway/README|API Gateway]] is an API integration/authorization service, not the network-security page.

## Investigation exercise

Choose one HTTPS request. Record DNS answer, client route, load-balancer listener, target health, target route, SG/NACL permissions and application authorization. Trace the response as well. Change one sandbox component, predict the symptom and compare with observed logs/configuration.

Do not deploy every product in the list by default. Specify AZ/account/Region boundaries, RTO/latency and transfer volume before selecting a topology. Existing cross-cloud notes are comparisons, not prerequisites for AWS routing.

## Service map and example paths

| Problem                    | Starting component                                 | Path or question to trace                                    |
| -------------------------- | -------------------------------------------------- | ------------------------------------------------------------ |
| Public ingress             | Route 53, CloudFront, ALB/NLB                      | DNS → listener → target → return path                        |
| Private egress             | NAT or supported endpoint                          | Which destination and AZ route receives the packet?          |
| Cross-VPC                  | Peering or TGW                                     | Are both route tables and security rules present?            |
| Hybrid                     | DX and/or VPN                                      | Which prefixes, BGP sessions and DNS resolvers are involved? |
| API/private service access | Interface/gateway endpoint, PrivateLink or Lattice | Who owns the service and how is access authorized?           |
| Inspection                 | SG/NACL, WAF, Network Firewall                     | What traffic traverses the control and in which direction?   |

```text
Internet client → DNS → edge/WAF → public load balancer
                                      ↓ target group
                               private application subnet
                                      ↓ authorized port
                               private database subnet
```

For this three-tier pattern, draw one subnet set per chosen AZ and note each route table. Public ingress still needs an eligible public address and an application listener. Private application egress can use a NAT path or suitable endpoints. A database subnet may have only local routes and still need backups and control-plane access through supported paths. When diagnosing a timeout, trace both request and response; when diagnosing a 403, identify which layer generated it before changing network rules.

## References

- [VPC guide](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html).
- [Networking services](https://aws.amazon.com/products/networking/).
- [Network cost lesson](https://aws.amazon.com/vpc/pricing/).

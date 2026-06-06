---
title: Network ACLs
description: Network ACLs — stateless subnet-level firewalls in AWS VPC. Rule evaluation order, comparison to security groups, and when to use NACLs vs security groups.
tags:
  - aws
  - networking
  - network-acls
---

# Network ACLs (NACLs)

A Network ACL is a stateless subnet-level firewall. Unlike security groups (stateful, instance-level), NACLs are evaluated by rule number in order, and you must explicitly allow both directions of traffic.

## Key Differences from Security Groups

| Property | Security Group | Network ACL |
|----------|---------------|-------------|
| Scope | Instance-level (ENI) | Subnet-level |
| Stateful | Yes — return traffic auto-allowed | No — must explicitly allow return |
| Default rules | Allow all outbound, deny all inbound | Allow all inbound and outbound |
| Rule evaluation | All rules, most permissive wins | By rule number (lowest first, first match) |
| Explicit deny | Supported | Supported |
| Use case | Primary firewall | Subnet-level explicit deny |

## Rule Structure

```
Rule #:100           ← evaluated in order (100, 200, 300...)
Type:    ALL Traffic   ← or specific protocol (TCP, UDP, ICMP)
Source:  10.0.0.0/16  ← CIDR or prefix list
Action:  ALLOW/DENY
```

AWS reserves rule numbers 100 (first rule) and 32766 (last rule, catch-all). You can use even numbers (100, 200, 300) to leave room for inserts.

## Default NACL

The default NACL for a VPC allows all traffic, inbound and outbound. When you create a custom NACL, it denies all traffic by default.

## Common NACL Configuration

```
Inbound:
┌──────┬────────────┬─────────────┬────────┬────────┐
│ Rule │ Source     │ Protocol    │ Action │ Notes  │
├──────┼────────────┼─────────────┼────────┼────────┤
│ 100  │ 0.0.0.0/0  │ TCP 443 │ ALLOW  │ HTTPS  │
│ 110  │ 0.0.0.0/0  │ TCP 80      │ ALLOW  │ HTTP   │
│ 120  │ 10.0.0.0/8 │ TCP22      │ ALLOW  │ SSH    │
│ 200  │ 0.0.0.0/0  │ ALL │ DENY   │ Block │
└──────┴────────────┴─────────────┴────────┴────────┘

Outbound:
┌──────┬────────────┬─────────────┬────────┬────────┐
│ Rule │ Dest │ Protocol    │ Action │ Notes  │
├──────┼────────────┼─────────────┼────────┼────────┤
│ 100  │ 0.0.0.0/0  │ TCP 443     │ ALLOW  │ HTTPS  │
│ 100  │ 0.0.0.0/0  │ TCP 80      │ ALLOW  │ HTTP   │
│ 100  │ 0.0.0.0/0  │ UDP 53 │ ALLOW  │ DNS    │
│ 200  │ 0.0.0.0/0  │ ALL         │ DENY   │ Block  │
└──────┴────────────┴─────────────┴────────┴────────┘
```

## When to Use NACLs vs Security Groups

**Use NACLs for:**
- Explicit deny of specific IP ranges at the subnet boundary (e.g., deny known malicious IPs)
- Subnet-level policies that apply to all instances in the subnet regardless of their security group
- Compliance requirements for explicit deny at network layer
- Controlling traffic between tiers at the subnet level

**Use Security Groups for:**
- Primary firewall for most workloads
- Instance-level access control
- Stateful connection tracking (automatic return traffic)

**Best practice:** Use both. Security groups as the primary firewall, NACLs as the explicit deny layer for specific threats.

## Common Pattern: Public Subnet NACL

```
Public Subnet (ALB-facing):
Inbound:  Allow 0.0.0.0/0 → TCP 443 (HTTPS)
          Allow 0.0.0.0/0 → TCP 80  (HTTP, redirect to HTTPS)
Outbound: Allow 0.0.0.0/0 → TCP 443 (HTTPS outbound to internet)
          Allow 0.0.0.0/0 → TCP 80  (HTTP outbound)
```

## Limits

| Resource | Limit |
|----------|-------|
| NACLs per VPC | 200 |
| Rules per NACL | 20 inbound + 20 outbound |
| Subnets per NACL | 1 (but one NACL can be attached to many subnets) |

## References

- **Homepage:** https://docs.aws.amazon.com/vpc/latest/userguide/network-acls.html
- **Documentation:** https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html
- **Pricing:** https://aws.amazon.com/vpc/pricing/ (NACLs are free)

## Pricing Examples

NACLs are free. The cost is in the EC2 or other resources using the subnets they protect.

**Scenario 1:** An NACL blocking a known malicious IP range (e.g., a botnet C2 server) at the subnet level before it reaches any instance. This saves compute resources (CPU cycles on each instance) that would otherwise process blocked traffic. At10,000 blocked connections/day × 10 instances, that's significant CPU savings.

**Scenario 2:** A compliance requirement to log all network traffic at the subnet boundary. NACLs with a rule to DENY and log all traffic not explicitly allowed provides a subnet-level audit trail. CloudWatch Logs ingestion for NACL deny events: ~$0.50/GB. For a busy subnet processing 100GB/day of traffic, logging only the denies costs ~$0.01/day = $0.30/month.

## Nuggets & Gotchas

- **NACLs are stateless — you must explicitly allow return traffic:** If you allow inbound TCP 80 from 0.0.0.0/0, you also need an outbound rule allowing TCP 80 response traffic. Without it, the established connection reply is blocked, and your instance can't respond to HTTP requests.
- **NACL rule numbers are evaluated in order — first match wins:** Rule 100 is evaluated before rule 200. If you have an ALLOW rule at 100 and a DENY rule at 200 for the same traffic, the ALLOW wins. Use low numbers for allow rules and high numbers for deny rules.
- **NACLs apply to all instances in a subnet:** If you attach an NACL to a subnet with 50 instances, the NACL rules apply to all 50 instances. This is powerful but dangerous — a misconfigured NACL affects every instance in the subnet.
- **The default NACL allows everything:** The moment you create a custom NACL, it denies everything by default. If you attach it to a subnet without adding allow rules, all connectivity is cut off. Always configure the NACL before attaching it.
- **NACLs don't filter traffic between instances in the same subnet:** NACLs are evaluated at the subnet boundary, not per-instance. Traffic between two instances in the same subnet doesn't cross the subnet boundary, so NACLs don't apply. Use security groups for instance-to-instance filtering.

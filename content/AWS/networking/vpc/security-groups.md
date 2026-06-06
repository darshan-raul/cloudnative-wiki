---
title: Security Groups
description: Security Groups — stateful instance-level firewalls in AWS VPC. Rules, defaults, best practices, and comparison to Network ACLs.
tags:
  - aws
  - networking
  - security-groups
---

# Security Groups

A Security Group acts as a virtual stateful firewall for an EC2 instance (or any resource with an ENI). You assign a security group to an ENI, and it controls inbound and outbound traffic.

## How Security Groups Work

**Stateful:** When you send a request from an instance, the return traffic is automatically allowed regardless of inbound rules. If your outbound rule allows HTTP, inbound return traffic for established HTTP connections is allowed automatically.

**Default allow all outbound:** If you don't specify outbound rules, all outbound traffic is allowed.

**Implicit deny + explicit allow:** If no rule matches, traffic is denied. Only rules you explicitly add are enforced.

**Evaluate order:** Security groups evaluate rules in no particular order — AWS evaluates all rules and uses the most permissive match. This differs from NACLs which are evaluated by rule number.

## Default Security Group

Every VPC has a default security group. When you launch an instance without specifying a security group, the default SG is attached.

Default rules:
- Inbound: Allow traffic from other instances attached to the same default SG
- Outbound: Allow all

## Rule Structure

```
Type:       HTTP (TCP 80)          ← can use well-known name or port number
Protocol:  TCP                    ← TCP, UDP, ICMP, or all
Source: 10.0.0.0/8             ← CIDR, another security group, or IP range
Port:      80                    ← port or range (80-443)
Description: "Allow HTTP from app tier"
```

**Source options:**
- Another security group (e.g., `sg-0123456789abcdef`) — allows traffic from any instance using that SG
- CIDR block (e.g., `10.0.1.0/24`) — allows traffic from that IP range
- Prefix list (e.g., `pl-0123456789abcdef`) — AWS-managed IP ranges (used for AWS managed services)
- Single IP (e.g., `203.0.113.5/32`) — specific IP

## Common Rule Set Example

```
Inbound:
┌─────────────────────────────────┬──────────┬────────────────────┐
│ Source │ Port     │ Purpose │
├─────────────────────────────────┼──────────┼────────────────────┤
│ sg-allow-http-sg │ TCP 80   │ HTTP from ALB      │
│ sg-allow-https-sg              │ TCP 443  │ HTTPS from ALB     │
│ 10.0.0.0/16                    │ TCP 22   │ SSH from corporate │
│ sg-other-app-sg               │ TCP 5432 │ PostgreSQL from app │
└─────────────────────────────────┴──────────┴────────────────────┘

Outbound:
┌─────────────────────────────────┬──────────┬────────────────────┐
│ Destination │ Port     │ Purpose            │
├─────────────────────────────────┼──────────┼────────────────────┤
│ 0.0.0.0/0                      │ TCP 443  │ HTTPS to internet   │
│ sg-rds-sg                      │ TCP 5432 │ PostgreSQL to RDS   │
│ sg-redis-sg                    │ TCP 6379 │ Redis to ElastiCache│
└─────────────────────────────────┴──────────┴────────────────────┘
```

## Security Group best Practices

```
□ Never allow0.0.0.0/0 for RDP (TCP3389) or SSH (TCP 22) in production
□ Use source security groups, not CIDRs, for inter-tier traffic — CIDRs couple networking to security intent
□ Default security group: remove the inbound "allow same SG" rule and the outbound "allow all" rule
□ Create one security group per application tier (web-tier, app-tier, data-tier) — don't put all rules in one SG
□ Add descriptions to every rule — security groups are audited, descriptions explain intent
□ Restrict outbound to only what's needed — don't use 0.0.0.0/0 outbound unless necessary
□ Use prefix lists for AWS-managed services — pl-63a2c0a8 for S3 and DynamoDB gateway endpoints
```

## Monitoring Security Group Changes

Security group changes are logged in CloudTrail (`AuthorizeSecurityGroupIngress`, `RevokeSecurityGroupIngress`, etc.). Use AWS Config rules to detect:
- Security groups allowing 0.0.0.0/0 on sensitive ports
- Security groups with rules referencing deprecated SGs
- Security groups modified in production without change management

## Limits

| Resource | Limit |
|----------|-------|
| Security groups per VPC | 500 |
| Rules per security group | 60 inbound + 60 outbound |
| Security groups per ENI | 5 |
| Security groups you can reference per rule | 10 |

## References

- **Homepage:** https://docs.aws.amazon.com/vpc/latest/userguide/security-groups.html
- **Documentation:** https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html
- **Pricing:** https://aws.amazon.com/vpc/pricing/ (Security Groups are free)

## Pricing Examples

Security Groups are free to create and free to attach. The cost is in the EC2 instance or other resources that use them.

**Scenario 1:** A microservice architecture with 10 security groups (one per service). Using source security groups instead of CIDRs means the rules don't need updating when subnet CIDRs change. Saves approximately 2 hours/month of manual CIDR management work at $50/hr = $100/month in avoided labor.

**Scenario 2:** A production environment where a security group audit discovers 3 instances allowing0.0.0.0/0 on SSH. These are remediated before a breach. The audit took 1 hour. Without security group rules as code (e.g., Terraform), manual remediation of security group misconfigurations is common and costly.

## Nuggets & Gotchas

- **Security groups are stateful — return traffic is always allowed:** If you allow inbound HTTP (TCP 80), the return outbound traffic (TCP source port 80 response) is automatically allowed. Don't add an outbound rule for established connections — it's redundant.
- **Security group rules have no order — most permissive wins:** Unlike iptables with its numbered rules, security groups evaluate all rules simultaneously. You can't have "deny this IP, allow everything else" in one security group. Use NACLs for explicit deny rules.
- **References to security groups create implicit dependencies:** If SG-A allows traffic from SG-B, you can't delete SG-B while SG-A rules reference it. This creates coupling between resources that isn't visible in the console. Document SG dependencies.
- **Cross-account SG references require VPC Peering or Transit Gateway:** A security group in Account A can't reference a security group in Account B unless the VPCs are peered or connected via TGW. Shared VPCs in AWS Organizations can share SGs within the same Organization.
- **Default security group rules are a common attack surface:** The default SG allows all traffic from other instances with the same SG. If you launch an instance with the default SG and that instance is compromised, it can reach all other instances using the default SG. Use dedicated security groups per workload.

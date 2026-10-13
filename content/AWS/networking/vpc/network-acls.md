---
title: Network ACLs
description: Trace stateless subnet filtering, return ports and ordered deny rules, then test and roll back a sandbox NACL change.
tags:
  - cloud/aws/networking
  - cloud/aws/security
date: 2026-10-12
---

# Network ACLs

A network ACL filters traffic at a subnet boundary. It is stateless: an allowed request does not automatically permit its response. Use [[AWS/networking/vpc/security-groups|security groups]] as the primary resource firewall; add NACL restrictions when subnet-level controls are required.

## Rule evaluation

NACLs evaluate the lowest numbered matching rule first. Numbers such as 100 and 200 are ordinary configurable numbers; the immutable `*` rule denies unmatched traffic. Use distinct rule numbers within each direction. A deny must precede an overlapping allow to take effect.

| Property         | Security group                                     | Network ACL                                                |
| ---------------- | -------------------------------------------------- | ---------------------------------------------------------- |
| Attachment       | Network interface                                  | Subnet                                                     |
| Rule type        | Allow only                                         | Allow or deny                                              |
| Response traffic | Connection tracking                                | Explicit return rules                                      |
| Default          | New group has outbound allow-all; no inbound allow | Default VPC ACL allows traffic; a new custom ACL denies it |
| Association      | Multiple groups can apply to an ENI                | One ACL per subnet; one ACL can serve multiple subnets     |

## Trace an HTTPS exchange

Suppose an external client uses TCP source port 53000 to contact a server on port 443:

1. The request arrives at destination port 443: the subnet needs an inbound allow.
2. The response leaves with source port 443 and **destination port 53000**: the subnet needs an outbound ephemeral-port allow.
3. Allowing outbound destination port 443 alone does not allow that response.

For a sandbox web server accepting only HTTPS from `192.0.2.0/24`, the conceptual rules are:

| Direction | Rule | Peer CIDR    | Protocol / destination ports | Action |
| --------- | ---- | ------------ | ---------------------------- | ------ |
| Inbound   | 100  | 192.0.2.0/24 | TCP 443                      | Allow  |
| Outbound  | 100  | 192.0.2.0/24 | TCP 1024–65535               | Allow  |
| Both      | \*   | All          | All                          | Deny   |

The client chooses its ephemeral port. Narrow the return range only when you control the clients and have verified their range. IPv4 and IPv6 need separate rules. This example does not include DNS, outbound updates, load-balancer health checks or administrative access; design those paths separately.

## Sandbox exercise and rollback

Prerequisites: a non-production VPC/subnet, an HTTPS server with working routing and security groups, a permitted client, and EC2 permissions to read/create/associate ACLs. NACLs themselves have no extra charge; compute, addresses, telemetry and other network services can.

1. Record the original subnet ACL association and rules using `aws ec2 describe-network-acls`. Keep an independent administration path.
2. Replace the documentation-only 192.0.2.0/24 example with the actual sandbox client's verified CIDR. Create a custom ACL, add both rules with that source/return destination, and review the final rules **before** associating it.
3. Associate it only with the sandbox subnet. A successful HTTPS response is the checkpoint.
4. Remove the outbound return rule. Expect a connection failure despite the inbound allow; use [[AWS/networking/networking-security/README|VPC Flow Logs]] and Reachability Analyzer to investigate.
5. Restore the rule and repeat the successful request.
6. Reassociate the original ACL, verify connectivity, then delete the now-unassociated lab ACL. Delete only lab resources.

NACLs do not contain their own logging destination. Flow Logs provide traffic metadata, not packet payloads; do not infer log bytes or cost from total network bytes.

## Capacity and design

Consult current regional [VPC quotas](https://docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html) before adding rules. Increasing rule count can affect performance; do not treat copied defaults as every account's effective allocation. NACLs do not filter traffic between resources in the same subnet.

## Design patterns and investigation

Keep a short table for every subnet class rather than copying a universal public-subnet ACL. A public ALB subnet, private application subnet and database subnet need different peer CIDRs and return ports. If an application client chooses an ephemeral source port, the **server subnet's outbound** ACL must allow that destination port; the **client subnet's inbound** ACL must allow the return response as well. Apply the same trace to health checks and database sessions.

| Symptom                                | First check                                          |
| -------------------------------------- | ---------------------------------------------------- |
| SYN arrives, no response               | Outbound response rule and return route              |
| Only some clients fail                 | Source CIDR and client ephemeral-port range          |
| New custom ACL cuts off administration | Default deny and missing explicit admin/return rules |
| IPv4 works, IPv6 fails                 | Separate IPv6 entries and routes                     |

When investigating, compare the associated ACL ID for both endpoint subnets, then evaluate rules in number order for **each direction**. A broad low-numbered allow can make a later deny ineffective. Record the old association ID before changing anything so rollback does not depend on the new path.

## References and next steps

- [Custom NACLs, return traffic and client port ranges](https://docs.aws.amazon.com/vpc/latest/userguide/custom-network-acl.html).
- [Rule evaluation](https://docs.aws.amazon.com/vpc/latest/userguide/nacl-rules.html).
- [Security group rules](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html).
- Next: [[AWS/networking/vpc/README|VPC routing]], [[AWS/networking/load-balancing/README|load-balancer paths]] and [[AWS/networking/networking-security/README|network inspection]].

## Across the wiki

- [[Azure/networking/nsg|Azure Network Security Groups (NSGs) & ASGs]] — network firewalls (Azure)
- [[GCP/networking/vpc/firewalls|GCP Firewalls & Hierarchical Policies]] — network firewalls (GCP)
- [[Linux/networking/iptables|iptables]] — network firewalls (Linux)
- [[Kubernetes/concepts/L04-services-networking/05-network-policy|Explicit is better than implicit]] — network firewalls (Kubernetes)

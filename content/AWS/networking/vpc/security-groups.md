---
title: "Security groups"
description: "Trace stateful ENI filtering, default outbound rules and source-group references, then verify least-privilege access."
tags:
  - cloud/aws/networking/security
date: 2026-10-12
---

# Security groups

Security groups filter traffic for associated network interfaces. They have **allow rules only**; [[AWS/networking/vpc/network-acls|NACLs]] provide ordered subnet-level allow/deny rules.

## Evaluation and defaults

Rules from associated groups combine as allowed traffic, subject to documented connection-tracking behavior and service restrictions. Return traffic for tracked allowed connections does not need a reverse-direction allow.

A newly created group normally contains an outbound allow-all rule. If you **remove all outbound rules**, new outbound traffic is blocked; absence of outbound rules is not implicit allow-all. The default VPC group also has its own same-group inbound rule; do not confuse it with every newly created group.

Group references identify permitted traffic from/to supported associated resources, not copies of all the referenced group's rules. Peering/TGW/cross-account references have direction/topology restrictions; inspect the actual support contract rather than assuming every connected VPC permits every reference.

## Sandbox access exercise

Prerequisites: one disposable server/client, an excluded test client, known VPC/subnet routes, scoped EC2 permissions and an independent administrative channel. Record the original groups first. On the disposable test ENI, replace the associated group set with the lab group for the experiment rather than adding it alongside existing permissive groups: rules across associated groups are additive. Keep administrative access on a separate ENI/path, not a broad rule on the tested interface. If you cannot isolate the test ENI safely, keep the exercise design-only.

1. Create a dedicated lab group and allow the server's application port only from the client group's supported reference or exact client CIDR.
2. Verify that the lab group is the **only** group associated with the tested ENI. Confirm the application is listening and routes/NACLs/host firewall permit the intended path, then make a new connection; expect success.
3. Connect from an excluded client; expect failure.
4. Record a successful fresh TCP connection to a known reachable ordinary application destination, then remove the sandbox group's default outbound allow and try a **new outbound** TCP connection from the server to the same destination/port; expect failure. Do not use AmazonProvidedDNS/Route 53 Resolver as the denial target: that traffic has a documented SG-filtering exception. Verify that no second group, alternate ENI, IPv6 path or cached/tracked connection supplies an unintended allow.
5. Restore the approved outbound destinations and confirm only intended access.

Do not use an existing tracked connection as the sole test of a rule removal. Connection tracking can affect existing flows; follow the documented untracked/timeout behavior. Check SG, NACL, routes, DNS and guest firewall separately. Record the tested ENI/group IDs, source/destination address family and fresh connection result at each step. A failure without a successful pre-change baseline does not prove the SG caused it.

Cleanup: restore the original ENI groups, remove only the lab group after all references/associations are gone, and remove dedicated test resources. Security groups have no separate create/attach fee, but workloads and telemetry do.

## Design and capacity

Use a tier model: clients → load balancer group; load balancer group → application port; application group → database port. Do not expose SSH/database ingress to all sources. Use approved administration paths and IPv6 rules when needed.

Discover actual limits for groups, rules and ENI associations in your Region/account. Managed prefix-list IDs vary; retrieve the correct list for the service/Region instead of copying a hard-coded ID. Extra groups/rules can affect effective capacity constraints.

## Tiered rule pattern and change diagnosis

```text
client CIDR → ALB SG: HTTPS listener
ALB SG     → application SG: application port
app SG     → database SG: database port
app role   → AWS API: IAM permission plus network endpoint/egress
```

Use SG references when a service should trust members of another group rather than a changing host IP. A reference authorizes traffic from the associated ENIs under supported topology rules; it does not copy the referenced group's allow rules. For an Internet-facing load balancer, the target SG should normally accept application traffic from the LB group, not from every client CIDR.

To audit a change, record rule ID, protocol/ports, source or destination, referenced group/prefix list and affected ENIs. Compare VPC Flow Logs and application logs after a **new** connection attempt. Existing tracked flows can mask the effect of removing a rule. If a new flow still fails with an apparently correct SG, check subnet routes, NACLs, listener health, IPv6 family and the host firewall. A security-group rule cannot make an unreachable route work.

## References

- [Rule basics](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html).
- [Connection tracking](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/security-group-connection-tracking.html).
- [VPC quotas](https://docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html).
- [Security-group referencing](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html#security-group-referencing).
- Next: [[AWS/networking/vpc/README|routes]] and [[AWS/networking/load-balancing/README|load-balancer health paths]].

## Across the wiki

- [[Azure/networking/nsg|Azure Network Security Groups (NSGs) & ASGs]] — network firewalls (Azure)
- [[GCP/networking/vpc/firewalls|GCP Firewalls & Hierarchical Policies]] — network firewalls (GCP)
- [[Linux/networking/iptables|iptables]] — network firewalls (Linux)
- [[Kubernetes/concepts/L04-services-networking/05-network-policy|Explicit is better than implicit]] — network firewalls (Kubernetes)

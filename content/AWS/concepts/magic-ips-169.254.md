---
title: "AWS link-local service addresses"
description: "Identify metadata, time, DNS and credential endpoints while treating instance-local access as a security boundary, not a secret."
tags:
  - cloud/aws/networking
date: 2026-10-12
---

# AWS link-local service addresses

AWS uses link-local endpoints for selected local services. They do not need an internet/NAT path, but “local” does not mean every process should have access.

| Address         | Common purpose               | Check                                              |
| --------------- | ---------------------------- | -------------------------------------------------- |
| 169.254.169.254 | EC2 instance metadata        | Require IMDSv2 and control exposure                |
| 169.254.169.123 | Amazon Time Sync NTP         | Configure supported time client                    |
| 169.254.169.253 | Amazon-provided DNS resolver | Check VPC DNS settings/Resolver behavior           |
| 169.254.170.2   | ECS task credential endpoint | Use SDK credential provider; never log credentials |

Supported IPv6/addressing and EKS credential paths differ; do not reuse one endpoint for every workload identity integration.

## Why these addresses work

IPv4 link-local addresses belong to `169.254.0.0/16`; they are intended for local-link communication and are not internet-routable destinations. AWS exposes selected instance or task services at addresses in that range. The exact service path is platform-specific: do not infer that every `169.254` request is handled by one universal hypervisor mechanism or that an address is reachable from every container network namespace.

For IMDS, an instance can retrieve nonsecret metadata and, when a role is attached, temporary role credentials. Protect the endpoint as a credential path: require IMDSv2 where supported, use least-privilege instance roles, set an appropriate hop limit and consider SSRF/container exposure. The DNS resolver and time service solve different problems; a missing DNS answer or clock drift needs a separate diagnostic path from failed metadata access.

## Metadata exercise

On the sandbox instance in [[AWS/compute/ec2/README|the EC2 lab]], acquire an IMDSv2 token and retrieve only instance-id. Verify tokenless access fails when HttpTokens=required. Review hop-limit behavior for the intended container/network layout; do not disable protections merely to make an example work.

Never fetch/publish role credential documents in a tutorial output. An SSRF-capable application or compromised process may reach metadata even though the address is not publicly routed. Use least-privilege roles and application/network controls as well as IMDSv2.

Inspect DNS and time synchronization with the supported client tools; an address alone does not prove the service is enabled or correctly configured.

## References

- [IMDSv2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html).
- [Amazon DNS](https://docs.aws.amazon.com/vpc/latest/userguide/AmazonDNS-concepts.html).
- [Time synchronization](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/set-time.html).
- [ECS task role credentials](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html).

## Across the wiki

- [[GCP/networking/vpc/cloud-nat|GCP Cloud NAT Deep Dive & SNAT Port Allocation]] — NAT and egress (GCP)
- [[Architecture/solution-architecture-concepts/networking/nat|Nat]] — NAT and egress (Architecture)

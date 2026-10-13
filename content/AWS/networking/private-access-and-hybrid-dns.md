---
title: "Private access and hybrid DNS"
description: "Compare gateway/interface endpoints, PrivateLink producer-consumer boundaries and Resolver forwarding with a private-path test."
tags:
  - cloud/aws/networking
date: 2026-10-12
---

# Private access and hybrid DNS

Private connectivity still requires DNS, routing and authorization. Start with [[AWS/networking/vpc/README|VPC]], [[AWS/networking/vpc/security-groups|SGs]] and [[AWS/networking/dns/README|DNS]].

## Endpoint models

S3/DynamoDB gateway endpoints are real VPC endpoint resources that add routes to selected tables. They have IDs, policies and lifecycle operations; they are not invisible unmanaged routes. They do not behave like interface ENIs and are not a universal direct on-premises endpoint path.

Interface endpoints use ENIs, security groups and supported private DNS. PrivateLink endpoint services separate producer ownership/acceptance from consumer network placement. Service access still needs applicable identity/resource/endpoint/key permissions.

A private DNS name can resolve correctly while TLS, SG, route or application authorization fails. Avoid treating all errors as DNS problems.

## Hybrid resolution

Resolver inbound endpoints let approved on-premises resolvers query AWS private namespaces. Outbound endpoints/rules forward selected AWS queries to on-premises DNS. Choose conditional forwarding domains and prevent forwarding loops. Private hosted-zone association, endpoint reachability and rule sharing are separate setup steps.

## Sandbox path exercise

Prerequisites: a sandbox VPC, existing private client with management access, a small private S3 test object and approved endpoint permissions.

1. Record the route table and current S3 access path.
2. Create an S3 gateway endpoint, select only the lab route table and scope its endpoint policy.
3. From the client, retrieve the approved test object; confirm the route target is the endpoint.
4. Narrow the sandbox endpoint policy to exclude that test access; expect denial despite intact DNS/routes.
5. Restore the approved policy and successful access.
6. Remove only the lab endpoint after restoring the original design; retain shared buckets/client/network.

For interface endpoints, repeat with private DNS and SG checks and account for per-AZ hourly/data-processing costs. A single-AZ endpoint can reduce cost but also introduces zonal dependency; do not recommend it without the availability requirement.

## References

- [Gateway endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/gateway-endpoints.html).
- [PrivateLink concepts](https://docs.aws.amazon.com/vpc/latest/privatelink/concepts.html).
- [Hybrid Resolver](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html).
- [Endpoint policies](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-access.html).

---
title: "AWS foundations"
description: "Understand AWS boundaries, safe account access and the prerequisites for a first reversible deployment."
tags:
  - cloud/aws/foundations
date: 2026-10-12
---

# AWS foundations

Start here before choosing services. You need basic TCP/IP, HTTP, JSON, a shell and an understanding of credentials. Cloud services remove selected infrastructure tasks, not responsibility for application correctness, security or cost.

## Boundaries that affect design

A Region is a geographic service boundary; an Availability Zone contains one or more data centers. AZ names such as us-east-1a can map differently across accounts, so use AZ IDs for cross-account coordination. Partitions separate namespaces and credentials; construct ARNs from the actual partition, service, Region, account and resource format rather than blindly copying arn:aws.

A multi-AZ deployment handles selected zonal failures, not arbitrary regional loss. Global services still have region-specific resources/integrations: for example, a global DNS control surface does not make every certificate usable in every Region.

Shared responsibility changes with the service: on EC2 you patch guest OS/software, whereas a managed database shifts infrastructure work but leaves data, access, configuration and application correctness with you.

## Safe account baseline

Protect root access with strong MFA and recovery procedures; do not use root for daily CLI activity. Use [[AWS/security/iam/identity-center|workforce federation]] and temporary credentials. Establish billing contacts, a budget alert and resource ownership tags before labs. Budget alerts can lag and do not constitute a hard spending cap.

Choose a sandbox account and one Region. Check service eligibility, effective quotas and paid resources such as public IPv4 addresses, NAT, storage and logging. New and legacy accounts have different Free Tier programs; do not assume a lab is free.

## Learning route

1. [[AWS/foundations/getting-started|Authenticate, inspect and deploy a small reversible workload]].
2. [[AWS/security/iam/policy-evaluation|Explain the permission decision]].
3. [[AWS/networking/vpc/README|Trace the network path]].
4. [[AWS/compute/lambda/README|Build a small Lambda function]] or [[AWS/compute/ec2/README|operate a VM]].
5. [[AWS/monitoring/tracing-and-observability|Observe outcomes and failures]].
6. [[AWS/reliability/backup-and-recovery|Prove recovery]].
7. [[AWS/architecture/well-architected|Review the workload across six pillars]].

Checkpoint: explain which account and Region will be changed, whose role is active, what incurs cost, what evidence proves success and exactly which resources cleanup removes. If you cannot answer, do not run a create/delete command.

## References

- [Global infrastructure](https://docs.aws.amazon.com/whitepapers/latest/aws-overview/global-infrastructure.html).
- [Shared responsibility](https://aws.amazon.com/compliance/shared-responsibility-model/).
- [ARN structure](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference-arns.html).
- [IAM best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html).
- [AZ IDs](https://docs.aws.amazon.com/ram/latest/userguide/working-with-az-ids.html).

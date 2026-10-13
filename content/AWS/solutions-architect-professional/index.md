---
title: AWS Solutions Architect Professional (SAP-C02)
tags:
  - aws/certification/sap-c02
date: 2026-10-12
description: Sourced task-by-task SAP-C02 revision path with prerequisites, design scenarios and practical study drills.
aliases:
  - AWS/solutions-architect-professional
---

# AWS Certified Solutions Architect - Professional (SAP-C02)

This study path maps 20 task lessons to the current official exam guide. It teaches design decisions through prerequisites, original scenarios, rationale, rejected alternatives and proposed drills. It is a revision companion, not an exhaustive syllabus or a guarantee of a passing score.

## Official exam structure

The guide describes 65 scored and 10 unscored questions, with a minimum passing scaled score of 750. Scaled score is not a raw percentage. Emerging-topic questions described by the current guide are unscored; consult the guide rather than assuming every newly announced service is a scored objective.

| Domain                        | Scored-content weight | Study path                                                        |
| ----------------------------- | --------------------- | ----------------------------------------------------------------- |
| Organizational complexity     | 26%                   | [[AWS/solutions-architect-professional/domain-1/index\|Domain 1]] |
| New solutions                 | 29%                   | [[AWS/solutions-architect-professional/domain-2/index\|Domain 2]] |
| Existing-solution improvement | 25%                   | [[AWS/solutions-architect-professional/domain-3/index\|Domain 3]] |
| Migration and modernization   | 20%                   | [[AWS/solutions-architect-professional/domain-4/index\|Domain 4]] |

## Prerequisites and workflow

Start with [[AWS/networking/README|networking]], [[AWS/security/README|security]], [[AWS/compute/README|compute]], [[AWS/storage/README|storage]], [[AWS/databases/README|databases]] and [[AWS/cost-management/README|cost management]]. The official target candidate has substantial hands-on architectural experience; reading service names alone is insufficient preparation.

For each task, identify the business constraint, select the simplest compliant design, explain why alternatives fail and define evidence that would validate the choice. Track weak topics and revisit the linked service lessons. Check the current guide's service references and lifecycle notices before undertaking labs; historical exam mentions do not guarantee present service availability.

## Service study map

| Area               | Representative lessons and questions                                                                                             |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| Compute/containers | [[AWS/compute/README\|EC2, Lambda, ECS/EKS, Fargate and Batch]]: control, execution model and scaling                            |
| Storage            | [[AWS/storage/README\|S3, EBS, EFS, FSx and Storage Gateway]]: protocol, access, performance and recovery                        |
| Databases          | [[AWS/databases/README\|RDS/Aurora, DynamoDB, ElastiCache and analytics stores]]: compatibility, consistency and topology        |
| Networking         | [[AWS/networking/README\|VPC, DNS, hybrid connectivity, delivery and load balancing]]: permitted paths and failure domains       |
| Governance         | [[AWS/management-governance/README\|Organizations, Control Tower, IaC and Systems Manager]]: ownership and controlled operations |
| Security           | [[AWS/security/README\|IAM, KMS, detection and posture tools]]: identity, data and evidence boundaries                           |
| Integration        | [[AWS/serverless/README\|APIs, events, queues and workflows]]: decoupling, retries and idempotency                               |
| Economics          | [[AWS/cost-management/README\|Pricing, allocation and optimization]]: eligible units and avoidable cost                          |

This service study map is representative, not the exhaustive official in-scope list. Check the current guide's service references. A service may appear historically on an objective while its current availability is restricted; labs must use supported offerings.

### Review record

For each task, record the requirement, chosen option, rejected option, decisive constraint, calculation and proposed validation. Revisit a lesson when you can name services but cannot explain a failure, permission denial or bill. Reading completion is not an exam score or hands-on experience.

## Capstone scenario

A regulated business is acquiring a company while launching a new customer portal and exiting a data center. Combine account/network isolation, a staged deployment, recovery objectives, migration waves and cost ownership into one decision record. Reject a single “best service” answer: different components have different compatibility, risk and time constraints.

## Practical capstone drill

Produce a dependency/account diagram, requirements matrix, three option comparisons, a cost model with units, a cutover/recovery runbook and a prioritized improvement backlog. Include at least one rejected alternative per domain and identify assumptions requiring measurement. Use supplied data or an authorized sandbox only; this collection does not claim the drills were executed or services deployed.

## References

- [Current SAP-C02 exam guide, structure and emerging topics](https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02.html)
- [Official certification overview](https://aws.amazon.com/certification/certified-solutions-architect-professional/)
- [Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)
- [AWS service lifecycle notices](https://docs.aws.amazon.com/general/latest/gr/full_shutdown_services.html)

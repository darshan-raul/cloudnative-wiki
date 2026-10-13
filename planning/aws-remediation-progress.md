# AWS remediation progress

> Follow-up: the user identified excessive trimming across the rewritten lessons. The earlier completion status below covered the audit's factual and structural corrections, but did not establish preservation of teaching depth. [Depth restoration](aws-depth-restoration.md) is complete: all 155 original notes reviewed, 152 restored/rebuilt, and fresh checks passed.

Started 2026-10-12 against the [preserved baseline audit](aws-notes-gap-audit.md). **Complete for the inventoried authoring and local-validation scope.** Scope: confirmed N/C/S/M/I/F/R findings, pending claim queues, the 24-row missing-topic matrix, all 155 original per-note actions, reference failures and canonical navigation.

## Completion gates

- [x] Resolve confirmed corrections and inconsistent duplicates.
- [x] Verify or replace unsupported pending claims/API examples.
- [x] Repair references and add owning documentation sources.
- [x] Fill the missing-topic matrix and meaningful learning navigation.
- [x] Add bounded exercises with prerequisites, checkpoints, failures and cleanup.
- [x] Upgrade all 25 SAP pages with official mapping, scenarios and references.
- [x] Normalize hierarchical tags and canonical lesson ownership.
- [x] Finish final checks/build and emitted-page smoke verification.

## Implemented scope

**181 current notes: all 155 original notes updated, 26 new lessons/indexes.** No original note path deleted. [Current per-note inventory](aws-remediation-inventory.md); [verification evidence](aws-remediation-verification.md).

| Workstream                                                      | Baseline pages | Findings / closure                                                                               |
| --------------------------------------------------------------- | -------------: | ------------------------------------------------------------------------------------------------ |
| Data, storage, analytics, ML and governance                     |             42 | [S-series/source-decision and per-note closure](aws-data-remediation-progress.md)                |
| Security, migration, monitoring and integration                 |             33 | [R/M/I and scoped S/N/C closure](aws-operations-remediation-progress.md)                         |
| Costs, cost concept view and certification                      |             46 | [F/S, pending costs and all 25 SAP pages](aws-cost-curriculum-remediation-progress.md)           |
| Root-owned compute/network/serverless, hubs and protected notes |             34 | N01–N31/C01–C12 completed across root/operations paths; retirement and baseline stub corrections |
| New topics and navigation                                       |             26 | Missing-topic dispositions below                                                                 |
| Independent review                                              |      51 bodies | [All ten concrete findings corrected](aws-final-review.md)                                       |

Finding IDs overlap across duplicate notes; do not sum them into a unique-error count. Confirmed errors were corrected; suspected assertions without a verified contract were removed or replaced with explicitly conceptual, owning-source-linked workflows.

## Root finding dispositions

- N01–N03: NACL allow/deny, catch-all, associations and client ephemeral return ports corrected; real client CIDR required in the sandbox exercise.
- N04–N10: load-balancer protocol/health/access, empty SG egress, real endpoint resources, REJECT records and firewall order corrected.
- N11–N18: TGW route/quota/price scope, static VPN, Client VPN identity, DNS TTL/arithmetic and cache/range behavior corrected.
- N19–N20: external ID is not a secret or independent permission; API keys/plans are not authentication or hard cost caps.
- N21–N28: obsolete Lambda/ECS/EKS catalogs/examples were replaced by scoped invocation, task and canonical EKS guidance; billing arithmetic and Fargate storage corrected.
- N29/N31 and C08/C09: Inspector/KMS corrected in the operations workstream.
- N30: App Runner timeout/tracing corrected, with the newly verified closed-to-new-customers restriction.
- C01–C03/C05: complete Lambda handler and launch/task request objects supplied; local syntax/model and fixture checks recorded.
- C04/C06/C07: invented Spot Fleet/discovery/scaling/IRSA examples removed or replaced with supported request contracts/canonical implementations.
- C10–C11: language mixing and incomplete JSON examples eliminated; retained snippets parse.
- C12: Lattice now includes targets, listener, auth, evidence, failure and dependency-order cleanup rather than a partial “production” command list.
- Historical QLDB, Kinesis SQL, SMS and App Mesh deployment advice retired; new-customer restrictions differentiated from full shutdown.
- Currency dollar signs escaped so billing arithmetic renders as prose rather than equations.

## Missing-topic matrix closure

| Inventoried module                               | Implemented learning location                                                                                                                         |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Foundations / first deployment                   | [Foundations](../content/AWS/foundations/README.md), [safe session](../content/AWS/foundations/getting-started.md), canonical Lambda lab              |
| Six-pillar review                                | [Well-Architected](../content/AWS/architecture/well-architected.md)                                                                                   |
| IAM evaluation / STS                             | [Evaluation](../content/AWS/security/iam/policy-evaluation.md), [STS](../content/AWS/security/iam/sts-and-federation.md)                              |
| Workforce federation                             | [Identity Center](../content/AWS/security/iam/identity-center.md)                                                                                     |
| Application identity                             | [Cognito](../content/AWS/security/cognito.md), with separate tenant-isolation extension                                                               |
| Organizations/RAM                                | [Guardrail/share workflow](../content/AWS/management-governance/guardrails-and-resource-sharing.md), Organizations/delegation lessons                 |
| AWS Backup / DRS                                 | [Backup and recovery](../content/AWS/reliability/backup-and-recovery.md)                                                                              |
| Fleet lifecycle                                  | [Auto Scaling](../content/AWS/compute/auto-scaling.md)                                                                                                |
| Registry / Fargate                               | [ECR](../content/AWS/compute/ecr.md), complete ECS/Fargate task and Batch request                                                                     |
| Delivery                                         | [Developer tools](../content/AWS/developer-tools/README.md), existing canonical EKS pipeline                                                          |
| Tracing / operations                             | [Observability](../content/AWS/monitoring/tracing-and-observability.md), corrected CloudWatch lessons                                                 |
| Quotas / Health / support                        | [Operations](../content/AWS/operations/quotas-health-and-support.md)                                                                                  |
| Private access / hybrid DNS                      | [Endpoints and Resolver](../content/AWS/networking/private-access-and-hybrid-dns.md)                                                                  |
| Hybrid routing / inspection drill                | Corrected [hybrid](../content/AWS/networking/hybrid/README.md), [inspection](../content/AWS/networking/protection-and-inspection.md)                  |
| IPAM / Cloud WAN / Network Manager / accelerator | [Global networking](../content/AWS/networking/global-network-services.md)                                                                             |
| Object protection                                | [S3 protection/recovery](../content/AWS/storage/s3/protection-and-recovery.md)                                                                        |
| DLM                                              | [Expanded policy/restore lesson](../content/AWS/storage/ebs/amazon-data-lifecycle-manager.md)                                                         |
| CUR 2.0 / allocation                             | [Exports and locally checked SQL fixture](../content/AWS/cost-management/cost-usage-report.md), allocation/governance cost lessons                    |
| Database selection / operations                  | [Selection and restore/failover](../content/AWS/architecture/data-store-selection.md), corrected engine lessons                                       |
| Kafka / MSK                                      | [MSK guarantees](../content/AWS/analytics/msk.md)                                                                                                     |
| Managed analytics / BI                           | [Flink](../content/AWS/analytics/managed-flink.md), [lakehouse and BI](../content/AWS/analytics/lakehouse-and-bi.md), Redshift/Athena/Iceberg lessons |
| Bedrock production boundaries                    | Corrected [Bedrock](../content/AWS/machine-learning/bedrock/README.md); existing AI implementation retained                                           |
| SAP practice layer                               | All 20 task sheets, four domain indexes and [capstone](../content/AWS/solutions-architect-professional/index.md)                                      |
| WAF / Shield / Firewall Manager                  | [Protection and staged rollout](../content/AWS/networking/protection-and-inspection.md)                                                               |
| Optional specialist breadth                      | [Requirement-led specialist selection](../content/AWS/architecture/specialist-services.md); not an exhaustive course for every AWS product            |

## Verification boundaries and preservation

Many old notes contained intertwined fabricated API calls, speculative tariffs and unsupported absolute “gotchas.” Those sections were rewritten rather than retained beside contradicting corrections. Conceptual/service breadth, meaningful links and bounded tests remain; many pages are intentionally shorter. Original tracked versions can be recovered from Git. No note paths, user Obsidian files, framework behavior or package dependencies were removed.

No live AWS account/resource operations or purchases were performed. Guided exercises are not deployment-certified; an actual sandbox still needs approved identities, roles, connectivity, Region/service eligibility and budget. This is completion of the inventoried authoring/local-validation work, not an assertion that every possible AWS fact or deployment is certified.

No commits or pushes.

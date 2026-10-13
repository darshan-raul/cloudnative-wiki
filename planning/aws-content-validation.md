# AWS content validation — remaining findings

Date: 2026-10-12. **Initial review: 29 grouped defects and teaching gaps. Remediation is complete; all 29 findings are closed in the closure ledger below.** Earlier successful tests/builds did not establish content correctness or restoration completeness.

## Scope and method

Read all **181 current AWS note bodies**: the AWS root plus 180 notes below `content/AWS/`. Compare existing notes against Git HEAD, not the staged trimmed snapshot, for original topic coverage and relevant explanations/examples. Inspect prose, request/policy semantics, adjacent example compatibility, operational assumptions, prerequisites, expected evidence and cleanup. Check questionable consequential claims against owning AWS/engine documentation. Original code comparisons were targeted/sampled rather than an exhaustive live execution of every historical example.

Four review ledgers cover the collection without overlap: core 46, data/governance 50, cost/curriculum 46, operations 39. A filesystem-to-ledger reconciliation confirmed 181 unique covered paths, no missing paths and no duplicate assignments. This reconciliation checks coverage only; it does not certify the claims.

The review used parallel independent reviewers for the three specialist groups and a primary-agent core review. No content source was changed in this validation pass. Only review reports were written. No live AWS resources, authorization tests, failovers, billing experiments or deployments were used. No commits or pushes were made.

## Nine confirmed factual or example defects

| Finding | Affected note                                   | Required correction                                                                                         |
| ------- | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| DG01    | `databases/dynamodb/README.md:57`               | Same-PK logical collection does not guarantee permanent physical colocation; explain no-LSI split-for-heat. |
| DG02    | `databases/elasticache/README.md:67,87`         | Hash and string cache examples reuse one key and produce WRONGTYPE; separate type-aware keys.               |
| DG03    | `databases/neptune/README.md:67–80`             | Separate SPARQL update and query submissions; one combined fence is not one valid HTTP request.             |
| C1      | `cost-management/efs-cost-optimization.md:63`   | EFS lifecycle policy scope is the filesystem, not a prefix/application filter.                              |
| C2      | `cost-management/s3-cost-optimization.md:42`    | Distinguish RTC 99.99% design target from 99.9% monthly SLA credit threshold.                               |
| OPS-01  | `monitoring/cloudwatch-events/README.md:47`     | Restore valid inline-code daily cron expression.                                                            |
| OPS-02  | `application-integration/sqs/README.md:123–125` | Validate JSON body type before `.get`; non-object JSON must not crash the entire partial batch.             |
| OPS-03  | `serverless/api-gateway/README.md:60`           | Model sustained concurrency with reconnects, not individual 30-day WebSocket connections.                   |
| OPS-04  | `security/guardduty/README.md:3`                | Remove fabricated Enterprise tier from description, which contradicts the corrected body.                   |

Paths in this and the following section are relative to `content/AWS/`. Exact evidence, severity, source citations, confidence and proposed corrections are in the linked group reports. The nine-count groups concrete claim/example defects; it does not imply missing workflow configuration is harmless.

## Twenty restoration and teaching-workflow findings

These are separately classified: an outline may be conceptually accurate while still failing the promised learning-depth or reproducibility standard. Some findings affect several notes. Twenty is the number of grouped findings, not the number of affected files.

| Finding | Required addition or repair                                                                                               |
| ------- | ------------------------------------------------------------------------------------------------------------------------- |
| K1      | Auto Scaling group/scaling/refresh configuration, numeric version selection and cancellation versus rollback checkpoints. |
| K2      | Route 53's valid original DNS record types and health-check type distinctions, with corrected limits/behavior.            |
| K3      | ELB's original cross-zone and sticky-session explanations, supported overrides and operational trade-offs.                |
| K4      | IAM role-ARN versus role-session-ARN policy fixtures and worked outcomes.                                                 |
| K5      | First-session Lambda execution-role/logging prerequisites and creation handoff.                                           |
| K6      | Concrete CodeBuild artifact/buildspec and one CodePipeline deployment/rollback target.                                    |
| K7      | One resource-specific AWS Backup restore example with metadata and recovery checks.                                       |
| C3      | Supported Elastic Beanstalk deployment comparison lost alongside removal of retired OpsWorks advice.                      |
| DG04    | A complete bookmark-capable Glue job and repeat-run/duplicate-safe output evidence.                                       |
| DG05    | Lake Formation table fixture, real DataCellsFilter/grant wiring and two-principal result checks.                          |
| DG06    | A selected supported SageMaker training/evaluation/deployment example, not an unspecified repository root.                |
| DG07    | EMR's actual application/input/output fixture and matching bounded step submission.                                       |
| DG08    | One selected FSx product's concrete creation/client/mount/recovery walkthrough.                                           |
| DG09    | A valid selected Storage Gateway activation/share/client recipe and observable synchronization.                           |
| DG10    | A selected RDS engine's safe creation, TLS data fixture and failover/restore workflow.                                    |
| DG11    | Kinesis consumer/checkpoint/replay fixture and specified MSK/Flink experiments.                                           |
| DG12    | Valid original AI task examples and supported Lex V2/Kendra coverage, without reviving fabricated APIs.                   |
| DG13    | CDK cross-stack references/dependencies and accurate tooling comparison.                                                  |
| DG14    | Systems Manager command-result polling plus scoped session/parameter examples.                                            |
| DG15    | Selected RAM guardrail/share, BI RLS datasets and Canvas labelled-data workflows.                                         |

## Detailed evidence and coverage

- [Core: 46 notes](aws-content-review-core.md).
- [Data and governance: 50 notes](aws-content-review-data-governance.md).
- [Cost and SAP curriculum: 46 notes](aws-content-review-cost-curriculum.md).
- [Integration, migration, monitoring, security and serverless: 39 notes](aws-content-review-operations.md).

The reports also keep uncertainty separate: Macie cleanup wording, Timestream's reusable timestamp demonstration, supplied SAP drill inputs, SG test isolation, and omitted installation/per-engine examples are not silently counted as proven AWS API failures. Current Aurora encryption defaults, Lambda execution-mode limits, Organizations quotas, and service retirement/eligibility corrections were not reverted to obsolete originals.

## Status and follow-up

All 29 findings were open in the initial reviewed snapshot above. All 29 findings are now closed at content and example-contract level across the three closure ledgers below.

| Findings         | Current status                           | Closure evidence                                                                                             |
| ---------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| K1–K7            | Closed at content/example-contract level | [Core changes, sources, local extracted-fixture checks and independent review](aws-findings-closure-core.md) |
| OPS-01–04, C1–C3 | Closed at content/example-contract level | [Operations/cost corrections, mixed-batch fixture and sources](aws-findings-closure-operations-cost.md)      |
| DG01–DG15        | Closed at content/example-contract level | [Data and governance corrections, extracted fixtures and sources](aws-findings-closure-data-governance.md)   |

Macie cleanup, SG isolation, SAP supplied inputs/gross-versus-net accounting, Timestream identity reuse and CLI installation/completion followups are recorded separately in the operations/cost closure report. They are not silently counted as additional numbered findings.

Inventory completion is not remediation completion. Re-read changed bodies and verify each worked example's inputs, outputs, permissions, dependencies and cleanup. Site tests/builds are supplementary checks, not acceptance evidence for these semantic findings. No paid AWS deployments or live authorization/recovery outcomes are claimed by documentation closure.

This report supersedes any interpretation of the earlier restoration/build reports as a blanket content-quality sign-off. It does not claim every sentence or deployment configuration in the collection has been independently source-certified.

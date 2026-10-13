# AWS operations remediation progress

Updated: 2026-10-12. Scope is 33 existing notes under security, migration, monitoring and application-integration; excluded root-owned IAM additions/external-ID lesson, SMS archive and tracing additions. No commits, pushes, live AWS calls or deployed resources.

## Resolved inventory

| Audit group                                                       | Disposition                                                                                                                                                                                                                                                                                                                                  |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M01–M12 plus monitoring contract/teaching queue                   | Replaced wrong retention, namespaces, API shapes, timestamp/query functions, missing-data semantics, Live Tail and cost units. Added metric/log/query/alarm/dashboard fixtures, bounded polling, retention, cardinality, notification tests, cleanup and canonical EventBridge pointer.                                                      |
| I01–I09 plus integration queue                                    | Fixed SNS retry behavior, SQS payload/FIFO/concurrency, AppSync pricing/filtering, EventBridge routing/archive and Express duration. Added queue redelivery/idempotency, topic-scoped delivery policy, event fixture/pattern/target-policy workflow, complete ASL and AppSync NONE resolver lab.                                             |
| R01–R08, R14 and scoped pending security/migration claims         | Replaced certificate issuance/export/renewal/CA rates, CloudTrail coverage/integrity/delivery, Config costs/scope/aggregation, Secrets promotion/rotation, Macie scores, MGN staging/network/cutover, Detective rates/arithmetic. Main owns remaining R-series serverless/compute/database claims.                                           |
| S26–S27, S29–S32                                                  | Removed fictional MGN/DMS contracts and IAM/STS pricing; corrected role lifecycle, policy validation and linked canonical Identity Center lesson rather than preserving broken permission-set requests.                                                                                                                                      |
| N29/N31 and C08–C11 (owned-path portions)                         | Corrected Inspector trials/Inspector2/ECR APIs and KMS create-key policy flag/math; eliminated mixed-language/commented-JSON failures in owned notes.                                                                                                                                                                                        |
| Source decisions D02–D19, D33–D37, D49–D54, D59 (scoped portions) | Applied eligibility/retirement, collector distinctions, agent requirements, transfer/endpoint schemas, security product boundaries and source-linked current behavior. Retained only supported exact values; unsupported universal quotas/tariffs/installers/tuning snippets were removed or replaced by explicit owning-contract workflows. |

## Note coverage

Each note below has required frontmatter, hierarchical tags, at least one H1, primary references and a scoped learning/exercise/failure/cleanup path (hubs provide learning sequence and decision boundaries). Useful cross-wiki links were preserved; dense unsourced tables and contradictory instructions were not carried forward.

- [monitoring/README.md](../content/AWS/monitoring/README.md)
- [monitoring/cloudwatch-metrics/README.md](../content/AWS/monitoring/cloudwatch-metrics/README.md)
- [monitoring/cloudwatch-logs/README.md](../content/AWS/monitoring/cloudwatch-logs/README.md)
- [monitoring/cloudwatch-insights/README.md](../content/AWS/monitoring/cloudwatch-insights/README.md)
- [monitoring/cloudwatch-alarms/README.md](../content/AWS/monitoring/cloudwatch-alarms/README.md)
- [monitoring/cloudwatch-dashboards/README.md](../content/AWS/monitoring/cloudwatch-dashboards/README.md)
- [monitoring/cloudwatch-events/README.md](../content/AWS/monitoring/cloudwatch-events/README.md)
- [application-integration/README.md](../content/AWS/application-integration/README.md)
- [application-integration/sqs/README.md](../content/AWS/application-integration/sqs/README.md)
- [application-integration/sns/README.md](../content/AWS/application-integration/sns/README.md)
- [application-integration/eventbridge/README.md](../content/AWS/application-integration/eventbridge/README.md)
- [application-integration/step-functions/README.md](../content/AWS/application-integration/step-functions/README.md)
- [application-integration/amazon-mq/README.md](../content/AWS/application-integration/amazon-mq/README.md)
- [application-integration/appsync/README.md](../content/AWS/application-integration/appsync/README.md)
- [security/README.md](../content/AWS/security/README.md)
- [security/iam/README.md](../content/AWS/security/iam/README.md)
- [security/iam/various-types-of-roles.md](../content/AWS/security/iam/various-types-of-roles.md)
- [security/kms/README.md](../content/AWS/security/kms/README.md)
- [security/inspector/README.md](../content/AWS/security/inspector/README.md)
- [security/certificate-manager/README.md](../content/AWS/security/certificate-manager/README.md)
- [security/cloudtrail/README.md](../content/AWS/security/cloudtrail/README.md)
- [security/config/README.md](../content/AWS/security/config/README.md)
- [security/guardduty/README.md](../content/AWS/security/guardduty/README.md)
- [security/macie/README.md](../content/AWS/security/macie/README.md)
- [security/secrets-manager/README.md](../content/AWS/security/secrets-manager/README.md)
- [security/security-hub/README.md](../content/AWS/security/security-hub/README.md)
- [security/detective/README.md](../content/AWS/security/detective/README.md)
- [migration/README.md](../content/AWS/migration/README.md)
- [migration/application-discovery-service/README.md](../content/AWS/migration/application-discovery-service/README.md)
- [migration/migration-evaluator/README.md](../content/AWS/migration/migration-evaluator/README.md)
- [migration/application-migration-service/README.md](../content/AWS/migration/application-migration-service/README.md)
- [migration/datasync/README.md](../content/AWS/migration/datasync/README.md)
- [migration/dms/README.md](../content/AWS/migration/dms/README.md)

## Verification

- Prettier formatted all 33 owned notes successfully.
- Local AWS CLI input skeletons confirmed KMS Policy, MGN sourceServerIDs, DMS PostgreSQLSettings, Inspector2 filterCriteria, ECR scanType/rules and Lambda ScalingConfig field names. Skeleton generation is offline and does not make resource calls.
- Corpus fenced JSON/Python/shell audit currently checks 115 blocks with **zero parse failures**. This is syntax validation, not deployment certification. JavaScript/AppSync snippets are formatted/parsed by Prettier.
- Read-only URL check covered 150 unique AWS URLs across these four groups (including root-owned additions). One new business-case URL returned 404 and was replaced with the already validated owning Migration Evaluator capability page. All retained checked endpoints resolved; an HTTP response alone does not certify every associated claim.
- AWS content validator currently reports **no errors in these 33 owned notes**. Other writers’ directory links/new-note navigation are root-owned and were reported to root for its global integration pass.
- No snippets were executed against AWS; all deployment instructions explicitly require isolated resources, permissions, expected evidence, negative tests and cleanup. Existing Obsidian changes were untouched.

## Remaining boundaries

No scoped confirmed audit finding or retained unsupported claim remains knowingly unresolved. CloudWatch subscription-filter documentation conflicts remain explicitly documented as an account/Region quota preflight, not disguised as a certified universal number. Regional pricing/quotas/version matrices are intentionally source-linked and scoped rather than exhaustive permanent tables. Real deployment and client failover/rotation testing require an authorized sandbox/budget and are not claimed as performed.

# AWS data, ML and governance remediation

Completed 2026-10-12. Scope is **42 existing notes**: storage 7 (main-owned DLM excluded), databases 9 (main-owned QLDB excluded), analytics 10 (main-owned retired SQL excluded), machine learning 7 and governance 9. Main owns all new lesson paths and global navigation/build validation.

## Resolution

All scoped lessons and hubs are applied. Service boundaries, useful conceptual breadth, source-linked API contracts, controlled authorization/failure/recovery exercises, cleanup, current product modes and cost arithmetic replace fabricated executable snippets, unsourced quota tables and obsolete regional-price scenarios.

The high density of invalid snippets required consolidation rather than cosmetic amendments: unsupported examples were removed under the source-decisions' explicit editorial disposition. Their removal does **not** assert that research proved each suspected claim false. Canonical database Redshift now links to the analytical implementation instead of maintaining duplicate SQL.

Scoped confirmed findings resolved: S01–S05 (current hub references, LiveAnalytics, Firehose and Edge Manager); S08–S16; S25; S28; S38–S107; S109–S112. Each ID is scoped to occurrences in the owned notes. Cost/security/migration occurrences and the protected retirement/DLM pages are owned by the main/other editing agents.

Source decisions applied: D20–D32, D44–D48, D58, D59 (scoped Lake Formation/Rekognition/SageMaker feature retirements), and the residual scoped regional quota/price, EMR/OpenSearch and SageMaker broken-example dispositions. No unverified numerical table is represented as certified.

Added/updated coverage includes Redshift Serverless/Iceberg/BI; Neptune openCypher, Analytics and ML; ElastiCache Valkey/Serverless dimensions; current KCL; Glue bookmark/crawler/registry contracts; LF hybrid/data-filter authorization; Bedrock lifecycle/retention; Canvas production eligibility; SSM hybrid billing/patch policies. Hubs link main-owned Flink/MSK, foundations, datastore selection, backup/recovery and S3 safety lessons.

## Validation

- Prettier check passed for all 42 owned notes and this tracker.
- Scoped primary URLs: 188 unique links. Initial check gave 187 HTTP 200 and one storage-guide HTTP 403 after GET retry. Replaced that unavailable guide link with the owning AWS storage overview, separately verified HTTP 200; all retained scoped URLs resolved in this check.
- Whole-AWS snippet audit after application: 70 JSON/Python/shell blocks, **zero parse failures**. Snippets were parsed, not executed against AWS.
- Scoped notes have no structural/content-validator findings after fixing two nonexistent concepts hub links. At this point global validation still reported 51 directory-link errors in main/other-agent pages; root owns reconciliation.
- Corrected schema qualification in the Redshift late-binding view example.
- No AWS deployment/live-account operation performed. Exercises have prerequisites/expected observations/cleanup but are not claimed to have been deployed.
- No commits/pushes and no Obsidian changes.

## Per-note closure

| Owned note                                                                                                                      | Original confirmed findings or curriculum work | Closure                                                      |
| ------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------ |
| [analytics/README.md](../content/AWS/analytics/README.md)                                                                       | S01                                            | Applied; formatted; sources resolve; no scoped content error |
| [analytics/athena/README.md](../content/AWS/analytics/athena/README.md)                                                         | S91                                            | Applied; formatted; sources resolve; no scoped content error |
| [analytics/emr/README.md](../content/AWS/analytics/emr/README.md)                                                               | S92                                            | Applied; formatted; sources resolve; no scoped content error |
| [analytics/glue/README.md](../content/AWS/analytics/glue/README.md)                                                             | S93, S94, S95                                  | Applied; formatted; sources resolve; no scoped content error |
| [analytics/kinesis/README.md](../content/AWS/analytics/kinesis/README.md)                                                       | S109, S110                                     | Applied; formatted; sources resolve; no scoped content error |
| [analytics/kinesis/data-firehose.md](../content/AWS/analytics/kinesis/data-firehose.md)                                         | S04, S14, S15, S16, S110                       | Applied; formatted; sources resolve; no scoped content error |
| [analytics/kinesis/data-streams.md](../content/AWS/analytics/kinesis/data-streams.md)                                           | S99, S100                                      | Applied; formatted; sources resolve; no scoped content error |
| [analytics/lake-formation/README.md](../content/AWS/analytics/lake-formation/README.md)                                         | S96, S97                                       | Applied; formatted; sources resolve; no scoped content error |
| [analytics/opensearch/README.md](../content/AWS/analytics/opensearch/README.md)                                                 | S98                                            | Applied; formatted; sources resolve; no scoped content error |
| [analytics/redshift/README.md](../content/AWS/analytics/redshift/README.md)                                                     | S111                                           | Applied; formatted; sources resolve; no scoped content error |
| [databases/README.md](../content/AWS/databases/README.md)                                                                       | S02, S03, S112                                 | Applied; formatted; sources resolve; no scoped content error |
| [databases/aurora/README.md](../content/AWS/databases/aurora/README.md)                                                         | S58, S88, S89, S90                             | Applied; formatted; sources resolve; no scoped content error |
| [databases/documentdb/README.md](../content/AWS/databases/documentdb/README.md)                                                 | S61, S62                                       | Applied; formatted; sources resolve; no scoped content error |
| [databases/dynamodb/README.md](../content/AWS/databases/dynamodb/README.md)                                                     | S59, S60                                       | Applied; formatted; sources resolve; no scoped content error |
| [databases/elasticache/README.md](../content/AWS/databases/elasticache/README.md)                                               | S65, S66                                       | Applied; formatted; sources resolve; no scoped content error |
| [databases/neptune/README.md](../content/AWS/databases/neptune/README.md)                                                       | S63, S64                                       | Applied; formatted; sources resolve; no scoped content error |
| [databases/rds/README.md](../content/AWS/databases/rds/README.md)                                                               | S56, S57, S80                                  | Applied; formatted; sources resolve; no scoped content error |
| [databases/redshift/README.md](../content/AWS/databases/redshift/README.md)                                                     | S76, S77, S78, S79                             | Applied; formatted; sources resolve; no scoped content error |
| [databases/timestream/README.md](../content/AWS/databases/timestream/README.md)                                                 | S03, S08, S09, S10, S11, S12, S13              | Applied; formatted; sources resolve; no scoped content error |
| [machine-learning/README.md](../content/AWS/machine-learning/README.md)                                                         | Section learning path / links / references     | Applied; formatted; sources resolve; no scoped content error |
| [machine-learning/ai-services/README.md](../content/AWS/machine-learning/ai-services/README.md)                                 | S28, S101, S102                                | Applied; formatted; sources resolve; no scoped content error |
| [machine-learning/bedrock/README.md](../content/AWS/machine-learning/bedrock/README.md)                                         | S104, S105                                     | Applied; formatted; sources resolve; no scoped content error |
| [machine-learning/comprehend/README.md](../content/AWS/machine-learning/comprehend/README.md)                                   | S28, S101, S107                                | Applied; formatted; sources resolve; no scoped content error |
| [machine-learning/rekognition/README.md](../content/AWS/machine-learning/rekognition/README.md)                                 | S107                                           | Applied; formatted; sources resolve; no scoped content error |
| [machine-learning/sagemaker-canvas/README.md](../content/AWS/machine-learning/sagemaker-canvas/README.md)                       | S25, S106                                      | Applied; formatted; sources resolve; no scoped content error |
| [machine-learning/sagemaker/README.md](../content/AWS/machine-learning/sagemaker/README.md)                                     | S05, S103                                      | Applied; formatted; sources resolve; no scoped content error |
| [management-governance/README.md](../content/AWS/management-governance/README.md)                                               | S70                                            | Applied; formatted; sources resolve; no scoped content error |
| [management-governance/cdk/README.md](../content/AWS/management-governance/cdk/README.md)                                       | S73                                            | Applied; formatted; sources resolve; no scoped content error |
| [management-governance/cli/README.md](../content/AWS/management-governance/cli/README.md)                                       | S74                                            | Applied; formatted; sources resolve; no scoped content error |
| [management-governance/cloudformation/README.md](../content/AWS/management-governance/cloudformation/README.md)                 | S70, S71, S72                                  | Applied; formatted; sources resolve; no scoped content error |
| [management-governance/control-tower/README.md](../content/AWS/management-governance/control-tower/README.md)                   | S69, S82                                       | Applied; formatted; sources resolve; no scoped content error |
| [management-governance/organizations/README.md](../content/AWS/management-governance/organizations/README.md)                   | S67, S68, S81                                  | Applied; formatted; sources resolve; no scoped content error |
| [management-governance/organizations/delegated-admin.md](../content/AWS/management-governance/organizations/delegated-admin.md) | S68                                            | Applied; formatted; sources resolve; no scoped content error |
| [management-governance/systems-manager/README.md](../content/AWS/management-governance/systems-manager/README.md)               | S75, S83, S84, S86                             | Applied; formatted; sources resolve; no scoped content error |
| [management-governance/systems-manager/patch-manager.md](../content/AWS/management-governance/systems-manager/patch-manager.md) | S85, S86, S87                                  | Applied; formatted; sources resolve; no scoped content error |
| [storage/README.md](../content/AWS/storage/README.md)                                                                           | S54                                            | Applied; formatted; sources resolve; no scoped content error |
| [storage/ebs/README.md](../content/AWS/storage/ebs/README.md)                                                                   | S46, S47, S48                                  | Applied; formatted; sources resolve; no scoped content error |
| [storage/efs/README.md](../content/AWS/storage/efs/README.md)                                                                   | S49, S50, S51                                  | Applied; formatted; sources resolve; no scoped content error |
| [storage/fsx/README.md](../content/AWS/storage/fsx/README.md)                                                                   | S52, S53                                       | Applied; formatted; sources resolve; no scoped content error |
| [storage/glacier/README.md](../content/AWS/storage/glacier/README.md)                                                           | S40, S43, S44, S45                             | Applied; formatted; sources resolve; no scoped content error |
| [storage/s3/README.md](../content/AWS/storage/s3/README.md)                                                                     | S38, S39, S40, S41, S42                        | Applied; formatted; sources resolve; no scoped content error |
| [storage/storage-gateway/README.md](../content/AWS/storage/storage-gateway/README.md)                                           | S54, S55                                       | Applied; formatted; sources resolve; no scoped content error |

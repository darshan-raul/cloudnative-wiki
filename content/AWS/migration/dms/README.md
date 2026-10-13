---
title: Database Migration Service (DMS)
description: AWS DMS — database migration types (full load, CDC, full+CDC), endpoint configuration, replication instance sizing, schema conversion with SCT, and best practices
tags:
  - aws/migration
date: 2026-10-12
---

# Database Migration Service (DMS)

Prerequisites: [[AWS/security/iam/README|temporary-credential IAM roles]], [[AWS/networking/vpc/README|VPC routing]] and the [[AWS/migration/README|migration acceptance/rollback plan]].

DMS migrates supported database data using engine-specific endpoints and replication tasks. Full load plus change data capture (CDC) can reduce downtime, but correct cutover depends on source logging, schema and validation.

## Architecture and prerequisites

Provisioned replication instances and DMS Serverless are distinct capacity/billing models. Endpoint secrets belong in the documented engine-specific settings (for example SecretsManagerSecretId/SecretsManagerAccessRoleArn), not fictional top-level --secrets-manager-arn or --rds-settings flags.

Schema conversion is separate from moving rows; do not promise all indexes, procedures, permissions or application semantics migrate automatically. DMS Fleet Advisor retired May 20, 2026; core migration remains a different service capability.

For PostgreSQL CDC validate logical replication permissions, slots and WAL retention; for other engines use their actual prerequisite guide. Monitor retained logs/backlog against source disk capacity. Oracle capture methods are documented engine choices, not an invented AWS XDB reader.

S3 targets use supported CSV or Parquet—not ORC. LOB modes, primary/unique keys, DDL handling and target table preparation require deliberate task settings.

## Rehearsed migration lab

1. Create disposable source/target databases with the intended engine versions. Insert fixtures including nullable values, updates/deletes, keys and representative LOBs.
2. Configure network/TLS and least-privilege source/target credentials. Create documented endpoints and test each connection before starting the task.
3. Create a full-load-and-CDC task with explicit table mappings and supported task settings. Enable supported validation deliberately; save configuration under review.
4. Wait for full-load completion, make source updates/deletes and observe CDC catch-up. Inspect CDCLatencySource/Target and task/table errors; row count alone is not correctness.
5. Compare checksums or business invariants, constraints, null/encoding/LOB behavior and application transactions. Test a source logging/permission failure and confirm the runbook detects blocked replication.
6. Freeze source writes at cutover, meet the agreed lag/validation threshold, switch the application and retain a bounded rollback plan. Reconcile target-only writes before rolling back.
7. Stop/delete the disposable task and remove replication capacity/endpoints/databases after acceptance. Stopping a task does not necessarily stop provisioned-instance billing; do not invent stop-replication-instance.

## Cost and tuning

Provisioned capacity is charged for running hours, not a mandatory whole month for a two-week migration. Serverless meters its own replication-capacity model; Database Savings Plans are a separate discount commitment. T3 burst CPU credits are compute capacity, not CDC backlog credits.

Use documented tuning settings for the selected engine/task and load-test them. Include replication storage, source log retention, transfer, validation overhead and overlapping databases in the budget.

## Migration modes and engine capture model

| Mode            | Data flow                             | Application boundary                                        |
| --------------- | ------------------------------------- | ----------------------------------------------------------- |
| Full load       | Existing selected rows to target      | Writes during/after load need another catch-up method       |
| CDC only        | Supported source log positions onward | Existing target state and log retention must be established |
| Full load + CDC | Load plus buffered/ongoing changes    | Validate consistency and quiesce source for final switch    |

```text
source engine + retained change logs → DMS replication capacity
          │                              ├─ mappings/settings
          │                              ├─ full-load/CDC state
          │                              └─ target endpoint → application validation
          └─ log-retention/backlog pressure ── monitoring/runbook
```

MySQL CDC uses documented binlog configuration/permissions; PostgreSQL uses logical replication/slots/WAL; Oracle uses supported redo capture methods with prerequisites. Source log settings and required privileges differ by engine/version/managed source. Burstable CPU credits do not represent CDC change credits.

## Endpoint and replication-capacity walkthrough

Use protected Secrets Manager credentials and the engine-specific endpoint structure. First obtain and verify the source database's trusted CA chain, import it into DMS with the documented import-certificate workflow and record its returned DMS CertificateArn (not an ACM certificate ARN). Confirm the source hostname matches the certificate for MySQL verify-full mode. Save source-endpoint.json after substituting real sandbox secret/access-role and imported-certificate values:

```json
{
  "EndpointIdentifier": "wiki-source",
  "EndpointType": "source",
  "EngineName": "mysql",
  "SslMode": "verify-full",
  "CertificateArn": "DMS_IMPORTED_CA_CERTIFICATE_ARN",
  "MySQLSettings": {
    "SecretsManagerSecretId": "SOURCE_SECRET_ARN",
    "SecretsManagerAccessRoleArn": "DMS_SECRET_ACCESS_ROLE_ARN"
  }
}
```

```bash
aws dms create-endpoint --cli-input-json file://source-endpoint.json
aws dms describe-orderable-replication-instances
```

The access role must trust the documented DMS principal and read only that secret/key. Secret schema/endpoint and TLS-mode support are engine-specific. For this MySQL source, verify-full validates the trusted certificate and hostname; do not silently fall back to none or the unsupported MySQL require mode. A target PostgreSQL secret uses PostgreSQLSettings and its own supported certificate/TLS configuration, not a universal RdsSettings or top-level secrets-manager-arn flag.

Select an available instance class, private subnet group and SGs. Save a complete provisioned-capacity request with placeholders replaced:

```json
{
  "ReplicationInstanceIdentifier": "wiki-dms-lab",
  "ReplicationInstanceClass": "REPLACE_WITH_SUPPORTED_CLASS",
  "AllocatedStorage": 50,
  "ReplicationSubnetGroupIdentifier": "LAB_SUBNET_GROUP",
  "VpcSecurityGroupIds": ["LAB_SECURITY_GROUP_ID"],
  "PubliclyAccessible": false
}
```

Create through create-replication-instance --cli-input-json and wait for availability. Test both endpoints using test-connection with their returned ARNs and the instance ARN; inspect describe-connections. Passing endpoint tests does not validate schema or every table permission.

## Table mappings and task creation

Save mappings.json, replacing the exact schema/table:

```json
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "orders-only",
      "object-locator": { "schema-name": "labdb", "table-name": "orders" },
      "rule-action": "include"
    }
  ]
}
```

Save settings.json for an engine/task combination supporting validation:

```json
{
  "ValidationSettings": { "EnableValidation": true },
  "FullLoadSettings": { "TargetTablePrepMode": "DO_NOTHING" }
}
```

DO_NOTHING assumes the intended compatible target table already exists; it does not create all constraints/indexes. Choosing DROP_AND_CREATE/TRUNCATE changes target data destructively and requires explicit authorization.

```bash
aws dms create-replication-task --replication-task-identifier wiki-orders \
  --source-endpoint-arn SOURCE_ENDPOINT_ARN --target-endpoint-arn TARGET_ENDPOINT_ARN \
  --replication-instance-arn REPLICATION_INSTANCE_ARN \
  --migration-type full-load-and-cdc \
  --table-mappings file://mappings.json --replication-task-settings file://settings.json
aws dms start-replication-task --replication-task-arn TASK_ARN \
  --start-replication-task-type start-replication
aws dms describe-table-statistics --replication-task-arn TASK_ARN
```

Starting/resuming/reloading are different lifecycle choices; don't reload a live target to “fix” an unknown error. Validate new/mutated/deleted fixture records and supported LOB settings. Check actual ValidationState/error statistics and engine restrictions.

## Monitoring, tuning and diagnosis

| Symptom             | Inspect first                                            | Safe response                                                  |
| ------------------- | -------------------------------------------------------- | -------------------------------------------------------------- |
| Source lag          | Source logging/capture permissions and resource pressure | Repair capture; protect source log retention/storage           |
| Target lag          | Target write/index/locking/throughput and task resources | Measure bottleneck, then adjust documented settings/capacity   |
| Table failed        | Task/table logs, keys/types/LOB/mapping and permissions  | Correct in sandbox; define reload/reconciliation scope         |
| Source disk growth  | Replication slots/WAL/binlogs retained behind capture    | Restore processing or apply reviewed retention actions         |
| Validation mismatch | Actual values/updates/deletes and known exclusions       | Investigate business invariants; counts alone are insufficient |

Use documented metrics such as CDCLatencySource, CDCLatencyTarget and task/table statistics with their actual namespace/dimensions; verify each metric name and tuning key in the selected engine/task contract. Parallel load, batch apply and LOB mode have correctness/engine trade-offs, not a universal increase-threads recipe.

## Data lake target and cleanup

S3 endpoint settings select supported CSV/Parquet, prefix/date partitioning/compression and role permissions. That does not perform arbitrary analytics-schema conversion or produce ORC. Reconcile schema, nulls, ordering/CDC delete representation and downstream table interpretation.

Stop/delete only the lab task, wait for dependency cleanup, remove dedicated endpoints/replication capacity/subnet group/logs and source/target fixtures after approval. Protect source slots/log cleanup and secrets; deleting a task does not necessarily remove every source-side retained log or paid instance.

References: [endpoint contract](https://docs.aws.amazon.com/cli/latest/reference/dms/create-endpoint.html), [task settings](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TaskSettings.html), [table mappings](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TableMapping.html), [monitoring](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Monitoring.html), [validation](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Validating.html).

## References

- [DMS TLS modes and engine matrix](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.SSL.html).
- [Import a DMS certificate](https://docs.aws.amazon.com/cli/latest/reference/dms/import-certificate.html).

- [DMS guide](https://docs.aws.amazon.com/dms/latest/userguide/Welcome.html)
- [Endpoint contract](https://docs.aws.amazon.com/cli/latest/reference/dms/create-endpoint.html)
- [PostgreSQL prerequisites](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.PostgreSQL.html)
- [S3 target formats](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.S3.html)
- [Validation](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Validating.html)
- [Feature retirements](https://docs.aws.amazon.com/general/latest/gr/full_shutdown_services.html)
- [Pricing](https://aws.amazon.com/dms/pricing/)

## Across the wiki

- [[Architecture/solution-architecture-concepts/migration-patterns/README|Migration Patterns]]
- [[Architecture/solution-architecture-concepts/migration-patterns/data-migration|Data Migration Patterns]]
- [[Architecture/solution-architecture-concepts/migration-patterns/change-data-capture|Change Data Capture (CDC)]]
- [[Architecture/solution-architecture-concepts/migration-patterns/strangler-fig|Strangler Fig Pattern]]

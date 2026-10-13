# AWS depth restoration: final semantic review

Reviewed 2026-10-12. Read all prose and snippets in the saved working versions of Athena, Glue, DMS, DataSync, CloudTrail and Secrets Manager. Checked owning contracts and the existing source decisions. Content remained read-only; no AWS calls or deployments were performed. Line numbers below identify the review snapshot and can shift during other agents' edits.

Resolution: the main agent reviewed the saved corrections for R1–R4. Secrets Manager now distinguishes single-user backend authentication from label state; DataSync describes transfer versus final verification; Glue separates native Condition fields from EventBridge events; DMS explicitly uses verify-full and an imported DMS CA certificate. D06 in the source-decision report was also corrected. The findings below preserve the evidence that prompted those changes.

## Findings requiring correction

### R1 — Secrets Manager single-user rotation does not preserve old-password usability

**Evidence:** `content/AWS/security/secrets-manager/README.md:32`, `:38` and `:107` say to maintain current credentials until tests pass, confirm AWSCURRENT remains usable on a pending-test failure, and keep current usable in testSecret.

**Problem:** In single-user rotation, setSecret changes the backend password before finishSecret updates the current stage. New connections using the old AWSCURRENT credential can fail during that window; a testSecret failure can leave backend and current-labelled secret out of sync. Keeping the label unchanged is not proof that the old credential still authenticates.

**Replacement:** Distinguish strategies. Alternating-user rotation can retain valid current credentials while the other user is updated, with its own permission/propagation requirements. For single-user rotation, describe retry/cache refresh and explicit reconciliation/recovery after setSecret succeeds but testing/finalization fails. Do not promise universal uninterrupted current-credential validity.

Primary source: [Rotation strategies and denial window](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotation-strategy.html), [four-stage safeguards](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_lambda-functions.html). Confidence: high. Priority: P1 workflow/recovery correctness.

### R2 — DataSync NONE skips final verification, not all integrity checks

**Evidence:** `content/AWS/migration/datasync/README.md:23` says NONE disables integrity verification.

**Replacement:** VerifyMode NONE still performs integrity checks during transfer; it skips additional end-of-transfer verification. Keep the correct separation from TransferMode/change comparison. The earlier D06 wording also needs this nuance if reused.

Primary source: [Options: VerifyMode NONE](https://docs.aws.amazon.com/datasync/latest/apireference/API_Options.html). Confidence: high. Priority: P2 incorrect verification contract.

### R3 — Glue native conditional-trigger fields are conflated with EventBridge event patterns

**Evidence:** `content/AWS/analytics/glue/README.md:24` states crawler-state EventBridge patterns use CrawlerName/CrawlState instead of JobName/State.

**Problem/replacement:** CrawlerName/CrawlState and JobName/State are fields of Glue's native trigger **Condition** object. Do not describe that API schema as an EventBridge event-detail schema. Explain native conditional triggers separately from EventBridge rules. For an EventBridge rule, select the documented source/detail-type and actual captured/owning event-detail contract; crawler event status names also differ from the native trigger enums. Do not invent an exact replacement payload without verifying that event type.

Primary source: [Glue Condition contract](https://docs.aws.amazon.com/glue/latest/webapi/API_Condition.html), [Glue EventBridge event types/states](https://docs.aws.amazon.com/glue/latest/dg/automating-awsglue-with-cloudwatch-events.html). Confidence: high for the schema conflation; no unverified exact EventBridge payload is proposed. Priority: P2 automation that would not match the intended events.

### R4 — DMS endpoint example silently uses no database TLS

**Evidence:** `content/AWS/migration/dms/README.md:28` requires network/TLS setup, but the executable source endpoint JSON at `:65–73` omits SslMode.

**Problem/replacement:** CreateEndpoint defaults SslMode to none. Reading a credential from Secrets Manager does not encrypt the database connection. Add an explicit supported source-engine SSL mode and required imported certificate/CA settings, or clearly label this synthetic endpoint as intentionally non-TLS rather than presenting it as the TLS lab implementation. The current MySQL matrix supports verify-ca/verify-full with the certificate configuration; require is not supported. A suitable reviewed example can specify SslMode=verify-full and the actual imported CertificateArn, then test the endpoint.

Primary source: [CreateEndpoint SslMode default](https://docs.aws.amazon.com/cli/latest/reference/dms/create-endpoint.html), [DMS SSL mode/engine matrix](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.SSL.html). Confidence: high. Priority: P2 security/workflow contradiction.

## Coverage and checks without additional findings

| Note            | Checks performed                                                                                                                                                                                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Athena          | CTAS SELECT/output behavior; external CSV/Parquet definitions; partition declaration/addition/query; empty output/location and schema prerequisites; archive/connector boundaries. No additional invalid API/SQL contract identified in the scoped examples.       |
| Glue            | DatabaseInput/CreateTable/StorageDescriptor/SerDe fields; headerless CSV assumption; actual month grouping; bookmark/init/commit/idempotency caveats. SDK and local transformation examples otherwise remain scoped correctly.                                     |
| DMS             | MySQLSettings secret fields, provisioned instance request, selection mappings, ValidationSettings/TargetTablePrepMode, task create/start/statistics operations; source-write fence and retention/cleanup. No fictional stop-replication-instance was reintroduced. |
| DataSync        | NFS/S3 location request shapes; valid task options and Atime/Mtime pairing; execution status; update-task filter/schedule and byte units. No unsupported hourly bandwidth array or ETL conversion claim was reintroduced.                                          |
| CloudTrail      | create/start/status/selectors, event lookup and validate-logs commands; bucket/key/logging prerequisites, delivered digest versus validated evidence, delayed delivery and cleanup boundaries. No additional contract contradiction identified.                    |
| Secrets Manager | GetSecretValue string schema versus binary behavior; version inspection, replica request and four-stage token/stage model. R1 concerns backend validity, not an invalid SDK retrieval field.                                                                       |

Supporting contracts checked: [CreateTable](https://docs.aws.amazon.com/boto3/latest/reference/services/glue/client/create_table.html), [DataSync CreateTask](https://docs.aws.amazon.com/cli/latest/reference/datasync/create-task.html), [DataSync UpdateTask](https://docs.aws.amazon.com/cli/latest/reference/datasync/update-task.html), [CloudTrail CreateTrail](https://docs.aws.amazon.com/cli/latest/reference/cloudtrail/create-trail.html), [CloudTrail ValidateLogs](https://docs.aws.amazon.com/cli/latest/reference/cloudtrail/validate-logs.html). This is a source/semantic spot-check, not execution certification, exhaustive engine testing or a finding-free security assessment.

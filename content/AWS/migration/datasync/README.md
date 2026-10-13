---
title: DataSync
description: AWS DataSync — managed file transfer between on-premises storage and AWS (S3, EFS, FSx), agent deployment, task scheduling, and bandwidth throttling
tags:
  - aws/migration
date: 2026-10-12
---

# DataSync

Prerequisites: [[AWS/security/iam/README|temporary-credential IAM roles]], [[AWS/networking/vpc/README|VPC routing]] and the [[AWS/migration/README|migration acceptance/rollback plan]].

DataSync transfers supported file/object data with configurable metadata and integrity verification. It is not an ETL service and does not convert arbitrary file formats.

## Modes and agents

Basic and Enhanced mode have different location support, scaling, verification and pricing. Some transfers need an agent; supported AWS-to-AWS paths can differ. DataSync Discovery was retired May 20, 2025; that does not retire DataSync transfer.

For non-EC2 Basic-mode VM agents current guidance is four vCPU, 80 GB disk and 32 GB RAM up to twenty million entries (64 GB above). Enhanced VM guidance is eight vCPU, 80 GB disk and 32 GB RAM. EC2 requirements are separately documented; four CPU/eight GB is not a universal minimum.

## Options and contracts

Uid/Gid use INT_VALUE where supported. VerifyMode is ONLY_FILES_TRANSFERRED, POINT_IN_TIME_CONSISTENT or NONE; OverwriteMode is a separate option. NONE skips additional end-of-transfer verification; integrity checks during transfer still occur. It does not fix same-size or timestamp change detection. TransferMode ALL explicitly bypasses change comparison.

For Basic mode, Atime NONE requires Mtime NONE; preserving Mtime requires Atime BEST_EFFORT. Enhanced mode has different option support. Set BytesPerSecond in task options, not a fabricated hourly --bandwidth array. External scheduling can update a supported bandwidth limit.

SMB locations use agent-arns and user/domain/password fields, not NFS on-prem-config. EFS locations need filesystem ARN plus subnet/security-group ARNs. FSx Windows needs its filesystem/security groups and documented credentials—not security-connector-arn.

## End-to-end sandbox

1. Prepare a disposable supported source directory and a private destination bucket/filesystem. Create a fixture with known bytes, sizes and checksums, plus one nested file. Grant only source read/destination write and required KMS access.
2. Follow the current console agent/location workflow for your mode. Store SMB credentials securely rather than in shell history. Validate task connectivity before copying.
3. Create a task with explicit metadata/overwrite/verification settings. Start it and wait for its terminal status; inspect counts, skipped files, verification errors and CloudWatch task evidence.
4. Verify fixture bytes/checksums at the destination. Change a file while preserving its size; test actual comparison behavior. Use TransferMode ALL where the intended workflow must copy independently of metadata comparison, not VerifyMode NONE.
5. Test an inaccessible fixture and confirm failure reporting. Decide whether to retry, correct permission or exclude it—never call partial transfer complete.
6. Delete the disposable task/locations/agent and target data only after validation. Do not delete source data as implicit cleanup.

## Cost

Estimate mode-specific transferred bytes, task-execution dimensions where applicable, S3 requests/storage, network and agent resources. Check current target Region, location support and quotas before deployment.

## Agent, location, task and execution architecture

```text
supported source → agent (where required) → transfer/verify → destination
                       │                         ↑
                network/activation        task options/filters/schedule
                                                 ↓
                                      execution status/report/logs
```

| Object    | Responsibility                                    | Not automatic                                    |
| --------- | ------------------------------------------------- | ------------------------------------------------ |
| Agent     | Supported source connectivity/transfer processing | Universal HA or every AWS-to-AWS path            |
| Location  | Endpoint/path/protocol/access configuration       | File-format conversion or unlimited permissions  |
| Task      | Source/destination/options/filter/schedule        | Correctness for every metadata/consistency model |
| Execution | One task run and evidence                         | Application cutover or deletion of source data   |

Multiple-agent support and behavior are mode/location-specific. Do not assume transfers automatically redistribute across arbitrary agents on failure.

## NFS-to-S3 location and task walkthrough

Prerequisites: a supported Basic-mode agent activated in the sandbox, authorized NFS export, dedicated private bucket/role and routing/firewall/KMS access. Obtain actual ARNs from the console.

```bash
aws datasync create-location-nfs --server-hostname NFS_HOST \
  --subdirectory /wiki-lab \
  --on-prem-config '{"AgentArns":["AGENT_ARN"]}'
aws datasync create-location-s3 --s3-bucket-arn BUCKET_ARN \
  --subdirectory /wiki-lab \
  --s3-config '{"BucketAccessRoleArn":"DATASYNC_BUCKET_ROLE_ARN"}'
aws datasync create-task --name wiki-lab-transfer \
  --source-location-arn NFS_LOCATION_ARN --destination-location-arn S3_LOCATION_ARN \
  --options '{"VerifyMode":"ONLY_FILES_TRANSFERRED","TransferMode":"CHANGED","OverwriteMode":"ALWAYS","PreserveDeletedFiles":"PRESERVE","Atime":"BEST_EFFORT","Mtime":"PRESERVE","Uid":"INT_VALUE","Gid":"INT_VALUE"}'
```

Substitute placeholders and validate option applicability for the selected location pair. S3 has object metadata, not every POSIX ownership/ACL behavior; a successful transfer does not promise identical filesystem semantics.

```bash
aws datasync start-task-execution --task-arn TASK_ARN
aws datasync describe-task-execution --task-execution-arn EXECUTION_ARN
```

Record the returned execution ARN, inspect terminal result/error and statistics, then verify known fixture bytes at the destination. Poll with timeout/backoff; do not treat a started execution as completed.

## Location and option comparison

| Destination/source | Required concepts                                     | Important difference                              |
| ------------------ | ----------------------------------------------------- | ------------------------------------------------- |
| SMB                | Agent, share/path and supported protected credentials | Top-level SMB fields, not NFS OnPremConfig        |
| EFS                | File-system ARN, mount subnet and SG ARNs             | Network/IAM/access-point and metadata constraints |
| FSx Windows        | Filesystem/SG and supported credentials               | Authentication/share contract differs from EFS    |
| S3                 | Bucket/access role, object namespace                  | Not a POSIX file tree or arbitrary output format  |

| Option                   | What it controls                                     | What it does not establish                 |
| ------------------------ | ---------------------------------------------------- | ------------------------------------------ |
| TransferMode CHANGED/ALL | Metadata comparison versus copying all selected data | Integrity validation by itself             |
| VerifyMode               | Supported integrity verification scope               | A new change-detection algorithm           |
| OverwriteMode            | Replacement behavior                                 | Authorization to destroy source data       |
| PreserveDeletedFiles     | Destination deletion policy                          | Backup versioning/immutable recovery       |
| Atime/Mtime/Uid/Gid      | Supported metadata preservation                      | Identical semantics for every storage type |
| BytesPerSecond           | Supported per-task/execution rate limit              | An invented hourly bandwidth array         |

ALL can overcome reliance on change comparison where that is the intended workflow; NONE verification is not a fix for same-size modified files.

## Filters, schedules and bandwidth

Use supported include/exclude SIMPLE_PATTERN filters against the actual paths; test nested names, escaping and excluded data before a large run. Filter syntax is not a generic regex engine.

```bash
aws datasync update-task --task-arn TASK_ARN \
  --excludes '[{"FilterType":"SIMPLE_PATTERN","Value":"/tmp|/cache"}]' \
  --schedule '{"ScheduleExpression":"cron(0 0 * * ? *)"}'
```

The schedule is a documented service expression, not an OS crontab. Apply only supported task/mode options. For a Basic task with rate limiting, 50 megabits/sec is about 6,250,000 bytes/sec before protocol overhead; BytesPerSecond uses bytes. Enhanced-mode options differ. External automation can change supported settings but must have scoped authorization.

## Monitoring, incremental correctness and common patterns

Inspect describe-task-execution status/ErrorCode/ErrorDetail and reported estimated/transferred/verified/skipped data in the actual API version/mode. Task reports/logs add detail; inspect access to their destination. Do not substitute invented file counters for documented fields.

Repeat a fixture transfer after changing one file; inspect overwrite, metadata and verification outcomes. Test same-size content changes and destination deletion behavior deliberately. A continuous mirror can replicate a mistake; use separate versioned/locked backup where recovery is required.

On-prem NFS→S3 migration, S3→EFS staging and supported cross-Region transfers each need their own authorization/metadata/cost model. DataSync does not output Parquet merely because the destination is S3. Delete dedicated schedules/tasks/locations/agents after acceptance and preserve source data; account for destination storage/reports and compute/network resources separately.

References: [NFS contract](https://docs.aws.amazon.com/cli/latest/reference/datasync/create-location-nfs.html), [task options](https://docs.aws.amazon.com/datasync/latest/apireference/API_Options.html), [filters](https://docs.aws.amazon.com/datasync/latest/userguide/filtering.html), [task schedules](https://docs.aws.amazon.com/datasync/latest/userguide/task-scheduling.html), [task monitoring](https://docs.aws.amazon.com/datasync/latest/userguide/monitor-task-execution.html).

## References

- [Agent requirements](https://docs.aws.amazon.com/datasync/latest/userguide/agent-requirements.html)
- [Options contract](https://docs.aws.amazon.com/datasync/latest/apireference/API_Options.html)
- [SMB location contract](https://docs.aws.amazon.com/cli/latest/reference/datasync/create-location-smb.html)
- [EFS location contract](https://docs.aws.amazon.com/cli/latest/reference/datasync/create-location-efs.html)
- [FSx Windows contract](https://docs.aws.amazon.com/cli/latest/reference/datasync/create-location-fsx-windows.html)
- [Feature retirements](https://docs.aws.amazon.com/general/latest/gr/full_shutdown_services.html)
- [Pricing](https://aws.amazon.com/datasync/pricing/)

## Across the wiki

- [[Architecture/solution-architecture-concepts/migration-patterns/README|Migration Patterns]]
- [[Architecture/solution-architecture-concepts/migration-patterns/data-migration|Data Migration Patterns]]
- [[Architecture/solution-architecture-concepts/migration-patterns/change-data-capture|Change Data Capture (CDC)]]
- [[Architecture/solution-architecture-concepts/migration-patterns/strangler-fig|Strangler Fig Pattern]]

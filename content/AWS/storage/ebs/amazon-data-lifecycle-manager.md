---
title: Amazon Data Lifecycle Manager
description: Design tag-based EBS snapshot and AMI lifecycle policies, validate retention and copies, and prove restore readiness in a sandbox.
tags:
  - cloud/aws/storage/ebs
  - cloud/aws/reliability
date: 2026-10-12
---

# Amazon Data Lifecycle Manager

Data Lifecycle Manager (DLM) automates supported EBS snapshot and EBS-backed AMI lifecycle workflows. A backup schedule is not proof that an application can be recovered. Start with [[AWS/storage/ebs/README|EBS]] and compare [[AWS/reliability/backup-and-recovery|AWS Backup and recovery requirements]].

## Policy decisions

Define the target by tags, resource type, schedules and retention. Decide whether an application needs crash consistency or application-consistent coordination. Specify copy destinations, encryption, permissions and retention separately; a cross-Region copy is not created simply because a volume is Multi-AZ.

| Decision   | Question to answer                                                 |
| ---------- | ------------------------------------------------------------------ |
| Selection  | Which volume/instance tags identify the protected workload?        |
| Schedule   | What capture interval meets the required recovery-point objective? |
| Retention  | How many generations or what age must remain?                      |
| Copies     | Which Region/account must survive the assumed failure?             |
| Encryption | Can the recovery principal use the destination KMS key?            |
| Restore    | Who tests boot, filesystem and application correctness?            |

Snapshot storage and copying may be billed even when the lifecycle service itself has no extra charge. Do not use S3 Standard prices for EBS snapshots.

## Sandbox policy exercise

Prerequisites: a sandbox EBS volume with disposable data, a unique `BackupScope=wiki-dlm-lab` tag, DLM permissions and an approved DLM execution role. The execution role trusts the lifecycle service and needs the supported snapshot/tag operations; use the documented default-role workflow or a reviewed equivalent.

Save this **PolicyDetails** object as `dlm-policy.json`:

```json
{
  "PolicyType": "EBS_SNAPSHOT_MANAGEMENT",
  "ResourceTypes": ["VOLUME"],
  "TargetTags": [{ "Key": "BackupScope", "Value": "wiki-dlm-lab" }],
  "Schedules": [
    {
      "Name": "DailyLab",
      "CreateRule": {
        "Interval": 24,
        "IntervalUnit": "HOURS",
        "Times": ["03:00"]
      },
      "RetainRule": { "Count": 2 },
      "CopyTags": true
    }
  ]
}
```

Set `DLM_LAB_ROLE_ARN` to the approved role ARN:

```bash
aws dlm create-lifecycle-policy \
  --execution-role-arn "$DLM_LAB_ROLE_ARN" \
  --description "wiki DLM sandbox" \
  --state ENABLED \
  --policy-details file://dlm-policy.json
aws dlm get-lifecycle-policies
```

Record the returned policy ID. Inspect its configuration with `get-lifecycle-policy` and, after the scheduled run, inspect snapshots for the tagged volume and DLM policy tags. Scheduled snapshots are not an immediate create-policy response.

Checkpoint: restore a snapshot into a new volume in the required AZ, attach only to a sandbox instance and verify a known marker/checksum plus application checks. A successful API response alone does not meet the restore objective.

Failure exercise: remove the selection tag from a disposable volume and check whether it still matches the policy; inspect policy state and IAM/KMS failures when a scheduled capture is absent.

Cleanup: disable then delete the specific lab policy. Inventory and delete retained lab snapshots, restored volumes and instances after confirming they contain no required data. Policy deletion is not a substitute for verifying backup cleanup; preserve shared roles and production backups.

## Next decisions

An AMI lifecycle policy includes instance image creation and deregistration concerns, not just volume snapshots. For cross-account/Region recovery, test sharing/copy permissions and destination-key access with the actual recovery identity. Use AWS Backup when the requirement spans multiple supported resource types, vault governance and centrally managed plans.

## References

- [DLM overview and supported policies](https://docs.aws.amazon.com/ebs/latest/userguide/snapshot-lifecycle.html).
- [CreateLifecyclePolicy contract](https://docs.aws.amazon.com/dlm/latest/APIReference/API_CreateLifecyclePolicy.html).
- [EBS snapshot pricing](https://aws.amazon.com/ebs/pricing/).

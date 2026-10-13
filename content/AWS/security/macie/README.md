---
title: AWS Macie
description: AWS Macie — data privacy and S3 data classification. PII/PHI/credentials detection, sensitivity scoring, policy findings, and automated remediation. Macie Classic vs Macie v2.
tags:
  - aws/security
date: 2026-10-12
---

# AWS Macie

Prerequisites: [[AWS/security/iam/README|IAM roles and least privilege]] and the [[AWS/security/README|security evidence/response model]].

Macie inventories S3 security posture and discovers sensitive data in supported objects. Automated discovery samples eligible data; a finding is not evidence that every object was scanned.

## Discovery and scoring

Distinguish automated sensitive-data discovery from one-time/scheduled classification jobs. Choose managed/custom identifiers, allow lists, sampling and bucket/object scope deliberately. Supported file formats, object size, encryption access and archive eligibility constrain what can be inspected.

A sensitivity score belongs to a bucket, not each object. Score 50 means not yet classified; documented sensitive/not-sensitive ranges and special values must not be replaced by invented low/medium/high/critical object bands. Finding severity is a different model.

## Controlled classification lab

Prerequisites: a private disposable S3 bucket, Block Public Access enabled, a non-sensitive synthetic fixture and an authorized Macie role/service-linked-role setup. Classification, S3 requests and storage can incur charges.

1. Enable Macie in the sandbox Region, inspect inventory and note automated-discovery settings.
2. Upload a tiny supported text/CSV fixture containing obviously synthetic test values. Never copy real personal data just to get a finding.
3. Create a one-time targeted discovery job for the exact bucket with explicit sampling/identifiers; wait for a terminal result, inspect job statistics and findings.
4. Compare inspected versus skipped objects. Test an unsupported format or deliberately inaccessible fixture and explain the coverage gap instead of claiming an all-clean bucket.
5. Review finding metadata without exposing sensitive samples. Sample retrieval requires separate authorization and careful handling.
6. Cancel any remaining running lab job through its supported lifecycle; do not promise to delete the retained cloud job record. Remove local request/configuration files and synthetic S3 fixtures, then remove the disposable bucket only after preserving required findings/results and clearing its lab-owned objects/versions. Restore prior discovery settings. Do not disable organization-wide Macie protection in a shared account.

## Permissions and response

Use narrow S3/KMS permissions and protect classification-result locations. A finding does not grant permission to delete/quarantine objects. Escalate to the data owner, preserve evidence and choose approved remediation (access restriction, encryption or lifecycle change).

## Cost and limits

Separate bucket inventory/monitoring, objects monitored for automated discovery and bytes inspected. Monitoring is paid after its thirty-day trial; targeted jobs can add S3 GET/LIST charges. Do not promise a permanent ten-GB allowance across operations/Regions.

Current targeted-discovery monthly default is five TB and adjustable under the owning quota page. Job sampling and automated sampling differ; verify account/Region limits and exclusions before sizing.

## Inventory, jobs and finding architecture

```text
S3 inventory/security posture → bucket monitoring
eligible objects → automated sample / targeted job → sensitive-data findings
                       ↓                               ↓
               coverage/skipped/error evidence   owner review/response
```

| Object/model        | Meaning                                             | Incorrect equivalence                            |
| ------------------- | --------------------------------------------------- | ------------------------------------------------ |
| Bucket sensitivity  | Documented bucket-level score/ranges/special states | Per-object low/medium/high/critical bands        |
| Finding severity    | Finding-specific impact context                     | Direct translation of every bucket score         |
| Automated discovery | Supported sampling/selection                        | Every object continuously scanned                |
| Targeted job        | Scope/schedule/sampling configuration               | Scan guarantee for unsupported/encrypted objects |
| Policy finding      | Supported bucket-access/configuration concern       | Permission to delete the data                    |

## Targeted job API walkthrough

With Macie already enabled in the authorized sandbox, save a valid one-time request as job.json and substitute account/bucket/token:

```json
{
  "jobType": "ONE_TIME",
  "name": "wiki-lab-sensitive-fixture",
  "clientToken": "wiki-lab-job-unique-1",
  "description": "Synthetic data only",
  "s3JobDefinition": {
    "bucketDefinitions": [
      { "accountId": "111122223333", "buckets": ["LAB_BUCKET_NAME"] }
    ]
  },
  "samplingPercentage": 100
}
```

```bash
aws macie2 create-classification-job --cli-input-json file://job.json
aws macie2 describe-classification-job --job-id JOB_ID
aws macie2 list-findings
aws macie2 get-findings --finding-ids FINDING_ID
```

100% sampling selection does not make unsupported/inaccessible objects inspectable. Record counts/skipped/error reasons and inspect actual finding evidence. Scheduled jobs need their own schedule/initial-run settings; avoid assuming one-time and scheduled input shapes are identical.

## Custom identifiers and practical fixture

A custom identifier uses a supported regex, optional keywords/proximity and validation fixtures; it does not create a new managed identifier.

```bash
aws macie2 create-custom-data-identifier --name WikiSyntheticAccount \
  --regex 'WIKI-[0-9]{8}' --keywords WIKI
```

Use test-custom-data-identifier with synthetic text before adding its returned ID to a job. Test matching, near-match and irrelevant text to quantify false positives; never publish real identifiers in fixtures. Supported regex behavior and discovery thresholds differ from generic language libraries.

## Security Hub/EventBridge and remediation safety

Findings can flow through supported integrations and event routing; account/Region/integration permissions still matter. Correlate bucket/object identifiers, classification scope and skipped coverage before assigning a privacy incident.

Review the finding with its data owner before mutation. Sensitive data may be lawful/required, and deletion can destroy evidence. An approved workflow can restrict access, encrypt, quarantine or delete according to owner/legal authorization, with idempotency, validation and rollback where feasible.

## Coverage/cost/troubleshooting

Inspect Macie eligibility, job scope, identifier configuration, object format/size/class, KMS/S3 access and per-job errors. Bucket inventory existence does not prove bytes were inspected. Price monitored buckets/objects and analyzed bytes using the actual operation/Region; source S3 requests and result storage are separate.

Cancel remaining lab work through the [documented pause/resume/cancel lifecycle](https://docs.aws.amazon.com/macie/latest/user/discovery-jobs-status-change.html); the [classification-job resource](https://docs.aws.amazon.com/macie/latest/APIReference/jobs-jobid.html) supports describe and status updates, not a job-delete operation. Retained job metadata is not a failed cleanup. Remove custom identifiers only when no jobs depend on them, delete synthetic fixtures and restore discovery settings. Preserve required findings/results and production Macie enrollment.

References: [job contract](https://docs.aws.amazon.com/cli/latest/reference/macie2/create-classification-job.html), [custom identifiers](https://docs.aws.amazon.com/macie/latest/user/custom-data-identifiers.html), [test identifier](https://docs.aws.amazon.com/cli/latest/reference/macie2/test-custom-data-identifier.html), [finding events](https://docs.aws.amazon.com/macie/latest/user/findings-monitor-events.html).

## References

- [Bucket sensitivity scores](https://docs.aws.amazon.com/macie/latest/user/discovery-scoring-s3.html)
- [Discovery jobs](https://docs.aws.amazon.com/macie/latest/user/discovery-jobs.html)
- [Supported objects](https://docs.aws.amazon.com/macie/latest/user/discovery-supported-storage.html)
- [Quotas](https://docs.aws.amazon.com/macie/latest/user/macie-quotas.html)
- [Pricing](https://aws.amazon.com/macie/pricing/)

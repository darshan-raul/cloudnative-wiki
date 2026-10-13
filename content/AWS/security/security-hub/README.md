---
title: AWS Security Hub
description: AWS Security Hub — centralized security findings aggregation. Integrates with GuardDuty, Inspector, Macie, IAM Access Analyzer, and custom plugins. ASFF format, compliance standards, automated remediation.
tags:
  - aws/security
date: 2026-10-12
---

# AWS Security Hub

Prerequisites: [[AWS/security/iam/README|IAM roles and least privilege]] and the [[AWS/security/README|security evidence/response model]].

Security Hub centralizes security evidence and operational workflows. Distinguish the unified Security Hub product from Security Hub CSPM's configuration checks, finding ingestion and automation rules.

## Product and regional boundaries

Unified Security Hub plans include separately defined capabilities such as essentials, threat analytics and Lambda code scanning. Do not apply an older CSPM check tariff to every plan. CSPM evaluates enabled standards/controls and consumes integrations; enabling it does not make underlying AWS Config recording/evaluations free.

Choose a delegated administrator and documented Organizations central-configuration workflow. Home/linked Regions and aggregation determine where findings/configuration are managed; aggregation does not independently authorize arbitrary remediation in source accounts.

Control findings, product findings and workflow state are different evidence. Marking a finding RESOLVED does not patch a workload or repair a policy. Track remediation evidence and re-evaluation independently.

## Safe triage lab

Prerequisites: an isolated account/Region, scoped Hub administration/read/workflow permissions and an explicit cost budget. Record existing standards/configuration before changing them.

1. Use the console's currently offered CSPM/security-product workflow to enable only the intended sandbox coverage. Choose a documented standard/control, not a guessed control identifier.
2. Inspect one existing/synthetic integration finding, its product ARN, account/Region/resource, severity, timestamps and workflow state. Follow its canonical [[AWS/security/guardduty/README|GuardDuty]], [[AWS/security/inspector/README|Inspector]] or [[AWS/security/config/README|Config]] evidence.
3. Assign an owner and route the finding to a sandbox notification through EventBridge. Test a workflow update; verify that the underlying resource remains unchanged.
4. If authorized, remediate the disposable resource with a narrow role and capture the next evaluation/scan. Confirm closure from evidence, not just a button click.
5. Restore prior sandbox standards/configuration and delete only lab automation/integrations. Do not disable organization-managed security coverage.

## Access and costs

Keep ingestion/workflow roles separate from resource-modification roles. Automated remediations need approval and rollback for disruptive changes, particularly IAM/network restrictions.

Estimate the selected unified plan or CSPM dimensions using the owning estimator and current Region's table. Include Config, partner/service scanners, EventBridge, Lambda and storage independently. A free trial is not permanent free checks.

## Findings architecture and ASFF boundaries

```text
GuardDuty / Inspector / Macie / Config / approved partner/custom findings
                                  ↓
                     supported ingestion + ASFF/product model
                                  ↓
          aggregation → workflow/automation rules → assigned owner
                                  ↓
                  approved remediation → source re-evaluation
```

| Field/category             | Purpose                   | Review concern                                     |
| -------------------------- | ------------------------- | -------------------------------------------------- |
| Product/source identity    | Where evidence originated | Not every product event shares a schema/API        |
| Resource/account/Region    | Affected boundary         | Cross-account remediation needs separate authority |
| Severity/status/timestamps | Triage and lifecycle      | Repeated updates/stale findings                    |
| Compliance                 | Control/evaluation result | Not a complete framework certification             |
| Workflow state             | Investigator process      | RESOLVED does not repair the resource              |

ASFF remains relevant to documented finding integration APIs. Current unified Hub versus CSPM product boundaries must be checked before applying old standards/pricing/API assumptions.

## Complete synthetic ASFF teaching record

For an authorized custom import experiment, replace account/Region/ARNs and use the current BatchImportFindings contract. This synthetic record is not evidence of a real vulnerability:

```json
{
  "SchemaVersion": "2018-10-08",
  "Id": "wiki-lab/finding-1",
  "ProductArn": "arn:aws:securityhub:us-east-1:111122223333:product/111122223333/default",
  "GeneratorId": "wiki-lab",
  "AwsAccountId": "111122223333",
  "Types": ["Software and Configuration Checks"],
  "CreatedAt": "2026-10-12T00:00:00Z",
  "UpdatedAt": "2026-10-12T00:00:00Z",
  "Severity": { "Label": "INFORMATIONAL" },
  "Title": "Synthetic workflow fixture",
  "Description": "No live vulnerability; workflow test only",
  "Resources": [
    {
      "Type": "AwsS3Bucket",
      "Id": "arn:aws:s3:::LAB_BUCKET",
      "Partition": "aws",
      "Region": "us-east-1"
    }
  ],
  "RecordState": "ACTIVE",
  "Workflow": { "Status": "NEW" }
}
```

Wrap the record in the API's Findings array, confirm product/account import permissions and inspect failed findings individually. Do not assume arbitrary standards/control IDs or product ARN strings are deployable.

## Standards, integrations and central configuration

Choose supported standards/control versions in the actual CSPM/Region model and inspect enabled control coverage. Config recording/evaluations may be prerequisites and remain separately billable. Partner product enablement requires its documented product subscription; creating a detector in another service is not always integration setup.

Central configuration has home/linked Region and organization/delegated-admin boundaries. Distinguish member enrollment, aggregation, standards policies and finding ingestion; a monitoring account is not automatically an administrator for every source resource.

## Workflow, automation and investigation

Filter findings using actual API field/comparison shapes and pagination, then inspect original product evidence. A batch update can change workflow state; it does not patch an image, close a network port or change an IAM trust policy.

For EventBridge remediation, use the documented emitted schema, test a synthetic event and authorize only a sandbox target. Prefer triage/approval first. Automation rules may enrich/prioritize finding data; actual Systems Manager/Lambda resource repair needs independently scoped roles, stale-state checks, idempotency and post-repair validation.

Measure unresolved age, repeated updates and exception expiry as workflow outcomes; retain source evidence separately from dashboard status. Restore sandbox standards/central policies, remove dedicated imported samples/automation routes as supported and preserve organization coverage.

References: [ASFF](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-findings-format.html), [BatchImportFindings](https://docs.aws.amazon.com/cli/latest/reference/securityhub/batch-import-findings.html), [central configuration](https://docs.aws.amazon.com/securityhub/latest/userguide/central-configuration-intro.html), [automation rules](https://docs.aws.amazon.com/securityhub/latest/userguide/automation-rules.html).

## Cross-wiki comparisons

- [[Azure/monitoring/sentinel/README|Microsoft Sentinel Architecture, Threat Intelligence, and SOAR]] — threat detection (Azure)

## References

- [Current cost estimator and product distinction](https://docs.aws.amazon.com/securityhub/latest/userguide/security-hub-cost-estimator.html)
- [CSPM pricing](https://aws.amazon.com/security-hub/cspm/pricing/)
- [Central configuration](https://docs.aws.amazon.com/securityhub/latest/userguide/central-configuration-intro.html)
- [Finding workflow](https://docs.aws.amazon.com/securityhub/latest/userguide/findings-workflow-status.html)

## Across the wiki

- [[GCP/security/scc|GCP Security Command Center (SCC) & Secret Manager]]
- [[Security/siem/README|SIEM]]
- [[Kubernetes/eks/security/guardduty|GuardDuty for EKS]]

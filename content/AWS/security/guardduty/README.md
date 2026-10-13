---
title: AWS GuardDuty
description: AWS GuardDuty — threat detection, foundational data sources, protection plans, findings, safe response and organization-wide delegated administration.
tags:
  - aws/security
date: 2026-10-12
---

# AWS GuardDuty

Prerequisites: [[AWS/security/iam/README|IAM roles and least privilege]] and the [[AWS/security/README|security evidence/response model]].

GuardDuty detects suspicious behavior from supported AWS telemetry and protection plans. Findings are signals to investigate, not automatic evidence that a resource must be deleted.

## Coverage and plans

Foundational detection analyzes supported CloudTrail management, VPC network and DNS activity through its service data sources; your own delivered trail/flow-log files are not required inputs. Additional plans include product-specific coverage for S3, EKS, runtime, RDS, Lambda and malware protection. There is no invented Enterprise tier or permanent free management-log tier.

Current APIs use named Features and supported AdditionalConfiguration fields. EKS_RUNTIME_MONITORING and RUNTIME_MONITORING cannot both be enabled. S3 Malware Protection is a separate plan with an IAM role and protectedResource.s3Bucket settings; its prefix selection does not mean foundational S3 detection can universally select arbitrary bucket log inputs.

## Safe detection lab

Use a sandbox Region with no existing production detector; record prior state first. The role needs GuardDuty detector/list/sample-finding permissions and any required service-linked-role creation authority.

```bash
aws guardduty create-detector --enable
```

Save DetectorId, then create sample findings through the console or:

```bash
aws guardduty create-sample-findings --detector-id DETECTOR_ID
aws guardduty list-findings --detector-id DETECTOR_ID
```

Inspect a sample with get-findings, correlate account/Region/resource identity and route it to a sandbox notification through EventBridge. Expected: synthetic findings clearly labeled as samples; no attack traffic is required.

Check the response runbook's triage, evidence preservation, containment approval and recovery verification. Suppression hides matching findings; it does not disable telemetry collection or remediate the resource.

## Quotas, costs and cleanup

Current quota examples include one trusted IP set and six threat-intelligence sets per account/Region; verify the quota page before deployment. Finding retention is ninety days, so export required evidence. Severity includes Critical (9–10), High (7–8.9) and lower bands.

Eligible foundational/protection-plan trials are generally thirty days per account/Region, with product-specific exceptions such as on-demand scans. Estimate by each plan's actual events/bytes/resources; do not multiply a per-event rate by GB without converting units.

Delete only the disposable detector or restore the earlier plan settings. Never disable a production detector merely to complete the exercise; record the trial/cost consequences first.

## Detection pipeline and plan comparison

```text
supported foundational telemetry + enabled protection plans
                         ↓
                    GuardDuty detector
                         ↓
finding + resource/principal/time/severity → EventBridge/Hub/export
                         ↓
                 triage → approved response → recovery
```

| Capability                   | Evidence/coverage                          | Do not infer                                       |
| ---------------------------- | ------------------------------------------ | -------------------------------------------------- |
| Foundation                   | Supported management/network/DNS activity  | Your S3 trail is its required ingestion source     |
| S3 protection                | Documented S3 threat-detection activity    | Generic per-bucket collection controls             |
| Runtime/EKS/Lambda/RDS plans | Plan-specific supported resource/telemetry | Every OS/process/workload is covered               |
| Malware protection           | Scan/plan-specific objects/resources       | A detector flag scans arbitrary objects everywhere |
| Findings                     | Type, severity, resource and context       | Confirmed business compromise or automatic repair  |

Low/Medium/High/Critical severity guides urgency but is not the final incident classification. Finding suppression/archive is a workflow choice, not turning off collection or fixing the source.

## Real detector and finding contracts

With the disposable DetectorId created in the existing lab:

```bash
aws guardduty get-detector --detector-id DETECTOR_ID
aws guardduty get-findings --detector-id DETECTOR_ID --finding-ids FINDING_ID
aws guardduty archive-findings --detector-id DETECTOR_ID --finding-ids SAMPLE_FINDING_ID
```

Only archive a reviewed sample/false positive; preserving investigation evidence matters. Detector feature updates use supported names and additional settings, not the deprecated/fabricated Enterprise configuration:

```bash
aws guardduty update-detector --detector-id DETECTOR_ID \
  --features '[{"Name":"S3_DATA_EVENTS","Status":"ENABLED"}]'
```

This can change paid coverage. Read previous settings first and restore only the lab change. Runtime plan combinations and organization settings have their own contracts; do not enable incompatible EKS_RUNTIME_MONITORING and RUNTIME_MONITORING together.

## EventBridge triage fixture

A rule matching GuardDuty findings can use this valid pattern:

```json
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": { "severity": [{ "numeric": [">=", 7] }] }
}
```

Test against a real sample envelope, authorize the target and use the actual service-generated fields. This router only extracts investigation metadata; it deliberately does not modify IAM/resources:

```python
def handler(event, context):
    detail = event.get("detail", {})
    return {
        "findingId": detail.get("id"),
        "account": event.get("account"),
        "region": event.get("region"),
        "type": detail.get("type"),
        "severity": detail.get("severity"),
        "resource": detail.get("resource", {}),
        "requiresReview": True,
    }
```

Forward only approved/redacted fields to an authorized case workflow. Design idempotency because repeated/new finding updates can arrive; a trigger must not repeatedly quarantine the same workload.

## Malware, organization rollout and operations

S3 malware plans require protectedResource.s3Bucket bucket/prefix configuration plus the supported role/notification/KMS dependencies. They are not created by a generic update-detector malware flag. Check eligible object/encryption/size/Region constraints and result interpretation.

Organization administration/member enrollment and protection-plan rollout need delegated administration/trusted service configuration. Stage one eligible sandbox account/Region, validate coverage/sample routing, then expand with an approved rollback. Detector visibility alone does not prove every member plan is enabled.

Diagnose missing findings through account/Region, plan eligibility, event/source coverage and actual state before assuming no activity. Preserve/export required evidence beyond finding retention. After tests remove lab routing/sample workflow, restore feature settings or delete only a detector created exclusively for the lab.

References: [finding details](https://docs.aws.amazon.com/cli/latest/reference/guardduty/get-findings.html), [features](https://docs.aws.amazon.com/guardduty/latest/APIReference/API_UpdateDetector.html), [EventBridge monitoring](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings_cloudwatch.html), [organization management](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_organizations.html).

## Cross-wiki comparisons

- [[Azure/monitoring/sentinel/README|Microsoft Sentinel Architecture, Threat Intelligence, and SOAR]] — threat detection (Azure)

## References

- [Protection-plan pricing/trials](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty-pricing.html)
- [Sample findings](https://docs.aws.amazon.com/cli/latest/reference/guardduty/create-sample-findings.html)
- [Feature API](https://docs.aws.amazon.com/guardduty/latest/APIReference/API_UpdateDetector.html)
- [S3 malware-plan contract](https://docs.aws.amazon.com/guardduty/latest/APIReference/API_CreateMalwareProtectionPlan.html)
- [Quotas](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_limits.html)
- [Severity](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings-severity.html)

## Across the wiki

- [[GCP/security/scc|GCP Security Command Center (SCC) & Secret Manager]]
- [[Security/siem/README|SIEM]]
- [[Kubernetes/eks/security/guardduty|GuardDuty for EKS]]

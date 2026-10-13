---
title: AWS Security
description: AWS security services — IAM for identity, KMS for encryption, CloudTrail for audit, GuardDuty for threat detection, Security Hub for aggregation, Inspector for vulnerability scanning, Macie for data privacy, Secrets Manager, ACM, and Detective.
tags:
  - aws/security
date: 2026-10-12
---

# AWS Security

AWS security combines identity, prevention, audit, detection and response. Managed security services provide evidence and controls; the customer still owns data classification, access design and incident decisions.

## Learning map

| Concern                            | Canonical lesson                                                                                                                      |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Identity and federation            | [[AWS/security/iam/README\|IAM]], [[AWS/security/iam/identity-center\|Identity Center]], [[AWS/security/iam/sts-and-federation\|STS]] |
| Authorization diagnosis            | [[AWS/security/iam/policy-evaluation\|Policy evaluation]]                                                                             |
| Encryption and TLS                 | [[AWS/security/kms/README\|KMS]], [[AWS/security/certificate-manager/README\|ACM]]                                                    |
| Audit and configuration            | [[AWS/security/cloudtrail/README\|CloudTrail]], [[AWS/security/config/README\|Config]]                                                |
| Threat and vulnerability detection | [[AWS/security/guardduty/README\|GuardDuty]], [[AWS/security/inspector/README\|Inspector]]                                            |
| Sensitive-data discovery           | [[AWS/security/macie/README\|Macie]]                                                                                                  |
| Secret lifecycle                   | [[AWS/security/secrets-manager/README\|Secrets Manager]]                                                                              |
| Findings and investigation         | [[AWS/security/security-hub/README\|Security Hub]], [[AWS/security/detective/README\|Detective]]                                      |

Start with [[AWS/foundations/README|account foundations]]: protect root credentials, use federation/temporary credentials and separate sandbox from production. Shared responsibility changes with the service: patching a guest EC2 OS is different from configuring a managed service's data/access controls.

## Response exercise

Use a test finding, not a live compromise. Verify collection in the correct Region/account, routing through EventBridge and assignment to an owner. Document the affected principal/resource, evidence preservation, containment approval and recovery check. Marking a finding resolved is not resource remediation.

Automation should have narrow permissions, idempotency, approval gates for destructive operations and rollback. Do not automatically delete resources based only on a single unreviewed event. Preserve CloudTrail coverage and evidence when estimating logging costs.

## Cost and scope

Each service has its own billable dimensions and trial rules. Config evaluations are not free merely because Security Hub consumes results. Unified Security Hub plans and standalone CSPM pricing differ. Check coverage by account/Region and partition; aggregation does not create authorization to remediate source accounts.

## Defense-in-depth request and response architecture

```text
federated identity → trust/session/IAM → application authorization
                            ↓
      network paths/SG/NACL/WAF → encrypted data + scoped key access
                            ↓
        CloudTrail/Config → detectors/scanners → findings workflow
                            ↓
           investigation → approved containment → recovery test
```

| Responsibility | AWS-managed boundary                      | Customer decision                                 |
| -------------- | ----------------------------------------- | ------------------------------------------------- |
| Infrastructure | Service-specific infrastructure operation | Workload placement/configuration                  |
| Identity       | IAM/STS mechanisms                        | Trust, assignments, policy/session scope          |
| Data           | Supported encryption/backup mechanisms    | Classification, access, keys and restore proof    |
| Detection      | Product-specific telemetry/analysis       | Coverage, triage, response and evidence retention |
| Guest software | Depends on service model                  | EC2 patches, images, application dependencies     |

## Product comparisons and investigation walkthrough

Inspector finds supported software vulnerabilities; GuardDuty detects supported suspicious activity; Macie discovers sensitive S3 data; Config evaluates configuration. Security Hub aggregates/workflows evidence and Detective helps investigation. They overlap without substituting for one another.

For a suspicious role session, preserve principal/session attribution and UTC interval; inspect CloudTrail-supported calls, GuardDuty finding/source context, related resource configuration and network evidence. Check the caller's trust/policy conditions and downstream key/data access. Containment can disrupt production: use approval, narrow scope and recovery validation rather than a blanket revoke/delete script.

For a vulnerable container, correlate its digest with deployment, patch/rebuild and redeploy through reviewed release controls. A resolved finding without a new image/scan/deployment is not remediation evidence. For sensitive data, contact the data owner before deletion/quarantine and preserve required audit trails.

A security budget includes separate Config/scanner/detection/secret/key/log dimensions. Optimize coverage and data retention deliberately, not by assuming all checks or management telemetry are permanently free.

## References

- [Shared responsibility](https://aws.amazon.com/compliance/shared-responsibility-model/)
- [Security best practices](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)

## Across the wiki

- [[Security/cloud-security/README|Cloud Security Hub]]
- [[GCP/compute/gke/security|GKE Security & Hardening — Workload Identity & Binary Authorization]]
- [[Security/cloud-security/aws/README|AWS Security]]
- [[Security/cloud-security/azure/README|Azure Security]]

## Application identity

Use [[AWS/security/cognito|Cognito]] for app-user pools, access tokens and optional identity-pool AWS credentials; workforce Identity Center is not every app's sign-in solution.

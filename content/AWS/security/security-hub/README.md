---
title: AWS Security Hub
description: AWS Security Hub — centralized security findings aggregation. Integrates with GuardDuty, Inspector, Macie, IAM Access Analyzer, and custom plugins. ASFF format, compliance standards, automated remediation.
tags:
  - aws
  - security
  - security-hub
---

# AWS Security Hub

Security Hub provides a centralized view of security findings across all your AWS accounts and services. It aggregates findings from GuardDuty, Inspector, Macie, IAM Access Analyzer, and other security services using a standard format (ASFF).

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Security Hub (Master Account)                               │
│                                                               │
│  Findings from:                                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │ GuardDuty  │  │ Inspector  │  │   Macie    │            │
│  └────────────┘  └────────────┘  └────────────┘            │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │  Config    │  │ IAM Access │  │  Partner   │            │
│  │            │  │  Analyzer  │  │  Products  │            │
│  └────────────┘  └────────────┘  └────────────┘            │
│                                                               │
│  ASFF (AWS Security Finding Format)                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ { "Findings": [ ... ] }                                 ││
│  └─────────────────────────────────────────────────────────┘│
│                                                               │
│  → EventBridge → Automated Remediation                       │
│  → Compliance Standards (CIS, PCI, AWS FSBP)               │
└──────────────────────────────────────────────────────────────┘
```

## ASFF (AWS Security Finding Format)

```json
{
  "SchemaVersion": "2018-10-08",
  "Id": "arn:aws:securityhub:us-east-1:123456789012:subscription/aws-foundational-security-best-practices/v/1.0.0/IAM.1/finding/xxxxx",
  "ProductArn": "arn:aws:securityhub:us-east-1:123456789012:product/123456789012/guardduty",
  "GeneratorId": "aws-foundational-security-best-practices/v/1.0.0/IAM.1",
  "AwsAccountId": "123456789012",
  "Types": ["Software and Configuration Checks/BC/AWS-1"],
  "FirstObservedAt": "2024-01-15T10:00:00Z",
  "LastObservedAt": "2024-01-15T10:30:00Z",
  "CreatedAt": "2024-01-15T10:00:00Z",
  "UpdatedAt": "2024-01-15T10:30:00Z",
  "Severity": {
    "Label": "HIGH",
    "Original": "90"
  },
  "Title": "IAM users should not have IAM access keys older than 90 days",
  "Description": "This AWS Foundational Security Best Practice rule checks whether IAM access keys are older than 90 days...",
  "Resources": [{
    "Type": "AwsIamUser",
    "Id": "arn:aws:iam::123456789012:user/alice",
    "Partition": "aws",
    "Region": "us-east-1"
  }],
  "Compliance": {
    "Status": "FAILED",
    "RelatedRequirements": ["AWS-1"]
  }
}
```

## Enabling Security Hub

```bash
# Enable Security Hub (requires AWS Config to be enabled first)
aws securityhub enable --region us-east-1

# Enable specific standards
aws securityhub enable-standards \
  --standards-subscription-arn "arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/subscription/v/1.0.0"

# Enable CIS standard
aws securityhub enable-standards \
  --standards-subscription-arn "arn:aws:securityhub:us-east-1::standards/cis-aws-foundations-benchmark/subscription/v/3.0.0"

# Enable PCI DSS standard
aws securityhub enable-standards \
  --standards-subscription-arn "arn:aws:securityhub:us-east-1::standards/pci-dss/v/3.2.1"
```

## Cross-Account Setup

```bash
# Master account: enable administration
aws securityhub enable-organization-admin-account \
  --admin-account-id 123456789012

# Member accounts: auto-enroll via Organizations
aws securityhub update-organization-configuration \
  --auto-enable
```

## Managing Findings

```bash
# List findings by severity
aws securityhub get-findings \
  --filters '{
    "SeverityLabel": [{"Value": "HIGH", "Comparison": "EQUALS"}],
    "RecordState": [{"Value": "ACTIVE", "Comparison": "EQUALS"}]
  }' \
  --sort-criteria '{"Field": "LastObservedAt", "SortOrder": "desc"}'

# Batch update (mark as resolved)
aws securityhub batch-update-findings \
  --finding-identifiers '[{"Id": "xxxxx", "ProductArn": "arn:aws:securityhub:..."}]' \
  --workflow '{"Status": "RESOLVED"}'

# Archive finding
aws securityhub batch-update-findings \
  --finding-identifiers '[{"Id": "xxxxx", "ProductArn": "arn:aws:securityhub:..."}]' \
  --workflow '{"Status": "ARCHIVED"}'
```

## Compliance Standards

| Standard | Description |
|----------|-------------|
| AWS Foundational Security Best Practices | AWS's own security standard |
| CIS AWS Foundations Benchmark | Center for Internet Security benchmarks |
| PCI DSS | Payment Card Industry Data Security Standard |
| NIST SP 800-53 | National Institute of Standards and Technology |

## Custom Plugins (Partner Products)

```bash
# List available integrations
aws securityhub list-enabled-products-for-import

# Enable a partner product
aws securityhub enable-import-findings-for-product \
  --product-arn "arn:aws:securityhub:us-east-1:123456789012:product/zscaler/zscaler-cloud-protection"
```

## Automated Remediation

```bash
# Create EventBridge rule for HIGH findings
aws events put-rule \
  --name security-hub-high \
  --event-pattern '{
    "source": ["aws.securityhub"],
    "detail": {
      "findings": {
        "Severity": {"Label": ["HIGH"]}
      }
    }
  }'

# Target: Systems Manager Automation
aws events put-targets \
  --rule security-hub-high \
  --targets '[{
    "Id": "remediation",
    "Arn": "arn:aws:ssm:us-east-1:123456789012:document/AWSResolvingDocument",
    "RoleArn": "arn:aws:iam::123456789012:role/RemediationRole"
  }]'
```

## Pricing

| Component | Cost |
|-----------|------|
| Security Hub (per account) | $0.0010 per finding (first 10,000/month free) |
| AWS Config rules evaluated | $0.001 per evaluation (first 50K/month free) |
| Custom actions | Free |

## References

- **Homepage:** https://aws.amazon.com/security-hub/
- **Documentation:** https://docs.aws.amazon.com/securityhub/
- **Pricing:** https://aws.amazon.com/security-hub/pricing/

## Pricing Examples

**Scenario 1:** A single account with 1000 findings/month. First 10K free = $0. Security Hub free for small accounts. Compare to running separate GuardDuty + Inspector + Macie: all have their own costs.

**Scenario 2:** An enterprise with 50 accounts, 10K findings/account/month. 500K total × $0.001 = $500/month. Plus AWS Config evaluations. Total: ~$500/month for centralized security visibility.

## Nuggets & Gotchas

- **Security Hub aggregates findings but doesn't prevent threats — you need GuardDuty for detection and EventBridge + SSM for remediation:** Security Hub is a dashboard and correlation engine, not a prevention tool. Build the full pipeline: GuardDuty → Security Hub → EventBridge → Lambda/SSM Automation.
- **Security Hub findings auto-expire after 90 days (same as GuardDuty) — export critical findings to S3 or SIEM:** If you need audit evidence beyond 90 days, create an automated export pipeline to S3.
- **Security Hub's "BatchUpdateFindings" with "Workflow.Status = RESOLVED" doesn't actually fix the issue — it just marks it as resolved in the console:** The underlying misconfiguration still exists. You must run actual remediation (SSM Automation, Lambda) before or after marking as resolved.
- **Not all Security Hub findings have remediations — some require manual review:** Finding "IAM.1: Access keys older than 90 days" requires human decision (rotate the key or mark as intentional). Automated remediation is only appropriate for clear-cut issues.
- **Security Hub requires AWS Config to be enabled for compliance standards to work:** If you disable AWS Config, the compliance standards (CIS, PCI, FSBP) won't generate findings.
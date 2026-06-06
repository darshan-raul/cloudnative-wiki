---
title: AWS Control Tower
description: AWS Control Tower — pre-configured landing zone with preventive and detective guardrails, OU structure, and automated compliance monitoring for multi-account AWS environments.
tags:
  - aws
  - management
  - control-tower
---

# AWS Control Tower

Control Tower automates the creation of a secure, multi-account AWS environment using a pre-configured landing zone. It sets up AWS Organizations with OUs, enables guardrails (preventive and detective), and provides a dashboard for compliance monitoring.

## What Control Tower Sets Up

When you run Control Tower, it creates:

```
Landing Zone
├── Organization Structure
│   ├── Core OUs:
│   │   ├── Security (Log Archive, Audit accounts)
│   │   ├── Sandbox (playground for experimentation)
│   │   └── Custom OUs (you define)
│   └── Management Account (payer)
│
├── Shared Accounts:
│   ├── Audit Account — Security team access, never used for workloads
│   └── Log Archive Account — Centralized CloudTrail and AWS Config logs
│
├── Pre-configured Guardrails:
│   ├── Preventive (SCPs) — Stop bad things from happening
│   └── Detective (AWS Config rules) — Detect when bad things happen
│
└── Shared Infrastructure:
    ├── VPC in each region with subnets
    ├── IAM Identity Center (SSO)
    └── CloudTrail and AWS Config in all accounts
```

## Guardrails

Control Tower ships with pre-built guardrails organized by category. Each guardrail is either preventive or detective.

### Preventive Guardrails (SCPs)

Preventive guardrails use Service Control Policies to stop non-compliant actions before they happen:

- **Disallow region:** Prevent resources in specific regions
- **Disallow public access to S3 buckets:** Enforce private buckets
- **Disallow broad IAM access keys:** Require temporary credentials
- **Disallow classic resources:** Prevent EC2-Classic, RDS-Classic

### Detective Guardrails (AWS Config Rules)

Detective guardrails use AWS Config rules to detect non-compliant resources after they are created:

- **VPC has flow logs enabled:** Detect VPCs without Flow Logs
- **EBS volumes encrypted:** Detect unencrypted volumes
- **Security groups allow open SSH:** Detect overly permissive SGs
- **CloudTrail enabled:** Detect accounts without CloudTrail

### Guardrail States

Each guardrail can be in one of three states:
- **Enforced:** Non-compliant actions are blocked (preventive) or resources are remediated (detective)
- **Not enabled:** Guardrail is not active
- ** detective only (clear):** Guardrail is in detection mode only (non-compliant but not blocked)

## Organization Units Created by Control Tower

```
Root
├── Security
│   ├── Audit (security team access)
│   └── Log Archive (centralized logging)
├── Sandbox (experimental, no production resources)
└── Custom (user-defined OUs you create)
    └── Production (your production workloads)
```

## Control Tower vs Manual Setup

| Task | Control Tower | Manual |
|------|--------------|--------|
| Set up Organizations | Automated | Manual |
| Create OUs | Pre-configured template | Manual |
| Enable CloudTrail | Auto-enabled in all accounts | Manual per account |
| Guardrails | 50+ pre-built | Write SCPs/Config rules from scratch |
| SSO integration | Built-in AWS IAM Identity Center | Manual |
| Time to deploy | Hours | Days to weeks |
| Customization | Limited (guardrail set is fixed) | Full control |

## Extending Control Tower

### Custom Guardrails

You can create custom preventive guardrails (SCPs) and attach them to your custom OUs alongside Control Tower's built-in guardrails.

### Preventive Guardrail via SCP

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": [
        "s3:PutBucketPublicAccessBlock"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalOrgID": "o-xxxxxxxxxx"
        }
      }
    }
  ]
}
```

### Adding Accounts via Account Factory

Control Tower's Account Factory (via AWS Service Catalog) allows you to provision new accounts programmatically:

```bash
# Using AWS Service Catalog to provision a new account
aws servicecatalog accept-responsibility-for-portfolio-access \
  --portfolio-id port-xxxxx

# Then via Service Catalog console, launch "AWS Control Tower Account Factory"
```

### Guardrail Compliance Dashboard

The Control Tower dashboard shows:
- Number of compliant vs non-compliant accounts
- Guardrails by category (security, operations, cost optimization)
- Non-compliant resources with remediation steps

## Drift Detection

Control Tower detects when your landing zone configuration changes (drift). For example, if someone manually modifies the Security OU SCPs, Control Tower will flag this as drift and offer to remediate.

```
Drift detected:
  - OU "Production" has unexpected SCP attached
  - CloudTrail disabled in account 111122223333
  - Security group in account 444455556666 allows SSH from 0.0.0.0/0
```

## Limits

| Resource | Limit |
|----------|-------|
| Landing zones per organization | 1 |
| Custom OUs | 5 (in addition to Core OUs) |
| AWS Regions where Control Tower is enabled | 3 (default) |
| Accounts per landing zone | 20 |

## References

- **Homepage:** https://aws.amazon.com/controltower/
- **Documentation:** https://docs.aws.amazon.com/controltower/
- **Pricing:** https://aws.amazon.com/controltower/pricing/

## Pricing Examples

**Scenario 1:** A new company setting up their first multi-account AWS environment. Manual setup takes 2 weeks (Organizations, SCPs, CloudTrail, Config, IAM Identity Center, VPCs). Control Tower deploys the same architecture in 4 hours at no extra cost beyond the AWS resources it creates (CloudTrail logs, Config rules, etc.). Monthly cost for the additional resources: ~$15/month for CloudTrail logs and Config rules across 3 accounts.

**Scenario 2:** An enterprise with existing AWS environment that wants to standardize on Control Tower. They must "landing zone v3" migration which involves creating a new landing zone and migrating accounts. This is a significant undertaking. Cost: $0 for Control Tower. Additional AWS Config rules and CloudTrail logs across 50 accounts: ~$250/month (Config rules at $0.001/rule/month × 100 rules × 50 accounts = $5/month, CloudTrail S3 logs at $0.03/GB × 50GB/month = $1.50/month — very small compared to the compliance benefit).

## Nuggets & Gotchas

- **Control Tower can only be enabled once per organization:** You cannot create multiple Control Tower landing zones in the same organization. The first Control Tower setup becomes the authoritative landing zone.
- **Control Tower creates its own Organization structure — do not modify manually:** If you manually add SCPs or modify the OUs created by Control Tower, you cause drift. Use Control Tower's APIs or console to make changes, not the raw Organizations API.
- **Detective guardrails detect but do not auto-remediate non-compliant resources:** A detective guardrail will flag an unencrypted EBS volume as non-compliant, but it won't automatically encrypt it. You must remediate manually or via AWS Config remediation actions.
- **Control Tower requires AWS IAM Identity Center (formerly AWS SSO):** If you already use a third-party SAML-based SSO, Control Tower will replace it with IAM Identity Center. This is a significant integration change that affects all users.
- **Control Tower Guardrails apply to all accounts in an OU:** When you enable a preventive guardrail on the Sandbox OU, it applies to every account in the Sandbox OU. If you want different guardrails per account, you need to put each account in its own OU, which doesn't scale.
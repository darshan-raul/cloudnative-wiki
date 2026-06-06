---
title: AWS Organizations
description: AWS Organizations — hierarchical account management, Service Control Policies (SCPs), consolidated billing, and organizational units (OUs) for multi-account AWS environments.
tags:
  - aws
  - management
  - organizations
---

# AWS Organizations

AWS Organizations enables centralized management of multiple AWS accounts. It provides hierarchical grouping via Organizational Units (OUs), consolidated billing, and Service Control Policies (SCPs) for access governance.

## Core Concepts

### Organization Structure

```
Root (Organization)
├── Management Account (payer account)
└── Organizational Units (OUs)
    ├── Security OU
    │   ├── Security Account
    │   └── Log Archive Account
    ├── Infrastructure OU
    │   ├── Network Account
    │   └── Shared Services Account
    ├── Production OU
    │   ├── Prod Account 1
    │   └── Prod Account 2
    └── Development OU
        └── Dev Account
```

- **Root:** The top-level container. All accounts live under the Root.
- **Management Account:** The payer account. Cannot be removed from the organization. Has full administrative control.
- **Organizational Units (OUs):** Containers that group accounts. OUs can be nested up to 5 levels deep.
- **Member Accounts:** Child accounts within OUs. Each account has its own IAM users, roles, and resources.

### Consolidated Billing

When accounts are under an organization, billing is consolidated:
- **Single payment account** — One credit card pays for all accounts
- **Single invoice** — One bill covers all member accounts
- **Cost allocation tags** — Use org-level tags to allocate costs per account/OUs
- **Reserved Instance sharing** — RIs purchased in any account can be shared with all accounts in the organization (Organization Reserved Instances)
- **Volume discounts aggregation** — Usage across all accounts contributes to volume discounts

### Service Control Policies (SCPs)

SCPs are JSON policies attached to OUs or the Root that restrict what actions are available in member accounts. They don't grant permissions — they restrict the permissions that identity-based or resource-based policies can grant.

**Key difference from IAM policies:**
- IAM policies: What a principal CAN do (allow/deny attached to users/roles)
- SCPs: What a principal CANNOT do (applied at the organizational level)

```
SCP Example — Deny access to specific regions:
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": ["cn-north-1", "cn-northwest-1"]
        }
      }
    }
  ]
}
```

### SCP Inheritance

```
Root (no SCP)
 └── Production OU (SCPs: deny eu-west-1)
      └── Prod Account (inherits deny eu-west-1)
```

- SCPs attached to a parent OU apply to all child OUs and accounts
- Child OU SCPs can ADD restrictions (more restrictive) but cannot REMOVE restrictions from parent SCPs
- An account is denied if ANY SCP in its path denies the action
- The management account is NOT affected by SCPs (it always has full access)

### Enabling All Features vs Consolidated Billing Only

When you create an organization, you choose:

**Consolidated billing features only (legacy):**
- Simple account grouping and billing
- No SCPs, no organization-wide CloudTrail/Config

**All features:**
- SCPs, organization root, OU hierarchy
- Trusted access for AWS services (CloudTrail, Config, Guard Duty)
- Recommended for new organizations

## AWS Organizations and AWS Config

With all features enabled, you can enable AWS Config across all accounts from a single management account using **trusted access**. AWS Config aggregator collects compliance data from all member accounts.

## Delegating Administrator

You can designate a member account as a delegated administrator for specific AWS services:

```bash
aws organizations register-delegated-administrator \
  --account-id 111122223333 \
  --service-principal config.amazonaws.com
```

This allows the Security account to manage AWS Config rules for the entire organization.

## API Integration with Organizations

```bash
# List all accounts
aws organizations list-accounts

# Move an account between OUs
aws organizations move-account \
  --account-id 111122223333 \
  --source-parent-id ou-xxxxx \
  --destination-parent-id ou-yyyyy

# Attach SCP to OU
aws organizations attach-policy \
  --policy-id p-xxxxx \
  --target-id ou-yyyyy
```

## Limits

| Resource | Limit |
|----------|-------|
| Accounts per organization | 10 (default, can request increase to 100) |
| OUs per parent | 10 |
| SCPs per account/OUs | 5 |
| SCP policy size | 5,120 bytes |
| Depth of OU nesting | 5 levels |

## References

- **Homepage:** https://aws.amazon.com/organizations/
- **Documentation:** https://docs.aws.amazon.com/organizations/
- **Pricing:** https://aws.amazon.com/organizations/pricing/

## Pricing Examples

**Scenario 1:** A startup with 5 AWS accounts (dev, staging, prod, security, log-archive) managed via Organizations. Organizations itself is free. Consolidated billing means one credit card pays all bills. Reserved Instances purchased in the prod account can be shared with all accounts, maximizing utilization. Total cost: $0/month for Organizations.

**Scenario 2:** An enterprise with 50 accounts across 3 OUs. SCPs enforce that no account can create resources in ap-southeast-1 (for compliance). Using SCP inheritance, the Production OU has an SCP that restricts all member accounts to approved regions. Cost: $0/month for Organizations. IAM administrators in the management account manage all 50 accounts from one place.

## Nuggets & Gotchas

- **SCP does not affect the management account:** The management account is exempt from all SCPs. You cannot use SCPs to restrict what the management account can do. This is intentional — the management account always has full access.
- **SCPs are deny-only — there is no "allow" SCP:** You can only restrict actions, not grant them. If an SCP denies an action, no IAM policy can override it (even with Allow). SCPs do not appear in IAM policy simulations by default — you must enable "SCP simulation mode" in the IAM policy simulator.
- **When you remove an account from an organization, it loses access to organization resources:** The account loses access to SCPs, consolidated billing, and shared Reserved Instances. The account becomes a standalone account with its own billing.
- **Organization-wide CloudTrail requires all features enabled:** If you create an organization with consolidated billing only (legacy), CloudTrail can only be configured per account. With all features enabled, CloudTrail can be configured once in the management account and applied to all member accounts.
- **SCPs affect every user in the account including the root:** SCPs apply to all accounts under the OU, including the account's IAM users and roles. If you attach an SCP that denies S3 to a Production OU, no one in any Production account can access S3, including the account administrator.
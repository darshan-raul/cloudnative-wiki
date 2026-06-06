---
title: Organizations Cost Strategy
description: AWS Organizations cost strategy — consolidated billing, volume discounts, RI/SP sharing, SCPs for cost governance, and multi-payer billing
tags:
  - aws
  - cost-management
---

# Organizations Cost Strategy

AWS Organizations is primarily an account governance tool, but it has significant cost implications. The key features that affect billing are consolidated billing, volume discounts, and cost allocation via SCPs.

## Consolidated Billing

When you enable consolidated billing in an Organization, all member accounts send their bills to the payer account. The payer account sees a single monthly bill, and member accounts see their own spend transparently.

**Benefits:**
1. **Single invoice** — one bill to pay, one payment method
2. **Volume discounts** — certain tier discounts apply across the organization based on total spend
3. **RI/SP sharing** — Reserved Instances and Savings Plans purchased in the payer account can be shared with member accounts
4. **Free tier sharing** — each account gets its own free tier, but unused free tier from one account doesn't transfer

**Important:** Being in an Organization doesn't automatically mean you share discounts. Only the payer account can purchase RIs/SPs that are shared. Member accounts can purchase their own, but those don't share.

## Volume Discounts

AWS has volume-based pricing tiers. With consolidated billing, the organization's total spend counts toward the tier:

| Spend Level | Additional Discount |
|------------|-------------------|
| $0-$150K/month | 0% (baseline) |
| $150K-$500K | 3% off select services |
| $500K-$1M | 7% off select services |
| $1M+ | 10% off select services |

These discounts apply to select services (EC2, S3, etc.) and are applied to the payer account's bill. The discount tiers are not published for all services — talk to your AWS TAM for specific discount schedules.

## RI/SP Sharing Across Accounts

When you buy RIs or Savings Plans in the payer account with the "Share RI/SP" option enabled:
- RIs/SPs are shared with all member accounts in the Organization
- Each account can use the shared RI/SP capacity
- Usage is tracked per account via the RI/SP utilization report

**How it works:** You buy 100 m6i.large RIs in the payer account. A member account in the Organization spins up 50 m6i.large instances — those 50 instances are covered by the shared RI pool, even though the member account didn't buy them.

**Benefit:** Individual member accounts don't need to buy their own RIs for baseline capacity — the payer account's RI pool covers shared baseline usage.

**Limitation:** Shared RIs cover the capacity, but member accounts still pay their own compute rates (which are the discounted RI rates, not On-Demand rates).

## SCPs for Cost Governance

Service Control Policies (SCPs) can enforce cost-related governance at the Organization or OU level. They restrict what member accounts can do, regardless of IAM permissions.

**Cost-related SCP examples:**

```json
// Deny creating resources in expensive regions
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "StringLike": {
      "aws:RequestedRegion": ["af-south-1", "eu-south-1"]
    }
  }
}

// Deny EC2 instance types larger than a certain size (prevent expensive instance creation)
{
  "Effect": "Deny",
  "Action": "ec2:RunInstances",
  "Resource": "arn:aws:ec2:*:*:instance/*",
  "Condition": {
    "NumericGreaterThan": {
      "ec2:InstanceType": "m6i.4xlarge"
    }
  }
}

// Deny creation of resources without required cost tags
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "Null": {
      "aws:RequestTag/Environment": true
    }
  }
}

// Deny certain services (e.g., no Redshift, no ElastiCache in dev accounts)
{
  "Effect": "Deny",
  "Action": "redshift:*",
  "Resource": "*"
}
```

## Tag Policies for Cost Allocation

AWS Organizations Tag Policies let you enforce consistent tagging across all accounts. A tag policy applied to an OU requires all resources in that OU to have specific tags with specific allowed values.

**Example tag policy:**
```json
{
  "tags": {
    "Environment": {
      "tag_key": {
        "是否符合": "enforce",
        "values": [
          "prod",
          "staging",
          "dev"
        ]
      }
    },
    "Team": {
      "tag_key": {
        "是否符合": "enforce"
      }
    }
  }
}
```

This ensures all resources in the Organization have `Environment` set to one of the allowed values and `Team` is always present. Cost allocation by tag then works across the entire Organization without gaps.

## Multi-Payer Billing

For large enterprises, Organizations supports multiple payer accounts — each paying for different parts of the organization. This is useful when:
- Different business units have separate budgets
- Regulatory requirements mandate separate billing
- Different entities within a conglomerate have independent finance relationships

**Implementation:** A management account can designate member accounts as "payer accounts" for specific services or OUs. This is an advanced feature — work with AWS to implement correctly.

## OU Structure for Cost Management

A common Organization structure for cost management:

```
Root
├── Core (payer account, shared services)
├── Platform (dev, staging, prod)
│   ├── Dev (low cost controls, SCPs to limit expensive resources)
│   ├── Staging (medium cost controls)
│   └── Prod (fewer restrictions, more budget visibility)
├── Data (large data workloads, separate budget tracking)
├── Security (security tooling, separate budget)
└── Sandboxes (sandbox accounts for experimentation, tight cost controls)
```

Each OU can have its own SCPs limiting what can be created and how. Sandbox accounts might be denied from creating anything beyond $100/month of resources. Production accounts might have fewer restrictions but mandatory budget alerts at lower thresholds.

## Cost Allocation with Organizations

1. **Enable cost allocation tags** in the payer account
2. **Apply tags to all resources** via SCPs and CI/CD pipelines
3. **Create member-specific budgets** in each linked account
4. **Use Cost Explorer** with Organization view for cross-account visibility

The payer account has full visibility into all member account spend. Member accounts see only their own spend unless granted read access to the management account.

## References

- **Homepage:** https://aws.amazon.com/organizations/
- **Documentation:** https://docs.aws.amazon.com/organizations/latest/userguide/
- **Pricing:** https://aws.amazon.com/organizations/pricing/

## Pricing Examples

**Scenario 1:** A 25-account AWS Organization with consolidated billing. The management account buys 3-year All Upfront Compute SPs covering $200/hour of spend. Each linked account automatically gets the SP discount applied — no manual sharing needed. Monthly org spend on compute is $220K, SPs cover $146K (73%), On-Demand covers the rest. Total annual compute bill: ~$2.1M vs $3.2M without SPs.

**Scenario 2:** An enterprise with separate business units (BU) for finance, engineering, and marketing. They structure OUs by BU and set SCPs restricting sandbox accounts to $500/month max via budget SCPs. Each BU has its own payer relationship for chargeback. Linked accounts exceeding their OU budget are blocked from creating resources via SCP evaluation.

## Nuggets & Gotchas

- **Consolidated billing doesn't automatically share RIs/SPs across accounts:** You must enable the "RI/SP sharing" setting in the Organizations console. Without it, each account's RIs only cover that account's usage.
- **SCP evaluation happens before resource creation:** An SCP blocking certain instance types or regions is enforced at the API level — the resource never gets created. This is more effective than auditing after the fact.
- **Organizations pricing discounts are tiered:** AWS provides volume discounts based on total monthly spend across the org. The more you spend, the higher the tier — but these tiers are not always visible in Cost Explorer.
- **Linked accounts inherit the payer account's tax settings:** If your payer account is set up for a specific tax regime, linked accounts inherit that. This can cause issues with VAT reporting for EU-based orgs with US payers.
- **Organizational units can be nested up to 5 levels deep:** This seems like a lot but large enterprises can hit this limit with fine-grained OU structures. Plan your OU hierarchy with growth in mind.
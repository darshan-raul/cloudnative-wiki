---
title: AWS Management & Governance
description: AWS management and governance services — Organizations for multi-account management, Control Tower for landing zones, CloudFormation for infrastructure as code, CDK for programmatic IaC, CLI for automation, and Systems Manager for operational management.
tags:
  - aws
  - management
  - governance
---

# AWS Management & Governance

AWS provides services for managing multiple accounts, governing infrastructure as code, automating operations, and maintaining compliance across your organization.

## Service Map

| Service | What It Does | When to Use |
|---------|-------------|-------------|
| [[organizations/README|Organizations]] | Hierarchical account management, SCPs, consolidated billing | Multi-account AWS environments |
| [[control-tower/README|Control Tower]] | Pre-configured landing zone with guardrails | New multi-account setup |
| [[cloudformation/README|CloudFormation]] | YAML/JSON IaC for AWS resources | Infrastructure provisioning |
| [[cdk/README|CDK]] | Programmatic IaC (TypeScript, Python, Java) | Developers who prefer code over YAML |
| [[cli/README|CLI]] | Unified tool for AWS API access | Automation, scripting, CI/CD |
| [[systems-manager/README|Systems Manager]] | Patch management, run commands, session manager, inventory | Day-2 operations, fleet management |

## Section Architecture

```
AWS Organizations (Root)
├── Security OU
│   ├── Security Account
│   └── Log Archive Account
├── Infrastructure OU
│   ├── Network Account
│   └── Shared Services Account
├── Production OU
│   ├── Prod Account
│   └── Staging Account
└── Development OU
    └── Dev Account

Control Tower → Enforces guardrails across OUs
CloudFormation → Provisions resources in each account
Systems Manager → Operates running fleets
```

## How These Services Relate

**Organizations** is the foundation — it creates the account hierarchy and enables SCPs for access control. **Control Tower** sits on top of Organizations and sets up a pre-configured landing zone with preventive/detective guardrails. **CloudFormation** and **CDK** provision resources within accounts. **CLI** provides the command-line interface for all AWS APIs. **Systems Manager** manages the operational aspects of running EC2 instances and other resources.

## References

- **Homepage:** https://aws.amazon.com/products-management-tools/
- **Documentation:** https://docs.aws.amazon.com/organizations/
- **Pricing:** https://aws.amazon.com/organizations/pricing/

## Nuggets & Gotchas

- **Organizations SCPs don't affect the management account itself:** The management account (payer account) is not affected by Service Control Policies. You cannot restrict what the management account can do via SCPs.
- **CloudFormation stack sets require a trust relationship:** To deploy across accounts via CloudFormation StackSets, the target accounts must first trust the administrative account. This is established via AWS RAM or within the StackSet itself.
- **Systems Manager requires SSM Agent on EC2 instances:** If an EC2 instance doesn't have SSM Agent installed and running, Systems Manager cannot manage it. For Amazon Linux 2 and recent AMIs, SSM Agent is pre-installed.
- **AWS CLI credentials take precedence over instance profile:** If you configure AWS CLI credentials (via `aws configure`) on an EC2 instance that also has an instance profile, the CLI credentials take precedence. This can cause unexpected behavior in automation scripts.
- **Control Tower creates its own CloudTrail and Config rules:** When you set up Control Tower, it enables CloudTrail in all accounts and creates AWS Config rules. This has cost implications — monitor CloudTrail log volume across all accounts.
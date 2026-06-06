---
title: Cost Allocation Tags
description: AWS cost allocation tags — user-defined tags, AWS-generated tags, tag enforcement via SCPs, AWS Config, and tag policy strategies
tags:
  - aws
  - cost-management
---

# Cost Allocation Tags

Cost allocation tags let you categorize AWS resources by metadata, then group and analyze spending by those categories. Without tags, you see spend by service and account. With tags, you see spend by environment, application, team, or any custom dimension.

## Types of Tags

### AWS-Generated Tags

These are automatically applied by AWS to supported resources. They start with `aws:` prefix:

| Tag | What it tracks |
|-----|---------------|
| `aws:createdBy` | IAM user/role that created the resource |
| `aws:cloudformation:stack-name` | CloudFormation stack that created the resource |
| `aws:cloudformation:logical-id` | CloudFormation logical resource ID |
| `aws:RequestId` | The API request that created the resource |
| `aws:region` | Region (implicit in the resource metadata) |

AWS-generated tags are automatically activated for cost allocation — you don't need to enable them.

### User-Defined Tags

Custom tags you apply yourself. Common examples:
```
Environment = {prod, staging, dev, qa}
Application = {api, frontend, payments, auth}
Team = {platform, data-eng, frontend}
Owner = {sre-team, product-team}
CostCenter = {1001, 1002, 1003}
Project = {apollo11, llmforsres, cloudnative-wiki}
```

User-defined tags must be **activated** in the Billing console before they appear in Cost Explorer.

## Activating Tags

1. AWS Console → Billing → Cost Allocation Tags
2. Select the tag keys you want to activate
3. Activation takes 24 hours to take effect in Cost Explorer

**Note:** Only the AWS account that pays the bill (payer account in an Organization) can activate tags. Linked accounts see their own resource tags but can't activate them.

## Tag Inheritance

Tags do NOT automatically inherit from parent resources:

- A tag on an EC2 instance does NOT apply to the EBS volumes attached to it
- A tag on a VPC does NOT apply to subnets, ENIs, or security groups
- A tag on an ECS cluster does NOT apply to task definitions or individual tasks

**Implication:** If you tag your prod VPC `Environment=prod`, the RDS instance inside it won't automatically show `Environment=prod` in Cost Explorer unless you explicitly tag the RDS instance.

**Exceptions (automatic inheritance):**
- Resources created by CloudFormation inherit stack-level tags
- Resources created by Terraform can inherit tags from the provider
- Some services support resource group propagation

**Tag policies** (AWS Organizations) can enforce tag inheritance across an OU, but this is governance, not automatic.

## Tag Enforcement Strategies

### SCP (Service Control Policy)

An SCP at the Organization or OU level can deny resource creation without required tags:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnforceEnvironmentTag",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "Null": {
          "aws:RequestTag/Environment": true
        }
      }
    }
  ]
}
```

This blocks any resource creation that doesn't include `Environment` tag. More specific versions can target specific resource types.

### AWS Config Rules

AWS Config can detect non-compliant resources:
- `required-tags` managed rule checks for presence of specified tags
- `aws-config-rules` can auto-remediate by applying tags when resources are created
- Non-compliant resources can trigger SNS notifications

### CI/CD Tag Injection

In CI/CD pipelines (CodePipeline, GitHub Actions), tag resources at creation time:
- Terraform `tags` block applies tags to all resources
- CloudFormation `Tags` property on each resource
- AWS CLI `--tag` flags on `run-instances`, `create-db-instance`, etc.

## Common Tagging Pitfalls

**Inconsistent tag values.** `env=prod`, `environment=Production`, `ENV=PROD` all count as different tags. Pick a convention and enforce it. Tools like AWS Tag Editor can bulk-rename tags but it's painful.

**Inherited tags not working.** Don't assume a VPC tag automatically applies to the RDS inside it. Verify by searching Cost Explorer.

**Case sensitivity.** `Costcenter` and `CostCenter` are different tags. AWS treats them as case-sensitive.

**Tag limits.** 50 tags per resource, tag keys max 128 characters, tag values max 256 characters. Most workloads won't hit this but good to know.

**Deleting tags doesn't retroactively remove them from billing data.** If you delete the `Environment` tag from all resources today, Cost Explorer will still show historical spend tagged as `Environment=prod` for past months.

## Tag-Based Cost Analysis Workflow

1. Activate tags in Billing console
2. Wait 24 hours for activation
3. In Cost Explorer, filter/group by the tag key (e.g., `Application`)
4. See spend by application across all accounts
5. Set up Cost Budgets with tag filters (e.g., alert if `Application=payments` exceeds $X)
6. Use Cost Anomaly Detection with tag context to identify which application's spend spiked

## References

- **Homepage:** https://aws.amazon.com/cost-management/cost-allocation/
- **Documentation:** https://docs.aws.amazon.com/cost-management/latest/userguide/configure-cost-tags.html
- **Pricing:** https://aws.amazon.com/cost-management/cost-allocation/pricing/

## Pricing Examples

**Scenario 1:** A 40-account AWS Organization uses a `Project` tag consistently across all resources. Finance activates the tag in Billing, and within a week they have a per-project cost breakdown across all accounts. The `payments-service` project is $180K/month — 3x what it was 6 months ago. Tag data reveals the growth is 15 new micro-services added by a different team. Now cost attribution is clear and chargeback is possible.

**Scenario 2:** A SaaS company uses `Environment=production|development|testing` and `Team=backend|frontend|platform` tags on all resources. Their Cost Explorer breakdown shows the `backend-team` spends $45K/month, of which $28K is production and $17K is development. They set a budget alert at $15K for the development tag to catch runaway test resources before they accumulate.

## Nuggets & Gotchas

- **Tags activated in Billing only apply going forward:** Historical data is not retroactively tagged. You can't see last month's spend by a new tag — only from the activation date forward.
- **AWS-generated tags take priority over user-defined tags:** `aws:createdBy`, `aws:owner`, `aws:region` are automatically applied and appear in Cost Explorer even without activation. Activate them in Billing to use them in reports.
- **Resources created by Lambda inherit the Lambda's tags only if you configure it:** By default, resources created by Lambda (e.g., DynamoDB tables, S3 buckets) don't inherit the Lambda's tags. Use `tag: true` in Lambda's DLQ configuration or a resource creation wrapper.
- **SCP tag policies apply to accounts within the OU:** An SCP requiring `Project` tag doesn't enforce it on the payer account itself (if it's in the same OU). The payer account is often exempt from OU-level SCPs.
- **Cost allocation tags don't work for every resource type:** Some resources (notably some third-party marketplace resources, and some legacy AWS resources) don't support tagging. Check the [tag support matrix](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/allocation-tag-support.html) before building a showback model.
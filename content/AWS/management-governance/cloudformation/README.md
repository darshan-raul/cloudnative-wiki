---
title: AWS CloudFormation
description: AWS CloudFormation — infrastructure as code (IaC) using YAML or JSON templates. Stacks, stack sets, change sets, drift detection, and resource provisioning.
tags:
  - aws
  - management
  - infrastructure-as-code
  - cloudformation
---

# AWS CloudFormation

CloudFormation is AWS's infrastructure as code (IaC) service. You define AWS resources in a YAML or JSON template, and CloudFormation provisions them in a deterministic, repeatable way.

## Core Concepts

### Template Structure

A CloudFormation template describes your infrastructure:

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: VPC with public and private subnets

Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: "10.0.0.0/16"
      EnableDnsHostnames: true
      EnableDnsSupport: true

  PublicSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: "10.0.1.0/24"
      AvailabilityZone: !Select [0, !GetAZs ""]

Outputs:
  VPCId:
    Description: ID of the VPC
    Value: !Ref VPC
```

### Intrinsic Functions

CloudFormation provides built-in functions for dynamic values:

| Function | Purpose | Example |
|----------|---------|---------|
| `!Ref` | Reference a resource's physical ID | `!Ref VPC` |
| `!GetAtt` | Get an attribute of a resource | `!GetAtt EC2Instance.PublicIp` |
| `!Sub` | Substitute variables in a string | `${AWS::StackName}` |
| `!If` | Conditional value | `!If [UseEncryption, true, false]` |
| `!Equals` | Compare two values | `!Equals !Ref Environment, prod` |
| `!Select` | Pick an item from a list | `!Select [0, !GetAZs ""]` |

### Stack Operations

**Create stack:** Provisions all resources in the template
**Update stack:** Modifies existing resources (uses Change Sets for preview)
**Delete stack:** Tears down all resources (deletion policy controls what happens to resources)

```
Create Stack:
  Template → CloudFormation → AWS API calls → Resources created
            ↓
        Stack events (create in progress, complete)

Update Stack:
  Template → Change Set → Review → Execute → Resources updated

Delete Stack:
  CloudFormation → API calls → Resources deleted
                   (or Snapshot/Retain/Delete based on DeletionPolicy)
```

### Change Sets

Before updating a stack, create a change set to preview what will change:

```bash
aws cloudformation create-change-set \
  --stack-name my-vpc \
  --template-body file://vpc.yaml \
  --change-set-type UPDATE
```

This lets you review additions, modifications, and deletions before executing.

### Drift Detection

CloudFormation can detect when actual infrastructure has drifted from the template:

```bash
aws cloudformation detect-stack-drift --stack-name my-vpc
aws cloudformation describe-stack-drift-detection-status --stack-name my-vpc
```

Drift detection compares actual resource properties against the template. Useful for catching configuration changes made outside CloudFormation.

### Stack Policies

A stack policy controls who can update which resources:

```json
{
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "Update:*",
      "Principal": "*",
      "Resource": "LogicalResourceId/ProductionDatabase"
    },
    {
      "Effect": "Allow",
      "Action": "Update:*",
      "Principal": "*",
      "Resource": "*"
    }
  ]
}
```

This prevents accidental updates to the ProductionDatabase resource.

## StackSets

StackSets deploy a CloudFormation template across multiple accounts and regions simultaneously.

```
StackSet (one template)
  ├── Account 111122223333, Region us-east-1 → Stack Instance 1
  ├── Account 111122223333, Region eu-west-1 → Stack Instance 2
  ├── Account 444455556666, Region us-east-1 → Stack Instance 3
  └── Account 444455556666, Region eu-west-1 → Stack Instance 4
```

**Requirements:**
- Target accounts must trust the StackSet administrator account
- Use AWS RAM to share the StackSet with target accounts, or configure trust manually

**Administration:**
```bash
# Create StackSet
aws cloudformation create-stack-set \
  --stack-set-name cross-account-vpc \
  --template-body file://vpc.yaml \
  --administration-role-arn arn:aws:iam::111122223333:role/CFNRole

# Create stack instances (deploy to accounts/regions)
aws cloudformation create-stack-instances \
  --stack-set-name cross-account-vpc \
  --accounts [111122223333, 444455556666] \
  --regions [us-east-1, eu-west-1]
```

### Stack Operations with StackSets

- **Create:** Deploys template to all accounts/regions
- **Update:** Updates all stack instances
- **Stop:** Cancels an in-progress operation
- **Delete:** Removes all stack instances

## Drift Detection and Configuration Management

CloudFormation drift detection checks whether actual infrastructure matches templates. Resources that were updated outside CloudFormation (via console, CLI, or SDK) show as "drifted."

```bash
# Detect drift on all stacks in an organization
aws cloudformation detect-stack-drift --stack-name my-stack
aws cloudformation describe-stack-resource-drifts --stack-name my-stack
```

Drifted resources can be corrected by updating the stack (CloudFormation applies the template) or by updating the template to match actual state.

## Nested Stacks

Nested stacks are stacks created from another stack. Use nested stacks to reuse common templates:

```
Root Stack (vpc.yaml)
  ├── Nested: networking/public-subnet.yaml
  ├── Nested: networking/private-subnet.yaml
  └── Nested: security/security-groups.yaml
```

```yaml
Resources:
  PublicSubnet:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: https://s3.amazonaws.com/mybucket/templates/public-subnet.yaml
      Parameters:
        VPCId: !Ref VPC
        AZ: !Select [0, !GetAZs ""]
```

## DeletionPolicy

Controls what happens to a resource when the stack is deleted:

| Policy | Behavior |
|--------|----------|
| `Delete` (default) | Resource is deleted |
| `Retain` | Resource is preserved (not deleted) |
| `Snapshot` | Snapshot is created before deletion (for RDS, EBS, etc.) |

```yaml
Database:
  Type: AWS::RDS::DBInstance
  DeletionPolicy: Snapshot
```

## AWS SAM (Serverless Application Model)

AWS SAM is an extension of CloudFormation for serverless applications:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31

Resources:
  MyFunction:
    Type: AWS::Serverless::Function
    Properties:
      Handler: index.handler
      Runtime: python3.11
      CodeUri: ./
      Events:
        Api:
          Type: Api
          Properties:
            Path: /api
            Method: get
```

SAM translates to CloudFormation and adds additional resource types for serverless (Lambda, API Gateway, DynamoDB).

## References

- **Homepage:** https://aws.amazon.com/cloudformation/
- **Documentation:** https://docs.aws.amazon.com/cloudformation/
- **Pricing:** https://aws.amazon.com/cloudformation/pricing/

## Pricing Examples

**Scenario 1:** A DevOps team managing 50 CloudFormation stacks across 3 AWS accounts (dev, staging, prod). Each stack creates ~20 resources. StackSets are used to deploy a common VPC template across all accounts. CloudFormation itself is free — you pay only for the resources created. Total: $0/month for CloudFormation.

**Scenario 2:** Using CloudFormation to provision and teardown an EMR cluster for a nightly ETL job. Cluster runs 4 hours, provisioned via CloudFormation, then stack is deleted. CloudFormation tracks all resources and deletes them cleanly. Without CloudFormation, manual cleanup of EMR, IAM roles, S3 buckets would fail regularly, causing resource leaks.

## Nuggets & Gotchas

- **CloudFormation uses eventual consistency — concurrent operations fail:** If you try to update a stack while another update is in progress, CloudFormation rejects the operation. Use a stack policy to prevent concurrent updates, or use a locking mechanism in your CI/CD pipeline.
- **Stack update failures can leave resources in an inconsistent state:** If a CloudFormation update fails partway through (e.g., a database update succeeds but an EC2 update fails), the stack rolls back automatically. But if the rollback also fails, the stack can be stuck in UPDATE_ROLLBACK_FAILED — you must then use `aws cloudformation continue-update-rollback` or contact AWS support.
- **CloudFormation doesn't track resources created outside itself:** If you manually create an S3 bucket in the Console and then add it to a CloudFormation template, CloudFormation won't detect it as an existing resource — it will try to create a new bucket with the same name and fail. Use `!If` or `!Ref` with conditionals to handle existing resources.
- **Nested stack outputs are not directly accessible from the parent stack — you must pass them as parameters:** If nested stack A creates a VPC ID and nested stack B needs that VPC ID, you must pass the VPC ID as a parameter from the root stack to nested stack B. There's no direct cross-nested-stack reference.
- **Change sets don't show all changes:** Change sets don't preview changes to drift-detected resources or to resources managed by AWS IAM policies (e.g., a role that CloudFormation creates but the template doesn't own). Always review the full change set output.
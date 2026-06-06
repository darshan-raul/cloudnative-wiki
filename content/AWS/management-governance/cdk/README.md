---
title: AWS CDK
description: AWS CDK (Cloud Development Kit) — programmatic infrastructure as code using TypeScript, Python, Java, and .NET. Constructs, stacks, apps, and synthesis.
tags:
  - aws
  - management
  - cdk
---

# AWS CDK (Cloud Development Kit)

CDK lets you define AWS infrastructure in code (TypeScript, Python, Java, .NET) and synthesize it into CloudFormation templates. You write application code that generates CloudFormation — combining the productivity of programming languages with the safety of CloudFormation.

## Core Concepts

### Constructs

A construct is the basic building block of CDK. It's a CloudFormation resource (or group of resources) defined in code.

```typescript
import { Construct } from 'constructs';
import { Stack, StackProps } from 'aws-cdk-lib';
import { Vpc } from 'aws-cdk-lib/aws-ec2';

class MyStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);
    new Vpc(this, 'MyVpc', {
      cidr: '10.0.0.0/16',
      maxAzs: 2,
    });
  }
}
```

### Construct Levels

| Level | Example | Use |
|-------|---------|-----|
| L1 | `CfnVPC`, `CfnSubnet` | Raw CloudFormation resources (100% feature coverage) |
| L2 | `Vpc`, `Instance`, `Bucket` | Opinionated, higher-level (recommended) |
| L3 | `eks.Cluster`, `aurora.DatabaseCluster` | Full application patterns |

### Stacks and Apps

- **Stack:** A unit of deployment. Maps to one CloudFormation stack.
- **App:** A container that holds multiple stacks.

```typescript
import { App } from 'aws-cdk-lib';

const app = new App();
new MyStack(app, 'dev-stack', { env: { region: 'us-east-1' } });
new MyStack(app, 'prod-stack', { env: { region: 'us-east-1' } });
```

### CDK App Structure

```
my-cdk-app/
  ├── bin/
  │   └── app.ts              ← Entry point, creates stacks
  ├── lib/
  │   ├── vpc-stack.ts         ← VPC stack
  │   ├── compute-stack.ts     ← EC2/ECS cluster
  │   └── database-stack.ts    ← RDS cluster
  ├── cdk.json                 ← CDK CLI configuration
  └── package.json
```

## CDK Workflow

```
1. Write code (TypeScript/Python/etc.)
         ↓
2. cdk synth                   ← Synthesize to CloudFormation template
         ↓ (produces cdk.out/*.template.json)
3. cdk diff                    ← Compare with deployed stack
         ↓
4. cdk deploy                  ← Deploy via CloudFormation
```

```bash
cdk synth                      # Generate CloudFormation template
cdk diff                       # Show differences from deployed stack
cdk deploy                     # Deploy changes
cdk destroy                    # Tear down stack
cdk doctor                     # Check CDK environment
```

## Cross-Stack References

CDK makes referencing resources across stacks easy:

```typescript
// vpc-stack.ts
const vpc = new Vpc(this, 'Vpc', { ... });
new CfnOutput(this, 'VpcId', { value: vpc.vpcId });

// compute-stack.ts
const vpc = Vpc.fromLookup(this, 'Vpc', {
  vpcId: 'vpc-xxxxx',  // or use export/import pattern
});
```

### Cross-Stack Import/Export

```typescript
// Stack A exports a value
new CfnOutput(this, 'VpcId', {
  value: vpc.vpcId,
  exportName: 'my-vpc-id',
});

// Stack B imports it
const vpcId = Fn.importValue('my-vpc-id');
```

## CDK Testing

CDK provides a testing framework (`@aws-cdk/assert`) for validating synthesized stacks:

```typescript
import { Template } from 'aws-cdk-lib/assertions';

const template = Template.fromStack(myStack);

template.hasResourceProperties('AWS::EC2::VPC', {
  CidrBlock: '10.0.0.0/16',
});

template.hasResource('AWS::EC2::Instance', 1);
```

### Integ Tests and Snapshot Testing

```typescript
import { IntegTest } from '@aws-cdk/integ-tests';

const integ = new IntegTest(app, 'Integ', {
  testCases: [myStack],
});
```

## CDK Pipelines

CDK Pipelines is a construct for CI/CD with CodePipeline:

```typescript
new Pipeline(this, 'MyPipeline', {
  synth: new CodePipelineStep('Synth', {
    input: CodePipelineSource.gitHub('myorg/myrepo', 'main'),
    commands: ['npm ci', 'npx cdk synth'],
  }),
  stages: [
    new Stage(this, 'Dev', { env: { account: '111122223333', region: 'us-east-1' } }),
    new Stage(this, 'Prod', { env: { account: '444455556666', region: 'us-east-1' } }),
  ],
});
```

## Aspects

Aspects apply operations to all constructs in a tree. Used for governance:

```typescript
// Apply a tag to all resources
const tagAspect = new Tag('Environment', 'production');
 Aspects.of(app).add(tagAspect);

// Check all S3 buckets are encrypted
class S3EncryptionChecker implements IAspect {
  visit(node: IConstruct) {
    if (node instanceof CfnBucket) {
      // enforce encryption
    }
  }
}
```

## CDK Context and Caching

CDK uses context values for dynamic inputs (like available AZs). These are cached in `cdk.context.json`:

```bash
cdk context --reset            # Clear context cache
cdk list                       # List stacks
cdk metadata                  # Show metadata
```

## Comparison: CDK vs CloudFormation vs Terraform

| | CDK | CloudFormation | Terraform |
|--|--|--|--|
| Language | TypeScript, Python, Java, .NET | YAML/JSON | HCL |
| State management | CloudFormation (stateless) | CloudFormation | State file |
| Drift detection | Yes (via CloudFormation) | Yes | Yes |
| Drift correction | Limited | Yes | Yes |
| Community | Growing | Large (AWS-native) | Largest |
| Use when | Developers comfortable with code | Simple templates, AWS-native | Multi-cloud, complex state |

## References

- **Homepage:** https://aws.amazon.com/cdk/
- **Documentation:** https://docs.aws.amazon.com/cdk/
- **Pricing:** https://aws.amazon.com/cdk/pricing/ (free — you pay for resources created)

## Pricing Examples

**Scenario 1:** A team of 5 developers using CDK to manage 20 CloudFormation stacks. CDK itself is free. Developer productivity: writing TypeScript vs YAML. A complex VPC with 10 subnets, route tables, NAT Gateways, and endpoints takes 2 days to write in YAML CloudFormation, 1 day in CDK TypeScript (with better IDE support, type checking, and reusable constructs). Saved: 1 day × 5 developers = 5 days of engineering time per major infrastructure change.

**Scenario 2:** A platform team building a "VPC construct" library for internal use. The library is published as an npm package. 50 product teams import the library and deploy VPCs with 3 lines of code. Without CDK: each team writes their own VPC CloudFormation (duplicated effort, inconsistencies). With CDK library: consistent VPCs across 50 teams, single source of truth for network standards. Engineering time saved per team: ~2 days × 50 = 100 days of duplicated work avoided.

## Nuggets & Gotchas

- **CDK generates CloudFormation — so all CloudFormation limitations apply:** CDK cannot create resources that CloudFormation doesn't support. If a service's API isn't in CloudFormation, CDK can't manage it directly. Use the escape hatch (`node.defaultChild`) to access L1 constructs.
- **CDK context values are per-environment — not in source control:** CDK caches available AZs, account IDs, etc. in `cdk.context.json`. If you commit this file, CI/CD works consistently. If you don't, CI/CD may use different AZs than local (causing stack drift).
- **`cdk destroy` doesn't clean up everything:** CDK will delete the CloudFormation stack, but resources outside the stack (like S3 buckets created with `bucketName` or DynamoDB tables) may fail to delete due to Retain DeletionPolicy or protection settings. Always verify deletion.
- **Constructs without scope need an explicit `scope` in constructor:** When creating L2 constructs, always pass `this` as the first argument (scope). Forgetting it causes the resource to be created in the wrong stack or without proper hierarchy.
- **CDK synth uses the default AWS profile's region — stacks may deploy to the wrong region:** If you have multiple AWS profiles configured, CDK uses the `default` profile's region. Always specify `env` in stack props or set `AWS_DEFAULT_REGION` in your environment.
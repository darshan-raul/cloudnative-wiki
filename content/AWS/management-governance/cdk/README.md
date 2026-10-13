---
title: "AWS Cloud Development Kit"
description: "CDK constructs generate CloudFormation templates from code."
tags:
  - aws/management-governance
date: 2026-10-12
---

# AWS Cloud Development Kit

CDK constructs generate [[AWS/management-governance/cloudformation/README|CloudFormation]] templates from code. It is an infrastructure programming model, not a way around template lifecycle, IAM permissions or deployment review.

Prerequisites: CloudFormation, [[AWS/management-governance/cli/README|CLI profiles]] and the selected language/runtime.

## Constructs, context and synthesis

Apps contain stacks; constructs model resources and higher-level patterns. Distinguish L1 resource definitions from L2/L3 abstractions, and inspect generated defaults rather than assuming they match production security. Pin dependencies and runtime/toolchain versions.

Commit relevant cdk.context.json to source control for reproducible synthesis; it caches lookup values, not credentials. Review context when environments change. Never commit secret values. An isolated synth run can still need valid lookup context/credentials unless the app is designed to avoid lookups.

Bootstrap resources support deployment/assets and need scoped trust/permissions. Cross-account/Region deployment should declare its environment and role path explicitly. Custom resources can call APIs beyond standard CloudFormation resources, but introduce permissions, retry/idempotency and deletion responsibilities.

## Assertions and deployment lifecycle

Use the current CDK assertions library for the pinned language/version. In TypeScript, resourceCountIs(type, count) counts resources; hasResource(type, 1) is not the correct count assertion. Test security-sensitive generated properties, not only successful synthesis.

```bash
npx cdk synth
npx cdk diff
```

These CLI examples require an existing CDK project and pinned local dependencies. They are not a complete application and may perform context lookups. Review logical-ID changes, replacements, permissions and retained resources before deployment.

## Review/rollback exercise

Create a minimal sandbox app following the official language-specific starter, with a budget and a nonproduction deployment role. Add one resource and assert its count plus security property. Synthesize and inspect the CloudFormation output; deliberately weaken a property and confirm the test fails.

Diff a harmless change, review it and deploy only into the authorized sandbox. Inspect stack events/outputs and compare desired versus actual state. Destroy the sandbox stack only after checking retention/deletion policies; inspect retained assets and bootstrap resources separately. Do not remove shared bootstrapping used by other stacks as generic cleanup.

## Constructs and a concrete minimal app

CDK L1 constructs expose CloudFormation resources; higher-level constructs add defaults/abstractions. Inspect synthesized output and assertions rather than assuming a high-level construct creates every application security dependency.

This TypeScript app is for an initialized project with a pinned CDK v2/toolchain. It creates a versioned, public-access-blocked bucket retained on stack deletion. Retention is deliberate: cleanup requires reviewing/removing disposable object versions separately.

```typescript
import { App, RemovalPolicy, Stack, StackProps } from "aws-cdk-lib";
import { BlockPublicAccess, Bucket } from "aws-cdk-lib/aws-s3";
import { Construct } from "constructs";

export class SandboxStorageStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);
    new Bucket(this, "SandboxBucket", {
      versioned: true,
      blockPublicAccess: BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.RETAIN,
    });
  }
}

const app = new App();
new SandboxStorageStack(app, "SandboxStorageStack");
```

This is an app source example, not a complete package/CI configuration or a deployed stack. Pin package versions, declare the target environment when needed and verify synthesis context/bootstrap requirements.

## Correct assertions and test workflow

In the matching initialized test project:

```typescript
import { App } from "aws-cdk-lib";
import { Template } from "aws-cdk-lib/assertions";
import { SandboxStorageStack } from "../lib/sandbox-storage-stack";

test("bucket is versioned and blocks public access", () => {
  const stack = new SandboxStorageStack(new App(), "TestStack");
  const template = Template.fromStack(stack);
  template.resourceCountIs("AWS::S3::Bucket", 1);
  template.hasResourceProperties("AWS::S3::Bucket", {
    VersioningConfiguration: { Status: "Enabled" },
    PublicAccessBlockConfiguration: {
      BlockPublicAcls: true,
      BlockPublicPolicy: true,
      IgnorePublicAcls: true,
      RestrictPublicBuckets: true,
    },
  });
});
```

The import path/test runner must match your project. Counting uses resourceCountIs, while properties use hasResourceProperties. Unit assertions cannot prove live permissions, network reachability or recovery.

## Context, assets and custom resources

Context caches lookup values for repeatable synthesis; commit appropriate cdk.context.json without secrets. Refresh lookups deliberately when environments change and review resulting diffs. Bootstrapping creates shared deployment/asset infrastructure with trust roles; don't destroy it as generic application cleanup.

Custom resources can call supported APIs not directly covered by ordinary resource types, but must implement safe create/update/delete, stable physical IDs, retries/idempotency and scoped roles. Code compilation is not proof the custom resource can recover from partial failure.

Use synth → assertions → diff/change review → sandbox deploy → live observation. Record logical-ID/resource replacement effects and retained assets. A code rename can trigger infrastructure replacement; treat it as a deployment decision.

## Worked two-stack reference and deployment order

Use an initialized TypeScript CDK v2 app in an isolated project, with a pinned `aws-cdk-lib`/`constructs` dependency lockfile and an approved sandbox deployment profile. For a new project, follow [the TypeScript starter](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-typescript.html). The code below is a **complete alternative app entry point**, not an extra invocation to append to the earlier single-stack example. Replace the generated app entry point with it and ensure `cdk.json` invokes that file. Do not rename an existing production app's stacks to run a lab.

```typescript
import { App, CfnOutput, RemovalPolicy, Stack, StackProps } from "aws-cdk-lib";
import { BlockPublicAccess, Bucket, IBucket } from "aws-cdk-lib/aws-s3";
import { StringParameter } from "aws-cdk-lib/aws-ssm";
import { Construct } from "constructs";

class LabStorageStack extends Stack {
  readonly bucket: Bucket;
  constructor(scope: Construct, id: string, props: StackProps) {
    super(scope, id, props);
    this.bucket = new Bucket(this, "Data", {
      versioned: true,
      blockPublicAccess: BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.RETAIN,
    });
    new CfnOutput(this, "BucketName", { value: this.bucket.bucketName });
  }
}

interface LabConfigProps extends StackProps {
  readonly sourceBucket: IBucket;
}
class LabConfigStack extends Stack {
  constructor(scope: Construct, id: string, props: LabConfigProps) {
    super(scope, id, props);
    new StringParameter(this, "BucketConfiguration", {
      parameterName: "/cloudnative-wiki/cdk/lab-bucket-name",
      stringValue: props.sourceBucket.bucketName,
    });
  }
}

const app = new App();
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};
const storage = new LabStorageStack(app, "WikiLabStorage", { env });
new LabConfigStack(app, "WikiLabConfig", { env, sourceBucket: storage.bucket });
```

The consumer stores the producer's generated bucket name, not a hard-coded guess. CDK creates the same-account/Region CloudFormation export/import and dependency. A configuration reference is not permission to read bucket objects. Keep both stacks in the same explicit environment for this demonstration; cross-account/Region sharing needs a different supported design.

```bash
aws sts get-caller-identity --profile sandbox
npx cdk synth --profile sandbox
npx cdk diff --profile sandbox WikiLabStorage WikiLabConfig
npx cdk deploy --profile sandbox WikiLabStorage WikiLabConfig
aws ssm get-parameter --profile sandbox \
  --name /cloudnative-wiki/cdk/lab-bucket-name \
  --query Parameter.Value --output text
aws cloudformation describe-stacks --profile sandbox --stack-name WikiLabStorage \
  --query 'Stacks[0].Outputs' --output json
```

Set the Region consistently on the profile. Bootstrap only if this approved environment needs it, using reviewed deployment trust and an exact account/Region target. Before deploy, inspect the synthesized S3 Versioning/PublicAccessBlockConfiguration, the export, consumer Fn::ImportValue and dependency; check the diff for replacements. Expected: the parameter equals the BucketName output. Try reading the parameter with a second identity lacking `ssm:GetParameter`; expect AccessDenied, not a missing bucket.

As a local failure experiment, remove `versioned: true` in the isolated app and use the earlier `hasResourceProperties` assertion for VersioningConfiguration; the assertion should fail. Restore the property before deployment. A passed synth/test is not evidence that the live profile can deploy or recover data.

Deleting or changing an exported value while the consumer still imports it is constrained by CloudFormation. Destroy the dedicated **consumer first**, then the producer after reviewing the diff/retention:

```bash
npx cdk destroy --profile sandbox WikiLabConfig
npx cdk destroy --profile sandbox WikiLabStorage
```

Inspect the retained private versioned bucket and remove only its reviewed disposable versions/bucket if retention is no longer required. Parameter deletion is owned by the consumer stack; shared bootstrap resources are not lab cleanup targets. Do not apply these names to existing unrelated stacks. [CDK references and cross-stack constraints](https://docs.aws.amazon.com/cdk/v2/guide/resources.html).

## IaC ownership comparison

| Concern                 | CDK                                                                            | CloudFormation                                                           | Terraform                                                                                       |
| ----------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| Desired state authoring | Language constructs synthesize templates                                       | YAML/JSON templates                                                      | Provider-backed configuration                                                                   |
| Deployment/state owner  | CloudFormation stacks plus CDK assets/context                                  | CloudFormation stack state                                               | Terraform state/backend and providers                                                           |
| Change evidence         | Generated template, assertions and diff/change review                          | Template/change set/events                                               | Plan plus provider/state interpretation                                                         |
| Drift/recovery          | Uses supported CloudFormation mechanisms; not automatic repair of every change | Detection has resource/property limits; repair is a deliberate operation | Refresh/plan/apply behavior depends on provider/configuration; not universal automatic recovery |
| Cross-unit dependency   | Stack references can synthesize exports/imports                                | Exports/imports have lifecycle constraints                               | Explicit configuration/state/data-source dependencies                                           |

No row promises a fixed engineering-time saving or automatic drift correction. Choose from team/tooling/provider and lifecycle requirements, and test retained-resource ownership separately.

## References

- [CDK context and reproducibility](https://docs.aws.amazon.com/cdk/v2/guide/context.html)
- [CDK testing](https://docs.aws.amazon.com/cdk/v2/guide/testing.html)
- [Custom resources](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.custom_resources-readme.html)
- [Bootstrapping](https://docs.aws.amazon.com/cdk/v2/guide/bootstrapping.html)

## Across the wiki

- [[DevOps/infrastructure-as-code/README|Infrastructure as Code]] — infrastructure as code (DevOps)
- [[Kubernetes/eks/automation/control-planes/ack|AWS Controllers for Kubernetes (ACK)]] — infrastructure as code (Kubernetes)
- [[DevOps/devsecops/stage2-build/10-iac-security|M10: Infrastructure-as-Code Security]] — infrastructure as code (DevOps)
- [[Kubernetes/eks/getting-started/cluster-creation|Cluster Creation]] — infrastructure as code (Kubernetes)

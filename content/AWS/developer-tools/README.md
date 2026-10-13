---
title: "AWS delivery pipeline"
description: "Build an artifact through CodeBuild and CodePipeline, deploy safely with versioned configuration and prove rollback."
tags:
  - cloud/aws/developer-tools
date: 2026-10-12
---

# AWS delivery pipeline

A delivery pipeline joins source, build/test, artifact and deployment stages. Infrastructure-as-code, source hosting and runtime deployment are distinct concerns. Start with [[AWS/compute/ecr|artifacts]], [[AWS/management-governance/cloudformation/README|CloudFormation]] and [[AWS/management-governance/cdk/README|CDK]].

## Ownership and security

CodePipeline orchestrates stages; CodeBuild runs builds/tests; CodeDeploy supports documented deployment targets and strategies. Choose a supported source integration and current product eligibility rather than relying on a stale source-service catalog.

Separate pipeline, build and deployment roles. Limit PassRole, artifact-bucket access, KMS and cross-account trust. Never put cloud credentials in build logs or repository files. Verify webhook/connection ownership and protect production approval paths.

## Small pipeline exercise

Prerequisites: a sandbox source repository with a tiny testable application, an approved connection, artifact storage/KMS configuration and least-privilege roles. Pipeline/build/artifact/runtime charges may apply.

1. Add a deterministic unit test and a build specification that fails on test errors.
2. Create a pipeline with source, CodeBuild and a sandbox deployment stage. Record artifact encryption, role and target configuration.
3. Commit a passing application change through your normal source workflow; verify source revision, build result, artifact digest and deployed version.
4. Submit an intentionally failing test change. The deploy stage must not run.
5. Deploy a sandbox version that fails health checks; verify the configured rollback or execute the documented rollback procedure.
6. Check audit events and demonstrate that a build role cannot directly mutate production.

These are learner instructions, not authorization for this remediation agent to commit, push or deploy.

### Worked target: private Lambda deployment through CloudFormation

This concrete pipeline uses a repository connection → CodeBuild → CloudFormation → a second CodeBuild health gate. Its target is `wiki-pipeline-greeting`, invoked directly with IAM, not a public API. Use a **new sandbox stack** `wiki-pipeline-lab` and keep previous known-good source revisions. Source commits/pushes below are actions for the learner through their normal workflow, not actions performed by this documentation change.

Prerequisites: an approved, AVAILABLE CodeConnections connection and repository/branch; a same-Region private artifact bucket with encryption and public access blocked; AWS CLI v2 and Python 3 locally. Choose the CodeBuild `aws/codebuild/standard:7.0` Linux image with Python 3.12 and confirm its current availability in [the image/runtime guide](https://docs.aws.amazon.com/codebuild/latest/userguide/available-runtimes.html). Deployment uses the supported `python3.13` Lambda runtime; confirm it in [the runtime table](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html) before creating resources.

Have the administrator provision these distinct lab roles and approve their resource scope; the pipeline does not create IAM roles:

| Role                  | Trust                          | Required scope                                                                                                                                                                       |
| --------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Pipeline              | `codepipeline.amazonaws.com`   | Use only the chosen connection; read/write the dedicated artifact prefix and KMS key; start/read the two projects; manage/read the named stack and pass only its CloudFormation role |
| Build                 | `codebuild.amazonaws.com`      | Read/write lab artifacts, key access and its own logs; **no** Lambda or CloudFormation mutation                                                                                      |
| Verify build          | `codebuild.amazonaws.com`      | Read lab artifacts/key, its own logs, and InvokeFunction only on `wiki-pipeline-greeting`                                                                                            |
| CloudFormation deploy | `cloudformation.amazonaws.com` | Manage only the named function/log group and pass only the chosen Lambda execution role                                                                                              |
| Lambda execution      | `lambda.amazonaws.com`         | CreateLogStream/PutLogEvents only under `/aws/lambda/wiki-pipeline-greeting`                                                                                                         |

Use the [[AWS/compute/lambda/README|Lambda trust/logging-policy recipe]] with the pipeline-specific role/group names; CloudFormation creates the group here, so do not pre-create it. The pipeline role also needs the CloudFormation action's documented artifact read/stack observation permissions; a KMS key policy must permit the intended roles, not just identity policies. Restrict PassRole service conditions. These administrator-provided account-specific policies are explicit prerequisites, not demonstrated by the artifact fixture. [Pipeline service-role contract](https://docs.aws.amazon.com/codepipeline/latest/userguide/how-to-custom-role.html).

Put these four files at the repository root. `app.py`:

```python
VERSION = "v1"

def handler(event, context):
    if not isinstance(event, dict) or not isinstance(event.get("name"), str):
        raise ValueError("name must be a string")
    return {"message": f"Hello, {event['name']}", "version": VERSION}
```

`test_app.py`:

```python
import unittest
import app

class GreetingTest(unittest.TestCase):
    def test_greeting(self):
        self.assertEqual(app.handler({"name": "learner"}, None),
                         {"message": "Hello, learner", "version": app.VERSION})
    def test_invalid(self):
        for event in ({"name": 42}, [], None):
            with self.assertRaises(ValueError):
                app.handler(event, None)

if __name__ == "__main__":
    unittest.main()
```

`package.py` constructs a CloudFormation JSON template (not an executable zip mislabeled as a template) and its parameter configuration:

```python
import hashlib
import json
import os
from pathlib import Path

code = Path("app.py").read_text(encoding="utf-8")
template = {
    "AWSTemplateFormatVersion": "2010-09-09",
    "Parameters": {"ExecutionRoleArn": {"Type": "String"}},
    "Resources": {
        "Logs": {"Type": "AWS::Logs::LogGroup", "Properties": {
            "LogGroupName": "/aws/lambda/wiki-pipeline-greeting", "RetentionInDays": 1}},
        "Greeting": {"Type": "AWS::Lambda::Function", "DependsOn": "Logs",
            "Properties": {"FunctionName": "wiki-pipeline-greeting",
                "Runtime": "python3.13", "Handler": "index.handler",
                "Role": {"Ref": "ExecutionRoleArn"}, "Timeout": 10,
                "MemorySize": 128, "Code": {"ZipFile": code}}},
    },
}
Path("template.json").write_text(json.dumps(template, sort_keys=True), encoding="utf-8")
Path("configuration.json").write_text(json.dumps({"Parameters": {
    "ExecutionRoleArn": os.environ["PIPELINE_LAB_EXECUTION_ROLE_ARN"]}}), encoding="utf-8")
print("template-sha256", hashlib.sha256(Path("template.json").read_bytes()).hexdigest())
```

Inline Python CloudFormation code is written as `index.py`, which is why Handler is `index.handler`, not `app.handler`. `buildspec.yml`:

```yaml
version: 0.2
phases:
  install:
    runtime-versions:
      python: 3.12
  build:
    commands:
      - python3 -m unittest -v test_app
      - python3 package.py
artifacts:
  files:
    - template.json
    - configuration.json
    - verify-buildspec.yml
```

Also save `verify-buildspec.yml`; it consumes BuildArtifact after deployment, checks actual Lambda behavior, and fails the pipeline on FunctionError or wrong output:

```yaml
version: 0.2
phases:
  build:
    commands:
      - aws lambda invoke --function-name wiki-pipeline-greeting --cli-binary-format raw-in-base64-out --payload '{"name":"learner"}' response.json > invoke.json
      - python3 -c 'import json; m=json.load(open("invoke.json")); r=json.load(open("response.json")); t=json.load(open("template.json")); scope={}; exec(t["Resources"]["Greeting"]["Properties"]["Code"]["ZipFile"],scope); assert "FunctionError" not in m; assert r==scope["handler"]({"name":"learner"},None), (m,r)'
```

Create two CodeBuild projects in the console: `wiki-pipeline-build` with Build role, CODEPIPELINE source/artifacts, the selected standard image, default `buildspec.yml`, and plaintext environment variable `PIPELINE_LAB_EXECUTION_ROLE_ARN` set to the dedicated non-secret ARN; `wiki-pipeline-verify` with Verify role, the same source/artifacts/image and buildspec override `verify-buildspec.yml`. Use SMALL compute, no privileged mode, no production VPC, and one-day dedicated log retention. Record each role/project ARN. [Buildspec artifact contract](https://docs.aws.amazon.com/codebuild/latest/userguide/build-spec-ref.html).

Save `pipeline.json`, replacing every uppercase placeholder consistently with the actual sandbox identifier. `OWNER/REPO` is the full connection repository name, not its HTTPS URL:

```json
{
  "pipeline": {
    "name": "wiki-delivery-lab",
    "roleArn": "PIPELINE_ROLE_ARN",
    "artifactStore": {
      "type": "S3",
      "location": "ARTIFACT_BUCKET",
      "encryptionKey": { "type": "KMS", "id": "ARTIFACT_KEY_ARN" }
    },
    "stages": [
      {
        "name": "Source",
        "actions": [
          {
            "name": "Repository",
            "actionTypeId": {
              "category": "Source",
              "owner": "AWS",
              "provider": "CodeStarSourceConnection",
              "version": "1"
            },
            "configuration": {
              "ConnectionArn": "CONNECTION_ARN",
              "FullRepositoryId": "OWNER/REPO",
              "BranchName": "LAB_BRANCH",
              "OutputArtifactFormat": "CODE_ZIP",
              "DetectChanges": "true"
            },
            "outputArtifacts": [{ "name": "SourceArtifact" }],
            "runOrder": 1
          }
        ]
      },
      {
        "name": "Build",
        "actions": [
          {
            "name": "TestAndPackage",
            "actionTypeId": {
              "category": "Build",
              "owner": "AWS",
              "provider": "CodeBuild",
              "version": "1"
            },
            "configuration": { "ProjectName": "wiki-pipeline-build" },
            "inputArtifacts": [{ "name": "SourceArtifact" }],
            "outputArtifacts": [{ "name": "BuildArtifact" }],
            "runOrder": 1
          }
        ]
      },
      {
        "name": "Deploy",
        "actions": [
          {
            "name": "SandboxStack",
            "actionTypeId": {
              "category": "Deploy",
              "owner": "AWS",
              "provider": "CloudFormation",
              "version": "1"
            },
            "configuration": {
              "ActionMode": "CREATE_UPDATE",
              "StackName": "wiki-pipeline-lab",
              "TemplatePath": "BuildArtifact::template.json",
              "TemplateConfiguration": "BuildArtifact::configuration.json",
              "RoleArn": "CLOUDFORMATION_ROLE_ARN"
            },
            "inputArtifacts": [{ "name": "BuildArtifact" }],
            "runOrder": 1
          }
        ]
      },
      {
        "name": "Verify",
        "actions": [
          {
            "name": "InvokeHealth",
            "actionTypeId": {
              "category": "Build",
              "owner": "AWS",
              "provider": "CodeBuild",
              "version": "1"
            },
            "configuration": { "ProjectName": "wiki-pipeline-verify" },
            "inputArtifacts": [{ "name": "BuildArtifact" }],
            "runOrder": 1
          }
        ]
      }
    ],
    "version": 1
  }
}
```

The historical source provider identifier remains `CodeStarSourceConnection` even when connection management is named CodeConnections. [Source-action fields](https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-CodestarConnectionSource.html), [CloudFormation template/configuration contract](https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-CloudFormation.html).

```bash
aws sts get-caller-identity
aws codepipeline create-pipeline --cli-input-json file://pipeline.json
PIPELINE_LAB_RUN=$(aws codepipeline start-pipeline-execution \
  --name wiki-delivery-lab --query pipelineExecutionId --output text)
aws codepipeline get-pipeline-execution --pipeline-name wiki-delivery-lab \
  --pipeline-execution-id "$PIPELINE_LAB_RUN"
aws codepipeline get-pipeline-state --name wiki-delivery-lab
```

Inspect every stage, actual source revision, template digest in build logs, stack events and verify output. Observe up to 30 minutes; record failed/pending stage and stop on timeout, rather than triggering more executions. Change VERSION to `v2` through the normal source workflow; confirm deployed invocation returns `v2`. Deliberately break the unit-test expected greeting in a later lab revision: Build must fail and Deploy must not run for **that execution**; prior/concurrent executions are separate.

For a runtime-only health failure, change the deployed handler to `return {"message": "wrong", "version": VERSION}` only when context is non-None, leaving local context-None tests passing. CloudFormation may successfully update it, but the Verify action must fail. This pipeline does **not** automatically roll back a successful stack update on health-gate failure. Recover by reverting the bad source change to the recorded known-good v2 content via the normal repository workflow and running the pipeline again. Confirm the new revision/template digest and actual v2 greeting; report this as manual application rollback. CloudFormation stack-operation failures have separate rollback semantics. Do not assume either path undoes external data changes.

Cleanup: stop active executions safely, delete only `wiki-delivery-lab`, delete the dedicated stack and wait for completion (function then log group), and remove the two build projects/dedicated logs. Inventory artifact object versions and remove only this lab's prefix after evidence/retention approval; an empty current listing is not an empty versioned bucket. Remove dedicated roles/key/connection only if their owner confirms no other consumers. Re-query the function/stack/project/pipeline identifiers and account for retained artifact storage.

## Deployment decisions

Rolling updates trade deployment time and capacity headroom. Blue/green uses separate target capacity and a traffic switch. Canary gradually shifts traffic and needs a measurable acceptance signal. A DNS switch is not an instant universal rollback because clients/resolvers cache results.

Keep backward-compatible schema changes and external side effects in the release plan; redeploying an old binary may not undo a data migration. Manual approvals supplement automated checks, not replace them.

Cleanup: disable/remove the dedicated pipeline/webhook, project, lab artifacts, logs and sandbox target after acceptance. Inspect retained artifacts/keys and preserve shared connection/roles. Reuse [[Kubernetes/eks/automation/continuous-delivery/codepipeline|the existing EKS pipeline lesson]] instead of duplicating Kubernetes manifests.

## References

- [CodePipeline concepts](https://docs.aws.amazon.com/codepipeline/latest/userguide/concepts.html).
- [CodeBuild build specifications](https://docs.aws.amazon.com/codebuild/latest/userguide/build-spec-ref.html).
- [CodeDeploy deployment types](https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-steps.html).

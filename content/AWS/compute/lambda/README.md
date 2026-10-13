---
title: AWS Lambda
description: Choose an invocation model, deploy and test a small function, and reason about retries, IAM, networking, concurrency and cost.
tags:
  - cloud/aws/compute
  - cloud/aws/serverless
date: 2026-10-12
---

# AWS Lambda

Lambda executes code in managed execution environments. Keep durable state outside the function and assume that events can be delivered more than once. This is the canonical Lambda lesson; [[AWS/serverless/lambda/README|the serverless view]] links here.

## Invocation and failure model

| Model                | Caller                                   | Failure ownership                                                       |
| -------------------- | ---------------------------------------- | ----------------------------------------------------------------------- |
| Synchronous          | SDK, API integration                     | Caller observes errors and decides retries                              |
| Asynchronous         | Event invocation, selected integrations  | Lambda queues and retries; configure event age, destinations or DLQ     |
| Event source mapping | SQS, streams and other supported sources | Lambda polls; source-specific retries, ordering and checkpoint behavior |

An HTTP success from an asynchronous invoke means acceptance, not successful business processing. For queue processing, use an idempotency key backed by conditional durable writes; a repeated delivery must not repeat a payment or email.

With [[AWS/application-integration/sqs/README|SQS]], configure visibility timeout for the processing duration, redrive policy and a DLQ. Partial batch responses let a handler identify failed records rather than retrying every successful record. FIFO processing must preserve order; stop after the first failure and report remaining unprocessed records.

## Minimal synchronous lab

Use the verified sandbox profile/Region from [[AWS/foundations/getting-started|the first-session handoff]] in a dedicated shell. Recheck GetCallerIdentity immediately before creation and stop on a non-sandbox account; the default profile is not implicitly safe.

Prerequisites: a sandbox account, AWS CLI v2, zip, a currently supported Python runtime, and permission to manage the lab function and pass its execution role. The role must trust `lambda.amazonaws.com` and have only the required log permissions. See [execution roles](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html). This lab invokes a function directly and needs no VPC or API Gateway. Resources and log ingestion can incur charges.

### Create the dedicated execution role and log group

If your administrator supplies a role, verify its trust/log scope and skip creation; do not delete it later. Otherwise, the sandbox caller needs IAM CreateRole/PutRolePolicy/GetRole/GetRolePolicy/DeleteRolePolicy/DeleteRole, scoped PassRole to `wiki-lambda-lab-role` for Lambda, and the relevant Logs create/retention/delete permissions. The execution role is separate from this deployment identity.

Save `lambda-trust.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Create the role and pre-create its named log group in the verified Region:

```bash
LAMBDA_LAB_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
: "${AWS_REGION:?Export the approved sandbox Region from the first-session handoff}"
LAMBDA_LAB_REGION="$AWS_REGION"
LAMBDA_LAB_ROLE_ARN=$(aws iam create-role \
  --role-name wiki-lambda-lab-role \
  --assume-role-policy-document file://lambda-trust.json \
  --query Role.Arn --output text)
aws logs create-log-group --log-group-name /aws/lambda/wiki-lambda-lab
aws logs put-retention-policy \
  --log-group-name /aws/lambda/wiki-lambda-lab --retention-in-days 1
```

Stop on an existing-name error rather than taking ownership of an unknown resource. For standard commercial AWS Regions, save `lambda-logs.json`, replacing ACCOUNT and REGION with these actual values. Other partitions require their actual ARN prefix.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "arn:aws:logs:REGION:ACCOUNT:log-group:/aws/lambda/wiki-lambda-lab:*"
    }
  ]
}
```

```bash
aws iam put-role-policy --role-name wiki-lambda-lab-role \
  --policy-name WikiLambdaLabLogs --policy-document file://lambda-logs.json
aws iam get-role --role-name wiki-lambda-lab-role \
  --query 'Role.{Arn:Arn,Trust:AssumeRolePolicyDocument}'
aws iam get-role-policy --role-name wiki-lambda-lab-role \
  --policy-name WikiLambdaLabLogs --query PolicyDocument
```

This function does not create log groups or need S3/DynamoDB/network permissions. Pre-creating the group lets the execution policy omit `logs:CreateLogGroup`. IAM propagation can briefly prevent Lambda assuming a just-created role; verify trust and retry the create a bounded number of times, never add administrator permissions to make it pass. [Logging permissions](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs.html).

Save as `lambda_function.py`:

```python
import json

def handler(event, context):
    name = event.get("name", "learner")
    if not isinstance(name, str):
        raise ValueError("name must be a string")
    return {
        "statusCode": 200,
        "body": json.dumps({"message": f"Hello, {name}"})
    }
```

Set `LAMBDA_LAB_ROLE_ARN` to the sandbox execution role ARN and `LAMBDA_LAB_RUNTIME` to a supported Python runtime from the [current runtime table](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html).

```bash
aws sts get-caller-identity
zip function.zip lambda_function.py
aws lambda create-function \
  --function-name wiki-lambda-lab \
  --runtime "$LAMBDA_LAB_RUNTIME" \
  --role "$LAMBDA_LAB_ROLE_ARN" \
  --handler lambda_function.handler \
  --zip-file fileb://function.zip \
  --timeout 10 --memory-size 128
aws lambda wait function-active-v2 --function-name wiki-lambda-lab
aws lambda invoke \
  --function-name wiki-lambda-lab \
  --cli-binary-format raw-in-base64-out \
  --payload '{"name":"AWS learner"}' \
  response.json
```

Checkpoint: inspect `response.json`; it contains statusCode 200 and a JSON-encoded greeting. Lambda's invoke response should not include FunctionError. Invoke again with `{"name":42}`: expect FunctionError and the validation exception, not a successful greeting. Inspect the CloudWatch log group for the exception without logging credentials or sensitive input.

Cleanup: delete only `wiki-lambda-lab`, its `/aws/lambda/wiki-lambda-lab` log group and its dedicated role/policy if you created them for this lab. Keep shared roles. Remove the local archive and test output through your normal file manager.

For resources created by the role-setup section, use dependency order after recording invocation/log evidence:

```bash
aws lambda delete-function --function-name wiki-lambda-lab
aws logs delete-log-group --log-group-name /aws/lambda/wiki-lambda-lab
aws iam delete-role-policy --role-name wiki-lambda-lab-role \
  --policy-name WikiLambdaLabLogs
aws iam delete-role --role-name wiki-lambda-lab-role
```

Re-query each identifier: expect ResourceNotFoundException/NoSuchEntity, not a permissions error. Do not run role deletion for an administrator-provided/shared role.

## Networking and latency

A VPC configuration is for reaching private dependencies, not a requirement for every function. Lambda uses Hyperplane ENIs shared across compatible subnet/security-group configurations; do not model a new ten-second ENI attachment per invocation. A public subnet does **not** give the function a public IP. Internet access from a VPC-connected function requires a supported egress path such as NAT; use endpoints for supported private AWS API access.

Measure initialization time by runtime, package and dependency behavior. Provisioned concurrency can reduce initialization latency but has its own capacity charge and does not replace invocation/duration billing. See [VPC access](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html) and [internet access](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc-internet.html).

## Capacity and lifecycle

Reserved concurrency isolates capacity and caps a function; provisioned concurrency prepares environments. They solve different problems. Check actual account/Region allocations before a load test.

Standard invocation timeout is 900 seconds. Managed Instances allow up to 5,400 seconds for documented asynchronous/event-source cases, with exceptions. Payload limits depend on synchronous, asynchronous and streamed responses; current async maximum is 1 MB. These are mode-scoped limits, not guarantees of throughput. [Owning quota table](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html).

Choose a supported runtime and schedule upgrades before deprecation. Managed Go 1.x is not a current managed runtime; Go uses supported OS-only runtimes or images. Container images also require patch ownership. Pin immutable layer versions and update functions explicitly.

## Cost calculation

For a hypothetical us-east-1 x86 on-demand study dated 2026-10-12, assume \$0.0000166667/GB-second and \$0.20/million requests, excluding free tier, discounts and other services:

- 512 MB = 0.5 GB; 200 ms = 0.2 seconds.
- Ten million invokes consume 0.5 × 0.2 × 10,000,000 = 1,000,000 GB-seconds.
- Duration is approximately \$16.67; requests cost \$2; total approximately \$18.67.
- One million 150 ms image operations at 512 MB consume 75,000 GB-seconds: about \$1.25 duration + \$0.20 requests = \$1.45.

Region, architecture, tiers and execution mode matter. Provisioned capacity is memory GB × provisioned concurrency × enabled seconds × its regional capacity rate, **plus** requests and applicable execution-duration charges. Include logs, storage, API Gateway, queue, network and database charges separately. Check [Lambda pricing](https://aws.amazon.com/lambda/pricing/) before using any rate in a forecast.

## Next exercise

Add a sandbox queue and a handler that intentionally fails one record. Enable ReportBatchItemFailures, resend an already-processed event, and prove both partial failure handling and idempotency using a durable store. Do not infer exactly-once business effects from successful invocation.

## Event sources, versions and operations

An S3 notification, an SQS event source mapping and a schedule have different failure paths. S3 and scheduled notifications invoke the function asynchronously; SQS is polled through an event source mapping and retains messages until the batch succeeds or the visibility timeout/redrive policy applies. An HTTP front end such as API Gateway has its own authorization, throttling and response mapping. Test the failure path for the chosen source instead of assuming the direct `invoke` lab proves it.

Publish a function version after testing code and configuration; route an alias to the version used by clients. Keep the previous version available until rollback requirements expire. A layer can share dependencies across functions, but each published layer version is immutable and must match runtime/architecture requirements. Package size, dependency cold-start cost, patch ownership and supported runtime versions belong in the release checklist.

```text
event source → invocation mode → function version/alias
                                  ├─ execution role → AWS permissions
                                  ├─ logs/metrics/traces → diagnosis
                                  └─ destination/DLQ or source redrive → recovery
```

Investigate production errors with `Errors`, `Invocations`, `Duration`, `Throttles`, concurrency and source-specific age/backlog metrics. A zero `Errors` count does not prove that an SQS batch made the desired business change; the handler may return success while dropping a record. Correlate request IDs with structured logs, trace dependency calls where allowed, and alert on destination/DLQ growth. For an SQS backlog, compare event-source maximum concurrency, reserved concurrency, visibility timeout and downstream rate limits before raising concurrency.

## References and next steps

- [SQS partial batch failures](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html).
- [Asynchronous error handling](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-error-handling.html).
- [Python handlers](https://docs.aws.amazon.com/lambda/latest/dg/python-handler.html).
- Prerequisites: [[AWS/security/iam/README|IAM]] and [[AWS/monitoring/cloudwatch-logs/README|logs]].
- Next: [[AWS/application-integration/step-functions/README|Step Functions]], [[AWS/serverless/api-gateway/README|API Gateway]] and [[AWS/application-integration/sqs/README|SQS]].

## Across the wiki

- [[GCP/compute/cloud-functions/README|GCP Cloud Functions (2nd Gen) & Eventarc]] — functions (GCP)
- [[Architecture/solution-architecture-concepts/api-design/stateful-vs-stateless|Stateful vs Stateless]] — functions (Architecture)

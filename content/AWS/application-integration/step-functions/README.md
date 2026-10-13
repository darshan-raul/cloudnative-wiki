---
title: AWS Step Functions
description: AWS Step Functions — state machine orchestration. Standard vs Express workflows, tasks, choices, parallel, map, wait, nested workflows, and activity workers.
tags:
  - aws/application-integration
date: 2026-10-12
---

# AWS Step Functions

Prerequisites: [[AWS/security/iam/README|scoped IAM roles]] and [[AWS/monitoring/README|delivery/processing observability]].

Step Functions executes state machines defined in Amazon States Language (ASL). It coordinates work but does not make arbitrary external effects transactional.

## Workflow choice

Standard workflows support durable executions up to one year and charge for state transitions. Express workflows support up to five minutes and charge for executions plus memory-duration. Asynchronous Express is at-least-once; synchronous Express is at-most-once. Standard execution semantics do not prevent explicitly retried tasks or duplicate external business requests.

Standard has execution history APIs with bounded retention. Express investigation depends on configured CloudWatch logging; logs are not an unbounded durable history guarantee. Express does not support .sync job-run or .waitForTaskToken callback integration patterns.

## Complete non-destructive ASL fixture

Save definition.json. This complete machine validates a boolean and has no external side effects:

```json
{
  "Comment": "Disposable validation lab",
  "StartAt": "Validate",
  "TimeoutSeconds": 30,
  "States": {
    "Validate": {
      "Type": "Choice",
      "Choices": [
        { "Variable": "$.approved", "BooleanEquals": true, "Next": "Approved" }
      ],
      "Default": "Rejected"
    },
    "Approved": { "Type": "Pass", "Result": { "accepted": true }, "End": true },
    "Rejected": {
      "Type": "Fail",
      "Error": "ApprovalRequired",
      "Cause": "approved must be true"
    }
  }
}
```

Create a sandbox execution role whose trust principal is states.amazonaws.com. This no-task machine needs no permission to invoke another service; scope the caller's iam:PassRole to this role and states CreateStateMachine/StartExecution/DescribeExecution/DeleteStateMachine to the lab.

```bash
aws stepfunctions create-state-machine --name wiki-lab-validation \
  --definition file://definition.json --role-arn EXECUTION_ROLE_ARN --type STANDARD
aws stepfunctions start-execution --state-machine-arn STATE_MACHINE_ARN \
  --name approved-fixture --input '{"approved":true}'
```

Save the returned executionArn, poll describe-execution with bounded backoff, and expect SUCCEEDED with accepted=true. Run a separate name/input approved=false and expect FAILED with ApprovalRequired. Inspect history to explain the chosen route.

Delete the disposable state machine after executions terminate, then remove the lab role. Do not delete production workflows to change their immutable type.

## Production additions

Task states need explicit timeouts and narrow IAM actions/resource ARNs. Retry transient failures with bounded attempts/backoff; Catch routes failures to a compensating action or human-review state. Use idempotency keys for payment/provisioning side effects and protect callback tokens as credentials. Observe payload/history/concurrency quotas and handle large payloads through authorized object references rather than unbounded state data.

Retries and transitions can increase cost. Logging may expose sensitive inputs/outputs and incurs separate CloudWatch charges.

## State types and integration patterns

| State        | Responsibility           | Common failure                                                       |
| ------------ | ------------------------ | -------------------------------------------------------------------- |
| Task         | Invoke supported work    | Missing execution-role permission, timeout or repeated side effect   |
| Choice       | Select a branch          | Missing/type-mismatched input; no appropriate Default                |
| Parallel     | Run independent branches | One branch fails; effects in others already happened                 |
| Map          | Process a collection     | Unbounded concurrency/large history/payload                          |
| Wait         | Delay by duration/time   | Stale data or unsuitable workflow maximum                            |
| Pass         | Transform/provide data   | Wrong path/JSONata-versus-JSONPath assumptions                       |
| Succeed/Fail | Terminate explicitly     | Confusing a finished orchestration with a committed business outcome |

Request-response, .sync and callback-token patterns have different supported services/workflow types. Express does not support the latter two. Activity workers poll a Standard activity and return a token-based result/heartbeat; a callback token is sensitive authority, not an event ID.

## Complete Task, Retry and Catch example

This second definition uses JSONPath mode and a disposable Lambda function. Replace its ARN, provide an execution role authorized for that exact function and log only non-sensitive fixtures.

```json
{
  "StartAt": "Invoke",
  "TimeoutSeconds": 60,
  "States": {
    "Invoke": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "LAMBDA_FUNCTION_ARN",
        "Payload.$": "$"
      },
      "ResultSelector": { "result.$": "$.Payload" },
      "ResultPath": "$.worker",
      "TimeoutSeconds": 20,
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException"
          ],
          "IntervalSeconds": 2,
          "MaxAttempts": 2,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.failure",
          "Next": "Review"
        }
      ],
      "Next": "Finished"
    },
    "Review": { "Type": "Pass", "Result": { "accepted": false }, "End": true },
    "Finished": { "Type": "Succeed" }
  }
}
```

Start with an object input. Observe a successful result under worker; an application exception routes to Review without being treated as a service-transient retry. Some terminal error classes have special catchability rules: consult the owning error table rather than assuming States.ALL covers literally everything. Review ends successfully as an orchestration, so inspect its accepted=false business outcome too.

## Input/output, nested work and workers

InputPath/Parameters/ResultSelector/ResultPath/OutputPath transform different boundaries in JSONPath workflows. JSONata states use different expression/data-flow fields; do not combine the modes blindly. Keep payloads bounded; store large data behind authorized object references.

Nested state machines need permission to start the child and, for supported synchronous behavior, the required execution-observation permissions. Parent success is not automatic proof of each child business effect. Map concurrency must match downstream capacity; Distributed Map has separate resource/child limits and charges.

Worker loop design includes bounded polling, task-token handling, heartbeats, timeout and shutdown. On a worker crash, determine whether the external effect committed before reporting/retrying. Never embed raw callback tokens in a public URL or log.

## Operational walkthrough and cost

For Standard, describe-execution/get-execution-history distinguish RUNNING/SUCCEEDED/FAILED/TIMED_OUT/ABORTED and state-level errors. Express investigation uses configured logs with sensitive-data controls; logs are not a replacement for an external business ledger.

Price transitions for Standard, including retries/loops. For example, 10,000 executions following five transitions each produce 50,000 transitions before retries; multiply by a rate in matching units and applicable allowance. Express requires execution count plus actual billed memory-duration; minutes alone do not establish cost.

Stop remaining lab executions, delete only dedicated state machines/activities and role/log resources after the workflow has no dependents. Keep an idempotency record through the replay/retention window.

References: [state types](https://docs.aws.amazon.com/step-functions/latest/dg/amazon-states-language-state-machine-structure.html), [input/output](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-input-output-filtering.html), [Lambda integration](https://docs.aws.amazon.com/step-functions/latest/dg/connect-lambda.html), [activities](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-activities.html).

## Cross-wiki comparisons

- [[Linux/boot-init/cron-anacron|Cron and Anacron]] — scheduled work (Linux)
- [[Linux/boot-init/systemd-timers|systemd Timers]] — scheduled work (Linux)

## References

- [Workflow types and execution guarantees](https://docs.aws.amazon.com/step-functions/latest/dg/choosing-workflow-type.html)
- [ASL specification](https://states-language.net/spec.html)
- [Error handling](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-error-handling.html)
- [CLI create-state-machine](https://docs.aws.amazon.com/cli/latest/reference/stepfunctions/create-state-machine.html)
- [Pricing](https://aws.amazon.com/step-functions/pricing/)

## Across the wiki

- [[Kubernetes/concepts/L03-workloads/07-cronjob|CronJobs — Time-Scheduled Workloads]]

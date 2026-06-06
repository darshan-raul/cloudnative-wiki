---
title: AWS Step Functions
description: AWS Step Functions — state machine orchestration. Standard vs Express workflows, tasks, choices, parallel, map, wait, nested workflows, and activity workers.
tags:
  - aws
  - application-integration
  - step-functions
  - orchestration
---

# AWS Step Functions

Step Functions orchestrate multi-step workflows as state machines. Each step in your workflow is a state — you define the flow (sequence, parallel, choice, map) and Step Functions handles execution, retries, and error handling.

## Standard vs Express

| Feature | Standard Workflow | Express Workflow |
|---------|-----------------|-----------------|
| Duration | Up to 1 year | Up to 5 minutes |
| Execution rate | 1,200/min (default) | 100,000/min |
| State types | All | All (except Activity) |
| Execution history | Full history in CloudWatch | Limited (async only) |
| Price | $0.025/1K state transitions | $1.00/million executions + $0.000016/execution-minute |
| Use case | Long-running, human approval, audit | High-volume, event-driven, Lambda |

## State Machine Definition

```json
{
  "Comment": "Order processing workflow",
  "StartAt": "ValidateOrder",
  "States": {
    "ValidateOrder": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789012:function:validate-order",
      "Next": "CheckInventory",
      "ResultPath": "$.order"
    },
    "CheckInventory": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.order.available",
          "BooleanEquals": true,
          "Next": "ProcessPayment"
        }
      ],
      "Default": "RejectOrder"
    },
    "ProcessPayment": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789012:function:process-payment",
      "Next": "ShipOrder",
      "Retry": [
        {
          "ErrorEquals": ["PaymentFailedException"],
          "IntervalSeconds": 3,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "NotifyFailure"
        }
      ]
    },
    "ShipOrder": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789012:function:ship-order",
      "Next": "NotifySuccess"
    },
    "RejectOrder": {
      "Type": "Fail",
      "Error": "OrderUnavailable",
      "Cause": "Order is not available"
    },
    "NotifySuccess": {
      "Type": "Pass",
      "End": true
    },
    "NotifyFailure": {
      "Type": "Pass",
      "End": true
    }
  }
}
```

## Creating and Running

```bash
# Create state machine (Standard)
aws stepfunctions create-state-machine \
  --name order-processor \
  --definition file://order-workflow.json \
  --role-arn arn:aws:iam::123456789012:role/step-functions-role \
  --type STANDARD

# Create Express workflow
aws stepfunctions create-state-machine \
  --name order-processor-express \
  --definition file://order-workflow.json \
  --role-arn arn:aws:iam::123456789012:role/step-functions-role \
  --type EXPRESS

# Start execution
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:us-east-1:123456789012:stateMachine:order-processor \
  --input '{"order_id": "12345"}'

# List executions
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:us-east-1:123456789012:stateMachine:order-processor
```

## Python SDK

```python
import boto3

sfn = boto3.client('stepfunctions')

# Start execution
response = sfn.start_execution(
    stateMachineArn='arn:aws:states:us-east-1:123456789012:stateMachine:order-processor',
    name='my-execution-001',
    input=json.dumps({'order_id': '12345'})
)
execution_arn = response['executionArn']

# Describe execution
result = sfn.describe_execution(executionArn=execution_arn)
print(f"Status: {result['status']}")

# Stop execution
sfn.stop_execution(executionArn=execution_arn, error='ErrorReason')
```

## State Types

### Task (Lambda, ECS, etc.)

```json
"ProcessOrder": {
  "Type": "Task",
  "Resource": "arn:aws:lambda:us-east-1:123456789012:function:process",
  "Next": "Notify",
  "TimeoutSeconds": 300
}
```

### Choice (Branching)

```json
"CheckStatus": {
  "Type": "Choice",
  "Choices": [
    {"Variable": "$.status", "StringEquals": "pending", "Next": "Process"},
    {"Variable": "$.status", "StringEquals": "cancelled", "Next": "Cancel"}
  ],
  "Default": "Unknown"
}
```

### Parallel

```json
"ProcessOrder": {
  "Type": "Parallel",
  "End": true,
  "Branches": [
    {
      "StartAt": "ChargeCard",
      "States": {
        "ChargeCard": {"Type": "Task", "Resource": "arn:aws:lambda:...", "End": true}
      }
    },
    {
      "StartAt": "UpdateInventory",
      "States": {
        "UpdateInventory": {"Type": "Task", "Resource": "arn:aws:lambda:...", "End": true}
      }
    }
  ]
}
```

### Map (Iterate)

```json
"ProcessItems": {
  "Type": "Map",
  "ItemProcessor": {
    "StartAt": "ProcessOne",
    "States": {
      "ProcessOne": {
        "Type": "Task",
        "Resource": "arn:aws:lambda:...",
        "End": true
      }
    }
  },
  "End": true
}
```

### Wait

```json
"WaitForApproval": {
  "Type": "Wait",
  "Seconds": 86400,
  "Next": "Process"
}
```

## Nested Workflows

```python
# Parent workflow calls child workflow
child_workflow = {
    "Type": "Task",
    "Resource": "arn:aws:states:us-east-1:123456789012:stateMachine:child-workflow",
    "Parameters": {
        "input.$": "$.childInput"
    },
    "Next": "ContinueAfterChild"
}
```

## Error Handling

```json
"ProcessWithRetry": {
  "Type": "Task",
  "Resource": "arn:aws:lambda:...",
  "Retry": [
    {
      "ErrorEquals": ["ThrottlingException"],
      "IntervalSeconds": 1,
      "MaxAttempts": 3,
      "BackoffRate": 2
    },
    {
      "ErrorEquals": ["States.Timeout"],
      "IntervalSeconds": 5,
      "MaxAttempts": 2,
      "BackoffRate": 2
    }
  ],
  "Catch": [
    {
      "ErrorEquals": ["States.ALL"],
      "ResultPath": "$.error",
      "Next": "HandleError"
    }
  ]
}
```

## Activity Workers

```python
# Activity worker (poll for tasks)
activities = boto3.client('stepfunctions')

while True:
    task = activities.get_activity_task(
        activityArn='arn:aws:states:us-east-1:123456789012:activity:my-activity',
        workerName='worker-1'
    )
    
    if task:
        # Process task
        result = process(task['Input'])
        
        # Send heartbeat (if long-running)
        activities.send_task_heartbeat(taskToken=task['taskToken'])
        
        # Complete
        activities.send_task_success(
            taskToken=task['taskToken'],
            output=json.dumps(result)
        )
```

## Pricing

| Type | Cost |
|------|------|
| Standard (state transitions) | $0.025/1K transitions |
| Express (executions) | $1.00/million + $0.000016/exec-min |
| Express (synchronous) | $0.50/million + $0.000016/exec-min |

## References

- **Homepage:** https://aws.amazon.com/step-functions/
- **Documentation:** https://docs.aws.amazon.com/step-functions/
- **Pricing:** https://aws.amazon.com/step-functions/pricing/

## Nuggets & Gotchas

- **Step Functions has a 256KB payload limit — you can't pass large data between states:** If you need to pass large files, store in S3 and pass the S3 URI between states. Don't try to embed a 10MB file in the state output.
- **Standard workflow executions are charged per STATE TRANSITION — every step counts:** A workflow with 10 states that runs 1000 times = 10,000 transitions. $0.025/1K = $0.25. But if a step is retried 3 times, that's 3 extra transitions per retry.
- **Express workflows DON'T have full execution history in CloudWatch — only async Express:** If you need detailed step-by-step logging (for debugging), use Standard workflows. Express synchronous workflows don't log history at all.
- **Map state runs items IN PARALLEL by default — if you need sequential processing, set "Mode": "Inline" and "MaxConcurrency": 1:** The default is parallel. If your items must be processed in order, set `MaxConcurrency: 1`.
- **Nested workflow results are NOT automatically merged — you must explicitly extract and combine outputs:** When a child workflow completes, its output is in `$.<task-name>`. You need to use `ResultPath` or `OutputPath` to merge it into the parent state.
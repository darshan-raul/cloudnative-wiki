---
title: AWS Batch
description: AWS Batch — managed batch job processing. Job definitions, queues, compute environments (EC2/Fargate), scheduling, retry logic, and dependency management.
tags:
  - aws
  - compute
  - batch
---

# AWS Batch

AWS Batch manages batch job scheduling and execution on managed compute infrastructure. You define job definitions (what to run), job queues (where to run), and compute environments (how to run). AWS Batch handles provisioning, scaling, and cleanup of compute resources.

## Core Concepts

### How AWS Batch Works

```
Job Definition (what to run)
  │
  ▼
Job Queue (priority, compute environment)
  │
  ▼
Compute Environment (EC2 or Fargate)
  │
  ▼
Job Scheduler (runs jobs based on priority, dependencies)
```

### Key Terms

| Term | Description |
|------|-------------|
| Job Definition | Blueprint for a job (image, resources, retry strategy) |
| Job | A running instance of a job definition |
| Job Queue | Queue with priority, maps to compute environment |
| Compute Environment | Managed EC2 or Fargate infra |
| Job Scheduler | AWS Batch scheduler (runs jobs in order) |

## Job Definitions

```json
{
  "jobDefinitionName": "my-batch-job",
  "type": "container",
  "containerProperties": {
    "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-batch:latest",
    "vcpus": 2,
    "memory": 4096,
    "command": ["python", "process.py", "Ref::input_file"],
    "environment": [
      {"name": "BATCH_LOG_LEVEL", "value": "INFO"}
    ],
    "readonlyRootFilesystem": true,
    "privileged": false
  },
  "retryStrategy": {
    "attempts": 3,
    "evaluateOnExit": [
      {"action": "RETRY", "onStatusReason": "HostUsageError"},
      {"action": "EXIT", "onStatusReason": "TaskFailed"}
    ]
  },
  "timeout": {
    "attemptDurationSeconds": 3600
  }
}
```

### Parameters (Job Template)

```json
{
  "parameters": {
    "input_file": "s3://my-bucket/data/input.csv"
  }
}
```

Override at submit time:
```bash
aws batch submit-job \
  --job-name my-run \
  --job-definition my-batch-job \
  --job-queue my-queue \
  --parameters input_file=s3://my-bucket/data/new-input.csv
```

## Compute Environments

### Fargate (Serverless)

```bash
aws batch create-compute-environment \
  --compute-environment-name my-fargate-env \
  --type MANAGED \
  --service-role arn:aws:iam::123456789012:role/AWSBatchServiceRole \
  --compute-resources '{
    "type": "FARGATE",
    "maxvCpus": 256,
    "subnets": ["subnet-xxxxx", "subnet-yyyyy"],
    "securityGroupIds": ["sg-xxxxx"]
  }' \
  --state ENABLED
```

### EC2 (Managed)

```bash
aws batch create-compute-environment \
  --compute-environment-name my-ec2-env \
  --type MANAGED \
  --service-role arn:aws:iam::123456789012:role/AWSBatchServiceRole \
  --compute-resources '{
    "type": "EC2",
    "minvCpus": 0,
    "desiredvCpus": 0,
    "maxvCpus": 256,
    "instanceTypes": ["m5", "m5d"],
    "subnets": ["subnet-xxxxx", "subnet-yyyyy"],
    "securityGroupIds": ["sg-xxxxx"],
    "instanceRole": "arn:aws:iam::123456789012:instance-profile/batch-instance-role"
  }' \
  --state ENABLED
```

### Spot (Cheaper)

```bash
aws batch create-compute-environment \
  --compute-environment-name my-spot-env \
  --type MANAGED \
  --service-role arn:aws:iam::123456789012:role/AWSBatchServiceRole \
  --compute-resources '{
    "type": "SPOT",
    "allocationStrategy": "BEST_FIT_PROGRESSIVE",
    "minvCpus": 0,
    "maxvCpus": 256,
    "instanceTypes": ["m5", "c5"],
    "bidPercentage": 50,
    "subnets": ["subnet-xxxxx"],
    "securityGroupIds": ["sg-xxxxx"],
    "instanceRole": "arn:aws:iam::123456789012:instance-profile/batch-instance-role"
  }' \
  --state ENABLED
```

## Job Queues

```bash
# Create queue
aws batch create-job-queue \
  --job-queue-name my-queue \
  --priority 1 \
  --compute-environment-order '[{"computeEnvironment": "my-fargate-env", "order": 1}]' \
  --state ENABLED

# Create with multiple compute environments (priority)
aws batch create-job-queue \
  --job-queue-name production-queue \
  --priority 10 \
  --compute-environment-order '[
    {"computeEnvironment": "my-fargate-env", "order": 1},
    {"computeEnvironment": "my-ec2-env", "order": 2}
  ]' \
  --state ENABLED
```

Job queues can have multiple compute environments with different priority. Jobs try the first environment, fall back to the next if insufficient resources.

## Submitting Jobs

### Simple Job

```bash
aws batch submit-job \
  --job-name my-analysis \
  --job-definition my-batch-job \
  --job-queue my-queue
```

### Array Job (parallel processing)

```bash
aws batch submit-job \
  --job-name my-array \
  --job-definition my-batch-job \
  --job-queue my-queue \
  --array-properties size=100
```

100 jobs run in parallel. Each job can reference its array index:
```python
import os
array_index = os.environ.get('AWS_BATCH_JOB_ARRAY_INDEX')
```

### Multi-node Parallel Job

For MPI/HPC workloads:

```bash
aws batch submit-job \
  --job-name my-mpi \
  --job-definition my-mpi-job \
  --job-queue my-queue \
  --node-properties '{
    "numNodes": 4,
    "mainNode": 0,
    "nodeRangeProperties": [{
      "targetNodes": "0:3",
      "container": {
        "image": "my-mpi-image",
        "vcpus": 8,
        "memory": 16384
      }
    }]
  }'
```

### Job Dependencies

```bash
# Job 2 depends on Job 1 completing successfully
aws batch submit-job \
  --job-name job2 \
  --job-definition my-batch-job \
  --job-queue my-queue \
  --depends-on '[{"jobId": "xxxxx", "type": "N_TO_N"}]'
```

## Monitoring

```bash
# List jobs
aws batch list-jobs --job-queue my-queue --job-status RUNNABLE

# Describe job
aws batch describe-jobs --jobs xxxxx

# Get job logs
aws batch describe-job-log-groups
# Or: CloudWatch Logs (if configured in job definition)
```

### CloudWatch Events

Monitor job state changes:

```bash
aws events put-rule \
  --name batch-job-events \
  --event-pattern '{
    "source": ["aws.batch"],
    "detail-type": ["AWS Batch Job State Change"]
  }'
```

## Retry Strategy

```json
{
  "retryStrategy": {
    "attempts": 3,
    "evaluateOnExit": [
      {"action": "RETRY", "onReason": "HostUsageError"},
      {"action": "RETRY", "onReason": "NonZeroExitCode"},
      {"action": "EXIT", "onReason": "TaskFailed"}
    ]
  }
}
```

Common `onStatusReason` values:
- `HostUsageError` — resource exhaustion, retry
- `TaskFailed` — task failed, don't retry
- `JobTimeout` — job timed out, retry

## Pricing

| Component | Cost |
|-----------|------|
| EC2 (on-demand) | $0.096/hr (m5.xlarge) |
| EC2 (Spot) | 70-90% off |
| Fargate | $0.04048/vCPU-hr + $0.00444/GB-hr |
| No charge | Job scheduling, queues |

## Architecture: Batch Processing Pipeline

```
S3 (input bucket)
  │
  ▼
Lambda (trigger on new file)
  │
  ▼
AWS Batch (submit job)
  │
  ├── Job 1 (EC2/Spot, 8 vCPU, 16GB)
  ├── Job 2 (EC2/Spot, 8 vCPU, 16GB)
  └── Job 100 (EC2/Spot, 8 vCPU, 16GB)
         │
         ▼
       S3 (output bucket)
         │
         ▼
       SNS (notify completion)
```

## References

- **Homepage:** https://aws.amazon.com/batch/
- **Documentation:** https://docs.aws.amazon.com/batch/
- **Pricing:** https://aws.amazon.com/batch/pricing/

## Pricing Examples

**Scenario 1:** A nightly data processing job (8 vCPU, 16GB) running 5 hours on 10 parallel nodes. Fargate: 10 × 8 vCPU × 5hr × $0.04048 = $16.19. Plus memory: 10 × 16GB × 5hr × $0.00444 = $3.55. Total: ~$19.74 per run. 30 runs/month = $592/month.

**Scenario 2:** The same job on EC2 Spot (70% savings). EC2 m5.xlarge (4 vCPU, 16GB) Spot: $0.058/hr × 20 instances × 5hr = $5.80/job × 30 = $174/month. Fargate is 3.4x more expensive but requires no EC2 management.

**Scenario 3:** An ML training job (64 vCPU, 256GB) running 10 hours once. EC2 Spot (c5.16xlarge = 64 vCPU): $1.38/hr × 10hr × 1 instance = $13.80/job. On-demand: $2.61/hr × 10 = $26.10. Spot saves $12.30 per run. 20 runs/month = $246 savings.

## Nuggets & Gotchas

- **AWS Batch doesn't have a built-in retry for Spot interruptions — configure `evaluateOnExit`:** When Spot interrupts a job, Batch marks it as `FAILED`. Use `"onStatusReason": "HostUsageError"` in retry strategy to automatically resubmit interrupted jobs.
- **Array jobs share the same job definition — each array index gets its own job:** If you need different parameters per array index, use `AWS_BATCH_JOB_ARRAY_INDEX` in your code to determine which chunk of data to process.
- **Fargate compute environments have a 16-vCPU limit per job — for larger jobs use EC2:** If you try to submit a job with 32 vCPU to a Fargate environment, it will fail. Use EC2 for high-vCPU workloads.
- **Jobs timeout based on `attemptDurationSeconds` — if your job takes > 1 hour and you forget to set timeout, it will fail:** Default timeout is infinite (no timeout). Set `timeout.attemptDurationSeconds` to a value slightly above your expected runtime.
- **The `jobQueue` parameter on submit-job is required — don't confuse it with `computeEnvironmentOrder`:** The queue is where you submit jobs. The compute environment is what the queue maps to. You can't submit directly to a compute environment.
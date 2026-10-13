---
title: "AWS Batch"
description: "Model queues, compute environments, resource-compatible jobs and retry/timeout behavior without assuming simultaneous or strict ordered execution."
tags:
  - cloud/aws/compute/batch
date: 2026-10-12
---

# AWS Batch

Batch schedules container jobs onto supported compute environments. A job definition describes execution; a queue connects jobs to capacity. Start with [[AWS/compute/ecs/README|container resources/roles]] and [[AWS/compute/ecr|images]].

## Scheduling and execution

Without a scheduling policy, a queue uses FIFO scheduling; fair-share policies and priority/resource/dependency constraints change placement. Submission order does not guarantee completion order. Array jobs create indexed children, not a promise that every child runs at once.

Choose EC2, Fargate or another supported model based on resource shape and job needs. Multi-node parallel jobs have model-specific restrictions; do not copy EC2 vCPU fields into a Fargate definition or mix incompatible compute-environment types in a queue.

Service, execution and application job roles are distinct. The container must be able to pull its image, emit logs and reach dependencies without broad permissions.

## Small Fargate job exercise

Prerequisites: a sandbox Fargate compute environment and compatible queue created through the documented console workflow, subnets/SGs with approved egress for the public image (or a private ECR mirror and its endpoints), reachable CloudWatch Logs, an execution role and existing log group. This is a paid-resource lab; record every identifier.

Save as `batch-job.json` and replace the role/Region:

```json
{
  "jobDefinitionName": "wiki-batch-lab",
  "type": "container",
  "platformCapabilities": ["FARGATE"],
  "containerProperties": {
    "image": "public.ecr.aws/docker/library/alpine:3",
    "executionRoleArn": "arn:aws:iam::111122223333:role/REPLACE_WITH_EXECUTION_ROLE",
    "resourceRequirements": [
      { "type": "VCPU", "value": "0.25" },
      { "type": "MEMORY", "value": "512" }
    ],
    "command": ["/bin/sh", "-c", "echo Batch-lab-ok"],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/aws/batch/wiki-lab",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "job"
      }
    }
  },
  "retryStrategy": { "attempts": 1 },
  "timeout": { "attemptDurationSeconds": 60 }
}
```

```bash
aws batch register-job-definition --cli-input-json file://batch-job.json
aws batch submit-job \
  --job-name wiki-batch-test --job-definition wiki-batch-lab \
  --job-queue "$BATCH_LAB_QUEUE"
```

Record the job ID. Follow describe-jobs through scheduling/start to SUCCEEDED; verify exit code and Batch-lab-ok in the recorded CloudWatch stream. Batch has no describe-job-log-groups command.

## Retry and failure exercise

Use a second lab definition that exits nonzero and a bounded retry strategy. Match documented onReason/onStatusReason/onExitCode patterns with an explicit EXIT fallback; invented status strings are not a reliable policy.

Timeout termination is not retried. Batch has no universal maximum timeout value, but Fargate execution should not be expected beyond fourteen days. Save durable checkpoints for long or interruptible jobs.

Investigate a stuck RUNNABLE job by examining capacity, compatible CPU/memory, permissions, image reachability and dependencies; “queue enabled” is not proof that it can launch.

## Cost and cleanup

Batch has no additional service charge for standard scheduling; underlying compute/storage/network/logging are billed. A compute environment can retain resources beyond one completed job.

Cancel queued and terminate running lab jobs, disable/delete the dedicated queue after jobs drain, then disable/delete the dedicated compute environment when dependencies permit. Deregister the lab definition and remove dedicated logs/resources; verify no residual paid capacity.

## Queue, retry and pipeline details

```text
S3 input event / schedule → submit-job → job queue
                                         │
                              compute environment
                                         │
                             job definition revision
                                         │
                           container → logs + output
```

The job definition is the versioned blueprint; the queue determines where eligible jobs wait; the compute environment supplies compatible capacity. This distinction matters when `RUNNABLE` jobs remain queued: a valid image and definition are insufficient if resource requirements exceed available capacity or the queue points at an incompatible environment. A successful submit response gives a job ID, not a promise that it will start immediately.

Use a simple job for one unit of work. Use an array job when items can run independently and read `AWS_BATCH_JOB_ARRAY_INDEX` to select a partition; reserve multi-node parallel jobs for tightly coupled work on a supported environment. A dependency can require a prior job to complete before a downstream job is eligible. For a data pipeline, put durable input/output in S3 or another approved store so a retry does not silently duplicate results.

For retry testing, distinguish an application exit from capacity delay, image-pull failure and timeout. Record the attempt number and exit code; make the job idempotent or write outputs under attempt-specific temporary keys and publish once. Send terminal job state to an event rule or query `describe-jobs`; use the job's log stream to inspect application failure. A CloudWatch alarm on queued-job age or failed-job count helps detect a stuck pipeline, but it requires an explicit metric/threshold design.

Compare cost as `sum of running compute duration × selected capacity price`, plus EBS/EFS, image storage, network and logs. Spot can lower compute cost only when interruptions and reruns are acceptable; a cheap attempt that regularly loses work can cost more overall.

## References

- [Scheduling policies](https://docs.aws.amazon.com/batch/latest/userguide/job_scheduling.html).
- [Fargate job definitions](https://docs.aws.amazon.com/batch/latest/userguide/fargate-job-definitions.html).
- [Retries](https://docs.aws.amazon.com/batch/latest/userguide/job_retries.html).
- [Timeouts](https://docs.aws.amazon.com/batch/latest/userguide/job_timeouts.html).
- [Getting started](https://docs.aws.amazon.com/batch/latest/userguide/GettingStarted.html).

## Across the wiki

- [[Azure/compute/aks/batch-workloads|AKS Batch Workloads, Job Orchestration, and Kueue Fair-Share Scheduling]] — batch workloads (Azure)
- [[GCP/compute/gke/batch-workloads-kueue|GKE Batch Workloads & Kueue Job Orchestration Architecture]] — batch workloads (GCP)
- [[Kubernetes/concepts/L03-workloads/06-job|Jobs — Run-to-Completion Workloads]] — batch workloads (Kubernetes)
- [[GCP/compute/cloud-run/jobs|GCP Cloud Run Jobs & Batch Processing]] — batch workloads (GCP)

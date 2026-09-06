---
title: GCP Cloud Run Jobs & Batch Processing
description: Cloud Run Jobs architecture — run-to-completion batch processing, task arrays, concurrency parallelism, Cloud Scheduler integration, and 24-hour execution limits.
tags:
  - gcp
  - compute
  - cloud-run
  - serverless
  - batch
  - containers
---

# GCP Cloud Run Jobs & Batch Processing 🚀⚙️

While **Cloud Run Services** are designed for long-lived, request-driven HTTP web applications that scale down to zero when idle, **Cloud Run Jobs** are designed specifically for **run-to-completion batch workloads**. 

Jobs execute an OCI container to completion (until exit code 0 or failure) and terminate automatically. Jobs support execution durations of up to **24 hours per task**, parallel task array slicing, dynamic execution overrides, and direct VPC egress.

---

## Architecture & Mental Model

### Task Array Slicing & Parallel Execution

A Cloud Run Job can execute an array of independent, parallel container tasks. Cloud Run automatically injects task-specific environment variables into each container instance:

```
                              Job Execution Trigger
                      (Cloud Scheduler / gcloud CLI / API)
                                       │
                                       ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        Cloud Run Jobs Controller                       │
│   Settings: --tasks=100 (Total items)  --parallelism=10 (Concurrency)  │
└──────────────────────────────────────┬─────────────────────────────────┘
                                       │
                ┌──────────────────────┴──────────────────────┐
                ▼                                             ▼
     ┌─────────────────────┐                       ┌─────────────────────┐
     │ Container Task 0    │                       │ Container Task 9    │
     │ CLOUD_RUN_TASK_     │                       │ CLOUD_RUN_TASK_     │
     │ INDEX = 0           │                       │ INDEX = 9           │
     │ CLOUD_RUN_TASK_     │                       │ CLOUD_RUN_TASK_     │
     │ COUNT = 100         │                       │ COUNT = 100         │
     └──────────┬──────────┘                       └──────────┬──────────┘
                │ Processes slice 0/100                       │ Processes slice 9/100
                │                                             │
                ▼                                             ▼
     ┌─────────────────────┐                       ┌─────────────────────┐
     │ Task 0 Exits Code 0 │                       │ Task 9 Exits Code 0 │
     └──────────┬──────────┘                       └──────────┬──────────┘
                │                                             │
                ▼                                             ▼
     [Schedules Task 10]                           [Schedules Task 19]
```

* **Data Slicing:** A Python script inspects `int(os.environ["CLOUD_RUN_TASK_INDEX"])` and processes only its assigned partition of data from Cloud Storage or BigQuery, enabling effortless, serverless map-reduce parallelism.

---

## Core Concepts

### 1. Cloud Run Services vs. Cloud Run Jobs

| Dimension | Cloud Run Services | Cloud Run Jobs |
| :--- | :--- | :--- |
| **Invocation** | Incoming HTTP/HTTPS, WebSockets, gRPC, Pub/Sub | Explicit trigger via API, CLI, or Cloud Scheduler |
| **Network Interface** | Must listen on `$PORT` (default 8080) | **No listening port:** Container executes and exits |
| **Max Timeout** | 60 minutes per request | **24 hours per task** |
| **Billing Model** | Pay per request + active vCPU-seconds | Pay strictly for the exact runtime of the task |
| **Scaling Metric** | Ingress request concurrency | Sliced task arrays (`--tasks` and `--parallelism`) |
| **Use Cases** | REST APIs, microservices, web apps | DB migrations, batch video rendering, nightly ETL, ML inference |

### 2. Task Indices & Environment Variables

Cloud Run Jobs injects the following runtime environment variables into every container task:
* `CLOUD_RUN_TASK_INDEX`: The unique zero-based index of this specific task (e.g. `0` to `99`).
* `CLOUD_RUN_TASK_COUNT`: The total number of tasks defined in the job (e.g. `100`).
* `CLOUD_RUN_TASK_ATTEMPT`: The current retry attempt for this task index (starts at `0`; increments on failure).
* `CLOUD_RUN_EXECUTION`: The unique execution identifier string.

### 3. Fault Tolerance & Retry Policies

* **`--max-retries`:** Specifies how many times Cloud Run will restart an individual task index if the container crashes or returns a non-zero exit code.
* **Independent Failure Retries:** If Task 4 crashes but Tasks 0–3 succeed, Cloud Run retries **only Task 4**. The successfully completed tasks are not re-executed.

### 4. Direct VPC Egress for Batch Workers

Batch jobs frequently need to query internal relational databases or push data to private Redis caches. Direct VPC Egress attaches the container directly to a private VPC subnet without requiring expensive Serverless VPC Access connector VMs:
* Configured via `--network` and `--subnet`.
* Egress options: `--vpc-egress=private-ranges-only` (default) or `--vpc-egress=all-traffic`.

---

## Production `gcloud` CLI Commands

### 1. Creating a Parallel Batch Processing Job with Direct VPC Egress

```bash
gcloud run jobs create nightly-etl-job \
  --image=gcr.io/my-prod-project/etl-worker:v2.1.0 \
  --region=us-central1 \
  --tasks=50 \
  --parallelism=10 \
  --max-retries=3 \
  --task-timeout=3600s \
  --cpu=2 \
  --memory=4Gi \
  --network=prod-vpc \
  --subnet=prod-us-central1 \
  --vpc-egress=private-ranges-only \
  --set-secrets="DB_PASSWORD=projects/123456789012/secrets/db-pass:latest" \
  --service-account=batch-runner@my-prod-project.iam.gserviceaccount.com
```

### 2. Executing a Job with Dynamic Argument Overrides

```bash
# Execute job immediately with custom arguments overriding default container entrypoint
gcloud run jobs execute nightly-etl-job \
  --region=us-central1 \
  --args="--date=2026-09-01,--dry-run=false" \
  --wait
```

### 3. Scheduling a Job with Cloud Scheduler (Nightly Cron)

```bash
# Trigger the job automatically every night at 02:00 UTC
gcloud scheduler jobs create http trigger-nightly-etl \
  --location=us-central1 \
  --schedule="0 2 * * *" \
  --time-zone="UTC" \
  --uri="https://us-central1-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/my-prod-project/jobs/nightly-etl-job:run" \
  --http-method=POST \
  --oauth-service-account-email="scheduler-runner@my-prod-project.iam.gserviceaccount.com"
```

### 4. Sample Python Worker Script Using Task Slicing

```python
#!/usr/bin/env python3
import os
import sys

def main():
    task_index = int(os.environ.get("CLOUD_RUN_TASK_INDEX", 0))
    total_tasks = int(os.environ.get("CLOUD_RUN_TASK_COUNT", 1))
    attempt = int(os.environ.get("CLOUD_RUN_TASK_ATTEMPT", 0))

    print(f"Starting Task {task_index} of {total_tasks} (Attempt: {attempt})")

    # Example: Process a slice of 1,000,000 user IDs
    total_users = 1_000_000
    chunk_size = total_users // total_tasks
    start_id = task_index * chunk_size
    end_id = start_id + chunk_size if task_index != total_tasks - 1 else total_users

    print(f"Task {task_index} processing records from ID {start_id} to {end_id}")

    # Process data...
    # If unhandled error occurs, sys.exit(1) triggers automated retry by Cloud Run

    print(f"Task {task_index} completed successfully.")
    sys.exit(0)

if __name__ == "__main__":
    main()
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max tasks per job** | 10,000 tasks | Subdivide large workloads into tasks |
| **Max parallelism** | 100 concurrent tasks | Can request increase via quota console |
| **Max task execution timeout** | 24 hours (86,400s) | Up from 60 mins on Services |
| **Max memory per task** | 32 GiB | Up to 8 vCPUs per task container |
| **Max retries per task** | 10 retries | Exponential backoff between attempts |

---

## References

* **Cloud Run Jobs Overview:** https://cloud.google.com/run/docs/create-jobs
* **Executing Jobs Guide:** https://cloud.google.com/run/docs/execute-jobs
* **Scheduling Cloud Run Jobs:** https://cloud.google.com/run/docs/triggering/using-scheduler
* **Pricing:** https://cloud.google.com/run/pricing

---

## Pricing Examples

### Scenario 1: Nightly Database Schema Migration
* Single task job (`--tasks=1`, 2 vCPU, 2 GB RAM).
* Runs once every deployment or nightly test (executes in 45 seconds).
* Compute cost: 2 vCPUs × $0.00002400 / sec × 45s = **$0.00216 / execution**.
* 30 runs per month = **~$0.06 / month** (Falls within monthly permanent free tier).

### Scenario 2: Large-Scale Monthly Financial Report Generation
* 50 parallel tasks (`--tasks=50`, `--parallelism=25`, 4 vCPU, 8 GB RAM).
* Each task runs for 30 minutes (1,800 seconds).
* Total vCPU-seconds: 50 tasks × 4 vCPU × 1,800s = 360,000 vCPU-seconds.
* Total GiB-seconds: 50 tasks × 8 GB × 1,800s = 720,000 GiB-seconds.
* Pricing (us-central1):
  * vCPU: 360,000 × $0.000024 = $8.64.
  * RAM: 720,000 × $0.0000025 = $1.80.
* **Total Monthly Cost:** **~$10.44 / month** (Eliminates the cost of keeping a dedicated batch server running 24/7).

---

## Nuggets & Gotchas

1. **Containers Must Not Listen on a Port:** If you reuse a Docker image built for Cloud Run Services (which starts an Nginx or Express server listening on `$PORT`), the container will never terminate on its own. The job will run continuously until it hits `--task-timeout`, burning unnecessary compute dollars. Override the Docker container `CMD` or entrypoint to run your batch script instead.
2. **Task Index Failures Do Not Block Other Tasks:** If Task 12 fails with an exit code 1, Cloud Run retries Task 12 while Tasks 13–50 continue executing unimpeded. If your batch logic requires strict sequential execution (e.g. step 2 must strictly follow step 1), Cloud Run Jobs is the wrong tool; use **Cloud Workflows** or **Cloud Composer (Apache Airflow)** instead.
3. **The Ephemeral RAM Disk Trap (`/tmp` Consumption):** Just like Cloud Run Services, the local `/tmp` filesystem is an in-memory RAM disk. If a batch task downloads a 5 GB video file to `/tmp` on a container with 4 GB allocated RAM, the container will instantly be killed with an `OutOfMemory` (OOM) error. Stream files directly to Cloud Storage or allocate sufficient RAM.
4. **Cloud Scheduler Requires Explicit OIDC/OAuth IAM Permissions:** When triggering a job via Cloud Scheduler, the Scheduler service account must have the IAM role `roles/run.invoker` on the job. Without this specific binding, the scheduled execution will fail silently with an HTTP 403 Forbidden in Cloud Scheduler logs.
5. **Dynamic Argument Overrides Replace, Not Append:** When using `gcloud run jobs execute --args="..."`, the supplied arguments **completely replace** the default container arguments rather than appending to them. Ensure your override string includes all necessary operational flags.

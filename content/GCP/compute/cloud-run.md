---
title: GCP Cloud Run
description: Cloud Run architecture — serverless containers, request concurrency, direct VPC egress, CPU allocation models, Cloud Run Jobs, and cold-start optimization.
tags:
  - gcp
  - compute
  - serverless
  - containers
  - cloud-run
---

# GCP Cloud Run 🚀📦

Google Cloud Run is a managed serverless compute platform that runs stateless OCI container images directly. Cloud Run abstracts all infrastructure management, automatically scaling container instances from **zero to thousands** based on incoming HTTP traffic, WebSockets, gRPC, or events.

Unlike AWS Lambda (which executes exactly one request per container instance at a time), Cloud Run's defining architectural advantage is its **request concurrency model**: a single container instance can process up to **1,000 concurrent requests simultaneously**.

---

## Architecture & Mental Model

### Cloud Run Request Lifecycle & Concurrency

```
                        Incoming HTTP Requests
                                  │
                                  ▼
                   Google Global Front End (GFE)
                                  │
                                  ▼
                     Cloud Run Request Autoscaler
             ┌────────────────────┴────────────────────┐
             │ Current Load: 150 concurrent requests   │
             │ Container Concurrency setting: 80       │
             │ Target instances needed: ceil(150/80)=2 │
             └────────────────────┬────────────────────┘
                                  │
                  ┌───────────────┴───────────────┐
                  ▼                               ▼
       ┌─────────────────────┐         ┌─────────────────────┐
       │ Container Instance 1│         │ Container Instance 2│
       │  (Handling 80 reqs) │         │  (Handling 70 reqs) │
       │  vCPU: 1, RAM: 512MB│         │  vCPU: 1, RAM: 512MB│
       └─────────────────────┘         └─────────────────────┘
```

* **Cost Efficiency:** Instead of provisioning 150 separate instances (as Lambda would), Cloud Run serves the identical workload using only **2 container instances**.

---

## Core Concepts

### 1. Cloud Run Services vs. Cloud Run Jobs

| Dimension | Cloud Run Services | Cloud Run Jobs |
| :--- | :--- | :--- |
| **Trigger** | Ingress-driven: HTTP, HTTPS, WebSockets, gRPC, Pub/Sub | Invoked explicitly via CLI, API, or Cloud Scheduler |
| **Execution Model** | Continuously listening on `$PORT` (default 8080) | Runs until completion (exit code 0 or error) |
| **Max Timeout** | 60 minutes per request | 24 hours per task execution |
| **Scaling** | Scale-to-zero when traffic stops; scales out on concurrency | Parallel tasks array (`--tasks=50`, `--parallelism=10`) |
| **Use Cases** | Web apps, REST APIs, webhooks, microservices | DB migrations, batch video processing, periodic reports |

### 2. Concurrency Tuning

Concurrency specifies the maximum number of simultaneous requests a single container instance can receive:
* **Default:** 80 concurrent requests per instance.
* **Range:** 1 to 1,000.
* **Tuning Guide:**
  * **I/O-Bound (Node.js, Go, Python AsyncIO):** Concurrency 80–200 works exceptionally well because threads yield during network/DB waits.
  * **CPU-Bound (Image processing, ML inference, cryptography):** Set concurrency to **1 to 4** to prevent CPU starvation and latency spikes.

### 3. CPU Allocation: Throttled vs. Always-On

* **CPU allocated during request processing (Default):**
  * CPU is granted only while an active HTTP request is being processed.
  * When no requests are in flight, CPU is throttled to near 0%.
  * **Gotcha:** Any background thread or async task executing outside an active request scope is frozen!
* **CPU always allocated:**
  * CPU is continuously provided throughout the container's entire lifecycle.
  * Enables background tasks, scheduled polling, and long-lived WebSockets without freezing.
  * Incurs hourly billing for the entire duration the instance exists.

### 4. Direct VPC Egress vs. Serverless VPC Access Connector

To connect Cloud Run to private resources (like a private Cloud SQL instance or Redis):

| Approach | Mechanics | Tradeoffs |
| :--- | :--- | :--- |
| **Serverless VPC Access Connector** | Deploys dedicated `e2-micro` bridge VMs in your VPC | Extra cost ($20–$30/mo/connector), scaling bottlenecks, slow provisioning |
| **Direct VPC Egress (Modern Default)** | Directly attaches container network interfaces to your VPC subnet | **Zero connector VMs**, zero connector cost, sub-second scaling, lower latency |

---

## Production `gcloud` CLI Commands

### 1. Deploying a Production Service with Direct VPC Egress & Secrets

```bash
gcloud run deploy api-service \
  --image=gcr.io/my-prod-project/api:v1.2.0 \
  --region=us-central1 \
  --platform=managed \
  --allow-unauthenticated \
  --concurrency=80 \
  --cpu=1 \
  --memory=512Mi \
  --min-instances=1 \
  --max-instances=50 \
  --timeout=30s \
  --network=prod-vpc \
  --subnet=prod-us-central1 \
  --vpc-egress=private-ranges-only \
  --set-secrets="DB_PASSWORD=projects/123456789012/secrets/db-pass:latest" \
  --service-account=api-runner@my-prod-project.iam.gserviceaccount.com
```

### 2. Executing a Parallel Batch Job

```bash
# 1. Create a Cloud Run Job
gcloud run jobs create data-indexer \
  --image=gcr.io/my-prod-project/indexer:latest \
  --region=us-central1 \
  --tasks=20 \
  --parallelism=5 \
  --max-retries=3 \
  --cpu=2 \
  --memory=2Gi

# 2. Execute the job
gcloud run jobs execute data-indexer --region=us-central1 --wait
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max instances per service** | 1,000 (default) | Can be increased to 10,000 via quota request |
| **Max request timeout** | 60 minutes | Default is 5 minutes |
| **Max container image size** | 32 GB | Keep under 500 MB for fast cold starts |
| **Max memory per instance** | 32 GiB | Up to 8 vCPUs |
| **Default HTTP port** | Reads `$PORT` (8080 default) | Container must bind to `0.0.0.0:$PORT` |

---

## References

* **Homepage:** https://cloud.google.com/run
* **Documentation:** https://cloud.google.com/run/docs
* **Concurrency Guide:** https://cloud.google.com/run/docs/about-instance-concurrency
* **Direct VPC Egress:** https://cloud.google.com/run/docs/configuring/vpc-direct-vpc
* **Pricing:** https://cloud.google.com/run/pricing

---

## Pricing Examples

### Scenario 1: Low-Traffic Web API (Scale-to-Zero)
* API receives 500,000 requests / month with average response time of 200 ms.
* Concurrency: 80. Instance footprint: 1 vCPU, 512 MB RAM.
* Active compute time: (500,000 reqs × 0.2s) / 80 = 1,250 instance-seconds.
* Monthly Free Tier: First 2 million requests, 360,000 vCPU-seconds, and 180,000 GiB-seconds are **completely free** every month.
* **Total Monthly Bill:** **$0.00 / month** (Falls entirely within the permanent free tier).

### Scenario 2: High-Traffic Production Microservice
* 100 million requests / month, average execution time: 100 ms.
* Settings: 1 vCPU, 512 MB RAM, concurrency: 50.
* Billable vCPU-seconds: ~200,000 vCPU-seconds.
* Minimum instances: 1 continuous warm instance (to eliminate cold starts):
  * 730 hours × 3600s = 2,628,000 vCPU-seconds (idle tier @ $0.0000025/sec = ~$6.57).
* Total requests + active execution: ~$45.00.
* **Total Monthly Cost:** **~$51.57 / month**. (An equivalent AWS Lambda workload with 100M invocations would cost ~$180+ due to 1-request-per-instance limitations).

---

## Nuggets & Gotchas

1. **The Background Processing Freeze Trap:** If using default request-based CPU allocation, Cloud Run **throttles CPU to 0% the microsecond the HTTP response is returned**. If your code spawns an unawaited goroutine, Celery worker, or background promise (`setTimeout`), it will freeze immediately and only resume execution when the next unrelated HTTP request arrives hours later. Use Cloud Tasks or set `--no-cpu-throttling`.
2. **Container Must Listen on `0.0.0.0`, Not `127.0.0.1`:** Cloud Run injects the listening port via the `$PORT` environment variable (default 8080). If your web framework binds to `localhost` or `127.0.0.1`, Cloud Run's external health checks cannot reach the container, causing deployments to fail with `Container failed to start. Failed to listen on PORT`. Always bind to `0.0.0.0`.
3. **Cold Starts and Ephemeral Filesystem Limits:** The container filesystem is an in-memory `tmpfs` RAM disk. Writing large files (e.g., generating 1 GB PDFs or video exports) directly to `/tmp` consumes the container's allocated RAM memory quota. If RAM runs out, the container is immediately killed with an `OutOfMemory (OOM)` error.
4. **Direct VPC Egress Requires Private Google Access:** When using Direct VPC Egress with `--vpc-egress=all-traffic`, outbound calls from Cloud Run to public Google APIs (like BigQuery or Secret Manager) are routed through your VPC subnet. If that subnet lacks `Private Google Access` or a Cloud NAT gateway, all outbound Google API calls will time out.
5. **Database Connection Pool Explosions:** If traffic surges and Cloud Run autoscales from 2 instances to 100 instances, each container instance opening a connection pool of 20 database connections will suddenly bombard Cloud SQL with 2,000 simultaneous connections, crashing Postgres or MySQL. Always use **Cloud SQL Auth Proxy** with connection limits or deploy an external pooler like **PgBouncer**.

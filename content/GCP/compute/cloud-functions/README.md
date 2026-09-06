---
title: GCP Cloud Functions (2nd Gen) & Eventarc
description: Cloud Functions 2nd Gen architecture — Cloud Run infrastructure, Eventarc CloudEvents triggers, concurrency, cold-start mitigation, and 60-minute execution limits.
tags:
  - gcp
  - compute
  - cloud-functions
  - serverless
  - eventarc
  - cloudevents
---

# GCP Cloud Functions (2nd Gen) & Eventarc ⚡📨

Google Cloud Functions (2nd Gen) is Google's next-generation Function-as-a-Service (FaaS) platform. Re-architected from the ground up, Cloud Functions (2nd Gen) runs directly on top of **Google Cloud Run** and **Eventarc**, transforming simple developer code into containerized, high-concurrency serverless microservices.

---

## Architecture & Mental Model

### Cloud Functions 2nd Gen Architecture Stack

Unlike 1st Gen functions (which ran on legacy App Engine infrastructure), 2nd Gen functions are compiled into OCI container images via **Google Cloud Build** and executed on **Cloud Run**:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Developer Source Code                           │
│          (Python, Node.js, Go, Java, .NET, Ruby, PHP)                  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ gcloud functions deploy
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        Google Cloud Build                              │
│   Uses open-source Buildpacks to package code into an OCI image        │
│   and pushes to Artifact Registry (us-docker.pkg.dev/...)              │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Deploys container
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   Underlying Cloud Run Service                         │
│                                                                        │
│   • Request Concurrency: Up to 1,000 requests per instance (Def: 1)    │
│   • Execution Timeout: Up to 60 minutes for HTTP functions             │
│   • CPU/Memory Sizing: Up to 8 vCPU and 32 GiB RAM                     │
│   • Traffic Splitting: Native canary revisions (e.g. 90/10 split)      │
└───────────────────────────────────▲────────────────────────────────────┘
                                    │ Invokes
                                    │
┌───────────────────────────────────┴────────────────────────────────────┐
│                             Eventarc                                   │
│   Standardized CNCF CloudEvents v1.0 Delivery Engine:                  │
│   • Direct Cloud Storage mutations (object.finalize)                   │
│   • Cloud Pub/Sub message publishing                                   │
│   • 130+ GCP services via Cloud Audit Log event filtering             │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 1st Gen vs. 2nd Gen Comparison

| Architectural Dimension | 1st Gen Functions (Legacy) | 2nd Gen Functions (Modern Standard) |
| :--- | :--- | :--- |
| **Underlying Infrastructure**| App Engine internal runtime | **Google Cloud Run** |
| **Event Routing Engine** | Legacy proprietary event broker | **Eventarc (CNCF CloudEvents v1.0)** |
| **Concurrency per Instance** | Strictly **1 request at a time** | **Up to 1,000 concurrent requests** |
| **Max Request Timeout** | 9 minutes (540 seconds) | **60 minutes (3,600s)** for HTTP |
| **Max Memory & CPU** | 8 GiB RAM / 2 vCPUs | **32 GiB RAM / 8 vCPUs** |
| **Traffic Splitting** | Not supported | **Supported natively (Canary rollouts)** |
| **Direct VPC Egress** | Requires Serverless VPC Access | **Direct VPC Egress** supported |

---

## Core Concepts

### 1. Concurrency Tuning in Serverless FaaS

In AWS Lambda and 1st Gen Cloud Functions, if 100 simultaneous requests arrive, the cloud provider spins up **100 independent container instances**, triggering 100 separate cold starts and risking database connection pool exhaustion.
* In Cloud Functions 2nd Gen, setting `--concurrency=80` allows a single warm function instance to process 80 requests simultaneously.
* Dramatically slashes compute costs and eliminates cold starts for concurrent traffic.

### 2. Eventarc & CloudEvents Specification

All asynchronous event-driven functions in 2nd Gen receive payloads structured according to the **CNCF CloudEvents v1.0** specification:

```json
{
  "specversion": "1.0",
  "type": "google.cloud.storage.object.v1.finalized",
  "source": "//storage.googleapis.com/projects/_/buckets/my-prod-bucket",
  "id": "1234567890",
  "time": "2026-09-06T12:00:00Z",
  "datacontenttype": "application/json",
  "data": {
    "bucket": "my-prod-bucket",
    "name": "invoices/invoice-001.pdf",
    "size": "45210"
  }
}
```

* **Uniform Developer Experience:** Whether an event originates from a Cloud Storage upload, a BigQuery table creation, or a Firebase user sign-up, the envelope format is identical.

### 3. Cold Start Optimization

* **Min Instances (`--min-instances=1`):** Keeps a pre-warmed instance constantly provisioned to eliminate cold starts for latency-sensitive customer APIs.
* **Buildpack Optimization:** Keep dependency manifests (`package.json`, `requirements.txt`) lean. Heavy libraries (like Pandas, PyTorch, or TensorFlow) dramatically increase container initialization time.

---

## Production `gcloud` CLI Commands

### 1. Deploying a High-Concurrency HTTP Function with Direct VPC Egress

```bash
gcloud functions deploy user-service \
  --gen2 \
  --runtime=python311 \
  --region=us-central1 \
  --source=./src \
  --entry-point=handle_request \
  --trigger-http \
  --allow-unauthenticated \
  --concurrency=80 \
  --cpu=1 \
  --memory=512Mi \
  --min-instances=1 \
  --max-instances=20 \
  --timeout=60s \
  --network=prod-vpc \
  --subnet=prod-us-central1 \
  --vpc-egress=private-ranges-only \
  --set-secrets="API_KEY=projects/123456789012/secrets/api-key:latest" \
  --service-account=func-runner@my-prod-project.iam.gserviceaccount.com
```

### 2. Deploying an Event-Driven Function Triggered by Cloud Storage via Eventarc

```bash
gcloud functions deploy thumbnail-generator \
  --gen2 \
  --runtime=nodejs20 \
  --region=us-central1 \
  --source=./thumbnail-src \
  --entry-point=generateThumbnail \
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
  --trigger-event-filters="bucket=prod-raw-images" \
  --memory=1Gi \
  --timeout=120s \
  --service-account=func-runner@my-prod-project.iam.gserviceaccount.com
```

### 3. Python Sample: Processing a CloudEvent Payload

```python
import functions_framework
from cloudevents.http import CloudEvent

@functions_framework.cloud_event
def generate_thumbnail(cloudevent: CloudEvent):
    # Extract CloudEvent metadata and data payload
    event_type = cloudevent["type"]
    data = cloudevent.data

    bucket_name = data["bucket"]
    file_name = data["name"]
    file_size = data["size"]

    print(f"Received event: {event_type}")
    print(f"Processing newly created object: gs://{bucket_name}/{file_name} ({file_size} bytes)")

    # Execute image processing logic...
    return "OK", 200
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max HTTP execution timeout** | 60 minutes (3,600s) | Configurable up from 1st Gen 9-min limit |
| **Max event-driven timeout** | 10 minutes (600s) | For Eventarc background triggers |
| **Max function memory** | 32 GiB | Up to 8 vCPUs |
| **Max request concurrency** | 1,000 per instance | Default is 1; tune according to I/O vs CPU |
| **Max deployment size** | 500 MB (compressed) | Store heavy model weights in Cloud Storage |

---

## References

* **Cloud Functions 2nd Gen Documentation:** https://cloud.google.com/functions/docs/2nd-gen/overview
* **Eventarc Overview:** https://cloud.google.com/eventarc/docs
* **CloudEvents Specification:** https://cloudevents.io/
* **Pricing:** https://cloud.google.com/functions/pricing

---

## Pricing Examples

### Scenario 1: Event-Driven Image Thumbnail Generation
* 500,000 image uploads per month triggering a 2nd Gen function.
* Execution time: 800 ms per invocation. Allocation: 1 vCPU, 512 MB RAM.
* Total vCPU-seconds: 500,000 × 1 vCPU × 0.8s = 400,000 vCPU-seconds.
* Monthly Free Tier: First 2 million invocations, 400,000 vCPU-seconds, and 200,000 GB-seconds are **100% free every month**.
* **Total Monthly Bill:** **$0.00 / month** (Falls entirely within the permanent free tier).

### Scenario 2: High-Throughput Webhook Ingestion API
* 50 million inbound webhook requests per month with average latency of 150 ms.
* Concurrency tuned to 50 requests per instance.
* Billable compute: (50M reqs × 0.15s) / 50 = 150,000 instance-seconds.
* Invocation requests fee (after 2M free): 48M × $0.40 / million = $19.20.
* Active vCPU/RAM compute time: ~$5.50.
* 1 Pre-warmed min-instance (`--min-instances=1`) to eliminate cold starts: ~$6.50 / month.
* **Total Monthly Cost:** **~$31.20 / month** (Handling 50M webhooks with zero cold starts).

---

## Nuggets & Gotchas

1. **2nd Gen Functions Appear in the Cloud Run Console:** Because 2nd Gen functions compile directly to Cloud Run services, they will appear in both the Cloud Functions console and the Cloud Run console. If an operator edits the service configuration directly in Cloud Run, those changes can be wiped out on the next `gcloud functions deploy` execution. Always manage configuration via the Functions CLI or Terraform.
2. **The CloudEvent `finalized` Loop Disaster:** If an event-driven function is triggered by `google.cloud.storage.object.v1.finalized` on Bucket A, and the function's code writes an output file or thumbnail back to **Bucket A**, the newly written file will trigger another `finalized` event! This creates an **infinite recursive execution loop** that can burn thousands of dollars in minutes. Always write output files to a separate destination bucket (e.g. Bucket B).
3. **Missing Eventarc Service Agent Permissions:** When deploying an event-driven function for the first time, Eventarc requires permission to publish events from your services. If you see `FAILED_PRECONDITION: Eventarc Service Agent lacks roles/eventarc.serviceAgent`, you must explicitly grant the service agent role or allow GCP to auto-generate it.
4. **Default Concurrency is 1 (Not Cloud Run's 80):** When deploying a service directly via Cloud Run, concurrency defaults to 80. However, when deploying via `gcloud functions deploy --gen2`, concurrency defaults to **1** to maintain backwards compatibility with 1st Gen single-threaded behavior! To take advantage of multi-request cost savings, you must explicitly pass `--concurrency=80`.
5. **Cold Starts on Min-Instances Scaling:** Setting `--min-instances=1` ensures that the *first* instance is warm. However, if traffic suddenly bursts to 50 concurrent requests and your function has `--concurrency=1`, Cloud Run must provision 49 new instances simultaneously. All 49 new instances will experience cold starts. Tune `--concurrency` alongside `--min-instances`.

---
title: Cloud Logging Architecture, Log Router, and Log Analytics
description: Exhaustive engineering guide to Google Cloud Logging — Log Router mechanics, exclusion filters, sink routing to BigQuery/Pub/Sub/GCS, log-based metrics, Log Analytics with SQL, and enterprise retention compliance.
tags:
  - gcp
  - logging
  - observability
  - log-analytics
  - bigquery
---

# Cloud Logging Architecture, Log Router, and Log Analytics 📜🔍

Google Cloud **Logging** (formerly Stackdriver Logging) is a fully managed, real-time distributed log management and analytics platform engineered to ingest, process, route, index, and analyze petabytes of log data from cloud infrastructure, Kubernetes clusters, audit trails, and application workloads. At its core is the **Log Router**, a high-performance filtering and routing engine that directs log events to durable storage buckets, BigQuery for SQL analytics, Cloud Pub/Sub for SIEM integration, or Cloud Storage for cost-effective multi-year compliance archiving.

---

## 1. Architecture & Log Router Mechanics

Every log entry generated across Google Cloud passes through the centralized **Log Router** before any storage fees or indexing operations occur.

```
                           LOG SOURCES & PRODUCERS
     ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────────┐
     │  Cloud Audit Logs    │ │ GKE / Kubernetes Log │ │ Application / Fluent │
     │  (Admin / Data / Sys)│ │ (Fluentbit / Daemon) │ │ Bit OpenTelemetry    │
     └──────────┬───────────┘ └──────────┬───────────┘ └──────────┬───────────┘
                │                        │                        │
                ▼                        ▼                        ▼
     ┌────────────────────────────────────────────────────────────────────────┐
     │                           THE LOG ROUTER                               │
     │                                                                        │
     │  ┌──────────────────────────────────────────────────────────────────┐  │
     │  │                   EXCLUSION FILTERS                              │  │
     │  │   - Discards noisy debug / health check logs BEFORE storage      │  │
     │  │   - Zero ingestion cost for excluded entries                     │  │
     │  └──────────────────────────────────┬───────────────────────────────┘  │
     │                                     │ Remaining Logs                   │
     │  ┌──────────────────────────────────▼───────────────────────────────┐  │
     │  │                      LOG ROUTER SINKS                            │  │
     │  │  Evaluates filter queries; forks stream across multiple targets  │  │
     │  └──────────────────────────────────┬───────────────────────────────┘  │
     └─────────────────────────────────────┼──────────────────────────────────┘
                                           │
         ┌───────────────────┬─────────────┴───────┬───────────────────┐
         │                   │                     │                   │
         ▼                   ▼                     ▼                   ▼
  ┌─────────────┐     ┌─────────────┐       ┌─────────────┐     ┌─────────────┐
  │ LOG BUCKETS │     │  BIGQUERY   │       │   PUBSUB    │     │ CLOUD STORE │
  │ _Default &  │     │ Log Analytic│       │ Real-Time   │     │ Multi-Year  │
  │ Custom CMEK │     │ SQL Engine  │       │ SIEM (Splunk│     │ Compliance  │
  │ (30d - 10y) │     │ PBI / Looker│       │ Datadog)    │     │ Cold Archive│
  └─────────────┘     └─────────────┘       └─────────────┘     └─────────────┘
```

### Core Log Flow Mechanics

1. **Log Router Evaluation:** Log entries arrive formatted as JSON payloads conformant to the standard `LogEntry` protocol buffer specification (timestamp, severity, monitored resource, labels, HTTP request metadata, and text/JSON payload).
2. **Exclusion Filters:** Exclusion rules intercept logs at the router level. Excluded logs are discarded immediately, incurring **$0.00 ingestion cost** and zero retention footprint.
3. **Default Sinks:** Every GCP project includes two built-in sinks:
   - `_Required`: Ingests Admin Activity, System Event, and Access Transparency audit logs. Retained for 400 days at $0.00 cost; cannot be modified or disabled.
   - `_Default`: Ingests all other logs (GKE stdout/stderr, Cloud Run, Data Access audit logs) into the project's `_Default` bucket with 30-day retention.
4. **Log Sinks & Dedicated Service Accounts:** Custom sinks use dedicated Google-managed service identities (`serviceAccount:service-<PROJECT_NUMBER>@gcp-sa-logging.iam.gserviceaccount.com`). Sinks route logs to external destinations (cross-project BigQuery, centralized Splunk Pub/Sub topics) with strict IAM validation.

---

## 2. Core Concepts: Log Analytics & Log-Based Metrics

### Log Analytics with BigQuery

Traditional log searching relies on text/regex filters. Cloud Logging provides **Log Analytics**, transforming log buckets into SQL-queryable analytics warehouses:
- **BigQuery Linked Datasets:** You can link a Log Bucket to BigQuery without copying data. Cloud Logging exposes a read-only BigQuery schema view directly over the bucket's underlying Capacitor storage.
- **SQL Analysis:** SREs and security analysts can execute standard ANSI SQL queries across billions of log records, joining logs against relational tables (e.g., querying order logs joined with customer master tables).

### Log-Based Metrics

Cloud Logging allows extracting numerical time-series metrics from log streams in real time as they pass through the Log Router:
- **Counter Metrics:** Increments a time-series counter every time a log matches a specific filter (e.g., count of `severity=ERROR` or HTTP `status=502`).
- **Distribution Metrics:** Extracts numerical values from JSON payloads (e.g., latency in ms, payload size in bytes) and records them into distribution histograms with configurable bucket boundaries. These metrics can trigger alerts in Cloud Monitoring.

---

## 3. Production Configuration & CLI (`gcloud`)

### 1. Optimize Ingestion with Router Exclusion Filters

Drastically cut logging bills by excluding routine HTTP 200 health check logs from GKE ingress and Kubernetes kubelet heartbeats:

```bash
# Update the _Default sink to exclude health probes and static asset requests
gcloud logging sinks update _Default \
    --exclusions="name=exclude-health-checks,description='Drop high-volume Kubelet and ALB health checks',filter='resource.type=\"k8s_container\" AND (jsonPayload.path=\"/healthz\" OR jsonPayload.path=\"/live\") AND jsonPayload.status=200'" \
    --project=core-infrastructure-prod
```

### 2. Create an Aggregated Enterprise Org Sink to Pub/Sub (SIEM)

Centralize all security and firewall logs across an entire GCP Organization into a centralized Pub/Sub topic for consumption by Splunk or Datadog:

```bash
# Create org-level sink with aggregation enabled
gcloud logging sinks create org-security-siem-sink \
    pubsub.googleapis.com/projects/security-hub-prod/topics/enterprise-siem-stream \
    --organization=123456789012 \
    --include-children \
    --log-filter='logName:"cloudaudit.googleapis.com" OR resource.type="gce_firewall_rule" OR resource.type="k8s_cluster"'

# Extract the writer identity generated for the sink
SINK_WRITER=$(gcloud logging sinks describe org-security-siem-sink \
    --organization=123456789012 \
    --format='value(writerIdentity)')

# Grant publisher permissions to the sink writer on the destination topic
gcloud pubsub topics add-iam-policy-binding enterprise-siem-stream \
    --member="${SINK_WRITER}" \
    --role="roles/pubsub.publisher" \
    --project=security-hub-prod
```

### 3. Deploy a Custom Log Bucket with Log Analytics & 365-Day Retention

```bash
# Create custom log bucket with SQL analytics enabled
gcloud logging buckets create enterprise-compliance-bucket \
    --location=us-central1 \
    --retention-days=365 \
    --enable-analytics \
    --description="HIPAA & PCI compliant immutable log bucket with SQL analytics" \
    --project=compliance-prod

# Link the log bucket to BigQuery for SQL queries
gcloud logging links create compliance-link \
    --bucket=enterprise-compliance-bucket \
    --location=us-central1 \
    --project=compliance-prod
```

### 4. Create a Log-Based Distribution Metric for Payment Latency

```bash
gcloud logging metrics create payment-processing-duration \
    --description="Tracks payment gateway latency extracted from JSON logs" \
    --log-filter='resource.type="k8s_container" AND jsonPayload.service="payment-processor" AND jsonPayload.duration_ms:*' \
    --value-extractor='EXTRACT(jsonPayload.duration_ms)' \
    --metric-descriptor='metric-kind=DELTA,value-type=DISTRIBUTION,unit=ms' \
    --project=compliance-prod
```

### 5. Query Logs with Cloud Logging CLI & SQL

Query via standard filter:
```bash
gcloud logging read \
    'resource.type="cloud_run_revision" AND severity>=ERROR AND timestamp >= "2026-09-06T00:00:00Z"' \
    --limit=10 \
    --format="table(timestamp,severity,resource.labels.service_name,textPayload,jsonPayload.message)" \
    --project=compliance-prod
```

Query via SQL using BigQuery linked dataset:
```sql
SELECT
  timestamp,
  log_name,
  severity,
  json_payload.user_id,
  json_payload.action,
  http_request.status
FROM
  `compliance-prod.us_central1.compliance-link._AllLogs`
WHERE
  timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND severity IN ('ERROR', 'CRITICAL')
ORDER BY
  timestamp DESC
LIMIT 100;
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Default Limit | Engineering Guidance |
| :--- | :--- | :--- |
| **Max Single Log Entry Size** | 256 KB | Truncated if exceeding 256 KB |
| **Log Router Write Throughput** | 10 MB/s per project | Auto-scalable to hundreds of MB/s upon request |
| **Log Buckets per Project** | 100 buckets per region | Organize by classification (audit, app, security) |
| **Log Retention Range** | 1 day to 3,650 days (10 yrs) | `_Default` is 30 days; `_Required` is 400 days (fixed) |
| **Exclusion Filters per Sink** | 50 exclusion filters | Combine patterns using boolean `OR` expressions |
| **Log Sinks per Project** | 200 sinks | Use organization/folder sinks for bulk forwarding |
| **Log-Based Counter Metrics** | 500 per project | Use regex / JSON extractors carefully |
| **Log-Based Distribution Metrics**| 100 per project | Custom histogram boundaries consume time-series slots |

---

## 5. Official References & Documentation

- [Google Cloud Logging Documentation](https://cloud.google.com/logging/docs)
- [Log Router Sinks & Exclusion Filters](https://cloud.google.com/logging/docs/routing/overview)
- [Log Analytics with SQL Overview](https://cloud.google.com/logging/docs/log-analytics)
- [Log-Based Metrics Guide](https://cloud.google.com/logging/docs/logs-based-metrics)
- [Cloud Logging Pricing Matrix](https://cloud.google.com/stackdriver/pricing)

---

## 6. Realistic Pricing Scenarios

Cloud Logging pricing is based on:
1. **Log Ingestion:**
   - First 50 GiB per project per month: **Free**.
   - Additional ingestion: **$0.50 per GiB**.
2. **Retention Beyond Default (30 Days):**
   - $0.01 per GiB per month for retention between 31 and 3,650 days.
3. **Log Analytics (SQL Queries):**
   - Direct queries inside Cloud Logging console: Free.
   - Queries executed via BigQuery linked dataset: Standard BigQuery query rates ($6.25 per TB scanned, or slots).
4. **Log Router Forwarding to Pub/Sub, BigQuery, or GCS:**
   - Ingestion into Log Router is evaluated; no extra egress fees for router sink forwarding to internal services.

### Scenario A: High-Traffic Microservice Fleet (Unfiltered vs Filtered)

- **Unfiltered State:**
  - 100 microservices logging debug lines and health probes.
  - Ingestion: 2,000 GiB (2 TiB) / month.
  - Ingestion Cost: $(2{,}000 - 50) \times \$0.50 = \mathbf{\$975.00 / month}$.
- **Filtered State (Applying Exclusion Filters):**
  - Exclude HTTP 200 health checks and verbose INFO logs: Drops 70% of noise.
  - Ingestion: 600 GiB / month.
  - Ingestion Cost: $(600 - 50) \times \$0.50 = \mathbf{\$275.00 / month}$.
- **Net Monthly Savings:** **$700.00 / month** ($8,400/year).

### Scenario B: Enterprise Regulatory Audit & Security Logging (Multi-Year Retention)

- **Profile:**
  - Ingests 5,000 GiB (5 TiB) / month of compliance audit logs.
  - Retention requirement: 365 days (1 year).
  - First 30 days storage included in ingestion price.
  - 11 additional months retained ($5{,}000 \text{ GiB} \times 11 = 55{,}000 \text{ GiB-months}$ accumulated steady state).
- **Monthly Cost Calculation:**
  - Ingestion: $(5{,}000 - 50) \times \$0.50 = \mathbf{\$2{,}475.00}$
  - Extended Retention: $55{,}000 \text{ GiB} \times \$0.01/\text{GiB} = \mathbf{\$550.00}$
- **Total Monthly Cost:** **$3,025.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Ingestion Cost Trap (Discard at the Router, Not the Bucket):** If you route logs into a bucket and later delete them, or if you write custom worker scripts to purge logs after 3 days, **you still pay the full $0.50/GiB ingestion fee**. The only way to prevent logging charges is to discard logs **at the Log Router** using exclusion filters before ingestion occurs.
2. **Log Entry 256 KB Truncation Silently Corrupts JSON:** If an application outputs a large stack trace, GraphQL response, or uncompressed JSON object exceeding 256 KB in a single log line, Cloud Logging silently truncates the payload, appending `... [TRUNCATED]`. This invalidates the JSON syntax, causing downstream log parsers and BigQuery linked views to fail to parse `jsonPayload`. Ensure client-side logging formatters truncate or chunk large text payloads before emitting.
3. **Aggregated Sinks Require Manual IAM Role Assignment:** When creating an aggregated sink across an Organization or Folder (`--include-children`), Cloud Logging generates a unique `writerIdentity` service account. The sink will **fail silently** and discard logs until you manually grant that generated `writerIdentity` write permissions on the destination Pub/Sub topic, BigQuery dataset, or GCS bucket in the target project.
4. **Log-Based Metrics Cannot Retroactively Parse Past Logs:** When you create a new log-based counter or distribution metric, it begins evaluating data from the exact second of creation forward. It cannot backfill or extract metrics from historical logs already stored in log buckets. Always declare critical operational and security log-based metrics during initial Terraform infrastructure provisioning.
5. **BigQuery Linked Dataset Metadata Overhead:** When running SQL queries on a BigQuery linked dataset (`_AllLogs`), queries scan the underlying partitioned storage. If you omit the `timestamp` filter in your `WHERE` clause, BigQuery scans the entire multi-month retention history of your log bucket, incurring massive on-demand query scanning costs. Always enforce strict timestamp bounds (e.g., `WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)`).
6. **Application Stdout/Stderr Formatting Matters:** When running containers on GKE or Cloud Run, standard output strings are ingested as `textPayload`. If your microservice outputs structured JSON strings (e.g., `{"message": "user login", "severity": "WARNING", "userId": 123}`), Cloud Logging automatically promotes it to `jsonPayload` and elevates the log entry's severity level to `WARNING`. If you log unformatted text with the word "error" in the middle, the entry will be ingested with default severity `INFO`, rendering severity-based alerts blind to the incident.

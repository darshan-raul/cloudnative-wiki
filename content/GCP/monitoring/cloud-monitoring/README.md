---
title: Cloud Monitoring Architecture, MQL, and SRE Observability
description: Exhaustive engineering guide to Google Cloud Monitoring (formerly Stackdriver) — cross-project metric scopes, Monitoring Query Language (MQL), PromQL, Google Managed Service for Prometheus (GMP), SLO/SLI tracking, and alerting policies.
tags:
  - gcp
  - monitoring
  - observability
  - sre
  - prometheus
---

# Cloud Monitoring Architecture, MQL, and SRE Observability 📈🛡️

Google Cloud **Monitoring** (formerly Stackdriver Monitoring) is a fully managed, enterprise-scale observability platform providing real-time visibility into infrastructure, container runtimes, managed services, and application telemetry. It delivers native collection of Google Cloud system metrics, deep Kubernetes monitoring via **Google Cloud Managed Service for Prometheus (GMP)**, advanced analytics using **Monitoring Query Language (MQL)** and **PromQL**, automated uptime checks, and mathematically rigorous **Service Level Objective (SLO)** tracking for SRE teams.

---

## 1. Architecture & Metric Collection Model

Cloud Monitoring employs a disaggregated time-series ingestion engine capable of processing millions of data points per second with sub-minute query latency across multiple Google Cloud projects.

```
                  SOURCES OF METRICS & TELEMETRY
    ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────────┐
    │  GCP System Metrics  │ │ GKE / Kubernetes GMP │ │ Application Custom / │
    │ (Compute, GCS, SQL)  │ │ (Pod / Node Exporters│ │ OpenTelemetry Agent  │
    └──────────┬───────────┘ └──────────┬───────────┘ └──────────┬───────────┘
               │ Native                 │ PromQL / OTLP          │ OTLP / StatsD
               ▼                        ▼                        ▼
    ┌────────────────────────────────────────────────────────────────────────┐
    │                 CLOUD MONITORING TIME-SERIES INGESTION                 │
    │                                                                        │
    │  - Metric Descriptors: Gauge, Delta, Cumulative                        │
    │  - Value Types: INT64, DOUBLE, STRING, DISTRIBUTION                    │
    │  - Monitored Resource: gce_instance, k8s_pod, cloud_run_revision       │
    └───────────────────────────────────┬────────────────────────────────────┘
                                        │ High-Speed Time-Series DB (Monarch)
                                        ▼
    ┌────────────────────────────────────────────────────────────────────────┐
    │                     CROSS-PROJECT METRICS SCOPE                        │
    │          (Single-Pane-of-Glass Scoping Project for Entire Org)         │
    │                                                                        │
    │   ┌────────────────────┐ ┌────────────────────┐ ┌───────────────────┐  │
    │   │ Projects: Core-VPC │ │ Projects: Prod-GKE │ │ Projects: Data-WH │  │
    │   └────────────────────┘ └────────────────────┘ └───────────────────┘  │
    └───────────────────────────────────┬────────────────────────────────────┘
                                        │
             ┌──────────────────────────┼──────────────────────────┐
             ▼                          ▼                          ▼
    ┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
    │ METRICS EXPLORER│        │ ALERTING ENGINE │        │ SRE SLO TRACKER │
    │   MQL / PromQL  │        │ Incident Routing│        │ Error Budgets & │
    │   Dashboards    │        │  PagerDuty / SC │        │ Burn Rate Alerts│
    └─────────────────┘        └─────────────────┘        └─────────────────┘
```

### Core Architecture Constructs

1. **Scoping Project vs Monitored Projects:** In an enterprise organization, a central **Scoping Project** is designated as the monitoring hub. Up to 375 **Monitored Projects** are bound to this scope, enabling unified dashboards, cross-project metric correlations, and enterprise-wide alerts without duplicating metric ingestion.
2. **Metric Descriptor Taxonomy:** Every metric is modeled as a tuple:
   - **Metric Type:** A unique URI string, e.g., `compute.googleapis.com/instance/cpu/utilization`.
   - **Metric Kind:** `GAUGE` (instantaneous snapshot), `DELTA` (change over time window), or `CUMULATIVE` (monotonically increasing counter, e.g., total bytes sent).
   - **Value Type:** `INT64`, `DOUBLE`, `STRING`, `BOOLEAN`, or `DISTRIBUTION` (histograms preserving percentiles P50, P90, P99).
3. **Monitored Resource Model:** Captures metadata about where the data originated (e.g., `resource.type="k8s_container"`, `resource.labels.cluster_name="prod-us-east"`, `resource.labels.pod_name="auth-service-xyz"`).

---

## 2. Advanced Query Languages: MQL vs PromQL

Cloud Monitoring natively supports both **Monitoring Query Language (MQL)** and standard **PromQL**.

### Monitoring Query Language (MQL)

MQL is a functional, pipe-delimited (`|`) language designed for sophisticated time-series algebra, multi-metric joins, and distribution percentile calculations.

#### Example 1: Compute P99 Latency Across All GKE Microservices
```mql
fetch k8s_container
| metric 'custom.googleapis.com/http/server/duration'
| group_by [resource.cluster_name, metric.service_name],
    [p99: percentile(val(), 99)]
| every 1m
| condition p99 > 500 'ms'
```

#### Example 2: Ratio Calculation (HTTP 5xx Error Rate)
```mql
fetch cloud_run_revision
| metric 'run.googleapis.com/request_count'
| filter metric.response_code_class == '5xx'
| group_by [resource.service_name], [error_count: sum(val())]
| every 1m
| {
    ident
  ;
    fetch cloud_run_revision
    | metric 'run.googleapis.com/request_count'
    | group_by [resource.service_name], [total_count: sum(val())]
    | every 1m
  }
| ratio
| condition val() > 0.01
```

### Google Cloud Managed Service for Prometheus (GMP)

- **Pure Prometheus Compatibility:** Deploys lightweight collectors (`PodMonitoring` and `ClusterPodMonitoring` Custom Resources) directly into GKE clusters.
- **Serverless Ingestion:** Workers scrape metrics and push directly into Monarch (Google's planetary-scale time-series database), eliminating local Prometheus TSDB disk volume management, long-term retention sharding, and Thanos/Cortex operational complexity.

---

## 3. Production Deployment & Management CLI (`gcloud`)

### 1. Create a Scoping Project & Link Monitored Projects

```bash
# Link production microservice project to the central observability project
gcloud monitoring metrics-scopes list --project=observability-hub-prod

gcloud monitoring metrics-scopes create \
    "projects/observability-hub-prod/monitoredProjects/microservices-prod" \
    --project=observability-hub-prod
```

### 2. Configure GKE Managed Service for Prometheus (GMP)

Enable GMP on an existing GKE cluster:

```bash
gcloud container clusters update prod-cluster \
    --region=us-central1 \
    --enable-managed-prometheus \
    --project=microservices-prod
```

Apply a `PodMonitoring` resource to scrape application metrics:

```yaml
apiVersion: monitoring.googleapis.com/v1
kind: PodMonitoring
metadata:
  name: order-service-metrics
  namespace: e-commerce
spec:
  selector:
    matchLabels:
      app: order-service
  endpoints:
  - port: metrics
    interval: 15s
    path: /actuator/prometheus
```

### 3. Create a Multi-Channel Notification Channel (Slack + PagerDuty + Webhook)

```bash
# Create PagerDuty notification channel
gcloud beta monitoring channels create \
    --display-name="PagerDuty - SRE High Severity" \
    --type=pagerduty \
    --channel-content-from-file=- <<EOF
{
  "service_key": "pd-service-routing-key-991288"
}
EOF
```

### 4. Deploy Production Alerting Policy via CLI

Create an alert policy `high-memory-alert.json`:

```json
{
  "displayName": "GCE High Memory Utilization (>90% for 5m)",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "Compute VM Memory Pressure",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"agent.googleapis.com/memory/percent_used\" AND metric.labels.state = \"used\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 90,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "notificationChannels": [
    "projects/observability-hub-prod/notificationChannels/123456789012345"
  ],
  "documentation": {
    "content": "## Runbook: GCE VM High Memory Utilization\n1. SSH to instance via OS Login: `gcloud compute ssh ${resource.label.instance_id}`\n2. Inspect top memory consumers: `top -o %MEM` or `ps aux --sort=-%mem`\n3. Check dmesg for OOM killer invocations: `dmesg -T | grep -i oom`",
    "mimeType": "text/markdown"
  }
}
```

Apply alert policy:

```bash
gcloud alpha monitoring policies create \
    --policy-from-file=high-memory-alert.json \
    --project=observability-hub-prod
```

### 5. Deploy Service Level Objectives (SLO) and Multi-Burn-Rate Alerts

Create an availability SLO for a Cloud Run service:

```bash
# List discovered services in the project
gcloud monitoring services list --project=microservices-prod

# Create 99.9% availability SLO over a 28-day rolling window
gcloud monitoring services slo create \
    --service=cloud-run:service:order-api \
    --display-name="Order API 99.9% Availability (Rolling 28d)" \
    --goal=0.999 \
    --rolling-period=28d \
    --basic-sli-availability \
    --project=microservices-prod
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Default Quota | Engineering Guidance |
| :--- | :--- | :--- |
| **Monitored Projects per Scope** | Up to 375 projects | Allocate 1 scoping project per organization/environment |
| **Alerting Policies per Project** | 500 policies | Consolidate alerts using multi-condition policies |
| **Notification Channels** | 500 channels | Manage channels via Terraform / gcloud |
| **Uptime Checks per Project** | 100 public checks | Runs from 6 geographical probing locations worldwide |
| **Metric Ingestion Rate (Custom)**| 10,000 requests/sec | Soft limit; request expansion for large GMP deployments |
| **Data Retention (System Metrics)**| 6 weeks (42 days) | Downsampled for long-term historical visibility |
| **Data Retention (Custom / GMP)** | 24 months (730 days) | Retained without downsampling at native resolution |
| **Scrape Frequency (GMP)** | Minimum 5 seconds | Standard production default is 15s to 30s |

---

## 5. Official References & Documentation

- [Google Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)
- [Monitoring Query Language (MQL) Reference](https://cloud.google.com/monitoring/mql/reference)
- [Google Cloud Managed Service for Prometheus (GMP)](https://cloud.google.com/stackdriver/docs/managed-prometheus)
- [Google SRE Book: Alerting on SLOs and Error Budgets](https://sre.google/workbook/alerting-on-slos/)
- [Cloud Monitoring Pricing Calculator](https://cloud.google.com/stackdriver/pricing)

---

## 6. Realistic Pricing Scenarios

Cloud Monitoring pricing is based on:
1. **Google Cloud System Metrics:** **100% Free** (Compute, GKE system, GCS, Cloud SQL, etc. incur zero ingestion charge).
2. **Custom Metrics / Prometheus Metrics / Logs-based Metrics:**
   - First 150 MiB/month: Free.
   - Next 100,000 MiB: $0.2580 per MiB.
   - Next 150,000 MiB: $0.1510 per MiB.
   - Above 250,000 MiB: $0.0610 per MiB.
3. **Metric Read Queries (API calls):** Free for Cloud Monitoring console & dashboards; API calls beyond 1M requests charged at $0.01 per 1,000 requests.

### Scenario A: Mid-Sized Enterprise GKE Infrastructure with GMP

- **Workload Profile:**
  - 5 GKE clusters, 40 nodes, 300 pods.
  - Google System metrics: ~2,500 series (Free).
  - Managed Prometheus (GMP) scraping: 15,000 active metric samples per second.
  - Monthly Metric Volume:
    - 15,000 samples/sec × 8 bytes/sample × 2,592,000 sec/month = $311{,}040{,}000{,}000 \text{ bytes} \approx 296{,}630 \text{ MiB} \approx 290 \text{ GiB}$.
- **Monthly Cost Calculation:**
  - First 150 MiB: Free
  - Tier 1 (100,000 MiB): $100{,}000 \times \$0.2580 = \mathbf{\$258.00}$
  - Tier 2 (150,000 MiB): $150{,}000 \times \$0.1510 = \mathbf{\$226.50}$
  - Tier 3 (Remaining $46{,}480 \text{ MiB}$): $46{,}480 \times \$0.0610 = \mathbf{\$28.35}$
- **Total Monthly Cost:** **$512.85 / month**

### Scenario B: Massive Scale Telemetry & SRE Fleet (500+ Microservices)

- **Workload Profile:**
  - 50 GKE clusters across 3 regions.
  - GMP scraping 120,000 samples/sec across all microservices.
  - Monthly Volume: $120{,}000 \times 8 \times 2{,}592{,}000 \approx 2{,}373{,}000 \text{ MiB} \approx 2.3 \text{ TiB}$.
- **Monthly Cost Calculation:**
  - Tier 1 ($100{,}000 \text{ MiB}$): $100{,}000 \times \$0.2580 = \mathbf{\$258.00}$
  - Tier 2 ($150{,}000 \text{ MiB}$): $150{,}000 \times \$0.1510 = \mathbf{\$226.50}$
  - Tier 3 ($2{,}123{,}000 \text{ MiB}$): $2{,}123{,}000 \times \$0.0610 = \mathbf{\$1{,}295.03}$
- **Total Monthly Cost:** **$1,779.53 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **Cardinaity Explosions in Custom Metrics:** A metric's unique time-series count equals the Cartesian product of all its label values. If an engineer injects `user_id`, `transaction_id`, or `order_id` as a Prometheus metric label, millions of short-lived time series are generated. Cloud Monitoring bills by data volume ingested; a cardinality explosion can drive monthly monitoring costs from $200 to over $20,000 in days. Enforce strict code-review policies rejecting high-cardinality labels in metrics.
2. **The "Alignment Period" vs "Query Window" Alert Pitfall:** When configuring alert conditions in Cloud Monitoring, the `alignmentPeriod` must never be shorter than the metric's reporting interval. If an agent reports memory metrics every 60 seconds, setting an `alignmentPeriod` of 10 seconds results in empty buckets and intermittent `NO_DATA` alert oscillations. For 60-second collection intervals, always configure an alignment period of at least 120 seconds.
3. **Use Multi-Burn-Rate Alerts to Avoid Alert Fatigue:** Traditional threshold alerts (e.g., "Error rate > 1% for 5 mins") trigger noisy alerts during brief traffic blips and miss slow, catastrophic leaks that exhaust 100% of the monthly error budget over 3 weeks. Implement Google SRE **Multi-Window Multi-Burn-Rate Alerts**: trigger page alerts only when the 1-hour burn rate exceeds 14x (consuming 2% of budget in 1 hour) **AND** the 5-minute burn rate confirms the incident is still actively occurring.
4. **Scoping Project Centralization Prevents IAM Sprawl:** Never create independent alert notification channels or dashboards inside every individual project. Create an isolated project (e.g., `company-observability-prod`), add all departmental GCP projects to its **Metrics Scope**, and manage all notification channels, SLOs, and MQL dashboards in this single hub. This guarantees engineers only need read access to the scoping project to view telemetry across the entire corporate estate.
5. **PromQL Metric Name Sanitization in GMP:** When migrating Prometheus PromQL dashboards to Cloud Monitoring, note that Google Cloud Managed Service for Prometheus prepends custom metrics with the prefix `prometheus.googleapis.com/`. While raw PromQL queries in the Cloud Console automatically handle metric name resolution, querying via the standard Cloud Monitoring REST API or Terraform requires the fully qualified name (e.g., `prometheus.googleapis.com/http_requests_total/counter`).
6. **Uptime Check Source IP Range Whitelisting:** Cloud Monitoring public uptime checks originate from dynamic Google probing servers worldwide. If your firewall rules or Cloud Armor security policies block unauthenticated external traffic, uptime checks will report false-positive outages. Either whitelist the official Google Cloud Uptime Check IP range (`gcloud monitoring uptime-check-ips list`) or deploy **Private Uptime Checks** targeting internal VPC endpoints via Private Service Connect.

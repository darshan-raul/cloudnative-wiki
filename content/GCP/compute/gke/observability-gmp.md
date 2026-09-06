---
title: GKE Observability Architecture — Managed Prometheus (GMP), Logging, and Trace
description: Exhaustive engineering guide to GKE observability — Google Cloud Managed Service for Prometheus (GMP), PodMonitoring & ClusterPodMonitoring Custom Resources, Cloud Logging high-volume filters, and Cloud Trace distributed tracing.
tags:
  - gcp
  - gke
  - observability
  - prometheus
  - gmp
  - logging
---

# GKE Observability Architecture — Managed Prometheus (GMP), Logging, and Trace 📈🔍

Operating enterprise Kubernetes clusters at scale requires deep, real-time observability across cluster nodes, system components, and microservices. Google Kubernetes Engine provides a fully integrated, cloud-native observability stack centered on **Google Cloud Managed Service for Prometheus (GMP)**. GMP delivers pure Prometheus-compatible metric collection without the operational burden of managing self-hosted Prometheus servers, TSDB storage volumes, long-term retention sharding, or Thanos clusters. Coupled with **Cloud Logging ContainerLogV2** and **Cloud Trace**, GKE provides end-to-end telemetry across metrics, logs, and distributed traces.

---

## 1. Architecture & The Managed Prometheus Pipeline

GMP replaces self-hosted Prometheus servers with lightweight, Kubernetes-native collectors that stream scraped metrics directly into Google Cloud's planetary-scale time-series database (**Monarch**).

```
                  KUBERNETES APPLICATION PODS (/metrics endpoints)
       ┌────────────────────────┐         ┌────────────────────────┐
       │ Pod A (App Service)    │         │ Pod B (Payment Engine) │
       │ Port 8080: /metrics    │         │ Port 9090: /prometheus │
       └───────────┬────────────┘         └───────────┬────────────┘
                   │                                  │
                   └─────────────────┬────────────────┘
                                     │ Scraped via HTTP / PromQL
                                     ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                   GKE MANAGED PROMETHEUS COLLECTOR FLEET               │
       │                   (Lightweight Go Collector per Node)                  │
       │                                                                        │
       │  ┌──────────────────────────────────────────────────────────────────┐  │
       │  │               PODMONITORING & CLUSTERPODMONITORING               │  │
       │  │  - Declarative Kubernetes Custom Resources (CRDs)                │  │
       │  │  - Automatically discovers pods based on labels & annotations    │  │
       │  │  - Configurable scrape intervals (15s to 60s) & metric relabeling│  │
       │  └──────────────────────────────────┬───────────────────────────────┘  │
       └─────────────────────────────────────┼──────────────────────────────────┘
                                             │ Parallel Ingestion Streams
       ══════════════════════════════════════╪═══════════════════════════════════
       GOOGLE CLOUD OBSERVABILITY BACKPLANE (Monarch Planetary Time-Series DB)  │
                                             ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                     GOOGLE CLOUD MONITORING ENGINE                     │
       │                                                                        │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ Native PromQL Engine   │         │ 24-Month Long-Term Ret │         │
       │  │ (Cloud Monitoring UI,  │         │ (Full resolution raw   │         │
       │  │  Grafana GCP Plugin)   │         │  data retention)       │         │
       │  └────────────────────────┘         └────────────────────────┘         │
       └────────────────────────────────────────────────────────────────────────┘
```

### Core Architecture Constructs

1. **Managed Data Collection:** GKE automatically deploys and manages the collector daemonset and Operator. Upgrades and patches are handled by Google with zero downtime.
2. **Declarative Custom Resources:**
   - **PodMonitoring:** Namespace-scoped resource that tells GMP which pods to scrape within a specific namespace.
   - **ClusterPodMonitoring:** Cluster-scoped resource that scrapes pods matching label selectors across *all* namespaces (e.g., scraping Istio or Envoy proxies globally).
3. **ContainerLogV2:** GKE's high-efficiency structured logging format. It splits logs into parsed JSON fields, separating stdout from stderr, container metadata, and log volume to optimize log querying in Cloud Logging.
4. **Grafana Integration:** Native Cloud Monitoring data source plugin enables connecting self-hosted or managed Grafana directly to GMP using standard **PromQL**.

---

## 2. PodMonitoring vs Standard Prometheus Operator

| Dimension | Standard Open-Source Prometheus | Google Managed Service for Prometheus (GMP) |
| :--- | :--- | :--- |
| **TSDB Storage Backend** | Local Persistent Disks (PDs) | **Monarch** (Google's planet-scale time-series DB) |
| **Data Retention** | Typically 14 to 30 days | **24 Months (730 days)** without downsampling |
| **High Availability** | Complex Thanos / Cortex setup | **Built-in multi-zone high availability** |
| **Collector Footprint** | Heavy (~2-8 GiB RAM per Prometheus)| Ultra-lightweight (~50 MiB RAM per collector) |
| **Query Language** | PromQL | **Pure PromQL** + Monitoring Query Language (MQL) |
| **Pricing Model** | Provisioned VM & PD disk cost | Ingestion volume (samples ingested per month) |

---

## 3. Production Deployment & CLI Operations (`gcloud` & `kubectl`)

### 1. Enable Managed Prometheus on GKE Cluster

```bash
gcloud container clusters update prod-regional-cluster \
    --region=us-central1 \
    --enable-managed-prometheus \
    --project=core-infrastructure-prod
```

### 2. Deploy a Production PodMonitoring Custom Resource

Create `order-service-podmonitoring.yaml`:

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
  - port: metrics # Matches containerPort name in deployment
    interval: 15s
    path: /actuator/prometheus
    # Metric Relabeling: Drop high-cardinality debugging metrics to cut ingestion costs
    metricRelabeling:
    - action: keep
      sourceLabels: [__name__]
      regex: "(http_server_requests_seconds_.*|jvm_memory_used_bytes|jvm_threads_live_threads|process_cpu_usage)"
```

Apply PodMonitoring:

```bash
kubectl apply -f order-service-podmonitoring.yaml

# Verify target discovery status
kubectl get podmonitorings -n e-commerce
```

### 3. Deploy ClusterPodMonitoring for Infrastructure Services

Create `envoy-cluster-podmonitoring.yaml`:

```yaml
apiVersion: monitoring.googleapis.com/v1
kind: ClusterPodMonitoring
metadata:
  name: envoy-sidecar-global-monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/component: proxy
  endpoints:
  - port: 15090
    interval: 30s
    path: /stats/prometheus
```

Apply ClusterPodMonitoring:

```bash
kubectl apply -f envoy-cluster-podmonitoring.yaml
```

### 4. Optimize GKE Cloud Logging with Exclusion Filters

GKE cluster system logs (Kubelet heartbeats, health checks) generate high-volume noise. Drop routine logs at the Log Router to eliminate unnecessary charges:

```bash
# Update Log Router _Default sink to exclude routine kubelet and health check probes
gcloud logging sinks update _Default \
    --exclusions="name=exclude-gke-kubelet-noise,description='Drop high-frequency Kubelet and liveness probe logs',filter='resource.type=\"k8s_container\" AND (textPayload=~\"GET /healthz\" OR textPayload=~\"GET /livez\" OR jsonPayload.path=\"/healthz\") AND jsonPayload.status=200'" \
    --project=core-infrastructure-prod
```

### 5. Query Metrics via PromQL in Cloud Shell / Monitoring API

```bash
# Query P99 HTTP latency across pods using PromQL
gcloud monitoring timeseries list \
    --filter='metric.type="prometheus.googleapis.com/http_server_requests_seconds_bucket/histogram"' \
    --project=core-infrastructure-prod
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Standard Limit / Quota | Engineering Guidance |
| :--- | :--- | :--- |
| **Max Scrape Frequency** | Minimum 5 seconds | Recommended production default: 15s to 30s |
| **Max Samples per Scrape** | 100,000 samples | Relabel metrics to drop unused time series |
| **Metric Retention** | **24 Months (730 days)** | Retained at native resolution without rollups |
| **Query Range Timeout** | 60 seconds per query | Restrict PromQL query windows (`[5m]`, `[1h]`) |
| **Monitored Projects per Scope**| Up to 375 projects | Unify multi-cluster metrics in single scoping project |

---

## 5. Official References & Documentation

- [Google Cloud Managed Service for Prometheus (GMP) Overview](https://cloud.google.com/stackdriver/docs/managed-prometheus)
- [GKE PodMonitoring and ClusterPodMonitoring Reference](https://cloud.google.com/stackdriver/docs/managed-prometheus/setup-managed#pod-monitoring)
- [Querying GMP Using PromQL](https://cloud.google.com/stackdriver/docs/managed-prometheus/query)
- [GKE ContainerLogV2 Structured Logging](https://cloud.google.com/kubernetes-engine/docs/how-to/fluentbit-structured-logging)
- [Cloud Monitoring Pricing](https://cloud.google.com/stackdriver/pricing)

---

## 6. Realistic Pricing Scenarios

Pricing components:
1. **Google Cloud System Metrics:** **100% Free** (CPU, RAM, disk I/O from GKE node agents).
2. **GMP Custom Prometheus Ingestion:**
   - First 150 MiB/month: Free.
   - Next 100,000 MiB: $0.2580 per MiB.
   - Next 150,000 MiB: $0.1510 per MiB.
   - Beyond 250,000 MiB: $0.0610 per MiB.
3. **Cloud Logging:** First 50 GiB free, then $0.50 per GiB.

### Scenario A: Mid-Sized Production GKE Cluster (20 Nodes, 100 Pods)

- **Workload Profile:**
  - 100 microservice pods scraped every 15 seconds.
  - Average metric generation: 250 active metrics per pod = 25,000 active time-series samples.
  - Samples per second: $25{,}000 / 15 \approx 1{,}666 \text{ samples/sec}$.
  - Monthly Volume: $1{,}666 \times 8 \text{ bytes} \times 2{,}592{,}000 \text{ sec} \approx 34{,}560 \text{ MiB} \approx 33.7 \text{ GiB}$.
- **Monthly Cost Calculation:**
  - Free Tier: 150 MiB deducted ($34{,}410 \text{ MiB}$ billable).
  - Ingestion Cost: $34{,}410 \text{ MiB} \times \$0.2580/\text{MiB} = \mathbf{\$88.78}$
  - System Metrics: **$0.00**
  - Cloud Logging (150 GiB logs - 50 GiB free = 100 GiB): $100 \times \$0.50 = \mathbf{\$50.00}$
- **Total Monthly Cost:** **$138.78 / month**

### Scenario B: Massive Multi-Cluster Enterprise Fleet (5,000 Pods with Relabeling)

- **Unoptimized State (Without Relabeling):**
  - Ingests 150,000 samples/sec (Spring Boot default metrics).
  - Ingestion Volume: $3{,}110{,}000 \text{ MiB} \approx 3 \text{ TiB}$.
  - Monthly Cost: **~$2,350.00 / month**.
- **Optimized State (Applying `metricRelabeling`):**
  - Drops 80% of unused JVM internal metrics; keeps only Golden Signals.
  - Ingestion Volume drops to 30,000 samples/sec (620,000 MiB).
  - Monthly Cost: **~$540.00 / month** (**$1,810/month saved**).

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Prometheus Cardinality Explosion Disaster:** If a developer adds a dynamic identifier (such as `user_id`, `email`, `order_uuid`, or full HTTP request path `/users/1238914`) as a label in a Prometheus counter or histogram, every single unique user creates a brand-new time series in Monarch. Within 24 hours, metric volume spikes by 1,000x, and your Cloud Monitoring invoice jumps from $100 to **over $15,000**. Enforce strict code review and use `metricRelabeling` to drop any label matching high-cardinality patterns.
2. **PromQL Metric Prefix Requirement in API Queries:** In the Cloud Console, you can query `http_requests_total`. However, when querying GMP through Terraform, the Cloud Monitoring REST API, or Python SDKs, the metric type **must be prefixed with `prometheus.googleapis.com/`** (e.g., `prometheus.googleapis.com/http_requests_total/counter`). Omitting the prefix returns `404 Metric type not found`.
3. **Scrape Timeout Must Be Lower Than Scrape Interval:** If you configure a scrape `interval: 15s` and a pod takes 18 seconds to generate its `/metrics` endpoint payload (due to high heap memory or slow metric serialization), the scrape times out. The collector skips the scrape, causing gaps in time-series graphs and triggering false `NO_DATA` alerting notifications. Always configure `timeout: 10s` for a 15s interval, and optimize application `/metrics` endpoint response times.
4. **ContainerLogV2 JSON Parsing Truncation:** ContainerLogV2 parses structured JSON output from containers into queryable fields (`jsonPayload`). However, if an application emits a single JSON log line exceeding 256 KB (e.g., a massive base64 string or giant GraphQL trace), Cloud Logging silently truncates the line, invalidating the JSON. The entry is degraded to raw `textPayload`, causing JSON-based alerting filters to fail silently.
5. **Multiple PodMonitorings Scraping the Same Pod Duplicates Costs:** If Team A creates a `PodMonitoring` matching `app: order-service` in namespace `finance`, and the platform team deploys a `ClusterPodMonitoring` matching `app.kubernetes.io/part-of: e-commerce`, **both collectors will scrape the pod concurrently**. Every metric will be ingested twice, doubling your monitoring invoice and causing fluctuating step artifacts in PromQL graphs. Audit active scrape targets using `kubectl get podmonitoring,clusterpodmonitoring --all-namespaces`.
6. **Log Exclusion Filters Save Thousands on GKE Clusters:** A default GKE cluster running 50 nodes generates over 500 GB of routine system logs (Kubelet probe checks, container start/stop events, health checks) every month ($250/month in useless logging). Deploying an exclusion filter on the `_Default` sink targeting `jsonPayload.path="/healthz"` and `jsonPayload.status=200` eliminates this noise with zero impact on operational troubleshooting.

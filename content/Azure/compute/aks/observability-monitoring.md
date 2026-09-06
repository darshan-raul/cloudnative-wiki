---
title: AKS Observability — Container Insights, Managed Prometheus, and ContainerLogV2
description: Exhaustive engineering guide to production observability on AKS — Azure Monitor Container Insights, Azure Managed Prometheus, Azure Managed Grafana, ContainerLogV2 cost optimization, and KQL performance troubleshooting.
tags:
  - azure
  - aks
  - observability
  - monitoring
  - prometheus
  - grafana
  - log-analytics
  - kql
---

# AKS Observability — Container Insights, Managed Prometheus, and ContainerLogV2 📊🔍

Operating distributed systems on Azure Kubernetes Service (AKS) requires complete visibility across three telemetry pillars: **Metrics**, **Logs**, and **Traces**. Historically, monitoring AKS involved ingesting massive volumes of raw stdout/stderr logs into Log Analytics, resulting in astronomical ingestion bills and querying lag. Today, modern AKS observability relies on a dual-engine architecture: **Azure Managed Service for Prometheus + Azure Managed Grafana** for high-frequency cloud-native time-series metrics, paired with **Azure Monitor Container Insights** using the **ContainerLogV2 schema** for structured, cost-optimized logging.

---

## 1. Architecture: The Unified Telemetry Ingestion Pipeline

```
                              AKS CLUSTER WORKLOADS & NODES
       ┌───────────────────────────────┬───────────────────────────────┐
       │ Application Pods (L7 Metrics) │ Host Node OS & Kubelet (L3/L4)│
       └───────────────┬───────────────┴───────────────┬───────────────┘
                       │                               │
       ┌───────────────┴───────────────┐               │
       │ Stdout / Stderr Log Streams   │               │ /metrics (Prometheus Format)
       ▼                               ▼               ▼
┌──────────────────────────────────────────────┐ ┌──────────────────────────────────────────────┐
│       CONTAINER INSIGHTS AMA AGENT           │ │     AZURE MANAGED PROMETHEUS AGENT           │
│       (Azure Monitor DaemonSet)              │ │     (Managed Prometheus Collector DaemonSet) │
│                                              │ │                                              │
│  - Filters out high-churn debug logs         │ │  - Scrapes metrics endpoints every 30s       │
│  - Formats into **ContainerLogV2 Schema**    │ │  - Excludes high-cardinality label noise     │
│  - Compresses and batches HTTP payloads      │ │  - Direct remote-write to Azure Monitor      │
└──────────────────────┬───────────────────────┘ └──────────────────────┬───────────────────────┘
                       │ Encrypted TLS Ingestion                        │ Ingestion (18-Month Retention)
                       ▼                                                ▼
┌──────────────────────────────────────────────┐ ┌──────────────────────────────────────────────┐
│         AZURE LOG ANALYTICS WORKSPACE        │ │         AZURE MONITOR PROMETHEUS STORE       │
│                                              │ │                                              │
│  - KQL Query Engine: Instant log analytics   │ │  - Native PromQL query compatibility         │
│  - Ingestion Alerting & Sentinel SIEM feeds  │ │  - Integrated with **Azure Managed Grafana** │
└──────────────────────────────────────────────┘ └──────────────────────────────────────────────┘
```

---

## 2. Ingestion Cost Optimization: ContainerLog vs. ContainerLogV2

The legacy `ContainerLog` schema stores raw unstructured text, duplicating container name, image, and pod ID metadata on every single log entry line, leading to massive billing bloat. **ContainerLogV2** structures and optimizes log payloads:

| Dimension | Legacy `ContainerLog` Schema | Modern `ContainerLogV2` Schema |
| :--- | :--- | :--- |
| **Log Format** | Raw string with duplicate metadata columns | **Consolidated JSON with dedicated LogSource**|
| **Ingestion Volume** | Baseline (100%) | **Reduced by 50% to 70%** |
| **Pod / Container Metadata**| Repeated per row | Compact normalized fields |
| **Log Splitting** | Chunks split across arbitrary lines | Preserves unbroken log entry integrity |
| **KQL Query Performance** | Slower string parsing | **Significantly faster indexing & querying** |

---

## 3. Production Configuration & CLI Operations (`az` CLI & KQL)

### 1. Enable Azure Managed Prometheus and Grafana on AKS

```bash
# Provision Azure Monitor Workspace for Managed Prometheus
az resource create \
    --resource-group rg-prod-monitoring \
    --namespace Microsoft.Monitor \
    --resource-type accounts \
    --name amw-eastus-prod \
    --location eastus \
    --properties "{}"

# Provision Azure Managed Grafana instance
az grafana create \
    --resource-group rg-prod-monitoring \
    --name grafana-prod-eastus

# Connect AKS to Managed Prometheus and link to Grafana
az aks update \
    --resource-group rg-prod-monitoring \
    --name aks-core-prod \
    --enable-azure-monitor-metrics \
    --azure-monitor-workspace-resource-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod-monitoring/providers/Microsoft.Monitor/accounts/amw-eastus-prod" \
    --grafana-resource-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod-monitoring/providers/Microsoft.Dashboard/grafana/grafana-prod-eastus"
```

### 2. Enable Container Insights with ContainerLogV2 Schema

```bash
# Enable Container Insights using a dedicated Log Analytics workspace
az aks enable-addons \
    --resource-group rg-prod-monitoring \
    --name aks-core-prod \
    --addons monitoring \
    --workspace-resource-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-prod-eastus"

# Switch schema to ContainerLogV2 using ConfigMap
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: container-azm-ms-agentconfig
  namespace: kube-system
data:
  schema-version: "v1"
  configfilter: "false"
  containerlog_schema_version: "v2"
EOF
```

### 3. SRE KQL Runbook: Diagnostic Queries in Log Analytics

#### Query 1: Detect OOMKilled Containers and Crash Loops

```kusto
// Find all pods terminated by Linux OOM killer (Exit Code 137) in the last 6 hours
KubePodInventory
| where TimeGenerated >= ago(6h)
| where PodStatus == "Failed" or ContainerStatusReason == "OOMKilled"
| project TimeGenerated, Namespace, Name, ContainerName, ContainerStatusReason, ExitCode=ContainerStatusExitCode
| summarize FailureCount = count() by Namespace, Name, ContainerName, tostring(ExitCode)
| order by FailureCount desc
```

#### Query 2: Search Error Logs via ContainerLogV2

```kusto
// High-performance search for 500 errors and Exceptions in production namespaces
ContainerLogV2
| where TimeGenerated >= ago(1h)
| where PodNamespace == "production"
| where LogLevel in ("Error", "Fatal") or LogMessage has_any ("Exception", "Fatal", "panic", "500 Internal Server Error")
| project TimeGenerated, PodName, ContainerName, LogMessage
| order by TimeGenerated desc
| take 100
```

---

## 4. Quotas, Performance & Configuration Limits

| Parameter | Metric / Platform Limit | Production Impact |
| :--- | :--- | :--- |
| **Prometheus Metric Retention** | **18 Months** | Included free in Azure Monitor Workspace |
| **Default Scrape Interval** | **30 seconds** | Configurable down to 10 seconds via PodAnnotations |
| **Log Analytics Ingestion Limit**| **Up to 500 TB / day** | Unconstrained enterprise log capacity |
| **Default Log Retention** | **30 Days** | Configurable up to 730 days (2 years) |
| **Prometheus Scraping Cap** | **Up to 5,000,000 samples/sec** | Scales to 100+ node clusters seamlessly |

---

## 5. Official References

- [Azure Monitor Container Insights Overview](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview)
- [Azure Managed Service for Prometheus](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-metrics-overview)
- [ContainerLogV2 Schema & Cost Optimization](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-cost-config#containerlogv2)
- [Azure Monitor Pricing Details](https://azure.microsoft.com/en-us/pricing/details/monitor/)

---

## 6. Realistic Pricing Scenarios

### Scenario A: High-Density Production Cluster (50 Nodes, ContainerLogV2)

- **Cluster Profile:**
  - 50x `Standard_D8ds_v5` nodes generating 500 GB of raw logs daily.
- **Cost Comparison: Legacy ContainerLog vs. ContainerLogV2:**
  - *Legacy ContainerLog:* 500 GB/day × 30 days = 15,000 GB/month × $2.30/GB = **$34,500 / month**.
  - *ContainerLogV2 (60% payload reduction):* 200 GB/day × 30 days = 6,000 GB/month × $2.30/GB = **$13,800 / month**.
- **Monthly Savings:** **$20,700 / month** *(Achieved simply by activating ContainerLogV2).*

### Scenario B: Cloud-Native Metrics with Azure Managed Prometheus & Grafana

- **Cluster Profile:**
  - 20 nodes scraping 15,000 active metric time-series.
  - Azure Managed Grafana Standard instance for operations dashboards.
- **Monthly Cost Breakdown:**
  - Managed Prometheus Ingestion: First 1,000,000 samples free; 15,000 series ≈ **$15.00 / month**.
  - Azure Managed Grafana Instance: 1 instance @ **$29.00 / month**.
- **Total Metrics Spend:** **$44.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Verbose Debug Logging Bill Shock:** In microservices where developers leave logging set to `DEBUG` or `TRACE` (e.g., logging every incoming HTTP payload and database query), a single microservice can ingest 20 GB of logs per hour ($1,100+/month in Log Analytics fees). Deploy a **Data Collection Rule (DCR)** or configure the Container Insights ConfigMap with `exclude-namespaces: ["dev", "staging"]` and filter out non-error logs.
2. **Prometheus High-Cardinality Label Explosions:** If developers expose Prometheus metrics with unbounded labels (e.g., `http_requests_total{user_id="1234567"}` where `user_id` is a UUID), the number of distinct time-series skyrockets to millions. This triggers **throttling in Azure Monitor Workspace** and results in huge ingestion bills. Always sanitize Prometheus metrics to only include bounded labels (e.g., `method`, `status_code`, `route`).
3. **Log Ingestion Latency (The 2-Minute Lag):** Azure Monitor Container Insights is a batched asynchronous log collection pipeline. There is an inherent **1 to 3 minute ingestion latency** between when a container writes to stdout and when the row appears in Log Analytics KQL search results. For real-time incident triage during an active outage, always use `kubectl logs -n <ns> <pod> --tail=100 -f` rather than waiting on Log Analytics.
4. **Agentless vs. DaemonSet AMA Performance Overhead:** The Azure Monitor Linux agent (`ama-logs`) runs as a DaemonSet on every node. If not configured with resource limits, the logging agent can consume 1 to 2 vCPUs on nodes processing heavy log bursts. Ensure the DaemonSet CPU request is capped at `250m` to prevent stealing compute from customer microservices.
5. **Grafana Managed Identity Authorization Failures:** When creating an Azure Managed Grafana instance, Azure does not automatically grant it read permissions on existing Azure Monitor Workspaces. Grafana dashboards will report `Permission Denied / No Data`. You must explicitly assign the Grafana managed identity the **"Monitoring Reader"** role on the Azure Monitor Workspace resource group.

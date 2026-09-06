---
title: Azure Monitor & Log Analytics Architecture, KQL, and Observability
description: Exhaustive engineering guide to Azure Monitor and Log Analytics Workspaces — centralized log ingestion, Kusto Query Language (KQL), diagnostic settings, commitment tiers, and observability pipelines.
tags:
  - azure
  - monitoring
  - observability
  - log-analytics
  - kql
---

# Azure Monitor & Log Analytics Architecture, KQL, and Observability 📊🔍

**Azure Monitor** and **Log Analytics** form the unified observability and telemetry backbone of Microsoft Azure. Ingesting metrics, distributed traces, and petabytes of structured log events from Azure resources, on-premises servers, and hybrid clouds, Log Analytics powers real-time troubleshooting, security analytics (Microsoft Sentinel), and infrastructure monitoring. Telemetry is queried using the **Kusto Query Language (KQL)**, an exceptionally fast, pipe-delimited data exploration language optimized for analytical aggregation over massive datasets.

---

## 1. Architecture & Centralized Workspace Topology

Azure Monitor collects telemetry from across the IT estate and routes it into either time-series metric databases or centralized **Log Analytics Workspaces (LAW)**.

```
                           SOURCES OF ENTERPRISE TELEMETRY
    ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────────┐
    │  Azure PaaS Services │ │  AKS / Kubernetes    │ │ Virtual Machines     │
    │  (App Service, SQL)  │ │  (Container Insights)│ │ (Azure Monitor Agent)│
    └──────────┬───────────┘ └──────────┬───────────┘ └──────────┬───────────┘
               │ Diagnostic Settings    │ OTLP / Syslog          │ AMA / DCR
               ▼                        ▼                        ▼
    ┌────────────────────────────────────────────────────────────────────────┐
    │                   DATA COLLECTION RULES (DCR) PIPELINE                 │
    │  - Filter, transform, and sample incoming telemetry at ingestion       │
    │  - KQL-based ingestion-time transformations (KQL `project` / `drop`)   │
    └───────────────────────────────────┬────────────────────────────────────┘
                                        │ High-Speed Ingestion Engine
                                        ▼
    ┌────────────────────────────────────────────────────────────────────────┐
    │                    LOG ANALYTICS WORKSPACE (LAW)                       │
    │                                                                        │
    │  ┌──────────────────────────────────────────────────────────────────┐  │
    │  │                   ANALYTICS LOG DATA TABLE TIER                  │  │
    │  │   - Full interactive KQL queries, alerts, and dashboards         │  │
    │  │   - Retention: 30 to 730 days (Interactive)                      │  │
    │  └──────────────────────────────────┬───────────────────────────────┘  │
    │                                     │ Archive Policy                   │
    │  ┌──────────────────────────────────▼───────────────────────────────┐  │
    │  │                   BASIC / ARCHIVE LOG DATA TIER                  │  │
    │  │   - Low-cost compliance retention up to 12 years (4,383 days)    │  │
    │  │   - Asynchronous search jobs and table restore capabilities      │  │
    │  └──────────────────────────────────────────────────────────────────┘  │
    └───────────────────────────────────┬────────────────────────────────────┘
                                        │
             ┌──────────────────────────┼──────────────────────────┐
             ▼                          ▼                          ▼
    ┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
    │ KQL LOG SEARCH  │        │ METRIC ALERTS   │        │ MICROSOFT       │
    │ Workbooks &     │        │ Action Groups & │        │ SENTINEL        │
    │ Grafana Plugin  │        │ Incident Alerts │        │ Cloud SIEM/SOAR │
    └─────────────────┘        └─────────────────┘        └─────────────────┘
```

### Core Architecture Constructs

1. **Log Analytics Workspace (LAW):** The administrative, security, and geographic boundary for log storage. All tables (e.g., `AzureActivity`, `ContainerLogV2`, `AppRequests`, `SecurityEvent`) exist inside a workspace.
2. **Data Collection Rules (DCR):** Declarative definitions that specify what data to collect, how to transform it during stream ingestion, and which destinations to deliver it to. DCRs can filter out junk logs *before* they are written to disk, directly reducing ingestion billing.
3. **Table Data Tiers:**
   - **Analytics Tier (Default):** Full KQL analytical query capabilities, sub-second execution, alerting, and workbooks.
   - **Basic Tier:** Cut-rate ingestion price (approx. 80% cheaper) for high-volume debugging logs; supports simple KQL queries.
   - **Archive Tier:** Low-cost cold storage for regulatory compliance up to 12 years.

---

## 2. Kusto Query Language (KQL) Mastery

KQL is a read-only, declarative data analysis language structured with pipes (`|`).

### Essential Production KQL Queries

#### 1. Analyze Container Crash Loops in AKS (ContainerLogV2)
```kql
ContainerLogV2
| where TimeGenerated > ago(1h)
| where LogLevel in ("Error", "Fatal")
| summarize ErrorCount = count() by PodNamespace, PodName, ContainerName
| order by ErrorCount desc
| render barchart
```

#### 2. Detect High-Latency HTTP Requests in Azure App Service
```kql
AppRequests
| where TimeGenerated > ago(24h)
| where Success == false or DurationMs > 2000
| summarize 
    FailedCount = countif(Success == false),
    SlowCount = countif(DurationMs > 2000),
    P95Latency = percentile(DurationMs, 95)
  by OperationName
| order by FailedCount desc
```

#### 3. Correlate Firewall Denied Connections Across Spoke VNets
```kql
AzureDiagnostics
| where Category == "AzureFirewallNetworkRule"
| where msg_s has "Deny"
| parse msg_s with Protocol " request from " SourceIP ":" SourcePort " to " DestIP ":" DestPort ". Action: " Action
| summarize DeniedPackets = count() by SourceIP, DestIP, DestPort, Protocol
| top 20 by DeniedPackets desc
```

---

## 3. Production Deployment & CLI Operations (`az`)

### 1. Deploy Enterprise Log Analytics Workspace with 365-Day Retention

```bash
az group create --name rg-observability-prod --location eastus

# Deploy Log Analytics Workspace
az monitor log-analytics workspace create \
    --resource-group rg-observability-prod \
    --workspace-name law-enterprise-core-prod \
    --location eastus \
    --sku PerGB2018 \
    --retention-time 365 \
    --quota 50
```
*(Note: `--quota 50` sets a daily ingestion cap of 50 GB to prevent accidental runaway billing spikes).*

### 2. Configure Diagnostic Settings on Key Infrastructure

Route all audit logs, administrative actions, and metrics from an Azure Key Vault into the Log Analytics Workspace:

```bash
# Obtain Key Vault and Workspace Resource IDs
KV_ID=$(az keyvault show --name kv-secops-prod --query id -o tsv)
LAW_ID=$(az monitor log-analytics workspace show \
    --resource-group rg-observability-prod \
    --workspace-name law-enterprise-core-prod \
    --query id -o tsv)

# Create Diagnostic Setting
az monitor diagnostic-settings create \
    --name diag-kv-to-law \
    --resource "${KV_ID}" \
    --workspace "${LAW_ID}" \
    --logs '[{"categoryGroup": "allLogs", "enabled": true}]' \
    --metrics '[{"category": "AllMetrics", "enabled": true}]'
```

### 3. Deploy an Action Group (PagerDuty & SRE Webhook)

```bash
az monitor action-group create \
    --resource-group rg-observability-prod \
    --name ag-sre-critical \
    --short-name "SRE-P1" \
    --webhook-receivers name=PagerDutyReceiver service-uri="https://events.pagerduty.com/v2/enqueue" use-common-alert-schema=true
```

### 4. Create a Production Scheduled Query Alert Rule via KQL

Trigger an incident alert when HTTP 5xx error rates exceed 5% over a 5-minute window:

```bash
AG_ID=$(az monitor action-group show \
    --resource-group rg-observability-prod \
    --name ag-sre-critical \
    --query id -o tsv)

az monitor scheduled-query create \
    --resource-group rg-observability-prod \
    --name alert-high-http-5xx-rate \
    --scopes "${LAW_ID}" \
    --severity 1 \
    --evaluation-frequency 5m \
    --window-size 5m \
    --condition "count > 10" \
    --condition-query "AppRequests | where Success == false and ResultCode startswith '5' | summarize count() by bin(TimeGenerated, 5m)" \
    --action-groups "${AG_ID}" \
    --description "Triggers P1 alert when App Service generates more than 10 HTTP 5xx errors in 5 minutes"
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Default Quota | Engineering Guidance |
| :--- | :--- | :--- |
| **Max Ingestion Rate** | 6 GB/min (~100 MB/s) | Soft limit; raise quota for enterprise Sentinel hubs |
| **Daily Ingestion Cap** | Unlimited (Default) | Configure cap (`dailyQuotaGb`) in non-prod workspaces |
| **Data Retention (Analytics)**| 30 to 730 days | 30 to 90 days is standard; first 30 days included |
| **Data Retention (Archive)**  | Up to 4,383 days (12 yrs) | Used for financial, HIPAA, and SOC2 compliance |
| **Max KQL Query Timeout** | 10 minutes | Structure queries with `TimeGenerated` filters |
| **Max Query Result Records** | 30,000 rows | Use `summarize`, `top`, or `take` to aggregate |

---

## 5. Official References & Documentation

- [Azure Monitor Overview & Architecture](https://learn.microsoft.com/en-us/azure/azure-monitor/overview)
- [Log Analytics Workspace Design & Best Practices](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/workspace-design)
- [Kusto Query Language (KQL) Reference](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)
- [Data Collection Rules (DCR) Architecture](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Azure Monitor Pricing Matrix](https://azure.microsoft.com/en-us/pricing/details/monitor/)

---

## 6. Realistic Pricing Scenarios

Azure Monitor Log Analytics pricing is based on:
1. **Pay-As-You-Go Ingestion:** ~$2.30 per GB ingested (Analytics tier).
2. **Commitment Tiers:**
   - 100 GB/day: $1.96/GB ($196/day).
   - 200 GB/day: $1.73/GB ($346/day).
   - 500 GB/day: $1.50/GB ($750/day).
3. **Data Retention:**
   - First 30 days: **Free** (included in ingestion price).
   - Interactive retention (day 31 to 730): $0.10 per GB-month.
   - Archive retention (day 731 to 4,383): $0.02 per GB-month.

### Scenario A: Medium Microservice Estate (Pay-As-You-Go vs 100 GB Commitment)

- **Ingestion Volume:**
  - 10 AKS clusters + 50 PaaS services generating **80 GB of logs per day** ($2{,}400 \text{ GB / month}$).
  - Retention requirement: 90 days (30 days free, 60 days billed).
- **Pay-As-You-Go Calculation:**
  - Ingestion: $2{,}400 \text{ GB} \times \$2.30/\text{GB} = \mathbf{\$5{,}520.00}$
  - Retention (60 days accum. = 4,800 GB-months): $4{,}800 \times \$0.10 = \mathbf{\$480.00}$
  - Total: **$6,000.00 / month**
- **Evaluating Commitment Tier:**
  - If daily volume grows to 100 GB/day:
    - 100 GB Commitment: $196.00/day × 30 days = **$5,880.00 / month** (Includes 3,000 GB, equivalent to $1.96/GB).

### Scenario B: Massive Enterprise SIEM / Security Hub (500 GB/day Commitment Tier)

- **Ingestion Volume:**
  - 500 GB/day ($15{,}000 \text{ GB} = 15 \text{ TB / month}$).
  - 500 GB/day Commitment Tier applied ($1.50/GB).
  - Retention: 365 days (11 months billable after 30-day grace = $165{,}000 \text{ GB-months}$ steady state).
- **Monthly Cost Calculation:**
  - Ingestion (500 GB/day commitment): $750.00/\text{day} \times 30 \text{ days} = \mathbf{\$22{,}500.00}$
  - Interactive Retention: $165{,}000 \text{ GB} \times \$0.10/\text{GB} = \mathbf{\$16{,}500.00}$
- **Total Monthly Cost:** **$39,000.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **Workspace Sprawl Destroys Visibility and Inflates Costs:** Creating separate Log Analytics Workspaces for every department, team, or application is an anti-pattern. You cannot run cross-workspace KQL queries efficiently, alert rules duplicate across workspaces, and you miss out on high-volume **Commitment Tier discounts** (100 GB+). Consolidate workspaces into a single centralized workspace (or one per region for data sovereignty) and use **Azure Table-Level RBAC** to restrict who can view specific tables.
2. **The Missing `TimeGenerated` Filter Performance Penalty:** When running KQL queries via scheduled alert rules or custom dashboards, **always place `| where TimeGenerated > ago(...)` at the very first line of the query**. If you omit the time filter or place it after an expensive `parse` or `join`, KQL initiates a full-table historical scan across months of data, resulting in query timeouts and throttling.
3. **Daily Cap Kills Critical Security Logs During Attacks:** Setting a daily ingestion cap (`dailyQuotaGb`) stops all log ingestion for the rest of the day once the limit is reached. If an attacker launches a distributed brute-force attack or data exfiltration campaign that floods logs, the workspace reaches its cap and **stops recording security logs precisely when you need them most**. Never set a daily cap on production or security-critical workspaces; use ingestion alert rules instead.
4. **Data Collection Rules (DCR) Ingestion Transformations Save 50% on Bills:** Many services log verbose JSON payloads containing useless headers, cookies, or debug traces. Using DCR ingestion-time transformations, you can apply KQL expressions (e.g., `source | project-away UserAgent, RawHeaders | where LogLevel != "DEBUG"`) directly at the Azure ingestion pipeline. The discarded data never lands on disk and is **not billed for ingestion**.
5. **Basic Logs Tier for High-Volume Firewalls and Proxy Logs:** Azure Firewall, Application Gateway, and NGINX ingress controllers generate millions of routine HTTP flow logs that are rarely queried interactively. Switching these specific tables from the `Analytics` tier ($2.30/GB) to the `Basic` tier ($0.50/GB) cuts ingestion costs for those tables by **nearly 80%**.
6. **Time Skew in Diagnostic Logs:** Diagnostic settings from certain Azure services (like Cosmos DB or Azure SQL) batch events and emit them with an ingestion delay of 2 to 5 minutes. If an alert rule checks `where TimeGenerated > ago(5m)` every 5 minutes, events delayed in transit might miss the query evaluation window. Set the alert rule query window to 10 or 15 minutes (`ago(15m)`) with an evaluation frequency of 5 minutes to guarantee 100% event capture.

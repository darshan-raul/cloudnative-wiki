---
title: Microsoft Sentinel Architecture, Threat Intelligence, and SOAR
description: Exhaustive engineering guide to Microsoft Sentinel — Cloud-native SIEM/SOAR platform, data connectors, KQL-based analytics rules, incident investigation graphs, and automated response playbooks via Azure Logic Apps.
tags:
  - azure
  - security
  - sentinel
  - siem
  - soar
---

# Microsoft Sentinel Architecture, Threat Intelligence, and SOAR 🛡️🕵️‍♂️

**Microsoft Sentinel** is a scalable, cloud-native **Security Information and Event Management (SIEM)** and **Security Orchestration, Automated Response (SOAR)** solution. Built directly on top of Azure Monitor Log Analytics, Sentinel delivers intelligent security analytics and threat intelligence across the enterprise. It provides a single solution for alert detection, threat visibility, proactive threat hunting, and automated incident response powered by artificial intelligence and Microsoft's global threat intelligence signals.

---

## 1. Architecture & Multi-Cloud Ingestion Engine

Microsoft Sentinel operates as an intelligence layer on top of an Azure Log Analytics Workspace. Data is ingested from Azure, Microsoft 365, on-premises datacenters, AWS, and Google Cloud.

```
                  ENTERPRISE DATA SOURCES & TELEMETRY
    ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────────┐
    │ Microsoft Entra ID   │ │ Microsoft Defender   │ │ AWS CloudTrail /     │
    │ Sign-ins & Audits    │ │ XDR / Endpoint       │ │ GCP Audit Logs       │
    └──────────┬───────────┘ └──────────┬───────────┘ └──────────┬───────────┘
               │ Native                 │ API Connector          │ S3 / PubSub Ingestion
               ▼                        ▼                        ▼
    ┌────────────────────────────────────────────────────────────────────────┐
    │                      MICROSOFT SENTINEL DATA CONNECTORS                │
    │  - 100+ native out-of-the-box connectors & CEF/Syslog Forwarders       │
    │  - Threat Intelligence (STIX / TAXII / Microsoft Graph TI)             │
    └───────────────────────────────────┬────────────────────────────────────┘
                                        │ High-Throughput Stream
                                        ▼
    ┌────────────────────────────────────────────────────────────────────────┐
    │                 LOG ANALYTICS WORKSPACE (BACKING STORE)                │
    │  Tables: SecurityAlert, SigninLogs, AzureActivity, CommonSecurityLog   │
    └───────────────────────────────────┬────────────────────────────────────┘
                                        │
             ┌──────────────────────────┼──────────────────────────┐
             ▼                          ▼                          ▼
    ┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
    │ ANALYTICS ENGINE│        │ INCIDENTS &     │        │ SOAR AUTOMATION │
    │ KQL Detections, │        │ INVESTIGATION   │        │ Logic App       │
    │ Fusion ML, UEBA │        │ Entity Graph &  │        │ Playbooks, Auto-│
    │ NRT Rules       │        │ Timeline Visual │        │ Remediation     │
    └─────────────────┘        └─────────────────┘        └─────────────────┘
```

### Core Architecture Constructs

1. **Workspace Association:** Sentinel is enabled on top of an existing Log Analytics workspace. All security events land in Log Analytics tables, allowing security teams to leverage the full power of KQL.
2. **Data Connectors:** Specialized ingestion pipelines. Includes free native connectors (Azure Activity, Office 365 audit logs) and enterprise connectors (Palo Alto, Cisco, AWS CloudTrail, Linux Syslog via Azure Monitor Agent).
3. **Analytics Rules:**
   - **Scheduled Rules:** Run KQL queries on a periodic schedule (e.g., every 5 minutes querying the last 15 minutes) to detect anomalous patterns.
   - **Near-Real-Time (NRT) Rules:** Stream-evaluated rules that execute every minute on single-minute data for instantaneous high-severity detection.
   - **Fusion Machine Learning:** Multi-stage attack detection using graph algorithms to correlate low-fidelity alerts from multiple sources into a single actionable high-severity incident.
4. **SOAR Playbooks:** Automated workflows built on **Azure Logic Apps**. When an incident is generated, Sentinel can automatically execute playbooks to block a firewall IP, isolate a compromised AKS pod, revoke Entra ID user tokens, or notify the SOC in Slack/Teams.

---

## 2. Advanced Threat Detection with KQL

### 1. Detect Suspicious Mass File Downloads / Exfiltration
```kql
AzureActivity
| where TimeGenerated > ago(1h)
| where OperationNameValue has "Microsoft.Storage/storageAccounts/listKeys/action"
| summarize KeyListCount = count() by Caller, CallerIpAddress, bin(TimeGenerated, 10m)
| where KeyListCount > 10
| project TimeGenerated, Caller, CallerIpAddress, KeyListCount
```

### 2. Detect Password Spray Attacks across Microsoft Entra ID
```kql
SigninLogs
| where TimeGenerated > ago(1h)
| where ResultType in (50126, 50053) // Invalid password or account locked
| summarize FailedAttempts = count(), DistinctUsers = dcount(UserPrincipalName) by IPAddress
| where DistinctUsers > 15 and FailedAttempts > 30
| extend IPCustomEntity = IPAddress
```

### 3. Correlate AWS CloudTrail root activity with Azure Alerts
```kql
AWSCloudTrail
| where TimeGenerated > ago(2h)
| where EventName in ("ConsoleLogin", "CreateUser", "AttachUserPolicy")
| where UserIdentityType == "Root"
| project TimeGenerated, EventName, SourceIpAddress, UserAgent
```

---

## 3. Production Deployment & CLI Operations (`az`)

### 1. Enable Microsoft Sentinel on a Log Analytics Workspace

```bash
az group create --name rg-soc-prod --location eastus

# Deploy backing Log Analytics Workspace
az monitor log-analytics workspace create \
    --resource-group rg-soc-prod \
    --workspace-name law-sentinel-hub-prod \
    --location eastus \
    --sku PerGB2018 \
    --retention-time 180

# Onboard Sentinel to the workspace
az sentinel onboarding-state create \
    --resource-group rg-soc-prod \
    --workspace-name law-sentinel-hub-prod \
    --name "default"
```

### 2. Connect Microsoft Entra ID (Azure AD) Data Connector

Stream Entra ID Sign-in Logs and Audit Logs into Sentinel:

```bash
az sentinel data-connector create \
    --resource-group rg-soc-prod \
    --workspace-name law-sentinel-hub-prod \
    --data-connector-id "aad-connector" \
    --aad-data-connector \
        data-types='{"alerts":{"state":"enabled"},"auditLogs":{"state":"enabled"},"signinLogs":{"state":"enabled"}}' \
        tenant-id="$(az account show --query tenantId -o tsv)"
```

### 3. Deploy Scheduled Analytics Rule via CLI

Create a detection rule `brute-force-detection.json`:

```json
{
  "displayName": "Brute Force Attack Detected against Entra ID",
  "severity": "High",
  "enabled": true,
  "query": "SigninLogs | where TimeGenerated > ago(15m) | where ResultType == 50126 | summarize FailedLogins = count() by IPAddress, UserPrincipalName | where FailedLogins > 10",
  "queryFrequency": "PT15M",
  "queryPeriod": "PT15M",
  "triggerOperator": "GreaterThan",
  "triggerThreshold": 0,
  "tactics": ["CredentialAccess"],
  "techniques": ["T1110"],
  "entityMappings": [
    {
      "entityType": "IP",
      "fieldMappings": [{"identifier": "Address", "columnName": "IPAddress"}]
    },
    {
      "entityType": "Account",
      "fieldMappings": [{"identifier": "Name", "columnName": "UserPrincipalName"}]
    }
  ]
}
```

Deploy rule to Sentinel:

```bash
az sentinel alert-rule create \
    --resource-group rg-soc-prod \
    --workspace-name law-sentinel-hub-prod \
    --rule-id "alert-entra-bruteforce" \
    --scheduled-alert-rule @brute-force-detection.json
```

### 4. Deploy Automated Response SOAR Playbook (Logic App)

```bash
# Create automated response trigger: Revoke Entra ID user session on High severity incident
az logic workflow create \
    --resource-group rg-soc-prod \
    --name "soar-revoke-user-token" \
    --location eastus \
    --definition @soar-playbook-definition.json
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Default Quota | Engineering Guidance |
| :--- | :--- | :--- |
| **Max Ingestion Rate** | Scaled by Log Analytics | Supports hundreds of terabytes per day |
| **Active Analytics Rules** | 512 scheduled rules | Consolidate detection logic using KQL functions |
| **NRT Rules per Workspace**| 50 NRT rules | Reserve NRT rules for immediate Tier-1 threats |
| **Automation Rules** | 100 rules per workspace | Direct playbooks based on incident tags |
| **Incident Retention** | Matches workspace retention | Incidents persist as long as underlying logs exist |
| **Free Data Sources** | Entra ID Activity, Office 365, Defender alerts | Free ingestion into Sentinel |

---

## 5. Official References & Documentation

- [Microsoft Sentinel Documentation](https://learn.microsoft.com/en-us/azure/sentinel/)
- [Microsoft Sentinel Data Connectors Catalog](https://learn.microsoft.com/en-us/azure/sentinel/connect-data-sources)
- [Create Custom Analytics Rules with KQL](https://learn.microsoft.com/en-us/azure/sentinel/detect-threats-custom)
- [SOAR Playbooks & Automation Rules](https://learn.microsoft.com/en-us/azure/sentinel/automate-responses-with-playbooks)
- [Microsoft Sentinel Pricing](https://azure.microsoft.com/en-us/pricing/details/microsoft-sentinel/)

---

## 6. Realistic Pricing Scenarios

Microsoft Sentinel pricing is an **additive layer on top of Log Analytics**:
1. **Pay-As-You-Go:**
   - Log Analytics Ingestion: $2.30 per GB.
   - Microsoft Sentinel Analysis: $4.30 per GB.
   - Combined Pay-As-You-Go Cost: **~$6.60 per GB**.
2. **Sentinel Commitment Tiers (Co-Commitment with Log Analytics):**
   - 100 GB/day: $290/day Sentinel ($2.90/GB) + $196/day Log Analytics = **$4.86/GB combined**.
   - 200 GB/day: $540/day Sentinel ($2.70/GB) + $346/day Log Analytics = **$4.43/GB combined**.
   - 500 GB/day: $1,250/day Sentinel ($2.50/GB) + $750/day Log Analytics = **$4.00/GB combined**.

### Scenario A: Small-to-Mid Sized Cloud Security Estate (30 GB/day)

- **Profile:**
  - Ingests 30 GB/day ($900 \text{ GB / month}$) of Linux audit, firewall, and cloud activity logs.
  - 10 GB/day of Entra ID sign-in and Office 365 audit logs (**Free from Sentinel charges**).
  - Billable Volume: 20 GB/day ($600 \text{ GB / month}$).
- **Monthly Cost Calculation:**
  - Log Analytics Ingestion: 600 GB × $2.30/GB = **$1,380.00**
  - Microsoft Sentinel Analysis: 600 GB × $4.30/GB = **$2,580.00**
- **Total Monthly Cost:** **$3,960.00 / month**

### Scenario B: Enterprise Global SOC (200 GB/day Commitment Tier)

- **Profile:**
  - 200 GB/day billable security telemetry ($6{,}000 \text{ GB} = 6 \text{ TB / month}$).
  - 200 GB/day Commitment Tier enabled across Sentinel and Log Analytics.
  - 180-day retention (first 90 days included with Sentinel; 90 days billed).
- **Monthly Cost Calculation:**
  - Log Analytics Ingestion (200 GB tier): $346.00/day × 30 days = **$10,380.00**
  - Sentinel Analysis (200 GB tier): $540.00/day × 30 days = **$16,200.00**
  - Extended Retention (90 days = 18,000 GB-months): $18{,}000 \times \$0.10/\text{GB} = \mathbf{\$1{,}800.00}$
- **Total Monthly Cost:** **$28,380.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **Free Data Sources Are Only Free from Sentinel Fees:** Microsoft provides free Sentinel ingestion for Office 365 audit logs, Microsoft Entra ID audit logs, and Microsoft Defender alerts. However, non-security logs (like Kubernetes container stdout or verbose web server access logs) ingested into the same workspace will be billed for **both Log Analytics AND Sentinel ($6.60/GB total)**. Never ingest general application debug logs into a Sentinel workspace; keep application observability in a separate Log Analytics workspace.
2. **Entity Mappings Are Mandatory for Incident Correlation:** When creating custom scheduled analytics rules in KQL, you must define **Entity Mappings** (e.g., mapping column `IPAddress` to entity `IP`, and `UserPrincipalName` to entity `Account`). If you omit entity mappings, Sentinel cannot correlate alerts, the investigation graph will be empty, and UEBA (User and Entity Behavior Analytics) anomalies will not link to the incident.
3. **The 90-Day Free Retention Benefit:** Enabling Microsoft Sentinel on a Log Analytics workspace automatically grants **90 days of free retention** for all data ingested into that workspace (compared to only 30 days for standard Log Analytics). If your organization already pays for Sentinel, you get 3 full months of interactive KQL security log retention at zero additional storage cost.
4. **NRT (Near-Real-Time) Rule Limitations:** Near-Real-Time rules evaluate log streams every minute on 1-minute batches. However, NRT rules do not support `join`, `summarize`, or multi-table lookups. They are intended strictly for simple high-fidelity indicators (e.g., a known malicious IP matched against a threat intelligence feed). Attempting to write complex aggregations in an NRT rule will trigger a deployment validation error.
5. **Logic App SOAR Loops Can Empty Budgets in Minutes:** If you attach a SOAR playbook that runs on incident creation, and an analytics rule generates an alert storm (e.g., 5,000 alerts generated by an automated vulnerability scanner), Sentinel triggers 5,000 concurrent Logic App workflow runs. If the playbook sends SMS messages or calls external billable APIs, you will rack up thousands of dollars in Logic App and API charges. Always configure **Alert Grouping** (grouping all alerts from the same IP/account into a single incident over a 5-hour window) and add rate-limiting conditions in playbooks.
6. **Syslog Forwarder VM High-Availability Bottlenecks:** When forwarding on-premises firewall logs (CEF/Syslog) via the Azure Monitor Agent forwarder VM, that single forwarder VM is a critical point of failure. If the VM runs out of memory or its rsyslog daemon crashes, incoming UDP syslog packets are silently dropped without retry. Always deploy forwarder VMs in a load-balanced pair behind an internal Azure Load Balancer.

---
title: Azure SQL Database & Managed Instance
description: Azure SQL architecture — Single Database vs Managed Instance, vCore vs DTU models, Serverless auto-pause, Hyperscale distributed storage, and Auto-Failover Groups.
tags:
  - azure
  - databases
  - sql-server
  - azure-sql
  - relational
---

# Azure SQL Database & Managed Instance 🗄️⚡

Microsoft Azure SQL is a family of managed relational database engines built on the Microsoft SQL Server engine. Azure SQL eliminates manual patching, high availability clustering, and backup management while offering two primary deployment models: **Azure SQL Database** (lightweight, cloud-native DB-as-a-Service) and **Azure SQL Managed Instance** (near-100% feature compatibility with on-premises SQL Server).

---

## Architecture & Mental Model

### Deployment Option Spectrum

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Azure SQL Deployment Flavors                    │
├───────────────────────────────┬────────────────────────────────────────┤
│ Azure SQL Database            │ Azure SQL Managed Instance             │
├───────────────────────────────┼────────────────────────────────────────┤
│ • Scoped to a single database │ • Complete SQL Server instance         │
│ • Serverless auto-pause       │ • Cross-database queries               │
│ • Hyperscale (up to 100 TB)   │ • SQL Server Agent jobs                │
│ • Microservices & cloud apps  │ • Native VNet subnet integration       │
│ • Shared or Elastic Pool tiers│ • Enterprise lift-and-shift migrations │
└───────────────────────────────┴────────────────────────────────────────┘
```

---

## Core Concepts

### 1. Purchasing Models: vCore vs. DTU

| Purchasing Model | Mechanics | Production Recommendation |
| :--- | :--- | :--- |
| **DTU (Database Transaction Unit)** | Legacy blended metric combining CPU, memory, and I/O (Basic, Standard, Premium tiers) | Avoid for new workloads; rigid scaling ratios |
| **vCore (Modern Standard)** | Independently configures vCore count, memory, and storage allocation | **Production Default**: Supports Azure Hybrid Benefit (license reuse) |

### 2. Service Tiers in the vCore Model

* **General Purpose:** Budget-friendly tier. Decouples compute from remote Azure Premium Storage. 99.99% availability.
* **Business Critical:** High-performance OLTP. Uses local NVMe SSDs directly on the compute host and synchronous **Always On Availability Groups** across 3 zones. Sub-millisecond latency.
* **Hyperscale:** Highly scalable distributed architecture:
  * Scales storage up to **100 TB**.
  * Near-instant point-in-time recovery (snapshots in minutes regardless of database size).
  * Rapid auto-scaling of compute and read-only secondary replicas.

### 3. Serverless Compute Tier

Available on Azure SQL Database (General Purpose vCore):
* Automatically scales vCores up and down in real time based on active query load.
* **Auto-Pause Feature:** If no queries arrive for a configured duration (e.g. 1 hour), the database **auto-pauses compute**, reducing compute billing to **$0.00** during idle periods (only paying for storage).

### 4. Auto-Failover Groups

Provides cross-region disaster recovery for mission-critical databases:
* Replicates data asynchronously to a secondary region.
* Exposes a **Read-Write Listener FQDN** (`<group>.database.windows.net`) and a **Read-Only Listener FQDN**.
* During a regional outage, Azure automatically redirects client connections to the secondary region without requiring connection string changes in application code!

---

## Production `az` CLI Commands

### 1. Provisioning an Azure SQL Database with Serverless Auto-Pause

```bash
# 1. Create the logical SQL Server (enforcing Entra ID only auth)
az sql server create \
  --resource-group prod-data-rg \
  --name sql-core-prod-01 \
  --location eastus \
  --enable-ad-only-auth \
  --external-admin-principal-type Group \
  --external-admin-name "DBA-Admins" \
  --external-admin-sid "00000000-0000-0000-0000-000000000000"

# 2. Create the Serverless Database
az sql db create \
  --resource-group prod-data-rg \
  --server sql-core-prod-01 \
  --name db-ecommerce \
  --edition GeneralPurpose \
  --compute-model Serverless \
  --family Gen5 \
  --min-capacity 1 \
  --capacity 4 \
  --auto-pause-delay 60 \
  --zone-redundant false
```

### 2. Creating an Auto-Failover Group for Cross-Region DR

```bash
az sql failover-group create \
  --resource-group prod-data-rg \
  --server sql-core-prod-01 \
  --name fg-ecommerce-dr \
  --partner-server sql-core-dr-02 \
  --failover-policy Automatic \
  --grace-period 60 \
  --add-db db-ecommerce
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max storage (Hyperscale)** | 100 TB per database | Auto-grows in 10 GB increments |
| **Max storage (General Purpose)** | 4 TB per database | vCore dependent |
| **Auto-failover grace period** | Minimum 1 hour | Grace period for data loss prevention |
| **Max databases per elastic pool** | 500 databases | Consolidates multitenant workloads |

---

## References

* **Homepage:** https://azure.microsoft.com/en-us/products/azure-sql/database
* **Azure SQL Documentation:** https://learn.microsoft.com/en-us/azure/azure-sql/
* **vCore Model Overview:** https://learn.microsoft.com/en-us/azure/azure-sql/database/service-tiers-vcore
* **Auto-Failover Groups:** https://learn.microsoft.com/en-us/azure/azure-sql/database/auto-failover-group-overview
* **Pricing:** https://azure.microsoft.com/en-us/pricing/details/azure-sql-database/

---

## Pricing Examples

### Scenario 1: Intermittent Internal Business Application (Serverless)
* Internal HR application accessed only during business hours (40 hours / week = 160 hours / month).
* Automatically paused during nights and weekends (570 hours idle / month).
* Active usage: 2 vCores average ($0.25 / vCore-hour = $0.50 / hour × 160 hrs = **$80.00 / month**).
* Idle compute: 570 hours paused = **$0.00**.
* Storage: 100 GB SSD ($0.115 / GB = $11.50).
* **Total Monthly Bill:** **~$91.50 / month** (A provisioned 24/7 2-vCore database would cost ~$365/month).

### Scenario 2: Mission-Critical 24/7 E-Commerce Platform (Business Critical)
* 8-vCore Business Critical tier with 500 GB storage and Zone Redundancy.
* Includes 1 free built-in read replica.
* Compute rate (with Azure Hybrid Benefit for SQL Server): ~$680.00 / month.
* Local NVMe storage (500 GB): $150.00 / month.
* **Total Monthly Database Cost:** **~$830.00 / month** (Sub-millisecond latency and automatic multi-zone failover).

---

## Nuggets & Gotchas

1. **Serverless Auto-Pause Cold Start Latency:** When a serverless database auto-pauses, the first incoming query must wake up the database engine and re-attach storage. This introduces a **15 to 45 second delay** on the initial HTTP connection! If client applications have a 10-second connection timeout, the initial request will fail with a timeout error before the database finishes resuming.
2. **Managed Instance Subnet Requirements:** Azure SQL Managed Instance **cannot be placed into an existing populated subnet**. It requires a dedicated, delegated subnet (`Microsoft.Sql/managedInstances`) with an NSG allowing specific Azure management ports (9000, 9003, 1438). Modifying this NSG incorrectly will brick the instance control plane.
3. **Firewall "Allow Azure Services" Security Hole:** In the Azure Portal, checking the box *"Allow Azure services and resources to access this server"* does **not** restrict access to your subscriptions. It permits **any VM or tenant in the entire worldwide Azure ecosystem** to reach your database port 1433! Always uncheck this box and connect exclusively via **Private Endpoints**.
4. **TempDB Bottlenecks in General Purpose:** In the General Purpose tier, `tempdb` runs on remote Azure Premium Storage, which can bottleneck heavy sorting, CTEs, and table variables. The **Business Critical** and **Hyperscale** tiers run `tempdb` directly on local NVMe SSDs, yielding 5x–10x higher write throughput for complex queries.
5. **Cross-Database Queries Not Supported on Single DB:** If your legacy application executes queries like `SELECT * FROM DatabaseA.dbo.Table JOIN DatabaseB.dbo.Table`, Azure SQL Single Database **does not support this syntax**. You must either rewrite queries via Elastic Queries or deploy **Azure SQL Managed Instance**.

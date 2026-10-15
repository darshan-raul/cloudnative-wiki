---
title: Azure SQL Database & Managed Instance
description: Exhaustive engineering guide to Azure SQL — Logical SQL Server control boundaries, Single DB vs Managed Instance, Elastic Pools, vCore vs DTU models, Serverless auto-pause, Hyperscale, and Auto-Failover Groups.
tags:
  - azure
  - databases
  - sql-server
  - azure-sql
  - relational
  - enterprise
date: 2026-10-16
---

# Azure SQL Database & Managed Instance 🗄️⚡

**Microsoft Azure SQL** is an enterprise portfolio of managed relational database services built upon the Microsoft SQL Server database engine. Azure SQL eliminates administrative operational burdens—including automated OS patching, multi-zone high availability clustering, point-in-time recovery backups, and hardware provisioning—while providing two primary deployment models: **Azure SQL Database** (cloud-native DB-as-a-Service managed via Logical SQL Servers) and **Azure SQL Managed Instance** (near-100% compatibility with on-premises SQL Server instances inside a dedicated VNet).

---

## 1. Single-Service Fundamentals & Mental Models

### The Logical SQL Server vs. Managed Instance Architecture

Understanding Azure SQL requires recognizing the boundary difference between a cloud-native **Logical Server** and a VNet-injected **Managed Instance**:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│               AZURE SQL DATABASE: LOGICAL SERVER CONTROL PLANE                         │
│               Endpoint: https://sql-core-prod-01.database.windows.net:1433             │
│                                                                                        │
│  - Control Plane Management Scope (No underlying VM or OS access)                      │
│  - IP Firewall, VNet Rules & Private Link (Private Endpoint) Boundary                  │
│  - Microsoft Entra ID Authentication & Security Policies (TDE, Auditing)               │
│                                                                                        │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ SINGLE DATABASE: db-ecommerce (General Purpose Serverless, 1-4 vCores)         │   │
│   │ - Dedicated independent compute & storage; auto-pauses when idle               │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                        │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ ELASTIC POOL: pool-saas-tenants (8 vCores Shared Pool)                         │   │
│   │   ├── Tenant-DB-01 (Bursts up to 4 vCores)                                     │   │
│   │   ├── Tenant-DB-02 (Bursts up to 4 vCores)                                     │   │
│   │   └── Tenant-DB-50 (Shared compute absorption; dynamic cost smoothing)         │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────┘

                                         VS.

┌────────────────────────────────────────────────────────────────────────────────────────┐
│             AZURE SQL MANAGED INSTANCE (VNet Injected Virtual Cluster)                 │
│             Subnet: snet-sqlmi (Delegated to Microsoft.Sql/managedInstances)           │
│                                                                                        │
│  - Near-100% on-premises SQL Server engine feature parity                              │
│  - Native cross-database queries: SELECT * FROM DB_A.dbo.T JOIN DB_B.dbo.T            │
│  - SQL Server Agent (Scheduled background jobs, maintenance tasks)                     │
│  - Service Broker, Database Mail, Linked Servers, and CLR modules                      │
│  - Private RFC 1918 IP address directly inside your VNet (No public IP needed)         │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### Architectural Comparison: Single Database vs. Elastic Pool vs. Managed Instance

| Capability / Dimension     | Azure SQL Single Database                | Azure SQL Elastic Pool               | Azure SQL Managed Instance                     |
| :------------------------- | :--------------------------------------- | :----------------------------------- | :--------------------------------------------- |
| **Architectural Scope**    | Scoped to a single isolated database     | Pool of databases sharing vCores/RAM | Entire SQL Server instance with system DBs     |
| **Cross-Database Queries** | Not supported (requires Elastic Query)   | Not supported                        | **Fully supported natively** (`DB1.dbo.T1`)    |
| **SQL Server Agent Jobs**  | Not available (use Azure Logic Apps/ADF) | Not available                        | **Built-in native SQL Server Agent**           |
| **VNet Integration**       | Via Private Endpoints (Private Link)     | Via Private Endpoints (Private Link) | **Dedicated delegated VNet Subnet**            |
| **Serverless Auto-Pause**  | Supported (General Purpose tier)         | Not supported                        | Not supported                                  |
| **Best Production Fit**    | Modern microservices, single cloud apps  | Multi-tenant SaaS with 20+ tenants   | Enterprise lift-and-shift datacenter migration |

---

## 2. Purchasing Models: vCore vs. DTU

| Purchasing Model                    | Architectural Mechanics                                                                                                     | Production Recommendation                                                                                            |
| :---------------------------------- | :-------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------- |
| **DTU (Database Transaction Unit)** | Legacy blended metric combining CPU, memory, and disk read/write rates into an artificial ratio (Basic, Standard, Premium). | **Avoid for new architectures**: Storage and compute scale in rigid locked increments.                               |
| **vCore (Modern Standard)**         | Independently configures virtual core count, memory allocation, and storage capacity.                                       | **Production Default**: Supports Azure Hybrid Benefit (license reuse for up to 55% discount) and Serverless compute. |

---

## 3. Service Tiers in the vCore Model

- **General Purpose:** Budget-friendly tier for mainstream business apps. Decouples compute from remote Azure Premium Storage. 99.99% availability.
- **Business Critical:** High-performance OLTP. Binds compute directly to **local NVMe SSDs** with synchronous **Always On Availability Groups** across 3 zones. Yields sub-millisecond I/O latency and includes 1 free read-only replica.
- **Hyperscale:** Highly scalable distributed tiered architecture:
  - Storage auto-grows dynamically up to **100 TB** in 10 GB increments.
  - Near-instant point-in-time snapshots (< 5 minutes) regardless of database volume size.
  - Supports rapid vertical scaling of compute and up to 30 read-only secondary replicas.

### Serverless Compute Tier (General Purpose)

Available on Azure SQL Single Database:

- Automatically scales vCores up and down in real-time based on active query load.
- **Auto-Pause Feature:** If zero connections are active for a configured threshold (e.g., 60 minutes), compute pauses completely, reducing the hourly compute bill to **$0.00** (paying only for allocated disk storage).

---

## 4. Disaster Recovery & Auto-Failover Groups

**Auto-Failover Groups** provide cross-region disaster recovery for mission-critical SQL architectures:

```
┌─────────────────────────────────┐                 ┌─────────────────────────────────┐
│     PRIMARY REGION: EAST US     │                 │   SECONDARY REGION: WEST US     │
│                                 │                 │                                 │
│  Logical Server: sql-core-prod  │                 │  Logical Server: sql-core-dr    │
│  ├── Database: db-orders        │─── Async ──────►│  ├── Database: db-orders (RO)   │
│  └── Failover Group Primary     │    Replication  │  └── Failover Group Secondary   │
└────────────────┬────────────────┘                 └────────────────┬────────────────┘
                 │                                                   │
                 │                                                   │
                 ▼                                                   ▼
       Read-Write Listener FQDN                            Read-Only Listener FQDN
  (sql-fg.database.windows.net)                       (sql-fg.secondary.database.windows.net)
```

- **Zero Client Code Changes:** The Read-Write Listener FQDN automatically points to the current active primary region. During a regional failover, Azure updates internal DNS routing within seconds, preserving client connection strings.

---

## 5. Production `az` CLI Workflows

### 1. Creating a Logical SQL Server Enforcing Entra ID Authentication

```bash
# 1. Create Resource Group
az group create --name rg-database-prod --location eastus

# 2. Provision Logical SQL Server with Entra ID Only Authentication
az sql server create \
  --resource-group rg-database-prod \
  --name sql-core-prod-eastus \
  --location eastus \
  --enable-ad-only-auth \
  --external-admin-principal-type Group \
  --external-admin-name "SecOps-DBA-Admins" \
  --external-admin-sid "00000000-0000-0000-0000-000000000000"

# 3. Disable Public Network Access (Enforce Private Link)
az sql server update \
  --resource-group rg-database-prod \
  --name sql-core-prod-eastus \
  --public-network-access Disabled
```

### 2. Deploying an Azure SQL Database with Serverless Auto-Pause

```bash
az sql db create \
  --resource-group rg-database-prod \
  --server sql-core-prod-eastus \
  --name db-catalog-prod \
  --edition GeneralPurpose \
  --compute-model Serverless \
  --family Gen5 \
  --min-capacity 1 \
  --capacity 4 \
  --auto-pause-delay 60 \
  --zone-redundant false
```

### 3. Establishing an Auto-Failover Group for Cross-Region DR

```bash
az sql failover-group create \
  --resource-group rg-database-prod \
  --server sql-core-prod-eastus \
  --name fg-catalog-dr \
  --partner-server sql-core-dr-westus \
  --failover-policy Automatic \
  --grace-period 60 \
  --add-db db-catalog-prod
```

---

## 6. Quotas & Limits

| Parameter                          | Limit               | Architectural Guidance                              |
| :--------------------------------- | :------------------ | :-------------------------------------------------- |
| **Max Storage (Hyperscale)**       | 100 TB per database | Auto-grows dynamically; snapshots in minutes        |
| **Max Storage (General Purpose)**  | 4 TB per database   | Scales with vCore count                             |
| **Max Databases per Elastic Pool** | 500 databases       | Consolidates multitenant workloads                  |
| **Auto-Failover Grace Period**     | Minimum 1 hour      | Grace threshold before automatic data loss failover |
| **Max vCores per Database**        | Up to 128 vCores    | Available on Business Critical & Hyperscale         |

---

## 7. Pricing Examples

### Scenario 1: Intermittent Internal Business Application (Serverless)

- **Workload Pattern:** HR portal active only during business hours (40 hours/week = 160 hours/month; idle 570 hours/month).
- **Active Usage:** 2 vCores average ($0.25 / vCore-hour = $0.50 / hr × 160 hrs = **$80.00 / month**).
- **Idle Compute:** 570 hours auto-paused = **$0.00**.
- **Storage:** 100 GB SSD ($0.115 / GB = $11.50).
- **Total Monthly Cost:** **~$91.50 / month** (Saving ~$270/month compared to a provisioned 24/7 2-vCore database).

### Scenario 2: Mission-Critical 24/7 E-Commerce Platform (Business Critical)

- **Configuration:** 8-vCore Business Critical tier with 500 GB local NVMe storage and Zone Redundancy across 3 availability zones. Includes 1 free built-in read replica.
- **Compute Cost (with Azure Hybrid Benefit):** ~$680.00 / month.
- **Local NVMe Storage (500 GB):** $150.00 / month.
- **Total Monthly Cost:** **~$830.00 / month** (Delivers sub-millisecond latency and automated multi-zone failover).

---

## 8. Battle-Tested Nuggets & Gotchas

1. **Serverless Auto-Pause Cold Start Latency:** When a serverless database auto-pauses, the first incoming query must wake up the database engine and re-attach storage. This introduces a **15 to 45 second connection latency delay**. If application connection strings enforce a default 15-second timeout, the initial HTTP request will fail with a connection timeout error. Ensure client retry policies allow sufficient startup headroom.
2. **Managed Instance Subnet Requirements:** Azure SQL Managed Instance **cannot be placed into an existing populated subnet**. It requires an empty, dedicated subnet delegated strictly to `Microsoft.Sql/managedInstances` with an NSG permitting mandatory management ports (9000, 9003, 1438). Modifying this NSG manually will break the instance control plane.
3. **Firewall "Allow Azure Services" Security Hole:** In the Azure Portal, checking _"Allow Azure services and resources to access this server"_ does **not** restrict access to your subscriptions. It permits **any VM or tenant in the entire worldwide Azure public cloud** to reach your database port 1433! Always disable this option and connect exclusively via **Private Endpoints**.
4. **TempDB Bottlenecks in General Purpose:** In the General Purpose tier, `tempdb` runs on remote Azure Premium Storage, which bottlenecks heavy table variables, sorting, and CTEs. The **Business Critical** and **Hyperscale** tiers run `tempdb` directly on local hypervisor NVMe SSDs, yielding 5x–10x higher throughput.
5. **Cross-Database Queries Not Supported on Single DB:** Queries executing `SELECT * FROM DatabaseA.dbo.Table JOIN DatabaseB.dbo.Table` are strictly unsupported on Azure SQL Single Database. Applications requiring cross-database transactions must use **Azure SQL Managed Instance**.

---

## Across the Wiki

- [[Azure/databases/README|Azure Databases Hub]] — Master directory for Azure database engines
- [[Azure/databases/cosmos-db|Azure Cosmos DB]] — Globally distributed multi-model NoSQL
- [[Azure/databases/postgres-flexible/README|Azure Database for PostgreSQL Flexible Server]] — Open-source relational database
- [[AWS/databases/rds/README|Amazon RDS]] — Managed relational databases in AWS
- [[AWS/databases/aurora/README|Amazon Aurora]] — Hyperscale relational database in AWS
- [[GCP/databases/cloud-sql|GCP Cloud SQL]] — Fully managed relational databases in GCP

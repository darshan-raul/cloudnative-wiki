---
title: Azure Analytics & Modern Data Platform Hub
description: Master architectural guide to Microsoft Azure analytics and big data — Microsoft Fabric, Azure Synapse Analytics, Azure Data Factory (ADF), Azure Databricks, and OneLake.
tags:
  - azure
  - analytics
  - big-data
  - fabric
  - synapse
  - databricks
  - data-factory
date: 2026-10-15
---

# Azure Analytics & Modern Data Platform Hub 📊🏛️

Microsoft Azure's analytics ecosystem spans unified SaaS lakehouses, enterprise data orchestration, Apache Spark big data processing, open Delta Parquet storage, and cloud data warehousing.

---

## Architectural Decision Framework

```
                                  Analytics Architecture Need
                                               │
             ┌─────────────────────────────────┼─────────────────────────────────┐
             ▼                                 ▼                                 ▼
    Unified SaaS Lakehouse            Data Integration & ETL              Advanced Spark & AI
             │                                 │                                 │
[[Azure/analytics/fabric-synapse|Microsoft Fabric / Synapse]]    [[Azure/analytics/data-factory|Azure Data Factory (ADF)]]       [[Azure/analytics/databricks|Azure Databricks]]
- OneLake Unified Lakehouse       - Hybrid Data Pipelines         - Unity Catalog Governance
- Delta Parquet & Open Formats    - Self-Hosted IR (On-Premises)  - Photon Vectorized C++ Engine
- Power BI Direct Lake In-Memory  - Mapping Data Flows (Spark)     - Delta Lake ACID Transactions
```

### Analytics Platform Capabilities Matrix

| Capability                         | Azure Solution                                                 | AWS Equivalent         | GCP Equivalent               | Key Cloud Native Differentiator                                                                                        |
| :--------------------------------- | :------------------------------------------------------------- | :--------------------- | :--------------------------- | :--------------------------------------------------------------------------------------------------------------------- |
| **Unified Lakehouse Platform**     | [[Azure/analytics/fabric-synapse\|Microsoft Fabric & OneLake]] | AWS Lake Formation     | BigQuery & Dataplex          | OneLake provides zero-copy shortcuts to AWS S3/GCS; Power BI Direct Lake queries Delta Parquet in RAM without refresh. |
| **Hybrid ETL / ELT Orchestration** | [[Azure/analytics/data-factory\|Azure Data Factory (ADF)]]     | AWS Glue & AppFlow     | Cloud Data Fusion & Dataflow | Self-Hosted IR (SHIR) securely bridges on-premises Oracle/SAP over outbound TLS 443 without inbound firewall holes.    |
| **Enterprise Apache Spark & AI**   | [[Azure/analytics/databricks\|Azure Databricks]]               | Amazon EMR / SageMaker | Dataproc & Vertex AI         | First-party Azure integration, VNet injection, Unity Catalog fine-grained access, and C++ Photon acceleration.         |
| **Serverless SQL Querying**        | [[Azure/analytics/fabric-synapse\|Synapse Serverless SQL]]     | Amazon Athena          | BigQuery Serverless SQL      | Queries raw Parquet, CSV, and Delta files in ADLS Gen2 on-demand at $5 per TB scanned.                                 |

---

## Service Catalog

- [[Azure/analytics/fabric-synapse|Microsoft Fabric & Azure Synapse Analytics Architecture]] — OneLake unified lakehouse, Direct Lake Power BI querying, Delta Parquet native storage, Serverless SQL pools, and Spark runtimes.
- [[Azure/analytics/data-factory|Azure Data Factory (ADF) Architecture & Hybrid ETL]] — Control plane vs Integration Runtime, Self-Hosted IR (SHIR) on-premises clustering, Mapping Data Flows, and Data Integration Units (DIUs).
- [[Azure/analytics/databricks|Azure Databricks Architecture & Lakehouse Analytics]] — Dual-plane VNet injection, Unity Catalog three-level namespace governance, Photon vectorized C++ engine, and Lakehouse Federation.

---

## Multi-Cloud Equivalents

| Capability                   | Microsoft Azure                                                     | Amazon Web Services (AWS)  | Google Cloud Platform (GCP)     |
| :--------------------------- | :------------------------------------------------------------------ | :------------------------- | :------------------------------ |
| **Data Lake Engine**         | [[Azure/analytics/fabric-synapse\|OneLake / ADLS Gen2]]             | Amazon S3 / Lake Formation | Google Cloud Storage / Dataplex |
| **Serverless SQL**           | [[Azure/analytics/fabric-synapse\|Synapse Serverless SQL / Fabric]] | Amazon Athena              | BigQuery Serverless             |
| **Data Orchestration / ETL** | [[Azure/analytics/data-factory\|Azure Data Factory]]                | AWS Glue                   | Cloud Data Fusion / Dataflow    |
| **Managed Apache Spark**     | [[Azure/analytics/databricks\|Azure Databricks]]                    | Amazon EMR                 | Dataproc                        |
| **Data Governance**          | [[Azure/analytics/databricks\|Unity Catalog / Microsoft Purview]]   | AWS Lake Formation         | Dataplex / Cloud Data Catalog   |

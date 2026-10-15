---
title: Azure
tags:
  - azure
  - cloud
  - microsoft
date: 2026-10-15
description: "Microsoft Azure cloud platform — comprehensive architectural deep dives across compute, storage, networking, AI, databases, developer tools, analytics, and security."
---

# Azure ☁️

Microsoft Azure cloud platform — comprehensive architectural deep dives covering enterprise identity, software-defined regional networking, managed Kubernetes, distributed NoSQL, generative AI, hybrid multi-cloud operations, and platform governance. Built to match the depth of the AWS and GCP knowledge bases with **Architecture & Mental Models + Production `az` CLI + Quotas & Limits + References + 2 Realistic Pricing Scenarios + 5+ Battle-Tested Nuggets & Gotchas**.

---

## Service Catalog by Architectural Domain

### 1. [[Azure/compute/README|Compute & Containers]]

- [[Azure/compute/aks|AKS Architecture Hub]] — Master architectural directory indexing 22 specialized engineering deep dives (Automatic, CNI Overlay, Cilium eBPF, Gateway API, GPU AI/ML, Kata Containers, Fleet Manager, SRE Runbooks).
- [[Azure/compute/vm|Virtual Machines & Scale Sets (VMSS)]] — VM series taxonomy, Flexible VMSS, Availability Zones vs Fault Domains, and Proximity Placement Groups.
- [[Azure/compute/vm/spot-vms|Azure Spot VMs & Scheduled Events]] — Surplus compute at 90% discount, 30-second eviction handling, and resilient batch pipelines.
- [[Azure/compute/container-apps/README|Azure Container Apps (ACA), KEDA & Dapr]] — Serverless containers on AKS/Envoy, event-driven KEDA autoscaling, Dapr sidecars, and scale-to-zero.
- [[Azure/compute/app-service/README|Azure App Service & Deployment Slots]] — Dedicated App Service Plans, zero-downtime deployment slots, and regional VNet integration.
- [[Azure/compute/functions|Azure Functions & Serverless Computing]] — Event-driven FaaS, Flex Consumption, Isolated Worker Model, Durable Functions stateful orchestrations, and cold-start optimization.

### 2. [[Azure/networking/README|Networking & Connectivity]]

- [[Azure/networking/vnet|Virtual Network (VNet) & Hybrid Routing]] — Regional VNet architecture, 5 reserved subnet IPs, VNet Peering with Gateway Transit, UDRs, and system routing.
- [[Azure/networking/nsg|Network Security Groups (NSGs) & ASGs]] — Stateful L3/L4 filtering, rule priority (100–4096), Service Tags, Application Security Groups, and dual-layer evaluation.
- [[Azure/networking/load-balancing|Azure Load Balancing, Application Gateway & Front Door]] — Layer 4 Azure Load Balancer, Layer 7 App Gateway WAF v2, and Azure Front Door Anycast edge CDN.
- [[Azure/networking/firewall/README|Azure Firewall & IDPS]] — Standard vs Premium, TLS inspection, 67,000+ signature IDPS, FQDN filtering, and Virtual WAN Secured Hubs.
- [[Azure/networking/virtual-wan/README|Azure Virtual WAN (vWAN)]] — Global transit networking, Secured Virtual Hubs, any-to-any VNet transit, ExpressRoute, and S2S VPN.
- [[Azure/networking/private-link/README|Azure Private Link & Private Endpoints]] — Private PaaS connectivity, Private DNS Zones, eliminating public IPs, and data exfiltration prevention.
- [[Azure/networking/dns-traffic-manager|Azure DNS & Traffic Manager Architecture]] — Public Anycast DNS, Private DNS Zones, Azure DNS Private Resolver, and Traffic Manager's 6 routing methods.
- [[Azure/networking/expressroute-vpn|Azure ExpressRoute & VPN Gateway Hybrid Architecture]] — Dedicated Layer 3 circuits, FastPath wire-speed bypass, Active-Active BGP (ASN 65515), and S2S VPN failover.
- [[Azure/networking/bastion-nat|Azure Bastion & NAT Gateway Architecture]] — Zero-public-IP browser/CLI jump hosts (Developer vs Standard SKU) and outbound SNAT port exhaustion mitigation.

### 3. [[Azure/storage/README|Storage & Shared Filesystems]]

- [[Azure/storage/blob|Azure Blob Storage & Data Lake Storage Gen2 (ADLS)]] — Redundancy tiers (LRS, ZRS, GRS, GZRS), Access Tiers (Hot/Cool/Cold/Archive), ADLS Gen2 Hierarchical Namespace (HNS), and User Delegation SAS.
- [[Azure/storage/files-netapp|Azure Files & Azure NetApp Files (ANF)]] — Cloud-native SMB 3.1.1 and NFSv4.1 shares vs bare-metal NetApp ONTAP infrastructure, sub-millisecond latencies, and FSLogix user profiles.
- [[Azure/storage/disks-elastic-san|Azure Managed Disks & Elastic SAN Architecture]] — Standard HDD/SSD, Premium SSD v1/v2, Ultra Disk, SCSI-3 Shared Disks, and cloud-native iSCSI SAN pools.

### 4. [[Azure/databases/README|Databases & In-Memory Caching]]

- [[Azure/databases/azure-sql|Azure SQL Database & Managed Instance]] — Single Database vs Managed Instance, vCore vs DTU, Serverless auto-pause, Hyperscale distributed storage, and Auto-Failover Groups.
- [[Azure/databases/cosmos-db|Azure Cosmos DB]] — Request Units (RUs), multi-region active-active writes, 5 mathematical consistency levels, partition key design, and Autoscale throughput.
- [[Azure/databases/postgres-flexible/README|PostgreSQL Flexible Server]] — Zone-redundant HA failover, integrated PgBouncer connection pooling, storage autogrow, and maintenance windows.
- [[Azure/databases/mysql-flexible|MySQL Flexible Server Architecture]] — Zone-redundant high availability, pre-provisioned vs Autoscale IOPS, read replicas, and server parameter tuning.
- [[Azure/databases/redis/README|Azure Cache for Redis]] — Basic vs Standard vs Premium (clustering, persistence) vs Enterprise (CRDT multi-region active-active).

### 5. [[Azure/application-integration/README|Application Integration & Messaging]]

- [[Azure/messaging/README|Azure Messaging & Event Architecture]] — Dedicated enterprise message queuing and streaming hub (Service Bus, Event Hubs, Event Grid).
- [[Azure/application-integration/event-grid|Azure Event Grid Architecture & CloudEvents Broker]] — Namespaces, MQTT v5.0 broker, CNCF CloudEvents v1.0 standard, push vs pull delivery, and reactive event routing.
- [[Azure/messaging/service-bus/README|Azure Service Bus Enterprise Architecture]] — Queues vs Topics, AMQP 1.0, FIFO message sessions, duplicate detection, dead-lettering, and transactions.
- [[Azure/messaging/event-hubs/README|Azure Event Hubs & Kafka Ingestion]] — Distributed partitioned streaming, Event Hubs Capture to ADLS Gen2, consumer groups, and Kafka protocol parity.
- [[Azure/application-integration/logic-apps|Azure Logic Apps Architecture & Enterprise Integration]] — Standard (single-tenant containerized) vs Consumption runtimes, 400+ connectors, stateful vs stateless workflows, and VNet integration.
- [[Azure/application-integration/apim|Azure API Management (APIM) Architecture & Gateway]] — Modern v2 tiers (Standard v2, Premium v2), XML policy pipeline, developer portal, OAuth2/JWT validation, and internal VNet injection.

### 6. [[Azure/ai/README|Artificial Intelligence & Machine Learning]]

- [[Azure/ai/openai|Azure OpenAI Service Architecture & Enterprise GenAI]] — Frontier LLMs (GPT-4o, o1), Provisioned Throughput Units (PTU) vs Pay-as-you-go TPM, Azure AI Content Safety, and zero model training boundaries.
- [[Azure/ai/ai-search|Azure AI Search Architecture & Enterprise Vector Retrieval]] — Dense vector search with HNSW, BM25 inverted indexes, Reciprocal Rank Fusion (RRF), deep Semantic Ranker reranking, and partition/replica scaling.
- [[Azure/ai/azure-ml|Azure Machine Learning (AML) Architecture & MLOps Platform]] — Workspace architecture, Managed Online Endpoints with blue/green deployment traffic splitting, autoscaling GPU compute clusters, and MLflow tracking.

### 7. [[Azure/developer-tools/README|Developer Tools & DevOps]]

- [[Azure/developer-tools/acr|Azure Container Registry (ACR) Architecture & Supply Chain Security]] — Premium SKU, Geo-replication, ACR Tasks for automated base image patching, OCI artifact store, private endpoints, and Defender for Containers.
- [[Azure/developer-tools/devops-github|Azure DevOps & GitHub Actions on Azure Architecture]] — Workload Identity Federation (keyless OIDC authentication), Actions Runner Controller (ARC) on AKS, and multi-stage enterprise release pipelines.
- [[Azure/developer-tools/bicep-stacks|Azure Bicep & Deployment Stacks Architecture]] — Declarative DSL for ARM, zero-day provider support, `actionOnUnmanage` lifecycle cleanup, `denySettingsMode` drift prevention, and private registry modules.

### 8. [[Azure/analytics/README|Analytics & Modern Data Platform]]

- [[Azure/analytics/fabric-synapse|Microsoft Fabric & Azure Synapse Analytics Architecture]] — OneLake unified lakehouse, Direct Lake Power BI querying, Delta Parquet native storage, Serverless SQL pools, and Spark runtimes.
- [[Azure/analytics/data-factory|Azure Data Factory (ADF) Architecture & Hybrid ETL]] — Control plane vs Integration Runtime, Self-Hosted IR (SHIR) on-premises clustering, Mapping Data Flows, and Data Integration Units (DIUs).
- [[Azure/analytics/databricks|Azure Databricks Architecture & Lakehouse Analytics]] — Dual-plane VNet injection, Unity Catalog three-level namespace governance, Photon vectorized C++ engine, and Lakehouse Federation.

### 9. [[Azure/security/README|Security & Zero Trust]]

- [[Azure/security/defender-for-cloud|Microsoft Defender for Cloud Architecture & CNAPP]] — Cloud Security Posture Management (CSPM), Cloud Workload Protection Platform (CWPP), Secure Score, Defender for Servers/Containers/Storage, and multi-cloud security.
- [[Azure/security/key-vault/README|Azure Key Vault & Managed HSM Architecture]] — FIPS 140-2 Level 3 hardware HSM, Azure RBAC authorization, Keys, Secrets, Certificates, Soft-Delete, and Purge Protection.

### 10. [[Azure/identity/README|Identity & Access Management]]

- [[Azure/identity/README|Microsoft Entra ID & Azure RBAC Architecture]] — Tenant architecture, Directory Roles vs Azure Resource RBAC, Managed Identities, PIM, and Conditional Access.
- [[Azure/identity/entraid|Microsoft Entra ID Architecture & Administration]] — Identity Provider (IdP), dynamic security groups, administrative units, and hybrid synchronization.
- [[Azure/identity/workload-identity|Workload Identity & Federated Credentials]] — Keyless authentication for AKS pods and GitHub Actions CI/CD using OIDC federation.

### 11. [[Azure/governance/README|Governance & Platform Operations]]

- [[Azure/governance/policy|Azure Governance — Management Groups, Policy & Locks]] — Management Group hierarchy, Azure Policy evaluation engines (Deny vs DeployIfNotExists), Initiatives, and Resource Locks.
- [[Azure/governance/resource-groups|Azure Resource Groups & ARM Lifecycle Architecture]] — ARM control plane boundaries, regional metadata constraints, resource locking, tagging strategies, and cross-group migration.
- [[Azure/governance/resource-graph|Azure Resource Graph (ARG) Architecture & Governance Querying]] — Distributed KQL search engine, cross-subscription inventory queries, schema tables, throttling mitigation, and FinOps audit automation.

### 12. [[Azure/monitoring/README|Monitoring & Cloud Observability]]

- [[Azure/monitoring/log-analytics/README|Azure Monitor & Log Analytics Architecture (KQL)]] — Centralized log workspaces, Kusto Query Language (KQL), diagnostic settings, commitment tiers, data retention, and Data Collection Rules (DCR).
- [[Azure/monitoring/sentinel/README|Microsoft Sentinel Architecture, Threat Intelligence & SOAR]] — Cloud-native SIEM/SOAR, multi-cloud data connectors, KQL threat analytics, incident investigation graphs, and automated Logic Apps playbooks.
- [[Azure/compute/aks/observability-monitoring|AKS Observability & Monitoring Deep Dive]] — Container Insights, Managed Prometheus, Azure Managed Grafana, and ContainerLogV2 schema optimization.

### 13. [[Azure/migration/README|Hybrid, Multi-Cloud & Migration]]

- [[Azure/migration/azure-arc|Azure Arc Architecture & Hybrid Multi-Cloud Governance]] — Arc-enabled servers, Arc-enabled Kubernetes with Flux v2 GitOps, Azure Policy guest configuration, zero-public-IP Arc SSH access, and Extended Security Updates (ESU).
- [[Azure/migration/azure-migrate|Azure Migrate Architecture & Datacenter Modernization]] — Agentless discovery appliance, performance-based right-sizing, dependency mapping, business case modeling, and wave migration planning.

### 14. [[Azure/cost-management/README|Cost Management & FinOps]]

- [[Azure/cost-management/cost-management-finops|Microsoft Cost Management & Enterprise FinOps Architecture]] — Azure Savings Plans vs Reserved Instances (RIs), FOCUS schema exports, automated budgets with forecast alerts, and Azure Advisor cost rules.
- [[Azure/compute/aks/cost-optimization-finops|AKS FinOps & Cost Allocation Deep Dive]] — Container cost attribution, Microsoft Cost Management AKS integration, OpenCost metrics, and capacity overprovisioning.

---

## Multi-Cloud Architecture Translation Matrix (AWS vs. GCP vs. Azure)

| Architectural Capability   | Amazon Web Services (AWS) | Google Cloud Platform (GCP) | Microsoft Azure                              | Key Cloud Native Differentiator                                                                                        |
| :------------------------- | :------------------------ | :-------------------------- | :------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------- |
| **Virtual Network Scope**  | Regional VPC              | **Global VPC**              | **Regional VNet**                            | GCP spans all regions globally; AWS and Azure isolate networks to single regions.                                      |
| **Enterprise Identity**    | AWS IAM / Identity Center | Cloud Identity & IAM        | **Microsoft Entra ID**                       | Entra ID natively unifies corporate Windows/M365 accounts with cloud RBAC.                                             |
| **Subnet IP Reservation**  | 5 IPs reserved per subnet | 4 IPs reserved per subnet   | **5 IPs reserved per subnet**                | Subnet sizing in Azure and AWS must account for 5 unusable addresses per CIDR.                                         |
| **Kubernetes Engine**      | Amazon EKS                | **Google GKE**              | **Azure AKS**                                | GKE pioneered Autopilot and Datapath V2; AKS excels with CNI Overlay and Cilium eBPF.                                  |
| **Serverless Compute**     | AWS Lambda                | **Cloud Run**               | [[Azure/compute/functions\|Azure Functions]] | Cloud Run handles concurrent requests per instance; Functions Flex scales up to 1,000 instances with VNet integration. |
| **Global Edge Anycast**    | Route 53 + CloudFront     | **Global Anycast IP**       | **Azure Front Door**                         | GCP and Azure Front Door terminate SSL at edge Anycast PoPs worldwide.                                                 |
| **Distributed NoSQL**      | Amazon DynamoDB           | Cloud Bigtable / Firestore  | **Azure Cosmos DB**                          | Cosmos DB offers 5 well-defined consistency levels and active-active global multi-master.                              |
| **Shared File Storage**    | Amazon EFS / FSx ONTAP    | Cloud Filestore             | **Azure Files / NetApp Files**               | Azure NetApp Files provides bare-metal ONTAP hardware delivering sub-millisecond latencies.                            |
| **Container Registry**     | Amazon ECR                | Artifact Registry           | **Azure Container Registry**                 | ACR Premium features multi-region geo-replication under a single FQDN and automated base image patching.               |
| **Reactive Event Router**  | Amazon EventBridge        | Eventarc                    | **Azure Event Grid**                         | Event Grid standardizes on CNCF CloudEvents v1.0 and integrates native MQTT v5.0 brokers for IoT.                      |
| **Enterprise API Gateway** | Amazon API Gateway        | Apigee API Management       | **Azure API Management**                     | APIM v2 offers rapid 5-minute auto-scaling, XML policy pipelines, and internal VNet injection.                         |
| **Generative AI Platform** | Amazon Bedrock            | Vertex AI (Gemini)          | **Azure OpenAI Service**                     | Exclusive enterprise hosting of frontier OpenAI models (GPT-4o, o1) within Azure boundary.                             |
| **Vector Retrieval / RAG** | Amazon OpenSearch Service | Vertex AI Vector Search     | **Azure AI Search**                          | Combines BM25 lexical search, HNSW vector search, and deep transformer Semantic Ranker via RRF.                        |
| **Unified Lakehouse**      | AWS Lake Formation        | BigQuery + Dataplex         | **Microsoft Fabric & OneLake**               | Direct Lake mode queries Delta Parquet in RAM without data refresh or duplication.                                     |
| **Hybrid Control Plane**   | AWS Systems Manager       | Google Distributed Cloud    | **Azure Arc**                                | Projects any physical server or CNCF Kubernetes cluster into ARM with Flux v2 GitOps.                                  |
| **Governance Engine**      | AWS Organizations SCPs    | Organization Policies       | **Azure Policy & Stacks**                    | Azure Policy provides real-time ARM evaluation; Deployment Stacks automatically purge deleted resources.               |

---

## Related Hubs

- [[AWS]] — Amazon Web Services catalog and deep dives
- [[GCP]] — Google Cloud Platform catalog and deep dives
- [[Kubernetes]] — Cloud-native container orchestration and deep dives
- [[Security/cloud-security/azure/README|Azure Security Hub]] — Cloud-native security operations

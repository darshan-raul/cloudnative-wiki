---
title: Azure Vault Progress Tracker
description: Tracks progress of Azure section expansion — 14 categories, deep dive engineering notes, and completion status.
tags:
  - azure
  - tracking
---

# Azure Vault Progress ☁️

Tracks completion of the Microsoft Azure knowledge base, adhering to the high-depth engineering standard: **Architecture & Mental Models + Production `az` CLI + Quotas & Limits + References + 2 Realistic Pricing Scenarios + 5+ Battle-Tested Nuggets & Gotchas**.

---

## 14 Domain Catalog & Coverage Status

### 1. Compute & Serverless 🖥️

- [x] **[[Azure/compute/README|Azure Compute Architecture Hub]]** — Decision trees, VM series taxonomy, compute paradigms
- [x] **[[Azure/compute/aks|Azure Kubernetes Service (AKS)]]** — Master hub: Azure CNI, Cilium eBPF, System/User pools, Ephemeral OS disks, Workload Identity
  - [x] 22 AKS Sub-modules (`automatic-deep-dive`, `networking-cni`, `cilium-ebpf`, `ingress-appgw-gateway`, `autoscaling-keda`, `storage-csi-disks`, `storage-csi-files-blob`, `gpu-orchestration-ai`, `batch-workloads`, `security-workload-identity`, `security-key-vault-csi`, `governance-azure-policy`, `multi-tenancy-isolation`, `observability-monitoring`, `backup-disaster-recovery`, `troubleshooting-runbook`, `cost-optimization-finops`, `fleet-manager-multicluster`, `upgrades-maintenance`, `node-pools-heterogeneous`, `cluster-tiers-sla`)
- [x] **[[Azure/compute/vm|Virtual Machines & Scale Sets (VMSS)]]** — VM series, Flexible VMSS, AZs vs Fault Domains, Proximity Placement Groups
- [x] **[[Azure/compute/vm/spot-vms|Azure Spot VMs & Scheduled Events]]** — 90% discount, 30s eviction notice, metadata polling
- [x] **[[Azure/compute/container-apps/README|Azure Container Apps (ACA), KEDA & Dapr]]** — Serverless microservices, Envoy ingress, scale-to-zero
- [x] **[[Azure/compute/app-service/README|Azure App Service & Deployment Slots]]** — App Service Plans, zero-downtime swap slots, VNet integration
- [x] **[[Azure/compute/functions|Azure Functions & Serverless Compute]]** — Flex Consumption, dedicated Premium/Consumption, Cold Start mitigation, trigger bindings

### 2. Networking & Content Delivery 🌐

- [x] **[[Azure/networking/README|Azure Networking Architecture Hub]]** — L4/L7 routing, hybrid connectivity, Zero-Trust isolation
- [x] **[[Azure/networking/vnet|Virtual Network (VNet) & Hybrid Routing]]** — Subnet reservations, VNet Peering, Gateway Transit, UDRs, NAT Gateway
- [x] **[[Azure/networking/nsg|Network Security Groups (NSGs) & ASGs]]** — Rule priorities (100–4096), Service Tags, ASGs, dual-layer filtering
- [x] **[[Azure/networking/load-balancing|Azure Load Balancing, Application Gateway & Front Door]]** — Layer 4 SLB, Layer 7 App Gateway WAF v2, Anycast Front Door
- [x] **[[Azure/networking/firewall/README|Azure Firewall & IDPS]]** — Standard vs Premium, TLS inspection, 67,000+ signature IDPS, Secured Virtual Hubs
- [x] **[[Azure/networking/virtual-wan/README|Azure Virtual WAN (vWAN)]]** — Global transit networking, Secured Virtual Hubs, ExpressRoute, S2S VPN
- [x] **[[Azure/networking/private-link/README|Azure Private Link & Private Endpoints]]** — Private PaaS connectivity, Private DNS Zones, zero public IPs
- [x] **[[Azure/networking/dns-traffic-manager|Azure DNS & Traffic Manager]]** — Public/Private DNS zones, Private Resolver, TM 6 routing methods
- [x] **[[Azure/networking/expressroute-vpn|ExpressRoute & VPN Gateway]]** — L3 dedicated circuits, FastPath bypass, Active-Active BGP, S2S VPN
- [x] **[[Azure/networking/bastion-nat|Azure Bastion & NAT Gateway]]** — Zero-public-IP jump hosts (Developer vs Standard SKU) and outbound SNAT exhaustion mitigation

### 3. Storage & Shared Filesystems 💽

- [x] **[[Azure/storage/README|Azure Storage Architecture Hub]]** — Object, block, file, and data lake storage models
- [x] **[[Azure/storage/blob|Azure Blob Storage & ADLS Gen2]]** — LRS/ZRS/GRS/GZRS, Hot/Cool/Cold/Archive, Hierarchical Namespace (HNS), SAS
- [x] **[[Azure/storage/files-netapp|Azure Files & Azure NetApp Files (ANF)]]** — SMB 3.1.1, NFSv4.1, bare-metal NetApp ONTAP, sub-millisecond latencies
- [x] **[[Azure/storage/disks-elastic-san|Azure Managed Disks & Elastic SAN]]** — Premium SSD v1/v2, Ultra Disk, SCSI-3 Shared Disks, cloud-native iSCSI SAN

### 4. Databases & In-Memory Caching 🗄️

- [x] **[[Azure/databases/README|Azure Databases Architecture Hub]]** — Relational, NoSQL, and caching decision trees
- [x] **[[Azure/databases/azure-sql|Azure SQL Database & Managed Instance]]** — Hyperscale distributed storage, Serverless auto-pause, Auto-Failover Groups
- [x] **[[Azure/databases/cosmos-db|Azure Cosmos DB]]** — Request Units (RUs), multi-region active-active writes, 5 mathematical consistency models
- [x] **[[Azure/databases/postgres-flexible/README|PostgreSQL Flexible Server]]** — Zone-redundant HA failover, built-in PgBouncer pooling, storage autogrow
- [x] **[[Azure/databases/mysql-flexible|MySQL Flexible Server]]** — Zone-redundant HA, pre-provisioned vs Autoscale IOPS, read replicas
- [x] **[[Azure/databases/redis/README|Azure Cache for Redis]]** — Basic vs Standard vs Premium vs Enterprise (active-active CRDT)

### 5. Application Integration & Messaging 📨🔄

- [x] **[[Azure/application-integration/README|Application Integration & Messaging Hub]]** — Enterprise messaging, streaming, eventing, workflows, APIs
- [x] **[[Azure/messaging/README|Azure Messaging Architecture]]** — Core message queue and stream directory
- [x] **[[Azure/application-integration/event-grid|Azure Event Grid]]** — CloudEvents v1.0 standard, MQTT v5.0 broker, push vs pull delivery
- [x] **[[Azure/messaging/service-bus/README|Azure Service Bus]]** — Queues vs Topics, AMQP 1.0, FIFO sessions, duplicate detection, dead-lettering
- [x] **[[Azure/messaging/event-hubs/README|Azure Event Hubs]]** — Distributed partitioned streaming, Kafka protocol parity, ADLS Capture
- [x] **[[Azure/application-integration/logic-apps|Azure Logic Apps]]** — Standard containerized vs Consumption, 400+ connectors, stateful vs stateless
- [x] **[[Azure/application-integration/apim|Azure API Management (APIM)]]** — Modern v2 tiers, XML policy pipeline, developer portal, VNet injection

### 6. Artificial Intelligence & Machine Learning 🧠🤖

- [x] **[[Azure/ai/README|Azure AI Architecture Hub]]** — Generative AI, cognitive services, and enterprise MLOps
- [x] **[[Azure/ai/openai|Azure OpenAI Service]]** — GPT-4o / o1-preview, Provisioned Throughput Units (PTUs), Content Safety, private endpoints
- [x] **[[Azure/ai/ai-search|Azure AI Search]]** — Hybrid retrieval, Reciprocal Rank Fusion (RRF), vector search, semantic ranking
- [x] **[[Azure/ai/azure-ml|Azure Machine Learning (AML)]]** — Managed Online Endpoints, MLflow tracking, Prompt flow, GPU compute clusters

### 7. Developer Tools & DevOps 🛠️🚀

- [x] **[[Azure/developer-tools/README|Developer Tools Architecture Hub]]** — IaC, container registries, and CI/CD pipelines
- [x] **[[Azure/developer-tools/acr|Azure Container Registry (ACR)]]** — Geo-replication, Task auto-builds, quarantine, Private Link, OCI artifacts
- [x] **[[Azure/developer-tools/devops-github|Azure DevOps & GitHub Actions]]** — Self-hosted scale set runners, Workload Identity OIDC federation, environments
- [x] **[[Azure/developer-tools/bicep-stacks|Bicep & ARM Deployment Stacks]]** — Clean syntax, `actionOnUnmanage: delete/detach`, zero state drift

### 8. Analytics & Big Data 📈📊

- [x] **[[Azure/analytics/README|Azure Analytics Architecture Hub]]** — Unified lakehouse, data warehousing, and ETL engines
- [x] **[[Azure/analytics/fabric-synapse|Microsoft Fabric & Synapse Analytics]]** — OneLake, Delta Parquet, Direct Lake Power BI, unified F-SKUs
- [x] **[[Azure/analytics/data-factory|Azure Data Factory (ADF)]]** — Mapping Data Flows, Self-Hosted Integration Runtime (SHIR), CDC
- [x] **[[Azure/analytics/databricks|Azure Databricks]]** — Unity Catalog governance, Serverless compute, Delta Lake engine, VNet injection

### 9. Security & Key Management 🛡️🔑

- [x] **[[Azure/security/README|Azure Security Architecture Hub]]** — Zero-Trust, CSPM/CWPP, and cryptographic key hierarchy
- [x] **[[Azure/security/key-vault/README|Azure Key Vault & Managed HSM]]** — FIPS 140-2 Level 3 HSM, RBAC authorization, auto-rotation
- [x] **[[Azure/security/defender-for-cloud|Microsoft Defender for Cloud]]** — CSPM security posture, CWPP runtime defenses, agentless container scanning

### 10. Governance, Compliance & Resource Management 🏛️📋

- [x] **[[Azure/governance/README|Azure Governance Architecture Hub]]** — Hierarchical policies, auditing, and resource inventory
- [x] **[[Azure/governance/policy|Azure Governance — Management Groups, Policy & Locks]]** — Hierarchy, Policy effects (Deny/DINE), Initiatives, Resource Locks
- [x] **[[Azure/governance/resource-groups|Resource Groups]]** — Lifecycle boundaries, deployment scopes, ARM metadata
- [x] **[[Azure/governance/resource-graph|Azure Resource Graph]]** — Millisecond cross-tenant KQL asset queries, schema introspection

### 11. Monitoring, Observability & Cloud SIEM 📊🔎

- [x] **[[Azure/monitoring/README|Azure Monitoring & Observability Hub]]** — Telemetry ingestion, metrics, logs, distributed tracing
- [x] **[[Azure/monitoring/log-analytics/README|Azure Monitor & Log Analytics (KQL)]]** — Log Analytics workspaces, KQL queries, diagnostic settings, commitment tiers
- [x] **[[Azure/monitoring/sentinel/README|Microsoft Sentinel SIEM/SOAR]]** — Cloud-native SIEM, threat hunting, Logic Apps automation playbooks

### 12. Migration, Hybrid & Multicloud 🚢🌐

- [x] **[[Azure/migration/README|Azure Migration & Hybrid Hub]]** — Cloud adoption framework, datacenter migration, hybrid control planes
- [x] **[[Azure/migration/azure-arc|Azure Arc]]** — Multicloud control plane, Arc-enabled Kubernetes (GitOps / Flux), Arc servers
- [x] **[[Azure/migration/azure-migrate|Azure Migrate]]** — Agentless discovery appliance, dependency mapping, hypervisor VM replication

### 13. Cost Management & FinOps 💰📉

- [x] **[[Azure/cost-management/README|Azure Cost Management & FinOps Hub]]** — Cloud financial management, rate optimization, governance
- [x] **[[Azure/cost-management/cost-management-finops|Microsoft Cost Management & FinOps Architecture]]** — Cost allocation rules, EA/MCA exports, Reserved Instances vs Savings Plans

### 14. Identity & Access Management (IAM) 🆔🔐

- [x] **[[Azure/identity/README|Microsoft Entra ID & Azure RBAC]]** — Tenant structure, Directory vs RBAC roles, Service Principals, Managed Identities, PIM, Conditional Access
- [x] **[[Azure/identity/workload-identity|Workload Identity & Federated Credentials]]** — AKS Workload Identity, GitHub Actions OIDC federation, eliminating client secrets
- [x] **[[Azure/identity/entraid|Microsoft Entra ID (Azure AD) Deep Dive]]** — Authentication protocols (OAuth2/OIDC/SAML), hybrid sync (Entra Connect)

---

## Completion Status: 100% ✅

All 14 core domains, 13 category landing hubs, and 24 deep technical service notes are fully drafted, verified, formatted, and validated against the production build pipeline.

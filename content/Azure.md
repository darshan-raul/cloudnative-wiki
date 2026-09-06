---
title: Azure
tags: [azure, cloud, microsoft]
date: 2026-09-06
description: "Microsoft Azure cloud platform — compute, storage, networking, Entra ID, governance, databases, and enterprise security deep dives."
---

# Azure ☁️

Microsoft Azure cloud platform — comprehensive architectural deep dives covering enterprise identity, software-defined regional networking, managed Kubernetes, distributed NoSQL, and cloud governance. Built to match the depth of the AWS and GCP knowledge bases with **Architecture & Mental Models + Production `az` CLI + Quotas & Limits + References + 2 Realistic Pricing Scenarios + 5+ Battle-Tested Nuggets & Gotchas**.

Track overall progress in [[Azure/PROGRESS|Azure Vault Progress]].

---

## Service Catalog

### 1. Identity & Governance
* [[Azure/identity/README|Microsoft Entra ID & Azure RBAC]] — Tenant architecture, Directory Roles vs. Azure Resource RBAC, Managed Identities, PIM, and Conditional Access.
* [[Azure/identity/workload-identity|Workload Identity & Federated Credentials]] — Keyless authentication for AKS pods and GitHub Actions CI/CD using OIDC federation.
* [[Azure/governance/policy|Azure Governance — Management Groups, Policy & Locks]] — Management Group hierarchy, Azure Policy evaluation engines (Deny vs DeployIfNotExists), Initiatives, and Resource Locks.
* [[Azure/resource-group|Resource Groups]] — Logical lifecycle boundaries, ARM deployments, and tagging strategies.

### 2. Networking
* [[Azure/networking/vnet|Virtual Network (VNet) & Hybrid Routing]] — Regional VNet architecture, 5 reserved subnet IPs, VNet Peering with Gateway Transit, User Defined Routes (UDRs), NAT Gateway, and Private Endpoints.
* [[Azure/networking/nsg|Network Security Groups (NSGs) & ASGs]] — Rule priority (100–4096), immutable default rules, Service Tags, Application Security Groups, and dual-layer filtering.
* [[Azure/networking/load-balancing|Azure Load Balancing, Application Gateway & Front Door]] — Layer 4 Azure Load Balancer, Layer 7 Application Gateway WAF v2, Azure Front Door Anycast CDN, and Private Link.
* [[Azure/networking/firewall/README|Azure Firewall & IDPS]] — Standard vs Premium, TLS inspection, 67,000+ signature IDPS, FQDN filtering, and Virtual WAN Secured Hub integration.
* [[Azure/networking/virtual-wan/README|Azure Virtual WAN (vWAN)]] — Global transit networking, Secured Virtual Hubs, any-to-any VNet transit, ExpressRoute, and Site-to-Site VPN.
* [[Azure/networking/private-link/README|Azure Private Link & Private Endpoints]] — Private PaaS connectivity, Private DNS Zones, eliminating public IPs, and data exfiltration prevention.

### 3. Compute & Containers
* [[Azure/compute/aks|Azure Kubernetes Service (AKS)]] — Azure CNI vs. Kubenet vs. CNI Overlay, Cilium eBPF dataplane, System vs. User node pools, Ephemeral OS disks, and Workload Identity.
* [[Azure/compute/vm|Virtual Machines & Scale Sets (VMSS)]] — VM series decision matrix, Flexible VMSS, Availability Zones vs Fault Domains, Spot VMs, Proximity Placement Groups, and Azure Bastion.
* [[Azure/compute/vm/spot-vms|Azure Spot VMs & Scheduled Events]] — Unallocated capacity at 90% discount, 30-second eviction notification, metadata polling, and resilient batch architectures.
* [[Azure/compute/container-apps/README|Azure Container Apps (ACA), KEDA & Dapr]] — Serverless containers on AKS/Envoy, KEDA event-driven autoscaling, Dapr microservice sidecars, and scale-to-zero.
* [[Azure/compute/app-service/README|Azure App Service & Deployment Slots]] — App Service Plans, zero-downtime deployment slots, regional VNet integration, and custom domain TLS.

### 4. Storage
* [[Azure/storage/blob|Azure Blob Storage & Data Lake Storage Gen2]] — Redundancy tiers (LRS, ZRS, GRS, GZRS), Hot/Cool/Cold/Archive access tiers, ADLS Gen2 Hierarchical Namespace (atomic directory renames), and User Delegation SAS.

### 5. Databases & Messaging
* [[Azure/databases/azure-sql|Azure SQL Database & Managed Instance]] — Single Database vs Managed Instance, vCore vs DTU purchasing models, Serverless auto-pause, Hyperscale distributed storage, and Auto-Failover Groups.
* [[Azure/databases/cosmos-db|Azure Cosmos DB]] — Request Units (RUs), multi-region active-active writes, 5 mathematical consistency levels, partition key design, and Autoscale throughput.
* [[Azure/databases/postgres-flexible/README|PostgreSQL Flexible Server]] — Zone-redundant HA failover, built-in PgBouncer pooling, storage autogrow, and custom maintenance windows.
* [[Azure/databases/redis/README|Azure Cache for Redis]] — Basic vs Standard vs Premium (clustering, RDB/AOF persistence) vs Enterprise (CRDT multi-region active-active).
* [[Azure/messaging/service-bus/README|Azure Service Bus]] — Enterprise messaging broker, Queues vs Topics, AMQP 1.0, FIFO message sessions, duplicate detection, and dead-lettering.
* [[Azure/messaging/event-hubs/README|Azure Event Hubs & Kafka Ingestion]] — Kafka 1.0+ wire protocol, Event Hubs Capture to Blob/ADLS, partitions, consumer groups, and throughput units.

### 6. Monitoring & Security
* [[Azure/monitoring/log-analytics/README|Azure Monitor & Log Analytics (KQL)]] — Centralized log workspaces, Kusto Query Language (KQL), diagnostic settings, commitment tiers, and data retention.
* [[Azure/monitoring/sentinel/README|Microsoft Sentinel SIEM/SOAR]] — Cloud-native SIEM, data connectors, KQL threat detections, incident investigation graphs, and Logic Apps SOAR playbooks.
* [[Azure/security/key-vault/README|Azure Key Vault & Managed HSM]] — FIPS 140-2 Level 3 hardware HSM, Azure RBAC authorization, Keys/Secrets/Certificates, Soft-Delete, and Purge Protection.

---

## Multi-Cloud Architecture Translation Matrix (AWS vs. GCP vs. Azure)

| Architectural Capability | Amazon Web Services (AWS) | Google Cloud Platform (GCP) | Microsoft Azure | Key Cloud Native Tradeoff |
| :--- | :--- | :--- | :--- | :--- |
| **Virtual Network Scope** | Regional VPC | **Global VPC** | **Regional VNet** | GCP spans all regions globally; AWS and Azure isolate networks to single regions. |
| **Enterprise Identity** | AWS IAM / Identity Center | Cloud Identity & IAM | **Microsoft Entra ID** | Entra ID natively unifies corporate Windows/M365 accounts with cloud RBAC. |
| **Subnet IP Reservation** | 5 IPs reserved per subnet | 4 IPs reserved per subnet | **5 IPs reserved per subnet** | Subnet sizing in Azure and AWS must account for 5 unusable addresses per CIDR. |
| **Kubernetes Engine** | Amazon EKS | **Google GKE** | **Azure AKS** | GKE pioneered Autopilot and Datapath V2; AKS excels with CNI Overlay and Cilium eBPF. |
| **Serverless Compute** | AWS Lambda | **Cloud Run** | Azure Functions | Cloud Run handles 1,000 concurrent requests per instance; Lambda is 1 request per container. |
| **Global Load Balancing** | Route 53 DNS + ALB | **Global Anycast IP** | **Azure Front Door** | GCP and Azure Front Door terminate SSL at edge Anycast PoPs worldwide. |
| **Distributed NoSQL** | Amazon DynamoDB | Cloud Bigtable / Firestore | **Azure Cosmos DB** | Cosmos DB offers 5 well-defined consistency levels and active-active global multi-master. |
| **Cold Storage Latency** | S3 Glacier (Hours) | **GCS Archive (Milliseconds)**| Azure Archive (Hours) | GCS Archive delivers instant first-byte retrieval; AWS and Azure require offline rehydration. |
| **Governance Engine** | AWS Organizations SCPs | Organization Policies | **Azure Policy & Blueprints** | Azure Policy provides granular real-time resource attribute evaluation and auto-remediation (DINE). |

---

## Related Hubs

* [[AWS]] — Amazon Web Services catalog and deep dives
* [[GCP]] — Google Cloud Platform catalog and deep dives
* [[Kubernetes]] — Cloud-native container orchestration and deep dives
* [[Security/cloud-security/azure/README|Azure Security Hub]] — Cloud-native security operations
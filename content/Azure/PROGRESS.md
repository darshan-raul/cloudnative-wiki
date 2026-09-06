---
title: Azure Vault Progress Tracker
description: Tracks progress of Azure section expansion — categories, in-depth notes written, and roadmap
tags:
  - azure
  - tracking
---

# Azure Vault Progress ☁️

Tracks completion of the Microsoft Azure knowledge base, adhering to the high-depth engineering standard: **Architecture & Mental Models + Production `az` CLI + Quotas & Limits + References + 2 Realistic Pricing Scenarios + 5+ Battle-Tested Nuggets & Gotchas**.

---

## Section Progress

### 1. Identity & Governance 🔐
- [x] **[[Azure/identity/README|Microsoft Entra ID & Azure RBAC]]** — Tenant structure, Directory vs RBAC roles, Service Principals, Managed Identities, PIM, and Conditional Access
- [x] **[[Azure/identity/workload-identity|Workload Identity & Federated Credentials]]** — AKS Workload Identity, GitHub Actions OIDC federation, eliminating client secrets
- [x] **[[Azure/governance/policy|Azure Governance — Management Groups, Policy & Locks]]** — Hierarchy, Policy effects (Deny/DINE), Initiatives, and Resource Locks
- [x] **[[Azure/resource-group|Resource Groups]]** — Lifecycle boundaries, deployment scopes, and ARM metadata

### 2. Networking 🌐
- [x] **[[Azure/networking/vnet|Virtual Network (VNet) & Hybrid Routing]]** — Regional VNets, 5 reserved subnet IPs, VNet Peering with Gateway Transit, UDRs, NAT Gateway, and Private Endpoints
- [x] **[[Azure/networking/nsg|Network Security Groups (NSGs) & ASGs]]** — Rule priority (100–4096), default rules, Service Tags, Application Security Groups, and dual-layer filtering
- [x] **[[Azure/networking/load-balancing|Azure Load Balancing, Application Gateway & Front Door]]** — Layer 4 Azure Load Balancer, Layer 7 Application Gateway WAF v2, Azure Front Door Anycast CDN, and Private Link
- [x] **[[Azure/networking/firewall/README|Azure Firewall & IDPS]]** — Standard vs Premium, TLS inspection, 67,000+ signature IDPS, FQDN filtering, and Virtual WAN Secured Hub integration
- [x] **[[Azure/networking/virtual-wan/README|Azure Virtual WAN (vWAN)]]** — Global transit networking, Secured Virtual Hubs, any-to-any VNet transit, ExpressRoute, and Site-to-Site VPN
- [x] **[[Azure/networking/private-link/README|Azure Private Link & Private Endpoints]]** — Private PaaS connectivity, Private DNS Zones, eliminating public IPs, and data exfiltration prevention

### 3. Compute & Containers 🖥️
- [x] **[[Azure/compute/aks|Azure Kubernetes Service (AKS)]]** — Azure CNI vs Kubenet vs CNI Overlay, Cilium eBPF dataplane, System/User node pools, Ephemeral OS disks, and Workload Identity
- [x] **[[Azure/compute/vm|Virtual Machines & Scale Sets (VMSS)]]** — VM series, Flexible VMSS, Availability Zones vs Fault Domains, Spot VMs, Proximity Placement Groups, and Azure Bastion
- [x] **[[Azure/compute/vm/spot-vms|Azure Spot VMs & Scheduled Events]]** — Unallocated capacity at 90% discount, 30-second eviction notification, metadata polling, and resilient batch architectures
- [x] **[[Azure/compute/container-apps/README|Azure Container Apps (ACA), KEDA & Dapr]]** — Serverless containers on AKS/Envoy, KEDA event-driven autoscaling, Dapr microservice sidecars, and scale-to-zero
- [x] **[[Azure/compute/app-service/README|Azure App Service & Deployment Slots]]** — App Service Plans, zero-downtime deployment slots, regional VNet integration, and custom domain TLS

### 4. Storage 💽
- [x] **[[Azure/storage/blob|Azure Blob Storage & ADLS Gen2]]** — Redundancy tiers (LRS/ZRS/GRS), access tiers, Archive rehydration, Hierarchical Namespace (HNS), and User Delegation SAS

### 5. Databases & Messaging 🗄️📨
- [x] **[[Azure/databases/azure-sql|Azure SQL Database & Managed Instance]]** — Single DB vs Managed Instance, vCore vs DTU, Serverless auto-pause, Hyperscale distributed storage, and Auto-Failover Groups
- [x] **[[Azure/databases/cosmos-db|Azure Cosmos DB]]** — Request Units (RUs), multi-region active-active writes, 5 consistency levels, partition key design, and Autoscale throughput
- [x] **[[Azure/databases/postgres-flexible/README|PostgreSQL Flexible Server]]** — Zone-redundant HA failover, built-in PgBouncer pooling, storage autogrow, and custom maintenance windows
- [x] **[[Azure/databases/redis/README|Azure Cache for Redis]]** — Basic vs Standard vs Premium (clustering, RDB/AOF persistence) vs Enterprise (CRDT multi-region active-active)
- [x] **[[Azure/messaging/service-bus/README|Azure Service Bus]]** — Enterprise messaging broker, Queues vs Topics, AMQP 1.0, FIFO message sessions, duplicate detection, and dead-lettering
- [x] **[[Azure/messaging/event-hubs/README|Azure Event Hubs & Kafka Ingestion]]** — Kafka 1.0+ wire protocol, Event Hubs Capture to Blob/ADLS, partitions, consumer groups, and throughput units

### 6. Monitoring & Security 📊🔐
- [x] **[[Azure/monitoring/log-analytics/README|Azure Monitor & Log Analytics (KQL)]]** — Centralized log workspaces, Kusto Query Language (KQL), diagnostic settings, commitment tiers, and data retention
- [x] **[[Azure/monitoring/sentinel/README|Microsoft Sentinel SIEM/SOAR]]** — Cloud-native SIEM, data connectors, KQL threat detections, incident investigation graphs, and Logic Apps SOAR playbooks
- [x] **[[Azure/security/key-vault/README|Azure Key Vault & Managed HSM]]** — FIPS 140-2 Level 3 hardware HSM, Azure RBAC authorization, Keys/Secrets/Certificates, Soft-Delete, and Purge Protection

---

## Roadmap & Future Expansions

- [x] **Azure Compute & PaaS Expansion** — Spot VMs, Container Apps, App Service
- [x] **Azure Advanced Networking** — Azure Firewall, Virtual WAN, Private Link
- [x] **Azure Databases & In-Memory Caching** — PostgreSQL Flexible Server, Azure Cache for Redis
- [x] **Azure Event Streaming & Enterprise Messaging** — Azure Service Bus, Azure Event Hubs
- [x] **Azure Observability & Cloud SIEM** — Azure Monitor / Log Analytics, Microsoft Sentinel, Key Vault & Managed HSM
- [ ] **Azure AI & Modern Data Stack** — Azure OpenAI Service, Microsoft Fabric, Azure Synapse

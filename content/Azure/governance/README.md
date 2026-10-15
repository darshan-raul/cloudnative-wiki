---
title: Azure Governance & Platform Operations Hub
description: Master architectural guide to Microsoft Azure governance — Management Groups, Azure Policy, Resource Locks, Resource Groups, Azure Resource Graph (ARG), and Cloud Adoption Framework (CAF).
tags:
  - azure
  - governance
  - management-groups
  - policy
  - resource-groups
  - resource-graph
  - caf
date: 2026-10-15
---

# Azure Governance & Platform Operations Hub 🏛️🛡️

Enterprise cloud governance in Microsoft Azure provides the organizational, regulatory, and policy guardrails required to control multi-subscription cloud estates securely, predictably, and cost-effectively without impeding developer agility.

---

## Architectural Decision Framework

```
                             Azure Governance Hierarchy
                                         │
        ┌────────────────────────────────┴────────────────────────────────┐
        ▼                                                                 ▼
Administrative Hierarchy & Guardrails                             Inventory & Querying
        │                                                                 │
┌───────┴───────┐                                                         │
│Management Grp.│ (e.g. Enterprise Root, Prod, Dev)                       │
└───┬───────────┘                                                         │
    ▼                                                                     │
┌───────────────┐                                                         │
│ Subscriptions │ (Billing, Regional Quotas)                              ▼
└───┬───────────┘                                        [[Azure/governance/resource-graph|Azure Resource Graph (ARG)]]
    ▼                                                    - Cross-Subscription KQL Queries
┌───────────────┐                                        - Sub-second Fleet Inventory
│Resource Groups│ [[Azure/governance/resource-groups|Resource Groups]]   - Change Tracking (14 Days)
└───┬───────────┘ - Lifecycle & ARM Scope
    ▼
[[Azure/governance/policy|Azure Policy & Locks]]
- Deny, Audit, Modify, DINE
- CanNotDelete / ReadOnly
```

### Governance Capabilities Matrix

| Capability                   | Azure Solution                                            | AWS Equivalent                        | GCP Equivalent               | Key Cloud Native Differentiator                                                                                    |
| :--------------------------- | :-------------------------------------------------------- | :------------------------------------ | :--------------------------- | :----------------------------------------------------------------------------------------------------------------- |
| **Enterprise Hierarchy**     | Management Groups (Up to 6 levels)                        | AWS Organizations                     | GCP Resource Manager Folders | Unified policy inheritance downward from Tenant Root to Subscriptions and Resource Groups.                         |
| **Real-Time Guardrails**     | [[Azure/governance/policy\|Azure Policy]]                 | AWS Organizations SCPs                | Organization Policy Service  | Evaluates resource properties inside the ARM control plane before creation; supports auto-remediation (DINE).      |
| **Fleet Inventory Querying** | [[Azure/governance/resource-graph\|Azure Resource Graph]] | AWS Resource Explorer / Config        | Cloud Asset Inventory        | Distributed KQL engine executing sub-second queries across 10,000 subscriptions without ARM throttling.            |
| **Lifecycle Boundaries**     | [[Azure/governance/resource-groups\|Resource Groups]]     | Resource Groups (Tag-based)           | Resource Manager Projects    | True physical lifecycle and deployment container; deleting an RG permanently purges all child objects.             |
| **Accidental Deletion Lock** | [[Azure/governance/policy\|Resource Locks]]               | Service Control Policies / MFA Delete | Project Liens                | `CanNotDelete` locks block deletion attempts from everyone, including Entra Global Admins and Subscription Owners. |

---

## Service Catalog

- [[Azure/governance/policy|Azure Governance — Management Groups, Policy & Locks]] — Management Group hierarchy, Azure Policy evaluation engines (Deny vs Audit vs DeployIfNotExists), Initiatives, and Resource Locks.
- [[Azure/governance/resource-groups|Azure Resource Groups & ARM Lifecycle Architecture]] — ARM control plane boundaries, regional metadata constraints, resource locking, tagging strategies, and cross-group migration.
- [[Azure/governance/resource-graph|Azure Resource Graph (ARG) Architecture & Governance Querying]] — Distributed KQL search engine, cross-subscription inventory queries, schema tables, throttling mitigation, and FinOps audit automation.

---

## Multi-Cloud Equivalents

| Capability            | Microsoft Azure                                           | Amazon Web Services (AWS)       | Google Cloud Platform (GCP) |
| :-------------------- | :-------------------------------------------------------- | :------------------------------ | :-------------------------- |
| **Root Management**   | Management Groups                                         | AWS Organizations (OUs)         | GCP Organization & Folders  |
| **Governance Engine** | [[Azure/governance/policy\|Azure Policy]]                 | Service Control Policies (SCPs) | Organization Policies       |
| **Asset Querying**    | [[Azure/governance/resource-graph\|Azure Resource Graph]] | AWS Resource Explorer           | Cloud Asset Inventory       |
| **Audit Trails**      | ARM Activity Log / Log Analytics                          | AWS CloudTrail                  | Cloud Audit Logs            |

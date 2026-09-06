---
title: Azure Governance — Management Groups, Policy & Locks
description: Azure Governance architecture — Management Group hierarchy, Azure Policy evaluation engines (Deny vs DeployIfNotExists), Initiatives, and Resource Locks.
tags:
  - azure
  - governance
  - policy
  - management-groups
  - compliance
  - security
---

# Azure Governance — Management Groups, Policy & Locks 🏛️📋

Azure Governance establishes enterprise guardrails, regulatory compliance, and cost control across multi-subscription environments. While **Azure RBAC** controls *who* can manage resources, **Azure Policy** controls *what* configurations are permitted, and **Resource Locks** prevent catastrophic deletions.

---

## Architecture & Mental Model

### The Enterprise Management Group Hierarchy

Azure organizes subscriptions into a strict hierarchical tree under a single **Tenant Root Group**:

```
                  ┌────────────────────────┐
                  │    Tenant Root Group   │ (Root Management Group)
                  └───────────┬────────────┘
                              │
               ┌──────────────┴──────────────┐
               ▼                             ▼
      ┌─────────────────┐           ┌─────────────────┐
      │   Platform MG   │           │   Workloads MG  │
      └────────┬────────┘           └────────┬────────┘
               │                             │
        ┌──────┴──────┐               ┌──────┴──────┐
        ▼             ▼               ▼             ▼
  ┌───────────┐ ┌───────────┐   ┌───────────┐ ┌───────────┐
  │Management │ │Connectivity│   │Non-Prod MG│ │  Prod MG  │
  │Subscription│ │Subscription│  └─────┬─────┘ └─────┬─────┘
  └───────────┘ └───────────┘         │             │
                                ┌─────┴─────┐ ┌─────┴─────┐
                                ▼           ▼ ▼           ▼
                              Sub-Dev    Sub-QA Sub-Prod1 Sub-Prod2
```

* **Policy Inheritance:** Policies and RBAC applied at `Tenant Root Group` automatically flow downward to all subscriptions and resource groups in the entire enterprise.

---

## Core Concepts

### 1. Azure Policy vs. Azure RBAC

| Governance Pillar | Focus | Evaluation Scope | Example Rule |
| :--- | :--- | :--- | :--- |
| **Azure RBAC** | **Who** has permission | Identity & Roles | "Alice can deploy virtual machines in Subscription A" |
| **Azure Policy** | **What** properties are allowed | Resource properties & state | "No virtual machine may be assigned a public IP address" |
| **Resource Locks** | **Accidental changes** | Delete and write locks | "Even Subscription Owners cannot delete the production VNet" |

### 2. Policy Effects & Evaluation Logic

When a user or CI/CD pipeline deploys a resource via Azure Resource Manager (ARM), Azure Policy evaluates the request through an evaluation pipeline:

```
Incoming ARM Request (az cli / Terraform)
               │
               ▼
   Is Effect = Disabled? ──────────────► Allow Request
               │ NO
               ▼
   Is Effect = Append / Modify? ───────► Alter payload (e.g. inject tags)
               │
               ▼
   Is Effect = Deny? ──────────────────► Immediate 403 Forbidden (Block)
               │ NO
               ▼
   Is Effect = Audit? ─────────────────► Mark non-compliant in compliance dashboard
               │
               ▼
   Is Effect = DeployIfNotExists? ─────► Trigger background remediation task
```

* **DeployIfNotExists (DINE):** Automatically deploys dependent resources (e.g., if a new VM is created, DINE automatically provisions the Azure Monitor Agent and connects it to Log Analytics).

### 3. Policy Initiatives (Policy Sets)

A Policy Initiative bundles multiple related policy definitions into a single assignable unit:
* **Predefined Compliance Initiatives:** Microsoft maintains curated initiatives for standards such as **PCI-DSS v4.0**, **ISO 27001**, **HIPAA**, and **NIST SP 800-53**.
* Assigning one initiative checks compliance across hundreds of controls simultaneously.

### 4. Resource Locks: CanNotDelete vs. ReadOnly

Locks apply to an entire scope (Subscription, Resource Group, or individual Resource) and are inherited by all child resources:

* **CanNotDelete (Delete Lock):** Authorized users can read and modify the resource, but **no one can delete it**.
* **ReadOnly (Read-Only Lock):** Users can read the resource, but **cannot modify, update, or delete it** (simulates a freeze).
* **Owner Override:** Even an Azure Subscription `Owner` cannot delete a locked resource until they explicitly delete the lock first.

---

## Production `az` CLI Commands

### 1. Assigning a Built-in Azure Policy (Deny Public IP Creation)

```bash
# Assign the 'Network interfaces should not have public IPs' built-in policy to a Subscription
az policy assignment create \
  --name "deny-public-ips" \
  --display-name "Enforce Private Networking (Deny Public IPs)" \
  --scope "/subscriptions/00000000-0000-0000-0000-000000000000" \
  --policy "83a827e2-0ec2-482c-b0b4-3f7d3773e769" \
  --enforcement-mode Default
```

### 2. Restricting Allowed Deployment Regions (Geo-Fencing)

```bash
# Assign Allowed Locations policy restricting deployments strictly to East US and East US 2
az policy assignment create \
  --name "allowed-locations" \
  --scope "/subscriptions/00000000-0000-0000-0000-000000000000" \
  --policy "e56962a6-4747-49cd-b67b-bf7b01975c4c" \
  --params '{ "listOfAllowedLocations": { "value": ["eastus", "eastus2"] } }'
```

### 3. Applying a Delete Lock to a Production Resource Group

```bash
az lock create \
  --name "lock-prevent-accidental-deletion" \
  --resource-group "prod-core-rg" \
  --lock-type CanNotDelete \
  --notes "Production infrastructure lock. Requires change approval to remove."
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Management Group depth** | 6 levels below root | Keeps hierarchy manageable |
| **Policy assignments per scope** | 500 assignments | Group definitions into Initiatives |
| **Resource locks per resource** | Up to 20 locks | Inherited downward to children |
| **Custom policy definitions per tenant** | 5,000 definitions | Share definitions at Management Group |

---

## References

* **Management Groups Overview:** https://learn.microsoft.com/en-us/azure/governance/management-groups/overview
* **Azure Policy Documentation:** https://learn.microsoft.com/en-us/azure/governance/policy/
* **Resource Locks Documentation:** https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/lock-resources
* **Pricing:** Free (Azure Policy and Resource Locks incur zero charges)

---

## Pricing Examples

### Scenario 1: Enterprise Multi-Subscription Governance
* 40 Azure Subscriptions organized under 5 Management Groups.
* Enforcing CIS Azure Benchmark Initiative and 25 custom policies across 10,000 resources.
* **Monthly Governance Cost:** **$0.00 / month** (Azure Policy, Management Groups, and Resource Locks are core platform features included with all Azure subscriptions).

### Scenario 2: Automated Remediation Storage Consumption
* DeployIfNotExists (DINE) policies automatically configure diagnostic log streaming to an Azure Log Analytics Workspace for 500 VMs.
* Policy evaluation: Free.
* Log Analytics ingestion (500 GB / month @ $2.30 / GB): ~$1,150.00 / month.
* **Effective Operational Cost:** **~$1,150.00 / month** in telemetry storage.

---

## Nuggets & Gotchas

1. **ReadOnly Locks Break Applications Unexpectedly:** Applying a `ReadOnly` lock to a Resource Group containing an App Service or Virtual Machine prevents write operations on the control plane. However, this also blocks Azure services from rotating internal state, writing temporary diagnostic status, or renewing managed TLS certificates, causing unexpected operational failures.
2. **Policy Evaluation Takes ~15–30 Minutes to Trigger on Existing Resources:** When you assign a new Azure Policy, new resources created via ARM are evaluated in real time. However, scanning *existing* resources for non-compliance does not happen immediately; Azure schedules a compliance scan that takes **15 to 30 minutes** to complete. To trigger an immediate on-demand scan:
```bash
az policy state trigger-scan --resource-group prod-core-rg
```
3. **DeployIfNotExists (DINE) Requires a Managed Identity:** When assigning a policy with the `DeployIfNotExists` or `Modify` effect, Azure Policy creates a system-assigned managed identity for the assignment. If you forget to grant this managed identity appropriate RBAC permissions (e.g. `Contributor`) over the target subscription, automated remediation will fail with `UnauthorizedOperation`.
4. **Subscription Moves Drop Resource Locks:** If you move a resource group from Subscription A to Subscription B, Azure Resource Locks attached at the Subscription level do not follow the resources. Verify and reapply resource locks immediately following any subscription reorganization.
5. **Enforcement Mode "DoNotEnforce" for Dry-Runs:** Never assign an unfamiliar `Deny` policy with default enforcement into production. Always assign the policy with `--enforcement-mode DoNotEnforce` first. This enables compliance auditing without blocking active developer deployments, allowing you to review the blast radius before turning on strict denial.

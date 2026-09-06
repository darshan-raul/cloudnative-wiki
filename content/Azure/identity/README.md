---
title: Microsoft Entra ID & Azure RBAC
description: Azure Identity architecture — Microsoft Entra ID (Azure AD), Directory Roles vs Azure RBAC, Managed Identities, Privileged Identity Management (PIM), and Conditional Access.
tags:
  - azure
  - identity
  - entra-id
  - rbac
  - security
---

# Microsoft Entra ID & Azure RBAC 🔐

Microsoft Entra ID (formerly Azure Active Directory) is Microsoft's multi-tenant, cloud-based identity and access management service. Unlike traditional Active Directory (Kerberos/NTLM/LDAP on Windows domain controllers), Entra ID is an internet-native identity provider communicating exclusively over **OIDC, OAuth 2.0, and SAML 2.0**.

In Azure, access governance is divided into two distinct control planes: **Microsoft Entra Directory Roles** (governing identity objects in the tenant) and **Azure Role-Based Access Control (RBAC)** (governing Azure infrastructure resources like VMs, VNets, and databases).

---

## Architecture & Mental Model

### The Dual Control Plane: Entra ID vs. Azure RBAC

A fundamental architectural pitfall in Azure is confusing Directory roles with Resource RBAC roles:

```
┌────────────────────────────────────────────────────────────────────────┐
│               Microsoft Entra ID Tenant (Identity Plane)               │
│               Root Authority: Global Administrator                     │
│                                                                        │
│   Users, Security Groups, App Registrations, Enterprise Applications   │
│   Directory Roles: User Administrator, Application Admin, etc.        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Trusts
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   Azure Subscriptions (Resource Plane)                 │
│                   Root Authority: Azure RBAC 'Owner'                   │
│                                                                        │
│   Management Groups ──► Subscriptions ──► Resource Groups ──► VMs/VNet │
│   Azure RBAC Roles: Owner, Contributor, Reader, Custom Roles           │
└────────────────────────────────────────────────────────────────────────┘
```

* **The Separation:** A **Global Administrator** in Entra ID does **not** have access to view or delete VMs in an Azure Subscription by default! However, an Entra Global Admin has a emergency toggle ("Access management for Azure resources") that can elevate themselves to `User Access Administrator` at the root Management Group level.

---

## Core Concepts

### 1. Azure RBAC Scope Hierarchy

Azure RBAC permissions are inherited downward through four administrative tiers:

```
               ┌────────────────────────┐
               │    Management Group    │ (e.g. Enterprise Root, Prod MG)
               └───────────┬────────────┘
                           │
            ┌──────────────┴──────────────┐
            ▼                             ▼
   ┌─────────────────┐           ┌─────────────────┐
   │ Subscription A  │           │ Subscription B  │ (Billing & Quota Boundary)
   └────────┬────────┘           └────────┬────────┘
            │                             │
     ┌──────┴──────┐                      │
     ▼             ▼                      ▼
┌─────────────┐ ┌─────────────┐      ┌─────────────┐
│ Resource    │ │ Resource    │      │ Resource    │ (Lifecycle & RBAC Boundary)
│ Group: Web  │ │ Group: Data │      │ Group: Sandbox│
└──────┬──────┘ └─────────────┘      └─────────────┘
       │
   ┌───┴─────────────────────────┐
   ▼                             ▼
┌──────────────┐          ┌──────────────┐
│  VM Instance │          │  Virtual Net │ (Resource Level)
└──────────────┘          └──────────────┘
```

* **Role Assignment Components:** `Security Principal` (User, Group, Service Principal, Managed Identity) + `Role Definition` (Owner, Contributor, Reader, Custom) + `Scope` (Management Group, Subscription, Resource Group, Resource).

### 2. Service Principals vs. Managed Identities

| Dimension | Service Principal (App Registration) | System-Assigned Managed Identity | User-Assigned Managed Identity |
| :--- | :--- | :--- | :--- |
| **Creation** | Created manually in Entra ID | Enabled directly on an Azure resource (VM, AKS, App Service) | Created as an independent standalone Azure resource |
| **Credential Storage** | Requires client secrets or X.509 certs that expire and must be rotated | **Zero credentials to manage:** Handled transparently by Azure platform | **Zero credentials to manage:** Handled transparently by Azure platform |
| **Lifecycle** | Independent of Azure resources | Tied 1:1 to the hosting resource (deleted when resource is deleted) | Independent lifecycle; can be shared across multiple resources |
| **Production Recommendation** | CI/CD pipelines outside Azure (use Workload Identity Federation) | Single-instance workloads (e.g. one VM connecting to Key Vault) | Multi-instance fleets (e.g. VMSS instances sharing DB access) |

### 3. Privileged Identity Management (PIM)

Privileged Identity Management enforces Just-In-Time (JIT) access for high-privilege roles (e.g., `Owner`, `Global Administrator`):
* Permanent standing administrator access is strictly prohibited.
* Users are marked **Eligible** rather than active.
* To perform administrative tasks, users activate the role for a limited window (e.g., 4 hours), requiring MFA, business justification, and optional peer approval.

### 4. Conditional Access Policies

Zero Trust policy engine evaluating context before issuing tokens:
* **Signals:** User risk score, geographic IP location, device compliance (Intune), client application.
* **Decisions:** Block access, require Phishing-resistant MFA, require Microsoft Entra hybrid joined device, require password change.

---

## Production `az` CLI Commands

### 1. Assigning Least-Privilege RBAC at Resource Group Scope

```bash
# Assign 'Key Vault Secrets User' role to an application service principal
az role assignment create \
  --assignee "00000000-0000-0000-0000-000000000000" \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/sub-123/resourceGroups/prod-app-rg/providers/Microsoft.KeyVault/vaults/prod-vault-01"
```

### 2. Creating and Attaching a User-Assigned Managed Identity

```bash
# 1. Create the managed identity
az identity create \
  --name "id-payment-worker" \
  --resource-group "prod-app-rg" \
  --location "eastus"

# Get Client ID and Resource ID
IDENTITY_ID=$(az identity show --name "id-payment-worker" --resource-group "prod-app-rg" --query id -o tsv)

# 2. Attach identity to a Virtual Machine
az vm identity assign \
  --name "prod-worker-vm" \
  --resource-group "prod-app-rg" \
  --identities "$IDENTITY_ID"
```

### 3. Querying Instance Metadata Service (IMDS) for Managed Identity Token

```bash
# Executed inside the Azure VM to retrieve a 1-hour access token for Azure Key Vault:
curl -s -H Metadata:true \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net"
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max RBAC assignments per subscription** | 4,000 assignments | Assign roles to Security Groups rather than individual users |
| **Max custom roles per tenant** | 5,000 custom roles | Keep custom roles modular |
| **Management Group nesting depth** | Up to 6 levels deep | Root → Core → Department → Environment → ... |
| **Managed Identities per resource** | 1 System-Assigned + up to 32 User-Assigned | Standard VM attachment limit |
| **App Registration client secret max validity** | 24 months | Rotate regularly or switch to Federated Credentials |

---

## References

* **Homepage:** https://www.microsoft.com/en-us/security/business/identity-access/microsoft-entra-id
* **Azure RBAC Documentation:** https://learn.microsoft.com/en-us/azure/role-based-access-control/overview
* **Managed Identities Overview:** https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview
* **Privileged Identity Management (PIM):** https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-configure
* **Pricing:** https://www.microsoft.com/en-us/security/business/microsoft-entra-pricing

---

## Pricing Examples

### Scenario 1: Standard Enterprise Cloud Infrastructure
* 20 Azure Subscriptions, 500 virtual machines, 50 AKS clusters using Managed Identities and standard RBAC.
* Azure RBAC operations, Managed Identity generation, and IMDS token requests: **$0.00** (Included free with Azure).
* Basic Microsoft Entra ID tier: **Free**.
* **Total Infrastructure IAM Cost:** **$0.00 / month**.

### Scenario 2: Zero Trust Governance with Entra ID P2 & PIM
* Enterprise requiring Privileged Identity Management (PIM), Risk-based Conditional Access, and Access Reviews for 250 privileged IT and DevOps administrators.
* Microsoft Entra ID P2 License: ~$9.00 / user / month.
* Monthly cost: 250 × $9.00 = **$2,250.00 / month**.
* General business employees remain on Entra ID Free or Microsoft 365 E3 licenses.

---

## Nuggets & Gotchas

1. **The "Contributor" Role Cannot Grant Permissions:** Many engineers assume `Contributor` has full access to a resource group. While a Contributor can create, restart, and delete VMs, databases, and networks, they **cannot assign RBAC permissions or create role assignments**. If a deployment pipeline needs to grant an AKS cluster access to an Azure Container Registry (ACR), the pipeline identity must have `User Access Administrator` or `Role Based Access Control Administrator`.
2. **Subnet Delegation Lockouts:** When delegating an Azure Subnet to a specific PaaS service (e.g. `Microsoft.Web/serverFarms` for App Service VNet Integration or `Microsoft.ContainerInstance/containerGroups`), Azure places strict internal service policies on that subnet. You cannot place standard VMs or other PaaS services into that subnet; attempting to do so will fail with a `SubnetIsDelegated` error.
3. **IMDS Header Requirement:** Just as GCP requires `Metadata-Flavor: Google`, Azure IMDS calls to `http://169.254.169.254/metadata/identity/oauth2/token` strictly require the HTTP header `Metadata: true`. Calls lacking this header are instantly rejected with an HTTP 400 Bad Request to prevent basic SSRF vulnerabilities.
4. **Custom Role AssignableScopes Cannot Exceed 100 Scopes:** A custom Azure RBAC role defines `assignableScopes` (where the role can be applied). If you list individual subscriptions, you will hit the hard limit of 100 assignable scopes. To use a custom role across an enterprise, set `assignableScopes` to a top-level **Management Group** (`/providers/Microsoft.Management/managementGroups/my-enterprise-mg`).
5. **Subscription Role Inheritance Cannot Be Blocked:** Azure RBAC permissions are strictly additive and flow downward. There is no concept of a "Deny" rule in standard Azure RBAC (Deny assignments only exist in Azure Blueprints and Managed Applications). If an engineer has `Contributor` at the Subscription level, you cannot restrict their access to a sensitive `prod-secrets-rg` Resource Group inside that subscription. Place sensitive workloads into a dedicated, isolated Subscription.

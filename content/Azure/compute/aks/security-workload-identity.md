---
title: AKS Security & Microsoft Entra Workload Identity Architecture
description: Exhaustive engineering guide to keyless authentication on AKS — Microsoft Entra Workload Identity, OIDC federated credentials, eliminating deprecated aad-pod-identity, Azure RBAC for Kubernetes Authorization, and PIM just-in-time access.
tags:
  - azure
  - aks
  - security
  - identity
  - entra-id
  - workload-identity
  - rbac
---

# AKS Security & Microsoft Entra Workload Identity Architecture 🔐🛡️

Securing pod-level access to Azure resources (Azure Key Vault, Cosmos DB, Azure SQL, Blob Storage) has historically presented significant operational security risks. Early patterns relied on static Service Principal client secrets mounted into containers (vulnerable to credential leakage) or legacy `aad-pod-identity` (which intercepted VM Instance Metadata Service requests using complex, high-privilege `NMI` DaemonSets). Today, **Microsoft Entra Workload Identity** is the enterprise standard: a keyless, cryptographically verified mechanism powered by the **Kubernetes Service Account Token Volume Projection** and **OIDC Federation**.

---

## 1. Architecture: OIDC Token Federation Exchange

```
                           KUBERNETES APPLICATION POD (Namespace: `finance`)
                           - Projected Service Account Token (`/var/run/secrets/tokens/jwt`)
                           - Signed by AKS OIDC Issuer Private Key
                                          │
                                          ▼ Presents Projected K8s JWT
       ┌────────────────────────────────────────────────────────────────────────┐
       │               MICROSOFT ENTRA ID (FORMERLY AZURE AD)                   │
       │                                                                        │
       │  Step 1: Entra fetches AKS OIDC Discovery Document:                    │
       │          `https://<region>.oic.prod-aks.azure.com/.../.well-known/...` │
       │  Step 2: Validates JWT signature using AKS public keys                 │
       │  Step 3: Matches Claims:                                               │
       │          - Subject (`sub`): `system:serviceaccount:finance:billing-sa` │
       │          - Issuer (`iss`): `https://<region>.oic.prod-aks.azure.com`   │
       │  Step 4: Locates User-Assigned Managed Identity: `id-billing-worker`   │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ Issues Short-Lived Azure Access Token
                                          ▼ (Valid for 1 Hour)
       ┌────────────────────────────────────────────────────────────────────────┐
       │                   TARGET SECURE AZURE RESOURCE                         │
       │                                                                        │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ Azure Key Vault        │         │ Azure Cosmos DB        │         │
       │  │ (GetSecret Permission) │         │ (Data Reader Role)     │         │
       │  └────────────────────────┘         └────────────────────────┘         │
       └────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Evolution: Workload Identity vs. Legacy `aad-pod-identity`

| Architectural Dimension | Legacy `aad-pod-identity` (DEPRECATED) | Microsoft Entra Workload Identity (CURRENT) |
| :--- | :--- | :--- |
| **Authentication Flow** | Intercepts node-level IMDS (`169.254.169.254`) | **Direct OIDC JWT token exchange with Entra** |
| **Cluster Node Daemons** | Requires heavy `NMI` (Node Managed Identity) pods| **Zero Node Daemons** (Lightweight webhook only) |
| **Linux `iptables` Tampering**| Intercepts and rewrites host IP routing | **Zero host networking manipulation** |
| **Token Acquisition Latency**| **2 to 10 seconds** (Host interception hop) | **< 200 milliseconds** (Direct HTTPS to Entra) |
| **Windows Node Support** | Not supported | **Fully Supported on Windows and Linux** |
| **Privilege Requirement** | Required cluster-wide `Virtual Machine Contributor`| **Least privilege (Scoped to Managed Identity)** |

---

## 3. Production Configuration & CLI Operations (`az` CLI & `kubectl`)

### 1. Enable Workload Identity & OIDC Issuer on AKS

```bash
# Enable OIDC Issuer and Workload Identity on target AKS cluster
az aks update \
    --resource-group rg-prod-security \
    --name aks-core-prod \
    --enable-oidc-issuer \
    --enable-workload-identity

# Extract cluster OIDC Issuer URL
export AKS_OIDC_ISSUER=$(az aks show \
    --resource-group rg-prod-security \
    --name aks-core-prod \
    --query "oidcIssuerProfile.issuerUrl" -o tsv)
echo "AKS OIDC Issuer: ${AKS_OIDC_ISSUER}"
```

### 2. Create Managed Identity and Configure Federated Credential

```bash
# Create User-Assigned Managed Identity in Azure
az identity create \
    --name id-billing-worker \
    --resource-group rg-prod-security

export MANAGED_IDENTITY_CLIENT_ID=$(az identity show \
    --name id-billing-worker \
    --resource-group rg-prod-security \
    --query "clientId" -o tsv)

# Create Federated Identity Credential linking K8s ServiceAccount to Azure Managed Identity
az identity federated-credential create \
    --name fed-credential-billing \
    --identity-name id-billing-worker \
    --resource-group rg-prod-security \
    --issuer "${AKS_OIDC_ISSUER}" \
    --subject "system:serviceaccount:finance:billing-sa" \
    --audience "api://AzureADTokenExchange"
```

### 3. Grant Azure RBAC Roles to Managed Identity

Grant the identity access to read secrets from an Azure Key Vault:

```bash
export KEY_VAULT_ID=$(az keyvault show --name kv-finance-prod --query "id" -o tsv)

az role assignment create \
    --role "Key Vault Secrets User" \
    --assignee "${MANAGED_IDENTITY_CLIENT_ID}" \
    --scope "${KEY_VAULT_ID}"
```

### 4. Deploy Kubernetes ServiceAccount & Application Workload

Create `billing-deployment.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: billing-sa
  namespace: finance
  annotations:
    # Binds ServiceAccount to Azure Managed Identity Client ID
    azure.workload.identity/client-id: "00000000-0000-0000-0000-000000000000"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: billing-service
  namespace: finance
spec:
  replicas: 3
  selector:
    matchLabels:
      app: billing-service
  template:
    metadata:
      labels:
        app: billing-service
        # Injects Workload Identity environment variables and projected token volume
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: billing-sa
      containers:
      - name: api
        image: mcr.microsoft.com/dotnet/samples:aspnetapp
        resources:
          limits:
            cpu: "1"
            memory: "1Gi"
          requests:
            cpu: "250m"
            memory: "512Mi"
```

Apply deployment:

```bash
kubectl apply -f billing-deployment.yaml
```

---

## 4. Azure RBAC for Kubernetes Authorization

In addition to pod identities, AKS supports **Azure RBAC for Kubernetes Authorization**, replacing static `kubeconfig` clusters with centralized Microsoft Entra ID directory role assignments:

| Role Name | Kubernetes Equivalent | Operational Scope |
| :--- | :--- | :--- |
| **Azure Kubernetes Service RBAC Reader** | `view` ClusterRole | Read-only inspection of pods, services, deployments |
| **Azure Kubernetes Service RBAC Writer** | `edit` ClusterRole | Create and modify deployments, configmaps, services |
| **Azure Kubernetes Service RBAC Admin** | `admin` ClusterRole| Full access within namespace, including RoleBindings |
| **Azure Kubernetes Service RBAC Cluster Admin**| `cluster-admin` | Unrestricted root control over all cluster resources |

---

## 5. Quotas, Performance & Configuration Limits

| Dimension | Platform Metric / Limit | Production Context |
| :--- | :--- | :--- |
| **Max Federated Credentials per Identity**| **20 Federated Credentials**| Max K8s ServiceAccounts linked to 1 Managed Identity |
| **Token Projection Expiration** | Default: **3,600 seconds (1 hr)** | Automatically rotated by Kubelet at 80% lifetime |
| **Entra Token Issuance Latency** | **< 150 milliseconds** | High-speed cryptographic token exchange |
| **Max Service Principals / Identities** | Enterprise scale (thousands)| Managed Identities avoid client secret rotations |

---

## 6. Official References

- [Microsoft Entra Workload Identity on AKS](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [Migrate from AAD Pod Identity to Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-migrate-from-pod-identity)
- [Use Azure RBAC for Kubernetes Authorization](https://learn.microsoft.com/en-us/azure/aks/azure-ad-rbac)
- [Azure AD Workload Identity GitHub Repository](https://github.com/Azure/azure-workload-identity)

---

## 7. Realistic Pricing Scenarios

### Scenario A: Enterprise Financial Platform (Zero Secret Rotations)

- **Architecture:** 50 microservices across 10 namespaces authenticating to Azure SQL and Azure Key Vault via Workload Identity.
- **Cost Comparison vs Secret Management Tools:**
  - *Option 1 (Third-Party HashiCorp Vault Cluster):* 3x dedicated nodes + Vault Enterprise licensing = **~$2,500 / month**.
  - *Option 2 (Entra Workload Identity):* **$0.00 / month** (Included natively with Microsoft Entra ID and AKS).
- **Total Operational Security Spend:** **$0.00** *(While eliminating all static secrets from Kubernetes manifests).*

### Scenario B: Regulatory Just-In-Time Cluster Administration via PIM

- **Architecture:**
  - 10 SRE engineers manage production AKS clusters using Azure RBAC.
  - Engineers hold zero persistent `cluster-admin` privileges.
  - Privileged Identity Management (PIM) grants 2-hour elevated access upon ticket approval.
- **Monthly Cost Breakdown:**
  - Microsoft Entra ID P2 License: 10 users × $9.00/user/mo = **$90.00**
  - AKS Cluster Audit Logging to Log Analytics: ~$30.00
- **Total Monthly Security Governance Spend:** **$120.00 / month**

---

## 8. Battle-Tested Nuggets & Production Gotchas

1. **The Subject Name Exact String Mismatch Trap:** When creating a federated credential in Azure, the `--subject` string must match the Kubernetes ServiceAccount token claims **with character-perfect precision**: `system:serviceaccount:<namespace>:<serviceaccount-name>`. If a developer creates the credential with `system:serviceaccount:finance:Billing-SA` (with capital letters) while the Kubernetes manifest defines `name: billing-sa`, Entra ID will reject token exchanges with `AADSTS70021: No matching federated identity record found`.
2. **Missing `azure.workload.identity/use: "true"` Label on Pods:** The Workload Identity mutating admission webhook only injects the projected token volume and environment variables (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_FEDERATED_TOKEN_FILE`) if the **Pod template metadata** contains the label `azure.workload.identity/use: "true"`. If an engineer places this label on the `Deployment` metadata instead of `.spec.template.metadata`, the webhook ignores the pod, and authentication crashes with `DefaultAzureCredential failed to retrieve token`.
3. **Federated Credential Limit (20 per Managed Identity):** Microsoft Entra ID enforces a strict limit of **20 federated identity credentials per Managed Identity**. If you have 30 microservices that attempt to reuse the exact same Managed Identity across different namespaces or clusters, the 21st credential creation will fail. Create dedicated, domain-scoped Managed Identities per microservice domain.
4. **Azure SDK Client Version Incompatibility:** Workload Identity relies on standard Azure SDKs (`Azure.Identity` in .NET, `@azure/identity` in Node.js, `azure-identity` in Python) that support token projection. If an application utilizes legacy SDK versions authored before 2022, the library will not know how to read `AZURE_FEDERATED_TOKEN_FILE` and will fail back to trying IMDS, which times out. Always verify that application dependencies use modern Azure SDKs.
5. **Azure RBAC Role Propagation Lag:** When an engineer is activated via Privileged Identity Management (PIM) for emergency cluster access, Azure RBAC role assignments take **3 to 5 minutes** to replicate across Microsoft Entra ID and the AKS API server. Attempting to run `kubectl get pods` immediately after PIM approval will fail with `Unauthorized`. Advise SRE teams to wait 3 minutes before executing incident runbooks.

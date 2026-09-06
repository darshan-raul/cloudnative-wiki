---
title: Azure Workload Identity & Federated Credentials
description: Azure Workload Identity — keyless authentication for AKS pods and GitHub Actions using OIDC federation and Microsoft Entra federated identity credentials.
tags:
  - azure
  - identity
  - workload-identity
  - aks
  - kubernetes
  - oidc
  - security
---

# Azure Workload Identity & Federated Credentials 🔑🚫

Azure Workload Identity enables applications running outside Azure (such as GitHub Actions CI/CD) or inside Kubernetes (AKS pods) to authenticate to Microsoft Entra ID and Azure resources **without storing static client secrets or managing certificate rollovers**.

By leveraging **Federated Identity Credentials**, Entra ID trusts external OpenID Connect (OIDC) identity providers, directly exchanging external JWTs for short-lived Azure access tokens.

---

## Architecture & Mental Model

### Token Exchange Flow with AKS Workload Identity

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Azure Kubernetes Service (AKS)                  │
│                                                                        │
│   ┌────────────────────────┐         ┌──────────────────────────────┐  │
│   │ Kubernetes Pod         │         │ Azure Workload Identity      │  │
│   │                        │         │ Webhook                      │  │
│   │ 1. Requests projected  │         │ Injects:                     │  │
│   │    service account     │         │ AZURE_CLIENT_ID              │  │
│   │    token (JWT)         │         │ AZURE_TENANT_ID              │  │
│   │                        │         │ AZURE_FEDERATED_TOKEN_FILE   │  │
│   └───────────┬────────────┘         └──────────────────────────────┘  │
└───────────────┼────────────────────────────────────────────────────────┘
                │
                │ 2. Exchanges projected token for Entra ID access token
                │    via STS endpoint (https://login.microsoftonline.com/...)
                ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      Microsoft Entra ID (Tenant)                       │
│                                                                        │
│   3. Validates token signature against AKS Cluster OIDC Issuer URL     │
│   4. Evaluates Federated Identity Credential:                          │
│      - Issuer: https://<location>.oic.prod-aks.azure.com/...          │
│      - Subject: system:serviceaccount:<namespace>:<serviceaccount>     │
│   5. Issues Azure RBAC Access Token (1-hour expiry)                    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    │ 6. Accesses Azure Resource
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│        Azure Key Vault / Azure SQL / Cosmos DB / Storage Account       │
└────────────────────────────────────────────────────────────────────────┘
```

* **Elimination of AAD Pod Identity:** The legacy `aad-pod-identity` used a Node-Managed Identity (NMI) daemonset that intercepted IMDS traffic on the node's loopback interface, introducing 10–30 second token latencies and severe iptables scaling bottlenecks. Modern Azure Workload Identity operates entirely via Kubernetes mutating webhooks and standard OIDC tokens.

---

## Core Concepts

### 1. AKS Workload Identity vs. Node Managed Identity

| Dimension | Legacy AAD Pod Identity (Deprecated) | Azure Workload Identity (Modern Standard) |
| :--- | :--- | :--- |
| **Mechanism** | Intercepts node IMDS (`169.254.169.254`) via NMI DaemonSet | Injects projected service account tokens via admission webhook |
| **Performance** | High latency (10–40s initial token acquisition) | **Sub-second** instant token acquisition |
| **Cluster Scaling** | Heavy iptables manipulation; crashed on large clusters | Lightweight; uses native Kubernetes projected volumes |
| **Security Scope** | Node-level; potential token leaks across co-located pods | **Pod-level isolation**: Tokens signed strictly for specific service accounts |

### 2. Federated Identity Credentials for GitHub Actions

Allows GitHub Actions workflows to deploy directly to Azure without saving an Azure Service Principal password/secret in repository settings:
* **Issuer:** `https://token.actions.githubusercontent.com`
* **Subject identifier:** `repo:<org>/<repo>:ref:refs/heads/main` or `repo:<org>/<repo>:environment:<env>`
* **Audience:** `api://AzureADTokenExchange`

---

## Production `az` CLI Commands

### 1. Configuring AKS Workload Identity on a Cluster

```bash
# 1. Update AKS cluster to enable OIDC Issuer and Workload Identity
az aks update \
  --resource-group prod-aks-rg \
  --name prod-aks-cluster \
  --enable-oidc-issuer \
  --enable-workload-identity

# 2. Retrieve the cluster's unique OIDC Issuer URL
OIDC_ISSUER=$(az aks show --resource-group prod-aks-rg --name prod-aks-cluster --query "oidcIssuerProfile.issuerUrl" -o tsv)

# 3. Create a User-Assigned Managed Identity
az identity create \
  --resource-group prod-aks-rg \
  --name id-order-service \
  --location eastus

USER_ASSIGNED_CLIENT_ID=$(az identity show --resource-group prod-aks-rg --name id-order-service --query "clientId" -o tsv)

# 4. Create the Federated Identity Credential linking K8s ServiceAccount to Azure Identity
az identity federated-credential create \
  --name "fed-cred-order-service" \
  --identity-name "id-order-service" \
  --resource-group "prod-aks-rg" \
  --issuer "$OIDC_ISSUER" \
  --subject "system:serviceaccount:production:order-service-sa" \
  --audience "api://AzureADTokenExchange"
```

### 2. Annotating Kubernetes ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: order-service-sa
  namespace: production
  annotations:
    azure.workload.identity/client-id: "00000000-0000-0000-0000-000000000000" # $USER_ASSIGNED_CLIENT_ID
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: production
spec:
  template:
    metadata:
      labels:
        azure.workload.identity/use: "true" # Triggers mutating webhook injection
    spec:
      serviceAccountName: order-service-sa
      containers:
        - name: app
          image: myacr.azurecr.io/order-service:v1.0
```

### 3. Configuring GitHub Actions OIDC Federated Credential

```bash
# Create federated credential on an App Registration for GitHub Actions main branch
az ad app federated-credential create \
  --id "app-object-id-123" \
  --parameters '{
    "name": "gh-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:my-company/my-service:ref:refs/heads/main",
    "description": "Deployment from main branch",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Federated credentials per Managed Identity** | 20 credentials | Create separate managed identities if scale exceeds 20 |
| **Federated credentials per App Registration** | 20 credentials | Can link to multiple repos or environments |
| **Subject identifier length** | Max 600 characters | Exact string match on OIDC `sub` claim |
| **Token lifetime** | 1 hour | Handled and renewed automatically by Azure SDKs |

---

## References

* **AKS Workload Identity Documentation:** https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview
* **Entra ID Workload Identity Federation:** https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation
* **GitHub Actions Azure Login:** https://github.com/Azure/login
* **Pricing:** Free (Included with Microsoft Entra ID and AKS)

---

## Pricing Examples

### Scenario 1: Enterprise Microservices Fleet
* 80 Microservices deployed across 4 AKS clusters in East US and West US.
* Each pod authenticates to Azure Key Vault, Azure SQL, and Azure Service Bus via Workload Identity.
* **Monthly Workload Identity Cost:** **$0.00 / month** (No charges for token exchanges, projected tokens, or federated credentials).

### Scenario 2: High-Velocity GitHub Actions CI/CD Pipeline
* 50 GitHub repositories executing 1,000 builds per day authenticating to Azure ARM via federated credentials.
* **Monthly Credential Management Cost:** **$0.00 / month** (Saves hundreds of engineering hours otherwise lost to manual client secret renewal).

---

## Nuggets & Gotchas

1. **The Label `azure.workload.identity/use: "true"` Is Mandatory:** If you configure the ServiceAccount annotation but forget to add `azure.workload.identity/use: "true"` to the **Pod template labels** in your Deployment, the AKS mutating webhook will ignore the pod. The projected volume and environment variables will not be injected, and the Azure SDK will fail with `CredentialUnavailableError`.
2. **Subject String Whitespace & Case Sensitivity:** The `--subject` field in federated credentials requires an exact, case-sensitive match against the OIDC token's `sub` claim. In AKS, the subject format must be strictly `system:serviceaccount:<namespace>:<service-account-name>`. A single typo in namespace or name results in an immediate `AADSTS70021: No matching federated identity record found`.
3. **Audience Must Be `api://AzureADTokenExchange`:** When creating federated identity credentials for both AKS and GitHub Actions, the audience **must** be set to `api://AzureADTokenExchange`. Setting this to custom values will cause token exchange validation to fail.
4. **Proxy & Firewall Blockers to AKS OIDC Discovery:** During token exchange, Microsoft Entra ID connects back to the AKS cluster's public OIDC Issuer URL to fetch its JSON Web Key Set (`/.well-known/openid-configuration` and `/openid/v1/jwks`). If the AKS cluster is deployed in an isolated enterprise network where outbound internet egress or Microsoft telemetry is blocked, Entra ID cannot retrieve the signing keys.
5. **Multiple Containers in a Single Pod:** If a pod contains multiple containers (e.g., application container + logging sidecar), the webhook injects the federated token volume into all containers. However, ensure that each container's process has filesystem permissions to read the projected token file at `/var/run/secrets/azure/tokens/azure-identity-token`.

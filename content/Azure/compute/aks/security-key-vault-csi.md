---
title: AKS Secrets Management — Azure Key Vault Provider for Secrets Store CSI Driver
description: Exhaustive engineering guide to secrets management on AKS — Azure Key Vault CSI driver add-on, in-memory tmpfs mounts, auto-syncing to Kubernetes Secret objects, secret auto-rotation, and FIPS 140-2 Level 3 HSM security.
tags:
  - azure
  - aks
  - security
  - key-vault
  - secrets-store-csi
  - hsm
  - encryption
---

# AKS Secrets Management — Azure Key Vault Provider for Secrets Store CSI Driver 🔐📦

Storing sensitive configuration data (database credentials, API keys, private TLS certificates) directly in Kubernetes `Secret` resources presents inherent security risks: Kubernetes Secrets are stored in `etcd` merely base64-encoded (not encrypted unless envelope encryption is explicitly configured), prone to unauthorized RBAC inspection, and disconnected from centralized corporate secrets management. The **Azure Key Vault Provider for Secrets Store CSI Driver** integrates AKS natively with **Azure Key Vault**, mounting secrets, keys, and certificates directly into pods as an in-memory **`tmpfs` volume** without ever writing plaintext secrets to disk or persisting them in `etcd`.

---

## 1. Architecture: The Secrets Store CSI Lifecycle

```
                           KUBERNETES APPLICATION POD (Namespace: `payments`)
                                          │
                                          ▼ Mounts Volume: `/mnt/secrets/vault`
       ┌────────────────────────────────────────────────────────────────────────┐
       │                SECRET PROVIDER CLASS (`SecretProviderClass`)           │
       │                - References Key Vault: `kv-prod-payments`              │
       │                - Authenticates via Microsoft Entra Workload Identity   │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ Dynamic Volume Mount Trigger
                                          ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │             SECRETS STORE CSI DRIVER (csi-secrets-store DaemonSet)     │
       │                                                                        │
       │  Step 1: Pod starts -> Kubelet invokes CSI Driver NodePublishVolume    │
       │  Step 2: Driver uses Workload Identity to fetch token from Entra ID    │
       │  Step 3: Calls Azure Key Vault REST API over TLS port 443              │
       │  Step 4: Mounts secrets directly into container memory (`tmpfs`)       │
       │  Step 5: Optional: Auto-creates synchronized Kubernetes `Secret` object│
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ Encrypted Private Link Transit
                                          ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │              AZURE KEY VAULT / MANAGED HSM (FIPS 140-2 Level 3)        │
       │              - Database Passwords     - API OAuth Secrets              │
       │              - mTLS Certificates      - Asymmetric Signing Keys        │
       └────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Secrets Store CSI vs. Native Kubernetes Secrets

| Dimension | Native Kubernetes Secrets | Azure Key Vault Secrets Store CSI Driver |
| :--- | :--- | :--- |
| **Storage Substrate** | Persisted in `etcd` (Base64 encoded) | **In-memory (`tmpfs`) volume mount only** |
| **Hardware Backing** | None (Software database) | **FIPS 140-2 Level 2 / Level 3 Hardware HSM** |
| **Centralized Governance** | Distributed across multiple clusters | **Single enterprise-wide Azure Key Vault** |
| **Audit Logging** | Kubernetes API audit logs | **Full Azure Monitor diagnostic audit logs** |
| **Secret Auto-Rotation** | Manual rollout / External scripts | **Automated polling with live file refresh** |
| **Access Control** | Kubernetes RBAC (Namespace scope) | **Azure RBAC (Granular Key Vault Secrets User)** |

---

## 3. Production Configuration & CLI Operations (`az` CLI & `kubectl`)

### 1. Enable Key Vault Secrets Store CSI Driver Add-on on AKS

```bash
# Enable the Secrets Store CSI Driver with automated secret rotation
az aks enable-addons \
    --resource-group rg-prod-security \
    --name aks-core-prod \
    --addons azure-keyvault-secrets-provider \
    --enable-secret-rotation
```

### 2. Grant Workload Identity Access to Key Vault

```bash
# Obtain Managed Identity Client ID
export USER_ASSIGNED_CLIENT_ID=$(az identity show \
    --name id-payments-sa \
    --resource-group rg-prod-security \
    --query "clientId" -o tsv)

# Grant "Key Vault Secrets User" role on Azure Key Vault
az role assignment create \
    --role "Key Vault Secrets User" \
    --assignee "${USER_ASSIGNED_CLIENT_ID}" \
    --scope "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod-security/providers/Microsoft.KeyVault/vaults/kv-prod-payments"
```

### 3. Deploy `SecretProviderClass` Manifest

Create `secret-provider-class.yaml`:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-kv-payments-spc
  namespace: payments
spec:
  provider: azure
  parameters:
    usePodIdentity: "false" # Uses modern Workload Identity!
    clientID: "00000000-0000-0000-0000-000000000000" # Managed Identity Client ID
    keyvaultName: "kv-prod-payments"
    tenantId: "11111111-1111-1111-1111-111111111111"
    objects: |
      array:
        - |
          objectName: DatabasePassword
          objectType: secret
          objectVersion: "" # Empty string retrieves latest active version
        - |
          objectName: StripeApiKey
          objectType: secret
        - |
          objectName: api-tls-cert
          objectType: cert
  # Optional: Automatically create and sync a native Kubernetes Secret for ENV variable injection
  secretObjects:
  - secretName: payments-synced-secret
    type: Opaque
    data:
    - objectName: DatabasePassword
      key: DB_PASSWORD
    - objectName: StripeApiKey
      key: STRIPE_KEY
```

### 4. Mount Key Vault Secrets into Application Pod

Create `payments-app-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-processor
  namespace: payments
spec:
  replicas: 3
  selector:
    matchLabels:
      app: payment-processor
  template:
    metadata:
      labels:
        app: payment-processor
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: payments-sa
      containers:
      - name: api
        image: mcr.microsoft.com/dotnet/samples:aspnetapp
        # Access secret via environment variable synced from Key Vault
        env:
        - name: DATABASE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: payments-synced-secret
              key: DB_PASSWORD
        # Mount secret files directly into in-memory tmpfs
        volumeMounts:
        - name: secrets-store-inline
          mountPath: "/mnt/secrets/vault"
          readOnly: true
      volumes:
      - name: secrets-store-inline
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: "azure-kv-payments-spc"
```

Apply manifests:

```bash
kubectl apply -f secret-provider-class.yaml
kubectl apply -f payments-app-deployment.yaml
```

---

## 4. Quotas, Performance & Configuration Limits

| Parameter / Feature | Platform Limit | Production Rule |
| :--- | :--- | :--- |
| **Key Vault API Rate Limit** | **4,000 requests per 10s** | Poll interval must be tuned to avoid throttling |
| **Default Secret Rotation Interval**| **2 minutes** | Configurable via `--rotation-poll-interval` |
| **Max Objects per SecretProviderClass**| Up to **100 Secrets/Keys** | Group related microservice secrets together |
| **Mount Latency Overhead** | **100–300 milliseconds** | Incurred strictly during container cold start |
| **Memory Consumption** | In-memory `tmpfs` | Secrets consume minuscule RAM (kilobytes) |

---

## 5. Official References

- [Azure Key Vault Provider for Secrets Store CSI Driver on AKS](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)
- [Enable Auto-Rotation of Secrets in AKS](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-rotation)
- [Secrets Store CSI Driver Kubernetes Documentation](https://secrets-store-csi-driver.sigs.k8s.io/)
- [Azure Key Vault Pricing Details](https://azure.microsoft.com/en-us/pricing/details/key-vault/)

---

## 6. Realistic Pricing Scenarios

### Scenario A: High-Security Fintech Core (100 Microservices, 500 Secrets)

- **Architecture:** 100 microservices fetching rotating credentials from Azure Key Vault via Secrets Store CSI.
- **Transaction Volume:**
  - 500 pods polling Key Vault every 5 minutes.
  - Total Monthly Key Vault Operations: ~$50,000 operations.
- **Monthly Cost Breakdown:**
  - Secrets Store CSI Add-on: **$0.00 (Free AKS Extension)**.
  - Azure Key Vault Base: **$0.00**.
  - Key Vault Secret Operations: 50,000 operations × $0.03 per 10,000 = **$0.15**
  - Managed Identity Operations: **$0.00**.
- **Total Monthly Cost:** **$0.15 / month** *(Achieving enterprise bank-grade secret security for under a dollar).*

### Scenario B: Payment Gateway with Hardware Security Module (Managed HSM)

- **Architecture:** High-assurance payment processing using dedicated FIPS 140-2 Level 3 Managed HSM.
- **Monthly Cost Breakdown:**
  - Azure Key Vault Managed HSM Instance: $4.40/hr × 730 hrs = **$3,212.00**
  - Secrets Store CSI Integration: **$0.00**
- **Total Monthly Spend:** **$3,212.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Synced Kubernetes Secret Chicken-and-Egg Problem:** If you configure `secretObjects` in the `SecretProviderClass` to create a native Kubernetes Secret, **the Kubernetes Secret object is NOT created until at least one pod actually mounts the CSI volume!** If an application container attempts to inject the secret via `envFrom.secretRef` before mounting the CSI volume, pod startup crashes with `CreateContainerConfigError: secret "payments-synced-secret" not found`. Ensure the container explicitly defines a `volumeMounts` entry referencing the CSI driver.
2. **Key Vault API Throttling during Massive Cluster Scaling:** Azure Key Vault enforces a subscription threshold of **4,000 operations per 10 seconds**. If a cluster with 500 pods scales up simultaneously during a traffic surge, 500 pods will concurrently query Key Vault, triggering HTTP `429 Too Many Requests`. The CSI driver fails, leaving pods stuck in `ContainerCreating`. Deploy an Azure Key Vault Private Endpoint and tune `--rotation-poll-interval` to at least `5m`.
3. **In-Memory File Updates Do Not Trigger Process Restarts:** When the CSI driver auto-rotates a secret, the file inside `/mnt/secrets/vault` is dynamically updated in the container's `tmpfs`. However, **applications that read secrets into memory only once at startup will continue using the stale credential indefinitely**. Use tools like **Stakater Reloader** or configure applications to watch filesystem events via `inotify`.
4. **Secret Versions Must Be Empty for Auto-Rotation:** In the `SecretProviderClass`, if you specify an explicit version hash in `objectVersion: "4376f9b..."`, the CSI driver will pin that exact version forever. Auto-rotation will never pull updated secrets. Always leave `objectVersion: ""` to ensure the latest active secret version is synchronized.
5. **Private Key Certificate Parsing Traps:** When syncing TLS certificates from Azure Key Vault, mounting `objectType: cert` retrieves only the public certificate chain. If your web server requires both the public cert and the private key, you must specify `objectType: secret` (which exports the complete PKCS#12 bundle) and split it into cert and key via `secretObjects`.

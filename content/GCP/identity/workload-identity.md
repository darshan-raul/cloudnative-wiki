---
title: GCP Workload Identity & Federation
description: Workload Identity Federation — keyless authentication for GKE, GitHub Actions, AWS, and external CI/CD pipelines using OIDC and STS token exchange.
tags:
  - gcp
  - identity
  - workload-identity
  - oidc
  - security
  - kubernetes
---

# GCP Workload Identity & Federation 🔑🚫

Workload Identity Federation eliminates long-lived service account keys (`.json` files) for both internal workloads (Kubernetes pods on GKE) and external workloads (GitHub Actions, AWS EC2/Lambda, GitLab, on-prem). 

Instead of storing secrets, workloads exchange external cryptographic tokens (Kubernetes Projected ServiceAccount Tokens or external OIDC JSON Web Tokens) for short-lived Google Cloud OAuth 2.0 access tokens via the **Security Token Service (STS)**.

---

## Architecture & Mental Model

### The Token Exchange Flow (RFC 8693)

```
┌─────────────────┐                                  ┌──────────────────────────┐
│ External Caller │                                  │  Google Cloud STS & IAM  │
│ (GitHub / AWS)  │                                  └────────────┬─────────────┘
└────────┬────────┘                                               │
         │ 1. Mint external token (OIDC JWT or AWS SigV4)         │
         │                                                        │
         │ 2. POST /v1/token (audience, grant_type, external_jwt) │
         ├───────────────────────────────────────────────────────►│
         │                                                        │ 3. Validate signature against
         │                                                        │    IdP JWKS or AWS STS
         │                                                        │ 4. Evaluate Attribute Condition
         │                                                        │    (e.g., repo == 'org/app')
         │ 5. Return Federated STS Token                          │
         │◄───────────────────────────────────────────────────────┤
         │                                                        │
         │ 6. Exchange STS Token for GCP SA Access Token          │
         │    (IAMCredentials generateAccessToken)               │
         ├───────────────────────────────────────────────────────►│
         │                                                        │ 7. Check roles/iam.workloadIdentityUser
         │ 8. Return Google OAuth2 Access Token (1 hour expiry)   │
         │◄───────────────────────────────────────────────────────┤
         │                                                        │
         │ 9. Authenticate to GCS, BigQuery, GKE, etc.            │
         └────────────────────────────────────────────────────────┘
```

---

## Part 1: GKE Workload Identity

GKE Workload Identity ties a **Kubernetes ServiceAccount (KSA)** directly to a **Google Cloud ServiceAccount (GSA)**. Pods running under that KSA seamlessly authenticate to GCP APIs via the GKE metadata server without mounting secret keys.

### Mechanics & Metadata Interception

When Workload Identity is enabled on a GKE cluster:
1. GKE deploys the **GKE Metadata Server** DaemonSet to every node.
2. Calls from pods to `http://metadata.google.internal/computeMetadata/v1/` are intercepted by the local metadata server.
3. The metadata server verifies the calling Pod's identity using Kubernetes TokenRequest API, checks the binding, and returns a GCP access token for the bound GSA.

### Production Configuration Steps

```bash
# 1. Enable Workload Identity on existing GKE cluster
gcloud container clusters update prod-cluster \
  --region=us-central1 \
  --workload-pool=my-prod-project.svc.id.goog

# 2. Create the Google Service Account (GSA)
gcloud iam service-accounts create backend-gsa \
  --project=my-prod-project

# 3. Grant GSA permissions on GCP resources (e.g. Cloud Storage)
gcloud projects add-iam-policy-binding my-prod-project \
  --member="serviceAccount:backend-gsa@my-prod-project.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

# 4. Allow the Kubernetes Service Account (KSA) to impersonate the GSA
gcloud iam service-accounts add-iam-policy-binding \
  backend-gsa@my-prod-project.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:my-prod-project.svc.id.goog[production/backend-ksa]"
```

```yaml
# 5. Define Kubernetes Service Account annotated with the GSA
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-ksa
  namespace: production
  annotations:
    iam.gke.io/gcp-service-account: backend-gsa@my-prod-project.iam.gserviceaccount.com
---
# 6. Deploy Pod referencing the KSA
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      serviceAccountName: backend-ksa
      containers:
        - name: app
          image: gcr.io/my-prod-project/backend:v1.0
```

---

## Part 2: External Workload Identity Federation (GitHub Actions)

Use Workload Identity Federation to allow GitHub Actions CI/CD to deploy to Google Cloud without storing long-lived JSON keys in GitHub Secrets.

### Step 1: Create Pool & Provider

```bash
# 1. Create a Workload Identity Pool
gcloud iam workload-identity-pools create github-pool \
  --project=my-prod-project \
  --location=global \
  --display-name="GitHub Actions Pool"

# 2. Create an OIDC Provider inside the Pool
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --project=my-prod-project \
  --location=global \
  --workload-identity-pool=github-pool \
  --display-name="GitHub Actions Provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == 'my-company'"
```

### Step 2: Grant Pool Impersonation Rights

```bash
# Get project number
PROJECT_NUMBER=$(gcloud projects describe my-prod-project --format='value(projectNumber)')

# Allow GitHub workflow from repository 'my-company/my-app' on main branch to impersonate deployer SA
gcloud iam service-accounts add-iam-policy-binding \
  deployer@my-prod-project.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/my-company/my-app"
```

### Step 3: GitHub Actions Workflow

```yaml
name: Deploy to GCP

on:
  push:
    branches: [main]

permissions:
  id-token: write # Mandatory for requesting the GitHub OIDC JWT
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: 'projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-provider'
          service_account: 'deployer@my-prod-project.iam.gserviceaccount.com'

      - name: Deploy to Cloud Run
        run: |
          gcloud run deploy my-service \
            --image=gcr.io/my-prod-project/my-service:${{ github.sha }} \
            --region=us-central1
```

---

## Quotas & Limits

| Attribute | Default Limit | Description |
| :--- | :--- | :--- |
| **Pools per Project** | 50 pools | Total Workload Identity Pools per project |
| **Providers per Pool** | 100 providers | Number of external IdPs (e.g. GitHub, AWS, GitLab) per pool |
| **Attribute Condition Size** | 2,048 characters | Max size for the CEL filtering expression |
| **Attribute Mapping Entries** | 32 custom mappings | Mappings from OIDC claims to Google security attributes |
| **Token Lifetime** | 1 hour default | Max configurable up to 12 hours via ServiceAccount policy |

---

## References

* **Homepage:** https://cloud.google.com/iam/docs/workload-identity-federation
* **GKE Workload Identity Docs:** https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
* **GitHub Actions Auth Action:** https://github.com/google-github-actions/auth
* **Pricing:** https://cloud.google.com/iam/pricing (Workload Identity Federation is free)

---

## Pricing Examples

### Scenario 1: High-Volume CI/CD Pipeline
* 100 active repositories running 5,000 GitHub Actions builds per day.
* Every build performs Workload Identity token exchange to push container images and deploy to GKE.
* Total STS Token Exchanges: 150,000 requests/month.
* **STS Exchange Cost:** **$0.00** (Google does not charge for STS token exchanges or federation).
* **Total Cost:** **$0.00 / month**.

### Scenario 2: Large Enterprise Multi-Cluster GKE Deployment
* 15 GKE clusters across 3 regions running 2,500 pods authenticating to Cloud Spanner, Pub/Sub, and Secret Manager via GKE Workload Identity.
* **GKE Workload Identity Add-on Cost:** **$0.00** (Included with GKE cluster management).
* **Total Monthly Federation Cost:** **$0.00**.

---

## Nuggets & Gotchas

1. **Missing `permissions: id-token: write` in GitHub Actions:** If your GitHub workflow fails with `400: Invalid Token` or `Unable to retrieve OIDC token`, 99% of the time it is because the workflow is missing `permissions: id-token: write`. Without this block, GitHub refuses to generate a signed JWT for the runner.
2. **Missing GSA Annotation on KSA Causes Silent Node Fallback:** If you bind the IAM role `roles/iam.workloadIdentityUser` to a KSA but forget to add `iam.gke.io/gcp-service-account: <gsa-email>` to the Kubernetes ServiceAccount annotations, the pod will **silently fall back** to the underlying GKE Node's Compute Engine service account. This can lead to either confusing permission-denied errors or unintentional privilege escalation.
3. **The `attribute-condition` Injection Trap:** Always enforce an `--attribute-condition` matching `assertion.repository_owner == '<your-org>'` or `assertion.repository == '<your-org>/<your-repo>'` at the provider level. If you create a GitHub Actions provider without a repository restriction and only bind permissions loosely at the pool, *any* public GitHub repository could theoretically exchange a token against your pool.
4. **HostNetwork Pods Bypass Workload Identity:** Pods running with `hostNetwork: true` share the network namespace of the GKE node. Because of this, their requests to `169.254.169.254` bypass the GKE Metadata Server daemonset filter and always receive the node's machine service account credentials. **Never use `hostNetwork: true` for pods requiring fine-grained Workload Identity.**
5. **Node Pool Upgrades & Metadata Server Restart Blips:** During GKE node pool rolling upgrades, the local metadata server pod is briefly restarted on newly scheduled nodes. Applications initiating connections during pod startup should implement standard exponential backoff retries when fetching initial tokens from the metadata endpoint.

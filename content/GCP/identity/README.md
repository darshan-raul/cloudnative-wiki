---
title: GCP Identity & Access Management (IAM)
description: GCP IAM — resource hierarchy, roles, service accounts, impersonation, policy evaluation, organization policies, and keyless authentication.
tags:
  - gcp
  - identity
  - iam
  - security
---

# GCP Identity & Access Management (IAM) 🔐

Google Cloud IAM provides centralized authorization across all GCP resources. Access control in GCP operates fundamentally on a **hierarchical inheritance model**: permissions defined at a parent container (Organization or Folder) flow downward to all descendant projects and resources.

Unlike AWS IAM (where policies are identity-centric or resource-centric JSON documents attached directly to users or roles), GCP IAM uses an **Allow Policy binding model**: an allow policy is attached to a resource, binding **Principals** (Who) to **Roles** (What permissions) with optional **Conditions** (When/Context).

---

## Architecture & Mental Model

### The GCP Resource Hierarchy

All GCP resources reside in a strict tree hierarchy. IAM policies are inherited downward:

```
                  ┌────────────────────────┐
                  │      Organization      │  (Root: example.com)
                  │  iam.example.com admin │
                  └───────────┬────────────┘
                              │
               ┌──────────────┴──────────────┐
               ▼                             ▼
      ┌─────────────────┐           ┌─────────────────┐
      │  Folder: Core   │           │ Folder: Sandbox │
      └────────┬────────┘           └────────┬────────┘
               │                             │
        ┌──────┴──────┐                      │
        ▼             ▼                      ▼
 ┌─────────────┐ ┌─────────────┐      ┌─────────────┐
 │ Project:    │ │ Project:    │      │ Project:    │
 │ prod-app    │ │ stage-app   │      │ dev-testing │
 └──────┬──────┘ └─────────────┘      └─────────────┘
        │
   ┌────┴────────────────────────┐
   ▼                             ▼
┌──────────────┐          ┌──────────────┐
│  GCE / GKE   │          │  GCS Buckets │
└──────────────┘          └──────────────┘
```

1. **Organization:** Represents the company (tied 1:1 to a Google Workspace or Cloud Identity domain). Top-level root for Org Policies and centralized billing.
2. **Folders:** Organizational units to group projects by department, environment (prod vs non-prod), or regulatory boundary. Can be nested up to 10 levels deep.
3. **Projects:** The fundamental boundary for billing, enabled APIs, quotas, and permissions. Resources *must* belong to exactly one project.
4. **Resources:** The actual infrastructure components (VM instances, Cloud Storage buckets, BigQuery datasets).

---

## Core Concepts

### 1. Principals (Who)

GCP does not maintain standalone "IAM Users" inside a project. Instead, identities come from external identity providers or GCP-managed services:

* `user:{email}` — A Google Account or Google Workspace / Cloud Identity account (e.g., `user:alice@company.com`).
* `group:{email}` — A Google Group. **Best Practice:** Always grant permissions to groups, never directly to individual users.
* `serviceAccount:{email}` — An application identity for machine-to-machine workloads.
* `domain:{domain}` — All identities within an entire Google Workspace/Cloud Identity domain.
* `principalSet://...` — Workload Identity Federation pools (GitHub Actions, AWS roles, Azure AD).
* `allAuthenticatedUsers` — Any identity with a valid Google account worldwide (rarely used, high risk).
* `allUsers` — Anyone on the public internet (used for public GCS assets or public Cloud Run endpoints).

### 2. Roles (What Permissions)

Permissions in GCP take the form `<service>.<resource>.<action>` (e.g., `compute.instances.start`, `storage.objects.get`). Permissions are **never** granted individually; they are bundled into roles:

| Role Category | Description | Example | Production Guidance |
| :--- | :--- | :--- | :--- |
| **Primitive / Basic** | Legacy roles (`Owner`, `Editor`, `Viewer`). Extremely broad. | `roles/editor` | **NEVER use in production.** `Editor` can delete nearly all resources; `Owner` can manage billing and IAM. |
| **Predefined** | Curated by Google for specific job functions per service. Granular and maintained. | `roles/storage.objectViewer`, `roles/container.admin` | **Default choice** for most infrastructure and deployment needs. |
| **Custom Roles** | User-defined bundles of specific permissions at Project or Org level. | `projects/my-proj/roles/customDeployer` | Use when predefined roles grant too much privilege (Principle of Least Privilege). Cannot include permissions marked "supported: false" for custom roles. |

### 3. Policy Structure & Conditions

An IAM Allow Policy consists of bindings:

```json
{
  "bindings": [
    {
      "role": "roles/storage.objectAdmin",
      "members": [
        "group:data-platform@company.com"
      ]
    },
    {
      "role": "roles/compute.instanceAdmin.v1",
      "members": [
        "serviceAccount:ci-runner@prod-infra.iam.gserviceaccount.com"
      ],
      "condition": {
        "title": "Business Hours Only",
        "description": "Allow modifications only between 08:00 and 18:00 UTC",
        "expression": "request.time.getHours('UTC') >= 8 && request.time.getHours('UTC') <= 18"
      }
    }
  ]
}
```

* **IAM Conditions:** Expressed in Common Expression Language (CEL). Evaluate attributes like `request.time`, `resource.name`, `request.auth.claims`, or destination IP ranges.

### 4. Policy Evaluation Algorithm

```
                 Incoming Request
                        │
                        ▼
             Does a Deny Policy apply?
             ├── YES ──► ACCESS DENIED (Immediate stop)
             └── NO
                  │
                  ▼
         Evaluate Allow Policies at:
         1. Organization level
         2. Folder level(s)
         3. Project level
         4. Resource level (if supported)
                  │
                  ▼
         Union of all Allow Policies
         contains requested permission?
         ├── YES ──► ACCESS GRANTED
         └── NO  ──► ACCESS DENIED
```

* **Inheritance is strictly additive:** Permissions granted at a parent cannot be removed or restricted by an allow policy at a child. If a user is `Editor` at the Folder, giving them `Viewer` at the child Project does **not** downgrade their access.
* **Deny Policies:** Introduced to explicitly override inherited allow permissions. Evaluated before any allow policy.

---

## Service Accounts & Impersonation

A Service Account is a special account used by an application or compute workload, identified by an email address:
`<sa-name>@<project-id>.iam.gserviceaccount.com`

### Service Account Types

1. **Default Service Accounts:**
   * Compute Engine default: `<project-number>-compute@developer.gserviceaccount.com`
   * Automatically created when APIs are enabled.
   * **Massive Gotcha:** Historically created with the primitive `Editor` role! Always disable default service accounts or remove the `Editor` binding immediately.
2. **Google-Managed Service Accounts (Service Agents):**
   * Format: `service-<project-number>@compute-system.iam.gserviceaccount.com`
   * Used internally by GCP services to act on your behalf (e.g., Cloud Build deploying to Cloud Run).
3. **User-Managed Service Accounts:**
   * Created manually for dedicated applications with least-privilege predefined roles.

### Eliminating Long-Lived Service Account Keys

Service Account keys (`.json` files) are one of the most common causes of cloud breaches. Google Cloud provides two keyless alternatives:

1. **Short-Lived Token Impersonation:**
   Instead of exporting a private key, an authenticated user or CI runner assumes the service account dynamically:

```bash
# Grant a developer the ability to impersonate the deployment SA
gcloud iam service-accounts add-iam-policy-binding \
  deployer@my-project.iam.gserviceaccount.com \
  --member="user:alice@company.com" \
  --role="roles/iam.serviceAccountTokenCreator"

# Developer executes commands as that service account without a JSON key
gcloud compute instances list \
  --impersonate-service-account=deployer@my-project.iam.gserviceaccount.com
```

2. **Metadata Server Authentication (Within GCP):**
   Workloads running inside Compute Engine, GKE, or Cloud Run fetch short-lived OAuth 2.0 access tokens directly from the link-local metadata server:

```bash
# Retrieve OAuth2 access token with 1-hour expiry
curl -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
```

---

## Organization Policies vs IAM Policies

A critical distinction in GCP governance:

| Dimension | IAM Policy | Organization Policy |
| :--- | :--- | :--- |
| **Focus** | **Who** can do **what** on which resource | **What configurations** are permitted across resources |
| **Question** | "Can Bob create a public GCS bucket?" | "Are public GCS buckets allowed anywhere in this Org?" |
| **Enforcement** | Evaluates identity and roles | Evaluates resource attributes and constraints |
| **Key Constraints** | N/A | `constraints/storage.publicAccessPrevention`<br>`constraints/iam.disableServiceAccountKeyCreation`<br>`constraints/compute.vmExternalIpAccess` |

---

## Production `gcloud` CLI Commands

### 1. Managing Project IAM Bindings

```bash
# Add a predefined role to a Google Group
gcloud projects add-iam-policy-binding my-prod-project \
  --member="group:sre-team@company.com" \
  --role="roles/monitoring.admin"

# View current project policy in JSON
gcloud projects get-iam-policy my-prod-project \
  --format=json > current-policy.json

# Test what permissions the current authenticated identity has
gcloud projects test-iam-permissions my-prod-project \
  --permissions="compute.instances.create,storage.buckets.create"
```

### 2. Creating Least-Privilege Service Accounts

```bash
# 1. Create the service account
gcloud iam service-accounts create payment-worker \
  --description="Worker service account for payment processing" \
  --display-name="Payment Worker"

# 2. Grant specific predefined role on project
gcloud projects add-iam-policy-binding my-prod-project \
  --member="serviceAccount:payment-worker@my-prod-project.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"

# 3. Restrict bucket access to only one specific bucket (Resource-level binding)
gcloud storage buckets add-iam-policy-binding gs://prod-payment-receipts \
  --member="serviceAccount:payment-worker@my-prod-project.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

### 3. Enforcing Essential Organization Policies

```bash
# Disable export/download of service account JSON private keys across the entire org
gcloud org-policies set-policy-binding \
  --organization=123456789012 \
  --constraint=constraints/iam.disableServiceAccountKeyCreation \
  --enforce

# Enforce Public Access Prevention (PAP) on all GCS buckets in production folder
gcloud resource-manager org-policies enable-enforce \
  constraints/storage.publicAccessPrevention \
  --folder=987654321
```

---

## Quotas & Limits

| Resource / Action | Default Quota / Limit | Notes |
| :--- | :--- | :--- |
| **Max policy size** | 250 KB per policy | Max limit across all bindings and conditions on a single resource |
| **Max condition length** | 1,024 characters per CEL expression | Keep condition logic concise |
| **Max Service Accounts per project** | 100 | Can be raised via quota request |
| **Service Account key expiration** | Indefinite (until revoked) | Why keys are dangerous; use impersonation instead |
| **Token creator token lifetime** | Max 1 hour (default), up to 12 hours | Configurable via `max_token_lifetime` organization policy |
| **Folder nesting depth** | Up to 10 levels deep | Organization root → Folder 1 → ... → Folder 10 |

---

## References

* **Homepage:** https://cloud.google.com/iam
* **Documentation:** https://cloud.google.com/iam/docs
* **Predefined Roles Reference:** https://cloud.google.com/iam/docs/understanding-roles
* **Pricing:** https://cloud.google.com/iam/pricing (Core IAM is free; Policy Intelligence/Recommender incurs usage tiers)

---

## Pricing Examples

### Scenario 1: Standard Enterprise IAM Usage
* An organization with 50 projects, 400 developers, and 250 service accounts managing 10,000 resources.
* **IAM Core Operations:** $0.00 (Authentication, role evaluation, policy binding, and service account tokens are completely free).
* **Monthly Cost:** **$0.00 / month**.

### Scenario 2: Security Governance with IAM Recommender & Policy Intelligence
* A security operations team utilizes GCP Policy Intelligence to automatically detect over-privileged service accounts and unused permissions across 100 projects.
* Policy Analyzer & IAM Recommender basic insights: Free.
* Exporting audit logs and IAM change events to BigQuery / Cloud Storage: Standard Cloud Logging ingestion pricing applies (~$0.50/GiB after the first 50 GiB/month free tier).
* **Estimated Cost:** **~$15 – $30 / month** in logging analytics.

---

## Nuggets & Gotchas

1. **Default Service Account Privilege Creep:** When you enable the Compute Engine API, GCP automatically creates `<project-number>-compute@developer.gserviceaccount.com` and grants it the primitive `Editor` role. If a developer launches a VM with default settings, anyone who obtains shell on that VM can query the metadata server and inherit full Editor rights over your entire GCP project. **Always pass `--no-scopes` or attach a custom, least-privileged service account when launching VMs.**
2. **Inheritance Cannot Be Narrowed by Allow Policies:** You cannot "override" or revoke an access grant at a lower level of the hierarchy using allow policies. If a security team member has `roles/viewer` at the Organization level, assigning them nothing or a narrower role at a Project will not restrict their read access to that project. Use **IAM Deny Policies** if explicit blocking is required.
3. **Eventual Consistency Latency:** GCP IAM policy changes are eventually consistent across global regions. While changes typically propagate in under 7 seconds, global propagation can take up to 60–80 seconds in edge scenarios. Automated CI/CD pipelines that create a service account and immediately attempt to authenticate with it must implement retries with exponential backoff.
4. **Custom Role Permission Incompatibilities:** Not all GCP permissions can be added to custom roles. Permissions containing `*.list` or `*.get` are almost universally supported, but complex lifecycle permissions or operations marked as testing/preview often fail with `Permission [x] is not valid for custom roles`. Always check Google's custom role support table before architecting custom roles.
5. **Metadata Server SSRF Vulnerability & Header Protection:** Workloads query `http://metadata.google.internal/computeMetadata/v1/` to fetch tokens. To prevent Server-Side Request Forgery (SSRF) exploits, GCP requires the HTTP header `Metadata-Flavor: Google`. Requests missing this header are rejected with an HTTP 403. However, if an application blindly proxies custom headers, an attacker can still steal credentials; use workload identity protections and IMDS filtering.
6. **Project Deletion Grace Period & Service Account Zombies:** When a project or service account is deleted, its email remains in cached IAM policies for other projects as a deleted principal (displayed as `deleted:serviceAccount:...`). If you recreate a service account with the identical name later, it will receive a **new unique numeric ID** and will **not** inherit the old permissions.

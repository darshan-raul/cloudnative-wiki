---
title: OIDC Integration
tags:
  - Kubernetes
  - Non-Functional
  - OIDC
  - Authentication
  - Keycloak
---

Cluster auth with OIDC: every cluster trusts the same IdP (Keycloak, Okta, Azure AD). One set of credentials, mapped to k8s groups, mapped to RBAC roles. **Get this right once and you never manage cluster credentials again.**

## Why OIDC

**Without OIDC:**
- Each user has a static cert/token in their kubeconfig
- Tokens expire, need rotation
- No central audit of who accessed the cluster
- No SSO, no MFA
- Service accounts use long-lived JWTs (legacy)

**With OIDC:**
- Users authenticate via SSO (Okta, Azure AD, Keycloak, etc.)
- Tokens are short-lived (15min-1hr), auto-refreshed
- Central audit (in your IdP)
- MFA, conditional access, etc.
- Service accounts use projected tokens (workload identity)

**This is the production default.** Static credentials should be a relic.

## The flow

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  1. User runs: kubectl get pods                              │
│       ↓                                                      │
│  2. kubectl sees: kubeconfig has exec auth                  │
│       ↓                                                      │
│  3. kubectl runs the exec command (e.g. aws, gcloud,         │
│     kubelogin)                                               │
│       ↓                                                      │
│  4. exec command contacts IdP:                               │
│     - "I need a token for user alice in k8s cluster"        │
│       ↓                                                      │
│  5. IdP authenticates alice:                                 │
│     - Password + MFA                                         │
│     - Group membership: alice is in "developers"             │
│       ↓                                                      │
│  6. IdP issues a JWT signed by the IdP                       │
│       ↓                                                      │
│  7. kubectl sends the JWT to the apiserver                   │
│       ↓                                                      │
│  8. apiserver validates:                                     │
│     - JWT signature is valid                                 │
│     - JWT issuer matches configured OIDC issuer              │
│     - JWT audience matches configured audience               │
│     - JWT is not expired                                     │
│       ↓                                                      │
│  9. apiserver extracts username + groups from JWT claims     │
│       ↓                                                      │
│  10. apiserver checks RBAC: can this user do this?           │
│       ↓                                                      │
│  11. Yes → return data                                       │
│      No  → 403 Forbidden                                     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## The components

### The IdP (Identity Provider)

Stores users, groups, credentials. Examples:
- **Keycloak** — open source, self-hosted
- **Okta** — commercial, popular
- **Azure AD / Entra ID** — for Azure shops
- **Google Workspace** — for GCP shops
- **Auth0** — commercial

The IdP issues JWTs that the apiserver validates.

### The OIDC client

Runs on the user's machine (or CI runner). Handles the IdP login, token exchange, refresh.

Examples:
- **kubelogin** (`kubelogin`) — generic OIDC client
- **aws** (CLI) — uses AWS SSO / IAM Identity Center
- **gcloud** (CLI) — uses Google OIDC
- **azure-cli** — uses Azure AD
- **Keycloak's `kcfed`** — for Keycloak

### The apiserver

Configured to trust the IdP. Reads the OIDC config (issuer URL, client ID, etc.), validates incoming JWTs.

### The kubeconfig

Has an `exec` block that runs the OIDC client to get tokens.

## Setting it up: Keycloak

Keycloak is the most common self-hosted IdP for k8s.

### Step 1: Install Keycloak

```bash
# install via Helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install keycloak bitnami/keycloak \
  --namespace keycloak --create-namespace \
  --set auth.adminUser=admin \
  --set auth.adminPassword=xxx
```

Or use the official Keycloak operator. Or use a managed Keycloak (e.g., Red Hat SSO).

### Step 2: Create a realm

A realm is an isolated namespace in Keycloak. Create `k8s-prod` for production.

```bash
# via Keycloak admin UI or via API
curl -X POST http://keycloak:8080/admin/realms \
  -H "Authorization: Bearer xxx" \
  -H "Content-Type: application/json" \
  -d '{"realm": "k8s-prod", "enabled": true}'
```

### Step 3: Create a client

The cluster is the client. The kube-apiserver is the audience.

```bash
# create a client in the realm
curl -X POST http://keycloak:8080/admin/realms/k8s-prod/clients \
  -H "Authorization: Bearer xxx" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "kubernetes",
    "publicClient": false,
    "standardFlowEnabled": true,
    "directAccessGrantsEnabled": true,
    "redirectUris": ["https://kubernetes.example.com/*"],
    "webOrigins": ["*"]
  }'
```

### Step 4: Create users and groups

In Keycloak:
- Create users (alice, bob, etc.)
- Create groups (developers, ops, sre)
- Add users to groups
- Map group claims to JWT

```bash
# create a group
curl -X POST http://keycloak:8080/admin/realms/k8s-prod/groups \
  -H "Authorization: Bearer xxx" \
  -H "Content-Type: application/json" \
  -d '{"name": "k8s-developers"}'

# add user to group
curl -X PUT http://keycloak:8080/admin/realms/k8s-prod/users/<user-id>/groups/<group-id> \
  -H "Authorization: Bearer xxx"
```

### Step 5: Configure the apiserver

The apiserver needs to know how to validate Keycloak-issued JWTs.

```yaml
# apiserver flags
--oidc-issuer-url=https://keycloak.example.com/realms/k8s-prod
--oidc-client-id=kubernetes
--oidc-username-claim=preferred_username
--oidc-groups-claim=groups
--oidc-required-claim=hd=example.com   # restrict to specific org (Google)
--oidc-signing-algs=RS256
--oidc-ca-file=/etc/ssl/certs/ca.crt  # CA that signed Keycloak's cert
```

**For self-signed Keycloak certs:**

```yaml
--oidc-ca-file=/etc/keycloak/ca.crt
```

### Step 6: Configure RBAC

Map OIDC groups to k8s roles.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: developers-edit
subjects:
- kind: Group
  name: k8s-developers   # matches the Keycloak group name
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
```

The apiserver extracts the `groups` claim from the JWT and matches it to the `subjects[].name` in the RoleBinding.

### Step 7: Configure the kubeconfig

The kubeconfig has an `exec` block that runs an OIDC client.

```yaml
apiVersion: v1
kind: Config
clusters:
- name: prod
  cluster:
    server: https://api.example.com
    certificate-authority-data: xxx
users:
- name: alice
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1
      command: kubelogin
      args:
      - get-token
      - --oidc-issuer-url=https://keycloak.example.com/realms/k8s-prod
      - --oidc-client-id=kubernetes
      - --oidc-client-secret=xxx
      - --oidc-extra-scope=email,profile,groups
contexts:
- name: prod
  context:
    cluster: prod
    user: alice
current-context: prod
```

**`kubelogin` handles the OIDC dance.** When kubectl runs it, it:
1. Opens a browser to the IdP
2. User logs in (MFA, etc.)
3. IdP redirects with an auth code
4. kubelogin exchanges for an ID token + refresh token
5. kubelogin returns a bearer token to kubectl
6. kubectl uses the token for the API call
7. Token expires → kubelogin refreshes

**For headless environments (CI, automation):** use device-code flow or service account tokens instead.

## Setting it up: cloud-managed IdP

### EKS + IAM Identity Center

```bash
# enable IAM Identity Center
aws sso create-instance

# create a permission set
aws sso create-permission-set \
  --name K8sAdmin \
  --instance-arn <sso-instance-arn> \
  --session-duration PT12H

# attach to your EKS cluster
aws eks create-access-entry \
  --cluster-name my-cluster \
  --principal-arn <user-or-group-arn>

# associate access policy
aws eks associate-access-policy \
  --cluster-name my-cluster \
  --principal-arn <user-or-group-arn> \
  --access-scope cluster \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
```

**kubeconfig with aws-cli:**

```bash
aws eks update-kubeconfig --name my-cluster --region us-east-1
# the resulting kubeconfig has an exec block using aws sso
```

### GKE + Google Workspace

```bash
# create a Google group
gcloud identity groups create k8s-developers@example.com

# create a cluster with OIDC
gcloud container clusters create my-cluster \
  --enable-stackdriver-kubernetes \
  --enable-security-group \
  --enable-legacy-authorization

# get credentials
gcloud container clusters get-credentials my-cluster

# the kubeconfig uses your Google credentials
```

### AKS + Azure AD

```bash
# create an AKS cluster with Azure AD integration
az aks create \
  --resource-group my-rg \
  --name my-cluster \
  --enable-aad \
  --aad-admin-group-object-ids <group-id>

# get credentials
az aks get-credentials --resource-group my-rg --name my-cluster
```

## Workload identity

For pods, not users. Pods need to authenticate to cloud APIs (S3, RDS, etc.) without static credentials.

### AWS IRSA (IAM Roles for Service Accounts)

```bash
# 1. create an IAM role with a trust policy
aws iam create-role \
  --role-name my-pod-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Federated": "arn:aws:iam::xxx:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/xxx" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-east-1.amazonaws.com/id/xxx:sub": "system:serviceaccount:my-ns:my-sa"
        }
      }
    }]
  }'

# 2. annotate the ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-sa
  namespace: my-ns
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::xxx:role/my-pod-role
```

The pod's ServiceAccount token (projected) is automatically exchanged for AWS credentials. No static creds.

### GKE Workload Identity

```bash
# create a GCP service account
gcloud iam service-accounts create my-pod-sa \
  --project my-project

# bind k8s SA to GCP SA
gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:my-project.svc.id.goog[my-ns/my-sa]" \
  my-pod-sa@my-project.iam.gserviceaccount.com

# annotate the k8s SA
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-sa
  namespace: my-ns
  annotations:
    iam.gke.io/gcp-service-account: my-pod-sa@my-project.iam.gserviceaccount.com
```

### Azure Workload Identity

```bash
# create a managed identity
az identity create --name my-pod-id --resource-group my-rg

# create a federated credential
az identity federated-credential create \
  --name my-pod-fc \
  --identity-name my-pod-id \
  --resource-group my-rg \
  --issuer $AKS_OIDC_ISSUER \
  --subject system:serviceaccount:my-ns:my-sa

# annotate the k8s SA
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-sa
  namespace: my-ns
  labels:
    azure.workload.identity/client-id: <client-id-from-identity>
```

## The "kubelogin" depth

`kubelogin` is the most-used OIDC client for k8s.

**Install:**

```bash
brew install kubelogin
# or
kubectl krew install oidc-login
```

**Auth flows:**

- **Interactive (browser)** — opens browser, login, returns token. Default.
- **Device code** — prints a URL, user opens it on another device. For headless.
- **Resource owner password** — username/password direct. Avoid (not OIDC).
- **Client credentials** — service-to-service. For automation.
- **Token file** — pre-obtained token. For testing.

**Common args:**

```bash
kubelogin get-token \
  --oidc-issuer-url=https://keycloak.example.com/realms/k8s-prod \
  --oidc-client-id=kubernetes \
  --oidc-client-secret=xxx \
  --oidc-extra-scope=email,profile,groups \
  --oidc-extra-scope=offline_access   # for refresh token
```

## Common RBAC patterns with OIDC

### Developers (namespace-scoped)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developers
  namespace: my-app
subjects:
- kind: Group
  name: k8s-developers   # OIDC group
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit   # most namespace operations
  apiGroup: rbac.authorization.k8s.io
```

### SREs (cluster-wide read)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sre-read
subjects:
- kind: Group
  name: sre   # OIDC group
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view   # read-only cluster-wide
  apiGroup: rbac.authorization.k8s.io
```

### Platform admins (cluster-wide write)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-admins
subjects:
- kind: Group
  name: platform-admins
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
```

## The token expiration and refresh

OIDC tokens are short-lived (15min-1hr). After expiration:

- **Refresh token** (if `offline_access` scope is requested) lets kubelogin get a new ID token without user interaction.
- **No refresh token** → user has to log in again.

**For CI/CD:** use long-lived service account tokens (legacy, deprecated) or projected tokens with explicit durations.

## Common gotchas

* **Group claim format varies.** Keycloak uses `groups`, Okta uses `groups` (different default), Azure AD uses `groups` (object IDs, not names). Map explicitly.
* **Refresh tokens require offline_access scope.** Without it, the user is prompted to log in every hour.
* **OIDC requires HTTPS.** The issuer URL must be HTTPS. Self-signed certs need `--oidc-ca-file`.
* **The `sub` claim is the unique identifier.** Don't use email as the subject — emails change.
* **Group names with special characters** can break RBAC matching. Stick to alphanumeric.
* **Workload identity requires the cloud's OIDC integration** (EKS OIDC, GKE Workload Identity, AKS OIDC). It's not just a config flag.
* **The legacy long-lived ServiceAccount tokens** are deprecated. Use projected tokens (bound to a pod, time-limited).
* **The apiserver caches OIDC config.** Changes to OIDC config require apiserver restart.
* **Cross-tenant trust** is complex. One IdP, multiple clusters is fine. Multiple IdPs, one cluster: use OIDC federation or multiple `--oidc-issuer-url` flags (not supported in all versions).
* **Kubelogin prints the device URL for headless auth.** Make sure users know to copy it.
* **The `--oidc-required-claim` flag** can restrict to a specific organization or tenant. Use it for multi-tenant IdPs.

## A worked example

**Company:** mid-size SaaS, 50 engineers, 1 platform team, 2 production clusters (us, eu).

**Setup:**

- **Keycloak** (self-hosted in `identity` namespace)
- **One realm per environment** (`k8s-prod`, `k8s-staging`, `k8s-dev`)
- **One OIDC client per cluster** (`kubernetes-prod-us`, `kubernetes-prod-eu`, etc.)
- **Groups** in Keycloak:
  - `k8s-platform-admins` — full cluster-admin
  - `k8s-sre` — read-only cluster-wide
  - `k8s-developers-prod` — namespace edit in prod
  - `k8s-developers-staging` — namespace edit in staging

**RBAC:**

```yaml
# SRE read
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sre-read
subjects:
- kind: Group
  name: k8s-sre
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io

# Developers can do anything in team-a
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-developers
  namespace: team-a
subjects:
- kind: Group
  name: k8s-developers-prod
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin   # namespace admin
  apiGroup: rbac.authorization.k8s.io
```

**Onboarding a new engineer:**

1. Platform team adds the engineer to Keycloak
2. Engineer added to `k8s-sre` group
3. Engineer installs kubelogin
4. Engineer's kubeconfig has the OIDC config
5. First `kubectl get pods` triggers Keycloak login
6. Engineer is now in the cluster

**No more "share the kubeconfig" emails.**

## See also

* [[Kubernetes/guides/non-functional/security-baseline|security-baseline]] — auth in the security layer
* [[Kubernetes/guides/non-functional/multi-tenancy|multi-tenancy]] — RBAC patterns
* [[Kubernetes/guides/tools/context-switching|context-switching]] — kubeconfig
* [kubelogin](https://github.com/int128/kubelogin)
* [Keycloak docs](https://www.keycloak.org/documentation.html)

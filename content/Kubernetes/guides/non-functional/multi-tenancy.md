---
title: Multi-Tenancy
tags:
  - Kubernetes
  - Non-Functional
  - Multi-Tenancy
  - Isolation
---

Multi-tenancy in k8s: multiple teams, customers, or environments share one cluster. The challenge: how to give each tenant isolation without giving each one their own cluster. **The cost of multi-tenant mistakes is shared — that's what makes it dangerous.**

## The four isolation levels

```
┌──────────────────────────────────────────────────────────────┐
│ Level 4: Cluster (separate)                                  │
│   ├─ Total isolation                                         │
│   ├─ Each tenant has their own cluster                       │
│   └─ Highest cost, strongest isolation                       │
├──────────────────────────────────────────────────────────────┤
│ Level 3: vCluster (virtual cluster)                          │
│   ├─ Tenant has their own k8s control plane (cheap)          │
│   ├─ Worker nodes are shared                                 │
│   └─ Good isolation, moderate cost                            │
├──────────────────────────────────────────────────────────────┤
│ Level 2: Namespace + policy (soft multi-tenancy)             │
│   ├─ Tenants share a cluster, isolated by namespace          │
│   ├─ NetworkPolicy, RBAC, quotas for isolation              │
│   └─ Cheap, weaker isolation                                 │
├──────────────────────────────────────────────────────────────┤
│ Level 1: Shared everything (no isolation)                    │
│   └─ One cluster, all tenants in `default` namespace         │
│       Don't do this.                                          │
└──────────────────────────────────────────────────────────────┘
```

Most production clusters are **Level 2**. Strong isolation (Levels 3-4) for compliance or untrusted tenants.

## Level 2: Namespace-based multi-tenancy

The most common pattern. Each tenant gets a namespace, with policies to prevent stepping on others.

### Namespace structure

```
prod/
├── team-a/
│   ├── web
│   ├── api
│   └── worker
├── team-b/
│   ├── web
│   ├── api
│   └── worker
└── shared/
    ├── monitoring
    ├── logging
    └── ingress
```

### What each tenant needs

```yaml
# 1. namespace
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
  labels:
    name: team-a
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
```

```yaml
# 2. resource quota (total usage cap)
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "100"
    requests.memory: 200Gi
    limits.cpu: "200"
    limits.memory: 400Gi
    persistentvolumeclaims: "50"
    pods: "100"
    services: "100"
    secrets: "100"
    configmaps: "100"
```

```yaml
# 3. default limit range (per-pod cap)
apiVersion: v1
kind: LimitRange
metadata:
  name: team-a-limits
  namespace: team-a
spec:
  limits:
  - type: Container
    default:
      cpu: 1
      memory: 1Gi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    max:
      cpu: 4
      memory: 8Gi
    min:
      cpu: 50m
      memory: 64Mi
```

```yaml
# 4. network policy (default-deny + explicit allows)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: team-a
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: team-a
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-ingress
  namespace: team-a
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
```

```yaml
# 5. RBAC (tenant-scoped)
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-developers
  namespace: team-a
subjects:
- kind: Group
  name: team-a-developers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit   # can do most things in this namespace
  apiGroup: rbac.authorization.k8s.io
```

### What the tenant cannot do

With the above policies, team-a cannot:
- Use more than 100 CPU / 200Gi memory
- Run pods without CPU/memory limits
- Have more than 100 pods, 50 PVCs, etc.
- Reach pods in team-b (NetworkPolicy blocks it)
- Reach external IPs except via explicit allow (NetworkPolicy egress)
- Modify RBAC, NetworkPolicy, ResourceQuota (those are admin-only)
- Read secrets in other namespaces (RBAC denies)

**This is the security baseline for soft multi-tenancy.**

### The platform team owns

- Cluster creation / upgrades
- Node pools, autoscaling
- CNI, ingress, service mesh
- Network policies (cluster-wide)
- Monitoring, logging
- cert-manager
- Backup
- Cluster-scoped RBAC

The platform team does NOT own:
- Tenant's Deployments
- Tenant's app code
- Tenant's day-2 operations (deployments, scaling within quota)

## Level 3: vCluster

A vCluster is a **virtual k8s cluster** that runs inside a namespace of a host cluster. The tenant gets their own apiserver, their own control plane (scheduler, controller-manager), and full admin inside their vCluster. The worker nodes are shared with the host.

```
┌─────────────────────────────────────────────────────────────┐
│  Host cluster                                               │
│                                                             │
│  ┌─────────────────┐     ┌─────────────────┐                │
│  │ vCluster A      │     │ vCluster B      │                │
│  │ ┌─────────────┐ │     │ ┌─────────────┐ │                │
│  │ │ syncer      │ │     │ │ syncer      │ │                │
│  │ ├─────────────┤ │     │ ├─────────────┤ │                │
│  │ │ "API server"│ │     │ │ "API server"│ │                │
│  │ ├─────────────┤ │     │ ├─────────────┤ │                │
│  │ │ controller-  │ │     │ │ controller-  │ │                │
│  │ │ manager     │ │     │ │ manager     │ │                │
│  │ ├─────────────┤ │     │ ├─────────────┤ │                │
│  │ │ scheduler    │ │     │ │ scheduler    │ │                │
│  │ └──────┬──────┘ │     │ └──────┬──────┘ │                │
│  │        │        │     │        │        │                │
│  │   Pods (real,  │     │   Pods (real,  │                │
│  │   scheduled    │     │   scheduled    │                │
│  │   on host)     │     │   on host)     │                │
│  └─────────────────┘     └─────────────────┘                │
│                                                             │
│  Host nodes (shared)                                        │
└─────────────────────────────────────────────────────────────┘
```

### When to use vCluster

- **Multi-tenant SaaS** where each customer needs their own cluster
- **Dev environments** that should be self-contained
- **Multi-region** where each region has its own k8s but you want one control plane
- **Testing** — spin up isolated clusters for testing

### Tools

- **vCluster (official)** — `loft-sh/vcluster`, the original
- **Kubevirt** — for VM-based isolation (different problem)
- **Capsule** — namespace-as-a-service, lighter than vCluster

### Install vCluster

```bash
# CLI
brew install vcluster

# create a vCluster
vcluster create my-vcluster --namespace my-vcluster-ns

# use it (auto-configures kubeconfig)
vcluster connect my-vcluster

# now you have a separate k8s context
kubectl get nodes
# NAME           STATUS   ROLES                  AGE
# vcluster-node  Ready    control-plane,master   5m
# only "nodes" are virtual; pods are real

# tear down
vcluster delete my-vcluster
```

### vCluster gotchas

- **Storage.** PVs are in the host cluster, visible to other tenants if you don't restrict.
- **Network.** vCluster has its own Service CIDR. Cross-vCluster Service communication requires routing.
- **Cost.** Cheaper than full clusters, more expensive than namespaces.
- **Operators.** Some operators (e.g., cert-manager) should run in the host, not in vCluster.

## Level 4: Multi-cluster (separate clusters per tenant)

Strongest isolation, highest cost. Each tenant (or group of tenants) has their own cluster.

**When to use:**
- Compliance mandates (PCI-DSS Level 1, FedRAMP High)
- Untrusted tenants (third-party workloads)
- Different lifecycle needs (different k8s versions, different cloud)
- Geopolitical isolation (data residency)
- Blast radius concerns (one tenant's incident doesn't affect others)

**Tools for managing many clusters:**

- **Cluster API** — declarative cluster lifecycle
- **Rancher** — fleet management UI
- **Anthos** (Google) — multi-cluster GCP
- **Azure Arc** — extend Azure control plane to any cluster
- **Red Hat ACM** — OpenShift fleet management

## Tenancy patterns by team size

### 1-2 teams, all trusted

**Level 2, light policy:**

- One shared cluster
- One namespace per team
- RBAC for separation
- ResourceQuotas to prevent one team from using all the resources
- NetworkPolicy default-deny + explicit allow

**Cost:** low
**Isolation:** moderate

### 5-10 teams, mostly trusted, one or two less so

**Level 2, strict policy:**

- One shared cluster
- One namespace per team
- PSS `restricted` enforced
- NetworkPolicy default-deny + allow rules
- Kyverno policies
- Service mesh for mTLS
- External secret store

**Cost:** moderate
**Isolation:** strong

### 10+ teams, mixed trust, regulatory constraints

**Level 3 or 4:**

- Per-tenant vCluster or per-tenant cluster
- Cluster-level audit logging
- Stronger isolation (separate etcd, separate control plane)
- More operators, more cost

**Cost:** high
**Isolation:** strongest

### SaaS, customer-facing multi-tenancy

**Level 4, dedicated clusters per customer:**

- Each customer has their own cluster (or vCluster)
- Single-tenant guarantees
- Higher cost, but you can charge for it
- Strongest compliance posture

## Common multi-tenant features

### Tenant onboarding automation

Manually creating namespaces + RBAC + quotas + NetworkPolicy for each new tenant doesn't scale. Use a controller:

- **Kubernetes Namespace Controller** — basic
- **Capsule** — multi-tenant operator with tenant CRDs
- **Rafay** — commercial multi-tenant platform
- **Crossplane** — declare tenants as IaC

```yaml
# Capsule Tenant
apiVersion: capsule.clastix.io/v1beta1
kind: Tenant
metadata:
  name: team-a
spec:
  owners:
  - name: alice
    kind: User
  namespaceQuota: 5
  nodeSelector:
    matchLabels:
      tenant: team-a
  networkPolicies:
  - ingress:
    - from:
      - podSelector: {}
  limitRanges:
  - limits:
    - type: Container
      default:
        cpu: 1
        memory: 1Gi
  resourceQuotas:
  - hard:
      requests.cpu: "10"
      requests.memory: 20Gi
```

### Per-tenant cost tracking

Tag every namespace with the tenant, then cost rolls up:

```yaml
metadata:
  name: team-a
  labels:
    tenant: team-a
    cost-center: engineering
```

Tools:
- **Kubecost** — per-namespace, per-label cost
- **OpenCost** — CNCF, open source
- **Cloud-native billing** — per-tag, per-account

### Per-tenant monitoring

Each tenant should see only their workloads. Multi-tenant monitoring is hard:

- **Grafana** — folder/team-based dashboards
- **Prometheus** — recording rules per label, federation
- **Datadog / New Relic** — tenant-scoped dashboards

### Per-tenant ingress

Two patterns:
1. **Shared ingress** with `host: tenant-a.example.com` rules
2. **Per-tenant ingress controller** (heavier, more isolated)

For most cases, shared ingress is fine. Use NetworkPolicy to prevent tenant-to-tenant traffic.

## Per-tenant DNS

Internal DNS for tenant services:
- `tenant-a.api.cluster.local` (with `ndots:5`, this resolves)
- Cross-tenant: `tenant-b.api.cluster.local` (blocked by NetworkPolicy)

For external:
- `tenant-a.example.com`, `tenant-b.example.com` (separate certs)

## Tenant data isolation

Beyond the cluster, ensure tenant data is isolated:

- **Database** — separate database per tenant, or schema with row-level security
- **Object storage** — separate bucket per tenant, or prefix-based isolation
- **Caches** — separate Redis namespace per tenant
- **Logs** — separate log stream per tenant (or filter at query time)

## Service mesh for multi-tenant

A service mesh (Istio, Linkerd) adds:
- **mTLS** between all pods (default-deny at network level)
- **AuthorizationPolicy** for fine-grained access control
- **Telemetry** per workload

```yaml
# Istio AuthorizationPolicy: only team-a can call team-a
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: team-a-only
  namespace: team-a
spec:
  rules:
  - from:
    - source:
        principals:
        - cluster.local/ns/team-a/sa/*
```

**Mesh cost:** operational complexity. Istio in particular is heavy. Linkerd is lighter. Cilium is the modern alternative.

## Multi-tenant RBAC

### Role-based (most common)

- Admin — full cluster access
- Developer — namespace-scoped edit
- Viewer — namespace-scoped read
- Operator — namespace-scoped operations (no RBAC changes)

```yaml
# example: tenant admin
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alice-admin
  namespace: team-a
subjects:
- kind: User
  name: alice@example.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
```

### Group-based

Most clusters use SSO (OIDC) and map groups to roles:

```yaml
subjects:
- kind: Group
  name: team-a-developers
  apiGroup: rbac.authorization.k8s.io
```

The IdP (Okta, Azure AD, etc.) controls group membership.

### Time-bound

For break-glass or temporary access, use time-bound RBAC:

```bash
# using rbac-tool or similar
kubectl create rolebinding temp-admin \
  --clusterrole=admin \
  --user=alice@example.com \
  --namespace=team-a \
  --expire-in=4h
```

Or use a tool like [bouncer](https://github.com/flatlydeveloped/bouncer) for time-bound access.

## The "noisy neighbor" problem

In a shared cluster, one tenant's traffic spike can affect others. Mitigations:

- **ResourceQuotas** — cap per-tenant usage
- **LimitRanges** — cap per-pod usage
- **HPA / Karpenter** — cluster scales as a whole
- **PriorityClass** — critical tenants get priority scheduling
- **NodeSelectors** — pin a tenant to specific nodes (noisy nodes)
- **Taints/tolerations** — keep a tenant off critical nodes

For very noisy tenants, isolate to dedicated nodes (taint nodes, add toleration to that tenant).

## Common gotchas

* **NetworkPolicy doesn't apply if the CNI doesn't enforce it.** Flannel doesn't. Use Calico, Cilium, or Weave.
* **ResourceQuota and LimitRange are namespace-scoped.** They don't apply across namespaces.
* **A `default` ServiceAccount has wide permissions in some setups.** Bind to a more restrictive SA per namespace.
* **The cluster-admin role is cluster-wide.** Don't bind it to tenant users.
* **The `system:` group is special.** Don't let tenants use those names.
* **PodSecurityStandards is namespace-level.** Apply per-tenant.
* **A tenant can DOS the apiserver.** The apiserver is shared. Rate-limit requests per ServiceAccount.
* **The `kube-system` namespace is sensitive.** Lock down RBAC for it.
* **CRDs are cluster-wide.** A bad CRD can affect all tenants. Be careful with who can create CRDs.
* **Webhook configurations are global.** A misconfigured admission webhook can break the cluster for everyone.
* **Resource pressure is shared.** A noisy tenant can starve the cluster. Use quotas.
* **DNS is shared.** A tenant can use a lot of DNS. Use NodeLocal DNSCache or split DNS for very large clusters.
* **`hostPath` volumes bypass NetworkPolicy isolation.** A pod with `hostPath: /` can read all node data. Disallow in policy.
* **The image cache is shared.** A tenant pulling a huge image fills the cache. Use a registry mirror with rate limiting.
* **Logs are shared (typically).** Use filters in the logging pipeline to keep tenant data separate.

## A worked example

**Company:** 8 product teams, 1 platform team. Compliance requires audit logs, encrypted secrets, default-deny network.

**Architecture:**

- **One EKS cluster** (shared)
- **One namespace per team** (`team-a`, `team-b`, ..., `team-h`)
- **Shared namespaces** for platform: `monitoring`, `logging`, `ingress-nginx`, `cert-manager`
- **NetworkPolicy: default-deny** in every team namespace
- **ResourceQuotas** per team
- **LimitRanges** per team
- **RBAC:** admin/dev/viewer per team
- **OIDC** with Okta, groups mapped to roles
- **External secrets** in AWS Secrets Manager (via ESO)
- **EBS** for storage (encrypted)
- **Karpenter** for node scaling, with priority-based scheduling

**Onboarding a new team:**

1. Platform team runs a `tenant-onboarding` pipeline
2. Pipeline creates namespace, RBAC, ResourceQuota, LimitRange, default-deny NetworkPolicy
3. Pipeline grants team OIDC group access
4. Team gets a GitOps repo, can deploy
5. Pipeline runs on team namespace create

**Ongoing:**

- Team has full admin in their namespace
- Cannot touch other teams' namespaces
- Cannot exceed their quota
- Cannot escalate to cluster-admin
- Cannot create privileged pods (PSS `restricted` blocks)
- Cannot use `hostPath` (policy)
- Cannot pull from untrusted registries (Kyverno)

**Cost:** the team's bill rolls up by namespace label, charged back to their cost center.

## See also

* [[Kubernetes/guides/non-functional/security-baseline|security-baseline]] — security NFRs
* [[Kubernetes/guides/tools/multi-cluster|multi-cluster]] — fleet patterns
* [[Kubernetes/guides/non-functional/oidc-integration|oidc-integration]] — auth
* [[Kubernetes/concepts/L01-architecture/03-namespaces|namespaces]] — how namespaces work

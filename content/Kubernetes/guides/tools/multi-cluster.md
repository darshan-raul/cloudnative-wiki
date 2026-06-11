---
title: Multi-Cluster
tags:
  - Kubernetes
  - Tools
  - Operations
  - Multi-cluster
---

*Sources: [Kubernetes Federation v2 (KubeFed)](https://github.com/kubernetes-retired/contrib/tree/master/federation), [Cluster API](https://cluster-api.sigs.k8s.io/), [Rancher](https://ranchermanager.docs.rancher.com/), [Lens](https://k8slens.dev/)*

Operating 1 cluster is ops. Operating 10+ is a different discipline. This note covers the **patterns, tools, and gotchas** of fleet-scale Kubernetes.

## The shapes of "multi-cluster"

| Pattern | What it solves | Example |
|---------|---------------|---------|
| **Multi-region HA** | Survive a region going down | GKE multi-cluster ingress, EKS Anywhere stretched |
| **Multi-cloud** | Avoid vendor lock-in, regional latency | Anthos, Azure Arc, Rancher |
| **Per-environment** | dev / staging / prod isolated | Standard EKS/GKE/AKS |
| **Per-tenant** | SaaS multi-tenancy at infra layer | vCluster, Cluster API tenants |
| **Per-team** | Team-owned cluster boundaries | Hub-and-spoke with cluster admin per team |
| **Burst / spillover** | Overflow traffic from primary | Karmada, KubeFed, Clusterpedia |
| **Edge** | Many small clusters at the edge | K3s, KubeEdge, K0s |

The patterns combine. A typical enterprise has **multi-region + multi-env + per-team** all at once.

## The mental model

```
                              ┌────────────────────────┐
                              │   Cluster Registry    │
                              │   (a list of clusters) │
                              └─────────┬──────────────┘
                                        │
              ┌───────────────────┬─────┴─────┬─────────────────────┐
              ▼                   ▼           ▼                     ▼
    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
    │ Cluster A    │    │ Cluster B    │    │ Cluster C    │    │ Cluster D    │
    │ prod-us-east │    │ prod-eu-west │    │ dev          │    │ edge-001     │
    │              │    │              │    │              │    │              │
    │ - 200 nodes  │    │ - 200 nodes  │    │ - 5 nodes    │    │ - 1 node     │
    │ - 5k pods    │    │ - 5k pods    │    │ - 100 pods   │    │ - 10 pods    │
    └──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
            │                  │                  │                   │
            └──────────────────┴──────────────────┴───────────────────┘
                                       │
                              shared: identity, secrets,
                              observability, CI/CD
```

Every cluster is **independent** — its own control plane, its own apiserver, its own etcd. They don't share state automatically. You have to **explicitly** replicate or federate.

## Tooling tiers

### Tier 1: shell + kubectl

For up to ~10 clusters, the shell + `kubectl --context` is fine:

```bash
for ctx in $(kubectl config get-contexts -o name); do
  echo "=== $ctx ==="
  kubectl --context $ctx get nodes --no-headers | wc -l
done
```

Tools that help:
- `kubectx` / `kubens` — fast context switch
- `kubectl` + `krew` plugins — `kubectl get-all`, `kubectl ns`
- `fzf` — fuzzy context pick
- `direnv` — per-project kubeconfig
- `stern` — multi-pod log tail

Pros: zero new infra. Cons: doesn't scale, no central view.

### Tier 2: dashboards

- **Lens** — desktop app, multi-cluster support, best UX for engineers
- **Octant** — web-based, in-cluster
- **Headlamp** — web-based, in-cluster
- **k8slens/k9s** — terminal UI, one cluster at a time
- **rancher/dashboard** — fleet-wide

For 10-50 clusters, a **dashboard is the right tool**. Engineers need a way to "see all my clusters" without scripting.

### Tier 3: fleet management platforms

- **Rancher** — manages EKS/AKS/GKE/on-prem, RBAC across clusters, fleet policies
- **Anthos** (Google) — GKE + attached clusters
- **Azure Arc** — extends Azure control plane to any k8s
- **Red Hat Advanced Cluster Management (ACM)** — for OpenShift/OKD
- **Cluster API** — declarative cluster lifecycle (provision, upgrade, delete)
- **KubeFed v2** — sync resources across clusters (mostly retired)
- **Karmada** — multi-cluster scheduler, modern KubeFed successor
- **Liqo** — peer-to-peer, lets one cluster "borrow" capacity from another
- **Clusterpedia** — federated read (search resources across all clusters)

For 50+ clusters, you need a **fleet platform**. Hand-rolling doesn't scale.

## Cluster API (CAPI)

CAPI is the de-facto way to **declaratively manage cluster lifecycle** — provision, scale, upgrade, delete — using k8s APIs.

```
                         ┌──────────────────┐
                         │  Management      │
                         │  cluster         │
                         │  (CAPI runs here)│
                         └────────┬─────────┘
                                  │  Machine, Cluster, MachineDeployment
                                  ▼
                         ┌──────────────────┐
                         │  Infrastructure  │
                         │  provider        │
                         │  (AWS / Azure /  │
                         │   vSphere / etc) │
                         └────────┬─────────┘
                                  │  Provisions
                                  ▼
                         ┌──────────────────┐
                         │  Workload        │
                         │  cluster         │
                         │  (your apps)     │
                         └──────────────────┘
```

Key CRDs:
- **Cluster** — the target cluster
- **MachineDeployment** — group of worker nodes, scalable like a Deployment
- **Machine** — single node
- **MachineHealthCheck** — auto-replace failed nodes

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod-us-east
spec:
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSCluster
    name: prod-us-east
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: prod-us-east-cp
```

CAPI + a provider (CAPA/CAPZ/CAPV for AWS/Azure/vSphere) gives you:
- GitOps-managed cluster lifecycle
- Consistent upgrades across many clusters
- Auto-replace unhealthy nodes
- Same `kubectl` UX for cluster ops

## GitOps at fleet scale

Single-cluster GitOps is easy. Multi-cluster GitOps is where it gets interesting.

```
                  GitHub repo (single source of truth)
                              │
                              ▼
                  ┌──────────────────────┐
                  │  Argo CD (or Flux)   │
                  │  in each cluster     │
                  │  pulls the same repo │
                  └────────┬─────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
   prod-us-east       prod-eu-west         dev
   (overlay path:     (overlay path:       (overlay path:
    overlays/prod-us) overlays/prod-eu)    overlays/dev)
```

Patterns:
- **Same repo, different paths** — each cluster syncs a different subdir
- **Same repo, different values** — Kustomize overlays per cluster
- **AppSets** (Argo CD) — generate many apps from a template, parameterized per cluster
- **Hub cluster** — one Argo CD that deploys to many spoke clusters (push model)

For 50+ clusters, AppSets or a hub-spoke model becomes essential. Hand-managing 50 Argo CD instances doesn't scale.

## Cross-cluster networking

Pod-to-Pod across clusters doesn't work out of the box — different clusters have non-routable Pod CIDRs.

| Tool | Pattern | Notes |
|------|---------|-------|
| **Submariner** | L3 VPN between clusters | Mature, but heavyweight |
| **Skupper** | L7 app-level bridge | Per-app, not cluster-wide |
| **Cilium ClusterMesh** | eBPF, mesh between Cilium-managed clusters | Fast, requires Cilium |
| **Istio multi-cluster** | Mesh across clusters, active-active or primary-remote | Requires Istio on both sides |
| **Linkerd multi-cluster** | Mirror/headless service mirroring | Simpler than Istio |
| **Cluster API networking** | CNI-backed if all clusters on same VPC | AWS VPC peering, Azure vnet peering |
| **Cloud-native** | GKE multi-cluster ingress, EKS Anywhere, AKS connected | Cloud-specific, vendor-tied |

Pick the simplest one that works:
- Same VPC/VNet + same CNI → native pod-to-pod via peering
- Different VPCs / different clouds → service mesh (Istio/Linkerd)
- Edge / disconnected → Submariner or ClusterMesh

## Identity and secrets

Each cluster has its own RBAC. Multi-cluster identity:

- **OIDC** — every cluster trusts the same IdP (Keycloak, Okta, Azure AD)
  - User logs in once, gets tokens for many clusters
  - Tools: `kubelogin`, `dex`, `Pinniped`
- **Workload identity** — Pods in cluster A have a different identity than pods in cluster B
  - AWS IRSA, GKE Workload Identity, Azure Workload Identity
  - Each cluster has its own trust relationship with the cloud IAM
- **Service accounts across clusters** — there's no built-in way. You replicate SA + token manually, or use a service mesh to issue them.

## Observability: one place for N clusters

You don't log into 50 Grafanas. The standard pattern:

```
         Cluster A                  Cluster B
        ┌──────────┐               ┌──────────┐
        │ Prom +   │               │ Prom +   │
        │ logs     │               │ logs     │
        └────┬─────┘               └────┬─────┘
             │ remote_write / OTLP       │
             └─────────────┬─────────────┘
                           ▼
                  ┌─────────────────────┐
                  │  Central store:     │
                  │  Thanos / Mimir /   │
                  │  Grafana Cloud /    │
                  │  Datadog / New Relic│
                  └─────────────────────┘
```

Either:
- **Push:** cluster Proms remote_write to central Thanos/Mimir
- **Pull:** central Prom federates from cluster Proms (deprecated, slow)
- **Agent-based:** OpenTelemetry Collector in each cluster ships to central

For cost reasons, **Mimir or Cortex** is the modern choice over Thanos (Thanos is fine, Mimir is better at scale). For SaaS, Datadog/Grafana Cloud/New Relic handle this for you.

## The 12-factor cluster

A multi-cluster cluster should be:

1. **Boring** — same CNI, same ingress, same service mesh in every cluster
2. **Drifted rarely** — managed by a tool, not a person (CAPI, Argo CD AppSets)
3. **Observable from one place** — central logs, metrics, traces
4. **Auth from one IdP** — OIDC, not per-cluster users
5. **Recoverable** — clusters can be rebuilt from git in <1 hour
6. **Tested** — every change goes through a dev cluster first, then a canary cluster, then prod

## Common gotchas

* **Clock skew** — OIDC tokens and TLS certs assume clocks are within 5 minutes. Different regions drift. Run `chrony` / `ntp` on every node.
* **DNS leakage** — `kube-dns` in cluster A might resolve external names differently than cluster B's `kube-dns`. Be explicit about which DNS you mean.
* **Image registry** — multi-cluster usually means multi-region. Pull from the same registry (ECR cross-region, Harbor replicated, etc.) — don't have clusters pulling from `docker.io` over a slow link.
* **Cost duplication** — control planes × N clusters adds up. Consider per-team clusters vs shared clusters with namespaces.
* **Stale clusters** — clusters you forgot about. Tag them, expire them, prune them.
* **RBAC drift** — `kubectl apply` per cluster, and they drift apart. Use Fleet policies or GitOps.
* **Resource quotas** — set per-cluster quotas. One runaway namespace can take down a shared cluster.
* **Backup blast radius** — back up every cluster, including the "dev" ones you forgot exist. Restore drill quarterly.
* **Cross-cluster PVs** — if your app has a PV in cluster A, and you fail over to cluster B, the data isn't there. Use replicated storage (Ceph, Rook, S3 CSI driver) or `VolumeSnapshots` + cross-region restore.
* **CNI lock-in** — switching CNIs is hard. Pick once, standardize.

## When NOT to multi-cluster

Sometimes "multi-cluster" is the wrong answer. Consider:

* **Multi-tenancy via namespaces** — same cluster, isolation via NetworkPolicy + RBAC + ResourceQuotas. Simpler.
* **vCluster** — virtual k8s clusters per tenant, all running in one physical cluster. Each tenant gets their own control plane (cheap to run) but shares the worker nodes.
* **Namespaced GitOps** — Argo CD with `Applications` per namespace, not per cluster.

Rule of thumb: **multi-cluster is expensive.** Each cluster is ~$70-300/month minimum (control plane + nodes), and operational complexity grows nonlinearly. Only split when:
- Compliance requires it (data residency, isolation)
- Blast radius demands it (one prod issue can't take down everything)
- Tenants demand it (true separation, not just RBAC)
- Latency demands it (regional endpoints)

## See also

* [[Kubernetes/guides/tools/context-switching|context-switching]] — kubeconfig patterns
* [[Kubernetes/guides/tools/kubectl|kubectl]] — the underlying CLI
* [[Kubernetes/guides/tools/k9s|k9s]] — single-cluster TUI
* [[Kubernetes/guides/tools/lens|lens]] — multi-cluster dashboard
* [[Kubernetes/guides/delivery/gitops/argo-cd/README|argo-cd]] — multi-cluster GitOps
* [[Kubernetes/guides/non-functional/multi-tenancy|multi-tenancy]] — alternatives to multi-cluster

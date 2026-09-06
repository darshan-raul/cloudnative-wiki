---
title: Azure Kubernetes Fleet Manager — Multi-Cluster Governance, Staged Upgrades, and Multi-Cluster Services (MCS)
description: Exhaustive engineering guide to multi-cluster orchestration on AKS — Azure Kubernetes Fleet Manager, staged rolling update runs, ClusterResourcePlacement, Multi-Cluster Services (MCS), and global Anycast load balancing.
tags:
  - azure
  - aks
  - fleet-manager
  - multi-cluster
  - mcs
  - governance
  - gitops
---

# Azure Kubernetes Fleet Manager — Multi-Cluster Governance, Staged Upgrades, and Multi-Cluster Services (MCS) 🌐🏛️

As enterprise Kubernetes footprints expand beyond single clusters, organizations grapple with **multi-cluster sprawl: dozens or hundreds of independent AKS clusters distributed across Azure regions, subscriptions, and development environments**. Managing these clusters independently leads to version fragmentation, inconsistent security policies, and fragmented network topologies. **Azure Kubernetes Fleet Manager (Fleet)** establishes a unified management plane across multiple AKS clusters, providing **staged multi-cluster rolling upgrades**, declarative **workload placement (`ClusterResourcePlacement`)**, and cross-cluster service discovery via **Multi-Cluster Services (MCS)**.

---

## 1. Architecture: The Fleet Manager Control Plane

Azure Kubernetes Fleet Manager operates an intelligent central hub that coordinates member clusters across multiple Azure regions without requiring permanent site-to-site VPN meshes between every cluster.

```
                         AZURE KUBERNETES FLEET MANAGER (HUB)
                                           │
             ┌─────────────────────────────┼─────────────────────────────┐
             │                             │                             │
     STAGED UPDATE ENGINE          WORKLOAD PLACEMENT (CRP)       MULTI-CLUSTER SERVICES (MCS)
     - Staged cluster rollouts     - Declarative scheduling       - `clusterset.local` DNS
     - Canary -> Dev -> Prod       - Balances across regions      - Cross-cluster pod routing
     - Automated soak periods      - Affinity & topology spread   - L4/L7 Multi-Cluster Ingress
             │                             │                             │
             └─────────────────────────────┼─────────────────────────────┘
                                           │ Encrypted Secure Tunnel
                                           ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                     FLEET MEMBER CLUSTER FEDERATION                    │
       └───────────────────┬────────────────────────────────┬───────────────────┘
                           │                                │
         EAST US MEMBER    │                                │ WEST EUROPE MEMBER
                           ▼                                ▼
       ┌───────────────────────────────┐        ┌───────────────────────────────┐
       │ AKS CLUSTER: `aks-prod-eastus`│        │ AKS CLUSTER: `aks-prod-weur`  │
       │                               │        │                               │
       │  ┌─────────────────────────┐  │        │  ┌─────────────────────────┐  │
       │  │ ServiceExport: `catalog`│  │        │  │ ServiceImport: `catalog`│  │
       │  │ (Exposes pod endpoints) │  │        │  │ (Resolves to East US)   │  │
       │  └────────────┬────────────┘  │        │  └────────────┬────────────┘  │
       │               │ Pod IP:       │        │               │ Transparent   │
       │               ▼ 192.168.1.15  │        │               ▼ Global Routing│
       │  ┌─────────────────────────┐  │        │  ┌─────────────────────────┐  │
       │  │ Pod A (Local Worker)    │◄─┼────────┼──┤ Pod B (Remote Caller)   │  │
       │  └─────────────────────────┘  │        │  └─────────────────────────┘  │
       └───────────────────────────────┘        └───────────────────────────────┘
```

---

## 2. Core Architectural Capabilities

### 1. Staged Update Runs (Safe Global Upgrades)
Upgrading 50 production clusters manually is fraught with risk. Fleet Manager orchestrates **Update Runs**:
- Clusters are grouped into sequential **Update Stages** (e.g., *Stage 1: Dev/Canary (10%)*, *Stage 2: Regional Staging*, *Stage 3: Global Production*).
- Enforces configurable **Soak Times** (e.g., wait 24 hours between stages) to catch regressions before touching Tier-1 production clusters.
- If a cluster in Stage 1 fails its upgrade, the Update Run halts automatically, protecting remaining clusters.

### 2. Multi-Cluster Services (MCS)
Implements the Kubernetes SIG Multi-Cluster Services specification:
- Pods export services across cluster boundaries by declaring a **`ServiceExport`** resource.
- Peer member clusters discover the service via an auto-generated **`ServiceImport`** object.
- Internal DNS resolves the cross-cluster service using the standardized domain:
  ```
  <service-name>.<namespace>.svc.clusterset.local
  ```

### 3. Workload Placement (`ClusterResourcePlacement`)
Platform engineers can author a single deployment or policy on the Fleet Hub and declare a `ClusterResourcePlacement` (CRP) rule:
- Fleet dynamically deploys the manifest to all matching member clusters using labels, resource availability, or regional criteria.

---

## 3. Production Configuration & CLI Operations (`az` CLI & `kubectl`)

### 1. Provision an Azure Kubernetes Fleet Manager Hub

```bash
# Register required Fleet provider
az provider register --namespace Microsoft.ContainerService

# Create a Fleet Manager Hub with a managed Kubernetes API endpoint (with hub)
az fleet create \
    --resource-group rg-prod-fleet \
    --name fleet-core-prod \
    --location eastus \
    --enable-hub
```

### 2. Join Member Clusters to the Fleet

```bash
# Register East US cluster as a member
az fleet member create \
    --resource-group rg-prod-fleet \
    --fleet-name fleet-core-prod \
    --name member-prod-eastus \
    --member-cluster-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod-aks/providers/Microsoft.ContainerService/managedClusters/aks-prod-eastus"

# Register West Europe cluster as a member
az fleet member create \
    --resource-group rg-prod-fleet \
    --fleet-name fleet-core-prod \
    --name member-prod-weur \
    --member-cluster-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod-aks/providers/Microsoft.ContainerService/managedClusters/aks-prod-weur"
```

### 3. Execute a Staged Multi-Cluster Rolling Upgrade

Create `staged-update-run.json`:

```json
{
  "properties": {
    "upgrade": {
      "type": "Full",
      "kubernetesVersion": "1.30.2"
    },
    "strategy": {
      "stages": [
        {
          "name": "canary-stage",
          "groups": [
            { "name": "canary-group" }
          ],
          "afterStageWaitInSeconds": 86400
        },
        {
          "name": "global-prod-stage",
          "groups": [
            { "name": "prod-group" }
          ]
        }
      ]
    }
  }
}
```

Trigger the staged update run:

```bash
az fleet updaterun create \
    --resource-group rg-prod-fleet \
    --fleet-name fleet-core-prod \
    --name upgrade-to-1-30 \
    --file staged-update-run.json

# Start update run
az fleet updaterun start \
    --resource-group rg-prod-fleet \
    --fleet-name fleet-core-prod \
    --name upgrade-to-1-30
```

### 4. Export Service across Clusters using Multi-Cluster Services (MCS)

On the East US cluster, expose the `catalog-service` to the entire Fleet:

Create `catalog-service-export.yaml`:

```yaml
apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: catalog-service
  namespace: e-commerce
```

Apply on `aks-prod-eastus`:

```bash
kubectl apply -f catalog-service-export.yaml
```

*Pods in `aks-prod-weur` can now query `catalog-service.e-commerce.svc.clusterset.local` directly.*

---

## 4. Quotas, Performance & Configuration Limits

| Parameter | Platform Limit | Production Impact |
| :--- | :--- | :--- |
| **Max Member Clusters per Fleet** | **Up to 100 Clusters** | Single Fleet management capacity |
| **Cross-Cluster DNS Protocol** | `clusterset.local` | Standardized Kubernetes SIG MCS domain |
| **Update Run Soak Time** | **Up to 30 Days** | Configurable wait periods between upgrade stages |
| **Network Prerequisite for MCS** | **Routable Pod IPs** | Requires Azure CNI with routable VNet IPs or VNet Peering |
| **Hub Type** | Hubless vs Managed Hub | Managed Hub enables Kubernetes API server and CRP |

---

## 5. Official References

- [Azure Kubernetes Fleet Manager Documentation](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/)
- [Staged Upgrades in Fleet Manager](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/update-orchestration)
- [Multi-Cluster Services (MCS) on Fleet](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/multi-cluster-networking)
- [Azure Kubernetes Fleet Manager Pricing](https://azure.microsoft.com/en-us/pricing/details/kubernetes-fleet-manager/)

---

## 6. Realistic Pricing Scenarios

### Scenario A: Global Enterprise Fleet (20 Clusters Managed)

- **Architecture:** 20 production AKS clusters (1,000 total nodes) coordinated by Azure Kubernetes Fleet Manager with a Managed Hub.
- **Monthly Cost Breakdown:**
  - Fleet Manager Hub Management Fee: **$0.20 / hour** (~$146.00 / month).
  - Member Cluster Management: Standard AKS cluster fees apply.
  - Multi-Cluster Service Discovery: **$0.00** (Included with Fleet).
- **Total Fleet Management Overhead:** **$146.00 / month** *(Achieving automated multi-cluster governance across 20 clusters for under $5/day).*

### Scenario B: Multi-Region Active Failover Fleet (2 Large Hub Clusters)

- **Architecture:** 2 regional clusters in East US and West Europe using Fleet for Multi-Cluster Ingress and staged patch management.
- **Monthly Cost Breakdown:**
  - Fleet Manager Hub: **$146.00**
  - Cross-Region VNet Peering Data Transfer (20 TB): 20,000 GB × $0.035/GB = **$700.00**
- **Total Multi-Cluster Spend:** **$846.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **MCS Requires Non-Overlapping Private IP Address Spaces:** Multi-Cluster Services enables direct pod-to-pod communication across member clusters. If Cluster A and Cluster B both use Azure CNI with overlapping VNet CIDRs (e.g., both use `10.0.0.0/16`), packets cannot be routed over VNet peering, and MCS cross-cluster calls will fail with **silent packet routing loops**. Always ensure all member VNets have strictly disjoint CIDRs.
2. **Staged Update Run Halts on Cluster Health Check Failures:** During a staged update run, Fleet Manager validates cluster health before progressing from Stage 1 to Stage 2. If a developer deployed a broken pod in Stage 1 that triggered an alerting condition, Fleet will mark the stage as failed and **halt the rollout for all remaining clusters**. SREs must remediate the broken cluster and execute `az fleet updaterun resume`.
3. **Hubless vs. Hub-Enabled Fleet Cannot Be Converted in Place:** When creating a Fleet, you choose between a **Hubless Fleet** (simple grouping for basic updates) and a **Hub-Enabled Fleet** (provisions a managed Kubernetes API endpoint for GitOps and CRP). You **cannot convert a Hubless fleet to Hub-enabled later**. Always provision with `--enable-hub` if you plan to use `ClusterResourcePlacement`.
4. **ServiceExport Namespace Sameness Rule:** Multi-Cluster Services enforces **Namespace Sameness**: an exported service in namespace `production` on Cluster A can only be imported into namespace `production` on Cluster B. If the target namespace does not exist on the remote cluster, the `ServiceImport` object will not be generated.
5. **Fleet Hub RBAC vs. Member Cluster RBAC:** Granting an engineer `Contributor` permissions on the Azure Kubernetes Fleet Manager resource allows them to orchestrate global rollouts and placement rules, but **does not automatically grant them `cluster-admin` inside the member clusters' local Kubernetes API servers**. Access to member clusters must still be granted via Microsoft Entra ID or Azure RBAC.

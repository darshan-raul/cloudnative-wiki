---
title: AKS Upgrades, Maintenance Windows, and Safe Rollout Strategies
description: Exhaustive engineering guide to AKS lifecycle management — Node image auto-upgrades (NodeImage channel), Kubernetes auto-upgrades, planned maintenance windows, surge upgrade tuning (maxSurge), PDB deadlocks, and blue-green cluster rollouts.
tags:
  - azure
  - aks
  - upgrades
  - maintenance
  - lifecycle
  - pdb
  - sre
---

# AKS Upgrades, Maintenance Windows, and Safe Rollout Strategies 🔄🛡️

Operating mission-critical Kubernetes clusters requires balancing two opposing forces: **rapid CVE security patching** and **production workload stability**. In Azure Kubernetes Service (AKS), lifecycle operations occur at two distinct levels: **Kubernetes Control Plane & Kubelet Upgrades** (which introduce API version changes) and **Node OS Image Upgrades** (which deliver weekly Linux kernel and container runtime patches). Failing to architect safe rollout mechanisms can lead to **upgrade timeouts, PodDisruptionBudget (PDB) deadlocks, and cascading outages**.

---

## 1. Architecture: Automated Upgrade Channels & Cadence

AKS separates the automated upgrade lifecycle into **Cluster Auto-Upgrade** (Kubernetes version) and **Node OS Auto-Upgrade** (Host Linux VHD):

```
       KUBERNETES UPSTREAM RELEASES                   MICROSOFT OS CVE RELEASES
                    │                                             │
                    ▼ (~2-4 weeks)                                ▼ (Weekly cadence)
  ┌───────────────────────────────────────────┐ ┌───────────────────────────────────────────┐
  │         CLUSTER AUTO-UPGRADE CHANNELS     │ │        NODE OS AUTO-UPGRADE CHANNELS      │
  │                                           │ │                                           │
  │ - Rapid: Earliest GA releases (dev/test)  │ │ - NodeImage: Weekly fresh VHD with OS &   │
  │ - Regular: Soaked releases (production)   │ │   kernel CVE patches. (RECOMMENDED)       │
  │ - Stable: Conservative N-1 release        │ │ - Unmanaged: OS unattended-upgrades reboot│
  │ - Patch: Security patches for current minor││ - None: Fully manual node upgrades        │
  └─────────────────────┬─────────────────────┘ └─────────────────────┬─────────────────────┘
                        │ Controlled By Planned Maintenance Window    │
                        ▼                                             ▼
  ┌─────────────────────────────────────────────────────────────────────────────────────────┐
  │                 PLANNED MAINTENANCE ENGINE (Weekly Schedule & Exclusions)               │
  │                 Example: Tuesdays & Thursdays, 01:00 - 05:00 UTC                        │
  └─────────────────────────────────────────────┬───────────────────────────────────────────┘
                                                │ Triggers Safe Rollout
                                                ▼
  ┌─────────────────────────────────────────────────────────────────────────────────────────┐
  │                       SURGE UPGRADE ENGINE (`maxSurge: 33%`)                            │
  │                                                                                         │
  │  Step 1: Provisions +2 Surge Nodes with new OS/K8s version                              │
  │  Step 2: Cordon and safely drain existing nodes respecting PodDisruptionBudgets (PDB)   │
  │  Step 3: Deletes drained legacy nodes sequentially; repeats until pool is 100% updated  │
  └─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Upgrade Strategy Comparison: In-Place Surge vs. Blue-Green Cluster Migration

| Dimension | AKS In-Place Surge Upgrade (`maxSurge`) | Multi-Cluster Blue-Green Migration |
| :--- | :--- | :--- |
| **Complexity** | Low (Native `az aks upgrade` command) | High (Requires DNS / Traffic Manager routing) |
| **Rollback Capability** | **Impossible to downgrade** (K8s invariant)| **Instant Rollback** (Shift traffic back to Blue)|
| **Additional Cloud Spend** | Temporary VM surge capacity (~10–33% for 1 hr)| Full duplicate cluster running in parallel |
| **PDB Sensitivity** | High (Strict PDBs stall in-place upgrades) | Zero impact on existing active cluster |
| **Recommended Scope** | Minor patch & weekly NodeImage updates | Major minor versions (e.g., v1.28 -> v1.31) |

---

## 3. Production Configuration & CLI Operations (`az` CLI)

### 1. Configure Automated Upgrades with `NodeImage` Channel

Configure the cluster to automatically upgrade Kubernetes to the `stable` channel and apply weekly OS security fixes via the `NodeImage` channel:

```bash
# Set cluster auto-upgrade channel to stable and node-os auto-upgrade to NodeImage
az aks update \
    --resource-group rg-prod-aks \
    --name aks-core-prod \
    --auto-upgrade-channel stable \
    --node-os-upgrade-channel NodeImage
```

### 2. Define Production Planned Maintenance Windows

Ensure that automated upgrades and node re-imaging only execute during low-traffic maintenance windows, and block updates during critical business quarters (Black Friday / Cyber Week):

```bash
# Create weekly maintenance window (Sundays from 02:00 to 06:00 UTC)
az aks maintenanceconfiguration add \
    --resource-group rg-prod-aks \
    --cluster-name aks-core-prod \
    --name weekly-prod-window \
    --weekday Sunday \
    --start-hour 2 \
    --duration 4 \
    --schedule-type Weekly

# Add a maintenance exclusion window blocking all upgrades during holiday freeze
az aks maintenanceconfiguration add \
    --resource-group rg-prod-aks \
    --cluster-name aks-core-prod \
    --name holiday-freeze \
    --start-date 2026-11-20 \
    --end-date 2026-12-05 \
    --schedule-type Absolute
```

### 3. Tune Surge Upgrade Parameters (`maxSurge`) on Node Pools

Speed up node pool upgrades while ensuring capacity redundancy:

```bash
# Configure node pool to upgrade 33% of nodes concurrently (faster rolling upgrades)
az aks nodepool update \
    --resource-group rg-prod-aks \
    --cluster-name aks-core-prod \
    --name userpool01 \
    --max-surge 33%
```

### 4. Deploy Resilient PodDisruptionBudget (PDB)

Create `order-api-pdb.yaml`:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: order-api-pdb
  namespace: production
spec:
  minAvailable: 75%
  selector:
    matchLabels:
      app: order-api
```

Apply PDB:

```bash
kubectl apply -f order-api-pdb.yaml
```

---

## 4. Quotas, Performance & Configuration Limits

| Parameter | Default Value | Tunable Limit | Production Impact |
| :--- | :--- | :--- | :--- |
| **Default `maxSurge`** | **1 extra node** | Up to 100% or absolute node count | Set to `33%` for balanced speed and safety |
| **Node Drain Timeout** | **30 minutes** | Configurable via `--drain-timeout`| Prevents hung pods from stalling upgrades |
| **Undrainable Node Action**| **Fail Upgrade** | `DrainWithoutForce` or `Run` | Can be set to `--undrainable-node-behavior` |
| **Max Upgrade Duration** | **24 hours** | Hard Azure ARM timeout | Cluster marks upgrade failed if timeout hits |
| **Maintenance Window Duration**| Minimum **4 hours**| Up to 24 hours | Microsoft enforces minimum 4-hour window |

---

## 5. Official References

- [AKS Auto-Upgrade Channels](https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-cluster)
- [Node OS Auto-Upgrade Mechanics](https://learn.microsoft.com/en-us/azure/aks/node-os-channel)
- [Use Planned Maintenance in AKS](https://learn.microsoft.com/en-us/azure/aks/planned-maintenance)
- [Customize Node Surge Upgrades](https://learn.microsoft.com/en-us/azure/aks/upgrade-cluster#customize-node-surge-upgrade)

---

## 6. Realistic Pricing Scenarios

### Scenario A: In-Place Surge Upgrade on a 30-Node Production Cluster

- **Cluster Profile:** 30x `Standard_D8ds_v5` instances ($0.384/hr each).
- **Upgrade Tuning:** `--max-surge 33%` (spins up 10 extra surge nodes during the upgrade).
- **Duration of Upgrade Execution:** ~45 minutes.
- **Cost Calculation:**
  - Surge VM Compute: 10 surge nodes × $0.384/hr × 0.75 hrs = **$2.88**
  - Ephemeral OS Disks: **$0.00**
- **Total Operational Upgrade Cost:** **$2.88 per upgrade event** *(A negligible cost for zero application downtime).*

### Scenario B: Blue-Green Multi-Cluster Enterprise Cutover

- **Cluster Profile:**
  - Blue (Active): 20x `Standard_D16ds_v5` instances ($0.768/hr each).
  - Green (Staging new K8s minor release): 20x `Standard_D16ds_v5` running for 7 days during end-to-end regression testing before traffic cutover.
- **Cost Calculation:**
  - Parallel Green Cluster (7 days): 20 nodes × $0.768/hr × 168 hrs = **$2,580.48**
  - Additional Control Plane SLA: $0.10/hr × 168 hrs = **$16.80**
  - Azure Traffic Manager / Front Door Weighted Routing: ~$25.00
- **Total Migration Cost:** **$2,622.28** *(Provides 100% risk elimination and instant rollback capability).*

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The Strict PDB Deadlock Trap (`minAvailable: 100%`):** If an application deployment has 3 replicas and a developer sets `minAvailable: 100%` (or `maxUnavailable: 0`), Kubernetes evictions are strictly prohibited. When AKS attempts to cordoned and drain the node hosting one of these replicas during a surge upgrade, the drain call is rejected. The upgrade hangs for **60 minutes** before finally failing with `NodeDrainTimeout`. Always enforce `maxUnavailable: 1` or `minAvailable: 75%`.
2. **Subnet IP Exhaustion during Surge Upgrades:** If your cluster runs Traditional Azure CNI with `maxSurge: 33%` on a 30-node cluster, the surge engine will attempt to provision 10 new nodes simultaneously. Each node demands its own VNet IP plus 110 reserved Pod IPs ($10 \times 111 = 1,110 \text{ VNet IPs}$). If your subnet only has 200 free IPs, the surge nodes fail to provision, and the upgrade aborts in a degraded state.
3. **Weekly `NodeImage` Rollouts Rebooting Single-Replica Pods:** Many teams assume that setting the cluster Kubernetes version to manual prevents unexpected reboots. However, if `--node-os-upgrade-channel` is set to `NodeImage`, Microsoft re-images nodes weekly. If an internal tool runs as a single replica without high availability, it will experience downtime every week during the maintenance window. Always run at least 2 replicas for all services.
4. **DaemonSet Image Pull BackOff Locking Drains:** During a node surge upgrade, the new surge node must pull all DaemonSet images (Cilium, Datadog, Falco) before application pods can be scheduled onto it. If a private container registry (ACR) credentials expired or if rate limits are hit, the surge node enters a perpetual `NotReady` state, blocking the entire cluster upgrade indefinitely.
5. **Major Version Leapfrogging is Strictly Forbidden:** Kubernetes upstream and AKS do **not support skipping minor versions** (e.g., upgrading directly from Kubernetes 1.28 to 1.30). Attempting to submit an upgrade request skipping a minor version is rejected by the Azure API. You must perform sequential upgrades (`1.28 -> 1.29 -> 1.30`), testing each minor release along the path.

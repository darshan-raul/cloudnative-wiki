---
title: AKS Cluster Tiers, High Availability Control Plane, and Private Cluster Architecture
description: Exhaustive engineering guide to AKS control plane architectures — Free vs Standard (99.95% SLA) vs Premium (LTS), API Server VNet integration, Private Link clusters, etcd Raft quorum across Availability Zones, and outbound network types.
tags:
  - azure
  - aks
  - control-plane
  - sla
  - networking
  - private-link
  - security
---

# AKS Cluster Tiers, High Availability Control Plane, and Private Cluster Architecture 🏛️🛡️

In enterprise Kubernetes deployments, the resilience, accessibility, and security of the **Kubernetes Control Plane (API Server, `etcd`, `kube-controller-manager`, and `kube-scheduler`)** determine overall service availability. Azure Kubernetes Service (AKS) manages the control plane infrastructure entirely as a managed service, but architecting a resilient cluster requires understanding the differences between **Cluster Pricing Tiers**, the underlying **etcd Raft quorum replication across Azure Availability Zones**, and securing control plane ingress via **Private Link** or **API Server VNet Integration**.

---

## 1. Architecture: The Highly Available AKS Control Plane

In an enterprise-grade AKS cluster provisioned with Availability Zones (`--zones 1 2 3`), Microsoft deploys a multi-master control plane distributed across three physically isolated datacenters within an Azure region.

```
       ENTERPRISE DEVELOPER / CI/CD (ExpressRoute / VPN / Bastion)
                                  │
                                  ▼ Private Endpoint (10.240.0.4)
       ┌────────────────────────────────────────────────────────────────────────┐
       │                AZURE PRIVATE LINK / API SERVER ENDPOINT                │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ Encrypted TLS (Port 443)
                                          ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                 AKS MANAGED CONTROL PLANE (MICROSOFT TENANT)           │
       │                                                                        │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ API SERVER (Zone 1)    │         │ API SERVER (Zone 2)    │         │
       │  │ - kube-controller-mgr  │         │ - kube-controller-mgr  │         │
       │  │ - kube-scheduler       │         │ - kube-scheduler       │         │
       │  └───────────┬────────────┘         └───────────┬────────────┘         │
       │              │ Synchronous Raft                 │ Synchronous Raft     │
       │              ▼                                  ▼                      │
       │  ┌──────────────────────────────────────────────────────────┐          │
       │  │    CLUSTERED ETCD REPLICAS (3-Node / 5-Node Raft Quorum) │          │
       │  │    - Zone 1 Leader        - Zone 2 Follower              │          │
       │  │    - Zone 3 Follower (Zero Data Loss - RPO=0)            │          │
       │  └──────────────────────────────────────────────────────────┘          │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ Konnectivity Tunnel (gRPC)
                                          ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                 CUSTOMER VNET: WORKER NODE POOLS                       │
       │                                                                        │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ Node 1 (Zone 1)        │         │ Node 2 (Zone 2)        │         │
       │  │ - Kubelet              │         │ - Kubelet              │         │
       │  │ - konnectivity-agent   │         │ - konnectivity-agent   │         │
       │  └────────────────────────┘         └────────────────────────┘         │
       └────────────────────────────────────────────────────────────────────────┘
```

### Control Plane Communication: The Konnectivity Tunnel

To securely bridge communication between the Microsoft-managed control plane and customer worker nodes in private VNets without exposing worker nodes to the public internet, AKS deploys **Konnectivity (Uplink/Agent)**:
- `konnectivity-agent` runs as a DaemonSet/Deployment on the worker nodes.
- It initiates an outbound secure gRPC tunnel over TCP port 443 to the `konnectivity-server` inside the managed control plane.
- When the API server needs to stream logs (`kubectl logs`) or open an interactive shell (`kubectl exec`), traffic is multiplexed down this existing outbound tunnel.

---

## 2. Cluster Tier Comparison: Free vs. Standard vs. Premium

Microsoft offers three distinct SLA and support tiers for AKS:

| Dimension | Free Tier | Standard Tier (Production Recommended) | Premium Tier (Enterprise LTS) |
| :--- | :--- | :--- | :--- |
| **Control Plane Cost** | **$0.00 / hour** | **$0.10 / hour** (~$73 / month) | **$0.60 / hour** (~$438 / month) |
| **Uptime SLA (with AZs)** | No financially backed SLA | **99.95% Availability SLA** | **99.95% Availability SLA** |
| **Uptime SLA (without AZs)**| No financially backed SLA | **99.90% Availability SLA** | **99.90% Availability SLA** |
| **Scale Limit** | Up to 1,000 nodes | **Up to 5,000 nodes** | **Up to 5,000 nodes** |
| **Kubernetes Version Support**| Standard N-2 community window | Standard N-2 community window (~14 mo) | **Long-Term Support (LTS - 2 Years)** |
| **Target Workload** | Dev/Test, Staging, Sandboxes | Production Enterprise Applications | Regulated industries (Banking, Health) |

---

## 3. Control Plane Network Topologies

### 1. Public Cluster with Authorized IP Ranges
The API server receives a public IP, but access is restricted via Azure network firewalls to designated CIDRs (corporate egress IPs or bastion CIDRs).

### 2. Private AKS Cluster (Azure Private Link)
The API server FQDN resolves exclusively to a private IP located on a Private Endpoint inside your Azure VNet:
- Requires a **Private DNS Zone** (`privatelink.<region>.azmk8s.io`) linked to your VNet.
- Prevents any public internet exposure. Access requires an on-premises VPN/ExpressRoute connection or an Azure Bastion jumpbox.

### 3. API Server VNet Integration (Modern Standard)
Rather than provisioning a separate Private Endpoint with complex Private DNS Zone peering, **API Server VNet Integration** projects the API server directly into a dedicated delegated subnet within your VNet:
- Eliminates the need for Private DNS Zone management.
- Guarantees bi-directional network routability between API server and customer subnets.

---

## 4. Production Deployment & CLI Operations (`az` CLI)

### 1. Provision a Standard Tier Private AKS Cluster with Azure CNI Overlay and Multi-Zone

```bash
# Register feature flags and create resource group
az group create --name rg-prod-aks --location eastus

# Provision Standard Tier Private AKS Cluster
az aks create \
    --resource-group rg-prod-aks \
    --name aks-core-prod-001 \
    --location eastus \
    --tier standard \
    --enable-private-cluster \
    --private-dns-zone system \
    --zones 1 2 3 \
    --node-count 3 \
    --node-vm-size Standard_D4ds_v5 \
    --node-osdisk-type Ephemeral \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --network-dataplane cilium \
    --pod-cidr 192.168.0.0/16 \
    --service-cidr 10.240.0.0/16 \
    --dns-service-ip 10.240.0.10 \
    --vnet-subnet-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod-net/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-aks-nodes" \
    --enable-managed-identity \
    --enable-oidc-issuer \
    --enable-workload-identity \
    --outbound-type userDefinedRouting
```

### 2. Configure API Server Authorized IP Ranges (for Public Control Planes)

```bash
# Restrict public API server to corporate office CIDRs and CI/CD agent IPs
az aks update \
    --resource-group rg-prod-aks \
    --name aks-core-prod-001 \
    --api-server-authorized-ip-ranges 198.51.100.0/24,203.0.113.50/32
```

### 3. Upgrade Cluster Tier from Free to Standard

```bash
# Dynamically add 99.95% financially backed SLA to an existing cluster without downtime
az aks update \
    --resource-group rg-prod-aks \
    --name aks-core-prod-001 \
    --tier standard
```

---

## 5. Quotas, Performance & Configuration Limits

| Architectural Parameter | Hard Limit / Metric | Production Recommendation |
| :--- | :--- | :--- |
| **Max Nodes (Standard Tier)** | **5,000 nodes** | Free tier is restricted to 1,000 nodes |
| **API Server QPS / Burst** | Managed dynamically | Control plane auto-scales compute automatically |
| **etcd Database Size Limit** | **8 GiB** | Monitor `etcd_mvcc_db_total_size_in_bytes` via Prometheus |
| **Max Pods per Cluster** | **100,000 pods** | Subject to CIDR IP allocation limits |
| **Uptime SLA Availability** | **99.95% (Multi-Zone)** | 99.90% for single-zone or regional non-AZ clusters |
| **Private DNS Records** | 1 per private cluster | Auto-registered in `privatelink.<region>.azmk8s.io` |

---

## 6. Official References

- [AKS Cluster Pricing Tiers & SLA](https://learn.microsoft.com/en-us/azure/aks/free-standard-pricing-tiers)
- [Create a Private Azure Kubernetes Service Cluster](https://learn.microsoft.com/en-us/azure/aks/private-clusters)
- [API Server VNet Integration (Preview/GA)](https://learn.microsoft.com/en-us/azure/aks/api-server-vnet-integration)
- [AKS Outbound Network Routing Types](https://learn.microsoft.com/en-us/azure/aks/limit-egress-traffic)

---

## 7. Realistic Pricing Scenarios

### Scenario A: Production Banking Cluster with Premium Tier (LTS Support)

- **Architecture:**
  - 1 Multi-Zone Regional AKS Cluster running Kubernetes 1.28 under Premium Tier LTS.
  - 12x `Standard_D8ds_v5` worker nodes across 3 Availability Zones.
  - Strict compliance requires avoiding upstream minor upgrades for 24 months.
- **Monthly Cost Breakdown:**
  - Premium Tier Management Fee: $0.60/hr × 730 hrs = **$438.00**
  - Compute Costs (12 nodes): 12 × $0.384/hr × 730 hrs = **$3,363.84**
  - Ephemeral OS Disks: **$0.00**
  - Private Endpoint & VNet Peering: ~$15.00
- **Total Monthly Cost:** **$3,816.84 / month**

### Scenario B: Cloud-Native Microservices Suite (Standard Tier)

- **Architecture:**
  - 1 Multi-Zone Cluster on Standard Tier (99.95% SLA).
  - 6x `Standard_D4ds_v5` worker nodes.
  - Active version tracking on the Regular release cadence.
- **Monthly Cost Breakdown:**
  - Standard Tier Management Fee: $0.10/hr × 730 hrs = **$73.00**
  - Compute Costs (6 nodes): 6 × $0.192/hr × 730 hrs = **$840.96**
  - Ephemeral OS Disks: **$0.00**
  - Azure Standard Load Balancer & Egress: ~$35.00
- **Total Monthly Cost:** **$948.96 / month**

---

## 8. Battle-Tested Nuggets & Production Gotchas

1. **The Free Tier SLA Illusion:** Running production workloads on the Free Tier saves $73/month, but Microsoft offers **zero financially backed service level agreement** on Free tier control planes. During Azure maintenance events or underlying master node host failovers, the API server can become unresponsive for 10–15 minutes. While running pods continue executing, Autoscalers fail, CI/CD deploys abort, and failed pods cannot be rescheduled. Always provision production clusters on the **Standard Tier**.
2. **Private Cluster DNS Resolution Failure from On-Premises:** When an AKS private cluster is provisioned with `--private-dns-zone system`, Azure creates a private DNS zone inside an auto-generated node resource group (`MC_...`). If on-premises clients connect via ExpressRoute, they will fail to resolve the API server FQDN because on-prem DNS forwarders cannot query Azure private zones without an **Azure DNS Private Resolver**. Ensure you deploy an Azure DNS Private Resolver or specify a centralized custom Private DNS Zone during cluster provisioning.
3. **Outbound Type `UserDefinedRouting` (UDR) Asymmetric Routing:** When configuring `--outbound-type userDefinedRouting` to force all egress through an Azure Firewall, the cluster node subnet must have a Default Route (`0.0.0.0/0` -> Next Hop: Firewall Private IP). If an Azure Load Balancer with public frontend IPs is attached to a service, return packets will be routed out through the Firewall instead of directly back to the client, triggering **TCP SYN/ACK drops due to asymmetric routing**. Configure Azure Firewall SNAT or use internal load balancers with Application Gateway.
4. **etcd Size Creep from Custom Resource Definitions (CRDs):** Operators and CI/CD pipelines deploying high volumes of Helm releases often store large secrets or CRD instances in etcd. Because AKS enforces an **8 GiB hard quota on the underlying etcd database**, exceeding this quota locks etcd into read-only mode, crashing the control plane. Continuously monitor `etcd_mvcc_db_total_size_in_bytes` and prune outdated Helm release secrets.
5. **Private Endpoint IP Collision during Subnet Migration:** Once a private AKS cluster is created with an Azure Private Endpoint, the Private Endpoint's IP cannot be changed dynamically. If network engineering re-architects VNet CIDRs or migrates subnets, the cluster cannot be "moved"—you must build a new cluster in the new subnet and migrate workloads using GitOps.
